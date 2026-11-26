# RealJustinCase's WoW addons

Each addon lives in its own folder, each shipped on CurseForge as a zip
of that folder alone:

| Folder | Addon | What it does |
|---|---|---|
| [`RestedXPMulti/`](RestedXPMulti/) | **RestedXP Party Sync** | Syncs RestedXP guide progress between party members and holds the group in lockstep |
| [`RXPProfessions/`](RXPProfessions/) | **RestedXP Professions** | Keeps your professions leveled while you follow the guides (Classic Era, TBC, Mists Classic, WoW Forever and retail Midnight) |
| [`ForeverClassicUI/`](ForeverClassicUI/) | **Classic UI (Forever)** | The Classic Era look on World of Warcraft Forever, part by part |
| [`RIPBozo/`](RIPBozo/) | **RIP Bozo** | Hardcore death roasts |
| [`CrossTalk/`](CrossTalk/) | **CrossTalk (Forever)** | Short phrases the other faction can read on WoW Forever, spelled out in letters the game lets through |
| [`PacesQualityOfLife/`](PacesQualityOfLife/) | **Pace's Quality of Life (Forever)** | Track or untrack a whole zone from the quest log, LFG players by role, a quest tracker that follows your zone, who's in a community voice channel before you join, each person's voice volume kept, your party's pets on the party frames, each computer its own Edit Mode layout, and a gold finder for the auction house (your recipes' profit, bargains, vendor items, your bags, recipes worth buying) |

Each folder's README covers that addon. `tests/` holds the offline
harnesses (`lua5.1 tests/harness_<name>.lua .`) and `scripts/package.sh`
builds the CurseForge zips into `dist/`.
