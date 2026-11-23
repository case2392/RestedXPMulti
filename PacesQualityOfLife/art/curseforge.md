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

> Track or untrack a whole zone's quests in one click, filter Looking For Group players by role, keep the quest tracker on your zone, see who's in voice, keep each person's voice volume, see your party's pets, give each computer its own Edit Mode layout, and find what makes gold: your recipes' profit, auction house bargains, the best way to sell your bags.

## Description

`curseforge-description.html` in this folder, paste-ready. Open it in a
browser, select all, copy, and paste into CurseForge's description editor
(the formatting comes along). If the editor has an HTML/source view, the
file's text can go there directly.

## File upload

| Field | Value |
|---|---|
| File | `dist/PacesQualityOfLife-1.4.0.zip` (contains the `PacesQualityOfLife` folder) |
| Display name | Pace's Quality of Life 1.4.0 |
| Release type | Beta (1.4.0's gold finder, 1.3.0's Edit Mode layouts and 1.2's party pets, voice volumes and voice fix not tried in game yet; switch to Release once they have been) |
| Game version | WoW Forever |
| Changelog | below: 1.4.0's |

## Changelog (1.4.0)

```
1.4.0
- New: the Gold finder, a window that says what makes you gold right now. Open it with /pqol gold or the Gold finder button above the auction house's top right corner. It never buys, bids, posts or cancels - it reads prices and adds up; you do the buying and selling.
- New: Crafts tab. Every recipe of yours that makes an item: what the materials cost (the cheapest of auctions, a vendor or your own craft), what it sells for (the best of auction, vendor or disenchanting), the profit, how many are listed and how many you can make. Open each profession window once on each character so your recipes are known. A checkbox shows what each enchant's materials cost.
- New: Bargains tab. Auctions worth buying, with the price to buy up to: listed for less than a vendor pays, gear under what it disenchants into, stackable items at 70% or less of their usual price, your recipes' materials cheaper than usual, and essences worth combining or splitting. Only from prices less than an hour old.
- New: Vendors tab. Things a vendor sells that go for at least 20% more on the auction house after the cut. Vendors' prices are remembered as you visit them.
- New: Your bags tab. For each item, what a vendor pays, what it sells for at auction, what it disenchants into and the best of the three, added up under the list.
- New: prices three ways, with the auction house open. Scan reads every auction once (the game allows it about once every 15 minutes; the button counts down). Price my items looks up just what your recipes and bags use, one item a second, and works during Scan's wait; it pauses while you buy or sell. What you browse yourself is read as it goes by. Your own auctions aren't counted. An option scans each time you open the auction house.
- New: a selling price is the lowest listed now, or the item's usual price if that is lower, so one hopeful listing doesn't count. A * marks a price that isn't proven, or an item with none listed now. Prices over 48 hours old show their age and aren't used as today's.
- New: Auctionator is optional. When it's installed, its recent prices fill in where there are none, and the Search button uses its search; without it, Search puts the item's name in the auction house's search box and you click Search. TradeSkillMaster is not used.
- New: /pqol gold cut <0-30> sets the auction house's cut that is counted (5% unless changed). /pqol gold forget forgets this realm's prices. /pqol gold help lists the commands.
- Disenchanting values, essence conversions and the built-in vendor prices are vanilla's numbers: shown as estimates (~), not checked on WoW Forever.
```

## Changelog (1.3.0)

```
1.3.0
- New: each computer its own Edit Mode layout. Edit Mode's layouts are your account's, and so is which one each character has on, so playing on your laptop after your PC brings the PC's layout. Pick a computer's layout in Edit Mode, then press Use current next to "Edit Mode: each computer its own layout" in the options (or /pqol layout use) - once on each computer. Every character logging in there is then switched to it. The switch reloads the UI once, so the game applies the layout as its own and your bars keep working in combat; it only happens at a login (not a /reload) when the layout isn't the computer's already, and never in combat. A layout you put on during a session stays until you log out. /pqol layout forget stops it.
```

## Changelog (1.2.1)

```
1.2.1
- Voice volumes: a change made from a member list opened inside a dungeon or raid (Chat Channels, Communities), where the game doesn't say whose a change is, is now kept once you're out only for someone whose volume was kept before. 1.2.0 also kept a first change that way, which could tie it to the wrong name for that person (someone in a Battle.net community with you who isn't your Battle.net friend has one name in the community and another in party voice) and later undo a newer change. Such a first change still applies; to keep it, set it again from their party frame, or from the list once you've closed and opened it again.
- /pqol voicevolume says "from a list drawn in a dungeon or raid" for those changes.
```

## Changelog (1.2.0)

```
1.2.0
- New: your party's pets. The standard party frames can show a pet under each party member, but WoW Forever's options have no switch for it: tick "Party frames: show your party members' pets" (or /pqol partypets on). It takes effect at your next /reload - the options page has a Reload now button - so the party frames take it cleanly and keep working in combat. If the game refuses the switch, you're told what to type instead.
- New: voice volumes kept. The volume you set for someone in voice (right-click them, or their party frame in party voice: the slider) is remembered and set again whenever they're in voice with you, the next time you play too. One volume per person: a Battle.net friend in a Battle.net community with you, set from their party frame and from the community's roster, gets the one you set last. In dungeons and raids nothing is set; a change you make there is kept once you're out, not undone (except a change to 100% from a member list opened in there: everyone starts at 100%, so whose it was can't be told). /pqol voicevolume forget forgets them all.
- Voice: a Battle.net friend in a Battle.net community is now asked even when the community gives no Battle.net account for them (it is read from their GUID, as the game's own menus do). 1.1.0 asked nobody then - one possible reason a friend in voice never showed. /pqol voice says when it happened.
```

## Changelog (1.1.0)

```
1.1.0
- Chat Channels voice: microphones now show in Battle.net communities. Answers name you the way the community lists you (your Battle.net account), which 1.0.0 didn't, so nothing matched there.
- Voice: friends are found on their WoW Forever client even when their Battle.net app has the focus; guildmates and group members are found in any community; a friend still on 1.0.0 shows too, and sees you.
- Voice: no more waiting for ever on the game's "can whisper" check; your own voice is read from the game (after a /reload, a stream switch); a question the game refused is asked again.
- Voice: logging out tells the people looking at once (a /reload doesn't), and after a /reload your joins and leaves still reach them; a join or leave in a dungeon goes out once you're out; someone who goes offline loses the microphone with their grey row.
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
6. The Gold finder window on its Crafts tab, next to the auction house.
