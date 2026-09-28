# CLAUDE.md — Polypode Data (Addon WoW)

Addon compagnon de **Polypode** (dossier voisin `../Polypode`, dépôt séparé) : fenêtre « Données
des personnages » (données durables de chaque personnage, façon DataStore / WoWthing). Les
conventions de Polypode s'appliquent (voir `../Polypode/CLAUDE.md`) : commentaires en français,
code en anglais, pas de librairie externe, pas de `print()`, bloc `-- Polypode Data: Fichier —
rôle` en tête de fichier, tout contenu de taille variable défile, Retail (120000) et WoW Forever
(16001) avec tests d'existence des API (lectures sous `pcall`). Rester **simple** : on n'ajoute une
donnée que si elle sert à gérer ses personnages.

## Architecture

| Fichier | Rôle |
|---|---|
| `Polypode_Data.toc` | `## Dependencies: Polypode`, SavedVariables de compte `PolypodeDataDB` (`chars`, `window`) |
| `Data.lua` | Relevé du personnage joué par section (`READERS`) : `I` identité (`c` classe, `r` race, `l` niveau, `i` ilvl équipé, `s` spé, `f` faction, `g` cuivre, `z` zone, `p`/`pa` temps de jeu et date du relevé), `T` métiers (`GetProfessions` → `p1 p2 s1 s2 s3` = « skillLine/niveau/max/icône/nom »), `E` équipement (`<slot>` = « ilvl@chaîne d'objet » du lien — `itemID:enchant:gemmes...:bonus` sans `item:`, les « : » passent dans le dernier champ du message ; ancien format « itemID-ilvl » encore lu par `EquippedItem`), `B` sacs / `K` banque / `A` banque de bataillon (`i<itemID>` = nombre ; sacs classés par nom dans `Enum.BagIndex` via `BagKind` ; `K` et `A` seulement banque ouverte, `BANKFRAME_OPENED`/`CLOSED`). `Update` (2 s après un événement, `ScheduleUpdate`) : section changée (texte comparé à `lastText`) → nouvelle version (`NextVersion`, heure serveur croissante), envoi 10 s après (`Push`). Sauvegarde `PolypodeDataDB.chars[clé] = { s, t, seen }`. Synchro : `DATAV:token:clé:S=version,...` à chaque HELLO/HI (`P.RegisterPeerCallback`), `DATAREQ:token:clé:S,S` pour les sections plus récentes, `DATA:token:clé:section:flag:version:k=v,...` (flag `N`/`+`, fragmenté ; `N` ignoré s'il n'est pas plus récent, `+` seulement pour la version commencée ; expéditeur vérifié par `P.IsSender`, le personnage joué fait foi pour lui-même). Temps de jeu : `RequestTimePlayed` à `PLAYER_LOGIN`, affichage coupé en court-circuitant `ChatFrameUtil.DisplayTimePlayed` le temps de la réponse (comme WoWthing). API interne `ns.GetEntry`, `ns.GetKeys`, `ns.Forget`, `ns.Clean`, `ns.SECTIONS` |
| `UI.lua` | Fenêtre `PolypodeDataFrame` (`P.ToggleData`, `P.RefreshData` = `ns.Refresh`, `P.ui.dataFrame` / `dataPanel` / `dataSearchBox`), redimensionnable (taille dans `PolypodeDataDB.window`), titre à gauche, champ `SearchBoxTemplate` à droite. Tableau sans trait (même mécanique que Polypode Suivi : ligne d'en-tête `{ columnHeader, cells, tips }`, `COLUMNS` { en-tête, cellule(clé), tip }, largeurs mesurées dans `columnWidths`, `LayoutCells` depuis le bord droit, `CellHover` pour l'infobulle des en-têtes) : Niveau, iLvl, Métiers, Or, Temps de jeu (`PlayedSeconds` : relevé + temps connecté jusqu'à `seen`), Vu. Détail `CharacterEntries(clé)` (entrées `{ text, detail, hint }`, marque « » » si `detail`) : infobulle `CharacterTooltip` ; clic gauche → fiche épinglée `OpenCard(titre, build)` (cadres réutilisés `cards`, `CreateCard` : déplaçable par glisser, croix `CloseButton` pour fermer, liste `P.CreateScrollList` ; clic (gauche ou droit) sur une ligne = `detail()` : `ContainerEntries` des sacs / banques dans une autre fiche, ou `ShowItem` → `SetItemRef` du lien complet ; sous chaque pièce, `ItemEnhancements(lien)` : enchantement et niveau d'amélioration lus dans `C_TooltipInfo.GetHyperlink` (motifs `FormatPattern` de `ENCHANTED_TOOLTIP_LINE` / `ITEM_UPGRADE_TOOLTIP_FORMAT_STRING`, textes secrets ignorés), gemmes par `C_Item.GetItemGem` ; `RefreshCards` à chaque `ns.Refresh`, `namesPending` remis à zéro au début) ; clic droit → `MenuUtil.CreateContextMenu` « Oublier ce personnage ». Recherche (`SearchItems`, dès 2 lettres, `Normalize` sans accents) sur B, K, E et la banque de bataillon la plus récente par compte (`WarbandBanks`, compte = `P.db.roster[clé].token`) ; noms inconnus demandés (`C_Item.RequestLoadItemDataByID`), `ITEM_DATA_LOAD_RESULT` relance la recherche. Bouton `P.AddTitleButton` « Data » (`P.ui.dataButton`), commande `/poly data` |

## Dépendances vers Polypode (API publique utilisée)

`P.AddTitleButton`, `P.RegisterSlashCommand`, `P.RegisterMessageHandler`, `P.RegisterPeerCallback`,
`P.WhisperOnline`, `P.IsSender`, `P.MAX_MESSAGE_LENGTH`, `P.GetTeamToken`, `P.GetCharKey`,
`P.GetDisplayName`, `P.IsCharacterOnline`, `P.db.roster`, `P.SortedKeyItems`, `P.CreatePanel`,
`P.CreateScrollList` (`opts.tooltip` renvoyant nil = pas d'infobulle : Polypode 0.51.1),
`P.SetListData`, `P.SkinFrame`, `P.SkinPanel`.

## Pistes

- Monnaies, réputations, courrier, enchères, collections : non relevés (voir DataStore).

## Après chaque modification

Mettre à jour `README.md` (et ce fichier si l'architecture change), commiter puis pousser sur
`origin` (https://github.com/Baktov/polypode-data).
