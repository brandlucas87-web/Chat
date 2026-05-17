from flask import Flask, request, jsonify, Response
from flask_cors import CORS

import threading
import time
import os
import requests

app = Flask(__name__)
CORS(app)

MAX_HISTORY = 500

messages_lock = threading.Lock()
messages = []
message_counter = 0

inventories = {}
inventories_lock = threading.Lock()

thumbnail_cache = {}

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

@app.route("/")
def home():
    return jsonify({
        "ok": True,
        "message": "Roblox Chat Server Online"
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
                headers={
                    "Cache-Control": "public, max-age=86400"
                }
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
            return jsonify({
                "ok": False,
                "error": "No image"
            }), 404

        img = requests.get(image_url, timeout=10)

        if img.status_code != 200:
            return jsonify({
                "ok": False,
                "error": "Failed image"
            }), 500

        thumbnail_cache[asset_id] = img.content

        return Response(
            img.content,
            mimetype="image/png",
            headers={
                "Cache-Control": "public, max-age=86400"
            }
        )

    except Exception as e:

        print("THUMB ERROR:", e)

        return jsonify({
            "ok": False,
            "error": str(e)
        }), 500

@app.route("/upload_inventory", methods=["POST"])
def upload_inventory():

    try:

        data = request.get_json()

        username = str(data.get("username", ""))[:32]
        pets = data.get("pets", [])

        if not username:

            return jsonify({
                "ok": False,
                "error": "Missing username"
            }), 400

        with inventories_lock:

            inventories[username.lower()] = {
                "username": username,
                "pets": pets,
                "updated": time.time()
            }

        print(f"[INV] {username} uploaded {len(pets)} pets")

        return jsonify({
            "ok": True
        })

    except Exception as e:

        print("UPLOAD ERROR:", e)

        return jsonify({
            "ok": False,
            "error": str(e)
        }), 500

@app.route("/user/<username>")
def get_user(username):

    with inventories_lock:

        inv = inventories.get(username.lower())

    if not inv:

        return jsonify({
            "ok": False,
            "error": "User not found"
        }), 404

    return jsonify({
        "ok": True,
        "inventory": inv
    })

@app.route("/users")
def users():

    with inventories_lock:

        user_list = list(inventories.keys())

    return jsonify({
        "ok": True,
        "users": user_list
    })

@app.route("/send", methods=["POST"])
def send_message():

    try:

        data = request.get_json(silent=True)

        if not data:

            return jsonify({
                "ok": False,
                "error": "Invalid JSON"
            }), 400

        sender = str(data.get("sender", "Unknown"))[:32]
        message = str(data.get("message", ""))[:200]
        system = bool(data.get("system", False))

        if not message.strip():

            return jsonify({
                "ok": False,
                "error": "Empty message"
            }), 400

        entry = add_message(sender, message, system)

        print(
            f"[{time.strftime('%H:%M:%S')}] "
            f"{'[SYSTEM]' if system else sender}: {message}"
        )

        return jsonify({
            "ok": True,
            "id": entry["id"]
        }), 200

    except Exception as e:

        print("SEND ERROR:", e)

        return jsonify({
            "ok": False,
            "error": "Internal server error"
        }), 500

@app.route("/messages", methods=["GET"])
def get_messages():

    try:
        after = int(request.args.get("after", 0))
    except:
        after = 0

    with messages_lock:

        new_messages = [
            m for m in messages
            if m["id"] > after
        ]

    return jsonify({
        "ok": True,
        "messages": new_messages
    }), 200

@app.route("/history", methods=["GET"])
def history():

    with messages_lock:

        history_messages = list(messages)

    return jsonify({
        "ok": True,
        "messages": history_messages
    }), 200

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

add_message(
    "System",
    "Server started.",
    system=True
)

if __name__ == "__main__":

    PORT = int(os.environ.get("PORT", 10000))

    print("=" * 50)
    print(" Roblox Chat Server")
    print(f" Running on port {PORT}")
    print("=" * 50)

    app.run(
        host="0.0.0.0",
        port=PORT,
        debug=False,
        threaded=True
    )
