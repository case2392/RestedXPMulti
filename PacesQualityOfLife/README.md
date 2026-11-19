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
them, the newest winning: their character; in a Battle.net community
their Battle.net account and their place in the community (which still
finds them should the account's GUID change between sessions); and for a
Battle.net friend both the account and the character they're playing. So
a friend set from their party frame and from a community's roster has
one volume: the one you set last.

In dungeons and raids (the game's chat lockdown) nothing is set and no
community list is read. A change you make there is kept under what the
game still says, and under the rest of the person's names once you're
out. When the game doesn't say whose it was (a roster drawn inside the
dungeon), the volume is noted, and once you're out the person found at
exactly that volume keeps it instead of being set back - except at the
top (100%), where everyone starts, so that can't be told. Such a change
is lost if you log out before leaving the dungeon.

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

Whether the switch took is read back from the setting itself. If the
game refuses it, it isn't tried again: you're told once what to type
instead, and the options page says so until the setting changes. If the
game marks the setting as one add-ons can't change, the box can't be
ticked and says so. A switch is made at the logout of the character it
was asked on. Not tried in game yet.

## Commands

- `/pqol` - the options page
- `/pqol status` - what's on, and any errors this session
- `/pqol <feature> on|off` - `questlog`, `lfgroles`, `zonetracker`, `voice`, `voicevolume`, `partypets`
- `/pqol voice` - what voice sharing sent, heard and was refused (`/pqol voice log`: the last messages)
- `/pqol voicevolume` - how many volumes are kept (`/pqol voicevolume forget`: forget them all)

## Offline tests

`lua5.1 tests/harness_pacesqol.lua .` from the repository root.
