-- Offline harness for RIP Bozo (Lua 5.1).   lua5.1 tests/harness_ripbozo.lua .
local root = arg and arg[1] or "."
local realPrint = print
local passed, failed = 0, 0
local function check(cond, label)
    if cond then passed = passed + 1 else failed = failed + 1; realPrint("FAIL: " .. label) end
end

local printed, whispers, timers
local function Printed(pat)
    for _, l in ipairs(printed) do if l:find(pat, 1, true) then return true end end
    return false
end

local function NewWorld(opts)
    opts = opts or {}
    printed, whispers, timers = {}, {}, {}
    _G.print = function(...) local t = {} for i = 1, select("#", ...) do t[i] = tostring(select(i, ...)) end table.insert(printed, table.concat(t, " ")) end
    _G.RIPBozoDB = opts.db
    _G.CreateFrame = function() local f = {} function f:RegisterEvent() end function f:SetScript(_, fn) self.fn = fn end return f end
    _G.SlashCmdList = {}
    _G.C_Timer = {After = function(s, fn) table.insert(timers, {s, fn}) end}
    _G.SendChatMessage = function(msg, kind, _, target) table.insert(whispers, {msg = msg, kind = kind, target = target}) end
    _G.GetTime = function() return opts.now or 1000 end
    _G.UnitName = function(u) if u == "player" then return "Pacetrio" elseif u == "target" then return opts.target end end
    _G.UnitExists = function(u) return u == "target" and opts.target ~= nil end
    _G.UnitIsPlayer = function(u) return u == "target" and opts.target ~= nil end
    _G.Ambiguate = function(n) return (n:match("^([^%-]+)")) end
    _G.IsInGuild = function() return opts.guild ~= nil end
    _G.GetNumGuildMembers = function() return opts.guild and #opts.guild or 0 end
    _G.GetGuildRosterInfo = function(i) return opts.guild[i] end
    _G.C_FriendList = {
        GetNumFriends = function() return opts.friends and #opts.friends or 0 end,
        GetFriendInfoByIndex = function(i) return {name = opts.friends[i]} end
    }
    _G.BNGetNumFriends = function() return opts.bnet and #opts.bnet or 0 end
    _G.C_BattleNet = {GetFriendAccountInfo = function(i) return {gameAccountInfo = {characterName = opts.bnet[i]}} end}
    _G.UnitInParty = function(n) return opts.party and opts.party[n] or false end
    _G.UnitInRaid = function() return false end
    math.randomseed(opts.seed or 1)
    local ns = {}
    _G.GetSubZoneText = function() return opts.subzone end
    _G.GetRealZoneText = function() return opts.zone end
    for _, f in ipairs({"Zones.lua", "RIPBozo.lua"}) do
        local chunk = assert(loadfile(root .. "/RIPBozo/" .. f))
        chunk("RIPBozo", ns)
    end
    ns.OnEvent("ADDON_LOADED", "RIPBozo")
    ns.OnEvent("PLAYER_LOGIN")
    return ns
end

local function RunTimers() for _, t in ipairs(timers) do t[2]() end timers = {} end

-- parsing
do
    local ns = NewWorld()
    local i = ns.ParseDeath("Rheaper has been slain by a Defias Captive in The Stockade! They were level 31")
    check(i and i.name == "Rheaper" and i.level == 31 and i.killer == "Defias Captive" and i.zone == "The Stockade", "parse: real HardcoreDeaths format")
    i = ns.ParseDeath("[5] : Rheaper has been slain by a Defias Captive in The Stockade! They were level 31")
    check(i and i.name == "Rheaper" and i.zone == "The Stockade", "parse: chat-rendered [5] : prefix")
    i = ns.ParseDeath("[12. HardcoreDeaths] Grimjaw-Defias has been slain by an Elder Mottled Boar in Durotar! They were level 4")
    check(i and i.name == "Grimjaw-Defias" and i.killer == "Elder Mottled Boar" and i.zone == "Durotar" and i.level == 4, "parse: channel-name prefix, realm suffix, 'an'")
    i = ns.ParseDeath("|cffff0000|Hplayer:Bob|h[Bob]|h|r has been slain by Stitches in Duskwood! They were level 22")
    check(i and i.name == "Bob" and i.killer == "Stitches", "parse: link and colour codes stripped")
    i = ns.ParseDeath("Old has died at level 23.")
    check(i and i.name == "Old" and i.level == 23 and i.zone == nil, "parse: older 'died at level' form")
    check(ns.ParseDeath("Bob has joined the guild.") == nil, "parse: non-death ignored")
    check(ns.ParseDeath("[Bob] has joined the guild.") == nil, "parse: bracketed name, non-death ignored")
    check(ns.ParseDeath(nil) == nil, "parse: nil safe")
end

-- contextual roasts
do
    local ns = NewWorld({seed = 7})
    local function ctx(text)
        local info = ns.ParseDeath(text)
        local line, kind = ns.ContextLine(info)
        return line, kind, info
    end
    local seenKinds = {}
    for _ = 1, 20 do
        local line, kind = ctx("Rheaper has been slain by a Guard in The Stockade! They were level 31")
        seenKinds[kind] = line
    end
    check(seenKinds.dungeonHigh and seenKinds.dungeonHigh:find("31", 1, true) and seenKinds.dungeonHigh:find("The Stockade", 1, true), "31 in the Stockade: too high for the dungeon, level and place named")
    local line, kind = ctx("Rheaper has been slain by a Guard in The Stockade! They were level 19")
    check(kind == "dungeonLow" and line:find("19", 1, true), "19 in the Stockade: too low")
    line, kind = ctx("Rheaper has been slain by a Guard in The Stockade! They were level 25")
    check(kind == "range" and line:find("Guard", 1, true), "25 in the Stockade: in range, killer named")
    line, kind = ctx("Rheaper has been slain by a Bear in Elwynn Forest! They were level 30")
    check(kind == "high" and line:find("Elwynn Forest", 1, true), "30 in Elwynn: outleveled the zone")
    line, kind = ctx("Rheaper has been slain by a Ghoul in Eastern Plaguelands! They were level 20")
    check(kind == "low" and line:find("20", 1, true), "20 in EPL: too low, level quoted")
    line, kind = ctx("Rheaper has been slain by a Guard in Stormwind City! They were level 40")
    check(kind == "city", "died in a city")
    local gotKiller = false
    for _ = 1, 40 do
        local l, k = ctx("Rheaper has been slain by a Murloc Tidehunter in Wetlands! They were level 24")
        if k == "killer" and l:find("Mrgl", 1, true) then gotKiller = true end
    end
    check(gotKiller, "murloc kill gets the murloc line sometimes")
    -- subzones resolve to their zone
    line, kind = ctx("Pkizaz has been slain by a Riverpaw Outrunner in Alexston Farmstead! They were level 16")
    check(kind == "range" and line:find("Westfall", 1, true), "Alexston Farmstead -> Westfall, level 16 in range")
    check(ns.ResolveZone("Alexston Farmstead") == "Westfall", "the real death from the screenshot resolves to Westfall")
    line, kind = ctx("Pkizaz has been slain by a Defias Pillager in Alexston Farmstead! They were level 30")
    check(kind == "high" and line:find("Westfall", 1, true), "level 30 in a Westfall subzone: outleveled")
    line, kind = ctx("Bob has been slain by a Ghoul in Corin's Crossing! They were level 30")
    check(kind == "low" and line:find("Eastern Plaguelands", 1, true), "Corin's Crossing -> Eastern Plaguelands")
    line, kind = ctx("Bob has been slain by a Guard in Trade District! They were level 30")
    check(kind == "city" and line:find("Stormwind City", 1, true), "Trade District -> Stormwind City")
    check(ns.ResolveZone("the crossroads") == "The Barrens" and ns.ResolveZone("The Crossroads") == "The Barrens", "subzone lookup is case-insensitive")
    -- learned subzones fill the gaps
    check(ns.ResolveZone("Some New Cave") == nil, "unknown subzone: nothing")
    _G.GetSubZoneText = function() return "Some New Cave" end
    _G.GetRealZoneText = function() return "Redridge Mountains" end
    ns.OnEvent("ZONE_CHANGED")
    check(_G.RIPBozoDB.learned["some new cave"] == "Redridge Mountains", "walking through a subzone records its zone")
    check(ns.ResolveZone("Some New Cave") == "Redridge Mountains", "learned subzone resolves")
    line, kind = ctx("Bob has been slain by a Gnoll in Some New Cave! They were level 40")
    check(kind == "high" and line:find("Redridge Mountains", 1, true), "learned subzone feeds the roast")
    line, kind = ctx("Rheaper has been slain by a Thing in Nowhere Land! They were level 24")
    check(line == nil, "unknown zone: no context line (generic used instead)")
    line = ns.ContextLine(ns.ParseDeath("Old has died at level 23."))
    check(line == nil, "no zone in the message: no context line")
    for _, pool in pairs(ns.CONTEXT) do
        for _, tpl in ipairs(pool) do check(#tpl <= 255, "context line fits a whisper") end
    end
end

-- who gets whispered
do
    local ns = NewWorld({guild = {"Rheaper", "Grimjaw-Defias"}, friends = {"Sneaky"}, bnet = {"Bnetbud"}, party = {Groupie = true}})
    ns.OnEvent("HARDCORE_DEATHS", "Rheaper has died at level 23")
    check(#timers == 1, "guildmate: whisper scheduled")
    check(timers[1][1] >= 2 and timers[1][1] <= 5, "guildmate: whisper delayed a few seconds")
    RunTimers()
    check(#whispers == 1 and whispers[1].kind == "WHISPER" and whispers[1].target == "Rheaper", "guildmate: whispered")
    check(Printed("Rheaper (level 23) died. Whispering your guildmate"), "guildmate: announced in chat")

    ns.OnEvent("CHAT_MSG_CHANNEL", "Sneaky has died at level 40", "Sneaky", "", "1. HardcoreDeaths", "", "", 0, 1, "HardcoreDeaths")
    RunTimers()
    check(#whispers == 2 and whispers[2].target == "Sneaky", "friend via death channel: whispered")
    ns.OnEvent("CHAT_MSG_CHANNEL", "Bnetbud has died at level 12", "", "", "1. HardcoreDeaths", "", "", 0, 1, "HardcoreDeaths")
    RunTimers()
    check(#whispers == 3 and whispers[3].target == "Bnetbud", "battle.net friend: whispered")
    ns.OnEvent("HARDCORE_DEATHS", "Groupie has died at level 9")
    RunTimers()
    check(#whispers == 4 and whispers[4].target == "Groupie" and Printed("Whispering your party member"), "party member: whispered")

    -- strangers: chat feed only, never a whisper
    ns.OnEvent("HARDCORE_DEATHS", "Randomguy has died at level 31")
    RunTimers()
    check(#whispers == 4, "stranger: no whisper")
    check(Printed("Randomguy (level 31) died."), "stranger: roasted in own chat")

    -- other channels are ignored
    ns.OnEvent("CHAT_MSG_CHANNEL", "Rheaper has died lol", "Someone", "", "2. Trade", "", "", 0, 2, "Trade")
    check(#timers == 0, "trade chat 'died' ignored")

    -- dedupe: alert + channel for the same death -> one whisper
    ns.OnEvent("HARDCORE_DEATHS", "Rheaper has died at level 23")
    ns.OnEvent("CHAT_MSG_CHANNEL", "Rheaper has died at level 23", "", "", "1. HardcoreDeaths", "", "", 0, 1, "HardcoreDeaths")
    check(#timers == 0, "same death announced twice: no second whisper")

    -- own death is never whispered, roasted locally instead
    ns.OnEvent("HARDCORE_DEATHS", "Pacetrio has died at level 50")
    check(#timers == 0, "own name in the feed: no self whisper")
    ns.OnEvent("PLAYER_DEAD")
    check(Printed("You died."), "own death: self roast")
    check(#whispers == 4, "own death: nothing sent")
end

-- everyone mode
do
    local ns = NewWorld({friends = {"Sneaky"}})
    ns.OnEvent("HARDCORE_DEATHS", "Stranger1 has been slain by a Wolf in Elwynn Forest! They were level 8")
    check(#timers == 0, "everyone off: stranger not whispered")
    ns.HandleOptions("everyone on")
    check(_G.RIPBozoDB.everyone == true and Printed("heads up"), "everyone on: saved with a warning")
    ns.OnEvent("HARDCORE_DEATHS", "Newbie has been slain by a Wolf in Elwynn Forest! They were level 8")
    check(#timers == 0 and Printed("Newbie (level 8)"), "everyone on: level 8 skipped (min level 10), still in the feed")
    ns.OnEvent("HARDCORE_DEATHS", "Stranger2 has been slain by a Defias Captive in The Stockade! They were level 31")
    RunTimers()
    check(#whispers == 1 and whispers[1].target == "Stranger2" and Printed("Whispering them"), "everyone on: stranger whispered")
    check(whispers[1].msg:find("31", 1, true) or whispers[1].msg:find("Captive", 1, true) or #whispers[1].msg > 0, "everyone on: whisper has content")
    ns.HandleOptions("minlevel 30")
    ns.OnEvent("HARDCORE_DEATHS", "Stranger3 has been slain by a Boar in Durotar! They were level 25")
    check(#timers == 0, "minlevel 30: level 25 skipped")
    ns.HandleOptions("minlevel 1")
    for i = 4, 30 do
        ns.OnEvent("HARDCORE_DEATHS", ("Stranger%d has been slain by a Boar in Durotar! They were level 25"):format(i))
    end
    RunTimers()
    check(#whispers == 20, "rate limit: at most 20 stranger whispers an hour")
    ns.OnEvent("HARDCORE_DEATHS", "Sneaky has been slain by a Boar in Durotar! They were level 25")
    RunTimers()
    check(#whispers == 21 and whispers[21].target == "Sneaky", "rate limit: friends are not limited")
    ns.HandleOptions("everyone off")
    check(_G.RIPBozoDB.everyone == false, "everyone off again")
end

-- toggles
do
    local ns = NewWorld({guild = {"Rheaper"}, party = {Groupie = true}})
    ns.HandleOptions("guild off")
    ns.OnEvent("HARDCORE_DEATHS", "Rheaper has died at level 23")
    check(#timers == 0 and Printed("Rheaper (level 23) died."), "guild off: guildmate only roasted locally")
    ns.HandleOptions("feed off")
    ns.OnEvent("HARDCORE_DEATHS", "Nobody has died at level 5")
    check(not Printed("Nobody (level 5)"), "feed off: strangers silent")
    ns.OnEvent("HARDCORE_DEATHS", "Groupie has died at level 5")
    check(#timers == 1, "feed off: party member still whispered")
    ns.HandleOptions("self off")
    printed = {}
    ns.OnEvent("PLAYER_DEAD")
    check(#printed == 0, "self off: no self roast")
    check(_G.RIPBozoDB.guild == false and _G.RIPBozoDB.feed == false and _G.RIPBozoDB.self == false, "toggles saved")
    ns.HandleOptions("")
    check(Printed("auto-whisper: guild"), "status prints")
end

-- line cycling and custom lines
do
    local ns = NewWorld()
    local total = #ns.AllLines()
    local seen = {}
    for i = 1, total do
        local l = ns.PickLine()
        check(not seen[l], "no repeat before the whole list is used (" .. i .. ")")
        seen[l] = true
    end
    check(seen["RIPBOZO"] and seen["Bro, you shouldn't have done that."] and seen["See you in Forever."] and seen["Enjoy Skyborne, bro. LOL"], "requested lines present")
    local again = ns.PickLine()
    check(seen[again], "cycle restarts after all lines used")
    ns.HandleOptions("add You're him. Were.")
    check(#ns.AllLines() == total + 1 and _G.RIPBozoDB.custom[1] == "You're him. Were.", "custom line added and saved")
    ns.HandleOptions("clear")
    check(#ns.AllLines() == total, "custom lines cleared")
    ns.HandleOptions("test")
    check(#printed >= 1, "test prints a line")
    for _, l in ipairs(ns.LINES) do
        check(#l <= 255, "line fits a whisper: " .. l)
    end
end

-- manual /rip
do
    local ns = NewWorld({target = "Victim"})
    local name = ns.RoastNow(nil)
    check(name == "Victim" and #whispers == 1 and whispers[1].target == "Victim", "/rip roasts the target")
    ns.RoastNow("Other")
    check(#whispers == 2 and whispers[2].target == "Other", "/rip <name> roasts by name")
    local ns2 = NewWorld({})
    check(ns2.RoastNow(nil) == nil and Printed("nobody to roast"), "/rip with nothing: explains")
    ns2.OnEvent("HARDCORE_DEATHS", "Fresh has died at level 3")
    check(ns2.RoastNow(nil) == "Fresh", "/rip falls back to the last death seen")
    SlashCmdList["RIP"]("  Spaced  ")
    check(whispers[#whispers].target == "Spaced", "slash trims the name")
end

realPrint(("RIP Bozo harness: %d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
