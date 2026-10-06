# CrossTalk (Forever)

Say short things the other faction can read on **World of Warcraft
Forever**: RIP BOZO, GG, GOOD LUCK, LOSER. A phrase board sits on screen;
left click says a phrase in /say, right click yells it, and the tooltip
shows exactly what the other side will read.

## How it works

The game hides the other faction's speech by swapping every word for a
word of the same length from that language's word list, picked by a hash
of the original word. A one-character word always comes out as a
one-letter word, so the right single characters, sent one per word, spell
out capital letters on the other side:

```
you click:   RIP BOZO
you send:    ‡ 0 ῁ à ῁ 6 Ğ 6        (whatever characters your table says)
they read:   R I B r B O S O
```

A lowercase letter (here `r`) marks the gap between words. Letters the
language cannot make are swapped for the nearest sound: Common had no P or
Z on the clients this was seen on, so RIP BOZO reads RIB BOSO. Digits are
spelled out, punctuation becomes a word gap. The technique is the one the
Hermes addon published for Classic; this is its own code.

Incoming works too: when someone of the other faction spells a message
this way (with CrossTalk, Hermes or PVPTaunt), your chat gets a line
reading it back: `Hordie spelled: THANK YOU`.

## The one-time calibration

Which character turns into which letter changes from patch to patch
(Hermes's Common table changed every letter but one with a single Wrath
Classic patch), and nobody has published the table for Forever. So
CrossTalk finds it, once per patch, with one player of each faction:

1. Both of you install CrossTalk and stand next to each other.
2. The player of the other faction targets you and clicks **Listen** on
   their board (or types `/ct listen YourName`).
3. You open **Calibrate** and click **Send probe** three or four times,
   until their window says all the letters are found.
4. Their window shows a code like `CT1:7:70009:A12,B88,...`. They copy it
   and send it to you: a Battle.net whisper crosses factions.
5. You click **Paste their code**. Done until the next patch.

The table is the same for every player of your faction on the same game
build, so once one person has it, `/ct code` shows it as a code to hand
to friends, and it can ship with the addon.

If a probe loses a character on the way (the server drops some), the
listener sets that probe aside rather than misreading it; and if the same
character ever turns into two different letters, the window says so,
because then no table can hold.

## Commands

| Command | What it does |
|---|---|
| `/ct` | Show or hide the phrase board |
| `/ct <text>` or `/ct say <text>` | Say it so the other faction can read it |
| `/ct yell <text>` | The same, yelled |
| `/ct add <text>`, `/ct remove <text>` | Phrases on the board (Ctrl-click a phrase also removes it) |
| `/ct calibrate` | The calibration window |
| `/ct probe [n]` | Send the next probe (or probe n) |
| `/ct listen [name]` | Read someone's probes (no name: your target); `/ct stop` |
| `/ct import [code]` | Use a code; `/ct code` shows yours to share |
| `/ct decode on\|off` | Read spelled messages from the other faction |
| `/ct status` | Your language, build and table |

## Notes

- Forever only by design (toc 16001). It would work on any client with the
  same chat rules once calibrated there, but that is untested.
- Forever only lets an addon /say from a key press or a click, so every
  message goes out from a button or a typed command, never on a timer.
- Blizzard's terms: an old version of the WoW Terms of Use forbade
  communicating with the opposite faction; Hermes's authors say the clause
  went when the Battle.net and WoW agreements merged in 2018, and Hermes
  and PVPTaunt are both on CurseForge. Blizzard can still change how the
  scrambling works at any patch, which is what calibration is for.

## Offline tests

```
lua5.1 tests/harness_crosstalk.lua .
```

simulates two players on one server with a scrambler that behaves like the
game's (same-length words, hash per build, lowercase stays lowercase, the
first word capitalised, a character swallowed), and runs calibration both
ways, sharing and importing codes, the board, a patch change and hidden
chat text.
