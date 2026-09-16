-- RIP Bozo - hardcore death roasts
--
-- Listens for hardcore death announcements (the HARDCORE_DEATHS alert event,
-- the HardcoreDeaths chat channel, and the system-message fallback), prints
-- a roast for every death in your own chat, and whispers a random line to
-- the fallen player. By default that whisper only goes to people you know
-- (guildmates, friends, party/raid members). "Everyone" mode whispers any
-- death on the realm, rate limited and skipping brand-new characters, so it
-- stays banter rather than a spam cannon.

local addonName, ns = ...

ns.VERSION = "1.0.0"

--------------------------------------------------------------------------
-- the lines
--------------------------------------------------------------------------

ns.LINES = {
    "RIPBOZO",
    "Bro, you shouldn't have done that.",
    "See you in Forever.",
    "Enjoy Skyborne, bro. LOL",
    "F",
    "Skill issue.",
    "Should've hearthed, bro.",
    "Level 1 speedrun starts now.",
    "Rest in pieces.",
    "The mob sends its regards.",
    "You had one job: don't die.",
    "Have you tried not dying?",
    "Achievement unlocked: Permanent Vacation.",
    "Gone but not forgotten. Actually, forgotten.",
    "That graveyard has a great view though.",
    "Boss music was for you, bro.",
    "New character, who dis?",
    "Delete key's right there, bro.",
    "Hardcore? More like hard corpse.",
    "Ran it back yet?",
    "Your gear is a souvenir now.",
    "Congrats on the free character slot.",
    "Nice try, bozo.",
    "The Spirit Healer says hi.",
    "Bro really thought he could pull two.",
    "In Forever you can rez. Just saying.",
    "Ghost form suits you.",
    "Press F to pay respects. Actually don't, he's a bozo.",
    "Somewhere a murloc is celebrating.",
    "Big yikes, bro."
}

local DEFAULTS = {
    guild = true, -- whisper guildmates who die
    friends = true, -- whisper friends (friends list + Battle.net) who die
    party = true, -- whisper party/raid members who die
    everyone = false, -- whisper anyone who dies (rate limited, see below)
    minLevel = 10, -- "everyone" mode ignores deaths below this level
    self = true, -- roast yourself in chat when you die
    feed = true, -- roast every death you see, in your own chat only
    custom = {} -- extra lines added with /ripbozo add
}

--------------------------------------------------------------------------
-- where people die: level ranges so the roast can do the math
--------------------------------------------------------------------------

ns.ZONES = {
    -- dungeons
    ["Ragefire Chasm"] = {13, 18, dungeon = true},
    ["Wailing Caverns"] = {17, 24, dungeon = true},
    ["The Deadmines"] = {17, 26, dungeon = true},
    ["Deadmines"] = {17, 26, dungeon = true},
    ["Shadowfang Keep"] = {22, 30, dungeon = true},
    ["The Stockade"] = {22, 30, dungeon = true},
    ["Stormwind Stockade"] = {22, 30, dungeon = true},
    ["Blackfathom Deeps"] = {24, 32, dungeon = true},
    ["Gnomeregan"] = {29, 38, dungeon = true},
    ["Razorfen Kraul"] = {29, 38, dungeon = true},
    ["Scarlet Monastery"] = {34, 45, dungeon = true},
    ["Razorfen Downs"] = {37, 46, dungeon = true},
    ["Uldaman"] = {41, 51, dungeon = true},
    ["Zul'Farrak"] = {44, 54, dungeon = true},
    ["Maraudon"] = {46, 55, dungeon = true},
    ["The Temple of Atal'Hakkar"] = {50, 60, dungeon = true},
    ["Sunken Temple"] = {50, 60, dungeon = true},
    ["Blackrock Depths"] = {52, 60, dungeon = true},
    ["Blackrock Spire"] = {55, 60, dungeon = true},
    ["Lower Blackrock Spire"] = {55, 60, dungeon = true},
    ["Upper Blackrock Spire"] = {58, 60, dungeon = true},
    ["Dire Maul"] = {55, 60, dungeon = true},
    ["Stratholme"] = {58, 60, dungeon = true},
    ["Scholomance"] = {58, 60, dungeon = true},
    -- cities
    ["Stormwind City"] = {1, 60, city = true},
    ["Ironforge"] = {1, 60, city = true},
    ["Darnassus"] = {1, 60, city = true},
    ["Orgrimmar"] = {1, 60, city = true},
    ["Thunder Bluff"] = {1, 60, city = true},
    ["Undercity"] = {1, 60, city = true},
    -- zones
    ["Elwynn Forest"] = {1, 10}, ["Dun Morogh"] = {1, 10}, ["Teldrassil"] = {1, 10},
    ["Durotar"] = {1, 10}, ["Mulgore"] = {1, 10}, ["Tirisfal Glades"] = {1, 10},
    ["Westfall"] = {10, 20}, ["Loch Modan"] = {10, 20}, ["Darkshore"] = {10, 20},
    ["The Barrens"] = {10, 25}, ["Silverpine Forest"] = {10, 20},
    ["Redridge Mountains"] = {15, 25}, ["Stonetalon Mountains"] = {15, 27},
    ["Duskwood"] = {18, 30}, ["Ashenvale"] = {18, 30}, ["Wetlands"] = {20, 30},
    ["Hillsbrad Foothills"] = {20, 30}, ["Thousand Needles"] = {25, 35},
    ["Desolace"] = {30, 40}, ["Arathi Highlands"] = {30, 40},
    ["Alterac Mountains"] = {30, 40}, ["Stranglethorn Vale"] = {30, 45},
    ["Dustwallow Marsh"] = {35, 45}, ["Badlands"] = {35, 45},
    ["Swamp of Sorrows"] = {35, 45}, ["The Hinterlands"] = {40, 50},
    ["Tanaris"] = {40, 50}, ["Feralas"] = {40, 50}, ["Searing Gorge"] = {43, 50},
    ["Azshara"] = {45, 55}, ["Blasted Lands"] = {45, 55},
    ["Un'Goro Crater"] = {48, 55}, ["Felwood"] = {48, 55},
    ["Burning Steppes"] = {50, 58}, ["Western Plaguelands"] = {51, 58},
    ["Eastern Plaguelands"] = {53, 60}, ["Winterspring"] = {53, 60},
    ["Silithus"] = {55, 60}, ["Deadwind Pass"] = {55, 60}
}

-- {name} {level} {killer} {zone} {min} {max} get filled in
ns.CONTEXT = {
    low = {
        "Level {level} in {zone}? That's a {min}-{max} zone. What did you think was gonna happen, bro.",
        "{zone} at level {level}. Bold. Dead, but bold.",
        "You walked into {zone} at level {level} and got humbled by {killer}. Yeah.",
        "{min}+ zone, level {level} character. The math was right there, bro."
    },
    high = {
        "Bro, {level} in {zone}? That's a {min}-{max} zone and you still died. LOL. Come on.",
        "Outleveled {zone} by miles and {killer} still got you. Impressive, honestly.",
        "Level {level} losing to {killer} in a {max} zone. RIPBOZO.",
        "{zone} caps at {max}. You were {level}. Explain."
    },
    range = {
        "{killer} in {zone}. Textbook.",
        "A {killer}. Really, bro. A {killer}.",
        "Level {level}, {zone}, {killer}. Speedrun to the graveyard.",
        "{zone} claims another one. {killer} says thanks for the XP."
    },
    city = {
        "You died in {zone}. A city. With guards. Bro.",
        "Killed by {killer} inside {zone}. The guards watched.",
        "Dying in {zone} is a choice. You chose it."
    },
    dungeonLow = {
        "{zone} is a {min}-{max} dungeon and you went in at {level}. Your group carried a corpse, bro.",
        "Level {level} in {zone}. Who invited you, bro."
    },
    dungeonHigh = {
        "Bro, {level} in {zone} and you died? That dungeon is {min}-{max}. LOL. Come on.",
        "You were {level} in a {max} dungeon and {killer} still got the kill. RIPBOZO."
    }
}

-- a few killers deserve their own line
ns.KILLERS = {
    {"murloc", "Mrglglgl. Rest in peace."},
    {"captive", "Killed by a Captive. A prisoner. Behind bars. Bro."},
    {"defias", "VanCleef's boys send their regards."},
    {"kobold", "You no take candle. Or life, apparently."},
    {"critter", "Killed by a critter. There is no coming back from that."},
    {"fatigue", "Swam into the fog and drowned in it. Nature's leash, bro."},
    {"drowning", "Drowned. In a video game. With a breath bar on screen."},
    {"falling", "Gravity: 1. You: 0."},
    {"lava", "It's red and it hurts. Nobody told you?"},
    {"son of arugal", "Son of Arugal. Every Horde player saw that coming."},
    {"stitches", "Stitches did his job. You didn't do yours."},
    {"devilsaur", "Devilsaur. You heard the footsteps. You stayed."},
    {"rare", "Died to a rare. At least it was special."}
}

local function Expand(template, vars)
    return (template:gsub("{(%w+)}", function(k) return tostring(vars[k] or "") end))
end

local function ZoneInfo(zone)
    if not zone then return nil end
    local z = ns.ZONES[zone]
    if z then return z end
    local lower = zone:lower()
    for name, data in pairs(ns.ZONES) do
        if lower:find(name:lower(), 1, true) then return data end
    end
    return nil
end

-- a line that uses the death details, or nil when there's nothing to say
function ns.ContextLine(info)
    if not info then return nil end
    local killer = info.killer and info.killer:lower() or ""
    for _, k in ipairs(ns.KILLERS) do
        if killer:find(k[1], 1, true) and math.random() < 0.5 then
            return k[2], "killer"
        end
    end
    local z = ZoneInfo(info.zone)
    if not z or not info.level then return nil end
    local vars = {
        name = info.name, level = info.level, killer = info.killer or "something",
        zone = info.zone, min = z[1], max = z[2]
    }
    local kind
    if z.city then
        kind = "city"
    elseif info.level < z[1] then
        kind = z.dungeon and "dungeonLow" or "low"
    elseif info.level > z[2] then
        kind = z.dungeon and "dungeonHigh" or "high"
    else
        kind = "range"
    end
    local pool = ns.CONTEXT[kind]
    return Expand(pool[math.random(#pool)], vars), kind
end

local DEDUPE_SECONDS = 600 -- same name dying twice inside this = same death
local WHISPER_DELAY_MIN, WHISPER_DELAY_MAX = 2, 5
local STRANGER_LIMIT, STRANGER_WINDOW = 20, 3600 -- "everyone" whispers per hour

ns.db = nil
ns.seen = {} -- name -> time of last roast (dedupe)
ns.lastDeath = nil -- name of the most recent death we saw
ns.strangerTimes = {} -- when we whispered strangers (rate limit window)
local used = {} -- lines handed out since the last full cycle
local usedCount = 0

function ns.Print(fmt, ...)
    local msg = fmt
    if select("#", ...) > 0 then msg = fmt:format(...) end
    print("|cFFFF4444RIP Bozo|r: " .. msg)
end

--------------------------------------------------------------------------
-- line picking: cycles through every line before any repeats
--------------------------------------------------------------------------

function ns.AllLines()
    local all = {}
    for _, l in ipairs(ns.LINES) do all[#all + 1] = l end
    if ns.db and ns.db.custom then
        for _, l in ipairs(ns.db.custom) do all[#all + 1] = l end
    end
    return all
end

function ns.PickLine()
    local all = ns.AllLines()
    if usedCount >= #all then
        used = {}
        usedCount = 0
    end
    local fresh = {}
    for _, l in ipairs(all) do
        if not used[l] then fresh[#fresh + 1] = l end
    end
    if #fresh == 0 then return all[1] end
    local line = fresh[math.random(#fresh)]
    used[line] = true
    usedCount = usedCount + 1
    return line
end

--------------------------------------------------------------------------
-- who counts as "someone you know"
--------------------------------------------------------------------------

local function Short(name)
    if not name then return nil end
    if Ambiguate then return Ambiguate(name, "none") end
    return name
end

local function SameName(a, b)
    if not a or not b then return false end
    a, b = a:lower(), b:lower()
    if a == b then return true end
    -- "Name" vs "Name-Realm"
    local ab = a:match("^([^%-]+)") or a
    local bb = b:match("^([^%-]+)") or b
    return ab == bb
end

function ns.IsGuildmate(name)
    if not IsInGuild or not IsInGuild() or not GetNumGuildMembers then
        return false
    end
    local total = GetNumGuildMembers() or 0
    for i = 1, total do
        local member = GetGuildRosterInfo(i)
        if member and SameName(member, name) then return true end
    end
    return false
end

function ns.IsFriend(name)
    if C_FriendList and C_FriendList.GetNumFriends then
        for i = 1, C_FriendList.GetNumFriends() or 0 do
            local info = C_FriendList.GetFriendInfoByIndex(i)
            if info and info.name and SameName(info.name, name) then
                return true
            end
        end
    end
    if BNGetNumFriends and C_BattleNet and C_BattleNet.GetFriendAccountInfo then
        for i = 1, BNGetNumFriends() or 0 do
            local info = C_BattleNet.GetFriendAccountInfo(i)
            local game = info and info.gameAccountInfo
            if game and game.characterName and
                SameName(game.characterName, name) then
                return true
            end
        end
    end
    return false
end

function ns.IsGroupmate(name)
    if UnitInParty and UnitInParty(name) then return true end
    if UnitInRaid and UnitInRaid(name) then return true end
    return false
end

-- strangers: at most STRANGER_LIMIT whispers per STRANGER_WINDOW seconds
function ns.StrangerAllowed(now)
    local kept = {}
    for _, t in ipairs(ns.strangerTimes) do
        if now - t < STRANGER_WINDOW then kept[#kept + 1] = t end
    end
    ns.strangerTimes = kept
    return #kept < STRANGER_LIMIT
end

-- returns why we'd whisper them, or nil
function ns.Relationship(name, level, now)
    local db = ns.db
    if db.party and ns.IsGroupmate(name) then return "party" end
    if db.guild and ns.IsGuildmate(name) then return "guild" end
    if db.friends and ns.IsFriend(name) then return "friend" end
    if db.everyone then
        if level and level < (db.minLevel or 0) then return nil end
        if not ns.StrangerAllowed(now or 0) then return nil end
        return "everyone"
    end
    return nil
end

--------------------------------------------------------------------------
-- parsing death announcements
--------------------------------------------------------------------------

-- Real channel text:
--   "Name has been slain by a Defias Captive in The Stockade! They were level 31"
-- Chat shows it as "[5] : Name has been ..." (5 = channel number, varies).
-- Older/other forms: "Name has died at level 23", "Name has fallen ...".
-- Returns {name=, level=, killer=, zone=} or nil.
function ns.ParseDeath(text)
    if type(text) ~= "string" then return nil end
    local plain = text:gsub("|H.-|h%[(.-)%]|h", "%1") -- [Name] links -> Name
    plain = plain:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    plain = plain:gsub("|H.-|h", ""):gsub("|h", "")
    -- strip "[5] :", "[5. HardcoreDeaths]", "[HardcoreDeaths]" style prefixes
    while true do
        local inner, rest = plain:match("^%s*%[([^%]]*)%]%s*:?%s*(.*)$")
        if not inner then break end
        local li = inner:lower()
        if li:match("^%d") or li:find("hardcore", 1, true) then
            plain = rest
        else
            break
        end
    end
    plain = plain:gsub("^%s*:%s*", "")
    local lower = plain:lower()
    if not (lower:find("slain") or lower:find("died") or lower:find("fallen") or
        lower:find("killed") or lower:find("perished")) then
        return nil
    end
    local name = plain:match("^%s*([%a\128-\255][%w\128-\255%-']*)")
    if not name then return nil end
    local info = {name = name}
    info.level = tonumber(plain:match("[Ll]evel (%d+)"))
    local killer, zone = plain:match("slain by (.-) in (.-)[!%.]")
    if not killer then killer = plain:match("slain by (.-)[!%.]") end
    if killer then
        killer = killer:gsub("^an? ", "")
        info.killer = killer
    end
    if zone then info.zone = zone end
    if not info.zone then
        zone = plain:match(" in ([%a' ]+)[!%.]")
        if zone then info.zone = zone end
    end
    return info
end

--------------------------------------------------------------------------
-- reacting to a death
--------------------------------------------------------------------------

local function Whisper(name, line)
    if SendChatMessage then
        SendChatMessage(line, "WHISPER", nil, name)
    end
end

local function Later(seconds, fn)
    if C_Timer and C_Timer.After then
        C_Timer.After(seconds, fn)
    else
        fn()
    end
end

function ns.OnDeath(info, source)
    if not info or not info.name or not ns.db then return end
    local name, level = info.name, info.level
    local me = UnitName and UnitName("player")
    if me and SameName(name, me) then return end -- own death handled by PLAYER_DEAD

    local now = (GetTime and GetTime()) or 0
    local key = Short(name):lower()
    if ns.seen[key] and now - ns.seen[key] < DEDUPE_SECONDS then return end
    ns.seen[key] = now
    ns.lastDeath = Short(name)
    ns.lastInfo = info

    local line = ns.ContextLine(info) or ns.PickLine()
    local who = Short(name)
    if level then who = ("%s (level %d)"):format(who, level) end
    if info.killer and info.zone then
        who = ("%s, %s in %s"):format(who, info.killer, info.zone)
    end

    local relation = ns.Relationship(name, level, now)
    if relation then
        if relation == "everyone" then
            ns.strangerTimes[#ns.strangerTimes + 1] = now
        end
        local delay = WHISPER_DELAY_MIN +
                          math.random() * (WHISPER_DELAY_MAX - WHISPER_DELAY_MIN)
        Later(delay, function() Whisper(name, line) end)
        local label = ({party = "your party member", guild = "your guildmate",
                        friend = "your friend", everyone = "them"})[relation]
        ns.Print("%s died. Whispering %s: \"%s\"", who, label, line)
    elseif ns.db.feed then
        ns.Print("%s died. %s", who, line)
    end
end

function ns.OnOwnDeath()
    if not ns.db or not ns.db.self then return end
    ns.Print("You died. %s", ns.PickLine())
end

--------------------------------------------------------------------------
-- manual roast
--------------------------------------------------------------------------

function ns.RoastNow(target)
    local name = target
    if not name or name == "" then
        if UnitExists and UnitExists("target") and UnitIsPlayer and
            UnitIsPlayer("target") then
            name = UnitName("target")
        else
            name = ns.lastDeath
        end
    end
    if not name then
        ns.Print("nobody to roast: target a player, or wait for someone to die.")
        return nil
    end
    local line
    if ns.lastInfo and SameName(ns.lastInfo.name, name) then
        line = ns.ContextLine(ns.lastInfo)
    end
    line = line or ns.PickLine()
    Whisper(name, line)
    ns.Print("roasted %s: \"%s\"", Short(name), line)
    return name, line
end

--------------------------------------------------------------------------
-- events
--------------------------------------------------------------------------

function ns.InitDB()
    RIPBozoDB = RIPBozoDB or {}
    for k, v in pairs(DEFAULTS) do
        if RIPBozoDB[k] == nil then
            if type(v) == "table" then
                RIPBozoDB[k] = {}
            else
                RIPBozoDB[k] = v
            end
        end
    end
    ns.db = RIPBozoDB
end

local function IsDeathChannel(channelName, baseName)
    local n = ((baseName or "") .. " " .. (channelName or "")):lower()
    return n:find("hardcoredeaths", 1, true) ~= nil or
               n:find("hardcore deaths", 1, true) ~= nil
end

function ns.OnEvent(event, ...)
    if event == "ADDON_LOADED" then
        if (...) == addonName then ns.InitDB() end
    elseif event == "PLAYER_LOGIN" then
        if not ns.db then ns.InitDB() end
    elseif event == "HARDCORE_DEATHS" then
        local info = ns.ParseDeath((...))
        if info then ns.OnDeath(info, "alert") end
    elseif event == "CHAT_MSG_CHANNEL" then
        local text, _, _, channelName, _, _, _, _, baseName = ...
        if IsDeathChannel(channelName, baseName) then
            local info = ns.ParseDeath(text)
            if info then ns.OnDeath(info, "channel") end
        end
    elseif event == "CHAT_MSG_SYSTEM" then
        local text = ...
        local info = ns.ParseDeath(text)
        if info and info.level then ns.OnDeath(info, "system") end
    elseif event == "PLAYER_DEAD" then
        ns.OnOwnDeath()
    end
end

if CreateFrame then
    local frame = CreateFrame("Frame")
    for _, e in ipairs({
        "ADDON_LOADED", "PLAYER_LOGIN", "HARDCORE_DEATHS", "CHAT_MSG_CHANNEL",
        "CHAT_MSG_SYSTEM", "PLAYER_DEAD"
    }) do pcall(frame.RegisterEvent, frame, e) end
    frame:SetScript("OnEvent", function(_, event, ...) ns.OnEvent(event, ...) end)
    ns.frame = frame
end

--------------------------------------------------------------------------
-- slash commands
--------------------------------------------------------------------------

local function OnOff(v) return v and "|cFF66FF66on|r" or "|cFFFF6666off|r" end

local function PrintStatus()
    local db = ns.db
    ns.Print("v%s - auto-whisper: guild %s, friends %s, party %s, everyone %s (min level %d) | self-roast %s | death feed %s",
             ns.VERSION, OnOff(db.guild), OnOff(db.friends), OnOff(db.party),
             OnOff(db.everyone), db.minLevel or 0, OnOff(db.self), OnOff(db.feed))
    ns.Print("%d lines (%d custom). /ripbozo help for commands.",
             #ns.AllLines(), #db.custom)
end

local function PrintHelp()
    ns.Print("commands:")
    ns.Print("  /rip - whisper a roast to your target (or the last death you saw)")
    ns.Print("  /rip <name> - whisper a roast to that player")
    ns.Print("  /ripbozo guild|friends|party on|off - who gets auto-whispered when they die")
    ns.Print("  /ripbozo everyone on|off - whisper anyone who dies (max %d an hour, skips low levels)", STRANGER_LIMIT)
    ns.Print("  /ripbozo minlevel <n> - everyone mode ignores deaths below this level")
    ns.Print("  /ripbozo self on|off - roast yourself in chat when you die")
    ns.Print("  /ripbozo feed on|off - roast every death you see, in your chat only")
    ns.Print("  /ripbozo test - print a random line")
    ns.Print("  /ripbozo list - print every line")
    ns.Print("  /ripbozo add <text> - add your own line")
    ns.Print("  /ripbozo clear - remove your custom lines")
end

function ns.HandleOptions(input)
    input = input or ""
    local cmd, arg = input:match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()
    local db = ns.db
    if cmd == "" or cmd == "status" then
        PrintStatus()
    elseif cmd == "help" then
        PrintHelp()
    elseif cmd == "minlevel" then
        local n = tonumber(arg)
        if n then
            db.minLevel = math.floor(n)
            ns.Print("everyone mode ignores deaths below level %d.", db.minLevel)
        else
            ns.Print("usage: /ripbozo minlevel <level> (currently %d)", db.minLevel or 0)
        end
    elseif cmd == "guild" or cmd == "friends" or cmd == "party" or cmd ==
        "self" or cmd == "feed" or cmd == "everyone" then
        arg = arg:lower()
        if arg == "on" then
            db[cmd] = true
        elseif arg == "off" then
            db[cmd] = false
        else
            db[cmd] = not db[cmd]
        end
        ns.Print("%s %s.", cmd, OnOff(db[cmd]))
        if cmd == "everyone" and db.everyone then
            ns.Print("heads up: this whispers strangers. It's capped at %d an hour, one per death, and skips deaths below level %d. Unsolicited whispers can get reported, so keep it to banter.",
                     STRANGER_LIMIT, db.minLevel or 0)
        end
    elseif cmd == "test" then
        ns.Print(ns.PickLine())
    elseif cmd == "list" then
        for i, l in ipairs(ns.AllLines()) do ns.Print("%d. %s", i, l) end
    elseif cmd == "add" then
        if arg == "" then
            ns.Print("usage: /ripbozo add <text>")
        else
            table.insert(db.custom, arg)
            ns.Print("added: \"%s\"", arg)
        end
    elseif cmd == "clear" then
        db.custom = {}
        ns.Print("custom lines removed.")
    else
        PrintHelp()
    end
end

if SlashCmdList then
    SLASH_RIPBOZO1 = "/ripbozo"
    SlashCmdList["RIPBOZO"] = ns.HandleOptions
    SLASH_RIP1 = "/rip"
    SlashCmdList["RIP"] = function(input)
        input = (input or ""):match("^%s*(.-)%s*$")
        ns.RoastNow(input ~= "" and input or nil)
    end
end

_G.RIPBozo = ns
