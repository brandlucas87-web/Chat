local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local FishingRemote = ReplicatedStorage:WaitForChild("FishingRemote")

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
local MaxRuntime = 30 * 60

local AllowedRarities = {
	["og"] = true,
	["godly"] = true,
	["ancestral"] = true,
	["toxico"] = true,
	["infernal"] = true,
	["noir"] = true,
	["aqua"] = true,
	["boss"] = true,
	["ruler"] = true
}

local FishParagraph = InfoTab:CreateParagraph({
	Title = "Current Fish",
	Content = "Waiting for fish..."
})

-- =========================================
-- CACHE de peixes (evita varrer Workspace todo ciclo)
-- =========================================
local fishCache = {} -- [uuid] = model

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

-- Popula cache inicial
for _, v in ipairs(Workspace:GetDescendants()) do
	tryAddToCache(v)
end

-- Atualiza cache automaticamente conforme objetos aparecem/somem
Workspace.DescendantAdded:Connect(function(v)
	-- pequeno delay para o frame estar pronto
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
			-- Re-checa raridade caso toggles tenham mudado
			local rarityText = getRarityOf(model)
			if rarityText and isAllowedRarity(rarityText) then
				table.insert(valid, model)
			end
		else
			-- Remove entradas inválidas da cache
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
                        -- Limpa cache de entradas mortas antes de buscar
                        for uuid, model in pairs(fishCache) do
                            if not model or not model.Parent then
                                fishCache[uuid] = nil
                            end
                        end

                        local fishes = getValidFish()

                        if #fishes > 0 then
                            local chosenModel = fishes[math.random(1, #fishes)]
                            local uuid = chosenModel.Name

                            -- Valida se ainda existe antes de tentar
                            if not chosenModel.Parent then
                                task.wait(0.2)
                                continue  -- pula esse ciclo e tenta outro
                            end

                            updateFishInfo(chosenModel)

                            local pos = hrp.Position + Vector3.new(
                                math.random(-15, 15),
                                0,
                                math.random(-15, 15)
                            )

                            FishingRemote:FireServer({
                                kind = "requestCast",
                                targetPosition = { X = pos.X, Y = pos.Y, Z = pos.Z }
                            })

                            task.wait(0.2)

                            FishingRemote:FireServer({
                                kind = "requestHook",
                                uuid = uuid
                            })

                            task.wait(0.2)

                            -- Verifica se é ruler para dar reel infinito
                            local rarityText = getRarityOf(chosenModel)
                            local isRuler = rarityText and string.find(rarityText, "ruler")

                            if isRuler then
                                -- Reel infinito até o peixe não existir mais
                                while AutoFishing do
                                    if not chosenModel or not chosenModel.Parent then
                                        break
                                    end

                                    FishingRemote:FireServer({
                                        kind = "requestReel",
                                        uuid = uuid
                                    })

                                    task.wait(0.05)
                                end
                            else
                                -- Reel normal com limite de tempo (5 segundos)
                                local reelStart = tick()
                                while AutoFishing and tick() - reelStart < 5 do
                                    if not chosenModel or not chosenModel.Parent then
                                        break
                                    end

                                    FishingRemote:FireServer({
                                        kind = "requestReel",
                                        uuid = uuid
                                    })

                                    task.wait(0.05)
                                end
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
