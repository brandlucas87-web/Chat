--[[ AutoStack v1.1
   Automaticamente junta (stack) brainrots iguais do inventario nos stands.
   Equipa o brainrot na mao antes de mandar o stack.
   Roda a cada 1 segundo.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer

-- Não bloquear carregamento do script esperando Remotes/globals imediatamente
local PlotRemote = nil
local FishingRemote = nil

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

	-- Mandar o stack (usa PlotRemote se disponível)
	if PlotRemote then
		PlotRemote:FireServer({
			kind = "stackBrainrot",
			stand = standName,
			brainrotUUID = uuid,
		})
	end
	task.wait(0.5)

	-- Desequipar
	humanoid:UnequipTools()
	task.wait(0.5)

	return true
end

-- =========================================
-- CARREGAR UI IMEDIATAMENTE (não bloquear)
-- =========================================
local BrainrotRarities = require(game.ReplicatedStorage.Datas.BrainrotRarities)

local Rayfield
local Window

local ok, rf = pcall(function()
	return loadstring(game:HttpGet('https://sirius.menu/rayfield'))()
end)

if ok and rf then
	Rayfield = rf
else
	local status, res = pcall(function()
		return loadstring(game:HttpGet('https://sirius.menu/rayfield'))()
	end)
	if status and res then
		Rayfield = res
	else
		warn("[Fishing] Falha ao carregar Rayfield UI:", res)
		Rayfield = {
			CreateWindow = function() return {
				CreateTab = function() return {
					CreateSection = function() end,
					CreateToggle = function() end,
					CreateButton = function() end,
					CreateParagraph = function() return { Set = function() end } end
				}
			end }
	end
end

Window = Rayfield:CreateWindow({
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

-- Hierarquia de raridades lida dinamicamente de BrainrotRarities (do pior para o melhor)
local RarityHierarchy = {}
for rarityName in pairs(BrainrotRarities) do
	table.insert(RarityHierarchy, string.lower(rarityName))
end

local function getRarityPriority(rarityName)
	for priority, rarity in ipairs(RarityHierarchy) do
		if rarity == string.lower(rarityName) then
			return priority
		end
	end
	return 0
end

local function getBestBrainrot()
	local InventoryClient = _G.BrainrotInventoryClient
	if not InventoryClient then return nil end

	local inventory = InventoryClient.getInventory()
	if not inventory or not next(inventory) then return nil end

	local bestUUID = nil
	local bestPriority = 0

	for uuid, brainrotData in pairs(inventory) do
		if brainrotData and brainrotData.rarity then
			local priority = getRarityPriority(brainrotData.rarity)
			if priority > bestPriority then
				bestPriority = priority
				bestUUID = uuid
			end
		end
	end

	return bestUUID
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

-- Cache inicial (não bloqueante)
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

-- Função autoStack (usa globals quando estiverem prontos)
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

-- =========================================
-- INICIALIZAÇÃO EM SEGUNDO PLANO (não bloqueante)
-- =========================================
task.spawn(function()
	-- curta espera para permitir que o jogo carregue minimamente
	task.wait(1)

	-- buscar remotes/globals com timeouts menores para não bloquear muito
	PlotRemote = ReplicatedStorage:FindFirstChild("PlotRemote") or ReplicatedStorage:WaitForChild("PlotRemote", 5)
	FishingRemote = ReplicatedStorage:FindFirstChild("FishingRemote") or ReplicatedStorage:WaitForChild("FishingRemote", 5)

	local pc = waitForGlobal("PlotController", 10)
	local ic = waitForGlobal("BrainrotInventoryClient", 10)

	if not pc or not ic then
		warn("[Fishing] Alguns globals não estão disponíveis após timeout. Funções dependentes podem não funcionar imediatamente.")
	end

	-- iniciar loop de autoStack (antes estava lançado no topo e podia bloquear)
	task.spawn(function()
		task.wait(3)
		while true do
			autoStack()
			task.wait(1)
		end
	end)

	print("[AutoStack] Inicializado em background.")
end)

print("[AutoStack] Ativo! Stacking automatico (inicialização em background).")

local player = LocalPlayer

-- Se FishingRemote não estiver definido ainda, usaremos a variável definida na inicialização em background

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

							-- Buscar e equipar o melhor brainrot disponível
							local bestBrainrotUUID = getBestBrainrot()
							if bestBrainrotUUID then
								local tool = findBrainrotTool(bestBrainrotUUID)
								if tool then
									local humanoid = char and char:FindFirstChildOfClass("Humanoid")
									if humanoid then
										humanoid:EquipTool(tool)
										task.wait(0.2)
									end
								end
							end

							local pos = hrp.Position + Vector3.new(
								math.random(-15, 15),
								0,
								math.random(-15, 15)
							)

							if FishingRemote then
								FishingRemote:FireServer({
									kind = "requestCast",
									targetPosition = {
										X = pos.X,
										Y = pos.Y,
										Z = pos.Z
									}
								})
							end

							task.wait(0.2)

							if FishingRemote then
								FishingRemote:FireServer({
									kind = "requestHook",
									uuid = uuid
								})
							end

							task.wait(0.2)

							while AutoFishing do
								if not chosenModel or not chosenModel.Parent then
									break
								end

								if FishingRemote then
									FishingRemote:FireServer({
										kind = "requestReel",
										uuid = uuid
									})
								end

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

-- Auto Collect loop (usa PlotRemote se disponível; não bloqueante)
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

				local pr = PlotRemote or ReplicatedStorage:FindFirstChild("PlotRemote")
				if pr then
					pr:FireServer(unpack(args))
				else
					-- se não existe PlotRemote ainda, esperar um pouco
					task.wait(0.05)
				end

				task.wait(0.05)
			end
		else
			task.wait(0.1)
		end
	end
end)
