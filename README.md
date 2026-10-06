# RealJustinCase's WoW addons

Six addons, each in its own folder, each shipped on CurseForge as a zip
of that folder alone:

| Folder | Addon | What it does |
|---|---|---|
| [`RestedXPMulti/`](RestedXPMulti/) | **RestedXP Party Sync** | Syncs RestedXP guide progress between party members and holds the group in lockstep |
| [`RXPProfessions/`](RXPProfessions/) | **RestedXP Professions** | Keeps your professions leveled while you follow the guides |
| [`ForeverClassicUI/`](ForeverClassicUI/) | **Classic UI (Forever)** | The Classic Era look on World of Warcraft Forever, part by part |
| [`AdventurePlates/`](AdventurePlates/) | **Adventure Plates** | Final Fantasy XIV-style adventurer plates you can open on any player with the addon |
| [`RIPBozo/`](RIPBozo/) | **RIP Bozo** | Hardcore death roasts |
| [`CrossTalk/`](CrossTalk/) | **CrossTalk (Forever)** | Short phrases the other faction can read on WoW Forever, spelled out in letters the game lets through |

Each folder's README covers that addon. `tests/` holds the offline
harnesses (`lua5.1 tests/harness_<name>.lua .`) and `scripts/package.sh`
builds the CurseForge zips into `dist/`.
