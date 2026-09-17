# Classic UI for Forever

Brings the classic look back on *World of Warcraft Forever*: nameplates,
cast bars, combo points, player and target frames, the main action bar art
and the minimap. Every part has its own switch under Options > AddOns >
Classic UI for Forever, with Select all / Deselect all buttons. On Classic Era it recognises the classic look is already
there and does nothing, which makes it safe to test today.

Forever runs the retail UI engine with a "Camelot" flavor on top (that is
what its UI source calls it). This addon reads the same Blizzard frames retail
addons do and moves their art, sizes and anchors to the Classic values taken
from Classic Era's own UI code.

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
- **Action bar art** — the classic stone bar under the main action bar
  between the gryphons; the retail frame border and the divider strips
  between buttons are hidden.
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
| `/cui unitframes\|actionbars\|minimap\|tracker on\|off\|force` | The other parts |
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
frames, action bar and minimap are re-skinned, combo points use Blizzard's
classic frame.

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
