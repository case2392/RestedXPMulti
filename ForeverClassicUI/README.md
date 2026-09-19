# Classic UI for Forever

Brings the classic look back on *World of Warcraft Forever*: nameplates,
cast bars, combo points, player, target, pet and party frames, the character sheet,
the spellbook, the whole classic bottom bar and the minimap. Every part has its own switch under Options > AddOns >
Classic UI for Forever, with Select all / Deselect all buttons. On Classic Era it recognises the classic look is already
there and does nothing, which makes it safe to test today.

Forever runs the retail UI engine with a "Camelot" flavor on top (that is
what its UI source calls it). This addon reads the same Blizzard frames retail
addons do and moves their art, sizes and anchors to the Classic values taken
from Classic Era's own UI code.

## Reporting a bug

An addon cannot send anything anywhere: the client gives Lua no network of
any kind, and a screenshot it takes is saved into the game's Screenshots
folder and stays there. So the addon does the next best thing and makes
the report one click away:

- a **welcome window** the first time it runs on an account (`/cui welcome`
  brings it back), which explains the two things worth reporting: something
  that looks wrong, and a window that is still the modern one because that
  part is not built yet (the talent tree, anything past level 25). It has
  buttons to open the report and to take a screenshot, and the page to
  paste it on in a box to copy;
- a **minimap button** (left click opens the report, right click the
  settings, drag moves it round the ring). `/cui button off` hides it;
- a **notice the first time something errors** in a session, with the same
  button on it, once per session so it cannot nag;
- the report itself now says on its first two lines what it is and where
  to paste it, so it explains itself wherever it ends up.

The report carries the client build, which parts are on, every error of
the session and the full layout of whatever window is open, which is
usually enough to rebuild that window in the classic style.

## What it does

- **Nameplates** — the old rounded nameplate border with the level in it,
  the name centered above the bar, and the small classic cast bar with its
  spark. Blizzard's nameplate code still contains this whole style (it is what
  Classic Era draws); it is selected by the `nameplateStyle` CVar. On Classic
  Era the addon just sets it. **On Forever you type `/console nameplateStyle 6`
  once** (the addon tells you at login): Forever protects unit health with
  "secret values", and a CVar set by an addon taints Blizzard's nameplate
  code so every plate errors out half-built. The value is saved with your
  character. The addon then hides Forever's extra level badge next to each
  plate with a plain alpha change (the classic border has its own level
  slot) and warns you if Forever's Options > Nameplates page overwrites the
  style.
- **Cast bars** — the player cast bar and the target's spell bar get the
  classic art back (`UI-CastingBar-Border`, `-Flash`, `-Spark`, the shield for
  uninterruptible casts, yellow/green fill). Only widget calls and
  `hooksecurefunc` are used, never writes into the bar's Lua tables, because
  Forever's enemy cast times are secret values. Clients that already draw the
  classic bar are left alone.
- **Combo points** — the five red dots arcing down the right side of the
  target frame, with the classic highlight fade and shine (same art, offsets
  and timings as the old ComboFrame). Retail-style clients draw combo points
  as a pip bar under the player frame instead; that bar (rogue and druid)
  is parked on a hidden frame, out of combat, and the dots take over.
  Classic clients that still draw the original are left alone.
- **Player, target and pet frames** — the classic UI-TargetingFrame art
  (mirrored for the player) drawn *over* 119x12 health and mana bars the
  way Classic does (retail draws the bars over the art, which is why they
  looked flat and stuck out; Forever locks the bar frames to their parent's
  level, so the art sits on a frame of the addon's one level above them,
  with a copy of the level text on it), round portraits filling the art's
  ring, level in the frame corner in the small gold font,
  elite / rare / rare-elite target art, the classic combat flash and rest
  icon, and the small classic pet frame. Focus frame too. Every size and
  anchor comes from a `/cui report all` taken on Classic Era. Blizzard's own
  redraws (vehicle art, power-type changes, target classification, level
  repaints) are re-skinned as they happen.
- **Party frames** — each of the four member frames gets Era's
  `UI-PartyFrame` art (128x64 over a 128x53 frame, drawn on Blizzard's
  overlay so it sits above the bars and under the leader crown and pvp
  icon), the 37x37 round portrait, the name in the small gold font over
  a green 70x8 health bar and a 70x8 mana bar with the classic fill, the
  black box behind them, and the small pet frame under each member (64x26,
  its own 18px portrait and 35x4 health bar). Forever's atlas art, bar
  masks and role icon are faded out. Blizzard's roster refresh puts the
  retail art back on every update; it is re-skinned each time, with
  anchors waiting for combat to end.
- **Character sheet** — on the Character tab the window becomes Era's
  384x512 sheet: the four-piece `UI-Character-CharacterTab` art, portrait
  and name in the top corners, "Level 39 Human Priest" and guild lines
  under the name, Blizzard's equipment slots moved into the two Era columns
  with the weapon row along the bottom (and the classic ammo plate), the
  model in the 233x224 window between them, the small attribute box
  (Strength… Spirit, Armor, Melee Attack, Attack Power, Damage, Ranged
  Attack…) filled from the unit stat API the way Era's PaperDollFrame.lua
  did, with the same green/red buff colouring and tooltips, the resistance
  column, and text tabs along the bottom edge (Character, Reputation,
  Skills, Honor, plus Forever's Currency and Statistics, tightened to fit)
  instead of the picture tabs down the side. Forever's shell (metal frame,
  stats list, sidebar tabs, level banner, collapse button) is faded out
  and unclickable, never destroyed: Blizzard keeps driving the slots and
  model. The Reputation and Skills tabs are Era's too: the "General" art,
  the column of 137px reputation bars with their bevel art, +/- headers,
  the at-war swords and the watched-faction check mark, the 212x203
  detail popup off the right edge with the At War / Inactive / Show as
  Experience Bar boxes; twelve 271px skill bars with the bevel border,
  the "All" expand tab, the detail bar with the unlearn button and the
  description under the list. Both are Era's FauxScrollFrame lists
  (Forever still ships the template) fed from `C_Reputation` and
  `C_SkillInfo`; Blizzard's scroll boxes and side panes are hidden while
  they are up. (Forever's copy of `UI-Character-ReputationBar` is retail's,
  with a smaller box drawn elsewhere, so the reputation bars are boxed by
  the two ends of the skills bevel instead and the at-war swords come from
  the sword check mark.) The Honor tab keeps Era's layout (Honor art
  panel, rank badge and title, the 315x29 rank bar) and fills Era's five
  boxes (HonorFrame.xml's grid: titles at -112/-165/-220/-274/-350 with
  278x12 label/value rows) with what Forever tracks: rank points and
  season total, this week's cap and its rise, the next reward with its
  icon and vendor, the season's end and maximum, and the cap paragraph in
  the three-row box. Currency and
  Statistics are Forever's own tabs (Era had neither); they get the same
  Era list inside the General sheet: header rows with the +/- buttons,
  entries in the small font with the amount and icon at the right (click
  a currency to show it on the backpack, the check mark says it is), the
  statistics as a tree of categories that expand in place with each
  statistic's value at the right, the classic scroll bar beside the list.
  Blizzard's scroll boxes and detail panes on those frames are hidden
  while the list is up. The selected bottom tab is told apart by white
  text with the button disabled, the way Era's PanelTemplates did; Era's
  raised "active tab" art is not used because Forever's copy of that file
  draws as a glow with no tab body.
  Forever can hand a unit number back as a "secret value" when the call
  comes from addon code; arithmetic on one is a hard error the client
  throws past `pcall`, so every number the attribute box reads is checked
  with `issecretvalue` first and a refused row keeps what it last showed.
- **Spellbook** — Forever's spell window (`PlayerSpellsFrame`) becomes Era's
  384x512 book while its spellbook page is up: the four-piece
  `UI-SpellbookPanel` art, the book icon in the corner, "Spellbook" over
  the top edge, twelve spell buttons in Era's two columns (icon in the
  quickslot ring, gold name, brown rank line, black ring and dim name for
  passives), the skill line tabs down the right edge, "Page N" and the
  two page arrows along the bottom, the Spellbook / Pet tabs. Those
  bottom tabs are built from the character sheet's tab art, three-sliced
  so each one fits its label: Forever's copy of the Era spellbook tab
  file draws as a retail metal box with the label low and left in it.
  The selected skill line tab gets Era's additive glow; drawn the normal
  way that file is a glow on black and paints the icon out. Spells come
  from `C_SpellBook`; each button is a secure action button, so left
  click casts and dragging puts the spell on a bar (cast attributes are
  only written out of combat and caught up afterwards). Blizzard's window
  is resized and its shell faded, its page moved out of reach; on the
  talents page the retail size comes back until talents get their classic
  version.
- **Professions window** — Forever's professions window
  (`ProfessionsFrame`, the professions micro button) becomes the same Era
  384x512 book as the spellbook while its overview page is up, the way
  the pre-retail spellbook's Professions page did it: Blizzard's five
  cards (two primary, three secondary) stay live and become 316x68 rows
  down the page in the same band the spellbook's columns use, so the
  page keeps an even margin either side, the profession name top left, the two profession spell
  buttons under it with the classic quickslot ring round each icon and a
  brown rank line, and in place of Blizzard's animated rank bar a
  classic skill bar of the addon's (Era's blue skill-bar fill in the
  skills bevel, "rank/max" with any modifier) filled from
  `GetProfessionInfo`, the unlearn button past its end; an empty card's
  "learn a profession" text wraps in the row in the book's small font.
  Everything stays clear of the right edge, where the tabs sit. The side tabs become Era's
  32px skill line tabs down the right edge of the book. The retail shell
  and card art are faded and restored, along with every anchor and
  colour, when the part is turned off. On the crafting page (a
  profession's recipe list) the retail size and look come back until
  that page gets its classic version. Era had no such window
  (professions were the Skills tab), so this is the closest classic
  layout.
- **Quest log** — Era kept the quest log and the map apart: the quest log
  was its own 384x512 parchment book, the map was the map. Forever ships
  retail's merged window instead (`WorldMapFrame` with `QuestMapFrame`
  docked down its left side), and no addon can pull the two apart without
  taking the map's own panel handling with it, so the quest log side is
  reskinned in place: retail's dark sidebar background and border are
  faded and Era's quest log parchment (`UI-QuestLog-TopLeft` and the
  three pieces that go with it, stretched to whatever height Forever's
  window is) is drawn behind it, with Era's book icon in the corner and
  "Quest Log" over the top in Era's font, and every quest title gets
  Era's font and `UI-QuestLogTitleHighlight` under the mouse in place of
  retail's flat bar. The map itself is left alone — it is the same map
  either way.
- **Appearances** — there is no Era original here: transmog did not exist
  in 1.15, so Forever's Appearances window (`CollectionsJournal`) is
  treated the way the Currency and Statistics tabs were, dressed in Era's
  furniture rather than rebuilt. Retail's nine-slice shell, portrait and
  flat backdrop are faded and the spellbook's parchment drawn behind it,
  the title goes over the top edge in Era's font with Era's round close
  button, and the bottom tabs are redrawn from the character sheet's tab
  art cut into three, the open one brightened. The lists, the model and
  the filters inside are Blizzard's and are left alone.
- **Action bars** — Era's whole bottom bar. The addon draws the 1024x53
  `UI-MainMenuBar-Dwarf` stone bar with the gryphon end caps along the
  bottom of the screen and moves Blizzard's pieces onto it: the twelve
  main buttons as 36px buttons 42px apart in the stone slots (the button
  containers are scaled, so every piece of button art shrinks with them),
  the page number and the classic arrows right of them, the micro
  buttons (29x37 classic art, character portrait included) from x=552,
  the bag slots (37px, quickslot ring) ending at the right edge with
  Era's 18x39 keyring and Forever's reagent bag (30px) left of them, and
  the experience bar in the top 13px of the bar with the 10px stone ledge
  over it, purple/blue fill, the classic rest tick and none of Forever's
  segment dividers. Forever has more micro buttons than Era's nine
  (professions, legacy, group finder, collections): they are laid out at
  Era's 26px stride and the row is scaled down just enough to end before
  the keyring; the disabled Store button is hidden so it takes no slot
  (it comes back if the client ever enables it). Every action
  button on every bar gets the classic look: square icon, the
  `UI-Quickslot2` ring, classic pushed/highlight textures, no retail
  slot art or bag-bar border and dividers. The bottom-left and bottom-right bars sit either side of the
  screen centre above the bar, the right bars are vertical with the same
  spacing. Everything here is an Edit Mode system that Blizzard
  re-anchors on every layout apply, so each of its refreshes is hooked
  and the classic layout put back; bar anchors are protected and wait
  for combat to end.
- **Minimap** — the 140px round map with the classic ring border and the
  zone-name strip; the day/night dial is hidden.
- **Quest tracker** — the retail header boxes ("All Objectives", "Quests")
  are faded out so the tracker reads as plain text like the classic quest
  watch. Layout and text stay Blizzard's.
- **Probe** — `/cui probe` opens a copyable report of everything the addon
  depends on: client build and toc number, which Blizzard UI pieces are
  loaded, nameplate style support, cast bar art, whether the classic textures
  still exist, and any error the addon hit. That report is what gets the
  addon adjusted for a new client build.

Everything runs inside error guards, so one part failing on a new build never
takes the other parts down.

## Commands

| Command | What it does |
|---|---|
| `/cui` | Status of each part and how it was applied |
| `/cui nameplates on\|off` | Classic-look nameplates (off restores your previous style) |
| `/cui nameplates size small\|medium\|large\|xl\|huge` | Nameplate size (Blizzard's `nameplateSize`; on Forever it prints the `/console` command for you to type) |
| `/cui nameplates force` | Force the Lua fallback even if the option exists (testing) |
| `/cui castbar on\|off` | Classic-look cast bars (`/reload` after off) |
| `/cui castbar force` | Re-skin the cast bars right now (testing) |
| `/cui combo on\|off` | Classic combo points on the target frame (`/reload` after off) |
| `/cui combo offset <x> <y>` | Nudge the dots if the target frame art differs (no numbers = reset) |
| `/cui combo force` | Draw the classic combo points right now, replacing Blizzard's (testing) |
| `/cui unitframes\|party\|charsheet\|spellbook\|actionbars\|minimap\|tracker on\|off\|force` | The other parts |
| `/cui options` | Open the settings panel (Options > AddOns > Classic UI for Forever) |
| `/cui report` | Everything for support in one copyable window: the probe, a dump of every frame the addon touches (plus your target's nameplate), and the last Lua errors the client raised |
| `/cui report all` | The same including hidden pieces (marked). Run it on Classic Era with a mob targeted to capture the exact classic layout for comparison |
| `/cui probe` | The client report on its own |
| `/cui dump <FrameName>` or `/cui dump target` | Copyable list of a frame's visible textures, text and child frames with size, anchor, art and colour (e.g. `/cui dump TargetFrame` with something targeted) |

## Testing on Classic Era today

1. Options > Nameplates > Nameplate Style: pick **Modern** so the plates look
   like the new ones.
2. `/cui nameplates force` — the plates should snap back to the classic look
   without a reload. That is the exact code path the addon uses on a client
   that hides the option.
3. `/cui castbar force` — the cast bars should look unchanged (they are
   already classic on Era); the point is that the re-skin path runs clean.
4. On a rogue: `/cui combo force`, then build combo points on a target. The
   dots should look identical to Blizzard's (it is the same art and offsets;
   the point is that our copy drives correctly). `/cui combo offset 0 0`
   nudges them if they sit wrong.
5. `/cui probe` — the report should list every classic texture with an id and
   "none" under errors.

## On the Forever beta

Confirmed on 1.60.1 (build 69893, toc 16001). After installing, type
`/console nameplateStyle 6` once for the classic nameplates. Cast bars, unit
frames, character sheet (all six tabs), spellbook, action bars and minimap
are re-skinned, combo points use Blizzard's classic frame. The bottom bar
was tuned from a 0.6.0 report (bag border, keyring and reagent bag, micro
row, XP dividers); the party frames are built from Era's layout files and
Forever's frame dumps and still need a look on Forever: `/cui report all`
while grouped, with a screenshot, is what tunes them.

Settings are kept in the usual SavedVariables file and, because the beta
was seen never writing that file, also in a CVar of the addon's own
(`ForeverClassicUI_settings`), which the client does persist. At login the
CVar copy is used when no saved file comes back; `/cui probe` says which
one the settings came from.

Rule for every part on this client: no Lua field writes into Blizzard's
frames and no calls into Blizzard's nameplate/unit-frame functions from addon
code. Forever wraps unit health, cast times and similar in "secret values"
that only untainted Blizzard code may compare; one tainted field and the
frame errors on its next update. Textures, anchors, sizes and alpha are set
with widget calls, and `hooksecurefunc` re-applies them after Blizzard's own
code runs.

For anything that still looks wrong, target a mob, type `/cui report`, and
send the text with a screenshot.

## Offline tests

```
lua5.1 tests/harness_classicui.lua .
```

drives the addon through a Classic-style client (nothing to do), a client
that accepts the style CVar, and a retail-style client (CVar refused → Lua
fallback, cast bars re-skinned, combat deferral, Blizzard re-applying its
layout), plus the slash commands and the probe report.
