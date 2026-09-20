-- Adventure Plates - an adventurer plate for your character
--
-- Final Fantasy XIV lets every player fill in a small card about
-- themselves - what they like doing, when they play, a motto - and anyone
-- can open it on anyone. This is that for World of Warcraft: a plate with
-- the character's model, name and title, guild and rank, level, race and
-- class, the roles they play, up to four playstyle tags, an active
-- playtime chart (weekdays and weekends, hour by hour, server time) and
-- a motto. /plate opens your own, "Edit My Plate" fills it in, and
-- /plate <name> (or the entry on a player's right-click menu) asks that
-- player's addon for theirs and shows it when it arrives. Plates travel
-- over the addon message channel, so both sides need the addon; nothing
-- is sent anywhere else and nothing is sent unless someone asks.
--
-- Core.lua: the data. What a plate holds, the tags and roles to pick
-- from, the saved variables (one plate per character on the account, the
-- settings, and a cache of plates received), the slash commands, and the
-- sanitising of text that came from another player.

local addonName, ns = ...

ns.VERSION = "1.2.0"
ns.PREFIX = "ADVPLATE"
ns.FORMAT = 1
ns.MAX_TAGS = 4
ns.MAX_TITLE = 30
ns.MAX_MOTTO = 160
ns.MAX_LOOKING = 60     -- "looking for" line
ns.MAX_MAIN = 24        -- a main character's name
ns.MAX_PROFS = 2        -- primary professions on the plate
ns.CACHE_SIZE = 60
ns.LEARN_EVERY = 600    -- seconds between playtime samples
ns.LEARN_MIN = 6        -- samples (an hour) before the learned hours are offered

-- playstyle tags: key (what travels), label, icon
ns.TAGS = {
    {key = "dungeons", label = "Dungeon Delver", icon = "Interface\\Icons\\INV_Misc_Key_03"},
    {key = "leveling", label = "Casual Leveling", icon = "Interface\\Icons\\Ability_Hunter_Pathfinding"},
    {key = "worldpvp", label = "World PvP", icon = "Interface\\Icons\\INV_Sword_27"},
    {key = "hardcore", label = "Hardcore / Survival", icon = "Interface\\Icons\\Spell_Shadow_DeathScream"},
    {key = "raiding", label = "Raiding", icon = "Interface\\Icons\\INV_Misc_Head_Dragon_01"},
    {key = "battlegrounds", label = "Battlegrounds", icon = "Interface\\Icons\\INV_BannerPVP_02"},
    {key = "roleplay", label = "Roleplay", icon = "Interface\\Icons\\INV_Misc_Book_09"},
    {key = "crafting", label = "Crafting & Trading", icon = "Interface\\Icons\\Trade_BlackSmithing"},
    {key = "exploring", label = "Exploration", icon = "Interface\\Icons\\INV_Misc_Map_01"},
    {key = "social", label = "Chatting & Hanging Out", icon = "Interface\\Icons\\INV_Misc_GroupNeedMore"},
    {key = "helping", label = "Helping Newcomers", icon = "Interface\\Icons\\Spell_Holy_PrayerOfHealing"},
    {key = "gold", label = "Gold Making", icon = "Interface\\Icons\\INV_Misc_Coin_02"},
    {key = "pets", label = "Pets & Mounts", icon = "Interface\\Icons\\Ability_Mount_WhiteTiger"},
    {key = "quests", label = "Questing & Lore", icon = "Interface\\Icons\\INV_Misc_Note_01"}
}
ns.TAG_BY_KEY = {}
for _, t in ipairs(ns.TAGS) do ns.TAG_BY_KEY[t.key] = t end

-- roles, with their slots in Era's role icon sheet
ns.ROLE_ICON = "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES"
ns.ROLES = {
    {key = "tank", label = "Tank", coords = {0, 19 / 64, 22 / 64, 41 / 64}},
    {key = "healer", label = "Healer", coords = {20 / 64, 39 / 64, 1 / 64, 20 / 64}},
    {key = "dps", label = "Damage", coords = {20 / 64, 39 / 64, 22 / 64, 41 / 64}}
}

local DEFAULT_SETTINGS = {
    share = "everyone", -- who may ask for your plate: everyone, friends (friends, guild, party), off
    menu = true,        -- the entry on a player's right-click menu
    greet = false,      -- say in chat when someone looks at your plate
    minimap = true,     -- the button on the minimap
    minimapAngle = 160, -- where round the minimap it sits
    welcomed = false,   -- the welcome has been read
    learn = true        -- note the hours I am logged in, to fill the playtime rows from
}

-- the primary professions, for a client without GetProfessions: their
-- names in the client's own language come from the profession spells,
-- with the English names as a fallback
ns.PRIMARY_PROFESSION_SPELLS = {2259, 2018, 7411, 4036, 2366, 2108, 2575, 8613, 3908, 25229, 45357}
ns.PRIMARY_PROFESSIONS = {
    Alchemy = true, Blacksmithing = true, Enchanting = true, Engineering = true, Herbalism = true,
    Leatherworking = true, Mining = true, Skinning = true, Tailoring = true, Jewelcrafting = true, Inscription = true
}
local function ProfessionNames()
    if ns.professionNamesLoaded then return ns.PRIMARY_PROFESSIONS end
    local byName = ns.PRIMARY_PROFESSIONS
    for _, id in ipairs(ns.PRIMARY_PROFESSION_SPELLS) do
        local name
        if C_Spell and C_Spell.GetSpellName then
            local ok, n = pcall(C_Spell.GetSpellName, id)
            if ok then name = n end
        elseif GetSpellInfo then
            local ok, n = pcall(GetSpellInfo, id)
            if ok then name = n end
        end
        if type(name) == "string" and name ~= "" then byName[name] = true end
    end
    ns.professionNamesLoaded = true
    return byName
end

ns.errors = {}

local function Guard(label, fn)
    return function(...)
        local ok, err = pcall(fn, ...)
        if not ok then ns.errors[#ns.errors + 1] = label .. ": " .. tostring(err) end
        return ok
    end
end
ns.Guard = Guard

function ns.Print(fmt, ...)
    local text = select("#", ...) > 0 and fmt:format(...) or fmt
    print("|cff66ccffAdventure Plates:|r " .. text)
end

--------------------------------------------------------------------------
-- text from other players: no links, no colour codes, no control codes
--------------------------------------------------------------------------

-- lengths are counted in characters, not bytes, so an accented motto is
-- capped where the editor caps it and never cut in the middle of a letter
function ns.Utf8Len(s)
    if type(s) ~= "string" then return 0 end
    local n = 0
    for _ in s:gmatch("[^\128-\191]") do n = n + 1 end
    return n
end

function ns.Utf8Cut(s, limit)
    if type(s) ~= "string" or not limit then return s end
    local n, cut = 0, #s
    for i = 1, #s do
        local b = s:byte(i)
        if b < 128 or b > 191 then
            n = n + 1
            if n > limit then cut = i - 1; break end
        end
    end
    return s:sub(1, cut)
end

function ns.Sanitize(text, limit)
    if type(text) ~= "string" then return "" end
    text = text:gsub("|", ""):gsub("[%c]", " ")
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    if limit then text = ns.Utf8Cut(text, limit) end
    return text
end

-- a number from the wire: within its bounds, or 0 (inf and nan included)
function ns.CleanNumber(v, lo, hi)
    v = tonumber(v)
    if type(v) ~= "number" or v ~= v or v < lo or v > hi then return 0 end
    return math.floor(v)
end

-- a 24-character string of 0/1, one per hour from midnight
function ns.CleanHours(s)
    if type(s) ~= "string" then return string.rep("0", 24) end
    s = s:gsub("[^01]", "0")
    if #s < 24 then s = s .. string.rep("0", 24 - #s) end
    return s:sub(1, 24)
end

--------------------------------------------------------------------------
-- the plate
--------------------------------------------------------------------------

function ns.NewPlate()
    return {
        v = ns.FORMAT,
        title = "",
        tags = {},
        roles = {},
        weekdays = string.rep("0", 24),
        weekends = string.rep("0", 24),
        motto = "",
        looking = "",   -- what they are looking for
        main = "",      -- their main character, if this is an alt
        profs = {}      -- primary professions: {name, skill, max}
    }
end

-- "Herbalism:75:150,Alchemy:40:150" <-> a list, at most two, each checked
function ns.CleanProfs(v)
    local out = {}
    local list = v
    if type(v) == "string" then
        list = {}
        for entry in v:gmatch("[^,]+") do
            local f = {}
            for part in (entry .. ":"):gmatch("([^:]*):") do f[#f + 1] = part end
            list[#list + 1] = {name = f[1], skill = f[2], max = f[3]}
        end
    end
    if type(list) ~= "table" then return out end
    for _, p in ipairs(list) do
        if type(p) == "table" then
            local name = ns.Sanitize(p.name, 24):gsub("[:,]", "")
            if name ~= "" and #out < ns.MAX_PROFS then
                out[#out + 1] = {name = name, skill = ns.CleanNumber(p.skill, 0, 1000), max = ns.CleanNumber(p.max, 0, 1000)}
            end
        end
    end
    return out
end

function ns.ProfsText(list)
    local parts = {}
    for _, p in ipairs(list or {}) do
        parts[#parts + 1] = ("%s:%d:%d"):format(p.name, p.skill or 0, p.max or 0)
    end
    return table.concat(parts, ",")
end

-- the fields another player fills in, checked and trimmed
function ns.CleanPlate(p)
    local out = ns.NewPlate()
    if type(p) ~= "table" then return out end
    out.title = ns.Sanitize(p.title, ns.MAX_TITLE)
    out.motto = ns.Sanitize(p.motto, ns.MAX_MOTTO)
    out.looking = ns.Sanitize(p.looking, ns.MAX_LOOKING)
    -- a character name: letters and one realm dash, nothing else
    out.main = ns.Sanitize(p.main, ns.MAX_MAIN):gsub("[^%w%-\128-\255]", "")
    out.main = out.main:match("^([^%-]+%-?[^%-]*)") or ""
    out.profs = ns.CleanProfs(p.profs)
    out.weekdays = ns.CleanHours(p.weekdays)
    out.weekends = ns.CleanHours(p.weekends)
    if type(p.tags) == "table" then
        for _, key in ipairs(p.tags) do
            if ns.TAG_BY_KEY[key] and #out.tags < ns.MAX_TAGS then out.tags[#out.tags + 1] = key end
        end
    end
    if type(p.roles) == "table" then
        for _, r in ipairs(ns.ROLES) do
            if p.roles[r.key] == true then out.roles[r.key] = true end
        end
    end
    -- what the sender's client said about them
    out.name = ns.Sanitize(p.name, 48)
    out.realm = ns.Sanitize(p.realm, 48)
    out.level = ns.CleanNumber(p.level, 0, 100)
    out.race = ns.Sanitize(p.race, 32)
    out.class = ns.Sanitize(p.class, 32)
    out.classFile = ns.Sanitize(p.classFile, 16):upper()
    out.guild = ns.Sanitize(p.guild, 48)
    out.rank = ns.Sanitize(p.rank, 32)
    out.gameTitle = ns.Sanitize(p.gameTitle, 48)
    out.faction = ns.Sanitize(p.faction, 16)
    out.updated = ns.CleanNumber(p.updated, 0, 4102444800) -- up to the year 2100
    return out
end

local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local r = {pcall(fn, ...)}
    if r[1] then return unpack(r, 2) end
end

function ns.RealmName()
    local r = Call(GetNormalizedRealmName)
    if type(r) ~= "string" or r == "" then
        r = Call(GetRealmName) or ""
        r = r:gsub("%s+", "")
    end
    return r
end

function ns.CharKey()
    local name = Call(UnitName, "player") or "Unknown"
    return name .. "-" .. ns.RealmName()
end

-- the character's primary professions, from the client
function ns.Professions()
    local out = {}
    if GetProfessions and GetProfessionInfo then
        local prof1, prof2 = Call(GetProfessions)
        for _, index in ipairs({prof1, prof2}) do
            if type(index) == "number" then
                local name, _, skill, max = Call(GetProfessionInfo, index)
                if type(name) == "string" then out[#out + 1] = {name = name, skill = skill or 0, max = max or 0} end
            end
        end
    elseif GetNumSkillLines and GetSkillLineInfo then
        for i = 1, Call(GetNumSkillLines) or 0 do
            local name, isHeader, _, rank, _, _, maxRank = Call(GetSkillLineInfo, i)
            if type(name) == "string" and not isHeader and ProfessionNames()[name] then
                out[#out + 1] = {name = name, skill = rank or 0, max = maxRank or 0}
            end
        end
    end
    return ns.CleanProfs(out)
end

-- the character's own facts, read from the client every time the plate is shown or sent
function ns.Snapshot(plate)
    plate.name = Call(UnitName, "player") or ""
    plate.realm = ns.RealmName()
    plate.level = Call(UnitLevel, "player") or 0
    plate.race = Call(UnitRace, "player") or ""
    local class, classFile = Call(UnitClass, "player")
    plate.class, plate.classFile = class or "", classFile or ""
    local guild, rank = Call(GetGuildInfo, "player")
    plate.guild, plate.rank = guild or "", rank or ""
    local titleID = Call(GetCurrentTitle)
    local gameTitle = titleID and titleID > 0 and Call(GetTitleName, titleID) or ""
    plate.gameTitle = type(gameTitle) == "string" and gameTitle:gsub("^%s+", ""):gsub("%s+$", "") or ""
    plate.faction = Call(UnitFactionGroup, "player") or ""
    plate.profs = ns.Professions()
    plate.updated = Call(time) or 0
    return plate
end

--------------------------------------------------------------------------
-- learned playtime: a sample every ten minutes of being logged in
--------------------------------------------------------------------------

-- server time: the hour now, and whether today is a weekend
function ns.ServerNow()
    local hour = Call(GetGameTime) or 0
    local weekend = false
    if C_DateAndTime and C_DateAndTime.GetCurrentCalendarTime then
        local t = Call(C_DateAndTime.GetCurrentCalendarTime)
        if type(t) == "table" and t.weekday then weekend = t.weekday == 1 or t.weekday == 7 end
    end
    return hour, weekend
end

local function LearnedTable()
    local db = ns.db
    if type(db.learned) ~= "table" then db.learned = {} end
    local l = db.learned
    l.weekdays = type(l.weekdays) == "table" and l.weekdays or {}
    l.weekends = type(l.weekends) == "table" and l.weekends or {}
    l.samples = tonumber(l.samples) or 0
    l.since = tonumber(l.since) or Call(time) or 0
    return l
end

function ns.RecordPlaytime()
    if not ns.db or not ns.db.settings.learn then return false end
    local hour, weekend = ns.ServerNow()
    if type(hour) ~= "number" or hour < 0 or hour > 23 then return false end
    local l = LearnedTable()
    -- a /reload or a character switch is not another ten minutes
    local now = Call(time) or 0
    if l.last and now - l.last < ns.LEARN_EVERY * 0.5 then return false end
    l.last = now
    local row = weekend and l.weekends or l.weekdays
    row[hour + 1] = (tonumber(row[hour + 1]) or 0) + 1
    l.samples = l.samples + 1
    return true
end

-- the learned hours as the two 24-character rows, or nil until enough has
-- been seen: an hour is lit when it has a fair share of the samples
function ns.LearnedHours()
    if not ns.db or type(ns.db.learned) ~= "table" then return nil end
    local l = LearnedTable()
    if l.samples < ns.LEARN_MIN then return nil, l.samples end
    -- each row has its own floor: weekends are two days to the weekdays' five
    local out, any = {}, false
    for _, key in ipairs({"weekdays", "weekends"}) do
        local peak = 0
        for h = 1, 24 do peak = math.max(peak, tonumber(l[key][h]) or 0) end
        local floor = math.max(2, peak * 0.25)
        local bits = {}
        for h = 1, 24 do
            local lit = (tonumber(l[key][h]) or 0) >= floor
            bits[h] = lit and "1" or "0"
            any = any or lit
        end
        out[key] = table.concat(bits)
    end
    -- nothing to offer until some hour has been seen more than once
    if not any then return nil, l.samples end
    return out, l.samples
end

function ns.ForgetPlaytime()
    if ns.db then ns.db.learned = nil end
end

local function ScheduleSample()
    if not (C_Timer and C_Timer.After) then return end
    C_Timer.After(ns.LEARN_EVERY, function()
        Guard("learn", ns.RecordPlaytime)()
        ScheduleSample()
    end)
end
ns.ScheduleSample = ScheduleSample

--------------------------------------------------------------------------
-- a link to the plate in chat
--------------------------------------------------------------------------

-- what goes over chat is plain text (the game only lets its own link kinds
-- through); the receiving addon turns it into a clickable link
ns.CHAT_TAG = "Adventure Plate"

function ns.ChatText(key)
    return ("[%s: %s]"):format(ns.CHAT_TAG, key or ns.CharKey())
end

local function ChatLink(key)
    return ("|cff66ccff|Haddon:AdventurePlates:%s|h[%s: %s]|h|r"):format(key, ns.CHAT_TAG, key)
end
ns.ChatLink = ChatLink

-- the chat filter: "[Adventure Plate: Name-Realm]" in a message becomes a link
-- a name is anything that cannot break the tag or the link: no space, bar, bracket or colon
local KEY_CLASS = "[^%s%c%[%]|:]+"
local TAG_PATTERN = "%[" .. ns.CHAT_TAG .. ": (" .. KEY_CLASS .. ")%]"
function ns.LinkifyChat(self, event, msg, ...)
    if type(msg) ~= "string" or not msg:find(ns.CHAT_TAG, 1, true) then return false, msg, ... end
    local out = msg:gsub(TAG_PATTERN, function(key) return ChatLink(key) end)
    return false, out, ...
end

local CHAT_EVENTS = {"CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER",
                     "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_CHANNEL",
                     "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER", "CHAT_MSG_BN_WHISPER", "CHAT_MSG_BN_WHISPER_INFORM"}

-- the chat API: ChatFrameUtil on current clients, the old globals (the
-- deprecation fallbacks, gone when loadDeprecationFallbacks is off) before
function ns.ChatAPI(new, old)
    local u = ChatFrameUtil
    if type(u) == "table" and type(u[new]) == "function" then return u[new] end
    local f = _G[old]
    if type(f) == "function" then return f end
end

function ns.InstallChatLinks()
    if ns.chatLinksInstalled then return end
    local addFilter = ns.ChatAPI("AddMessageEventFilter", "ChatFrame_AddMessageEventFilter")
    if addFilter then
        for _, e in ipairs(CHAT_EVENTS) do pcall(addFilter, e, ns.LinkifyChat) end
        ns.chatFilterInstalled = true
    end
    if hooksecurefunc and SetItemRef then
        hooksecurefunc("SetItemRef", function(link)
            local key = type(link) == "string" and link:match("^addon:AdventurePlates:(" .. KEY_CLASS .. ")$")
            -- a shift-click is the game putting the link in the chat box, not a request
            if key and not (IsModifiedClick and Call(IsModifiedClick, "CHATLINK")) then
                Guard("chat link", ns.RequestPlate)(ns.FullName(key))
            end
        end)
    end
    ns.chatLinksInstalled = true
end

-- put the link in the chat box (into the message being typed, or a new one)
function ns.ShareInChat()
    local text = ns.ChatText()
    local active = ns.ChatAPI("GetActiveWindow", "ChatEdit_GetActiveWindow")
    local insert = ns.ChatAPI("InsertLink", "ChatEdit_InsertLink")
    local open = ns.ChatAPI("OpenChat", "ChatFrame_OpenChat")
    if active and insert and Call(active) then
        if Call(insert, text) then return "inserted" end
    end
    if open then
        Call(open, text)
        return "opened"
    end
    ns.Print("paste this in chat: %s", text)
    return "printed"
end

function ns.MyPlate()
    local key = ns.CharKey()
    local p = ns.db.plates[key]
    if not p then
        p = ns.NewPlate()
        ns.db.plates[key] = p
    end
    return ns.Snapshot(p)
end

-- the cache of plates seen, newest first, capped
function ns.Remember(key, plate)
    local cache = ns.db.cache
    for i = #cache, 1, -1 do if ns.SameName(cache[i].key, key) then table.remove(cache, i) end end
    table.insert(cache, 1, {key = key, plate = plate, seen = Call(time) or 0})
    while #cache > ns.CACHE_SIZE do table.remove(cache) end
end

-- names compare without case: what a player types and what the server
-- says are the same player either way
function ns.SameName(a, b)
    return type(a) == "string" and type(b) == "string" and a:lower() == b:lower()
end

function ns.Cached(key)
    for _, entry in ipairs(ns.db.cache) do
        if ns.SameName(entry.key, key) then return entry.plate, entry.seen end
    end
end

-- "Name" or "Name-Realm" -> "Name-Realm" for our own realm, as typed otherwise
function ns.FullName(name)
    if type(name) ~= "string" or name == "" then return nil end
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then return nil end
    name = name:sub(1, 1):upper() .. name:sub(2)
    if not name:find("-", 1, true) then name = name .. "-" .. ns.RealmName() end
    return name
end

--------------------------------------------------------------------------
-- saved variables and events
--------------------------------------------------------------------------

local function LoadDB()
    local db = _G.AdventurePlatesDB
    if type(db) ~= "table" then db = {}; _G.AdventurePlatesDB = db end
    db.plates = type(db.plates) == "table" and db.plates or {}
    db.cache = type(db.cache) == "table" and db.cache or {}
    db.settings = type(db.settings) == "table" and db.settings or {}
    for k, v in pairs(DEFAULT_SETTINGS) do
        if db.settings[k] == nil then db.settings[k] = v end
    end
    ns.db = db
end

local function Slash(msg)
    msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local typed, rest = msg:match("^(%S*)%s*(.-)$")
    typed = typed or ""
    local cmd = typed:lower()
    if cmd == "" or cmd == "me" or cmd == "show" then
        ns.ShowOwnPlate()
    elseif cmd == "edit" then
        ns.ShowOwnPlate(true)
    elseif cmd == "target" or cmd == "mouseover" or cmd == "focus" then
        local unit = cmd
        if not Call(UnitExists, unit) or not Call(UnitIsPlayer, unit) then
            ns.Print("no player %s", cmd == "target" and "targeted" or ("under the " .. cmd))
            return
        end
        local name, realm = Call(UnitName, unit)
        ns.RequestPlate(ns.FullName(realm and realm ~= "" and (name .. "-" .. realm) or name), unit)
    elseif cmd == "share" then
        local mode = rest:lower()
        if mode == "everyone" or mode == "friends" or mode == "off" then
            ns.db.settings.share = mode
            ns.Print("your plate is shared with: %s", mode)
        else
            ns.Print("share is %s. /plate share everyone|friends|off", ns.db.settings.share)
        end
    elseif cmd == "options" then
        if ns.OpenOptions then ns.OpenOptions() end
    elseif cmd == "welcome" then
        if ns.ShowWelcome then ns.ShowWelcome() end
    elseif cmd == "report" or cmd == "probe" or cmd == "bug" then
        if ns.ShowReport then ns.ShowReport() end
    elseif cmd == "link" then
        ns.Print("comments: %s", ns.FEEDBACK_URL)
        ns.Print("email: %s", ns.FEEDBACK_EMAIL)
    elseif cmd == "chat" then
        ns.ShareInChat()
    elseif cmd == "hours" then
        local mode = rest:lower()
        if mode == "on" or mode == "off" then
            ns.db.settings.learn = mode == "on"
            ns.Print("learning my hours: %s", mode)
        elseif mode == "forget" then
            ns.ForgetPlaytime()
            ns.Print("learned hours forgotten")
        else
            local learned, samples = ns.LearnedHours()
            ns.Print("learning my hours is %s, %d samples so far%s. /plate hours on|off|forget", ns.db.settings.learn and "on" or "off", samples or 0,
                     learned and " (enough to fill the playtime rows: Edit My Plate, Use my hours)" or "")
        end
    elseif cmd == "button" then
        local mode = rest:lower()
        if mode == "on" or mode == "off" then
            ns.SetMinimapButton(mode == "on")
            ns.Print("minimap button %s", mode)
        else
            ns.Print("the minimap button is %s. /plate button on|off", ns.db.settings.minimap and "on" or "off")
        end
    elseif cmd == "help" then
        ns.Print("/plate - your plate.  /plate edit - fill it in.  /plate <name> - ask for someone's plate.  /plate target - the player you have targeted.  /plate chat - a link to your plate in the chat box.  /plate share everyone|friends|off - who may ask for yours.  /plate hours on|off|forget - learning when you play.  /plate button on|off - the minimap button.  /plate report - a report to paste with a bug or an idea.  /plate welcome - the welcome again.  /plate options.")
    else
        -- a name, as typed: the realm part keeps its case so the reply's
        -- sender matches it
        ns.RequestPlate(ns.FullName(typed))
    end
end

function ns.OnEvent(event, arg1, arg2, arg3, arg4)
    if event == "ADDON_LOADED" and arg1 == addonName then
        LoadDB()
        if ns.RegisterComm then ns.RegisterComm() end
    elseif event == "PLAYER_LOGIN" then
        if not ns.db then LoadDB() end
        if ns.InstallMenu then Guard("menu", ns.InstallMenu)() end
        if ns.BuildOptionsPanel then Guard("options", ns.BuildOptionsPanel)() end
        if ns.SetMinimapButton and ns.db.settings.minimap then Guard("minimap", ns.SetMinimapButton)(true) end
        if ns.ShowWelcome and not ns.db.settings.welcomed then Guard("welcome", ns.ShowWelcome)() end
        Guard("chat links", ns.InstallChatLinks)()
        Guard("learn", ns.RecordPlaytime)()
        ScheduleSample()
        _G.SLASH_ADVENTUREPLATES1 = "/plate"
        _G.SLASH_ADVENTUREPLATES2 = "/adventureplates"
        _G.SLASH_ADVENTUREPLATES3 = "/aplate"
        SlashCmdList["ADVENTUREPLATES"] = Guard("slash", Slash)
    elseif event == "CHAT_MSG_ADDON" then
        if ns.OnAddonMessage then Guard("comm", ns.OnAddonMessage)(arg1, arg2, arg3, arg4) end
    end
end

if CreateFrame then
    local f = CreateFrame("Frame")
    f:RegisterEvent("ADDON_LOADED")
    f:RegisterEvent("PLAYER_LOGIN")
    f:RegisterEvent("CHAT_MSG_ADDON")
    f:SetScript("OnEvent", function(_, ...) ns.OnEvent(...) end)
    ns.eventFrame = f
end
