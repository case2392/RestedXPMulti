# RestedXP Party Sync

**[Download on CurseForge](https://www.curseforge.com/wow/addons/restedxpmulti)**

A small companion addon for [RestedXP / RXPGuides](https://www.restedxp.com/) that
syncs guide progress between party members, so you and a friend can level
together in lockstep:

- **Sync prompt** — when you join a party with another RestedXP Party Sync user, both of
  you get a popup: *"«Name» is also using RestedXP Party Sync. Sync your RestedXP
  guide progress with them?"* Both click **Sync** and you're linked. Your
  choice is remembered, so the same friend never has to be confirmed again.
- **See each other's steps, with live progress** — a window (skinned to match
  your RestedXP theme) shows every synced partner's current guide, step
  number, and the step text exactly as *their* RestedXP renders it, running
  objective counts included: "Webwood Ichor: 4/7", "Webwood Venom Sac: 1/3",
  updating as they kill and loot. This works even when they're on a step your
  own guide doesn't contain (their class quest, for example) — you see what
  they're doing, labeled as their class/race step.
- **Step lock** — the guide will *not* advance to the next step until everyone
  you're synced with has finished the current one. When you finish first you'll
  see "Waiting for: <friend>", and the moment they finish, both guides move on
  automatically.
- **Class quests handled properly** — RestedXP guides contain steps only some
  classes see (class quests, weapon training, etc.), so step *numbers* differ
  between classes. The addon matches steps by their position in the guide
  itself, not by number: when your friend reaches their class quest, you simply
  wait (or go help!), and you both move on together afterwards.

It does **not** modify RestedXP itself — it hooks in from the outside, so you
can keep updating RestedXP normally. The window adopts whatever RestedXP theme
you use (RXP Red, RXP Blue, Gold, custom...) automatically.

## Requirements

- Both players need **RestedXP (RXPGuides)** installed and working.
- Both players need **this addon** installed.
- You must be **in the same party** (addon messages travel over the party
  channel).
- For the step lock to hold you in lockstep, both players should follow the
  **same guide**. Partners on a different guide are still shown in the window
  but never hold you back. Keep your RestedXP versions in step too — if your
  guide versions differ, the addon shows a warning and stops gating rather
  than guessing.

## Installation

Get **RestedXP Party Sync** [on CurseForge](https://www.curseforge.com/wow/addons/restedxpmulti) —
install it with the [CurseForge app](https://www.curseforge.com/download/app)
or download it from the project page. Both players need it installed.

(Installing manually instead? Unzip so your AddOns folder contains
`RestedXPMulti/RestedXPMulti.toc`, then restart the game.)

## Quick start (you + one friend)

1. Both install the addon (see above) and pick the same RestedXP guide.
2. Invite each other to a party.
3. Within a few seconds you'll both get the sync popup — click **Sync** on
   both screens. Done: the Party Sync window shows both of you, and the step
   lock keeps you together from then on.

## Commands

| Command | What it does |
|---|---|
| `/rxpm` | Show/hide the partner window |
| `/rxpm sync` | Offer to sync with everyone detected (the popup does this for you normally) |
| `/rxpm sync <name>` | Offer/accept sync with a specific player |
| `/rxpm unsync <name>` | Stop syncing with a player (no name = everyone) |
| `/rxpm lock` | Toggle the step lock on/off (`/rxpm lock on`, `/rxpm lock off` also work) |
|  `/rxpm skip` (or the window's **Skip wait** button) | Stop waiting and advance to the next step right now |
| `/rxpm status` | Print your partners' progress to chat |
| `/rxpm help` | List the commands |

## How the step lock decides you're "ready"

Steps are compared by their position in the guide source (RestedXP's internal
`stepId`), which is identical for every class even when step numbering isn't.
When RestedXP tries to advance you to a step, the addon checks every synced
partner (same guide, same guide version, seen in the last 90 seconds). You
advance when each of them either:

- is already **at or past** that position in the guide, **or**
- has **finished their current step** and their next step is at or past that
  position (this is what lets someone sit through your class quest without
  either of you getting stuck).

If a partner logs off or leaves the party, they stop holding you back
automatically. You can always force your way forward with `/rxpm skip`, by
turning the lock off, or by jumping to a step from RestedXP's own step menu.

## Notes & limitations

- Addon messages require being in the same party/raid; you can't sync while
  ungrouped.
- Declining the popup lasts for the current session; the popup returns next
  session (or use `/rxpm sync <name>` any time). Accepting is remembered
  permanently until you `/rxpm unsync` them.
- Sticky steps (RestedXP's "do this later" steps) are never gated, since
  RestedXP skips through them as part of its own bookkeeping.
- Works with any number of partners, not just two — everyone who accepts the
  sync and follows the same guide stays in lockstep.
