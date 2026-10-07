# CrossTalk (Forever) - CurseForge upload kit

Everything to paste into CurseForge for the first upload. Not shipped in
the addon zip (`scripts/package.sh` only takes the folder's top level).

## Project settings

| Field | Value |
|---|---|
| Project name | CrossTalk (Forever) |
| Slug (URL) | crosstalk-forever |
| Avatar | `crosstalk-logo-1024.png` (square; CurseForge scales it) |
| Main category | Chat & Communication |
| Additional categories | PvP, Roleplay |
| License | MIT License |
| Game version | The same WoW Forever version you pick for Classic UI (Forever) (toc 16001) |

## Summary

> Say GG, RIP BOZO and GOOD LUCK to the other faction on WoW Forever, spelled out in letters the game lets through. One-click phrase board.

## Description

Paste below this line into the description editor (Markdown).

---

# CrossTalk (Forever)

**Say short things the other faction can actually read on World of Warcraft Forever.**

The game turns everything you say into gibberish for the other faction. CrossTalk spells your message out in single letters the game lets through, so a Horde player standing next to you reads:

```
R I B r B O S O
```

and their CrossTalk reads it back as **RIB BOSO**. (Your faction's language can't make every letter, so a few get swapped for the nearest sound: P becomes B, Z becomes S.)

## Features

- **Phrase board:** RIP BOZO, GOOD LUCK, LOSER, GG, LOL, NICE TRY, HELLO, BYE, THANKS, WELL PLAYED, SORRY, RUN. **Left click** says it, **right click** yells it.
- **See before you send:** every phrase's tooltip shows exactly what the other side will read.
- **Your own phrases:** type one into the board and click Add. Ctrl-click a phrase to remove it.
- **Free text:** `/ct good game` says anything short.
- **Reads them back:** when someone of the other faction spells a message this way (CrossTalk, Hermes or PVPTaunt), your chat shows `Name spelled: THANK YOU`.
- **Works both ways:** Alliance to Horde and Horde to Alliance.

## One-time setup (important)

Which character turns into which letter **changes from patch to patch**, and nobody has published the letters for Forever yet. CrossTalk finds them once, with one player of each faction:

1. Both of you install CrossTalk and stand next to each other.
2. The player of the other faction **targets you** and clicks **Listen** on their board.
3. You click **Calibrate**, then **Send probe** three or four times, until their window says all letters are found.
4. Their window shows a short code. They send it to you (a **Battle.net whisper** crosses factions).
5. You click **Paste their code**. Done until the next patch.

The letters are the same for everyone of your faction on the same game version, so **share your code** with friends (`/ct code`) and they can skip the setup. Updated codes will ship with the addon as they are found.

## Commands

| Command | What it does |
|---|---|
| `/ct` | Show or hide the phrase board |
| `/ct <text>` | Say it so the other faction can read it |
| `/ct yell <text>` | The same, yelled |
| `/ct add <text>` / `/ct remove <text>` | Edit the board's phrases |
| `/ct calibrate` | The setup window |
| `/ct listen [name]` | Help someone of the other faction set up (no name: your target) |
| `/ct import <code>` / `/ct code` | Use a code / show yours to share |
| `/ct decode on\|off` | Read spelled messages from the other faction |
| `/ct status` | Your language, game version and letters |

## Good to know

- Only short messages fit: each letter is its own word, and a message is capped at 255 bytes.
- The game only lets an addon /say from a click or a typed command, so CrossTalk never sends anything on its own.
- After a game patch, if the other side reads gibberish, run the setup again.
- The spelling trick was first published by the Hermes addon for Classic; CrossTalk is its own code, built for Forever.

## Also by RealJustinCase

- **Classic UI (Forever):** the Classic Era look on WoW Forever
- **RestedXP Party Sync** and **RestedXP Professions**

Found a bug? Leave a comment with what you typed and what the other side saw, and paste the output of `/ct status` from both of you.

---

## File upload

| Field | Value |
|---|---|
| File | `dist/CrossTalk-1.0.0.zip` (contains the `CrossTalk` folder) |
| Display name | CrossTalk (Forever) 1.0.0 |
| Release type | Beta (no Forever letter table ships yet; every user needs the one-time setup) |
| Game version | WoW Forever |

## Changelog (1.0.0)

```
1.0.0
- First release.
- Phrase board: say or yell RIP BOZO, GG, GOOD LUCK and more so the other faction can read them; add your own.
- /ct <text> for anything short; tooltips show what the other side will read.
- Reads spelled messages from the other faction back in your chat.
- One-time setup with a player of the other faction finds the letters for your game version; share the code with friends.
```

## Screenshots to add

None can be made outside the game. Worth adding after the first in-game test:

1. The phrase board on screen, with a phrase's tooltip showing "They see: ...".
2. A Horde player's chat showing the spelled letters and the "spelled:" line.
3. The setup window mid-calibration.
