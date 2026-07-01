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
local AutoCollectMoney = false
local MaxRuntime = 24 * 60 * 60

local AllowedRarities = {
	common = true,
	uncommon = true,
	rare = true,
	epic = true,
	legendary = true,
	mythic = true,
	secret = true,
	og = true,
	godly = true,
	ancestral = true,
	toxic = true,
	infernal = true,
	noir = true,
	aqua = true,
	boss = true,
	ruler = true,
	anime = true,
	glitched = true,
	summer = true,
	exclusive = true,
	admin = true,
}

local RarityPriority = {
	common = 1,
	uncommon = 2,
	rare = 3,
	epic = 4,
	legendary = 5,
	mythic = 6,
	secret = 7,
	og = 8,
	godly = 9,
	ancestral = 10,
	toxic = 11,
	infernal = 12,
	noir = 13,
	aqua = 14,
	boss = 15,
	ruler = 16,
	anime = 17,
	glitched = 18,
	summer = 19,
	exclusive = 20,
	admin = 21
}

local FishParagraph = InfoTab:CreateParagraph({
	Title = "Current Fish",
	Content = "Waiting for fish..."
})

local fishCache = {}
local FishData = {}

local function isUUID(str)
	return string.match(str, "^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$")
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

local function getIncomeOf(model)
	local frame = model:FindFirstChild("Frame", true)
	if not frame then return 0 end
	local incomeLabel = frame:FindFirstChild("income")
	if not incomeLabel then return 0 end
	return parseIncome(safeText(incomeLabel))
end

local function isAllowedRarity(rarityText)
	for rarityName, enabled in pairs(AllowedRarities) do
		if enabled and string.find(rarityText, string.lower(rarityName)) then
			return true
		end
	end
	return false
end

local function loadFishInfo(model)
	if not model or not model.PrimaryPart then
		return nil
	end

	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")

	if not hrp then
		return nil
	end

	local oldCFrame = hrp.CFrame
	hrp.CFrame = model.PrimaryPart.CFrame + Vector3.new(0, 5, 0)
	
	local startTime = tick()
	local success = false
	
	while tick() - startTime < 1.5 do
		local frame = model:FindFirstChild("Frame", true)
		if frame then
			local rarity = frame:FindFirstChild("rarity")
			if rarity and rarity.Text ~= "" then
				success = true
				break
			end
		end
		task.wait()
	end
	
	hrp.CFrame = oldCFrame
	
	if success then
		local rarity = getRarityOf(model)
		local income = getIncomeOf(model)
		
		if rarity and isAllowedRarity(rarity) then
			FishData[model.Name] = {
				rarity = rarity,
				income = income,
				scanned = true,
				lastSeen = tick()
			}
			return true
		end
	end
	
	return false
end

task.spawn(function()
	while true do
		for uuid, data in pairs(FishData) do
			if not fishCache[uuid] or not fishCache[uuid].Parent then
				FishData[uuid] = nil
				fishCache[uuid] = nil
			end
		end
		
		for uuid, model in pairs(fishCache) do
			if model and model.Parent then
				if not FishData[uuid] or not FishData[uuid].scanned then
					pcall(function()
						loadFishInfo(model)
					end)
					task.wait(0.05)
				end
			else
				fishCache[uuid] = nil
				FishData[uuid] = nil
			end
		end
		task.wait(0.5)
	end
end)

local function tryAddToCache(v)
	if isUUID(v.Name) then
		local rarityText = getRarityOf(v)
		if rarityText and isAllowedRarity(rarityText) then
			fishCache[v.Name] = v
		end
	end
end

local function parseIncome(text)
	text = string.lower(text or "")
	text = text:gsub(",", "")

	local number = tonumber(text:match("[%d%.]+")) or 0

	if text:find("k") then
		number *= 1e3
	elseif text:find("m") then
		number *= 1e6
	elseif text:find("b") then
		number *= 1e9
	elseif text:find("t") then
		number *= 1e12
	elseif text:find("q") then
		number *= 1e15
	end

	return number
end

task.spawn(function()
	while true do
		local newCache = {}
		local newFishData = {}
		
		for _, v in ipairs(Workspace:GetDescendants()) do
			if isUUID(v.Name) then
				local rarityText = getRarityOf(v)
				if rarityText and isAllowedRarity(rarityText) then
					newCache[v.Name] = v
					if FishData[v.Name] then
						newFishData[v.Name] = FishData[v.Name]
					end
				end
			end
		end
		
		fishCache = newCache
		
		for uuid, data in pairs(FishData) do
			if newCache[uuid] then
				newFishData[uuid] = data
			end
		end
		FishData = newFishData
		
		task.wait(2)
	end
end)

Workspace.DescendantAdded:Connect(function(v)
	task.delay(0.1, function()
		pcall(function()
			tryAddToCache(v)
		end)
	end)
end)

Workspace.DescendantRemoving:Connect(function(v)
	if isUUID(v.Name) then
		fishCache[v.Name] = nil
		FishData[v.Name] = nil
	end
end)

local function getBestFish()
	local best
	local bestPriority = -1
	local bestIncome = -1
	local currentTime = tick()

	for uuid, model in pairs(fishCache) do
		if model and model.Parent then
			local rarity
			local income = 0
			
			if FishData[uuid] and FishData[uuid].scanned then
				rarity = FishData[uuid].rarity
				income = FishData[uuid].income
			else
				rarity = getRarityOf(model)
				income = getIncomeOf(model)
				
				if rarity and isAllowedRarity(rarity) then
					FishData[uuid] = {
						rarity = rarity,
						income = income,
						scanned = true,
						lastSeen = currentTime
					}
				end
			end
			
			if rarity and isAllowedRarity(rarity) then
				local priority = RarityPriority[rarity] or 0
				
				if FishData[uuid] and FishData[uuid].lastSeen then
					if currentTime - FishData[uuid].lastSeen < 5 then
						priority = priority + 0.5
					end
				end
				
				if priority > bestPriority or (priority == bestPriority and income > bestIncome) then
					best = model
					bestPriority = priority
					bestIncome = income
				end
			end
		else
			fishCache[uuid] = nil
			FishData[uuid] = nil
		end
	end

	return best
end

local function safeFire(args)
	local success = pcall(function()
		FishingRemote:FireServer(args)
	end)
	return success
end

local function updateFishInfo(model)
	if not model then
		FishParagraph:Set({
			Title = "No Fish",
			Content = "Waiting for fish..."
		})
		return
	end
	
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
		Content = "Rarity: " .. rarity .. "\nLevel: " .. level .. "\nIncome: " .. income .. "\nWeight: " .. weight .. "\nUUID: " .. model.Name
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
				local lastFishUUID = nil
				local fishChangeCooldown = 0

				while AutoFishing and tick() - START < MaxRuntime do
					local success = pcall(function()
						local char = player.Character
						local hrp = char and char:FindFirstChild("HumanoidRootPart")

						if not hrp then
							task.wait(0.5)
							return
						end

						for uuid, model in pairs(fishCache) do
							if not model or not model.Parent then
								fishCache[uuid] = nil
								FishData[uuid] = nil
							end
						end

						local chosenModel = getBestFish()

						if not chosenModel or not chosenModel.Parent then
							task.wait(0.3)
							return
						end

						local uuid = chosenModel.Name
						
						if lastFishUUID == uuid and tick() - fishChangeCooldown < 2 then
							task.wait(0.1)
							return
						end

						updateFishInfo(chosenModel)
						lastFishUUID = uuid
						fishChangeCooldown = tick()

						local pos = hrp.Position + Vector3.new(math.random(-15, 15), 0, math.random(-15, 15))

						safeFire({
							kind = "requestCast",
							targetPosition = { X = pos.X, Y = pos.Y, Z = pos.Z }
						})

						task.wait(0.15)

						safeFire({
							kind = "requestHook",
							uuid = uuid
						})

						task.wait(0.15)

						local reelStart = tick()
						local reelAttempts = 0

						while AutoFishing do
							reelAttempts = reelAttempts + 1
							
							if reelAttempts % 3 == 0 then
								local bestFish = getBestFish()
								
								if bestFish and bestFish ~= chosenModel then
									local bestRarity = getRarityOf(bestFish)
									local currentRarity = getRarityOf(chosenModel)
									
									if bestRarity and currentRarity then
										local bestPriority = RarityPriority[bestRarity] or 0
										local currentPriority = RarityPriority[currentRarity] or 0
										
										if bestPriority > currentPriority then
											break
										elseif bestPriority == currentPriority then
											local bestIncome = getIncomeOf(bestFish)
											local currentIncome = getIncomeOf(chosenModel)
											if bestIncome > currentIncome then
												break
											end
										end
									end
								end
							end
							
							if not chosenModel or not chosenModel.Parent then
								break
							end
							
							if tick() - reelStart > 8 then
								break
							end
							
							safeFire({
								kind = "requestReel",
								uuid = uuid
							})
							
							task.wait(0.03)
						end
					end)

					task.wait(0.15)
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

task.spawn(function()
	while true do
		if AutoCollectMoney then
			pcall(function()
				for i = 1, 100 do
					local args = { { stand = "Stand" .. i, kind = "collectMoney" } }
					local PlotRemote = ReplicatedStorage:FindFirstChild("PlotRemote")
					if PlotRemote then
						PlotRemote:FireServer(unpack(args))
					end
					task.wait(0.05)
				end
			end)
		else
			task.wait(0.1)
		end
	end
end)

task.spawn(function()
	while true do
		local fishCount = 0
		local scannedCount = 0
		
		for uuid, model in pairs(fishCache) do
			if model and model.Parent then
				fishCount = fishCount + 1
				if FishData[uuid] and FishData[uuid].scanned then
					scannedCount = scannedCount + 1
				end
			end
		end
		
		local currentContent = FishParagraph.Content
		if currentContent == "Waiting for fish..." then
			FishParagraph:Set({
				Title = "Scanning...",
				Content = string.format("Fish found: %d\nScanned: %d\nScanning in progress...", fishCount, scannedCount)
			})
		end
		
		task.wait(5)
	end
end)

Rayfield:LoadConfiguration()
