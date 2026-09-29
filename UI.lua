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

local MIN_WIDTH, MIN_HEIGHT = 620, 220
local DEFAULT_WIDTH, DEFAULT_HEIGHT = 700, 360
local COLUMN_GAP = 14
local MIN_SEARCH = 2 -- lettres avant de lancer la recherche

local frame, listPanel, searchBox
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
				list[#list + 1] = { slot = slot, level = tonumber(level), max = tonumber(maxLevel),
					icon = tonumber(icon) or icon, name = name }
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

-- Compte Battle.net d'un personnage (token), pour la banque de bataillon commune.
local function AccountOf(key)
	if IsOwn(key) then
		return P.GetTeamToken and P.GetTeamToken() or key
	end
	local roster = P.db.roster[key]
	return roster and roster.token or key
end

-- Banque de bataillon la plus récente par compte : { [compte] = { key, data, version } }.
local function WarbandBanks()
	local banks = {}
	for key in pairs(ns.GetKeys()) do
		local sections, entry = Sections(key)
		local version = entry and tonumber(entry.t.A)
		if sections.A and version then
			local account = AccountOf(key)
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
local COLUMNS = {
	{ "Niveau", function(key)
		local identity = Sections(key).I
		return identity and identity.l and tostring(identity.l) or ""
	end, tip = { "Niveau", "Niveau du personnage." } },
	{ "iLvl", function(key)
		local identity = Sections(key).I
		return identity and identity.i and tostring(identity.i) or ""
	end, tip = { "Niveau d'objet", "Niveau d'objet moyen équipé." } },
	{ "Métiers", function(key)
		local parts = {}
		for _, profession in ipairs(Professions(key)) do
			if profession.slot == "p1" or profession.slot == "p2" then
				parts[#parts + 1] = Icon(profession.icon) .. " " .. profession.level
			end
		end
		return table.concat(parts, "  ")
	end, tip = { "Métiers", "Métiers principaux et leur niveau (tous les métiers au survol d'un personnage)." } },
	{ "Or", function(key)
		local identity = Sections(key).I
		return identity and FormatGold(identity.g) or ""
	end, tip = { "Or", "Or sur le personnage." } },
	{ "Temps de jeu", function(key)
		local seconds = PlayedSeconds(key)
		return seconds and FormatDuration(seconds) or ""
	end, tip = { "Temps de jeu", "Temps de jeu total (relevé à la connexion, puis compté)." } },
	{ "Vu", SeenText, tip = { "Dernière connexion", "« en ligne », ou quand le personnage a été vu connecté." } },
}

local function BuildCharacterItems()
	local keys = ns.GetKeys()
	keys[P.GetCharKey()] = true
	local items = P.SortedKeyItems(keys, IsOwn)
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
		header.cells[i] = "|cffffd200" .. column[1] .. "|r"
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
-- Entrée d'une fiche : { text, detail = fonction appelée au clic, hint = texte d'aide }.

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

-- Contenu d'un sac ou d'une banque : une ligne par objet (nom, nombre), triées par nom.
local function ContainerEntries(data)
	local entries = {}
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
			}
		end
	end
	table.sort(entries, function(a, b)
		return a.sort < b.sort
	end)
	return entries
end

-- Lignes du détail d'un personnage (infobulle au survol et fiche épinglée).
local function CharacterEntries(key)
	local sections, entry = Sections(key)
	local identity = sections.I or {}
	local entries = {}
	local function Add(text, detail, hint)
		entries[#entries + 1] = { text = detail and (text .. DETAIL_MARK) or text, detail = detail, hint = hint }
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
		for _, profession in ipairs(professions) do
			Add("  " .. Icon(profession.icon) .. " " .. profession.name .. " : " .. profession.level .. "/" .. profession.max)
		end
	end

	if sections.E then
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
	local containers = {}
	for _, part in ipairs({ { "B", "Sacs" }, { "K", "Banque" } }) do
		local data = sections[part[1]]
		if data then
			local total, distinct = ContainerCount(data)
			local when = part[1] == "K" and entry and entry.t.K and Gray(" (relevée " .. FormatWhen(entry.t.K) .. ")") or ""
			containers[#containers + 1] = { "  " .. part[2] .. " : " .. total .. " objets (" .. distinct .. " différents)" .. when,
				function()
					OpenCard(part[2] .. " de " .. name, function()
						return ContainerEntries((Sections(key))[part[1]])
					end)
				end }
		end
	end
	local bank = WarbandBanks()[AccountOf(key)]
	if bank then
		local total, distinct = ContainerCount(bank.data)
		local account = AccountOf(key)
		containers[#containers + 1] = { "  Banque de bataillon : " .. total .. " objets (" .. distinct .. " différents)"
			.. Gray(" (relevée " .. FormatWhen(bank.version) .. ")"),
			function()
				OpenCard("Banque de bataillon", function()
					local current = WarbandBanks()[account]
					return ContainerEntries(current and current.data)
				end)
			end }
	end
	local guild = identity.gu
	local guildBank = guild and GuildBanks()[guild]
	if guildBank then
		local total, distinct = ContainerCount(guildBank.data)
		local money = tonumber(guildBank.data.m)
		containers[#containers + 1] = { "  Banque de guilde (" .. guild .. ") : " .. total .. " objets (" .. distinct
			.. " différents)" .. (money and (" · " .. FormatGold(money)) or "")
			.. Gray(" (relevée " .. FormatWhen(guildBank.version) .. ")"),
			function()
				OpenCard("Banque de guilde " .. guild, function()
					local current = GuildBanks()[guild]
					return ContainerEntries(current and current.data)
				end)
			end }
	end
	if #containers > 0 then
		Add(" ")
		Add("|cffffd200Sacs et banques|r")
		for _, line in ipairs(containers) do
			Add(line[1], line[2], "Clic : contenu détaillé")
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

-- Infobulle au survol d'un personnage : ses lignes de détail, et les actions.
local function CharacterTooltip(key)
	local lines = { CharacterName(key) .. Gray("  " .. key) }
	for _, entry in ipairs(CharacterEntries(key)) do
		lines[#lines + 1] = entry.text
	end
	lines[#lines + 1] = " "
	lines[#lines + 1] = Gray("Clic gauche : épingler cette fiche (déplaçable, plusieurs possibles)")
	if not IsOwn(key) then
		lines[#lines + 1] = Gray("Clic droit : oublier ce personnage")
	end
	return lines
end

-- Bouton d'action et ligne d'état d'une fiche (card.action = { update(bouton, état), onClick,
-- tooltip() → { titre, texte } }), ou masqués si elle n'en a pas.
local function UpdateCardAction(card)
	local action = card.action
	card.actionButton:SetShown(action ~= nil)
	card.statusText:SetShown(action ~= nil)
	if action then
		action.update(card.actionButton, card.statusText)
	end
end

-- Remplit une fiche (titre et lignes) et ajuste sa hauteur à son contenu.
local function FillCard(card)
	local entries = card.build() or {}
	local extra = card.action and CARD_STATUS_HEIGHT or 0
	card.TitleText:SetText(card.title)
	card.TitleText:SetPoint("RIGHT", card.action and card.actionButton or card.CloseButton, "LEFT", -4, 0)
	card.panel:SetPoint("TOPLEFT", 8, -32 - extra)
	UpdateCardAction(card)
	P.SetListData(card.panel, entries)
	card.panel.emptyText:SetText(card.empty or "Vide.")
	card:SetHeight(math.min(CARD_MAX_HEIGHT, 40 + extra + math.max(#entries, 1) * CARD_ROW_HEIGHT + 16))
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
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:AddLine(tip[1])
			if tip.error then
				GameTooltip:AddLine(tip[2], 1, 0.3, 0.3, true)
			else
				GameTooltip:AddLine(tip[2], 1, 1, 1, true)
			end
			GameTooltip:Show()
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
			return data.hint and { data.hint } or nil
		end,
	})
	card.panel = panel
	P.SkinFrame(card)
	cards[#cards + 1] = card
	return card
end

-- Ouvre une fiche épinglée titrée title, dont build() renvoie les lignes (relu à chaque
-- rafraîchissement de la fenêtre), près du curseur, décalée des fiches déjà ouvertes ; empty :
-- texte si vide ; action : bouton et ligne d'état (voir UpdateCardAction), nil = aucun.
OpenCard = function(title, build, empty, action)
	local card
	for _, existing in ipairs(cards) do
		if not existing:IsShown() then
			card = existing
			break
		end
	end
	card = card or CreateCard()
	card.title, card.build, card.empty, card.action = title, build, empty, action
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

-- Bouton « Ranger » de la fiche des dépôts (Deposit.lua) : banque du personnage et banque de
-- bataillon ; grisé si aucune n'est ouverte ou si la banque de guilde l'est aussi (l'infobulle
-- dit pourquoi).
local DEPOSIT_ACTION = {
	update = function(button, status)
		local running = ns.IsDepositRunning()
		button:SetText(running and "Arrêter" or "Ranger")
		button:SetEnabled(running or (ns.CanDeposit()) or false)
		status:SetText(ns.GetDepositStatus() or Gray("Ranger : banque du personnage ou de bataillon ouverte."))
	end,
	onClick = function()
		if ns.IsDepositRunning() then
			ns.StopDeposit()
		else
			ns.StartDeposit()
		end
	end,
	tooltip = function()
		if ns.IsDepositRunning() then
			return { "Rangement en cours", "Clic : arrêter." }
		end
		local ok, reason = ns.CanDeposit()
		if not ok then
			return { "Ranger dans la banque", reason, error = true }
		end
		return { "Ranger dans la banque", "Dépose les objets des sacs qui se trouvent déjà dans une banque "
			.. "ouverte, et seulement eux : dans la banque du personnage s'ils y sont, sinon dans la banque de "
			.. "bataillon ; sur la pile existante, sinon dans le même onglet, sinon ailleurs dans cette banque." }
	end,
}

-- Rangement en cours : bouton et ligne d'état de la fiche des dépôts.
function ns.UpdateDepositControls()
	if depositCard and depositCard:IsShown() and depositCard.action == DEPOSIT_ACTION then
		UpdateCardAction(depositCard)
	end
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
		hover = CreateFrame("Frame", nil, row)
		hover:SetFrameLevel(row:GetFrameLevel() + 2)
		hover:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:AddLine(self.tip[1])
			GameTooltip:AddLine(self.tip[2], 1, 1, 1, true)
			GameTooltip:Show()
		end)
		hover:SetScript("OnLeave", GameTooltip_Hide)
		row.cellHovers[i] = hover
	end
	return hover
end

-- Place les cellules d'une ligne (lignes recyclées : tout est recalculé ici) ; renvoie la
-- cellule la plus à gauche, contre laquelle le nom s'arrête.
local function LayoutCells(row, data)
	row.cells = row.cells or {}
	for _, hover in pairs(row.cellHovers or {}) do
		hover:Hide()
	end
	local offset = -4
	local firstCell
	for i = #columnWidths, 1, -1 do
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
			cell:SetPoint("RIGHT", row, "RIGHT", offset, 0)
			cell:SetWidth(width)
			cell:SetText(data.cells[i] or "")
			cell:Show()
			offset = offset - width - COLUMN_GAP
			firstCell = cell
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

	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("LEFT", depositBtn, "RIGHT", 10, 0)
	title:SetText("Données des personnages")
	frame.TitleText = title

	local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	closeBtn:SetPoint("TOPRIGHT", -4, -4)
	frame.CloseButton = closeBtn

	searchBox = CreateFrame("EditBox", nil, frame, "SearchBoxTemplate")
	searchBox:SetSize(200, 20)
	searchBox:SetPoint("RIGHT", closeBtn, "LEFT", -8, 0)
	searchBox:SetAutoFocus(false)
	if searchBox.Instructions then
		searchBox.Instructions:SetText("Rechercher un objet")
	end
	searchBox:HookScript("OnTextChanged", function()
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

	P.CreateScrollList(listPanel, function(data)
		if data.columnHeader then
			return ""
		elseif data.result then
			return Icon(ItemIcon(data.result.itemID)) .. " " .. data.result.colored
				.. Gray("  ×" .. data.result.total)
		end
		return CharacterName(data.key)
	end, nil, {
		onClick = function(data, button)
			if not data.key then
				return
			elseif button == "RightButton" then
				ShowForgetMenu(data.key)
			else
				local key = data.key
				OpenCard(CharacterName(key), function()
					return CharacterEntries(key)
				end)
			end
		end,
		tooltip = function(data)
			if data.columnHeader then
				return nil
			elseif data.result then
				return ResultTooltip(data.result)
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
			if data.result then
				row.rightText:SetText(ResultRightText(data.result))
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

	P.SkinFrame(frame)
	P.SkinPanel(listPanel)
	if P.SkinButton then
		P.SkinButton(depositBtn)
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
	local items, header, emptyText
	if searching then
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
if not (C_EventUtils and C_EventUtils.IsEventValid) or C_EventUtils.IsEventValid("ITEM_DATA_LOAD_RESULT") then
	itemEvents:RegisterEvent("ITEM_DATA_LOAD_RESULT")
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

-- INTÉGRATION À POLYPODE -------------------------------------------------------------------------

if P.AddTitleButton then
	P.AddTitleButton({
		text = "Data",
		width = 50,
		onClick = function()
			P.ToggleData()
		end,
		tooltip = {
			"Données des personnages",
			"Niveau, or, métiers, équipement, sacs et banques de tous vos personnages, avec recherche "
				.. "d'objet (détail au survol d'un personnage).",
		},
		onCreate = function(button)
			P.ui.dataButton = button
		end,
	})
end

if P.RegisterSlashCommand then
	P.RegisterSlashCommand("data", P.ToggleData, "données des personnages (or, métiers, équipement, sacs, banques)")
end
