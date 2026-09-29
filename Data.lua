-- Polypode Data: Data — relevé des données « fixes » de chaque personnage, sauvegarde et synchro

local _, ns = ...
local P = Polypode -- dépendance obligatoire (## Dependencies: Polypode), chargée avant nous

-- Addon compagnon de Polypode, dans l'esprit de DataStore (Altoholic) ou WoWthing : les données
-- durables de chaque personnage (identité, or, métiers, équipement, sacs et banques), gardées dans
-- PolypodeDataDB (fichier de compte) et échangées entre les clients connectés.
--
-- Sections (une table { clé = valeur } chacune ; valeurs sans « , : = ») :
--   I identité : c classe (fichier), r race, l niveau, i niveau d'objet équipé, s spécialisation,
--     f faction, g or (pièces de cuivre), z zone, p temps de jeu (s) relevé à la date pa ;
--   T métiers : p1 / p2 principaux, s1 / s2 / s3 archéologie, pêche, cuisine =
--     « skillLine/niveau/max/icône/nom » ;
--   E équipement : <emplacement 1-19> = « niveau d'objet@chaîne d'objet » (la chaîne du lien,
--     « itemID:enchantement:gemmes...:bonus... », sans « item: » : enchantement, gemmes et
--     améliorations compris ; les « : » passent, seuls « , » et « = » séparent) ;
--   B sacs, K banque du personnage, A banque de bataillon : i<itemID> = nombre.
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

ns.SECTIONS = { "I", "T", "E", "B", "K", "A", "G" }

local SCAN_DELAY = 2 -- secondes : regroupe les rafales d'événements (sacs, or)
local SEND_DELAY = 10 -- secondes : envoi des sections modifiées aux clients connectés

local store -- PolypodeDataDB.chars
local bankOpen = false
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
			end
		end
	end
	return data
end

local function ReadEquipment()
	local data = {}
	for slot = 1, 19 do
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

local function ReadContainers(kind)
	local data = {}
	if not (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemInfo) then
		return data
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

-- SYNCHRO ----------------------------------------------------------------------------------

local changed = {} -- sections du personnage joué modifiées depuis le dernier envoi
local lastText = {} -- [section] = texte de la dernière version, pour détecter un changement
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

local function ScheduleUpdate()
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
			target[k] = tonumber(v) or v
		end
	end
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
	"PLAYER_SPECIALIZATION_CHANGED", "PLAYER_EQUIPMENT_CHANGED", "SKILL_LINES_CHANGED",
	"BAG_UPDATE_DELAYED", "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "PLAYERBANKSLOTS_CHANGED",
	"PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED", "BANK_TABS_CHANGED", "TIME_PLAYED_MSG",
	"PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE", -- banque de guilde
	"GUILDBANKBAGSLOTS_CHANGED", "GUILDBANK_UPDATE_MONEY", "PLAYER_GUILD_UPDATE",
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
	elseif event == "GUILDBANKBAGSLOTS_CHANGED" and guildBankOpen then
		ScanGuildTabs() -- onglet reçu relu tout de suite, avant qu'un autre ne le remplace
	end
	ScheduleUpdate()
end)
