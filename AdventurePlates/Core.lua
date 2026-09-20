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

ns.VERSION = "1.1.0"
ns.PREFIX = "ADVPLATE"
ns.FORMAT = 1
ns.MAX_TAGS = 4
ns.MAX_TITLE = 30
ns.MAX_MOTTO = 160
ns.CACHE_SIZE = 60

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
    welcomed = false    -- the welcome has been read
}

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

function ns.Sanitize(text, limit)
    if type(text) ~= "string" then return "" end
    text = text:gsub("|", ""):gsub("[%c]", " ")
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    if limit and #text > limit then text = text:sub(1, limit) end
    return text
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
        motto = ""
    }
end

-- the fields another player fills in, checked and trimmed
function ns.CleanPlate(p)
    local out = ns.NewPlate()
    if type(p) ~= "table" then return out end
    out.title = ns.Sanitize(p.title, ns.MAX_TITLE)
    out.motto = ns.Sanitize(p.motto, ns.MAX_MOTTO)
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
    out.level = tonumber(p.level) or 0
    out.race = ns.Sanitize(p.race, 32)
    out.class = ns.Sanitize(p.class, 32)
    out.classFile = ns.Sanitize(p.classFile, 16):upper()
    out.guild = ns.Sanitize(p.guild, 48)
    out.rank = ns.Sanitize(p.rank, 32)
    out.gameTitle = ns.Sanitize(p.gameTitle, 48)
    out.faction = ns.Sanitize(p.faction, 16)
    out.updated = tonumber(p.updated) or 0
    return out
end

local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d = pcall(fn, ...)
    if ok then return a, b, c, d end
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
    plate.updated = Call(time) or 0
    return plate
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
    for i = #cache, 1, -1 do if cache[i].key == key then table.remove(cache, i) end end
    table.insert(cache, 1, {key = key, plate = plate, seen = Call(time) or 0})
    while #cache > ns.CACHE_SIZE do table.remove(cache) end
end

function ns.Cached(key)
    for _, entry in ipairs(ns.db.cache) do
        if entry.key == key then return entry.plate, entry.seen end
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
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()
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
    elseif cmd == "button" then
        local mode = rest:lower()
        if mode == "on" or mode == "off" then
            ns.SetMinimapButton(mode == "on")
            ns.Print("minimap button %s", mode)
        else
            ns.Print("the minimap button is %s. /plate button on|off", ns.db.settings.minimap and "on" or "off")
        end
    elseif cmd == "help" then
        ns.Print("/plate - your plate.  /plate edit - fill it in.  /plate <name> - ask for someone's plate.  /plate target - the player you have targeted.  /plate share everyone|friends|off - who may ask for yours.  /plate button on|off - the minimap button.  /plate report - a report to paste with a bug or an idea.  /plate welcome - the welcome again.  /plate options.")
    else
        ns.RequestPlate(ns.FullName(cmd))
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
