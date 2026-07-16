local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Player = Players.LocalPlayer

local CageRebirthRequirements = require(game.ReplicatedStorage.CageRebirthRequirements)
local BrainrotConfig = require(game.ReplicatedStorage.BrainrotConfig)
local SpawnChanceConfig = require(ReplicatedStorage.SpawnChanceConfig)
local PickaxeConfig = require(game.ReplicatedStorage:WaitForChild("PickaxeConfig"))
local BrainrotInventoryController = require(game.ReplicatedStorage.Modules:WaitForChild("BrainrotInventoryController"))
local CageOrder = SpawnChanceConfig.CageOrder
local RarityChances = SpawnChanceConfig.RarityChances

local RARITY_COLORS = {
	Common = Color3.fromRGB(180, 180, 180),
	Rare = Color3.fromRGB(80, 150, 255),
	Epic = Color3.fromRGB(180, 80, 255),
	Legendary = Color3.fromRGB(255, 180, 50),
	Mythic = Color3.fromRGB(255, 60, 60),
	Cosmic = Color3.fromRGB(100, 220, 255),
	Secret = Color3.fromRGB(255, 255, 100),
	Meme = Color3.fromRGB(255, 150, 255),
	Glitch = Color3.fromRGB(0, 255, 200),
	Celestial = Color3.fromRGB(255, 220, 180),
	Ancient = Color3.fromRGB(200, 150, 80),
}

local RARITY_ORDER = {
	"Common",
	"Rare",
	"Epic",
	"Legendary",
	"Mythic",
	"Cosmic",
	"Secret",
	"Meme",
	"Glitch",
	"Celestial",
	"Ancient"
}

local Analyzer = {}

local sortedCages = {}
do
	local seen = {}
	for cageName, reqLevel in pairs(CageRebirthRequirements.ByCageName) do
		if not seen[reqLevel] then
			seen[reqLevel] = true
			table.insert(sortedCages, { Name = cageName, RequiredRebirth = reqLevel })
		end
	end
	table.sort(sortedCages, function(a, b)
		return a.RequiredRebirth < b.RequiredRebirth
	end)
end

local sortedBrainrots = {}
do
	for name, data in pairs(BrainrotConfig) do
		table.insert(sortedBrainrots, {
			Name = name,
			Rarity = data.Rarity or "Common",
			BaseIncome = data.BaseIncome or 0,
			Icon = data.Icon or "",
		})
	end
	table.sort(sortedBrainrots, function(a, b)
		return a.BaseIncome > b.BaseIncome
	end)
end

function Analyzer.GetPlayerRebirths(player)
	if not player then return 0 end
	for _, attrName in ipairs({ "RebirthLevel", "Rebirths", "Rebirth" }) do
		local v = player:GetAttribute(attrName)
		if typeof(v) == "number" then
			return v
		end
	end
	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		for _, attrName in ipairs({ "Rebirths", "RebirthLevel", "Rebirth" }) do
			local v = leaderstats:FindFirstChild(attrName)
			if v and v:IsA("ValueBase") then
				return tonumber(v.Value) or 0
			end
		end
	end
	return 0
end

function Analyzer.GetAllCages()
	return sortedCages
end

function Analyzer.GetUnlockedCages(player)
	local rebirths = Analyzer.GetPlayerRebirths(player)
	local unlocked = {}
	for _, cage in ipairs(sortedCages) do
		if rebirths >= cage.RequiredRebirth then
			table.insert(unlocked, cage)
		end
	end
	return unlocked, rebirths
end

function Analyzer.GetBestCage(player)
	local unlocked = Analyzer.GetUnlockedCages(player)
	if #unlocked == 0 then return nil end
	return unlocked[#unlocked]
end

function Analyzer.GetBestBrainrots(count)
	count = count or 10
	local result = {}
	for i = 1, math.min(count, #sortedBrainrots) do
		table.insert(result, sortedBrainrots[i])
	end
	return result
end

function Analyzer.GetBestBrainrotForCage(cageRequiredRebirth)
	local rarityPool = {}
	if cageRequiredRebirth >= 9 then
		rarityPool = { "Mythic", "Legendary", "Epic", "Rare", "Common" }
	elseif cageRequiredRebirth >= 7 then
		rarityPool = { "Legendary", "Epic", "Rare", "Common" }
	elseif cageRequiredRebirth >= 5 then
		rarityPool = { "Epic", "Rare", "Common" }
	elseif cageRequiredRebirth >= 3 then
		rarityPool = { "Rare", "Common" }
	else
		rarityPool = { "Common" }
	end
	for _, br in ipairs(sortedBrainrots) do
		for _, r in ipairs(rarityPool) do
			if br.Rarity == r then
				return br
			end
		end
	end
	return sortedBrainrots[1]
end

function Analyzer.GetFullReport(player)
	local rebirths = Analyzer.GetPlayerRebirths(player)
	local unlocked, _ = Analyzer.GetUnlockedCages(player)
	local bestCage = Analyzer.GetBestCage(player)
	local cageDetails = {}
	for _, cage in ipairs(sortedCages) do
		local unlocked = rebirths >= cage.RequiredRebirth
		local bestBr = Analyzer.GetBestBrainrotForCage(cage.RequiredRebirth)
		table.insert(cageDetails, {
			CageName = cage.Name,
			RequiredRebirth = cage.RequiredRebirth,
			Unlocked = unlocked,
			BestBrainrot = bestBr,
		})
	end
	return {
		PlayerRebirths = rebirths,
		TotalCages = #sortedCages,
		UnlockedCageCount = #unlocked,
		BestCage = bestCage,
		CageDetails = cageDetails,
		TopBrainrots = Analyzer.GetBestBrainrots(10),
	}
end

local function fmtNumber(n)
	if n >= 1e9 then return string.format("%.1fB", n / 1e9)
	elseif n >= 1e6 then return string.format("%.1fM", n / 1e6)
	elseif n >= 1e3 then return string.format("%.1fK", n / 1e3)
	end
	return tostring(math.floor(n))
end

local function getDisplayCageName(cageKey)
	local cleaned = cageKey:gsub("Base$", ""):gsub("Cage$", ""):gsub("s$", "")
	local words = {}
	for w in cleaned:gmatch("[A-Z][a-z]*") do
		table.insert(words, w)
	end
	return #words > 0 and table.concat(words, " ") or cleaned
end

local function getRebirthForCage(cageIndex)
	local cageKey = CageOrder[cageIndex]
	if CageRebirthRequirements then
		local req = CageRebirthRequirements.ByCageName and CageRebirthRequirements.ByCageName[cageKey]
		if typeof(req) == "number" then return req end
		if CageRebirthRequirements[cageKey] then
			local v = CageRebirthRequirements[cageKey]
			if typeof(v) == "number" then return v end
			if typeof(v) == "table" and v.Rebirths then return v.Rebirths end
		end
	end
	return (cageIndex - 1)
end

local function getBestBrainrotForCage(cageIndex)
	local chances = RarityChances[cageIndex]
	if not chances then return nil, nil, nil end
	local availableRarities = {}
	for rarity, _ in pairs(chances) do
		table.insert(availableRarities, rarity)
	end
	local bestName, bestIncome, bestRarity = nil, 0, nil
	for name, data in pairs(BrainrotConfig) do
		if typeof(data) == "table" and data.Rarity and data.BaseIncome then
			for _, r in ipairs(availableRarities) do
				if data.Rarity == r then
					if data.BaseIncome > bestIncome then
						bestIncome = data.BaseIncome
						bestName = name
						bestRarity = data.Rarity
					end
					break
				end
			end
		end
	end
	return bestName, bestIncome, bestRarity
end

local remotes = ReplicatedStorage:FindFirstChild("Remotes", 10)
local remotesFolder = remotes or ReplicatedStorage:FindFirstChild("Remotes")

local function getRemote(name)
	if not remotesFolder then return nil end
	return remotesFolder:FindFirstChild(name)
end

local pickaxeRemotes = remotesFolder and remotesFolder:FindFirstChild("PickaxeSystem")
local hitWallRemote = pickaxeRemotes and pickaxeRemotes:FindFirstChild("HitWall")
local equipPickaxeRemote = pickaxeRemotes and pickaxeRemotes:FindFirstChild("EquipPickaxe")
local getWallStateRemote = pickaxeRemotes and pickaxeRemotes:FindFirstChild("GetWallState")

-- State variables (moved up for use by guard/money systems and other functions)
local autoFarmStatus = "Idle"
local autoFarmLog = {}
local loopDelay = 2

-- Forward declarations for functions defined later
local findPlayerBase

local function addLog(msg)
	table.insert(autoFarmLog, 1, os.date("%H:%M:%S") .. " - " .. msg)
	if #autoFarmLog > 50 then table.remove(autoFarmLog) end
end

-- Guard creature disabling system
local guardDisabled = false
local guardDisableThread = nil

local function disableGuardCreature(model)
	if not model or not model:IsA("Model") then return end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		pcall(function() humanoid.WalkSpeed = 0 end)
		pcall(function() humanoid.JumpPower = 0 end)
		pcall(function() humanoid.JumpHeight = 0 end)
	end
	local hrp = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChildWhichIsA("BasePart")
	if hrp then
		pcall(function() hrp.Anchored = true end)
	end
	for _, child in model:GetDescendants() do
		if child:IsA("BasePart") then
			pcall(function() child.Anchored = true end)
		end
		if child:IsA("Script") or child:IsA("LocalScript") then
			pcall(function() child.Disabled = true end)
		end
	end
end

local function isGuardModel(model)
	if not model or not model:IsA("Model") then return false end
	local name = string.lower(model.Name)
	return string.find(name, "guard") or string.find(name, "creature") or string.find(name, "monster")
		or string.find(name, "chaser") or string.find(name, "enemy") or string.find(name, "hunter")
		or string.find(name, "beast") or string.find(name, "killer") or string.find(name, "predator")
end

local function findAndDisableGuards()
	-- Scan ZooArea for guard creatures
	local zooArea = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("ZooArea")
	if zooArea then
		for _, descendant in zooArea:GetDescendants() do
			if isGuardModel(descendant) then
				disableGuardCreature(descendant)
			end
		end
	end
	-- Also scan near the player character for any NPC that might chase/push
	local char = Player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp then
		for _, model in ipairs(workspace:GetChildren()) do
			if model:IsA("Model") and model ~= char then
				local hum = model:FindFirstChildOfClass("Humanoid")
				local modelHrp = model:FindFirstChild("HumanoidRootPart")
				if hum and modelHrp and (modelHrp.Position - hrp.Position).Magnitude < 50 then
					if isGuardModel(model) then
						disableGuardCreature(model)
					end
				end
			end
		end
	end
end

-- Cached base reference to avoid repeated lookups
local cachedBase = nil
local function getCachedBase()
	if cachedBase and cachedBase.Parent then return cachedBase end
	cachedBase = findPlayerBase()
	return cachedBase
end

local guardDescendantConn = nil

local function startGuardDisable()
	if guardDisabled then return end
	guardDisabled = true

	-- Hook BrainrotGuardCaught to prevent client-side caught effects
	local guardCaughtRemote = remotesFolder and remotesFolder:FindFirstChild("BrainrotGuardCaught")
	if guardCaughtRemote and guardCaughtRemote:IsA("RemoteEvent") then
		pcall(function()
			guardCaughtRemote.OnClientEvent:Connect(function()
				addLog("Guard catch prevented")
			end)
		end)
	end

	-- Also hook BrainrotStealLost to prevent steal-loss processing
	local stealLostRemote = remotesFolder and remotesFolder:FindFirstChild("BrainrotStealLost")
	if stealLostRemote and stealLostRemote:IsA("RemoteEvent") then
		pcall(function()
			stealLostRemote.OnClientEvent:Connect(function()
				addLog("Steal loss prevented")
			end)
		end)
	end

	-- Use DescendantAdded for real-time guard detection (event-driven, no polling)
	guardDescendantConn = workspace.DescendantAdded:Connect(function(descendant)
		if isGuardModel(descendant) then
			disableGuardCreature(descendant)
		end
	end)

	-- Initial scan only (event-driven via DescendantAdded handles new guards)
	findAndDisableGuards()
	-- Re-scan every 3s (more frequent to catch guards before they can push)
	guardDisableThread = task.spawn(function()
		while guardDisabled do
			findAndDisableGuards()
			task.wait(3)
		end
	end)
	addLog("Guard disable system started")
end

local function stopGuardDisable()
	guardDisabled = false
	if guardDisableThread then
		task.cancel(guardDisableThread)
		guardDisableThread = nil
	end
	if guardDescendantConn then
		guardDescendantConn:Disconnect()
		guardDescendantConn = nil
	end
	addLog("Guard disable system stopped")
end

-- Money notification suppression system
local moneyNotifSuppressed = false
local moneyNotifThread = nil

local function startMoneyNotifSuppression()
	if moneyNotifSuppressed then return end
	moneyNotifSuppressed = true

	-- Hook TextUpdatesBarNotifier to filter money notifications
	local textNotifierModule = ReplicatedStorage:FindFirstChild("Modules") and ReplicatedStorage.Modules:FindFirstChild("TextUpdatesBarNotifier")
	if textNotifierModule then
		pcall(function()
			local mod = require(textNotifierModule)
			if mod and mod.Show and not mod._autoFarmHooked then
				local originalShow = mod.Show
				mod._autoFarmHooked = true
				mod.Show = function(text, tone, duration, options)
					if tone == "Green" and text and (string.find(text, "%$") or string.find(string.lower(text), "money") or string.find(string.lower(text), "cash") or string.find(string.lower(text), "dinheiro") or string.find(text, "%+")) then
						return
					end
					return originalShow(text, tone, duration, options)
				end
			end
			if mod and mod.SetExternalSuppression then
				pcall(function() mod.SetExternalSuppression("AutoFarmMoney", true) end)
			end
		end)
	end

	-- Use DescendantAdded for event-driven detection (no polling workspace)
	local function hideMoneyGui(gui)
		if not gui then return end
		if gui:IsA("BillboardGui") then
			local name = string.lower(gui.Name)
			if string.find(name, "money") or string.find(name, "cash") or string.find(name, "coin") or string.find(name, "floating") or string.find(name, "pop") then
				pcall(function() gui.Enabled = false end)
			end
		end
	end

	-- Initial hide on player base BillboardGuis only (not entire workspace)
	local base = getCachedBase()
	if base then
		for _, d in base:GetDescendants() do
			hideMoneyGui(d)
		end
	end

	-- Use DescendantAdded on player base for new money popups (event-driven only, no polling)
	moneyNotifThread = task.spawn(function()
		local conn
		if base then
			conn = base.DescendantAdded:Connect(function(d)
				hideMoneyGui(d)
			end)
		end
		-- Just sleep until suppression is stopped (no polling needed)
		while moneyNotifSuppressed do
			task.wait(10)
		end
		if conn then conn:Disconnect() end
	end)
	addLog("Money notification suppression started")
end

local function stopMoneyNotifSuppression()
	moneyNotifSuppressed = false
	if moneyNotifThread then
		task.cancel(moneyNotifThread)
		moneyNotifThread = nil
	end
	addLog("Money notification suppression stopped")
end

local function isPickaxeTool(item)
	if not item or not item:IsA("Tool") then return false end
	if item:GetAttribute("IsPickaxe") == true then return true end
	if item:GetAttribute("ToolType") == "Pickaxe" then return true end
	if item:GetAttribute("PickaxeId") then return true end
	local name = string.lower(item.Name)
	if string.find(name, "pickaxe") then return true end
	return false
end

local function getEquippedPickaxeTool()
	local char = Player.Character
	if not char then return nil end
	for _, item in ipairs(char:GetChildren()) do
		if isPickaxeTool(item) then
			return item
		end
	end
	return nil
end

local function getBackpackPickaxe()
	local backpack = Player:FindFirstChild("Backpack")
	if not backpack then return nil end
	for _, item in ipairs(backpack:GetChildren()) do
		if isPickaxeTool(item) then
			return item
		end
	end
	return nil
end

local function simulateKey1()
	-- Simulate pressing key '1' to equip/unequip tool from slot 1
	local keyCode = Enum.KeyCode.One.Value
	local success = false
	-- Try executor's keypress/keyrelease first
	pcall(function()
		if keypress and keyrelease then
			keypress(keyCode)
			task.wait(0.05)
			keyrelease(keyCode)
			success = true
		end
	end)
	-- Fallback: VirtualInputManager
	if not success then
		pcall(function()
			local vim = game:GetService("VirtualInputManager")
			vim:SendKeyEvent(true, Enum.KeyCode.One, false, game)
			task.wait(0.05)
			vim:SendKeyEvent(false, Enum.KeyCode.One, false, game)
			success = true
		end)
	end
	task.wait(0.15)
end

local function equipPickaxe()
	local equipped = getEquippedPickaxeTool()
	if equipped then return equipped end
	-- Simulate pressing '1' to equip the pickaxe (first tool slot)
	simulateKey1()
	return getEquippedPickaxeTool()
end

local function unequipPickaxe()
	local equipped = getEquippedPickaxeTool()
	if not equipped then return true end
	-- Simulate pressing '1' again to unequip
	simulateKey1()
	return getEquippedPickaxeTool() == nil
end

local function getPickaxeId(tool)
	if not tool then return nil end
	local id = tool:GetAttribute("PickaxeId") or tool:GetAttribute("Id")
	if id then return id end
	local modelName = tool:GetAttribute("ModelName") or tool.Name
	if PickaxeConfig and PickaxeConfig.ModelNameToId then
		local mapped = PickaxeConfig.ModelNameToId[string.lower(modelName)]
		if mapped then return mapped end
	end
	return modelName
end

local function getCharacter()
	local char = Player.Character
	if not char or not char.Parent then
		char = Player.CharacterAdded:Wait()
	end
	return char, char:WaitForChild("HumanoidRootPart", 5), char:WaitForChild("Humanoid", 5)
end

local function teleportTo(pos)
	local _, hrp = getCharacter()
	if hrp then hrp.CFrame = CFrame.new(pos + Vector3.new(0, 3, 0)) end
end

local function findCageWall(cageName)
	if not cageName then return nil end
	local zooArea = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("ZooArea")
	if not zooArea then return nil end
	local zooCages = zooArea:FindFirstChild("ZooCages")
	if not zooCages then return nil end
	local cage = zooCages:FindFirstChild(cageName)
	if not cage then return nil end
	return cage:FindFirstChild("BreakableCageWall")
end

local function isWallBroken(cageName)
	local wall = findCageWall(cageName)
	if not wall then return true end
	if wall:GetAttribute("Broken") == true then return true end
	if wall:GetAttribute("LocalBroken") == true then return true end
	local health = wall:GetAttribute("Health")
	if health and health <= 0 then return true end
	-- Also try GetWallState remote for authoritative check
	if getWallStateRemote and getWallStateRemote:IsA("RemoteFunction") then
		local ok, result = pcall(function()
			return getWallStateRemote:InvokeServer(wall)
		end)
		if ok and typeof(result) == "table" and result.Broken == true then
			return true
		end
	end
	return false
end

local function breakCageWall(cageName)
	if isWallBroken(cageName) then return true end
	local wall = findCageWall(cageName)
	if not wall then return true end
	local barrier = wall:FindFirstChild("Barrier")
	if not barrier then return true end

	local pickaxe = equipPickaxe()
	if not pickaxe then
		autoFarmStatus = "No pickaxe found!"
		addLog("Cannot break wall: no pickaxe in backpack")
		return false
	end

	local pickaxeId = getPickaxeId(pickaxe)
	local barrierPos = barrier.Position
	local maxHealth = wall:GetAttribute("MaxHealth") or wall:GetAttribute("Health") or 100
	local attempts = 0
	local maxAttempts = 200

	teleportTo(barrierPos)
	task.wait(0.1)

	while not isWallBroken(cageName) and attempts < maxAttempts do
		attempts = attempts + 1
		local char, hrp = getCharacter()
		if not hrp then break end
		local origin = hrp.Position
		local direction = (barrierPos - origin).Unit
		local metadata = { RequestId = tick() }
		pcall(function()
			hitWallRemote:FireServer(pickaxeId, origin, direction, barrier, barrierPos, metadata)
		end)
		local currentHealth = wall:GetAttribute("Health") or 0
		autoFarmStatus = "Breaking wall: " .. cageName .. " (HP: " .. fmtNumber(currentHealth) .. "/" .. fmtNumber(maxHealth) .. ")"
		task.wait(0.15)
	end

	if isWallBroken(cageName) then
		autoFarmStatus = "Wall broken: " .. cageName
		addLog("Broke cage wall: " .. cageName)
		return true
	else
		autoFarmStatus = "Failed to break wall: " .. cageName
		addLog("Failed to break cage wall: " .. cageName)
		return false
	end
end

local function getMyOwnedBrainrotData()
	local ownedData = {}
	local inventory = Player:FindFirstChild("Brainrots") or Player:FindFirstChild("Inventory") or Player:FindFirstChild("OwnedBrainrots")
	if inventory then
		for _, item in inventory:GetChildren() do
			local name = item.Name or item:GetAttribute("BrainrotName") or (item:IsA("StringValue") and item.Value) or nil
			if name and BrainrotConfig[name] then
				local data = BrainrotConfig[name]
				local rarity = data.Rarity or "Common"
				local income = data.BaseIncome or 0
				table.insert(ownedData, {
					Name = name,
					Rarity = rarity,
					Income = income,
					Item = item
				})
			end
		end
	end
	return ownedData
end

local function getMyWorstBrainrot(allowedRarities)
	local owned = getMyOwnedBrainrotData()
	if #owned == 0 then return nil, nil, 0 end

	local filtered = {}
	for _, data in ipairs(owned) do
		if allowedRarities[data.Rarity] then
			table.insert(filtered, data)
		end
	end

	if #filtered == 0 then return nil, nil, 0 end

	local worst, worstIncome = nil, math.huge
	for _, data in ipairs(filtered) do
		if data.Income < worstIncome then
			worstIncome = data.Income
			worst = data
		end
	end
	return worst and worst.Item, worst and worst.Name, worstIncome
end

local function playerHasBrainrot(name)
	local owned = getMyOwnedBrainrotData()
	for _, data in ipairs(owned) do
		if data.Name == name then
			return true
		end
	end
	return false
end

local function isCageUnlocked(cageName)
	if not cageName then return true end
	local reqRebirth = nil
	if CageRebirthRequirements and CageRebirthRequirements.GetRequiredRebirth then
		local ok, result = pcall(CageRebirthRequirements.GetRequiredRebirth, cageName)
		if ok and typeof(result) == "number" then reqRebirth = result end
	end
	if not reqRebirth and CageRebirthRequirements and CageRebirthRequirements.ByCageName then
		reqRebirth = CageRebirthRequirements.ByCageName[cageName] or 0
	end
	if not reqRebirth then reqRebirth = 0 end
	local myRebirths = Analyzer.GetPlayerRebirths(Player)
	return myRebirths >= reqRebirth
end

local function findCageStealPrompt(cageName, padName)
	if not cageName then return nil, nil end
	local zooArea = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("ZooArea")
	if not zooArea then return nil, nil end
	local zooCages = zooArea:FindFirstChild("ZooCages")
	if not zooCages then return nil, nil end
	local cage = zooCages:FindFirstChild(cageName)
	if not cage then return nil, nil end
	local spawnPads = cage:FindFirstChild("SpawnPads")
	if not spawnPads then return nil, nil end

	-- If we know the specific pad, try that first
	if padName then
		local platform = spawnPads:FindFirstChild(padName)
		if platform then
			local platformSpawnTop = platform:FindFirstChild("PlatformSpawnTop")
			if platformSpawnTop then
				local stealPrompt = platformSpawnTop:FindFirstChild("StealPrompt")
				if stealPrompt and stealPrompt:IsA("ProximityPrompt") then
					return stealPrompt, platformSpawnTop
				end
			end
		end
	end

	-- Otherwise search all platforms for an enabled StealPrompt
	local fallbackPrompt, fallbackPlatform = nil, nil
	for _, platform in ipairs(spawnPads:GetChildren()) do
		local platformSpawnTop = platform:FindFirstChild("PlatformSpawnTop")
		if platformSpawnTop then
			local stealPrompt = platformSpawnTop:FindFirstChild("StealPrompt")
			if stealPrompt and stealPrompt:IsA("ProximityPrompt") then
				if stealPrompt.Enabled then
					return stealPrompt, platformSpawnTop
				end
				if not fallbackPrompt then
					fallbackPrompt = stealPrompt
					fallbackPlatform = platformSpawnTop
				end
			end
		end
	end
	return fallbackPrompt, fallbackPlatform
end

local function findCageBrainrot(allowedRarities)
	local bestModel, bestName, bestIncome = nil, nil, -1
	local cageFolder = workspace:FindFirstChild("LocalCageBrainrots")
	if not cageFolder then return nil, nil, 0 end

	for _, model in cageFolder:GetChildren() do
		if model:IsA("Model") or model:IsA("BasePart") then
			local bName = model:GetAttribute("BrainrotName") or model.Name
			if bName and BrainrotConfig[bName] then
				local rarity = BrainrotConfig[bName].Rarity or "Common"
				local modelRarity = model:GetAttribute("Rarity")
				local checkRarity = modelRarity or rarity
				if allowedRarities[checkRarity] then
					local cageName = model:GetAttribute("CageName")
					local isLuckyBlock = model:GetAttribute("IsCageLuckyBlock")
					if isLuckyBlock then
						-- Skip lucky blocks
					elseif not isCageUnlocked(cageName) then
						-- Skip brainrots from locked cages
					elseif not playerHasBrainrot(bName) then
						local inc = model:GetAttribute("BaseIncome") or BrainrotConfig[bName].BaseIncome or 0
						local mutationMult = model:GetAttribute("MutationMultiplier") or 1
						local actualInc = inc * mutationMult
						if actualInc > bestIncome then
							bestIncome = actualInc
							bestName = bName
							bestModel = model
						end
					end
				end
			end
		end
	end
	return bestModel, bestName, bestIncome
end

local function interactWithPart(part)
	if not part then return end
	local prompt = part:FindFirstChildWhichIsA("ProximityPrompt")
	if prompt then fireproximityprompt(prompt, 0); return end
	local click = part:FindFirstChildWhichIsA("ClickDetector")
	if click then fireclickdetector(click); return end
	local remote = getRemote("GrabBrainrot") or getRemote("Grab")
	if remote then pcall(function() remote:FireServer(part) end) end
end

local function placeOnBase(brainrotName)
	local remote = getRemote("PlaceBrainrot") or getRemote("Place")
	if remote then pcall(function() remote:FireServer(brainrotName) end) end
end

local function swapBrainrot(oldName, newName)
	local remote = getRemote("SwapBrainrot") or getRemote("Swap")
	if remote then pcall(function() remote:FireServer(oldName, newName) end) end
end

function findPlayerBase()
	local baseFolder = workspace:FindFirstChild("Bases")
		or workspace:FindFirstChild("PlayerBases")
		or (workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("SafeZone") and workspace.Map.SafeZone:FindFirstChild("PlayerBases"))
	if baseFolder then
		for _, child in baseFolder:GetChildren() do
			if child.Name == Player.Name or child.Name == (Player.UserId .. "") then return child end
			local ownerAttr = child:GetAttribute("OwnerUserId") or child:GetAttribute("OwnerId")
			if ownerAttr and tostring(ownerAttr) == tostring(Player.UserId) then return child end
			local ownerVal = child:FindFirstChild("OwnerUserId", true)
			if ownerVal and ownerVal:IsA("IntValue") and ownerVal.Value == Player.UserId then return child end
		end
	end
	return nil
end

local function waitForBaseTeleport()
	local base = getCachedBase()
	if base then
		local spawnPart = base:FindFirstChild("SpawnCenter") or base:FindFirstChild("CenterSpawn") or base:FindFirstChildWhichIsA("BasePart")
		if spawnPart then teleportTo(spawnPart.Position); return true end
	end
	return false
end

local function getBasePosition()
	local base = getCachedBase()
	if base then
		local spawnPart = base:FindFirstChild("SpawnCenter") or base:FindFirstChild("CenterSpawn") or base:FindFirstChildWhichIsA("BasePart")
		if spawnPart then return spawnPart.Position end
	end
	return nil
end

local function hasEquippedBrainrotTool()
	local char = Player.Character
	if not char then return false end
	for _, item in ipairs(char:GetChildren()) do
		if item:IsA("Tool") then
			local name = string.lower(item.Name)
			if string.find(name, "brainrot") or item:GetAttribute("BrainrotName") or item:GetAttribute("IsBrainrot") then
				return true
			end
		end
	end
	return false
end

local function teleportToBaseWithProtection()
	local basePos = getBasePosition()
	if not basePos then return false end

	local _, hrp = getCharacter()
	if not hrp then return false end

	-- Teleport to base
	hrp.CFrame = CFrame.new(basePos + Vector3.new(0, 3, 0))

	-- Anchor briefly to prevent guard creature push forces
	hrp.Anchored = true
	task.wait(0.15)
	hrp.Anchored = false
	hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)

	return true
end

local function forceTeleportToBaseWithRetries(maxRetries)
	maxRetries = maxRetries or 3
	for i = 1, maxRetries do
		local success = teleportToBaseWithProtection()
		if success then
			task.wait(0.1)
			-- Verify we're actually at base
			local char = Player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			local basePos = getBasePosition()
			if hrp and basePos and (hrp.Position - basePos).Magnitude < 20 then
				return true
			end
		end
	end
	return false
end

local function findCollectPad()
	local base = getCachedBase()
	if not base then return nil end
	local collectPad = base:FindFirstChild("CollectPad", true)
	if collectPad and collectPad:IsA("BasePart") then return collectPad end
	return nil
end

local cachedPads = nil
local function findAllCollectPads()
	if cachedPads then
		-- Verify pads are still valid
		local valid = true
		for _, pad in ipairs(cachedPads) do
			if not pad.Parent then valid = false break end
		end
		if valid then return cachedPads end
	end
	local base = getCachedBase()
	if not base then return {} end
	cachedPads = {}
	for _, d in ipairs(base:GetDescendants()) do
		if d.Name == "CollectPad" and d:IsA("BasePart") then
			table.insert(cachedPads, d)
		end
	end
	return cachedPads
end

local autoCollectMoneyEnabled = false
local autoCollectThread = nil

local function autoCollectMoneyLoop()
	while autoCollectMoneyEnabled do
		local char = Player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp then
			local pads = findAllCollectPads()
			if #pads > 0 then
				local hasFireTouch = false
				pcall(function()
					if firetouchinterest then hasFireTouch = true end
				end)

				if hasFireTouch then
					-- Use firetouchinterest to collect from all pads without teleporting
					for _, pad in ipairs(pads) do
						pcall(function()
							firetouchinterest(pad, hrp, 0)
							firetouchinterest(pad, hrp, 1)
						end)
					end
				else
					-- Fallback: teleport to each pad
					for _, pad in ipairs(pads) do
						teleportTo(pad.Position)
						task.wait(0.05)
					end
				end
			else
				cachedPads = nil -- Force refresh on next cycle
			end
		end
		task.wait(1)
	end
end

local autoFarmEnabled = false
local autoFarmThread = nil
local placeBestThread = nil
local antiAfkThread = nil
local SPEEDS = { Normal = 2, Fast = 1, Turbo = 0.5 }
local speedOrder = { "Normal", "Fast", "Turbo" }
local currentSpeedIdx = 1
loopDelay = SPEEDS.Normal

local ALLOWED_RARITIES = {}
for _, rarity in ipairs(RARITY_ORDER) do
	ALLOWED_RARITIES[rarity] = true
end

local function farmCycle()
	local cageModel, cageName, cageIncome = findCageBrainrot(ALLOWED_RARITIES)
	if not cageModel then
		return false
	end

	local _, _, myWorstIncome = getMyWorstBrainrot(ALLOWED_RARITIES)
	autoFarmStatus = "Found: " .. (cageName or "?") .. " ($" .. fmtNumber(cageIncome) .. "/s)"
	addLog("Cage best: " .. (cageName or "?") .. " $" .. fmtNumber(cageIncome) .. "/s")

	if cageIncome <= myWorstIncome and myWorstIncome > 0 then
		autoFarmStatus = "Cage ($" .. fmtNumber(cageIncome) .. ") <= Base worst ($" .. fmtNumber(myWorstIncome) .. ")"
		addLog("Cage not better than base worst")
		return false
	end

	-- Invalidate pad cache when we teleport to cage (base may change context)
	cachedPads = nil

	local cageNameAttr = cageModel:GetAttribute("CageName")
	if cageNameAttr and not isWallBroken(cageNameAttr) then
		autoFarmStatus = "Breaking cage door: " .. cageNameAttr
		addLog("Breaking cage door: " .. cageNameAttr)
		local broken = breakCageWall(cageNameAttr)
		if not broken then
			return false
		end
		-- Unequip pickaxe after breaking wall (press '1' to unequip)
		unequipPickaxe()
		task.wait(0.1)
	end

	-- Find the StealPrompt in the cage structure
	local padName = cageModel:GetAttribute("PadName") or cageModel:GetAttribute("PlatformName")
	local stealPrompt, platformSpawnTop = findCageStealPrompt(cageNameAttr, padName)

	if stealPrompt and platformSpawnTop then
		-- Unequip pickaxe before collecting brainrot (press '1' to unequip)
		unequipPickaxe()
		-- Force disable guards right before steal to prevent push
		findAndDisableGuards()
		task.wait(0.1)
		-- Teleport to the platform with the StealPrompt
		teleportTo(platformSpawnTop.Position)
		task.wait(0.2)

		-- Get the hold duration from the prompt, fallback to 2 seconds
		local holdDuration = stealPrompt.HoldDuration
		if not holdDuration or holdDuration <= 0 then
			holdDuration = 2
		end

		autoFarmStatus = "Stealing: " .. (cageName or "?")
		addLog("Stealing brainrot: " .. (cageName or "?"))

		-- Enable the StealPrompt before firing (it's disabled by default, only enabled by StealPromptGateClient when close)
		stealPrompt.Enabled = true
		-- Fire the proximity prompt to initiate the steal
		fireproximityprompt(stealPrompt, holdDuration)
		-- Wait for the steal to register on mobile
		task.wait(0.3)
		-- Immediately teleport to base with protection (anchor to prevent guard push)
		forceTeleportToBaseWithRetries(3)
	else
		-- Fallback: use the old method with direct model interaction
		local cageSpawn = nil
		if cageModel:IsA("Model") then
			cageSpawn = cageModel:FindFirstChild("SpawnCenter") or cageModel:FindFirstChildWhichIsA("BasePart")
		end
		if cageSpawn then
			teleportTo(cageSpawn.Position)
			task.wait(0.1)
			interactWithPart(cageModel)
			task.wait(0.1)
		end
		autoFarmStatus = "Collected (fallback): " .. (cageName or "?")
		addLog("Collected brainrot (fallback method): " .. (cageName or "?"))
	end

	-- Immediately teleport to base after steal attempt with protection (anchor prevents guard push)
	forceTeleportToBaseWithRetries(3)
	-- Invalidate pad cache after teleporting to base
	cachedPads = nil
	task.wait(0.1)

	-- Automatically place best brainrots on base using PlaceBestBrainrots remote
	autoFarmStatus = "Placing best brainrots on base..."
	addLog("Placing best brainrots")
	local placeBestRemote = remotesFolder and remotesFolder:FindFirstChild("PlaceBestBrainrots")
	if placeBestRemote and placeBestRemote:IsA("RemoteFunction") then
		pcall(function()
			placeBestRemote:InvokeServer()
		end)
		addLog("PlaceBestBrainrots called")
	else
		-- Fallback to manual swap/place
		local worstItem, worstName, _ = getMyWorstBrainrot(ALLOWED_RARITIES)
		if worstName and cageName and worstName ~= cageName then
			autoFarmStatus = "Swapping: " .. (worstName or "?") .. " -> " .. (cageName or "?")
			addLog("Swap: " .. (worstName or "?") .. " -> " .. (cageName or "?"))
			swapBrainrot(worstName, cageName)
		elseif not worstName and cageName then
			autoFarmStatus = "Placing: " .. (cageName or "?")
			addLog("Placing: " .. (cageName or "?"))
			placeOnBase(cageName)
		end
	end
	task.wait(0.1)

	autoFarmStatus = "Cycle complete"
	addLog("Cycle complete")
	return true
end

local function autoFarmLoop()
	while autoFarmEnabled do
		local ok, result = pcall(farmCycle)
		if not ok then
			autoFarmStatus = "Error: " .. tostring(result)
			addLog("Error: " .. tostring(result))
		end
		task.wait(loopDelay)
	end
end

local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()
if not Rayfield then
	warn("CageAnalyzer: Failed to load Rayfield")
	return
end

local currentLocale = "en"
local translations = {
	en = {
		WindowName = "Cage Analyzer Pro",
		WindowSubtitle = "Brainrot Farming Co.",
		TabAnalyzer = "Analyzer",
		TabAutoFarm = "Auto Farm",
		TabTopBrainrots = "Top Brainrots",
		TabSettings = "Settings",
		SectionPlayerInfo = "Player Information",
		SectionStats = "Stats Overview",
		SectionCages = "Cages and Best Brainrots",
		ButtonRefresh = "Refresh Analysis",
		NotifAnalysisRefreshed = "Analysis refreshed!",
		LabelRebirths = "Rebirths",
		LabelBestCage = "Best Cage",
		LabelTotalCages = "Total Cages",
		LabelUnlocked = "Unlocked",
		LabelNone = "None",
		LabelLoading = "Loading...",
		LabelNoBrainrot = "No brainrot available",
		SectionRarityFilter = "Rarity Filter",
		RarityFilterDesc = "Select which rarities the auto farm should collect.",
		DropdownRarities = "Allowed Rarities",
		NotifRarityUpdated = "Rarity Filter Updated",
		NotifRarityCount = "Now farming ",
		NotifRarityCountEnd = " rarities",
		SectionAutoControls = "Auto Farm Controls",
		AutoControlsDesc = "Start/stop automatic brainrot farming.",
		ToggleAutoFarm = "Auto Farm Best Brainrot",
		ToggleAutoCollectMoney = "Auto Collect Money",
		NotifAutoCollectStarted = "Auto collect money started!",
		NotifAutoCollectStopped = "Auto collect money stopped.",
		NotifNoRarity = "Please select at least one rarity to farm!",
		NotifAutoStarted = "Auto farm started! Finding best brainrots...",
		NotifAutoStopped = "Auto farm stopped.",
		DropdownSpeed = "Farm Speed",
		NotifSpeedChanged = "Speed Changed",
		NotifSpeedSet = "Farm speed set to ",
		SectionStatus = "Status",
		StatusIdle = "Status: Idle",
		SectionLog = "Farm Log",
		LogEmpty = "No logs yet.",
		ButtonRefreshLog = "Refresh Log",
		SectionTopBrainrots = "Highest Income Brainrots",
		TopDesc = "Top 20 brainrots by income.",
		ParagraphRankings = "Brainrot Rankings",
		ButtonRefreshTop = "Refresh Top Brainrots",
		NotifListRefreshed = "List refreshed!",
		SectionConfig = "Configuration",
		ConfigDesc = "Settings and information.",
		KeybindToggle = "Toggle Cage Analyzer",
		NotifKeybind = "Cage Analyzer toggle key: ",
		SectionInfo = "Information",
		InfoText = "Cage Analyzer Pro v2.0\nAuto farms best brainrots from cage\nAnalyzes all cages and rarities\n\nMade with by Brainrot Farming Co.",
		LanguageLabel = "Language",
		LanguageEnglish = "English",
		LanguagePortuguese = "Portugues",
		NotifLanguageChanged = "Language changed to ",
	},
	pt = {
		WindowName = "Cage Analyzer Pro",
		WindowSubtitle = "Brainrot Farming Co.",
		TabAnalyzer = "Analisador",
		TabAutoFarm = "Auto Farm",
		TabTopBrainrots = "Top Brainrots",
		TabSettings = "Configuracoes",
		SectionPlayerInfo = "Informacoes do Jogador",
		SectionStats = "Visao Geral das Estatisticas",
		SectionCages = "Gaiolas e Melhores Brainrots",
		ButtonRefresh = "Atualizar Analise",
		NotifAnalysisRefreshed = "Analise atualizada!",
		LabelRebirths = "Renascimentos",
		LabelBestCage = "Melhor Gaiola",
		LabelTotalCages = "Total de Gaiolas",
		LabelUnlocked = "Desbloqueadas",
		LabelNone = "Nenhuma",
		LabelLoading = "Carregando...",
		LabelNoBrainrot = "Nenhum brainrot disponivel",
		SectionRarityFilter = "Filtro de Raridades",
		RarityFilterDesc = "Selecione quais raridades o auto farm deve coletar.",
		DropdownRarities = "Raridades Permitidas",
		NotifRarityUpdated = "Filtro de Raridades Atualizado",
		NotifRarityCount = "Coletando ",
		NotifRarityCountEnd = " raridades",
		SectionAutoControls = "Controles do Auto Farm",
		AutoControlsDesc = "Iniciar/parar a coleta automatica de brainrots.",
		ToggleAutoFarm = "Coletar Melhor Brainrot",
		ToggleAutoCollectMoney = "Coletar Dinheiro Automatico",
		NotifAutoCollectStarted = "Coleta de dinheiro automatica iniciada!",
		NotifAutoCollectStopped = "Coleta de dinheiro automatica parada.",
		NotifNoRarity = "Por favor selecione pelo menos uma raridade para coletar!",
		NotifAutoStarted = "Auto farm iniciado! Procurando melhores brainrots...",
		NotifAutoStopped = "Auto farm parado.",
		DropdownSpeed = "Velocidade da Coleta",
		NotifSpeedChanged = "Velocidade Alterada",
		NotifSpeedSet = "Velocidade definida para ",
		SectionStatus = "Status",
		StatusIdle = "Status: Ocioso",
		SectionLog = "Registro da Coleta",
		LogEmpty = "Nenhum registro ainda.",
		ButtonRefreshLog = "Atualizar Registro",
		SectionTopBrainrots = "Brainrots com Maior Renda",
		TopDesc = "Top 20 brainrots por renda.",
		ParagraphRankings = "Ranking de Brainrots",
		ButtonRefreshTop = "Atualizar Top Brainrots",
		NotifListRefreshed = "Lista atualizada!",
		SectionConfig = "Configuracao",
		ConfigDesc = "Configuracoes e informacoes.",
		KeybindToggle = "Alternar Cage Analyzer",
		NotifKeybind = "Tecla para alternar Cage Analyzer: ",
		SectionInfo = "Informacoes",
		InfoText = "Cage Analyzer Pro v2.0\nColeta automaticamente os melhores brainrots da gaiola\nAnalisa todas as gaiolas e raridades\n\nFeito com por Brainrot Farming Co.",
		LanguageLabel = "Idioma",
		LanguageEnglish = "English",
		LanguagePortuguese = "Portugues",
		NotifLanguageChanged = "Idioma alterado para ",
	}
}

local function t(key)
	local localeTable = translations[currentLocale] or translations.en
	return localeTable[key] or key
end

-- Icon IDs for Rayfield (using standard Roblox image IDs)
local ICONS = {
	Analyzer = 4483362458,
	AutoFarm = 4483362458,
	Top = 4483362458,
	Settings = 4483362458,
	Refresh = 4483362458,
	Play = 4483362458,
	Square = 4483362458,
	Filter = 4483362458,
	Gauge = 4483362458,
	Trophy = 4483362458,
	Key = 4483362458,
	Alert = 4483362458,
	Check = 4483362458,
}

local Window = Rayfield:CreateWindow({
	Name = t("WindowName"),
	LoadingTitle = t("WindowName"),
	LoadingSubtitle = t("WindowSubtitle"),
	ConfigurationSaving = {
		Enabled = true,
		FolderName = "CageAnalyzerConfig",
		FileName = "Settings"
	},
	Discord = {
		Enabled = false,
	},
	KeySystem = false,
})

-- Settings Tab (create first for language dropdown)
local SettingsTab = Window:CreateTab(t("TabSettings"), ICONS.Settings)

SettingsTab:CreateSection(t("SectionConfig"))

local langDropdown = SettingsTab:CreateDropdown({
	Name = t("LanguageLabel"),
	Options = { t("LanguageEnglish"), t("LanguagePortuguese") },
	CurrentOption = { t("LanguageEnglish") },
	Flag = "Language",
	Callback = function(Options)
		local lang = Options[1]
		if lang == t("LanguageEnglish") then
			currentLocale = "en"
		elseif lang == t("LanguagePortuguese") then
			currentLocale = "pt"
		end

		Rayfield:Notify({
			Title = t("TabSettings"),
			Content = t("NotifLanguageChanged") .. lang,
			Duration = 2,
			Image = ICONS.Check,
		})

		Window.Name = t("WindowName")
	end,
})

SettingsTab:CreateDivider()

-- Analyzer Tab
local AnalyzerTab = Window:CreateTab(t("TabAnalyzer"), ICONS.Analyzer)

AnalyzerTab:CreateSection(t("SectionPlayerInfo"))

local infoParagraph = AnalyzerTab:CreateParagraph({
	Title = t("SectionPlayerInfo"),
	Content = t("LabelLoading"),
})

AnalyzerTab:CreateSection(t("SectionStats"))

local statsParagraph = AnalyzerTab:CreateParagraph({
	Title = t("SectionStats"),
	Content = t("LabelLoading"),
})

local function updateAnalyzerInfo()
	local report = Analyzer.GetFullReport(Player)
	local bestCage = report.BestCage and report.BestCage.Name or t("LabelNone")

	infoParagraph:Set({
		Title = t("SectionPlayerInfo"),
		Content = string.format(
			"%s: %d\n%s: %s\n%s: %d\n%s: %d/%d",
			t("LabelRebirths"),
			report.PlayerRebirths,
			t("LabelBestCage"),
			bestCage,
			t("LabelTotalCages"),
			report.TotalCages,
			t("LabelUnlocked"),
			report.UnlockedCageCount,
			report.TotalCages
		)
	})
end

updateAnalyzerInfo()

AnalyzerTab:CreateSection(t("SectionCages"))

local cagesParagraph = AnalyzerTab:CreateParagraph({
	Title = t("SectionCages"),
	Content = t("LabelLoading"),
})

local function updateCagesList()
	local rebirths = Analyzer.GetPlayerRebirths(Player)
	local lines = {}

	for i, cageKey in ipairs(CageOrder) do
		local req = getRebirthForCage(i)
		local unlocked = rebirths >= req
		local status = unlocked and "[UNLOCKED]" or "[LOCKED]"
		local cageDisplay = getDisplayCageName(cageKey)

		if unlocked then
			local bName, bIncome, bRarity = getBestBrainrotForCage(i)
			local incomeStr = bName and string.format(" -> %s ($%s/s)", bName, fmtNumber(bIncome)) or " -> " .. t("LabelNoBrainrot")
			table.insert(lines, string.format("%s %s (RB: %d)%s", status, cageDisplay, req, incomeStr))
		else
			table.insert(lines, string.format("%s %s (Requires: %d RB)", status, cageDisplay, req))
		end
	end

	cagesParagraph:Set({
		Title = t("SectionCages"),
		Content = table.concat(lines, "\n")
	})
end

updateCagesList()

AnalyzerTab:CreateButton({
	Name = t("ButtonRefresh"),
	Callback = function()
		updateAnalyzerInfo()
		updateCagesList()
		Rayfield:Notify({
			Title = t("TabAnalyzer"),
			Content = t("NotifAnalysisRefreshed"),
			Duration = 2,
			Image = ICONS.Refresh,
		})
	end,
})

-- Auto Farm Tab
local AutoFarmTab = Window:CreateTab(t("TabAutoFarm"), ICONS.AutoFarm)

AutoFarmTab:CreateSection(t("SectionRarityFilter"))

AutoFarmTab:CreateParagraph({
	Title = t("SectionRarityFilter"),
	Content = t("RarityFilterDesc"),
})

local rarityOptions = {}
for _, rarity in ipairs(RARITY_ORDER) do
	table.insert(rarityOptions, rarity)
end

AutoFarmTab:CreateDropdown({
	Name = t("DropdownRarities"),
	Options = rarityOptions,
	CurrentOption = rarityOptions,
	MultipleOptions = true,
	Flag = "AllowedRarities",
	Callback = function(Options)
		for rarity, _ in pairs(ALLOWED_RARITIES) do
			ALLOWED_RARITIES[rarity] = false
		end

		for _, rarity in ipairs(Options) do
			ALLOWED_RARITIES[rarity] = true
		end

		local count = 0
		for _, v in pairs(ALLOWED_RARITIES) do
			if v then count = count + 1 end
		end

		Rayfield:Notify({
			Title = t("NotifRarityUpdated"),
			Content = t("NotifRarityCount") .. count .. t("NotifRarityCountEnd"),
			Duration = 2,
			Image = ICONS.Filter,
		})
	end,
})

AutoFarmTab:CreateDivider()

AutoFarmTab:CreateSection(t("SectionAutoControls"))

AutoFarmTab:CreateParagraph({
	Title = t("SectionAutoControls"),
	Content = t("AutoControlsDesc"),
})

local autoToggle = AutoFarmTab:CreateToggle({
	Name = t("ToggleAutoFarm"),
	CurrentValue = false,
	Flag = "AutoFarmToggle",
	Callback = function(Value)
		autoFarmEnabled = Value
		if autoFarmEnabled then
			local hasAllowed = false
			for _, v in pairs(ALLOWED_RARITIES) do
				if v then hasAllowed = true; break end
			end

			if not hasAllowed then
				Rayfield:Notify({
					Title = t("TabAutoFarm"),
					Content = t("NotifNoRarity"),
					Duration = 3,
					Image = ICONS.Alert,
				})
				autoFarmEnabled = false
				autoToggle:Set(false)
				return
			end

			autoFarmThread = task.spawn(autoFarmLoop)
			startGuardDisable()
			-- Start PlaceBestBrainrots loop (every 1 second)
			placeBestThread = task.spawn(function()
				local placeBestRemote = remotesFolder and remotesFolder:FindFirstChild("PlaceBestBrainrots")
				while autoFarmEnabled do
					if placeBestRemote and placeBestRemote:IsA("RemoteFunction") then
						pcall(function() placeBestRemote:InvokeServer() end)
					end
					task.wait(1)
				end
			end)
			-- Start Anti-AFK system
			antiAfkThread = task.spawn(function()
				local vu = game:GetService("VirtualUser")
				while autoFarmEnabled do
					pcall(function()
						vu:CaptureController()
						vu:ClickButton2(Vector2.new())
					end)
					task.wait(30)
				end
			end)
			Rayfield:Notify({
				Title = t("TabAutoFarm"),
				Content = t("NotifAutoStarted"),
				Duration = 3,
				Image = ICONS.Play,
			})
		else
			if autoFarmThread then
				task.cancel(autoFarmThread)
				autoFarmThread = nil
			end
			if placeBestThread then
				task.cancel(placeBestThread)
				placeBestThread = nil
			end
			if antiAfkThread then
				task.cancel(antiAfkThread)
				antiAfkThread = nil
			end
			stopGuardDisable()
			stopMoneyNotifSuppression()
			Rayfield:Notify({
				Title = t("TabAutoFarm"),
				Content = t("NotifAutoStopped"),
				Duration = 2,
				Image = ICONS.Square,
			})
		end
	end,
})

AutoFarmTab:CreateDropdown({
	Name = t("DropdownSpeed"),
	Options = { "Normal", "Fast", "Turbo" },
	CurrentOption = { "Normal" },
	Flag = "FarmSpeed",
	Callback = function(Option)
		local speedName = Option[1]
		currentSpeedIdx = table.find(speedOrder, speedName) or 1
		loopDelay = SPEEDS[speedName]
		Rayfield:Notify({
			Title = t("NotifSpeedChanged"),
			Content = t("NotifSpeedSet") .. speedName .. " (" .. loopDelay .. "s delay)",
			Duration = 2,
			Image = ICONS.Gauge,
		})
	end,
})

AutoFarmTab:CreateDivider()

AutoFarmTab:CreateSection(t("SectionAutoControls"))

local autoCollectToggle = AutoFarmTab:CreateToggle({
	Name = t("ToggleAutoCollectMoney"),
	CurrentValue = false,
	Flag = "AutoCollectMoneyToggle",
	Callback = function(Value)
		autoCollectMoneyEnabled = Value
		if autoCollectMoneyEnabled then
			startMoneyNotifSuppression()
			autoCollectThread = task.spawn(autoCollectMoneyLoop)
			Rayfield:Notify({
				Title = t("TabAutoFarm"),
				Content = t("NotifAutoCollectStarted"),
				Duration = 3,
				Image = ICONS.Play,
			})
		else
			if autoCollectThread then
				task.cancel(autoCollectThread)
				autoCollectThread = nil
			end
			stopMoneyNotifSuppression()
			Rayfield:Notify({
				Title = t("TabAutoFarm"),
				Content = t("NotifAutoCollectStopped"),
				Duration = 2,
				Image = ICONS.Square,
			})
		end
	end,
})

AutoFarmTab:CreateDivider()

AutoFarmTab:CreateSection(t("SectionStatus"))

local statusLabel = AutoFarmTab:CreateLabel(t("StatusIdle"))

AutoFarmTab:CreateDivider()

AutoFarmTab:CreateSection(t("SectionLog"))

local logParagraph = AutoFarmTab:CreateParagraph({
	Title = t("SectionLog"),
	Content = t("LogEmpty"),
})

local function updateLog()
	local logContent = #autoFarmLog > 0 and table.concat(autoFarmLog, "\n") or t("LogEmpty")
	logParagraph:Set({
		Title = t("SectionLog"),
		Content = logContent
	})

	local statusText = "Status: " .. autoFarmStatus
	statusLabel:Set(statusText)
end

AutoFarmTab:CreateButton({
	Name = t("ButtonRefreshLog"),
	Callback = function()
		updateLog()
	end,
})

-- Top Brainrots Tab
local TopTab = Window:CreateTab(t("TabTopBrainrots"), ICONS.Top)

TopTab:CreateSection(t("SectionTopBrainrots"))

TopTab:CreateParagraph({
	Title = t("SectionTopBrainrots"),
	Content = t("TopDesc"),
})

local topParagraph = TopTab:CreateParagraph({
	Title = t("ParagraphRankings"),
	Content = t("LabelLoading"),
})

local function updateTopBrainrots()
	local topList = Analyzer.GetBestBrainrots(20)
	local lines = {}

	for i, br in ipairs(topList) do
		local medal = i == 1 and "[1st]" or i == 2 and "[2nd]" or i == 3 and "[3rd]" or "[" .. i .. "th]"
		table.insert(lines, string.format("%s %s (%s) - $%s/s", medal, br.Name, br.Rarity, fmtNumber(br.BaseIncome)))
	end

	topParagraph:Set({
		Title = t("ParagraphRankings"),
		Content = table.concat(lines, "\n")
	})
end

updateTopBrainrots()

TopTab:CreateButton({
	Name = t("ButtonRefreshTop"),
	Callback = function()
		updateTopBrainrots()
		Rayfield:Notify({
			Title = t("TabTopBrainrots"),
			Content = t("NotifListRefreshed"),
			Duration = 2,
			Image = ICONS.Refresh,
		})
	end,
})

-- Settings Tab (continued)
SettingsTab:CreateDivider()

SettingsTab:CreateSection(t("SectionInfo"))

SettingsTab:CreateParagraph({
	Title = t("SectionInfo"),
	Content = t("InfoText"),
})

SettingsTab:CreateKeybind({
	Name = t("KeybindToggle"),
	CurrentKeybind = "C",
	HoldToInteract = false,
	Flag = "ToggleKeybind",
	Callback = function(Keybind)
		Rayfield:Notify({
			Title = t("TabSettings"),
			Content = t("NotifKeybind") .. Keybind,
			Duration = 2,
			Image = ICONS.Key,
		})
	end,
})

-- Auto Refresh
task.spawn(function()
	while true do
		task.wait(5)
		updateAnalyzerInfo()
		updateLog()
	end
end)

-- Keybind Toggle
UserInputService.InputBegan:Connect(function(input, gpe)
	if gpe then return end
	if input.KeyCode == Enum.KeyCode.C then
		Window:Toggle()
	end
end)

-- Character Respawn
Player.CharacterAdded:Connect(function()
	task.wait(1)
	updateAnalyzerInfo()
	updateCagesList()
end)

local backpack = Player:WaitForChild("Backpack")
local brainrotInventory = Player:WaitForChild("BrainrotInventory")

local function getInventoryCapacity()
	local success, result = pcall(function()
		return BrainrotInventoryController.getConfigValue("MaxSlots", brainrotInventory)
	end)
	return success and result or 20
end

local function getInventoryCount()
	local count = 0
	for _, item in ipairs(brainrotInventory:GetChildren()) do
		if item:IsA("Tool") or item.Name ~= "EmptySlot" then
			count = count + 1
		end
	end
	return count
end

local function isInventoryFull()
	return getInventoryCount() >= getInventoryCapacity()
end

local function getBestBrainrots()
	local items = {}
	for _, item in ipairs(brainrotInventory:GetChildren()) do
		if item:IsA("Tool") and item:FindFirstChild("BrainrotConfig") then
			table.insert(items, item)
		end
	end

	table.sort(items, function(a, b)
		local rarityA = a:FindFirstChild("BrainrotConfig") and a.BrainrotConfig.Rarity or 1
		local rarityB = b:FindFirstChild("BrainrotConfig") and b.BrainrotConfig.Rarity or 1
		return rarityA > rarityB
	end)

	return items
end

local function placeBestBrainrots()
	local bestBrainrots = getBestBrainrots()

	for _, brainrot in ipairs(bestBrainrots) do
		local success, result = pcall(function()
			return BrainrotInventoryController.requestPlaceBestSpotlightState(Player)
		end)
		if success then
			wait(0.5)
		end
	end
end

local function sellAllInventory()
	for _, item in ipairs(backpack:GetChildren()) do
		if item:IsA("Tool") then
			item:Destroy()
		end
	end

	for _, item in ipairs(brainrotInventory:GetChildren()) do
		if item:IsA("Tool") then
			item:Destroy()
		end
	end
end

Player.CharacterAdded:Connect(function()
	wait(1)

	if isInventoryFull() then
		placeBestBrainrots()
		wait(2)
		sellAllInventory()
	end
end)

brainrotInventory:GetChildrenAdded():Connect(function()
	wait(1)

	if isInventoryFull() then
		placeBestBrainrots()
		wait(2)
		sellAllInventory()
	end
end)

Rayfield:LoadConfiguration()
