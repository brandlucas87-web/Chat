from flask import Flask, request, jsonify, Response, render_template_string
from flask_cors import CORS

import threading
import time
import os
import requests
import re

app = Flask(__name__)
CORS(app)

MAX_HISTORY = 500

messages_lock = threading.Lock()
messages = []
message_counter = 0

inventories = {}
inventories_lock = threading.Lock()

thumbnail_cache = {}

# ========== NOVO: Sistema de Scripts ==========
scripts_lock = threading.Lock()
current_script = {
    "id": 1,
    "code": "-- Write your Lua script here\nprint('Hello from Roblox!')\n\n-- Example:\n-- game.Players.LocalPlayer.Character.Humanoid.JumpPower = 50",
    "updated_at": time.time(),
    "version": 1
}

script_history = []
MAX_SCRIPT_HISTORY = 50

def add_message(sender: str, message: str, system: bool = False):
    global message_counter

    with messages_lock:
        message_counter += 1

        entry = {
            "id": message_counter,
            "sender": sender,
            "message": message,
            "system": system,
            "ts": time.time()
        }

        messages.append(entry)

        if len(messages) > MAX_HISTORY:
            messages.pop(0)

        return entry

# ========== NOVOS ENDPOINTS DE SCRIPT ==========

@app.route("/script/current", methods=["GET"])
def get_current_script():
    """Retorna o script atual para o loadstring"""
    with scripts_lock:
        return jsonify({
            "ok": True,
            "script": {
                "code": current_script["code"],
                "version": current_script["version"],
                "updated_at": current_script["updated_at"]
            }
        })

@app.route("/script/update", methods=["POST"])
def update_script():
    """Atualiza o script (usado pelo editor web)"""
    try:
        data = request.get_json()
        new_code = data.get("code", "")
        
        if not isinstance(new_code, str):
            return jsonify({"ok": False, "error": "Code must be string"}), 400
        
        # Limitar tamanho do script (10MB máximo)
        if len(new_code) > 10 * 1024 * 1024:
            return jsonify({"ok": False, "error": "Script too large (max 10MB)"}), 400
        
        with scripts_lock:
            # Salvar no histórico antes de atualizar
            script_history.append({
                "version": current_script["version"],
                "code": current_script["code"],
                "updated_at": current_script["updated_at"]
            })
            
            if len(script_history) > MAX_SCRIPT_HISTORY:
                script_history.pop(0)
            
            # Atualizar script atual
            current_script["code"] = new_code
            current_script["version"] += 1
            current_script["updated_at"] = time.time()
        
        add_message("System", f"Script updated to version {current_script['version']}", system=True)
        
        return jsonify({
            "ok": True,
            "version": current_script["version"]
        })
        
    except Exception as e:
        print("SCRIPT UPDATE ERROR:", e)
        return jsonify({"ok": False, "error": str(e)}), 500

@app.route("/script/execute", methods=["POST"])
def execute_script():
    """Endpoint para o Roblox executar o script via loadstring"""
    try:
        data = request.get_json()
        executor_id = data.get("executor", "Unknown")[:32]
        
        with scripts_lock:
            script_code = current_script["code"]
            version = current_script["version"]
        
        # Gerar URL completa para o loadstring
        base_url = request.host_url.rstrip('/')
        script_url = f"{base_url}/script/raw"
        
        # Criar o código loadstring
        loadstring_code = f'''-- Auto-generated loadstring code
-- Server: {base_url}
-- Script Version: {version}

local success, result = pcall(function()
    local script = game:GetService("HttpService"):GetAsync("{script_url}")
    local func = loadstring(script)
    if func then
        func()
    else
        warn("Failed to load script")
    end
end)

if not success then
    warn("Execution error: " .. tostring(result))
end
'''
        
        add_message("System", f"Script requested for execution by {executor_id}", system=True)
        
        return jsonify({
            "ok": True,
            "loadstring": loadstring_code,
            "script_url": script_url,
            "version": version
        })
        
    except Exception as e:
        print("EXECUTE ERROR:", e)
        return jsonify({"ok": False, "error": str(e)}), 500

@app.route("/script/raw", methods=["GET"])
def raw_script():
    """Endpoint raw para o loadstring pegar o código puro"""
    with scripts_lock:
        script_code = current_script["code"]
    
    return Response(
        script_code,
        mimetype="text/plain",
        headers={
            "Cache-Control": "no-cache, no-store, must-revalidate",
            "Content-Type": "text/plain; charset=utf-8"
        }
    )

@app.route("/script/history", methods=["GET"])
def get_script_history():
    """Retorna histórico de versões do script"""
    limit = request.args.get("limit", 20, type=int)
    
    with scripts_lock:
        history = script_history[-limit:] if limit > 0 else script_history
    
    return jsonify({
        "ok": True,
        "history": history,
        "current_version": current_script["version"]
    })

@app.route("/script/rollback/<int:version>", methods=["POST"])
def rollback_script(version):
    """Reverte para uma versão anterior do script"""
    try:
        with scripts_lock:
            # Procurar a versão no histórico
            target_script = None
            for script in script_history:
                if script["version"] == version:
                    target_script = script
                    break
            
            if not target_script:
                return jsonify({"ok": False, "error": f"Version {version} not found"}), 404
            
            # Salvar atual no histórico antes do rollback
            script_history.append({
                "version": current_script["version"],
                "code": current_script["code"],
                "updated_at": current_script["updated_at"]
            })
            
            # Restaurar versão anterior
            current_script["code"] = target_script["code"]
            current_script["version"] += 1
            current_script["updated_at"] = time.time()
        
        add_message("System", f"Rollback to version {version} (now v{current_script['version']})", system=True)
        
        return jsonify({
            "ok": True,
            "version": current_script["version"]
        })
        
    except Exception as e:
        print("ROLLBACK ERROR:", e)
        return jsonify({"ok": False, "error": str(e)}), 500

# ========== EDITOR WEB COM MONACO ==========

EDITOR_TEMPLATE = '''
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Lua Script Editor - Roblox Executor</title>
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css">
    <style>
        body {
            margin: 0;
            padding: 0;
            height: 100vh;
            display: flex;
            flex-direction: column;
            background: #1e1e1e;
            color: #ccc;
        }
        #toolbar {
            background: #252526;
            padding: 10px 20px;
            border-bottom: 1px solid #3e3e42;
            display: flex;
            gap: 10px;
            align-items: center;
            flex-wrap: wrap;
        }
        #editor-container {
            flex: 1;
            min-height: 0;
        }
        .status-bar {
            background: #007acc;
            padding: 5px 20px;
            font-size: 12px;
            display: flex;
            justify-content: space-between;
            align-items: center;
        }
        .btn {
            font-size: 13px;
            padding: 5px 15px;
        }
        .btn-primary {
            background: #0e639c;
            border-color: #0e639c;
        }
        .btn-primary:hover {
            background: #1177bb;
        }
        .btn-success {
            background: #2ea043;
            border-color: #2ea043;
        }
        .btn-danger {
            background: #da3633;
            border-color: #da3633;
        }
        .version-badge {
            background: #3e3e42;
            padding: 5px 12px;
            border-radius: 15px;
            font-family: monospace;
            font-size: 12px;
        }
        .alert {
            margin: 0;
            padding: 5px 15px;
            font-size: 12px;
        }
        select {
            background: #3e3e42;
            color: #ccc;
            border: 1px solid #0e639c;
            padding: 5px 10px;
            border-radius: 5px;
        }
    </style>
</head>
<body>
    <div id="toolbar">
        <strong style="color: #fff;">🎮 Lua Script Editor</strong>
        <button class="btn btn-primary btn-sm" onclick="saveScript()">💾 Save to Server</button>
        <button class="btn btn-success btn-sm" onclick="showLoadString()">📋 Get Loadstring</button>
        <button class="btn btn-danger btn-sm" onclick="revertChanges()">🔄 Revert</button>
        <div class="version-badge" id="version-display">Version: Loading...</div>
        <select id="history-select" onchange="loadHistoryVersion()" style="width: auto;">
            <option value="">Load history version...</option>
        </select>
        <span style="margin-left: auto; font-size: 11px;" id="save-status">Ready</span>
    </div>
    <div id="editor-container"></div>
    <div class="status-bar">
        <span>📝 Lua Script • Execute with: loadstring(game:HttpGet("{{BASE_URL}}/script/raw"))()</span>
        <span>🟢 Server Online</span>
    </div>

    <script src="https://cdnjs.cloudflare.com/ajax/libs/monaco-editor/0.45.0/min/vs/loader.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
    
    <script>
        let editor;
        let currentVersion = 0;
        let originalCode = "";
        const BASE_URL = window.location.origin;
        
        // Inicializar Monaco
        require.config({ paths: { vs: 'https://cdnjs.cloudflare.com/ajax/libs/monaco-editor/0.45.0/min/vs' } });
        require(['vs/editor/editor.main'], function() {
            editor = monaco.editor.create(document.getElementById('editor-container'), {
                value: '-- Loading script...',
                language: 'lua',
                theme: 'vs-dark',
                fontSize: 14,
                fontFamily: 'Consolas, monospace',
                minimap: { enabled: true },
                automaticLayout: true,
                scrollBeyondLastLine: false,
                lineNumbers: 'on',
                renderWhitespace: 'selection',
                tabSize: 4,
                insertSpaces: true
            });
            
            // Auto-save a cada 30 segundos
            setInterval(autoSave, 30000);
            
            loadCurrentScript();
        });
        
        async function loadCurrentScript() {
            try {
                const response = await fetch(BASE_URL + '/script/current');
                const data = await response.json();
                
                if (data.ok) {
                    originalCode = data.script.code;
                    editor.setValue(originalCode);
                    currentVersion = data.script.version;
                    document.getElementById('version-display').innerHTML = `Version: v${currentVersion}`;
                    updateStatus('Script loaded', 'success');
                    loadHistoryList();
                } else {
                    updateStatus('Failed to load script', 'danger');
                }
            } catch (error) {
                console.error('Load error:', error);
                updateStatus('Connection error', 'danger');
            }
        }
        
        async function saveScript() {
            const code = editor.getValue();
            
            try {
                updateStatus('Saving...', 'info');
                const response = await fetch(BASE_URL + '/script/update', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ code: code })
                });
                
                const data = await response.json();
                
                if (data.ok) {
                    originalCode = code;
                    currentVersion = data.version;
                    document.getElementById('version-display').innerHTML = `Version: v${currentVersion}`;
                    updateStatus('Saved successfully!', 'success');
                    loadHistoryList();
                    showNotification('Script saved!', 'success');
                } else {
                    updateStatus('Save failed: ' + data.error, 'danger');
                }
            } catch (error) {
                console.error('Save error:', error);
                updateStatus('Save error: ' + error.message, 'danger');
            }
        }
        
        function revertChanges() {
            if (confirm('Revert to last saved version? All unsaved changes will be lost.')) {
                editor.setValue(originalCode);
                updateStatus('Reverted to saved version', 'info');
            }
        }
        
        async function autoSave() {
            if (editor.getValue() !== originalCode) {
                console.log('Auto-saving...');
                await saveScript();
            }
        }
        
        async function showLoadString() {
            try {
                const response = await fetch(BASE_URL + '/script/execute', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ executor: 'WebEditor' })
                });
                
                const data = await response.json();
                
                if (data.ok) {
                    // Mostrar modal com loadstring
                    const modalHtml = `
                        <div class="modal fade" id="loadstringModal" tabindex="-1">
                            <div class="modal-dialog modal-lg">
                                <div class="modal-content bg-dark text-light">
                                    <div class="modal-header">
                                        <h5 class="modal-title">📋 Loadstring Code</h5>
                                        <button type="button" class="btn-close btn-close-white" data-bs-dismiss="modal"></button>
                                    </div>
                                    <div class="modal-body">
                                        <p>Copy this code and execute it in your Roblox executor:</p>
                                        <pre style="background: #1e1e1e; padding: 15px; border-radius: 5px; overflow-x: auto;"><code id="loadstring-code" style="color: #9cdcfe;">${escapeHtml(data.loadstring)}</code></pre>
                                        <hr>
                                        <p><strong>Alternative method (simple):</strong></p>
                                        <pre style="background: #1e1e1e; padding: 10px;"><code>loadstring(game:HttpGet("${data.script_url}"))()</code></pre>
                                        <p class="text-muted small">Version: v${data.version}</p>
                                    </div>
                                    <div class="modal-footer">
                                        <button class="btn btn-primary" onclick="copyToClipboard()">📋 Copy Loadstring</button>
                                        <button class="btn btn-secondary" data-bs-dismiss="modal">Close</button>
                                    </div>
                                </div>
                            </div>
                        </div>
                    `;
                    
                    // Remover modal existente se houver
                    const existingModal = document.getElementById('loadstringModal');
                    if (existingModal) existingModal.remove();
                    
                    document.body.insertAdjacentHTML('beforeend', modalHtml);
                    const modal = new bootstrap.Modal(document.getElementById('loadstringModal'));
                    modal.show();
                    
                    // Armazenar loadstring para copy
                    window.currentLoadstring = data.loadstring;
                } else {
                    updateStatus('Failed to get loadstring', 'danger');
                }
            } catch (error) {
                console.error('Loadstring error:', error);
                updateStatus('Error generating loadstring', 'danger');
            }
        }
        
        function copyToClipboard() {
            if (window.currentLoadstring) {
                navigator.clipboard.writeText(window.currentLoadstring).then(() => {
                    updateStatus('Copied to clipboard!', 'success');
                    showNotification('Loadstring copied!', 'success');
                }).catch(() => {
                    updateStatus('Failed to copy', 'danger');
                });
            }
        }
        
        async function loadHistoryList() {
            try {
                const response = await fetch(BASE_URL + '/script/history?limit=20');
                const data = await response.json();
                
                if (data.ok && data.history.length > 0) {
                    const select = document.getElementById('history-select');
                    select.innerHTML = '<option value="">Load history version...</option>';
                    
                    data.history.reverse().forEach(script => {
                        const date = new Date(script.updated_at * 1000);
                        const option = document.createElement('option');
                        option.value = script.version;
                        option.textContent = `v${script.version} - ${date.toLocaleString()}`;
                        select.appendChild(option);
                    });
                }
            } catch (error) {
                console.error('History load error:', error);
            }
        }
        
        async function loadHistoryVersion() {
            const select = document.getElementById('history-select');
            const version = select.value;
            
            if (!version) return;
            
            try {
                const response = await fetch(BASE_URL + '/script/history?limit=100');
                const data = await response.json();
                
                if (data.ok) {
                    const script = data.history.find(s => s.version == version);
                    if (script) {
                        if (confirm(`Load version v${version}? This will replace current editor content.`)) {
                            editor.setValue(script.code);
                            updateStatus(`Loaded version v${version} (not saved to server)`, 'info');
                        }
                    }
                }
                select.value = '';
            } catch (error) {
                console.error('Load version error:', error);
            }
        }
        
        function updateStatus(message, type) {
            const statusDiv = document.getElementById('save-status');
            statusDiv.textContent = message;
            statusDiv.style.color = type === 'danger' ? '#f48771' : type === 'success' ? '#6a9955' : '#9cdcfe';
            setTimeout(() => {
                if (statusDiv.textContent === message) {
                    statusDiv.textContent = 'Ready';
                    statusDiv.style.color = '';
                }
            }, 3000);
        }
        
        function showNotification(message, type) {
            // Criar toast simples
            const toast = document.createElement('div');
            toast.className = `alert alert-${type} position-fixed bottom-0 end-0 m-3`;
            toast.style.zIndex = '9999';
            toast.style.background = type === 'success' ? '#2ea043' : '#da3633';
            toast.style.color = 'white';
            toast.innerHTML = message;
            document.body.appendChild(toast);
            setTimeout(() => toast.remove(), 3000);
        }
        
        function escapeHtml(text) {
            const div = document.createElement('div');
            div.textContent = text;
            return div.innerHTML;
        }
        
        // Keyboard shortcuts
        document.addEventListener('keydown', (e) => {
            if ((e.ctrlKey || e.metaKey) && e.key === 's') {
                e.preventDefault();
                saveScript();
            }
        });
    </script>
</body>
</html>
'''

@app.route("/editor")
def editor():
    """Editor web com Monaco"""
    return render_template_string(EDITOR_TEMPLATE, BASE_URL=request.host_url.rstrip('/'))

# ========== ENDPOINTS ORIGINAIS ==========

@app.route("/")
def home():
    return jsonify({
        "ok": True,
        "message": "Roblox Chat Server Online",
        "endpoints": {
            "chat": "/send, /messages, /history",
            "inventory": "/upload_inventory, /user/<username>, /users",
            "scripts": "/editor, /script/current, /script/update, /script/execute, /script/raw",
            "thumbnail": "/thumbnail/<asset_id>"
        }
    })

@app.route("/thumbnail/<asset_id>")
def thumbnail(asset_id):
    try:
        asset_id = str(asset_id)

        if asset_id in thumbnail_cache:
            cached = thumbnail_cache[asset_id]
            return Response(
                cached,
                mimetype="image/png",
                headers={"Cache-Control": "public, max-age=86400"}
            )

        thumb_api = (
            "https://thumbnails.roblox.com/v1/assets"
            f"?assetIds={asset_id}"
            "&returnPolicy=PlaceHolder"
            "&size=420x420"
            "&format=Png"
            "&isCircular=false"
        )

        api_res = requests.get(thumb_api, timeout=10)
        data = api_res.json()
        image_url = data["data"][0]["imageUrl"]

        if not image_url:
            return jsonify({"ok": False, "error": "No image"}), 404

        img = requests.get(image_url, timeout=10)

        if img.status_code != 200:
            return jsonify({"ok": False, "error": "Failed image"}), 500

        thumbnail_cache[asset_id] = img.content

        return Response(
            img.content,
            mimetype="image/png",
            headers={"Cache-Control": "public, max-age=86400"}
        )

    except Exception as e:
        print("THUMB ERROR:", e)
        return jsonify({"ok": False, "error": str(e)}), 500

@app.route("/upload_inventory", methods=["POST"])
def upload_inventory():
    try:
        data = request.get_json()
        username = str(data.get("username", ""))[:32]
        pets = data.get("pets", [])

        if not username:
            return jsonify({"ok": False, "error": "Missing username"}), 400

        with inventories_lock:
            inventories[username.lower()] = {
                "username": username,
                "pets": pets,
                "updated": time.time()
            }

        print(f"[INV] {username} uploaded {len(pets)} pets")
        return jsonify({"ok": True})

    except Exception as e:
        print("UPLOAD ERROR:", e)
        return jsonify({"ok": False, "error": str(e)}), 500

@app.route("/user/<username>")
def get_user(username):
    with inventories_lock:
        inv = inventories.get(username.lower())

    if not inv:
        return jsonify({"ok": False, "error": "User not found"}), 404

    return jsonify({"ok": True, "inventory": inv})

@app.route("/users")
def users():
    with inventories_lock:
        user_list = list(inventories.keys())
    return jsonify({"ok": True, "users": user_list})

@app.route("/send", methods=["POST"])
def send_message():
    try:
        data = request.get_json(silent=True)
        if not data:
            return jsonify({"ok": False, "error": "Invalid JSON"}), 400

        sender = str(data.get("sender", "Unknown"))[:32]
        message = str(data.get("message", ""))[:200]
        system = bool(data.get("system", False))

        if not message.strip():
            return jsonify({"ok": False, "error": "Empty message"}), 400

        entry = add_message(sender, message, system)
        print(f"[{time.strftime('%H:%M:%S')}] {'[SYSTEM]' if system else sender}: {message}")
        return jsonify({"ok": True, "id": entry["id"]}), 200

    except Exception as e:
        print("SEND ERROR:", e)
        return jsonify({"ok": False, "error": "Internal server error"}), 500

@app.route("/messages", methods=["GET"])
def get_messages():
    try:
        after = int(request.args.get("after", 0))
    except:
        after = 0

    with messages_lock:
        new_messages = [m for m in messages if m["id"] > after]

    return jsonify({"ok": True, "messages": new_messages}), 200

@app.route("/history", methods=["GET"])
def history():
    with messages_lock:
        history_messages = list(messages)
    return jsonify({"ok": True, "messages": history_messages}), 200

@app.route("/status", methods=["GET"])
def status():
    with messages_lock:
        total = len(messages)
    return jsonify({
        "ok": True,
        "total_messages": total,
        "last_id": message_counter,
        "server_time": time.time()
    }), 200

add_message("System", "Server started.", system=True)

if __name__ == "__main__":
    PORT = int(os.environ.get("PORT", 10000))

    print("=" * 50)
    print(" Roblox Chat Server with Lua Executor")
    print(f" Running on port {PORT}")
    print("=" * 50)
    print("\n📝 Web Editor: http://localhost:" + str(PORT) + "/editor")
    print("🔧 Execute in Roblox:")
    print("   loadstring(game:HttpGet('http://localhost:" + str(PORT) + "/script/raw'))()")
    print("=" * 50)

    app.run(host="0.0.0.0", port=PORT, debug=False, threaded=True)
