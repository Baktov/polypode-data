-- Polypode Data: Data — relevé des données « fixes » de chaque personnage, sauvegarde et synchro

local _, ns = ...
local P = Polypode -- dépendance obligatoire (## Dependencies: Polypode), chargée avant nous

-- Addon compagnon de Polypode, dans l'esprit de DataStore (Altoholic) ou WoWthing : les données
-- durables de chaque personnage (identité, or, métiers, équipement, sacs et banques), gardées dans
-- PolypodeDataDB (fichier de compte) et échangées entre les clients connectés.
--
-- Sections (une table { clé = valeur } chacune ; valeurs sans « , : = ») :
--   I identité : c classe (fichier), r race, l niveau, i niveau d'objet équipé, s spécialisation,
--     ap points de haut fait,
--     f faction, g or (pièces de cuivre), z zone, p temps de jeu (s) relevé à la date pa ;
--   T métiers : p1 / p2 principaux, s1 / s2 / s3 archéologie, pêche, cuisine =
--     « skillLine/niveau/max/icône/nom » ;
--   E équipement : <emplacement 1-19> = « niveau d'objet@chaîne d'objet » (la chaîne du lien,
--     « itemID:enchantement:gemmes...:bonus... », sans « item: » : enchantement, gemmes et
--     améliorations compris ; les « : » passent, seuls « , » et « = » séparent) ;
--   B sacs, K banque du personnage, A banque de bataillon : i<itemID> = nombre.
--   R recettes apprises (fenêtre du métier ouverte) : r<recipeID> = métier d'extension,
--     c<métier d'extension> = « métier de base/extension » (voir RECETTES APPRISES) ;
--   T contient aussi g<p1...> = emplacements des objets du métier (section E, 20 et plus).
--   G banque de guilde (relevée par ce personnage) : n nom de la guilde, m or (cuivre), i<itemID>.
-- K, A et G ne sont lisibles que banque ouverte : sinon les dernières connues restent. Le nom de
-- la guilde du personnage est dans I (gu).
--
-- Sauvegarde : PolypodeDataDB.chars[clé] = { s = { [section] = données }, t = { [section] =
-- version }, seen = dernière date où le personnage a été vu connecté }. Version = heure serveur
-- du dernier changement, strictement croissante.
--
-- Synchro (le personnage joué fait foi pour lui-même ; expéditeur vérifié par P.IsSender) :
--   DATAV:token:clé:I=version,T=version,... — versions de ses sections, envoyées à chaque
--     rencontre (P.RegisterPeerCallback) ;
--   DATAREQ:token:clé:I,B,... — demande des sections plus récentes que les siennes ;
--   DATA:token:clé:section:flag:version:k=v,k=v,... — une section (flag N premier fragment,
--     + suite), en réponse à DATAREQ, et aux clients connectés 10 s après un changement.

ns.SECTIONS = { "I", "T", "E", "B", "K", "A", "G", "R" }

local SCAN_DELAY = 2 -- secondes : regroupe les rafales d'événements (sacs, or)
local SEND_DELAY = 10 -- secondes : envoi des sections modifiées aux clients connectés

local store -- PolypodeDataDB.chars
local bankOpen = false
local tradeSkillOpen = false -- fenêtre d'un métier ouverte (TRADE_SKILL_SHOW / CLOSE)
local guildBankOpen = false
local GUILD_TAB_SLOTS = 98 -- emplacements d'un onglet de banque de guilde
local guildTabs = {} -- [onglet] = { i<itemID> = nombre }, onglets relevés pendant cette visite
local queriedTabs = {} -- onglets demandés au serveur à l'ouverture
local played, playedAt -- temps de jeu du personnage joué (TIME_PLAYED_MSG) et date du relevé

-- Texte sûr dans un message (séparateurs retirés).
local function Clean(text)
	return (tostring(text or ""):gsub("[,:=/]", " "))
end

ns.Clean = Clean

-- Version suivante d'une donnée : heure serveur, strictement croissante.
local function NextVersion(old)
	return math.max(GetServerTime(), (tonumber(old) or 0) + 1)
end

-- LECTURE DU PERSONNAGE JOUÉ ----------------------------------------------------------------

local function ReadIdentity()
	local data = {}
	local _, classFile = UnitClass("player")
	data.c = classFile
	data.r = Clean(UnitRace("player"))
	data.l = UnitLevel("player")
	if GetAverageItemLevel then
		local _, equipped = GetAverageItemLevel()
		data.i = equipped and math.floor(equipped) or nil
	end
	if GetSpecialization and GetSpecializationInfo then
		local index = GetSpecialization()
		local name = index and select(2, GetSpecializationInfo(index))
		data.s = name and Clean(name) or nil
	end
	local faction, factionName = UnitFactionGroup("player")
	data.f = faction and Clean(factionName or faction) or nil
	data.g = GetMoney()
	data.z = GetRealZoneText and Clean(GetRealZoneText()) or nil
	local guild = GetGuildInfo and GetGuildInfo("player")
	data.gu = guild and Clean(guild) or nil
	data.p, data.pa = played, playedAt
	-- Points de haut fait (communs aux personnages d'un même compte).
	local okPoints, points = pcall(GetTotalAchievementPoints)
	data.ap = okPoints and tonumber(points) or nil
	return data
end

-- Métiers : GetProfessions renvoie les index des deux métiers principaux, de l'archéologie, de
-- la pêche et de la cuisine (nil si absent).
local PROFESSION_KEYS = { "p1", "p2", "s1", "s2", "s3" }

local function ReadProfessions()
	local data = {}
	if not (GetProfessions and GetProfessionInfo) then
		return data
	end
	local indexes = { GetProfessions() }
	for i, key in ipairs(PROFESSION_KEYS) do
		local index = indexes[i]
		if index then
			local name, icon, level, maxLevel, _, _, skillLine = GetProfessionInfo(index)
			if name then
				data[key] = table.concat({ skillLine or 0, level or 0, maxLevel or 0, icon or 0, Clean(name) }, "/")
				-- g<clé> = emplacements de ses objets (outil, accessoires), « 20/21/22 » : propres au
				-- personnage (premier / second métier principal), lus dans la section E.
				local ui = C_TradeSkillUI or {}
				local okInfo, info = pcall(ui.GetProfessionInfoBySkillLineID, skillLine)
				local okSlots, slots = pcall(ui.GetProfessionSlots, okInfo and info and info.profession)
				if okSlots and type(slots) == "table" and #slots > 0 then
					data["g" .. key] = table.concat(slots, "/")
				end
			end
		end
	end
	return data
end

local function ReadEquipment()
	local data = {}
	local slots = {}
	for slot = 1, 19 do
		slots[#slots + 1] = slot
	end
	-- Objets de métier (outils, accessoires) : emplacements 20 et plus.
	local okProf, profSlots = pcall(C_TradeSkillUI and C_TradeSkillUI.GetProfessionInventorySlots)
	for _, slot in ipairs(okProf and type(profSlots) == "table" and profSlots or {}) do
		slots[#slots + 1] = slot
	end
	for _, slot in ipairs(slots) do
		local itemID = GetInventoryItemID("player", slot)
		if itemID then
			local link = GetInventoryItemLink("player", slot)
			local level = link and C_Item and C_Item.GetDetailedItemLevelInfo and C_Item.GetDetailedItemLevelInfo(link)
			local itemString = link and link:match("|Hitem:([^|]+)|h")
			data[tostring(slot)] = (level or 0) .. "@" .. (itemString or itemID)
		end
	end
	return data
end

-- Genre d'un sac d'après son nom dans Enum.BagIndex : B sacs, K banque, A bataillon.
local function BagKind(name)
	if name == "Backpack" or name == "ReagentBag" or name:match("^Bag_%d+$") then
		return "B"
	elseif name:match("^CharacterBankTab_%d+$") or name == "Bank" or name:match("^BankBag_%d+$")
		or name == "Reagentbank" then
		return "K"
	elseif name:match("^AccountBankTab_%d+$") then
		return "A"
	end
end

local function BagIDs(kind)
	local ids = {}
	if Enum and Enum.BagIndex then
		for name, id in pairs(Enum.BagIndex) do
			if type(name) == "string" and BagKind(name) == kind then
				ids[#ids + 1] = id
			end
		end
	elseif kind == "B" then
		for id = 0, 4 do
			ids[#ids + 1] = id
		end
	end
	table.sort(ids) -- ordre des sacs / onglets
	return ids
end

ns.BagIDs = BagIDs

-- Banque (du personnage ou de bataillon, même fenêtre) / banque de guilde ouverte.
function ns.IsBankOpen()
	return bankOpen
end

function ns.IsGuildBankOpen()
	return guildBankOpen
end

-- Contenu des sacs de kind, ou nil si aucun emplacement n'est lisible (banque pas encore chargée :
-- un relevé vide remplacerait le bon). Banque de bataillon : a = compte Battle.net (token), pour
-- ne garder qu'une copie par compte (voir BANQUES PARTAGÉES).
local function ReadContainers(kind)
	local data = {}
	if not (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemInfo) then
		return data
	end
	local slots = 0
	for _, bag in ipairs(BagIDs(kind)) do
		slots = slots + (C_Container.GetContainerNumSlots(bag) or 0)
	end
	if slots == 0 and kind ~= "B" then
		return nil
	end
	if kind == "A" then
		data.a = P.GetTeamToken and P.GetTeamToken() or nil
	end
	for _, bag in ipairs(BagIDs(kind)) do
		for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and info.itemID then
				local key = "i" .. info.itemID
				data[key] = (data[key] or 0) + (info.stackCount or 1)
			end
		end
	end
	return data
end

-- RECETTES APPRISES (section R) : lisibles seulement fenêtre du métier ouverte, pour un métier du
-- personnage joué (pas un lien de recettes, une guilde ni une commande d'artisanat). Clés :
--   r<recipeID> = métier d'extension de la recette (« Alchimie de Khaz Algar » : professionID) ;
--   c<métier d'extension> = « métier de base/nom de l'extension » (base = skillLine de la section T).
-- Les métiers d'extension relus remplacent leurs anciennes entrées ; ceux des autres métiers (ou
-- non relus) sont gardés. Nom et icône d'une recette : ceux de son sort (recipeID = spellID).
local function ReadRecipes()
	local ui = C_TradeSkillUI
	if not (tradeSkillOpen and ui and ui.GetBaseProfessionInfo and ui.GetAllRecipeIDs and ui.GetRecipeInfo
		and ui.GetProfessionInfoByRecipeID) then
		return nil
	end
	local function Is(fn)
		return fn and select(2, pcall(fn)) == true
	end
	if Is(ui.IsTradeSkillLinked) or Is(ui.IsTradeSkillGuild) or Is(ui.IsTradeSkillGuildMember)
		or Is(ui.IsNPCCrafting) or Is(ui.IsRuneforging) then
		return nil
	end
	local base = ui.GetBaseProfessionInfo()
	local baseLine = base and base.professionID
	local ids = ui.GetAllRecipeIDs()
	if not baseLine or baseLine == 0 or type(ids) ~= "table" or #ids == 0 then
		return nil
	end
	local fresh, lines = {}, {}
	for _, recipeID in ipairs(ids) do
		local info = ui.GetRecipeInfo(recipeID)
		if info and info.learned then
			local prof = ui.GetProfessionInfoByRecipeID(recipeID)
			local child = prof and prof.professionID
			if child and child ~= 0 then
				fresh["r" .. recipeID] = child
				if not lines[child] then
					lines[child] = true
					local label = prof.expansionName ~= "" and prof.expansionName or prof.professionName
					fresh["c" .. child] = baseLine .. "/" .. Clean(label)
				end
			end
		end
	end
	if not next(lines) then
		return nil -- rien d'appris lisible (données pas encore chargées) : on garde l'ancien
	end
	local own = store and store[P.GetCharKey()]
	for key, value in pairs(own and own.s.R or {}) do
		local child = key:match("^c(%d+)$") or (key:match("^r%d+$") and value)
		if child and not lines[tonumber(child)] then
			fresh[key] = value
		end
	end
	return fresh
end

-- Lecteurs par section ; nil = rien de lisible maintenant (banque fermée), on garde l'ancien.
local READERS = {
	I = ReadIdentity,
	T = ReadProfessions,
	E = ReadEquipment,
	B = function()
		return ReadContainers("B")
	end,
	K = function()
		return bankOpen and ReadContainers("K") or nil
	end,
	A = function()
		return bankOpen and ReadContainers("A") or nil
	end,
	G = function()
		return ns.ReadGuildBank()
	end,
	R = ReadRecipes,
}

-- BANQUE DE GUILDE : à l'ouverture, tous les onglets visibles sont demandés au serveur
-- (QueryGuildBankTab) ; chaque onglet reçu (GUILDBANKBAGSLOTS_CHANGED) est relu. La section G
-- réunit les onglets relevés pendant la visite (nil tant qu'aucun ne l'est : on garde l'ancienne).
local function OpenGuildBank()
	guildBankOpen = true
	wipe(guildTabs)
	wipe(queriedTabs)
	if not (GetNumGuildBankTabs and GetGuildBankTabInfo and QueryGuildBankTab) then
		return
	end
	for tab = 1, GetNumGuildBankTabs() or 0 do
		local _, _, isViewable = GetGuildBankTabInfo(tab)
		if isViewable then
			queriedTabs[tab] = true
			QueryGuildBankTab(tab)
		end
	end
end

local function ScanGuildTabs()
	if not (GetGuildBankItemLink and GetGuildBankItemInfo) then
		return
	end
	for tab in pairs(queriedTabs) do
		local items, any = {}, false
		for slot = 1, GUILD_TAB_SLOTS do
			local link = GetGuildBankItemLink(tab, slot)
			local itemID = link and tonumber(link:match("|Hitem:(%d+)"))
			if itemID then
				local _, count = GetGuildBankItemInfo(tab, slot)
				local key = "i" .. itemID
				items[key] = (items[key] or 0) + (count or 1)
				any = true
			end
		end
		-- Onglet vide ou pas encore reçu : on ne remplace qu'un onglet déjà lu par du contenu.
		if any or guildTabs[tab] == nil then
			guildTabs[tab] = any and items or guildTabs[tab]
		end
	end
end

-- Objets d'un onglet relevés pendant la visite ({ i<itemID> = nombre }), ou nil : le jeu ne
-- garde lisible que l'onglet affiché, les autres ne le sont qu'à leur réception (Deposit.lua).
function ns.GetGuildTabItems(tab)
	return guildBankOpen and guildTabs[tab] or nil
end

function ns.ReadGuildBank()
	if not guildBankOpen then
		return nil
	end
	ScanGuildTabs()
	local data = {}
	local any = false
	for _, items in pairs(guildTabs) do
		for key, count in pairs(items) do
			data[key] = (data[key] or 0) + count
			any = true
		end
	end
	if not any then
		return nil
	end
	local guild = GetGuildInfo and GetGuildInfo("player")
	data.n = guild and Clean(guild) or nil
	data.m = GetGuildBankMoney and GetGuildBankMoney() or nil
	return data
end

-- SAUVEGARDE -------------------------------------------------------------------------------

-- Liste triée « k=v » d'une section (valeurs vides omises).
local function SectionItems(data)
	local items = {}
	for k, v in pairs(data or {}) do
		if v ~= nil and v ~= "" then
			items[#items + 1] = k .. "=" .. tostring(v)
		end
	end
	table.sort(items)
	return items
end

local function Entry(key, create)
	local entry = store and store[key]
	if not entry and create and store then
		entry = { s = {}, t = {} }
		store[key] = entry
	end
	return entry
end

-- Données enregistrées d'un personnage (le personnage joué y est tenu à jour), ou nil.
function ns.GetEntry(key)
	return Entry(key)
end

-- Clés de tous les personnages connus.
function ns.GetKeys()
	local keys = {}
	for key in pairs(store or {}) do
		keys[key] = true
	end
	return keys
end

-- Oublie un personnage (jamais le personnage joué).
function ns.Forget(key)
	if store and key ~= P.GetCharKey() then
		store[key] = nil
	end
end

-- Personnage supprimé dans Polypode (Maj + clic dans « Personnages disponibles », ou sur un
-- autre client) : ses données relevées sont oubliées ici aussi (Polypode 0.53.0).
if P.RegisterCharacterData then
	P.RegisterCharacterData({
		name = "Polypode Data",
		describe = function(key)
			if store and store[key] then
				return "niveau, or, métiers, équipement, sacs et banques relevés"
			end
		end,
		remove = function(key)
			ns.Forget(key)
			if ns.Refresh then
				ns.Refresh()
			end
		end,
	})
end

-- BANQUES PARTAGÉES ----------------------------------------------------------------------------
-- La banque de bataillon appartient à un compte Battle.net, la banque de guilde à une guilde :
-- plusieurs personnages en ont un relevé (le leur, ou reçu). Une seule copie est gardée par
-- compte / guilde, la plus récente ; les autres sont effacées (leur version reste notée, pour ne
-- pas redemander cette copie ancienne à la synchro). Jamais cumulées.

-- Compte Battle.net d'un personnage (token de Polypode ; personnage joué : le sien).
function ns.AccountOf(key)
	if key == P.GetCharKey() then
		return P.GetTeamToken and P.GetTeamToken() or key
	end
	local roster = P.db.roster[key]
	return roster and roster.token or key
end

-- Propriétaire d'une section partagée d'un personnage : compte (A, noté dans le relevé depuis
-- 1.9.2, sinon d'après le roster) ou guilde (G) ; nil pour les autres sections.
function ns.SharedOwner(key, section)
	local entry = Entry(key)
	local data = entry and entry.s[section]
	if section == "A" then
		return data and (data.a or ns.AccountOf(key)) or nil
	elseif section == "G" then
		return data and data.n or nil
	end
end

-- Garde la copie la plus récente de la section partagée de ce propriétaire.
local function KeepNewestShared(section, owner)
	if not (store and owner) then
		return
	end
	local newestKey, newestVersion
	for key, entry in pairs(store) do
		if entry.s[section] and ns.SharedOwner(key, section) == owner then
			local version = tonumber(entry.t[section]) or 0
			if not newestVersion or version > newestVersion then
				newestKey, newestVersion = key, version
			end
		end
	end
	for key, entry in pairs(store) do
		if key ~= newestKey and entry.s[section] and ns.SharedOwner(key, section) == owner then
			entry.s[section] = nil
		end
	end
end

-- REMISE À ZÉRO (clic droit sur les icônes sacs / banques de la fenêtre, UI.lua) : efface le
-- relevé du personnage joué (B sacs, K banque), de la banque de bataillon de son compte (A, toutes
-- les copies) ou de la banque de guilde de sa guilde (G, toutes les copies), sur ce client. Le
-- prochain relevé l'enregistre de nouveau (sacs : tout de suite ; banques : à leur réouverture).
local lastText -- défini dans SYNCHRO (texte de la dernière version de chaque section)
local ScheduleUpdate -- défini dans SYNCHRO

function ns.ResetSection(section)
	local key = P.GetCharKey()
	local owner
	if section == "A" then
		owner = ns.AccountOf(key)
	elseif section == "G" then
		local own = Entry(key)
		owner = own and own.s.I and own.s.I.gu
	end
	for otherKey, entry in pairs(store or {}) do
		local match
		if section == "A" or section == "G" then
			match = owner and ns.SharedOwner(otherKey, section) == owner
		else
			match = otherKey == key
		end
		if match then
			entry.s[section] = nil
		end
	end
	if lastText then
		lastText[section] = nil -- le prochain relevé est enregistré même identique
	end
	if section == "B" and ScheduleUpdate then
		ScheduleUpdate()
	end
end

-- Toutes les copies en double (nettoyage au chargement).
local function KeepNewestSharedAll()
	for _, section in ipairs({ "A", "G" }) do
		local owners = {}
		for key in pairs(store or {}) do
			local owner = ns.SharedOwner(key, section)
			if owner then
				owners[owner] = true
			end
		end
		for owner in pairs(owners) do
			KeepNewestShared(section, owner)
		end
	end
end

-- SYNCHRO ----------------------------------------------------------------------------------

local changed = {} -- sections du personnage joué modifiées depuis le dernier envoi
lastText = {} -- (déclaré dans REMISE À ZÉRO) [section] = texte de la dernière version, pour détecter un changement
local pushPending, scanPending

local function Token()
	return P.GetTeamToken and P.GetTeamToken()
end

-- Envoie une section du personnage joué (fragmentée) à target, sinon aux clients connectés.
local function SendSection(section, target)
	local token, key = Token(), P.GetCharKey()
	local entry = Entry(key)
	if not token or not entry or not entry.s[section] or not P.WhisperOnline then
		return
	end
	local version = entry.t[section] or 0
	local header = string.format("DATA:%s:%s:%s:N:%d:", token, key, section, version)
	local budget = (P.MAX_MESSAGE_LENGTH or 255) - #header
	local chunks, current, used = {}, {}, 0
	for _, item in ipairs(SectionItems(entry.s[section])) do
		local cost = #item + (#current > 0 and 1 or 0)
		if #current > 0 and used + cost > budget then
			chunks[#chunks + 1] = current
			current, used, cost = {}, 0, #item
		end
		current[#current + 1] = item
		used = used + cost
	end
	chunks[#chunks + 1] = current -- au moins un fragment, même vide
	for i, chunk in ipairs(chunks) do
		P.WhisperOnline(string.format("DATA:%s:%s:%s:%s:%d:%s", token, key, section, i == 1 and "N" or "+",
			version, table.concat(chunk, ",")), target)
	end
end

local function Push()
	pushPending = nil
	for _, section in ipairs(ns.SECTIONS) do
		if changed[section] then
			changed[section] = nil
			SendSection(section)
		end
	end
end

-- Relit le personnage joué ; les sections changées reçoivent une nouvelle version et partent
-- aux clients connectés (sauf send == false, à la déconnexion).
local function Update(send)
	scanPending = nil
	local entry = Entry(P.GetCharKey(), true)
	if not entry then
		return
	end
	entry.seen = GetServerTime()
	local any = false
	for _, section in ipairs(ns.SECTIONS) do
		local ok, data = pcall(READERS[section]) -- une API qui change ne doit pas tout bloquer
		if ok and data then
			local text = table.concat(SectionItems(data), ",")
			if lastText[section] == nil and entry.s[section] then
				lastText[section] = table.concat(SectionItems(entry.s[section]), ",")
			end
			if text ~= lastText[section] then
				lastText[section] = text
				entry.s[section] = data
				entry.t[section] = NextVersion(entry.t[section])
				changed[section] = true
				any = true
				KeepNewestShared(section, ns.SharedOwner(P.GetCharKey(), section))
			end
		end
	end
	if any and send ~= false and not pushPending then
		pushPending = true
		C_Timer.After(SEND_DELAY, Push)
	end
	if any and ns.Refresh then
		ns.Refresh()
	end
end

function ScheduleUpdate() -- déclaré dans REMISE À ZÉRO
	if not scanPending then
		scanPending = true
		C_Timer.After(SCAN_DELAY, Update)
	end
end

-- Rencontre d'un client : on lui annonce les versions de nos sections.
local function SendVersions(target)
	local token, key = Token(), P.GetCharKey()
	local entry = Entry(key)
	if not token or not entry or not P.WhisperOnline then
		return
	end
	local list = {}
	for _, section in ipairs(ns.SECTIONS) do
		if entry.t[section] then
			list[#list + 1] = section .. "=" .. entry.t[section]
		end
	end
	P.WhisperOnline(string.format("DATAV:%s:%s:%s", token, key, table.concat(list, ",")), target)
end

local function RefreshSoon()
	if ns.Refresh then
		ns.Refresh()
	end
end

-- DATAV : on demande les sections dont la version annoncée est plus récente que la nôtre.
local function OnVersions(rest, sender)
	local key, list = strsplit(":", rest or "", 2)
	if not key or key == P.GetCharKey() or not (P.IsSender and P.IsSender(sender, key)) then
		return
	end
	local entry = Entry(key, true)
	entry.seen = GetServerTime()
	local wanted = {}
	for section, version in (list or ""):gmatch("(%u)=(%d+)") do
		if READERS[section] and (tonumber(entry.t[section]) or 0) < tonumber(version) then
			wanted[#wanted + 1] = section
		end
	end
	local token = Token()
	if #wanted > 0 and token then
		P.WhisperOnline(string.format("DATAREQ:%s:%s:%s", token, key, table.concat(wanted, ",")), sender)
	end
	RefreshSoon()
end

-- DATAREQ : un client demande certaines de nos sections.
local function OnRequest(rest, sender)
	local key, list = strsplit(":", rest or "", 2)
	if key ~= P.GetCharKey() then
		return
	end
	for section in (list or ""):gmatch("%u") do
		if READERS[section] then
			SendSection(section, sender)
		end
	end
end

-- DATA : une section d'un autre personnage.
local function OnData(rest, sender)
	local key, section, flag, version, data = strsplit(":", rest or "", 5)
	version = tonumber(version)
	if not key or not READERS[section] or not version or key == P.GetCharKey()
		or not (P.IsSender and P.IsSender(sender, key)) then
		return
	end
	local entry = Entry(key, true)
	entry.seen = GetServerTime()
	if flag == "N" then
		if (tonumber(entry.t[section]) or 0) >= version then
			return -- déjà à jour
		end
		entry.s[section] = {}
		entry.t[section] = version
	elseif tonumber(entry.t[section]) ~= version or not entry.s[section] then
		return -- suite d'une version qu'on n'a pas commencée
	end
	local target = entry.s[section]
	for pair in (data or ""):gmatch("[^,]+") do
		local k, v = pair:match("^([^=]+)=(.*)$")
		if k then
			target[k] = (k == "a" or k == "n") and v or (tonumber(v) or v) -- compte / guilde : texte
		end
	end
	KeepNewestShared(section, ns.SharedOwner(key, section))
	RefreshSoon()
end

if P.RegisterMessageHandler then
	P.RegisterMessageHandler("DATA", OnData)
	P.RegisterMessageHandler("DATAV", OnVersions)
	P.RegisterMessageHandler("DATAREQ", OnRequest)
	P.RegisterPeerCallback(function(sender)
		SendVersions(sender)
	end)
end

-- TEMPS DE JEU : demandé au serveur à la connexion sans l'afficher dans la discussion
-- (ChatFrameUtil.DisplayTimePlayed court-circuité le temps de la réponse, comme WoWthing) ; un
-- /played tapé par le joueur s'affiche normalement et est relevé aussi.
local requestingPlayed = false

local function RequestPlayedSilently()
	if not RequestTimePlayed or not (ChatFrameUtil and type(ChatFrameUtil.DisplayTimePlayed) == "function") then
		return
	end
	if not ns.playedHooked then
		ns.playedHooked = true
		local original = ChatFrameUtil.DisplayTimePlayed
		ChatFrameUtil.DisplayTimePlayed = function(...)
			if requestingPlayed then
				requestingPlayed = false
				return
			end
			return original(...)
		end
	end
	requestingPlayed = true
	RequestTimePlayed()
	C_Timer.After(10, function()
		requestingPlayed = false -- pas de réponse : ne pas masquer un /played ultérieur
	end)
end

-- ÉVÉNEMENTS --------------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_LOGOUT")
for _, event in ipairs({
	"PLAYER_ENTERING_WORLD", "PLAYER_LEVEL_UP", "PLAYER_MONEY", "ZONE_CHANGED_NEW_AREA",
	"PLAYER_SPECIALIZATION_CHANGED", "PLAYER_EQUIPMENT_CHANGED", "SKILL_LINES_CHANGED", "ACHIEVEMENT_EARNED",
	"BAG_UPDATE_DELAYED", "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "PLAYERBANKSLOTS_CHANGED",
	"PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED", "BANK_TABS_CHANGED", "TIME_PLAYED_MSG",
	"PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE", -- banque de guilde
	"GUILDBANKBAGSLOTS_CHANGED", "GUILDBANK_UPDATE_MONEY", "PLAYER_GUILD_UPDATE",
	"TRADE_SKILL_SHOW", "TRADE_SKILL_CLOSE", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_DATA_SOURCE_CHANGED", -- recettes
}) do
	if not (C_EventUtils and C_EventUtils.IsEventValid) or C_EventUtils.IsEventValid(event) then
		pcall(events.RegisterEvent, events, event)
	end
end
events:SetScript("OnEvent", function(_, event, ...)
	if event == "ADDON_LOADED" then
		if ... == "Polypode_Data" then
			PolypodeDataDB = PolypodeDataDB or {}
			PolypodeDataDB.chars = PolypodeDataDB.chars or {}
			store = PolypodeDataDB.chars
			KeepNewestSharedAll() -- copies en double des versions précédentes
		end
		return
	elseif event == "PLAYER_LOGIN" then
		-- Dernier temps de jeu connu, gardé tant que le serveur n'a pas répondu.
		local own = Entry(P.GetCharKey())
		local identity = own and own.s.I
		if identity then
			played, playedAt = tonumber(identity.p), tonumber(identity.pa)
		end
		RequestPlayedSilently()
	elseif event == "PLAYER_LOGOUT" then
		-- Pas de relevé ici : à la déconnexion, sacs, équipement, métiers et or sont déjà vidés
		-- par le jeu (GetMoney = 0, sacs vides...) et écraseraient les données. On garde le
		-- dernier relevé (au plus SCAN_DELAY secondes plus tôt) et on note seulement l'heure.
		local own = Entry(P.GetCharKey())
		if own then
			own.seen = GetServerTime()
		end
		return
	elseif event == "TIME_PLAYED_MSG" then
		played, playedAt = ..., GetServerTime()
	elseif event == "BANKFRAME_OPENED" then
		bankOpen = true
	elseif event == "BANKFRAME_CLOSED" then
		-- Dernier relevé avant la fermeture (les sacs de banque restent lisibles à cet instant).
		Update()
		bankOpen = false
		return
	elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" or event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
		local guildBanker = Enum and Enum.PlayerInteractionType and Enum.PlayerInteractionType.GuildBanker
		if not guildBanker or ... ~= guildBanker then
			return
		end
		if event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then
			OpenGuildBank()
		else
			Update() -- dernier relevé, puis fermeture
			guildBankOpen = false
			return
		end
	elseif event == "TRADE_SKILL_SHOW" then
		tradeSkillOpen = true
	elseif event == "TRADE_SKILL_CLOSE" then
		Update() -- dernier relevé des recettes, puis fermeture
		tradeSkillOpen = false
		return
	elseif event == "GUILDBANKBAGSLOTS_CHANGED" and guildBankOpen then
		ScanGuildTabs() -- onglet reçu relu tout de suite, avant qu'un autre ne le remplace
	end
	ScheduleUpdate()
end)
