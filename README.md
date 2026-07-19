# RestedXP Multi

A small companion addon for [RestedXP / RXPGuides](https://www.restedxp.com/) that
syncs guide progress between party members, so you and a friend can level
together in lockstep:

- **See each other's steps** — a small movable window shows every synced
  partner's current guide, step number, and the text of the step they're on.
- **Step lock** — the guide will *not* advance to the next step until everyone
  in your sync group has finished the current one. When you finish first you'll
  see "Waiting for: <friend>", and the moment they finish, both guides move on
  automatically.
- **Sync codes (optional)** — type in a shared code so you only sync with the
  people you intend to, even in a full party.

It does **not** modify RestedXP itself — it hooks in from the outside, so you
can keep updating RestedXP normally.

## Requirements

- Both players need **RestedXP (RXPGuides)** installed and working.
- Both players need **this addon** installed.
- You must be **in the same party** (addon messages travel over the party
  channel).
- For the step lock to hold you in lockstep, both players should be following
  the **same guide**. Partners on a different guide are still shown in the
  window but never hold you back.

## Installation

1. Download this repository (green **Code** button → *Download ZIP*, or
   `git clone`).
2. Copy/rename the folder so it is called exactly `RestedXPMulti`, and place it
   in your AddOns folder, e.g.:
   - Classic Era / Anniversary: `World of Warcraft/_classic_era_/Interface/AddOns/RestedXPMulti`
   - Wrath/Cata/Mists Classic: `World of Warcraft/_classic_/Interface/AddOns/RestedXPMulti`
   - Retail: `World of Warcraft/_retail_/Interface/AddOns/RestedXPMulti`
3. The folder must directly contain `RestedXPMulti.toc` (not a nested folder).
4. Restart the game (or `/reload`). Do this on **both** players' machines.

## Quick start (you + one friend)

1. Both install the addon (see above) and pick the same RestedXP guide.
2. Invite each other to a party.
3. That's it — within a few seconds the **RXP Multi** window shows both of you.
   The step lock is **on by default**: whoever finishes a step first simply
   waits, and both guides advance together.
4. (Optional) agree on a code and both type, e.g.: `/rxpm code bananas`

## Commands

| Command | What it does |
|---|---|
| `/rxpm` | Show/hide the partner window |
| `/rxpm code <word>` | Set a sync code — only players with the same code sync with you |
| `/rxpm code off` | Clear the code (sync with your whole party) |
| `/rxpm lock` | Toggle the step lock on/off (`/rxpm lock on`, `/rxpm lock off` also work) |
| `/rxpm skip` | Stop waiting and advance to the next step right now |
| `/rxpm status` | Print your partners' progress to chat |
| `/rxpm help` | List the commands |

## How the step lock decides you're "ready"

When RestedXP tries to advance you to step *N*, the addon checks every synced
partner (same code, same guide, seen in the last 90 seconds). You advance when
each of them either:

- is already on step *N* or beyond, **or**
- is on step *N − 1* and has finished it too.

If a partner logs off or leaves the party, they stop holding you back
automatically. You can always force your way forward with `/rxpm skip`, by
turning the lock off, or by jumping to a step from RestedXP's own step menu.

## Notes & limitations

- Addon messages require being in the same party/raid; you can't sync while
  ungrouped.
- The lock also applies to forward jumps made through RestedXP's automatic
  step handling. Backward jumps are never blocked.
- Sticky steps (RestedXP's "do this later" steps) are never gated, since
  RestedXP skips through them as part of its own bookkeeping.
- Works with any number of partners, not just two — everyone with the addon,
  the same code, and the same guide stays in lockstep.
