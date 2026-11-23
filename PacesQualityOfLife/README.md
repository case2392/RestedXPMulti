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
only at a login (never at a /reload) and only when the character's
layout isn't the computer's already - that is, the first login on a
computer after playing on the other one. In combat it waits for the
fight to end (a /reload meanwhile doesn't lose it); with Edit Mode open
it leaves the layout to you.

Another layout put on during a session - picked in Edit Mode, or a new,
copied or imported one - stays until you log out, a /reload included
(it says so); press **Use current** to make it the computer's instead.
`/pqol layout forget` stops the switching.

The computer's layout is found by its name (a preset by its number): one
of the kind you kept first - the account's, or a character's own - else
one of that name of the other kind. A character with no layout of that
name (it was renamed or deleted, or it's another character's own) isn't
switched, and you're told. If a switch doesn't take, it isn't tried
again (no reload after reload) until you choose the layout again.

"This computer" means this computer's own saved settings for Pace's QoL
(in WoW's `WTF` folder, never sent to the game's servers). If you copy or
sync that folder between computers, they can't be told apart. Not tried
in game yet.

## Auction house: Gold finder

A window that says what makes you gold right now, from your own recipes
and the auction house's prices. Open it with `/pqol gold`, the **Gold
finder** tab along the bottom of the auction house (after its other
tabs, Auctionator's included), or **Open** in the options. It has four tabs. Click a column to sort by it;
hover a row to see how its numbers were worked out and how old its price
is. To keep the columns readable, a price of a gold or more is shown in
the lists without its copper.

It only reads and adds up. It never buys, bids, posts or cancels: you do
that yourself, in the auction house.

**Crafts** - one row per recipe that makes an item, for every character
of yours on the realm whose profession window you've opened (that's how
recipes are learned: open each profession once on each character;
Forever changed some recipes, so none are built in). *Cost* is the
cheapest way to get the materials: the cheapest auctions, a vendor, or
your own craft of them, whichever is less (the tooltip says when more
is needed than is listed, and part of the cost is a guess, and when a
vendor's price is a built-in one no vendor has confirmed). *Sells for*
is the best of three: the auction house (after the cut), a vendor, or
disenchanting (when one of your characters is an enchanter, and never for
what disenchanting won't take: what enchanters make - wands - and shirts
and tabards). *Profit* is
one less the other. *Listed* is how many are on the auction house; *Can
make* is how many your bags and bank hold the materials for. A recipe
whose output binds when it is made is shown for an enchanter's own
recipes only, with "-" for Listed: it can be vendored or disenchanted,
never auctioned, and no price is looked up for it. Tick
**Enchants: what they cost** to see each enchant's materials cost
instead - the least to charge.

**Bargains** - auctions worth buying, from a scan or a price check less
than an hour old:

- *Vendor*: listed for less than a vendor pays.
- *Disenchant*: gear listed well under what its materials sell for (for
  enchanters). Never what disenchanting won't take: what enchanters make
  (the wands, anything an enchanting recipe of yours makes) and shirts
  and tabards. Never on a material that has none listed and no usual
  price yet: the price it was last seen at is no reason to buy. (Your
  bags and Crafts still show such a disenchant value, and the tooltip
  says what it rests on.)
- *Resell*: stackable items at 70% or less of their usual price. Only a
  quarter of what's listed is counted, and resale is a guess.
- *Material*: a material of your recipes at 80% or less of its usual
  price (and under the vendor's, if a vendor sells it; against a
  built-in vendor price the saving is an estimate, and says so).
- *Essence*: buy three Lesser and combine them, or a Greater and split
  it, when the other size sells for more (for enchanters).

*Buy up to* is the highest price still worth paying, *Units* how many
the profit counts (for essences: how many conversions).

**Vendors** - things a vendor sells that go for more on the auction
house: at least 20% more after the cut. Vendors' prices are remembered
as you visit them; a short built-in list of trade supplies (thread, dye,
vials, flux...) is shown as "price not confirmed" until you've visited
one. Limited-supply items are marked.

**Your bags** - for each item: what a vendor pays, what it sells for at
auction after the cut, what it disenchants into, and the best of the
three. The line under the list adds them up; an unproven auction price
is left out of the sums (a stack whose best is the vendor or
disenchanting anyway still counts there), and the line says how many
stacks that leaves out. An item that could be auctioned but has no price
shows "?" and isn't guessed at - Price my items looks it up. One that
was looked up, or that a whole scan didn't see, and isn't listed (a
piece "of the Bear" when only other kinds, or none at all, are for
sale, too) has its answer: its best is the vendor or disenchanting -
unless it was listed within the last 14 days and has no usual price
yet: then it is valued at the price it last went for, marked as
unproven, and the tooltip says when that was. An
item a profitable recipe of yours uses says so. For an enchanter, an
essence is valued as its other size when that pays more (three Lesser
make a Greater, and back); the tooltip then says to combine or split
first.

How a selling price is worked out: the lowest price listed now, or the
item's usual price if that is lower - one hopeful listing far above the
going rate doesn't count. Neither does one cheap lot far below it: units
listed for less than a vendor pays, or at 70% or less of the usual
price, are passed over when they are a quarter of what's listed at most
(Bargains is where those show up, to buy); the tooltip then says which
price was used. The usual price is the middle of the last 14
days' prices, and needs three days of them. A yellow * marks an unproven
price (only one or two listed, or all at one price: one seller's asking
price - or none listed now and no usual price yet, so the price it was
last seen at in the last 14 days is shown); a grey * means none are
listed now and the usual price is shown.
A price over 48 hours old is "last seen": it shows its age in grey and
isn't used as today's.

### Getting prices

With the auction house open, three ways:

- **Scan** reads every auction once. The game allows it about once every
  15 minutes; the button counts down the wait. Keep the auction house
  open while it reads - closing it (or a /reload) cuts the scan short
  and changes nothing, and the wait still runs. What the last scan knew
  and this one doesn't see counts as sold out, and what your recipes,
  bags and vendors use and it didn't see as "none listed" - so straight
  after a scan there is nothing left for Price my items to do. (One
  exception: a piece of gear whose details the game hadn't loaded yet is
  read without its "of the Bear". The scan then says nothing about that
  item's kinds, and Price my items looks up the one in your bags.) The
  wait is counted as one for all of a realm's auction houses. The
  options have "Scan the whole auction house each time I open it" (off
  unless you tick it).
- **Price my items** looks up just what your recipes and bags use - the
  materials, what they make, an enchanter's materials, what's in your
  bags, the vendor items - one a second, up to 300 a press, skipping
  anything priced (or scanned) in the last 10 minutes. It works while
  Scan is on its wait. Press it again to stop. It pauses while you are
  buying or selling, and goes on when you're back on the list.
- **What you browse yourself** is read as it goes by: the results of
  your own searches. A price seen only in a browse list never raises a
  bargain, and for an hour it doesn't replace what a scan or a look-up
  read - unless that was "none listed" and the list now shows some.

Your own auctions aren't counted. A look-up always tells them apart. A
scan goes by the sellers' names, or else by what your Auctions tab
listed on this visit to the auction house - the list isn't kept from
one visit to the next, since auctions sell without a word, and an
auction the list shows as sold isn't taken for one still up. If a scan
can do neither (the tab wasn't opened this visit, or you posted or
cancelled an auction since), the window asks you to open your Auctions
tab once. If prices the scan read then still count yours, it says how
many and to press Price my items, which looks those items up again and
leaves yours out; the next scan does too. One thing is counted: a
stackable item another character of yours has up at a price other
sellers share. The game doesn't say how many of those are the alt's, so
that price stays, the alt's units included; only a price that is yours
alone is left out.

The header says what the price book holds: how many items have a
price, when the last full scan was, and when your items were last
looked up if that was later.

**Search** puts the selected row's name into the auction house's search
box; you click Search there.

### Auctionator

Optional. When Auctionator is installed, its price is used where Pace's
QoL has none of its own from the last 48 hours - if Auctionator's is at
most two days old, and not for weapons and armor (it can't tell "of the
Bear" from "of the Whale"). The window's header then says "(some prices
from Auctionator)". The Search button uses Auctionator's exact search
instead of the search box. Nothing is written to Auctionator, and its
prices raise no bargains. TradeSkillMaster is not used.

### The cut, and estimates

The auction house's cut is counted as 5% of every sale.
`/pqol gold cut` says what is counted, `/pqol gold cut 10` changes it
(0 to 30). A neutral auction house is counted at 15% at least and keeps
prices of its own (the header says so, before its first scan too); it
is told by the auctioneer's faction not being yours, which may not hold
on Forever. The listing deposit isn't
counted: it comes back when the item sells and is lost when it doesn't.

Some numbers are estimates: what disenchanting gives (vanilla's tables
- an average over many items, a single one can give less), the essence
conversions, and the built-in vendor prices. A profit that rests on one
is shown with a "~", and a built-in vendor price is called "not
confirmed" wherever it is used, until a vendor has shown its own. None
of them was checked on Forever.

### What is remembered

In Pace's QoL's saved settings (WoW's `WTF` folder, shared by your
account's characters), nothing is sent anywhere:

- prices, per realm and faction (WoW Forever gives no realm name: there,
  one set per faction for the whole game): each item's lowest price, how many
  were listed, the few cheapest prices and 14 days of its typical
  price, never the auctions themselves. A price not seen for 30 days
  is dropped (a "none listed" answer: 30 days after it was last asked
  for);
- each character's recipes (dropped when the character hasn't opened a
  profession for 180 days);
- vendors' prices, and where the window was left.

`/pqol gold forget` forgets this realm's prices; recipes and vendor
prices stay, and so does the wait until the next scan. Not tried in
game yet.

## Commands

- `/pqol` - the options page
- `/pqol status` - what's on, and any errors this session (with where each
  came from), in a window with the text selected: Ctrl+C copies it to send
  with a bug report. The options page's **Status** button opens it too.
- `/pqol <feature> on|off` - `questlog`, `lfgroles`, `zonetracker`, `voice`, `voicevolume`, `partypets`, `layout`, `gold`
- `/pqol voice` - what voice sharing sent, heard and was refused (`/pqol voice log`: the last messages)
- `/pqol voicevolume` - how many volumes are kept (`/pqol voicevolume forget`: forget them all)
- `/pqol layout` - this computer's Edit Mode layout and the one on now (`/pqol layout use`: make the one on now this computer's; `/pqol layout forget`: stop switching)
- `/pqol gold` - open or close the gold finder
- `/pqol gold scan` - read the whole auction house (it must be open; about once every 15 minutes)
- `/pqol gold price` - look up the items your recipes and bags use (again: stop)
- `/pqol gold cut` - the auction house's cut that is counted (`/pqol gold cut <0-30>`: change it)
- `/pqol gold forget` - forget this realm's prices
- `/pqol gold help` - this list, in game

## Offline tests

`lua5.1 tests/harness_pacesqol.lua .` from the repository root.
