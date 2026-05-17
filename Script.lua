-- CHAT SYSTEM - Sem persistência local (mensagens em memória; sempre busca do servidor)

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer

-- Config do servidor
local SERVER_URL = "https://chat-p5md.onrender.com/"
local POLL_INTERVAL = 0.8
local lastMessageId = 0

-- Estado
local chatVisible = true
local chatJustOpened = false
local firstOpenDone = false

-- Sem persistência local: tudo em memória
local outgoingQueue = {}
local messageHistory = {}
local seenIds = {}

local connected = true
local tryingReconnect = false
local unreadCount = 0

-- Desativa chat padrão
game:GetService("StarterGui"):SetCoreGuiEnabled(Enum.CoreGuiType.Chat, false)

-- GUI (igual ao anterior; badge com ZIndex alto para ficar por cima)
local ChatGui = Instance.new("ScreenGui")
ChatGui.Name = "ChatGui"
ChatGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ChatGui.IgnoreGuiInset = true
ChatGui.ResetOnSpawn = false
ChatGui.Parent = game.CoreGui

local ToggleButton = Instance.new("TextButton")
ToggleButton.Name = "ToggleChat"
ToggleButton.BackgroundColor3 = Color3.fromRGB(20,20,38)
ToggleButton.BackgroundTransparency = 0.08
ToggleButton.BorderSizePixel = 0
ToggleButton.Position = UDim2.new(1, -48, 0, 8)
ToggleButton.Size = UDim2.new(0, 38, 0, 38)
ToggleButton.Font = Enum.Font.GothamBold
ToggleButton.Text = "💬"
ToggleButton.TextSize = 18
ToggleButton.TextColor3 = Color3.fromRGB(255,255,255)
ToggleButton.ZIndex = 9000
ToggleButton.Parent = ChatGui
Instance.new("UICorner", ToggleButton).CornerRadius = UDim.new(0,8)

local toggleStroke = Instance.new("UIStroke")
toggleStroke.Color = Color3.fromRGB(60,140,255)
toggleStroke.Thickness = 1.2
toggleStroke.Transparency = 0.4
toggleStroke.Parent = ToggleButton

local ChatFrame = Instance.new("Frame")
ChatFrame.Name = "ChatFrame"
ChatFrame.BackgroundColor3 = Color3.fromRGB(15,15,25)
ChatFrame.BackgroundTransparency = 0.08
ChatFrame.BorderSizePixel = 0
ChatFrame.Position = UDim2.new(1, -420, 0, 60)
ChatFrame.Size = UDim2.new(0,400,0,260)
ChatFrame.Parent = ChatGui
Instance.new("UICorner", ChatFrame).CornerRadius = UDim.new(0,10)

local frameStroke = Instance.new("UIStroke")
frameStroke.Color = Color3.fromRGB(60,140,255)
frameStroke.Thickness = 1.2
frameStroke.Transparency = 0.4
frameStroke.Parent = ChatFrame

local MessagesContainer = Instance.new("ScrollingFrame")
MessagesContainer.Name = "MessagesContainer"
MessagesContainer.BackgroundTransparency = 1
MessagesContainer.Position = UDim2.new(0,6,0,6)
MessagesContainer.Size = UDim2.new(1,-12,1,-48)
MessagesContainer.CanvasSize = UDim2.new(0,0,0,0)
MessagesContainer.ScrollBarThickness = 3
MessagesContainer.ScrollBarImageColor3 = Color3.fromRGB(60,140,255)
MessagesContainer.Parent = ChatFrame

local UIListLayout = Instance.new("UIListLayout")
UIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
UIListLayout.Padding = UDim.new(0,3)
UIListLayout.Parent = MessagesContainer

local InputFrame = Instance.new("Frame")
InputFrame.Name = "InputFrame"
InputFrame.BackgroundColor3 = Color3.fromRGB(30,30,50)
InputFrame.BackgroundTransparency = 0.1
InputFrame.BorderSizePixel = 0
InputFrame.Position = UDim2.new(0,6,1,-38)
InputFrame.Size = UDim2.new(1,-12,0,32)
InputFrame.Parent = ChatFrame
Instance.new("UICorner", InputFrame).CornerRadius = UDim.new(0,8)

local inputStroke = Instance.new("UIStroke")
inputStroke.Color = Color3.fromRGB(60,140,255)
inputStroke.Thickness = 1
inputStroke.Transparency = 0.6
inputStroke.Parent = InputFrame

local ChatInput = Instance.new("TextBox")
ChatInput.Name = "ChatInput"
ChatInput.BackgroundTransparency = 1
ChatInput.Position = UDim2.new(0,8,0,0)
ChatInput.Size = UDim2.new(1,-55,1,0)
ChatInput.ClearTextOnFocus = false
ChatInput.Font = Enum.Font.Gotham
ChatInput.PlaceholderColor3 = Color3.fromRGB(100,110,140)
ChatInput.PlaceholderText = "Digite sua mensagem..."
ChatInput.Text = ""
ChatInput.TextColor3 = Color3.fromRGB(220,235,255)
ChatInput.TextSize = 13
ChatInput.TextXAlignment = Enum.TextXAlignment.Left
ChatInput.Parent = InputFrame

local SendButton = Instance.new("TextButton")
SendButton.Name = "SendButton"
SendButton.BackgroundColor3 = Color3.fromRGB(30,100,255)
SendButton.BackgroundTransparency = 0.1
SendButton.BorderSizePixel = 0
SendButton.Position = UDim2.new(1,-48,0,3)
SendButton.Size = UDim2.new(0,44,0,26)
SendButton.Font = Enum.Font.GothamBold
SendButton.Text = "Enviar"
SendButton.TextColor3 = Color3.fromRGB(255,255,255)
SendButton.TextScaled = true
SendButton.Parent = InputFrame
Instance.new("UICorner", SendButton).CornerRadius = UDim.new(0,6)

local UnreadBadge = Instance.new("TextLabel")
UnreadBadge.Name = "UnreadBadge"
UnreadBadge.Size = UDim2.new(0,24,0,24)
UnreadBadge.Position = UDim2.new(1,-18,0,-4)
UnreadBadge.BackgroundColor3 = Color3.fromRGB(255,80,80)
UnreadBadge.TextColor3 = Color3.fromRGB(255,255,255)
UnreadBadge.Font = Enum.Font.GothamBold
UnreadBadge.TextSize = 14
UnreadBadge.Text = ""
UnreadBadge.Visible = false
UnreadBadge.Parent = ToggleButton
Instance.new("UICorner", UnreadBadge).CornerRadius = UDim.new(0,12)
UnreadBadge.ZIndex = 10001
UnreadBadge.Active = true
UnreadBadge.Selectable = true

local COLORS = {
    system = Color3.fromRGB(255,200,0),
    self = Color3.fromRGB(80,170,255),
    other = Color3.fromRGB(120,220,130),
    queued = Color3.fromRGB(200,160,255),
}

-- util: copiar p/ clipboard (se executor suportar)
local function copyToClipboard(text)
    if not text then return false end
    if type(setclipboard) == "function" then
        local ok = pcall(setclipboard, text)
        return ok
    end
    if _G and type(_G.setclipboard) == "function" then
        local ok = pcall(_G.setclipboard, text)
        return ok
    end
    return false
end

-- cria linha clicável (não-sistema) para copiar texto
local function createMessageDisplay(senderName, message, isSystemMessage, opts)
    opts = opts or {}
    local queued = opts.queued
    local msgText = message or ""

    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1,0,0,0)
    frame.BackgroundTransparency = 1
    frame.AutomaticSize = Enum.AutomaticSize.Y
    frame.Parent = MessagesContainer

    local pad = Instance.new("UIPadding", frame)
    pad.PaddingLeft = UDim.new(0,4)
    pad.PaddingRight = UDim.new(0,4)

    local lbl
    if isSystemMessage then
        lbl = Instance.new("TextLabel")
        lbl.BackgroundTransparency = 1
    else
        lbl = Instance.new("TextButton")
        lbl.BackgroundTransparency = 1
        lbl.AutoButtonColor = false
        lbl.MouseButton1Click:Connect(function()
            local ok = copyToClipboard(msgText)
            if ok then
                -- feedback efêmero em painel (não persistente)
                local fb = Instance.new("TextLabel")
                fb.Size = UDim2.new(1,0,0,18)
                fb.BackgroundTransparency = 1
                fb.Font = Enum.Font.Gotham
                fb.TextSize = 12
                fb.TextColor3 = COLORS.system
                fb.Text = "Mensagem copiada para o clipboard."
                fb.Parent = MessagesContainer
                task.delay(2, function() pcall(function() fb:Destroy() end) end)
            else
                local fb = Instance.new("TextLabel")
                fb.Size = UDim2.new(1,0,0,18)
                fb.BackgroundTransparency = 1
                fb.Font = Enum.Font.Gotham
                fb.TextSize = 12
                fb.TextColor3 = COLORS.system
                fb.Text = "Falha ao copiar: setclipboard não disponível."
                fb.Parent = MessagesContainer
                task.delay(2, function() pcall(function() fb:Destroy() end) end)
            end
        end)
    end

    lbl.Size = UDim2.new(1,0,0,0)
    lbl.TextSize = 13
    lbl.Font = Enum.Font.Gotham
    lbl.TextWrapped = true
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.AutomaticSize = Enum.AutomaticSize.Y
    lbl.Parent = frame

    if isSystemMessage then
        lbl.Text = "⚙ " .. msgText
        lbl.TextColor3 = COLORS.system
    else
        local isSelf = senderName == player.Name
        lbl.Text = (isSelf and "▶ [Você] " or "● [" .. senderName .. "] ") .. msgText .. (queued and " (aguardando envio)" or "")
        lbl.TextColor3 = isSelf and COLORS.self or (queued and COLORS.queued or COLORS.other)
    end

    task.wait(0.05)
    MessagesContainer.CanvasSize = UDim2.new(0,0,0, MessagesContainer.UIListLayout.AbsoluteContentSize.Y + 8)
    MessagesContainer.CanvasPosition = Vector2.new(0, MessagesContainer.CanvasSize.Y.Offset)
end

local function updateToggleText()
    if chatVisible then
        ToggleButton.Text = "✕"
        UnreadBadge.Visible = false
    else
        ToggleButton.Text = "💬"
        UnreadBadge.Visible = unreadCount > 0
        UnreadBadge.Text = tostring(unreadCount > 99 and "99+" or unreadCount)
    end
end

local function setChatVisible(visible)
    chatVisible = visible
    ChatFrame.Visible = visible
    updateToggleText()
    if visible then
        toggleStroke.Color = Color3.fromRGB(255,80,80)
    else
        toggleStroke.Color = Color3.fromRGB(60,140,255)
    end
end

setChatVisible(true)

ToggleButton.MouseButton1Click:Connect(function()
    if chatVisible then
        setChatVisible(false)
        firstOpenDone = true
    else
        chatJustOpened = true
        setChatVisible(true)
        unreadCount = 0
        updateToggleText()
        task.delay(POLL_INTERVAL + 0.1, function() chatJustOpened = false end)
    end
end)

-- Bubbles (mantido; não interativo para cópia)
local BUBBLE_DURATION = 8
local BUBBLE_FADE_TIME = 1.5
local BUBBLE_SPACING = 2.2
local BUBBLE_BASE_Y = 2.5
local playerBubbles = {}

local function getHead(senderName)
    for _, p in pairs(Players:GetPlayers()) do
        if p.Name == senderName and p.Character then
            return p.Character:FindFirstChild("Head") or p.Character:FindFirstChildOfClass("BasePart")
        end
    end
end

local function recalcBubbles(name)
    local list = playerBubbles[name]
    if not list then return end
    for i = #list, 1, -1 do
        local bb = list[i]
        if bb and bb.Parent then
            local targetY = BUBBLE_BASE_Y + (#list - i) * BUBBLE_SPACING
            task.spawn(function()
                local t0, dur = os.clock(), 0.25
                local startY = bb.StudsOffset.Y
                while os.clock() - t0 < dur do
                    local a = (os.clock() - t0) / dur
                    a = 1 - (1-a)^3
                    if bb and bb.Parent then
                        bb.StudsOffset = Vector3.new(0, startY + (targetY - startY)*a, 0)
                    end
                    task.wait()
                end
                if bb and bb.Parent then bb.StudsOffset = Vector3.new(0, targetY, 0) end
            end)
        end
    end
end

local function createBubble(senderName, message)
    if chatJustOpened then return end
    local head = getHead(senderName)
    if not head then return end
    local character = head.Parent
    playerBubbles[senderName] = playerBubbles[senderName] or {}
    table.insert(playerBubbles[senderName], 1, nil)

    local bb = Instance.new("BillboardGui")
    bb.Name = "ChatBubble"
    bb.Adornee = head
    bb.Size = UDim2.new(5,0,1.8,0)
    bb.StudsOffset = Vector3.new(0, BUBBLE_BASE_Y, 0)
    bb.MaxDistance = 100
    bb.AlwaysOnTop = true
    bb.Parent = character

    local bg = Instance.new("Frame", bb)
    bg.Size = UDim2.new(1,0,1,0)
    bg.BackgroundColor3 = Color3.fromRGB(12,12,22)
    bg.BackgroundTransparency = 0.08
    bg.BorderSizePixel = 0
    Instance.new("UICorner", bg).CornerRadius = UDim.new(0,12)

    local nameLbl = Instance.new("TextLabel", bg)
    nameLbl.Size = UDim2.new(1,0,0,13)
    nameLbl.BackgroundTransparency = 1
    nameLbl.Font = Enum.Font.GothamBold
    nameLbl.TextSize = 10
    nameLbl.TextColor3 = Color3.fromRGB(80,170,255)
    nameLbl.TextXAlignment = Enum.TextXAlignment.Left
    nameLbl.Text = senderName

    local msgLbl = Instance.new("TextLabel", bg)
    msgLbl.Size = UDim2.new(1,0,1,-14)
    msgLbl.Position = UDim2.new(0,0,0,14)
    msgLbl.BackgroundTransparency = 1
    msgLbl.TextColor3 = Color3.fromRGB(225,238,255)
    msgLbl.Font = Enum.Font.Gotham
    msgLbl.TextSize = 13
    msgLbl.TextWrapped = true
    msgLbl.TextXAlignment = Enum.TextXAlignment.Left
    msgLbl.TextYAlignment = Enum.TextYAlignment.Top
    msgLbl.Text = message

    playerBubbles[senderName][1] = bb
    recalcBubbles(senderName)

    task.delay(BUBBLE_DURATION, function()
        if not bb or not bb.Parent then return end
        for i, b in pairs(playerBubbles[senderName] or {}) do
            if b == bb then table.remove(playerBubbles[senderName], i) break end
        end
        bb.Parent = nil
        recalcBubbles(senderName)
    end)
end

Players.PlayerRemoving:Connect(function(p) playerBubbles[p.Name] = nil end)

-- Mensagens: em memória apenas
local function addToHistoryInMemory(entry)
    if not entry or not entry.id then return end
    if seenIds[entry.id] then return end
    seenIds[entry.id] = true
    table.insert(messageHistory, entry)
end

local function onMessage(senderName, message, isSystemMessage, opts)
    opts = opts or {}
    createMessageDisplay(senderName, message, isSystemMessage, opts)
    if not isSystemMessage then
        createBubble(senderName, message)
        if not chatVisible then
            unreadCount = unreadCount + 1
            updateToggleText()
        end
    end
    if opts.entry and opts.entry.id then
        addToHistoryInMemory(opts.entry)
    end
end

-- HTTP helpers (request is expected to be available in executor)
local function httpPostRaw(path, body)
    local ok, res = pcall(request, {
        Url = SERVER_URL .. path,
        Method = "POST",
        Headers = { ["Content-Type"] = "application/json" },
        Body = HttpService:JSONEncode(body),
    })
    return ok and res or nil
end

local function httpGetRaw(path)
    local ok, res = pcall(request, {
        Url = SERVER_URL .. path,
        Method = "GET",
    })
    return ok and res or nil
end

local function enqueueOutgoing(entry)
    table.insert(outgoingQueue, entry)
end

local function trySendOutgoing()
    if #outgoingQueue == 0 then return end
    local i = 1
    while i <= #outgoingQueue do
        local e = outgoingQueue[i]
        local res = httpPostRaw("/send", { sender = e.sender, message = e.message, system = e.system or false })
        if res and res.StatusCode == 200 then
            table.remove(outgoingQueue, i)
        else
            break
        end
    end
end

local function httpPost(path, body)
    local res = httpPostRaw(path, body)
    if res and res.StatusCode == 200 then
        connected = true
        return res
    else
        connected = false
        if path == "/send" and body and body.sender and body.message then
            enqueueOutgoing({ sender = body.sender, message = body.message, system = body.system or false, ts = os.time() })
            onMessage(body.sender, body.message, body.system or false, { queued = true })
        end
        return nil
    end
end

local function httpGet(path)
    local res = httpGetRaw(path)
    if res and res.StatusCode == 200 then
        connected = true
        return res
    else
        connected = false
        return nil
    end
end

-- Envio de mensagem
local function sendMessage()
    local msg = ChatInput.Text
    if not msg or msg:match("^%s*$") then return end
    ChatInput.Text = ""
    httpPost("/send", {
        sender = player.Name,
        message = msg,
    })
end

-- Sincronização com servidor (sempre busca do servidor)
local function clearUI()
    for _, child in ipairs(MessagesContainer:GetChildren()) do
        if child ~= UIListLayout then
            pcall(function() child:Destroy() end)
        end
    end
    MessagesContainer.CanvasSize = UDim2.new(0,0,0,0)
end

local function repopulateFromHistoryInMemory()
    clearUI()
    table.sort(messageHistory, function(a,b)
        if a.id and b.id then return a.id < b.id end
        return (a.ts or 0) < (b.ts or 0)
    end)
    for _, entry in ipairs(messageHistory) do
        onMessage(entry.sender or "?", entry.message or "", entry.system or false, { entry = entry })
    end
end

local function fetchAndSyncFromServer()
    local res = httpGet("/messages?after=0")
    if res and res.StatusCode == 200 then
        local ok, data = pcall(function() return HttpService:JSONDecode(res.Body) end)
        if ok and data and data.messages then
            for _, entry in ipairs(data.messages) do
                if entry.id and not seenIds[entry.id] then
                    addToHistoryInMemory(entry)
                end
                if entry.id and entry.id > lastMessageId then lastMessageId = entry.id end
            end
            repopulateFromHistoryInMemory()
        end
    end
end

local function onReconnect()
    trySendOutgoing()
    fetchAndSyncFromServer()
end

-- Polling
task.spawn(function()
    while true do
        task.wait(POLL_INTERVAL)
        local res = httpGet("/messages?after=" .. lastMessageId)
        if res and res.StatusCode == 200 then
            local ok, data = pcall(function() return HttpService:JSONDecode(res.Body) end)
            if ok and data and data.messages then
                if not connected then onReconnect() end
                for _, entry in ipairs(data.messages) do
                    if entry.id and not seenIds[entry.id] then
                        lastMessageId = math.max(lastMessageId, entry.id or lastMessageId)
                        addToHistoryInMemory(entry)
                        onMessage(entry.sender, entry.message, entry.system or false, { entry = entry })
                    end
                end
            else
                connected = false
            end
        else
            if not tryingReconnect then
                tryingReconnect = true
                task.spawn(function()
                    while not connected do
                        task.wait(2)
                        local test = httpGet("/messages?after=" .. lastMessageId)
                        if test and test.StatusCode == 200 then
                            connected = true
                            tryingReconnect = false
                            onReconnect()
                            break
                        end
                    end
                end)
            end
        end
    end
end)

-- Eventos de input
SendButton.MouseButton1Click:Connect(sendMessage)
ChatInput.FocusLost:Connect(function(enter) if enter then sendMessage() end)
UserInputService.InputBegan:Connect(function(input, processed)
    if not processed and input.KeyCode == Enum.KeyCode.Slash then
        ChatInput:CaptureFocus()
    end
end)

-- Inicialização: sempre buscar do servidor
fetchAndSyncFromServer()

return nil
