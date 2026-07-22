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
- English-language clients only for now (professions are matched by name).
- Craft routes are the standard approximate ones; skill-up RNG means brackets
  can shift by a few points.
- Planned next: more crafting professions, recipe/vendor locations, and
  shopping lists ("gather 15 Silverleaf before hitting town").
