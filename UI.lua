-- Polypode Data: UI — fenêtre « Données des personnages » : tableau, détail au survol, recherche d'objet

local _, ns = ...
local P = Polypode

-- Fenêtre PolypodeDataFrame (bouton « Data » de la fenêtre Polypode, /poly data) :
--   * tableau sans trait de tous les personnages connus (le personnage joué en tête) : niveau,
--     niveau d'objet, métiers principaux, or, temps de jeu, dernière connexion ; détail au survol
--     (identité, métiers, équipement, sacs et banques), clic gauche = fiche épinglée (voir
--     FICHES ÉPINGLÉES), clic droit = oublier le personnage ;
--   * champ de recherche (en haut à droite) : dès 2 lettres, la liste devient celle des objets
--     dont le nom correspond (sans accents ni casse), avec qui les possède et où.
-- Colonnes ancrées au bord droit, à la largeur de leur plus long contenu (mesurée à chaque
-- rafraîchissement) ; le nom prend la place restante (comme la fenêtre de Polypode Suivi).

local MIN_WIDTH, MIN_HEIGHT = 640, 220 -- largeur : boutons, titre et deux champs de recherche
local SEARCH_WIDTH = 105 -- chaque champ de recherche (objets, recettes), côte à côte
local DEFAULT_WIDTH, DEFAULT_HEIGHT = 820, 360
local COLUMN_GAP = 14
local MIN_SEARCH = 2 -- lettres avant de lancer la recherche

local frame, listPanel, searchBox, recipeBox
local columnWidths = {} -- largeurs des colonnes affichées (0 = masquée)
local measure -- texte caché servant à mesurer les cellules
local namesPending = false -- noms d'objets demandés au serveur (recherche, fiches)

local GOLD_ICON = "|TInterface\\MoneyFrame\\UI-GoldIcon:12:12:2:0|t"
local SLOT_NAMES = { "HEADSLOT", "NECKSLOT", "SHOULDERSLOT", "SHIRTSLOT", "CHESTSLOT", "WAISTSLOT",
	"LEGSSLOT", "FEETSLOT", "WRISTSLOT", "HANDSSLOT", "FINGER0SLOT", "FINGER1SLOT", "TRINKET0SLOT",
	"TRINKET1SLOT", "BACKSLOT", "MAINHANDSLOT", "SECONDARYHANDSLOT", "RANGEDSLOT", "TABARDSLOT" }

local function WindowSettings()
	PolypodeDataDB = PolypodeDataDB or {}
	PolypodeDataDB.window = PolypodeDataDB.window or {}
	return PolypodeDataDB.window
end

-- Affichage du contenu d'un sac ou d'une banque (option « Contenu des sacs et banques ») :
-- "list" (une ligne par objet) ou "icons" (grille d'icônes, comme les sacs de WoW).
local function ContainerView()
	return PolypodeDataDB and PolypodeDataDB.containerView or "list"
end

-- FORMATAGE ------------------------------------------------------------------------------------

local function Icon(fileID, size)
	size = size or 14
	return (fileID and fileID ~= 0 and fileID ~= "0") and ("|T" .. fileID .. ":" .. size .. ":" .. size .. "|t") or ""
end

local function Gray(text)
	return "|cff999999" .. text .. "|r"
end

-- Lettres accentuées (UTF-8) ramenées à leur lettre de base, pour une recherche sans accents.
local ACCENT_BASES = {
	a = "àáâãäåÀÁÂÃÄÅ", c = "çÇ", e = "èéêëÈÉÊË", i = "ìíîïÌÍÎÏ", n = "ñÑ",
	o = "òóôõöøÒÓÔÕÖØ", u = "ùúûüÙÚÛÜ", y = "ýÿÝ", ae = "æÆ", oe = "œŒ", ss = "ß",
}
local ACCENT_MAP = {}
for base, letters in pairs(ACCENT_BASES) do
	for letter in letters:gmatch("[\195\197][\128-\191]") do
		ACCENT_MAP[letter] = base
	end
end

local function Normalize(text)
	return (tostring(text or ""):gsub("[\195\197][\128-\191]", ACCENT_MAP):lower())
end

local function IsOwn(key)
	return key == P.GetCharKey()
end

local function IsOnline(key)
	return IsOwn(key) or (P.IsCharacterOnline and P.IsCharacterOnline(key))
end

local function Sections(key)
	local entry = ns.GetEntry(key)
	return entry and entry.s or {}, entry
end

local function ClassFile(key)
	local identity = Sections(key).I
	local roster = P.db.roster[key]
	return (identity and identity.c) or (roster and roster.class)
end

local function CharacterName(key)
	local name = P.GetDisplayName(key)
	local classFile = ClassFile(key)
	local color = classFile and C_ClassColor and C_ClassColor.GetClassColor(classFile)
	return color and color:WrapTextInColorCode(name) or name
end

local function FormatGold(copper)
	copper = tonumber(copper)
	if not copper then
		return ""
	end
	local gold = math.floor(copper / 10000)
	return (BreakUpLargeNumbers and BreakUpLargeNumbers(gold) or tostring(gold)) .. " " .. GOLD_ICON
end

-- « 12 j 5 h », « 3 h 20 min ».
local function FormatDuration(seconds)
	seconds = math.floor(tonumber(seconds) or 0)
	local days, hours = math.floor(seconds / 86400), math.floor(seconds % 86400 / 3600)
	if days > 0 then
		return days .. " j " .. hours .. " h"
	end
	return hours .. " h " .. math.floor(seconds % 3600 / 60) .. " min"
end

-- « il y a 5 min », « il y a 3 h », « le 24/09 ».
local function FormatWhen(at)
	at = tonumber(at)
	if not at then
		return ""
	end
	local minutes = math.floor((GetServerTime() - at) / 60)
	if minutes < 1 then
		return "à l'instant"
	elseif minutes < 60 then
		return "il y a " .. minutes .. " min"
	elseif minutes < 24 * 60 then
		return "il y a " .. math.floor(minutes / 60) .. " h"
	end
	return "le " .. date("%d/%m", at)
end

-- Dernière connexion : « en ligne » (vert) ou la date où le personnage a été vu.
local function SeenText(key)
	if IsOnline(key) then
		return "|cff40ff40en ligne|r"
	end
	local _, entry = Sections(key)
	return entry and entry.seen and FormatWhen(entry.seen) or ""
end

-- Temps de jeu estimé maintenant : relevé (p, à la date pa) + temps connecté depuis.
local function PlayedSeconds(key)
	local identity, entry = Sections(key)
	identity = identity.I
	local total, at = tonumber(identity and identity.p), tonumber(identity and identity.pa)
	if not total then
		return nil
	end
	local until_ = IsOwn(key) and GetServerTime() or (entry and tonumber(entry.seen))
	if at and until_ and until_ > at then
		total = total + (until_ - at)
	end
	return total
end

-- Métiers d'un personnage : { clé, skillLine, niveau, max, icône, nom }, dans l'ordre p1 p2 s1 s2 s3.
local function Professions(key)
	local list = {}
	local professions = Sections(key).T or {}
	for _, slot in ipairs({ "p1", "p2", "s1", "s2", "s3" }) do
		local value = professions[slot]
		if value then
			local skillLine, level, maxLevel, icon, name = tostring(value):match("^(%d+)/(%d+)/(%d+)/([^/]*)/(.*)$")
			if skillLine then
				local gear = {}
				for gearSlot in tostring(professions["g" .. slot] or ""):gmatch("%d+") do
					gear[#gear + 1] = tonumber(gearSlot)
				end
				list[#list + 1] = { slot = slot, skillLine = tonumber(skillLine), level = tonumber(level),
					max = tonumber(maxLevel), icon = tonumber(icon) or icon, name = name, gear = gear }
			end
		end
	end
	return list
end

-- Nom d'objet (couleur de qualité) ; demandé au serveur s'il n'est pas encore connu.
local function ItemName(itemID)
	local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)
	if not name then
		if C_Item and C_Item.RequestLoadItemDataByID then
			C_Item.RequestLoadItemDataByID(itemID)
		end
		namesPending = true
		return nil
	end
	local quality = C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(itemID)
	local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
	return name, color and color.color and color.color:WrapTextInColorCode(name) or name
end

local function ItemIcon(itemID)
	return C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemID)
end

-- Nombre total d'objets et d'objets différents d'une section de sac.
local function ContainerCount(data)
	local total, distinct = 0, 0
	for key, count in pairs(data or {}) do
		if tostring(key):match("^i%d+$") then -- objets seulement (pas le nom ni l'or d'une guilde)
			total = total + (tonumber(count) or 0)
			distinct = distinct + 1
		end
	end
	return total, distinct
end

-- Compte Battle.net d'un personnage (token), pour la banque de bataillon commune (Data.lua).
local AccountOf = ns.AccountOf

-- Banque de bataillon la plus récente par compte : { [compte] = { key, data, version } } ; compte
-- noté dans le relevé (ns.SharedOwner), une seule copie gardée par compte (Data.lua).
local function WarbandBanks()
	local banks = {}
	for key in pairs(ns.GetKeys()) do
		local sections, entry = Sections(key)
		local version = entry and tonumber(entry.t.A)
		if sections.A and version then
			local account = ns.SharedOwner(key, "A")
			if not banks[account] or banks[account].version < version then
				banks[account] = { key = key, data = sections.A, version = version }
			end
		end
	end
	return banks
end

-- Banque de guilde la plus récente par guilde : { [nom] = { key, data, version } }.
local function GuildBanks()
	local banks = {}
	for key in pairs(ns.GetKeys()) do
		local sections, entry = Sections(key)
		local version = entry and tonumber(entry.t.G)
		local guild = sections.G and sections.G.n
		if guild and version and (not banks[guild] or banks[guild].version < version) then
			banks[guild] = { key = key, data = sections.G, version = version }
		end
	end
	return banks
end

-- TABLEAU DES PERSONNAGES -----------------------------------------------------------------------

-- Colonnes : { en-tête, cellule(clé), tip = { titre, texte } }.
-- n-ième métier principal (p1, p2) d'un personnage, ou nil.
local function MainProfession(key, n)
	local count = 0
	for _, profession in ipairs(Professions(key)) do
		if profession.slot == "p1" or profession.slot == "p2" then
			count = count + 1
			if count == n then
				return profession
			end
		end
	end
end

local COLUMNS = {
	{ "Niveau", function(key)
		local identity = Sections(key).I
		return identity and identity.l and tostring(identity.l) or ""
	end, sort = function(key)
		return tonumber((Sections(key).I or {}).l)
	end, tip = { "Niveau", "Niveau du personnage." } },
	{ "iLvl", function(key)
		local identity = Sections(key).I
		return identity and identity.i and tostring(identity.i) or ""
	end, sort = function(key)
		return tonumber((Sections(key).I or {}).i)
	end, tip = { "Niveau d'objet", "Niveau d'objet moyen équipé." } },
	-- Métiers principaux : une colonne chacun, alignées à gauche (icônes les unes sous les autres) ;
	-- la seconde sans en-tête, les deux se lisent comme un bloc « Métiers ».
	{ "Métiers", function(key)
		local profession = MainProfession(key, 1)
		return profession and (Icon(profession.icon) .. " " .. profession.level) or ""
	end, sort = function(key)
		local profession = MainProfession(key, 1)
		return profession and profession.level
	end, align = "LEFT",
	tip = { "Métiers", "Métiers principaux et leur niveau (tous les métiers au survol d'un personnage)." } },
	{ "", function(key)
		local profession = MainProfession(key, 2)
		return profession and (Icon(profession.icon) .. " " .. profession.level) or ""
	end, sort = function(key)
		local profession = MainProfession(key, 2)
		return profession and profession.level
	end, align = "LEFT",
	tip = { "Métiers", "Second métier principal et son niveau." } },
	{ "Or", function(key)
		local identity = Sections(key).I
		return identity and FormatGold(identity.g) or ""
	end, sort = function(key)
		return tonumber((Sections(key).I or {}).g)
	end, tip = { "Or", "Or sur le personnage." } },
	{ "Hauts faits", function(key)
		local identity = Sections(key).I
		return identity and identity.ap and tostring(identity.ap) or ""
	end, sort = function(key)
		return tonumber((Sections(key).I or {}).ap)
	end, tip = { "Points de haut fait", "Points des hauts faits obtenus par ce personnage (pas le total du bataillon)." } },
	{ "Temps de jeu", function(key)
		local seconds = PlayedSeconds(key)
		return seconds and FormatDuration(seconds) or ""
	end, sort = PlayedSeconds, tip = { "Temps de jeu", "Temps de jeu total (relevé à la connexion, puis compté)." } },
	{ "Vu", SeenText, sort = function(key)
		if IsOnline(key) then
			return math.huge -- en ligne : le plus récent
		end
		local _, entry = Sections(key)
		return entry and tonumber(entry.seen)
	end, tip = { "Dernière connexion", "« en ligne », ou quand le personnage a été vu connecté." } },
}

-- TRI PAR COLONNE (clic sur un en-tête) : sortColumn = 0 (nom) ou n° de colonne, sortDesc =
-- ordre inverse ; gardés dans PolypodeDataDB.window. Sans tri choisi : personnage joué en tête,
-- puis ordre alphabétique. Premier clic : noms de A à Z, nombres du plus grand au plus petit ;
-- clic suivant sur la même colonne : ordre inverse.
local SORT_UP = "|TInterface\\Buttons\\Arrow-Up-Up:12:12:0:-2|t"
local SORT_DOWN = "|TInterface\\Buttons\\Arrow-Down-Up:12:12:0:2|t"

local function SetSort(column)
	local settings = WindowSettings()
	if settings.sortColumn == column then
		settings.sortDesc = not settings.sortDesc
	else
		settings.sortColumn = column
		settings.sortDesc = column ~= 0 -- nombres : du plus grand au plus petit
	end
	ns.Refresh()
end

-- Flèche du tri en cours sur l'en-tête de la colonne column, sinon "".
local function SortMark(column)
	local settings = WindowSettings()
	if settings.sortColumn ~= column then
		return ""
	end
	return " " .. (settings.sortDesc and SORT_DOWN or SORT_UP)
end

local function SortItems(items)
	local settings = WindowSettings()
	local column = settings.sortColumn
	if column == nil or (column ~= 0 and not (COLUMNS[column] and COLUMNS[column].sort)) then
		return
	end
	local values, names = {}, {}
	for _, item in ipairs(items) do
		names[item.key] = Normalize(CharacterName(item.key))
		if column ~= 0 then
			local ok, value = pcall(COLUMNS[column].sort, item.key)
			values[item.key] = ok and tonumber(value) or nil
		end
	end
	local desc = settings.sortDesc
	table.sort(items, function(a, b)
		if column ~= 0 then
			local va, vb = values[a.key], values[b.key]
			if va ~= vb then
				if va == nil or vb == nil then
					return vb == nil -- sans valeur : toujours en bas
				end
				if desc then
					return va > vb
				end
				return va < vb
			end
		elseif names[a.key] ~= names[b.key] then
			if desc then
				return names[a.key] > names[b.key]
			end
			return names[a.key] < names[b.key]
		end
		return names[a.key] < names[b.key]
	end)
end

local function BuildCharacterItems()
	local keys = ns.GetKeys()
	keys[P.GetCharKey()] = true
	local items = P.SortedKeyItems(keys, IsOwn)
	SortItems(items)
	local header = { columnHeader = true, cells = {}, tips = {} }
	local used = {}
	for _, item in ipairs(items) do
		item.cells = {}
		for i, column in ipairs(COLUMNS) do
			local ok, cell = pcall(column[2], item.key)
			item.cells[i] = ok and cell or ""
			used[i] = used[i] or item.cells[i] ~= ""
		end
	end
	if not measure then
		measure = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		measure:Hide()
	end
	local function Width(text)
		measure:SetText(text)
		return math.ceil(measure:GetStringWidth())
	end
	wipe(columnWidths)
	for i, column in ipairs(COLUMNS) do
		header.cells[i] = "|cffffd200" .. column[1] .. "|r" .. SortMark(i)
		header.tips[i] = column.tip
		local width = 0
		if used[i] then
			width = Width(header.cells[i])
			for _, item in ipairs(items) do
				width = math.max(width, Width(item.cells[i]))
			end
		end
		columnWidths[i] = width
	end
	table.insert(items, 1, header)
	return items
end

-- Or total des personnages connus.
local function TotalGold()
	local total = 0
	for key in pairs(ns.GetKeys()) do
		local identity = Sections(key).I
		total = total + (tonumber(identity and identity.g) or 0)
	end
	return total
end

-- FICHES ÉPINGLÉES : un clic gauche sur un personnage ouvre sa fiche (le détail de l'infobulle)
-- dans un cadre qui reste affiché, déplaçable (glisser) ; plusieurs à l'écran ; croix en haut à
-- droite pour la fermer. Clic (gauche ou droit) sur une ligne marquée « » » : son détail (contenu
-- d'un sac ou d'une banque dans une autre fiche, objet équipé dans l'infobulle d'objet de WoW).
-- Entrée d'une fiche : { text, detail = fonction appelée au clic, hint = texte d'aide, note =
-- précision montrée dans l'infobulle de la ligne, avant hint (sur sa propre ligne dans
-- l'infobulle d'un personnage) }.

local CARD_WIDTH = 460
local CARD_MAX_HEIGHT = 520
local CARD_ROW_HEIGHT = 20 -- hauteur d'une ligne de P.CreateScrollList
local CARD_STATUS_HEIGHT = 20 -- ligne d'état sous le titre (fiche avec bouton d'action)
local DETAIL_MARK = " |cff999999»|r"
local cards = {} -- fiches créées (réutilisées une fois fermées)
local OpenCard -- défini plus bas

-- Infobulle d'objet de WoW, épinglée et déplaçable (comme un lien d'objet cliqué) ; item :
-- identifiant ou lien « item:... » complet (enchantement, gemmes, bonus).
local function ShowItem(item)
	if type(SetItemRef) == "function" then
		item = tostring(item)
		SetItemRef(item:match("^item:") and item or ("item:" .. item), nil, "LeftButton")
	end
end

-- Pièce d'équipement enregistrée : itemID, niveau d'objet, lien « item:... » (format
-- « niveau@chaîne d'objet », ou l'ancien « itemID-niveau » sans enchantement ni gemmes).
local function EquippedItem(value)
	value = tostring(value or "")
	local level, itemString = value:match("^(%d+)@(.+)$")
	if itemString then
		return tonumber(itemString:match("^(%d+)")), tonumber(level), "item:" .. itemString
	end
	local itemID, oldLevel = value:match("^(%d+)%-(%d+)$")
	if itemID then
		return tonumber(itemID), tonumber(oldLevel), "item:" .. itemID
	end
end

-- Motif Lua d'une chaîne de format WoW (« Enchanté : %s » → « ^Enchanté : (.+)$ »).
local function FormatPattern(format)
	if type(format) ~= "string" then
		return nil
	end
	local pattern = format:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%s", "(.+)"):gsub("%%d", "%%d+")
	return "^" .. pattern .. "$"
end

local ENCHANT_PATTERN = FormatPattern(ENCHANTED_TOOLTIP_LINE)
local UPGRADE_PATTERN = FormatPattern(ITEM_UPGRADE_TOOLTIP_FORMAT_STRING)

-- Améliorations d'une pièce, lues dans son lien : { enchant, upgrade, gems = { texte... } }.
-- Enchantement et niveau d'amélioration : lignes de l'infobulle de l'objet (C_TooltipInfo) ;
-- gemmes : C_Item.GetItemGem.
local function ItemEnhancements(link)
	local result = { gems = {} }
	local info = C_TooltipInfo and C_TooltipInfo.GetHyperlink and C_TooltipInfo.GetHyperlink(link)
	for _, line in ipairs(info and info.lines or {}) do
		local text = line.leftText
		if type(text) == "string" and not (issecretvalue and issecretvalue(text)) then
			local plain = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
			if ENCHANT_PATTERN and not result.enchant and plain:match(ENCHANT_PATTERN) then
				result.enchant = plain:match(ENCHANT_PATTERN)
			elseif UPGRADE_PATTERN and not result.upgrade and plain:match(UPGRADE_PATTERN) then
				result.upgrade = plain:match(UPGRADE_PATTERN) and plain:gsub("^[^:]*:%s*", "")
			end
		end
	end
	if C_Item and C_Item.GetItemGem then
		for index = 1, 4 do
			local name, gemLink = C_Item.GetItemGem(link, index)
			if name then
				local gemID = gemLink and tonumber(gemLink:match("item:(%d+)"))
				result.gems[#result.gems + 1] = Icon(gemID and ItemIcon(gemID), 12) .. " " .. name
			end
		end
	end
	return result
end

-- Contenu d'un sac ou d'une banque : une ligne par objet (nom, nombre), triées par nom ; item et
-- count servent à l'affichage en icônes (entries.items, voir GRILLE D'ICÔNES).
local function ContainerEntries(data)
	local entries = { items = true }
	for itemKey, count in pairs(data or {}) do
		local itemID = tonumber(tostring(itemKey):match("^i(%d+)$"))
		if itemID then
			local name, colored = ItemName(itemID)
			entries[#entries + 1] = {
				sort = Normalize(name or ("~" .. itemID)),
				text = Icon(ItemIcon(itemID)) .. " " .. (colored or ("objet n° " .. itemID)) .. Gray("  ×" .. count),
				detail = function()
					ShowItem(itemID)
				end,
				hint = "Clic : infobulle de l'objet",
				item = itemID,
				count = tonumber(count) or 0,
			}
		end
	end
	table.sort(entries, function(a, b)
		return a.sort < b.sort
	end)
	return entries
end

-- FICHE D'UN MÉTIER (clic sur un métier dans la fiche d'un personnage) : ses objets (outil,
-- accessoires : section E, emplacements notés g<métier> dans T), puis ses recettes apprises
-- (section R, relevée fenêtre du métier ouverte) par extension, repliables (repliées par défaut,
-- la plus récente en tête). Nom et icône d'une recette : ceux de son sort (recipeID = spellID).
local expandedTiers = {} -- ["clé#métier d'extension"] = true : extension dépliée (session)

local function SpellName(spellID)
	local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
	if not name and C_Spell and C_Spell.RequestLoadSpellData then
		C_Spell.RequestLoadSpellData(spellID)
		namesPending = true -- SPELL_DATA_LOAD_RESULT relance l'affichage
	end
	return name
end

local function ShowSpell(spellID)
	if type(SetItemRef) == "function" then
		SetItemRef("spell:" .. spellID, nil, "LeftButton")
	end
end

local function ProfessionEntries(key, professionSlot)
	local sections = Sections(key)
	local entries = {}
	local function Add(text, detail, hint, noMark)
		entries[#entries + 1] = { text = (detail and not noMark) and (text .. DETAIL_MARK) or text, detail = detail,
			hint = hint }
	end
	local profession
	for _, candidate in ipairs(Professions(key)) do
		if candidate.slot == professionSlot then
			profession = candidate
		end
	end
	if not profession then
		Add(Gray("Métier inconnu (plus relevé pour ce personnage)."))
		return entries
	end

	Add("|cffffd200Objets de métier|r")
	local anyItem = false
	for _, slot in ipairs(profession.gear) do
		local itemID, level, link = EquippedItem(sections.E and sections.E[tostring(slot)])
		if itemID then
			anyItem = true
			local _, colored = ItemName(itemID)
			Add("  " .. Icon(ItemIcon(itemID)) .. " " .. (colored or ("objet n° " .. itemID))
				.. ((level or 0) > 0 and Gray(" " .. level) or ""), function()
				ShowItem(link)
			end, "Clic : infobulle de l'objet")
		end
	end
	if not anyItem then
		Add("  " .. Gray(#profession.gear > 0 and "Aucun objet équipé."
			or "Pas encore relevés : reconnectez une fois ce personnage."))
	end

	-- Recettes de ce métier, regroupées par métier d'extension.
	local tiers, count = {}, 0
	local recipes = sections.R or {}
	for itemKey, value in pairs(recipes) do
		local child = tonumber(tostring(itemKey):match("^c(%d+)$") or "")
		local base, label = tostring(value):match("^(%d+)/(.*)$")
		if child and tonumber(base) == profession.skillLine then
			tiers[child] = { child = child, label = label ~= "" and label or ("n° " .. child), ids = {} }
		end
	end
	for itemKey, value in pairs(recipes) do
		local recipeID = tonumber(tostring(itemKey):match("^r(%d+)$") or "")
		local tier = recipeID and tiers[tonumber(value)]
		if tier then
			tier.ids[#tier.ids + 1] = recipeID
			count = count + 1
		end
	end
	Add(" ")
	Add("|cffffd200Recettes apprises|r" .. Gray(" (" .. count .. ")"))
	if count == 0 then
		Add("  " .. Gray("Pas encore relevées : ouvrez une fois la fenêtre de ce métier avec ce personnage."))
		return entries
	end
	local order = {}
	for _, tier in pairs(tiers) do
		if #tier.ids > 0 then
			order[#order + 1] = tier
		end
	end
	table.sort(order, function(a, b)
		return a.child > b.child -- extension la plus récente en tête
	end)
	for _, tier in ipairs(order) do
		local stateKey = key .. "#" .. tier.child
		local open = expandedTiers[stateKey]
		Add("|cffffd200" .. (open and "-" or "+") .. "|r " .. tier.label .. Gray(" (" .. #tier.ids .. ")"), function()
			expandedTiers[stateKey] = not open or nil
			ns.Refresh()
		end, "Clic : " .. (open and "replier" or "déplier"), true)
		if open then
			local rows = {}
			for _, recipeID in ipairs(tier.ids) do
				rows[#rows + 1] = { id = recipeID, name = SpellName(recipeID) or ("recette n° " .. recipeID) }
			end
			table.sort(rows, function(a, b)
				return Normalize(a.name) < Normalize(b.name)
			end)
			for _, row in ipairs(rows) do
				local icon = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(row.id)
				Add("      " .. Icon(icon) .. " " .. row.name, function()
					ShowSpell(row.id)
				end, "Clic : infobulle de la recette")
			end
		end
	end
	return entries
end

-- Ouvre la fiche d'un métier d'un personnage.
local function OpenProfessionCard(key, professionSlot)
	local name = professionSlot
	for _, candidate in ipairs(Professions(key)) do
		if candidate.slot == professionSlot then
			name = candidate.name
		end
	end
	OpenCard(name .. " — " .. CharacterName(key), function()
		return ProfessionEntries(key, professionSlot)
	end)
end

-- Lignes du détail d'un personnage (infobulle au survol et fiche épinglée). Une ligne peut avoir
-- une colonne de droite (right : métiers deux par ligne). noEquipment : sans la liste de
-- l'équipement (fiche épinglée : il y est montré en icônes, voir ÉQUIPEMENT EN ICÔNES).
local function CharacterEntries(key, noEquipment)
	local sections, entry = Sections(key)
	local identity = sections.I or {}
	local entries = {}
	local function Add(text, detail, hint, right, rightDetail)
		entries[#entries + 1] = { text = detail and (text .. DETAIL_MARK) or text, detail = detail, hint = hint,
			right = right and rightDetail and (right .. DETAIL_MARK) or right, rightDetail = rightDetail }
	end
	local className = identity.c and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[identity.c]
	local who = {}
	if identity.l then
		who[#who + 1] = "Niveau " .. identity.l
	end
	who[#who + 1] = identity.r
	who[#who + 1] = className
	if identity.s then
		who[#who + 1] = "(" .. identity.s .. ")"
	end
	if #who > 0 then
		Add(table.concat(who, " "))
	end
	local place = {}
	place[#place + 1] = identity.f
	place[#place + 1] = identity.z
	if #place > 0 then
		Add(table.concat(place, " · "))
	end
	if identity.i then
		Add("Niveau d'objet : " .. identity.i)
	end
	if identity.g then
		Add("Or : " .. FormatGold(identity.g))
	end
	local seconds = PlayedSeconds(key)
	if seconds then
		Add("Temps de jeu : " .. FormatDuration(seconds))
	end
	Add("Vu : " .. SeenText(key))

	local professions = Professions(key)
	if #professions > 0 then
		Add(" ")
		Add("|cffffd200Métiers|r")
		-- Deux colonnes : principaux côte à côte, puis secondaires deux par deux.
		local function ProfessionText(profession)
			return Icon(profession.icon) .. " " .. profession.name .. " : " .. profession.level .. "/" .. profession.max
		end
		-- Chaque métier ouvre sa fiche (objets, recettes) ; celui de droite par sa propre zone.
		local hint = "Clic : objets et recettes de ce métier"
		for i = 1, #professions, 2 do
			local first, second = professions[i], professions[i + 1]
			Add("  " .. ProfessionText(first), function()
				OpenProfessionCard(key, first.slot)
			end, hint, second and ProfessionText(second) or nil, second and function()
				OpenProfessionCard(key, second.slot)
			end or nil)
		end
	end

	if sections.E and not noEquipment then
		Add(" ")
		Add("|cffffd200Équipement|r")
		for slot, global in ipairs(SLOT_NAMES) do
			local itemID, level, link = EquippedItem(sections.E[tostring(slot)])
			if itemID then
				local _, colored = ItemName(itemID)
				local extra = ItemEnhancements(link)
				local function ShowThis()
					ShowItem(link)
				end
				Add("  " .. (_G[global] or ("Emplacement " .. slot)) .. " : " .. Icon(ItemIcon(itemID)) .. " "
					.. (colored or ("objet n° " .. itemID)) .. ((level or 0) > 0 and Gray(" " .. level) or "")
					.. (extra.upgrade and Gray("  " .. extra.upgrade) or ""),
					ShowThis, "Clic : infobulle de l'objet (enchantement, gemmes, améliorations)")
				-- Enchantement et gemmes sous la pièce.
				if extra.enchant then
					Add("      |cff40ff40" .. extra.enchant .. "|r")
				end
				if #extra.gems > 0 then
					Add("      " .. table.concat(extra.gems, "   "))
				end
			end
		end
	end

	local name = P.GetDisplayName(key)
	-- Une banque par ligne (nom et nombre d'objets) ; précisions (guilde, or, date du relevé) dans
	-- l'infobulle de la ligne (note), sur la ligne suivante dans l'infobulle du personnage.
	local containers = {}
	local function Counts(data)
		local total, distinct = ContainerCount(data)
		return " : " .. total .. " objets (" .. distinct .. " différents)"
	end
	local function Read(at)
		return "relevée " .. FormatWhen(at)
	end
	for _, part in ipairs({ { "B", "Sacs" }, { "K", "Banque" } }) do
		local data = sections[part[1]]
		if data then
			containers[#containers + 1] = { "  " .. part[2] .. Counts(data),
				function()
					OpenCard(part[2] .. " de " .. name, function()
						return ContainerEntries((Sections(key))[part[1]])
					end)
				end, part[1] == "K" and entry and entry.t.K and Gray(Read(entry.t.K)) or nil }
		end
	end
	local bank = WarbandBanks()[AccountOf(key)]
	if bank then
		local account = AccountOf(key)
		containers[#containers + 1] = { "  Banque de bataillon" .. Counts(bank.data),
			function()
				OpenCard("Banque de bataillon", function()
					local current = WarbandBanks()[account]
					return ContainerEntries(current and current.data)
				end)
			end, Gray(Read(bank.version)) }
	end
	local guild = identity.gu
	local guildBank = guild and GuildBanks()[guild]
	if guildBank then
		local money = tonumber(guildBank.data.m)
		containers[#containers + 1] = { "  Banque de guilde" .. Counts(guildBank.data),
			function()
				OpenCard("Banque de guilde " .. guild, function()
					local current = GuildBanks()[guild]
					return ContainerEntries(current and current.data)
				end)
			end, Gray(guild .. " · ") .. (money and (FormatGold(money) .. Gray(" · ")) or "")
				.. Gray(Read(guildBank.version)) }
	end
	if #containers > 0 then
		Add(" ")
		Add("|cffffd200Sacs et banques|r")
		for _, line in ipairs(containers) do
			Add(line[1], line[2], "Clic : contenu détaillé")
			entries[#entries].note = line[3]
		end
		if not (entry and entry.t.K) then
			Add("  " .. Gray("Banque : ouvrez-la une fois avec ce personnage pour la relever"))
		end
		if guild and not guildBank then
			Add("  " .. Gray("Banque de guilde : ouvrez-la une fois (avec un personnage de la guilde) pour la relever"))
		end
	end
	return entries
end

-- SACS ET BANQUES DU PERSONNAGE JOUÉ (boutons de l'en-tête) ----------------------------------
-- B sacs, K banque, A banque de bataillon de son compte, G banque de guilde de sa guilde : les
-- mêmes fiches que le détail d'un personnage (ContainerEntries), avec le dernier relevé.
-- Icônes (utilisées par l'interface de Blizzard) : texture, ou atlas pour le bataillon.
local OWN_CONTAINERS = {
	{ code = "B", texture = "Interface\\Icons\\INV_Misc_Bag_08" },
	{ code = "K", texture = "Interface\\Icons\\INV_Misc_Coin_02" },
	{ code = "A", atlas = "warbands-icon", texture = "Interface\\Icons\\INV_Misc_Coin_17" },
	{ code = "G", texture = "Interface\\Icons\\achievement_guildperk_mobilebanking" },
}
local CONTAINER_ICON_SIZE = 20

-- { title, data, version, missing } d'un sac / d'une banque du personnage joué.
local function OwnContainer(code)
	local key = P.GetCharKey()
	local sections, entry = Sections(key)
	if code == "B" or code == "K" then
		return {
			title = (code == "B" and "Sacs" or "Banque") .. " de " .. P.GetDisplayName(key),
			data = sections[code],
			version = entry and tonumber(entry.t[code]),
			missing = code == "K" and "Banque pas encore relevée : ouvrez-la une fois avec ce personnage."
				or "Sacs pas encore relevés.",
		}
	elseif code == "A" then
		local bank = WarbandBanks()[AccountOf(key)]
		return {
			title = "Banque de bataillon",
			data = bank and bank.data,
			version = bank and bank.version,
			missing = "Banque de bataillon pas encore relevée : ouvrez une fois une banque.",
		}
	end
	local guild = (sections.I or {}).gu
	local bank = guild and GuildBanks()[guild]
	return {
		title = guild and ("Banque de guilde " .. guild) or "Banque de guilde",
		data = bank and bank.data,
		version = bank and bank.version,
		missing = guild and "Banque de guilde pas encore relevée : ouvrez-la une fois (avec un personnage de la guilde)."
			or "Ce personnage n'a pas de guilde.",
	}
end

local REOPEN_HINT_SHORT = {
	B = "sacs relus aussitôt",
	K = "à rouvrir pour la relever",
	A = "à rouvrir pour la relever",
	G = "à rouvrir pour la relever",
}

-- Infobulle d'un bouton : nombre d'objets, d'objets différents, date du relevé.
local function OwnContainerTooltip(owner, code)
	local container = OwnContainer(code)
	GameTooltip:SetOwner(owner, "ANCHOR_BOTTOM")
	GameTooltip:AddLine(container.title)
	if container.data then
		local total, distinct = ContainerCount(container.data)
		GameTooltip:AddLine(total .. " objets (" .. distinct .. " différents)", 1, 1, 1)
		local money = code == "G" and tonumber(container.data.m)
		if money then
			GameTooltip:AddLine(FormatGold(money), 1, 1, 1)
		end
		if container.version then
			GameTooltip:AddLine("Relevé " .. FormatWhen(container.version), 0.6, 0.6, 0.6)
		end
		GameTooltip:AddLine("Clic : contenu détaillé", 0.6, 0.6, 0.6)
		GameTooltip:AddLine("Clic droit : remettre à zéro (" .. REOPEN_HINT_SHORT[code] .. ")", 0.6, 0.6, 0.6, true)
	else
		GameTooltip:AddLine(container.missing, 0.6, 0.6, 0.6, true)
	end
	GameTooltip:Show()
end

-- Clic droit : remise à zéro du relevé (ns.ResetSection, Data.lua) ; il faut rouvrir la banque
-- pour le relever de nouveau (les sacs sont relus aussitôt).
local REOPEN_HINT = {
	B = "Les sacs sont relus aussitôt.",
	K = "Rouvrez la banque avec ce personnage pour la relever de nouveau.",
	A = "Rouvrez une banque (avec un personnage de ce compte) pour relever de nouveau la banque de bataillon.",
	G = "Rouvrez la banque de guilde pour la relever de nouveau.",
}

local function ShowOwnContainerMenu(owner, code)
	if not (MenuUtil and MenuUtil.CreateContextMenu) then
		return
	end
	local container = OwnContainer(code)
	MenuUtil.CreateContextMenu(owner, function(_, root)
		root:CreateTitle(container.title)
		root:CreateButton("Remettre à zéro", function()
			ns.ResetSection(code)
			if UIErrorsFrame then
				UIErrorsFrame:AddMessage(container.title .. " : relevé effacé. " .. REOPEN_HINT[code], 1, 0.82, 0)
			end
			ns.Refresh()
		end)
	end)
end

-- Clic : fiche épinglée du contenu (relue à chaque rafraîchissement).
local function OpenOwnContainer(code)
	local container = OwnContainer(code)
	OpenCard(container.title, function()
		return ContainerEntries(OwnContainer(code).data)
	end, container.missing)
end

-- Infobulle au survol d'un personnage : ses lignes de détail, et les actions.
local function CharacterTooltip(key)
	local lines = { CharacterName(key) .. Gray("  " .. key) }
	for _, entry in ipairs(CharacterEntries(key)) do
		if entry.right and P.LIST_TOOLTIP_COLUMNS then
			lines[#lines + 1] = { entry.text, entry.right } -- deux colonnes (Polypode 0.51.4)
		elseif entry.right then
			lines[#lines + 1] = entry.text .. "     " .. entry.right
		else
			lines[#lines + 1] = entry.text
		end
		if entry.note then
			lines[#lines + 1] = "      " .. entry.note
		end
	end
	return lines
end

-- Infobulle d'un bouton d'action : titre en jaune, résumé (summary) en bleu clair, puis le texte
-- (rouge si error : pourquoi le bouton est grisé).
local function ShowActionTooltip(owner, anchor, tip)
	GameTooltip:SetOwner(owner, anchor)
	GameTooltip:AddLine(tip[1], 1, 0.82, 0)
	if tip.summary then
		GameTooltip:AddLine(tip.summary, 0.4, 0.8, 1, true)
	end
	if tip.error then
		GameTooltip:AddLine(tip[2], 1, 0.3, 0.3, true)
	else
		GameTooltip:AddLine(tip[2], 1, 1, 1, true)
	end
	GameTooltip:Show()
end

-- Bouton d'action et ligne d'état d'une fiche (card.action = { update(bouton, état), onClick,
-- tooltip() → { titre, texte, summary, error } }), ou masqués si elle n'en a pas.
local function UpdateCardAction(card)
	local action = card.action
	card.actionButton:SetShown(action ~= nil)
	card.statusText:SetShown(action ~= nil)
	if action then
		action.update(card.actionButton, card.statusText)
	end
end

-- ÉQUIPEMENT EN ICÔNES (fiche épinglée d'un personnage) : disposition de la fenêtre de
-- personnage de WoW, 8 emplacements à gauche, 8 à droite, les armes en bas ; la liste des autres
-- informations au milieu. Infobulle de l'objet (enchantement, gemmes, améliorations) au survol,
-- clic = infobulle épinglée (ShowItem). Emplacement vide : fond d'emplacement de Blizzard.
local GEAR_LEFT = { 1, 2, 3, 15, 5, 4, 19, 9 } -- tête, cou, épaules, dos, torse, chemise, tabard, poignets
local GEAR_RIGHT = { 10, 6, 7, 8, 11, 12, 13, 14 } -- mains, taille, jambes, pieds, anneaux, bijoux
local GEAR_BOTTOM = { 16, 17 } -- main droite, main gauche
local GEAR_ICON, GEAR_GAP, GEAR_MARGIN = 34, 4, 10
local GEAR_COLUMN_HEIGHT = #GEAR_LEFT * (GEAR_ICON + GEAR_GAP) - GEAR_GAP

local function CreateGearButton(parent, slot)
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(GEAR_ICON, GEAR_ICON)
	button.slot = slot
	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetAllPoints()
	button.border = button:CreateTexture(nil, "OVERLAY")
	button.border:SetTexture("Interface\\Common\\WhiteIconFrame")
	button.border:SetAllPoints()
	button.level = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	button.level:SetPoint("BOTTOMRIGHT", -2, 2)
	button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		if self.link then
			GameTooltip:SetHyperlink(self.link)
		else
			GameTooltip:AddLine(_G[SLOT_NAMES[self.slot]] or ("Emplacement " .. self.slot))
			GameTooltip:AddLine("Vide", 0.6, 0.6, 0.6)
		end
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", GameTooltip_Hide)
	button:SetScript("OnClick", function(self)
		if self.link then
			ShowItem(self.link)
		end
	end)
	return button
end

-- Crée (une fois) les emplacements d'une fiche.
local function EnsureGear(card)
	if card.gear then
		return card.gear
	end
	local gear = {}
	for index, slot in ipairs(GEAR_LEFT) do
		local button = CreateGearButton(card, slot)
		button:SetPoint("TOPLEFT", GEAR_MARGIN, -32 - (index - 1) * (GEAR_ICON + GEAR_GAP))
		gear[slot] = button
	end
	for index, slot in ipairs(GEAR_RIGHT) do
		local button = CreateGearButton(card, slot)
		button:SetPoint("TOPRIGHT", -GEAR_MARGIN, -32 - (index - 1) * (GEAR_ICON + GEAR_GAP))
		gear[slot] = button
	end
	for index, slot in ipairs(GEAR_BOTTOM) do
		local button = CreateGearButton(card, slot)
		local offset = (index == 1 and -1 or 1) * (GEAR_ICON + GEAR_GAP) / 2
		button:SetPoint("BOTTOM", card, "BOTTOM", offset, GEAR_MARGIN)
		gear[slot] = button
	end
	card.gear = gear
	return gear
end

-- Remplit les emplacements d'après l'équipement relevé du personnage key (nil = masqués).
local function FillGear(card, key)
	local equipment = key and Sections(key).E
	if not key then
		if card.gear then
			for _, button in pairs(card.gear) do
				button:Hide()
			end
		end
		return
	end
	for slot, button in pairs(EnsureGear(card)) do
		local itemID, level, link = EquippedItem(equipment and equipment[tostring(slot)])
		button.link = itemID and link or nil
		if itemID then
			ItemName(itemID) -- demande l'objet au serveur s'il n'est pas connu (qualité, icône)
			button.icon:SetTexture(ItemIcon(itemID) or 134400) -- point d'interrogation à défaut
			button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
			button.icon:SetDesaturated(false)
			local quality = C_Item and C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(link)
			local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
			button.border:SetShown(color ~= nil)
			if color then
				button.border:SetVertexColor(color.r, color.g, color.b)
			end
			button.level:SetText((level or 0) > 0 and level or "")
		else
			local getSlotInfo = C_PaperDollInfo and C_PaperDollInfo.GetInventorySlotInfo or GetInventorySlotInfo
			local _, emptyTexture = getSlotInfo(SLOT_NAMES[slot])
			button.icon:SetTexture(emptyTexture)
			button.icon:SetTexCoord(0, 1, 0, 1)
			button.icon:SetDesaturated(true)
			button.border:Hide()
			button.level:SetText("")
		end
		button:Show()
	end
end

-- GRILLE D'ICÔNES (option « icons ») : le contenu d'un sac ou d'une banque (lignes de
-- ContainerEntries, entries.items) en icônes comme les sacs de WoW, GRID_COLUMNS par rangée ;
-- chaque rangée est une ligne de la liste défilante de la fiche (P.CreateScrollList avec
-- opts.rowHeight, Polypode 0.56.0). Nombre en bas à droite, bordure de qualité, infobulle de
-- l'objet au survol, clic = infobulle épinglée (ShowItem).
local GRID_ICON, GRID_GAP, GRID_COLUMNS = 36, 4, 10
local GRID_CELL = GRID_ICON + GRID_GAP

-- Nombre affiché sur une icône (abrégé au-delà de 9 999).
local function ShortCount(count)
	if count >= 10000 then
		return math.floor(count / 1000) .. "k"
	end
	return count > 1 and tostring(count) or ""
end

local function CreateGridButton(parent)
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(GRID_ICON, GRID_ICON)
	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetAllPoints()
	button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	button.border = button:CreateTexture(nil, "OVERLAY")
	button.border:SetTexture("Interface\\Common\\WhiteIconFrame")
	button.border:SetAllPoints()
	button.count =button:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	button.count:SetPoint("BOTTOMRIGHT", -2, 2)
	button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetItemByID(self.item)
		GameTooltip:AddLine("Clic : infobulle de l'objet", 0.6, 0.6, 0.6)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", GameTooltip_Hide)
	button:SetScript("OnClick", function(self)
		ShowItem(self.item)
	end)
	return button
end

-- Habille une rangée de la grille (lignes recyclées : boutons créés une fois, remplis à chaque
-- affichage) ; data.items = entrées de ContainerEntries de cette rangée.
local function FillGridRow(row, data)
	row.icons = row.icons or {}
	for index = 1, GRID_COLUMNS do
		local entry = data.items[index]
		local button = row.icons[index]
		if entry and not button then
			button = CreateGridButton(row)
			button:SetPoint("LEFT", (index - 1) * GRID_CELL, 0)
			row.icons[index] = button
		end
		if button then
			button.item = entry and entry.item
			button:SetShown(entry ~= nil)
		end
		if entry then
			button.icon:SetTexture(ItemIcon(entry.item) or 134400) -- point d'interrogation à défaut
			local quality = C_Item and C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(entry.item)
			-- Bordure à partir de « inhabituel » (vert), comme les sacs de WoW.
			local color = quality and quality >= 2 and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
			button.border:SetShown(color and true or false)
			if color then
				button.border:SetVertexColor(color.r, color.g, color.b)
			end
			button.count:SetText(ShortCount(entry.count))
			if GameTooltip:IsOwned(button) then
				button:GetScript("OnEnter")(button)
			end
		end
	end
end

-- Lignes d'une fiche regroupées en rangées d'icônes.
local function GridRows(entries)
	local rows = {}
	for index, entry in ipairs(entries) do
		local rowIndex = math.floor((index - 1) / GRID_COLUMNS) + 1
		rows[rowIndex] = rows[rowIndex] or { items = {} }
		table.insert(rows[rowIndex].items, entry)
	end
	return rows
end

-- Remplit une fiche (titre et lignes) et ajuste sa hauteur à son contenu.
local function FillCard(card)
	local entries = card.build() or {}
	local extra = card.action and CARD_STATUS_HEIGHT or 0
	card.TitleText:SetText(card.title)
	card.TitleText:SetPoint("RIGHT", card.action and card.actionButton or card.CloseButton, "LEFT", -4, 0)
	-- Contenu d'un sac ou d'une banque en icônes (option) : liste en rangées d'icônes.
	local grid = entries.items and ContainerView() == "icons" and card.gridPanel ~= nil
	if card.gridPanel then
		card.gridPanel:SetShown(grid)
	end
	card.panel:SetShown(not grid)
	local listPanel = grid and card.gridPanel or card.panel
	if grid then
		entries = GridRows(entries)
	end
	local listHeight = math.max(#entries, 1) * (grid and GRID_CELL or CARD_ROW_HEIGHT) + 16
	card.panel:ClearAllPoints()
	FillGear(card, card.gearKey)
	if card.gearKey then
		-- Liste entre les deux colonnes d'emplacements, armes dessous.
		local side = GEAR_MARGIN + GEAR_ICON + 6
		card.panel:SetPoint("TOPLEFT", side, -32 - extra)
		card.panel:SetPoint("BOTTOMRIGHT", -side, GEAR_MARGIN + GEAR_ICON + 6)
		card:SetHeight(40 + extra + math.max(GEAR_COLUMN_HEIGHT, math.min(listHeight, CARD_MAX_HEIGHT - 40))
			+ GEAR_ICON + GEAR_MARGIN)
	else
		listPanel:ClearAllPoints()
		listPanel:SetPoint("TOPLEFT", 8, -32 - extra)
		listPanel:SetPoint("BOTTOMRIGHT", -8, 8)
		card:SetHeight(math.min(CARD_MAX_HEIGHT, 40 + extra + listHeight))
	end
	UpdateCardAction(card)
	P.SetListData(listPanel, entries)
	listPanel.emptyText:SetText(card.empty or "Vide.")
end

local function CreateCard()
	local card = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
	card:SetSize(CARD_WIDTH, 200)
	card:SetFrameStrata("DIALOG")
	card:SetToplevel(true)
	card:SetClampedToScreen(true)
	card:SetMovable(true)
	card:EnableMouse(true)
	card:SetBackdrop({
		bgFile = "Interface/Tooltips/UI-Tooltip-Background",
		edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
		edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 },
	})
	card:SetBackdropColor(0, 0, 0, 0.92)

	local title = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", 12, -12)
	title:SetPoint("RIGHT", -12, 0)
	title:SetJustifyH("LEFT")
	title:SetWordWrap(false)
	card.TitleText = title

	-- Glisser déplace la fiche ; la croix la ferme.
	card:RegisterForDrag("LeftButton")
	card:SetScript("OnDragStart", card.StartMoving)
	card:SetScript("OnDragStop", card.StopMovingOrSizing)

	local closeBtn = CreateFrame("Button", nil, card, "UIPanelCloseButton")
	closeBtn:SetPoint("TOPRIGHT", -2, -2)
	card.CloseButton = closeBtn

	-- Bouton d'action (fiche Dépôts : « Ranger ») à gauche de la croix, ligne d'état dessous ;
	-- l'infobulle reste visible bouton grisé (elle dit pourquoi).
	local actionBtn = CreateFrame("Button", nil, card, "UIPanelButtonTemplate")
	actionBtn:SetSize(80, 20)
	actionBtn:SetPoint("RIGHT", closeBtn, "LEFT", -2, 0)
	actionBtn:SetMotionScriptsWhileDisabled(true)
	actionBtn:SetScript("OnClick", function()
		if card.action then
			card.action.onClick()
			UpdateCardAction(card)
		end
	end)
	actionBtn:SetScript("OnEnter", function(self)
		local tip = card.action and card.action.tooltip()
		if tip then
			ShowActionTooltip(self, "ANCHOR_TOP", tip)
		end
	end)
	actionBtn:SetScript("OnLeave", GameTooltip_Hide)
	actionBtn:Hide()
	card.actionButton = actionBtn
	if P.SkinButton then
		P.SkinButton(actionBtn)
	end
	title:SetPoint("RIGHT", closeBtn, "LEFT", -4, 0)

	local statusText = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	statusText:SetPoint("TOPLEFT", 12, -34)
	statusText:SetPoint("RIGHT", -12, 0)
	statusText:SetJustifyH("LEFT")
	statusText:SetWordWrap(false)
	statusText:Hide()
	card.statusText = statusText

	-- État du bouton relu régulièrement : la banque affichée (personnage / bataillon) change
	-- sans événement.
	local elapsedSince = 0
	card:SetScript("OnUpdate", function(self, elapsed)
		elapsedSince = elapsedSince + elapsed
		if self.action and elapsedSince >= 0.25 then
			elapsedSince = 0
			UpdateCardAction(self)
		end
	end)

	local panel = P.CreatePanel(card, "")
	panel:SetPoint("TOPLEFT", 8, -32)
	panel:SetPoint("BOTTOMRIGHT", -8, 8)
	panel:SetBackdropColor(0, 0, 0, 0)
	panel:SetBackdropBorderColor(0, 0, 0, 0)
	P.CreateScrollList(panel, function(data)
		return data.text
	end, 6, {
		inset = 4,
		onClick = function(data)
			if data.detail then
				data.detail()
			end
		end,
		tooltip = function(data)
			if data.note then
				return { data.note, data.hint }
			end
			return data.hint and { data.hint } or nil
		end,
		-- Colonne de droite (data.right) dans la moitié droite de la ligne.
		decorate = function(row, data)
			if not row.rightText then
				row.rightText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
				row.rightText:SetPoint("LEFT", row, "CENTER", 4, 0)
				row.rightText:SetPoint("RIGHT", -4, 0)
				row.rightText:SetJustifyH("LEFT")
				row.rightText:SetWordWrap(false)
			end
			row.rightText:SetText(data.right or "")
			row.rightText:SetShown(data.right ~= nil)
			-- Zone cliquable de la colonne de droite (rightDetail : le second métier de la ligne).
			if not row.rightButton then
				row.rightButton = CreateFrame("Button", nil, row)
				row.rightButton:SetPoint("TOPLEFT", row, "TOP", 0, 0)
				row.rightButton:SetPoint("BOTTOMRIGHT")
				row.rightButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
				local highlight = row.rightButton:CreateTexture(nil, "HIGHLIGHT")
				highlight:SetAllPoints()
				highlight:SetColorTexture(1, 1, 1, 0.08)
				row.rightButton:SetScript("OnClick", function(self)
					local current = self:GetParent().data
					if current and current.rightDetail then
						current.rightDetail()
					end
				end)
				row.rightButton:SetScript("OnEnter", function(self)
					GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
					GameTooltip:AddLine("Clic : objets et recettes de ce métier", 1, 1, 1)
					GameTooltip:Show()
				end)
				row.rightButton:SetScript("OnLeave", GameTooltip_Hide)
			end
			row.rightButton:SetShown(data.rightDetail ~= nil)
			-- Surbrillance de la ligne (texture HIGHLIGHT de P.CreateScrollList) : moitié gauche seulement
			-- quand la droite a sa propre zone cliquable, pour ne montrer que le métier survolé.
			if row.rowHighlight == nil then
				row.rowHighlight = false
				for _, region in ipairs({ row:GetRegions() }) do
					if region.GetDrawLayer and region:GetDrawLayer() == "HIGHLIGHT" then
						row.rowHighlight = region
						break
					end
				end
			end
			if row.rowHighlight then
				row.rowHighlight:ClearAllPoints()
				row.rowHighlight:SetPoint("TOPLEFT", row, "TOPLEFT")
				if data.rightDetail then
					row.rowHighlight:SetPoint("BOTTOMRIGHT", row, "BOTTOM")
				else
					row.rowHighlight:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT")
				end
			end
			row.text:SetPoint("RIGHT", data.right and row.rightText or row, data.right and "LEFT" or "RIGHT",
				data.right and -4 or -4, 0)
		end,
	})
	card.panel = panel

	-- Grille d'icônes (option « icons ») : rangées hautes, seulement si Polypode règle la hauteur
	-- des lignes (0.56.0) ; sinon le contenu reste en liste.
	if P.LIST_ROW_HEIGHT then
		local gridPanel = P.CreatePanel(card, "")
		gridPanel:SetBackdropColor(0, 0, 0, 0)
		gridPanel:SetBackdropBorderColor(0, 0, 0, 0)
		P.CreateScrollList(gridPanel, function()
			return ""
		end, 6, { inset = 4, rowHeight = GRID_CELL, decorate = FillGridRow })
		gridPanel:Hide()
		card.gridPanel = gridPanel
	end
	P.SkinFrame(card)
	cards[#cards + 1] = card
	return card
end

-- Ouvre une fiche épinglée titrée title, dont build() renvoie les lignes (relu à chaque
-- rafraîchissement de la fenêtre), près du curseur, décalée des fiches déjà ouvertes ; empty :
-- texte si vide ; action : bouton et ligne d'état (voir UpdateCardAction), nil = aucun.
OpenCard = function(title, build, empty, action, gearKey)
	local card
	-- Une seule fiche par personnage : déjà ouverte, elle est ramenée au premier plan, sur place.
	if gearKey then
		for _, existing in ipairs(cards) do
			if existing:IsShown() and existing.gearKey == gearKey then
				existing:Raise()
				FillCard(existing)
				return existing
			end
		end
	end
	for _, existing in ipairs(cards) do
		if not existing:IsShown() then
			card = existing
			break
		end
	end
	card = card or CreateCard()
	card.title, card.build, card.empty, card.action, card.gearKey = title, build, empty, action, gearKey
	local scale = UIParent:GetEffectiveScale()
	local x, y = GetCursorPosition()
	card:ClearAllPoints()
	card:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale + 16, y / scale + 16)
	card:Show()
	card:Raise()
	FillCard(card)
	return card
end

-- Fiches ouvertes : relues (noms d'objets arrivés, données reçues).
local function RefreshCards()
	for _, card in ipairs(cards) do
		if card:IsShown() then
			FillCard(card)
		end
	end
end

-- DÉPÔTS POSSIBLES (bouton « Dépôts » de la barre de titre) : pour chaque personnage, les objets
-- de ses sacs qui existent déjà dans sa banque, dans la banque de bataillon de son compte ou dans
-- la banque de guilde de sa guilde, et qui pourraient donc y être déposés. Une fiche épinglée
-- (même fonctionnement que les autres), relue à chaque rafraîchissement.
local depositCard

local function DepositEntries()
	local entries = {}
	local warbands, guilds = WarbandBanks(), GuildBanks()
	for _, item in ipairs(P.SortedKeyItems(ns.GetKeys(), IsOwn)) do
		local key = item.key
		local sections = Sections(key)
		local identity = sections.I or {}
		local warband = warbands[AccountOf(key)]
		local guildBank = identity.gu and guilds[identity.gu]
		local targets = {
			{ "Banque", sections.K },
			{ "Banque de bataillon", warband and warband.data },
			{ "Banque de guilde" .. (identity.gu and (" (" .. identity.gu .. ")") or ""), guildBank and guildBank.data },
		}
		local block = {}
		for _, target in ipairs(targets) do
			local lines = {}
			for itemKey, count in pairs(target[2] and sections.B or {}) do
				local itemID = tonumber(tostring(itemKey):match("^i(%d+)$"))
				local stored = itemID and tonumber(target[2][itemKey])
				if stored then
					local name, colored = ItemName(itemID)
					lines[#lines + 1] = {
						sort = Normalize(name or ("~" .. itemID)),
						text = "      " .. Icon(ItemIcon(itemID)) .. " " .. (colored or ("objet n° " .. itemID))
							.. " ×" .. count .. Gray("  (déjà " .. stored .. ")") .. DETAIL_MARK,
						detail = function()
							ShowItem(itemID)
						end,
						hint = "Clic : infobulle de l'objet",
					}
				end
			end
			if #lines > 0 then
				table.sort(lines, function(a, b)
					return a.sort < b.sort
				end)
				block[#block + 1] = { text = "   |cffffd200" .. target[1] .. "|r" }
				for _, line in ipairs(lines) do
					block[#block + 1] = line
				end
			end
		end
		if #block > 0 then
			if #entries > 0 then
				entries[#entries + 1] = { text = " " }
			end
			entries[#entries + 1] = { text = CharacterName(key) }
			for _, line in ipairs(block) do
				entries[#entries + 1] = line
			end
		end
	end
	return entries
end

-- Bouton « Ranger » de la fiche des dépôts (Deposit.lua) : banque du personnage, de bataillon
-- ou de guilde ; grisé si aucune n'est ouverte, si la banque de guilde l'est en même temps
-- qu'une autre, ou sans droit de dépôt en guilde (l'infobulle dit pourquoi).
local DEPOSIT_ACTION = {
	update = function(button, status)
		local running = ns.IsDepositRunning()
		button:SetText(running and "Arrêter" or "Ranger")
		button:SetEnabled(running or (ns.CanDeposit()) or false)
		status:SetText(ns.GetDepositStatus() or Gray("Ranger : ouvrez une banque (personnage, bataillon ou guilde)."))
	end,
	onClick = function()
		if ns.IsDepositRunning() then
			ns.StopDeposit()
		else
			ns.StartDeposit()
		end
	end,
	tooltip = function()
		local summary = "Tout objet des sacs qui existe déjà dans une banque y est rangé."
		if ns.IsDepositRunning() then
			return { "Rangement en cours", "Clic : arrêter.", summary = summary }
		end
		local ok, reason = ns.CanDeposit()
		if not ok then
			return { "Ranger dans la banque", reason, summary = summary, error = true }
		end
		return { "Ranger dans la banque", summary = summary, "Dépose les objets des sacs qui se trouvent déjà dans une banque "
			.. "ouverte, et seulement eux : dans la banque du personnage s'ils y sont, sinon dans la banque de "
			.. "bataillon ; ou dans la banque de guilde (onglets où vous pouvez déposer) ; sur la pile "
			.. "existante, sinon dans le même onglet, sinon ailleurs dans cette banque." }
	end,
}

-- Bouton « Ranger » de l'en-tête de la fenêtre : même action que celui de la fiche Dépôts, sans
-- ligne d'état (NO_STATUS).
local rangerButton
local NO_STATUS = { SetText = function() end }

local function UpdateRangerButton()
	if rangerButton and rangerButton:IsVisible() then
		DEPOSIT_ACTION.update(rangerButton, NO_STATUS)
	end
end

local function ShowDepositTooltip(owner, anchor)
	ShowActionTooltip(owner, anchor, DEPOSIT_ACTION.tooltip())
end

-- Rangement en cours : bouton et ligne d'état de la fiche des dépôts, bouton de l'en-tête.
function ns.UpdateDepositControls()
	if depositCard and depositCard:IsShown() and depositCard.action == DEPOSIT_ACTION then
		UpdateCardAction(depositCard)
	end
	UpdateRangerButton()
end

-- Ouvre la fiche des dépôts possibles, ou la ferme si elle est ouverte.
local function ToggleDeposits()
	if depositCard and depositCard:IsShown() and depositCard.build == DepositEntries then
		depositCard:Hide()
		return
	end
	depositCard = OpenCard("Dépôts possibles", DepositEntries,
		"Rien à déposer (ou banques pas encore relevées : ouvrez-les une fois).", DEPOSIT_ACTION)
end

-- RECHERCHE D'OBJETS ------------------------------------------------------------------------------

-- Objets dont le nom contient query : { itemID, name, colored, total, holders, warband }.
local function SearchItems(query)
	local needle = Normalize(query)
	local found = {} -- [itemID] = résultat
	local function Add(itemID, holderKey, place, count)
		itemID = tonumber(itemID)
		if not itemID then
			return
		end
		local result = found[itemID]
		if result == false then
			return
		end
		if not result then
			local name, colored = ItemName(itemID)
			if not name or not Normalize(name):find(needle, 1, true) then
				if name then
					found[itemID] = false -- ne correspond pas (nom inconnu : retenté au prochain rafraîchissement)
				end
				return
			end
			result = { itemID = itemID, name = name, colored = colored, total = 0, holders = {}, order = {} }
			found[itemID] = result
		end
		local holder = result.holders[holderKey]
		if not holder then
			holder = { key = holderKey }
			result.holders[holderKey] = holder
			result.order[#result.order + 1] = holderKey
		end
		holder[place] = (holder[place] or 0) + count
		result.total = result.total + count
	end
	for key in pairs(ns.GetKeys()) do
		local sections = Sections(key)
		for _, place in ipairs({ "B", "K" }) do
			for itemKey, count in pairs(sections[place] or {}) do
				Add(itemKey:match("^i(%d+)$"), key, place, tonumber(count) or 0)
			end
		end
		for _, value in pairs(sections.E or {}) do
			Add((EquippedItem(value)), key, "E", 1)
		end
	end
	for account, bank in pairs(WarbandBanks()) do
		for itemKey, count in pairs(bank.data) do
			Add(itemKey:match("^i(%d+)$"), "warband:" .. account, "A", tonumber(count) or 0)
		end
	end
	for guild, bank in pairs(GuildBanks()) do
		for itemKey, count in pairs(bank.data) do
			Add(tostring(itemKey):match("^i(%d+)$"), "guild:" .. guild, "G", tonumber(count) or 0)
		end
	end
	local results = {}
	for _, result in pairs(found) do
		if result then
			results[#results + 1] = result
		end
	end
	table.sort(results, function(a, b)
		return Normalize(a.name) < Normalize(b.name)
	end)
	return results
end

local function HolderName(holderKey)
	if holderKey:match("^warband:") then
		return "|cff00ccffBataillon|r"
	end
	local guild = holderKey:match("^guild:(.+)$")
	if guild then
		return "|cff40ff40Guilde " .. guild .. "|r"
	end
	return CharacterName(holderKey)
end

local function HolderCount(holder)
	return (holder.B or 0) + (holder.K or 0) + (holder.E or 0) + (holder.A or 0) + (holder.G or 0)
end

local function ResultRightText(result)
	local parts = {}
	for _, holderKey in ipairs(result.order) do
		parts[#parts + 1] = HolderName(holderKey) .. " ×" .. HolderCount(result.holders[holderKey])
	end
	return table.concat(parts, "  ")
end

local function ResultTooltip(result)
	local lines = { Icon(ItemIcon(result.itemID)) .. " " .. result.colored }
	for _, holderKey in ipairs(result.order) do
		local holder = result.holders[holderKey]
		local places = {}
		if holder.B then
			places[#places + 1] = "sacs " .. holder.B
		end
		if holder.K then
			places[#places + 1] = "banque " .. holder.K
		end
		if holder.E then
			places[#places + 1] = "équipé"
		end
		lines[#lines + 1] = HolderName(holderKey) .. " : " .. HolderCount(holder)
			.. (#places > 0 and not holder.A and Gray(" (" .. table.concat(places, ", ") .. ")") or "")
	end
	lines[#lines + 1] = "Total : " .. result.total
	return lines
end

-- CELLULES DU TABLEAU -----------------------------------------------------------------------------

-- Zone survolable d'une cellule d'en-tête : infobulle de la colonne (hover.tip).
local function CellHover(row, i)
	row.cellHovers = row.cellHovers or {}
	local hover = row.cellHovers[i]
	if not hover then
		-- En-tête de colonne : infobulle, et clic = trier par cette colonne (SetSort).
		hover = CreateFrame("Button", nil, row)
		hover:SetFrameLevel(row:GetFrameLevel() + 2)
		hover.column = i
		local highlight = hover:CreateTexture(nil, "HIGHLIGHT")
		highlight:SetAllPoints()
		highlight:SetColorTexture(1, 1, 1, 0.08)
		hover:SetScript("OnClick", function(self)
			if COLUMNS[self.column] and COLUMNS[self.column].sort then
				SetSort(self.column)
			end
		end)
		hover:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:AddLine(self.tip[1])
			GameTooltip:AddLine(self.tip[2], 1, 1, 1, true)
			if COLUMNS[self.column] and COLUMNS[self.column].sort then
				GameTooltip:AddLine("Clic : trier par cette colonne (clic suivant : ordre inverse)", 0.6, 0.6, 0.6, true)
			end
			GameTooltip:Show()
		end)
		hover:SetScript("OnLeave", GameTooltip_Hide)
		row.cellHovers[i] = hover
	end
	return hover
end

-- Place les cellules d'une ligne (lignes recyclées : tout est recalculé ici) ; renvoie la
-- cellule la plus à gauche, contre laquelle le nom s'arrête.
-- Colonnes placées de gauche à droite à partir de COLUMNS_START (40 %) de la largeur de la
-- fenêtre ; si elles ne tiennent pas de là jusqu'au bord droit, elles s'y recollent.
local COLUMNS_START = 0.4
local ROW_LEFT = 22 -- bord gauche des lignes dans la fenêtre (cadre de la liste + marge de la liste)

local function ColumnsStart(row)
	local total = 0
	for _, width in ipairs(columnWidths) do
		if width > 0 then
			total = total + width + COLUMN_GAP
		end
	end
	local rowWidth = (frame and frame:GetWidth() or 0) - 2 * ROW_LEFT
	local wanted = (frame and frame:GetWidth() or 0) * COLUMNS_START - ROW_LEFT
	return math.max(0, math.min(wanted, rowWidth - total + COLUMN_GAP - 4))
end

local function LayoutCells(row, data)
	row.cells = row.cells or {}
	for _, hover in pairs(row.cellHovers or {}) do
		hover:Hide()
	end
	local offset = ColumnsStart(row)
	local firstCell
	for i = 1, #columnWidths do
		local cell = row.cells[i]
		if not cell then
			cell = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
			cell:SetJustifyH("RIGHT")
			cell:SetWordWrap(false)
			row.cells[i] = cell
		end
		local width = columnWidths[i]
		if width > 0 and data.cells then
			cell:ClearAllPoints()
			cell:SetPoint("LEFT", row, "LEFT", offset, 0)
			cell:SetWidth(width)
			cell:SetJustifyH(COLUMNS[i] and COLUMNS[i].align or "RIGHT") -- à droite, sauf Métiers
			cell:SetText(data.cells[i] or "")
			cell:Show()
			offset = offset + width + COLUMN_GAP
			firstCell = firstCell or cell -- la plus à gauche : le nom s'arrête avant
			local tip = data.tips and data.tips[i]
			if tip then
				local hover = CellHover(row, i)
				hover.tip = tip
				hover:ClearAllPoints()
				hover:SetPoint("TOP", row, "TOP")
				hover:SetPoint("BOTTOM", row, "BOTTOM")
				hover:SetPoint("LEFT", cell, "LEFT", -COLUMN_GAP / 2, 0)
				hover:SetPoint("RIGHT", cell, "RIGHT", COLUMN_GAP / 2, 0)
				hover:Show()
			end
		else
			cell:Hide()
		end
	end
	for i = #columnWidths + 1, #row.cells do
		row.cells[i]:Hide()
	end
	return firstCell
end

-- FENÊTRE ---------------------------------------------------------------------------------------

local function IsSearching()
	local text = searchBox and searchBox:GetText() or ""
	return #text >= MIN_SEARCH, text
end

-- RECHERCHE DE RECETTES (champ sous celui des objets) : dans les recettes apprises relevées de
-- tous les personnages en mémoire (section R), par nom (celui du sort de la recette, sans accents
-- ni majuscules). Résultat : { id, name, holders = { { key, label } } } (label = extension).
local function IsRecipeSearching()
	local text = recipeBox and recipeBox:GetText() or ""
	return #text >= MIN_SEARCH, text
end

local function SearchRecipes(query)
	local needle = Normalize(query)
	local byID = {}
	for key in pairs(ns.GetKeys()) do
		local recipes = Sections(key).R or {}
		for itemKey, value in pairs(recipes) do
			local recipeID = tonumber(tostring(itemKey):match("^r(%d+)$") or "")
			if recipeID then
				local tier = recipes["c" .. tostring(value)]
				local label = tier and tostring(tier):match("^%d+/(.*)$") or ""
				local result = byID[recipeID]
				if result == nil then
					local name = SpellName(recipeID)
					result = name and Normalize(name):find(needle, 1, true) and { id = recipeID, name = name, holders = {} }
						or false
					byID[recipeID] = result
				end
				if result then
					result.holders[#result.holders + 1] = { key = key, label = label }
				end
			end
		end
	end
	local results = {}
	for _, result in pairs(byID) do
		if result then
			table.sort(result.holders, function(a, b)
				return Normalize(CharacterName(a.key)) < Normalize(CharacterName(b.key))
			end)
			results[#results + 1] = result
		end
	end
	table.sort(results, function(a, b)
		return Normalize(a.name) < Normalize(b.name)
	end)
	return results
end

local function RecipeRightText(recipe)
	local names = {}
	for _, holder in ipairs(recipe.holders) do
		names[#names + 1] = CharacterName(holder.key)
	end
	return table.concat(names, "  ")
end

local function RecipeTooltip(recipe)
	local icon = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(recipe.id)
	local lines = { Icon(icon) .. " " .. recipe.name }
	for _, holder in ipairs(recipe.holders) do
		lines[#lines + 1] = CharacterName(holder.key) .. (holder.label ~= "" and Gray("  " .. holder.label) or "")
	end
	lines[#lines + 1] = Gray("Clic : infobulle de la recette")
	return lines
end

local function ShowForgetMenu(key)
	if not (MenuUtil and MenuUtil.CreateContextMenu) or IsOwn(key) then
		return
	end
	MenuUtil.CreateContextMenu(frame, function(_, root)
		root:CreateTitle(P.GetDisplayName(key, true))
		root:CreateButton("Oublier ce personnage", function()
			ns.Forget(key)
			ns.Refresh()
		end)
	end)
end

local function Build()
	local settings = WindowSettings()
	frame = CreateFrame("Frame", "PolypodeDataFrame", UIParent, "BackdropTemplate")
	frame:SetSize(math.max(settings.width or DEFAULT_WIDTH, MIN_WIDTH),
		math.max(settings.height or DEFAULT_HEIGHT, MIN_HEIGHT))
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("DIALOG")
	frame:SetMovable(true)
	frame:SetResizable(true)
	frame:SetResizeBounds(MIN_WIDTH, MIN_HEIGHT)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame:SetBackdrop({
		bgFile = "Interface/Tooltips/UI-Tooltip-Background",
		edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
		edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 },
	})
	frame:SetBackdropColor(0, 0, 0, 0.9)
	frame:Hide()
	tinsert(UISpecialFrames, "PolypodeDataFrame") -- Échap ferme la fenêtre

	-- Bouton « Dépôts » à gauche, puis le titre ; le champ de recherche occupe la droite.
	local depositBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	depositBtn:SetSize(70, 20)
	depositBtn:SetPoint("TOPLEFT", 6, -3)
	depositBtn:SetText("Dépôts")
	depositBtn:SetScript("OnClick", ToggleDeposits)
	depositBtn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine("Dépôts possibles")
		GameTooltip:AddLine("Pour chaque personnage, les objets de ses sacs qui existent déjà dans sa banque, "
			.. "la banque de bataillon ou la banque de guilde, et qui pourraient y être déposés.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	depositBtn:SetScript("OnLeave", GameTooltip_Hide)
	P.ui.dataDepositButton = depositBtn

	-- « Ranger » : la même action que le bouton de la fiche Dépôts (qui le garde aussi) ; état relu
	-- toutes les 0,25 s (la banque ouverte change sans événement), infobulle visible grisé.
	rangerButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	rangerButton:SetSize(70, 20)
	rangerButton:SetPoint("LEFT", depositBtn, "RIGHT", 4, 0)
	rangerButton:SetText("Ranger")
	rangerButton:SetMotionScriptsWhileDisabled(true)
	rangerButton:SetScript("OnClick", function()
		DEPOSIT_ACTION.onClick()
		ns.UpdateDepositControls()
	end)
	rangerButton:SetScript("OnEnter", function(self)
		ShowDepositTooltip(self, "ANCHOR_BOTTOM")
	end)
	rangerButton:SetScript("OnLeave", GameTooltip_Hide)
	local sinceUpdate = 0
	rangerButton:SetScript("OnUpdate", function(_, elapsed)
		sinceUpdate = sinceUpdate + elapsed
		if sinceUpdate >= 0.25 then
			sinceUpdate = 0
			UpdateRangerButton()
		end
	end)
	rangerButton:SetScript("OnShow", UpdateRangerButton)
	P.ui.dataRangerButton = rangerButton

	-- Sacs, banque, banque de bataillon, banque de guilde du personnage joué (icônes) : infobulle =
	-- nombre d'objets (et différents), clic = fiche du contenu.
	local previous = rangerButton
	local containerButtons = {}
	for index, spec in ipairs(OWN_CONTAINERS) do
		local button = CreateFrame("Button", nil, frame)
		button:SetSize(CONTAINER_ICON_SIZE, CONTAINER_ICON_SIZE)
		button:SetPoint("LEFT", previous, "RIGHT", index == 1 and 8 or 4, 0)
		local icon = button:CreateTexture(nil, "ARTWORK")
		icon:SetAllPoints()
		if spec.atlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(spec.atlas) then
			icon:SetAtlas(spec.atlas)
		else
			icon:SetTexture(spec.texture)
			icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) -- sans le liseré des icônes
		end
		button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
		button:SetScript("OnMouseDown", function()
			icon:SetPoint("TOPLEFT", 1, -1) -- léger enfoncement au clic
		end)
		button:SetScript("OnMouseUp", function()
			icon:SetAllPoints()
		end)
		button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		button:SetScript("OnClick", function(self, mouseButton)
			if mouseButton == "RightButton" then
				ShowOwnContainerMenu(self, spec.code)
			else
				OpenOwnContainer(spec.code)
			end
		end)
		button:SetScript("OnEnter", function(self)
			OwnContainerTooltip(self, spec.code)
		end)
		button:SetScript("OnLeave", GameTooltip_Hide)
		containerButtons[#containerButtons + 1] = button
		previous = button
	end
	P.ui.dataContainerButtons = containerButtons

	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("LEFT", previous, "RIGHT", 10, 0)
	title:SetJustifyH("LEFT")
	title:SetWordWrap(false) -- tronqué si la fenêtre est étroite
	title:SetText("Données des personnages")
	frame.TitleText = title

	local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	closeBtn:SetPoint("TOPRIGHT", -4, -4)
	frame.CloseButton = closeBtn

	-- Deux champs côte à côte à droite du titre : objets, puis recettes (contre la croix).
	recipeBox = CreateFrame("EditBox", nil, frame, "SearchBoxTemplate")
	recipeBox:SetSize(SEARCH_WIDTH, 20)
	recipeBox:SetPoint("RIGHT", closeBtn, "LEFT", -8, 0)
	searchBox = CreateFrame("EditBox", nil, frame, "SearchBoxTemplate")
	searchBox:SetSize(SEARCH_WIDTH, 20)
	searchBox:SetPoint("RIGHT", recipeBox, "LEFT", -10, 0)
	title:SetPoint("RIGHT", searchBox, "LEFT", -12, 0)
	searchBox:SetAutoFocus(false)
	if searchBox.Instructions then
		searchBox.Instructions:SetText("Rech. objet")
	end
	searchBox:HookScript("OnTextChanged", function(self, userInput)
		if userInput and self:GetText() ~= "" and recipeBox and recipeBox:GetText() ~= "" then
			recipeBox:SetText("") -- une seule recherche à la fois
		end
		ns.Refresh()
	end)
	searchBox:HookScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:AddLine("Rechercher un objet")
		GameTooltip:AddLine("Dès " .. MIN_SEARCH .. " lettres : objets des sacs, banques et équipements de "
			.. "tous les personnages dont le nom contient le texte (sans accents ni majuscules).", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	searchBox:HookScript("OnLeave", GameTooltip_Hide)

	-- Recherche de recettes (créée plus haut, à droite de celle des objets).
	recipeBox:SetAutoFocus(false)
	if recipeBox.Instructions then
		recipeBox.Instructions:SetText("Rech. recette")
	end
	recipeBox:HookScript("OnTextChanged", function(self, userInput)
		if userInput and self:GetText() ~= "" and searchBox:GetText() ~= "" then
			searchBox:SetText("") -- une seule recherche à la fois
		end
		ns.Refresh()
	end)
	recipeBox:HookScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:AddLine("Rechercher une recette")
		GameTooltip:AddLine("Dès " .. MIN_SEARCH .. " lettres : recettes apprises de tous les personnages en "
			.. "mémoire dont le nom contient le texte (sans accents ni majuscules), avec qui les connaît. "
			.. "Recettes relevées en ouvrant la fenêtre de chaque métier.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	recipeBox:HookScript("OnLeave", GameTooltip_Hide)

	listPanel = P.CreatePanel(frame, "")
	listPanel:SetPoint("TOPLEFT", 12, -36)
	listPanel:SetPoint("BOTTOMRIGHT", -12, 12)

	-- Poignée de redimensionnement (coin bas-droit), taille gardée dans PolypodeDataDB.window.
	local grip = CreateFrame("Button", nil, frame)
	grip:SetSize(16, 16)
	grip:SetPoint("BOTTOMRIGHT", -2, 2)
	grip:SetFrameLevel(frame:GetFrameLevel() + 10)
	grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
	grip:SetScript("OnMouseDown", function()
		frame:StartSizing("BOTTOMRIGHT")
	end)
	grip:SetScript("OnMouseUp", function()
		frame:StopMovingOrSizing()
		local current = WindowSettings()
		current.width, current.height = frame:GetSize()
	end)
	frame.resizeGrip = grip
	-- Colonnes recalées à 40 % de la largeur pendant le redimensionnement (regroupé).
	local relayoutPending
	frame:HookScript("OnSizeChanged", function()
		if not relayoutPending then
			relayoutPending = true
			C_Timer.After(0.05, function()
				relayoutPending = nil
				ns.Refresh()
			end)
		end
	end)

	P.CreateScrollList(listPanel, function(data)
		if data.columnHeader then
			return "|cffffd200Personnage|r" .. SortMark(0)
		elseif data.result then
			return Icon(ItemIcon(data.result.itemID)) .. " " .. data.result.colored
				.. Gray("  ×" .. data.result.total)
		elseif data.recipe then
			local icon = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(data.recipe.id)
			return Icon(icon) .. " " .. data.recipe.name .. Gray("  ×" .. #data.recipe.holders)
		end
		-- Nom, puis sa guilde entre parenthèses (relevée avec l'identité).
		local identity = Sections(data.key).I
		local guild = identity and identity.gu
		return CharacterName(data.key) .. (guild and guild ~= "" and Gray(" (" .. guild .. ")") or "")
	end, nil, {
		onClick = function(data, button)
			if data.columnHeader then
				SetSort(0) -- tri par nom (hors colonnes : leurs en-têtes ont leur propre clic)
				return
			elseif data.recipe then
				ShowSpell(data.recipe.id)
				return
			elseif not data.key then
				return
			elseif button == "RightButton" then
				ShowForgetMenu(data.key)
			else
				local key = data.key
				OpenCard(CharacterName(key), function()
					return CharacterEntries(key, true)
				end, nil, nil, key)
			end
		end,
		tooltip = function(data)
			if data.columnHeader then
				return { "Personnage", "Clic : trier par nom (clic suivant : ordre inverse)" }
			elseif data.result then
				return ResultTooltip(data.result)
			elseif data.recipe then
				return RecipeTooltip(data.recipe)
			end
			return CharacterTooltip(data.key)
		end,
		-- Cellules du tableau (personnages) ou texte de droite (résultats de recherche).
		decorate = function(row, data)
			local firstCell = LayoutCells(row, data)
			if not row.rightText then
				row.rightText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
				row.rightText:SetPoint("LEFT", row, "CENTER", 0, 0)
				row.rightText:SetPoint("RIGHT", -4, 0)
				row.rightText:SetJustifyH("RIGHT")
				row.rightText:SetWordWrap(false)
			end
			if data.result or data.recipe then
				row.rightText:SetText(data.result and ResultRightText(data.result) or RecipeRightText(data.recipe))
				row.rightText:Show()
				row.text:SetPoint("RIGHT", row.rightText, "LEFT", -6, 0)
			elseif firstCell then
				row.rightText:Hide()
				row.text:SetPoint("RIGHT", firstCell, "LEFT", -COLUMN_GAP, 0)
			else
				row.rightText:Hide()
				row.text:SetPoint("RIGHT", -4, 0)
			end
		end,
	})

	P.ui.dataFrame = frame
	P.ui.dataPanel = listPanel
	P.ui.dataSearchBox = searchBox
	P.ui.dataRecipeBox = recipeBox

	P.SkinFrame(frame)
	P.SkinPanel(listPanel)
	if P.SkinButton then
		P.SkinButton(depositBtn) -- les icônes gardent leur image
		P.SkinButton(rangerButton)
	end
end

-- Remplit la liste, si la fenêtre est ouverte.
function ns.Refresh()
	namesPending = false -- remis à vrai par ItemName si un nom manque encore
	RefreshCards()
	if not frame or not frame:IsShown() then
		return
	end
	local searching, query = IsSearching()
	local recipeSearching, recipeQuery = IsRecipeSearching()
	local items, header, emptyText
	if recipeSearching and not searching then
		wipe(columnWidths)
		items = {}
		for _, recipe in ipairs(SearchRecipes(recipeQuery)) do
			items[#items + 1] = { recipe = recipe }
		end
		header = "Recherche de recette « " .. recipeQuery .. " » : " .. #items .. " recette(s)"
			.. (namesPending and Gray("  · chargement des noms…") or "")
		emptyText = "Aucune recette trouvée (recettes relevées en ouvrant la fenêtre de chaque métier)."
	elseif searching then
		wipe(columnWidths)
		items = {}
		for _, result in ipairs(SearchItems(query)) do
			items[#items + 1] = { result = result }
		end
		header = "Recherche « " .. query .. " » : " .. #items .. " objet(s)"
			.. (namesPending and Gray("  · chargement des noms…") or "")
		emptyText = "Aucun objet trouvé."
	else
		items = BuildCharacterItems()
		local count = #items - 1
		header = count .. " personnage(s)  " .. Gray("· or total : ") .. FormatGold(TotalGold())
		emptyText = "Aucune donnée enregistrée."
	end
	listPanel.header:SetText(header)
	listPanel.emptyText:SetText(emptyText)
	P.SetListData(listPanel, items)
end

P.RefreshData = ns.Refresh

-- Ouvre / ferme la fenêtre (bouton « Data », /poly data).
function P.ToggleData()
	if not frame then
		Build()
	end
	if frame:IsShown() then
		frame:Hide()
	else
		frame:Show()
		ns.Refresh()
	end
end

-- Noms d'objets reçus du serveur : la recherche en cours est relancée (regroupé).
local refreshPending
local itemEvents = CreateFrame("Frame")
for _, event in ipairs({ "ITEM_DATA_LOAD_RESULT", "SPELL_DATA_LOAD_RESULT" }) do -- noms d'objets / de recettes
	if not (C_EventUtils and C_EventUtils.IsEventValid) or C_EventUtils.IsEventValid(event) then
		itemEvents:RegisterEvent(event)
	end
end
itemEvents:SetScript("OnEvent", function()
	if refreshPending or not namesPending then
		return
	end
	refreshPending = true
	C_Timer.After(0.5, function()
		refreshPending = nil
		ns.Refresh()
	end)
end)

-- OPTIONS : sous-catégorie « Data » du panneau de Polypode (P.optionsCategory, créée à son
-- PLAYER_LOGIN), ou catégorie « Polypode Data » à part si elle manque.
local function BuildSettingsPanel()
	if not (Settings and Settings.RegisterProxySetting and Settings.CreateDropdown) then
		return
	end
	local category
	if P.optionsCategory and Settings.RegisterVerticalLayoutSubcategory then
		category = Settings.RegisterVerticalLayoutSubcategory(P.optionsCategory, "Data")
	else
		category = Settings.RegisterVerticalLayoutCategory("Polypode Data")
	end
	local setting = Settings.RegisterProxySetting(category, "POLYPODE_DATA_CONTAINER_VIEW",
		Settings.VarType.String, "Contenu des sacs et banques", "list",
		ContainerView,
		function(value)
			PolypodeDataDB.containerView = value
			RefreshCards()
		end)
	Settings.CreateDropdown(category, setting, function()
		local container = Settings.CreateControlTextContainer()
		container:Add("list", "Liste")
		container:Add("icons", "Icônes")
		return container:GetData()
	end, "Affichage du contenu détaillé d'un sac ou d'une banque (clic sur sa ligne dans la fiche d'un "
		.. "personnage, ou sur une icône de l'en-tête) : une ligne par objet avec son nom, ou une grille "
		.. "d'icônes comme les sacs de WoW (nombre sur l'icône, nom dans l'infobulle). Réglage commun à "
		.. "tous les personnages.")
	Settings.RegisterAddOnCategory(category)
end

local settingsEvents = CreateFrame("Frame")
settingsEvents:RegisterEvent("PLAYER_LOGIN")
settingsEvents:SetScript("OnEvent", function()
	-- Différé d'une image : Polypode crée P.optionsCategory à son propre PLAYER_LOGIN.
	C_Timer.After(0, BuildSettingsPanel)
end)

-- INTÉGRATION À POLYPODE -------------------------------------------------------------------------

if P.AddTitleButton then
	-- Clic droit (bouton de la fenêtre Polypode et celui de la colonne de la barre flottante) :
	-- la même action que « Ranger » (DEPOSIT_ACTION) ; sans banque utilisable, la raison s'affiche.
	P.AddTitleButton({
		text = "Data",
		width = 50,
		rightClick = true,
		onClick = function(_, mouseButton)
			if mouseButton ~= "RightButton" then
				P.ToggleData()
				return
			end
			if not ns.IsDepositRunning() then
				local ok, reason = ns.CanDeposit()
				if not ok then
					UIErrorsFrame:AddMessage(reason, 1, 0.3, 0.3)
					return
				end
			end
			DEPOSIT_ACTION.onClick()
			ns.UpdateDepositControls()
		end,
		tooltip = {
			"Données des personnages",
			"Niveau, or, métiers, équipement, sacs et banques de tous vos personnages, avec recherche "
				.. "d'objet (détail au survol d'un personnage).",
			"Clic droit : ranger (comme le bouton « Ranger » : objets des sacs déjà présents dans la banque "
				.. "ouverte) ; pendant le rangement, clic droit pour l'arrêter.",
		},
		onCreate = function(button)
			P.ui.dataButton = button
		end,
	})
end

if P.RegisterSlashCommand then
	P.RegisterSlashCommand("data", P.ToggleData, "données des personnages (or, métiers, équipement, sacs, banques)")
end
