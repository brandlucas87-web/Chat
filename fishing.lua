--[[ AutoStack v1.1
   Automaticamente junta (stack) brainrots iguais do inventario nos stands.
   Equipa o brainrot na mao antes de mandar o stack.
   Roda a cada 1 segundo.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer
local PlotRemote = ReplicatedStorage:WaitForChild("PlotRemote", 30)

local function waitForGlobal(name, timeout)
	local start = tick()
	while not _G[name] and tick() - start < (timeout or 30) do
		task.wait(0.5)
	end
	return _G[name]
end

-- Achar tool do brainrot no backpack pelo UUID
local function findBrainrotTool(uuid)
	local backpack = LocalPlayer:FindFirstChild("Backpack")
	if not backpack then return nil end
	for _, tool in backpack:GetChildren() do
		if tool:IsA("Tool") and tool:GetAttribute("brainrotUUID") == uuid then
			return tool
		end
	end
	return nil
end

-- Equipar brainrot, mandar stack, desequipar
local function equipAndStack(standName, uuid)
	local character = LocalPlayer.Character
	if not character then return false end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return false end

	local tool = findBrainrotTool(uuid)
	if not tool then return false end

	-- Equipar o brainrot na mao
	humanoid:EquipTool(tool)
	task.wait(0.5)

	-- Mandar o stack
	PlotRemote:FireServer({
		kind = "stackBrainrot",
		stand = standName,
		brainrotUUID = uuid,
	})
	task.wait(0.5)

	-- Desequipar
	humanoid:UnequipTools()
	task.wait(0.5)

	return true
end

-- Esperar o jogo carregar
task.wait(8)
waitForGlobal("PlotController", 30)
waitForGlobal("BrainrotInventoryClient", 30)

local isStacking = false

local function autoStack()
	if isStacking then return end

	local PlotController = _G.PlotController
	local InventoryClient = _G.BrainrotInventoryClient
	if not PlotController or not InventoryClient then return end

	local plot = PlotController.getPlot()
	if not plot then return end

	local inventory = InventoryClient.getInventory()
	if not inventory then return end

	local brainrotStands = plot.brainrotStands or {}

	-- Para cada brainrot no inventario, ver se tem um stand com o mesmo nome
	for uuid, brainrotData in pairs(inventory) do
		if not brainrotData or not brainrotData.name or not brainrotData.uuid then continue end

		-- Achar stand com brainrot de mesmo nome
		for standName, standData in pairs(brainrotStands) do
			if standData and standData.name == brainrotData.name then
				isStacking = true
				local success = equipAndStack(standName, uuid)
				isStacking = false
				return -- Re-ler estado no proximo tick
			end
		end
	end
end

-- Loop a cada 1 segundo
task.spawn(function()
	task.wait(3)
	while true do
		autoStack()
		task.wait(1)
	end
end)

print("[AutoStack] Ativo! Stacking automatico a cada 1s.")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local FishingRemote = ReplicatedStorage:WaitForChild("FishingRemote")

local BrainrotRarities = require(game.ReplicatedStorage.Datas.BrainrotRarities)

local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

local Window = Rayfield:CreateWindow({
	Name = "Fishing Autofarm",
	Icon = "fish",
	LoadingTitle = "Fishing Script",
	LoadingSubtitle = "by ChatGPT",
	ShowText = "Fishing UI",
	Theme = "Ocean",
	ToggleUIKeybind = "K",
	ConfigurationSaving = {
		Enabled = true,
		FolderName = "FishingHub",
		FileName = "FishingConfig"
	},
	DisableRayfieldPrompts = true,
	DisableBuildWarnings = true,
	KeySystem = false
})

local MainTab = Window:CreateTab("Main", "fish")
local ShopTab = Window:CreateTab("Shop", "shopping-cart")
local InfoTab = Window:CreateTab("Fish Info", "info")

MainTab:CreateSection("Autofarm")

local AutoFishing = false
local AutoCollectMoney = false
local MaxRuntime = 30 * 60

local AllowedRarities = {}
for rarityName in pairs(BrainrotRarities) do
	AllowedRarities[string.lower(rarityName)] = true
end

local FishParagraph = InfoTab:CreateParagraph({
	Title = "Current Fish",
	Content = "Waiting for fish..."
})

-- =========================================
-- CACHE de peixes
-- =========================================
local fishCache = {}

local function isUUID(str)
	return string.match(
		str,
		"^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$"
	)
end

local function safeText(obj)
	if obj and obj:IsA("TextLabel") then
		return obj.Text
	end
	return "Unknown"
end

local function getRarityOf(model)
	local frame = model:FindFirstChild("Frame", true)
	if not frame then return nil end

	local rarityLabel = frame:FindFirstChild("rarity")
	if not rarityLabel then return nil end

	return string.lower(safeText(rarityLabel))
end

local function isAllowedRarity(rarityText)
	for rarityName, enabled in pairs(AllowedRarities) do
		if enabled and string.find(rarityText, string.lower(rarityName)) then
			return true
		end
	end

	return false
end

local function tryAddToCache(v)
	if isUUID(v.Name) then
		local rarityText = getRarityOf(v)

		if rarityText and isAllowedRarity(rarityText) then
			fishCache[v.Name] = v
		end
	end
end

-- Cache inicial
for _, v in ipairs(Workspace:GetDescendants()) do
	tryAddToCache(v)
end

Workspace.DescendantAdded:Connect(function(v)
	task.delay(0.2, function()
		tryAddToCache(v)
	end)
end)

Workspace.DescendantRemoving:Connect(function(v)
	if isUUID(v.Name) then
		fishCache[v.Name] = nil
	end
end)

local function getValidFish()
	local valid = {}

	for uuid, model in pairs(fishCache) do
		if model and model.Parent then
			local rarityText = getRarityOf(model)

			if rarityText and isAllowedRarity(rarityText) then
				table.insert(valid, model)
			end
		else
			fishCache[uuid] = nil
		end
	end

	return valid
end

-- =========================================

local function updateFishInfo(model)
	local frame = model:FindFirstChild("Frame", true)
	if not frame then return end

	local rarity = safeText(frame:FindFirstChild("rarity"))
	local level = safeText(frame:FindFirstChild("level"))
	local income = safeText(frame:FindFirstChild("income"))
	local brainrotName = safeText(frame:FindFirstChild("brainrotName"))

	local weight = "Unknown"
	local weightFrame = frame:FindFirstChild("Weight")

	if weightFrame then
		weight = safeText(weightFrame:FindFirstChild("weightText"))
	end

	FishParagraph:Set({
		Title = brainrotName,
		Content =
			"Rarity: " .. rarity ..
			"\nLevel: " .. level ..
			"\nIncome: " .. income ..
			"\nWeight: " .. weight ..
			"\nUUID: " .. model.Name
	})
end

MainTab:CreateToggle({
	Name = "Auto Fishing",
	CurrentValue = false,
	Flag = "AutoFishingToggle",

	Callback = function(Value)
		AutoFishing = Value

		if Value then
			Rayfield:Notify({
				Title = "Auto Fishing",
				Content = "Started autofarm",
				Duration = 3,
				Image = "fish"
			})

			task.spawn(function()
				local START = tick()

				while AutoFishing and tick() - START < MaxRuntime do
					local char = player.Character
					local hrp = char and char:FindFirstChild("HumanoidRootPart")

					if hrp then
						for uuid, model in pairs(fishCache) do
							if not model or not model.Parent then
								fishCache[uuid] = nil
							end
						end

						local fishes = getValidFish()

						if #fishes > 0 then
							local chosenModel = fishes[math.random(1, #fishes)]
							local uuid = chosenModel.Name

							if not chosenModel.Parent then
								task.wait(0.2)
								continue
							end

							updateFishInfo(chosenModel)

							local pos = hrp.Position + Vector3.new(
								math.random(-15, 15),
								0,
								math.random(-15, 15)
							)

							FishingRemote:FireServer({
								kind = "requestCast",
								targetPosition = {
									X = pos.X,
									Y = pos.Y,
									Z = pos.Z
								}
							})

							task.wait(0.2)

							FishingRemote:FireServer({
								kind = "requestHook",
								uuid = uuid
							})

							task.wait(0.2)

							while AutoFishing do
								if not chosenModel or not chosenModel.Parent then
									break
								end

								FishingRemote:FireServer({
									kind = "requestReel",
									uuid = uuid
								})

								task.wait()
							end

							Rayfield:Notify({
								Title = "Fish Captured",
								Content = tostring(uuid),
								Duration = 2,
								Image = "check"
							})
						else
							task.wait(0.5)
						end
					else
						task.wait(0.5)
					end

					task.wait(0.3)
				end

				AutoFishing = false

				Rayfield:Notify({
					Title = "Auto Fishing",
					Content = "Finished",
					Duration = 3,
					Image = "circle-stop"
				})
			end)
		else
			Rayfield:Notify({
				Title = "Auto Fishing",
				Content = "Stopped autofarm",
				Duration = 2,
				Image = "x"
			})
		end
	end,
})

MainTab:CreateToggle({
	Name = "Auto Collect Money",
	CurrentValue = false,
	Flag = "AutoCollectMoneyToggle",

	Callback = function(Value)
		AutoCollectMoney = Value

		if Value then
			Rayfield:Notify({
				Title = "Auto Collect",
				Content = "Started collecting money",
				Duration = 3,
				Image = "coins"
			})
		else
			Rayfield:Notify({
				Title = "Auto Collect",
				Content = "Stopped collecting money",
				Duration = 2,
				Image = "x"
			})
		end
	end,
})

ShopTab:CreateButton({
	Name = "Rod Shop",
	Callback = function()
		local player = Players.LocalPlayer
		player.PlayerGui.main.middle.rodShop.Visible = true
	end,
	Icon = "shopping-cart"
})

MainTab:CreateSection("Allowed Rarities")

for rarityName in pairs(AllowedRarities) do
	MainTab:CreateToggle({
		Name = rarityName,
		CurrentValue = true,
		Flag = "RARITY_" .. rarityName,

		Callback = function(Value)
			AllowedRarities[rarityName] = Value
		end,
	})
end

Rayfield:LoadConfiguration()

task.spawn(function()
	while true do
		if AutoCollectMoney then
			for i = 1, 100 do
				local args = {
					{
						stand = "Stand" .. i,
						kind = "collectMoney"
					}
				}

				ReplicatedStorage
					:WaitForChild("PlotRemote")
					:FireServer(unpack(args))

				task.wait(0.05)
			end
		else
			task.wait(0.1)
		end
	end
end)
