-- Polypode Data: Deposit — rangement dans les banques des objets des sacs qui s'y trouvent déjà

local _, ns = ...

-- Bouton « Ranger » de la fiche Dépôts (UI.lua) : chaque pile des sacs dont l'objet est déjà
-- dans une banque accessible (relue en direct) y est déposée, une à la fois ; un objet absent
-- des banques ouvertes ne bouge pas. Une seule banque ouverte à la fois (voir ns.OpenBanks) :
--   * banque du personnage (« K ») / de bataillon (« A ») : la banque du personnage si l'objet y
--     est, sinon celle de bataillon s'il y est et qu'elle l'accepte (objets liés refusés) ;
--   * banque de guilde (« G ») : onglets où l'on a le droit de déposer seulement.
-- Dans la banque choisie :
--   1. sur une pile incomplète du même objet (partage de la pile si elle ne tient pas entière) ;
--   2. sinon dans un emplacement libre d'un onglet qui contient déjà l'objet ;
--   3. sinon dans le premier emplacement libre de cette banque ; aucun : l'objet reste dans
--      les sacs, « plus de place » signalé à la fin (les suivants peuvent encore compléter
--      une pile existante).
-- Un déplacement = prendre l'objet (curseur) puis le poser ; le suivant attend que la pile se
-- déverrouille (réponse du serveur). Arrêt si la banque se ferme ou si une autre s'ouvre.
--
-- Banque de guilde : le jeu ne tient à jour que l'onglet affiché. Avant de déposer dans un
-- onglet, il devient l'onglet affiché (SetCurrentGuildBankTab), son contenu est redemandé au
-- serveur (QueryGuildBankTab) et on attend la réponse (GUILDBANKBAGSLOTS_CHANGED) ; après
-- chaque dépôt aussi. On ne pose ainsi jamais un objet sur un emplacement cru libre à tort.

local STEP_INTERVAL = 0.1 -- secondes entre deux vérifications
local STEP_TIMEOUT = 5 -- secondes d'attente au plus pour une pile (verrou, curseur)
local GUILD_WAIT = 3 -- secondes d'attente au plus d'une réponse de la banque de guilde
local GUILD_TAB_SLOTS = 98 -- emplacements d'un onglet de banque de guilde
local BANK_KINDS = { "K", "A" } -- ordre de priorité des banques de destination (hors guilde)

-- Rangement en cours : { queue, index, done, skipped, total, since, full, used, ticker,
-- guildWait, guildFresh, fullTabs = { ["itemID:onglet"] = true } } ; entrées de queue
-- { bag, slot, itemID, kind, moved }.
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
--   * chez un banquier : K et A, quel que soit l'onglet affiché dans la fenêtre de banque (les
--     deux banques sont lisibles et accessibles, comme avec un addon de sacs).
function ns.OpenBanks()
	local open = {}
	if ns.IsBankOpen() then
		if Interacting("AccountBanker") and not Interacting("Banker") and not Interacting("CharacterBanker") then
			open.A = true
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

-- BANQUE DE GUILDE : LECTURE ------------------------------------------------------------------

-- Onglets de la banque de guilde : { tab, canDeposit } pour chaque onglet visible.
local function GuildTabs()
	local tabs = {}
	if not (GetNumGuildBankTabs and GetGuildBankTabInfo) then
		return tabs
	end
	for tab = 1, GetNumGuildBankTabs() or 0 do
		local _, _, isViewable, canDeposit = GetGuildBankTabInfo(tab)
		if isViewable then
			tabs[#tabs + 1] = { tab = tab, canDeposit = canDeposit and true or false }
		end
	end
	return tabs
end

local function CanDepositInGuild()
	for _, info in ipairs(GuildTabs()) do
		if info.canDeposit then
			return true
		end
	end
	return false
end

-- Emplacement d'un onglet : itemID (nil = vide), nombre, verrouillé.
local function GuildSlot(tab, slot)
	local link = GetGuildBankItemLink(tab, slot)
	local itemID = link and tonumber(link:match("|Hitem:(%d+)"))
	local _, count, locked = GetGuildBankItemInfo(tab, slot)
	return itemID, tonumber(count) or 0, locked
end

-- Objets d'un onglet : { [itemID] = true }. Seul l'onglet affiché est lisible en direct ; pour
-- les autres, le relevé fait à leur réception pendant la visite (Data.lua) complète la lecture.
local function GuildTabItems(tab)
	local items = {}
	for slot = 1, GUILD_TAB_SLOTS do
		local itemID = GuildSlot(tab, slot)
		if itemID then
			items[itemID] = true
		end
	end
	for key in pairs(ns.GetGuildTabItems and ns.GetGuildTabItems(tab) or {}) do
		local itemID = tonumber(tostring(key):match("^i(%d+)$"))
		if itemID then
			items[itemID] = true
		end
	end
	return items
end

-- Rangement possible maintenant : true, ou false et la raison.
function ns.CanDeposit()
	local open = ns.OpenBanks()
	if open.G and (open.K or open.A) then
		return false, "Une seule banque doit être ouverte : personnage, bataillon ou guilde."
	elseif open.G and not CanDepositInGuild() then
		return false, "Vous n'avez le droit de déposer dans aucun onglet de cette banque de guilde."
	elseif not (open.K or open.A or open.G) then
		return false, "Ouvrez la banque du personnage, la banque de bataillon ou la banque de guilde "
			.. "(une seule banque ouverte à la fois)."
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

-- Emplacements d'une banque (K ou A), dans l'ordre des onglets : { bag, slot, itemID, count,
-- locked }.
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

-- Objet autorisé dans cette banque (objets liés refusés en bataillon et en guilde...) ;
-- inconnu = oui. Guilde : C_Bank.IsItemAllowedInBankType n'y répond pas (tout refusé) ; on
-- écarte les objets liés et liés au bataillon jusqu'à équipement, comme Baganator.
local BANK_TYPE_NAMES = { K = "Character", A = "Account" }

local function Allowed(kind, bag, slot, info)
	if kind == "G" then
		if info.isBound then
			return false
		end
		local ok, warbound = pcall(function()
			return C_Item.IsItemBindToAccountUntilEquip and info.hyperlink
				and C_Item.IsItemBindToAccountUntilEquip(info.hyperlink)
		end)
		return not (ok and warbound)
	end
	local bankType = Enum.BankType and Enum.BankType[BANK_TYPE_NAMES[kind]]
	if not (bankType and C_Bank and C_Bank.IsItemAllowedInBankType and ItemLocation) then
		return true
	end
	local ok, allowed = pcall(C_Bank.IsItemAllowedInBankType, bankType, ItemLocation:CreateFromBagAndSlot(bag, slot))
	return not ok or allowed
end

-- Place pour count exemplaires de itemID parmi slots ({ itemID, count, locked, group }) :
-- pile incomplète du même objet, sinon emplacement libre d'un groupe (sac, onglet) qui contient
-- l'objet, sinon premier libre. Renvoie l'emplacement et le nombre qui y tient, ou nil.
local function PickSlot(slots, itemID, count)
	local maxStack = MaxStack(itemID)
	local groupsWithItem = {}
	for _, target in ipairs(slots) do
		if target.itemID == itemID then
			groupsWithItem[target.group] = true
			if not target.locked and target.count < maxStack then
				return target, math.min(count, maxStack - target.count)
			end
		end
	end
	local anyFree
	for _, target in ipairs(slots) do
		if not target.itemID and not target.locked then
			if groupsWithItem[target.group] then
				return target, count
			end
			anyFree = anyFree or target
		end
	end
	return anyFree, anyFree and count
end

local function FindBankTarget(kind, itemID, count)
	local slots = BankSlots(kind)
	for _, target in ipairs(slots) do
		target.group = target.bag
	end
	return PickSlot(slots, itemID, count)
end

-- Place dans un onglet de guilde (à jour : onglet affiché, contenu reçu).
local function FindGuildTarget(tab, itemID, count)
	local slots = {}
	for slot = 1, GUILD_TAB_SLOTS do
		local slotItem, slotCount, locked = GuildSlot(tab, slot)
		slots[slot] = { tab = tab, slot = slot, itemID = slotItem, count = slotCount, locked = locked, group = tab }
	end
	return PickSlot(slots, itemID, count)
end

-- Onglets de guilde où déposer itemID, dans l'ordre : ceux qui contiennent l'objet, puis les
-- autres (droit de dépôt seulement, onglets déjà pleins exclus).
local function GuildCandidateTabs(itemID)
	local withItem, others = {}, {}
	for _, info in ipairs(GuildTabs()) do
		if info.canDeposit and not run.fullTabs[itemID .. ":" .. info.tab] then
			if GuildTabItems(info.tab)[itemID] then
				withItem[#withItem + 1] = info.tab
			else
				others[#others + 1] = info.tab
			end
		end
	end
	for _, tab in ipairs(others) do
		withItem[#withItem + 1] = tab
	end
	return withItem
end

-- DÉROULEMENT --------------------------------------------------------------------------------

local function Progress()
	status = "Rangement : " .. run.done .. " sur " .. run.total
end

-- « la banque », « la banque de bataillon » ou « la banque et la banque de bataillon ».
local function BanksText(set)
	local names = {}
	for _, kind in ipairs({ "K", "A", "G" }) do
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

-- Prend la pile (ou amount exemplaires) de entry et la pose avec place() ; faux si refusé.
local function Move(entry, info, amount, place)
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
	place()
	if CursorHasItem() then
		ClearCursor() -- refusé par la banque : l'objet retourne dans le sac
		return NextEntry(false)
	end
	entry.moved = true
	run.since = GetTime()
	return true
end

-- Dépôt en banque de guilde d'une pile (voir en tête de fichier).
local function GuildStep(entry, info)
	local count = info.stackCount or 1
	for _, tab in ipairs(GuildCandidateTabs(entry.itemID)) do
		if GetCurrentGuildBankTab() ~= tab or run.guildFresh ~= tab then
			-- Onglet affiché puis relu : on attend la réponse du serveur avant d'y déposer.
			SetCurrentGuildBankTab(tab)
			QueryGuildBankTab(tab)
			run.guildFresh = tab
			run.guildWait = GetTime()
			return
		end
		local target, amount = FindGuildTarget(tab, entry.itemID, count)
		if target then
			if Move(entry, info, amount, function()
				PickupGuildBankItem(tab, target.slot)
			end) then
				run.guildWait = GetTime()
			end
			return
		end
		run.fullTabs[entry.itemID .. ":" .. tab] = true -- pas de place pour cet objet : onglet suivant
		return
	end
	run.full.G = true
	NextEntry(false)
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
	if (open.G and (open.K or open.A)) or not open[entry.kind] then
		return Finish("closed")
	end
	if run.guildWait and GetTime() - run.guildWait < GUILD_WAIT then
		return -- réponse de la banque de guilde attendue
	end
	run.guildWait = nil
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
	if entry.kind == "G" then
		return GuildStep(entry, info)
	end
	local target, amount = FindBankTarget(entry.kind, entry.itemID, info.stackCount or 1)
	if not target then
		run.full[entry.kind] = true
		return NextEntry(false)
	end
	Move(entry, info, amount, function()
		C_Container.PickupContainerItem(target.bag, target.slot)
	end)
end

-- Lance le rangement : piles des sacs dont l'objet est déjà dans une banque accessible (voir
-- en tête de fichier pour le choix de la banque).
function ns.StartDeposit()
	if run or not ns.CanDeposit() then
		return
	end
	local open = ns.OpenBanks()
	local kinds = open.G and { "G" } or BANK_KINDS
	local inBank = {} -- [kind] = { [itemID] = true }
	for _, kind in ipairs(kinds) do
		if open[kind] then
			inBank[kind] = {}
			if kind == "G" then
				for _, info in ipairs(GuildTabs()) do
					for itemID in pairs(GuildTabItems(info.tab)) do
						inBank.G[itemID] = true
					end
				end
			else
				for _, target in ipairs(BankSlots(kind)) do
					if target.itemID then
						inBank[kind][target.itemID] = true
					end
				end
			end
		end
	end
	local queue = {}
	for _, bag in ipairs(ns.BagIDs("B")) do
		for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
			local info = Info(bag, slot)
			if info and info.itemID then
				for _, kind in ipairs(kinds) do
					if inBank[kind] and inBank[kind][info.itemID] and Allowed(kind, bag, slot, info) then
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
		-- Aucun objet éligible : dit à l'écran aussi (le bouton « Ranger » de l'en-tête et le clic
		-- droit sur « Data » n'ont pas de ligne d'état).
		status = "Tous les objets ont déjà été déposés dans " .. BanksText(accessible) .. "."
		if UIErrorsFrame then
			UIErrorsFrame:AddMessage(status, 1, 0.82, 0)
		end
		Notify()
		return
	end
	run = { queue = queue, index = 1, done = 0, skipped = 0, total = #queue, since = GetTime(),
		full = {}, used = {}, fullTabs = {} }
	run.ticker = C_Timer.NewTicker(STEP_INTERVAL, Step)
	Progress()
	Notify()
end

function ns.StopDeposit()
	Finish("stopped")
end

-- Contenu d'un onglet de guilde reçu : l'attente est levée.
local events = CreateFrame("Frame")
if not (C_EventUtils and C_EventUtils.IsEventValid) or C_EventUtils.IsEventValid("GUILDBANKBAGSLOTS_CHANGED") then
	events:RegisterEvent("GUILDBANKBAGSLOTS_CHANGED")
end
events:SetScript("OnEvent", function()
	if run and run.guildWait then
		run.guildWait = nil
	end
end)
