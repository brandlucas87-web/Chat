--[[ AutoOptimizer v2.1
   Fase 1: Substitui brainrots dos stands pelos do inventario quando rendem mais dinheiro.
   Fase 2: Junta (stack) brainrots iguais do inventario nos stands para subir level e income.
   Roda automaticamente a cada 1 segundo. Digite /optimize ou /opt para forcar manualmente.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer
local PlotRemote = ReplicatedStorage:WaitForChild("PlotRemote", 30)
local MiddleMan = require(ReplicatedStorage.Modules.MiddleMan)

local function waitForGlobal(name, timeout)
	local start = tick()
	while not _G[name] and tick() - start < (timeout or 30) do
		task.wait(0.5)
	end
	return _G[name]
end

local function getBrainrotIncome(brainrotData)
	if not brainrotData or not brainrotData.name then return 0 end
	return MiddleMan:getBrainrotIncome(brainrotData)
end

-- Ler estado atual dos stands e inventario
local function readState()
	local PlotController = _G.PlotController
	local InventoryClient = _G.BrainrotInventoryClient
	if not PlotController or not InventoryClient then return nil end

	local plot = PlotController.getPlot()
	if not plot then return nil end

	local inventory = InventoryClient.getInventory()
	if not inventory then return nil end

	return {
		plot = plot,
		brainrotStands = plot.brainrotStands or {},
		standParts = plot.standParts or {},
		inventory = inventory,
	}
end

-- FASE 1: Trocar brainrots ruins dos stands pelos melhores do inventario
local function phaseSwap()
	local PlotController = _G.PlotController
	local InventoryClient = _G.BrainrotInventoryClient

	if not PlotController or not InventoryClient then
		warn("[AutoOptimizer] Controllers nao encontrados! Aguarde o jogo carregar.")
		return
	end

	local plot = PlotController.getPlot()
	if not plot then
		warn("[AutoOptimizer] Nenhum plot encontrado!")
		return
	end

	local inventory = InventoryClient.getInventory()
	if not inventory then
		warn("[AutoOptimizer] Inventario nao encontrado!")
		return
	end

	local brainrotStands = plot.brainrotStands or {}
	local standParts = plot.standParts or {}

	-- Coletar todos os nomes de stands
	local allStandNames = {}
	for standName, _ in pairs(standParts) do
		table.insert(allStandNames, standName)
	end

	if #allStandNames == 0 then
		print("[AutoOptimizer] Nenhum stand encontrado!")
		return
	end

	-- Coletar TODOS os brainrots (stands + inventario)
	local allBrainrots = {}
	local standUUIDs = {}

	for standName, brainrotData in pairs(brainrotStands) do
		if brainrotData and brainrotData.uuid then
			standUUIDs[brainrotData.uuid] = standName
			table.insert(allBrainrots, {
				uuid = brainrotData.uuid,
				name = brainrotData.name,
				level = brainrotData.level or 1,
				mutation = brainrotData.mutation or "Basic",
				income = getBrainrotIncome(brainrotData),
				currentStand = standName,
			})
		end
	end

	for uuid, brainrotData in pairs(inventory) do
		if brainrotData and brainrotData.uuid and not standUUIDs[brainrotData.uuid] then
			table.insert(allBrainrots, {
				uuid = brainrotData.uuid,
				name = brainrotData.name,
				level = brainrotData.level or 1,
				mutation = brainrotData.mutation or "Basic",
				income = getBrainrotIncome(brainrotData),
				currentStand = nil,
			})
		end
	end

	-- Ordenar por income (maior primeiro)
	table.sort(allBrainrots, function(a, b) return a.income > b.income end)

	-- Os top N brainrots devem estar nos stands
	local numStands = #allStandNames
	local shouldBeOnStand = {}
	for i = 1, math.min(numStands, #allBrainrots) do
		shouldBeOnStand[allBrainrots[i].uuid] = true
		allBrainrots[i]._rank = i
	end

	-- Determinar o que precisa mudar
	local toPickup = {}  -- brainrots nos stands que NAO deveriam estar
	local toPlace = {}   -- brainrots no inventario que DEVERIAM estar nos stands

	for _, br in ipairs(allBrainrots) do
		if br.currentStand and not shouldBeOnStand[br.uuid] then
			table.insert(toPickup, br)
		elseif not br.currentStand and shouldBeOnStand[br.uuid] then
			table.insert(toPlace, br)
		end
	end

	-- Encontrar stands vazios que podem ser preenchidos
	local emptyStands = {}
	for _, standName in ipairs(allStandNames) do
		if not brainrotStands[standName] then
			table.insert(emptyStands, standName)
		end
	end

	-- Brainrots do inventario que sobraram (nao estao no top N)
	local assignedToPlace = {}
	for _, br in ipairs(toPlace) do
		assignedToPlace[br.uuid] = true
	end

	local availableForEmpty = {}
	for _, br in ipairs(allBrainrots) do
		if not br.currentStand and not shouldBeOnStand[br.uuid] and not assignedToPlace[br.uuid] then
			table.insert(availableForEmpty, br)
		end
	end
	table.sort(availableForEmpty, function(a, b) return a.income > b.income end)

	-- Preencher stands vazios com brainrots disponiveis
	for i, standName in ipairs(emptyStands) do
		if i <= #availableForEmpty then
			local br = availableForEmpty[i]
			br.targetStand = standName
			table.insert(toPlace, br)
		end
	end

	if #toPickup == 0 and #toPlace == 0 then
		print("[AutoOptimizer] Seus stands ja estao otimizados! Nenhum swap necessario.")
		return
	end

	-- Ordenar: pickup dos piores primeiro, placement dos melhores primeiro
	table.sort(toPickup, function(a, b) return a.income < b.income end)
	table.sort(toPlace, function(a, b) return a.income > b.income end)

	-- Log dos swaps planejados
	print("[AutoOptimizer] === PLANEJAMENTO DE SWAPS ===")
	print(string.format("[AutoOptimizer] Total brainrots: %d | Stands: %d | Vazios: %d",
		#allBrainrots, numStands, #emptyStands))

	-- Executar swaps (pickup + place)
	local swapCount = 0
	local maxSwaps = math.max(#toPickup, #toPlace)

	for i = 1, maxSwaps do
		local pickup = toPickup[i]
		local place = toPlace[i]

		if pickup and place then
			-- Swap: tira o pior, coloca o melhor
			local targetStand = place.targetStand or pickup.currentStand
			print(string.format("[AutoOptimizer] Swap %d: Stand '%s' | %s ($%d/s) -> %s ($%d/s)",
				swapCount + 1, targetStand,
				pickup.name, pickup.income,
				place.name, place.income))

			-- Pickup brainrot atual do stand
			PlotRemote:FireServer({
				kind = "pickupBrainrot",
				stand = pickup.currentStand,
			})
			task.wait(1)

			-- Place brainrot novo no stand
			PlotRemote:FireServer({
				kind = "placeBrainrot",
				brainrotUUID = place.uuid,
				stand = targetStand,
			})
			task.wait(1)

			swapCount = swapCount + 1

		elseif place and not pickup then
			-- So colocar (stand vazio)
			local targetStand = place.targetStand
			if targetStand then
				print(string.format("[AutoOptimizer] Place %d: Stand '%s' | %s ($%d/s)",
				swapCount + 1, targetStand, place.name, place.income))

				PlotRemote:FireServer({
					kind = "placeBrainrot",
					brainrotUUID = place.uuid,
					stand = targetStand,
				})
				task.wait(1)

				swapCount = swapCount + 1
			end

		elseif pickup and not place then
			-- So pickup (brainrot ruim sendo removido sem substituicao)
			-- Isso nao deveria acontecer no algoritmo normal, mas por seguranca
			print(string.format("[AutoOptimizer] Pickup %d: Stand '%s' | %s ($%d/s) removido",
				swapCount + 1, pickup.currentStand, pickup.name, pickup.income))

			PlotRemote:FireServer({
				kind = "pickupBrainrot",
				stand = pickup.currentStand,
			})
			task.wait(1)

			swapCount = swapCount + 1
		end
	end

	print(string.format("[AutoOptimizer] Fase 1 completa! %d swap(s) realizados.", swapCount))
	return swapCount
end

-- FASE 2: Juntar (stack) brainrots iguais do inventario nos stands
local function phaseStack()
	-- Esperar o estado sincronizar apos os swaps
	task.wait(2)

	local state = readState()
	if not state then
		warn("[AutoOptimizer] Nao foi possivel ler o estado para stacking.")
		return 0
	end

	local brainrotStands = state.brainrotStands
	local inventory = state.inventory

	-- Mapear: nome do brainrot -> stands que tem esse brainrot
	local standByBrainrotName = {}
	for standName, brainrotData in pairs(brainrotStands) do
		if brainrotData and brainrotData.name then
			if not standByBrainrotName[brainrotData.name] then
				standByBrainrotName[brainrotData.name] = {}
			end
			table.insert(standByBrainrotName[brainrotData.name], {
				stand = standName,
				brainrotData = brainrotData,
				income = getBrainrotIncome(brainrotData),
			})
		end
	end

	-- Mapear: nome do brainrot -> lista de UUIDs no inventario que dao match
	local inventoryByName = {}
	local usedUUIDs = {}
	for uuid, brainrotData in pairs(inventory) do
		if brainrotData and brainrotData.name and brainrotData.uuid then
			-- Pular se ja esta num stand
			local isOnStand = false
			for _, standData in pairs(brainrotStands) do
				if standData and standData.uuid == uuid then
					isOnStand = true
					break
				end
			end
			if not isOnStand then
				if not inventoryByName[brainrotData.name] then
					inventoryByName[brainrotData.name] = {}
				end
				table.insert(inventoryByName[brainrotData.name], {
					uuid = brainrotData.uuid,
					name = brainrotData.name,
					level = brainrotData.level or 1,
					mutation = brainrotData.mutation or "Basic",
					income = getBrainrotIncome(brainrotData),
				})
			end
		end
	end

	-- Ordenar inventory lists por income desc (stack dos melhores primeiro)
	for name, list in pairs(inventoryByName) do
		table.sort(list, function(a, b) return a.income > b.income end)
	end

	-- Ordenar stands por income desc (priorizar stack nos que rendem mais)
	for name, stands in pairs(standByBrainrotName) do
		table.sort(stands, function(a, b) return a.income > b.income end)
	end

	print("[AutoOptimizer] === FASE 2: STACKING (JUNTAR) ===")

	local stackCount = 0

	-- Para cada brainrot no inventario que tem nome igual a um no stand
	for brainrotName, invList in pairs(inventoryByName) do
		local stands = standByBrainrotName[brainrotName]
		if stands and #stands > 0 and #invList > 0 then
			-- Para cada brainrot no inventario com esse nome
			for _, invBr in ipairs(invList) do
				if usedUUIDs[invBr.uuid] then continue end

				-- Encontrar o melhor stand com esse brainrot para stackar
				-- Prioridade: stand com maior income (base maior = ganho maior por stack)
				local bestStand = nil
				local bestIncome = -1
				for _, standInfo in ipairs(stands) do
					if standInfo.income > bestIncome then
						bestIncome = standInfo.income
						bestStand = standInfo
					end
				end

				if bestStand then
					local currentLevel = bestStand.brainrotData.level or 1
					-- Calcular income apos stack
					local newIncome = getBrainrotIncome({
						name = bestStand.brainrotData.name,
						level = currentLevel + 1,
						mutation = bestStand.brainrotData.mutation or "Basic",
					})
					local incomeGain = newIncome - bestStand.income

					print(string.format("[AutoOptimizer] Stack %d: '%s' (lvl %d->%d) no Stand '%s' | $%d/s -> $%d/s (+$%d/s)",
						stackCount + 1, brainrotName, currentLevel, currentLevel + 1,
						bestStand.stand, bestStand.income, newIncome, incomeGain))

					PlotRemote:FireServer({
						kind = "stackBrainrot",
						stand = bestStand.stand,
						brainrotUUID = invBr.uuid,
					})
					task.wait(1)

					-- Atualizar o income do stand localmente para o proximo calculo
					bestStand.brainrotData.level = currentLevel + 1
					bestStand.income = newIncome
					usedUUIDs[invBr.uuid] = true
					stackCount = stackCount + 1
				end
			end
		end
	end

	if stackCount == 0 then
		print("[AutoOptimizer] Fase 2: Nenhum brainrot do inventario combina com os stands para stacking.")
	else
		print(string.format("[AutoOptimizer] Fase 2 completa! %d stack(s) realizados.", stackCount))
	end

	return stackCount
end

-- Flag para evitar execucoes sobrepostas
local isRunning = false

-- Funcao principal
local function optimize(forceLog)
	if isRunning then return end
	isRunning = true

	local PlotController = _G.PlotController
	local InventoryClient = _G.BrainrotInventoryClient

	if not PlotController or not InventoryClient then
		isRunning = false
		return
	end

	local swaps = phaseSwap() or 0
	local stacks = phaseStack() or 0

	if forceLog or swaps > 0 or stacks > 0 then
		print(string.format("[AutoOptimizer] %d swap(s) + %d stack(s)", swaps, stacks))
	end

	isRunning = false
end

-- Esperar o jogo carregar completamente
task.wait(8)

-- Garantir que os controllers estao prontos
waitForGlobal("PlotController", 30)
waitForGlobal("BrainrotInventoryClient", 30)

-- Expor funcao global
_G.AutoOptimizeStands = optimize

-- Comando no chat (forca log)
LocalPlayer.Chatted:Connect(function(msg)
	local cmd = string.lower(string.gsub(msg, "%s+$", ""))
	if cmd == "/optimize" or cmd == "/opt" then
		task.spawn(function() optimize(true) end)
	end
end)

-- Loop automatico: roda a cada 1 segundo
task.spawn(function()
	task.wait(3)
	while true do
		optimize(false)
		task.wait(1)
	end
end)

print("[AutoOptimizer v2.1] Auto-otimizacao ativa! Roda a cada 1s automaticamente. /opt para forcar log.")
