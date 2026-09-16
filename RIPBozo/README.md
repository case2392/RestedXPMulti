# RIP Bozo

Hardcore death roasts for WoW Classic Hardcore. When someone dies, RIP Bozo
whispers them a random line ("RIPBOZO", "Bro, you shouldn't have done that.",
"See you in Forever."...) and roasts every death in your own chat. It reads
the death announcement, so it knows *what* killed them, *where*, and at what
level, and it uses that:

> Bro, 31 in The Stockade and you died? That dungeon is 22-30. LOL. Come on.

> Level 20 in Eastern Plaguelands? That's a 53-60 zone. What did you think was
> gonna happen, bro.

> You died in Stormwind City. A city. With guards. Bro.

> Mrglglgl. Rest in peace.

Every zone and dungeon in Classic has its level range built in, so anyone
who dies too high or too low for where they were gets called out for it.
Deaths in cities, deaths to murlocs, kobolds, critters, fatigue, drowning,
falling, lava, Stitches, Son of Arugal and devilsaurs get their own lines.
Everything else cycles through 30 generic roasts (no repeats until the whole
list has been used) plus any lines you add yourself.

## How it decides who to whisper

| Setting | Default | Who gets the whisper |
|---|---|---|
| `guild` | on | guildmates |
| `friends` | on | friends list and Battle.net friends |
| `party` | on | party / raid members |
| `everyone` | **off** | anyone who dies on the realm |

Everyone mode is off by default because unsolicited whispers to strangers get
reported. When you turn it on it is capped at 20 whispers an hour, one per
death, and it skips deaths below level 10 (`/ripbozo minlevel` changes that).
Every death still shows in your own chat with a roast regardless of the
setting, and `/rip` roasts anyone on demand.

## Commands

| Command | What it does |
|---|---|
| `/rip` | Whisper a roast to your target (or the last death you saw) |
| `/rip <name>` | Whisper a roast to that player |
| `/ripbozo` | Show settings |
| `/ripbozo guild\|friends\|party\|everyone on\|off` | Who gets auto-whispered when they die |
| `/ripbozo minlevel <n>` | Everyone mode ignores deaths below this level (default 10) |
| `/ripbozo self on\|off` | Roast yourself in chat when you die |
| `/ripbozo feed on\|off` | Roast every death you see, in your chat only |
| `/ripbozo test` | Print a random line |
| `/ripbozo list` | Print every line |
| `/ripbozo add <text>` | Add your own line |
| `/ripbozo clear` | Remove your custom lines |

## Setup

Install it like any addon (`RIPBozo/RIPBozo.toc` in your AddOns folder). It
listens to Blizzard's hardcore death alert and the **HardcoreDeaths** channel,
so make sure you have not left that channel. No configuration needed.

## Offline tests

```
lua5.1 tests/harness_ripbozo.lua .
```
