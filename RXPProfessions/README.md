# RestedXP Professions

A companion addon that keeps your professions leveled **while** you follow
RestedXP leveling guides, instead of switching to a separate profession guide.
Sister addon to RestedXP Party Sync (both live in this repository).

On first launch a setup window asks **which professions you're leveling**
(Herbalism, Mining, Skinning, First Aid, Alchemy) and whether you want to
**use the Auction House for materials**. Then a small window — skinned to
match your RestedXP theme — always shows what to do *right now*:

- **Gathering:** what to gather at your current skill ("Mine: Copper Vein"),
  what unlocks next ("At 65: Tin Vein"), with a chat ping when a new tier
  unlocks.
- **Trainer reminders:** "Cap soon — train Journeyman at 50", and a warning
  when you're capped and wasting skill-ups.
- **Pace check:** if your skill falls well behind your character level, it
  tells you to catch up before leaving the zone (roughly 5 skill per level).
- **First Aid:** which bandage to craft in your bracket, plus early warnings
  for the Expert book and the Triage quest.
- **Alchemy:** what to craft in your bracket with the materials needed, vial
  vendor reminder, and an AH tip if you opted in.
- Professions you picked but haven't learned yet show a "visit a trainer"
  reminder.

## Install

Copy the `RXPProfessions` folder into `Interface/AddOns/` so you have
`Interface/AddOns/RXPProfessions/RXPProfessions.toc`, then restart the game.
Works with or without RestedXP installed (it borrows RestedXP's theme when
present).

## Commands

- `/rxpp` — show/hide the window
- `/rxpp setup` — reopen the profession/AH setup

## Notes & roadmap

- Skill data targets Classic Era / Anniversary (works in TBC; Outland
  content not yet covered).
- The craft routes are static tables, so a row can be wrong: a TBC report
  had Leatherworking "a tier ahead at all times" (the gloves the row put at
  30 are trained at 55, the belt at 85). Those rows are fixed (0.6.2), and
  the addon now learns from the game as you play: every trainer window you
  open records what skill each recipe needs, a row the trainer contradicts
  is stepped back to the last recipe you can have, and your profession
  window's skill-up colours are remembered so "Meanwhile: X (still skills
  up)" names a recipe you know when the route's is out of reach.
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

drives the addon on a Classic Era client, a Forever client (its API
tables, a secret rank, its trade skill window) and a retail-style one.
- English-language clients only for now (professions are matched by name).
- Craft routes are the standard approximate ones; skill-up RNG means brackets
  can shift by a few points.
- Planned next: more crafting professions, recipe/vendor locations, and
  shopping lists ("gather 15 Silverleaf before hitting town").
