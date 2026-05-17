-- ============================================================
--  CHAT SYSTEM - LocalScript único (executor) + Python server
--  Comunicação via HTTP polling com request()
-- ============================================================

local Players        = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService     = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ── Config do servidor Python ────────────────────────────────
local SERVER_URL    = "https://chat-p5md.onrender.com/"   -- troque pelo IP/porta do seu servidor
local POLL_INTERVAL = 0.8                        -- segundos entre cada poll
local lastMessageId = 0                          -- controle de mensagens já recebidas

-- ── Desativar chat padrão ────────────────────────────────────
game:GetService("StarterGui"):SetCoreGuiEnabled(Enum.CoreGuiType.Chat, false)

-- ============================================================
--  GUI
-- ============================================================
local ChatGui = Instance.new("ScreenGui")
ChatGui.Name            = "ChatGui"
ChatGui.ZIndexBehavior  = Enum.ZIndexBehavior.Sibling
ChatGui.IgnoreGuiInset  = true
ChatGui.ResetOnSpawn    = false
ChatGui.Parent          = game.CoreGui

local ChatFrame = Instance.new("Frame")
ChatFrame.Name                  = "ChatFrame"
ChatFrame.BackgroundColor3      = Color3.fromRGB(15, 15, 25)
ChatFrame.BackgroundTransparency = 0.08
ChatFrame.BorderSizePixel       = 0
ChatFrame.Position              = UDim2.new(1, -420, 0, 60)
ChatFrame.Size                  = UDim2.new(0, 400, 0, 260)
ChatFrame.Parent                = ChatGui
Instance.new("UICorner", ChatFrame).CornerRadius = UDim.new(0, 10)

-- Borda decorativa
local frameStroke = Instance.new("UIStroke")
frameStroke.Color       = Color3.fromRGB(60, 140, 255)
frameStroke.Thickness   = 1.2
frameStroke.Transparency = 0.4
frameStroke.Parent      = ChatFrame

-- Área de mensagens
local MessagesContainer = Instance.new("ScrollingFrame")
MessagesContainer.Name                  = "MessagesContainer"
MessagesContainer.BackgroundTransparency = 1
MessagesContainer.Position              = UDim2.new(0, 6, 0, 6)
MessagesContainer.Size                  = UDim2.new(1, -12, 1, -48)
MessagesContainer.CanvasSize            = UDim2.new(0, 0, 0, 0)
MessagesContainer.ScrollBarThickness    = 3
MessagesContainer.ScrollBarImageColor3  = Color3.fromRGB(60, 140, 255)
MessagesContainer.Parent                = ChatFrame

local UIListLayout = Instance.new("UIListLayout")
UIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
UIListLayout.Padding   = UDim.new(0, 3)
UIListLayout.Parent    = MessagesContainer

-- Frame de input
local InputFrame = Instance.new("Frame")
InputFrame.Name                  = "InputFrame"
InputFrame.BackgroundColor3      = Color3.fromRGB(30, 30, 50)
InputFrame.BackgroundTransparency = 0.1
InputFrame.BorderSizePixel       = 0
InputFrame.Position              = UDim2.new(0, 6, 1, -38)
InputFrame.Size                  = UDim2.new(1, -12, 0, 32)
InputFrame.Parent                = ChatFrame
Instance.new("UICorner", InputFrame).CornerRadius = UDim.new(0, 8)

local inputStroke = Instance.new("UIStroke")
inputStroke.Color       = Color3.fromRGB(60, 140, 255)
inputStroke.Thickness   = 1
inputStroke.Transparency = 0.6
inputStroke.Parent      = InputFrame

local ChatInput = Instance.new("TextBox")
ChatInput.Name                  = "ChatInput"
ChatInput.BackgroundTransparency = 1
ChatInput.Position              = UDim2.new(0, 8, 0, 0)
ChatInput.Size                  = UDim2.new(1, -55, 1, 0)
ChatInput.ClearTextOnFocus      = false
ChatInput.Font                  = Enum.Font.Gotham
ChatInput.PlaceholderColor3     = Color3.fromRGB(100, 110, 140)
ChatInput.PlaceholderText       = "Digite sua mensagem..."
ChatInput.Text                  = ""
ChatInput.TextColor3            = Color3.fromRGB(220, 235, 255)
ChatInput.TextSize              = 13
ChatInput.TextXAlignment        = Enum.TextXAlignment.Left
ChatInput.Parent                = InputFrame

local SendButton = Instance.new("TextButton")
SendButton.Name                  = "SendButton"
SendButton.BackgroundColor3      = Color3.fromRGB(30, 100, 255)
SendButton.BackgroundTransparency = 0.1
SendButton.BorderSizePixel       = 0
SendButton.Position              = UDim2.new(1, -48, 0, 3)
SendButton.Size                  = UDim2.new(0, 44, 0, 26)
SendButton.Font                  = Enum.Font.GothamBold
SendButton.Text                  = "Enviar"
SendButton.TextColor3            = Color3.fromRGB(255, 255, 255)
SendButton.TextScaled            = true
SendButton.Parent                = InputFrame
Instance.new("UICorner", SendButton).CornerRadius = UDim.new(0, 6)

-- ============================================================
--  CORES
-- ============================================================
local COLORS = {
	system = Color3.fromRGB(255, 200, 0),
	self   = Color3.fromRGB(80,  170, 255),
	other  = Color3.fromRGB(120, 220, 130),
}

-- ============================================================
--  EXIBIR MENSAGEM NA UI
-- ============================================================
local function createMessageDisplay(senderName, message, isSystemMessage)
	local frame = Instance.new("Frame")
	frame.Size                  = UDim2.new(1, 0, 0, 0)
	frame.BackgroundTransparency = 1
	frame.AutomaticSize         = Enum.AutomaticSize.Y
	frame.Parent                = MessagesContainer

	local pad = Instance.new("UIPadding", frame)
	pad.PaddingLeft  = UDim.new(0, 4)
	pad.PaddingRight = UDim.new(0, 4)

	local lbl = Instance.new("TextLabel")
	lbl.Size                  = UDim2.new(1, 0, 0, 0)
	lbl.BackgroundTransparency = 1
	lbl.TextSize              = 13
	lbl.Font                  = Enum.Font.Gotham
	lbl.TextWrapped           = true
	lbl.TextXAlignment        = Enum.TextXAlignment.Left
	lbl.AutomaticSize         = Enum.AutomaticSize.Y
	lbl.Parent                = frame

	if isSystemMessage then
		lbl.Text       = "⚙ " .. message
		lbl.TextColor3 = COLORS.system
	else
		local isSelf = senderName == player.Name
		lbl.Text       = (isSelf and "▶ [Você] " or "● [" .. senderName .. "] ") .. message
		lbl.TextColor3 = isSelf and COLORS.self or COLORS.other
	end

	task.wait(0.05)
	MessagesContainer.CanvasSize = UDim2.new(0, 0, 0,
		MessagesContainer.UIListLayout.AbsoluteContentSize.Y + 8)
	MessagesContainer.CanvasPosition = Vector2.new(0,
		MessagesContainer.CanvasSize.Y.Offset)
end

-- ============================================================
--  BUBBLE CHAT
-- ============================================================
local BUBBLE_DURATION  = 8
local BUBBLE_FADE_TIME = 1.5
local BUBBLE_SPACING   = 2.2
local BUBBLE_BASE_Y    = 2.5
local playerBubbles    = {}

local function getHead(senderName)
	for _, p in Players:GetPlayers() do
		if p.Name == senderName and p.Character then
			return p.Character:FindFirstChild("Head")
				or p.Character:FindFirstChildOfClass("BasePart")
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
				if bb and bb.Parent then
					bb.StudsOffset = Vector3.new(0, targetY, 0)
				end
			end)
		end
	end
end

local function createBubble(senderName, message)
	local head = getHead(senderName)
	if not head then return end

	local character = head.Parent
	playerBubbles[senderName] = playerBubbles[senderName] or {}
	table.insert(playerBubbles[senderName], 1, nil)

	local bb = Instance.new("BillboardGui")
	bb.Name         = "ChatBubble"
	bb.Adornee      = head
	bb.Size         = UDim2.new(5, 0, 1.8, 0)
	bb.StudsOffset  = Vector3.new(0, BUBBLE_BASE_Y, 0)
	bb.MaxDistance  = 100
	bb.AlwaysOnTop  = true
	bb.Parent       = character

	local bg = Instance.new("Frame", bb)
	bg.Size                  = UDim2.new(1, 0, 1, 0)
	bg.BackgroundColor3      = Color3.fromRGB(12, 12, 22)
	bg.BackgroundTransparency = 0.08
	bg.BorderSizePixel       = 0
	Instance.new("UICorner", bg).CornerRadius = UDim.new(0, 12)

	local glow = Instance.new("UIStroke", bg)
	glow.Color       = Color3.fromRGB(0, 100, 255)
	glow.Thickness   = 2.5
	glow.Transparency = 0.55

	local border = Instance.new("UIStroke")          -- second stroke trick
	border.Color       = Color3.fromRGB(80, 170, 255)
	border.Thickness   = 1
	border.Transparency = 0.1
	border.Parent      = bg

	local pad = Instance.new("UIPadding", bg)
	pad.PaddingTop    = UDim.new(0, 5)
	pad.PaddingBottom = UDim.new(0, 5)
	pad.PaddingLeft   = UDim.new(0, 9)
	pad.PaddingRight  = UDim.new(0, 9)

	local nameLbl = Instance.new("TextLabel", bg)
	nameLbl.Size                  = UDim2.new(1, 0, 0, 13)
	nameLbl.BackgroundTransparency = 1
	nameLbl.Font                  = Enum.Font.GothamBold
	nameLbl.TextSize              = 10
	nameLbl.TextColor3            = Color3.fromRGB(80, 170, 255)
	nameLbl.TextXAlignment        = Enum.TextXAlignment.Left
	nameLbl.Text                  = senderName

	local msgLbl = Instance.new("TextLabel", bg)
	msgLbl.Size                  = UDim2.new(1, 0, 1, -14)
	msgLbl.Position              = UDim2.new(0, 0, 0, 14)
	msgLbl.BackgroundTransparency = 1
	msgLbl.TextColor3            = Color3.fromRGB(225, 238, 255)
	msgLbl.TextStrokeTransparency = 0.8
	msgLbl.Font                  = Enum.Font.Gotham
	msgLbl.TextSize              = 13
	msgLbl.TextWrapped           = true
	msgLbl.TextXAlignment        = Enum.TextXAlignment.Left
	msgLbl.TextYAlignment        = Enum.TextYAlignment.Top
	msgLbl.Text                  = message

	-- Pop-in
	task.spawn(function()
		local t0, dur = os.clock(), 0.28
		while os.clock() - t0 < dur do
			local a = (os.clock() - t0) / dur
			local s = 1 - math.pow(2, -10*a) * math.sin((a*10 - 0.75)*(2*math.pi)/3)
			s = math.clamp(s, 0, 1.1)
			if bg and bg.Parent then
				bg.Size = UDim2.new(s, 0, s, 0)
			end
			task.wait()
		end
		if bg and bg.Parent then bg.Size = UDim2.new(1, 0, 1, 0) end
	end)

	playerBubbles[senderName][1] = bb
	recalcBubbles(senderName)

	-- Fade out
	task.delay(BUBBLE_DURATION, function()
		if not bb or not bb.Parent then return end
		local t0 = os.clock()
		while os.clock() - t0 < BUBBLE_FADE_TIME do
			local a = (os.clock() - t0) / BUBBLE_FADE_TIME
			if bg     and bg.Parent     then bg.BackgroundTransparency     = 0.08 + a*0.92 end
			if msgLbl and msgLbl.Parent then
				msgLbl.TextTransparency       = a
				msgLbl.TextStrokeTransparency = 0.8 + a*0.2
			end
			if nameLbl and nameLbl.Parent then nameLbl.TextTransparency = a end
			if glow   and glow.Parent   then glow.Transparency   = 0.55 + a*0.45 end
			if border and border.Parent then border.Transparency = 0.1  + a*0.9  end
			task.wait()
		end
		for i, b in (playerBubbles[senderName] or {}) do
			if b == bb then table.remove(playerBubbles[senderName], i) break end
		end
		bb.Parent = nil
		recalcBubbles(senderName)
	end)
end

Players.PlayerRemoving:Connect(function(p) playerBubbles[p.Name] = nil end)

-- ============================================================
--  RECEBER mensagem (exibe na UI + cria bubble)
-- ============================================================
local function onMessage(senderName, message, isSystemMessage)
	createMessageDisplay(senderName, message, isSystemMessage)
	if not isSystemMessage then
		createBubble(senderName, message)
	end
end

-- ============================================================
--  HTTP — enviar mensagem ao servidor Python
-- ============================================================
local function httpPost(path, body)
	-- request() é a função global disponível em executors (Synapse, KRNL, etc.)
	-- Se estiver rodando num servidor dedicado com HttpService habilitado,
	-- troque request() por HttpService:PostAsync()
	local ok, res = pcall(request, {
		Url    = SERVER_URL .. path,
		Method = "POST",
		Headers = { ["Content-Type"] = "application/json" },
		Body   = game:GetService("HttpService"):JSONEncode(body),
	})
	return ok and res or nil
end

local function httpGet(path)
	local ok, res = pcall(request, {
		Url    = SERVER_URL .. path,
		Method = "GET",
	})
	return ok and res or nil
end

-- Enviar mensagem
local function sendMessage()
	local msg = ChatInput.Text
	if not msg or msg:match("^%s*$") then return end
	ChatInput.Text = ""

	httpPost("/send", {
		sender  = player.Name,
		message = msg,
	})
end

-- ============================================================
--  POLLING — receber mensagens novas do servidor
-- ============================================================
task.spawn(function()
	local HttpService = game:GetService("HttpService")
	while true do
		task.wait(POLL_INTERVAL)
		local res = httpGet("/messages?after=" .. lastMessageId)
		if res and res.StatusCode == 200 then
			local ok, data = pcall(function()
				return HttpService:JSONDecode(res.Body)
			end)
			if ok and data and data.messages then
				for _, entry in ipairs(data.messages) do
					if entry.id > lastMessageId then
						lastMessageId = entry.id
						onMessage(entry.sender, entry.message, entry.system or false)
					end
				end
			end
		end
	end
end)

-- ============================================================
--  EVENTOS DE INPUT
-- ============================================================
SendButton.MouseButton1Click:Connect(sendMessage)

ChatInput.FocusLost:Connect(function(enter)
	if enter then sendMessage() end
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == Enum.KeyCode.Slash then
		ChatInput:CaptureFocus()
	end
end)

-- ============================================================
--  MENSAGEM DE BOAS-VINDAS
-- ============================================================
onMessage("Sistema", "Bem-vindo! Pressione / para digitar. Conectando ao servidor...", true)

-- Anunciar entrada no chat para todos via servidor
httpPost("/send", {
	sender  = "Sistema",
	message = player.Name .. " entrou no chat.",
	system  = true,
})

return nil
