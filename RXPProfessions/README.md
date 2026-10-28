# RestedXP Professions

A companion addon that keeps your professions leveled **while** you follow
RestedXP leveling guides, instead of switching to a separate profession guide.
Sister addon to RestedXP Party Sync (both live in this repository).

On first launch a setup window asks **which professions you're leveling**
(any of Herbalism, Mining, Skinning, Alchemy, Blacksmithing, Enchanting,
Engineering, Leatherworking, Tailoring, Cooking, First Aid and Fishing) and
whether you want to
**use the Auction House for materials**. Then a small window — skinned to
match your RestedXP theme — always shows what to do *right now*:

- **Gathering:** what to gather at your current skill ("Mine: Copper Vein"),
  what unlocks next ("At 65: Tin Vein"), with a chat ping when a new tier
  unlocks.
- **Trainer reminders:** "Can train Journeyman now (50 needed)" once you can
  rank up, and "Capped! Train Journeyman at a Tailoring trainer" when you're
  capped and wasting skill-ups - with the character level a trainer asks
  for, and, for First Aid, Cooking and Fishing, the book or quest instead
  where that is how the game gives the rank.
- **Pace check:** if your skill falls well behind your character level, it
  tells you to catch up before leaving the zone (roughly 5 skill per level).
- **Crafting (Alchemy, Blacksmithing, Enchanting, Engineering,
  Leatherworking, Tailoring, First Aid, Cooking):** what to craft in your
  bracket with the materials needed, where to get a recipe a trainer does
  not teach, the trainers for the higher ranks, and an AH tip if you opted
  in. Cooking and Fishing together level off your own catches.
- Professions you picked but haven't learned yet show a "visit a trainer"
  reminder.

## Languages

RXPP works on every client language (1.1.0). A French player reported
"my professions are not detected because I play in French": until then it
looked professions up by their English names only. Now:

- **Professions are found in any language** - by the skill line's ID
  where the game gives one, else by the name the game uses (French,
  German, Spanish, Portuguese, Italian, Russian, Korean and Chinese, with
  the spellings that differ between Classic Era, TBC, Mists and Forever).
- **Recipes, materials, herbs and zones are named by the game itself**, by
  spell, item and map ID, so they read exactly as your profession window
  and trainer show them. An item your client has not loaded yet shows in
  English for a moment and is filled in when it arrives. (Mists Classic
  numbers its maps differently, so there the fishing hints name zones in
  English and do not know which zone you are in.)
- **The addon's own sentences** ("Craft:", "Can train Journeyman now",
  "Capped!" ...) are translated into French, German, Spanish (Spain and
  Latin America), Brazilian Portuguese, Italian, Russian, Korean and
  Simplified and Traditional Chinese.
- Still in English: the trainer and vendor names in the "Get it" and
  trainer notes, the longer notes under a route, and `/rxpp status`.
  Corrections to any translation are welcome.

## Install

Copy the `RXPProfessions` folder into `Interface/AddOns/` so you have
`Interface/AddOns/RXPProfessions/RXPProfessions.toc`, then restart the game.
Works with or without RestedXP installed (it borrows RestedXP's theme when
present).

## Item tooltips

Hover an item and RXPP says what your profession plan needs of it, span
by span, so you can tell what to keep for now, what to keep for later and
what you can sell. A span is a row of the route for as long as the window
shows that row; the one you are in reads "Now" and counts from your skill.
Each span says how many of what you have go to it, and from where, against
what it needs (Wool Cloth at Tailoring 63 on Forever, 25 in the bags and 15
in the bank):

```
RXP Professions
Tailoring
  Now 63-70 · 21 (bags 21) of ~21 · Bolt of Woolen Cloth
  70-100 · 19 (bags 4 · bank 15) of ~69 · Woolen Cape (via Bolt of Woolen Cloth)
  110-120 · 0 of ~90 · Double-Stitched Woolen Shoulders (via Bolt of Woolen Cloth)
You have 40 (bags 25 · bank 15) · ~140 short
```

- Counts assume one craft per skill point, which orange recipes give,
  hence the "~".
- A reagent the route itself makes (bolts, grinding stones, blasting
  powder, Handful of Copper Bolts) is followed to what it is made of.
  What an earlier span makes, and what you already have of it, is used
  first, so nothing is counted twice. Another profession's product is
  followed only when that profession is one you picked, and what its own
  route makes of it goes first (Forever's Elixir of Defense, which Alchemy
  makes and Leatherworking's ammo pouches use).
- What you have is your bags (with the reagent bag) and your bank. It goes
  to "Now" first, then to the spans after it from the top down, the bags
  before the bank; the last line gives the total and what is short or to
  spare. Away from the bank, a client that does not see it is answered
  from the count taken at your last bank visit, and says so; once a client
  has been seen counting the closed bank, its own count stands.
- A row of alternatives ("Runecloth Shoulders / Runecloth Headband")
  counts the ones you already know, as the window would; all of them when
  you know none.
- Only the professions you picked in `/rxpp setup` count, the ones you
  have not learned yet from skill 1. `/rxpp tooltip others` adds the rest
  under a grey heading of their own, with what they need and nothing of
  yours handed out. With `/rxpp tooltip later` off, only "Now" shows and
  is counted.
- The tooltip reads the route as the window does, at your skill and at
  the skill each span ends at: trainer corrections and "the game outranks
  the route" included, and a row a trainer moved past the rows after it
  skipped, as the window skips it. The two never name different rows.
- The lines go on the game's item tooltip and on chat links only: not on
  the comparison tooltips beside them, nor on the hidden tooltips other
  addons read items with. They are translated like the window.
- The plan is built when a tooltip first needs it and kept until your
  skills, your picks, the recipes and trainer data the window keeps, or
  your count of a reagent the routes make change. A hover costs a few
  reads, not a rebuild.
- Materials no route row makes are followed too, to what you gather:
  ore through the bars it smelts into (when you picked Mining), cloth
  through the bolts Forever's route has no row for, hides through the
  cured hides, stone through grinding stones (Data.lua's `REFINE`).
  Leather is not combined: skinning gives the heavier leather itself.

## Commands

- `/rxpp` — show/hide the window
- `/rxpp setup` — reopen the profession/AH setup
- `/rxpp tooltip` — item tooltips on/off
- `/rxpp tooltip later` — show/hide the spans after the one you are in
- `/rxpp tooltip others` — also show the professions you did not pick
- `/rxpp need <item link or ID>` — what the item tooltip would say, in chat

## Notes & roadmap

- Skill data covers Classic Era / Anniversary, TBC (Outland content not
  yet covered) and World of Warcraft Forever, which has **routes of its
  own** (1.0.0). A report had RXPP recommend recipes that no longer gave
  skill-ups (Linen Bag at 63 Tailoring, an Enchanting bracer at 63, and
  enchant names that no longer matched). That player was on Forever,
  whose skill-up ranges, trainer levels and recipe names differ from
  Classic's: Linen Bag greys at 65 there, not 105, and Classic's Enchant
  Bracer - Minor Health is "Inferior Stamina" (grey at 25). Every route
  row, Forever's and Classic's, is now checked against the game's own
  recipe data: learnable at the row's skill, and still giving skill-ups
  until the next row. That check also fixed rows in the Classic routes
  (Enchanting from 110 up asked for enchants the trainer does not teach
  yet, among others). In game, the colours your profession window shows
  still outrank the route: a recipe gone grey (or green, when you know
  something better) is replaced by the best one you know.
- The craft routes are static tables, so a row can be wrong: a TBC report
  had Leatherworking "a tier ahead at all times" (the gloves the row put at
  30 are trained at 55, the belt at 85). Those rows are fixed (0.6.2), and
  the addon now learns from the game as you play: every trainer window you
  open records what skill each recipe needs, a row the trainer contradicts
  is stepped back to the last recipe you can have, and your profession
  window's skill-up colours are remembered so "Meanwhile: Handstitched
  Leather Boots (orange)" names a recipe you know, with its colour, when the
  route's is out of reach.
- A skill stuck at an old value (a report: Skinning still 61 after
  levelling it to 105, reload or not): 0.6.1 read the profession list
  first and let the first source win, so a source that lagged behind
  held the number down. Since 0.6.3 every source is read and the highest
  number wins (a skill only goes up), a skill-up is looked at again a
  moment after its chat message, and `/rxpp status` shows what each
  source said when they disagree. The scan also ignores the "skills
  changed" events its own header opening causes, which on Forever run on
  the spot and could set off scan after scan.
- A profession under a folded header in the skills tab (a "Professions"
  heading clicked shut) is not in the game's skill list at all, and a
  trained one read as never learned (a report). Since 0.6.1 folded headers
  are opened for the scan and folded back after, and the profession list
  (`GetProfessions`, where the client has it) is read as well.
- Runs on World of Warcraft Forever too (0.6.0). Forever's engine has a
  different skill API (`C_SkillInfo`), keeps recipes behind
  `C_TradeSkillUI`, and lacks the `TRADE_SKILL_UPDATE` / `CRAFT_*` events:
  a report had the addon never start there ("Attempt to register unknown
  event"). Each event is now registered on its own and the missing ones
  skipped; `/rxpp status` says which skill API the client gave us and
  which events it lacks.

## Offline tests

```
lua5.1 tests/harness_rxpprofessions.lua .
```

drives the addon on a Classic Era client, a TBC one, a Forever client
(its API tables, a secret rank, its profession window, its routes) and a
retail-style one.
- English-language clients only for now (professions are matched by name).
- Craft routes are the standard approximate ones; skill-up RNG means brackets
  can shift by a few points.
- Planned next: shopping lists ("gather 15 Silverleaf before hitting town")
  and Outland routes for TBC.
