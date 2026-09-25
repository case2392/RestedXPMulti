# Adventure Plates

An adventurer plate for your character, the way Final Fantasy XIV does it:
a card anyone can open on anyone, with your model, your name and a title
of your choosing, your guild and rank, your level, race and class, the
roles you play, up to four playstyle tags, when you are usually on, and a
motto. Drawn on Classic Era's page (the same spellbook-page cut that
Classic UI (Forever) uses, kept here so nothing else is needed), with
your face in the ring. Built for World of Warcraft Forever; it also loads
on Classic Era. Inspired by the streamer Shobek asking for FFXIV's
adventurer plates in Forever.

```
/plate            your plate
/plate edit       fill it in
/plate <name>     ask another player for theirs
/plate target     the player you have targeted (mouseover and focus work too)
/plate share      who may ask for yours: everyone, friends, off
/plate chat       a link to your plate in the chat box
/plate hours      learning when you play: on, off, forget
/plate button     the minimap button on or off
/plate report     a report to paste with a bug or an idea
/plate welcome    the welcome window again
/plate options    the options panel
```

Right-clicking a player gives you **View Adventure Plate** on their menu,
and right-clicking your own portrait gives you **View** and **Edit My
Adventure Plate**. The minimap button opens your plate with a left click
and the settings with a right click; drag it round the ring.

The model turns like the character screen's: drag it, use the mouse
wheel to zoom, or hold Era's rotate buttons under it.

## Bugs and ideas

`/plate report` opens a copyable report (versions, settings, what the
plate holds, what was sent and received, any error the addon caught).
Paste it, with a screenshot if something looks wrong, as a comment on the
CurseForge page, or email it to classicuiforforever@gmail.com. Ideas and
suggestions are welcome the same way. A welcome window says so the first
time the addon runs.

## What is on a plate

- **Name and nickname.** The nickname is yours to type, shown as
  « The Explorer » under your name; if you leave it blank, the title your
  character wears in game is shown instead.
- **Guild and rank, level, race and class** in the class colour, read
  from the game each time the plate is shown or sent.
- **Roles** you play: tank, healer, damage, as the LFG role icons.
- **Playstyle & Focus**: up to four of Dungeon Delver, Casual Leveling,
  World PvP, Hardcore / Survival, Raiding, Battlegrounds, Roleplay,
  Crafting & Trading, Exploration, Chatting & Hanging Out, Helping
  Newcomers, Gold Making, Pets & Mounts, Questing & Lore.
- **Active Playtime (Server Time)**: two rows of 24 cells, weekdays and
  weekends, lit for the hours you usually play. The current server hour
  is marked, so a viewer can see at a glance whether now is one of your
  hours.
- **Looking for**: a line for what you are after, such as "a levelling
  guild" or "dungeon buddies".
- **Professions**: your two primary professions and their skill, read
  from the game.
- **Alt of**: name your main on an alt's plate. Viewers click it to open
  the main's plate.
- **Adventurer Motto**: up to 160 characters.

Two things the card does for you. On someone else's plate, the hours you
both play are green, so you can see at a glance when you overlap. And
the addon notes the hours this account is logged in (a sample every ten
minutes, kept only on your computer, off in the settings if you prefer),
so after an hour or so **Use my hours** in the editor fills the playtime
rows for you.

**Share in Chat** puts `[Adventure Plate: Name-Realm]` in your chat box.
The game only lets its own kinds of link through, so it travels as plain
text, and anyone with the addon sees it as a clickable link that opens
your plate.

## How plates travel

Plates go over the addon message channel, so both players need the addon.
Nothing is sent unless someone asks: `/plate Bob` whispers Bob's addon a
request, his addon answers with his plate (split into 255-byte pieces and
put back together), and the plate opens on your screen with his model if
he is in range (targeted, moused over, in your group) and his class icon
if not. Plates you have seen are kept, so asking again shows the last one
at once and refreshes it when the new answer arrives.

Who may ask for yours is a setting: everyone (the default, it is a social
feature), only friends, guildmates and your group (matched on the whole
Name-Realm, so a stranger on another realm with a friend's first name is
not the friend), or nobody. Requests are only answered when whispered,
and a request from the same player is answered at most once every few
seconds. Everything outgoing passes through one slow queue (a few
messages a second) so a burst of requests can never make your client
flood the channel.

Nothing comes in unasked either: a plate is only shown if it answers a
request you made, and whose plate it is comes from the server's word on
who sent it, never from the plate itself. Text in a plate that came from
someone else is stripped of links, colour codes and control characters
before it is shown or kept, every field is length-capped (in letters, so
accented text is never cut mid-character), and numbers are bounded, so a
plate cannot be used to inject anything into your chat or your saved file.

One plate per character on the account, in `AdventurePlatesDB`.

## Testing

```
lua5.1 tests/harness_adventureplates.lua .
```

A pure-Lua harness with a mock client covers the data, the wire format
(escaping, chunking, reassembly out of order), asking and answering, the
sharing modes, the card, the editor, saving and reloading, the menu
entries, the slash commands, Era's page, the model controls, the minimap
button, the welcome, the report, professions, the looking-for line, the
main link, learned and shared hours, and the chat link.
