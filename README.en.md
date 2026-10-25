# Polypode Data

*Version française : [README.md](README.md)*

**"Character data"** window for [Polypode](https://github.com/Baktov/polypode), as a separate
addon: the **lasting** data of all your characters (level, gold, professions, equipment, bags and
banks), in the spirit of DataStore (Altoholic) or WoWthing, while staying simple.

Requires **Polypode 0.51.1** or later.

> **Languages**: French, English, German, Spanish, Italian and Brazilian Portuguese, following the
> language chosen in Polypode (option "Langue / Language"). The translations were made with the help
> of Claude, Anthropic's AI: feedback from native speakers is very welcome
> ([GitHub issue](https://github.com/Baktov/polypode-data/issues)).

---

## Installation

1. Install **Polypode** first (required dependency; icon display: Polypode 0.56 or later).
2. Put the `Polypode_Data` folder in `World of Warcraft/_retail_/Interface/AddOns/`
   (and, for **WoW Forever**, in `World of Warcraft/_forever_/Interface/AddOns/`).
3. Enable "Polypode Data" in the AddOns list **on each character**: each one records its own data
   and sends it to the others.

---

## Usage

The **Data** button (title bar of the Polypode window) or `/poly data` opens a resizable window
(bottom-right corner grip; Escape closes it):

- the list header gives the **number of characters** and the **total gold**;
- a **borderless table** (aligned columns, headers explained on hover) lists every known
  character, the current character first: **Level**, **iLvl** (equipped item level),
  **Professions** (icon and level of the two main professions), **Gold**, **Time played**,
  **Seen** ("online" in green, or when the character was last seen logged in);
- **when hovering a character**, the details: race, class, specialization, faction, zone, item
  level, gold, time played, **all professions** (level / maximum), **equipment** slot by slot (name
  in quality color, item level, **upgrade level** such as "Champion 4/6", **enchantment** in green
  and **gems** below the piece), and the content of the character's **bags**, **bank**, **warband
  bank** and **guild bank** (number of items, guild gold, date of the record);
- **left-click** on a character: their **sheet** (the same details) stays shown in a **movable**
  frame (drag); you can open several to compare; the **close button** at the top right closes it. A
  **click** (left or right) on a line marked "»" shows its details: content of the **bags**, the
  **bank**, the **warband bank** or the **guild bank** (one more sheet, one item per line with its
  count; in the character's sheet, each bag or bank fits on one line, the guild, gold and date of
  the record are in its tooltip), or the **tooltip of the equipped item** (WoW's, pinned, with its
  exact enchantment, gems and bonuses). In a bag sheet, a click on an item shows its tooltip too;
- **right-click** on a character: "Forget this character" (deleted or renamed character...).

### Bags and banks of the current character

Right of the **Deposits** button, four icons: **bag** (bags), **gold coins** (character bank),
**warband emblem** (account warband bank) and **guild chest** (bank of their guild). On hover: the
number of items, the number of different items (and the guild bank's gold) and the date of the
record; on click: the content sheet, the same as from the character details. A bank never opened
with this character (or a character of the guild) is not recorded yet: the tooltip says so.

**Right-click** on an icon: **Reset** clears this record (on this client). Bags are read again at
once; a bank must be **opened again** to be recorded again (the message reminds you).

The warband bank belongs to a **Battle.net account**, the guild bank to a **guild**: whichever
character opens it, Polypode Data keeps **only one record** of it (the most recent replaces the
others, never added up).

### Time played by class

Left of the **Find an item** field, a small icon (**pocket watch**) opens the **Time played by
class** window, inspired by the AccountPlayed addon: the time played of **all known characters**
(all accounts) added up **by class**, from the most played to the least. Each class has a **bar in
its color** (length relative to the most played), its **share of the total** and its duration; the
**total** is at the bottom. The **Days** box shows durations in days (in years and days for a total
of a year or more), unchecked in hours. On **hover** over a class: its characters and their time
played; **click**: a sheet of these characters (click one of them: their sheet). The window moves
(drag), resizes (bottom-right corner) and closes with Escape; its size, position and box are kept.
Only characters whose time played was recorded (at login) count.

### Finding a recipe

Right of the **Find an item** field (both right of the title), a second field **Find a recipe**:
from 2 letters on, the list becomes the learned recipes (of all characters in memory) whose name
contains the text, ignoring accents and case. Each recipe says how many characters know it and
which ones; on hover, each one with the recipe's expansion; a click opens the recipe tooltip. Only
one search at a time: typing in one field empties the other. Only recipes already recorded are
found (each profession window opened once with each character).

### A character's professions

In a character's pinned sheet, **each profession can be clicked** (including the one of the right
column): it opens a sheet with

1. the equipped **profession items** (tool, accessories), with their tooltip on click;
2. the **learned recipes**, grouped **by expansion** ("Khaz Algar", "Dragon Isles"..., the most
   recent first), each expansion **collapsed / expanded** with a click (collapsed by default); a
   click on a recipe opens its tooltip.

WoW only gives recipes **with the profession window open**: open each profession once with each
character to record them (only your own professions are recorded, not another player's recipe link
or a crafting order). Profession items are recorded with the equipment. Like the rest, this data is
shared with your other logged-in clients.

### Possible deposits

The **Deposits** button (title bar, right of the **Options** button) opens a sheet (movable, close
button to close it) that lists, **for each character**, the items of their **bags** that **already**
exist in one of their three banks, and so could be stored there:

- **Bank** (their own);
- **Warband bank** (that of their Battle.net account);
- **Guild bank** (that of their guild).

Each item gives the count in the bags and, in grey, the count already in the bank; a click shows its
tooltip. The banks must have been recorded (opened once). The sheet updates by itself (loot,
deposit, data received); the button closes it again.

**Deposit** (at the top of the sheet, and also in the window's title bar, between **Deposits** and
the bag icon: same button, same function; or **Shift + right-click** on the **Data** button of the
Polypode window or of the floating bar, whose plain right-click opens a small options window):
deposits the bag items that are **already** in an open bank, and only those:

- destination: the **character bank** if the item is there, otherwise the **warband bank** if it is
  there (and accepts it: no item bound to the character); an item missing from the open banks does
  not move;
- onto the **existing stack** (filled up to the maximum), otherwise into a free slot of the **same
  tab**, otherwise elsewhere in that bank;
- a counter follows the progress ("Depositing: 5 of 30") until "The 30 items were deposited in the
  bank" (a stack in the bags counts as one item);
- a **unique** item ("Unique", "Unique (n)") that the warband or guild bank already holds at the
  maximum allowed stays in the bags, with no deposit attempt (the game would refuse it: these banks
  count separately), and it is reported at the end;
- an item whose deposit the game **refuses** ("You can't carry any more of those items"...) is not
  tried again: it stays in the bags, the deposit goes on with the next ones, and at the end a
  message in **your** chat window (visible to you only) lists the refused items, with their link;
- if there is no more room for an item, it stays in the bags (the next ones can still fill an
  existing stack) and it is reported at the end; the deposit stops if the bank closes; during the
  deposit, the button becomes **Stop**.

**Guild bank**: same behavior, only in the tabs where you have the **right to deposit** (an item
present in a tab without that right goes to another allowed tab). The game only keeps the shown tab
up to date: before depositing into a tab, Polypode Data shows it and waits for the server to send
back its content, then waits for its answer after each deposit. It is slower (about one second per
item), and the shown tab changes during the deposit.

Open banks:

- **at a banker** (Blizzard window or a bag addon such as Baganator): both banks, whatever the tab
  shown (character bank first);
- **warband bank alone** (warband chest, remote access): the warband;
- **guild bank**: the guild.

The button is greyed if none is open, if the guild bank is open at the same time as another one
(one bank open only), or if you have no right to deposit in any tab of the guild bank: the tooltip
explains why.

### Item search

The **Find an item** field (top right): from 2 letters on, the list becomes the items whose name
contains the text (ignoring accents and case), in the bags, banks and equipment of every
character. Each line gives the total and, on the right, who owns them ("Warband" for the warband
bank, "Guild ..." for a guild bank); the tooltip says where (bags, bank, equipped). Item names not
yet known by the game are requested from the server, and the list fills in by itself.

### Options

Options > AddOns > Polypode > **Data**, or the **Options** button (far left of the window's title
bar, which closes to let the panel show), or **right-click** on the **Data** button (Polypode window
or floating bar): small options window next to the button, with an **All options** button (requires
Polypode 0.57; otherwise the options panel):

| Option | Default | Effect |
|---|---|---|
| Bag and bank content | List | Display of the detailed content of a bag or bank (click on its line in a character's sheet, or on an icon of the header): **List** (one line per item, with its name and count) or **Icons** (grid of icons like WoW bags: count on the icon, border in quality color, name and details in the tooltip, click = pinned tooltip) or, if [Baganator](https://www.curseforge.com/wow/addons/baganator) is installed, **Baganator** (the click opens Baganator's window, as when opening your bags, for the characters it knows — those played on this PC, this account's warband bank, their guild banks; the others are shown as icons). Setting shared by all characters |

---

## How it works

- Each character records its data **2 seconds after a change** (gold, bags, equipment, level, zone,
  professions...); the last record is the one saved at logout (the game already empties bags,
  equipment and gold at that moment). The **bank** and the **warband bank** can only be read **with
  the bank open**: they are recorded at each visit, and the last known ones stay otherwise.
- **Time played** is requested from the server at login, without showing it in the chat (a
  `/played` typed by hand shows normally).
- The data is **saved** (account file `PolypodeDataDB`) and **exchanged** between your logged-in
  clients through Polypode: at each encounter, each client announces the version of its data, and
  the other only asks for what changed (`DATAV`, `DATAREQ`, `DATA` messages); a change goes out to
  the logged-in clients 10 seconds later (looting: a single grouped sending).
- The warband bank is shared by the characters of one Battle.net account: the most recent one is
  shown.
- **Guild bank**: recorded when one of your characters opens it (every tab it can see is requested
  from the server on opening); the most recent one of each guild is shown in the sheet of each
  character of that guild, and counted in the search.
- On **WoW Forever**, what does not exist (warband bank, specializations...) stays empty.

---

## Languages

Polypode Data follows the language chosen in Polypode ("Langue / Language" option,
`/poly language`), by default the game's: French, English, German, Spanish, Italian or Brazilian
Portuguese (English for any other language). Choosing the language requires Polypode 2.9; with an
older Polypode, the module stays in French. The `/poly data` command keeps its name.

---

## Versions

The full version history is in the [French README](README.md#version).
