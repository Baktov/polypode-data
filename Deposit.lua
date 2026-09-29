-- Polypode Data: Deposit — rangement dans les banques des objets des sacs qui s'y trouvent déjà

local _, ns = ...

-- Bouton « Ranger » de la fiche Dépôts (UI.lua) : chaque pile des sacs dont l'objet est déjà
-- dans une banque accessible (relue en direct) y est déposée, une à la fois. Destination :
-- banque du personnage (« K ») si l'objet y est, sinon banque de bataillon (« A ») s'il y est
-- et qu'elle l'accepte (objets liés au personnage refusés) ; un objet absent des banques ne
-- bouge pas. Dans la banque choisie :
--   1. sur une pile incomplète du même objet (SplitContainerItem si elle ne tient pas entière) ;
--   2. sinon dans un emplacement libre d'un onglet qui contient déjà l'objet ;
--   3. sinon dans le premier emplacement libre de cette banque ; aucun : « plus de place »,
--      les objets suivants pour cette banque sont laissés dans les sacs.
-- Un déplacement = prendre l'objet (curseur) puis le poser ; le suivant attend que la pile se
-- déverrouille (réponse du serveur). Arrêt si la banque se ferme ou si une autre s'ouvre.
-- La banque de guilde n'est pas encore gérée.

local STEP_INTERVAL = 0.1 -- secondes entre deux vérifications
local STEP_TIMEOUT = 5 -- secondes d'attente au plus pour une pile (verrou, curseur)
local KINDS = { "K", "A" } -- ordre de priorité des banques de destination

-- Rangement en cours : { queue, index, done, skipped, total, since, full, used, ticker } ;
-- entrées de queue { bag, slot, itemID, kind, moved }.
local run
local status -- texte d'avancement, affiché dans la fiche Dépôts

local BANK_NAMES = { K = "banque", A = "banque de bataillon", G = "banque de guilde" }

local function Notify()
	if ns.UpdateDepositControls then
		ns.UpdateDepositControls()
	end
end

-- Vrai si le personnage parle à un PNJ de ce type (Enum.PlayerInteractionType[name]).
local function Interacting(name)
	local interactionType = Enum.PlayerInteractionType and Enum.PlayerInteractionType[name]
	return interactionType ~= nil and C_PlayerInteractionManager ~= nil
		and C_PlayerInteractionManager.IsInteractingWithNpcOfType ~= nil
		and C_PlayerInteractionManager.IsInteractingWithNpcOfType(interactionType) == true
end

-- Banques accessibles maintenant : K (personnage), A (bataillon), G (guilde).
--   * banque de bataillon seule (coffre de bataillon, accès à distance : PNJ AccountBanker) : A ;
--   * fenêtre de banque de Blizzard : l'onglet affiché seulement (K ou A) ;
--   * fenêtre remplacée par un addon de sacs (Baganator...) : onglet illisible, K et A.
function ns.OpenBanks()
	local open = {}
	if ns.IsBankOpen() then
		if Interacting("AccountBanker") and not Interacting("Banker") and not Interacting("CharacterBanker") then
			open.A = true
		elseif BankFrame and BankFrame:IsShown() and BankFrame.GetActiveBankType then
			local ok, bankType = pcall(BankFrame.GetActiveBankType, BankFrame)
			if ok and bankType and Enum.BankType and bankType == Enum.BankType.Account then
				open.A = true
			else
				open.K = true
			end
		else
			open.K = true
			open.A = Enum.BankType ~= nil and Enum.BagIndex ~= nil and Enum.BagIndex.AccountBankTab_1 ~= nil
		end
	end
	if ns.IsGuildBankOpen() then
		open.G = true
	end
	return open
end

-- Rangement possible maintenant : true, ou false et la raison.
function ns.CanDeposit()
	local open = ns.OpenBanks()
	if open.G and (open.K or open.A) then
		return false, "Une seule banque doit être ouverte : personnage, bataillon ou guilde."
	elseif open.G then
		return false, "Le rangement dans la banque de guilde n'est pas encore possible : ouvrez la banque du "
			.. "personnage ou la banque de bataillon."
	elseif not (open.K or open.A) then
		return false, "Ouvrez la banque du personnage ou la banque de bataillon (une seule banque ouverte : "
			.. "personnage, bataillon ou guilde)."
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

-- Emplacements d'une banque, dans l'ordre des onglets : { bag, slot, itemID, count, locked }.
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

-- Objet autorisé dans cette banque (objets liés au personnage refusés en bataillon...) ;
-- inconnu = oui.
local function Allowed(kind, bag, slot)
	if not (C_Bank and C_Bank.IsItemAllowedInBankType and Enum.BankType and ItemLocation) then
		return true
	end
	local bankType = kind == "A" and Enum.BankType.Account or Enum.BankType.Character
	local ok, allowed = pcall(C_Bank.IsItemAllowedInBankType, bankType, ItemLocation:CreateFromBagAndSlot(bag, slot))
	return not ok or allowed
end

-- Où poser count exemplaires de itemID dans la banque kind : l'emplacement et le nombre qui y
-- tient, ou nil.
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

-- « la banque », « la banque de bataillon » ou « la banque et la banque de bataillon ».
local function BanksText(set)
	local names = {}
	for _, kind in ipairs(KINDS) do
		if set[kind] then
			names[#names + 1] = "la " .. BANK_NAMES[kind]
		end
	end
	return table.concat(names, " et ")
end

-- Fin du rangement ; reason : nil (terminé), "closed" ou "stopped".
local function Finish(reason)
	if not run then
		return
	end
	run.ticker:Cancel()
	local done, total, skipped, full, used = run.done, run.total, run.skipped, run.full, run.used
	run = nil
	local counts = done .. " sur " .. total .. " objets déposés"
	if reason == "closed" then
		status = "|cffff4040Banque fermée|r : " .. counts .. "."
	elseif reason == "stopped" then
		status = "Arrêté : " .. counts .. "."
	elseif next(full) then
		status = "|cffff4040Plus de place dans " .. BanksText(full) .. "|r : " .. counts .. "."
		UIErrorsFrame:AddMessage("Polypode Data : plus de place dans " .. BanksText(full) .. ".", 1, 0.1, 0.1)
	elseif skipped > 0 then
		status = counts .. (next(used) and (" dans " .. BanksText(used)) or "") .. " (" .. skipped .. " non déposés)."
	else
		status = "|cff40ff40Les " .. done .. " objets ont été déposés dans " .. BanksText(used) .. ".|r"
	end
	Notify()
end

local function NextEntry(counted)
	local entry = run.queue[run.index]
	if counted then
		run.done = run.done + 1
		run.used[entry.kind] = true
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
	local entry = run.queue[run.index]
	if not entry then
		return Finish()
	end
	local open = ns.OpenBanks()
	if open.G or not open[entry.kind] then
		return Finish("closed")
	end
	if CursorHasItem() then
		return -- le joueur tient un objet : on attend qu'il le pose
	end
	local info = Info(entry.bag, entry.slot)
	if not info or info.itemID ~= entry.itemID then
		-- Pile partie : déposée par nous, ou déplacée par le joueur (comptée à part).
		return NextEntry(entry.moved)
	end
	if run.full[entry.kind] then
		return NextEntry(false) -- banque pleine : l'objet reste dans les sacs
	end
	if info.isLocked then
		if GetTime() - run.since > STEP_TIMEOUT then
			NextEntry(false)
		end
		return
	end
	local target, amount = FindTarget(entry.kind, entry.itemID, info.stackCount or 1)
	if not target then
		run.full[entry.kind] = true
		return NextEntry(false)
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

-- Lance le rangement : piles des sacs dont l'objet est déjà dans une banque accessible (voir
-- en tête de fichier pour le choix de la banque).
function ns.StartDeposit()
	if run or not ns.CanDeposit() then
		return
	end
	local open = ns.OpenBanks()
	local inBank = {} -- [kind] = { [itemID] = true }
	for _, kind in ipairs(KINDS) do
		if open[kind] then
			inBank[kind] = {}
			for _, target in ipairs(BankSlots(kind)) do
				if target.itemID then
					inBank[kind][target.itemID] = true
				end
			end
		end
	end
	local queue = {}
	for _, bag in ipairs(ns.BagIDs("B")) do
		for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
			local info = Info(bag, slot)
			if info and info.itemID then
				for _, kind in ipairs(KINDS) do
					if inBank[kind] and inBank[kind][info.itemID] and Allowed(kind, bag, slot) then
						queue[#queue + 1] = { bag = bag, slot = slot, itemID = info.itemID, kind = kind }
						break
					end
				end
			end
		end
	end
	if #queue == 0 then
		local accessible = {}
		for kind in pairs(inBank) do
			accessible[kind] = true
		end
		status = "Rien à ranger : aucun objet des sacs n'est déjà dans " .. BanksText(accessible) .. "."
		Notify()
		return
	end
	run = { queue = queue, index = 1, done = 0, skipped = 0, total = #queue, since = GetTime(),
		full = {}, used = {} }
	run.ticker = C_Timer.NewTicker(STEP_INTERVAL, Step)
	Progress()
	Notify()
end

function ns.StopDeposit()
	Finish("stopped")
end
