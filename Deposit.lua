-- Polypode Data: Deposit — rangement dans la banque des objets des sacs qui s'y trouvent déjà

local _, ns = ...

-- Bouton « Ranger » de la fiche Dépôts (UI.lua) : chaque pile des sacs dont l'objet est déjà
-- dans la banque du personnage (relue en direct, banque ouverte) y est déposée, une à la fois :
--   1. sur une pile incomplète du même objet (SplitContainerItem si elle ne tient pas entière) ;
--   2. sinon dans un emplacement libre d'un onglet qui contient déjà l'objet ;
--   3. sinon dans le premier emplacement libre de la banque ; aucun : « banque pleine », arrêt.
-- Un déplacement = prendre l'objet (curseur) puis le poser ; le suivant attend que la pile se
-- déverrouille (réponse du serveur). Arrêt si la banque se ferme ou si une autre s'ouvre.
-- Seule la banque du personnage (« K ») est gérée pour l'instant.

local STEP_INTERVAL = 0.1 -- secondes entre deux vérifications
local STEP_TIMEOUT = 5 -- secondes d'attente au plus pour une pile (verrou, curseur)

local run -- rangement en cours : { kind, queue, index, done, skipped, total, since, ticker }
local status -- texte d'avancement, affiché dans la fiche Dépôts

local BANK_NAMES = { K = "banque", A = "banque de bataillon", G = "banque de guilde" }

local function Notify()
	if ns.UpdateDepositControls then
		ns.UpdateDepositControls()
	end
end

-- Banques ouvertes maintenant : { K = true } (personnage), { A = true } (bataillon), { G = true }
-- (guilde). La fenêtre de banque n'en montre qu'une à la fois : l'onglet affiché fait foi ;
-- fenêtre remplacée par un addon de sacs : banque du personnage.
function ns.OpenBanks()
	local open = {}
	if ns.IsBankOpen() then
		local bankType
		if BankFrame and BankFrame:IsShown() and BankFrame.GetActiveBankType then
			local ok, value = pcall(BankFrame.GetActiveBankType, BankFrame)
			bankType = ok and value or nil
		end
		if bankType and Enum.BankType and bankType == Enum.BankType.Account then
			open.A = true
		else
			open.K = true
		end
	end
	if ns.IsGuildBankOpen() then
		open.G = true
	end
	return open
end

-- Rangement possible dans la banque kind : true, ou false et la raison.
function ns.CanDeposit(kind)
	local open, count = ns.OpenBanks(), 0
	for _ in pairs(open) do
		count = count + 1
	end
	if count > 1 then
		return false, "Une seule banque doit être ouverte : personnage, bataillon ou guilde."
	elseif not open[kind] then
		return false, "Ouvrez la banque du personnage auprès d'un banquier (onglet « Banque du personnage ») : "
			.. "une seule banque doit être ouverte (personnage, bataillon ou guilde)."
	end
	return true
end

function ns.IsDepositRunning()
	return run ~= nil
end

function ns.GetDepositStatus()
	return status
end

-- LECTURE EN DIRECT -------------------------------------------------------------------------

local function Info(bag, slot)
	return C_Container.GetContainerItemInfo(bag, slot)
end

local function MaxStack(itemID)
	local size = C_Item and C_Item.GetItemMaxStackSizeByID and C_Item.GetItemMaxStackSizeByID(itemID)
	return tonumber(size) or 1
end

-- Emplacements de la banque, dans l'ordre des onglets : { bag, slot, itemID, count, locked }.
local function BankSlots(kind)
	local slots = {}
	for _, bag in ipairs(ns.BagIDs(kind)) do
		for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
			local info = Info(bag, slot)
			slots[#slots + 1] = { bag = bag, slot = slot, itemID = info and info.itemID,
				count = info and info.stackCount or 0, locked = info and info.isLocked }
		end
	end
	return slots
end

-- Objet autorisé dans cette banque (objets liés, de quête...) ; inconnu = oui.
local function Allowed(kind, bag, slot)
	if not (C_Bank and C_Bank.IsItemAllowedInBankType and Enum.BankType and ItemLocation) then
		return true
	end
	local bankType = kind == "A" and Enum.BankType.Account or Enum.BankType.Character
	local ok, allowed = pcall(C_Bank.IsItemAllowedInBankType, bankType, ItemLocation:CreateFromBagAndSlot(bag, slot))
	return not ok or allowed
end

-- Où poser count exemplaires de itemID : l'emplacement et le nombre qui y tient, ou nil.
local function FindTarget(kind, itemID, count)
	local slots = BankSlots(kind)
	local maxStack = MaxStack(itemID)
	local bagsWithItem = {}
	for _, target in ipairs(slots) do
		if target.itemID == itemID then
			bagsWithItem[target.bag] = true
			if not target.locked and target.count < maxStack then
				return target, math.min(count, maxStack - target.count)
			end
		end
	end
	local anyFree
	for _, target in ipairs(slots) do
		if not target.itemID and not target.locked then
			if bagsWithItem[target.bag] then
				return target, count
			end
			anyFree = anyFree or target
		end
	end
	return anyFree, anyFree and count
end

-- DÉROULEMENT --------------------------------------------------------------------------------

local function Progress()
	status = "Rangement : " .. run.done .. " sur " .. run.total
end

-- Fin du rangement ; reason : nil (terminé), "full", "closed" ou "stopped".
local function Finish(reason)
	if not run then
		return
	end
	run.ticker:Cancel()
	local done, total, skipped = run.done, run.total, run.skipped
	local bank = BANK_NAMES[run.kind]
	run = nil
	if reason == "full" then
		status = "|cffff4040Plus de place dans la " .. bank .. "|r : " .. done .. " sur " .. total .. " objets déposés."
		UIErrorsFrame:AddMessage("Polypode Data : plus de place dans la " .. bank .. ".", 1, 0.1, 0.1)
	elseif reason == "closed" then
		status = "|cffff4040Banque fermée|r : " .. done .. " sur " .. total .. " objets déposés."
	elseif reason == "stopped" then
		status = "Arrêté : " .. done .. " sur " .. total .. " objets déposés."
	elseif skipped > 0 then
		status = done .. " sur " .. total .. " objets déposés dans la " .. bank .. " (" .. skipped .. " non déposés)."
	else
		status = "|cff40ff40Les " .. done .. " objets ont été déposés dans la " .. bank .. ".|r"
	end
	Notify()
end

local function NextEntry(counted)
	if counted then
		run.done = run.done + 1
	else
		run.skipped = run.skipped + 1
	end
	run.index = run.index + 1
	run.since = GetTime()
	Progress()
	Notify()
end

local function Step()
	if not run then
		return
	end
	local open = ns.OpenBanks()
	if not open[run.kind] or open.G and run.kind ~= "G" then
		return Finish("closed")
	end
	local entry = run.queue[run.index]
	if not entry then
		return Finish()
	end
	if CursorHasItem() then
		return -- le joueur tient un objet : on attend qu'il le pose
	end
	local info = Info(entry.bag, entry.slot)
	if not info or info.itemID ~= entry.itemID then
		-- Pile partie : déposée par nous, ou déplacée par le joueur (comptée à part).
		return NextEntry(entry.moved)
	end
	if info.isLocked then
		if GetTime() - run.since > STEP_TIMEOUT then
			NextEntry(false)
		end
		return
	end
	local target, amount = FindTarget(run.kind, entry.itemID, info.stackCount or 1)
	if not target then
		return Finish("full")
	end
	if amount < (info.stackCount or 1) then
		C_Container.SplitContainerItem(entry.bag, entry.slot, amount)
	else
		C_Container.PickupContainerItem(entry.bag, entry.slot)
	end
	if not CursorHasItem() then
		if GetTime() - run.since > STEP_TIMEOUT then
			NextEntry(false)
		end
		return
	end
	C_Container.PickupContainerItem(target.bag, target.slot)
	if CursorHasItem() then
		ClearCursor() -- refusé par la banque : l'objet retourne dans le sac
		return NextEntry(false)
	end
	entry.moved = true
	run.since = GetTime()
end

-- Lance le rangement dans la banque kind (ouverte, seule) : piles des sacs dont l'objet s'y
-- trouve déjà.
function ns.StartDeposit(kind)
	if run or not ns.CanDeposit(kind) then
		return
	end
	local inBank = {}
	for _, target in ipairs(BankSlots(kind)) do
		if target.itemID then
			inBank[target.itemID] = true
		end
	end
	local queue = {}
	for _, bag in ipairs(ns.BagIDs("B")) do
		for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
			local info = Info(bag, slot)
			if info and info.itemID and inBank[info.itemID] and Allowed(kind, bag, slot) then
				queue[#queue + 1] = { bag = bag, slot = slot, itemID = info.itemID }
			end
		end
	end
	if #queue == 0 then
		status = "Rien à ranger : aucun objet des sacs n'est déjà dans la " .. BANK_NAMES[kind] .. "."
		Notify()
		return
	end
	run = { kind = kind, queue = queue, index = 1, done = 0, skipped = 0, total = #queue, since = GetTime() }
	run.ticker = C_Timer.NewTicker(STEP_INTERVAL, Step)
	Progress()
	Notify()
end

function ns.StopDeposit()
	Finish("stopped")
end
