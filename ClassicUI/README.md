# Classic UI

Brings the classic-look **nameplates**, **cast bars** and **combo points** back on
*World of Warcraft Forever* (and runs harmlessly on Classic Era, where it is
also testable today).

## What it does

- **Nameplates** — the old rounded nameplate border with the level in it,
  the name centered above the bar, and the small classic cast bar with its
  spark. Blizzard's nameplate code still contains this whole style (it is what
  Classic Era draws); the addon selects it. On clients that expose it as an
  option (`nameplateStyle` = Classic) that is all it does. On clients that hide
  the option and refuse the value, it hooks Blizzard's nameplate driver and
  forces the classic layout values through the same code path.
- **Cast bars** — the player cast bar and the target's spell bar get the
  classic art back (`UI-CastingBar-Border`, `-Flash`, `-Spark`, the shield for
  uninterruptible casts) and Blizzard's own code is switched to its classic
  behaviour (yellow/green/red fill colours, static spark). Clients that
  already draw the classic bar are left alone.
- **Combo points** — the five red dots arcing down the right side of the
  target frame, with the classic highlight fade and shine (same art, offsets
  and timings as the old ComboFrame). Retail-style clients draw combo points
  as a pip bar under the player frame instead; that bar (rogue and druid)
  is parked on a hidden frame, out of combat, and the dots take over.
  Classic clients that still draw the original are left alone.
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
| `/cui nameplates force` | Force the Lua fallback even if the option exists (testing) |
| `/cui castbar on\|off` | Classic-look cast bars (`/reload` after off) |
| `/cui castbar force` | Re-skin the cast bars right now (testing) |
| `/cui combo on\|off` | Classic combo points on the target frame (`/reload` after off) |
| `/cui combo offset <x> <y>` | Nudge the dots if the target frame art differs (no numbers = reset) |
| `/cui combo force` | Draw the classic combo points right now, replacing Blizzard's (testing) |
| `/cui probe` | Client report to copy and send for support |

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

## When the Forever beta opens

Run `/cui probe` on the beta and send the report (plus a screenshot of
anything that still looks wrong). The report's `toc` number goes on the
`## Interface:` line of `ClassicUI.toc`; until then enable *Load out of date
AddOns* in the AddOns list so the game loads it.

## Offline tests

```
lua5.1 tests/harness_classicui.lua .
```

drives the addon through a Classic-style client (nothing to do), a client
that accepts the style CVar, and a retail-style client (CVar refused → Lua
fallback, cast bars re-skinned, combat deferral, Blizzard re-applying its
layout), plus the slash commands and the probe report.
