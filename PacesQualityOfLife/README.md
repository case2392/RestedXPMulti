# Pace's Quality of Life (WoW Forever)

Small conveniences for World of Warcraft Forever's own windows. Each one
can be switched off in **Options > AddOns > Pace's Quality of Life**
(or `/pqol`).

## Quest log: track or untrack a whole zone, or everything

In the Map & Quest Log, every zone header (Redridge Mountains, Ashenvale,
Blackfathom Deeps...) gets a tracking checkbox like the ones on the
quests: click it to track every quest in that zone, click again to
untrack them all. A faint tick means some of the zone is tracked. The
"Quests: 34/40" box above the list has one for all quests, and the
list's gear menu has **Track all quests** / **Untrack all quests**.

The game tracks at most 25 quests at once (the quest log holds 40), so
"track all" fills up to 25 - the zones on the open map first - and says
how many didn't fit. A box that has filled what it can counts as full:
its next click untracks.

## Looking For Group: players by role

In the Looking For Group window, three role buttons (tank, healer,
damage) sit between **Send Message** and **Group Invite**. Click one to
see only the players listing that role - one click on the healer for
"healers only". Click others to add or remove roles; clear the last one
to see everyone again. While a filter is on, the matching players show
in a list of their own with its own Send Message and Group Invite
buttons (select a player, then click; double-click whispers).

Blizzard's own list is never changed. Inside dungeons, raids and
encounters the game hides this data from add-ons, so the filter steps
aside there and Blizzard's list shows as usual.

## Objective tracker follows your zone

When you enter a zone, the tracker switches to that zone's quests: every
quest under the zone's quest log header is tracked, the others are
untracked. Go to Duskwood and you see Duskwood's quests. It happens once
per zone - anything you track or untrack by hand stays until you enter
the next zone (a /reload doesn't count as entering one). A dungeon's
quests show inside the dungeon; the quest you've set your arrow on stays
tracked; nothing changes during combat or a flight (it catches up
after).

## Chat Channels: who's in voice, before you join

Forever's Chat Channels window only shows who is in a community's voice
channel once you're in it. With Pace's QoL, members who are in the voice
channel get a microphone next to their name in the roster - before you
join.

The game doesn't tell add-ons who's in a voice channel you haven't
joined, so Pace's QoL users tell each other with invisible add-on
messages (nothing appears in chat). Opening Chat Channels on a community
asks the members the game lets an add-on reach:

- your Battle.net friends who are playing Forever,
- your guild and your party or raid (one message each),
- in a WoW community, the members of your faction.

The ones in that voice channel who also run Pace's QoL answer, and say
when they join or leave. A big community is asked 60 at a time, every
minute while the window is open, the people who answered before first.
In a Battle.net community, someone who is not your Battle.net friend and
not in your guild or group can't be reached by any add-on, so they don't
show. Nothing is sent in dungeons, raids or encounters (the game's chat
lockdown); a join or leave made there is told once you're out of it. A
/reload while in voice doesn't hide you from the people looking, and
logging out tells them at once. You can stop answering in the options;
then nobody sees you, except in the case below.

A channel you joined earlier this session and left with the headset is
different: the game still knows who's in it, so those people show even
if they don't run the add-on.

Only a community stream's voice is covered, in the Chat Channels window
(not party voice, and not the Guild & Communities window).

If a microphone is missing, type `/pqol voice` on both sides - the one
looking (with Chat Channels open on the stream) and the one in voice. It
says what was sent, what came back and what the game refused, without
names. `/pqol voice log` lists the last messages.

Since 1.2.0 a Battle.net friend is also asked when the community gives
no Battle.net account for them: the account is then read from their
GUID, as the game's own menus do. 1.1.0 asked nobody in that case - one
possible reason for a report of a friend in voice who never showed
(`/pqol voice` says when it happened). Not tried in game yet.

## Voice chat: each person's volume, kept

Right-click someone in a voice channel (or their party frame, in party
voice) and the slider under their name sets how loud they are - but the
game doesn't keep it. Pace's QoL remembers the volume you set for each
person and sets it again whenever they're in voice with you: when they
join your channel, when you join theirs, after a /reload, and the next
time you play. It sets nothing when the volume already matches, and keeps
only what you set with the slider (never the game's own resets).

One person goes by several names, and the volume is kept under all of
them that can be told, the newest winning: their character; in a
Battle.net community you share, their Battle.net account and their place
in the community (which still finds them should the account's GUID change
between sessions); and for a Battle.net friend in such a community, both
the account and the character they're playing. So a friend set from their
party frame and from the community's roster has one volume - the one you
set last - and it follows them to another character. A Battle.net friend
you share no Battle.net community with is known by their character alone
(nothing gives an add-on a lasting name for their account): a volume set
for one of their characters isn't set for their others. And someone in a
Battle.net community with you who isn't your Battle.net friend is known
by their account in the community and by their character in party
voice, with nothing to link the two: each keeps the volume set under it.

In dungeons and raids (the game's chat lockdown) nothing is set and no
community list is read. A change you make there is kept under what the
game still says, and under the rest of the person's names once you're
out.

A member list drawn inside the dungeon (Chat Channels, Communities)
doesn't say whose a change is - nor once you're out, until the window is
opened again. A change made from it is noted, and once you're out
someone whose volume was kept before, found at exactly that volume, keeps
it instead of being set back. A first change for someone isn't kept that
way (someone found at that volume could be at a volume kept under another
of their names), nor is one to the top (100%), where everyone starts:
whoever has a volume kept is set back to it. Set them again from their
party frame, or from the list once you've closed and opened it again. A
change made from such a list is lost if you log out before leaving the
dungeon.

Up to 1000 names are kept (one person can have a few), the oldest change
going first. `/pqol voicevolume` says how many people that is, and
`/pqol voicevolume forget` forgets them all. Not tried in game yet.

## Party frames: your party's pets

The game's standard party frames (not the raid-style ones) have a pet
frame under each party member, but WoW Forever's options have no switch
for it, so a hunter's or warlock's pet never shows. Tick **Party frames:
show your party members' pets** in the options (or `/pqol partypets on`)
and they show **after your next /reload** - the options page has a
**Reload now** button. Untick it to hide them again (also at a reload).

Why a reload: the party frames act on this setting the moment it
changes, and changed from an add-on that would run as add-on code,
which could leave them unable to show a pet or move in combat until a
reload anyway. At the reload they read it afresh. Nothing is changed in
combat: a reload during a fight leaves it for the next one. It is the
game's own setting (`showPartyPets`, the same as typing
`/console showPartyPets 1` and then reloading), so it stays as it is
even with Pace's QoL removed.

Each character's switch is its own: it is made at that character's own
reload or logout, and your other characters neither see it nor make it.
Whether it took is read back from the setting itself. If the game
refuses it, it isn't tried again: at that character's next login you're
told once what to type instead, and its options page says so until the
setting changes or you ask for another switch. If the game marks the
setting as one add-ons can't change, the box can't be ticked and says
so. Not tried in game yet.

## Edit Mode: each computer its own layout

Edit Mode's layouts are your account's, and so is which one each
character has on: play on your laptop after your PC and the character
comes up with the PC's layout, until you switch it in Edit Mode. Pace's
QoL keeps a layout for each computer and switches to it as you log in.

Setting it up, once on each computer: pick the computer's layout in Edit
Mode, then press **Use current** next to "Edit Mode: each computer its
own layout" in the options (or type `/pqol layout use`). From then on,
every character logging in on that computer is switched to its layout.

How the switch is made: the game applies a layout from inside the call
that switches it, so switched from an add-on, the whole layout - the
action bars and frames it places - would be applied as add-on code, which
can leave them unable to change in combat for the rest of the session.
So the add-on switches and reloads the UI at once, and the reloaded UI
applies the layout as the game's own. That's one extra loading screen,
only when the character's layout isn't the computer's already - that is,
the first login on a computer after playing on the other one. In combat
it waits for the fight to end.

Picking another layout in Edit Mode keeps it until you log out (it says
so); press **Use current** to make it the computer's instead.
`/pqol layout forget` stops the switching. If the computer's layout is
renamed or deleted, or is another character's own layout, nothing is
switched and you're told. If a switch doesn't take, it isn't tried again
(no reload after reload) until you choose the layout again.

"This computer" means this computer's own saved settings for Pace's QoL
(in WoW's `WTF` folder, never sent to the game's servers). If you copy or
sync that folder between computers, they can't be told apart. Not tried
in game yet.

## Commands

- `/pqol` - the options page
- `/pqol status` - what's on, and any errors this session
- `/pqol <feature> on|off` - `questlog`, `lfgroles`, `zonetracker`, `voice`, `voicevolume`, `partypets`, `layout`
- `/pqol voice` - what voice sharing sent, heard and was refused (`/pqol voice log`: the last messages)
- `/pqol voicevolume` - how many volumes are kept (`/pqol voicevolume forget`: forget them all)
- `/pqol layout` - this computer's Edit Mode layout and the one on now (`/pqol layout use`: make the one on now this computer's; `/pqol layout forget`: stop switching)

## Offline tests

`lua5.1 tests/harness_pacesqol.lua .` from the repository root.
