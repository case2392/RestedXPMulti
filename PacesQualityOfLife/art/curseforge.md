# Pace's Quality of Life - CurseForge upload kit

Everything to fill in on CurseForge for the first upload. Not shipped in
the addon zip (`scripts/package.sh` only takes the folder's top level).

## Project settings (General page)

| Field | Value |
|---|---|
| Project name | Pace's Quality of Life |
| Logo | `paces-qol-logo-1024.png` (square; CurseForge scales it) |
| Summary | see below |
| Class | Addons (already set) |
| Main category | Quests & Leveling |
| Additional categories | Chat & Communication, Map & Minimap |
| Allow Comments | on (bug reports come in as comments) |
| Unlisted project | off |
| Social Links | none needed |
| Slug (URL), if asked | paces-quality-of-life |
| License | MIT License (as the repository's LICENSE) |
| Game version | WoW Forever, the same version you pick for Classic UI (Forever) and CrossTalk (Forever) (toc 16001) |

The name leaves out "(Forever)" because the form asks for no game name in
the title; the Forever game version and the logo's ribbon say it. If you'd
rather match "Classic UI (Forever)" and "CrossTalk (Forever)", use
"Pace's Quality of Life (Forever)".

## Summary

> Track or untrack a whole zone's quests in one click, filter Looking For Group players by role, keep the quest tracker on your zone, and see who's in voice.

## Description

`curseforge-description.html` in this folder, paste-ready. Open it in a
browser, select all, copy, and paste into CurseForge's description editor
(the formatting comes along). If the editor has an HTML/source view, the
file's text can go there directly.

## File upload

| Field | Value |
|---|---|
| File | `dist/PacesQualityOfLife-1.1.0.zip` (contains the `PacesQualityOfLife` folder) |
| Display name | Pace's Quality of Life 1.1.0 |
| Release type | Beta (1.1.0's voice changes not tried in game yet; switch to Release once they have been) |
| Game version | WoW Forever |
| Changelog | below: 1.1.0's, and 1.0.0's under it if 1.0.0 was never uploaded |

## Changelog (1.1.0)

```
1.1.0
- Chat Channels voice: microphones now show in Battle.net communities. Answers name you the way the community lists you (your Battle.net account), which 1.0.0 didn't, so nothing matched there.
- Voice: friends are found on their WoW Forever client even when their Battle.net app has the focus; guildmates and group members are found in any community; a friend still on 1.0.0 shows too, and sees you.
- Voice: no more waiting for ever on the game's "can whisper" check; your own voice is read from the game (after a /reload, a stream switch); failed sends are retried.
- Voice: a /reload in voice no longer hides you from the people looking; logging out tells them at once; a join or leave in a dungeon goes out once you're out; someone who goes offline loses the microphone with their grey row.
- New: /pqol voice (and /pqol voice log) says what voice sharing sent, heard and was refused, without names.
- A bare /pqol <feature> now shows its state instead of switching it (/pqol <feature> on|off switches).
```

## Changelog (1.0.0)

```
1.0.0
- First release.
- Quest log: a tracking checkbox on every zone header to track or untrack the whole zone, one for all quests, and Track all / Untrack all in the list's gear menu (up to the game's 25 tracked quests, the zone on the open map first).
- Looking For Group: tank / healer / damage buttons to show only the players listing the roles you need.
- Objective tracker follows your zone: entering a zone tracks that zone's quests and untracks the rest.
- Chat Channels: a microphone on community members in voice before you join (between Pace's QoL users).
- Every feature can be switched off: Options > AddOns > Pace's Quality of Life, or /pqol.
```

## Screenshots to add

None can be made outside the game. Worth adding after the first in-game
test:

1. The Map & Quest Log with the zone header checkboxes (one full, one faint).
2. The Looking For Group window with only healers shown and the role buttons.
3. The tracker in Duskwood showing only Duskwood's quests.
4. Chat Channels with microphones on members in voice, before joining.
5. The options page.
