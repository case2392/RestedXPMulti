-- Offline harness for Pace's Quality of Life (Lua 5.1).
--   lua5.1 tests/harness_pacesqol.lua .
-- Several simulated players, each loading the real addon files into an
-- environment of its own, with a stub of the Forever API the addon uses
-- and a message bus between them (addon whispers, GUILD, Battle.net game
-- data). Sections per feature further down.

local ROOT = arg and arg[1] or "."
local realPrint = print
-- the add-on's files, in the toc's order
local TOC_FILES = {}
for line in io.lines(ROOT .. "/PacesQualityOfLife/PacesQualityOfLife.toc") do
    local f = line:match("^([%w_]+%.lua)%s*$")
    if f then TOC_FILES[#TOC_FILES + 1] = f end
end
local passed, failed = 0, 0
local function check(cond, label)
    if cond then
        passed = passed + 1
    else
        failed = failed + 1
        realPrint("FAIL: " .. label)
    end
end

--------------------------------------------------------------------------
-- time
--------------------------------------------------------------------------

local clock, timers = 1000, {}
local function schedule(delay, fn, period, owner)
    local t = {at = clock + delay, fn = fn, period = period, owner = owner}
    table.insert(timers, t)
    return t
end
local function advance(dt)
    local target = clock + dt
    while true do
        local best, bestIdx
        for i, t in ipairs(timers) do
            if not t.cancelled and t.at <= target and (not best or t.at < best.at) then
                best, bestIdx = t, i
            end
        end
        if not best then break end
        clock = best.at
        if best.period then best.at = clock + best.period else table.remove(timers, bestIdx) end
        best.fn()
    end
    clock = target
    for i = #timers, 1, -1 do if timers[i].cancelled then table.remove(timers, i) end end
end

--------------------------------------------------------------------------
-- widgets: any CamelCase method is accepted; the ones with state are real
--------------------------------------------------------------------------

local Widget
Widget = function(kind, name, parent)
    local w = {kind = kind, name = name, parent = parent, shown = true, scripts = {},
               hooks = {}, regions = {}, events = {}, children = {}}
    setmetatable(w, {__index = function(_, k)
        if type(k) == "string" and k:match("^%u") then return function() end end
    end})
    if type(parent) == "table" and type(rawget(parent, "children")) == "table" then table.insert(parent.children, w) end
    function w:GetChildren() return unpack(self.children) end
    function w:GetObjectType() return self.kind end
    function w:Show() self.shown = true end
    function w:Hide() self.shown = false end
    function w:IsShown() return self.shown end
    function w:IsVisible() return self.shown and (not self.parent or not self.parent.IsVisible or self.parent:IsVisible()) end
    function w:SetShown(v) self.shown = v and true or false end
    function w:SetScript(k, fn) self.scripts[k] = fn end
    function w:GetScript(k) return self.scripts[k] end
    function w:HookScript(k, fn)
        self.hooks[k] = self.hooks[k] or {}
        table.insert(self.hooks[k], fn)
    end
    function w:RegisterEvent(e) self.events[e] = true end
    function w:UnregisterEvent(e) self.events[e] = nil end
    function w:SetText(t) self.text = t end
    function w:GetText() return self.text end
    function w:SetChecked(v) self.checked = v and true or false end
    function w:GetChecked() return self.checked end
    function w:SetAtlas(a) self.atlas = a end
    function w:SetAlpha(a) self.alpha = a end
    function w:GetAlpha() return self.alpha or 1 end
    function w:SetDesaturated(v) self.desaturated = v and true or false end
    function w:GetFrameLevel() return self.level or 1 end
    function w:SetFrameLevel(l) self.level = l end
    function w:SetTexture(t) self.texture = t end
    function w:SetWidth(v) self.width = v end
    function w:GetWidth() return self.width or 100 end
    function w:SetSize(x, y) self.width, self.height = x, y end
    function w:SetPoint(...) self.point = {...} end
    function w:GetPoint() if self.point then return unpack(self.point) end end
    function w:Enable() self.enabled = true end
    function w:Disable() self.enabled = false end
    function w:IsEnabled() return self.enabled ~= false end
    function w:GetParent() return self.parent end
    function w:CreateTexture() local t = Widget("Texture", nil, self); table.insert(self.regions, t); return t end
    function w:CreateFontString() local t = Widget("FontString", nil, self); table.insert(self.regions, t); return t end
    function w:GetStringHeight() return 14 end
    function w:Raise() self.raised = (self.raised or 0) + 1 end
    function w:SetWordWrap(v) self.wrap = v and true or false end
    function w:SetMaxLines(n) self.maxLines = n end
    return w
end

-- run a frame's script and its hooks, as the game does
local function RunScript(frame, k, ...)
    if frame.scripts[k] then frame.scripts[k](frame, ...) end
    for _, fn in ipairs(frame.hooks[k] or {}) do fn(frame, ...) end
end

--------------------------------------------------------------------------
-- the world: players, clubs, Battle.net
--------------------------------------------------------------------------

local players = {}          -- name -> P
-- Edit Mode: the game's presets (Modern, Classic, Gamepad), and the
-- account's saved layouts and the one each character has on - the game
-- servers', the same on every computer: {layoutName =, layoutType = 1
-- (account) or 2 (a character's own: owner =)}, active[guid] = index
local EM_PRESETS = {{layoutName = "Modern", layoutIndex = 0}, {layoutName = "Classic", layoutIndex = 1},
                    {layoutName = "Gamepad", layoutIndex = 2}}
local editModeServer = {layouts = {}, active = {}}
local clubs = {}            -- clubId -> {type=, members = {name...}, guild=}
local ENUM = {
    ClubMemberPresence = {Unknown = 0, Online = 1, OnlineMobile = 2, Offline = 3, Away = 4, Busy = 5},
    ClubType = {BattleNet = 0, Character = 1, Guild = 2, Other = 3},
    ChatWhisperTargetStatus = {CanWhisper = 0, CanWhisperGuild = 1, Offline = 2, WrongFaction = 3},
    SendAddonMessageResult = {Success = 0, AddonMessageThrottle = 3, ChannelThrottle = 8, GeneralError = 9,
                              NotInGuild = 10, AddOnMessageLockdown = 11, TargetOffline = 12},
    ChatChannelType = {None = 0, Custom = 1, PrivateParty = 2, PublicParty = 3, Communities = 4},
    AuctionHouseSortOrder = {Price = 0, Name = 1, Level = 2, Bid = 3, Buyout = 4, TimeRemaining = 5},
    CraftingReagentType = {Modifying = 0, Basic = 1, Finishing = 2, Automatic = 3},
}

local function playerByWire(n)
    if not n then return end
    local short = n:gsub("%-.*$", "")
    return players[n] or players[short]
end
local function playerByGUID(g)
    for _, P in pairs(players) do if P.guid == g then return P end end
end
local function playerByGameAccount(id)
    for _, P in pairs(players) do if P.gameAccountID == id then return P end end
end

local function FireEvent(P, event, ...)
    for _, f in ipairs(P.frames) do
        if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
    end
end

-- a pool proxy like Blizzard's: EnumerateActive yields (frame, true)
local function Pool()
    local pool = {active = {}, free = {}}
    function pool:Acquire(make)
        local f = table.remove(self.free) or make()
        f.shown = true
        table.insert(self.active, f)
        return f
    end
    function pool:ReleaseAll()
        for _, f in ipairs(self.active) do f.shown = false; table.insert(self.free, f) end
        self.active = {}
    end
    function pool:EnumerateActive()
        local i = 0
        return function() i = i + 1; local f = self.active[i]; if f then return f, true end end
    end
    return pool
end

local nextGUID = 1
local function makePlayer(name, opts)
    opts = opts or {}
    local P = {name = name, opts = opts, frames = {}, printed = {}, sent = {}, faction = opts.faction or "Alliance",
               online = true, guid = ("Player-1-%08d"):format(nextGUID), gameAccountID = opts.gameAccountID,
               -- (the GUID a Battle.net community lists the member under: the account's)
               accountGUID = ("BNetAccount-0-%012X"):format(0x5000 + nextGUID),
               bnetAccountId = opts.bnetAccountId, bnFriends = {}, voice = {}, selected = nil, locked = false,
               realm = "Forever", gameAccounts = {}}
    nextGUID = nextGUID + 1
    -- game accounts: the Forever client, and with appFocused the Battle.net
    -- app as well, holding the focus (an account's own gameAccountInfo is
    -- the focused one)
    if opts.gameAccountID then
        if opts.appFocused then
            table.insert(P.gameAccounts, {gameAccountID = opts.gameAccountID + 1000, clientProgram = "App", hasFocus = true})
        end
        table.insert(P.gameAccounts, {gameAccountID = opts.gameAccountID, clientProgram = "WoW", wowProjectID = 18,
                                      hasFocus = not opts.appFocused, forever = true, owner = P})
    end
    -- the same character after a /reload: what the game keeps
    local same = opts.same
    if same then
        P.guid, P.accountGUID, P.realm, P.bnName = same.guid, same.accountGUID, same.realm, same.bnName
        P.voice, P.bnFriends, P.guild, P.group = same.voice, same.bnFriends, same.guild, same.group
        P.hideGuid = same.hideGuid
        P.cvars, P.volumes = same.cvars, same.volumes
        P.strictLockdown, P.cvarSecure = same.strictLockdown, same.cvarSecure
        P.cvarReadOnly, P.cvarLocked = same.cvarReadOnly, same.cvarLocked
        -- (the gold finder's world: items, bags, professions, the calendar)
        P.items, P.counts, P.bags, P.trade = same.items, same.counts, same.bags, same.trade
        P.knowsDisenchant, P.timeShift, P.noRealm = same.knowsDisenchant, same.timeShift, same.noRealm
    end
    P.tick = 0
    if opts.strictLockdown then P.strictLockdown = true end
    if opts.cvarSecure then P.cvarSecure = true end
    if opts.cvarReadOnly then P.cvarReadOnly = true end
    if opts.cvarLocked then P.cvarLocked = true end
    players[name] = P
    local env = {}
    P.env = env
    for _, k in ipairs({"string", "table", "math", "pairs", "ipairs", "type", "tostring", "tonumber",
                        "select", "unpack", "error", "pcall", "xpcall", "setmetatable", "next", "rawget"}) do
        env[k] = _G[k]
    end
    env._G = env
    env.print = function(...)
        local t = {}
        for i = 1, select("#", ...) do t[#t + 1] = tostring(select(i, ...)) end
        table.insert(P.printed, table.concat(t, " "))
    end
    env.Enum = ENUM
    -- (the game's debugstack: where an error was raised, a line a call)
    env.debugstack = function(start) return debug.traceback("", (start or 1) + 1) end
    env.GetBuildInfo = function() return "12.0.5", "64000", "Nov 1 2026", 16001 end
    env.GetTime = function() return clock end
    -- (P.timeShift: the calendar moved on without the timers running - a
    -- day roll, the 15-minute wait, a month-old record)
    env.time = function() return math.floor(clock) + (P.timeShift or 0) end
    -- /reload goes through ReloadUI, which calls C_UI.Reload (InterfaceUtil.lua)
    env.C_UI = {Reload = function()
        P.reloadAsked = true
        if P.editModeLog then table.insert(P.editModeLog, "reload") end
    end}
    env.ReloadUI = function() env.C_UI.Reload() end
    env.UnitGUID = function(u) if u == "player" then return P.guid end end
    env.UnitName = function(u)
        if u == "player" then return P.name end
        if u == "npc" then return P.npcName end
    end
    env.BNET_CLIENT_WOW = "WoW"
    env.WOW_PROJECT_ID = 18 -- WOW_PROJECT_CAMELOT
    env.PLAYER_FACTION_GROUP = {[0] = "Horde", [1] = "Alliance", Horde = 0, Alliance = 1}
    env.UnitFactionGroup = function(u)
        if u == "player" then return P.faction end
        if u == "npc" then return P.npcFaction end
    end
    -- (P.noRealm: no name - true for none at all, "" for WoW Forever's empty one)
    env.GetRealmName = function()
        if P.noRealm == "" then return "" end
        if not P.noRealm then return P.realm end
    end
    env.GetNormalizedRealmName = env.GetRealmName
    env.RegionalUniqueNamesEnabled = function() return true end
    env.C_AccountInfo = {
        IsGUIDRelatedToLocalAccount = function(g) return g == P.guid or g == P.accountGUID end,
        IsGUIDBattleNetAccountType = function(g) return type(g) == "string" and g:find("^BNetAccount%-") ~= nil end,
        -- (the account id behind a Battle.net account GUID; 0 when unknown)
        GetIDFromBattleNetAccountGUID = function(g)
            for _, R in pairs(players) do if R.accountGUID == g then return R.bnetAccountId or 0 end end
            return 0
        end,
    }
    env.IsInGuild = function() return P.guild ~= nil end
    env.IsInGroup = function(category) if category then return false end return P.group ~= nil end
    env.IsInRaid = function() return false end
    env.LE_PARTY_CATEGORY_INSTANCE = 2
    env.issecretvalue = function(v) return type(v) == "table" and v.__secret == true end
    env.hooksecurefunc = function(a, b, c)
        local tbl, key, fn = a, b, c
        if type(a) == "string" then tbl, key, fn = env, a, b end
        local orig = tbl[key]
        tbl[key] = function(...)
            local r = {orig(...)}
            fn(...)
            return unpack(r)
        end
    end
    env.C_Timer = {
        -- (P.tick: the timer callbacks run for this player so far - a test
        -- can see work spread over ticks)
        After = function(d, fn) schedule(d, function() P.tick = P.tick + 1; fn() end, nil, P) end,
        NewTicker = function(d, fn)
            local t = schedule(d, fn, d, P)
            return {Cancel = function() t.cancelled = true end}
        end,
    }
    env.CreateFrame = function(kind, fname, parent, template)
        local f = Widget(kind, fname, parent)
        f.template = template
        if template == "PanelTabButtonTemplate" then
            -- (the parts the game's template has, and its parentArray: it
            -- files the tab into its parent's Tabs list)
            for _, k in ipairs({"LeftActive", "MiddleActive", "RightActive", "Left", "Middle", "Right"}) do
                f[k] = Widget("Texture", nil, f)
            end
            f.Text = Widget("FontString", nil, f)
            function f.Text:GetStringWidth() return #(f.text or "") * 6 end
            if type(parent) == "table" then
                local list = rawget(parent, "Tabs")
                if type(list) ~= "table" then list = {}; rawset(parent, "Tabs", list) end
                table.insert(list, f)
            end
        end
        if kind == "Slider" then
            -- (as the game's: a value outside a new range is moved into it,
            -- and every change of value runs OnValueChanged)
            f.value, f.min, f.max = 0, 0, 0
            local function Set(self, v)
                v = math.max(self.min, math.min(self.max, v))
                if v ~= self.value then
                    self.value = v
                    RunScript(self, "OnValueChanged", v)
                end
            end
            function f:GetValue() return self.value end
            function f:SetValue(v) Set(self, v) end
            function f:SetMinMaxValues(lo, hi)
                self.min, self.max = lo, hi
                Set(self, self.value)
            end
        end
        if template == "WowScrollBoxList" then
            function f:SetDataProvider(dp)
                self.rows = {}
                for _, item in ipairs(dp.items) do
                    local row = Widget("Button", nil, self)
                    table.insert(P.frames, row)
                    self.view.init(row, item)
                    table.insert(self.rows, row)
                end
            end
            function f:EnumerateFrames()
                local i = 0
                return function() i = i + 1; local r = self.rows and self.rows[i]; if r then return i, r end end
            end
        end
        -- (P.badEvent: an event this client doesn't know - registering it throws)
        local register = f.RegisterEvent
        function f:RegisterEvent(e)
            if P.badEvent == e then error("Frame:RegisterEvent(): Attempt to register unknown event \"" .. e .. "\"") end
            register(self, e)
        end
        table.insert(P.frames, f)
        if fname then env[fname] = f end
        return f
    end
    env.UIParent = Widget("Frame", "UIParent")
    env.SlashCmdList = {}
    env.C_AddOns = {
        GetAddOnMetadata = function(_, k) if k == "Version" then return "1.0.0" end end,
        IsAddOnLoaded = function(n) return P.loadedAddOns[n] or false end,
        -- (P.addonOff: switched off in the add-on list for the next load)
        GetAddOnEnableState = function(n, character)
            if character ~= P.guid then return 0 end
            return P.addonOff and 0 or 2
        end,
    }
    P.loadedAddOns = {Blizzard_Channels = true}
    env.Settings = {
        RegisterCanvasLayoutCategory = function(panel, title) P.optionsPanel = panel; return {ID = 77, GetID = function() return 77 end} end,
        RegisterAddOnCategory = function() end,
        OpenToCategory = function(id) P.openedCategory = id end,
    }

    -- chat / addon messages
    env.C_ChatInfo = {
        RegisterAddonMessagePrefix = function(p) P.prefix = p; return true end,
        InChatMessagingLockdown = function() return P.locked end,
        SendAddonMessage = function(prefix, msg, chatType, target)
            table.insert(P.sent, {kind = chatType, msg = msg, to = target})
            if chatType == "WHISPER" then
                local R = playerByWire(target)
                if R and R.online and R.prefix == prefix then
                    schedule(0.05, function() FireEvent(R, "CHAT_MSG_ADDON", prefix, msg, "WHISPER", P.name .. "-" .. P.realm) end)
                end
            elseif chatType == "GUILD" then
                if not P.guild then return ENUM.SendAddonMessageResult.NotInGuild end
                for _, R in pairs(players) do
                    if R.guild and R.guild == P.guild and R.online and R.prefix == prefix then
                        schedule(0.05, function() FireEvent(R, "CHAT_MSG_ADDON", prefix, msg, "GUILD", P.name .. "-" .. P.realm) end)
                    end
                end
            elseif chatType == "PARTY" or chatType == "RAID" then
                for _, R in pairs(players) do
                    if R.group and R.group == P.group and R.online and R.prefix == prefix then
                        schedule(0.05, function() FireEvent(R, "CHAT_MSG_ADDON", prefix, msg, chatType, P.name .. "-" .. P.realm) end)
                    end
                end
            end
            return ENUM.SendAddonMessageResult.Success
        end,
        IsAddonMessagePrefixRegistered = function(p) return P.prefix == p end,
        -- checkMode: nil answers after 0.05 s, "silent" never, "sync" inside the call
        RequestCanLocalWhisperTarget = function(guid)
            P.whisperChecks = (P.whisperChecks or 0) + 1
            if P.checkMode == "silent" then return end
            local R = playerByGUID(guid)
            local status = ENUM.ChatWhisperTargetStatus.Offline
            -- (cantWhisper: the club lists them online, the game says offline)
            if R and R.online and not R.cantWhisper then
                status = R.faction == P.faction and ENUM.ChatWhisperTargetStatus.CanWhisper or ENUM.ChatWhisperTargetStatus.WrongFaction
            end
            if P.checkMode == "sync" then
                FireEvent(P, "CAN_LOCAL_WHISPER_TARGET_RESPONSE", guid, status)
                return
            end
            schedule(0.05, function() FireEvent(P, "CAN_LOCAL_WHISPER_TARGET_RESPONSE", guid, status) end)
        end,
    }
    local function Friends()
        local names = {}
        for n in pairs(P.bnFriends) do if players[n] then names[#names + 1] = n end end
        table.sort(names)
        return names
    end
    -- (a game account's client: its owner, a second Forever client of the
    -- same Battle.net account included; hideGuid: the game gives no
    -- character GUID for it)
    local function GameAccountInfo(R, g)
        local C = g.owner and (players[g.owner.name] or g.owner) or R
        return {gameAccountID = g.gameAccountID, clientProgram = g.clientProgram, wowProjectID = g.wowProjectID,
                isOnline = C.online, hasFocus = g.hasFocus,
                playerGuid = g.forever and not C.hideGuid and C.guid or nil,
                characterName = g.forever and C.name or nil}
    end
    local function AccountInfo(R)
        local focused = {gameAccountID = 0, clientProgram = "", isOnline = false, hasFocus = false}
        for _, g in ipairs(R.gameAccounts) do if g.hasFocus then focused = GameAccountInfo(R, g) end end
        return {bnetAccountID = R.bnetAccountId, isFriend = true, gameAccountInfo = focused,
                accountName = R.bnName or R.name, battleTag = R.name .. "#1234"}
    end
    env.BNGetFriendIndex = function(bnetAccountId)
        for i, n in ipairs(Friends()) do if players[n].bnetAccountId == bnetAccountId then return i end end
    end
    env.C_BattleNet = {
        SendGameData = function(gameAccountID, prefix, data)
            table.insert(P.sent, {kind = "BN", msg = data, to = gameAccountID})
            if P.bnResult then return P.bnResult end
            local R = playerByGameAccount(gameAccountID)
            if R and R.online and R.prefix == prefix then
                schedule(0.05, function() FireEvent(R, "BN_CHAT_MSG_ADDON", prefix, data, "WHISPER", P.gameAccountID) end)
            end
            return ENUM.SendAddonMessageResult.Success
        end,
        -- (friends only: a stranger's account is no use to an add-on)
        GetAccountInfoByID = function(bnetAccountId)
            for _, n in ipairs(Friends()) do
                if players[n].bnetAccountId == bnetAccountId then return AccountInfo(players[n]) end
            end
        end,
        GetFriendNumGameAccounts = function(i)
            local n = Friends()[i]
            return n and #players[n].gameAccounts or 0
        end,
        GetFriendGameAccountInfo = function(i, j)
            local n = Friends()[i]
            local R = n and players[n]
            local g = R and R.gameAccounts[j]
            return g and GameAccountInfo(R, g) or nil
        end,
        -- (noGameInfo: the game no longer gives the account's info - gone offline)
        GetGameAccountInfoByID = function(id)
            for _, n in ipairs(Friends()) do
                for _, g in ipairs(players[n].gameAccounts) do
                    if g.gameAccountID == id and not players[n].noGameInfo then return GameAccountInfo(players[n], g) end
                end
            end
        end,
        GetGameAccountInfoByGUID = function(guid)
            for _, n in ipairs(Friends()) do
                local R = players[n]
                if R.guid == guid and not R.hideGuid then
                    for _, g in ipairs(R.gameAccounts) do if g.forever then return GameAccountInfo(R, g) end end
                end
            end
        end,
        GetAccountInfoByGUID = function(guid)
            for _, n in ipairs(Friends()) do
                if players[n].guid == guid and not players[n].hideGuid then return AccountInfo(players[n]) end
            end
        end,
    }
    env.GetPlayerInfoByGUID = function(g)
        local R = playerByGUID(g)
        if R then return "Warrior", "WARRIOR", "Human", "Human", 2, R.name, R.realm end
    end

    -- communities. A Battle.net community's member is an account: the club
    -- gives its Battle.net account GUID (none at all with noGuids) and its
    -- Battle.net name, as ChannelRoster.lua's rows then carry
    local function MemberInfo(c, memberId, R)
        local bn = c.type == ENUM.ClubType.BattleNet
        local guid = R.guid
        if bn then guid = (not c.noGuids) and R.accountGUID or nil end
        -- (appearOffline: Battle.net's "Appear Offline", the member shows offline while still playing)
        return {isSelf = R == P, memberId = memberId,
                presence = R.online and not R.appearOffline and ENUM.ClubMemberPresence.Online or ENUM.ClubMemberPresence.Offline,
                -- (noAccountIds: the community gives no Battle.net account id - nilable)
                guid = guid, bnetAccountId = (not c.noAccountIds) and R.bnetAccountId or nil, clubType = c.type,
                name = bn and (R.bnName or R.name) or R.name, faction = R.faction == "Horde" and 0 or 1}
    end
    -- (clubsNotReady: this client's club data not loaded yet. Reads made in
    -- the chat lockdown are counted in lockedClubReads; with strictLockdown
    -- they come back secret, as the game's do: SecretInChatMessagingLockdown)
    local function ClubRead()
        if P.locked then P.lockedClubReads = (P.lockedClubReads or 0) + 1 end
        return P.locked and P.strictLockdown
    end
    local function IsMember(c)
        for _, n in ipairs(c.members) do
            local R = players[n]
            if n == P.name or (c.type == ENUM.ClubType.BattleNet and R and R.bnetAccountId and R.bnetAccountId == P.bnetAccountId) then
                return true
            end
        end
        return false
    end
    env.C_Club = {
        GetClubInfo = function(id)
            if ClubRead() then return {__secret = true} end
            local c = clubs[id]
            if c and not P.clubsNotReady then return {clubId = id, clubType = c.type} end
        end,
        GetSubscribedClubs = function()
            P.clubListReads = (P.clubListReads or 0) + 1
            if ClubRead() then return {__secret = true} end
            local out = {}
            if P.clubsNotReady then return out end
            local ids = {}
            for id, c in pairs(clubs) do if IsMember(c) then ids[#ids + 1] = id end end
            table.sort(ids)
            for _, id in ipairs(ids) do out[#out + 1] = {clubId = id, clubType = clubs[id].type} end
            return out
        end,
        GetClubMembers = function(id)
            P.clubMemberReads = (P.clubMemberReads or 0) + 1
            P.clubReadsBy = P.clubReadsBy or {}
            P.clubReadsBy[id] = (P.clubReadsBy[id] or 0) + 1
            if ClubRead() then return {__secret = true} end
            local c = clubs[id]; if not c or c.notReady then return {} end
            local out = {}
            for i in ipairs(c.members) do out[i] = i end
            return out
        end,
        GetMemberInfo = function(id, memberId)
            if ClubRead() then return nil end
            local c = clubs[id]; local n = c and c.members[memberId]; local R = n and players[n]
            if not R then return nil end
            return MemberInfo(c, memberId, R)
        end,
        -- (in a Battle.net community the member is the account: a second
        -- client of it is the same member)
        GetMemberInfoForSelf = function(id)
            local c = clubs[id]
            if not c or P.clubsNotReady then return nil end
            for i, n in ipairs(c.members) do
                local R = players[n]
                if n == P.name or (c.type == ENUM.ClubType.BattleNet and R and R.bnetAccountId and
                                   R.bnetAccountId == P.bnetAccountId) then
                    return MemberInfo(c, i, P)
                end
            end
        end,
    }

    -- voice: P.voice[channelID] = {clubId=, streamId=, isActive=, members = {guid -> isActive},
    -- channelType= (a community's when not given; party voice: PrivateParty)}
    -- (a member's id is the GUID the channel names them by; the volume the
    -- game holds for a person, across channels, is P.volumes[name], nil
    -- being its default of 100. A secret GUID - {__secret = true, real =} -
    -- still names its person to the game.)
    local function Person(guid)
        if type(guid) == "table" and guid.__secret then guid = guid.real end
        if type(guid) ~= "string" then return end
        for _, R in pairs(players) do if R.guid == guid or R.accountGUID == guid then return R end end
    end
    P.volumes = P.volumes or {}
    P.volumeSets = {}
    env.PlayerLocation = {CreateFromGUID = function(_, guid)
        return {guid = guid, GetGUID = function(l) return l.guid end, IsGUID = function(l) return l.guid ~= nil end,
                IsVoiceID = function() return false end}
    end}
    env.C_VoiceChat = {
        GetChannel = function(id)
            local v = P.voice[id]
            if v then
                local members = {}
                for m, active in pairs(v.members) do members[#members + 1] = {memberID = m, isActive = active} end
                table.sort(members, function(a, b) return a.memberID < b.memberID end)
                return {channelID = id, channelType = v.channelType or ENUM.ChatChannelType.Communities, clubId = v.clubId,
                        streamId = v.streamId, isActive = v.isActive, members = members}
            end
        end,
        GetMemberGUID = function(memberID, channelID)
            local v = P.voice[channelID]
            if v and v.members[memberID] ~= nil then return memberID end
        end,
        GetMemberVolume = function(loc)
            local R = Person(loc and loc.guid)
            if R then return P.volumes[R.name] or 100 end
        end,
        SetMemberVolume = function(loc, volume)
            local R = Person(loc and loc.guid)
            if R then
                P.volumes[R.name] = volume
                table.insert(P.volumeSets, {who = R.name, volume = volume, at = clock})
            end
        end,
        GetChannelForCommunityStream = function(clubId, streamId)
            for id, v in pairs(P.voice) do
                if v.clubId == clubId and v.streamId == streamId then
                    return {channelID = id, channelType = ENUM.ChatChannelType.Communities, clubId = clubId,
                            streamId = streamId, isActive = v.isActive}
                end
            end
        end,
        -- (and as the game's roster does, a Battle.net account GUID finds the
        -- member the channel names by that account's character)
        GetMemberID = function(channelID, guid)
            local v = P.voice[channelID]
            if not v then return end
            if v.members[guid] ~= nil then return guid end
            for m in pairs(v.members) do
                local R = Person(m)
                if R and R.accountGUID == guid then return m end
            end
        end,
        GetMemberInfo = function(memberID, channelID)
            local v = P.voice[channelID]
            if v and v.members[memberID] ~= nil then return {memberID = memberID, isActive = v.members[memberID]} end
        end,
        IsMemberLocalPlayer = function(memberID) return memberID == P.guid end,
        GetActiveChannelID = function()
            if P.voiceUnreadable then return nil end
            for id, v in pairs(P.voice) do if v.isActive then return id end end
        end,
    }

    -- Chat Channels window: ChannelFrame with its list and roster
    local channelFrame = Widget("Frame", "ChannelFrame")
    channelFrame.shown = false
    local list = Widget("ScrollFrame")
    function list:GetSelectedChannelButton() return P.selected end
    function channelFrame:GetList() return list end
    function channelFrame:OnUserSelectedChannel() end
    local roster = Widget("Frame")
    local box = Widget("Frame")
    box.rows = {}
    box.initCallbacks = {}
    function box:EnumerateFrames()
        local i = 0
        return function() i = i + 1; local r = box.rows[i]; if r then return i, r end end
    end
    function box:RegisterCallback(event, fn, owner) table.insert(box.initCallbacks, {fn = fn, owner = owner}) end
    roster.ScrollBox = box
    channelFrame.ChannelRoster = roster
    channelFrame.ChannelList = list
    env.ChannelFrame = channelFrame
    env.ScrollUtil = {
        AddInitializedFrameCallback = function(sb, cb, owner) sb:RegisterCallback("OnInitializedFrame", cb, owner) end,
    }
    env.ScrollBoxListMixin = {Event = {OnInitializedFrame = "OnInitializedFrame"}}
    -- a roster row for member R, as Blizzard's ChannelRosterButtonMixin
    P.AddRosterRow = function(R)
        local row = Widget("Button")
        row.Name = Widget("FontString", nil, row)
        row.memberName = R.name
        -- (as ChannelRoster.lua builds a row from the selected club's member
        -- info: SetMemberID(memberInfo.memberId), the location from memberInfo.guid)
        local function Member()
            local c = P.selected and clubs[P.selected.clubId]
            if not c then return nil end
            for i, n in ipairs(c.members) do if n == R.name then return i, c end end
        end
        local function RowGUID()
            local _, c = Member()
            if c and c.type == ENUM.ClubType.BattleNet then
                if c.noGuids then return nil end
                return R.accountGUID
            end
            return R.guid
        end
        row.playerLocation = {GetGUID = function() return RowGUID() end}
        function row:GetMemberPlayerLocation() if RowGUID() then return self.playerLocation end end
        function row:GetMemberID() return (Member()) end
        function row:IsLocalPlayer() return R == P end
        function row:IsChannelActive() return P.selectedVoiceActive and true or false end
        -- (SetIsConnected(presence ~= Offline) as the row is drawn)
        function row:IsConnected()
            local C = players[R.name] or R
            return C.online and not C.appearOffline and true or false
        end
        -- the member's name as the club gives it (a Battle.net name in a
        -- Battle.net community): what the row shows, and must never be printed
        function row:GetMemberName()
            local _, c = Member()
            return c and c.type == ENUM.ClubType.BattleNet and (R.bnName or R.name) or R.name
        end
        function row:Update()
            self.Name:SetText(self:GetMemberName())
            self.Name:SetWidth(140) -- Blizzard's UpdateNameSize with no voice buttons
        end
        table.insert(box.rows, row)
        for _, cb in ipairs(box.initCallbacks) do cb.fn(cb.owner, row) end
        return row
    end
    P.Row = function(R)
        for _, row in ipairs(box.rows) do if row.memberName == R.name then return row end end
    end
    P.RowMic = function(R)
        local row = P.Row(R)
        if not row then return false end
        for _, t in ipairs(row.regions) do
            if t.atlas == "voicechat-icon-mic" and t.shown then return true end
        end
        return false
    end
    P.OpenChannels = function(clubId, streamId)
        P.selected = {clubId = clubId, streamId = streamId}
        channelFrame.shown = true
        RunScript(channelFrame, "OnShow")
        for _, row in ipairs(box.rows) do row:Update() end -- the roster is rebuilt on show
    end
    P.CloseChannels = function()
        channelFrame.shown = false
        RunScript(channelFrame, "OnHide")
    end
    P.SelectStream = function(clubId, streamId)
        P.selected = {clubId = clubId, streamId = streamId}
        channelFrame:OnUserSelectedChannel()
        for _, row in ipairs(box.rows) do row:Update() end
    end
    -- the player joins (activates) or leaves a community stream's voice
    P.JoinVoice = function(channelID, clubId, streamId)
        P.voice[channelID] = {clubId = clubId, streamId = streamId, isActive = true, members = {}}
        FireEvent(P, "VOICE_CHAT_CHANNEL_ACTIVATED", channelID)
    end
    P.LeaveVoice = function(channelID)
        if P.voice[channelID] then P.voice[channelID].isActive = false end
        FireEvent(P, "VOICE_CHAT_CHANNEL_DEACTIVATED", channelID)
    end
    -- another stream's headset: the new channel's event comes first
    P.SwitchVoice = function(oldID, newID, clubId, streamId)
        if P.voice[oldID] then P.voice[oldID].isActive = false end
        P.voice[newID] = {clubId = clubId, streamId = streamId, isActive = true, members = {}}
        FireEvent(P, "VOICE_CHAT_CHANNEL_ACTIVATED", newID)
        FireEvent(P, "VOICE_CHAT_CHANNEL_DEACTIVATED", oldID)
    end

    -- the game's settings (CVars): kept across a /reload; a change fires
    -- CVAR_UPDATE inside the call, as the game's does. cvars = {} for a
    -- client without showPartyPets.
    P.cvars = P.cvars or opts.cvars or {showPartyPets = "0"}
    P.cvarSets = {}
    env.C_CVar = {
        GetCVar = function(n) return P.cvars[n] end,
        -- value, default, server account, server character, locked from the
        -- user (cvarLocked: an add-on may still set it), secure (only the
        -- game's own code may set it), read-only
        GetCVarInfo = function(n)
            if P.cvars[n] == nil then return end
            return P.cvars[n], "0", false, false, P.cvarLocked or false, P.cvarSecure or false, P.cvarReadOnly or false
        end,
        SetCVar = function(n, v)
            -- (cvarRefused: the game won't let an add-on set it. A refusal
            -- returns nothing at all, not false: CVarDocumentation.lua's
            -- preconditions all have FailureMode "ReturnNothing")
            if P.cvars[n] == nil or P.cvarRefused or P.cvarSecure or P.cvarReadOnly then return end
            P.cvars[n] = tostring(v)
            table.insert(P.cvarSets, {name = n, value = P.cvars[n], inCombat = P.inCombat or false})
            FireEvent(P, "CVAR_UPDATE", n, P.cvars[n])
            return true
        end,
    }
    -- Edit Mode. EditModeManagerFrame lists the presets, then the saved
    -- layouts (a character's own only for it), by the index
    -- C_EditMode.SetActiveLayout takes, and applies a layout inside that
    -- call: it fires EDIT_MODE_LAYOUTS_UPDATED from within it (as
    -- EditModeManager.lua's SelectLayout expects; editModeAsync: a moment
    -- later). P.editModeLog: each switch, the player's (P.Pick, Edit Mode's
    -- menu) or the add-on's, each layout applied, each reload asked for.
    local function SavedLayouts()
        local out = {}
        for _, l in ipairs(editModeServer.layouts) do
            if l.layoutType ~= 2 or l.owner == P.guid then
                out[#out + 1] = {layoutName = l.layoutName, layoutType = l.layoutType, systems = {}}
            end
        end
        return out
    end
    P.editModeLog = {}
    env.C_EditMode = {
        GetLayouts = function()
            return {layouts = SavedLayouts(), activeLayout = editModeServer.active[P.guid] or 1}
        end,
        SetActiveLayout = function(i)
            if P.editModeRefuses then return end
            if type(i) ~= "number" or i < 1 or i > #EM_PRESETS + #SavedLayouts() then error("bad layout index") end
            editModeServer.active[P.guid] = i
            table.insert(P.editModeLog, (P.picking and "set:player:" or "set:addon:") .. i)
            local function Applied() FireEvent(P, "EDIT_MODE_LAYOUTS_UPDATED", env.C_EditMode.GetLayouts(), false) end
            if P.editModeAsync then schedule(0.1, Applied, nil, P) else Applied() end
        end,
    }
    do
        local em = Widget("Frame", "EditModeManagerFrame")
        em.shown = false -- (shown while Edit Mode is open)
        em:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
        em:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
        em:SetScript("OnEvent", function(self, event, info)
            -- (a spec change: the game reads its layouts again, EditModeManager.lua)
            if event == "PLAYER_SPECIALIZATION_CHANGED" then info = env.C_EditMode.GetLayouts() end
            local layouts = {}
            for _, l in ipairs(EM_PRESETS) do
                layouts[#layouts + 1] = {layoutName = l.layoutName, layoutType = 0, layoutIndex = l.layoutIndex, systems = {}}
            end
            for _, l in ipairs(info.layouts) do layouts[#layouts + 1] = l end
            self.layoutInfo = {layouts = layouts, activeLayout = info.activeLayout}
            table.insert(P.editModeLog, "apply:" .. info.activeLayout)
        end)
        function em:SelectLayout(i)
            if i ~= self.layoutInfo.activeLayout then env.C_EditMode.SetActiveLayout(i) end
        end
        table.insert(P.frames, em)
        env.EditModeManagerFrame = em
    end
    -- the game's own load of the layouts as the UI starts, and the player
    -- picking one in Edit Mode's menu
    P.EditModeLoad = function() FireEvent(P, "EDIT_MODE_LAYOUTS_UPDATED", env.C_EditMode.GetLayouts(), true) end
    P.Pick = function(i)
        P.picking = true
        env.EditModeManagerFrame:SelectLayout(i)
        P.picking = false
    end
    -- a new layout made in Edit Mode (New Layout, Copy, Import): the game
    -- turns it on through C_EditMode.OnLayoutAdded, not SelectLayout
    P.NewLayout = function(name)
        table.insert(editModeServer.layouts, {layoutName = name, layoutType = 1})
        editModeServer.active[P.guid] = #EM_PRESETS + #SavedLayouts()
        table.insert(P.editModeLog, "new:" .. name)
        FireEvent(P, "EDIT_MODE_LAYOUTS_UPDATED", env.C_EditMode.GetLayouts(), false)
    end
    env.HUD_EDIT_MODE_PRESET_LAYOUT = "%s (Preset)"

    -- the game's volume slider on someone's menu, built when the menu first
    -- opens: it takes C_VoiceChat.SetMemberVolume as it is then, and calls
    -- it with the menu's location, made from the row's GUID when the menu
    -- opens (one menu stays open while the same row's slider moves; another
    -- row's, or P.CloseMenu(), opens a new one)
    P.Slide = function(guid, volume)
        P.slider = P.slider or env.C_VoiceChat.SetMemberVolume
        if not P.menuLoc or P.menuFor ~= guid then
            P.menuLoc, P.menuFor = env.PlayerLocation:CreateFromGUID(guid), guid
        end
        P.slider(P.menuLoc, volume)
    end
    P.CloseMenu = function() P.menuLoc, P.menuFor = nil, nil end

    -- misc game API
    env.InCombatLockdown = function() return P.inCombat or false end
    env.UnitOnTaxi = function() return P.onTaxi or false end
    env.PlaySound = function() end
    env.SOUNDKIT = {IG_MAINMENU_OPTION_CHECKBOX_ON = 1, IG_MAINMENU_OPTION_CHECKBOX_OFF = 2}
    env.UIErrorsFrame = {AddMessage = function(_, msg) table.insert(P.errorsShown, msg) end}
    P.errorsShown = {}
    env.GameTooltip = Widget("GameTooltip")
    env.OBJECTIVES_WATCH_TOO_MANY = "You are already tracking the maximum number of quests."
    env.Constants = {QuestWatchConsts = {MAX_QUEST_WATCHES = 25}}
    env.QuestUtil = {CanRemoveQuestWatch = function() return true end}
    env.C_SuperTrack = {GetSuperTrackedQuestID = function() return P.superTracked or 0 end}

    -- the quest log: P.log = { {header="Duskwood"}, {id=, title=}, ... }
    P.log, P.watched = {}, {}
    local function entries()
        local out = {}
        for i, e in ipairs(P.log) do
            if e.header then
                out[i] = {title = e.header, isHeader = true, questLogIndex = i, isOnMap = e.onMap or false}
            else
                out[i] = {title = e.title or ("Quest " .. e.id), questID = e.id, questLogIndex = i, isHidden = e.hidden,
                          isTask = e.task, isBounty = false}
            end
        end
        return out
    end
    local function watchCount() local n = 0; for _ in pairs(P.watched) do n = n + 1 end; return n end
    P.WatchCount = watchCount
    P.questListRebuilds = 0
    env.C_QuestLog = {
        GetNumQuestLogEntries = function()
            local n = 0
            for _, e in ipairs(P.log) do if not e.header then n = n + 1 end end
            return #P.log, n
        end,
        GetInfo = function(i) return entries()[i] end,
        GetQuestWatchType = function(id) if P.watched[id] then return 1 end end,
        GetNumQuestWatches = function() return watchCount() end,
        IsQuestDisabledForSession = function() return false end,
        AddQuestWatch = function(id)
            if P.watched[id] then return false end
            P.watched[id] = true
            -- Blizzard's QUEST_WATCH_LIST_CHANGED handler rebuilds the list
            if P.questMapShown then env.QuestLogQuests_Update() end
            return true
        end,
        RemoveQuestWatch = function(id)
            if not P.watched[id] then return false end
            P.watched[id] = nil
            if P.questMapShown then env.QuestLogQuests_Update() end
            return true
        end,
    }
    local scroll = Widget("ScrollFrame", "QuestScrollFrame")
    scroll.headerFramePool = Pool()
    scroll.SettingsDropdown = Widget("DropdownButton")
    env.QuestScrollFrame = scroll
    env.QuestLogCount = Widget("Frame", "QuestLogCount", scroll)
    -- Blizzard rebuilds the list: one header frame per zone header
    env.QuestLogQuests_Update = function()
        P.questListRebuilds = P.questListRebuilds + 1
        scroll.headerFramePool:ReleaseAll()
        for i, e in ipairs(P.log) do
            if e.header then
                local h = scroll.headerFramePool:Acquire(function()
                    local f = Widget("Button", nil, scroll)
                    f.CollapseButton = Widget("Button", nil, f)
                    table.insert(P.frames, f)
                    return f
                end)
                h.questLogIndex = i
                h.text = e.header
            end
        end
    end
    P.OpenQuestMap = function() P.questMapShown = true; env.QuestLogQuests_Update() end
    P.HeaderBox = function(title)
        for h in scroll.headerFramePool:EnumerateActive() do
            if h.text == title then
                for _, f in ipairs(P.frames) do
                    if f.parent == h and f.kind == "Button" and f.scripts.OnClick then return f end
                end
            end
        end
    end
    P.MasterBox = function()
        for _, f in ipairs(P.frames) do
            if f.parent == scroll and f.kind == "Button" and f.scripts.OnClick and f.point and f.point[2] == env.QuestLogCount then return f end
        end
    end
    P.BoxState = function(box)
        if not box or not box.shown then return "hidden" end
        if not box.tick.shown then return "none" end
        return box.tick.alpha == 1 and "all" or "some"
    end
    env.Menu = {ModifyMenu = function(tag, fn) P.menus[tag] = fn end}
    P.menus = {}
    P.GearMenu = function()
        local items = {}
        local root = {CreateDivider = function() end,
                      CreateButton = function(_, text, fn) items[text] = fn end}
        P.menus["MENU_QUEST_MAP_FRAME_SETTINGS"](scroll.SettingsDropdown, root)
        return items
    end

    -- zones and maps
    P.zone = "Elwynn Forest"
    env.GetRealZoneText = function() return P.zone end
    env.GetZoneText = function() return P.zone end
    env.C_Map = {
        GetBestMapForUnit = function() return P.mapID end,
        GetMapInfo = function(id) return P.maps and P.maps[id] end,
    }

    -- Looking For Group (load-on-demand)
    env.RAID_CLASS_COLORS = {PRIEST = {r = 1, g = 1, b = 1}, WARRIOR = {r = 0.78, g = 0.61, b = 0.43}}
    env.LFG_LIST_CATEGORY_SOLO_PLAYERS = "Players"
    env.GetGeneralPlaystyleString = function(p) return p == 1 and "Relaxed" or "Focused" end
    P.lfg = {}         -- resultID -> {name=, level=, class=, roles={tank,healer,dps}, members=, self=}
    P.lfgOrder = {}
    env.C_LFGList = {
        GetFilteredSearchResults = function() return #P.lfgOrder, P.lfgOrder end,
        GetSearchResultInfo = function(id)
            local r = P.lfg[id]
            if r then return {searchResultID = id, leaderName = r.name, numMembers = r.members or 1, hasSelf = r.self or false,
                              isDelisted = false, activityIDs = {1}, generalPlaystyle = 1} end
        end,
        GetSearchResultPlayerInfo = function(id)
            local r = P.lfg[id]
            if r then return {name = r.name, level = r.level, classFilename = r.class, lfgRoles = r.roles} end
        end,
        GetActivityInfoTable = function() return {fullName = "Deadmines"} end,
    }
    env.CreateDataProvider = function(t) return {items = t} end
    env.ScrollBoxConstants = {RetainScrollPosition = true}
    env.CreateScrollBoxListLinearView = function()
        local view = {}
        function view:SetElementExtent(h) self.extent = h end
        function view:SetElementInitializer(kind, fn) self.init = fn end
        return view
    end
    env.ScrollUtil.InitScrollBoxListWithScrollBar = function(box, bar, view) box.view = view end
    env.ChatFrameUtil = {SendTell = function(n) P.toldTo = n end}
    env.C_PartyInfo = {InviteUnit = function(n) P.invited = n end}
    P.LoadLFG = function()
        local f = Widget("Frame", "LFGBrowseFrame")
        f.ScrollBox = Widget("Frame", nil, f)
        f.ScrollBar = Widget("EventFrame", nil, f)
        f.SendMessageButton = Widget("Button", nil, f)
        f.GroupInviteButton = Widget("Button", nil, f)
        f.SendMessageButton.alpha, f.GroupInviteButton.alpha = 1, 1
        function f.SendMessageButton:GetAlpha() return self.alpha end
        function f.GroupInviteButton:GetAlpha() return self.alpha end
        f.results = {}
        function f:UpdateResults() end
        env.LFGBrowseFrame = f
        P.loadedAddOns.Blizzard_GroupFinder_VanillaStyle = true
        FireEvent(P, "ADDON_LOADED", "Blizzard_GroupFinder_VanillaStyle")
        return f
    end
    -- Blizzard's refresh: results in, then UpdateResults
    P.LFGResults = function()
        env.LFGBrowseFrame.results = P.lfgOrder
        env.LFGBrowseFrame.searching = false
        env.LFGBrowseFrame:UpdateResults()
    end
    P.OverlayRows = function()
        local out = {}
        for _, fr in ipairs(P.frames) do
            if fr.template == "WowScrollBoxList" and fr.rows then
                for _, row in ipairs(fr.rows) do table.insert(out, row) end
            end
        end
        return out
    end

    ----------------------------------------------------------------------
    -- the gold finder's world: items, bags, professions, merchants, the
    -- auction house. All of it is the test's to set up (P.items, P.bags,
    -- P.trade, P.merchant, P.ah)
    ----------------------------------------------------------------------
    -- items: P.items[id] = {name, quality, ilvl, stack, sell, class, sub,
    -- bind, reagent, loaded = false until the game has been asked for it}
    P.items = P.items or {}
    P.counts = P.counts or {}         -- itemID -> how many the character has (bags and bank)
    P.itemAsks = {}                   -- {tick =, id =} per RequestLoadItemDataByID
    P.itemReads = {}                  -- tick -> GetItemInfo calls
    P.noSuchItem = {}
    local function ItemLoaded(id)
        local it = P.items[id]
        if it then it.loaded = true end
        FireEvent(P, "ITEM_DATA_LOAD_RESULT", id, it ~= nil)
        FireEvent(P, "GET_ITEM_INFO_RECEIVED", id, it ~= nil)
    end
    env.C_Item = {
        GetItemInfo = function(id)
            P.itemReads[P.tick] = (P.itemReads[P.tick] or 0) + 1
            local it = P.items[id]
            if not it or it.loaded == false then return nil end
            return it.name, it.link or ("|cffffffff|Hitem:" .. id .. "::::::::60:::::|h[" .. it.name .. "]|h|r"), it.quality or 1,
                   it.ilvl or 1, 0, "Type", "Subtype", it.stack or 1, "", it.icon or 134400, it.sell or 0, it.class or 15,
                   it.sub or 0, it.bind or 0, 0, nil, it.reagent or false
        end,
        GetItemInfoInstant = function(id)
            local it = P.items[id]
            if not it then return nil end
            return id, "Type", "Subtype", "", it.icon or 134400, it.class or 15, it.sub or 0
        end,
        -- (P.countedBank: whether the last count was asked to take the bank in)
        GetItemCount = function(id, includeBank)
            P.countedBank = includeBank
            return P.counts[id] or 0
        end,
        DoesItemExistByID = function(id) return not P.noSuchItem[id] end,
        -- (P.itemSync: the data is there at once, and the event fires inside the call)
        RequestLoadItemDataByID = function(id)
            table.insert(P.itemAsks, {tick = P.tick, id = id})
            if P.itemSync then ItemLoaded(id) else schedule(0.05, function() ItemLoaded(id) end, nil, P) end
        end,
    }
    -- bags: P.bags[bag] = {n = slots, [slot] = {itemID, stackCount, hyperlink, isBound, hasNoValue, quality}}
    P.bags = P.bags or {}
    env.NUM_TOTAL_EQUIPPED_BAG_SLOTS = 5
    env.C_Container = {
        GetContainerNumSlots = function(bag)
            local b = P.bags[bag]
            if b and b.throw then error("no such bag") end
            return b and b.n or 0
        end,
        GetContainerItemInfo = function(bag, slot) return P.bags[bag] and P.bags[bag][slot] end,
    }
    env.C_SpellBook = {ContainsAnyDisenchantSpell = function() return P.knowsDisenchant or false end}
    -- the profession window: P.trade = {ready, changing, linked, guild, npc,
    -- prof = the profession info, ids = {recipeID...}, recipes[id] =
    -- {info =, sch =, throw =, cooldown =}}
    P.trade = P.trade or {ready = true, ids = {}, recipes = {}, prof = {professionID = 0}}
    P.recipeReads = {}                -- the tick of each GetRecipeInfo call
    env.C_TradeSkillUI = {
        IsTradeSkillReady = function() return P.trade.ready and true or false end,
        IsDataSourceChanging = function() return P.trade.changing or false end,
        IsTradeSkillLinked = function() return P.trade.linked or false end,
        IsTradeSkillGuild = function() return P.trade.guild or false end,
        IsNPCCrafting = function() return P.trade.npc or false end,
        GetChildProfessionInfo = function() return P.trade.prof end,
        GetBaseProfessionInfo = function() return P.trade.prof end,
        GetAllRecipeIDs = function() return P.trade.ids end,
        GetRecipeInfo = function(id)
            table.insert(P.recipeReads, P.tick)
            if P.trade.onRead then P.trade.onRead(id) end
            local r = P.trade.recipes[id]
            if r and r.throw then error("recipe " .. id .. " can't be read") end
            return r and r.info
        end,
        GetRecipeSchematic = function(id) return P.trade.recipes[id] and P.trade.recipes[id].sch end,
        GetRecipeCooldown = function(id) return P.trade.recipes[id] and P.trade.recipes[id].cooldown or nil end,
    }
    -- a merchant: P.merchant = {{id, price, stack, avail (-1 unlimited), ext, purchasable}, ...}
    env.GetMerchantNumItems = function() return P.merchant and #P.merchant or 0 end
    env.GetMerchantItemID = function(i) return P.merchant and P.merchant[i] and P.merchant[i].id end
    env.C_MerchantFrame = {GetItemInfo = function(i)
        local m = P.merchant and P.merchant[i]
        if not m or m.nothing then return nil end
        return {name = "item", price = m.price, stackCount = m.stack or 1, numAvailable = m.avail or -1,
                hasExtendedCost = m.ext or false, isPurchasable = m.purchasable ~= false}
    end}
    -- the auction house. P.ah: open; rows (the full list: {id, count, buyout,
    -- owner, ownerFull, link, lateLink (the link only once linksReady),
    -- throw, secret}); replicate = "never" | "twice" | "throw" | nil;
    -- commodity[id] = true / false (GetItemKeyInfo; nil: it returns nothing);
    -- results[id] = {rows..., full = false for a partial answer};
    -- silent[id] = how many queries for it go unanswered; drop = the next
    -- query is dropped by the throttle; notReady; sends = every query sent
    P.ah = {open = false, rows = {}, commodity = {}, results = {}, silent = {}, sends = {}, browse = {}, owned = {},
            asked = 0, infoReads = {}, numReads = 0, browseReads = 0, sentNotReady = 0}
    local ah = P.ah
    local function Answer(id, kind)
        table.insert(ah.sends, {t = clock, id = id, kind = kind})
        if ah.notReady then ah.sentNotReady = ah.sentNotReady + 1 end
        if not ah.open then return end
        if ah.drop then
            ah.drop = false
            schedule(0.2, function() FireEvent(P, "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED") end, nil, P)
            return
        end
        if (ah.silent[id] or 0) > 0 then
            ah.silent[id] = ah.silent[id] - 1
            return
        end
        schedule(ah.answerDelay or 0.3, function()
            if not ah.open then return end
            if kind == "commodity" then
                FireEvent(P, "COMMODITY_SEARCH_RESULTS_UPDATED", id)
            else
                -- (a key table of the event's own, never the one we sent)
                FireEvent(P, "ITEM_SEARCH_RESULTS_UPDATED", {itemID = id, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0})
            end
        end, nil, P)
    end
    env.C_AuctionHouse = {
        ReplicateItems = function()
            ah.asked = ah.asked + 1
            if ah.replicate == "throw" then error("ReplicateItems is not available") end
            if ah.replicate == "never" then return end
            schedule(ah.replicateDelay or 1, function() FireEvent(P, "REPLICATE_ITEM_LIST_UPDATE") end, nil, P)
            if ah.replicate == "twice" then
                schedule((ah.replicateDelay or 1) + 0.1, function() FireEvent(P, "REPLICATE_ITEM_LIST_UPDATE") end, nil, P)
            end
        end,
        GetNumReplicateItems = function()
            ah.numReads = ah.numReads + 1
            if ah.numThrowAt and ah.numReads >= ah.numThrowAt then error("the list is gone") end
            return #ah.rows
        end,
        GetReplicateItemInfo = function(i)
            ah.infoReads[P.tick] = (ah.infoReads[P.tick] or 0) + 1
            local r = ah.rows[i + 1]
            if not r then return nil end
            if r.throw then error("row " .. i .. " can't be read") end
            local id = r.id
            if r.secret then id = {__secret = true} end
            return "item", 134400, r.count, 1, true, 1, "", 1, 1, r.buyout, 0, nil, nil, r.owner, r.ownerFull, 0, id, true
        end,
        GetReplicateItemLink = function(i)
            local r = ah.rows[i + 1]
            if not r then return nil end
            if r.lateLink then return ah.linksReady and r.lateLink or nil end
            return r.link
        end,
        MakeItemKey = function(id) return {itemID = id, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0} end,
        GetItemKeyInfo = function(key)
            local c = ah.commodity[key.itemID]
            if c == nil then return nil end
            return {itemID = key.itemID, itemName = "item", isCommodity = c}
        end,
        SendSearchQuery = function(key, sorts, separate)
            if ah.sendThrows then error("can't search") end
            ah.lastSorts, ah.lastSeparate = sorts, separate
            Answer(key.itemID, "commodity")
        end,
        SendSellSearchQuery = function(key, sorts, separate)
            ah.lastSellSorts, ah.lastSellSeparate = sorts, separate
            Answer(key.itemID, "item")
        end,
        GetNumCommoditySearchResults = function(id) return ah.results[id] and #ah.results[id] or 0 end,
        GetCommoditySearchResultInfo = function(id, i) return ah.results[id] and ah.results[id][i] end,
        HasFullCommoditySearchResults = function(id) return not (ah.results[id] and ah.results[id].full == false) end,
        GetNumItemSearchResults = function(key) return ah.results[key.itemID] and #ah.results[key.itemID] or 0 end,
        GetItemSearchResultInfo = function(key, i) return ah.results[key.itemID] and ah.results[key.itemID][i] end,
        HasFullItemSearchResults = function(key) return not (ah.results[key.itemID] and ah.results[key.itemID].full == false) end,
        IsThrottledMessageSystemReady = function() return not ah.notReady end,
        GetBrowseResults = function()
            ah.browseReads = ah.browseReads + 1
            return ah.browse
        end,
        GetOwnedAuctions = function() return ah.owned end,
    }
    -- Blizzard_AuctionHouseUI (load-on-demand): the frame and the parts of
    -- it the add-on looks at, each a real table, hidden until shown
    P.LoadAH = function()
        local f = Widget("Frame", "AuctionHouseFrame")
        f.shown = false
        for _, k in ipairs({"SearchBar", "CommoditiesBuyFrame", "ItemBuyFrame", "CommoditiesSellFrame", "ItemSellFrame",
                            "AuctionsFrame", "BuyDialog"}) do
            f[k] = Widget("Frame", nil, f)
            f[k].shown = false
        end
        f.SearchBar.shown = true
        f.SearchBar.SearchBox = Widget("EditBox", nil, f.SearchBar)
        -- the bottom tabs (the tab template's parentArray "Tabs"), 3 px
        -- apart; t.right is where it ends, t.top its top edge
        f.Tabs = {}
        local function Tab(parent, right, top)
            local t = Widget("Button", nil, parent)
            t.right, t.top = right, top
            function t:GetRight() return self.right end
            function t:GetTop() return self.top end
            return t
        end
        for i, k in ipairs({"BuyTab", "SellTab", "AuctionsTab"}) do
            local t = Tab(f, 20 + i * 75, 100)
            f[k], f.Tabs[i] = t, t
        end
        -- another add-on's tab, as Auctionator's are made (LibAHTab): on a
        -- frame of the add-on's own inside the auction house - never in the
        -- auction house's list
        P.AddAHTab = function(right, top)
            P.ahTabRoot = P.ahTabRoot or Widget("Frame", nil, f)
            return Tab(P.ahTabRoot, right, top or 100)
        end
        -- (and a button of Blizzard's that is no bottom tab, far to the right)
        f.AuctionsFrame.BidsTab = Tab(f.AuctionsFrame, 900, 400)
        f.AuctionsFrame.Tabs = {f.AuctionsFrame.BidsTab}
        env.AuctionHouseFrame = f
        P.loadedAddOns.Blizzard_AuctionHouseUI = true
        FireEvent(P, "ADDON_LOADED", "Blizzard_AuctionHouseUI")
        return f
    end
    P.OpenAH = function()
        if not env.AuctionHouseFrame then P.LoadAH() end
        ah.open, env.AuctionHouseFrame.shown = true, true
        FireEvent(P, "AUCTION_HOUSE_SHOW")
    end
    P.CloseAH = function()
        ah.open = false
        if env.AuctionHouseFrame then env.AuctionHouseFrame.shown = false end
        FireEvent(P, "AUCTION_HOUSE_CLOSED")
    end
    -- Auctionator's API (v1): mode "ok" | "error"; prices[id], ages[id]
    -- (days); searches = what MultiSearchExact was asked for
    P.SetAuctionator = function(a)
        P.auctionator = a
        if not a then env.Auctionator = nil return end
        a.prices, a.ages, a.searches, a.calls = a.prices or {}, a.ages or {}, {}, 0
        local function Call(fn)
            return function(caller, arg)
                a.calls = a.calls + 1
                a.caller = caller
                if type(caller) ~= "string" or a.mode == "error" then error("Auctionator: bad call") end
                return fn(arg)
            end
        end
        env.Auctionator = {API = {v1 = {
            GetAuctionPriceByItemID = Call(function(id) return a.prices[id] end),
            GetAuctionAgeByItemID = Call(function(id) return a.ages[id] end),
            MultiSearchExact = Call(function(terms)
                if a.searchError then error("Auctionator: can't search") end
                table.insert(a.searches, terms)
            end),
        }}}
    end

    P.Slash = function(s) env.SlashCmdList["PACESQOL"](s) end
    P.Fire = function(event, ...) FireEvent(P, event, ...) end

    if opts.voiceAtLoad then P.voice[opts.voiceAtLoad.id] = {clubId = opts.voiceAtLoad.club, streamId = opts.voiceAtLoad.stream, isActive = true, members = {}} end
    if opts.beforeLoad then opts.beforeLoad(P, env) end
    local ns = {}
    P.ns = ns
    for _, file in ipairs(P.files or TOC_FILES) do
        local path = ROOT .. "/PacesQualityOfLife/" .. file
        if file == "Voice.lua" and opts.voiceFile then path = ROOT .. "/" .. opts.voiceFile end
        local chunk = assert(loadfile(path))
        setfenv(chunk, env)
        chunk("PacesQualityOfLife", ns)
    end
    if opts.db then env.PacesQoLDB = opts.db end
    FireEvent(P, "PLAYER_LOGIN")
    return P
end

-- every error recorded this session, each time it happened (an error that
-- repeats is one entry of ns.errors, with a count)
local function Errs(P)
    local n = 0
    for _, info in pairs(P.ns.errorInfo or {}) do n = n + info.count end
    return n
end

local function Printed(P, needle)
    for _, l in ipairs(P.printed) do if l:find(needle, 1, true) then return true end end
    return false
end
local function SentCount(P, pred)
    local n = 0
    for _, s in ipairs(P.sent) do if not pred or pred(s) then n = n + 1 end end
    return n
end

-- a /reload: PLAYER_LOGOUT on the old UI (after ReloadUI, as /reload does,
-- unless direct), its timers and frames gone and nothing heard during the
-- loading screen, then the same character's add-on loaded again with its
-- saved settings - the game keeps voice, friends, guild and group
-- (how: "reloadui" the default, as /reload; "cui" C_UI.Reload called
-- directly; "console" no Lua at all. noAddon: switched off for the next
-- load. The hooks are assumed to run before PLAYER_LOGOUT: the old UI can't
-- be torn down while the call is still running.)
local function Reload(P, o)
    o = o or {}
    local how = o.how or (o.direct and "console") or "reloadui"
    if how == "reloadui" then P.env.ReloadUI() elseif how == "cui" then P.env.C_UI.Reload() end
    FireEvent(P, "PLAYER_LOGOUT")
    for _, t in ipairs(timers) do if t.owner == P then t.cancelled = true end end
    P.frames = {}
    advance(1)
    if o.during then o.during(P) end -- (a second into the loading screen)
    advance((o.loading or 5) - 1)
    return makePlayer(P.name, {same = P, gameAccountID = P.opts.gameAccountID, bnetAccountId = P.opts.bnetAccountId,
                               appFocused = P.opts.appFocused, faction = P.faction, voiceFile = P.opts.voiceFile,
                               db = P.env.PacesQoLDB,
                               beforeLoad = o.noAddon and function(N) N.files = {} end or o.beforeLoad})
end

-- a logout to character select: the old UI's PLAYER_LOGOUT, its timers and
-- frames gone (another character of the account may log in next, with the
-- same saved settings)
local function LogOut(P)
    FireEvent(P, "PLAYER_LOGOUT")
    for _, t in ipairs(timers) do if t.owner == P then t.cancelled = true end end
    P.frames = {}
    advance(5)
end

--------------------------------------------------------------------------
-- core: options page, slash command, saved settings
--------------------------------------------------------------------------
do
    local P = makePlayer("Coretest")
    check(P.ns.db and P.ns.db.voice == true and P.ns.db.voiceShare == true and P.ns.db.voicevolume == true,
          "core: every feature on by default")
    check(P.optionsPanel ~= nil, "core: an options page under AddOns")
    P.Slash("")
    check(P.openedCategory == 77, "core: /pqol opens it")
    P.Slash("voice off")
    check(P.ns.db.voice == false and Printed(P, "voice |cFFFF6666off|r"), "core: /pqol voice off")
    P.Slash("voice")
    check(P.ns.db.voice == false and Printed(P, "voice v1.0.0: OFF"),
          "core: a bare /pqol voice prints the voice readout and switches nothing (typing it to look must not turn voice off)")
    P.Slash("voice on")
    check(P.ns.db.voice == true, "core: /pqol voice on")
    P.Slash("questlog")
    check(P.ns.db.questlog == true and Printed(P, "questlog: |cFF66FF66on|r"), "core: a bare /pqol questlog says how it is, without switching it")
    P.printed = {}
    P.Slash("status")
    local sw = P.ns.statusFrame
    local text = sw and sw.edit.text or ""
    check(sw and sw.shown and text == P.ns.StatusText() and text:find("^Pace's Quality of Life %S+ %- status\n") and
          text:find("\nGame: 12.0.5 (build 64000, interface 16001, project 18)\n", 1, true) and
          text:find("\nquestlog: on", 1, true) and text:find("\nvoice: on ", 1, true) and
          text:find("\nNo errors this session.", 1, true) and #P.printed == 0,
          "core: /pqol status opens a window with the status in a text box, nothing in chat")
    check(not text:find("|", 1, true) and not text:find("Coretest", 1, true),
          "core: the status text is plain (no colour codes or icons to copy) and names nobody")
    -- (it is read only: typing puts it back; Escape closes it)
    sw.edit.text = "something typed"
    RunScript(sw.edit, "OnTextChanged", true)
    check(sw.edit.text == text, "core: the status window's text can't be typed over")
    sw.edit.text = "a change of ours"
    RunScript(sw.edit, "OnTextChanged", false)
    check(sw.edit.text == "a change of ours", "core: ... only what is typed is put back")
    RunScript(sw.edit, "OnEscapePressed")
    check(not sw.shown, "core: Escape closes the status window")
    -- an error that happens again and again: on record once, how many times, where from
    for _ = 1, 5 do P.ns.SafeCall("questlog", function() local t = nil; return t.x end) end
    P.printed = {}
    P.Slash("status")
    text = sw.edit.text
    local entry = P.ns.errors[#P.ns.errors]
    local info = P.ns.errorInfo[entry]
    check(sw.shown and #P.ns.errors == 1 and info and info.count == 5 and entry:find("^questlog: ") and
          text:find("\n1 error this session:\n1) questlog: ", 1, false) and text:find("(5 times)", 1, true) and
          type(info.stack) == "string" and text:find("\n     ", 1, true),
          "core: an error that repeats is listed once, with how many times and the calls that led to it")
    check(#P.printed == 0, "core: ... in the window only")
    -- the options page's Status button opens the same window
    sw:Hide()
    RunScript(P.optionsPanel.statusShow, "OnClick")
    check(sw.shown and P.ns.statusFrame == sw, "core: the options page's Status button opens it")
    sw:Hide()
    -- the window can't be made: the status in chat instead, the reason on record
    do
        local F = makePlayer("Corefallback", {beforeLoad = function(F, env)
            local create = env.CreateFrame
            env.CreateFrame = function(kind, ...)
                if kind == "EditBox" then error("no edit boxes here") end
                return create(kind, ...)
            end
        end})
        F.printed = {}
        F.Slash("status")
        check(Printed(F, "Pace's Quality of Life") and Printed(F, "questlog: on") and Printed(F, "1 error this session:") and
              Printed(F, "status: ") and Printed(F, "no edit boxes here"),
              "core: the status window can't be made: the status is printed in chat, with why")
        F.online = false
        players["Corefallback"] = nil
    end
    P.online = false
    players["Coretest"] = nil
end

--------------------------------------------------------------------------
-- voice: who's in a community voice channel, before you join it
--------------------------------------------------------------------------
do
    local justin = makePlayer("Justin", {gameAccountID = 501, bnetAccountId = 9001})
    local logan = makePlayer("Logan")
    local ryles = makePlayer("Ryles", {faction = "Horde"}) -- can't be whispered
    local sam = makePlayer("Sam", {gameAccountID = 503, bnetAccountId = 9003})
    local plain = makePlayer("Plain", {beforeLoad = function(P) P.files = {} end}) -- no addon
    plain.prefix = nil
    justin.bnFriends.Sam = true
    sam.bnFriends.Justin = true
    clubs["C1"] = {type = ENUM.ClubType.Character, members = {"Justin", "Logan", "Ryles", "Sam", "Plain"}}
    clubs["G1"] = {type = ENUM.ClubType.Guild, members = {"Justin", "Logan"}}
    justin.guild, logan.guild = "G1", "G1"

    -- Logan is in voice on C1's General stream
    logan.JoinVoice(7, "C1", "S1")
    advance(1)
    for _, R in ipairs({justin, logan, ryles, sam, plain}) do justin.AddRosterRow(R) end

    justin.OpenChannels("C1", "S1")
    local q = SentCount(justin, function(s) return s.msg:sub(1, 2) == "Q:" end)
    advance(3)
    check(justin.RowMic(logan), "voice: Logan, in voice, gets a microphone on Justin's roster before Justin joins")
    check(not justin.RowMic(sam) and not justin.RowMic(plain) and not justin.RowMic(justin),
          "voice: nobody else does (not in voice / no addon / yourself)")
    check(justin.Row(logan).Name.width == 124, "voice: Logan's name makes room for the icon")
    local whisperedRyles = SentCount(justin, function(s) return s.kind == "WHISPER" and s.to and s.to:find("^Ryles") end)
    check(whisperedRyles == 0, "voice: the other faction is never whispered (no 'no player named' errors)")
    check(SentCount(justin, function(s) return s.kind == "BN" and s.to == 503 end) >= 1,
          "voice: a Battle.net friend playing Forever is asked by game data")
    check(SentCount(justin, function(s) return s.kind == "WHISPER" and s.to and s.to:find("^Plain") end) >= 1,
          "voice: members without the addon are asked too (they just don't answer)")

    -- Logan leaves voice: Justin hears at once, no new question needed
    logan.LeaveVoice(7)
    advance(1)
    check(not justin.RowMic(logan), "voice: Logan leaves voice, the microphone goes")
    logan.JoinVoice(7, "C1", "S1")
    advance(1)
    check(justin.RowMic(logan), "voice: and comes back the moment he rejoins")

    -- Sam (Battle.net friend) joins: answered over Battle.net game data
    sam.JoinVoice(8, "C1", "S1")
    advance(1)
    check(justin.RowMic(sam), "voice: Sam, a Battle.net friend, shows too")

    -- Justin joins the channel himself: Blizzard's own icons take over
    justin.selectedVoiceActive = true
    justin.ns.Voice.Refresh()
    check(not justin.RowMic(logan), "voice: once Justin is in the channel, ours give way to Blizzard's")
    justin.selectedVoiceActive = false
    justin.ns.Voice.Refresh()

    -- the window re-asks every 90s while open, and stops when closed
    local before = SentCount(justin)
    advance(91)
    check(SentCount(justin) > before, "voice: asks again while the window stays open")
    justin.CloseChannels()
    advance(5)
    before = SentCount(justin)
    advance(200)
    check(SentCount(justin) == before, "voice: nothing sent while the window is closed")

    -- a guild's own club: one GUILD message instead of whispers
    justin.OpenChannels("G1", "GS")
    logan.LeaveVoice(7)
    logan.JoinVoice(9, "G1", "GS")
    advance(2)
    check(SentCount(justin, function(s) return s.kind == "GUILD" and s.msg:sub(1, 2) == "Q:" end) >= 1,
          "voice: a guild club is asked over GUILD")
    check(justin.RowMic(logan), "voice: Logan in the guild's voice shows")
    justin.printed = {}
    justin.Slash("voice")
    check(Printed(justin, "looking at: guild G1, stream GS; 2 members, 1 online;"),
          "readout: a guild's own stream counts its online members too")
    logan.printed = {}
    logan.Slash("voice")
    check(Printed(logan, "telling 0 asker(s) about my voice (and the guild, over GUILD);"),
          "readout: in the guild's voice, the guild is told (askers about other streams don't count)")
    justin.CloseChannels()

    -- Logan stops sharing: Justin no longer sees him after the answer runs out
    logan.ns.db.voiceShare = false
    logan.ns.VoiceShareChanged()
    logan.LeaveVoice(9)
    logan.JoinVoice(7, "C1", "S1")
    justin.OpenChannels("C1", "S1")
    advance(250)
    check(not justin.RowMic(logan), "voice: sharing off, Logan isn't shown")
    check(justin.RowMic(sam), "voice: Sam (sharing) still is")
    justin.CloseChannels()

    -- direct path: Justin joined C1's voice earlier and left with the
    -- headset; the game still knows Plain (no addon) is in it
    justin.voice[20] = {clubId = "C1", streamId = "S1", isActive = false, members = {[plain.guid] = true, [ryles.guid] = false}}
    justin.OpenChannels("C1", "S1")
    advance(1)
    check(justin.RowMic(plain) and not justin.RowMic(ryles),
          "voice: a channel joined then left: the game's own data shows Plain, no addon needed")
    justin.voice[20] = nil
    justin.CloseChannels()

    -- the game's chat lockdown: nothing sent, nothing shown
    justin.locked = true
    before = SentCount(justin)
    justin.OpenChannels("C1", "S1")
    advance(2)
    check(SentCount(justin) == before and not justin.RowMic(sam), "voice: in chat lockdown nothing is sent or shown")
    justin.locked = false
    justin.CloseChannels()

    -- the feature off: no questions, no icons
    justin.Slash("voice off")
    before = SentCount(justin)
    justin.OpenChannels("C1", "S1")
    advance(2)
    check(SentCount(justin) == before and not justin.RowMic(sam), "voice: switched off, nothing is sent or shown")
    justin.Slash("voice on")
    justin.CloseChannels()

    for _, R in ipairs({justin, logan, ryles, sam, plain}) do R.online = false; players[R.name] = nil end
end

--------------------------------------------------------------------------
-- quest log: track / untrack a whole zone, or everything
--------------------------------------------------------------------------
local function QuestLogOf(P, zones)
    P.log = {}
    local id = 100
    for _, z in ipairs(zones) do
        table.insert(P.log, {header = z[1], onMap = z.onMap})
        for _ = 1, z[2] do
            id = id + 1
            table.insert(P.log, {id = id})
        end
    end
end
local function Watched(P, from, to)
    local n = 0
    for id = from, to do if P.watched[id] then n = n + 1 end end
    return n
end
do
    local P = makePlayer("Questy")
    -- 34 quests in 6 zones, like the screenshot
    -- the open map shows Duskwood, the LAST zone in the log (129-134)
    QuestLogOf(P, {{"Redridge Mountains", 7}, {"Ashenvale", 5}, {"Blackfathom Deeps", 4},
                   {"Darkshore", 6}, {"Dun Morogh", 6}, {"Duskwood", 6, onMap = true}})
    P.watched[101], P.watched[102] = true, true -- two Redridge quests tracked
    P.OpenQuestMap()
    local red, ash = P.HeaderBox("Redridge Mountains"), P.HeaderBox("Ashenvale")
    check(red and ash, "questlog: every zone header gets a tracking checkbox")
    check(P.BoxState(red) == "some" and P.BoxState(ash) == "none",
          "questlog: ticked faintly when some of the zone is tracked, empty when none")
    -- header frames are pooled and reused for other zones on every
    -- rebuild: look the box up again after each click (the box itself
    -- always acts on the zone its header shows at click time)
    red.scripts.OnClick(red)
    red = P.HeaderBox("Redridge Mountains")
    check(Watched(P, 101, 107) == 7 and P.BoxState(red) == "all", "questlog: clicking a zone tracks all of it")
    red.scripts.OnClick(red)
    red = P.HeaderBox("Redridge Mountains")
    check(Watched(P, 101, 107) == 0 and P.BoxState(red) == "none", "questlog: clicking it again untracks all of it")
    ash = P.HeaderBox("Ashenvale")
    ash.scripts.OnClick(ash)
    check(Watched(P, 108, 112) == 5 and Watched(P, 101, 107) == 0, "questlog: Ashenvale's box tracks Ashenvale")

    -- everything: capped at 25, the zone on the map first
    local master = P.MasterBox()
    check(master and P.BoxState(master) == "some", "questlog: a box for all quests by the quest count")
    P.errorsShown = {}
    master.scripts.OnClick(master)
    check(P.WatchCount() == 25 and Watched(P, 129, 134) == 6, "questlog: track all fills the game's 25, the zone on the map first")
    check(P.errorsShown[1] and P.errorsShown[1]:find("9 not tracked", 1, true),
          "questlog: and says how many didn't fit")
    check(P.BoxState(master) == "some" and master.allTracked,
          "questlog: 25 of 34 is as full as it gets: the box offers to untrack")
    P.errorsShown = {}
    master.scripts.OnClick(master)
    check(P.WatchCount() == 0 and #P.errorsShown == 0, "questlog: so the next click untracks them all (no error)")
    -- a zone that only partly fits: its box untracks on the next click too
    for id = 101, 120 do P.watched[id] = true end -- 20 elsewhere tracked
    P.OpenQuestMap()
    local dusk = P.HeaderBox("Duskwood")
    dusk.scripts.OnClick(dusk)
    check(Watched(P, 129, 134) == 5 and P.WatchCount() == 25, "questlog: a zone fills what's left of the 25")
    dusk = P.HeaderBox("Duskwood")
    dusk.scripts.OnClick(dusk)
    check(Watched(P, 129, 134) == 0 and P.WatchCount() == 20, "questlog: and its next click untracks it")
    -- the tooltip under the mouse follows the click
    P.watched = {}
    P.OpenQuestMap()
    P.env.GameTooltip.IsOwned = function(_, b) return b == master end
    P.env.GameTooltip.lines = {}
    P.env.GameTooltip.AddLine = function(self, t) table.insert(self.lines, t) end
    master.scripts.OnClick(master)
    check(P.env.GameTooltip.lines[#P.env.GameTooltip.lines - 1] == "25 of 34 tracked",
          "questlog: the tooltip shows the new count after a click")
    -- untrack all from the gear menu
    local menu = P.GearMenu()
    check(menu["Track all quests"] and menu["Untrack all quests"], "questlog: Track all / Untrack all in the list's gear menu")
    menu["Untrack all quests"]()
    check(P.WatchCount() == 0 and P.BoxState(master) == "none", "questlog: untrack all clears every watch")
    menu["Track all quests"]()
    check(P.WatchCount() == 25, "questlog: and the gear menu's track all works too")

    -- hidden and task quests are never tracked
    QuestLogOf(P, {{"Duskwood", 2}})
    table.insert(P.log, {id = 900, hidden = true})
    table.insert(P.log, {id = 901, task = true})
    P.watched = {}
    P.OpenQuestMap()
    local dusk = P.HeaderBox("Duskwood")
    dusk.scripts.OnClick(dusk)
    check(P.watched[101] and P.watched[102] and not P.watched[900] and not P.watched[901],
          "questlog: hidden and task quests are left alone")

    -- switched off: the boxes go
    P.Slash("questlog off")
    P.OpenQuestMap()
    check(P.BoxState(P.HeaderBox("Duskwood")) == "hidden" and P.BoxState(P.MasterBox()) == "hidden",
          "questlog: off hides every box")
    check(next(P.GearMenu()) == nil, "questlog: and the gear menu entries")
    P.Slash("questlog on")
    P.online = false
    players[P.name] = nil
end

--------------------------------------------------------------------------
-- objective tracker follows the zone
--------------------------------------------------------------------------
do
    local P = makePlayer("Zoner")
    QuestLogOf(P, {{"Redridge Mountains", 7}, {"Blackfathom Deeps", 4}, {"Duskwood", 6}, {"Warrior", 1}})
    -- the map chain: a micro map in Duskwood -> Duskwood (zone) -> continent
    P.maps = {[1] = {name = "Darkshire", mapType = 5, parentMapID = 2}, [2] = {name = "Duskwood", mapType = 3, parentMapID = 3},
              [3] = {name = "Eastern Kingdoms", mapType = 2}}
    for id = 101, 107 do P.watched[id] = true end -- Redridge tracked
    P.zone, P.mapID = "Duskwood", 1
    P.Fire("ZONE_CHANGED_NEW_AREA")
    advance(2)
    check(Watched(P, 112, 117) == 6 and Watched(P, 101, 107) == 0 and P.WatchCount() == 6,
          "zone: entering Duskwood tracks Duskwood's quests and untracks the rest")
    -- the player tracks a Redridge quest by hand: it stays in Duskwood
    P.watched[101] = true
    P.Fire("ZONE_CHANGED_NEW_AREA")
    advance(2)
    check(P.watched[101], "zone: a quest tracked by hand stays until the next zone")
    -- into a dungeon: its header matches the instance's zone text
    P.zone, P.mapID = "Blackfathom Deeps", nil
    P.Fire("ZONE_CHANGED_NEW_AREA")
    advance(2)
    check(Watched(P, 108, 111) == 4 and P.WatchCount() == 4, "zone: inside Blackfathom Deeps, only its quests")
    -- combat: waits until it ends
    P.inCombat = true
    P.zone, P.mapID = "Redridge Mountains", nil
    P.Fire("ZONE_CHANGED_NEW_AREA")
    advance(2)
    check(Watched(P, 108, 111) == 4, "zone: nothing changes in combat")
    P.inCombat = false
    P.Fire("PLAYER_REGEN_ENABLED")
    advance(2)
    check(Watched(P, 101, 107) == 7 and P.WatchCount() == 7, "zone: and it catches up when combat ends")
    -- the super-tracked quest stays
    P.superTracked = 101
    P.zone = "Duskwood"
    P.Fire("ZONE_CHANGED_NEW_AREA")
    advance(2)
    check(P.watched[101] and Watched(P, 112, 117) == 6, "zone: the quest with your arrow stays tracked")
    P.superTracked = nil
    -- a zone with none of your quests: the tracker stays as it was
    P.zone, P.mapID = "Stormwind City", nil
    local was = P.WatchCount()
    P.Fire("ZONE_CHANGED_NEW_AREA")
    advance(2)
    check(P.WatchCount() == was and was > 0, "zone: a city with none of your quests leaves the tracker alone")
    -- a /reload in the same zone keeps what was tracked by hand
    local reloaded = makePlayer("Zoner2")
    reloaded.log, reloaded.maps = P.log, P.maps
    reloaded.zone, reloaded.mapID = "Duskwood", nil -- a zone with quests
    for id in pairs(P.watched) do reloaded.watched[id] = true end
    reloaded.watched[101] = true -- tracked by hand before the reload
    reloaded.Fire("PLAYER_ENTERING_WORLD", false, true)
    advance(2)
    check(reloaded.watched[101], "zone: a /reload doesn't redo the zone (hand-tracked quest stays)")
    reloaded.zone = "Redridge Mountains"
    reloaded.Fire("ZONE_CHANGED_NEW_AREA")
    advance(2)
    check(Watched(reloaded, 101, 107) == 7 and not reloaded.watched[112], "zone: the next real zone change does")
    reloaded.online = false
    players[reloaded.name] = nil
    -- off: zone changes leave watches alone
    P.Slash("zonetracker off")
    local before = P.WatchCount()
    P.zone = "Redridge Mountains"
    P.Fire("ZONE_CHANGED_NEW_AREA")
    advance(2)
    check(P.WatchCount() == before and P.watched[112], "zone: off, nothing changes")
    -- switched back on: applies to the zone you're in right away
    P.Slash("zonetracker on")
    advance(1)
    check(Watched(P, 101, 107) == 7 and not P.watched[112], "zone: switched on, the current zone at once")
    P.online = false
    players[P.name] = nil
end

--------------------------------------------------------------------------
-- Looking For Group: players by role
--------------------------------------------------------------------------
do
    local P = makePlayer("Seeker")
    local f = P.LoadLFG()
    f.shown = true
    P.lfg = {
        [1] = {name = "Seeker", self = true, roles = {dps = true}},
        [2] = {name = "Jujubinha", level = 17, class = "WARRIOR", roles = {dps = true}},
        [3] = {name = "Mendy", level = 20, class = "PRIEST", roles = {healer = true, dps = true}},
        [4] = {name = "Shieldy", level = 19, class = "WARRIOR", roles = {tank = true}},
        [5] = {name = "Grouply", members = 3, roles = {healer = true}},
        [6] = {name = "Holy", level = 21, class = "PRIEST", roles = {healer = true}},
    }
    P.lfgOrder = {1, 2, 3, 4, 5, 6}
    P.LFGResults()
    check(#P.OverlayRows() == 0, "lfg: all roles lit: Blizzard's own list, nothing of ours")
    local healer
    for _, fr in ipairs(P.frames) do
        if fr.role and fr.role.field == "healer" then healer = fr end
    end
    local bp = healer and healer:GetParent().point
    check(bp and bp[1] == "BOTTOM" and bp[2] == f and bp[3] == "BOTTOM" and bp[4] == 0 and bp[5] == 16 and
              healer:GetParent().width <= 196,
          "lfg: role buttons centred in the gap between Send Message and Group Invite")
    healer.scripts.OnClick(healer)
    local rows = P.OverlayRows()
    local names = {}
    for _, r in ipairs(rows) do names[#names + 1] = r.entry.name end
    table.sort(names)
    check(#rows == 2 and names[1] == "Holy" and names[2] == "Mendy",
          "lfg: one click on healer: only the solo players listing healer (not groups, not you)")
    check(f.SendMessageButton.alpha == 0 and f.GroupInviteButton.alpha == 0,
          "lfg: Blizzard's buttons fade under ours while filtering")
    local header
    for _, fr in ipairs(P.frames) do
        for _, rg in ipairs(fr.regions or {}) do
            if type(rg.text) == "string" and rg.text:find("^Players:") then header = rg.text end
        end
    end
    check(header and header:find("Healers", 1, true) and header:find("(2 of 4)", 1, true) and
              header:find("Your listing is hidden", 1, true),
          "lfg: the list says which roles, how many of the players, and that your listing is hidden")
    -- Blizzard refreshes the results: the filter holds
    P.lfg[7] = {name = "Newheals", level = 18, class = "PRIEST", roles = {healer = true}}
    table.insert(P.lfgOrder, 7)
    P.LFGResults()
    check(#P.OverlayRows() == 3, "lfg: a new search result is filtered too")
    -- select and invite / whisper
    local row = P.OverlayRows()[1]
    row.scripts.OnClick(row)
    local invite, send
    for _, fr in ipairs(P.frames) do
        if fr.text == "Group Invite" and fr.parent == f then invite = fr end
        if fr.text == "Send Message" and fr.parent == f then send = fr end
    end
    invite.scripts.OnClick(invite)
    send.scripts.OnClick(send)
    check(P.invited == row.entry.name and P.toldTo == row.entry.name, "lfg: Group Invite and Send Message act on our selection")
    -- double-click on the selected row: stays selected, whispers
    row.scripts.OnClick(row) -- first click of the double-click: deselects
    row.scripts.OnDoubleClick(row)
    local selTex
    for _, rg in ipairs(row.regions) do if rg.atlas == "common-button-list-mid2-selected" then selTex = rg end end
    check(selTex and selTex.shown and send:IsEnabled(), "lfg: a double-click leaves the row selected")
    -- a failed search: Blizzard's message, not our list
    f.searchFailed = true
    f:UpdateResults()
    local ovShown = P.OverlayRows()[1] and P.OverlayRows()[1].parent.parent.shown
    check(not ovShown, "lfg: a failed search shows Blizzard's message, not our list")
    f.searchFailed = nil
    P.LFGResults()
    -- add tanks
    local tank
    for _, fr in ipairs(P.frames) do if fr.role and fr.role.field == "tank" then tank = fr end end
    tank.scripts.OnClick(tank)
    check(#P.OverlayRows() == 4, "lfg: a second click adds tanks")
    -- remove healer and tank: back to everyone
    healer.scripts.OnClick(healer)
    tank.scripts.OnClick(tank)
    check(P.ns.db.lfgTank and P.ns.db.lfgHealer and P.ns.db.lfgDamage,
          "lfg: clearing the last role shows everyone again")
    check(f.SendMessageButton.alpha == 1, "lfg: and Blizzard's buttons come back")
    -- in a dungeon (chat lockdown): Blizzard's list, untouched
    healer.scripts.OnClick(healer)
    P.locked = true
    P.LFGResults()
    check(#P.OverlayRows() == 0 or not P.OverlayRows()[1].parent.parent.shown,
          "lfg: in lockdown ours steps aside")
    P.locked = false
    P.Slash("lfgroles off")
    P.LFGResults()
    check(f.SendMessageButton.alpha == 1, "lfg: off, Blizzard's list as always")
    P.online = false
    players[P.name] = nil
end

--------------------------------------------------------------------------
-- voice: reloads, asking once, big communities, late member lists, ranks
--------------------------------------------------------------------------
do
    local viewer = makePlayer("Viewer")
    local reloader = makePlayer("Reloader", {voiceAtLoad = {id = 31, club = "C3", stream = "S3"}})
    local filler = {}
    clubs["C3"] = {type = ENUM.ClubType.Character, members = {"Viewer", "Reloader"}}
    for _, R in ipairs({viewer, reloader}) do viewer.AddRosterRow(R) end
    viewer.OpenChannels("C3", "S3")
    advance(3)
    check(viewer.RowMic(reloader), "voice: someone who /reloaded while in voice is still seen")
    local function QTo(P, name)
        return SentCount(P, function(x) return x.msg:sub(1, 2) == "Q:" and x.to and x.to:find("^" .. name) end)
    end
    check(QTo(viewer, "Reloader") == 1, "voice: one question per member when the window opens")
    viewer.CloseChannels()
    viewer.OpenChannels("C3", "S3")
    viewer.SelectStream("C3", "S3") -- Blizzard re-selects on show
    advance(3)
    check(QTo(viewer, "Reloader") == 1, "voice: reopening at once doesn't ask again")
    viewer.CloseChannels()

    -- 70 online members without the addon, one user in voice at the end
    local names = {"Viewer"}
    for i = 1, 70 do
        local F = makePlayer("Filler" .. i, {beforeLoad = function(P) P.files = {} end})
        F.prefix = nil
        filler[#filler + 1] = F
        names[#names + 1] = F.name
    end
    local far = makePlayer("Faraway")
    names[#names + 1] = "Faraway"
    clubs["C4"] = {type = ENUM.ClubType.Character, members = names}
    far.JoinVoice(41, "C4", "S4")
    viewer.AddRosterRow(far)
    viewer.OpenChannels("C4", "S4")
    advance(5)
    check(not viewer.RowMic(far) and QTo(viewer, "Faraway") == 0, "voice: a big community: the first round asks 60 members")
    advance(25)
    check(viewer.RowMic(far) and QTo(viewer, "Faraway") == 1,
          "voice: the follow-up ten seconds later asks the rest, and finds the far one")
    advance(55) -- (the next round, and the 12 seconds 60 questions take to go out)
    local function QExact(P, name)
        return SentCount(P, function(x) return x.msg:sub(1, 2) == "Q:" and x.to == name end)
    end
    check(QExact(viewer, "Faraway") == 2 and QExact(viewer, "Filler1") == 2 and QExact(viewer, "Filler59") == 2 and
          QExact(viewer, "Filler60") == 1 and QExact(viewer, "Filler61") == 1,
          "voice: the next round asks the one who answered first, then whoever has waited longest")
    viewer.CloseChannels()

    -- the member list arrives after the stream is picked
    local late = makePlayer("Latecomer")
    clubs["C5"] = {type = ENUM.ClubType.Character, members = {"Viewer", "Latecomer"}, notReady = true}
    late.JoinVoice(51, "C5", "S5")
    viewer.AddRosterRow(late)
    viewer.OpenChannels("C5", "S5")
    advance(3)
    check(not viewer.RowMic(late), "voice: no members loaded yet, nobody to ask")
    clubs["C5"].notReady = false
    viewer.Fire("CLUB_MEMBERS_UPDATED", "C5")
    advance(4)
    check(viewer.RowMic(late), "voice: asked as soon as the member list comes in")
    viewer.CloseChannels()

    -- an owner's rank icon moves clear of the microphone
    local row = viewer.Row(late)
    row.showRank = true
    row.Rank = Widget("Texture", nil, row)
    row.Name.GetStringWidth = function() return 130 end
    viewer.OpenChannels("C5", "S5")
    advance(1)
    check(viewer.RowMic(late) and row.Rank.point and row.Rank.point[4] == 114,
          "voice: the rank icon sits after the shortened name, clear of the microphone")
    viewer.CloseChannels()

    for _, R in ipairs({viewer, reloader, far, late}) do R.online = false; players[R.name] = nil end
    for _, F in ipairs(filler) do F.online = false; players[F.name] = nil end
end

--------------------------------------------------------------------------
-- voice: a Battle.net community - the report ("I cannot see when other
-- users of the add-on are in a chat channel"). Its members are Battle.net
-- accounts: the roster rows carry the account's GUID, not a character's,
-- and 1.0.0 answered with the character's, so nothing ever matched.
--------------------------------------------------------------------------
local OLD = "tests/fixtures/pacesqol_voice_1_0_0.lua"
local function NoAddon(P) P.files = {} end
local function Msgs(P, kind, prefix)
    return SentCount(P, function(s) return (not kind or s.kind == kind) and s.msg:sub(1, #prefix) == prefix end)
end
do
    local justin = makePlayer("JustinB", {gameAccountID = 601, bnetAccountId = 9101})
    local logan = makePlayer("LoganB", {gameAccountID = 602, bnetAccountId = 9102})
    local stranger = makePlayer("StrangerB", {gameAccountID = 603, bnetAccountId = 9103})
    local appy = makePlayer("AppyB", {gameAccountID = 604, bnetAccountId = 9104, appFocused = true})
    local plain = makePlayer("PlainB", {gameAccountID = 605, bnetAccountId = 9105, beforeLoad = NoAddon})
    local idle = makePlayer("IdleB", {gameAccountID = 608, bnetAccountId = 9108})
    plain.prefix = nil
    for _, R in ipairs({logan, appy, plain, idle}) do
        justin.bnFriends[R.name] = true
        R.bnFriends.JustinB = true
    end
    logan.bnName, stranger.bnName = "Logan Broeker", "Stranger Danger" -- (Battle.net names, not characters)
    clubs["B1"] = {type = ENUM.ClubType.BattleNet, members = {"JustinB", "LoganB", "StrangerB", "AppyB", "PlainB", "IdleB"}}
    for _, R in ipairs({justin, logan, stranger, appy, plain, idle}) do justin.AddRosterRow(R) end
    logan.JoinVoice(70, "B1", "BS")
    stranger.JoinVoice(71, "B1", "BS")
    appy.JoinVoice(72, "B1", "BS")
    advance(1)
    justin.OpenChannels("B1", "BS")
    advance(3)
    local loc = justin.Row(logan):GetMemberPlayerLocation()
    check(loc and loc.GetGUID() == logan.accountGUID, "bn club: (the rows carry the members' Battle.net account GUIDs, as the game's do)")
    check(justin.RowMic(logan), "bn club: a Battle.net friend in the voice channel gets a microphone (the report)")
    check(SentCount(logan, function(x) return x.kind == "BN" and x.msg == "J:B1:BS:" .. logan.accountGUID end) >= 1,
          "bn club: the answer names Logan the way the club does (his Battle.net account), not by his character")
    check(justin.RowMic(appy), "bn club: a friend whose Battle.net app has the focus is still found on Forever")
    check(SentCount(justin, function(x) return x.kind == "BN" and x.to == 604 end) >= 1 and
          SentCount(justin, function(x) return x.kind == "BN" and x.to == 1604 end) == 0,
          "bn club: (asked on the Forever game account, not the app's)")
    check(not justin.RowMic(stranger), "bn club: a member who is nobody's friend, guildmate or group mate can't be reached")
    check(SentCount(justin, function(x) return x.kind == "WHISPER" end) == 0, "bn club: no whispers in a Battle.net community")
    check(not justin.RowMic(plain) and not justin.RowMic(idle) and not justin.RowMic(justin),
          "bn club: no microphone for a friend without the add-on, one not in voice, or yourself")
    check(Msgs(idle, "BN", "P:B1:BS:") == 1, "bn club: a friend with the add-on who isn't in voice says so (P)")

    -- the readout: everything one test needs, and no names
    justin.printed = {}
    justin.Slash("voice")
    check(justin.ns.db.voice == true and Printed(justin, "voice v1.0.0: on, sharing on, chat lockdown no, messages on, Chat Channels hooked, open"),
          "readout: /pqol voice prints the state line (and does not switch voice off)")
    check(Printed(justin, "me: not in voice"), "readout: my own voice")
    check(Printed(justin, "looking at: Battle.net community B1, stream BS; 6 members, 5 online; rows on screen 6 (Battle.net account 6, character 0, none 0)"),
          "readout: the community's kind, its members and the rows' GUID kinds")
    check(Printed(justin, "can ask: guild no, group no, Battle.net friends on Forever 4, by whisper 0, other faction 0, no way to reach 1"),
          "readout: who can be asked, and how many can't")
    check(Printed(justin, "sent: BN Q 4 | not sent: none"), "readout: what was sent, by route")
    check(Printed(justin, "BN J 2, BN P 1"), "readout: what came back")
    check(Printed(justin, "heard about this stream: 2 in voice (2 microphones on screen), 1 with the add-on but not in voice"),
          "readout: who was heard, and how many microphones that made")
    local function Named(P)
        for _, l in ipairs(P.printed) do
            for _, R in ipairs({justin, logan, stranger, appy, plain, idle}) do
                if l:find(R.name, 1, true) or (R.bnName and l:find(R.bnName, 1, true)) or l:find("#1234", 1, true) then
                    return true
                end
            end
        end
        return false
    end
    check(justin.Row(logan).Name:GetText() == "Logan Broeker", "readout: (the rows show Battle.net names, as the game's do)")
    check(not Named(justin), "readout: no names, Battle.net names or BattleTags in it")
    justin.printed = {}
    justin.Slash("voice log")
    check(Printed(justin, "out BN Q B1:BS P.."), "readout: /pqol voice log lists the last messages")
    check(not Named(justin), "readout: nor in the log")

    -- leaves and joins reach the asker at once
    logan.LeaveVoice(70)
    advance(1)
    check(not justin.RowMic(logan), "bn club: Logan leaves voice, the microphone goes")
    logan.JoinVoice(70, "B1", "BS")
    advance(1)
    check(justin.RowMic(logan), "bn club: and comes back when he rejoins")

    -- the readout on the side in voice: the stream, and the GUID its answers carry
    logan.printed = {}
    logan.Slash("voice")
    check(Printed(logan, "me: in voice in club B1 stream BS; that club knows me as B.." .. logan.accountGUID:sub(-4) ..
                         ", my character is P.." .. logan.guid:sub(-4)),
          "readout: in voice: which stream, and the GUID my answers carry (my Battle.net account's, as the club lists me)")
    check(Printed(logan, "telling 1 asker(s) about my voice;"), "readout: in voice: how many people hear my joins and leaves")
    check(not Named(logan), "readout: in voice: no names either")

    -- a friend still on 1.0.0 answers with the character's GUID: pinned on the member asked
    local old = makePlayer("OldLoganB", {gameAccountID = 606, bnetAccountId = 9106, voiceFile = OLD})
    -- (the game gives no character GUID for his game account: only the
    -- route he was asked by can place his answer)
    old.hideGuid = true
    justin.bnFriends.OldLoganB, old.bnFriends.JustinB = true, true
    table.insert(clubs["B1"].members, "OldLoganB")
    justin.AddRosterRow(old)
    old.JoinVoice(73, "B1", "BS")
    advance(61)
    check(SentCount(old, function(x) return x.kind == "BN" and x.msg == "J:B1:BS:" .. old.guid end) >= 1,
          "1.0.0: (the old answer carries the character's GUID)")
    check(justin.RowMic(old), "1.0.0: a friend who hasn't updated shows too (the answer is pinned on the member asked)")
    old.LeaveVoice(73)
    advance(1)
    check(not justin.RowMic(old), "1.0.0: and goes when he leaves")

    -- a 1.0.0 asker sees an updated friend: the answer carries the GUID its rows have
    local oldJ = makePlayer("OldJustinB", {gameAccountID = 607, bnetAccountId = 9107, voiceFile = OLD})
    oldJ.bnFriends.LoganB, logan.bnFriends.OldJustinB = true, true
    table.insert(clubs["B1"].members, "OldJustinB")
    oldJ.AddRosterRow(logan)
    oldJ.OpenChannels("B1", "BS")
    advance(3)
    check(oldJ.RowMic(logan), "1.0.0: an asker who hasn't updated sees an updated friend")
    -- (and hears his leaves and joins: they carry the GUID its rows have)
    logan.LeaveVoice(70)
    advance(1)
    check(not oldJ.RowMic(logan) and not justin.RowMic(logan), "1.0.0: the asker who hasn't updated hears him leave")
    logan.JoinVoice(70, "B1", "BS")
    advance(1)
    check(oldJ.RowMic(logan) and justin.RowMic(logan), "1.0.0: and rejoin")

    -- logging out in voice: the leave goes out there and then, to everyone who asked
    local before = #logan.sent
    logan.Fire("PLAYER_LOGOUT")
    local told = {}
    for i = before + 1, #logan.sent do
        local s = logan.sent[i]
        if s.kind == "BN" and s.msg == "L:B1:BS:" .. logan.accountGUID then told[s.to] = true end
    end
    check(told[601] and told[607], "logout: the leave goes at once to both people who asked (no timer runs after logout)")
    advance(0.5)
    check(not justin.RowMic(logan) and not oldJ.RowMic(logan), "logout: neither shows him any more (the one on 1.0.0 included)")

    justin.CloseChannels()
    oldJ.CloseChannels()
    for _, R in ipairs({justin, logan, stranger, appy, plain, idle, old, oldJ}) do R.online = false; players[R.name] = nil end
end

--------------------------------------------------------------------------
-- voice: guildmates and group mates in a Battle.net community who are not
-- Battle.net friends; a community whose rows carry no GUID at all
--------------------------------------------------------------------------
do
    local ga = makePlayer("GuildA", {gameAccountID = 611, bnetAccountId = 9111})
    local gb = makePlayer("GuildB", {gameAccountID = 612, bnetAccountId = 9112})
    local gc = makePlayer("GuildC", {gameAccountID = 613, bnetAccountId = 9113}) -- has the add-on, not in voice
    ga.guild, gb.guild, gc.guild = "GX", "GX", "GX"
    clubs["B2"] = {type = ENUM.ClubType.BattleNet, members = {"GuildA", "GuildB", "GuildC"}}
    ga.AddRosterRow(gb)
    ga.AddRosterRow(gc)
    gb.JoinVoice(80, "B2", "BS2")
    ga.OpenChannels("B2", "BS2")
    advance(3)
    check(ga.RowMic(gb), "guild: guildmates who aren't Battle.net friends find each other (one question over GUILD)")
    check(Msgs(gb, "WHISPER", "J:B2:BS2:") >= 1 and Msgs(gb, "GUILD", "J:") == 0,
          "guild: (answered by whisper: a Battle.net community's GUIDs aren't told to the whole guild)")
    check(SentCount(gc) == 0 and not ga.RowMic(gc),
          "guild: a guildmate not in that voice stays quiet (a question to the whole guild gets no 'not in voice')")
    ga.printed = {}
    ga.Slash("voice")
    check(Printed(ga, "my own coming back: GUILD 1"), "readout: our own GUILD question coming back is counted (GUILD messages flow)")
    ga.CloseChannels()

    local pa = makePlayer("PartyA", {gameAccountID = 621, bnetAccountId = 9121})
    local pb = makePlayer("PartyB", {gameAccountID = 622, bnetAccountId = 9122})
    local pc = makePlayer("PartyC", {gameAccountID = 623, bnetAccountId = 9123}) -- has the add-on, not in voice
    pa.group, pb.group, pc.group = "grp", "grp", "grp"
    clubs["B3"] = {type = ENUM.ClubType.BattleNet, members = {"PartyA", "PartyB", "PartyC"}}
    pa.AddRosterRow(pb)
    pb.JoinVoice(81, "B3", "BS3")
    pa.OpenChannels("B3", "BS3")
    advance(3)
    check(pa.RowMic(pb), "group: party members who aren't Battle.net friends find each other (one question to the party)")
    check(SentCount(pc) == 0, "group: a party member not in that voice stays quiet")
    pa.CloseChannels()

    -- the club gives no GUID: the row is matched by its member id
    local na = makePlayer("NoGuidA", {gameAccountID = 631, bnetAccountId = 9131})
    local nb = makePlayer("NoGuidB", {gameAccountID = 632, bnetAccountId = 9132})
    na.bnFriends.NoGuidB, nb.bnFriends.NoGuidA = true, true
    clubs["B4"] = {type = ENUM.ClubType.BattleNet, members = {"NoGuidA", "NoGuidB"}, noGuids = true}
    na.AddRosterRow(nb)
    nb.JoinVoice(82, "B4", "BS4")
    na.OpenChannels("B4", "BS4")
    advance(3)
    check(na.Row(nb):GetMemberPlayerLocation() == nil and na.RowMic(nb),
          "no GUID: a row without one still gets its microphone (matched by member id)")
    na.CloseChannels()

    -- the report after 1.1.0 ("I know Sam is in voice chat but it doesn't
    -- show", both updated): the community's member info carries no
    -- Battle.net account id (it is nilable), so 1.1.0 found no way to ask a
    -- friend at all. The account is read from the member's GUID, as
    -- Blizzard's own menus do.
    local aj = makePlayer("AcctJustin", {gameAccountID = 651, bnetAccountId = 9151})
    local as = makePlayer("AcctSam", {gameAccountID = 652, bnetAccountId = 9152})
    local ax = makePlayer("AcctStranger", {gameAccountID = 653, bnetAccountId = 9153})
    aj.bnFriends.AcctSam, as.bnFriends.AcctJustin = true, true
    clubs["B6"] = {type = ENUM.ClubType.BattleNet, members = {"AcctJustin", "AcctSam", "AcctStranger"}, noAccountIds = true}
    aj.AddRosterRow(as)
    aj.AddRosterRow(ax)
    as.JoinVoice(84, "B6", "BS6")
    ax.JoinVoice(85, "B6", "BS6")
    aj.OpenChannels("B6", "BS6")
    advance(3)
    check(aj.RowMic(as), "no account id: a Battle.net friend in voice gets his microphone (the account read from his GUID)")
    check(SentCount(aj, function(x) return x.kind == "BN" and x.to == 652 end) >= 1,
          "no account id: (asked on his Forever game account)")
    check(not aj.RowMic(ax) and SentCount(aj, function(x) return x.kind == "BN" and x.to == 653 end) == 0,
          "no account id: someone who isn't a friend still can't be reached")
    aj.printed = {}
    aj.Slash("voice")
    check(Printed(aj, "Battle.net friends on Forever 1, by whisper 0, other faction 0, no way to reach 1; for 1 of those friends the community gave no account, read from the GUID"),
          "readout: says when a friend's account came from the GUID")
    aj.CloseChannels()

    -- a refused send is counted, and the question goes again at the next chance
    local fa = makePlayer("FailA", {gameAccountID = 641, bnetAccountId = 9141})
    local fb = makePlayer("FailB", {gameAccountID = 642, bnetAccountId = 9142})
    fa.bnFriends.FailB, fb.bnFriends.FailA = true, true
    clubs["B5"] = {type = ENUM.ClubType.BattleNet, members = {"FailA", "FailB"}}
    fa.AddRosterRow(fb)
    fb.JoinVoice(83, "B5", "BS5")
    fa.bnResult = ENUM.SendAddonMessageResult.GeneralError
    fa.OpenChannels("B5", "BS5")
    advance(3)
    check(not fa.RowMic(fb), "refused: nothing arrives")
    fa.printed = {}
    fa.Slash("voice")
    check(Printed(fa, "not sent: BN code 9 1") and Printed(fa, "last problem: BN Q not sent: code 9"),
          "refused: the readout says so, with the game's code")
    fa.bnResult = nil
    advance(10)
    check(fa.RowMic(fb), "refused: the follow-up asks again (no 50-second wait for a question that never left)")
    fa.CloseChannels()

    for _, R in ipairs({ga, gb, gc, pa, pb, pc, na, nb, fa, fb, aj, as, ax}) do R.online = false; players[R.name] = nil end
end

--------------------------------------------------------------------------
-- voice: the whisper check, our own voice read from the game, a stream
-- switch, the guild's own stream, a window closed early
--------------------------------------------------------------------------
do
    -- the game never answers the "can whisper" check
    local sa, sb = makePlayer("SilentA"), makePlayer("SilentB")
    sa.checkMode, sb.checkMode = "silent", "silent"
    clubs["CS"] = {type = ENUM.ClubType.Character, members = {"SilentA", "SilentB"}}
    sb.JoinVoice(84, "CS", "SS")
    sa.AddRosterRow(sb)
    sa.OpenChannels("CS", "SS")
    advance(2)
    check(not sa.RowMic(sb) and Msgs(sa, "WHISPER", "Q:") == 0, "whisper check: waiting for the game's answer, nothing sent yet")
    advance(4)
    check(sa.RowMic(sb), "whisper check: the game never answers: the question goes after 4 seconds, and the answer comes back unchecked")
    sa.printed = {}
    sa.Slash("voice")
    check(Printed(sa, "whisper checks: asked 1, yes 0, no 0, no answer 1"), "readout: unanswered whisper checks are counted")
    sa.CloseChannels()

    -- the game answers inside the call
    local ya, yb = makePlayer("SyncA"), makePlayer("SyncB")
    ya.checkMode = "sync"
    clubs["CY"] = {type = ENUM.ClubType.Character, members = {"SyncA", "SyncB"}}
    yb.JoinVoice(85, "CY", "SY")
    ya.AddRosterRow(yb)
    ya.OpenChannels("CY", "SY")
    advance(2)
    check(ya.RowMic(yb) and Msgs(ya, "WHISPER", "Q:") == 1, "whisper check: an answer inside the call still finds the question waiting")
    ya.CloseChannels()

    -- the other faction is never whispered, even when the check would not answer
    local fh = makePlayer("HordeH", {faction = "Horde"})
    clubs["CY"].members[#clubs["CY"].members + 1] = "HordeH"
    ya.checkMode = "silent"
    ya.OpenChannels("CY", "SY")
    advance(6)
    check(SentCount(ya, function(x) return x.kind == "WHISPER" and x.to == "HordeH" end) == 0,
          "whisper: the other faction is left out before any check")
    ya.CloseChannels()

    -- the game says someone the club lists as online can't be whispered: not whispered, then or later
    local na, nw, nt = makePlayer("NoA"), makePlayer("NoWhisper"), makePlayer("NoTalker")
    nw.cantWhisper = true
    clubs["CN"] = {type = ENUM.ClubType.Character, members = {"NoA", "NoWhisper", "NoTalker"}}
    nt.JoinVoice(86, "CN", "SN")
    na.AddRosterRow(nt)
    na.AddRosterRow(nw)
    na.OpenChannels("CN", "SN")
    advance(3)
    local function ToNoWhisper() return SentCount(na, function(x) return x.kind == "WHISPER" and x.to == "NoWhisper" end) end
    check(na.RowMic(nt) and ToNoWhisper() == 0, "whisper check: a 'can't whisper' answer means no whisper")
    na.printed = {}
    na.Slash("voice")
    check(Printed(na, "whisper checks: asked 2, yes 1, no 1, no answer 0, skipped 1"), "readout: a 'can't whisper' is counted")
    advance(60)
    na.printed = {}
    na.Slash("voice")
    check(ToNoWhisper() == 0 and Printed(na, "whisper checks: asked 2, yes 1, no 1, no answer 0, skipped 2"),
          "whisper check: the next round goes by the stored answer, and still doesn't whisper")
    na.CloseChannels()

    -- our own voice: not readable at login, read again when a question comes
    local late = makePlayer("LateVoice", {voiceAtLoad = {id = 90, club = "C9", stream = "S9"},
                                          beforeLoad = function(P) P.voiceUnreadable = true end})
    local asker = makePlayer("AskerC9")
    clubs["C9"] = {type = ENUM.ClubType.Character, members = {"AskerC9", "LateVoice"}}
    late.voiceUnreadable = false -- the game reports it later; no event comes for that
    asker.AddRosterRow(late)
    asker.OpenChannels("C9", "S9")
    advance(3)
    check(asker.RowMic(late), "own voice: not readable at login, read again when a question comes")
    late.Fire("VOICE_CHAT_LOGOUT", 0)
    advance(2)
    check(asker.RowMic(late) and Msgs(late, nil, "L:") == 0,
          "own voice: a voice-chat logout that leaves the channel active changes nothing")
    asker.CloseChannels()

    -- another stream's headset: the old stream's askers hear the leave, whatever order the events come in
    local sw, sv = makePlayer("Switcher"), makePlayer("SwitchViewer")
    clubs["C11"] = {type = ENUM.ClubType.Character, members = {"SwitchViewer", "Switcher"}}
    sw.JoinVoice(96, "C11", "S1")
    sv.AddRosterRow(sw)
    sv.OpenChannels("C11", "S1")
    advance(3)
    check(sv.RowMic(sw), "stream switch: (in S1's voice, seen)")
    sw.SwitchVoice(96, 97, "C11", "S2")
    advance(2)
    check(not sv.RowMic(sw) and Msgs(sw, "WHISPER", "L:C11:S1:") == 1, "stream switch: moving to another stream says goodbye to the first")
    sv.CloseChannels()

    -- the guild's own stream: one answer over GUILD serves everyone looking
    local g1, g2, gt = makePlayer("Gv1"), makePlayer("Gv2"), makePlayer("Gtalk")
    for _, R in ipairs({g1, g2, gt}) do R.guild = "GZ" end
    clubs["GZ"] = {type = ENUM.ClubType.Guild, members = {"Gv1", "Gv2", "Gtalk"}}
    gt.JoinVoice(91, "GZ", "GS")
    advance(250) -- (the join's own announcement has run out)
    local before = Msgs(gt, "GUILD", "J:")
    g1.AddRosterRow(gt)
    g2.AddRosterRow(gt)
    g1.OpenChannels("GZ", "GS")
    g2.OpenChannels("GZ", "GS")
    advance(3)
    check(g1.RowMic(gt) and g2.RowMic(gt), "guild stream: both guildmates looking see the one in voice")
    check(Msgs(gt, "GUILD", "J:") - before == 1 and SentCount(gt, function(x) return x.kind == "WHISPER" end) == 0,
          "guild stream: one answer over GUILD serves both, and no whisper check is needed")
    g1.CloseChannels()
    g2.CloseChannels()

    -- closing the window drops the questions not yet sent; reopening asks them at once
    local closer = makePlayer("Closer")
    local names, quiet = {"Closer"}, {}
    for i = 1, 20 do
        local F = makePlayer("Quiet" .. i, {beforeLoad = NoAddon})
        F.prefix = nil
        quiet[#quiet + 1] = F
        names[#names + 1] = F.name
    end
    local endOne = makePlayer("EndOne")
    names[#names + 1] = "EndOne"
    clubs["C10"] = {type = ENUM.ClubType.Character, members = names}
    endOne.JoinVoice(95, "C10", "S10")
    closer.AddRosterRow(endOne)
    closer.OpenChannels("C10", "S10")
    advance(0.5)
    -- (a presence update right after opening arms a re-ask; the window closes before it runs)
    closer.Fire("CLUB_MEMBER_PRESENCE_UPDATED", "C10", 1, 1)
    advance(0.5)
    closer.CloseChannels()
    local whispersQ = function() return Msgs(closer, "WHISPER", "Q:") end
    local atClose = whispersQ()
    advance(6)
    check(atClose < 21 and whispersQ() == atClose,
          "window: closing drops the questions not yet sent, and nothing (a re-ask armed before) sends them while closed")
    closer.OpenChannels("C10", "S10")
    advance(6)
    check(closer.RowMic(endOne) and SentCount(closer, function(x) return x.to == "EndOne" and x.msg:sub(1, 2) == "Q:" end) == 1,
          "window: questions dropped on closing are asked at once on reopening, once")
    closer.CloseChannels()

    -- leaving voice in a dungeon (chat lockdown): nothing can be sent then, the leave goes once it lifts
    local lw, lt = makePlayer("LockView"), makePlayer("LockTalk")
    lw.guild, lt.guild = "GL", "GL"
    clubs["GL"] = {type = ENUM.ClubType.Guild, members = {"LockView", "LockTalk"}}
    lt.JoinVoice(98, "GL", "LS")
    lw.AddRosterRow(lt)
    lw.OpenChannels("GL", "LS")
    advance(3)
    check(lw.RowMic(lt), "lockdown: (in the guild's voice, seen)")
    lt.locked = true
    lt.LeaveVoice(98)
    advance(2)
    lt.printed = {}
    lt.Slash("voice")
    check(Printed(lt, "me: not in voice (the add-on tells the others once the lockdown ends)"),
          "lockdown: the readout says the leave waits for the lockdown's end")
    advance(20)
    check(lw.RowMic(lt) and Msgs(lt, nil, "L:") == 0, "lockdown: (nothing sent in it)")
    lt.locked = false
    advance(6)
    check(not lw.RowMic(lt) and Msgs(lt, "GUILD", "L:GL:LS:") == 1,
          "lockdown: once it lifts the leave goes out (not 200 seconds of a wrong microphone)")
    -- and the next dungeon of the session too (clear of the viewer's 60 s round)
    lt.JoinVoice(98, "GL", "LS")
    advance(2)
    check(lw.RowMic(lt), "lockdown: (back in voice, seen)")
    lt.locked = true
    lt.LeaveVoice(98)
    advance(10)
    lt.locked = false
    advance(6)
    check(not lw.RowMic(lt) and Msgs(lt, "GUILD", "L:GL:LS:") == 2, "lockdown: a second lockdown's leave goes out as it lifts too")
    lw.CloseChannels()

    -- a member who drops out without a leave (a crash): the microphone goes with Blizzard's grey row
    local ow, ot = makePlayer("OffView"), makePlayer("OffTalk")
    clubs["CO"] = {type = ENUM.ClubType.Character, members = {"OffView", "OffTalk"}}
    ot.JoinVoice(99, "CO", "OS")
    ow.AddRosterRow(ot)
    ow.OpenChannels("CO", "OS")
    advance(10)
    check(ow.RowMic(ot), "offline: (in voice, seen)")
    ot.online = false
    ow.Row(ot):Update() -- (Blizzard redraws the row on the presence change)
    check(not ow.RowMic(ot), "offline: a member who went offline loses the microphone with the grey row")
    ot.online = true
    ot.voice[99].isActive = false -- (logged back in: not in voice)
    ow.Row(ot):Update()
    check(not ow.RowMic(ot), "offline: and logging back in isn't being in voice")
    -- back in voice, then a second crash: the answer since the first doesn't outlive it
    ot.LeaveVoice(99) -- (the logged-in client's own view: not in voice yet)
    ot.JoinVoice(99, "CO", "OS")
    advance(10)
    check(ow.RowMic(ot), "offline: (back in voice, seen again)")
    ot.online = false
    ow.Row(ot):Update()
    check(not ow.RowMic(ot), "offline: a second drop-out takes it too")
    ot.online = true
    ow.Row(ot):Update()
    ow.CloseChannels()

    -- one who stops answering (the add-on switched off) loses it as the last answer runs out, not a round later
    local ev, et = makePlayer("ExpView"), makePlayer("ExpTalk")
    clubs["CE"] = {type = ENUM.ClubType.Character, members = {"ExpView", "ExpTalk"}}
    et.JoinVoice(100, "CE", "ES")
    ev.AddRosterRow(et)
    local opened = clock
    ev.OpenChannels("CE", "ES")
    advance(3)
    check(ev.RowMic(et), "expiry: (in voice, seen)")
    et.prefix = nil
    advance(opened + 195 - clock)
    check(ev.RowMic(et), "expiry: (still within the answer's 200 seconds)")
    advance(opened + 202 - clock)
    check(not ev.RowMic(et), "expiry: the microphone goes as the answer runs out")
    ev.CloseChannels()

    for _, R in ipairs({sa, sb, ya, yb, fh, na, nw, nt, late, asker, sw, sv, g1, g2, gt, closer, endOne, lw, lt, ow, ot, ev, et}) do
        R.online = false; players[R.name] = nil
    end
    for _, F in ipairs(quiet) do F.online = false; players[F.name] = nil end
end

--------------------------------------------------------------------------
-- voice: /reload. PLAYER_LOGOUT comes for a reload too; voice goes on
-- through it, so the people looking must go on seeing you.
--------------------------------------------------------------------------
do
    -- a WoW community: a Battle.net friend (asked by game data and by
    -- whisper), someone asked only by whisper, and someone still on 1.0.0
    local rj = makePlayer("ReJustin", {gameAccountID = 661, bnetAccountId = 9161})
    local rw = makePlayer("ReWhisper")
    local ro = makePlayer("ReOld", {voiceFile = OLD})
    local rl = makePlayer("ReLogan", {gameAccountID = 662, bnetAccountId = 9162})
    rj.bnFriends.ReLogan, rl.bnFriends.ReJustin = true, true
    clubs["CR"] = {type = ENUM.ClubType.Character, members = {"ReJustin", "ReWhisper", "ReOld", "ReLogan"}}
    for _, V in ipairs({rj, rw, ro}) do V.AddRosterRow(rl) end
    rl.JoinVoice(110, "CR", "RS")
    local t0 = clock
    for _, V in ipairs({rj, rw, ro}) do V.OpenChannels("CR", "RS") end
    advance(3)
    -- (to a moment well clear of the askers' rounds - every 60 s, 90 s on
    -- 1.0.0 - so that what follows can't come from a question)
    local function Quiet()
        for _ = 1, 200 do
            local a, b = (clock - t0) % 60, (clock - t0) % 90
            if a >= 2 and a < 38 and b >= 2 and b < 68 then return end
            advance(1)
        end
    end
    local function AllSee(R) return rj.RowMic(R) and rw.RowMic(R) and ro.RowMic(R) end
    local function NoneSee(R) return not rj.RowMic(R) and not rw.RowMic(R) and not ro.RowMic(R) end
    check(AllSee(rl), "reload: (in voice, seen by all three)")

    -- /reload: no leave, and everyone keeps the microphone through it
    local seen = true
    local rl2 = Reload(rl, {during = function() seen = AllSee(rl) end})
    check(Msgs(rl, nil, "L:") == 0 and seen, "reload: a /reload in voice tells nobody it left (it didn't)")
    advance(3)
    check(AllSee(rl2) and Msgs(rl2, nil, "J:") == 0, "reload: after it everyone still sees him, with no message needed")
    -- the reloaded UI took over who asked: his leave reaches them at once
    rl2.LeaveVoice(110)
    advance(1)
    check(NoneSee(rl2), "reload: the people who asked before the reload hear his leave after it")
    rl2.JoinVoice(110, "CR", "RS")
    advance(1)
    check(AllSee(rl2), "reload: and his rejoin")

    -- a reload that doesn't come through ReloadUI looks like a logout:
    -- the leave goes, and the reloaded UI says at once it is still in
    local leaves = Msgs(rl2, nil, "L:")
    local gone = false
    local rl3 = Reload(rl2, {direct = true, during = function() gone = NoneSee(rl2) end})
    check(Msgs(rl2, nil, "L:") - leaves == 4 and gone, "reload: (one the add-on can't tell from a logout says goodbye to all four routes)")
    advance(1)
    check(AllSee(rl3), "reload: and is back with everyone as soon as the UI is up, not a minute later")

    -- voice not readable yet just after a reload is not a leave
    local rl4 = Reload(rl3, {beforeLoad = function(P) P.voiceUnreadable = true end})
    advance(3)
    rl4.voiceUnreadable = false
    advance(10)
    check(Msgs(rl4, nil, "L:") == 0 and AllSee(rl4), "reload: voice the game reports a moment late is not taken for a leave")
    -- (but a leave the game does report in those seconds goes at once)
    local rl4b = Reload(rl4, {beforeLoad = function(P) P.voiceUnreadable = true end})
    advance(1)
    rl4b.voiceUnreadable = false
    rl4b.LeaveVoice(110)
    advance(1)
    check(NoneSee(rl4b), "reload: a leave the game reports during those seconds goes out at once")
    rl4b.JoinVoice(110, "CR", "RS")
    advance(1)
    check(AllSee(rl4b), "reload: (back in)")

    -- voice that ended across the reload: they hear the leave once the UI has looked again
    Quiet()
    local rl5 = Reload(rl4b, {during = function(P) P.voice[110].isActive = false end})
    advance(1)
    check(AllSee(rl5), "reload: (a few seconds' grace for the game to report voice)")
    advance(11)
    check(NoneSee(rl5), "reload: voice that ended with the reload is told as a leave (the add-on looks again by itself)")

    -- C_UI.Reload called directly (another add-on's /rl, Classic UI's nameplate switch): a reload too
    rl5.JoinVoice(110, "CR", "RS")
    advance(1)
    check(AllSee(rl5), "reload: (back in voice)")
    local leaves5, seen6 = Msgs(rl5, nil, "L:"), false
    local rl6 = Reload(rl5, {how = "cui", during = function() seen6 = AllSee(rl5) end})
    advance(1)
    check(Msgs(rl5, nil, "L:") == leaves5 and seen6 and AllSee(rl6), "reload: C_UI.Reload called directly is taken for a reload too")

    -- a reload no Lua sees (/console reloadui) with voice reported late:
    -- back about ten seconds after the UI is up, not at the next question
    Quiet()
    local rl7 = Reload(rl6, {how = "console", beforeLoad = function(P) P.voiceUnreadable = true end})
    advance(3)
    rl7.voiceUnreadable = false
    local early7 = AllSee(rl7)
    advance(9)
    check(not early7 and AllSee(rl7), "reload: one no add-on can see, voice reported late: back once the add-on looks again")

    -- a real logout: everyone hears the leave at once (no timer runs after it)
    rl7.Fire("PLAYER_LOGOUT")
    advance(0.5)
    check(NoneSee(rl7), "logout: a logout in voice is told at once, to all three")

    -- a reload that switches the add-on off (the add-on list, /disableaddons): told as a leave, like a logout
    rl7.LeaveVoice(110)
    rl7.JoinVoice(110, "CR", "RS")
    advance(2)
    check(AllSee(rl7), "reload: (in voice again)")
    rl7.addonOff = true
    local leaves7, gone8 = Msgs(rl7, nil, "L:"), false
    local rl8 = Reload(rl7, {noAddon = true, during = function() gone8 = NoneSee(rl7) end})
    check(Msgs(rl7, nil, "L:") - leaves7 == 4 and gone8, "reload: one that switches the add-on off tells everyone at once (nothing would after)")

    for _, V in ipairs({rj, rw, ro}) do V.CloseChannels() end
    for _, R in ipairs({rj, rw, ro, rl8}) do R.online = false; players[R.name] = nil end
end

do
    -- a Battle.net community whose data the client hasn't loaded when voice
    -- is joined (as at login after a /reload): what is told later still
    -- carries the GUID the club lists him under
    local cj = makePlayer("ClubJustin", {gameAccountID = 671, bnetAccountId = 9171})
    local cl = makePlayer("ClubLogan", {gameAccountID = 672, bnetAccountId = 9172})
    local cg = makePlayer("ClubGuildie", {gameAccountID = 673, bnetAccountId = 9173}) -- a guildmate, not a friend
    cj.bnFriends.ClubLogan, cl.bnFriends.ClubJustin = true, true
    cl.guild, cg.guild = "GC", "GC"
    clubs["B7"] = {type = ENUM.ClubType.BattleNet, members = {"ClubJustin", "ClubLogan", "ClubGuildie"}}
    cj.AddRosterRow(cl)
    cg.AddRosterRow(cl)
    cl.clubsNotReady = true
    cl.JoinVoice(120, "B7", "CS")
    advance(2)
    cl.clubsNotReady = false
    cj.OpenChannels("B7", "CS")
    cg.OpenChannels("B7", "CS")
    advance(3)
    check(cj.RowMic(cl) and cg.RowMic(cl), "club data late: (seen by a friend and by a guildmate who isn't one)")
    cl.LeaveVoice(120)
    advance(1)
    check(Msgs(cl, nil, "L:B7:CS:" .. cl.accountGUID) == 2 and Msgs(cl, nil, "L:B7:CS:" .. cl.guid) == 0,
          "club data late: the leave carries the club's GUID for him, though the club couldn't say when he joined")
    check(not cj.RowMic(cl) and not cg.RowMic(cl), "club data late: so the guildmate who isn't a friend hears it too")
    cj.CloseChannels()
    cg.CloseChannels()

    -- the guild's own club, its type not known yet when voice is joined:
    -- the leave still goes over GUILD, where the guildmates asking hear it
    local fv, ft = makePlayer("FlagView"), makePlayer("FlagTalk")
    fv.guild, ft.guild = "GF", "GF"
    clubs["GF"] = {type = ENUM.ClubType.Guild, members = {"FlagView", "FlagTalk"}}
    fv.AddRosterRow(ft)
    ft.clubsNotReady = true
    ft.JoinVoice(121, "GF", "FS")
    advance(2)
    ft.clubsNotReady = false
    fv.OpenChannels("GF", "FS")
    advance(3)
    check(fv.RowMic(ft), "club data late: (the guild stream, seen)")
    ft.LeaveVoice(121)
    advance(2)
    check(Msgs(ft, "GUILD", "L:GF:FS:") == 1 and not fv.RowMic(ft),
          "club data late: on the guild's own stream the leave goes over GUILD, though the club couldn't say it was the guild's")
    fv.CloseChannels()
    for _, R in ipairs({cj, cl, cg, fv, ft}) do R.online = false; players[R.name] = nil end
end

do
    -- /pqol voice in voice: "telling N" counts the people asking about the stream I'm in, once each
    local tt = makePlayer("TellTalk", {gameAccountID = 691, bnetAccountId = 9191})
    local t1 = makePlayer("TellOne", {gameAccountID = 692, bnetAccountId = 9192}) -- a friend: asks by game data and by whisper
    local t2 = makePlayer("TellTwo")                                           -- looks at another stream
    tt.bnFriends.TellOne, t1.bnFriends.TellTalk = true, true
    clubs["CT"] = {type = ENUM.ClubType.Character, members = {"TellTalk", "TellOne", "TellTwo"}}
    t1.AddRosterRow(tt)
    t2.AddRosterRow(tt)
    tt.JoinVoice(122, "CT", "T1")
    t1.OpenChannels("CT", "T1")
    t2.OpenChannels("CT", "T2")
    advance(3)
    check(t1.RowMic(tt) and Msgs(t1, "BN", "Q:") >= 1 and Msgs(t1, "WHISPER", "Q:") >= 1, "readout: (asked by game data and by whisper)")
    tt.printed = {}
    tt.Slash("voice")
    check(Printed(tt, "telling 1 asker(s) about my voice;"),
          "readout: one person asking two ways counts once, and someone asking about another stream not at all")
    t1.CloseChannels()
    t2.CloseChannels()

    -- the same client by another route: a 1.0.0 friend's leave by Battle.net clears what he said by whisper
    local ra = makePlayer("RouteA", {gameAccountID = 693, bnetAccountId = 9193})
    local rb = makePlayer("RouteB", {gameAccountID = 694, bnetAccountId = 9194, beforeLoad = NoAddon})
    rb.prefix = nil -- (his messages are played below, as 1.0.0 sends them)
    ra.bnFriends.RouteB, rb.bnFriends.RouteA = true, true
    clubs["CW"] = {type = ENUM.ClubType.Character, members = {"RouteA", "RouteB"}}
    ra.AddRosterRow(rb)
    ra.OpenChannels("CW", "WS")
    advance(3)
    ra.Fire("CHAT_MSG_ADDON", "PQoLVoice", "J:CW:WS:" .. rb.guid, "WHISPER", "RouteB-Forever")
    check(ra.RowMic(rb), "routes: (in voice, said by whisper)")
    ra.Fire("BN_CHAT_MSG_ADDON", "PQoLVoice", "L:CW:WS:" .. rb.guid, "WHISPER", 694)
    check(not ra.RowMic(rb), "routes: his leave by Battle.net game data clears it (the same client, another route)")
    -- (and when the game no longer says whose game account it was - he logged out - his character's GUID does)
    ra.Fire("CHAT_MSG_ADDON", "PQoLVoice", "J:CW:WS:" .. rb.guid, "WHISPER", "RouteB-Forever")
    rb.noGameInfo = true
    ra.Fire("BN_CHAT_MSG_ADDON", "PQoLVoice", "L:CW:WS:" .. rb.guid, "WHISPER", 694)
    check(not ra.RowMic(rb), "routes: a leave whose game account the game can't name any more still clears it, by the character's GUID")
    rb.noGameInfo = nil
    ra.CloseChannels()

    -- in a Battle.net community (the account's GUID on both): his own "not in voice" by game data
    -- corrects what he said by whisper, where only the routes' names tell it's him
    clubs["BR"] = {type = ENUM.ClubType.BattleNet, members = {"RouteA", "RouteB"}}
    ra.OpenChannels("BR", "RS")
    advance(3)
    ra.Fire("CHAT_MSG_ADDON", "PQoLVoice", "J:BR:RS:" .. rb.accountGUID, "WHISPER", "RouteB-Forever")
    check(ra.RowMic(rb), "routes: (a Battle.net community, in voice by whisper)")
    ra.Fire("BN_CHAT_MSG_ADDON", "PQoLVoice", "P:BR:RS:" .. rb.accountGUID, "WHISPER", 694)
    check(not ra.RowMic(rb), "routes: his own 'not in voice' by game data takes it back (the same client, another route)")
    ra.CloseChannels()

    -- asked by the guild and the party in the same round: one answer, not a second one ten seconds later
    local dx, dy = makePlayer("DupX", {gameAccountID = 699, bnetAccountId = 9199}), makePlayer("DupY", {gameAccountID = 700, bnetAccountId = 9200})
    dx.guild, dy.guild, dx.group, dy.group = "GDD", "GDD", "pdd", "pdd"
    clubs["BDD"] = {type = ENUM.ClubType.BattleNet, members = {"DupX", "DupY"}}
    dx.AddRosterRow(dy)
    dy.JoinVoice(125, "BDD", "DS")
    dx.OpenChannels("BDD", "DS")
    advance(15)
    check(dx.RowMic(dy) and Msgs(dx, "PARTY", "Q:") == 1 and Msgs(dx, "GUILD", "Q:") == 1 and Msgs(dy, "WHISPER", "J:") == 1,
          "gap: asked by the guild and the party in one round, answered once")
    dx.CloseChannels()

    -- Battle.net "Appear Offline": the row is grey, the guildmate is in voice and answers - shown
    local aa, ab = makePlayer("AppearA", {gameAccountID = 695, bnetAccountId = 9195}), makePlayer("AppearB", {gameAccountID = 696, bnetAccountId = 9196})
    aa.guild, ab.guild = "GAO", "GAO"
    ab.appearOffline = true
    clubs["BA"] = {type = ENUM.ClubType.BattleNet, members = {"AppearA", "AppearB"}}
    aa.AddRosterRow(ab)
    ab.JoinVoice(123, "BA", "AS")
    aa.OpenChannels("BA", "AS")
    advance(3)
    check(not aa.Row(ab):IsConnected() and aa.RowMic(ab),
          "offline: someone showing offline (Appear Offline) who answers from voice still gets the microphone")
    aa.CloseChannels()

    -- a stream switch: rows still showing the last club's members (Blizzard refills them a moment
    -- later) must not wipe what was heard from this club's member with the same id
    -- (SwitchB on 1.0.0: his answer carries his character, so only the member id places it)
    local sa2 = makePlayer("SwitchA", {gameAccountID = 697, bnetAccountId = 9197})
    local sb2 = makePlayer("SwitchB", {gameAccountID = 698, bnetAccountId = 9198, voiceFile = OLD})
    local so = makePlayer("SwitchOff")
    sa2.bnFriends.SwitchB, sb2.bnFriends.SwitchA = true, true
    clubs["BS"] = {type = ENUM.ClubType.BattleNet, members = {"SwitchA", "SwitchB"}}
    clubs["CS2"] = {type = ENUM.ClubType.Character, members = {"SwitchA", "SwitchOff"}}
    so.online = false
    sa2.AddRosterRow(sb2)
    sb2.JoinVoice(124, "BS", "SS")
    sa2.OpenChannels("BS", "SS")
    advance(10)
    check(sa2.RowMic(sb2), "stream switch: (seen)")
    -- a row as the last club left it: its member 2 is SwitchOff, offline
    local stale = Widget("Button")
    stale.Name = Widget("FontString", nil, stale)
    function stale:GetMemberID() return 2 end
    function stale:IsConnected() return false end
    function stale:GetMemberPlayerLocation() return {GetGUID = function() return so.guid end} end
    function stale:IsLocalPlayer() return false end
    function stale:IsChannelActive() return false end
    sa2.ns.Voice.Decorate(stale)
    sa2.ns.Voice.Refresh()
    check(sa2.RowMic(sb2), "stream switch: a row still showing the last club's offline member wipes nothing of this club's")
    sa2.CloseChannels()

    for _, R in ipairs({tt, t1, t2, ra, rb, dx, dy, aa, ab, sa2, sb2, so}) do R.online = false; players[R.name] = nil end
end

--------------------------------------------------------------------------
-- voice: an answer held back by its gap goes when the gap ends; one
-- Battle.net account with two Forever clients
--------------------------------------------------------------------------
do
    -- the asker reloads and asks again within seconds: answered within the gap's 10 seconds, not a round later
    local av = makePlayer("GapView")
    local at = makePlayer("GapTalk")
    clubs["CG"] = {type = ENUM.ClubType.Character, members = {"GapView", "GapTalk"}}
    at.JoinVoice(130, "CG", "GS")
    av.AddRosterRow(at)
    av.OpenChannels("CG", "GS")
    advance(2)
    check(av.RowMic(at), "gap: (seen)")
    local av2 = Reload(av, {loading = 2})
    av2.AddRosterRow(at)
    av2.OpenChannels("CG", "GS")
    advance(2)
    local early = av2.RowMic(at)
    advance(10)
    check(not early and av2.RowMic(at), "gap: someone who asks again inside the reply gap gets the answer as it ends")
    av2.CloseChannels()

    -- the guild's own stream: a guildmate who missed the last answer over GUILD (in a dungeon then)
    local q1, q2, qt = makePlayer("GapG1"), makePlayer("GapG2"), makePlayer("GapGT")
    for _, R in ipairs({q1, q2, qt}) do R.guild = "GQ" end
    clubs["GQ"] = {type = ENUM.ClubType.Guild, members = {"GapG1", "GapG2", "GapGT"}}
    qt.JoinVoice(131, "GQ", "QS")
    advance(250)
    local before = Msgs(qt, "GUILD", "J:")
    q1.AddRosterRow(qt)
    q2.AddRosterRow(qt)
    q2.locked = true
    q1.OpenChannels("GQ", "QS")
    advance(2)
    check(q1.RowMic(qt), "guild gap: (the first guildmate sees him)")
    q2.locked = false
    advance(10)
    q2.OpenChannels("GQ", "QS")
    advance(2)
    local early2 = q2.RowMic(qt)
    advance(8)
    check(not early2 and q2.RowMic(qt) and Msgs(qt, "GUILD", "J:") - before == 2,
          "guild gap: the second, asking inside the 20 seconds, gets an answer over GUILD as they end")
    q1.CloseChannels()
    q2.CloseChannels()

    -- one Battle.net account, two Forever clients: the one in voice is not undone by the other's "not in voice"
    local dv = makePlayer("DualView", {gameAccountID = 681, bnetAccountId = 9181})
    local d1 = makePlayer("DualOne", {gameAccountID = 682, bnetAccountId = 9182})
    local d2 = makePlayer("DualTwo", {gameAccountID = 683, bnetAccountId = 9182})
    d2.accountGUID = d1.accountGUID
    table.insert(d1.gameAccounts, d2.gameAccounts[1]) -- (the friend's game accounts: both clients)
    dv.bnFriends.DualOne, d1.bnFriends.DualView, d2.bnFriends.DualView = true, true, true
    clubs["BD"] = {type = ENUM.ClubType.BattleNet, members = {"DualView", "DualOne"}}
    dv.AddRosterRow(d1)
    d1.JoinVoice(140, "BD", "DS")
    dv.OpenChannels("BD", "DS")
    advance(3)
    check(Msgs(dv, "BN", "Q:") == 2 and Msgs(d2, "BN", "P:BD:DS:" .. d1.accountGUID) == 1,
          "two clients: (both asked; the one not in voice says so, under the same account)")
    check(dv.RowMic(d1), "two clients: the account shows in voice (the idle client's answer doesn't undo it)")
    advance(60)
    check(dv.RowMic(d1), "two clients: round after round")
    d1.LeaveVoice(140)
    advance(1)
    check(not dv.RowMic(d1), "two clients: the client in voice leaving takes it back")
    d2.JoinVoice(141, "BD", "DS")
    advance(1)
    check(dv.RowMic(d1), "two clients: the other client joining shows it again")
    dv.CloseChannels()

    for _, R in ipairs({av2, at, q1, q2, qt, dv, d1, d2}) do R.online = false; players[R.name] = nil end
end

--------------------------------------------------------------------------
-- party pets: the game's own pet frames under the party frames, through
-- its showPartyPets setting - switched at the next /reload, never on the
-- spot (the party frames act on the change at once, as add-on code)
--------------------------------------------------------------------------
local function OptionFrames(P)
    local box, reload
    for _, f in ipairs(P.frames) do
        if f.kind == "CheckButton" and f.label and (f.label.text or ""):find("^Party frames") then box = f end
        if f.kind == "Button" and f.text == "Reload now" then reload = f end
    end
    return box, reload
end
do
    local P = makePlayer("PetsA")
    check(not P.ns.IsOn("partypets") and P.cvars.showPartyPets == "0", "pets: off while the game's setting is off")
    check(P.ns.db.partypets == nil and P.ns.db.partyPetsPending == nil, "pets: nothing of it in the saved settings")
    local box, reload = OptionFrames(P)
    check(box and not box:GetChecked() and box:IsEnabled() and reload and not reload:IsShown(),
          "pets: the options page: a box, unticked, and no Reload button")
    P.printed = {}
    P.Slash("partypets on")
    check(P.cvars.showPartyPets == "0" and #P.cvarSets == 0,
          "pets: switching it on changes nothing on the spot (the party frames would take it as add-on code)")
    check(P.ns.IsOn("partypets") and Printed(P, "partypets |cFF66FF66on|r - party pets shown after your next |cFFFFCC00/reload|r"),
          "pets: it says when: after the next /reload")
    check(box:GetChecked() and reload:IsShown() and
          (P.optionsPanel.petsNote.text or ""):find("shown after your next /reload", 1, true),
          "pets: the options page: ticked, the note says when, and a Reload button")
    P.printed = {}
    P.Slash("partypets")
    check(Printed(P, "(the game's setting: hidden; shown at your next /reload)") and
          Printed(P, "|cFFFFCC00/pqol partypets on|off|r switches it"), "pets: a bare /pqol partypets says where it stands")

    -- the reload: the switch goes through at logout, and the new UI reads it
    local N = Reload(P)
    check(#P.cvarSets == 1 and P.cvarSets[1].value == "1" and not P.cvarSets[1].inCombat and N.cvars.showPartyPets == "1",
          "pets: the reload switches the game's setting (at logout)")
    check(N.ns.IsOn("partypets") and N.ns.db.partyPetsPending == nil, "pets: after it, on - and nothing left waiting")
    local _, reload2 = OptionFrames(N)
    check(reload2 and not reload2:IsShown(), "pets: no Reload button once it went through")
    check(#N.cvarSets == 0, "pets: (nothing set at login)")

    -- off, then back on before a reload: nothing waits
    N.Slash("partypets off")
    check(N.ns.db.partyPetsPending ~= nil and not N.ns.IsOn("partypets") and N.cvars.showPartyPets == "1",
          "pets: switching it off waits for the reload too")
    N.Slash("partypets on")
    check(N.ns.db.partyPetsPending == nil and N.ns.IsOn("partypets"), "pets: and back on before it: nothing waits")

    -- a reload in combat: nothing is changed in combat; the next reload does it
    N.Slash("partypets off")
    N.inCombat = true
    local N2 = Reload(N)
    check(#N.cvarSets == 0 and N2.cvars.showPartyPets == "1" and N2.ns.db.partyPetsPending ~= nil and not N2.ns.IsOn("partypets"),
          "pets: a reload in combat changes nothing; the switch keeps waiting")
    local N3 = Reload(N2)
    check(N3.cvars.showPartyPets == "0" and N3.ns.db.partyPetsPending == nil and not N3.ns.IsOn("partypets"),
          "pets: and goes through at the next one out of combat")

    -- changed another way meanwhile (/console showPartyPets 1): that stands
    N3.Slash("partypets on")
    N3.cvars.showPartyPets = "1"
    local N4 = Reload(N3)
    check(#N3.cvarSets == 0 and N4.cvars.showPartyPets == "1" and N4.ns.db.partyPetsPending == nil,
          "pets: changed some other way before the reload: left as it is, nothing waits")

    -- the Reload button
    N4.Slash("partypets off")
    N4.inCombat = true
    N4.printed = {}
    N4.ns.PartyPets.ReloadNow()
    check(not N4.reloadAsked and Printed(N4, "not in combat"), "pets: the Reload button does nothing in combat, and says why")
    N4.inCombat = false
    N4.ns.PartyPets.ReloadNow()
    check(N4.reloadAsked, "pets: out of combat it reloads")

    -- the game refusing the setting from an add-on (it returns nothing):
    -- said once, with what to type
    N4.cvarRefused = true
    local N5 = Reload(N4)
    check(N5.cvars.showPartyPets == "1" and N5.ns.db.partyPetsPending == nil and
          Printed(N5, "type |cFFFFCC00/console showPartyPets 0|r, then /reload"),
          "pets: the game refusing the switch: nothing left waiting for ever, and it says what to type")
    check((N5.optionsPanel.petsNote.text or ""):find("Type /console showPartyPets 0, then /reload.", 1, true) and
          not (N5.optionsPanel.petsNote.text or ""):find("last reload", 1, true),
          "pets: (the options page says it too, naming no time it may outlast)")
    local N5b = Reload(N5)
    check(N5b.ns.db.partyPetsPending == nil and #N5.cvarSets == 0 and
          (N5b.optionsPanel.petsNote.text or ""):find("didn't take the add-on's switch", 1, true) and
          not Printed(N5b, "didn't take"),
          "pets: (nothing tried again at the next reload, nor said again in chat; the note stays while the setting is as it was)")
    -- doing what it says (/console, then /reload): the note goes
    N5b.cvars.showPartyPets = "0"
    local N6 = Reload(N5b)
    check(N6.ns.db.partyPetsRefused == nil and not N6.ns.IsOn("partypets") and
          not (N6.optionsPanel.petsNote.text or ""):find("didn't take", 1, true),
          "pets: once the setting is changed the way it said, the refusal note goes")
    -- a refusal is also forgotten when a new switch is asked for
    N6.cvars.showPartyPets = "1"
    N6.ns.db.partyPetsRefused = {[N6.guid] = {want = false, from = true}}
    N6.Slash("partypets off")
    check(N6.ns.db.partyPetsRefused == nil and N6.ns.db.partyPetsPending ~= nil,
          "pets: (a new switch forgets the old refusal)")
    N6.Slash("partypets on")

    -- a switch that went through is done at logout itself: the add-on off for
    -- a session meanwhile, the setting put back by hand, it isn't made again
    N6.cvars.showPartyPets = "0"
    N6.cvarRefused = false
    N6.Slash("partypets on")
    local off = Reload(N6, {noAddon = true})
    check(off.cvars.showPartyPets == "1" and off.env.PacesQoLDB.partyPetsPending == nil,
          "pets: the switch made at logout is cleared there, not left for the next login")
    off.cvars.showPartyPets = "0" -- (/console showPartyPets 0 with Pace's QoL switched off)
    local back = Reload(off)
    local backBox = OptionFrames(back)
    check(not back.ns.IsOn("partypets") and backBox and not backBox:GetChecked() and back.ns.db.partyPetsPending == nil,
          "pets: back on later: the setting as it was left by hand, nothing waiting")
    local back2 = Reload(back)
    check(back2.cvars.showPartyPets == "0" and #back.cvarSets == 0, "pets: (and the next reload doesn't switch it again)")

    -- a session that ended without a logout (a crash), the setting switched
    -- some other way meanwhile: nothing waits at the next login
    back2.Slash("partypets on")
    back2.cvars.showPartyPets = "1"
    local crashed = makePlayer("PetsA", {same = back2, db = back2.env.PacesQoLDB})
    check(crashed.ns.db.partyPetsPending == nil and crashed.ns.IsOn("partypets"),
          "pets: after a crash, a switch the setting already has is done, not left waiting")

    -- each character's switch is its own: one kept by a reload in combat
    -- waits for that character, whoever logs in meanwhile
    crashed.Slash("partypets off")
    crashed.inCombat = true
    local still = Reload(crashed)
    check(still.ns.db.partyPetsPending ~= nil and still.ns.db.partyPetsPending[still.guid] ~= nil,
          "pets: a reload in combat keeps the switch, for this character")
    local other = makePlayer("PetsAlt", {db = still.env.PacesQoLDB, cvars = {showPartyPets = "1"}})
    local otherBox = OptionFrames(other)
    check(other.ns.IsOn("partypets") and otherBox and otherBox:GetChecked() and
          (other.ns.db.partyPetsPending or {})[still.guid] ~= nil and (other.ns.db.partyPetsPending or {})[other.guid] == nil,
          "pets: another character of the account isn't shown it (its own setting is), and it is left for the one that asked")
    local other2 = Reload(other)
    check(#other.cvarSets == 0 and other2.cvars.showPartyPets == "1", "pets: (nor switched at that character's logout)")
    LogOut(other2)
    local again = makePlayer("PetsA", {same = still, db = other2.env.PacesQoLDB})
    check(not again.ns.IsOn("partypets") and (again.ns.db.partyPetsPending or {})[again.guid] ~= nil,
          "pets: the character that asked comes back: its switch still waits")
    local again2 = Reload(again)
    check(again2.cvars.showPartyPets == "0" and again2.ns.db.partyPetsPending == nil, "pets: and is made at its own logout")

    -- refused at one character's logout, another logging in next: that one
    -- isn't told (not its switch) and leaves it; the one that asked is told
    -- at its next login. Another character's setting doesn't clear the report.
    again2.Slash("partypets on")
    again2.cvarRefused = true
    LogOut(again2)
    local alt = makePlayer("PetsAlt", {same = other2, db = again2.env.PacesQoLDB})
    check(not Printed(alt, "didn't take") and not (alt.optionsPanel.petsNote.text or ""):find("didn't take", 1, true) and
          alt.ns.db.partyPetsPending and alt.ns.db.partyPetsPending[again2.guid] and
          alt.ns.db.partyPetsPending[again2.guid].refused == true,
          "pets: refused at one character's logout: the next character in isn't told, and leaves it for the one that asked")
    local alt2 = Reload(alt)
    LogOut(alt2)
    local X = makePlayer("PetsA", {same = again2, db = alt2.env.PacesQoLDB})
    check(Printed(X, "type |cFFFFCC00/console showPartyPets 1|r, then /reload") and X.ns.db.partyPetsPending == nil and
          (X.optionsPanel.petsNote.text or ""):find("Type /console showPartyPets 1, then /reload.", 1, true),
          "pets: the character that asked is told at its next login, and its options page says what to type")
    LogOut(X)
    local alt3 = makePlayer("PetsAlt", {same = alt2, db = X.env.PacesQoLDB})
    check(alt3.cvars.showPartyPets == "1" and alt3.ns.db.partyPetsRefused and alt3.ns.db.partyPetsRefused[X.guid] ~= nil and
          not (alt3.optionsPanel.petsNote.text or ""):find("didn't take", 1, true),
          "pets: another character, its own setting not the one refused: neither shown the report nor clearing it")
    LogOut(alt3)
    local X2 = makePlayer("PetsA", {same = X, db = alt3.env.PacesQoLDB})
    check((X2.optionsPanel.petsNote.text or ""):find("Type /console showPartyPets 1, then /reload.", 1, true) and
          not Printed(X2, "didn't take"),
          "pets: back on the character that asked, the note is still there (said in chat once only)")

    -- one character holding a waiting switch and a report while another goes
    -- through every way its own are cleared: this one's stay (and anything
    -- in them that isn't a record of the add-on's goes at a login)
    do
        local me = makePlayer("PetsE"); LogOut(me)
        local them = makePlayer("PetsF", {db = me.env.PacesQoLDB, cvars = {showPartyPets = "1"}}); LogOut(them)
        local db = them.env.PacesQoLDB
        local function Seed(p, r)
            db.partyPetsPending = {[me.guid] = {want = true, from = false}, [them.guid] = p, who = me.guid}
            db.partyPetsRefused = {[me.guid] = {want = true, from = false, told = true}, [them.guid] = r, want = true}
        end
        local function Left(label)
            check(type(db.partyPetsPending) == "table" and db.partyPetsPending[me.guid] ~= nil and db.partyPetsPending.who == nil and
                  type(db.partyPetsRefused) == "table" and db.partyPetsRefused[me.guid] ~= nil and db.partyPetsRefused.want == nil,
                  "pets: another character " .. label .. ": this one's switch and report stay")
        end
        local gone = {me, them}
        for _, c in ipairs({{"whose switch went through meanwhile logs in", {want = true, from = false}},
                            {"whose switch was refused logs in", {want = false, from = true, refused = true}},
                            {"whose report is out of date logs in", nil, {want = false, from = false}}}) do
            Seed(c[2], c[3])
            local a = makePlayer("PetsF", {same = them, db = db}); Left(c[1]); LogOut(a); table.insert(gone, a)
        end
        Seed(nil, nil)
        local a = makePlayer("PetsF", {same = them, db = db})
        a.Slash("partypets on"); a.Slash("partypets off")
        a.cvars.showPartyPets = "0" -- (changed some other way before its logout)
        LogOut(a); Left("sets its box, and its setting is changed some other way before its logout")
        a.cvars.showPartyPets = "1"
        local b = makePlayer("PetsF", {same = them, db = db})
        b.Slash("partypets off"); LogOut(b)
        check(b.cvars.showPartyPets == "0", "pets: (that character's own switch made at its logout)")
        Left("makes its own switch at its logout")
        table.insert(gone, a); table.insert(gone, b)
        for _, R in ipairs(gone) do R.online = false end
        players["PetsE"], players["PetsF"] = nil, nil
    end

    -- a client without the setting
    local Q = makePlayer("PetsB", {cvars = {}})
    Q.printed = {}
    Q.Slash("partypets on")
    check(not Q.ns.IsOn("partypets") and Q.ns.db.partyPetsPending == nil and #Q.cvarSets == 0 and
          Printed(Q, "This client has no party pet frames"),
          "pets: a client without the setting says so and switches nothing")
    local qbox = OptionFrames(Q)
    check(qbox and not qbox:IsEnabled(), "pets: (its box can't be ticked)")
    Q.printed = {}
    Q.Slash("partypets")
    check(Printed(Q, "partypets:") and not Printed(Q, "switches it"), "pets: (a bare /pqol partypets there offers no switch)")

    -- a client whose setting the game keeps from add-ons (secure)
    local K = makePlayer("PetsK", {cvarSecure = true})
    K.printed = {}
    K.Slash("partypets on")
    local kbox = OptionFrames(K)
    check(not K.ns.IsOn("partypets") and K.ns.db.partyPetsPending == nil and kbox and not kbox:IsEnabled() and
          Printed(K, "The game keeps this setting from add-ons") and
          (K.optionsPanel.petsNote.text or ""):find("keeps this setting from add-ons", 1, true),
          "pets: a setting the game keeps from add-ons: said so, nothing waits, the box can't be ticked")
    K.printed = {}
    K.Slash("partypets")
    check(Printed(K, "the game keeps it from add-ons") and not Printed(K, "switches it"),
          "pets: (a bare /pqol partypets there offers no switch)")
    -- read-only: the same
    local RO = makePlayer("PetsRO", {cvarReadOnly = true})
    RO.printed = {}
    RO.Slash("partypets on")
    local robox = OptionFrames(RO)
    check(not RO.ns.IsOn("partypets") and RO.ns.db.partyPetsPending == nil and robox and not robox:IsEnabled() and
          Printed(RO, "The game keeps this setting from add-ons"),
          "pets: a read-only setting: the same, the box can't be ticked")
    -- locked from the player only, not from add-ons: switched as usual
    local LK = makePlayer("PetsLK", {cvarLocked = true})
    LK.Slash("partypets on")
    local lkbox = OptionFrames(LK)
    check(LK.ns.IsOn("partypets") and LK.ns.db.partyPetsPending ~= nil and lkbox and lkbox:IsEnabled(),
          "pets: a setting locked from the player only: the add-on's switch waits for the reload as usual")
    -- (whose switch it is was read at login: a logout where the game no
    -- longer says who the player is still makes it)
    LK.env.UnitGUID = function() return nil end
    local LK2 = Reload(LK)
    check(LK2.cvars.showPartyPets == "1" and LK2.ns.db.partyPetsPending == nil,
          "pets: (the character read at login: the logout makes its switch whatever the game says then)")
    for _, R in ipairs({P, N, N2, N3, N4, N5, N5b, N6, off, back, back2, crashed, still, other, other2, again, again2,
                        alt, alt2, X, alt3, X2, Q, K, RO, LK, LK2}) do R.online = false end
    players["PetsA"], players["PetsB"], players["PetsAlt"], players["PetsK"] = nil, nil, nil, nil
    players["PetsRO"], players["PetsLK"] = nil, nil
end

--------------------------------------------------------------------------
-- voice volume: what you set for each person is kept, and set again when
-- they're in voice with you - the next session too ("Can it also remember
-- the voice volume I have set for each person?")
--------------------------------------------------------------------------
do
    local vj = makePlayer("VolJustin", {gameAccountID = 701, bnetAccountId = 9201})
    local vs = makePlayer("VolSam", {gameAccountID = 702, bnetAccountId = 9202})
    local vl = makePlayer("VolLogan", {gameAccountID = 703, bnetAccountId = 9203})
    clubs["VC"] = {type = ENUM.ClubType.Character, members = {"VolJustin", "VolSam", "VolLogan"}}
    vj.voice[150] = {clubId = "VC", streamId = "VS", isActive = true, members = {[vj.guid] = true, [vs.guid] = true}}
    check(vj.ns.VoiceVolume.hooked, "volume: the game's volume setter is watched")
    vj.Slide(vs.guid, 38)
    check(vj.volumes.VolSam == 38, "volume: (the slider sets Sam to 38%)")
    local kept = vj.ns.db.voiceVolumes
    check(kept and kept[vs.guid] and kept[vs.guid].v == 38, "volume: and it is kept, under Sam's GUID")
    vj.Slide(vs.guid, 41)
    check(kept[vs.guid].v == 41, "volume: the latest setting is the one kept")
    vj.Fire("VOICE_CHAT_CHANNEL_MEMBER_VOLUME_CHANGED", vs.guid, 150, 100)
    check(kept[vs.guid].v == 41, "volume: the game's own volume event (a reset) changes nothing kept")

    -- the next session: the game starts Sam at its default again
    local nj = Reload(vj, {beforeLoad = function(N) N.volumes = {}; N.voice[150].members[vs.guid] = nil end})
    check(nj.volumes.VolSam == nil, "volume: (a new session starts Sam at the game's default)")
    nj.voice[150].members[vs.guid] = true
    nj.Fire("VOICE_CHAT_CHANNEL_MEMBER_ADDED", vs.guid, 150)
    check(nj.volumes.VolSam == 41, "volume: Sam joining the channel gets the 41% set last session")
    check((nj.clubMemberReads or 0) == 0, "volume: (a WoW community's member list isn't read for it: its members' GUIDs last)")
    local at = nj.ns.db.voiceVolumes[vs.guid].at
    nj.volumes.VolSam = 100 -- (the game setting its own as he finishes joining)
    advance(3.5)
    check(nj.volumes.VolSam == 41, "volume: looked at again a moment later, and set again")
    check(nj.ns.db.voiceVolumes[vs.guid].at == at and nj.ns.db.voiceVolumes[vs.guid].v == 41,
          "volume: setting it again is not taken as a change of Justin's")
    local sets = #nj.volumeSets
    nj.Fire("VOICE_CHAT_CHANNEL_MEMBER_ACTIVE_STATE_CHANGED", vs.guid, 150, true)
    advance(4)
    check(#nj.volumeSets == sets, "volume: nothing is set when it already matches")
    nj.voice[150].members[vl.guid] = true
    nj.Fire("VOICE_CHAT_CHANNEL_MEMBER_ADDED", vl.guid, 150)
    advance(4)
    check(nj.volumes.VolLogan == nil, "volume: someone whose volume was never set is left alone")

    -- joining a channel Sam is already in: everyone in it is looked at
    local j2 = Reload(nj, {beforeLoad = function(N) N.volumes = {}; N.voice[150].isActive = false end})
    check(j2.volumes.VolSam == nil, "volume: (not in voice at login: nothing set)")
    j2.voice[150].isActive = true
    j2.Fire("VOICE_CHAT_CHANNEL_ACTIVATED", 150)
    check(j2.volumes.VolSam == 41, "volume: joining the channel sets Sam's at once")
    -- after a /reload while in voice: no event comes, so it is looked at at login
    local j3 = Reload(j2, {beforeLoad = function(N) N.volumes = {} end})
    check(j3.volumes.VolSam == 41, "volume: logging in while in voice sets it too")

    -- the chat lockdown: nothing read or set; once it lifts, the channel is looked at
    local s2 = Reload(j3, {beforeLoad = function(N) N.volumes = {}; N.voice[150].members[vs.guid] = nil end})
    s2.locked = true
    s2.voice[150].members[vs.guid] = true
    s2.Fire("VOICE_CHAT_CHANNEL_MEMBER_ADDED", {__secret = true}, {__secret = true})
    check(s2.volumes.VolSam == nil, "volume: in the chat lockdown nothing is set")
    s2.locked = false
    advance(6)
    check(s2.volumes.VolSam == 41, "volume: once it lifts, the channel is looked at and Sam set again")

    -- switched off: nothing kept, nothing set
    s2.Slash("voicevolume off")
    s2.Slide(vs.guid, 70)
    check(s2.ns.db.voiceVolumes[vs.guid].v == 41, "volume: switched off, nothing new is kept")
    s2.volumes.VolSam = 100
    s2.Fire("VOICE_CHAT_CHANNEL_MEMBER_ADDED", vs.guid, 150)
    check(s2.volumes.VolSam == 100, "volume: nor set again")
    s2.Slash("voicevolume on")
    check(s2.volumes.VolSam == 41, "volume: switched back on, the channel is looked at at once")
    s2.printed = {}
    s2.Slash("voicevolume")
    check(Printed(s2, "voicevolume: |cFF66FF66on|r (1 person's volume kept;"), "volume: /pqol voicevolume says how many are kept")
    s2.Slash("voicevolume forget")
    check(s2.ns.db.voiceVolumes == nil and Printed(s2, "every remembered volume forgotten"), "volume: /pqol voicevolume forget forgets them")

    -- a Battle.net community: the row is the Battle.net account. That GUID
    -- may not last into the next session; the membership does
    local bj = makePlayer("VolBJ", {gameAccountID = 711, bnetAccountId = 9211})
    local bs = makePlayer("VolBS", {gameAccountID = 712, bnetAccountId = 9212})
    bj.bnFriends.VolBS, bs.bnFriends.VolBJ = true, true
    clubs["VB"] = {type = ENUM.ClubType.BattleNet, members = {"VolBJ", "VolBS"}}
    bj.voice[160] = {clubId = "VB", streamId = "VBS", isActive = true, members = {[bj.accountGUID] = true, [bs.accountGUID] = true}}
    bj.Slide(bs.accountGUID, 25)
    local bkept = bj.ns.db.voiceVolumes
    check(bkept and bkept[bs.accountGUID] and bkept[bs.accountGUID].v == 25 and bkept["club:VB:2"] and bkept["club:VB:2"].v == 25,
          "volume: in a Battle.net community it is kept under the account's GUID and the membership")
    bs.accountGUID = "BNetAccount-0-00000000BEEF"
    bj.bnFriends.VolBS = nil -- (not his friend this time: only the membership can find him)
    local nb = Reload(bj, {beforeLoad = function(N) N.volumes = {}; N.voice[160].members = {[N.accountGUID] = true} end})
    nb.voice[160].members[bs.accountGUID] = true
    nb.Fire("VOICE_CHAT_CHANNEL_MEMBER_ADDED", bs.accountGUID, 160)
    check(nb.volumes.VolBS == 25, "volume: another account GUID next session: found by the membership, set again")
    nb.bnFriends.VolBS = true
    -- a channel that names him by his character while the community names
    -- his account; an older setting kept under the character (set from his
    -- party frame, say) gives way to the newer one
    local nb2 = Reload(nb, {beforeLoad = function(N) N.volumes = {}; N.voice[160].members = {} end})
    nb2.voice[160].members[bs.guid] = true
    nb2.Fire("VOICE_CHAT_CHANNEL_MEMBER_ADDED", bs.guid, 160)
    check(nb2.volumes.VolBS == 25, "volume: a channel naming him by his character still finds him (through the community, as its roster does)")
    bkept[bs.guid] = {v = 80, at = 1}
    local nb3 = Reload(nb2, {beforeLoad = function(N) N.volumes = {}; N.voice[160].members = {} end})
    nb3.voice[160].members[bs.guid] = true
    nb3.Fire("VOICE_CHAT_CHANNEL_MEMBER_ADDED", bs.guid, 160)
    check(nb3.volumes.VolBS == 25, "volume: the newest setting of all his names wins (25, not an older 80 kept under his character)")

    -- not a friend: nothing says whose character the channel names, the
    -- community matches him as its roster does (C_VoiceChat.GetMemberID)
    nb3.bnFriends.VolBS = nil
    local nb4 = Reload(nb3, {beforeLoad = function(N) N.volumes = {}; N.voice[160].members = {} end})
    nb4.voice[160].members[bs.guid] = true
    nb4.Fire("VOICE_CHAT_CHANNEL_MEMBER_ADDED", bs.guid, 160)
    check(nb4.volumes.VolBS == 25, "volume: not a friend, named by his character: found through the community's own match")
    nb4.bnFriends.VolBS = true

    -- only so many kept: the oldest change goes first
    local many = {}
    for i = 1, 1010 do many[("Player-9-%05d"):format(i)] = {v = 50, at = i} end
    local pp = makePlayer("VolPrune", {db = {voiceVolumes = many}})
    pp.Slide("Player-9-99999", 60)
    local n = 0
    for _ in pairs(pp.ns.db.voiceVolumes) do n = n + 1 end
    check(n == 1000 and pp.ns.db.voiceVolumes["Player-9-99999"] and pp.ns.db.voiceVolumes["Player-9-00011"] == nil and
          pp.ns.db.voiceVolumes["Player-9-00012"] ~= nil,
          "volume: at most 1000 names kept, the oldest changes going first")

    for _, R in ipairs({vj, vs, vl, nj, j2, j3, s2, bj, bs, nb, nb2, nb3, nb4, pp}) do R.online = false; players[R.name] = nil end
end

--------------------------------------------------------------------------
-- voice volume: one person, several names. A Battle.net friend set from
-- their party frame (party voice: their character) and from a Battle.net
-- community's roster (their account) has one volume - the newest
--------------------------------------------------------------------------
do
    local pj = makePlayer("PvJustin", {gameAccountID = 721, bnetAccountId = 9301, strictLockdown = true})
    local ps = makePlayer("PvSam", {gameAccountID = 722, bnetAccountId = 9302})
    local pl = makePlayer("PvLogan", {gameAccountID = 723, bnetAccountId = 9303})
    pj.bnFriends.PvSam, ps.bnFriends.PvJustin = true, true
    clubs["PB"] = {type = ENUM.ClubType.BattleNet, members = {"PvJustin", "PvSam", "PvLogan"}}
    local PARTY = ENUM.ChatChannelType.PrivateParty
    pj.voice[170] = {channelType = PARTY, isActive = true, members = {[pj.guid] = true, [ps.guid] = true}}
    pj.voice[180] = {clubId = "PB", streamId = "PBS", isActive = false,
                     members = {[pj.accountGUID] = true, [ps.accountGUID] = true}}
    local function kept(P) return P.ns.db.voiceVolumes or {} end

    -- nothing kept yet: nothing read for it
    pj.Fire("VOICE_CHAT_CHANNEL_ACTIVATED", 170)
    pj.Fire("VOICE_CHAT_CHANNEL_MEMBER_ADDED", ps.guid, 170)
    check((pj.clubMemberReads or 0) == 0 and (pj.clubListReads or 0) == 0,
          "volume: nothing kept: no community list is read for it")

    -- from his party frame, in party voice: his character
    pj.Slide(ps.guid, 80)
    check(kept(pj)[ps.guid] and kept(pj)[ps.guid].v == 80 and kept(pj)[ps.accountGUID] and kept(pj)[ps.accountGUID].v == 80 and
          kept(pj)["club:PB:2"] and kept(pj)["club:PB:2"].v == 80,
          "volume: set from a friend's party frame: kept under his character, his Battle.net account and his community membership")
    -- then in the community's voice, from its roster: his account
    advance(5)
    pj.voice[170].isActive, pj.voice[180].isActive = false, true
    pj.Fire("VOICE_CHAT_CHANNEL_ACTIVATED", 180)
    check(pj.volumes.PvSam == 80, "volume: (in the community's voice he is already at 80)")
    pj.Slide(ps.accountGUID, 25)
    check(kept(pj)[ps.guid].v == 25 and kept(pj)["club:PB:2"].v == 25,
          "volume: set again from the community's roster: his character's volume is that too")
    -- back in party voice: the newest, not the party frame's older one
    advance(5)
    local sets = #pj.volumeSets
    pj.voice[180].isActive, pj.voice[170].isActive = false, true
    pj.Fire("VOICE_CHAT_CHANNEL_ACTIVATED", 170)
    advance(4)
    check(pj.volumes.PvSam == 25 and #pj.volumeSets == sets,
          "volume: back in party voice his latest (25) stands - the party frame's older 80 isn't set again")
    -- the next session, party voice first
    local pj2 = Reload(pj, {beforeLoad = function(N) N.volumes = {} end})
    check(pj2.volumes.PvSam == 25, "volume: next session, in party voice: his latest, 25")
    -- and the other way round: newest from the party frame, then the community
    advance(5)
    pj2.Slide(ps.guid, 60)
    local pj3 = Reload(pj2, {beforeLoad = function(N)
        N.volumes = {}
        N.voice[170].isActive, N.voice[180].isActive = false, true
    end})
    check(pj3.volumes.PvSam == 60, "volume: set last from his party frame: the community's voice gets that one")

    -- a drag of the slider is one change; one person is counted once
    pj3.printed = {}
    pj3.Slide(ps.accountGUID, 58); advance(0.2)
    pj3.Slide(ps.accountGUID, 57); advance(0.2)
    pj3.Slide(ps.accountGUID, 55)
    pj3.Slash("voicevolume")
    check(Printed(pj3, "(1 person's volume kept; this session 1 change(s) of yours kept"),
          "volume: one drag is one change, and one person is one person (whatever names he has)")

    -- in a dungeon (the chat lockdown) the roster's rows are drawn again with
    -- secret GUIDs: the game doesn't say whose a change is. Once out, the one
    -- found at that volume keeps it - not undone
    advance(5)
    pj3.Slide(pl.accountGUID, 45) -- (Logan, kept at 45)
    advance(5)
    pj3.locked = true
    pj3.voice[180].members[pl.accountGUID] = nil
    pj3.volumes.PvLogan = nil
    local reads = pj3.lockedClubReads or 0
    local secretSam = {__secret = true, real = ps.accountGUID}
    pj3.Slide(secretSam, 40); advance(0.2)
    pj3.Slide(secretSam, 30)
    check(pj3.volumes.PvSam == 30 and kept(pj3)["club:PB:2"].v == 55,
          "volume: in a dungeon, a change the game doesn't say whose: set by the game, nothing kept yet")
    pj3.voice[180].members[pl.accountGUID] = true -- (Logan joins meanwhile: at the game's 100)
    pj3.Fire("VOICE_CHAT_CHANNEL_MEMBER_ADDED", {__secret = true}, {__secret = true})
    check((pj3.lockedClubReads or 0) == reads, "volume: (no community list read in the lockdown)")
    pj3.locked = false
    advance(6)
    check(pj3.volumes.PvSam == 30 and kept(pj3)["club:PB:2"].v == 30 and kept(pj3)[ps.guid].v == 30,
          "volume: out of it: Sam, found at the 30 set in there, keeps it - kept, not undone")
    check(pj3.volumes.PvLogan == 45, "volume: (Logan, who joined in there at the game's own volume, is set to his 45)")
    pj3.printed = {}
    pj3.Slash("voicevolume")
    check(Printed(pj3, "1 change(s) the game didn't say whose (from a list drawn in a dungeon or raid), 1 of them kept after it"),
          "volume: /pqol voicevolume says so (one drag, one change)")
    -- at the slider's top - where the game starts everyone - it can't be
    -- told whose: nobody found there is taken as set to it, each is set
    -- back to their own - then, and whenever found there later
    advance(5)
    pj3.locked = true
    pj3.Slide(secretSam, 100)
    pj3.voice[180].members[pl.accountGUID] = nil
    pj3.volumes.PvLogan = nil
    pj3.voice[180].members[pl.accountGUID] = true
    pj3.locked = false
    advance(6)
    check(kept(pj3)["club:PB:3"].v == 45 and kept(pj3)["club:PB:2"].v == 30 and pj3.volumes.PvSam == 30 and
          pj3.volumes.PvLogan == 45,
          "volume: a change to the top in a dungeon can't be told from the game's own start: nobody taken as set to it, each set back to their own")
    advance(60)
    pj3.voice[180].members[pl.accountGUID] = nil
    pj3.volumes.PvLogan = nil
    pj3.voice[180].members[pl.accountGUID] = true
    pj3.Fire("VOICE_CHAT_CHANNEL_MEMBER_ADDED", pl.accountGUID, 180)
    check(pj3.volumes.PvLogan == 45, "volume: (and someone found at the top later is set again as usual)")
    -- one older than what is kept since isn't taken either
    advance(2)
    local later = math.floor(clock) + 1
    for _, k in ipairs({ps.guid, ps.accountGUID, "club:PB:2"}) do kept(pj3)[k] = {v = 70, at = later, p = "club:PB:2"} end
    advance(2)
    pj3.Fire("VOICE_CHAT_CHANNEL_MEMBER_ADDED", ps.accountGUID, 180)
    check(pj3.volumes.PvSam == 70, "volume: (a change the game didn't say whose, older than the volume kept since, isn't taken)")
    -- the list drawn in there, still showing once out: it still doesn't say
    -- whose, so a change to the top from it is set back too; set from the
    -- list opened again, it is kept
    advance(5)
    pj3.CloseMenu()
    pj3.Slide(secretSam, 100)
    check(pj3.volumes.PvSam == 100, "volume: (a change to the top once out, from the list drawn in there: set by the game)")
    advance(6)
    check(pj3.volumes.PvSam == 70 and kept(pj3)["club:PB:2"].v == 70,
          "volume: a change to the top once out, from the list drawn in there: still can't be told whose, set back")
    advance(5)
    pj3.CloseMenu()
    pj3.Slide(ps.accountGUID, 100)
    advance(6)
    check(pj3.volumes.PvSam == 100 and kept(pj3)["club:PB:2"].v == 100 and kept(pj3)[ps.guid].v == 100,
          "volume: set again from the list opened again: kept")

    -- a change made in a dungeon from a row drawn before it (its GUID still
    -- plain), the community not read this session: kept under the GUID at
    -- once, the community membership and character once out
    local pj4 = Reload(pj3, {beforeLoad = function(N) N.volumes = {}; N.locked = true end})
    advance(5)
    reads = pj4.lockedClubReads or 0
    pj4.Slide(ps.accountGUID, 33)
    check(kept(pj4)[ps.accountGUID].v == 33 and kept(pj4)["club:PB:2"].v == 100 and (pj4.lockedClubReads or 0) == reads,
          "volume: changed in a dungeon: kept under his account at once, no community list read")
    pj4.locked = false
    advance(6)
    check(kept(pj4)["club:PB:2"].v == 33 and kept(pj4)[ps.guid].v == 33,
          "volume: once out, under his community membership and character too")
    -- changed again in there, and once more just out of it, before that is filled in: the newest stays
    advance(5)
    pj4.locked = true
    pj4.Slide(ps.accountGUID, 34)
    pj4.locked = false
    advance(1.5)
    pj4.Slide(ps.accountGUID, 40)
    advance(6)
    check(kept(pj4)["club:PB:2"].v == 40 and kept(pj4)[ps.guid].v == 40 and kept(pj4)[ps.accountGUID].v == 40,
          "volume: a change made just after the lockdown, before the one in it is filled in, stays")

    -- next session, his account GUID another: through the membership (not
    -- his friend then, so nothing else can find him)
    ps.accountGUID = "BNetAccount-0-00000000CAFE"
    pj4.bnFriends.PvSam = nil
    local pj5 = Reload(pj4, {beforeLoad = function(N)
        N.volumes = {}
        N.voice[180].members = {[N.accountGUID] = true, [ps.accountGUID] = true}
    end})
    check(pj5.volumes.PvSam == 40, "volume: next session, with another account GUID: 40, through the membership")
    pj5.bnFriends.PvSam = true
    -- someone new in the community: he is read into its list (not the whole
    -- list again), and his membership kept with what is set for him
    advance(5)
    local pn = makePlayer("PvNew", {gameAccountID = 724, bnetAccountId = 9304})
    table.insert(clubs["PB"].members, "PvNew")
    local pbReads = (pj5.clubReadsBy or {})["PB"] or 0
    pj5.Fire("CLUB_MEMBER_ADDED", "PB", 4)
    pj5.Slide(pn.accountGUID, 52)
    check(kept(pj5)["club:PB:4"] and kept(pj5)["club:PB:4"].v == 52 and ((pj5.clubReadsBy or {})["PB"] or 0) == pbReads,
          "volume: someone who just joined the community: he alone is read, and his membership kept")
    -- the game saying the whole list changed: it is read again at its next use
    advance(5)
    local pn2 = makePlayer("PvNew2", {gameAccountID = 725, bnetAccountId = 9305})
    table.insert(clubs["PB"].members, "PvNew2")
    pj5.Fire("CLUB_MEMBERS_UPDATED", "PB")
    pj5.Slide(pn2.accountGUID, 44)
    check(kept(pj5)["club:PB:5"] and kept(pj5)["club:PB:5"].v == 44,
          "volume: (the community's whole list changed: read again, the newcomer's membership kept)")
    -- the community's list changed (it would be read again), then a dungeon:
    -- the list as it was is used, none read - a member changing in there too
    advance(5)
    pj5.Fire("CLUB_MEMBERS_UPDATED", "PB")
    pj5.locked = true
    reads = pj5.lockedClubReads or 0
    pj5.Fire("CLUB_MEMBER_UPDATED", "PB", 3)
    pj5.Slide(ps.accountGUID, 35)
    check(kept(pj5)["club:PB:2"].v == 35 and (pj5.lockedClubReads or 0) == reads,
          "volume: (in a dungeon, the community's list as read before it gives his membership at once)")
    pj5.locked = false
    advance(6)
    pj5.printed = {}
    pj5.Slash("voicevolume")
    check(Printed(pj5, "(4 people's volumes kept;"), "volume: (Sam, Logan and the two newcomers: four people, however many names)")
    -- forgetting in a dungeon: nothing comes back once out
    advance(5)
    pj5.locked = true
    pj5.Slide(ps.accountGUID, 36)
    pj5.Slash("voicevolume forget")
    pj5.locked = false
    advance(6)
    check(pj5.ns.db.voiceVolumes == nil, "volume: forgotten in a dungeon: nothing filled in once out")

    for _, R in ipairs({pj, ps, pl, pn, pn2, pj2, pj3, pj4, pj5}) do R.online = false; players[R.name] = nil end
    clubs["PB"] = nil
end

--------------------------------------------------------------------------
-- voice volume: changes the game doesn't say whose (rows drawn in a
-- dungeon), and which community lists are read for whom
--------------------------------------------------------------------------
do
    local fj = makePlayer("FcJustin", {gameAccountID = 731, bnetAccountId = 9401, strictLockdown = true})
    local fs = makePlayer("FcSam", {gameAccountID = 732, bnetAccountId = 9402})
    local fl = makePlayer("FcLogan", {gameAccountID = 733, bnetAccountId = 9403})
    clubs["FC"] = {type = ENUM.ClubType.BattleNet, members = {"FcJustin", "FcSam", "FcLogan"}}
    fj.voice[190] = {clubId = "FC", streamId = "FCS", isActive = true,
                     members = {[fj.accountGUID] = true, [fs.accountGUID] = true, [fl.accountGUID] = true}}
    local function kept(P) return P.ns.db.voiceVolumes or {} end
    local secretSam = {__secret = true, real = fs.accountGUID}
    local secretLogan = {__secret = true, real = fl.accountGUID}

    -- the first change for someone, made in a dungeon from a row drawn
    -- there: nothing says who could be at that volume (the game's volume is
    -- one per person, set from any of their names) - left as set, not kept
    advance(5)
    fj.locked = true
    fj.Slide(secretSam, 40)
    fj.locked = false
    advance(6)
    check(fj.volumes.FcSam == 40 and fj.ns.db.voiceVolumes == nil,
          "volume: a first change in a dungeon, from a list drawn there: left as set, not kept")
    fj.printed = {}
    fj.Slash("voicevolume")
    check(Printed(fj, "1 change(s) the game didn't say whose (from a list drawn in a dungeon or raid), 0 of them kept after it"),
          "volume: (/pqol voicevolume says so)")
    -- set from the list opened again once out: kept
    advance(5)
    fj.CloseMenu()
    fj.Slide(fs.accountGUID, 40)
    fj.CloseMenu()
    fj.Slide(fl.accountGUID, 35)
    check(kept(fj)["club:FC:2"].v == 40 and kept(fj)["club:FC:3"].v == 35, "volume: (set from a list opened once out: kept)")

    -- two people kept, changed there moments apart (one menu, then the next
    -- row's): two changes, each kept, neither undone
    advance(5)
    fj.locked = true
    fj.CloseMenu()
    fj.Slide(secretSam, 20)
    advance(1.5)
    fj.Slide(secretLogan, 80)
    fj.locked = false
    advance(6)
    check(fj.volumes.FcSam == 20 and fj.volumes.FcLogan == 80 and kept(fj)["club:FC:2"].v == 20 and
          kept(fj)["club:FC:3"].v == 80,
          "volume: two people changed in a dungeon moments apart: two changes, each kept, neither undone")
    fj.printed = {}
    fj.Slash("voicevolume")
    check(Printed(fj, "3 change(s) the game didn't say whose (from a list drawn in a dungeon or raid), 2 of them kept after it"),
          "volume: (counted as two more)")
    -- later, in party voice, his character (not a friend: nothing says whose
    -- character it is - the community knows his account) is found at that
    -- volume: it gets no volume of its own from it, so a later change from
    -- the community's list isn't undone in party voice
    fj.voice[190].isActive = false
    fj.voice[191] = {channelType = ENUM.ChatChannelType.PrivateParty, isActive = true,
                     members = {[fj.guid] = true, [fs.guid] = true}}
    fj.Fire("VOICE_CHAT_CHANNEL_ACTIVATED", 191)
    check(kept(fj)[fs.guid] == nil and fj.volumes.FcSam == 20,
          "volume: (his character, found at it in party voice later, isn't taken as changed: no volume of its own)")
    fj.voice[191].isActive, fj.voice[190].isActive = false, true
    fj.Fire("VOICE_CHAT_CHANNEL_ACTIVATED", 190)
    advance(5)
    fj.CloseMenu()
    fj.Slide(fs.accountGUID, 70)
    fj.voice[190].isActive, fj.voice[191].isActive = false, true
    fj.Fire("VOICE_CHAT_CHANNEL_ACTIVATED", 191)
    advance(4)
    check(fj.volumes.FcSam == 70, "volume: (a later change from the community's list stands in party voice)")
    fj.voice[191].isActive, fj.voice[190].isActive = false, true
    fj.Fire("VOICE_CHAT_CHANNEL_ACTIVATED", 190)
    local fj2 = Reload(fj, {beforeLoad = function(N) N.volumes = {} end})
    check(fj2.volumes.FcSam == 70 and fj2.volumes.FcLogan == 80, "volume: and both set again next session")

    -- someone else changed there to the volume Sam is at: he keeps it, and
    -- Sam's character (party voice) gets nothing from it
    advance(5)
    fj2.locked = true
    fj2.CloseMenu()
    fj2.Slide(secretLogan, 70)
    fj2.locked = false
    advance(6)
    check(kept(fj2)["club:FC:3"].v == 70 and kept(fj2)["club:FC:2"].v == 70,
          "volume: (someone kept, found once out at the volume another is at: he keeps it)")
    fj2.voice[190].isActive, fj2.voice[191].isActive = false, true
    fj2.Fire("VOICE_CHAT_CHANNEL_ACTIVATED", 191)
    check(kept(fj2)[fs.guid] == nil, "volume: (and the other's character, at it in party voice, gets nothing from it)")
    fj2.voice[191].isActive, fj2.voice[190].isActive = false, true
    fj2.Fire("VOICE_CHAT_CHANNEL_ACTIVATED", 190)

    -- a row drawn in the dungeon, moved once out of it: looked for in a moment
    advance(5)
    fj2.Slide(secretSam, 66)
    advance(6)
    check(fj2.volumes.FcSam == 66 and kept(fj2)["club:FC:2"].v == 66,
          "volume: a row drawn in a dungeon, its slider moved once out of it: kept a moment later")

    -- a drag still going as the dungeon ends: looked for once it stops, at
    -- the volume it ends at
    advance(5)
    fj2.locked = true
    fj2.Slide(secretLogan, 65)
    advance(1.5)
    fj2.Slide(secretLogan, 62)
    advance(1.5)
    fj2.Slide(secretLogan, 60)
    advance(1.5)
    fj2.locked = false
    fj2.Slide(secretLogan, 58)
    advance(1)
    check(kept(fj2)["club:FC:3"].v == 70, "volume: (nothing taken while the slider is still moving)")
    fj2.Slide(secretLogan, 50)
    advance(5)
    check(fj2.volumes.FcLogan == 50 and kept(fj2)["club:FC:3"].v == 50,
          "volume: a drag going on as the dungeon ends: what it ends at is kept")

    -- set from his party frame too (his character: a name of its own, not
    -- linked to his account), then changed once more from a list drawn in a
    -- dungeon: once out, each of his names found at it takes it - one change
    advance(5)
    fj2.voice[190].isActive, fj2.voice[191].isActive = false, true
    fj2.Fire("VOICE_CHAT_CHANNEL_ACTIVATED", 191)
    fj2.CloseMenu()
    fj2.Slide(fs.guid, 66)
    check(kept(fj2)[fs.guid] and kept(fj2)[fs.guid].v == 66, "volume: (set from his party frame: kept under his character)")
    fj2.voice[191].isActive, fj2.voice[190].isActive = false, true
    fj2.Fire("VOICE_CHAT_CHANNEL_ACTIVATED", 190)
    advance(5)
    fj2.locked = true
    fj2.CloseMenu()
    fj2.Slide(secretSam, 30)
    fj2.locked = false
    advance(6)
    fj2.voice[190].isActive, fj2.voice[191].isActive = false, true
    fj2.Fire("VOICE_CHAT_CHANNEL_ACTIVATED", 191)
    check(kept(fj2)["club:FC:2"].v == 30 and kept(fj2)[fs.guid].v == 30 and fj2.volumes.FcSam == 30,
          "volume: a change from a list drawn in a dungeon: each of his names kept, found at it, takes it")
    fj2.printed = {}
    fj2.Slash("voicevolume")
    check(Printed(fj2, "4 change(s) the game didn't say whose (from a list drawn in a dungeon or raid), 4 of them kept after it"),
          "volume: (one change, counted once however many of his names take it)")
    fj2.voice[191].isActive, fj2.voice[190].isActive = false, true
    fj2.Fire("VOICE_CHAT_CHANNEL_ACTIVATED", 190)

    -- your other Battle.net communities: read once, not again at each
    -- arrival who isn't in them (only the channel's own is read again for
    -- someone it doesn't have, at most every 30 seconds)
    clubs["FX"] = {type = ENUM.ClubType.BattleNet, members = {"FcJustin", "FcLogan"}}
    local fj3 = Reload(fj2, {beforeLoad = function(N) N.volumes = {} end})
    local before = (fj3.clubReadsBy or {})["FX"] or 0
    for _ = 1, 3 do
        advance(40)
        fj3.voice[190].members[fs.accountGUID] = nil
        fj3.volumes.FcSam = nil
        fj3.voice[190].members[fs.accountGUID] = true
        fj3.Fire("VOICE_CHAT_CHANNEL_MEMBER_ADDED", fs.accountGUID, 190)
    end
    check(before == 1 and fj3.volumes.FcSam == 30 and ((fj3.clubReadsBy or {})["FX"] or 0) == before,
          "volume: a community he isn't in is read once, not again at each of his arrivals")
    -- the channel's own community, someone in it the list as read doesn't
    -- have (no word from the game): read again for him
    local fn = makePlayer("FcNew", {gameAccountID = 734, bnetAccountId = 9404})
    table.insert(clubs["FC"].members, "FcNew")
    advance(40)
    fj3.Slide(fn.accountGUID, 33)
    check(kept(fj3)["club:FC:4"] and kept(fj3)["club:FC:4"].v == 33,
          "volume: someone the channel's community list didn't have: read again, his membership kept")
    -- one member updated over and over: the list voice members are matched
    -- against still has room for a newcomer (not a friend, in the channel by
    -- his character: only the community's own match finds him)
    for _ = 1, 600 do fj3.Fire("CLUB_MEMBER_UPDATED", "FC", 2) end
    local fn2 = makePlayer("FcNew2", {gameAccountID = 735, bnetAccountId = 9405})
    table.insert(clubs["FC"].members, "FcNew2")
    fj3.Fire("CLUB_MEMBER_ADDED", "FC", 5)
    fj3.Slide(fn2.accountGUID, 27)
    fj3.volumes.FcNew2 = nil
    fj3.voice[190].members[fn2.guid] = true
    fj3.Fire("VOICE_CHAT_CHANNEL_MEMBER_ADDED", fn2.guid, 190)
    check(fj3.volumes.FcNew2 == 27,
          "volume: a member updated over and over doesn't crowd a newcomer out of the community's match")
    -- someone joining another of your communities in a dungeon, or with the
    -- game giving no GUID as they join: that list is read again at its next use
    advance(5)
    local fx1 = makePlayer("FxNew1", {gameAccountID = 736, bnetAccountId = 9406})
    fj3.locked = true
    table.insert(clubs["FX"].members, "FxNew1")
    fj3.Fire("CLUB_MEMBER_ADDED", "FX", #clubs["FX"].members)
    fj3.locked = false
    advance(6)
    fj3.Slide(fx1.accountGUID, 61)
    check(kept(fj3)["club:FX:3"] and kept(fj3)["club:FX:3"].v == 61,
          "volume: someone joining another community in a dungeon: its list read again once out, his membership kept")
    advance(5)
    local fx2 = makePlayer("FxNew2", {gameAccountID = 737, bnetAccountId = 9407})
    table.insert(clubs["FX"].members, "FxNew2")
    clubs["FX"].noGuids = true
    fj3.Fire("CLUB_MEMBER_ADDED", "FX", #clubs["FX"].members)
    clubs["FX"].noGuids = nil
    advance(5)
    fj3.Slide(fx2.accountGUID, 62)
    check(kept(fj3)["club:FX:4"] and kept(fj3)["club:FX:4"].v == 62,
          "volume: (no GUID as he joined: the list read again at its next use, his membership kept)")
    for _, R in ipairs({fx1, fx2}) do R.online = false; players[R.name] = nil end

    for _, R in ipairs({fj, fs, fl, fn, fn2, fj2, fj3}) do R.online = false; players[R.name] = nil end
    clubs["FC"], clubs["FX"] = nil, nil
end

--------------------------------------------------------------------------
-- Edit Mode: each computer its own layout ("when I log on this PC, use
-- this edit mode preset"). The layouts, and which one each character has
-- on, are the account's (the game servers': editModeServer); the add-on's
-- saved settings are each computer's own
--------------------------------------------------------------------------
do
    editModeServer.layouts = {
        {layoutName = "j pace", layoutType = 1},
        {layoutName = "PC", layoutType = 1},
        {layoutName = "Laptop", layoutType = 1},
    }
    -- (the game's list: 1 Modern, 2 Classic, 3 Gamepad, 4 j pace, 5 PC, 6 Laptop)
    -- a login: the game loads its layouts, the world is entered (as a
    -- login), a moment; a /reload's UI (the add-on's own, or the player's):
    -- the world is entered as a reload's
    local function Login(P)
        P.EditModeLoad()
        P.Fire("PLAYER_ENTERING_WORLD", true, false)
        advance(2)
        return P
    end
    local function Reloaded(P)
        P.EditModeLoad()
        P.Fire("PLAYER_ENTERING_WORLD", false, true)
        advance(2)
        return P
    end
    -- logging out and in again on this computer (a character not logged in
    -- yet: beforeLoad)
    local function Relog(P, beforeLoad)
        LogOut(P)
        return makePlayer(P.name, {same = P, db = P.env.PacesQoLDB, beforeLoad = beforeLoad})
    end
    -- the player picking a layout in Edit Mode's menu, or making a new one
    local function Pick(P, i) P.Pick(i); advance(0.1) end
    local function Log(P) return table.concat(P.editModeLog, " ") end
    local function Note(P)
        return P.optionsPanel and P.optionsPanel.layoutNote and P.optionsPanel.layoutNote.text or ""
    end
    local gone = {}
    local function Keep(P) table.insert(gone, P); return P end

    -- the PC, nothing chosen for it yet: nothing switched
    local pc = Keep(Login(makePlayer("LayA")))
    check(Log(pc) == "apply:1" and not pc.reloadAsked and pc.ns.db.layoutHere == nil,
          "layout: nothing chosen for this computer: nothing switched as you log in")
    check(Note(pc):find("This computer: none yet", 1, true), "layout: (the options page says none is chosen)")
    -- a layout picked in Edit Mode: how to keep it for this computer, said once
    pc.printed = {}
    Pick(pc, 5)
    check(Printed(pc, "to have this computer switch to PC whenever you log in on it, type"),
          "layout: a layout picked in Edit Mode, this computer having none: it says how to keep it")
    pc.printed = {}
    Pick(pc, 4); Pick(pc, 5)
    check(not Printed(pc, "to have this computer"), "layout: (said once only)")
    -- kept for this computer
    pc.printed = {}
    pc.Slash("layout use")
    check(pc.ns.db.layoutHere and pc.ns.db.layoutHere.name == "PC" and Printed(pc, "PC is this computer's layout") and
          Note(pc):find("This computer: PC", 1, true),
          "layout: /pqol layout use keeps the layout on now for this computer")
    pc.printed = {}
    pc.Slash("layout")
    check(Printed(pc, "(this computer: PC; on now: PC;"), "layout: /pqol layout says which is this computer's and which is on")
    LogOut(pc)

    -- the laptop: the same character and layouts (the account's), its own
    -- saved settings. It comes up with the PC's layout on, nothing chosen
    -- there yet: left as it is; its options page's button keeps Laptop
    local lap = Keep(Login(makePlayer("LayA", {same = pc, db = {}})))
    check(lap.ns.db.layoutHere == nil and Log(lap) == "apply:5" and not lap.reloadAsked,
          "layout: the laptop comes up with the PC's layout (the account's), nothing chosen there: left as it is")
    Pick(lap, 6)
    local use
    for _, f in ipairs(lap.frames) do if f.kind == "Button" and f.text == "Use current" then use = f end end
    lap.printed = {}
    if use then RunScript(use, "OnClick") end
    check(lap.ns.db.layoutHere and lap.ns.db.layoutHere.name == "Laptop" and Note(lap):find("This computer: Laptop", 1, true) and
          Printed(lap, "Laptop is this computer's layout"),
          "layout: the options page's button keeps the layout on now for this computer")
    LogOut(lap)

    -- back on the PC, the laptop's layout on: switched to the PC's and the UI
    -- reloaded at once - nothing between the switch (the game applies it
    -- inside the call, as add-on code) and the reload
    local pc2 = Keep(Login(makePlayer("LayA", {same = lap, db = pc.env.PacesQoLDB})))
    check(Log(pc2) == "apply:6 set:addon:5 apply:5 reload",
          "layout: back on the PC with the laptop's layout on: switched to the PC's, the UI reloaded at once")
    local pc3 = Keep(Reloaded(Reload(pc2)))
    check(Log(pc3) == "apply:5" and Printed(pc3, "this computer's layout, PC, is on (switched as you logged in)") and
          pc3.ns.db.layoutSwitch == nil,
          "layout: after the reload the PC's is on, said so, nothing switched again")
    local pc4 = Keep(Login(Relog(pc3)))
    check(Log(pc4) == "apply:5" and not Printed(pc4, "Edit Mode"), "layout: (logging in with it on: nothing done, nothing said)")
    -- and the laptop again: switched to the laptop's
    LogOut(pc4)
    local lap2 = Keep(Login(makePlayer("LayA", {same = pc4, db = lap.env.PacesQoLDB})))
    check(Log(lap2) == "apply:5 set:addon:6 apply:6 reload", "layout: and on the laptop again: switched to the laptop's")
    local lap3 = Keep(Reloaded(Reload(lap2)))
    LogOut(lap3)

    -- another character on the PC, last played on the laptop: switched too
    local alt = Keep(Login(makePlayer("LayB", {db = pc.env.PacesQoLDB,
                                              beforeLoad = function(N) editModeServer.active[N.guid] = 6 end})))
    check(Log(alt) == "apply:6 set:addon:5 apply:5 reload", "layout: another character on the PC: switched to the PC's too")
    local alt2 = Keep(Reloaded(Reload(alt)))
    LogOut(alt2)

    -- a layout picked in Edit Mode that isn't this computer's: it lasts until
    -- logout - a /reload too - and it says so (once a session); the next
    -- login switches back
    local pc5 = Keep(Login(makePlayer("LayA", {same = lap3, db = pc.env.PacesQoLDB})))
    pc5 = Keep(Reloaded(Reload(pc5)))
    -- (a loading screen mid-session - an instance, a portal, a boat: the
    -- world entered again as neither a login nor a /reload)
    pc5.Fire("PLAYER_ENTERING_WORLD", false, false)
    advance(2)
    check(Log(pc5) == "apply:5" and not pc5.reloadAsked and pc5.ns.db.layoutDue == nil,
          "layout: a loading screen mid-session: nothing switched, no login's look made due")
    pc5.printed = {}
    Pick(pc5, 4)
    check(Printed(pc5, "j pace is on until you log out - this computer switches to PC as you log in") and
          pc5.ns.db.layoutHere.name == "PC",
          "layout: another layout picked in Edit Mode: on until you log out, and it says so")
    pc5.printed = {}
    Pick(pc5, 5); Pick(pc5, 4)
    check(not Printed(pc5, "until you log out"), "layout: (said once a session)")
    local pc6 = Keep(Reloaded(Reload(pc5)))
    check(Log(pc6) == "apply:4" and not pc6.reloadAsked and not Printed(pc6, "Edit Mode"),
          "layout: a /reload keeps the layout picked (on until you log out): nothing switched, no reload")
    pc6.printed = {}
    Pick(pc6, 5); Pick(pc6, 4)
    check(Printed(pc6, "j pace is on until you log out - this computer switches to PC as you log in"),
          "layout: (after a /reload, another layout picked: said too)")
    local pc7 = Keep(Login(Relog(pc6)))
    check(Log(pc7) == "apply:4 set:addon:5 apply:5 reload", "layout: (and the next login switches back)")
    pc7 = Keep(Reloaded(Reload(pc7)))
    -- a layout made new in Edit Mode (not through its menu), and the game's
    -- own switch at a spec change: said too
    pc7.printed = {}
    pc7.NewLayout("PC 2")
    advance(0.1)
    check(Printed(pc7, "PC 2 is on until you log out - this computer switches to PC as you log in"),
          "layout: a new layout made in Edit Mode: on until you log out, and it says so")
    local pc7b = Keep(Login(Relog(pc7)))
    check(Log(pc7b) == "apply:7 set:addon:5 apply:5 reload", "layout: (the next login switches back)")
    table.remove(editModeServer.layouts)
    pc7 = Keep(Reloaded(Reload(pc7b)))
    pc7.printed = {}
    editModeServer.active[pc7.guid] = 6
    pc7.Fire("PLAYER_SPECIALIZATION_CHANGED", "player")
    advance(0.1)
    check(Printed(pc7, "Laptop is on until you log out - this computer switches to PC as you log in"),
          "layout: the game switching at a spec change: said too")
    editModeServer.active[pc7.guid] = 5
    pc7.Fire("PLAYER_SPECIALIZATION_CHANGED", "player")
    advance(0.1)

    -- logging in in combat: nothing switched until the fight is over - a
    -- /reload meanwhile too
    editModeServer.active[pc7.guid] = 6
    local pc8 = Keep(Login(Relog(pc7, function(N) N.inCombat = true end)))
    check(Log(pc8) == "apply:6" and not pc8.reloadAsked, "layout: logging in in combat: nothing switched")
    pc8 = Keep(Reloaded(Reload(pc8, {beforeLoad = function(N) N.inCombat = true end})))
    check(Log(pc8) == "apply:6" and not pc8.reloadAsked, "layout: (a /reload still in combat: nothing switched)")
    pc8.inCombat = false
    pc8.Fire("PLAYER_REGEN_ENABLED")
    advance(2)
    check(Log(pc8) == "apply:6 set:addon:5 apply:5 reload", "layout: (switched once the fight is over, the login's look kept across the /reload)")

    -- a switch that doesn't last across its reload: not tried again (no
    -- reload after reload) until the layout is chosen again
    local pc9 = Keep(Reloaded(Reload(pc8, {beforeLoad = function(N) editModeServer.active[N.guid] = 6 end})))
    check(Log(pc9) == "apply:6" and not pc9.reloadAsked and Printed(pc9, "didn't last across the reload - not tried again"),
          "layout: a switch that didn't last across its reload: not tried again, and it says so")
    local pc10 = Keep(Login(Relog(pc9)))
    pc10.printed = {}
    pc10.Slash("layout")
    check(Log(pc10) == "apply:6" and not pc10.reloadAsked and Printed(pc10, "not switched to: the last switch didn't take") and
          Note(pc10):find("didn't take", 1, true),
          "layout: (nor at the next login; /pqol layout and the options page say why)")
    -- this computer's own layout picked (as it says to): nothing said; then
    -- another: no switch at login promised
    pc10.printed = {}
    Pick(pc10, 5)
    check(not Printed(pc10, "Edit Mode:"), "layout: this computer's own layout picked in Edit Mode: nothing said")
    Pick(pc10, 4)
    check(not Printed(pc10, "switches to PC as you log in") and
          Printed(pc10, "j pace is on - this computer's layout, PC, isn't switched to as you log in (its last switch didn't take)"),
          "layout: (another picked, the switch given up: no switch at login promised)")
    Pick(pc10, 5)
    pc10.Slash("layout use")
    Pick(pc10, 4)
    local pc10r = Keep(Reloaded(Reload(pc10)))
    check(Log(pc10r) == "apply:4" and not pc10r.reloadAsked,
          "layout: (chosen again after a given-up login, another picked, then a /reload: nothing switched)")
    editModeServer.active[pc10r.guid] = 6
    local pc11 = Keep(Login(Relog(pc10r)))
    check(Log(pc11) == "apply:6 set:addon:5 apply:5 reload", "layout: chosen again: switched again")
    local pc12 = Keep(Reloaded(Reload(pc11)))

    -- the game not taking the switch (it returns nothing): no reload, not tried again
    editModeServer.active[pc12.guid] = 6
    local pc13 = Keep(Login(Relog(pc12, function(N) N.editModeRefuses = true end)))
    check(Log(pc13) == "apply:6" and not pc13.reloadAsked and Printed(pc13, "the game didn't take the switch") and
          pc13.ns.db.layoutSwitch == nil,
          "layout: the game not taking the switch: no reload, and it says so")
    pc13.editModeRefuses = false
    Pick(pc13, 5)
    pc13.Slash("layout use")

    -- a game applying the layout after the call instead (as its own): no
    -- reload needed
    editModeServer.active[pc13.guid] = 6
    local pc14 = Keep(Login(Relog(pc13, function(N) N.editModeAsync = true end)))
    check(Log(pc14) == "apply:6 set:addon:5 apply:5" and not pc14.reloadAsked and
          Printed(pc14, "this computer's layout, PC, is on (switched as you logged in)") and pc14.ns.db.layoutSwitch == nil and
          not Printed(pc14, "until you log out"),
          "layout: the game applying the switch after the call, as its own: no reload")
    pc14.editModeAsync = false

    -- a preset as this computer's layout: kept by its number, said by its name
    Pick(pc14, 2)
    pc14.Slash("layout use")
    check(pc14.ns.db.layoutHere and pc14.ns.db.layoutHere.preset == 1, "layout: (a preset kept by its number)")
    editModeServer.active[pc14.guid] = 6
    local pc15 = Keep(Login(Relog(pc14)))
    check(Log(pc15) == "apply:6 set:addon:2 apply:2 reload", "layout: a preset as this computer's layout: switched to it")
    local pc16 = Keep(Reloaded(Reload(pc15)))
    check(Printed(pc16, "this computer's layout, Classic (Preset), is on (switched as you logged in)"),
          "layout: (and said, with its name)")
    -- (found by its number, not its name: the game's preset names follow the
    -- client's language)
    EM_PRESETS[2].layoutName = "Klassisch"
    editModeServer.active[pc16.guid] = 6
    local pc16b = Keep(Login(Relog(pc16)))
    check(Log(pc16b) == "apply:6 set:addon:2 apply:2 reload",
          "layout: (a preset found by its number: its name in the client's language changed)")
    pc16 = Keep(Reloaded(Reload(pc16b)))
    EM_PRESETS[2].layoutName = "Classic"
    pc16.EditModeLoad()
    Pick(pc16, 5)
    pc16.Slash("layout use")

    -- this computer's layout renamed or deleted (by name): nothing switched,
    -- said so - and a layout picked then promises no switch either
    editModeServer.layouts[2].layoutName = "Desk"
    editModeServer.active[pc16.guid] = 6
    local pc17 = Keep(Login(Relog(pc16)))
    check(Log(pc17) == "apply:6" and not pc17.reloadAsked and Printed(pc17, "this computer's layout, PC, isn't one this character has"),
          "layout: this computer's layout renamed or deleted: nothing switched, and it says so")
    pc17.printed = {}
    Pick(pc17, 4)
    check(not Printed(pc17, "until you log out") and Printed(pc17, "j pace is on - this computer's layout, PC, isn't one this character has"),
          "layout: (a layout picked then: no switch at login promised)")
    editModeServer.layouts[2].layoutName = "PC"
    pc17.EditModeLoad()

    -- a character's own layout as this computer's: another character, who
    -- has none of that name, isn't switched
    table.insert(editModeServer.layouts, {layoutName = "Mine", layoutType = 2, owner = pc17.guid})
    pc17.EditModeLoad()
    Pick(pc17, 7)
    pc17.Slash("layout use")
    check(pc17.ns.db.layoutHere and pc17.ns.db.layoutHere.name == "Mine" and pc17.ns.db.layoutHere.kind == 2,
          "layout: (a character's own layout kept, with its kind)")
    LogOut(pc17)
    local alt3 = Keep(Login(makePlayer("LayB", {same = alt2, db = pc17.env.PacesQoLDB})))
    check(not alt3.reloadAsked and Printed(alt3, "this computer's layout, Mine, isn't one this character has"),
          "layout: a character's own layout as this computer's: another character isn't switched, and is told")
    alt3.printed = {}
    Pick(alt3, 4)
    check(not Printed(alt3, "until you log out") and Printed(alt3, "this computer's layout, Mine, isn't one this character has"),
          "layout: (a layout that character picks: no switch at login promised)")
    LogOut(alt3)
    table.remove(editModeServer.layouts)
    local pc18 = Keep(Login(makePlayer("LayA", {same = pc17, db = pc17.env.PacesQoLDB})))
    Pick(pc18, 5)
    pc18.Slash("layout use")

    -- switched off: nothing switched at login, and the options page says so;
    -- switched on mid-session: nothing until the next login
    pc18.Slash("layout off")
    check(Note(pc18):find("This computer: PC - not switched to while this is off", 1, true),
          "layout: switched off: the options page says it isn't switched to")
    editModeServer.active[pc18.guid] = 6
    local pc19 = Keep(Login(Relog(pc18)))
    check(Log(pc19) == "apply:6" and not pc19.reloadAsked, "layout: switched off: nothing switched as you log in")
    pc19.printed = {}
    Pick(pc19, 4)
    check(not Printed(pc19, "as you log in"), "layout: (switched off: a layout picked promises no switch at login)")
    Pick(pc19, 6)
    pc19.Slash("layout on")
    check(Note(pc19):find("every character is switched to it as it logs in here", 1, true),
          "layout: (switched on again: the options page says it is switched to)")
    pc19.Fire("EDIT_MODE_LAYOUTS_UPDATED", pc19.env.C_EditMode.GetLayouts(), false)
    pc19.Fire("PLAYER_REGEN_ENABLED")
    advance(2)
    check(Log(pc19) == "apply:6 set:player:4 apply:4 set:player:6 apply:6 apply:6" and not pc19.reloadAsked,
          "layout: (switched on mid-session: nothing until the next login)")
    pc19 = Keep(Reloaded(Reload(pc19)))
    check(Log(pc19) == "apply:6" and not pc19.reloadAsked,
          "layout: (switched on mid-session, then a /reload: still nothing until the next login)")
    local pc20 = Keep(Login(Relog(pc19)))
    check(Log(pc20) == "apply:6 set:addon:5 apply:5 reload", "layout: (and at the next login, switched)")
    local pc21 = Keep(Reloaded(Reload(pc20)))

    -- forgotten: nothing switched
    pc21.Slash("layout forget")
    editModeServer.active[pc21.guid] = 6
    local pc22 = Keep(Login(Relog(pc21)))
    check(pc22.ns.db.layoutHere == nil and Log(pc22) == "apply:6" and not pc22.reloadAsked,
          "layout: /pqol layout forget: nothing switched as you log in")

    -- Edit Mode off by a game rule: nothing switched
    Pick(pc22, 5); pc22.Slash("layout use")
    editModeServer.active[pc22.guid] = 6
    ENUM.GameRule = {EditModeDisabled = 9}
    local pc23 = Keep(Login(Relog(pc22, function(N, env)
        env.C_GameRules = {IsGameRuleActive = function(rule) return rule == 9 end}
    end)))
    check(Log(pc23) == "apply:6" and not pc23.reloadAsked, "layout: Edit Mode off by a game rule: nothing switched")
    ENUM.GameRule = nil

    -- the layouts known before the world is entered: nothing until it is
    Pick(pc23, 5)
    editModeServer.active[pc23.guid] = 6
    local pc24 = Keep(Relog(pc23))
    pc24.EditModeLoad()
    advance(5)
    check(Log(pc24) == "apply:6" and not pc24.reloadAsked, "layout: (nothing switched before the world is entered)")
    pc24.Fire("PLAYER_ENTERING_WORLD", true, false)
    advance(2)
    check(Log(pc24) == "apply:6 set:addon:5 apply:5 reload", "layout: (switched once it is)")
    local pc25 = Keep(Reloaded(Reload(pc24)))

    -- the world entered before the game has its layouts: switched once it has
    editModeServer.active[pc25.guid] = 6
    local pc25b = Keep(Relog(pc25))
    pc25b.Fire("PLAYER_ENTERING_WORLD", true, false)
    advance(5)
    check(Log(pc25b) == "" and not pc25b.reloadAsked, "layout: (nothing before the game has its layouts)")
    pc25b.EditModeLoad()
    advance(2)
    check(Log(pc25b) == "apply:6 set:addon:5 apply:5 reload", "layout: the world entered before the game has its layouts: switched once it has")
    pc25 = Keep(Reloaded(Reload(pc25b)))

    -- Edit Mode open as it would switch: left to the player
    editModeServer.active[pc25.guid] = 6
    local pc25c = Keep(Relog(pc25))
    pc25c.env.EditModeManagerFrame:Show()
    Login(pc25c)
    check(Log(pc25c) == "apply:6" and not pc25c.reloadAsked, "layout: Edit Mode open as it would switch: left to the player")
    -- (and it stays left to them: another layout picked in it, Edit Mode
    -- closed, a fight's end later - nothing switched, no reload)
    Pick(pc25c, 4)
    advance(2)
    pc25c.env.EditModeManagerFrame:Hide()
    pc25c.Fire("PLAYER_REGEN_ENABLED")
    advance(2)
    check(Log(pc25c) == "apply:6 set:player:4 apply:4" and not pc25c.reloadAsked,
          "layout: (a layout picked in it stays once Edit Mode is closed: not switched later)")
    Pick(pc25c, 5)
    pc25 = Keep(Login(Relog(pc25c)))

    -- a switch marker from long ago (its reload never came): not taken as
    -- one just made - switched as usual
    editModeServer.active[pc25.guid] = 6
    pc25.ns.db.layoutSwitch = {name = "PC", at = math.floor(clock) - 1000}
    local pc26 = Keep(Login(Relog(pc25)))
    check(Log(pc26) == "apply:6 set:addon:5 apply:5 reload" and pc26.ns.db.layoutFailed == nil,
          "layout: a switch marker from long ago isn't taken as one just made: switched as usual")
    local pc27 = Keep(Reloaded(Reload(pc26)))
    -- (one from long ago seen at a /reload - its reload's look held up past
    -- it - isn't taken as one just made either: nothing given up)
    Pick(pc27, 6)
    pc27.ns.db.layoutSwitch = {name = "PC", at = math.floor(clock) - 1000}
    pc27 = Keep(Reloaded(Reload(pc27)))
    check(Log(pc27) == "apply:6" and not pc27.reloadAsked and pc27.ns.db.layoutFailed == nil and
          not Printed(pc27, "Edit Mode"),
          "layout: (a switch marker from long ago at a /reload: nothing given up, nothing said)")
    Pick(pc27, 5)

    -- an account's layout and a character's own with the same name: the kept
    -- one's own kind first; a character without one of its kind: the other
    table.insert(editModeServer.layouts, {layoutName = "PC", layoutType = 2, owner = pc27.guid})
    pc27.EditModeLoad()
    Pick(pc27, 7)
    pc27.Slash("layout use")
    check(pc27.ns.db.layoutHere.kind == 2, "layout: (this character's own PC kept)")
    Pick(pc27, 5)
    local pc28 = Keep(Login(Relog(pc27)))
    check(Log(pc28) == "apply:5 set:addon:7 apply:7 reload",
          "layout: an account's and a character's layout of one name: the kept one's own kind is switched to")
    local pc29 = Keep(Reloaded(Reload(pc28)))
    LogOut(pc29)
    local alt4 = Keep(Login(makePlayer("LayB", {same = alt3, db = pc29.env.PacesQoLDB,
                                               beforeLoad = function(N) editModeServer.active[N.guid] = 6 end})))
    check(Log(alt4) == "apply:6 set:addon:5 apply:5 reload",
          "layout: another character's own layout as this computer's, the account's of that name: that one switched to")
    LogOut(Keep(Reloaded(Reload(alt4))))
    pc29 = Keep(Login(makePlayer("LayA", {same = pc29, db = pc29.env.PacesQoLDB})))
    table.remove(editModeServer.layouts)
    pc29.EditModeLoad()
    Pick(pc29, 5)
    pc29.Slash("layout use")

    -- the game's call failing outright: an error noted (/pqol status), no
    -- reload, tried again next time (not given up on)
    editModeServer.active[pc29.guid] = 6
    local pc30 = Keep(Login(Relog(pc29, function(N)
        N.env.C_EditMode.SetActiveLayout = function() error("no such layout") end
    end)))
    local errs = 0
    for _, e in ipairs(pc30.ns.errors) do if e:find("^layout:") then errs = errs + 1 end end
    check(errs == 1 and not pc30.reloadAsked and pc30.ns.db.layoutFailed == nil and pc30.ns.db.layoutSwitch == nil,
          "layout: the game's call failing: noted as an error, no reload, not given up on")

    -- a session ending without saving just after the add-on's switch and
    -- its reload (a crash, a disconnect): the saved settings still have the
    -- switch's marker. A login isn't that switch's reload: nothing taken as
    -- its own, nothing given up on
    do
        local function copy(t)
            if type(t) ~= "table" then return t end
            local o = {}
            for k, v in pairs(t) do o[k] = copy(v) end
            return o
        end
        local function Crash(P)
            for _, t in ipairs(timers) do if t.owner == P then t.cancelled = true end end
            P.frames = {}
        end
        LogOut(pc30)
        local function SwitchedThenCrashed(from)
            editModeServer.active[from.guid] = 6
            local a = Keep(Login(makePlayer("LayA", {same = from, db = from.env.PacesQoLDB})))
            local r = Reload(a)
            local file = copy(r.env.PacesQoLDB) -- (as the reload wrote it)
            r = Keep(Reloaded(r))
            Crash(r)
            advance(60)
            return r, file
        end
        local la, file = SwitchedThenCrashed(pc30)
        local same = Keep(Login(makePlayer("LayA", {same = la, db = copy(file)})))
        check(Log(same) == "apply:5" and not Printed(same, "Edit Mode"),
              "layout: a crash just after the add-on's switch: that character logging in again - nothing done, nothing said")
        LogOut(same)
        local lb = Keep(Login(makePlayer("LayB", {same = alt4, db = file,
                                                 beforeLoad = function(N) editModeServer.active[N.guid] = 6 end})))
        check(Log(lb) == "apply:6 set:addon:5 apply:5 reload" and lb.ns.db.layoutFailed == nil,
              "layout: (another character logging in soon after: switched, nothing given up)")
        local lb2 = Keep(Reloaded(Reload(lb)))
        LogOut(lb2)
        local _, file2 = SwitchedThenCrashed(same)
        local lb3 = Keep(Login(makePlayer("LayB", {same = lb2, db = file2,
                                                  beforeLoad = function(N) editModeServer.active[N.guid] = 6; N.inCombat = true end})))
        lb3 = Keep(Reloaded(Reload(lb3, {beforeLoad = function(N) N.inCombat = true end})))
        lb3.inCombat = false
        lb3.Fire("PLAYER_REGEN_ENABLED")
        advance(2)
        check(Log(lb3) == "apply:6 set:addon:5 apply:5 reload" and lb3.ns.db.layoutFailed == nil,
              "layout: (nor when its login's look waits for a fight, across a /reload)")
        LogOut(Keep(Reloaded(Reload(lb3))))
    end

    for _, R in ipairs(gone) do R.online = false end
    players["LayA"], players["LayB"] = nil, nil
    editModeServer.layouts, editModeServer.active = {}, {}
end

--------------------------------------------------------------------------
-- gold finder: recipes and merchants remembered, the auction house read
-- (a full scan, "Price my items", what the player browses), and what is
-- worked out from it for the window's four tabs. The window itself
-- (GoldUI.lua) has its own section.
--------------------------------------------------------------------------
do
    local gone = {}
    local function GP(name, opts)
        -- (as in the game: WoW Forever gives an empty realm name)
        opts = opts or {}
        local before = opts.beforeLoad
        opts.beforeLoad = function(P, env)
            if P.noRealm == nil then P.noRealm = "" end
            if before then before(P, env) end
        end
        local P = makePlayer(name, opts)
        table.insert(gone, P)
        return P
    end
    local DAYSEC = 86400
    -- what the tests trade in
    local ITEMS = {
        [14047] = {name = "Runecloth", stack = 20, sell = 400, class = 7, reagent = true},
        [14048] = {name = "Bolt of Runecloth", stack = 20, sell = 1600, class = 7, reagent = true},
        [14341] = {name = "Rune Thread", stack = 20, sell = 1250, class = 7, reagent = true},
        [8170] = {name = "Rugged Leather", stack = 20, sell = 500, class = 7, reagent = true},
        [14046] = {name = "Runecloth Bag", stack = 1, sell = 20000, class = 1},
        [2589] = {name = "Linen Cloth", stack = 20, sell = 13, class = 7, reagent = true},
        [3000] = {name = "Odd Ore", stack = 20, sell = 10, class = 7},
        [7000] = {name = "Linen Scrap", stack = 20, sell = 1, class = 7},
        [13856] = {name = "Runecloth Belt", quality = 2, ilvl = 51, sell = 5000, class = 4, bind = 2},
        [20001] = {name = "Soulbound Robe", quality = 2, ilvl = 51, sell = 3000, class = 4, bind = 1},
        [15000] = {name = "Test Sword", quality = 2, ilvl = 30, sell = 4000, class = 2, bind = 2},
        [16000] = {name = "Blue Helm", quality = 3, ilvl = 40, sell = 9000, class = 4, bind = 2},
        [17000] = {name = "Green Gloves", quality = 2, ilvl = 38, sell = 2500, class = 4, bind = 2},
        [30000] = {name = "Quest Thing", class = 12},
        [4000] = {name = "Rare Recipe", stack = 1, sell = 500, class = 9},
        [2320] = {name = "Coarse Thread", stack = 20, sell = 2, class = 7, reagent = true},
        [10940] = {name = "Strange Dust", stack = 20, class = 7, reagent = true},
        [10938] = {name = "Lesser Magic Essence", stack = 10, class = 7, reagent = true},
        [10939] = {name = "Greater Magic Essence", stack = 10, class = 7, reagent = true},
        [10998] = {name = "Lesser Astral Essence", stack = 10, class = 7, reagent = true},
        [11082] = {name = "Greater Astral Essence", stack = 10, class = 7, reagent = true},
        [11176] = {name = "Dream Dust", stack = 20, class = 7, reagent = true},
        [16202] = {name = "Lesser Eternal Essence", stack = 10, class = 7, reagent = true},
        [16203] = {name = "Greater Eternal Essence", stack = 10, class = 7, reagent = true},
        [14343] = {name = "Small Brilliant Shard", stack = 20, class = 7, reagent = true},
        [11139] = {name = "Large Glowing Shard", stack = 20, class = 7, reagent = true},
    }
    local function Stock(P)
        for id, it in pairs(ITEMS) do
            local c = {}
            for k, v in pairs(it) do c[k] = v end
            P.items[id] = c
        end
        return P
    end
    local function Book(P, key)
        local b = P.ns.db.goldBook
        return b and b[key or (P.realm .. "-" .. P.faction)]
    end
    local function Rec(P, key, book)
        local b = Book(P, book)
        return b and b.items[key]
    end
    local function Days(P, n) P.timeShift = (P.timeShift or 0) + n * DAYSEC end
    local function Shift(P, sec) P.timeShift = (P.timeShift or 0) + sec end
    -- the player searching for a commodity themselves: its listings {{unit price, units}, ...}
    local function Listed(P, id, points, full)
        local rows = {full = full}
        for _, p in ipairs(points) do rows[#rows + 1] = {quantity = p[2], unitPrice = p[1], numOwnerItems = 0} end
        P.ah.results[id] = rows
        P.Fire("COMMODITY_SEARCH_RESULTS_UPDATED", id)
    end
    -- ... and for a piece of gear: its buyouts {{buyout, suffix}, ...}
    local function ListedGear(P, id, points)
        local rows = {}
        for _, p in ipairs(points) do
            rows[#rows + 1] = {quantity = 1, buyoutAmount = p[1], itemKey = {itemID = id, itemSuffix = p[2] or 0}}
        end
        P.ah.results[id] = rows
        P.Fire("ITEM_SEARCH_RESULTS_UPDATED", {itemID = id, itemSuffix = 0})
    end
    -- the same listings seen on `days` days in a row, ending yesterday
    local function History(P, id, points, days)
        for _ = 1, days do
            Listed(P, id, points)
            Days(P, 1)
        end
    end
    -- the Bargains pass, run again
    local function Analyse(P)
        P.Slash("gold cut " .. P.ns.db.goldCut)
        advance(0.2)
        return P.ns.Gold.BargainRows()
    end
    local function Recipe(P, id, name, out, reagents, o)
        o = o or {}
        local slots = {}
        for _, r in ipairs(reagents) do
            slots[#slots + 1] = {reagentType = 1, required = true, quantityRequired = r[2], reagents = {{itemID = r[1]}}}
        end
        P.trade.recipes[id] = {
            info = {recipeID = id, name = name, learned = o.learned ~= false, isEnchantingRecipe = o.enchant or false},
            sch = {outputItemID = out, quantityMin = o.min or 1, quantityMax = o.max or o.min or 1,
                   recipeType = o.enchant and 3 or 1, reagentSlotSchematics = slots},
            cooldown = o.cooldown, throw = o.throw}
        table.insert(P.trade.ids, id)
    end
    -- the character's own profession window, opened
    local function OpenTrade(P, prof, skill)
        P.trade.prof = {professionID = 197, professionName = prof, skillLevel = skill or 150, maxSkillLevel = 300}
        P.Fire("TRADE_SKILL_SHOW")
        advance(1)
    end
    local function Recipes(P, prof)
        local ch = P.ns.db.goldRecipes and P.ns.db.goldRecipes[P.guid]
        return ch and ch.profs[prof] and ch.profs[prof].list, ch
    end
    local function Find(rows, field, value)
        for _, row in ipairs(rows) do if row[field] == value then return row end end
    end
    local function Row(id, count, buyout, o)
        local r = {id = id, count = count, buyout = buyout, owner = "Someone"}
        for k, v in pairs(o or {}) do r[k] = v end
        return r
    end
    local function Link(id, suffix) return ("|cff1eff00|Hitem:%d:0:0:0:0:0:%d:0|h[Thing]|h|r"):format(id, suffix or 0) end
    -- a full scan from the button to the end
    local function Scan(P)
        local ok, why = P.ns.Gold.StartScan()
        advance(5)
        return ok, why
    end
    local function Total(t)
        local n = 0
        for _, v in pairs(t) do n = n + v end
        return n
    end
    local function Max(t)
        local m = 0
        for _, v in pairs(t) do if v > m then m = v end end
        return m
    end
    local function CountKeys(t)
        local n = 0
        for _ in pairs(t) do n = n + 1 end
        return n
    end

    ----------------------------------------------------------------------
    -- the basics
    ----------------------------------------------------------------------
    local A = Stock(GP("GoldA"))
    local G = A.ns.Gold
    check(A.ns.db.gold == true and A.ns.db.goldScanOnOpen == false and A.ns.db.goldCut == 5,
          "gold: on by default, no scan on opening, a 5% cut")
    check(G.Plain(5) == 5 and G.Plain("5") == nil and G.Plain({__secret = true}) == nil and G.Plain(nil) == nil and
          G.PlainStr("a") == "a" and G.PlainStr("") == nil and G.PlainStr({__secret = true}) == nil,
          "gold: only plain numbers and strings are used (a secret value counts as missing)")
    check(G.Money(12345) == "1g 23s 45c" and G.Money(0) == "0c" and G.Money(10000) == "1g" and G.Money(105.9) == "1s 5c" and
          G.Money(-250) == "-2s 50c" and G.Count(3210) == "3,210" and G.Count(1234567) == "1,234,567" and G.Count(12) == "12",
          "gold: money as g/s/c on whole copper, counts with thousands")
    check(G.PriceState("crafts"):find("Go to an auctioneer, open the auction house, then press Scan (everything, once per 15 minutes) or Price my items (quick).", 1, true) and
          G.Empty("crafts") == "Open each profession window once on each character - that's how I learn your recipes.",
          "gold: nothing known yet: the header and the Crafts tab say what to do")

    ----------------------------------------------------------------------
    -- recipes: read from the character's own profession window
    ----------------------------------------------------------------------
    Recipe(A, 1, "Runecloth Bag", 14046, {{14048, 5}, {8170, 2}, {14341, 1}}, {cooldown = 60})
    Recipe(A, 2, "Bolt of Runecloth", 14048, {{14047, 5}})
    Recipe(A, 3, "Enchant Bracer", nil, {{10940, 2}}, {enchant = true})
    Recipe(A, 4, "Honor Cloak", 13856, {{14048, 3}})
    table.insert(A.trade.recipes[4].sch.reagentSlotSchematics, 1,
                 {reagentType = 1, required = true, quantityRequired = 10, reagents = {{currencyID = 5}}})
    table.insert(A.trade.recipes[4].sch.reagentSlotSchematics,
                 {reagentType = 2, required = false, quantityRequired = 1, reagents = {{itemID = 3000}}})
    Recipe(A, 5, "Broken", 3000, {{14047, 1}}, {throw = true})
    Recipe(A, 6, "Not Learned", 3000, {{14047, 1}}, {learned = false})
    Recipe(A, 7, "Scraps", 7000, {{2589, 6}}, {min = 2, max = 4})
    for i = 100, 199 do Recipe(A, i, "Filler " .. i, 40000 + i, {{14047, 1}}) end

    A.trade.linked = true
    OpenTrade(A, "Tailoring")
    check(A.ns.db.goldRecipes == nil, "gold recipes: a linked profession window isn't read")
    A.trade.linked, A.trade.guild = false, true
    OpenTrade(A, "Tailoring")
    A.trade.guild, A.trade.npc = false, true
    OpenTrade(A, "Tailoring")
    check(A.ns.db.goldRecipes == nil, "gold recipes: nor a guild's, nor an NPC's crafting window")
    A.trade.npc, A.trade.ready = false, false
    OpenTrade(A, "Tailoring")
    check(A.ns.db.goldRecipes == nil, "gold recipes: nor one that isn't ready")
    A.trade.ready = true
    -- the first event of an opening window: nothing learned listed yet
    local ids = A.trade.ids
    A.trade.ids = {6}
    OpenTrade(A, "Tailoring")
    check(A.ns.db.goldRecipes == nil, "gold recipes: the empty first list of an opening window is ignored")
    A.trade.ids = ids
    -- the window closing while it is being read
    A.trade.onRead = function(id) if id == 150 then A.trade.ready = false end end
    OpenTrade(A, "Tailoring")
    check(A.ns.db.goldRecipes == nil, "gold recipes: a read interrupted by the window closing changes nothing")
    A.trade.onRead, A.trade.ready = nil, true
    A.recipeReads = {}
    OpenTrade(A, "Tailoring", 150)
    local list, ch = Recipes(A, "Tailoring")
    check(list and ch.name == "GoldA" and ch.realm == "Forever" and ch.faction == "Alliance" and
          ch.profs.Tailoring.skill == 150 and ch.profs.Tailoring.max == 300,
          "gold recipes: the character's own window is read: who, where, the skill")
    check(list and list[1] and list[1].n == "Runecloth Bag" and list[1].o == 14046 and list[1].a == 1 and list[1].b == 1 and
          list[1].r == "14048:5,8170:2,14341:1" and list[1].c == true and list[1].e == nil,
          "gold recipes: a recipe: name, output, quantities, reagents, the cooldown mark")
    check(list and list[7] and list[7].a == 2 and list[7].b == 4 and list[7].r == "2589:6", "gold recipes: an output of 2 to 4")
    check(list and list[3] and list[3].e == true and list[3].o == nil and list[3].r == "10940:2",
          "gold recipes: an enchant is kept, marked as one")
    check(list and list[4] and list[4].r == "14048:3", "gold recipes: a currency slot and an optional slot are left out")
    check(list and list[5] == nil and list[6] == nil and list[150] ~= nil,
          "gold recipes: a recipe that throws and one not learned are skipped, the rest read")
    do
        local perTick, ticks = {}, 0
        for _, t in ipairs(A.recipeReads) do
            if not perTick[t] then ticks = ticks + 1 end
            perTick[t] = (perTick[t] or 0) + 1
        end
        check(#A.recipeReads == 107 and Max(perTick) == 40 and ticks == 3,
              "gold recipes: read 40 at a time, a timer tick apart (" .. #A.recipeReads .. " reads, " .. ticks .. " ticks)")
    end
    -- read again: the list is replaced, a cooldown once seen stays
    A.trade.ids = {1, 2, 3, 4, 7}
    A.trade.recipes[1].cooldown = nil
    A.trade.prof.skillLevel = {__secret = true}
    A.Fire("TRADE_SKILL_LIST_UPDATE")
    advance(1)
    list, ch = Recipes(A, "Tailoring")
    check(list and list[150] == nil and list[2] ~= nil and list[1].c == true,
          "gold recipes: read again: the list is replaced (what's gone is gone), the cooldown mark kept")
    check(ch.profs.Tailoring.skill == nil and ch.profs.Tailoring.max == 300, "gold recipes: a skill that can't be read isn't saved")
    -- WoW Forever gives no realm name, in the world as at login (an empty
    -- one; none at all is taken the same way). 1.4.0 read that as "not yet":
    -- nothing was recorded, and the window's every refresh threw (Gold.lua:
    -- "attempt to concatenate local 'realm'"), so Scan did nothing
    for _, how in ipairs({"", true}) do
        local what = how == "" and "an empty realm name" or "no realm name at all"
        local N = GP(how == "" and "GoldEmptyRealm" or "GoldNoRealm", {beforeLoad = function(N) N.noRealm = how end})
        Recipe(N, 1, "Runecloth Bag", 14046, {{14048, 5}})
        OpenTrade(N, "Tailoring")
        N.merchant = {{id = 14341, price = 5000}}
        N.Fire("MERCHANT_SHOW")
        advance(1)
        N.OpenAH()
        local okState, st = pcall(N.ns.Gold.State)
        N.ns.Gold.Open()
        advance(1)
        local ok, why = N.ns.Gold.StartScan()
        local key = "Forever-" .. N.faction
        local ch = N.ns.db.goldRecipes and N.ns.db.goldRecipes[N.guid]
        check(okState and type(st) == "table" and st.scan and st.scan.enabled == true and #N.ns.errors == 0,
              "gold (" .. what .. "): the window's state is worked out without an error, and Scan is enabled")
        check(ok == true and why == nil and N.ns.Gold.State().state == "asked",
              "gold (" .. what .. "): Scan asks the game for the whole list")
        check(type(ch) == "table" and ch.realm == "Forever" and ch.profs.Tailoring ~= nil,
              "gold (" .. what .. "): the character's recipes are recorded, as of a game without realms")
        check(type(N.ns.db.goldVendors) == "table" and next(N.ns.db.goldVendors) ~= nil,
              "gold (" .. what .. "): a merchant's prices are recorded")
        check(type(N.ns.db.goldBook) == "table" and type(N.ns.db.goldBook[key]) == "table" and
              N.ns.db.goldBook[key].fullAsked ~= nil and N.ns.Gold.PriceState("crafts") ~= "Can't tell which realm this is yet",
              "gold (" .. what .. "): prices go into one book for the whole game, per faction")
    end

    ----------------------------------------------------------------------
    -- merchants
    ----------------------------------------------------------------------
    A.npcName = "Trader Bob"
    A.merchant = {{id = 14341, price = 5000}, {id = 2320, price = 50, stack = 5}, {id = 7000, price = 101, stack = 2},
                  {id = 3000, price = 100, ext = true}, {id = 2589, price = 0}, {id = 4000, price = 300, avail = 2},
                  {id = 8170, nothing = true}, {id = 14047, price = 100, purchasable = false}}
    A.Fire("MERCHANT_SHOW")
    A.Fire("MERCHANT_UPDATE")
    advance(0.5)
    local V = A.ns.db.goldVendors
    check(V and V[14341] and V[14341].p == 5000 and V[14341].w == "Trader Bob" and V[14341].z == "Elwynn Forest" and
          V[14341].lim == nil, "gold merchants: a price, who sells it and where")
    check(V and V[2320].p == 10 and V[7000].p == 51, "gold merchants: the price of one, rounded up (101 for 2 = 51)")
    check(V and V[3000] == nil and V[2589] == nil and V[8170] == nil and V[14047] == nil,
          "gold merchants: no gold price, an extended cost, nothing readable, not for sale: not recorded")
    check(V and V[4000].lim == true, "gold merchants: limited supply is marked")
    A.npcName = nil
    A.merchant = {{id = 14341, price = 4500}, {id = 4000, price = 300}}
    A.Fire("MERCHANT_SHOW")
    advance(0.5)
    check(V[14341].p == 4500 and V[14341].w == "a vendor", "gold merchants: a lower price replaces it; a merchant with no name is \"a vendor\"")
    check(V[4000].p == 300 and V[4000].lim == nil, "gold merchants: an unlimited seller replaces a limited one at the same price")
    A.npcName = "Pricey"
    A.merchant = {{id = 14341, price = 5000}, {id = 4000, price = 300, avail = 1}}
    A.Fire("MERCHANT_SHOW")
    advance(0.5)
    check(V[14341].p == 4500 and V[14341].w == "a vendor" and V[4000].lim == nil,
          "gold merchants: a higher price, or a limited seller at the same one, doesn't replace it")
    Days(A, 31)
    A.Fire("MERCHANT_SHOW")
    advance(0.5)
    check(V[14341].p == 5000 and V[14341].w == "Pricey", "gold merchants: a month-old price is overwritten")
    Days(A, -31)

    ----------------------------------------------------------------------
    -- the full scan
    ----------------------------------------------------------------------
    local B = Stock(GP("GoldB"))
    local GB = B.ns.Gold
    local function ScanRows()
        local rows = {
            Row(14047, 20, 20000), Row(14047, 10, 12000), Row(14047, 5, 7500), Row(14047, 1, 999),
            Row(14047, 5, 0),                                   -- bid only
            Row(14047, 20, 100, {owner = "GoldB"}),             -- ours
            Row(14047, 20, 100, {owner = "", ownerFull = "GoldB-Forever"}),
            Row(14047, 20, 100, {throw = true}),
            Row(14047, 20, 100, {secret = true}),
            Row(2589, 3, 100, {owner = false}),                 -- (a nil owner: 34 each, rounded up)
            Row(15000, 1, 50000, {link = Link(15000, 1200)}),
            Row(15000, 1, 45000, {link = Link(15000, 0)}),
            Row(15000, 1, 40000, {lateLink = Link(15000, 800)}),
            Row(31337, 1, 5),                                   -- no such item
            Row(8170, 4, 2000),
        }
        for i = 1, 600 do rows[#rows + 1] = Row(50000 + i, 1, 100 + i) end
        return rows
    end
    B.noSuchItem[31337] = true
    B.ah.rows = ScanRows()
    do
        local ok, why = GB.StartScan()
        check(not ok and why == "open the auction house first" and GB.State().scan.tip == "Open the auction house first" and
              not GB.State().scan.enabled, "gold scan: not without the auction house open")
    end
    B.OpenAH()
    check(GB.State().scan.enabled and GB.State().scan.label == "Scan" and GB.State().check.enabled and
          GB.State().check.label == "Price my items" and
          GB.PriceState("crafts") == "Press Scan (everything, once per 15 minutes) or Price my items (quick).",
          "gold scan: the auction house open: both buttons ready")
    check(GB.StartScan() == true and GB.State().state == "asked" and Book(B).fullAsked == B.env.time() and B.ah.asked == 1,
          "gold scan: the list is asked for, and the time noted")
    do
        local ok, why = GB.StartCheck()
        local st = GB.State()
        check(not ok and why == "wait for the scan to finish" and not st.check.enabled and st.check.tip == "Wait for the scan to finish" and
              not st.scan.enabled, "gold scan: a price check can't start while a scan runs")
    end
    B.ah.infoReads = {}
    advance(1.5)
    check(GB.State().state == "reading" and Total(B.ah.infoReads) == 615 and Max(B.ah.infoReads) == 250 and
          CountKeys(B.ah.infoReads) == 3, "gold scan: every row read, 250 a timer tick")
    check(Book(B).items[14047] == nil and Book(B).full == nil, "gold scan: (nothing written until the last row is in)")
    B.ah.linksReady = true
    advance(2.5)
    check(GB.State().state == "idle" and GB.State().message == "Scan finished: 606 items." and Book(B).full == B.env.time(),
          "gold scan: finished: " .. tostring(GB.State().message))
    do
        local r = Rec(B, 14047)
        local today = math.floor(B.env.time() / DAYSEC)
        check(r and r.m == 999 and r.q == 36 and r.v == 1000 and r.l == "999:1,1000:20,1200:10,1500:5" and r.s == "f" and
              r.h == today .. ":1000+" and r.p == nil and r.t == B.env.time(),
              "gold scan: lowest, units, typical price, price points, today's history - bid-only, own, unreadable rows left out")
        check(Rec(B, 2589) and Rec(B, 2589).m == 34 and Rec(B, 2589).q == 3 and Rec(B, 2589).l == nil and
              Rec(B, 2589).h == today .. ":34", "gold scan: a unit price rounds up; one price point needs no list; under 5 units no \"+\"")
        check(Rec(B, "15000:1200") and Rec(B, "15000:1200").m == 50000 and Rec(B, 15000) and Rec(B, 15000).m == 45000 and
              Rec(B, 15000).q == 1, "gold scan: gear is kept by its random suffix")
        check(Rec(B, "15000:800") and Rec(B, "15000:800").m == 40000,
              "gold scan: a gear row with no link yet is read again and moved to its suffix")
        check(Rec(B, 31337) == nil and Rec(B, 50600) and Rec(B, 50600).m == 700, "gold scan: an item that doesn't exist is left out")
        check(#B.ns.errors == 0, "gold scan: no errors")
        -- the Bargains pass that follows, and the item data it asks for
        local _, meta = GB.BargainRows()
        local asks = {}
        for _, a in ipairs(B.itemAsks) do asks[a.tick] = (asks[a.tick] or 0) + 1 end
        check(meta.loading == 600 and Max(B.itemReads) <= 260 and Total(B.itemReads) >= 600,
              "gold bargains: worked out 250 items a tick; items whose data hasn't loaded are counted (" .. meta.loading .. " loading)")
        check(#B.itemAsks > 20 and Max(asks) == 20, "gold items: at most 20 items asked for per tick (" .. #B.itemAsks .. " so far)")
        advance(5)
        local once = {}
        for _, a in ipairs(B.itemAsks) do once[a.id] = (once[a.id] or 0) + 1 end
        -- (the 600, and the gear row that had no link yet)
        check(#B.itemAsks == 601 and Max(once) == 1 and once[15000] == 1 and once[50600] == 1,
              "gold items: each item asked for once (" .. #B.itemAsks .. ")")
    end
    -- the 15 minutes
    do
        local ok, why = GB.StartScan()
        check(not ok and why == "a scan can be asked again in 15 min" and GB.State().scan.label == "Scan (in 15 min)" and
              not GB.State().scan.enabled and B.ah.asked == 1, "gold scan: asked again at once: not for 15 minutes")
        Shift(B, 600)
        check(GB.State().scan.label == "Scan (in 5 min)", "gold scan: the button counts down (" .. GB.State().scan.label .. ")")
        Shift(B, 300)
        check(GB.State().scan.label == "Scan" and GB.State().scan.enabled, "gold scan: after 15 minutes it may be asked again")
    end
    -- sold out: what the book knew and the next scan doesn't list
    advance(61)
    B.ah.rows = {Row(14047, 20, 20000), Row(14047, 2, 2000, {owner = "Other-Forever"})}
    Scan(B)
    do
        local r, l = Rec(B, 8170), Rec(B, 14047)
        local price, why = GB.Now(8170)
        check(r and r.q == 0 and r.m == 500 and r.l == nil and r.s == "f" and r.t == Book(B).full and price == nil and
              why == "none listed", "gold scan: an item the next scan doesn't list is sold out: none listed, its last price kept")
        check(l and l.q == 22 and l.m == 1000 and l.l == nil, "gold scan: (what is listed is as the new scan has it)")
        local hint = GB.State().hint
        check(hint == nil, "gold scan: rows with owners: no warning about own auctions")
    end
    -- a list too broken to trust: nothing is called sold out
    advance(61)
    Shift(B, 900)
    B.ah.rows = {Row(2589, 5, 500)}
    for i = 1, 4 do B.ah.rows[#B.ah.rows + 1] = Row(2589, 1, 1, {throw = true}) end
    Scan(B)
    check(Rec(B, 14047).q == 22 and Rec(B, 2589).m == 100 and Rec(B, 2589).q == 5,
          "gold scan: over 5% of the rows unreadable: what the scan didn't list is left as it was")

    -- ReplicateItems not there
    do
        local C = Stock(GP("GoldC"))
        local GC = C.ns.Gold
        C.OpenAH()
        C.ah.replicate = "throw"
        local ok = GC.StartScan()
        check(not ok and GC.State().state == "idle" and (Book(C) == nil or Book(C).fullAsked == nil) and
              GC.State().message == "A full scan isn't available here - use Price my items." and #C.ns.errors == 0,
              "gold scan: the game refusing a full scan: said so, and no wait started")
        -- it never answers
        C.ah.replicate = "never"
        check(GC.StartScan() == true, "gold scan: (asked)")
        advance(89)
        check(GC.State().state == "asked", "gold scan: (waiting for the list)")
        advance(2)
        check(GC.State().state == "idle" and Book(C).fullAsked ~= nil and
              GC.State().message == "The auction house didn't send its list. A full scan may be limited to once every 15 minutes, or not offered here. Price my items still works.",
              "gold scan: no list in 90 seconds: given up, the wait kept")
        -- an empty list is no list
        Shift(C, 900)
        C.ah.replicate, C.ah.rows = nil, {}
        GC.StartScan()
        advance(5)
        check(GC.State().state == "asked", "gold scan: a list of no rows is no list: still waiting")
        advance(90)
        check(GC.State().state == "idle" and Book(C).full == nil, "gold scan: (and given up in time)")
        -- two events for one list
        Shift(C, 900)
        C.ah.replicate, C.ah.infoReads = "twice", {}
        C.ah.rows = {Row(14047, 1, 100), Row(14047, 1, 110), Row(8170, 1, 100)}
        Scan(C)
        check(Total(C.ah.infoReads) == 3 and Rec(C, 14047) and Rec(C, 14047).q == 2,
              "gold scan: the list announced twice is read once")
        -- another add-on's scan, heard while idle
        C.ah.replicate = nil
        advance(61)
        local asked = Book(C).fullAsked
        Shift(C, 100)
        C.ah.rows = {Row(14047, 3, 300)}
        C.Fire("REPLICATE_ITEM_LIST_UPDATE")
        advance(1)
        check(Rec(C, 14047).q == 3 and Book(C).fullAsked == C.env.time() - 1 and Book(C).fullAsked > asked + 100 and Rec(C, 8170).q == 0,
              "gold scan: a list someone else asked for is read too, and counts as the scan of these 15 minutes")
        -- ... and within a minute of a read, or with the auction house closed, ignored
        C.ah.rows = {Row(14047, 9, 900)}
        C.Fire("REPLICATE_ITEM_LIST_UPDATE")
        advance(1)
        check(Rec(C, 14047).q == 3, "gold scan: a list within a minute of the last read is ignored")
        advance(61)
        C.CloseAH()
        C.Fire("REPLICATE_ITEM_LIST_UPDATE")
        advance(1)
        check(Rec(C, 14047).q == 3 and GC.State().state == "idle", "gold scan: a list with the auction house closed is ignored")
        -- closed while asked, and while reading
        C.OpenAH()
        Shift(C, 900)
        C.ah.replicateDelay = 3
        GC.StartScan()
        advance(1)
        C.CloseAH()
        advance(5)
        check(GC.State().state == "idle" and GC.State().message == "The scan was cut short - nothing was changed. The Scan button shows when the game allows the next one; Price my items works meanwhile." and
              Rec(C, 14047).q == 3, "gold scan: closing the auction house while waiting ends it; nothing changed, and it says what still works")
        C.OpenAH()
        Shift(C, 900)
        C.ah.replicateDelay = 1
        C.ah.rows = {}
        for i = 1, 600 do C.ah.rows[i] = Row(14047, 1, 50) end
        C.ah.infoReads = {}
        GC.StartScan()
        advance(1.005)
        check(GC.State().state == "reading" and Total(C.ah.infoReads) == 250 and
              GC.State().message == "Scanning: 250 of 600", "gold scan: (reading: " .. tostring(GC.State().message) .. ")")
        C.CloseAH()
        advance(5)
        check(GC.State().state == "idle" and Total(C.ah.infoReads) == 250 and Rec(C, 14047).q == 3 and Rec(C, 14047).m == 100 and
              GC.State().message == "The scan was cut short - nothing was changed. The Scan button shows when the game allows the next one; Price my items works meanwhile.",
              "gold scan: closing the auction house mid-read ends it; the book is as it was")
        -- a batch that throws
        C.OpenAH()
        Shift(C, 900)
        advance(61)
        local errors = Errs(C)
        C.ah.numThrowAt = C.ah.numReads + 3
        GC.StartScan()
        advance(5)
        check(GC.State().state == "idle" and Errs(C) == errors + 1 and Rec(C, 14047).q == 3 and
              GC.State().message == "Something went wrong reading the auction house - nothing was changed. /pqol status has the error.",
              "gold scan: a batch that throws ends the scan, once on record, the book as it was")
        do
            local info = C.ns.errorInfo[C.ns.errors[#C.ns.errors]]
            check(info and type(info.stack) == "string" and (info.stack:match("^(.-)in function 'Try'") or ""):find("Gold.lua", 1, true) ~= nil,
                  "gold scan: ... kept with the calls that led to where the batch threw")
        end
        C.ah.numThrowAt = nil
        -- switched off mid-scan
        Shift(C, 900)
        advance(61)
        C.ah.infoReads = {}
        GC.StartScan()
        advance(1.005)
        C.Slash("gold off")
        advance(5)
        check(GC.State().state == "idle" and Total(C.ah.infoReads) == 250 and Rec(C, 14047).q == 3 and
              not GC.eventFrame.events.REPLICATE_ITEM_LIST_UPDATE and not GC.eventFrame.events.AUCTION_HOUSE_SHOW and
              GC.State().message == nil, "gold scan: switched off mid-scan: it stops, nothing written, no event left registered")
        C.Fire("AUCTION_HOUSE_SHOW")
        C.merchant = {{id = 14341, price = 5000}}
        C.Fire("MERCHANT_SHOW")
        advance(1)
        local ok, why = GC.StartScan()
        check(not ok and C.ns.db.goldVendors == nil and not GC.State().ahOpen, "gold: switched off, it records nothing")
        C.Slash("gold on")
        check(GC.eventFrame.events.REPLICATE_ITEM_LIST_UPDATE and GC.State().ahOpen,
              "gold: switched on again with the auction house open: listening, and it knows it is open")
        -- scan on opening
        C.CloseAH()
        C.ns.db.goldScanOnOpen = true
        Shift(C, 900)
        local n = C.ah.asked
        C.OpenAH()
        check(C.ah.asked == n + 1 and GC.State().state == "asked", "gold scan: with the option on, opening the auction house scans")
        C.CloseAH()
        C.OpenAH()
        check(C.ah.asked == n + 1 and GC.State().state == "idle", "gold scan: (but not again within 15 minutes)")
    end

    ----------------------------------------------------------------------
    -- "Price my items": the items the recipes and bags use, one a second
    ----------------------------------------------------------------------
    do
        local D = Stock(GP("GoldD", {db = {goldRecipes = {["Player-9-ALT"] = {
            name = "Altchar", realm = "Forever", faction = "Alliance", at = 1000,
            profs = {Leatherworking = {at = 1000, list = {[77] = {n = "Thing", o = 4234, a = 1, b = 1, r = "2318:4"}}}}}}}}))
        local GD = D.ns.Gold
        -- (anything the mock isn't told about is a commodity)
        setmetatable(D.ah.commodity, {__index = function() return true end})
        D.ah.commodity[14046] = false
        Recipe(D, 1, "Runecloth Bag", 14046, {{14048, 5}, {8170, 2}, {14341, 1}})
        Recipe(D, 2, "Bolt of Runecloth", 14048, {{14047, 5}})
        OpenTrade(D, "Tailoring")
        D.bags[0] = {n = 4, [1] = {itemID = 2589, stackCount = 20, quality = 1},
                     [3] = {itemID = 20001, stackCount = 1, isBound = true, quality = 2},
                     [4] = {itemID = 3000, stackCount = 5, quality = 0}}
        do
            local ok, why = GD.StartCheck()
            check(not ok and why == "open the auction house first", "gold check: not without the auction house open")
        end
        D.OpenAH()
        Listed(D, 14047, {{100, 50}})
        local before = Rec(D, 14047)
        check(before and before.m == 100 and before.q == 50 and before.s == "c",
              "gold passive: an item the player searches for themselves is recorded")
        local beforeAt = before.t
        Shift(D, 700)
        advance(3)
        D.ah.results[14047] = nil
        D.ah.results[14048] = {{quantity = 10, unitPrice = 900, numOwnerItems = 10},
                               {quantity = 10, unitPrice = 1000, numOwnerItems = 4},
                               {quantity = 5, unitPrice = 1100, containsAccountItem = true, totalNumberOfOwners = 1},
                               {quantity = 3, unitPrice = 1200}}
        D.ah.results[14046] = {{quantity = 1}, {quantity = 1, buyoutAmount = 50000},
                               {quantity = 1, buyoutAmount = 40000, containsOwnerItem = true},
                               {quantity = 1, buyoutAmount = 30000, containsAccountItem = true}, full = false}
        D.ah.silent[8170], D.ah.silent[14047] = 1, 2
        local frame = D.env.AuctionHouseFrame
        local function Keys(t)
            local keys = {}
            for k, v in next, t do keys[#keys + 1] = tostring(k) .. "=" .. tostring(v) end
            table.sort(keys)
            return table.concat(keys, ";")
        end
        local was = Keys(frame) .. Keys(frame.SearchBar) .. Keys(frame.SearchBar.SearchBox) .. Keys(frame.ItemBuyFrame)
        D.ah.sends = {}
        check(GD.StartCheck() == true and GD.State().state == "checking" and GD.State().check.label == "Stop" and
              GD.State().message == "Pricing 1 of 51 (about 2 min)", "gold check: started: " .. tostring(GD.State().message))
        do
            local ok, why = GD.StartScan()
            check(not ok and why == "wait for the price check to finish" and
                  GD.State().scan.tip == "Wait for the price check to finish" and not GD.State().scan.enabled,
                  "gold check: a scan can't start while a price check runs")
        end
        advance(120)
        check(GD.State().state == "idle" and GD.State().message == "Priced 50 items. 1 didn't answer." and
              Book(D).check ~= nil, "gold check: finished: " .. tostring(GD.State().message))
        do
            local order = {}
            for i = 1, 9 do order[i] = D.ah.sends[i] and D.ah.sends[i].id end
            check(table.concat(order, " ") == "14048 8170 14341 14047 14046 2589 2318 4234 159",
                  "gold check: this character's reagents, their outputs, the bags, other characters' recipes, vendor goods (" ..
                  table.concat(order, " ") .. ")")
            local gapOK, perMinute = true, 0
            for i, s in ipairs(D.ah.sends) do
                if i > 1 and s.t - D.ah.sends[i - 1].t < 0.999 then gapOK = false end
                local n = 0
                for j = i, #D.ah.sends do if D.ah.sends[j].t - s.t < 60 then n = n + 1 end end
                if n > perMinute then perMinute = n end
            end
            check(#D.ah.sends == 53 and gapOK and perMinute <= 60 and D.ah.sentNotReady == 0,
                  "gold check: one query at a time, a second apart (" .. #D.ah.sends .. " sent, " .. perMinute .. " in the busiest minute)")
            local kinds = {}
            for _, s in ipairs(D.ah.sends) do kinds[s.id] = s.kind end
            check(kinds[14048] == "commodity" and kinds[14046] == "item" and #D.ah.lastSorts == 1 and
                  D.ah.lastSorts[1].sortOrder == 0 and D.ah.lastSorts[1].reverseSort == false and #D.ah.lastSellSorts == 2 and
                  D.ah.lastSellSorts[1].sortOrder == 4 and D.ah.lastSellSorts[2].sortOrder == 3,
                  "gold check: a commodity is searched by price, an item by its ID with buyout then bid")
            check(D.ah.lastSeparate == true and D.ah.lastSellSeparate == true,
                  "gold check: both searches ask for our own auctions to be told apart from the rest")
        end
        do
            local r = Rec(D, 14048)
            check(r and r.m == 1000 and r.q == 9 and r.l == "1000:6,1200:3" and r.s == "c" and r.p == nil,
                  "gold check: a commodity's answer: our own and the account's units left out")
            r = Rec(D, 14046)
            check(r and r.m == 50000 and r.q == 1 and r.p == true,
                  "gold check: an item's answer (matched by item ID, the event's own key): bid-only, own and account rows left out; a partial answer is marked")
            r = Rec(D, 8170)
            check(r and r.q == 0 and r.s == "c", "gold check: an answer with no rows: none listed; a query that got no answer is asked once more")
            check(Rec(D, 14047) == before and before.q == 50 and before.t == beforeAt,
                  "gold check: silence is not \"none listed\": the record is untouched")
            check(Keys(frame) .. Keys(frame.SearchBar) .. Keys(frame.SearchBar.SearchBox) .. Keys(frame.ItemBuyFrame) == was,
                  "gold check: nothing of Blizzard's auction house frame is written")
            local row = Find(GD.CraftRows(), "id", 14046)
            check(row and row.listed == 1 and row.listedText == "1+", "gold check: a partial answer shows as \"1+\" listed")
        end

        -- the list of that run, in order
        local order1, seen1 = {}, {}
        for _, snd in ipairs(D.ah.sends) do
            if not seen1[snd.id] then
                seen1[snd.id] = true
                order1[#order1 + 1] = snd.id
            end
        end
        -- a second run, disturbed
        Shift(D, 700)
        D.ah.results[14047] = {{quantity = 5, unitPrice = 120}}
        D.ah.sends = {}
        GD.StartCheck()
        advance(2.5)
        check(#D.ah.sends == 3, "gold check: (three sent in the first seconds)")
        -- the player opens an item to buy: Blizzard's panels listen to every answer
        frame.ItemBuyFrame.shown = true
        advance(40)
        check(#D.ah.sends == 3 and GD.State().paused and
              GD.State().message == "Paused while you buy or sell - continues when you're back on the list",
              "gold check: nothing is sent while a buy, sell or auctions panel is up, however long")
        frame.ItemBuyFrame.shown = false
        advance(1.2)
        check(#D.ah.sends == 4 and not GD.State().paused, "gold check: back on the list, it carries on")
        -- the game's throttle not ready
        D.ah.notReady = true
        advance(25)
        check(#D.ah.sends == 4 and D.ah.sentNotReady == 0, "gold check: nothing is sent while the game's throttle isn't ready")
        D.ah.notReady = false
        D.Fire("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
        advance(0.1)
        check(#D.ah.sends == 5 and D.ah.sends[5].id == order1[6],
              "gold check: ready again: on at once - past the item that waited 20 seconds")
        -- the player's own search in between
        advance(0.5)
        local at = clock
        D.Fire("COMMODITY_SEARCH_RESULTS_UPDATED", 99999)
        advance(4)
        check(D.ah.sends[6] and D.ah.sends[6].t >= at + 2 and D.ah.sends[6].t < at + 3 and Rec(D, 99999) == nil,
              "gold check: after an answer that wasn't ours, two seconds' wait")
        -- a query the throttle dropped
        advance(0.6 - (clock - D.ah.sends[#D.ah.sends].t))
        D.ah.drop = true
        local n = #D.ah.sends
        advance(1.5)
        local dropped = D.ah.sends[n + 1] and D.ah.sends[n + 1].id
        check(dropped and #D.ah.sends == n + 2, "gold check: a dropped query counts as unanswered at once, and the next goes out on time")
        advance(120)
        local times = 0
        for _, snd in ipairs(D.ah.sends) do if snd.id == dropped then times = times + 1 end end
        check(GD.State().state == "idle" and GD.State().message == "Priced 51 items." and times == 2 and
              D.ah.sends[#D.ah.sends - 1].id == order1[5] and D.ah.sends[#D.ah.sends].id == dropped and
              Rec(D, 14047).m == 120, "gold check: what went unanswered is asked once more at the end: " .. tostring(GD.State().message))
        -- stopped, and the auction house closed mid-way
        Shift(D, 700)
        D.ah.sends = {}
        GD.StartCheck()
        advance(2.6)
        local ok, why = GD.StartCheck()
        advance(5)
        check(ok and why == "stopped" and GD.State().state == "idle" and #D.ah.sends == 3 and
              GD.State().message == "Price check stopped: priced 3 items." and GD.State().check.label == "Price my items",
              "gold check: pressed again it stops: " .. tostring(GD.State().message))
        GD.StartCheck()
        advance(1.5)
        n = #D.ah.sends
        D.CloseAH()
        advance(10)
        check(GD.State().state == "idle" and #D.ah.sends == n and not GD.State().check.enabled and #D.ns.errors == 0,
              "gold check: the auction house closed mid-way: it ends, nothing more is sent")
    end
    -- more than one run's worth
    do
        local vendors = {}
        for i = 60001, 60400 do vendors[i] = {p = 100, w = "Trader", z = "", t = 1000} end
        local H = Stock(GP("GoldH", {db = {goldVendors = vendors}}))
        local GH = H.ns.Gold
        for i = 60001, 60400 do H.items[i] = {name = "Reagent " .. i, stack = 20, class = 7, reagent = true} end
        setmetatable(H.ah.commodity, {__index = function() return true end})
        H.OpenAH()
        H.ah.sendThrows = true
        H.Slash("gold price")
        advance(5)
        check(GH.State().state == "checking" and #H.ah.sends == 0 and #H.ns.errors == 0,
              "gold check: (a query that throws is an unanswered one, not an error)")
        H.ah.sendThrows = false
        GH.StopCheck()
        H.printed = {}
        H.Slash("gold price")
        check(Printed(H, "gold: pricing 300 items, about 360 seconds"), "gold check: /pqol gold price starts it")
        advance(400)
        local perMinute = 0
        for i, s in ipairs(H.ah.sends) do
            local n = 0
            for j = i, #H.ah.sends do if H.ah.sends[j].t - s.t < 60 then n = n + 1 else break end end
            if n > perMinute then perMinute = n end
        end
        check(GH.State().message == "Priced 300 items. 300 of 444 - press again for the rest." and #H.ah.sends == 300 and
              perMinute <= 60 and Book(H).checkN == 300, "gold check: 300 items a run, at most 60 a minute: " .. tostring(GH.State().message))
        -- (none of the 300 was listed: the header says what the book holds, not how many the last press asked about)
        check(GH.PriceState("crafts"):find("^Prices: nothing listed %- your items looked up ") ~= nil and
              not GH.PriceState("crafts"):find("300", 1, true), "gold check: the header: " .. GH.PriceState("crafts"))
        H.printed = {}
        H.Slash("gold check")
        check(Printed(H, "gold: pricing 144 items"), "gold check: the next run takes the rest (what was priced in the last 10 minutes is skipped)")
        H.Slash("gold check")
        check(Printed(H, "gold: price check stopped") and GH.State().state == "idle", "gold check: /pqol gold check again stops it")
        H.CloseAH()
        H.printed = {}
        H.Slash("gold price")
        H.Slash("gold scan")
        check(Printed(H, "gold: open the auction house first") and #H.printed == 2, "gold: /pqol gold price and scan say why they can't")
    end

    ----------------------------------------------------------------------
    -- what the player browses, and their own auctions
    ----------------------------------------------------------------------
    do
        local E = Stock(GP("GoldE"))
        local GE = E.ns.Gold
        E.ah.commodity[14047], E.ah.commodity[2589], E.ah.commodity[14048], E.ah.commodity[8170] = true, true, true, true
        E.ah.commodity[15000] = false
        E.OpenAH()
        E.ah.browse = {
            {itemKey = {itemID = 14047}, totalQuantity = 50, minPrice = 900},
            {itemKey = {itemID = 15000}, totalQuantity = 1, minPrice = 100},              -- gear: the price may be a bid
            {itemKey = {itemID = 3000}, totalQuantity = 5, minPrice = 100},               -- can't tell what it is
            {itemKey = {itemID = 14048}, totalQuantity = 5, minPrice = 100, containsOwnerItem = true},
            {itemKey = {itemID = 8170}, totalQuantity = 0, minPrice = 100},
        }
        E.Fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
        advance(0.1)
        local r = Rec(E, 14047)
        check(E.ah.browseReads == 1 and r and r.m == 900 and r.q == 50 and r.s == "b" and r.l == nil,
              "gold passive: the Buy list as the player browses it is read, once")
        check(Rec(E, 15000) == nil and Rec(E, 3000) == nil and Rec(E, 14048) == nil and Rec(E, 8170) == nil,
              "gold passive: commodities only - not gear, not what holds our own auction, not what has nothing listed")
        E.Fire("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", {{itemKey = {itemID = 2589}, totalQuantity = 7, minPrice = 30}})
        advance(0.1)
        check(E.ah.browseReads == 1 and Rec(E, 2589) and Rec(E, 2589).m == 30,
              "gold passive: more rows scrolled in: only those rows are read")
        -- a real look at the item is worth more than a browse row
        Listed(E, 8170, {{450, 4}, {480, 6}})
        E.ah.browse = {{itemKey = {itemID = 8170}, totalQuantity = 99, minPrice = 1}}
        E.Fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
        advance(0.1)
        check(Rec(E, 8170).m == 450 and Rec(E, 8170).s == "c", "gold passive: a browse row never replaces a fresh price of our own")
        Shift(E, 3700)
        E.Fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
        advance(0.1)
        check(Rec(E, 8170).m == 1 and Rec(E, 8170).s == "b", "gold passive: (an hour on, it does)")
        -- a browsed price below what a vendor pays raises no bargain
        local rows, meta = Analyse(E)
        check(#rows == 0 and GE.Now(8170) == 1, "gold passive: a browsed price never raises a bargain")
        -- 500 rows a tick
        local many = {}
        for i = 1, 1200 do
            many[i] = {itemKey = {itemID = 70000 + i}, totalQuantity = 1, minPrice = 10}
            E.ah.commodity[70000 + i] = true
        end
        E.ah.browse = many
        E.Fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
        check(Rec(E, 70500) and not Rec(E, 70501), "gold passive: 500 rows at a time")
        advance(0.1)
        check(Rec(E, 71200) ~= nil, "gold passive: (the rest a tick later)")
        do
            local all = true
            for i = 1, 1200 do if not Rec(E, 70000 + i) then all = false end end
            check(all and Rec(E, 70501) ~= nil and Rec(E, 71001) ~= nil, "gold passive: ... every row of them, none skipped between batches")
        end
        -- our own auctions, as the Auctions tab lists them, come out of a scan
        E.ah.owned = {{itemKey = {itemID = 14047}, quantity = 20, buyoutAmount = 1000},
                      {itemKey = {itemID = 14046}, quantity = 1, buyoutAmount = 60000},
                      {itemKey = {itemID = 2589}, quantity = 1}}
        E.ah.rows = {Row(14047, 20, 20000, {owner = false}), Row(14047, 10, 12000, {owner = false}),
                     Row(14046, 1, 60000, {owner = false}), Row(2589, 5, 500, {owner = false})}
        Scan(E)
        check(GE.State().hint == "Your own auctions may be counted - open your Auctions tab once.",
              "gold: a scan whose rows name no owner, the Auctions tab not yet seen: the header warns")
        E.Fire("OWNED_AUCTIONS_UPDATED")
        -- (the scan's records are as they were: the cloth and the bag still count ours)
        check(Rec(E, 14047).q == 30 and Rec(E, 14047).m == 1000 and Rec(E, 14046).q == 1 and
              GE.State().hint == "Your own auctions are still counted in 2 prices - press Price my items.",
              "gold: the Auctions tab opened after such a scan: the prices that still count our own are named, with what to press: " ..
              tostring(GE.State().hint))
        E.CloseAH()
        check(GE.State().hint == nil, "gold: ... and only at the auction house, where it can be acted on")
        E.OpenAH()
        check(GE.State().hint == "Your own auctions may be counted - open your Auctions tab once.",
              "gold: (what the Auctions tab listed is one visit's: back at the auction house it is asked for again)")
        E.Fire("OWNED_AUCTIONS_UPDATED")
        Shift(E, 900)
        advance(61)
        Scan(E)
        check(Rec(E, 14047).q == 10 and Rec(E, 14047).m == 1200 and Rec(E, 14046).q == 0 and Rec(E, 2589).q == 5,
              "gold: our own auctions are taken out of a scan's count")
        check(GE.State().hint == nil and Book(E).noOwners == nil, "gold: ... and after that scan there is nothing left to warn about")
        check(#E.ns.errors == 0, "gold passive: no errors")
    end

    ----------------------------------------------------------------------
    -- prices: now, usual, what it sells for, the cut, other sources
    ----------------------------------------------------------------------
    do
        local F = Stock(GP("GoldF"))
        local GF = F.ns.Gold
        setmetatable(F.ah.commodity, {__index = function() return true end})
        F.OpenAH()
        History(F, 2589, {{100, 10}}, 2)
        check(GF.Usual(2589) == nil and GF.Now(2589) == 100, "gold prices: two days of prices aren't a usual price yet")
        Listed(F, 2589, {{300, 10}, {310, 3}})
        Listed(F, 14047, {{1000, 10}, {1100, 5}})
        Listed(F, 8170, {{500, 2}})
        Listed(F, 14048, {{900, 50}})
        do
            local price, age, source = GF.Now(14047)
            local sell, flag = GF.SellPrice(14047)
            check(price == 1000 and age == 0 and source == "c" and sell == 1000 and flag == nil,
                  "gold prices: the lowest price listed now; with depth and no history that is what it sells for")
            sell, flag = GF.SellPrice(8170)
            local sell2, flag2 = GF.SellPrice(14048)
            check(sell == 500 and flag == "unproven" and sell2 == 900 and flag2 == "unproven",
                  "gold prices: two units, or a single price point, is one seller's asking price: unproven")
            sell, flag = GF.SellPrice(2589)
            check(GF.Usual(2589) == 100 and GF.Now(2589) == 300 and sell == 100 and flag == nil,
                  "gold prices: with three days known, it sells for the lower of now and usual")
            check(GF.AfterCut(999) == 949 and GF.AfterCut(100) == 95 and GF.Cut() == 5, "gold prices: the cut comes off rounded down")
            Listed(F, 2589, {})
            price, age = GF.Now(2589)
            sell, flag = GF.SellPrice(2589)
            check(price == nil and age == "none listed" and sell == 100 and flag == "none listed" and Rec(F, 2589).m == 300,
                  "gold prices: none listed now: it sells for its usual price, marked")
            Shift(F, 49 * 3600)
            price, age = GF.Now(14047)
            sell, flag = GF.SellPrice(14047)
            check(price == nil and age == "price is 2 d old" and sell == nil and flag == "price is 2 d old",
                  "gold prices: after 48 hours a price is no longer \"now\"")
            local text, old = GF.PriceState("crafts")
            check(old == true and text:find("from your own searches", 1, true) and GF.Old({t = Rec(F, 14047).t}) == "2 d old",
                  "gold prices: the header turns stale: " .. text)
        end
        -- a neutral auction house keeps its own prices, and takes 15%
        F.CloseAH()
        F.npcFaction = "Neutral"
        F.OpenAH()
        Listed(F, 3000, {{50, 5}, {60, 5}})
        check(GF.State().neutral and GF.Cut() == 15 and GF.AfterCut(1000) == 850 and Rec(F, 3000, "Forever-Neutral") and
              Rec(F, 3000) == nil and GF.Now(3000) == 50 and GF.PriceState("crafts"):find("Neutral auction house", 1, true),
              "gold prices: a neutral auction house: a book of its own and a 15% cut")
        F.CloseAH()
        check(not GF.State().neutral and GF.Cut() == 5 and GF.Now(3000) == nil, "gold prices: (closed: this faction's book again)")
        F.npcFaction = "Alliance"
        F.OpenAH()
        check(not GF.State().neutral, "gold prices: (our own faction's auctioneer: not neutral)")
        F.npcFaction = nil
        -- Auctionator's prices, where we have none
        Listed(F, 8170, {{500, 2}})
        F.SetAuctionator({prices = {[3000] = 77, [8170] = 1, [15000] = 999, [7000] = -5, [2320] = 0 / 0, [4000] = "12",
                                    [16000] = math.huge, [14341] = 40},
                          ages = {[3000] = 1, [8170] = 0, [15000] = 0, [7000] = 0, [2320] = 0, [4000] = 0, [16000] = 0, [14341] = 3}})
        Shift(F, 60)
        do
            local price, age, source = GF.Now(3000)
            local sell, flag = GF.SellPrice(3000)
            check(price == 77 and age == DAYSEC and source == "a" and sell == 77 and flag == "unproven" and
                  F.auctionator.caller == "PacesQualityOfLife", "gold prices: Auctionator's price where we have none (unproven)")
            check(GF.State().auctionator and GF.PriceState("crafts"):find("(some prices from Auctionator)", 1, true),
                  "gold prices: the header says some prices are Auctionator's")
            check(GF.Now(8170) == 500, "gold prices: our own price wins over Auctionator's")
            check(GF.Now(14341) == nil and GF.Now(15000) == nil, "gold prices: not a price over 2 days old, and never for gear")
            check(GF.Now(7000) == nil and GF.Now(2320) == nil and GF.Now(4000) == nil and GF.Now(16000) == nil and #F.ns.errors == 0,
                  "gold prices: a negative, not-a-number, text or infinite price is no price")
            F.auctionator.mode = "error"
            Shift(F, 60)
            check(GF.Now(3000) == nil and GF.Now(7000) == nil and GF.Now(4000) == nil, "gold prices: (Auctionator erroring: no price)")
            F.auctionator.mode = "ok"
            Shift(F, 60)
            local calls = F.auctionator.calls
            check(GF.Now(3000) == nil and F.auctionator.calls == calls and #F.ns.errors == 0,
                  "gold prices: three errors in a row and Auctionator is left alone for the session")
        end
    end

    ----------------------------------------------------------------------
    -- what things cost, and the Crafts tab
    ----------------------------------------------------------------------
    do
        local K = Stock(GP("GoldK", {db = {goldRecipes = {["Player-9-ALT"] = {
            name = "Altchar", realm = "Forever", faction = "Alliance", at = 1000,
            profs = {Leatherworking = {at = 1000, list = {[77] = {n = "Thing", o = 4234, a = 1, b = 1, r = "2318:4"}}}}}}}}))
        local GK = K.ns.Gold
        setmetatable(K.ah.commodity, {__index = function() return true end})
        K.items[14048].sell = 100
        Recipe(K, 1, "Runecloth Bag", 14046, {{14048, 5}, {8170, 2}, {14341, 1}})
        Recipe(K, 2, "Bolt of Runecloth", 14048, {{14047, 5}}, {cooldown = 30})
        Recipe(K, 4, "Runecloth Belt", 13856, {{14048, 3}})
        Recipe(K, 7, "Scraps", 7000, {{2589, 6}}, {min = 2, max = 4})
        Recipe(K, 8, "Ore from Recipe", 3000, {{4000, 1}})
        Recipe(K, 9, "Recipe from Ore", 4000, {{3000, 1}})
        Recipe(K, 10, "Soulbound Robe", 20001, {{14048, 1}})
        Recipe(K, 11, "Quest Thing", 30000, {{14048, 1}})
        OpenTrade(K, "Tailoring")
        K.npcName = "Trader Bob"
        K.merchant = {{id = 14341, price = 5000}, {id = 5555, price = 300, avail = 1}}
        K.Fire("MERCHANT_SHOW")
        advance(0.5)
        K.OpenAH()
        History(K, 14048, {{900, 20}, {950, 5}}, 3)
        Listed(K, 14048, {{900, 20}, {950, 5}})
        Listed(K, 14341, {{4000, 2}, {6000, 10}})
        Listed(K, 8170, {{500, 3}, {700, 2}})
        Listed(K, 14047, {{100, 100}, {110, 50}})
        Listed(K, 2589, {{10, 100}, {12, 50}})
        do
            local c, from, flag = GK.Cost(14341, 5)
            local c1, from1 = GK.Cost(14341, 1)
            check(c == 23000 and from == "auction + vendor" and c1 == 4000 and from1 == "auction",
                  "gold cost: the cheapest units from the auction house, the rest from the vendor")
            local v, how = GK.VendorBuy(14341)
            local s, how2 = GK.VendorBuy(2320)
            check(v == 5000 and how == "vendor" and s == 10 and how2 == "seed" and GK.VendorBuy(5555) == nil,
                  "gold cost: a merchant's own price, else the built-in one; a limited-supply price isn't counted on")
            c, from, flag = GK.Cost(8170, 10)
            check(c == 6400 and from == "auction" and flag == "only 5 listed",
                  "gold cost: more than is listed: the rest at the last price, and it says how few there are")
            c, from = GK.Cost(14048, 1)
            check(c == 500 and from == "your own craft" and GK.Cost(14048, 5) == 2500,
                  "gold cost: an intermediate you can craft for less than it is listed")
            c, from = GK.Cost(7000, 2)
            check(c == 40 and from == "your own craft", "gold cost: a craft's cost is shared over its average output (6 linen for 2-4)")
            c, from = GK.Cost(3000, 1)
            check(c == nil and from == "Odd Ore: no price yet", "gold cost: recipes that make each other don't loop: " .. tostring(from))
            c, from = GK.Cost(5555, 1)
            local c2, from2 = GK.Cost(99999)
            check(c == nil and from == "item #5555: no price yet" and c2 == nil and from2 == "item #99999: no price yet",
                  "gold cost: unknown, with the reason")
            check(GK.Cost(8170, 1) == 500, "gold cost: (500 now)")
            Listed(K, 8170, {{300, 5}, {310, 1}})
            check(GK.Cost(8170, 1) == 300, "gold cost: worked out again once the prices change")
        end
        ListedGear(K, 14046, {{30000}, {32000}, {35000}})
        K.counts = {[14048] = 12, [8170] = 5, [14341] = 1}
        do
            local rows = GK.CraftRows()
            local bag, bolt = Find(rows, "id", 14046), Find(rows, "id", 14048)
            check(bag and bag.cost == 7100 and bag.sells == 28500 and bag.how == "Auction" and bag.profit == 21400 and
                  bag.listed == 3 and bag.listedText == "3" and bag.rank == 1 and bag.mark == nil and rows[1] == bag,
                  "gold crafts: cost of the materials, what it sells for after the cut, the profit; the best first")
            check(bag and bag.by == "Tailoring - GoldK" and bag.mine == true and bag.canMake == 1 and bag.canMakeText == "1" and
                  bag.name == "Runecloth Bag" and bag.recipe == "Runecloth Bag" and K.countedBank == true,
                  "gold crafts: who makes it (named when several characters have recipes), how many the bags and bank allow")
            local tip = table.concat(GK.Tip(bag), "\n")
            check(tip:find("5 x Bolt of Runecloth: 25s (your own craft)", 1, true) and tip:find("1 x Rune Thread: 40s (auction)", 1, true) and
                  tip:find("Auction: 2g 85s (3g each, less the 5% cut)", 1, true) and tip:find("Vendor: 2g", 1, true) and
                  tip:find("Price from just now", 1, true) and
                  tip:find("Profit is after the 5% auction cut. The listing deposit comes back when it sells and is lost when it doesn't.", 1, true),
                  "gold crafts: the tooltip: materials and where from, the ways to sell, the age, the deposit")
            check(bolt and bolt.cooldown == true and bolt.cost == 500 and bolt.sells == 855 and bolt.profit == 355,
                  "gold crafts: a recipe with a cooldown is marked")
            local scraps = Find(rows, "id", 7000)
            check(scraps and scraps.cost == 60 and scraps.how == "Vendor" and scraps.sells == 3 and scraps.profit == -57,
                  "gold crafts: nothing on the auction house: what a vendor pays for the average output, and a loss shown as one")
            local belt = Find(rows, "id", 13856)
            check(belt and belt.how == "Vendor" and belt.sells == 5000 and belt.cost == 1500 and
                  Find(rows, "id", 20001) == nil and Find(rows, "id", 30000) == nil,
                  "gold crafts: without an enchanter: no disenchant value, no bind-on-pickup output; never a quest item")
            local alt = Find(rows, "id", 4234)
            check(alt and alt.by == "Leatherworking - Altchar" and alt.canMakeText == "-" and alt.canMake == nil and
                  alt.cost == nil and alt.costWhy == "item #2318: no price yet" and alt.profit == nil and alt.rank == 3 and
                  rows[#rows].rank == 3, "gold crafts: another character's recipe; an unknown cost says why and sorts last")
            Listed(K, 7000, {{50, 2}})
            scraps = Find(GK.CraftRows(), "id", 7000)
            check(scraps and scraps.sells == 141 and scraps.how == "Auction" and scraps.mark == "unproven" and scraps.rank == 2 and
                  scraps.profit == 81 and table.concat(GK.Tip(scraps), "\n"):find(
                      "Only 2 listed - this is one seller's asking price, not proof it sells.", 1, true),
                  "gold crafts: the average output times the price after the cut; a thin listing is marked unproven")
            K.counts[14341] = 3
            K.Fire("BAG_UPDATE_DELAYED")
            check(Find(GK.CraftRows(), "id", 14046).canMake == 2, "gold crafts: the bags changed: Can make follows")
            -- one hopeful listing far above the going rate
            Listed(K, 14048, {{999999, 1}})
            rows = GK.CraftRows()
            bolt = Find(rows, "id", 14048)
            check(GK.SellPrice(14048) == 900 and bolt.sells == 855 and rows[1].id == 14046,
                  "gold crafts: a single absurd listing doesn't make a craft the top one")
            Listed(K, 14048, {})
            bolt = Find(GK.CraftRows(), "id", 14048)
            tip = table.concat(GK.Tip(bolt), "\n")
            check(bolt.mark == "none listed" and bolt.sells == 855 and bolt.listed == 0 and bolt.listedText == "0" and
                  tip:find("None listed now - this is its usual price.", 1, true) and
                  tip:find("0 listed: nobody is selling - you set the price, but check that anyone buys.", 1, true),
                  "gold crafts: sold out: valued at its usual price, marked, and the tooltip says what 0 listed means")
        end
        -- an enchanter on the account
        K.trade.ids = {}
        Recipe(K, 3, "Enchant Bracer", nil, {{10940, 2}}, {enchant = true})
        OpenTrade(K, "Enchanting", 100)
        Listed(K, 10940, {{300, 20}, {310, 5}})
        Listed(K, 11176, {{2000, 10}, {2100, 5}})
        Listed(K, 16202, {{10000, 5}, {10500, 5}})
        Listed(K, 10938, {{1000, 10}, {1100, 5}})
        Listed(K, 10939, {{2400, 10}, {2500, 5}})
        Listed(K, 10998, {{500, 10}, {550, 5}})
        Listed(K, 11082, {{2000, 4}, {2100, 2}})
        do
            local rows = GK.EnchantRows()
            check(#rows == 1 and rows[1].name == "Enchant Bracer" and rows[1].cost == 600 and rows[1].by == "Enchanting - GoldK" and
                  rows[1].id == nil and GK.ENCHANT_FOOTER == "This is what the materials cost you. Charge at least this, plus your fee.",
                  "gold crafts: enchants: what the materials cost")
            local belt = Find(GK.CraftRows(), "id", 13856)
            check(GK.DisenchantValue(13856) == 7837 and belt.how == "Disenchant" and belt.sells == 7837 and belt.estimate == true and
                  belt.profit == 6337, "gold crafts: a green with no auction price whose disenchant value beats its materials shows a profit")
            local robe = Find(GK.CraftRows(), "id", 20001)
            ListedGear(K, 20001, {{99000}, {99500}, {99900}})
            local robe2 = Find(GK.CraftRows(), "id", 20001)
            check(robe and robe.how == "Disenchant" and robe.sells == 7837 and robe2 and robe2.how == "Disenchant" and robe2.sells == 7837,
                  "gold crafts: a bind-on-pickup output, with Enchanting: disenchant or vendor only")
            local c, from = GK.Cost(10938, 1)
            local c2, from2 = GK.Cost(10939, 1)
            check(c == 800 and from == "buy Greater and split" and c2 == 2400 and from2 == "auction",
                  "gold cost: a lesser essence may be a third of a greater one")
            c, from = GK.Cost(11082, 2)
            c2, from2 = GK.Cost(10998, 1)
            check(c == 3000 and from == "buy 3 Lesser and combine" and c2 == 500 and from2 == "auction",
                  "gold cost: a greater essence may be three lesser ones")
            K.printed = {}
            K.Slash("gold cut 10")
            check(GK.Cut() == 10 and GK.AfterCut(1000) == 900 and Find(GK.CraftRows(), "id", 14046).sells == 27000 and
                  Printed(K, "gold: the auction house's cut is now counted as 10%"), "gold: /pqol gold cut 10 changes the cut everywhere")
            K.Slash("gold cut 50")
            check(K.ns.db.goldCut == 30, "gold: the cut is kept between 0 and 30")
            K.printed = {}
            K.Slash("gold cut abc")
            K.Slash("gold cut")
            check(K.ns.db.goldCut == 30 and Printed(K, "/pqol gold cut <0-30>|r - the auction house's cut in percent, as a number") and
                  Printed(K, "gold: the auction house's cut is counted as 30%"), "gold: /pqol gold cut alone prints it; not a number: how to use it")
            K.Slash("gold cut 5")
        end
        -- status: figures, no names
        K.printed = {}
        K.Slash("status")
        do
            local line
            for l in (K.ns.statusFrame and K.ns.statusFrame.edit.text or ""):gmatch("[^\n]+") do
                if l:find("^gold:") then line = l end
            end
            check(line and line:find("prices of 14 items", 1, true) and line:find("recipes of 2 characters", 1, true) and
                  line:find("2 vendor prices", 1, true) and line:find("cut 5%", 1, true) and not line:find("Altchar", 1, true) and
                  not line:find("GoldK", 1, true) and not line:find("Trader", 1, true), "gold: /pqol status: " .. tostring(line))
            check(#K.ns.errors == 0, "gold crafts: no errors")
        end
    end

    ----------------------------------------------------------------------
    -- Bargains, Vendors, Your bags
    ----------------------------------------------------------------------
    do
        local M = Stock(GP("GoldM"))
        local GM = M.ns.Gold
        setmetatable(M.ah.commodity, {__index = function() return true end})
        Recipe(M, 3, "Enchant Bracer", nil, {{10940, 2}}, {enchant = true})
        OpenTrade(M, "Enchanting", 100)
        M.trade.ids = {}
        Recipe(M, 2, "Bolt of Runecloth", 14048, {{14047, 5}})
        OpenTrade(M, "Tailoring")
        M.OpenAH()
        check(GM.Empty("bargains") == "Press Scan (everything, once per 15 minutes) or Price my items (quick).",
              "gold bargains: no prices yet, the auction house open: what to press")
        for _ = 1, 3 do
            Listed(M, 3000, {{1000, 10}})
            Listed(M, 7000, {{1000, 4}})
            Listed(M, 14047, {{1000, 4}})
            Days(M, 1)
        end
        Listed(M, 3000, {{600, 4}, {650, 2}, {1000, 20}})
        Listed(M, 7000, {{600, 4}, {1000, 20}})
        Listed(M, 14047, {{700, 10}, {1000, 10}})
        Listed(M, 8170, {{300, 2}, {499, 1}, {600, 5}})
        Listed(M, 2589, {{3, 5}, {12, 5}})
        Listed(M, 11176, {{2000, 10}, {2100, 5}})
        Listed(M, 16202, {{10000, 5}, {10500, 5}})
        Listed(M, 11139, {{30000, 3}, {31000, 3}})
        ListedGear(M, 13856, {{5000}, {6600}})
        ListedGear(M, 17000, {{100}})
        ListedGear(M, 16000, {{20000}})
        Listed(M, 10938, {{400, 9}, {2000, 5}})
        Listed(M, 10939, {{2500, 5}, {2600, 5}})
        Listed(M, 10998, {{1500, 6}, {1600, 2}})
        Listed(M, 11082, {{2000, 4}, {2100, 2}})
        local first, meta0 = GM.BargainRows()
        check(#first == 0 and meta0.working == true, "gold bargains: worked out in the background: nothing on the first look")
        advance(0.2)
        local rows, meta = GM.BargainRows()
        local function Deal(kind, id)
            for _, row in ipairs(rows) do if row.kind == kind and row.id == id then return row end end
        end
        do
            local sorted = true
            for i = 2, #rows do if rows[i].profit > rows[i - 1].profit then sorted = false end end
            check(#rows == 8 and sorted and meta.working == false and meta.loading == 0 and meta.empty == nil,
                  "gold bargains: the list, most profit first (" .. #rows .. " rows)")
            local v = Deal("Vendor", 8170)
            check(v and v.cheapest == 300 and v.upTo == 499 and v.worth == 500 and v.units == 3 and v.profit == 401 and
                  Deal("Vendor", 2589) == nil and Deal("Vendor", 14047) == nil,
                  "gold bargains: listed below what a vendor pays: the units that qualify, buy up to; under 1 silver not shown")
            local tip = GM.Tip(v)
            check(tip[#tip] == "Press Search to see it in the auction house. Pace's QoL never buys for you." and
                  tip[#tip - 1] == "Buy the 3 cheapest (up to 4s 99c each), then sell them to any vendor." and
                  tip[#tip - 2] == "Price from just now", "gold bargains: the tooltip: how, how old, what to do, and that nothing is bought for you")
            local d = Deal("Disenchant", 13856)
            check(d and d.units == 1 and d.upTo == 5000 and d.worth == 7837 and d.profit == 2837 and d.estimate == true and
                  d.note == "may need skill 175", "gold bargains: gear below its disenchant value by 20% and 10 silver; the skill it may need")
            check(Deal("Disenchant", 17000) == nil and Deal("Vendor", 17000) ~= nil,
                  "gold bargains: a disenchant value with its dust unpriced is no value")
            local b = Deal("Disenchant", 16000)
            check(b and b.worth == 28500 and b.profit == 8500 and b.note == nil, "gold bargains: a rare item: its shard")
            local r = Deal("Resell", 3000)
            check(r and r.units == 6 and r.upTo == 650 and r.worth == 1000 and r.profit == 2000 and r.cheapest == 600 and
                  Deal("Resell", 7000) == nil and Deal("Resell", 14047) == nil,
                  "gold bargains: resale needs three days with 5 or more listed; units at 70% of usual or less, a quarter of what's listed at most")
            local m = Deal("Material", 14047)
            check(m and m.units == 10 and m.upTo == 700 and m.worth == 1000 and m.profit == 3000 and
                  m.note == "used by Bolt of Runecloth", "gold bargains: a material of your recipes at 80% of usual or less: the saving")
            local e = Deal("Essence", 10938)
            check(e and e.units == 3 and e.upTo == 400 and e.profit == 3525 and e.target == 10939 and e.estimate == true and
                  GM.Tip(e)[#GM.Tip(e) - 2] == "Buy 3 Lesser, right-click to combine, sell the Greater.",
                  "gold bargains: three lesser essences combined into a greater worth more")
            local s = Deal("Essence", 11082)
            check(s and s.units == 6 and s.upTo == 2100 and s.profit == 13450 and s.target == 10998 and
                  Deal("Essence", 10939) == nil and Deal("Essence", 10998) == nil,
                  "gold bargains: a greater essence split into three lesser worth more; only the way that pays")
            -- (a Greater Magic sells for 25s: a Lesser is worth a third; a Lesser Astral for 15s: a Greater three)
            check(e and e.worth == 833 and s and s.worth == 4500 and s.worth > s.upTo and
                  GM.Tip(e)[2] == "Units counts conversions (3 Lesser each): 3 keep 10s or more each." and
                  GM.Tip(s)[2] == "Units counts conversions (one Greater each): 6 keep 10s or more each.",
                  "gold bargains: an essence row's Worth is of one of its own item, and the tooltip says what Units counts")
        end
        -- the unit cap of a resale
        Listed(M, 3000, {{600, 4}, {1000, 4}})
        rows = Analyse(M)
        check(Deal("Resell", 3000) == nil, "gold bargains: a resale capped at a quarter of the units listed can fall under 20 silver")

        -- Your bags
        Listed(M, 14048, {{9000, 5}, {9100, 5}})
        M.bags[0] = {n = 6, [1] = {itemID = 14047, stackCount = 20, quality = 1},
                     [3] = {itemID = 20001, stackCount = 1, isBound = true, quality = 2},
                     [4] = {itemID = 30000, stackCount = 1, isBound = true, hasNoValue = true, quality = 1},
                     [5] = {itemID = 4000, stackCount = 1, quality = 1},
                     [6] = {itemID = 10938, stackCount = 3, quality = 1}}
        M.bags[2] = {throw = true}
        M.bags[5] = {n = 1, [1] = {itemID = 14047, stackCount = 5, quality = 1}}
        M.Fire("BAG_UPDATE_DELAYED")
        do
            local bags = GM.BagRows()
            local cloth, robe, quest, recipe, essence = Find(bags, "id", 14047), Find(bags, "id", 20001), Find(bags, "id", 30000),
                                                        Find(bags, "id", 4000), Find(bags, "id", 10938)
            check(#bags == 5 and cloth and cloth.count == 25 and cloth.vendor == 10000 and cloth.auction == 16625 and
                  cloth.best == 16625 and cloth.bestHow == "Auction" and cloth.bestText == "Auction 1g 66s 25c" and
                  cloth.confident == true and bags[1] == cloth,
                  "gold bags: a stack summed over the bags (the reagent bag too; empty slots and a bag that can't be read skipped)")
            check(cloth and cloth.keep == "Bolt of Runecloth" and GM.Tip(cloth)[1] == "or keep it: Bolt of Runecloth uses it",
                  "gold bags: a material of a craft that pays says so")
            check(robe and robe.bound == true and robe.auction == nil and robe.auctionText == nil and robe.vendor == 3000 and
                  robe.disenchant == 7837 and robe.best == 7837 and robe.bestHow == "Disenchant" and robe.confident == true,
                  "gold bags: a bound piece of gear: vendor or disenchant")
            check(quest and quest.vendor == nil and quest.best == nil and quest.bestText == "-" and quest.confident == true,
                  "gold bags: a thing with no value")
            check(recipe and recipe.auction == nil and recipe.auctionText == "?" and recipe.best == nil and recipe.confident == false and
                  recipe.bestText == "Vendor 5s - auction price unknown" and recipe.vendor == 500,
                  "gold bags: no auction price known: no \"best\" claimed")
            check(essence and essence.auction == 2373 and essence.bestHow == "Auction",
                  "gold bags: a lesser essence is worth a third of a greater when that is more")
            local t = GM.BagTotals(bags)
            check(t.vendor == 13500 and t.auction == 18998 and t.best == 26835 and t.unpriced == 1 and t.unproven == 0 and
                  t.text == "Vendors 1g 35s / Auction 1g 89s 98c / Best of each 2g 68s 35c - 1 unpriced (Price my items)",
                  "gold bags: the totals: " .. t.text)
            GM.Sort(bags, "count", true)
            check(bags[1] == cloth and bags[2] == essence, "gold: rows sort by a column")
            GM.Sort(bags, "best", false)
            check(bags[1] == essence and bags[#bags].best == nil and bags[#bags - 1].best == nil, "gold: rows without a value sort last")
            GM.Sort(bags, "best", true)
            check(bags[1] == cloth and bags[#bags].best == nil, "gold: (whichever way)")
        end
        check(GM.Empty("vendors") == "Visit vendors - I remember what they sell - then price the items." and #GM.VendorRows() == 0,
              "gold vendors: nothing to show yet: what to do")
        -- an hour on, the bargains are gone
        Shift(M, 3700)
        rows, meta = GM.BargainRows()
        local text, old = GM.PriceState("bargains")
        local _, oldCrafts = GM.PriceState("crafts")
        check(#rows == 0 and meta.empty == "These prices are 1 hour old - bargains will be gone. Press Scan or Price my items." and
              old == true and oldCrafts == false, "gold bargains: listings over an hour old raise none: " .. tostring(meta.empty))
        Listed(M, 2589, {{12, 5}, {13, 1}})
        rows, meta = Analyse(M)
        check(#rows == 0 and meta.empty == "Nothing worth buying in the last scan.", "gold bargains: fresh prices, nothing worth buying")
        check(#M.ns.errors == 0, "gold bargains: no errors")
    end
    do
        local V = Stock(GP("GoldV"))
        local GV = V.ns.Gold
        setmetatable(V.ah.commodity, {__index = function() return true end})
        V.npcName = "Trader Bob"
        V.merchant = {{id = 14341, price = 5000}, {id = 4000, price = 300, avail = 1}, {id = 8170, price = 450}}
        V.Fire("MERCHANT_SHOW")
        advance(0.5)
        V.OpenAH()
        Listed(V, 14341, {{7000, 5}, {7100, 5}})
        Listed(V, 8170, {{500, 5}, {510, 5}})
        ListedGear(V, 4000, {{2000}, {2100}})
        Listed(V, 2320, {{500, 5}, {510, 5}})
        Listed(V, 2321, {{9000, 1}})
        local rows = GV.VendorRows()
        local thread, recipe, seed = rows[1], rows[2], rows[3]
        check(#rows == 3 and thread.id == 14341 and thread.vendor == 5000 and thread.auction == 7000 and thread.profit == 1650 and
              thread.listed == 10 and thread.where == "Trader Bob, Elwynn Forest" and not thread.limited and not thread.seed,
              "gold vendors: bought from a vendor, sold for more after the cut")
        check(Find(rows, "id", 8170) == nil and Find(rows, "id", 2321) == nil,
              "gold vendors: not under 20% and 1 silver of profit, nor on a single listing with no history")
        check(recipe and recipe.id == 4000 and recipe.limited == true and recipe.profit == 1600 and
              recipe.where == "Trader Bob, Elwynn Forest (limited supply)" and GV.Tip(recipe)[1] == "limited supply - often the real money",
              "gold vendors: limited supply is flagged")
        local tip = GV.Tip(thread)
        check(tip[1] == "anyone can buy this from the vendor - sells slowly" and tip[#tip] == "your price may differ with reputation",
              "gold vendors: the tooltip's cautions")
        check(seed and seed.id == 2320 and seed.seed == true and seed.vendor == 10 and seed.profit == 465 and
              seed.where == "trade supplies vendors (price not confirmed - visit one)",
              "gold vendors: a built-in price no merchant has confirmed comes last, and says so")
        check(#V.ns.errors == 0, "gold vendors: no errors")
    end

    ----------------------------------------------------------------------
    -- saved data
    ----------------------------------------------------------------------
    do
        local S = Stock(GP("GoldS"))
        setmetatable(S.ah.commodity, {__index = function() return true end})
        Recipe(S, 2, "Bolt of Runecloth", 14048, {{14047, 5}})
        OpenTrade(S, "Tailoring")
        S.merchant = {{id = 14341, price = 5000}}
        S.Fire("MERCHANT_SHOW")
        advance(0.5)
        S.OpenAH()
        Listed(S, 14047, {{100, 10}, {110, 5}})
        S.ns.db.goldPos = {"CENTER", "CENTER", 10, 20}
        local saved = S.env.PacesQoLDB
        local kept = saved.goldBook["Forever-Alliance"].items[14047]
        check(kept.l == "100:10,110:5" and saved.goldRecipes[S.guid].profs.Tailoring.list[2].r == "14047:5",
              "gold saved: compact records (price points as text, reagents as text)")
        S = Reload(S)
        table.insert(gone, S)
        check(S.ns.db.goldBook["Forever-Alliance"].items[14047] == kept and S.ns.Gold.Now(14047) == 100 and
              Recipes(S, "Tailoring")[2].o == 14048 and S.ns.db.goldVendors[14341].p == 5000 and S.ns.db.goldPos[3] == 10 and
              S.ns.Gold.Cost(14048, 1) == 500, "gold saved: prices, recipes, vendors and the window's place survive a /reload")
        -- what is too old goes at login
        Shift(S, 20 * DAYSEC)
        local db, now = S.ns.db, S.env.time()
        local today = math.floor(now / DAYSEC)
        db.goldBook["Forever-Alliance"].items[1] = {m = 1, q = 1, t = now, h = ("1:5,2:6,%d:7,%d:8,%d:9"):format(today - 14, today - 13, today)}
        db.goldBook["Forever-Alliance"].items[2] = {m = "x", q = 1, t = now}
        db.goldBook["Old-Horde"] = {items = {[5] = {m = 1, q = 1, t = now - 31 * DAYSEC}}}
        db.goldBook["Asked-Horde"] = {items = {}, fullAsked = now}
        db.goldBook["Broken-Horde"] = "nonsense"
        db.goldRecipes["Player-old"] = {name = "Old", realm = "Forever", at = now - 181 * DAYSEC, profs = {}}
        db.goldRecipes["Player-recent"] = {name = "Recent", realm = "Forever", at = now - 10 * DAYSEC, profs = {}}
        for i = 1, 3005 do db.goldVendors[90000 + i] = {p = 5, w = "x", z = "", t = i} end
        db.goldCut = 99
        S = Reload(S)
        table.insert(gone, S)
        db = S.ns.db
        local items = db.goldBook["Forever-Alliance"].items
        check(items[1] and items[1].h == ("%d:8,%d:9"):format(today - 13, today) and items[2] == nil and items[14047] ~= nil,
              "gold saved: history is cut to 14 days and a malformed record dropped at login")
        check(db.goldBook["Old-Horde"] == nil and db.goldBook["Asked-Horde"] ~= nil and db.goldBook["Broken-Horde"] == nil,
              "gold saved: a month-old record goes, and a book left empty with it (unless its scan wait still runs)")
        check(db.goldRecipes["Player-old"] == nil and db.goldRecipes["Player-recent"] ~= nil and db.goldRecipes[S.guid] ~= nil,
              "gold saved: a character not seen for 180 days is forgotten")
        check(CountKeys(db.goldVendors) == 3000 and db.goldVendors[90001] == nil and db.goldVendors[90006] == nil and
              db.goldVendors[90007] ~= nil and db.goldVendors[14341] ~= nil, "gold saved: vendor prices are capped at 3,000, the oldest going first")
        check(db.goldCut == 30, "gold saved: a cut out of range is brought back in")
        Shift(S, 40 * DAYSEC)
        S = Reload(S)
        table.insert(gone, S)
        check(S.ns.db.goldBook["Forever-Alliance"] == nil and S.ns.db.goldBook["Asked-Horde"] == nil and #S.ns.errors == 0,
              "gold saved: 40 days on, the prices are gone and the emptied books with them")

        ------------------------------------------------------------------
        -- the Search button's work, the slash command, the options page, rules
        ------------------------------------------------------------------
        local GS = S.ns.Gold
        local heard = {}
        GS.Listen(function(what, arg) table.insert(heard, what .. ":" .. tostring(arg)) end)
        check(GS.Search(nil) == "Still loading this item's name" and GS.Search("Runecloth") == "Open the auction house first",
              "gold search: needs the item's name, and the auction house open")
        S.OpenAH()
        local frame = S.env.AuctionHouseFrame
        local box = frame.SearchBar.SearchBox
        check(GS.Search("Runecloth") == "Runecloth is in the auction house's search box - click Search there." and
              box.text == "Runecloth",
              "gold search: the name goes into the auction house's search box; the player is told to click Search there")
        local long = ("a"):rep(62) .. "\195\169" .. "b"
        GS.Search(long)
        check(box.text == ("a"):rep(62), "gold search: a long name is cut to 63 bytes, never through a character")
        GS.Search(("a"):rep(61) .. "\195\169" .. "bcd")
        check(box.text == ("a"):rep(61) .. "\195\169", "gold search: (a character that fits is kept)")
        frame.SearchBar.shown = false
        box.text = nil
        check(GS.Search("Runecloth") == "Open the Buy tab first" and box.text == nil, "gold search: the search bar not shown: it says to open the Buy tab")
        frame.SearchBar.shown = true
        S.SetAuctionator({})
        check(GS.Search("Runecloth") == "Searching in Auctionator" and S.auctionator.searches[1][1] == "Runecloth" and
              S.auctionator.caller == "PacesQualityOfLife" and box.text == nil,
              "gold search: with Auctionator there, its exact search, called under our name")
        S.auctionator.searchError = true
        check(GS.Search("Runecloth") == "Runecloth is in the auction house's search box - click Search there." and
              box.text == "Runecloth" and #S.ns.errors == 0,
              "gold search: Auctionator's search failing: the search box instead")
        S.SetAuctionator(nil)
        -- the window is the other file's: this one opens it when it is there
        S.printed = {}
        GS.ui = nil
        S.Slash("gold")
        check(Printed(S, "gold: the window isn't available"), "gold: /pqol gold with no window says so")
        local toggled = 0
        GS.ui = {Toggle = function() toggled = toggled + 1 end}
        S.Slash("gold")
        check(toggled == 1, "gold: /pqol gold toggles the window")
        local panel = S.optionsPanel
        check(panel and panel.goldNote and panel.goldOpen and panel.goldOpen.text == "Open" and panel.goldScan and
              (panel.goldScan.label.text or ""):find("Scan the whole auction house each time I open it (at most every 15 minutes)", 1, true),
              "gold options: a note, an Open button and the scan-on-opening box")
        RunScript(panel.goldOpen, "OnClick")
        check(toggled == 2, "gold options: Open opens the window")
        panel.goldScan:SetChecked(true)
        RunScript(panel.goldScan, "OnClick")
        check(S.ns.db.goldScanOnOpen == true, "gold options: the box sets scan-on-opening")
        S.ns.db.goldScanOnOpen = false
        Listed(S, 14047, {{100, 10}, {110, 5}})
        advance(0.1)
        check((panel.goldNote.text or ""):find("Prices: 1 item from your own searches", 1, true) and
              (panel.goldNote.text or ""):find("/pqol gold", 1, true), "gold options: the note says how fresh the prices are: " .. tostring(panel.goldNote.text))
        -- the subcommands
        S.printed = {}
        S.Slash("gold nonsense")
        check(#S.printed == 1 and Printed(S, "scan|r reads the whole auction house") and Printed(S, "forget|r forgets this realm's prices"),
              "gold: /pqol gold <anything else> lists the subcommands")
        S.printed = {}
        S.Slash("nonsense")
        check(Printed(S, "/pqol gold|r opens the gold finder") and Printed(S, "layout, gold"), "gold: /pqol's help line mentions it")
        S.printed = {}
        S.Slash("gold scan")
        check(Printed(S, "gold: asked the auction house for its list") and GS.State().state == "asked", "gold: /pqol gold scan asks for the list")
        S.printed = {}
        S.Slash("gold scan")
        S.Slash("gold price")
        check(Printed(S, "gold: a scan is already running") and Printed(S, "gold: wait for the scan to finish"),
              "gold: /pqol gold scan and price say why they can't")
        S.printed = {}
        S.Slash("gold forget")
        check(Printed(S, "gold: forgot the prices of 1 item on this realm") and GS.State().state == "idle" and
              S.ns.db.goldBook["Forever-Alliance"].items[14047] == nil and S.ns.db.goldBook["Forever-Alliance"].fullAsked ~= nil and
              S.ns.db.goldRecipes[S.guid] ~= nil and S.ns.db.goldVendors[14341] ~= nil,
              "gold: /pqol gold forget forgets this realm's prices - not the recipes, the vendors or the scan wait")
        S.printed = {}
        S.Slash("gold scan")
        check(Printed(S, "gold: a scan can be asked again in 15 min"), "gold: (and says how long until the next scan)")
        -- errors stay inside
        local errors = Errs(S)
        GS.Listen(function(what) if what == "bags" then error("boom") end end)
        S.Fire("BAG_UPDATE_DELAYED")
        check(Errs(S) == errors + 1, "gold: a listener's error is recorded, not thrown")
        local AH = S.env.C_AuctionHouse
        S.env.C_AuctionHouse = nil
        S.Fire("COMMODITY_SEARCH_RESULTS_UPDATED", 14047)
        S.Fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
        S.Fire("OWNED_AUCTIONS_UPDATED")
        S.Fire("REPLICATE_ITEM_LIST_UPDATE")
        check(Errs(S) == errors + 2 and GS.State().state == "idle", "gold: an error inside an event handler is recorded, not thrown")
        do
            local key = S.ns.errors[#S.ns.errors]
            local info = S.ns.errorInfo[key]
            local line = key and key:match("Gold%.lua:(%d+):")
            check(line and info and type(info.stack) == "string" and info.stack:find("Gold.lua:" .. line, 1, true) ~= nil and
                  not info.stack:find("in function 'error'", 1, true),
                  "gold: ... kept with the calls that led to where it was raised (not to where it was put on record)")
        end
        S.env.C_AuctionHouse = AH
        S.printed = {}
        S.Slash("status")
        local said = S.ns.statusFrame and S.ns.statusFrame.edit.text or ""
        check(said:find("\n%d+ errors? this session:\n") and said:find("\n%d+%) gold: ") and #S.printed == 0,
              "gold: /pqol status lists them, in its window")
        -- switched off and on
        heard = {}
        S.Slash("gold off")
        S.Slash("gold")
        check(heard[1] == "apply:false" and toggled == 2 and Printed(S, "gold: switched off") and
              CountKeys(GS.eventFrame.events) == 0 and (panel.goldNote.text or "") == "Switched off.",
              "gold: switched off: the window is told, no event stays registered, /pqol gold says it is off")
        S.Slash("gold on")
        S.Fire("BAG_UPDATE_DELAYED")
        S.CloseAH()
        advance(0.1)
        check(heard[2] == "apply:true" and heard[3] == "ah:true" and table.concat(heard, " "):find("bags:nil", 1, true) and
              table.concat(heard, " "):find("ah:false", 1, true) and table.concat(heard, " "):find("change:nil", 1, true),
              "gold: the window hears of switches, the auction house, the bags and changes (" .. table.concat(heard, " ") .. ")")
    end
    -- an event this client doesn't know
    do
        local X = Stock(GP("GoldX", {beforeLoad = function(N) N.badEvent = "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED" end}))
        X.merchant = {{id = 14341, price = 5000}}
        X.Fire("MERCHANT_SHOW")
        advance(0.5)
        check(#X.ns.errors == 0 and X.ns.db.goldVendors and X.ns.db.goldVendors[14341] and
              not X.ns.Gold.eventFrame.events.AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED and X.ns.Gold.eventFrame.events.AUCTION_HOUSE_SHOW,
              "gold: an event that can't be registered just isn't heard; the rest works")
        -- item data arriving inside the request itself
        X.items[8170].loaded = false
        X.itemSync = true
        check(X.ns.Gold.Info(8170, true) == nil, "gold items: (not loaded yet)")
        advance(0.5)
        check(X.ns.Gold.Info(8170) and X.ns.Gold.Info(8170).name == "Rugged Leather" and #X.ns.errors == 0,
              "gold items: data that arrives inside the request itself is taken a moment later")
        local info = X.ns.Gold.Info(13856)
        check(info and info.quality == 2 and info.ilvl == 51 and info.class == 4 and info.bind == 2 and info.sell == 5000 and
              info.stack == 1 and info.reagent == false and X.ns.Gold.Info(14047).reagent == true,
              "gold items: what is kept of an item")
        -- a client with none of it
        X.env.C_Item, X.env.C_Container, X.env.C_TradeSkillUI, X.env.C_AuctionHouse, X.env.C_MerchantFrame = nil, nil, nil, nil, nil
        X.env.C_SpellBook = nil
        X.OpenAH()
        X.Fire("TRADE_SKILL_SHOW")
        X.Fire("MERCHANT_SHOW")
        X.Fire("BAG_UPDATE_DELAYED")
        advance(1)
        local ok, why = X.ns.Gold.StartCheck()
        local ok2 = X.ns.Gold.StartScan()
        check(#X.ns.errors == 0 and not ok and why == "the auction house can't be searched here" and not ok2 and
              #X.ns.Gold.BagRows() == 0 and #X.ns.Gold.CraftRows() == 0 and X.ns.Gold.State().state == "idle",
              "gold: a client without these APIs: nothing breaks")
    end

    ----------------------------------------------------------------------
    -- the sums once more, each figure worked out by hand; and the corners
    -- the sections above leave out
    ----------------------------------------------------------------------
    do
        local Q = Stock(GP("GoldQ"))
        local GQ = Q.ns.Gold
        Q.knowsDisenchant = true
        Q.items[11083] = {name = "Soul Dust", stack = 20, class = 7, reagent = true}
        Q.items[11084] = {name = "Large Glimmering Shard", stack = 20, class = 7, reagent = true}
        Q.items[14344] = {name = "Large Brilliant Shard", stack = 20, class = 7, reagent = true}
        Q.items[20725] = {name = "Nexus Crystal", stack = 20, class = 7, reagent = true}
        Q.items[18000] = {name = "Epic Blade", quality = 4, ilvl = 60, sell = 90000, class = 2, bind = 2}
        Q.items[21000] = {name = "Blue Blade", quality = 3, ilvl = 58, sell = 30000, class = 2, bind = 2}
        Q.items[22000] = {name = "Starter Belt", quality = 2, ilvl = 3, sell = 5, class = 4, bind = 2}
        Q.OpenAH()

        -- a scan of more items than one step may write: the book is still
        -- written in one go, after the last of them
        Q.ah.rows = {}
        for i = 1, 2500 do Q.ah.rows[i] = Row(100000 + i, 1, 100 + i, {owner = false}) end
        local midway
        GQ.Listen(function(what)
            local st = GQ.State()
            if what == "change" and st.state == "reading" and st.message == "Scanning: 2,500 of 2,500" then
                midway = Book(Q).full == nil and Rec(Q, 100001) == nil
            end
        end)
        Scan(Q)
        check(midway == true and GQ.State().state == "idle" and GQ.State().message == "Scan finished: 2,500 items." and
              Rec(Q, 100001) and Rec(Q, 100001).m == 101 and Rec(Q, 102500) and Rec(Q, 102500).m == 2600 and #Q.ns.errors == 0,
              "gold scan: 2,500 items: nothing is in the book until every one is worked out, then all of them are")
        -- no row named its owner: the window says so beside how the scan ended
        Q.Slash("gold")
        local ui = GQ.ui
        check(ui.frame and ui.frame.shown and ui.status.text ==
              "Scan finished: 2,500 items. Your own auctions may be counted - open your Auctions tab once.",
              "gold window: the warning about own auctions shows beside the last job's message: " .. tostring(ui.status.text))
        Q.ah.owned = {{itemKey = {itemID = 14048}, quantity = 4, buyoutAmount = 3600}}
        Q.Fire("OWNED_AUCTIONS_UPDATED")
        advance(0.5)
        check(ui.status.text == "Scan finished: 2,500 items.", "gold window: (the Auctions tab seen: the warning goes)")
        Q.Slash("gold")
        advance(15) -- (the scan's items load)

        -- "Price my items": an item whose kind of search can't be told yet
        -- goes to the end of the list, once
        Q.items[19000] = {name = "Mystery", stack = 20, class = 7, loaded = false}
        Q.bags[0] = {n = 1, [1] = {itemID = 19000, stackCount = 5, quality = 1}}
        Q.ah.results[19000] = {{quantity = 5, unitPrice = 70}}
        local request = Q.env.C_Item.RequestLoadItemDataByID
        Q.env.C_Item.RequestLoadItemDataByID = function(id) if id ~= 19000 then return request(id) end end
        Q.ah.sends = {}
        -- (the scan answered for everything it didn't list: ten minutes on, those are asked again)
        Shift(Q, 601)
        GQ.StartCheck()
        local function Sent(id)
            local n, last = 0, nil
            for i, s in ipairs(Q.ah.sends) do
                if s.id == id then n, last = n + 1, i end
            end
            return n, last
        end
        for _ = 1, 400 do
            if Sent(2320) > 0 then break end
            advance(0.25)
        end
        check(Sent(2320) == 1 and Sent(19000) == 0 and GQ.State().state == "checking",
              "gold check: an item whose data hasn't loaded isn't searched for blind: the list goes on past it")
        Q.items[19000].loaded = true
        Q.Fire("ITEM_DATA_LOAD_RESULT", 19000, true)
        advance(60)
        do
            local n, at = Sent(19000)
            local _, thread = Sent(14341)
            local msg = GQ.State().message or ""
            check(n == 1 and at == #Q.ah.sends and thread and thread < at and Q.ah.sends[at].kind == "commodity" and
                  Rec(Q, 19000) and Rec(Q, 19000).m == 70 and Rec(Q, 19000).q == 5,
                  "gold check: ... and it is asked for at the end of the list, once its data is there")
            check(GQ.State().state == "idle" and msg:find("^Priced %d+ items%. %d+ didn't answer%.$") ~= nil and
                  Sent(11137) == 0 and #Q.ns.errors == 0,
                  "gold check: what never loads is counted unanswered, never searched for: " .. msg)
        end
        Q.env.C_Item.RequestLoadItemDataByID = request

        -- a handler that throws while a job waits: on record once, the job ends
        Shift(Q, 900)
        advance(61)
        Q.ah.replicate = "never"
        local errors = Errs(Q)
        local bad = setmetatable({}, {__index = function() error("unreadable key") end})
        check(GQ.StartScan() == true and GQ.State().state == "asked", "gold: (a scan asked for)")
        Q.Fire("ITEM_SEARCH_RESULTS_UPDATED", bad)
        check(GQ.State().state == "idle" and Errs(Q) == errors + 1 and GQ.State().message ==
              "Something went wrong reading the auction house - nothing was changed. /pqol status has the error.",
              "gold: an event handler that throws while a job runs ends the job, once on record")
        do
            local info = Q.ns.errorInfo[Q.ns.errors[#Q.ns.errors]]
            check(info and type(info.stack) == "string" and (info.stack:match("^(.-)in function 'Try'") or ""):find("Gold.lua", 1, true) ~= nil,
                  "gold: ... kept with the calls that led to where the handler threw")
        end
        Q.Fire("ITEM_SEARCH_RESULTS_UPDATED", bad)
        check(GQ.State().state == "idle" and Errs(Q) == errors + 2, "gold: ... and with no job running it is just recorded")
        Q.ah.replicate = nil

        -- the usual price: the middle of the days' typical prices
        for _, price in ipairs({100, 400, 200, 300}) do
            Listed(Q, 3000, {{price, 5}})
            Days(Q, 1)
        end
        check(GQ.Usual(3000) == 250 and GQ.UsualDeep(3000) == 250,
              "gold prices: four days at 100, 400, 200, 300: usual is 250 (the middle two, halved)")
        Listed(Q, 3000, {{1000, 4}})
        Days(Q, 1)
        check(GQ.Usual(3000) == 300 and GQ.UsualDeep(3000) == 250,
              "gold prices: a fifth day at 1000 with only 4 listed: usual 300; the deep usual (days with 5 or more) stays 250")
        Listed(Q, 3000, {{240, 8}, {500, 2}})
        do
            local sell, flag = GQ.SellPrice(3000)
            -- (today's typical price is 240: the price a quarter of the way into 10 units)
            check(Rec(Q, 3000).v == 240 and GQ.Usual(3000) == 270 and GQ.UsualDeep(3000) == 240 and GQ.Now(3000) == 240 and
                  sell == 240 and flag == nil, "gold prices: today at 240: usual (240 + 300) / 2 = 270, deep usual 240, sells for 240")
        end

        -- buying: unit by unit, the vendor whenever it is cheaper
        Listed(Q, 2320, {{8, 3}, {15, 10}})
        do
            local c, from = GQ.Cost(2320, 5)
            check(c == 44 and from == "auction + vendor, price not confirmed",
                  "gold cost: 3 at 8c listed, the vendor's (built-in, unconfirmed) 10c for the other 2: 44c")
            Listed(Q, 2320, {{15, 10}, {16, 5}})
            c, from = GQ.Cost(2320, 5)
            check(c == 50 and from == "vendor, price not confirmed", "gold cost: listed above the vendor's price: all 5 from the vendor, 50c")
        end

        -- disenchanting: a weapon's chances, a rare, an epic, nothing below the table
        Listed(Q, 11083, {{1000, 10}, {1100, 5}})
        Listed(Q, 11082, {{2000, 10}, {2100, 5}})
        Listed(Q, 11084, {{4000, 10}, {4100, 5}})
        do
            -- Test Sword (item level 30): 20% x 1.5 Soul Dust (950 after the cut) = 285
            -- + 75% x 1.5 Greater Astral (1900) = 2137.5 + 5% x Large Glimmering (3800) = 190
            local value, skill = GQ.DisenchantValue(15000)
            check(value == 2612 and skill == 50, "gold disenchant: a green weapon, item level 30: 285 + 2137.5 + 190 = 2612, skill 50")
            -- three Lesser Astral at 900 are worth more than the Greater's 2000:
            -- 75% x 1.5 x 2565 = 2885.625
            Listed(Q, 10998, {{900, 10}, {950, 5}})
            check(GQ.DisenchantValue(15000) == 3360,
                  "gold disenchant: an essence counts as its other size when that sells for more: 285 + 2885.625 + 190 = 3360")
            -- Blue Blade (rare, item level 58): 99.5% x Large Brilliant (47500 after the cut) = 47262.5
            Listed(Q, 14344, {{50000, 10}, {51000, 5}})
            value, skill = GQ.DisenchantValue(21000)
            check(value == 47262 and skill == 200, "gold disenchant: a rare, item level 58, the crystal unpriced: its shard, 47262")
            -- ... + 0.5% x Nexus Crystal (76000) = 380
            Listed(Q, 20725, {{80000, 3}, {81000, 3}})
            check(GQ.DisenchantValue(21000) == 47642, "gold disenchant: ... and with the crystal's small chance: 47642")
            value, skill = GQ.DisenchantValue(18000)
            check(value == 76000 and skill == 200, "gold disenchant: an epic, item level 60: one Nexus Crystal, 76000 after the cut")
            check(GQ.DisenchantValue(22000) == nil and GQ.DisenchantValue(14047) == nil,
                  "gold disenchant: gear below the table, and what isn't gear, has no value")
        end

        -- a cut that isn't a whole number; our own auctions said in the tooltip
        Recipe(Q, 2, "Bolt of Runecloth", 14048, {{14047, 5}})
        OpenTrade(Q, "Tailoring")
        Listed(Q, 14047, {{100, 100}, {110, 50}})
        Listed(Q, 14048, {{900, 20}, {950, 5}})
        Q.Slash("gold cut 7.5")
        do
            local bolt = Find(GQ.CraftRows(), "id", 14048)
            local tip = bolt and table.concat(GQ.Tip(bolt), "\n") or ""
            -- (900 less 7.5% is 832.5: a sale rounds down - and a vendor's 16s beats it)
            check(GQ.Cut() == 7.5 and GQ.AfterCut(1000) == 925 and GQ.AfterCut(999) == 924 and
                  tip:find("Auction: 8s 32c (9s each, less the 7.5% cut)", 1, true) and
                  tip:find("Profit is after the 7.5% auction cut.", 1, true),
                  "gold crafts: a cut of 7.5%: 900 sells for 832 on the auction house, and the tooltip says 7.5%")
            check(bolt and bolt.cost == 500 and bolt.how == "Vendor" and bolt.sells == 1600 and bolt.profit == 1100 and
                  bolt.mark == nil and tip:find("Vendor: 16s", 1, true),
                  "gold crafts: a vendor paying more than the auction house leaves: sold to the vendor, 16s - 5s = 11s")
            check(tip:find("Listed: 25, not counting 4 of yours", 1, true) and not tip:find("includes", 1, true),
                  "gold crafts: an output we have auctions of says so in the tooltip")
        end
        Q.Slash("gold cut 5")
        check(Errs(Q) == errors + 2, "gold: (no other errors)")
    end

    ----------------------------------------------------------------------
    -- review fixes: the scan and the saved book
    ----------------------------------------------------------------------
    do
        local R = Stock(GP("GoldR1"))
        local GR = R.ns.Gold
        R.OpenAH()
        -- the next scan, a day on
        local function Next(rows)
            Days(R, 1)
            advance(61)
            R.ah.rows = rows
            Scan(R)
            return math.floor(R.env.time() / DAYSEC)
        end
        R.ah.rows = {Row(14047, 5, 500), Row(2589, 5, 500)}
        Scan(R)
        local d1 = math.floor(R.env.time() / DAYSEC)
        -- a scan keeps the earlier days' history
        local d2 = Next({Row(14047, 5, 1000), Row(2589, 5, 500)})
        check(Rec(R, 14047).h == ("%d:100+,%d:200+"):format(d1, d2),
              "gold scan: the next day's scan adds to the history, the day before kept (" .. tostring(Rec(R, 14047).h) .. ")")
        local d3 = Next({Row(14047, 5, 1500), Row(2589, 5, 500)})
        check(Rec(R, 14047).h == ("%d:100+,%d:200+,%d:300+"):format(d1, d2, d3) and GR.Usual(14047) == 200 and
              GR.UsualDeep(14047) == 200, "gold scan: three days of scans make a usual price (the middle one)")
        -- sold out: last seen stays as it was, however often a scan looks
        local seen = Rec(R, 2589).t
        Next({Row(14047, 5, 1500)})
        local gone = Rec(R, 2589)
        check(gone and gone.q == 0 and gone.z == seen and gone.t == Book(R).full and gone.t > seen,
              "gold saved: a sold-out record keeps when it was last seen listed, apart from when it was last checked")
        check(GR.PriceState("crafts") == "Prices: 1 item - full scan just now" and R.ns.Gold:Status():find("prices of 1 item,", 1, true) ~= nil,
              "gold: the header and /pqol status count what is listed, not what is sold out (" .. GR.PriceState("crafts") .. ")")
        Next({Row(14047, 5, 1500), Row(2589, 5, 500)})
        check(Rec(R, 2589).q == 5 and Rec(R, 2589).z == nil, "gold saved: (listed again: an ordinary record)")
        for _ = 1, 29 do Next({Row(14047, 5, 1500)}) end
        gone = Rec(R, 2589)
        check(gone and gone.q == 0 and gone.t == Book(R).full and select(2, GR.Now(2589)) == "none listed",
              "gold saved: 29 days of scans without it: still on record as none listed, checked today")
        Next({Row(14047, 5, 1500)})
        Next({Row(14047, 5, 1500)})
        local listed = 0
        for _, rec in pairs(Book(R).items) do if rec.q > 0 then listed = listed + 1 end end
        -- (what is left besides the cloth: the built-in vendor goods, none listed)
        check(Rec(R, 2589) == nil and Rec(R, 14047) ~= nil and listed == 1 and
              CountKeys(Book(R).items) == 1 + CountKeys(R.ns.GoldData.seed),
              "gold saved: a month of daily scans without it: the sold-out record goes (the book doesn't only grow)")

        -- the list goes away while it is read (another add-on asked for a new one)
        Next({Row(14047, 5, 500), Row(2589, 5, 500)})
        local full, clothAt = Book(R).full, Rec(R, 14047).t
        local rows = {}
        for i = 1, 2999 do rows[i] = Row(60000 + i, 1, 100 + i) end
        rows[3000] = Row(14047, 5, 3500)
        local AH, calls = R.env.C_AuctionHouse, 0
        local real = AH.GetNumReplicateItems
        AH.GetNumReplicateItems = function()
            calls = calls + 1
            if calls >= 4 then return 0 end
            return real()
        end
        Next(rows)
        AH.GetNumReplicateItems = real
        check(GR.State().state == "idle" and
              GR.State().message == "Scan cut short: 500 items read - the auction house's list changed while it was read." and
              Rec(R, 60001) and Rec(R, 60001).m == 101 and Rec(R, 60500) and Rec(R, 60501) == nil,
              "gold scan: a list that empties mid-read: what was read is kept, and the window says it was cut short (" ..
              tostring(GR.State().message) .. ")")
        check(Rec(R, 14047).q == 5 and Rec(R, 14047).m == 100 and Rec(R, 14047).t == clothAt and Rec(R, 2589).q == 5 and
              Book(R).full == full and #R.ns.errors == 0,
              "gold scan: ... nothing unread is called sold out, and it doesn't count as a full scan")
    end
    do
        local T = Stock(GP("GoldR2"))
        local GT = T.ns.Gold
        setmetatable(T.ah.commodity, {__index = function() return true end})
        T.OpenAH()
        -- a list heard while idle (read as another add-on's scan)
        local function Heard(rows)
            advance(61)
            T.ah.rows = rows
            T.Fire("REPLICATE_ITEM_LIST_UPDATE")
            advance(1)
        end
        local function Hundred(bad)
            local rows = {}
            for i = 1, 100 - bad do rows[i] = Row(14047, 1, 100) end
            for _ = 1, bad do rows[#rows + 1] = Row(14047, 1, 100, {throw = true}) end
            return rows
        end
        Heard({Row(8170, 5, 2500), Row(14047, 5, 500)})
        Heard(Hundred(6))
        check(Rec(T, 8170).q == 5 and Rec(T, 14047).q == 94,
              "gold scan: 6 unreadable rows in 100: what the scan didn't list is left as it was")
        Heard(Hundred(5))
        check(Rec(T, 8170).q == 0 and Rec(T, 14047).q == 95, "gold scan: 5 in 100 (5%): what it didn't list is sold out")
        -- a second list: not within a minute of the last read
        advance(61)
        T.ah.rows = {Row(14047, 3, 300)}
        T.Fire("REPLICATE_ITEM_LIST_UPDATE")
        check(Rec(T, 14047).q == 3 and GT.State().state == "idle", "gold scan: (a short list is read at once)")
        advance(59)
        T.ah.rows = {Row(14047, 9, 900)}
        T.Fire("REPLICATE_ITEM_LIST_UPDATE")
        advance(0.5)
        check(Rec(T, 14047).q == 3, "gold scan: a list 59 seconds after the last read is ignored")
        advance(1.5)
        T.Fire("REPLICATE_ITEM_LIST_UPDATE")
        advance(0.5)
        check(Rec(T, 14047).q == 9, "gold scan: ... and one 61 seconds after it is read")
        -- announced again while the read is under way
        advance(61)
        T.ah.rows = {}
        for i = 1, 600 do T.ah.rows[i] = Row(14047, 1, 50) end
        T.ah.infoReads = {}
        T.Fire("REPLICATE_ITEM_LIST_UPDATE")
        check(GT.State().state == "reading" and Total(T.ah.infoReads) == 250, "gold scan: (a long list: the first 250 rows)")
        T.Fire("REPLICATE_ITEM_LIST_UPDATE")
        advance(1)
        check(Total(T.ah.infoReads) == 600 and Rec(T, 14047).q == 600 and GT.State().state == "idle",
              "gold scan: the list announced again mid-read doesn't start the read over (" .. Total(T.ah.infoReads) .. " rows read)")
        -- a gear row that had no link, and is another auction by the time it is looked at again
        advance(61)
        T.ah.rows = {Row(15000, 1, 40000, {lateLink = Link(15000, 800)})}
        T.Fire("REPLICATE_ITEM_LIST_UPDATE")
        T.ah.rows[1] = Row(16000, 1, 5, {link = Link(16000, 77)})
        advance(3)
        check(Rec(T, 15000) and Rec(T, 15000).q == 1 and Rec(T, "15000:77") == nil and Rec(T, "16000:77") == nil,
              "gold scan: a row that changed before its link was read again isn't given another auction's suffix")

        -- browsing: the auction house closed between two batches
        local many = {}
        for i = 1, 1200 do many[i] = {itemKey = {itemID = 72000 + i}, totalQuantity = 1, minPrice = 10} end
        T.ah.browse = many
        T.Fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
        T.CloseAH()
        advance(0.5)
        check(Rec(T, 72500) ~= nil and Rec(T, 72501) == nil,
              "gold passive: the auction house closed between batches: the rest of the browse list isn't written")
        T.OpenAH()
        -- a browse row doesn't rewrite today's scanned value in the history
        Heard({Row(3000, 5, 5000)})
        local h = Rec(T, 3000).h
        Shift(T, 3700)
        T.ah.browse = {{itemKey = {itemID = 3000}, totalQuantity = 7, minPrice = 900}}
        T.Fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
        advance(0.1)
        check(h == math.floor((T.env.time() - 3700) / DAYSEC) .. ":1000+" and Rec(T, 3000).s == "b" and Rec(T, 3000).m == 900 and
              Rec(T, 3000).h == h, "gold passive: a browse row leaves the day's scanned value in the history alone")
        check(#T.ns.errors == 0, "gold scan: (no errors)")
    end

    ----------------------------------------------------------------------
    -- review fixes: the item queue, bursts of events, Forget
    ----------------------------------------------------------------------
    do
        local U1 = Stock(GP("GoldR3"))
        local G3 = U1.ns.Gold
        setmetatable(U1.ah.commodity, {__index = function() return true end})
        -- the load queue goes on working after it has run dry
        for i = 1, 30 do U1.items[51000 + i] = {name = "Late " .. i, stack = 20, class = 7, loaded = false} end
        local n0 = #U1.itemAsks
        for i = 1, 20 do G3.Info(51000 + i) end
        advance(3)
        check(#U1.itemAsks == n0 + 20 and G3.Info(51020) ~= nil, "gold items: (20 items asked for, and loaded)")
        for i = 21, 30 do G3.Info(51000 + i) end
        advance(3)
        check(#U1.itemAsks == n0 + 30 and G3.Info(51025) and G3.Info(51025).name == "Late 25" and G3.Info(51030) ~= nil,
              "gold items: the queue still works after it has emptied once (" .. (#U1.itemAsks - n0) .. " of 30 asked for)")

        -- a burst of profession events: one read, after it has gone quiet
        Recipe(U1, 1, "Runecloth Bag", 14046, {{14048, 5}, {2320, 3}})
        Recipe(U1, 2, "Bolt of Runecloth", 14048, {{14047, 5}})
        U1.trade.prof = {professionID = 197, professionName = "Tailoring", skillLevel = 150, maxSkillLevel = 300}
        local reads = #U1.recipeReads
        for _ = 1, 10 do U1.Fire("TRADE_SKILL_LIST_UPDATE") end
        check(#U1.recipeReads == reads, "gold recipes: a burst of list updates reads nothing while it lasts")
        advance(0.6)
        check(#U1.recipeReads == reads + 2 and Recipes(U1, "Tailoring") and Recipes(U1, "Tailoring")[1] ~= nil,
              "gold recipes: ... and the list is read once when it has gone quiet (" .. (#U1.recipeReads - reads) .. " recipe reads)")
        -- ... and of merchant events
        local MF, looks = U1.env.C_MerchantFrame, 0
        local realInfo = MF.GetItemInfo
        MF.GetItemInfo = function(i)
            looks = looks + 1
            return realInfo(i)
        end
        U1.merchant = {{id = 4000, price = 5000}, {id = 8170, price = 450}}
        for _ = 1, 10 do U1.Fire("MERCHANT_UPDATE") end
        check(looks == 0, "gold merchants: a burst of merchant updates reads nothing while it lasts")
        advance(0.5)
        check(looks == 2 and U1.ns.db.goldVendors[8170].p == 450, "gold merchants: ... and the merchant is read once (" .. looks .. " looks)")
        MF.GetItemInfo = realInfo
        -- several changes in one tick: the window is told once
        U1.OpenAH()
        advance(1)
        local changes = 0
        G3.Listen(function(what) if what == "change" then changes = changes + 1 end end)
        Listed(U1, 14047, {{100, 10}, {110, 5}})
        Listed(U1, 14048, {{700, 30}, {720, 30}})
        Listed(U1, 8170, {{300, 2}, {499, 1}, {600, 5}})
        check(changes == 0, "gold: (a change is told a tick later)")
        advance(0.05)
        check(changes == 1, "gold: three changes in one tick are told as one (" .. changes .. ")")
        -- items arriving together: worked out again once
        local request = U1.env.C_Item.RequestLoadItemDataByID
        U1.env.C_Item.RequestLoadItemDataByID = function() end
        for i = 1, 5 do
            U1.items[52000 + i] = {name = "Batch " .. i, stack = 20, class = 7, loaded = false}
            G3.Info(52000 + i, true)
        end
        advance(1)
        local ver = G3.version
        for i = 1, 5 do
            U1.items[52000 + i].loaded = true
            U1.Fire("ITEM_DATA_LOAD_RESULT", 52000 + i, true)
        end
        advance(1)
        check(G3.version == ver + 1 and G3.Info(52003) ~= nil, "gold items: five items arriving together: everything is worked out again once")
        U1.env.C_Item.RequestLoadItemDataByID = request

        -- a reagent only a vendor sells (no auction price at all): its price times how many
        do
            local c, from = G3.Cost(2320, 3)
            local bag = Find(G3.CraftRows(), "id", 14046)
            -- (the bag's 5 bolts take 25 cloth, and 15 are listed: 10 at 1s, 5 and the last 10 at 1s 10c)
            check(Rec(U1, 2320) == nil and c == 30 and from == "vendor, price not confirmed" and bag and bag.cost == 2680 and
                  table.concat(G3.Tip(bag), "\n"):find("3 x Coarse Thread: 30c (vendor, price not confirmed)", 1, true) ~= nil,
                  "gold cost: three of a thread only the vendor sells cost three times its price - a built-in price, and said to be unconfirmed")
        end

        -- Forget while a Bargains pass is under way
        G3.BargainRows()
        advance(0.3)
        check(#G3.BargainRows() >= 1 and Find(G3.BargainRows(), "id", 8170) ~= nil, "gold bargains: (a bargain on the list)")
        U1.printed = {}
        U1.Slash("gold cut 5")
        U1.Slash("gold forget")
        advance(5)
        local book = Book(U1)
        check(Printed(U1, "gold: forgot the prices of 3 items on this realm") and #G3.BargainRows() == 0 and
              (book == nil or CountKeys(book.items) == 0) and #U1.ns.errors == 0,
              "gold: forgetting the prices while bargains are being worked out doesn't bring them back (" .. #G3.BargainRows() .. " rows)")
    end

    ----------------------------------------------------------------------
    -- review fixes: "Price my items"
    ----------------------------------------------------------------------
    do
        local C4 = Stock(GP("GoldR4"))
        local G4 = C4.ns.Gold
        -- (no built-in vendor goods here: only what is in the bags is priced)
        for id in pairs(C4.ns.GoldData.seed) do C4.ns.GoldData.seed[id] = nil end
        for i = 1, 3 do
            C4.items[53000 + i] = {name = "Cold " .. i, stack = 20, class = 7, loaded = false}
            C4.ah.results[53000 + i] = {{quantity = 5, unitPrice = 70, numOwnerItems = 0}}
        end
        C4.bags[0] = {n = 3, [1] = {itemID = 53001, stackCount = 5, quality = 1}, [2] = {itemID = 53002, stackCount = 5, quality = 1},
                      [3] = {itemID = 53003, stackCount = 5, quality = 1}}
        -- the game takes a second to load an item
        local request = C4.env.C_Item.RequestLoadItemDataByID
        C4.env.C_Item.RequestLoadItemDataByID = function(id)
            schedule(1, function()
                if C4.items[id] then C4.items[id].loaded = true end
                C4.Fire("ITEM_DATA_LOAD_RESULT", id, true)
            end, nil, C4)
        end
        C4.OpenAH()
        C4.ah.sends = {}
        local tick = C4.tick
        check(G4.StartCheck() == true, "gold check: (started on three items whose data hasn't loaded)")
        advance(0.5)
        check(G4.State().state == "checking" and #C4.ah.sends == 0 and C4.tick - tick <= 30,
              "gold check: items still loading are waited for, a look every 0.3 s - not written off in a few frames (" ..
              (C4.tick - tick) .. " timer ticks in half a second)")
        advance(15)
        check(G4.State().state == "idle" and G4.State().message == "Priced 3 items." and #C4.ah.sends == 3 and Rec(C4, 53001) and
              Rec(C4, 53001).m == 70 and Rec(C4, 53003) and Rec(C4, 53003).q == 5,
              "gold check: ... and priced once their data is there: " .. tostring(G4.State().message))
        -- one that never loads is given three seconds
        C4.items[53009] = {name = "Never", stack = 20, class = 7, loaded = false}
        C4.bags[0] = {n = 1, [1] = {itemID = 53009, stackCount = 1, quality = 1}}
        C4.env.C_Item.RequestLoadItemDataByID = function() end
        C4.ah.sends = {}
        G4.StartCheck()
        advance(2)
        check(G4.State().state == "checking", "gold check: (an item that doesn't load is still waited for after 2 seconds)")
        advance(2)
        check(G4.State().state == "idle" and G4.State().message == "Priced 0 items. 1 didn't answer." and #C4.ah.sends == 0,
              "gold check: ... and counted unanswered after about three, never searched for blind: " .. tostring(G4.State().message))
        C4.env.C_Item.RequestLoadItemDataByID = request

        -- the player's own item search: a part of a list sorted their way isn't a lowest price
        ListedGear(C4, 13856, {{90000}})
        check(Rec(C4, 13856) and Rec(C4, 13856).m == 90000 and Rec(C4, 13856).s == "c", "gold passive: (the player's full item answer is kept)")
        local at = Rec(C4, 13856).t
        Shift(C4, 600)
        C4.ah.results[13856] = {{quantity = 1, buyoutAmount = 120000, itemKey = {itemID = 13856, itemSuffix = 0}}, full = false}
        C4.ah.results[17000] = {{quantity = 1, buyoutAmount = 120000, itemKey = {itemID = 17000, itemSuffix = 0}}, full = false}
        C4.Fire("ITEM_SEARCH_RESULTS_UPDATED", {itemID = 13856, itemSuffix = 0})
        C4.Fire("ITEM_SEARCH_RESULTS_UPDATED", {itemID = 17000, itemSuffix = 0})
        check(Rec(C4, 13856).m == 90000 and Rec(C4, 13856).t == at and Rec(C4, 17000) == nil,
              "gold passive: a partial answer to the player's own item search is not recorded as a price")
        C4.ah.results[17000].full = nil
        C4.Fire("ITEM_SEARCH_RESULTS_UPDATED", {itemID = 17000, itemSuffix = 0})
        C4.ah.commodity[14047] = true
        Listed(C4, 14047, {{100, 5}, {110, 5}}, false)
        check(Rec(C4, 17000) and Rec(C4, 17000).m == 120000 and Rec(C4, 14047) and Rec(C4, 14047).m == 100 and
              Rec(C4, 14047).p == true and #C4.ns.errors == 0,
              "gold passive: the whole answer is; and a commodity's partial answer too (always cheapest first)")
    end
    do
        local D5 = Stock(GP("GoldR5"))
        local G5 = D5.ns.Gold
        setmetatable(D5.ah.commodity, {__index = function() return true end})
        D5.OpenAH()
        local frame = D5.env.AuctionHouseFrame
        D5.ah.sends = {}
        G5.StartCheck()
        advance(0.5)
        -- each of Blizzard's six panels that listen to search answers
        local held, resumed = {}, {}
        for _, key in ipairs({"CommoditiesBuyFrame", "ItemBuyFrame", "CommoditiesSellFrame", "ItemSellFrame", "AuctionsFrame",
                              "BuyDialog"}) do
            local n = #D5.ah.sends
            frame[key].shown = true
            advance(10)
            if #D5.ah.sends == n and G5.State().paused then held[#held + 1] = key end
            frame[key].shown = false
            advance(1.2)
            if #D5.ah.sends > n and not G5.State().paused then resumed[#resumed + 1] = key end
        end
        check(#held == 6, "gold check: nothing is sent while any of the six buy, sell and auctions panels is up (" ..
              table.concat(held, " ") .. ")")
        check(#resumed == 6 and G5.State().state == "checking", "gold check: ... and it carries on when each is gone (" .. table.concat(resumed, " ") .. ")")
        G5.StopCheck()
        advance(5)
        -- one query at a time, whatever arrives while it is unanswered
        Shift(D5, 700)
        D5.ah.answerDelay = 3
        D5.ah.sends = {}
        G5.StartCheck()
        local first = D5.ah.sends[1] and D5.ah.sends[1].id
        D5.ah.results[first or 0] = {{quantity = 5, unitPrice = 70, numOwnerItems = 0}}
        advance(1)
        D5.Fire("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
        advance(1)
        check(first and #D5.ah.sends == 1, "gold check: the throttle saying ready doesn't send a second query over an unanswered one")
        advance(0.5)
        local at = clock
        D5.Fire("COMMODITY_SEARCH_RESULTS_UPDATED", 99999)
        advance(0.4)
        check(#D5.ah.sends == 1 and Rec(D5, 99999) == nil and Rec(D5, first).q == 0,
              "gold check: an answer for another item isn't taken for ours")
        D5.ah.rows = {Row(14047, 1, 100)}
        D5.ah.infoReads = {}
        D5.Fire("REPLICATE_ITEM_LIST_UPDATE")
        check(G5.State().state == "checking" and Total(D5.ah.infoReads) == 0,
              "gold check: another add-on's scan list arriving mid-check isn't read")
        advance(4)
        check(Rec(D5, first) and Rec(D5, first).m == 70 and D5.ah.sends[2] and D5.ah.sends[2].t >= at + 2 and
              D5.ah.sends[2].t < at + 3 and G5.State().state == "checking" and #D5.ns.errors == 0,
              "gold check: our own answer still lands when it comes, and the next query waits two seconds after the other one")
        D5.ah.answerDelay = nil
        G5.StopCheck()
    end

    ----------------------------------------------------------------------
    -- review fixes: the sums
    ----------------------------------------------------------------------
    local function Deal(rows, kind, id)
        for _, row in ipairs(rows) do if row.kind == kind and row.id == id then return row end end
    end
    -- who can disenchant, and whose recipes count
    do
        local alt = {name = "Altench", realm = "Other", faction = "Horde", at = 1000, profs = {
            Enchanting = {at = 1000, skill = 300, list = {[5] = {n = "Enchant Bracer", e = true, a = 1, b = 1, r = "10940:2"}}},
            Tailoring = {at = 1000, list = {[6] = {n = "Runecloth Bag", o = 14046, a = 1, b = 1, r = "14048:5"}}}}}
        local N1 = Stock(GP("GoldR6", {db = {goldRecipes = {["Player-9-ALTENCH"] = alt}}}))
        local GN = N1.ns.Gold
        setmetatable(N1.ah.commodity, {__index = function() return true end})
        N1.OpenAH()
        Listed(N1, 11176, {{2000, 10}, {2100, 5}})
        Listed(N1, 16202, {{10000, 5}, {10500, 5}})
        Listed(N1, 14048, {{900, 20}, {950, 5}})
        Listed(N1, 10998, {{2000, 10}, {2100, 5}})
        Listed(N1, 11082, {{2400, 10}, {2500, 5}})
        N1.bags[0] = {n = 2, [1] = {itemID = 20001, stackCount = 1, isBound = true, quality = 2},
                      [2] = {itemID = 13856, stackCount = 1, quality = 2}}
        local function Bags()
            N1.Slash("gold cut 5")
            N1.Fire("BAG_UPDATE_DELAYED")
            local bags = GN.BagRows()
            return Find(bags, "id", 20001), Find(bags, "id", 13856)
        end
        local robe, belt = Bags()
        check(GN.DisenchantValue(13856) == 7837 and robe and robe.disenchant == nil and robe.bestHow == "Vendor" and
              robe.best == 3000 and robe.confident == true and belt and belt.disenchant == nil,
              "gold bags: an enchanter on another realm is no enchanter here: no disenchant value")
        check(#GN.CraftRows() == 0 and #GN.EnchantRows() == 0 and select(2, GN.Cost(10998, 1)) == "auction",
              "gold crafts: another realm's character adds no recipes and no essence splitting")
        -- the same character on this realm: reachable by mail, for what can be mailed
        alt.realm = "Forever"
        robe, belt = Bags()
        check(robe and robe.disenchant == nil and robe.bestHow == "Vendor" and robe.best == 3000 and belt and
              belt.disenchant == 7837 and #GN.CraftRows() == 1 and #GN.EnchantRows() == 1,
              "gold bags: an enchanter alt on this realm: a bound piece still can't be sent there - Best is the vendor; an unbound one can")
        N1.knowsDisenchant = true
        robe, belt = Bags()
        check(robe and robe.disenchant == 7837 and robe.bestHow == "Disenchant" and belt.disenchant == 7837 and #N1.ns.errors == 0,
              "gold bags: this character can disenchant: the bound piece too")
    end
    -- no enchanter anywhere, then one
    do
        local N4 = Stock(GP("GoldR9"))
        local G9 = N4.ns.Gold
        setmetatable(N4.ah.commodity, {__index = function() return true end})
        Recipe(N4, 4, "Runecloth Belt", 13856, {{14048, 3}})
        OpenTrade(N4, "Tailoring")
        N4.OpenAH()
        Listed(N4, 11176, {{2000, 10}, {2100, 5}})
        Listed(N4, 16202, {{10000, 5}, {10500, 5}})
        Listed(N4, 14048, {{900, 20}, {950, 5}})
        Listed(N4, 10998, {{2000, 10}, {2100, 5}})
        Listed(N4, 11082, {{2400, 10}, {2500, 5}})
        ListedGear(N4, 13856, {{100}})
        N4.bags[0] = {n = 1, [1] = {itemID = 13856, stackCount = 1, quality = 2}}
        N4.Fire("BAG_UPDATE_DELAYED")
        local rows = Analyse(N4)
        local kinds = {}
        for _, row in ipairs(rows) do kinds[row.kind] = true end
        local bagRow, craft = Find(G9.BagRows(), "id", 13856), Find(G9.CraftRows(), "id", 13856)
        local c, from = G9.Cost(10998, 1)
        check(G9.DisenchantValue(13856) == 7837 and Deal(rows, "Vendor", 13856) and not kinds.Disenchant and not kinds.Essence,
              "gold bargains: nobody on the account can enchant: no disenchant and no essence bargains")
        check(bagRow and bagRow.disenchant == nil and craft and craft.how == "Vendor" and c == 2000 and from == "auction",
              "gold: ... no disenchant value in the bags or on Crafts, and essences aren't costed as split ones")
        -- knows Disenchant, never opened the Enchanting window
        N4.knowsDisenchant = true
        rows = Analyse(N4)
        bagRow, craft = Find(G9.BagRows(), "id", 13856), Find(G9.CraftRows(), "id", 13856)
        c, from = G9.Cost(10998, 1)
        check(Deal(rows, "Disenchant", 13856) and Deal(rows, "Essence", 11082) and bagRow.disenchant == 7837 and
              craft.how == "Disenchant" and c == 800 and from == "buy Greater and split" and #N4.ns.errors == 0,
              "gold: a character who knows Disenchant counts as the enchanter: all of them appear")
    end
    -- bargains against what a vendor sells; a price seen on three days
    do
        local N2 = Stock(GP("GoldR7"))
        local G7 = N2.ns.Gold
        setmetatable(N2.ah.commodity, {__index = function() return true end})
        Recipe(N2, 1, "Runecloth Bag", 14046, {{14048, 5}, {14341, 1}})
        Recipe(N2, 4, "Runecloth Belt", 13856, {{14048, 3}})
        OpenTrade(N2, "Tailoring")
        N2.OpenAH()
        for _ = 1, 3 do
            Listed(N2, 14341, {{8000, 20}})
            Listed(N2, 3000, {{1000, 5}})
            ListedGear(N2, 13856, {{5000000}})
            Days(N2, 1)
        end
        -- Rune Thread: the vendor's (built-in) price is 50s, its usual auction price 80s
        Listed(N2, 14341, {{6000, 10}, {8000, 20}})
        local rows = Analyse(N2)
        check(G7.VendorBuy(14341) == 5000 and G7.Usual(14341) == 8000 and Deal(rows, "Material", 14341) == nil and
              Deal(rows, "Resell", 14341) == nil,
              "gold bargains: a material listed under its usual price but over the vendor's is no bargain")
        Listed(N2, 14341, {{5500, 10}, {8000, 30}})
        rows = Analyse(N2)
        check(Deal(rows, "Resell", 14341) == nil and Deal(rows, "Material", 14341) == nil,
              "gold bargains: nor is it a resale: nobody need pay more than the vendor asks")
        Listed(N2, 14341, {{4000, 10}, {8000, 30}})
        rows = Analyse(N2)
        local m, r = Deal(rows, "Material", 14341), Deal(rows, "Resell", 14341)
        check(m and m.units == 10 and m.upTo == 4000 and m.worth == 5000 and m.profit == 10000 and
              m.estimate == true and
              G7.Tip(m)[1] == "Usually 80s each, and a vendor should sell them for about 50s (price not confirmed - visit one); these are below both. The profit shown is what you would save on that price." and
              r and r.units == 10 and r.upTo == 4000,
              "gold bargains: listed under the vendor's price it is one, the saving counted against that price - a built-in one, so an estimate and said to be unconfirmed")
        -- one hopeful listing, seen on three days and today
        Listed(N2, 14048, {{900, 20}, {950, 5}})
        ListedGear(N2, 13856, {{5000000}})
        local sell, flag = G7.SellPrice(13856)
        local belt = Find(G7.CraftRows(), "id", 13856)
        check(G7.Usual(13856) == 5000000 and G7.UsualDeep(13856) == nil and sell == 5000000 and flag == "unproven" and
              belt and belt.sells == 4750000 and belt.mark == "unproven" and belt.rank == 2 and
              table.concat(G7.Tip(belt), "\n"):find("Only 1 listed - this is one seller's asking price", 1, true) ~= nil,
              "gold prices: one lone listing seen on three days is still one seller's asking price: unproven")
        -- ... while days with five or more listed do prove a price
        Listed(N2, 3000, {{1000, 2}})
        sell, flag = G7.SellPrice(3000)
        check(sell == 1000 and flag == nil and G7.UsualDeep(3000) == 1000, "gold prices: two listed now, five or more on three days: proven")
        check(#N2.ns.errors == 0, "gold bargains: (no errors)")
    end
    -- Your bags: what isn't proven, what isn't listed, what was only browsed
    do
        local N3 = Stock(GP("GoldR8"))
        local G8 = N3.ns.Gold
        setmetatable(N3.ah.commodity, {__index = function() return true end})
        N3.OpenAH()
        ListedGear(N3, 17000, {{5000000}})
        ListedGear(N3, 16000, {})
        N3.ah.browse = {{itemKey = {itemID = 14047}, totalQuantity = 5000, minPrice = 400}}
        N3.Fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
        advance(0.1)
        Listed(N3, 8170, {{500, 40}})
        N3.bags[0] = {n = 6, [1] = {itemID = 17000, stackCount = 1, quality = 2}, [2] = {itemID = 16000, stackCount = 1, quality = 3},
                      [3] = {itemID = 14047, stackCount = 20, quality = 1}, [4] = {itemID = 8170, stackCount = 5, quality = 1},
                      [5] = {itemID = 30000, stackCount = 1, quality = 1}, [6] = {itemID = 4000, stackCount = 1, quality = 1}}
        N3.Fire("BAG_UPDATE_DELAYED")
        local bags = G8.BagRows()
        local gloves, helm, cloth, leather, quest, recipe = Find(bags, "id", 17000), Find(bags, "id", 16000), Find(bags, "id", 14047),
                                                            Find(bags, "id", 8170), Find(bags, "id", 30000), Find(bags, "id", 4000)
        local function Tip(row) return table.concat(G8.Tip(row), "\n") end
        check(gloves and gloves.auction == 4750000 and gloves.mark == "unproven" and gloves.confident == true and
              Tip(gloves):find("Only 1 listed - this is one seller's asking price, not proof it sells.", 1, true) ~= nil,
              "gold bags: a single listing is one seller's asking price: marked, and the tooltip says so")
        check(Rec(N3, 16000) and Rec(N3, 16000).q == 0 and helm and helm.confident == true and helm.auction == nil and
              helm.auctionText == nil and helm.bestHow == "Vendor" and helm.best == 9000 and
              Tip(helm):find("None listed - no auction price to go by.", 1, true) ~= nil,
              "gold bags: looked for and none listed: that is an answer - Best is the vendor, not \"press Price my items\"")
        check(cloth and cloth.mark == "unproven" and Tip(cloth):find("Lowest price only - how many sell at it isn't known.", 1, true) and
              not Tip(cloth):find("Only 5000 listed", 1, true),
              "gold bags: a price read while browsing: only that it is the lowest, not \"only 5000 listed\"")
        check(leather and leather.mark == "unproven" and Tip(leather):find("All 40 are listed at one price - it may be one seller.", 1, true) ~= nil,
              "gold bags: forty at a single price: said as that")
        check(quest and quest.confident == true and quest.auctionText == nil and recipe and recipe.confident == false and
              recipe.auctionText == "?", "gold bags: a quest item is never auctioned; only what has no answer at all is without a price")
        local t = G8.BagTotals(bags)
-- (the helm's 90s; the cloth's 80s and the leather's 25s from the vendor
        -- beat their unproven auction prices and count; the gloves' best is an
        -- unproven auction price and doesn't)
        check(cloth.bestHow == "Vendor" and cloth.best == 8000 and leather.bestHow == "Vendor" and leather.best == 2500 and
              gloves.bestHow == "Auction" and t.unpriced == 1 and t.unproven == 1 and t.auction == 0 and t.best == 19500 and
              t.vendor == 22500 and
              t.text == "Vendors 2g 25s / Auction 0c / Best of each 1g 95s - 1 unpriced (Price my items) - 1 unproven, not counted",
              "gold bags: unproven auction prices stay out of the totals; a stack whose best is the vendor anyway still counts: " .. t.text)

        -- more wanted than the price points kept say anything about
        Listed(N3, 3000, {{10, 1}, {11, 1}, {12, 1}, {13, 1}, {14, 1}, {15, 1}, {100, 34}})
        local c, from, flag = G8.Cost(3000, 20)
        local c6, _, flag6 = G8.Cost(3000, 6)
        local _, _, flag50 = G8.Cost(3000, 50)
        check(Rec(N3, 3000).l == "10:1,11:1,12:1,13:1,14:1,15:1" and Rec(N3, 3000).q == 40 and c == 285 and from == "auction" and
              flag == "last 14 at a guessed price" and c6 == 75 and flag6 == nil and flag50 == "only 40 listed",
              "gold cost: units beyond the six price points kept are a guess, and said to be one")
        Recipe(N3, 7, "Scraps", 7000, {{3000, 20}})
        OpenTrade(N3, "Tailoring")
        c, from, flag = G8.Cost(7000, 1)
        local scraps = Find(G8.CraftRows(), "id", 7000)
        check(c == 285 and from == "your own craft" and flag == "materials partly at a guessed price" and scraps and
              Tip(scraps):find("20 x Odd Ore: 2s 85c (auction, last 14 at a guessed price)", 1, true) ~= nil and #N3.ns.errors == 0,
              "gold cost: ... through a craft of your own too, and in the Crafts tooltip")
    end
    -- the bargains' thresholds, each from both sides
    do
        local N5 = Stock(GP("GoldR10"))
        local G10 = N5.ns.Gold
        N5.knowsDisenchant = true
        setmetatable(N5.ah.commodity, {__index = function() return true end})
        Recipe(N5, 2, "Bolt of Runecloth", 14048, {{14047, 5}})
        OpenTrade(N5, "Tailoring")
        N5.OpenAH()
        local function Recipes5(low, high)
            local rows = {}
            for _ = 1, 4 do rows[#rows + 1] = {low} end
            for _ = 1, 4 do rows[#rows + 1] = {high} end
            return rows
        end
        for _ = 1, 3 do
            Listed(N5, 3000, {{1000, 20}})
            Listed(N5, 14047, {{1000, 10}})
            ListedGear(N5, 4000, {{10000}, {10000}, {10000}, {10000}, {10000}})
            Days(N5, 1)
        end
        local rows
        local function Now3000(points)
            Listed(N5, 3000, points)
            rows = Analyse(N5)
            return Deal(rows, "Resell", 3000)
        end
        check(G10.UsualDeep(3000) == 1000 and Now3000({{701, 20}, {1000, 60}}) == nil,
              "gold bargains: a resale at 70.1% of the usual price is none")
        local r = Now3000({{700, 20}, {1000, 60}})
        check(r and r.units == 20 and r.upTo == 700 and r.profit == 5000, "gold bargains: ... at 70% it is one")
        check(Now3000({{600, 8}, {1000, 8}}) == nil,
              "gold bargains: a quarter of the 16 listed is 4 units: 14s of profit, under the 20s a resale needs")
        r = Now3000({{600, 4}, {650, 5}, {1000, 15}})
        check(r and r.units == 6 and r.upTo == 650 and r.profit == 2000,
              "gold bargains: the quarter is counted across price points (4 at 6s, then 2 of the 5 at 6s 50c)")
        -- a thing that doesn't stack isn't a resale
        ListedGear(N5, 4000, Recipes5(5000, 10000))
        rows = Analyse(N5)
        check(G10.UsualDeep(4000) == 10000 and Deal(rows, "Resell", 4000) == nil, "gold bargains: only what stacks is offered as a resale")
        -- a material: at least 10 silver saved
        Listed(N5, 14047, {{800, 4}, {1000, 10}})
        rows = Analyse(N5)
        check(Deal(rows, "Material", 14047) == nil, "gold bargains: a material saving of 8 silver is none")
        Listed(N5, 14047, {{800, 5}, {1000, 10}})
        rows = Analyse(N5)
        local m = Deal(rows, "Material", 14047)
        check(m and m.units == 5 and m.profit == 1000 and m.worth == 1000, "gold bargains: ... of 10 silver it is one")
        -- disenchanting: at least 10 silver over the price
        Listed(N5, 11083, {{1000, 10}, {1100, 5}})
        Listed(N5, 11082, {{2000, 10}, {2100, 5}})
        Listed(N5, 11084, {{4000, 10}, {4100, 5}})
        local value = G10.DisenchantValue(15000)
        ListedGear(N5, 15000, {{(value or 0) - 999}})
        rows = Analyse(N5)
        check(value == 2612 and Deal(rows, "Disenchant", 15000) == nil,
              "gold bargains: gear 9s 99c under its disenchant value is none (10 silver at least)")
        ListedGear(N5, 15000, {{(value or 0) - 1000}})
        rows = Analyse(N5)
        local d = Deal(rows, "Disenchant", 15000)
        check(d and d.units == 1 and d.profit == 1000, "gold bargains: ... 10s under it is one")
        -- essences: each conversion keeps 10 silver at least
        Listed(N5, 10939, {{2000, 10}, {2100, 5}})
        Listed(N5, 10938, {{400, 9}, {2000, 5}})
        rows = Analyse(N5)
        check(Deal(rows, "Essence", 10938) == nil and Deal(rows, "Essence", 10939) == nil,
              "gold bargains: three lesser for 12s into a greater that leaves 19s keeps 7s: no bargain")
        Listed(N5, 10938, {{300, 9}, {2000, 5}})
        rows = Analyse(N5)
        local e = Deal(rows, "Essence", 10938)
        check(e and e.units == 3 and e.profit == 3000 and e.worth == 666, "gold bargains: ... for 9s it keeps 10s: one, three times over")
        -- ... and the essence it turns into must have been priced within the hour
        Shift(N5, 3700)
        Listed(N5, 10938, {{300, 9}, {2000, 5}})
        rows = Analyse(N5)
        check(G10.SellPrice(10939) == 2000 and Deal(rows, "Essence", 10938) == nil and #N5.ns.errors == 0,
              "gold bargains: the other essence's price over an hour old: no essence bargain on it")
    end

    ----------------------------------------------------------------------
    -- second review: what is left out and where each line is drawn, one
    -- reason at a time
    ----------------------------------------------------------------------
    -- recipes
    do
        local RP = Stock(GP("GoldT1"))
        Recipe(RP, 1, "Honor Cloak", 13856, {{14048, 3}})
        -- (an optional slot of the basic kind, and a required one of another kind)
        table.insert(RP.trade.recipes[1].sch.reagentSlotSchematics,
                     {reagentType = 1, required = false, quantityRequired = 1, reagents = {{itemID = 3000}}})
        table.insert(RP.trade.recipes[1].sch.reagentSlotSchematics,
                     {reagentType = 2, required = true, quantityRequired = 1, reagents = {{itemID = 7000}}})
        Recipe(RP, 2, "Dummy", 3000, {{14047, 1}})
        RP.trade.recipes[2].info.isDummyRecipe = true
        Recipe(RP, 3, "Salvage", 3000, {{14047, 1}})
        RP.trade.recipes[3].info.isSalvageRecipe = true
        Recipe(RP, 4, "Gathering", 3000, {{14047, 1}})
        RP.trade.recipes[4].info.isGatheringRecipe = true
        Recipe(RP, 5, "No Cooldown", 14048, {{14047, 5}}, {cooldown = 0})
        Recipe(RP, 6, "Backwards", 7000, {{2589, 6}}, {min = 3, max = 1})
        Recipe(RP, 7, "Free Reagent", 3000, {{14047, 1}})
        RP.trade.recipes[7].sch.reagentSlotSchematics[1].quantityRequired = 0
        Recipe(RP, 8, "On Cooldown", 14046, {{14048, 5}}, {cooldown = 1})
        OpenTrade(RP, "Tailoring", 0)
        local list, ch = Recipes(RP, "Tailoring")
        check(list and list[1] and list[1].r == "14048:3",
              "gold recipes: an optional slot (even of the basic kind) and a slot of another kind (even required) are no materials")
        check(list and list[1] and list[2] == nil and list[3] == nil and list[4] == nil,
              "gold recipes: a dummy, a salvage and a gathering recipe are left out")
        check(list and list[5] and list[5].c == nil and list[8] and list[8].c == true,
              "gold recipes: a cooldown of 0 is no cooldown; one of a second is")
        check(list and list[6] and list[6].a == 3 and list[6].b == 3, "gold recipes: a most-made under the least-made counts as the least")
        check(list and list[1] and list[7] == nil, "gold recipes: a recipe with a material needed 0 times can't be read: left out")
        check(ch and ch.profs.Tailoring.skill == nil and ch.profs.Tailoring.max == 300, "gold recipes: a skill of 0 is no skill")
        -- the window still changing what it shows
        RP.ns.db.goldRecipes = nil
        RP.trade.changing = true
        OpenTrade(RP, "Tailoring")
        check(RP.ns.db.goldRecipes == nil, "gold recipes: a window whose data source is changing isn't read")
        RP.trade.changing = false
        -- closed while the last recipes are read (and still \"ready\" when asked)
        RP.trade.onRead = function(id) if id == 8 then RP.Fire("TRADE_SKILL_CLOSE") end end
        OpenTrade(RP, "Tailoring")
        check(RP.ns.db.goldRecipes == nil, "gold recipes: the window closing during the last batch: nothing is written")
        RP.trade.onRead = nil
        -- a client that only has the filtered list
        local T = RP.env.C_TradeSkillUI
        T.GetFilteredRecipeIDs, T.GetAllRecipeIDs = T.GetAllRecipeIDs, nil
        OpenTrade(RP, "Tailoring")
        list = Recipes(RP, "Tailoring")
        check(list and list[1] ~= nil and list[8] ~= nil and #RP.ns.errors == 0,
              "gold recipes: without GetAllRecipeIDs the filtered list is read")
    end
    -- merchants, and the Vendors tab's two floors
    do
        local MP = Stock(GP("GoldT2"))
        local GMP = MP.ns.Gold
        setmetatable(MP.ah.commodity, {__index = function() return true end})
        MP.npcName = "Trader"
        MP.merchant = {{id = 14341, price = 5000}, {id = 4000, price = 300, avail = 0}, {id = 8170, price = 450}}
        local MF = MP.env.C_MerchantFrame
        local realInfo, throws = MF.GetItemInfo, true
        MF.GetItemInfo = function(i)
            if i == 2 and throws then error("row 2 can't be read") end
            return realInfo(i)
        end
        MP.Fire("MERCHANT_SHOW")
        advance(0.5)
        local V = MP.ns.db.goldVendors
        check(V and V[14341] and V[14341].p == 5000 and V[8170] and V[8170].p == 450 and V[4000] == nil and #MP.ns.errors == 0,
              "gold merchants: a row that throws is skipped; the rows before and after it are recorded, and nothing is on record as an error")
        throws = false
        MP.Fire("MERCHANT_SHOW")
        advance(0.5)
        check(V and V[4000] and V[4000].lim == true and GMP.VendorBuy(4000) == nil,
              "gold merchants: a limited item that is sold out (0 available) is still limited, not a price to count on")
        -- Vendors: at least 20% and at least 1 silver of profit, each alone not enough
        MP.merchant = {{id = 3000, price = 1000}, {id = 2589, price = 1000}, {id = 7000, price = 100}, {id = 14047, price = 100}}
        MP.Fire("MERCHANT_SHOW")
        advance(0.5)
        MP.OpenAH()
        Listed(MP, 3000, {{1211, 5}, {1300, 5}})   -- 11s 50c after the cut: 1s 50c over the vendor's 10s (15%)
        Listed(MP, 2589, {{1264, 5}, {1300, 5}})   -- 12s after the cut: 2s over it (20%)
        Listed(MP, 7000, {{158, 5}, {170, 5}})     -- 1s 50c after the cut: 50c over the vendor's 1s (50%)
        Listed(MP, 14047, {{211, 5}, {220, 5}})    -- 2s after the cut: 1s over it
        local rows = GMP.VendorRows()
        check(Find(rows, "id", 3000) == nil and Find(rows, "id", 2589) and Find(rows, "id", 2589).profit == 200,
              "gold vendors: 15% over the vendor's price is not shown (though it is over a silver); 20% is")
        check(Find(rows, "id", 7000) == nil and Find(rows, "id", 14047) and Find(rows, "id", 14047).profit == 100 and #MP.ns.errors == 0,
              "gold vendors: 50 copper of profit is not shown (though it is 50%); a silver is")
    end
    -- the scan: armor by its suffix, our own auctions by the price of one, whose names are ours
    do
        local SP = Stock(GP("GoldT3", {db = {goldRecipes = {
            ["Player-9-FAR"] = {name = "Faraway", realm = "Other", faction = "Alliance", at = 1000, profs = {}},
            ["Player-9-NEAR"] = {name = "Nearby", realm = "Forever", faction = "Alliance", at = 1000, profs = {}}}}}))
        local GSP = SP.ns.Gold
        Recipe(SP, 2, "Bolt of Runecloth", 14048, {{14047, 5}})
        OpenTrade(SP, "Tailoring")
        SP.OpenAH()
        SP.ah.owned = {{itemKey = {itemID = 14047}, quantity = 20, buyoutAmount = 2000},
                       {itemKey = {itemID = 14048}, quantity = 5, buyoutAmount = 0}}      -- (bid only)
        SP.Fire("OWNED_AUCTIONS_UPDATED")
        SP.ah.rows = {Row(14047, 50, 5000, {owner = false}),
                      Row(13856, 1, 50000, {link = Link(13856, 5)}), Row(13856, 1, 60000, {link = Link(13856, 7)}),
                      Row(8170, 4, 2000, {owner = "Faraway"}), Row(2589, 4, 2000, {owner = "Nearby"}),
                      Row(14048, 5, 4500, {owner = false}), Row(14048, 5, 5000, {owner = false})}
        Scan(SP)
        check(Rec(SP, "13856:5") and Rec(SP, "13856:5").m == 50000 and Rec(SP, "13856:7") and Rec(SP, "13856:7").m == 60000 and
              Rec(SP, 13856) == nil, "gold scan: armor is kept by its random suffix too, not only weapons")
        check(Rec(SP, 14047) and Rec(SP, 14047).q == 30 and Rec(SP, 14047).m == 100,
              "gold: our own 20 of a commodity come out of the 50 listed at that price for one (the stack's buyout isn't a price in the list)")
        check(Rec(SP, 8170) and Rec(SP, 8170).q == 4 and Rec(SP, 2589) == nil,
              "gold scan: a recorded character of this realm is ours by name; one of another realm with that name is somebody else")
        local bolt = Find(GSP.CraftRows(), "id", 14048)
        check(bolt and bolt.listed == 10 and not table.concat(GSP.Tip(bolt), "\n"):find("of yours", 1, true) and #SP.ns.errors == 0,
              "gold: an auction of ours with no buyout was never counted, so the tooltip doesn't say it was left out")
    end
    -- the Bargains pass: exactly 250 items a tick
    do
        local KP = Stock(GP("GoldT3b"))
        for i = 1, 600 do KP.items[80000 + i] = {name = "Ware " .. i, stack = 20, sell = 1, class = 7} end
        KP.OpenAH()
        KP.ah.rows = {}
        for i = 1, 600 do KP.ah.rows[i] = Row(80000 + i, 1, 100 + i) end
        KP.itemReads = {}
        Scan(KP)
        check(Total(KP.itemReads) == 600 and Max(KP.itemReads) == 250 and CountKeys(KP.itemReads) == 3 and #KP.ns.errors == 0,
              "gold bargains: 600 items are looked through 250 a tick, no more (" .. Max(KP.itemReads) .. " at most, over " ..
              CountKeys(KP.itemReads) .. " ticks)")
    end
    -- the bags: one row per item, by suffix, bound and unbound apart; and
    -- a piece nobody lists has its answer once it was looked for
    do
        local BP = Stock(GP("GoldT4"))
        local GBP = BP.ns.Gold
        setmetatable(BP.ah.commodity, {__index = function() return true end})
        BP.ah.commodity[17000] = false
        for id in pairs(BP.ns.GoldData.seed) do BP.ns.GoldData.seed[id] = nil end
        BP.bags[0] = {n = 5, [1] = {itemID = 17000, stackCount = 1, quality = 2, hyperlink = Link(17000, 5)},
                      [2] = {itemID = 17000, stackCount = 1, quality = 2, hyperlink = Link(17000, 0)},
                      [3] = {itemID = 14047, stackCount = 5, quality = 1, isBound = true},
                      [4] = {itemID = 14047, stackCount = 7, quality = 1},
                      [5] = {itemID = 14047, stackCount = 3, quality = 1, isBound = true}}
        BP.Fire("BAG_UPDATE_DELAYED")
        local function BagRow(key, bound)
            for _, row in ipairs(GBP.BagRows()) do
                if row.key == key and (row.bound or false) == bound then return row end
            end
        end
        check(#GBP.BagRows() == 4 and BagRow("17000:5", false) and BagRow(17000, false) and BagRow("17000:5", false).id == 17000,
              "gold bags: a piece with a random suffix is a row of its own, under the price book's key for it")
        check(BagRow(14047, true) and BagRow(14047, true).count == 8 and BagRow(14047, false) and BagRow(14047, false).count == 7 and
              BagRow(14047, true).auction == nil and BagRow(14047, true).vendor == 3200,
              "gold bags: bound and unbound stacks of one item are two rows")
        BP.OpenAH()
        local other = {quantity = 1, buyoutAmount = 40000, itemKey = {itemID = 17000, itemSuffix = 7}}
        -- the player's own look at the item: it says nothing of what it doesn't list
        BP.ah.results[17000] = {other}
        BP.Fire("ITEM_SEARCH_RESULTS_UPDATED", {itemID = 17000, itemSuffix = 0})
        check(Rec(BP, "17000:7") and Rec(BP, "17000:7").m == 40000 and Rec(BP, "17000:5") == nil and Rec(BP, 17000) == nil and
              BagRow("17000:5", false).confident == false and GBP.BagTotals(GBP.BagRows()).unpriced == 3,
              "gold bags: (three stacks without a price; the player's own search marks nothing \"none listed\")")
        -- our own look-up, cut short: no answer for the other suffixes either
        BP.ah.results[17000] = {other, full = false}
        BP.ah.results[14047] = {{quantity = 5, unitPrice = 70, numOwnerItems = 0}, {quantity = 5, unitPrice = 80, numOwnerItems = 0}}
        check(GBP.StartCheck() == true, "gold bags: (Price my items)")
        advance(10)
        check(GBP.State().state == "idle" and Rec(BP, "17000:5") == nil and Rec(BP, 17000) == nil and
              GBP.BagTotals(GBP.BagRows()).unpriced == 2, "gold bags: a partial answer says nothing of the pieces it didn't list")
        -- ... and whole: the two pieces in the bags aren't listed, and that is their answer
        BP.ah.results[17000] = {other}
        check(GBP.StartCheck() == true, "gold bags: (Price my items again)")
        advance(10)
        local bear, plain = BagRow("17000:5", false), BagRow(17000, false)
        local t = GBP.BagTotals(GBP.BagRows())
        check(Rec(BP, "17000:5") and Rec(BP, "17000:5").q == 0 and Rec(BP, "17000:5").s == "c" and Rec(BP, 17000) and
              Rec(BP, 17000).q == 0 and Rec(BP, "17000:7").q == 1,
              "gold check: our look-up lists every suffix of a piece: the ones in the bags it didn't list are none listed")
        check(bear and bear.confident == true and bear.auction == nil and bear.auctionText == nil and bear.bestHow == "Vendor" and
              bear.best == 2500 and table.concat(GBP.Tip(bear), "\n"):find("None listed - no auction price to go by.", 1, true) and
              plain and plain.confident == true and t.unpriced == 0 and not t.text:find("Price my items", 1, true) and
              #BP.ns.errors == 0,
              "gold bags: ... so their best is the vendor, and the totals no longer ask for a price check that can't bring a price: " ..
              t.text)
    end
    -- item data: asked for once, looked at again only after a while
    do
        local IP = Stock(GP("GoldT5"))
        local GI = IP.ns.Gold
        local asks = {}
        local request = IP.env.C_Item.RequestLoadItemDataByID
        -- (the game never answers)
        IP.env.C_Item.RequestLoadItemDataByID = function(id) asks[#asks + 1] = id end
        for i = 1, 3 do IP.items[56000 + i] = {name = "Slow " .. i, stack = 20, class = 7, loaded = false} end
        local reads = Total(IP.itemReads)
        for _ = 1, 3 do GI.Info(56001) end
        advance(1)
        GI.Info(56001)
        check(Total(IP.itemReads) == reads + 1 and #asks == 1, "gold items: an item still loading isn't looked at again within 5 seconds")
        advance(5)
        GI.Info(56001)
        advance(1)
        check(Total(IP.itemReads) == reads + 2 and #asks == 1,
              "gold items: ... after that it is, but the game is asked to load it only once a session (" .. #asks .. " asked)")
        -- an item event for something we never asked about
        local ver = GI.version
        IP.Fire("ITEM_DATA_LOAD_RESULT", 77777, true)
        IP.Fire("GET_ITEM_INFO_RECEIVED", 77778, true)
        advance(1)
        check(GI.version == ver, "gold items: another add-on's item arriving works nothing out again")
        -- the game says it couldn't load one: nothing changed, and no asking again
        local changes = 0
        GI.Listen(function(what)
            if what == "change" then
                changes = changes + 1
                GI.Info(56002)
            end
        end)
        GI.Info(56002)
        advance(1)
        reads, ver = Total(IP.itemReads), GI.version
        IP.Fire("ITEM_DATA_LOAD_RESULT", 56002, false)
        IP.Fire("GET_ITEM_INFO_RECEIVED", 56002, false)
        advance(60)
        GI.Info(56002)
        check(GI.version == ver and changes == 0 and Total(IP.itemReads) == reads,
              "gold items: an item the game couldn't load: nothing is worked out again and it isn't read again (" ..
              (Total(IP.itemReads) - reads) .. " reads in a minute)")
        advance(600)
        GI.Info(56002)
        GI.Info(56002)
        check(Total(IP.itemReads) == reads + 1, "gold items: ... until ten minutes on, once")
        IP.items[56002].loaded = true
        IP.Fire("ITEM_DATA_LOAD_RESULT", 56002, true)
        advance(1)
        check(GI.Info(56002) and GI.Info(56002).name == "Slow 2" and GI.version == ver + 1 and changes == 1,
              "gold items: ... and when it does arrive it is taken at once")
        -- the queue holds 2,000; switching off empties it
        asks = {}
        for i = 1, 2500 do GI.Info(57000 + i) end
        advance(0.15)
        check(#asks == 20, "gold items: (20 asked for in the first tick)")
        advance(30)
        check(#asks == 2000, "gold items: at most 2,000 items wait to be asked for (" .. #asks .. " asked)")
        asks = {}
        for i = 1, 100 do GI.Info(60000 + i) end
        advance(0.15)
        IP.Slash("gold off")
        advance(5)
        check(#asks == 20 and #IP.ns.errors == 0, "gold items: switched off, nothing more is asked for (" .. #asks .. " of 100)")
        IP.Slash("gold on")
        IP.env.C_Item.RequestLoadItemDataByID = request
    end
    -- prices, costs and bargains
    do
        local PP = Stock(GP("GoldT6"))
        local GPP = PP.ns.Gold
        PP.knowsDisenchant = true
        setmetatable(PP.ah.commodity, {__index = function() return true end})
        Recipe(PP, 1, "Runecloth Bag", 14046, {{14048, 5}})
        Recipe(PP, 2, "Bolt of Runecloth", 14048, {{14047, 5}})
        OpenTrade(PP, "Tailoring")
        PP.OpenAH()
        -- two listed is one seller's hope; three at two prices is a market
        Listed(PP, 3000, {{500, 1}, {510, 1}})
        local _, two = GPP.SellPrice(3000)
        Listed(PP, 3000, {{500, 2}, {510, 1}})
        local _, three = GPP.SellPrice(3000)
        check(two == "unproven" and three == nil, "gold prices: two units at two prices are unproven; three are not")
        -- an answer of up to 200 rows is read whole
        local many = {}
        for i = 1, 150 do many[i] = {1000 + i, 1} end
        Listed(PP, 7000, many)
        local whole = Rec(PP, 7000) and Rec(PP, 7000).q == 150 and Rec(PP, 7000).p == nil
        for i = 151, 250 do many[i] = {1000 + i, 1} end
        Listed(PP, 7000, many)
        check(whole and Rec(PP, 7000).q == 200 and Rec(PP, 7000).p == true,
              "gold check: 150 rows of an answer are all read; of 250 the first 200, marked as a part")
        -- the player's search for one suffix says nothing of the plain item
        ListedGear(PP, 13856, {{90000}})
        PP.ah.results[13856] = {}
        PP.Fire("ITEM_SEARCH_RESULTS_UPDATED", {itemID = 13856, itemSuffix = 5})
        local kept = Rec(PP, 13856) and Rec(PP, 13856).q == 1
        PP.Fire("ITEM_SEARCH_RESULTS_UPDATED", {itemID = 13856, itemSuffix = 0})
        check(kept and Rec(PP, 13856).q == 0,
              "gold passive: an empty answer for one \"of the Bear\" leaves the plain item's price alone; an empty one for the plain item is none listed")
        -- a craft's materials are bought together: five bolts take 25 cloth,
        -- and the cheap 20 don't cover them
        Listed(PP, 14047, {{400, 20}, {500, 80}})
        do
            local c, from, flag = GPP.Cost(14048, 5)
            local c1 = GPP.Cost(14048, 1)
            local bag = Find(GPP.CraftRows(), "id", 14046)
            check(c == 10500 and from == "your own craft" and flag == nil and c1 == 2000 and bag and bag.cost == 10500,
                  "gold cost: five bolts of your own craft cost their 25 cloth - 20 at 4s and 5 at 5s - not five times the first bolt")
            Listed(PP, 14047, {{400, 20}, {500, 2}})
            c, from, flag = GPP.Cost(14048, 5)
            bag = Find(GPP.CraftRows(), "id", 14046)
            check(c == 10500 and flag == "materials partly at a guessed price" and bag and table.concat(GPP.Tip(bag), "\n"):find(
                      "5 x Bolt of Runecloth: 1g 5s (your own craft, materials partly at a guessed price)", 1, true) ~= nil,
                  "gold cost: ... and with only 22 cloth listed for the 25, the cost is said to be partly a guess")
            -- (a craft that makes 2 to 4: one craft for 2, two crafts for 4 - each pays its share)
            Recipe(PP, 7, "Scraps", 7000, {{2589, 6}}, {min = 2, max = 4})
            OpenTrade(PP, "Tailoring")
            Listed(PP, 7000, {})
            Listed(PP, 2589, {{10, 6}, {40, 60}})
            check(GPP.Cost(7000, 2) == 40 and GPP.Cost(7000, 3) == 60 and GPP.Cost(7000, 4) == 200,
                  "gold cost: the average output still shares a craft's cost; a second craft's materials are priced where the first's left off")
            -- a lesser essence as a third of a greater: six take two greaters
            Listed(PP, 10939, {{2400, 1}, {3000, 5}})
            Listed(PP, 10938, {{1500, 10}, {1600, 5}})
            c, from = GPP.Cost(10938, 6)
            check(c == 5400 and from == "buy Greater and split" and GPP.Cost(10938, 1) == 800,
                  "gold cost: six lesser essences from two greater ones cost both greaters (24s + 30s), not twice the cheaper")
        end
        -- an unproven auction price that isn't the best way to sell marks nothing
        Listed(PP, 14048, {{900, 1}})
        do
            local bolt = Find(GPP.CraftRows(), "id", 14048)
            check(select(2, GPP.SellPrice(14048)) == "unproven" and bolt and bolt.how == "Vendor" and bolt.sells == 1600 and
                  bolt.mark == nil and bolt.rank == 1, "gold crafts: sold to a vendor, the row carries no mark of the auction price")
        end
        -- Bargains: a listing at exactly what the vendor pays earns nothing
        Listed(PP, 8170, {{300, 2}, {500, 50}})
        for i = 1, 3 do
            PP.items[58000 + i] = {name = "Unseen " .. i, stack = 20, sell = 500, class = 7, loaded = false}
            Listed(PP, 58000 + i, {{100, 5}, {110, 5}})
        end
        local rows, meta = Analyse(PP)
        local v = Deal(rows, "Vendor", 8170)
        check(v and v.units == 2 and v.upTo == 300 and v.profit == 400,
              "gold bargains: units listed at exactly the vendor's price aren't counted (2 of the 52)")
        -- items whose data hadn't loaded are left out, and looked at again when it has
        check(meta.loading == 3 and Deal(rows, "Vendor", 58001) == nil, "gold bargains: (three items left out: still loading)")
        advance(3)
        rows, meta = GPP.BargainRows()
        check(meta.loading == 0 and Deal(rows, "Vendor", 58001) and Deal(rows, "Vendor", 58003) and Deal(rows, "Vendor", 58003).units == 10,
              "gold bargains: once their data has arrived the pass runs again and they are on the list")
        -- one auction house's bargains aren't another's
        PP.CloseAH()
        PP.npcFaction = "Neutral"
        PP.OpenAH()
        local atNeutral = #GPP.BargainRows()
        advance(0.5)
        PP.CloseAH()
        PP.npcFaction = nil
        PP.OpenAH()
        advance(0.5)
        check(#rows >= 4 and atNeutral == 0 and #GPP.BargainRows() == #rows,
              "gold bargains: at a neutral auction house this faction's bargains aren't shown - not even until the pass has run again")
        -- errors stay inside: a timer's body, a listener, the window's own Toggle
        local errors = Errs(PP)
        local refresh = PP.ns.RefreshOptions
        PP.ns.RefreshOptions = function() error("the options page broke") end
        Listed(PP, 2589, {{10, 5}, {11, 5}})
        local ok = pcall(advance, 0.1)
        PP.ns.RefreshOptions = refresh
        check(ok and Errs(PP) == errors + 1, "gold: an error inside a timer of ours is recorded, never thrown into the game's timer")
        local breaking, heard = true, false
        GPP.Listen(function(what) if what == "ah" and breaking then error("a listener broke") end end)
        GPP.Listen(function(what) if what == "ah" then heard = true end end)
        errors = Errs(PP)
        PP.CloseAH()
        breaking = false
        check(heard and Errs(PP) == errors + 1, "gold: a listener that throws doesn't keep the next one from hearing")
        local ui = GPP.ui
        GPP.ui = {Toggle = function() error("the window broke") end}
        errors = Errs(PP)
        ok = pcall(GPP.Toggle)
        GPP.ui = ui
        check(ok and Errs(PP) == errors + 1, "gold: a window that throws on opening is recorded, not thrown at the caller")
        -- what "old" means: 48 hours
        PP.OpenAH()
        Listed(PP, 14046, {{60000, 3}, {65000, 2}})
        Shift(PP, 47 * 3600)
        local bag = Find(GPP.CraftRows(), "id", 14046)
        check(bag and bag.listed == 5 and bag.listedText == "5" and GPP.Old(bag) == nil and GPP.Old({t = PP.env.time() - 3 * 3600}) == nil,
              "gold prices: 47 hours on, a price is still current: its count is shown, and no age beside the name")
        Shift(PP, 2 * 3600)
        bag = Find(GPP.CraftRows(), "id", 14046)
        check(bag and bag.listed == nil and bag.listedText == "?" and GPP.Old(bag) == "2 d old",
              "gold prices: 49 hours on it is a last-seen one: \"2 d old\", and how many are listed isn't known")
    end
    -- "Price my items" for an enchanter takes the enchanting materials in
    do
        local NP, EP = Stock(GP("GoldT7")), Stock(GP("GoldT8"))
        EP.knowsDisenchant = true
        for _, P in ipairs({NP, EP}) do
            setmetatable(P.ah.commodity, {__index = function() return true end})
            for id in pairs(P.ns.GoldData.seed) do P.ns.GoldData.seed[id] = nil end
            P.OpenAH()
        end
        local ok, why = NP.ns.Gold.StartCheck()
        local ok2 = EP.ns.Gold.StartCheck()
        check(not ok and why == "everything was priced in the last 10 minutes" and ok2 == true and
              EP.ns.Gold.State().message == "Pricing 1 of 24 (about 29 s)" and EP.ah.sends[1] and EP.ah.sends[1].id == 10940,
              "gold check: an enchanter's list has the 24 enchanting materials; without one there is nothing to price (" ..
              tostring(EP.ns.Gold.State().message) .. ")")
        EP.ns.Gold.StopCheck()
    end

    ----------------------------------------------------------------------
    -- third review: answers that leave nothing to ask again, sums that owe
    -- an unproven price nothing, one cheap lot that isn't the going rate,
    -- our own auctions, and what the header and the status line say
    ----------------------------------------------------------------------
    local function BagOf(g, key)
        for _, row in ipairs(g.BagRows()) do if row.key == key then return row end end
    end
    local function TipOf(g, row) return row and table.concat(g.Tip(row), "\n") or "" end
    local function Has(s, needle) return type(s) == "string" and s:find(needle, 1, true) ~= nil end
    -- a piece with a random suffix that nobody lists at all, and one that is listed
    do
        local P = Stock(GP("GoldV1"))
        local g = P.ns.Gold
        setmetatable(P.ah.commodity, {__index = function() return true end})
        P.ah.commodity[17000] = false
        for id in pairs(P.ns.GoldData.seed) do P.ns.GoldData.seed[id] = nil end
        P.bags[0] = {n = 4, [1] = {itemID = 17000, stackCount = 1, quality = 2, hyperlink = Link(17000, 5)},
                     [2] = {itemID = 17000, stackCount = 1, quality = 2, hyperlink = Link(17000, 7)},
                     [3] = {itemID = 14047, stackCount = 7, quality = 1}, [4] = {itemID = 8170, stackCount = 4, quality = 1}}
        P.Fire("BAG_UPDATE_DELAYED")
        P.OpenAH()
        -- our look-up finds no Green Gloves at all; ten cloth at two prices; one lone leather
        P.ah.results[17000] = {}
        P.ah.results[14047] = {{quantity = 5, unitPrice = 70, numOwnerItems = 0}, {quantity = 5, unitPrice = 80, numOwnerItems = 0}}
        P.ah.results[8170] = {{quantity = 1, unitPrice = 70, numOwnerItems = 0}}
        check(g.StartCheck() == true, "gold bags: (Price my items, nothing of the piece listed)")
        advance(10)
        local bear, whale = BagOf(g, "17000:5"), BagOf(g, "17000:7")
        local t = g.BagTotals(g.BagRows())
        check(Rec(P, 17000) and Rec(P, 17000).q == 0 and Rec(P, "17000:5") and Rec(P, "17000:5").q == 0 and
              Rec(P, "17000:5").s == "c" and Rec(P, "17000:7") and Rec(P, "17000:7").q == 0,
              "gold check: an answer of ours with no rows at all: the suffixed pieces in the bags are none listed too, not only the plain item")
        check(bear and bear.confident == true and bear.auctionText == nil and bear.bestHow == "Vendor" and bear.best == 2500 and
              whale and whale.confident == true and t.unpriced == 0 and not Has(t.text, "Price my items"),
              "gold bags: ... so a suffixed piece nobody sells has its answer: Best is the vendor and the totals stop asking (" .. t.text .. ")")
        -- the leather's single listing is unproven, but its Best is the vendor's sure 20s
        local leather, cloth = BagOf(g, 8170), BagOf(g, 14047)
        check(leather and leather.mark == "unproven" and leather.auction == 264 and leather.bestHow == "Vendor" and
              leather.best == 2000 and leather.confident == true and cloth and cloth.auction == 462 and cloth.mark == nil,
              "gold bags: (a stack with an unproven auction price whose best is the vendor)")
        check(t.vendor == 9800 and t.auction == 462 and t.best == 9800 and t.unproven == 0 and
              t.text == "Vendors 98s / Auction 4s 62c / Best of each 98s",
              "gold bags: an unproven auction price leaves only the auction sum out; a vendor Best beside it still counts: " .. t.text)
        do
            local ok, why = g.StartCheck()
            check(not ok and why == "everything was priced in the last 10 minutes", "gold check: (nothing is asked twice in ten minutes)")
        end
        -- ten minutes on: one of the two is listed, the other still not
        Shift(P, 601)
        P.ah.results[17000] = {{quantity = 1, buyoutAmount = 40000, itemKey = {itemID = 17000, itemSuffix = 7}}}
        check(g.StartCheck() == true, "gold bags: (Price my items, one suffix listed)")
        advance(10)
        bear, whale, cloth = BagOf(g, "17000:5"), BagOf(g, "17000:7"), BagOf(g, 14047)
        check(Rec(P, "17000:7").q == 1 and Rec(P, "17000:7").m == 40000 and whale and whale.auction == 38000 and
              whale.mark == "unproven" and Rec(P, "17000:5").q == 0 and bear.confident == true and bear.auction == nil,
              "gold check: the suffix the answer lists keeps its price; only the piece it doesn't list is none listed")
        check(Rec(P, 14047).q == 10 and Rec(P, 14047).m == 70 and cloth and cloth.auction == 462 and Rec(P, 8170).q == 1,
              "gold check: ... and the answer for one item marks nothing of another in the bags")
        do
            -- (every row of the answer was under a suffix: the plain item is answered too)
            local plain = Rec(P, 17000)
            local ok, why = g.StartCheck()
            check(plain and plain.q == 0 and P.env.time() - plain.t < 60 and not ok and
                  why == "everything was priced in the last 10 minutes" and Has(g.State().check.tip, "About 0 seconds.") and
                  #P.ns.errors == 0,
                  "gold check: gear listed only under suffixes isn't asked for again at every press")
        end
    end
    -- the first visit, a first full scan, then Price my items: what the header says
    do
        local P = Stock(GP("GoldV2"))
        local g = P.ns.Gold
        setmetatable(P.ah.commodity, {__index = function() return true end})
        P.ah.commodity[17000], P.ah.commodity[14046] = false, false
        Recipe(P, 1, "Runecloth Bag", 14046, {{14048, 5}, {14341, 1}})
        OpenTrade(P, "Tailoring")
        P.bags[0] = {n = 2, [1] = {itemID = 17000, stackCount = 1, quality = 2, hyperlink = Link(17000, 5)},
                     [2] = {itemID = 4000, stackCount = 1, quality = 1}}
        P.Fire("BAG_UPDATE_DELAYED")
        P.OpenAH()
        -- (the recipe's two materials and its bag, the two things in the bags, the built-in vendor goods - Rune Thread is one)
        local want = 5 + CountKeys(P.ns.GoldData.seed) - 1
        local secs = tonumber((g.State().check.tip:match("About (%d+) seconds")))
        check(P.ns.db.goldBook == nil and secs == math.ceil(want * 1.2) and secs > 50,
              "gold check: before any price is on record the button already says how long a price check takes (" ..
              tostring(secs) .. " seconds), and no book is made for asking")
        P.ah.rows = {Row(14048, 20, 18000), Row(14048, 5, 4750)}
        Scan(P)
        local full = Book(P).full
        local function NoneAt(key) return Rec(P, key) and Rec(P, key).q == 0 and Rec(P, key).s == "f" and Rec(P, key).t == full end
        check(full and g.State().message == "Scan finished: 1 item." and NoneAt(14046) and NoneAt(14341) and NoneAt("17000:5") and
              NoneAt(17000) and NoneAt(4000) and NoneAt(2320) and Rec(P, 14047) == nil,
              "gold scan: a whole scan answers \"none listed\" for what the recipes, the bags and the vendors use and it didn't list: " ..
              tostring(g.State().message))
        local bag = Find(g.CraftRows(), "id", 14046)
        local t = g.BagTotals(g.BagRows())
        check(bag and bag.listed == 0 and bag.listedText == "0" and
              Has(TipOf(g, bag), "0 listed: nobody is selling - you set the price, but check that anyone buys.") and
              t.unpriced == 0 and BagOf(g, "17000:5").confident == true,
              "gold scan: ... so straight after it Crafts says \"0 listed\", not \"?\", and Your bags asks for no price check")
        check(g.PriceState("crafts") == "Prices: 1 item - full scan just now" and Has(g.State().check.tip, "About 0 seconds."),
              "gold: the header after a scan (" .. g.PriceState("crafts") .. ")")
        -- 14 minutes on, Price my items; one item never answers
        Shift(P, 840)
        P.ah.results[14048] = {{quantity = 20, unitPrice = 900, numOwnerItems = 0}, {quantity = 5, unitPrice = 950, numOwnerItems = 0}}
        P.ah.results[14341] = {{quantity = 10, unitPrice = 4000, numOwnerItems = 0}, {quantity = 5, unitPrice = 4100, numOwnerItems = 0}}
        P.ah.silent[4000] = 2
        check(g.StartCheck() == true, "gold: (Price my items after the scan)")
        advance(90)
        local header = g.PriceState("crafts")
        check(g.State().state == "idle" and g.State().message == ("Priced %d items. 1 didn't answer."):format(want - 1) and
              header == "Prices: 2 items - full scan 15 min ago, your items looked up just now",
              "gold: the header describes the book - how many items, the scan and the later look-up: " .. header .. " / " ..
              tostring(g.State().message))
        -- pressed once more for the straggler
        P.printed = {}
        P.Slash("gold price")
        advance(5)
        header = g.PriceState("crafts")
        check(Printed(P, "gold: pricing 1 item, about 2 seconds") and g.State().message == "Priced 1 item." and
              header == "Prices: 2 items - full scan 15 min ago, your items looked up just now" and Book(P).checkN == 1,
              "gold: a second press that prices one leftover item doesn't turn the header into \"1 items\": " .. header)
        -- the scan is the later one again
        Shift(P, 900)
        advance(61)
        Scan(P)
        check(g.PriceState("crafts") == "Prices: 1 item - full scan just now",
              "gold: a scan after the look-up: the header names the scan alone (" .. g.PriceState("crafts") .. ")")
        -- forgetting counts what the header counted
        P.printed = {}
        P.Slash("gold forget")
        check(Printed(P, "gold: forgot the prices of 1 item on this realm") and #P.ns.errors == 0,
              "gold: forget reports the items that had a price, as the header counted them, not every none-listed record")
    end
    -- a scan too broken, or cut short, answers for nothing it never saw
    do
        local P = Stock(GP("GoldV3"))
        local g = P.ns.Gold
        Recipe(P, 1, "Runecloth Bag", 14046, {{14048, 5}})
        OpenTrade(P, "Tailoring")
        P.OpenAH()
        P.ah.rows = {Row(14047, 1, 100), Row(14047, 1, 100, {throw = true})}
        Scan(P)
        check(Book(P).full and Rec(P, 14047) and Rec(P, 14046) == nil and Rec(P, 14048) == nil,
              "gold scan: over 5% of the rows unreadable: nothing the scan didn't list is called \"none listed\"")
        -- the list loses two of its hundred rows while it is read
        Shift(P, 900)
        advance(61)
        P.ah.rows = {}
        for i = 1, 100 do P.ah.rows[i] = Row(14047, 1, 100) end
        local AH, calls = P.env.C_AuctionHouse, 0
        local real = AH.GetNumReplicateItems
        AH.GetNumReplicateItems = function()
            calls = calls + 1
            return real() - (calls > 1 and 2 or 0)
        end
        local full = Book(P).full
        Scan(P)
        AH.GetNumReplicateItems = real
        check(g.State().message == "Scan cut short: 1 item read - the auction house's list changed while it was read." and
              Book(P).full == full and Rec(P, 14047).q == 98 and Rec(P, 14046) == nil and Rec(P, 14048) == nil and
              #P.ns.errors == 0,
              "gold scan: a list cut short answers for nothing it never saw either: " .. tostring(g.State().message))
    end
    -- one cheap lot is not what everything sells for
    do
        local P = Stock(GP("GoldV4"))
        local g = P.ns.Gold
        P.items[4338] = {name = "Mageweave Cloth", stack = 20, sell = 250, class = 7, reagent = true}
        P.items[4339] = {name = "Bolt of Mageweave", stack = 20, sell = 1, class = 7, reagent = true}
        setmetatable(P.ah.commodity, {__index = function() return true end})
        Recipe(P, 9, "Unravel", 4338, {{4339, 1}})
        OpenTrade(P, "Tailoring")
        P.bags[0] = {n = 1, [1] = {itemID = 4338, stackCount = 37, quality = 1}}
        P.Fire("BAG_UPDATE_DELAYED")
        P.OpenAH()
        -- three lone units: one far under the vendor's price, two far over
        Listed(P, 4338, {{100, 1}, {5000, 1}, {5100, 1}})
        local sp, flag, passed = g.SellPrice(4338)
        check(sp == 5000 and flag == "unproven" and passed == 1 and
              Has(TipOf(g, BagOf(g, 4338)), "Only 2 listed besides the cheap lot - this is one seller's asking price, not proof it sells."),
              "gold prices: what is left beside a cheap lot is judged on its own: two units are one seller's asking price")
        -- day 1: 160 at the going rate and one stack of 20 at 1s (a vendor pays 2s 50c)
        Listed(P, 4338, {{100, 20}, {380, 60}, {390, 50}, {400, 50}})
        sp, flag, passed = g.SellPrice(4338)
        local row = BagOf(g, 4338)
        local rows = Analyse(P)
        local craft = Find(g.CraftRows(), "id", 4338)
        check(g.Now(4338) == 100 and sp == 380 and flag == nil and passed == 20 and row and row.auction == 13357 and
              row.vendor == 9250 and row.bestHow == "Auction" and row.mark == nil,
              "gold prices: a lot listed under the vendor's price, a quarter of what is listed at most, isn't the selling price: " ..
              tostring(sp) .. " / " .. tostring(row and row.bestText))
        check(Has(TipOf(g, row), "Valued at 3s 80c each - 20 cheaper units are listed below the going rate.") and
              Has(TipOf(g, craft), "Valued at 3s 80c each - 20 cheaper units are listed below the going rate.") and
              craft and craft.sells == 361,
              "gold prices: ... and the Bags and Crafts tooltips say which price was used and what was passed over")
        check(Deal(rows, "Vendor", 4338) and Deal(rows, "Vendor", 4338).units == 20 and g.Cost(4338, 5) == 500,
              "gold prices: ... while Bargains still says to buy that lot, and buying is still costed at it")
        -- exactly a quarter, and one unit more
        Listed(P, 4338, {{100, 45}, {380, 135}})
        sp, flag, passed = g.SellPrice(4338)
        local line = TipOf(g, BagOf(g, 4338))
        Listed(P, 4338, {{100, 46}, {380, 134}})
        local sp2, _, passed2 = g.SellPrice(4338)
        check(sp == 380 and passed == 45 and flag == "unproven" and
              Has(line, "The 135 besides the cheap lot are listed at one price - it may be one seller.") and sp2 == 100 and
              passed2 == 0 and BagOf(g, 4338).bestHow == "Vendor" and not Has(TipOf(g, BagOf(g, 4338)), "Valued at"),
              "gold prices: a quarter of what is listed is still a lot to pass over; more than that is the market")
        -- six cheap price points kept, and what lies beyond them not known: the last of them it is
        do
            local rows = {{100, 1}, {101, 1}, {102, 1}, {103, 1}, {104, 1}, {105, 1}, {380, 994}}
            Listed(P, 4338, rows)
            local price, _, over = g.SellPrice(4338)
            check(Rec(P, 4338).l == "100:1,101:1,102:1,103:1,104:1,105:1" and price == 105 and over == 5 and BagOf(g, 4338) ~= nil,
                  "gold prices: when every price point kept is a cheap one, the last of them is the price - nothing is made up beyond it")
        end
        -- at the vendor's price exactly it is no cheap lot
        Listed(P, 4338, {{250, 20}, {380, 160}})
        check(g.SellPrice(4338) == 250 and select(3, g.SellPrice(4338)) == 0, "gold prices: a lot at what a vendor pays is not passed over")
        -- day 4: three days at 3s 80c, then 40 of 200 at 2s 60c (68% of it, and more than a vendor pays)
        History(P, 4338, {{380, 160}}, 3)
        Listed(P, 4338, {{260, 40}, {380, 160}})
        sp, flag, passed = g.SellPrice(4338)
        rows = Analyse(P)
        local resell = Deal(rows, "Resell", 4338)
        row = BagOf(g, 4338)
        check(g.UsualDeep(4338) == 380 and sp == 380 and flag == nil and passed == 40 and resell and resell.units == 40 and
              resell.upTo == 260 and row.auction == 13357 and row.bestHow == "Auction",
              "gold prices: the units Bargains says to buy up and relist aren't what the bags are valued at")
        Listed(P, 4338, {{270, 40}, {380, 160}})
        check(g.SellPrice(4338) == 270 and select(3, g.SellPrice(4338)) == 0 and #P.ns.errors == 0,
              "gold prices: at 71% of the usual price (and over the vendor's) a lot is the price to beat")
    end
    -- an essence valued as its other size says so, and carries that price's mark
    do
        local EP, NP = Stock(GP("GoldV5")), Stock(GP("GoldV6"))
        EP.knowsDisenchant = true
        for _, P in ipairs({EP, NP}) do
            setmetatable(P.ah.commodity, {__index = function() return true end})
            P.bags[0] = {n = 3, [1] = {itemID = 10939, stackCount = 4, quality = 2}, [2] = {itemID = 10998, stackCount = 6, quality = 2},
                         [3] = {itemID = 3000, stackCount = 2, quality = 1}}
            P.Fire("BAG_UPDATE_DELAYED")
            P.OpenAH()
            History(P, 3000, {{1000, 5}}, 3)
            Listed(P, 3000, {})
            Listed(P, 10939, {{900, 10}, {950, 5}})     -- Greater Magic: 9s, proven
            Listed(P, 10938, {{400, 5}})                -- Lesser Magic: 4s, all at one price
            Listed(P, 10998, {{100, 1}})                -- Lesser Astral: one lone unit
            Listed(P, 11082, {{900, 10}, {950, 5}})     -- Greater Astral: 9s, proven
        end
        local ge, gn = EP.ns.Gold, NP.ns.Gold
        local magic, astral = BagOf(ge, 10939), BagOf(ge, 10998)
        check(magic and magic.auction == 4560 and magic.mark == "unproven" and magic.bestHow == "Auction" and
              Has(TipOf(ge, magic), "Worth more split into 3 Lesser Magic Essence (4s each) - right-click to split, then sell (estimate).") and
              Has(TipOf(ge, magic), "All 5 are listed at one price - it may be one seller."),
              "gold bags: an enchanter's Greater essence worth more as three Lesser: the tooltip says to split, and the Lesser's unproven price marks the row")
        check(astral and astral.auction == 1710 and astral.mark == nil and
              Has(TipOf(ge, astral), "Worth more combined: 3 make one Greater Astral Essence (9s each) - right-click to combine, then sell (estimate).") and
              not Has(TipOf(ge, astral), "Only 1 listed"),
              "gold bags: a Lesser worth more as a third of a Greater: valued so, with the Greater's (proven) price and not its own lone listing's mark")
        local t = ge.BagTotals(ge.BagRows())
        check(t.unproven == 1 and t.auction == 1710 + 1900 and t.best == 1710 + 1900,
              "gold bags: ... and the sum that rests on the unproven Lesser price stays out of the totals (" .. t.text .. ")")
        magic, astral = BagOf(gn, 10939), BagOf(gn, 10998)
        check(magic and magic.auction == 3420 and magic.mark == nil and astral and astral.auction == 570 and
              astral.mark == "unproven" and not Has(TipOf(gn, magic), "Worth more") and not Has(TipOf(gn, astral), "Worth more") and
              Has(TipOf(gn, astral), "Only 1 listed - this is one seller's asking price, not proof it sells."),
              "gold bags: with no enchanter on the account an essence is only ever worth its own price")
        local ore = BagOf(gn, 3000)
        check(ore and ore.mark == "none listed" and ore.auction == 1900 and Has(TipOf(gn, ore), "None listed now - this is its usual price."),
              "gold bags: a stack with none listed now is valued at its usual price, and the tooltip says so")
        -- Vendors: an unproven auction price says what was seen
        NP.npcName = "Trader"
        NP.merchant = {{id = 2589, price = 10}}
        NP.Fire("MERCHANT_SHOW")
        advance(0.5)
        Listed(NP, 2589, {{500, 40}})
        local linen = Find(gn.VendorRows(), "id", 2589)
        check(linen and linen.mark == "unproven" and linen.tip[3] == "All 40 are listed at one price - it may be one seller." and
              #EP.ns.errors == 0 and #NP.ns.errors == 0, "gold vendors: an unproven auction price is explained in the row's tooltip")
    end
    -- a material bargain against a vendor's own price, and the one-unit vendor bargain
    do
        local P = Stock(GP("GoldV7"))
        local g = P.ns.Gold
        setmetatable(P.ah.commodity, {__index = function() return true end})
        Recipe(P, 1, "Oddity", 14046, {{3000, 2}, {7000, 2}})
        OpenTrade(P, "Tailoring")
        P.npcName = "Trader"
        P.merchant = {{id = 3000, price = 1000}, {id = 7000, price = 6000}}
        P.Fire("MERCHANT_SHOW")
        advance(0.5)
        P.OpenAH()
        History(P, 3000, {{5000, 30}}, 3)
        History(P, 7000, {{5000, 30}}, 3)
        -- Odd Ore: usually 50s, a vendor sells it for 10s; listed under, at and over the vendor's price
        Listed(P, 3000, {{900, 20}, {1000, 10}, {3000, 10}, {5000, 30}})
        -- Linen Scrap: usually 50s, the vendor is dearer (60s)
        Listed(P, 7000, {{3000, 10}, {5000, 30}})
        Listed(P, 8170, {{300, 1}, {600, 5}})
        local rows = Analyse(P)
        local ore, scrap, one = Deal(rows, "Material", 3000), Deal(rows, "Material", 7000), Deal(rows, "Vendor", 8170)
        check(g.Usual(3000) == 5000 and select(2, g.VendorBuy(3000)) == "vendor" and ore and ore.units == 20 and ore.upTo == 900 and
              ore.worth == 1000 and ore.profit == 2000 and ore.estimate == nil,
              "gold bargains: of a material a vendor sells, only the units strictly under the vendor's price are a bargain (" ..
              tostring(ore and ore.units) .. " units)")
        check(ore and g.Tip(ore)[1] == "Usually 50s each, and a vendor sells them for 10s; these are below both. The profit shown is what you save on the vendor's price.",
              "gold bargains: ... a visited merchant's price is stated as the vendor's")
        check(scrap and scrap.units == 10 and scrap.worth == 5000 and scrap.profit == 20000 and
              g.Tip(scrap)[1] == "Usually 50s each; these are at 80% of that or less. The profit shown is what you save.",
              "gold bargains: a vendor dearer than the usual price isn't mentioned: the saving is against the usual price")
        local tip = one and g.Tip(one) or {}
        check(one and one.units == 1 and tip[1] == "A vendor pays 5s each; 1 listed for less." and
              tip[#tip - 1] == "Buy it (up to 3s), then sell it to any vendor." and #P.ns.errors == 0,
              "gold bargains: a vendor bargain of one unit is worded for one: " .. tostring(tip[#tip - 1]))
    end
    -- our own auctions, when a scan couldn't tell whose they were
    do
        local P = Stock(GP("GoldV8"))
        local g = P.ns.Gold
        setmetatable(P.ah.commodity, {__index = function() return true end})
        P.ah.commodity[14046], P.ah.commodity[17000] = false, false
        for id in pairs(P.ns.GoldData.seed) do P.ns.GoldData.seed[id] = nil end
        P.items[14046].sell = 100
        Recipe(P, 1, "Runecloth Bag", 14046, {{14048, 5}})
        OpenTrade(P, "Tailoring")
        P.OpenAH()
        -- two bags of ours at 1g 25s among six listed; no row names its owner
        P.ah.rows = {Row(14046, 1, 12500, {owner = false}), Row(14046, 1, 12500, {owner = false}),
                     Row(14046, 1, 13000, {owner = false}), Row(14046, 1, 13100, {owner = false}),
                     Row(14046, 1, 13200, {owner = false}), Row(14046, 1, 13300, {owner = false}),
                     Row(14048, 20, 18000, {owner = false}), Row(14048, 5, 4750, {owner = false}),
                     -- (and, ours too: all the Odd Ore there is, and a pair of gloves "of the Whale")
                     Row(3000, 5, 500, {owner = false}), Row(17000, 1, 40000, {owner = false, link = Link(17000, 7)})}
        Scan(P)
        check(Book(P).noOwners == Book(P).full and g.State().hint == "Your own auctions may be counted - open your Auctions tab once.",
              "gold: (a scan that named no owner: the hint)")
        P.ah.owned = {{itemKey = {itemID = 14046}, quantity = 1, buyoutAmount = 12500},
                      {itemKey = {itemID = 14046}, quantity = 1, buyoutAmount = 12500},
                      {itemKey = {itemID = 3000}, quantity = 5, buyoutAmount = 500},
                      {itemKey = {itemID = 17000}, quantity = 1, buyoutAmount = 40000}}
        P.Fire("OWNED_AUCTIONS_UPDATED")
        local bag = Find(g.CraftRows(), "id", 14046)
        check(Rec(P, 14046).q == 6 and bag and bag.listed == 6 and
              Has(TipOf(g, bag), "Listed: 6 - your own 2 may be among them, and the price may be yours. Press Price my items to put that right.") and
              not Has(TipOf(g, bag), "not counting"),
              "gold crafts: a count read before our own auctions were known doesn't claim to leave them out")
        check(g.State().hint == "Your own auctions are still counted in 3 prices - press Price my items." and Book(P).noOwners ~= nil,
              "gold: opening the Auctions tab doesn't end the warning while a price still counts ours: " .. tostring(g.State().hint))
        -- Price my items seconds after the scan: those three are looked up all the same - the ore and the
        -- gloves though no recipe and no bag has them - and nothing else is
        local function Mine(buyout, mine)
            return {quantity = 1, buyoutAmount = buyout, containsOwnerItem = mine, itemKey = {itemID = 14046, itemSuffix = 0}}
        end
        P.ah.results[14046] = {Mine(12500, true), Mine(12500, true), Mine(13000), Mine(13100), Mine(13200), Mine(13300)}
        P.ah.results[3000] = {{quantity = 5, unitPrice = 100, numOwnerItems = 5}}
        P.ah.results[17000] = {{quantity = 1, buyoutAmount = 40000, containsOwnerItem = true, itemKey = {itemID = 17000, itemSuffix = 7}}}
        P.ah.sends = {}
        check(Has(g.State().check.tip, "About 4 seconds.") and g.StartCheck() == true, "gold: (Price my items is offered for them)")
        advance(0.5)
        check(g.State().hint == "Your own auctions are still counted in 2 prices - press Price my items.",
              "gold: (the warning counts down as they are looked up: " .. tostring(g.State().hint) .. ")")
        advance(10)
        bag = Find(g.CraftRows(), "id", 14046)
        check(#P.ah.sends == 3 and P.ah.sends[1].id == 3000 and P.ah.sends[2].id == 14046 and P.ah.sends[3].id == 17000 and
              Rec(P, 3000).q == 0 and Rec(P, "17000:7").q == 0 and Rec(P, 17000).q == 0,
              "gold check: every item whose price still counts our own auctions is looked up, first, and what was only ours is none listed")
        check(Rec(P, 14046).q == 4 and Rec(P, 14046).m == 13000 and
              Rec(P, 14046).s == "c" and bag and bag.listed == 4 and bag.sells == 12350,
              "gold check: an item whose price still counts our own auctions is priced again though it was scanned a moment ago")
        check(g.State().hint == nil and Book(P).noOwners == nil and Has(TipOf(g, bag), "Listed: 4, not counting 2 of yours") and
              #P.ns.errors == 0, "gold: ... after which the count leaves ours out, says so, and the warning is gone")
    end
    -- which prices still count our own: only what the ownerless scan itself wrote
    do
        local P = Stock(GP("GoldV8b"))
        local g = P.ns.Gold
        setmetatable(P.ah.commodity, {__index = function() return true end})
        P.OpenAH()
        -- a first scan that names its owners; then one that doesn't, too broken to call the leather sold out
        P.ah.rows = {Row(8170, 5, 2500)}
        Scan(P)
        Shift(P, 900)
        advance(61)
        P.ah.rows = {Row(3000, 5, 500, {owner = false}), Row(14047, 5, 500, {owner = false}), Row(14047, 1, 1, {throw = true})}
        Scan(P)
        local at = Book(P).noOwners
        P.ah.owned = {{itemKey = {itemID = 3000}, quantity = 5, buyoutAmount = 500},
                      {itemKey = {itemID = 14047}, quantity = 5, buyoutAmount = 500},
                      {itemKey = {itemID = 8170}, quantity = 5, buyoutAmount = 2500}}
        P.Fire("OWNED_AUCTIONS_UPDATED")
        check(at and Rec(P, 8170).q == 5 and Rec(P, 8170).t < at and
              g.State().hint == "Your own auctions are still counted in 2 prices - press Price my items.",
              "gold: a price an earlier scan read, with its owners named, isn't one that counts ours: " .. tostring(g.State().hint))
        -- the player's own search of one of them, in the very second the scan was written
        local back = P.env.time() - at
        Shift(P, -back)
        Listed(P, 3000, {{100, 5}, {110, 5}})
        Shift(P, back)
        check(Rec(P, 3000).t == at and Rec(P, 3000).s == "c" and
              g.State().hint == "Your own auctions are still counted in 1 price - press Price my items." and #P.ns.errors == 0,
              "gold: ... nor is one a look-up has read since, whenever that was: " .. tostring(g.State().hint))
    end
    -- the warning is the book's, and only shows where it can be acted on
    do
        local P = Stock(GP("GoldV9"))
        P.OpenAH()
        P.ah.rows = {Row(14047, 5, 500, {owner = false})}
        Scan(P)
        check(P.ns.Gold.State().hint ~= nil, "gold: (an ownerless scan: the hint, at the auction house)")
        P.CloseAH()
        check(P.ns.Gold.State().hint == nil, "gold: away from the auction house the hint about own auctions isn't shown")
        P = Reload(P)
        table.insert(gone, P)
        check(P.ns.Gold.State().hint == nil and Book(P).noOwners ~= nil, "gold: ... nor after a login in the field")
        P.OpenAH()
        check(P.ns.Gold.State().hint == "Your own auctions may be counted - open your Auctions tab once.",
              "gold: back at the auction house it is: the book remembers that its scan couldn't tell")
        -- the Auctions tab, with nothing of ours in what the scan read: settled for good
        P.ah.owned = {}
        P.Fire("OWNED_AUCTIONS_UPDATED")
        check(P.ns.Gold.State().hint == nil and Book(P).noOwners == nil, "gold: the Auctions tab seen and nothing of ours counted: no warning")
        P = Reload(P)
        table.insert(gone, P)
        P.OpenAH()
        check(P.ns.Gold.State().hint == nil, "gold: ... and none at the next login either")
        -- a scan whose rows do name their owners never warns, in this session or the next
        Shift(P, 900)
        P.ah.rows = {Row(14047, 5, 500)}
        Scan(P)
        local full = Book(P).full
        P = Reload(P)
        table.insert(gone, P)
        P.OpenAH()
        check(full and Book(P).full == full and Book(P).noOwners == nil and P.ns.Gold.State().hint == nil and #P.ns.errors == 0,
              "gold: a scan that did tell our auctions apart leaves no warning for the next login")
    end
    -- a scan that never finished
    do
        local P = Stock(GP("GoldV10"))
        P.OpenAH()
        P.ah.rows = {Row(14047, 5, 500)}
        P.ah.replicateDelay = 30
        check(P.ns.Gold.StartScan() == true and Book(P).fullPending == true, "gold scan: (asked, the list still to come)")
        advance(1)
        P = Reload(P)
        table.insert(gone, P)
        local g = P.ns.Gold
        local st = g.State()
        check(st.state == "idle" and st.scan.label == "Scan (in 15 min)" and
              st.message == "The last scan didn't finish - the game allows another in 15 min. Price my items works meanwhile.",
              "gold scan: a /reload during a scan: the window says the scan was lost and what still works: " .. tostring(st.message))
        Shift(P, 600)
        check(g.State().message == "The last scan didn't finish - the game allows another in 5 min. Price my items works meanwhile.",
              "gold scan: ... counting down with the button (" .. tostring(g.State().message) .. ")")
        P.Slash("gold off")
        check(g.State().message == nil, "gold scan: ... not while the feature is off")
        P.Slash("gold on")
        Shift(P, 300)
        check(g.State().message == nil and g.State().scan.label == "Scan", "gold scan: ... and gone when a scan may be asked again")
        -- a finished scan leaves nothing to say after a /reload
        P.OpenAH()
        P.ah.rows = {Row(14047, 5, 500)}
        Scan(P)
        check(Book(P).full and Book(P).fullPending == nil and g.State().message == "Scan finished: 1 item.", "gold scan: (a scan read to the end)")
        -- (a message that isn't about a job goes when the feature is switched off)
        P.Slash("gold off")
        P.Slash("gold on")
        check(g.State().message == nil, "gold: switching the feature off drops what the last job said")
        P = Reload(P)
        table.insert(gone, P)
        g = P.ns.Gold
        check(g.State().message == nil and g.State().scan.label == "Scan (in 15 min)",
              "gold scan: after a finished scan a /reload shows only the wait")
        -- forgetting the prices during the wait doesn't make the scan \"unfinished\"
        Shift(P, 900)
        P.OpenAH()
        P.ah.replicateDelay = 30
        g.StartScan()
        advance(1)
        P.Slash("gold forget")
        check(g.State().message == nil and g.State().scan.label == "Scan (in 15 min)" and #P.ns.errors == 0,
              "gold scan: prices forgotten mid-scan: the wait stays, with nothing said about a lost scan")
    end
    -- small texts: what an unproven price says, singulars, a guessed essence cost
    do
        local P = Stock(GP("GoldV11"))
        local g = P.ns.Gold
        P.knowsDisenchant = true
        setmetatable(P.ah.commodity, {__index = function() return true end})
        Recipe(P, 1, "Lesser Magic Wand", 14046, {{10938, 6}})
        OpenTrade(P, "Enchanting")
        P.bags[0] = {n = 2, [1] = {itemID = 3000, stackCount = 2, quality = 1}, [2] = {itemID = 7000, stackCount = 2, quality = 1}}
        P.Fire("BAG_UPDATE_DELAYED")
        P.OpenAH()
        -- an answer cut short that showed two units: there may be more
        Listed(P, 7000, {{500, 1}, {510, 1}}, false)
        check(Rec(P, 7000).p == true and Has(TipOf(g, BagOf(g, 7000)), "Only 2+ listed - this is one seller's asking price, not proof it sells."),
              "gold prices: two units of a partial answer are \"2+\" listed")
        -- six Lesser from two Greater, with only one Greater listed
        Listed(P, 10938, {{1500, 10}, {1600, 5}})
        Listed(P, 10939, {{2400, 1}})
        local c, from, flag = g.Cost(10938, 6)
        local wand = Find(g.CraftRows(), "id", 14046)
        check(c == 4800 and from == "buy Greater and split" and flag == "materials partly at a guessed price" and
              Has(TipOf(g, wand), "6 x Lesser Magic Essence: 48s (buy Greater and split, materials partly at a guessed price)"),
              "gold cost: an essence costed through its other size past what is listed is said to be partly a guess")
        -- one conversion that keeps 10 silver
        Listed(P, 10939, {{2000, 10}, {2100, 5}})
        Listed(P, 10938, {{300, 3}, {2000, 5}})
        local rows = Analyse(P)
        local e = Deal(rows, "Essence", 10938)
        check(e and e.units == 1 and g.Tip(e)[2] == "Units counts conversions (3 Lesser each): 1 keeps 10s or more each.",
              "gold bargains: one conversion \"keeps\" 10s: " .. tostring(e and g.Tip(e)[2]))
        -- a record of two units, two days old, and Auctionator's newer price for the item
        Listed(P, 3000, {{500, 1}, {510, 1}})
        check(Has(TipOf(g, BagOf(g, 3000)), "Only 2 listed - this is one seller's asking price"), "gold prices: (two units seen now)")
        Shift(P, 49 * 3600)
        P.SetAuctionator({prices = {[3000] = 400}, ages = {[3000] = 0}})
        local ore = BagOf(g, 3000)
        check(ore and ore.mark == "unproven" and ore.auction == 760 and
              Has(TipOf(g, ore), "Lowest price only - how many sell at it isn't known.") and not Has(TipOf(g, ore), "Only 2 listed") and
              #P.ns.errors == 0,
              "gold prices: a two-day-old record says nothing about what is listed now: Auctionator's price is only a lowest price")
        P.SetAuctionator(nil)
    end
    -- Price my items: items still loading don't hold up one that is ready
    do
        local P = Stock(GP("GoldV12"))
        local g = P.ns.Gold
        for id in pairs(P.ns.GoldData.seed) do P.ns.GoldData.seed[id] = nil end
        P.ah.commodity[14047] = true
        P.items[59001] = {name = "Slow A", stack = 20, class = 7, loaded = false}
        P.items[59002] = {name = "Slow B", stack = 20, class = 7, loaded = false}
        local request = P.env.C_Item.RequestLoadItemDataByID
        P.env.C_Item.RequestLoadItemDataByID = function() end
        P.bags[0] = {n = 3, [1] = {itemID = 59001, stackCount = 1, quality = 1}, [2] = {itemID = 59002, stackCount = 1, quality = 1},
                     [3] = {itemID = 14047, stackCount = 5, quality = 1}}
        P.Fire("BAG_UPDATE_DELAYED")
        P.OpenAH()
        P.ah.results[14047] = {{quantity = 5, unitPrice = 70, numOwnerItems = 0}}
        advance(1)
        local t0 = P.env.GetTime()
        check(g.StartCheck() == true, "gold check: (two items still loading ahead of one that is ready)")
        advance(0.05)
        check(#P.ah.sends == 1 and P.ah.sends[1].id == 14047 and P.ah.sends[1].t == t0,
              "gold check: the ready item's query goes out at once, not 0.3 s behind each item still loading")
        local ticks = P.tick
        advance(2)
        check(g.State().state == "checking" and P.tick - ticks <= 20,
              "gold check: with only loading items left it looks again a few times a second, no more (" .. (P.tick - ticks) .. " timers in 2 s)")
        advance(5)
        check(g.State().state == "idle" and g.State().message == "Priced 1 item. 2 didn't answer." and #P.ns.errors == 0,
              "gold check: ... and gives them up after a few seconds: " .. tostring(g.State().message))
        P.env.C_Item.RequestLoadItemDataByID = request
    end
    -- Your bags: greys, things with no vendor value, what to keep; bargains by quality
    do
        local P = Stock(GP("GoldV13"))
        local g = P.ns.Gold
        P.knowsDisenchant = true
        setmetatable(P.ah.commodity, {__index = function() return true end})
        P.items[61001] = {name = "Broken Fang", quality = 0, stack = 20, sell = 30, class = 15}
        P.items[61002] = {name = "Keepsake", quality = 1, stack = 1, sell = 500, class = 15}
        P.items[61003] = {name = "Blue Blade", quality = 3, ilvl = 58, sell = 100, class = 2, bind = 2}
        P.items[61004] = {name = "Purple Helm", quality = 4, ilvl = 60, sell = 100, class = 4, bind = 2}
        P.items[61005] = {name = "White Sword", quality = 1, ilvl = 58, sell = 100, class = 2, bind = 2}
        P.items[61006] = {name = "Orange Sword", quality = 5, ilvl = 60, sell = 100, class = 2, bind = 2}
        for _, id in ipairs({61003, 61004, 61005, 61006}) do P.ah.commodity[id] = false end
        -- one craft that pays (bolts from cloth) and one that loses (a bag from leather)
        Recipe(P, 1, "Bolt of Runecloth", 14048, {{14047, 5}})
        Recipe(P, 2, "Leather Sack", 14046, {{8170, 10}})
        OpenTrade(P, "Tailoring")
        P.bags[0] = {n = 4, [1] = {itemID = 61001, stackCount = 5, quality = 0},
                     [2] = {itemID = 61002, stackCount = 1, quality = 1, hasNoValue = true},
                     [3] = {itemID = 14047, stackCount = 5, quality = 1}, [4] = {itemID = 8170, stackCount = 5, quality = 1}}
        P.Fire("BAG_UPDATE_DELAYED")
        P.OpenAH()
        Listed(P, 14047, {{100, 50}, {110, 50}})
        Listed(P, 14048, {{900, 20}, {950, 5}})
        Listed(P, 8170, {{5000, 20}, {5100, 20}})
        Listed(P, 14046, {{30000, 3}, {31000, 3}})
        Listed(P, 61001, {{100, 5}, {110, 5}})
        Listed(P, 61002, {{900, 5}, {950, 5}})
        local grey, keepsake, cloth, leather = BagOf(g, 61001), BagOf(g, 61002), BagOf(g, 14047), BagOf(g, 8170)
        check(grey and grey.confident == true and grey.auction == nil and grey.auctionText == nil and grey.bestHow == "Vendor" and
              grey.best == 150, "gold bags: a grey item is never auctioned, whatever is listed: its best is the vendor")
        check(keepsake and keepsake.vendor == nil and keepsake.auction == 855 and keepsake.bestHow == "Auction",
              "gold bags: a thing the game says has no vendor value gets no vendor sum")
        local bolt, sack = Find(g.CraftRows(), "id", 14048), Find(g.CraftRows(), "id", 14046)
        check(bolt and bolt.profit and bolt.profit > 0 and sack and sack.profit and sack.profit < 0 and cloth and
              cloth.keep == "Bolt of Runecloth" and Has(TipOf(g, cloth), "or keep it: Bolt of Runecloth uses it") and leather and
              leather.keep == nil and not Has(TipOf(g, leather), "keep it"),
              "gold bags: \"keep it\" is only said for a craft that makes a profit")
        -- disenchanting bargains: rare and epic gear, never a white or an orange piece
        Listed(P, 14344, {{50000, 10}, {51000, 5}})
        Listed(P, 20725, {{80000, 3}, {81000, 3}})
        for _, id in ipairs({61003, 61004, 61005, 61006}) do ListedGear(P, id, {{1000}}) end
        local rows = Analyse(P)
        check(Deal(rows, "Disenchant", 61003) and Deal(rows, "Disenchant", 61004) and Deal(rows, "Disenchant", 61004).worth == 76000 and
              Deal(rows, "Disenchant", 61005) == nil and Deal(rows, "Disenchant", 61006) == nil and #P.ns.errors == 0,
              "gold bargains: rare and epic gear under its disenchant value is offered; common and legendary gear never is")
    end
    -- the built-in tables, as they were written down (a slip in one changes every estimate in its band)
    do
        local P = GP("GoldV14")
        local D = P.ns.GoldData
        local function Same(a, b)
            if type(a) ~= "table" or type(b) ~= "table" then return a == b end
            for k, v in pairs(a) do if not Same(v, b[k]) then return false end end
            for k in pairs(b) do if a[k] == nil then return false end end
            return true
        end
        local function Rows(name, want)
            local got = D[name] or {}
            for i = 1, math.max(#want, #got) do
                check(Same(want[i], got[i]), ("gold data: %s, row %d (%s)"):format(name, i,
                      want[i] and (tostring(want[i][1]) .. (want[i][2] and ("-" .. tostring(want[i][2])) or "")) or "one too many"))
            end
        end
        Rows("essences", {{10938, 10939}, {10998, 11082}, {11134, 11135}, {11174, 11175}, {16202, 16203}})
        Rows("uncommon", {
            {5, 15, 10940, 1, 2, 10938, 1, 2, false, 0.80, 0.20, 0, 0.20, 0.80, 0},
            {16, 20, 10940, 2, 3, 10939, 1, 2, 10978, 0.75, 0.20, 0.05, 0.20, 0.75, 0.05},
            {21, 25, 10940, 4, 6, 10998, 1, 2, 10978, 0.75, 0.15, 0.10, 0.15, 0.75, 0.10},
            {26, 30, 11083, 1, 2, 11082, 1, 2, 11084, 0.75, 0.20, 0.05, 0.20, 0.75, 0.05},
            {31, 35, 11083, 2, 5, 11134, 1, 2, 11138, 0.75, 0.20, 0.05, 0.20, 0.75, 0.05},
            {36, 40, 11137, 1, 2, 11135, 1, 2, 11139, 0.75, 0.20, 0.05, 0.20, 0.75, 0.05},
            {41, 45, 11137, 2, 5, 11174, 1, 2, 11177, 0.75, 0.20, 0.05, 0.20, 0.75, 0.05},
            {46, 50, 11176, 1, 2, 11175, 1, 2, 11178, 0.75, 0.20, 0.05, 0.20, 0.75, 0.05},
            {51, 55, 11176, 2, 5, 16202, 1, 2, 14343, 0.75, 0.20, 0.05, 0.20, 0.75, 0.05},
            {56, 60, 16204, 1, 2, 16203, 1, 2, 14344, 0.75, 0.20, 0.05, 0.20, 0.75, 0.05},
            {61, 65, 16204, 2, 5, 16203, 2, 3, 14344, 0.75, 0.20, 0.05, 0.20, 0.75, 0.05}})
        Rows("rare", {{1, 25, 10978, 1}, {26, 30, 11084, 1}, {31, 35, 11138, 1}, {36, 40, 11139, 1}, {41, 45, 11177, 1},
                      {46, 50, 11178, 1}, {51, 55, 14343, 1}, {56, 65, 14344, 0.995, 20725, 0.005}})
        Rows("epic", {{40, 45, 11177, 2, 4}, {46, 50, 11178, 2, 4}, {51, 55, 14343, 2, 4}, {56, 60, 20725, 1, 1}, {61, 999, 20725, 1, 2}})
        Rows("skill", {{20, 1}, {25, 25}, {30, 50}, {35, 75}, {40, 100}, {45, 125}, {50, 150}, {55, 175}, {60, 200}, {65, 225}})
        local SEED = {[2320] = 10, [2321] = 100, [4291] = 500, [8343] = 2000, [14341] = 5000, [2604] = 50, [6260] = 50, [2605] = 100,
                      [4340] = 350, [4341] = 500, [6261] = 1000, [2325] = 1000, [4342] = 2500, [10290] = 2500, [2324] = 25,
                      [4289] = 50, [2880] = 100, [3466] = 2000, [18567] = 150000, [4399] = 200, [4400] = 2000, [10647] = 2000,
                      [3371] = 4, [3372] = 40, [8925] = 500, [18256] = 4000, [6217] = 124, [4470] = 38, [11291] = 4500, [2678] = 2,
                      [2692] = 40, [3713] = 160, [2665] = 20, [159] = 5, [1179] = 25, [2894] = 50, [6530] = 100, [6529] = 50,
                      [2928] = 20, [2930] = 50, [5173] = 100, [8924] = 100, [8923] = 200, [3777] = 40}
        local wrong = {}
        for id, price in pairs(SEED) do if D.seed[id] ~= price then wrong[#wrong + 1] = id end end
        for id in pairs(D.seed) do if SEED[id] == nil then wrong[#wrong + 1] = id end end
        table.sort(wrong)
        check(#wrong == 0, "gold data: the built-in vendor prices (differing: " .. table.concat(wrong, ", ") .. ")")
        check(#D.materials == 24 and Same(D.materials, {10940, 11083, 11137, 11176, 16204, 10938, 10939, 10998, 11082, 11134, 11135,
                                                         11174, 11175, 16202, 16203, 10978, 11084, 11138, 11139, 11177, 11178,
                                                         14343, 14344, 20725}), "gold data: the 24 enchanting materials")
    end

    ----------------------------------------------------------------------
    -- fourth review, 1: edges of the rules above that no check held down
    ----------------------------------------------------------------------
    do
        local function X(cond, label) check(cond, "gold edges: " .. label) end
        -- K1: our own look-up of a plain piece of gear that IS listed keeps its price
        do
            local P = Stock(GP("GoldXK1"))
            local g = P.ns.Gold
            setmetatable(P.ah.commodity, {__index = function() return true end})
            P.ah.commodity[17000] = false
            for id in pairs(P.ns.GoldData.seed) do P.ns.GoldData.seed[id] = nil end
            P.bags[0] = {n = 1, [1] = {itemID = 17000, stackCount = 1, quality = 2, hyperlink = Link(17000, 0)}}
            P.Fire("BAG_UPDATE_DELAYED")
            P.OpenAH()
            g.Listen(function() g.State() end)
            -- an ownerless scan: one "of the Whale" of ours and one of somebody's
            P.ah.rows = {Row(17000, 1, 40000, {owner = false, link = Link(17000, 7)}), Row(17000, 1, 41000, {owner = false, link = Link(17000, 7)}),
                         Row(17000, 1, 30000, {owner = false, link = Link(17000, 0)})}
            Scan(P)
            P.ah.owned = {{itemKey = {itemID = 17000}, quantity = 1, buyoutAmount = 40000}}
            P.Fire("OWNED_AUCTIONS_UPDATED")
            advance(0.1)
            X(g.State().hint == "Your own auctions are still counted in 2 prices - press Price my items.", "K1 setup: " .. tostring(g.State().hint))
            P.ah.results[17000] = {{quantity = 1, buyoutAmount = 40000, containsOwnerItem = true, itemKey = {itemID = 17000, itemSuffix = 7}},
                                   {quantity = 1, buyoutAmount = 41000, itemKey = {itemID = 17000, itemSuffix = 7}},
                                   {quantity = 1, buyoutAmount = 30000, itemKey = {itemID = 17000, itemSuffix = 0}},
                                   {quantity = 1, buyoutAmount = 31000, itemKey = {itemID = 17000, itemSuffix = 0}}}
            g.StartCheck()
            advance(10)
            X(Rec(P, 17000) and Rec(P, 17000).q == 2 and Rec(P, 17000).m == 30000,
              "K1a: a listed plain piece keeps its price after our look-up: q=" .. tostring(Rec(P, 17000) and Rec(P, 17000).q))
            X(Rec(P, "17000:7") and Rec(P, "17000:7").q == 1 and Rec(P, "17000:7").m == 41000,
              "K1b: a suffix that counted ours and is still listed by someone keeps the other's price: q=" ..
              tostring(Rec(P, "17000:7") and Rec(P, "17000:7").q))
        end
        -- K2: a craft with no cheap lot has no "Valued at" line
        do
            local P = Stock(GP("GoldXK2"))
            local g = P.ns.Gold
            setmetatable(P.ah.commodity, {__index = function() return true end})
            Recipe(P, 1, "Bolt", 14048, {{14047, 5}})
            OpenTrade(P, "Tailoring")
            P.bags[0] = {n = 1, [1] = {itemID = 14048, stackCount = 3, quality = 1}}
            P.Fire("BAG_UPDATE_DELAYED")
            P.OpenAH()
            Listed(P, 14048, {{3000, 10}, {3100, 10}})
            X(not Has(TipOf(g, Find(g.CraftRows(), "id", 14048)), "Valued at"), "K2a: Crafts tooltip, nothing passed over: no \"Valued at\" line")
            X(not Has(TipOf(g, BagOf(g, 14048)), "Valued at"), "K2b: Bags tooltip, nothing passed over: no \"Valued at\" line")
        end
        -- K3: the header's orange flag
        do
            local P = Stock(GP("GoldXK3"))
            local g = P.ns.Gold
            setmetatable(P.ah.commodity, {__index = function() return true end})
            for id in pairs(P.ns.GoldData.seed) do P.ns.GoldData.seed[id] = nil end
            P.bags[0] = {n = 1, [1] = {itemID = 14047, stackCount = 3, quality = 1}}
            P.Fire("BAG_UPDATE_DELAYED")
            P.OpenAH()
            -- (the harness's calendar starts near zero: move it on, as the game's is)
            Shift(P, 100 * 86400)
            P.ah.rows = {Row(14047, 5, 500), Row(14047, 5, 600)}
            Scan(P)
            local text, old = g.PriceState("bags")
            X(old == false, "K3a: straight after a full scan the header isn't orange: " .. tostring(text))
            Shift(P, 49 * 3600)
            text, old = g.PriceState("bags")
            X(old == true, "K3b: 49 hours on it is: " .. tostring(text))
            P.ah.results[14047] = {{quantity = 5, unitPrice = 100, numOwnerItems = 0}, {quantity = 5, unitPrice = 110, numOwnerItems = 0}}
            g.StartCheck()
            advance(10)
            text, old = g.PriceState("bags")
            X(old == false, "K3c: ... and not any more once Price my items has run: " .. tostring(text))
        end
        -- K4: the "open your Auctions tab" warning survives a Price my items when the tab was never opened
        do
            local P = Stock(GP("GoldXK4"))
            local g = P.ns.Gold
            setmetatable(P.ah.commodity, {__index = function() return true end})
            for id in pairs(P.ns.GoldData.seed) do P.ns.GoldData.seed[id] = nil end
            P.bags[0] = {n = 1, [1] = {itemID = 14047, stackCount = 3, quality = 1}}
            P.Fire("BAG_UPDATE_DELAYED")
            P.OpenAH()
            P.ah.rows = {Row(14047, 5, 500, {owner = false}), Row(3000, 5, 500, {owner = false})}
            Scan(P)
            Shift(P, 601)
            P.ah.results[14047] = {{quantity = 5, unitPrice = 100, numOwnerItems = 0}}
            g.StartCheck()
            advance(10)
            X(g.State().state == "idle" and Book(P).noOwners ~= nil and
              g.State().hint == "Your own auctions may be counted - open your Auctions tab once.",
              "K4: Price my items without the Auctions tab ever seen doesn't end the warning: " .. tostring(g.State().hint))
        end
        -- K5: a stopped price check that already re-priced the last own-counted item settles the warning
        do
            local P = Stock(GP("GoldXK5"))
            local g = P.ns.Gold
            setmetatable(P.ah.commodity, {__index = function() return true end})
            for id in pairs(P.ns.GoldData.seed) do P.ns.GoldData.seed[id] = nil end
            P.bags[0] = {n = 2, [1] = {itemID = 14047, stackCount = 3, quality = 1}, [2] = {itemID = 8170, stackCount = 3, quality = 1}}
            P.Fire("BAG_UPDATE_DELAYED")
            P.OpenAH()
            P.ah.rows = {Row(3000, 5, 500, {owner = false}), Row(3000, 5, 600, {owner = false})}
            Scan(P)
            P.ah.owned = {{itemKey = {itemID = 3000}, quantity = 5, buyoutAmount = 500}}
            P.Fire("OWNED_AUCTIONS_UPDATED")
            Shift(P, 601)
            P.ah.results[3000] = {{quantity = 5, unitPrice = 100, numOwnerItems = 5}, {quantity = 5, unitPrice = 120, numOwnerItems = 0}}
            g.StartCheck()
            advance(0.5)
            local mid = Rec(P, 3000).s
            g.StopCheck()
            X(mid == "c" and g.State().state == "idle" and Book(P).noOwners == nil,
              "K5: a price check stopped after it re-read our item: the book no longer remembers the ownerless scan (" ..
              tostring(mid) .. ", " .. tostring(Book(P).noOwners) .. ")")
        end
        -- K6: the going rate's edges
        do
            local P = Stock(GP("GoldXK6"))
            local g = P.ns.Gold
            P.items[4338] = {name = "Mageweave Cloth", stack = 20, sell = 250, class = 7, reagent = true}
            setmetatable(P.ah.commodity, {__index = function() return true end})
            P.bags[0] = {n = 1, [1] = {itemID = 4338, stackCount = 37, quality = 1}}
            P.Fire("BAG_UPDATE_DELAYED")
            P.OpenAH()
            Listed(P, 4338, {{100, 1}, {5000, 1}, {5100, 1}})
            X(Has(TipOf(g, BagOf(g, 4338)), "Valued at 50s each - 1 cheaper unit is listed below the going rate."),
              "K6a: one unit passed over is worded for one")
            Listed(P, 4338, {{100, 20}, {110, 20}, {380, 80}})
            local sp, _, passed = g.SellPrice(4338)
            X(sp == 110 and passed == 20, "K6b: two cheap lots that together are over a quarter: only the first is passed over (" ..
              tostring(sp) .. ", " .. tostring(passed) .. ")")
            Listed(P, 4338, {{100, 3}, {380, 7}})
            sp, _, passed = g.SellPrice(4338)
            X(sp == 100 and passed == 0, "K6c: 3 of 10 is more than a quarter (" .. tostring(sp) .. ", " .. tostring(passed) .. ")")
            -- thin history (4 listed a day: never 5): a usual price, but no deep one
            History(P, 4338, {{380, 2}, {390, 2}}, 3)
            Listed(P, 4338, {{260, 40}, {380, 160}})
            sp, _, passed = g.SellPrice(4338)
            X(g.Usual(4338) == 380 and g.UsualDeep(4338) == nil and sp == 260 and passed == 0,
              "K6d: a usual price from thin days only passes nothing over (" .. tostring(sp) .. ", " .. tostring(passed) .. ")")
            Listed(P, 4338, {{5000, 1}, {5100, 1}})
            local _, flag = g.SellPrice(4338)
            X(flag == "unproven", "K6e: two units, a usual price from thin days: still unproven (" .. tostring(flag) .. ")")
            Listed(P, 4338, {{100, 1}, {5000, 1}, {5100, 1}})
            sp, flag, passed = g.SellPrice(4338)
            X(flag == "unproven" and passed == 1, "K6f: ... and so are the two left beside a cheap lot, which is still reported (" ..
              tostring(flag) .. ", " .. tostring(passed) .. ")")
            -- three deep days at 3s 80c; a lot at exactly 70% of it
            History(P, 4338, {{380, 160}}, 14)
            Listed(P, 4338, {{266, 40}, {380, 160}})
            sp, _, passed = g.SellPrice(4338)
            X(g.UsualDeep(4338) == 380 and sp == 380 and passed == 40, "K6g: a lot at exactly 70% of the usual price is passed over (" ..
              tostring(sp) .. ", " .. tostring(passed) .. ")")
            -- K9: a vendor bargain of two units isn't worded for one
            Listed(P, 4338, {{100, 2}, {380, 160}})
            local two = Deal(Analyse(P), "Vendor", 4338)
            local tip = two and g.Tip(two) or {}
            X(two and two.units == 2 and tip[#tip - 1] == "Buy the 2 cheapest (up to 1s each), then sell them to any vendor.",
              "K9: a vendor bargain of two units: " .. tostring(tip[#tip - 1]))
        end
        -- K7: a built-in vendor price above the usual price isn't mentioned, and the row is no estimate
        do
            local P = Stock(GP("GoldXK7"))
            local g = P.ns.Gold
            setmetatable(P.ah.commodity, {__index = function() return true end})
            for id in pairs(P.ns.GoldData.seed) do P.ns.GoldData.seed[id] = nil end
            P.ns.GoldData.seed[7000] = 6000
            Recipe(P, 1, "Oddity", 14046, {{7000, 2}})
            OpenTrade(P, "Tailoring")
            P.OpenAH()
            History(P, 7000, {{5000, 30}}, 3)
            Listed(P, 7000, {{3000, 10}, {5000, 30}})
            local scrap = Deal(Analyse(P), "Material", 7000)
            X(scrap and scrap.estimate == nil and g.Tip(scrap)[1] == "Usually 50s each; these are at 80% of that or less. The profit shown is what you save.",
              "K7: a built-in vendor price dearer than the usual price: " .. tostring(scrap and g.Tip(scrap)[1]))
        end
        -- K8: totals: a Disenchant best beside an unproven auction price counts too
        do
            local P = Stock(GP("GoldXK8"))
            local t = P.ns.Gold.BagTotals({{count = 1, confident = true, mark = "unproven", bestHow = "Disenchant", best = 500, auction = 100, vendor = 50}})
            X(t.best == 500 and t.unproven == 0 and t.auction == 0, "K8: Disenchant best beside an unproven auction price is in Best of each (" ..
              tostring(t.best) .. ", " .. tostring(t.unproven) .. ")")
        end
        -- K10: what counts our own
        do
            local P = Stock(GP("GoldXK10"))
            local g = P.ns.Gold
            setmetatable(P.ah.commodity, {__index = function() return true end})
            P.OpenAH()
            P.ah.rows = {Row(3000, 5, 500), Row(14047, 5, 500)}
            Scan(P)
            Shift(P, 900)
            advance(61)
            -- an ownerless scan that sees the cloth and no ore at all (ours was posted after it)
            P.ah.rows = {Row(14047, 5, 500, {owner = false}), Row(14047, 5, 600, {owner = false})}
            Scan(P)
            P.ah.owned = {{itemKey = {itemID = 3000}, quantity = 5, buyoutAmount = 500}}
            P.Fire("OWNED_AUCTIONS_UPDATED")
            X(Rec(P, 3000).q == 0 and g.State().hint == nil and Book(P).noOwners == nil,
              "K10a: an item the ownerless scan found none of counts nothing of ours: " .. tostring(g.State().hint))
        end
        do
            local P = Stock(GP("GoldXK11"))
            local g = P.ns.Gold
            setmetatable(P.ah.commodity, {__index = function() return true end})
            P.OpenAH()
            P.ah.rows = {Row(3000, 5, 500, {owner = false}), Row(3000, 5, 600, {owner = false})}
            Scan(P)
            P.ah.owned = {{itemKey = {itemID = 3000}, quantity = 5, buyoutAmount = 500}}
            P.Fire("OWNED_AUCTIONS_UPDATED")
            local before = g.State().hint
            Listed(P, 3000, {{600, 5}, {610, 5}})
            X(before == "Your own auctions are still counted in 1 price - press Price my items." and g.State().hint == nil,
              "K11: the player's own search of the last such item ends the warning, not \"0 prices\": " .. tostring(g.State().hint))
        end
        -- K12-K14: essences
        do
            local P = Stock(GP("GoldXK12"))
            local g = P.ns.Gold
            P.knowsDisenchant = true
            setmetatable(P.ah.commodity, {__index = function() return true end})
            P.bags[0] = {n = 1, [1] = {itemID = 10939, stackCount = 4, quality = 2}}
            P.Fire("BAG_UPDATE_DELAYED")
            P.OpenAH()
            Listed(P, 10939, {{2400, 1}, {3000, 5}})
            Listed(P, 10938, {{1500, 10}, {1600, 5}})
            local c, from = g.Cost(10938, 4)
            X(c == 3600 and from == "buy Greater and split", "K12: four lesser essences take two greaters (24s + 30s, four sixths of it): " ..
              tostring(c) .. " " .. tostring(from))
            -- a tie: three Lesser fetch exactly what the Greater does
            Listed(P, 10939, {{1200, 10}, {1300, 5}})
            Listed(P, 10938, {{400, 10}, {410, 5}})
            local row = BagOf(g, 10939)
            X(row and row.auction == 4560 and not Has(TipOf(g, row), "Worth more"), "K13: worth the same either way isn't \"Worth more split\"")
            -- the Greater has a cheap lot of its own, but is valued as three Lesser, read an hour before
            History(P, 10939, {{900, 10}}, 3)
            Listed(P, 10938, {{400, 10}, {410, 5}})
            Shift(P, 3600)
            Listed(P, 10939, {{500, 2}, {900, 10}, {950, 5}})
            row = BagOf(g, 10939)
            local own, _, passed = g.SellPrice(10939)
            X(own == 900 and passed == 2 and row and Has(TipOf(g, row), "Worth more split") and not Has(TipOf(g, row), "Valued at"),
              "K14a: valued as its other size, the row says nothing of a cheap lot of its own size: " .. (TipOf(g, row):gsub("\n", " | ")))
            X(row and row.t == Rec(P, 10938).t and row.t ~= Rec(P, 10939).t, "K14b: ... and its age is that of the price used")
        end
        -- K15, K16: a scan that never reached its end, in the two ways no check covers
        do
            local P = Stock(GP("GoldXK15"))
            P.OpenAH()
            P.ah.rows = {}
            for i = 1, 100 do P.ah.rows[i] = Row(14047, 1, 100) end
            local AH, calls = P.env.C_AuctionHouse, 0
            local real = AH.GetNumReplicateItems
            AH.GetNumReplicateItems = function()
                calls = calls + 1
                return real() - (calls > 1 and 2 or 0)
            end
            Scan(P)
            AH.GetNumReplicateItems = real
            local cut = P.ns.Gold.State().message
            P = Reload(P)
            table.insert(gone, P)
            X(Has(cut, "Scan cut short") and Has(P.ns.Gold.State().message, "The last scan didn't finish - the game allows another in 15 min."),
              "K15: a scan cut short, then a /reload: the window still says why Scan is waiting: " .. tostring(P.ns.Gold.State().message))
            local Q = Stock(GP("GoldXK16"))
            Q.OpenAH()
            Q.ah.rows = {}
            for i = 1, 5000 do Q.ah.rows[i] = Row(14047, 1, 100) end
            Q.Fire("REPLICATE_ITEM_LIST_UPDATE")
            local pending = Book(Q) and Book(Q).fullPending
            advance(5)
            X(pending == true and Book(Q).fullPending == nil and Book(Q).full ~= nil, "K16: another add-on's list, heard while idle and not yet read to the end, is a scan under way: " .. tostring(pending))
        end
    end

    ----------------------------------------------------------------------
    -- fourth review, 2: answers that last, our own auctions over more than
    -- one visit, the first days, things that are never auctioned, a price
    -- shared with an alt, and a neutral house
    ----------------------------------------------------------------------
    -- a "none listed" answer that is still wanted outlives the 30 days
    do
        local P = Stock(GP("GoldY1"))
        local g = P.ns.Gold
        setmetatable(P.ah.commodity, {__index = function() return true end})
        for id in pairs(P.ns.GoldData.seed) do P.ns.GoldData.seed[id] = nil end
        Recipe(P, 1, "Runecloth Bag", 14046, {{14048, 5}, {8170, 1}})
        OpenTrade(P, "Tailoring")
        P.bags[0] = {n = 1, [1] = {itemID = 3000, stackCount = 5, quality = 1}}
        P.Fire("BAG_UPDATE_DELAYED")
        P.OpenAH()
        P.ah.rows = {Row(14048, 20, 18000), Row(14048, 5, 4750), Row(7000, 5, 500)}
        Scan(P)
        check(Rec(P, 3000) and Rec(P, 3000).q == 0 and g.BagTotals(g.BagRows()).unpriced == 0 and
              Has(g.State().check.tip, "About 0 seconds."), "gold scan: (day 0: the scan answers for the ore nobody lists)")
        local bad
        for day = 1, 31 do
            Days(P, 1)
            advance(61)
            P.ah.rows = {Row(14048, 20, 18000), Row(14048, 5, 4750)}
            Scan(P)
            local t = g.BagTotals(g.BagRows())
            if not (Rec(P, 3000) and Rec(P, 3000).q == 0 and Rec(P, 8170) and Rec(P, 14046) and t.unpriced == 0 and
                Has(g.State().check.tip, "About 0 seconds.")) then
                bad = bad or day
            end
        end
        check(bad == nil, "gold scan: a scan a day for a month: straight after each, nothing is unpriced and Price my items has nothing to do (first bad day: " ..
              tostring(bad) .. ")")
        check(Rec(P, 7000) == nil, "gold scan: (what nothing uses, sold out for 30 days, is still dropped)")
        -- ... and so at a login: 29 days after it was last wanted it stays, at 31 it goes
        Days(P, 29)
        P = Reload(P)
        table.insert(gone, P)
        check(Rec(P, 3000) and Rec(P, 8170), "gold scan: a \"none listed\" answer is kept 30 days from when it was last wanted, not from the first")
        Days(P, 2)
        P = Reload(P)
        table.insert(gone, P)
        check(Rec(P, 3000) == nil and Rec(P, 8170) == nil, "gold scan: ... and no longer")
    end
    -- a look-up's "none listed" is wanted too
    do
        local P = Stock(GP("GoldY2"))
        setmetatable(P.ah.commodity, {__index = function() return true end})
        P.OpenAH()
        Listed(P, 3000, {{100, 5}, {110, 5}})
        Days(P, 20)
        Listed(P, 3000, {})
        Days(P, 20)
        P = Reload(P)
        table.insert(gone, P)
        check(Rec(P, 3000) and Rec(P, 3000).q == 0, "gold prices: a search that found none, 20 days after the item was last seen: kept 30 days from the search")
    end
    -- a browse row replaces "none listed", however new that answer is
    do
        local P = Stock(GP("GoldY3"))
        local g = P.ns.Gold
        setmetatable(P.ah.commodity, {__index = function() return true end})
        for id in pairs(P.ns.GoldData.seed) do P.ns.GoldData.seed[id] = nil end
        P.bags[0] = {n = 1, [1] = {itemID = 3000, stackCount = 5, quality = 1}}
        P.Fire("BAG_UPDATE_DELAYED")
        P.OpenAH()
        P.ah.rows = {Row(14047, 5, 500), Row(14047, 5, 600)}
        Scan(P)
        Shift(P, 1200)
        P.ah.browse = {{itemKey = {itemID = 3000}, minPrice = 900, totalQuantity = 40},
                       {itemKey = {itemID = 14047}, minPrice = 50, totalQuantity = 40}}
        P.Fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
        advance(1)
        local row = BagOf(g, 3000)
        check(Rec(P, 3000).q == 40 and Rec(P, 3000).s == "b" and row.auction and not Has(TipOf(g, row), "None listed"),
              "gold passive: a browse row that shows the item listed replaces a scan's \"none listed\", however new that is")
        check(Rec(P, 14047).s == "f" and Rec(P, 14047).m == 100, "gold passive: (a scan's record with listings is still left alone for an hour)")
    end
    -- six cheap price points kept and most of the units beyond them
    do
        local P = Stock(GP("GoldY4"))
        local g = P.ns.Gold
        P.items[4338] = {name = "Mageweave Cloth", stack = 20, sell = 250, class = 7, reagent = true}
        setmetatable(P.ah.commodity, {__index = function() return true end})
        P.bags[0] = {n = 1, [1] = {itemID = 4338, stackCount = 37, quality = 1}}
        P.Fire("BAG_UPDATE_DELAYED")
        P.OpenAH()
        Listed(P, 4338, {{100, 1}, {101, 1}, {102, 1}, {103, 1}, {104, 1}, {105, 1}, {380, 500}, {390, 494}})
        local sp, flag, over = g.SellPrice(4338)
        local tip = TipOf(g, BagOf(g, 4338))
        check(sp == 105 and flag == nil and over == 5 and not Has(tip, "listed at one price") and
              Has(tip, "Valued at 1s 5c each - 5 cheaper units are listed below the going rate."),
              "gold prices: units beyond the six price points kept are at other prices: never \"listed at one price\" (" ..
              tostring(sp) .. ", " .. tostring(flag) .. ", " .. tostring(over) .. ")")
        Listed(P, 4338, {{380, 500}})
        check(select(2, g.SellPrice(4338)) == "unproven" and Has(TipOf(g, BagOf(g, 4338)), "All 500 are listed at one price - it may be one seller."),
              "gold prices: (one price for everything listed is still one seller's, perhaps)")
    end
    -- our own auctions: the Auctions tab's list is one visit's, and only until we post or cancel
    do
        local P = Stock(GP("GoldY5"))
        local g = P.ns.Gold
        setmetatable(P.ah.commodity, {__index = function() return true end})
        P.ah.commodity[14046] = false
        for id in pairs(P.ns.GoldData.seed) do P.ns.GoldData.seed[id] = nil end
        Recipe(P, 1, "Runecloth Bag", 14046, {{14048, 5}})
        Recipe(P, 2, "Bolt of Runecloth", 14048, {{14047, 5}})
        OpenTrade(P, "Tailoring")
        P.OpenAH()
        local MAY = "Your own auctions may be counted - open your Auctions tab once."
        local function Market(bolts)
            P.ah.rows = {Row(14046, 1, 12500, {owner = false}), Row(14046, 1, 12500, {owner = false}), Row(14046, 1, 13000, {owner = false}),
                         Row(14048, 10, 22000, {owner = false}), Row(14048, 10, 23000, {owner = false})}
            if bolts then table.insert(P.ah.rows, Row(14048, 10, 15000, {owner = false})) end
        end
        local function Craft(id) return TipOf(g, Find(g.CraftRows(), "id", id)) end
        -- two bags up, the Auctions tab read; then ten bolts posted on the Sell tab, then a scan that names no owner
        P.ah.owned = {{itemKey = {itemID = 14046}, quantity = 1, buyoutAmount = 12500},
                      {itemKey = {itemID = 14046}, quantity = 1, buyoutAmount = 12500}}
        P.Fire("OWNED_AUCTIONS_UPDATED")
        P.Fire("AUCTION_HOUSE_AUCTION_CREATED", 77)
        Market(true)
        Scan(P)
        check(Book(P).noOwners ~= nil and g.State().hint == MAY and Rec(P, 14046).q == 1 and Rec(P, 14046).m == 13000 and
              Rec(P, 14048).m == 1500,
              "gold: an auction posted after the Auctions tab was read, then a scan that names no owner: the window warns (" ..
              tostring(g.State().hint) .. ")")
        P.ah.owned[3] = {itemKey = {itemID = 14048}, quantity = 10, buyoutAmount = 1500}
        P.Fire("OWNED_AUCTIONS_UPDATED")
        check(g.State().hint == "Your own auctions are still counted in 1 price - press Price my items." and
              Has(Craft(14048), "Listed: 30 - your own 10 may be among them") and Has(Craft(14046), "Listed: 1, not counting 2 of yours"),
              "gold: ... the tab read again: only what it didn't list before is named as still counted (" .. tostring(g.State().hint) .. ")")
        P.ah.results[14048] = {{quantity = 10, unitPrice = 1500, numOwnerItems = 10}, {quantity = 10, unitPrice = 2200, numOwnerItems = 0},
                               {quantity = 10, unitPrice = 2300, numOwnerItems = 0}}
        P.ah.sends = {}
        g.StartCheck()
        advance(5)
        check(P.ah.sends[1] and P.ah.sends[1].id == 14048 and Rec(P, 14048).m == 2200 and g.State().hint == nil and Book(P).noOwners == nil,
              "gold: ... and Price my items puts it right")
        -- one cancelled: the list is out of date again - but the tab then shows what the scan took out
        Shift(P, 900)
        advance(61)
        P.Fire("AUCTION_CANCELED", 5)
        Market(true)
        Scan(P)
        check(Book(P).noOwners ~= nil and g.State().hint == MAY and Rec(P, 14048).m == 2200,
              "gold: an auction cancelled since the tab was read: the next scan's list of ours may be out of date, and the window says so")
        P.Fire("OWNED_AUCTIONS_UPDATED")
        check(g.State().hint == nil and Book(P).noOwners == nil and Has(Craft(14048), "Listed: 20, not counting 10 of yours"),
              "gold: ... the tab read again and nothing new on it: what the scan took out was right, nothing left to warn about")
        -- the bags sell; three hours later, on another visit, a rival has two up at the same price
        P.CloseAH()
        check(not Has(Craft(14048), "of yours"), "gold: (away from the auction house nothing is said of our own auctions)")
        Shift(P, 3 * 3600)
        advance(61)
        P.OpenAH()
        Market(false)
        Scan(P)
        check(Rec(P, 14046).q == 3 and Rec(P, 14046).m == 12500 and g.State().hint == MAY and not Has(Craft(14046), "of yours"),
              "gold: what the Auctions tab listed on an earlier visit isn't taken out of a later scan (" .. tostring(Rec(P, 14046).q) ..
              " listed; " .. tostring(g.State().hint) .. ")")
        -- ... nor at another auction house
        P.Fire("OWNED_AUCTIONS_UPDATED")
        P.CloseAH()
        P.npcFaction = "Neutral"
        Shift(P, 900)
        advance(61)
        P.OpenAH()
        Market(false)
        Scan(P)
        local there = Rec(P, 14046, P.realm .. "-Neutral")
        check(there and there.q == 3 and there.m == 12500 and g.State().hint == MAY,
              "gold: ... nor out of a scan at another auction house")
        P.npcFaction = nil
        -- ... nor after the feature was switched off and on
        P.CloseAH()
        P.OpenAH()
        P.Fire("OWNED_AUCTIONS_UPDATED")
        P.Slash("gold off")
        P.Slash("gold on")
        Shift(P, 900)
        advance(61)
        Market(false)
        Scan(P)
        check(g.State().ahOpen and Rec(P, 14046).q == 3 and g.State().hint == MAY, "gold: ... nor after the gold finder was switched off and on")
        check(#P.ns.errors == 0, "gold: (no errors)")
    end
    -- an out-of-date list settles nothing either, and what one house's scan took out says nothing of another's
    do
        local P = Stock(GP("GoldY5b"))
        local g = P.ns.Gold
        setmetatable(P.ah.commodity, {__index = function() return true end})
        P.ah.commodity[14046] = false
        for id in pairs(P.ns.GoldData.seed) do P.ns.GoldData.seed[id] = nil end
        P.bags[0] = {n = 1, [1] = {itemID = 14047, stackCount = 3, quality = 1}}
        P.Fire("BAG_UPDATE_DELAYED")
        P.OpenAH()
        local MAY = "Your own auctions may be counted - open your Auctions tab once."
        local function Owned(n)
            P.ah.owned = {}
            for i = 1, n do P.ah.owned[i] = {itemKey = {itemID = 14046}, quantity = 1, buyoutAmount = 12500} end
            P.Fire("OWNED_AUCTIONS_UPDATED")
        end
        local function Market()
            P.ah.rows = {Row(14046, 1, 12500, {owner = false}), Row(14046, 1, 12500, {owner = false}), Row(14046, 1, 12500, {owner = false}),
                         Row(14046, 1, 13000, {owner = false}), Row(14047, 5, 500, {owner = false})}
        end
        Owned(1)
        P.Fire("AUCTION_HOUSE_AUCTION_CREATED", 78)
        Market()
        Scan(P)
        Shift(P, 601)
        P.ah.results[14047] = {{quantity = 5, unitPrice = 100, numOwnerItems = 0}, {quantity = 5, unitPrice = 110, numOwnerItems = 0}}
        g.StartCheck()
        advance(30)
        check(g.State().state == "idle" and Rec(P, 14047).s == "c" and Book(P).noOwners ~= nil and g.State().hint == MAY,
              "gold: a list of ours known to be out of date: Price my items doesn't end the warning (" .. tostring(g.State().hint) .. ")")
        -- a scan at the neutral house, its own list out of date as well
        P.CloseAH()
        P.npcFaction = "Neutral"
        Shift(P, 900)
        advance(61)
        P.OpenAH()
        Owned(3)
        P.Fire("AUCTION_CANCELED", 6)
        Market()
        Scan(P)
        P.CloseAH()
        P.npcFaction = nil
        P.OpenAH()
        -- back home the tab lists two bags: one more than the scan here knew of
        Owned(2)
        check(Rec(P, 14046).q == 3 and Book(P).noOwners ~= nil and
              g.State().hint == "Your own auctions are still counted in 1 price - press Price my items.",
              "gold: what a scan at another auction house took out says nothing of this one's (" .. tostring(g.State().hint) .. ")")
    end
    -- the Auctions tab's list while the game says it is still arriving settles nothing
    do
        local P = Stock(GP("GoldY6"))
        local g = P.ns.Gold
        setmetatable(P.ah.commodity, {__index = function() return true end})
        P.ah.commodity[14046] = false
        for id in pairs(P.ns.GoldData.seed) do P.ns.GoldData.seed[id] = nil end
        Recipe(P, 1, "Runecloth Bag", 14046, {{14048, 5}})
        OpenTrade(P, "Tailoring")
        P.OpenAH()
        P.ah.rows = {Row(14046, 1, 12500, {owner = false}), Row(14046, 1, 12500, {owner = false}),
                     Row(14046, 1, 13000, {owner = false}), Row(14046, 1, 13100, {owner = false}),
                     Row(14048, 20, 18000, {owner = false})}
        Scan(P)
        P.env.C_AuctionHouse.HasFullOwnedAuctionResults = function() return false end
        P.ah.owned = {}
        P.Fire("OWNED_AUCTIONS_UPDATED")
        check(Book(P).noOwners ~= nil, "gold: a list of our auctions that is still arriving doesn't end the warning")
        P.env.C_AuctionHouse.HasFullOwnedAuctionResults = function() return true end
        P.ah.owned = {{itemKey = {itemID = 14046}, quantity = 1, buyoutAmount = 12500},
                      {itemKey = {itemID = 14046}, quantity = 1, buyoutAmount = 12500}}
        P.Fire("OWNED_AUCTIONS_UPDATED")
        local bag = Find(g.CraftRows(), "id", 14046)
        check(g.State().hint == "Your own auctions are still counted in 1 price - press Price my items." and
              not Has(TipOf(g, bag), "not counting 2 of yours") and Has(TipOf(g, bag), "your own 2 may be among them"),
              "gold: ... and once it is whole, what still counts ours is named (" .. tostring(g.State().hint) .. ")")
    end
    -- a scan that read a piece of gear without its link says nothing of that item's suffixes
    do
        local P = Stock(GP("GoldY7"))
        local g = P.ns.Gold
        setmetatable(P.ah.commodity, {__index = function() return true end})
        P.ah.commodity[17000] = false
        for id in pairs(P.ns.GoldData.seed) do P.ns.GoldData.seed[id] = nil end
        P.bags[0] = {n = 2, [1] = {itemID = 17000, stackCount = 1, quality = 2, hyperlink = Link(17000, 5)},
                     [2] = {itemID = 15000, stackCount = 1, quality = 2, hyperlink = Link(15000, 5)}}
        P.Fire("BAG_UPDATE_DELAYED")
        P.OpenAH()
        ListedGear(P, 17000, {{50000, 7}})
        Shift(P, 601)
        -- the only gloves for sale are "of the Bear" (suffix 5), 4g; their link never arrives during the scan
        P.ah.rows = {Row(17000, 1, 40000, {lateLink = Link(17000, 5)}), Row(14047, 5, 500)}
        Scan(P)
        local row = BagOf(g, "17000:5")
        check(Rec(P, 17000) and Rec(P, 17000).q == 1 and Rec(P, "17000:5") == nil and Rec(P, "17000:7").q == 1 and
              Rec(P, "15000:5") and Rec(P, "15000:5").q == 0,
              "gold scan: gloves read without their link: nothing is said of the pair \"of the Bear\" in the bags, nor of the \"of the Whale\" the book knew - the sword nobody lists is still none listed")
        check(row and row.confident == false and not Has(TipOf(g, row), "None listed") and Has(g.State().check.tip, "About 2 seconds."),
              "gold scan: ... Your bags still asks for its price, and Price my items will look it up (" .. g.State().check.tip .. ")")
        P.ah.results[17000] = {{quantity = 1, buyoutAmount = 40000, itemKey = {itemID = 17000, itemSuffix = 5}}}
        P.ah.sends = {}
        g.StartCheck()
        advance(5)
        check(#P.ah.sends == 1 and P.ah.sends[1].id == 17000 and Rec(P, "17000:5").m == 40000 and BagOf(g, "17000:5").confident,
              "gold scan: ... which finds it")
        -- the link there for the second look: the scan answers as before
        Shift(P, 900)
        advance(61)
        P.ah.rows = {Row(17000, 1, 40000, {lateLink = Link(17000, 7)}), Row(14047, 5, 500)}
        g.StartScan()
        advance(1.5)
        check(g.State().state == "reading", "gold scan: (the rows read, the gloves' link still to come)")
        P.ah.linksReady = true
        advance(5)
        check(g.State().state == "idle" and Rec(P, "17000:5").q == 0 and Rec(P, "17000:7").q == 1 and Rec(P, "17000:7").m == 40000,
              "gold scan: (with every link read in the end, a suffix the scan didn't see is none listed)")
    end
    -- the first days: sold out, no usual price yet - the last price seen, and said to be no more
    do
        local P = Stock(GP("GoldY8"))
        local g = P.ns.Gold
        setmetatable(P.ah.commodity, {__index = function() return true end})
        P.ah.commodity[14046] = false
        for id in pairs(P.ns.GoldData.seed) do P.ns.GoldData.seed[id] = nil end
        Recipe(P, 1, "Runecloth Bag", 14046, {{14048, 5}})
        OpenTrade(P, "Tailoring")
        P.bags[0] = {n = 1, [1] = {itemID = 14046, stackCount = 1, quality = 1}}
        P.Fire("BAG_UPDATE_DELAYED")
        P.OpenAH()
        local bolts = {Row(14048, 20, 18000), Row(14048, 20, 19000)}
        P.ah.rows = {bolts[1], bolts[2], Row(14046, 1, 60000), Row(14046, 1, 62000), Row(14046, 1, 65000)}
        Scan(P)
        local row = BagOf(g, 14046)
        check(row.bestText == "Auction 5g 70s" and row.mark == nil, "gold prices: (day 1: the bag is listed at 6g)")
        Days(P, 1)
        advance(61)
        P.ah.rows = bolts
        Scan(P)
        local LAST = "None listed now - last seen at 6g, 24 h ago. Not proof it still sells for that."
        local sp, flag = g.SellPrice(14046)
        row = BagOf(g, 14046)
        local t = g.BagTotals(g.BagRows())
        check(sp == 60000 and flag == "unproven" and row.confident and row.bestHow == "Auction" and row.best == 57000 and
              row.mark == "unproven" and Has(TipOf(g, row), LAST) and not Has(TipOf(g, row), "no auction price to go by"),
              "gold prices: sold out the day after it was first seen: Your bags values it at the last price, marked unproven - not at the vendor's (" ..
              tostring(row.bestText) .. ")")
        check(t.unproven == 1 and t.auction == 0 and t.best == 0 and t.unpriced == 0, "gold prices: ... and out of the totals (" .. t.text .. ")")
        local craft = Find(g.CraftRows(), "id", 14046)
        check(craft.how == "Auction" and craft.mark == "unproven" and craft.profit == 57000 - 4500 and craft.rank == 2 and
              Has(TipOf(g, craft), LAST) and not Has(TipOf(g, craft), "usual price"),
              "gold prices: ... Crafts too: yesterday's craft isn't a loss for having sold out (" .. tostring(craft.profit) .. ")")
        -- two weeks without one listed: that price has had its day
        Days(P, 14)
        advance(61)
        Scan(P)
        sp, flag = g.SellPrice(14046)
        row = BagOf(g, 14046)
        check(sp == nil and flag == "none listed" and row.confident and row.bestText == "Vendor 2g" and
              Has(TipOf(g, row), "None listed - no auction price to go by."),
              "gold prices: ... after two weeks unlisted the last price is no guide any more")
    end
    do
        local P = Stock(GP("GoldY9"))
        local g = P.ns.Gold
        P.knowsDisenchant = true
        setmetatable(P.ah.commodity, {__index = function() return true end})
        P.OpenAH()
        Listed(P, 10939, {{3000, 5}, {3100, 5}})
        Days(P, 1)
        Listed(P, 10939, {})
        Listed(P, 10938, {{500, 30}, {510, 5}})
        local rows = Analyse(P)
        local sp, flag = g.SellPrice(10939)
        check(sp == 3000 and flag == "unproven" and Deal(rows, "Essence", 10938) == nil,
              "gold bargains: no essence bargain on a last-seen price alone (" .. tostring(sp) .. ", " .. tostring(flag) .. ")")
        Listed(P, 10939, {{3000, 5}, {3100, 5}})
        check(Deal(Analyse(P), "Essence", 10938) ~= nil, "gold bargains: (listed again, there is one)")
    end
    -- what binds as it is made is never on the auction house
    do
        local P = Stock(GP("GoldY10"))
        local g = P.ns.Gold
        P.knowsDisenchant = true
        setmetatable(P.ah.commodity, {__index = function() return true end})
        P.ah.commodity[20001] = false
        for id in pairs(P.ns.GoldData.seed) do P.ns.GoldData.seed[id] = nil end
        Recipe(P, 1, "Soulbound Robe", 20001, {{14047, 2}})
        OpenTrade(P, "Tailoring")
        P.OpenAH()
        P.ah.rows = {Row(14047, 20, 10000), Row(14047, 20, 11000)}
        Scan(P)
        local row = Find(g.CraftRows(), "id", 20001)
        local tip = TipOf(g, row)
        check(row and row.listed == nil and row.listedText == "-" and row.t == nil and row.cost == 1000 and
              Has(tip, "Binds when made: vendor or disenchant only.") and not Has(tip, "you set the price") and not Has(tip, "Price from"),
              "gold crafts: a bind-on-pickup output has no listed count and isn't told that nobody is selling")
        check(Rec(P, 20001) == nil, "gold scan: ... a whole scan writes no \"none listed\" for it")
        Shift(P, 601)
        P.ah.results[14047] = {{quantity = 20, unitPrice = 500, numOwnerItems = 0}}
        P.ah.sends = {}
        g.StartCheck()
        advance(60)
        local asked = false
        for _, s in ipairs(P.ah.sends) do if s.id == 20001 then asked = true end end
        -- (the cloth and an enchanter's 24 materials)
        check(g.State().state == "idle" and #P.ah.sends == 25 and not asked and Rec(P, 20001) == nil,
              "gold check: ... and Price my items doesn't ask for it (" .. #P.ah.sends .. " asked)")
    end
    -- a commodity's price shared with an alt's auction: left out only when it is ours alone
    do
        local P = Stock(GP("GoldY11"))
        setmetatable(P.ah.commodity, {__index = function() return true end})
        P.OpenAH()
        local function Read(o)
            local tier = {quantity = 120, unitPrice = 850, numOwnerItems = 0, containsAccountItem = true}
            for k, v in pairs(o) do tier[k] = v end
            P.ah.results[3000] = {tier, {quantity = 5, unitPrice = 2000, numOwnerItems = 0}}
            P.Fire("COMMODITY_SEARCH_RESULTS_UPDATED", 3000)
            return Rec(P, 3000).m .. "/" .. Rec(P, 3000).q
        end
        local shared, list = Read({totalNumberOfOwners = 3}), Read({owners = {"a", "b"}})
        check(shared == "850/125" and list == "850/125",
              "gold check: a price an alt shares with other sellers is kept (" .. shared .. ", " .. list .. ")")
        local solo, list1 = Read({totalNumberOfOwners = 1}), Read({owners = {"a"}})
        local both = Read({totalNumberOfOwners = 2, containsOwnerItem = true, numOwnerItems = 3})
        check(solo == "2000/5" and list1 == "2000/5" and both == "2000/5",
              "gold check: ... one that is the alt's alone, or the alt's and ours, is left out (" .. solo .. ", " .. list1 .. ", " .. both .. ")")
        local three = Read({totalNumberOfOwners = 3, containsOwnerItem = true, numOwnerItems = 3})
        local unknown = Read({})
        check(three == "850/122" and unknown == "850/125",
              "gold check: ... ours come out of a shared one, and one whose sellers can't be counted is kept (" .. three .. ", " .. unknown .. ")")
        P.ah.results[3000] = {{quantity = 120, unitPrice = 850, numOwnerItems = 0, containsAccountItem = true, totalNumberOfOwners = 4}}
        P.Fire("COMMODITY_SEARCH_RESULTS_UPDATED", 3000)
        check(Rec(P, 3000).q == 120, "gold check: (the only price listed, shared with an alt: not \"none listed\")")
    end
    -- a neutral auction house before its first scan
    do
        local P = Stock(GP("GoldY12"))
        local g = P.ns.Gold
        setmetatable(P.ah.commodity, {__index = function() return true end})
        for id in pairs(P.ns.GoldData.seed) do P.ns.GoldData.seed[id] = nil end
        P.bags[0] = {n = 1, [1] = {itemID = 14047, stackCount = 3, quality = 1}}
        P.Fire("BAG_UPDATE_DELAYED")
        P.OpenAH()
        P.ah.rows = {Row(14047, 5, 500)}
        Scan(P)
        check(g.State().message == "Scan finished: 1 item.", "gold: (a scan at home)")
        P.CloseAH()
        Shift(P, 300)
        P.npcFaction = "Neutral"
        P.OpenAH()
        local st = g.State()
        check(g.PriceState("crafts") == "Neutral auction house - no prices here yet. Press Scan (everything, once per 15 minutes) or Price my items (quick)." and
              st.neutral and st.message == nil,
              "gold: a neutral auction house with no prices yet says that it is one, and not how the last scan at home ended (" ..
              tostring(g.PriceState("crafts")) .. " / " .. tostring(st.message) .. ")")
        local ok, why = g.StartScan()
        check(not st.scan.enabled and st.scan.label == "Scan (in 10 min)" and ok == false and why == "a scan can be asked again in 10 min" and
              P.ah.asked == 1,
              "gold scan: the wait between scans is one for all of a realm's auction houses (" .. tostring(st.scan.label) .. ")")
        P.ah.results[14047] = {{quantity = 5, unitPrice = 100, numOwnerItems = 0}, {quantity = 5, unitPrice = 110, numOwnerItems = 0}}
        g.StartCheck()
        advance(10)
        check(g.State().message == "Priced 1 item." and Has(g.PriceState("crafts"), " - Neutral auction house"), "gold: (a look-up there)")
        P.CloseAH()
        check(g.State().message == nil and not g.State().neutral, "gold: ... nor is the neutral house's last job news at home")
        Shift(P, 900)
        advance(61)
        P.OpenAH()
        P.ah.replicateDelay = 30
        g.StartScan()
        advance(1)
        P.CloseAH()
        check(Has(g.State().message, "The scan was cut short"), "gold: (a scan cut short by leaving a neutral house still says so)")
        P.npcFaction = nil
    end
    -- essences and unfinished scans, the other way round
    do
        local P = Stock(GP("GoldY13"))
        local g = P.ns.Gold
        P.knowsDisenchant = true
        setmetatable(P.ah.commodity, {__index = function() return true end})
        P.OpenAH()
        Listed(P, 10938, {{400, 3}, {600, 20}})
        local c, from = g.Cost(10939, 2)
        check(c == 3000 and from == "buy 3 Lesser and combine",
              "gold prices: two greater essences from six lesser ones bought together, the dearer ones too (" .. tostring(c) .. " " .. tostring(from) .. ")")
        local Q = Stock(GP("GoldY14"))
        Q.OpenAH()
        for i = 1, 5000 do Q.ah.rows[i] = Row(14047, 1, 100) end
        Q.Fire("REPLICATE_ITEM_LIST_UPDATE")
        Q.CloseAH()
        Q = Reload(Q)
        table.insert(gone, Q)
        check(Has(Q.ns.Gold.State().message, "The last scan didn't finish - the game allows another in 15 min."),
              "gold scan: another add-on's scan lost with the auction house closed, then a /reload: the window says why Scan is waiting (" ..
              tostring(Q.ns.Gold.State().message) .. ")")
    end
    ----------------------------------------------------------------------
    -- fourth review: a last-seen price only where "none listed" still
    -- holds, never a Disenchant bargain on one, the unfinished scan of
    -- this house only, and our own auctions taken out once and no more
    ----------------------------------------------------------------------
    -- Auctionator's price isn't explained with our own old "none listed" record
    do
        local P = Stock(GP("GoldZ1"))
        local g = P.ns.Gold
        setmetatable(P.ah.commodity, {__index = function() return true end})
        for id in pairs(P.ns.GoldData.seed) do P.ns.GoldData.seed[id] = nil end
        P.bags[0] = {n = 1, [1] = {itemID = 14047, stackCount = 10, quality = 1}}
        P.Fire("BAG_UPDATE_DELAYED")
        P.OpenAH()
        Listed(P, 14047, {{6000, 5}, {6100, 5}})
        Days(P, 1)
        Listed(P, 14047, {})
        local tip = TipOf(g, BagOf(g, 14047))
        check(Has(tip, "None listed now - last seen at 60s"), "gold bags: (none listed today: the last price seen is said)")
        P.CloseAH()
        Days(P, 3)
        advance(1)
        P.SetAuctionator({prices = {[14047] = 20000}, ages = {[14047] = 0}})
        P.Slash("gold cut " .. P.ns.db.goldCut)
        advance(1)
        local sp, flag = g.SellPrice(14047)
        tip = TipOf(g, BagOf(g, 14047))
        check(sp == 20000 and flag == "unproven" and not Has(tip, "None listed now") and Has(tip, "Lowest price only"),
              "gold bags: Auctionator's price over our own days-old \"none listed\" isn't called the last price seen (" .. tip:gsub("\n", " | ") .. ")")
    end
    -- an old unfinished scan at home, then a finished one at the neutral house
    do
        local P = Stock(GP("GoldZ2"))
        local g = P.ns.Gold
        setmetatable(P.ah.commodity, {__index = function() return true end})
        P.OpenAH()
        P.ah.rows = {Row(14047, 5, 500)}
        P.ah.replicateDelay = 30
        g.StartScan()
        advance(1)
        P.CloseAH()
        P.ah.replicateDelay = nil
        Days(P, 3)
        advance(61)
        P.npcFaction = "Neutral"
        P.OpenAH()
        local ok = Scan(P)
        P.CloseAH()
        P.npcFaction = nil
        Shift(P, 300)
        advance(1)
        P.OpenAH()
        local st = g.State()
        check(ok == true and st.scan.label == "Scan (in 10 min)" and not Has(st.message, "didn't finish"),
              "gold scan: a scan that finished at another house doesn't make this one say \"The last scan didn't finish\" (" ..
              tostring(st.message) .. ")")
    end
    -- no Disenchant bargain on materials nobody lists, valued at a last sighting
    do
        local P = Stock(GP("GoldZ3"))
        local g = P.ns.Gold
        P.knowsDisenchant = true
        P.items[16500] = {name = "Bandit Cloak", quality = 2, ilvl = 10, sell = 300, class = 4, bind = 2}
        setmetatable(P.ah.commodity, {__index = function() return true end})
        P.ah.commodity[16500] = false
        for id in pairs(P.ns.GoldData.seed) do P.ns.GoldData.seed[id] = nil end
        P.bags[0] = {n = 1, [1] = {itemID = 16500, stackCount = 1, quality = 2}}
        P.Fire("BAG_UPDATE_DELAYED")
        P.OpenAH()
        Listed(P, 10940, {{5000, 3}, {5100, 2}})
        Listed(P, 10938, {{8000, 3}, {8100, 2}})
        ListedGear(P, 16500, {{2000, 0}})
        local value, _, guess = g.DisenchantValue(16500)
        check(value and not guess and Deal(Analyse(P), "Disenchant", 16500) ~= nil, "gold bargains: (materials listed: the Disenchant deal is there)")
        Days(P, 9)
        Listed(P, 10940, {})
        Listed(P, 10938, {})
        ListedGear(P, 16500, {{2000, 0}})
        local rows = Analyse(P)
        value, _, guess = g.DisenchantValue(16500)
        check(value and guess == true and Deal(rows, "Disenchant", 16500) == nil,
              "gold bargains: no Disenchant deal on materials nobody lists, valued at the last price seen")
        check(Has(TipOf(g, BagOf(g, 16500)), "Disenchant: a material has none listed now - valued at the last price seen."),
              "gold bags: ... and a Disenchant value that rests on one says so")
    end
    -- a list of our auctions that arrives after the auction house closed
    do
        local P = Stock(GP("GoldZ4"))
        local g = P.ns.Gold
        setmetatable(P.ah.commodity, {__index = function() return true end})
        P.OpenAH()
        P.ah.owned = {{itemKey = {itemID = 14048}, quantity = 20, buyoutAmount = 900}}
        P.CloseAH()
        P.Fire("OWNED_AUCTIONS_UPDATED")
        advance(1)
        Shift(P, 6 * 3600)
        advance(61)
        P.OpenAH()
        P.ah.rows = {Row(14048, 20, 18000, {owner = false}), Row(14048, 20, 20000, {owner = false}), Row(14047, 20, 4000, {owner = false})}
        Scan(P)
        check(Book(P).noOwners ~= nil and Has(g.State().hint, "open your Auctions tab once") and Rec(P, 14048).q == 40,
              "gold: a list of our auctions that arrived with the auction house closed isn't the next visit's list")
    end
    -- rows that name their owner, and the Auctions tab seen as well: ours come out once
    do
        local P = Stock(GP("GoldZ5"))
        setmetatable(P.ah.commodity, {__index = function() return true end})
        P.ah.commodity[14046] = false
        P.OpenAH()
        P.ah.owned = {{itemKey = {itemID = 14046}, quantity = 1, buyoutAmount = 12500},
                      {itemKey = {itemID = 14046}, quantity = 1, buyoutAmount = 12500},
                      {itemKey = {itemID = 14047}, quantity = 20, buyoutAmount = 380},
                      {itemKey = {itemID = 14048}, quantity = 5, buyoutAmount = 900},
                      {itemKey = {itemID = 14048}, quantity = 5, buyoutAmount = 900}}
        P.Fire("OWNED_AUCTIONS_UPDATED")
        P.ah.rows = {Row(14046, 1, 12500, {owner = "GoldZ5"}), Row(14046, 1, 12500, {owner = "GoldZ5"}),
                     Row(14046, 1, 12500), Row(14046, 1, 12500), Row(14046, 1, 13000), Row(14046, 1, 13000),
                     Row(14047, 20, 7600, {owner = "GoldZ5"}), Row(14047, 20, 7600), Row(14047, 20, 8000),
                     -- (one of ours named, the other not: only that one is still to come out)
                     Row(14048, 5, 4500, {owner = "GoldZ5"}), Row(14048, 5, 4500, {owner = false}), Row(14048, 5, 4500)}
        Scan(P)
        local bag, cloth, bolt = Rec(P, 14046), Rec(P, 14047), Rec(P, 14048)
        check(bag and bag.m == 12500 and bag.q == 4 and cloth and cloth.m == 380 and cloth.q == 40,
              "gold scan: our auctions left out by name aren't taken out of the others' a second time (" .. tostring(bag and bag.q) .. " " ..
              tostring(cloth and cloth.q) .. ")")
        check(bolt and bolt.q == 5 and Book(P).noOwners == nil, "gold scan: ... and one of ours a row didn't name still is (" .. tostring(bolt and bolt.q) .. ")")
    end
    -- an auction that has sold and is still in the Auctions tab's list isn't up
    do
        local P = Stock(GP("GoldZ6"))
        setmetatable(P.ah.commodity, {__index = function() return true end})
        P.ah.commodity[14046] = false
        P.OpenAH()
        P.ah.owned = {{itemKey = {itemID = 14046}, quantity = 1, buyoutAmount = 12500, status = 1},
                      {itemKey = {itemID = 14046}, quantity = 1, buyoutAmount = 12500, status = 1},
                      {itemKey = {itemID = 14046}, quantity = 1, buyoutAmount = 13000, status = 0}}
        P.Fire("OWNED_AUCTIONS_UPDATED")
        P.ah.rows = {Row(14046, 1, 12500, {owner = false}), Row(14046, 1, 12500, {owner = false}),
                     Row(14046, 1, 13000, {owner = false}), Row(14046, 1, 13000, {owner = false}), Row(14046, 1, 13000, {owner = false})}
        Scan(P)
        local bag = Rec(P, 14046)
        check(bag and bag.m == 12500 and bag.q == 4,
              "gold scan: a sold auction still in the Auctions tab's list isn't taken out of the listings (the one still up is): " ..
              tostring(bag and bag.m) .. " x" .. tostring(bag and bag.q))
    end
    -- the out-of-date list took nothing out (that auction sold; another was posted): still counted
    do
        local P = Stock(GP("GoldZ7"))
        local g = P.ns.Gold
        setmetatable(P.ah.commodity, {__index = function() return true end})
        P.ah.commodity[14046] = false
        P.OpenAH()
        P.ah.owned = {{itemKey = {itemID = 14046}, quantity = 1, buyoutAmount = 12000}}
        P.Fire("OWNED_AUCTIONS_UPDATED")
        P.Fire("AUCTION_HOUSE_AUCTION_CREATED", 556)
        P.ah.rows = {Row(14046, 1, 12800, {owner = false}), Row(14046, 1, 13000, {owner = false}), Row(14046, 1, 13100, {owner = false})}
        Scan(P)
        check(Rec(P, 14046).m == 12800 and Has(g.State().hint, "open your Auctions tab once"), "gold: (a scan with an out-of-date list of ours: the hint)")
        P.ah.owned = {{itemKey = {itemID = 14046}, quantity = 1, buyoutAmount = 12800}}
        P.Fire("OWNED_AUCTIONS_UPDATED")
        check(g.State().hint == "Your own auctions are still counted in 1 price - press Price my items." and Book(P).noOwners ~= nil,
              "gold: an auction the out-of-date list didn't take out is still counted once the Auctions tab is seen (" ..
              tostring(g.State().hint) .. ")")
    end
    -- a browse row over a sold-out record: its own price is what was last seen
    do
        local P = Stock(GP("GoldZ8"))
        local g = P.ns.Gold
        setmetatable(P.ah.commodity, {__index = function() return true end})
        for id in pairs(P.ns.GoldData.seed) do P.ns.GoldData.seed[id] = nil end
        P.bags[0] = {n = 1, [1] = {itemID = 14047, stackCount = 5, quality = 1}}
        P.Fire("BAG_UPDATE_DELAYED")
        P.OpenAH()
        Listed(P, 14047, {{900, 5}, {910, 5}})
        Days(P, 1)
        Listed(P, 14047, {})
        Days(P, 1)
        P.ah.browse = {{itemKey = {itemID = 14047}, totalQuantity = 4, minPrice = 3000}}
        P.Fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
        advance(1)
        check(Rec(P, 14047).s == "b" and Rec(P, 14047).v == 3000, "gold: a browse row over a sold-out record keeps its own price as the typical one")
        Days(P, 1)
        Listed(P, 14047, {})
        local tip = TipOf(g, BagOf(g, 14047))
        check(Has(tip, "None listed now - last seen at 30s, 24 h ago"),
              "gold bags: ... so the last price seen is that day's, not an older one (" .. tip:gsub("\n", " | ") .. ")")
    end
    for _, R in ipairs(gone) do
        R.online = false
        players[R.name] = nil
    end
end

--------------------------------------------------------------------------
-- gold finder: the window (GoldUI.lua) and the auction house button
--------------------------------------------------------------------------
do
    local gone = {}
    local function GP(name, opts)
        -- (as in the game: WoW Forever gives an empty realm name)
        opts = opts or {}
        local before = opts.beforeLoad
        opts.beforeLoad = function(P, env)
            if P.noRealm == nil then P.noRealm = "" end
            if before then before(P, env) end
        end
        local P = makePlayer(name, opts)
        table.insert(gone, P)
        return P
    end
    local ITEMS = {
        [14047] = {name = "Runecloth", stack = 20, sell = 400, class = 7, reagent = true},
        [14048] = {name = "Bolt of Runecloth", stack = 20, sell = 1600, class = 7, reagent = true},
        [14341] = {name = "Rune Thread", stack = 20, sell = 1250, class = 7, reagent = true},
        [14046] = {name = "Runecloth Bag", stack = 1, sell = 20000, class = 1, quality = 2},
        [10940] = {name = "Strange Dust", stack = 20, class = 7, reagent = true},
    }
    local function Stock(P)
        for id, it in pairs(ITEMS) do
            local c = {}
            for k, v in pairs(it) do c[k] = v end
            P.items[id] = c
        end
        return P
    end
    local function Listed(P, id, points)
        local rows = {}
        for _, p in ipairs(points) do rows[#rows + 1] = {quantity = p[2], unitPrice = p[1], numOwnerItems = 0} end
        P.ah.results[id] = rows
        P.Fire("COMMODITY_SEARCH_RESULTS_UPDATED", id)
    end
    local function Recipe(P, id, name, out, reagents, o)
        o = o or {}
        local slots = {}
        for _, r in ipairs(reagents) do
            slots[#slots + 1] = {reagentType = 1, required = true, quantityRequired = r[2], reagents = {{itemID = r[1]}}}
        end
        P.trade.recipes[id] = {
            info = {recipeID = id, name = name, learned = true, isEnchantingRecipe = o.enchant or false},
            sch = {outputItemID = out, quantityMin = 1, quantityMax = 1, recipeType = o.enchant and 3 or 1,
                   reagentSlotSchematics = slots}}
        table.insert(P.trade.ids, id)
    end
    local function Keys(t)
        local out = {}
        for k in next, t do out[#out + 1] = tostring(k) end
        table.sort(out)
        return table.concat(out, ",")
    end
    -- the frames parented to f
    local function ChildrenOf(P, f)
        local n = 0
        for _, fr in ipairs(P.frames) do if fr.parent == f then n = n + 1 end end
        return n
    end
    local function Click(b, ...) RunScript(b, "OnClick", ...) end
    local function Head(ui, title)
        for _, h in ipairs(ui.heads) do if h.col and h.col[1] == title then return h end end
    end
    local function Has(s, needle) return type(s) == "string" and s:find(needle, 1, true) ~= nil end
    -- the tooltip a widget shows on hover
    local function Hover(P, b)
        local tt = P.env.GameTooltip
        tt.lines, tt.item, tt.owner, tt.tried = {}, nil, nil, {}
        tt.AddLine = function(self, t) table.insert(self.lines, t) end
        -- (as the game's: a new owner clears the tooltip; hidden, it has no owner)
        tt.SetOwner = function(self, o) self.owner, self.lines, self.item = o, {}, nil end
        tt.IsOwned = function(self, o) return self.owner == o end
        tt.Hide = function(self) self.shown, self.owner = false, nil end
        -- (P.noTipData: the game has nothing to show for the item - the
        -- accessor hides the tooltip and says false; P.tipThrow: the name of
        -- an accessor that throws)
        local function Accessor(name)
            return function(self, what)
                table.insert(self.tried, name)
                if P.tipThrow == name then error(name .. " can't show this") end
                if P.noTipData then
                    self:Hide()
                    return false
                end
                self.item = what
                return true
            end
        end
        tt.SetItemByID = Accessor("SetItemByID")
        tt.SetHyperlink = Accessor("SetHyperlink")
        RunScript(b, "OnEnter")
        return table.concat(tt.lines, "\n"), tt
    end

    ----------------------------------------------------------------------
    -- opening and closing
    ----------------------------------------------------------------------
    local W = Stock(GP("GoldWin"))
    local G = W.ns.Gold
    local ui = G.ui
    check(type(ui) == "table" and type(ui.Toggle) == "function" and ui.frame == nil,
          "gold window: nothing is built until it is first opened")
    W.Slash("gold")
    local f = ui.frame
    check(f and f.shown and f.template == "BasicFrameTemplateWithInset" and f.width == 720 and f.height == 460 and
          f.parent == W.env.UIParent and f.point[1] == "CENTER" and Has(ui.title.text, "Gold finder"),
          "gold window: /pqol gold opens our own frame, 720 x 460, in the middle, with a title of our own")
    check(#ui.rows == 14 and #ui.heads == 8 and ui.tabs.crafts.text == "Crafts" and ui.tabs.bargains.text == "Bargains" and
          ui.tabs.vendors.text == "Vendors" and ui.tabs.bags.text == "Your bags" and ui.tabs.crafts.template == "UIPanelButtonTemplate" and
          ui.slider.kind == "Slider" and ui.slider.template == nil,
          "gold window: four tabs, 14 rows, a slider of our own")
    check(ui.tabs.crafts:IsEnabled() == false and ui.tabs.bags:IsEnabled() and ui.tab == "crafts",
          "gold window: it opens on Crafts, the selected tab's button disabled")
    check(ui.empty.shown and ui.empty.text == "Open each profession window once on each character - that's how I learn your recipes." and
          not ui.rows[1].shown,
          "gold window: Crafts with no recipes says how they are learned")
    check(ui.header.text == "Go to an auctioneer, open the auction house, then press Scan (everything, once per 15 minutes) or Price my items (quick).",
          "gold window: no prices and the auction house closed: the header says where to go (" .. tostring(ui.header.text) .. ")")
    check(ui.scan.text == "Scan" and ui.scan:IsEnabled() == false and ui.scan.tip == "Open the auction house first" and
          ui.check.text == "Price my items" and ui.check:IsEnabled() == false and ui.check.tip == "Open the auction house first" and
          ui.search:IsEnabled() == false and ui.search.tip == "Click a row first.",
          "gold window: away from the auction house the three buttons are disabled and say why")
    local tip = Hover(W, ui.scan)
    check(Has(tip, "Open the auction house first") and Has(tip, "Scan"), "gold window: a disabled button's tooltip gives the reason")
    W.Slash("gold")
    check(f.shown == false, "gold window: /pqol gold again closes it")
    Click(W.optionsPanel.goldOpen)
    check(f.shown == true and ui.frame == f, "gold window: the options page's Open button opens it (the same frame)")
    Click(ui.close)
    check(f.shown == false, "gold window: the close button hides it")
    local idle = W.tick
    advance(30)
    check(W.tick == idle, "gold window: closed, nothing of it runs")

    ----------------------------------------------------------------------
    -- the auction house tab
    ----------------------------------------------------------------------
    -- (a second player with the feature off: what Blizzard's frame holds untouched)
    local N = Stock(GP("GoldOff", {db = {gold = false}}))
    local bare = N.LoadAH()
    check(N.ns.Gold.ui.ahTab == nil and ChildrenOf(N, bare) == 0, "gold tab: the feature off: nothing on the auction house")
    check(ui.ahTab == nil, "gold tab: none before the auction house has loaded")
    local ahf = W.LoadAH()
    local ahb, holder = ui.ahTab, ui.ahHolder
    check(ahb and holder and holder.parent == ahf and ahb.parent == holder and ahb.template == "PanelTabButtonTemplate" and
          ahb.text == "Gold finder" and ahb.shown and holder.shown and ChildrenOf(W, ahf) == 1,
          "gold tab: made when the auction house loads - a bottom tab drawn as the auction house's own, on a frame of ours inside it")
    check(#ahf.Tabs == 3 and ahf.Tabs[1] == ahf.BuyTab and ahf.Tabs[3] == ahf.AuctionsTab and
          holder.tabPadding == 20 and holder.minTabWidth == 70,
          "gold tab: the auction house's own list of tabs is left as it was (the template files a tab into its parent's: the holder's)")
    check(ahb.point and ahb.point[1] == "TOPLEFT" and ahb.point[2] == ahf.AuctionsTab and ahb.point[3] == "TOPRIGHT" and
          ahb.point[4] == 3 and ahb.point[5] == 0 and ahb.width == 11 * 6 + 40,
          "gold tab: after the last tab, 3 px from it as the game spaces the auction house's tabs, as wide as theirs")
    -- (Auctionator adds its tabs as the auction house opens, after this
    -- add-on's tab was placed: the tab moves after them as it opens)
    local far = W.AddAHTab(400)
    local near = W.AddAHTab(330)
    W.OpenAH()
    RunScript(holder, "OnShow")
    check(ahb.point[2] == far and far.parent ~= ahf and #ahf.Tabs == 3,
          "gold tab: after another add-on's tabs (kept on a frame of its own, not in the auction house's list), beside the one furthest right")
    ahf.AuctionsFrame.shown = true
    local stray = W.AddAHTab(600, 300)
    local label = W.env.CreateFrame("Frame", nil, far.parent)
    label.right, label.top = 700, 100
    function label:GetRight() return self.right end
    function label:GetTop() return self.top end
    ui.PlaceTab()
    check(ahb.point[2] == far, "gold tab: ... only buttons level with the tabs count: not Blizzard's tabs inside a panel, another add-on's button elsewhere or a frame that is no button")
    ahf.AuctionsFrame.shown, stray.shown, label.shown = false, false, false
    far.parent.shown = false
    ui.PlaceTab()
    check(ahb.point[2] == ahf.AuctionsTab, "gold tab: ... nor the tabs of a frame that is hidden")
    far.parent.shown = true
    ui.PlaceTab()
    far.shown = false
    advance(1)
    check(ahb.point[2] == near, "gold tab: ... looked at again a moment after the auction house opens; a hidden tab is passed over")
    for _, t in ipairs(ahf.Tabs) do t.right, t.top = nil, nil end
    ui.PlaceTab()
    check(ahb.point[2] == ahf.AuctionsTab, "gold tab: where the tabs are can't be read yet: after the last one shown in the auction house's list")
    local keep = ahf.Tabs
    ahf.Tabs = nil
    ui.PlaceTab()
    check(ahb.point[1] == "BOTTOMRIGHT" and ahb.point[2] == ahf and ahb.point[3] == "BOTTOMRIGHT",
          "gold tab: no tabs to follow: at the right end of the auction house's bottom edge")
    ahf.Tabs = keep
    for i, t in ipairs(keep) do t.right, t.top = 20 + i * 75, 100 end
    far.shown = true
    ui.PlaceTab()
    W.CloseAH()
    check(ahb.LeftActive.shown == false and ahb.MiddleActive.shown == false and ahb.RightActive.shown == false and
          ahb.Left.shown and ahb.Middle.shown and ahb.Right.shown and #holder.Tabs == 1 and holder.Tabs[1] == ahb,
          "gold tab: never drawn as the tab the auction house is showing")
    check(Has(Hover(W, ahb), "Gold finder"), "gold tab: its tooltip")
    Click(ahb)
    check(f.shown == true, "gold tab: a click opens the window")
    Click(ahb)
    check(f.shown == false, "gold tab: another closes it")
    N.Slash("gold on")
    local nb = N.ns.Gold.ui.ahTab
    check(nb and N.ns.Gold.ui.ahHolder.parent == bare and nb.parent == N.ns.Gold.ui.ahHolder and N.ns.Gold.ui.ahHolder.shown,
          "gold tab: switched on with the auction house already loaded: made then")
    N.Slash("gold off")
    check(N.ns.Gold.ui.ahHolder.shown == false, "gold tab: hidden while the feature is off")
    N.Slash("gold on")
    check(N.ns.Gold.ui.ahTab == nb and N.ns.Gold.ui.ahHolder.shown and ChildrenOf(N, bare) == 1 and #bare.Tabs == 3,
          "gold tab: made once across off and on")

    ----------------------------------------------------------------------
    -- at the auction house: the buttons
    ----------------------------------------------------------------------
    W.OpenAH()
    Click(ahb)
    check(ui.header.text == "Press Scan (everything, once per 15 minutes) or Price my items (quick)." and ui.scan:IsEnabled() and
          ui.scan.text == "Scan" and ui.check:IsEnabled() and ui.check.text == "Price my items" and
          Has(ui.check.tip, "Looks up only the items your recipes and bags use.") and
          Has(ui.check.tip, "Works even when Scan is on its 15-minute wait."),
          "gold window: at the auction house Scan and Price my items are ready")
    W.CloseAH()
    check(ui.scan:IsEnabled() == false and ui.check:IsEnabled() == false, "gold window: the auction house closed: disabled at once")
    advance(0.5)
    check(Has(ui.header.text, "Go to an auctioneer"), "gold window: ... and the header says to go back")
    W.OpenAH()
    advance(0.5)

    -- recipes: a bag from bolts and thread, bolts from cloth, and an enchant
    Recipe(W, 1, "Runecloth Bag", 14046, {{14048, 5}, {14341, 1}})
    Recipe(W, 2, "Bolt of Runecloth", 14048, {{14047, 5}})
    Recipe(W, 3, "Enchant Bracer", nil, {{10940, 2}}, {enchant = true})
    W.trade.prof = {professionID = 197, professionName = "Tailoring", skillLevel = 300, maxSkillLevel = 300}
    W.Fire("TRADE_SKILL_SHOW")
    advance(1)
    Listed(W, 14047, {{100, 50}, {450, 40}})
    Listed(W, 14048, {{700, 30}, {720, 30}})
    Listed(W, 14341, {{5000, 10}, {5100, 10}})
    Listed(W, 14046, {{60000, 3}, {65000, 2}})
    Listed(W, 10940, {{300, 40}, {310, 40}})
    advance(1)
    local crafts = G.CraftRows()
    check(#crafts == 2 and ui.empty.shown == false and ui.rows[1].shown and ui.rows[2].shown and not ui.rows[3].shown and
          ui.rows[1].row == crafts[1] and ui.rows[2].row == crafts[2],
          "gold window: the list fills in by itself as recipes and prices arrive, in the logic's order")
    local bag = ui.rows[1].row
    local r1 = ui.rows[1]
    check(bag.name == "Runecloth Bag" and bag.profit and bag.profit > 0 and Has(r1.cells[1].text, "|cff1eff00Runecloth Bag|r") and
          r1.cells[2].text == "Tailoring" and r1.cells[3].text == ui.Coins(bag.cost, true) and
          Has(r1.cells[4].text, ui.Coins(bag.sells, true)) and r1.cells[5].text == "Auction" and
          r1.cells[6].text == ui.Coins(bag.profit, true) and r1.cells[7].text == "5" and r1.cells[8].text == "0" and
          r1.icon.shown and r1.icon.texture == 134400,
          "gold window: a Crafts row: icon, name in its quality colour, maker, cost, sells for, how, profit, listed, can make")
    check(ui.Coins(123456) == "12|TInterface\\MoneyFrame\\UI-GoldIcon:0|t 34|TInterface\\MoneyFrame\\UI-SilverIcon:0|t 56|TInterface\\MoneyFrame\\UI-CopperIcon:0|t" and
          ui.Coins(123456, true) == "12|TInterface\\MoneyFrame\\UI-GoldIcon:0|t 34|TInterface\\MoneyFrame\\UI-SilverIcon:0|t" and
          ui.Coins(0) == "0|TInterface\\MoneyFrame\\UI-CopperIcon:0|t" and ui.Coins(-250):sub(1, 2) == "-2" and ui.Coins(nil) == "?" and
          ui.Coins(12345678, true):sub(1, 5) == "1,234",
          "gold window: money is written with coin icons (two coins at most in a row)")
    check(Has(ui.header.text, "Prices: ") and not Has(ui.header.text, "|cffff9933"),
          "gold window: the header says where the prices are from (" .. tostring(ui.header.text) .. ")")
    check(ui.heads[1].label.text == "Item" and ui.heads[6].label.text == "Profit" and ui.heads[8].label.text == "Can make" and
          ui.heads[8].shown and ui.count.text == "1-2 of 2",
          "gold window: Crafts' eight column headers, and which rows are showing")
    -- hover
    local text, tt = Hover(W, r1)
    check(tt.owner == r1 and tt.item ~= nil and Has(text, G.Tip(bag)[1]) and Has(text, "Profit is after the 5% auction cut"),
          "gold window: hovering a row shows the item's tooltip and how the row was worked out")
    RunScript(r1, "OnLeave")
    check(tt.shown == false, "gold window: ... and leaving it hides the tooltip")

    -- sorting
    Click(Head(ui, "Cost"))
    check(ui.sort.crafts.field == "cost" and ui.sort.crafts.desc == true and ui.rows[1].row.cost >= ui.rows[2].row.cost and
          Head(ui, "Cost").label.text == "Cost" and Head(ui, "Cost").arrow.shown and
          Has(Head(ui, "Cost").arrow.texture, "Arrow-Down") and not Head(ui, "Item").arrow.shown and G.CraftRows()[1] == crafts[1],
          "gold window: a click on a number column sorts highest first (the logic's own list keeps its order)")
    Click(Head(ui, "Cost"))
    check(ui.sort.crafts.desc == false and ui.rows[1].row.cost <= ui.rows[2].row.cost and Head(ui, "Cost").label.text == "Cost" and
          Has(Head(ui, "Cost").arrow.texture, "Arrow-Up") and Head(ui, "Cost").arrow.shown,
          "gold window: a second click reverses it")
    Click(Head(ui, "Item"))
    check(ui.sort.crafts.field == "name" and ui.sort.crafts.desc == false and ui.rows[1].row.name == "Bolt of Runecloth" and
          Head(ui, "Cost").label.text == "Cost" and not Head(ui, "Cost").arrow.shown and Head(ui, "Item").arrow.shown and
          Head(ui, "Item").label.text == "Item",
          "gold window: a words column sorts a to z; the arrow is a texture of its own, the title never changes")
    Click(Head(ui, "Item"), "RightButton")
    check(ui.sort.crafts == nil and ui.rows[1].row == crafts[1] and Head(ui, "Item").label.text == "Item" and
          not Head(ui, "Item").arrow.shown,
          "gold window: a right click brings the list's own order back")

    -- selecting, and Search
    local box = ahf.SearchBar.SearchBox
    Click(r1)
    check(ui.selected == bag and r1.sel.shown and not ui.rows[2].sel.shown and ui.search:IsEnabled() and
          Has(ui.search.tip, "Runecloth Bag"),
          "gold window: a click selects the row; Search is for its item")
    Click(ui.search)
    check(box.text == "Runecloth Bag" and
          ui.status.text == "Runecloth Bag is in the auction house's search box - click Search there." and
          Has(ui.search.tip, "then click Search there"),
          "gold search button: the name goes into the auction house's search box and the window says to click Search there")
    ahf.SearchBar.shown = false
    box.text = nil
    Click(ui.search)
    check(box.text == nil and ui.status.text == "Open the Buy tab first", "gold search button: the search bar not showing: it says so")
    ahf.SearchBar.shown = true
    W.SetAuctionator({})
    Click(ui.search)
    check(ui.status.text == "Searching in Auctionator" and W.auctionator.searches[1][1] == "Runecloth Bag" and
          W.auctionator.caller == "PacesQualityOfLife" and box.text == nil,
          "gold search button: with Auctionator there, its exact search is asked")
    W.auctionator.searchError = true
    Click(ui.search)
    check(ui.status.text == "Runecloth Bag is in the auction house's search box - click Search there." and
          box.text == "Runecloth Bag" and #W.ns.errors == 0,
          "gold search button: Auctionator's search failing: the search box instead")
    W.SetAuctionator(nil)
    advance(1)
    check(ui.selected and ui.selected.name == "Runecloth Bag" and ui.rows[1].sel.shown,
          "gold window: the selection stays on the item when the lists are worked out again")

    -- the enchants view
    ui.enchantCheck:SetChecked(true)
    Click(ui.enchantCheck)
    local ench = G.EnchantRows()
    check(ui.view == "enchants" and #ench == 1 and ui.rows[1].row == ench[1] and ui.heads[1].label.text == "Enchant" and
          ui.heads[3].label.text == "Cost" and not ui.heads[4].shown and Has(ui.rows[1].cells[1].text, "Enchant Bracer") and
          ui.rows[1].cells[3].text == ui.Coins(ench[1].cost, true) and ui.rows[1].cells[4].text == "" and not ui.rows[1].icon.shown and
          ui.foot.text == G.ENCHANT_FOOTER and ui.enchantCheck.shown,
          "gold window: the Enchants box lists what each enchant's materials cost, with the footer")
    Click(ui.rows[1])
    check(ui.search:IsEnabled() == false and Has(ui.search.tip, "nothing to search for"),
          "gold window: an enchant can't be searched for")
    check(Has(Hover(W, ui.rows[1]), "Enchant Bracer"), "gold window: an enchant row's tooltip starts with its name")
    ui.enchantCheck:SetChecked(false)
    Click(ui.enchantCheck)
    check(ui.view == "crafts" and ui.rows[1].row == crafts[1] and ui.foot.text == "" and ui.heads[8].shown, "gold window: unticked: the crafts again")

    ----------------------------------------------------------------------
    -- Bargains and Vendors
    ----------------------------------------------------------------------
    Click(ui.tabs.bargains)
    advance(1)
    local bargains = G.BargainRows()
    local vrow
    for _, b in ipairs(ui.rows) do if b.row and b.row.kind == "Vendor" and b.row.id == 14047 then vrow = b end end
    check(ui.tab == "bargains" and ui.tabs.bargains:IsEnabled() == false and ui.tabs.crafts:IsEnabled() and #bargains > 0 and
          ui.rows[1].row == bargains[1] and ui.enchantCheck.shown == false and ui.heads[1].label.text == "Kind" and
          ui.heads[7].label.text == "Profit" and not ui.heads[8].shown,
          "gold window: the Bargains tab shows the background pass's rows")
    check(vrow and vrow.cells[1].text == "Vendor" and Has(vrow.cells[2].text, "Runecloth") and
          vrow.cells[3].text == ui.Coins(100, true) and vrow.cells[4].text == ui.Coins(vrow.row.upTo, true) and
          vrow.cells[5].text == ui.Coins(400, true) and vrow.cells[6].text == "50" and
          vrow.cells[7].text == ui.Coins(15000, true) and vrow.cells[8].text == "",
          "gold window: a Bargains row: kind, item, cheapest, buy up to, worth, units, profit")
    check(vrow and Has(Hover(W, vrow), "Press Search to see it in the auction house. Pace's QoL never buys for you."),
          "gold window: a bargain's tooltip ends with what to do")
    W.timeShift = (W.timeShift or 0) + 2 * 3600 + 60
    advance(0.5)
    Click(ui.tabs.vendors)
    Click(ui.tabs.bargains)
    check(#G.BargainRows() == 0 and ui.empty.shown and
          ui.empty.text == "These prices are 2 hours old - bargains will be gone. Press Scan or Price my items." and
          ui.header.text:sub(1, 10) == "|cffff9933" and ui.count.text == "",
          "gold window: two hours on, Bargains is empty and says why; the header turns orange (" .. tostring(ui.empty.text) .. ")")
    Click(ui.tabs.crafts)
    check(#G.CraftRows() == 2 and ui.header.text:sub(1, 10) ~= "|cffff9933", "gold window: (on Crafts the same prices are not old yet)")
    Click(ui.tabs.vendors)
    check(ui.tab == "vendors" and #G.VendorRows() == 0 and ui.empty.shown and
          ui.empty.text == "Visit vendors - I remember what they sell - then price the items." and ui.heads[6].label.text == "Where",
          "gold window: Vendors with nothing to show says to visit vendors")
    W.npcName = "Trader Tess"
    W.merchant = {{id = 14341, price = 1000}}
    W.Fire("MERCHANT_SHOW")
    advance(1)
    local vend = G.VendorRows()
    check(#vend == 1 and ui.rows[1].row == vend[1] and ui.empty.shown == false and Has(ui.rows[1].cells[1].text, "Rune Thread") and
          ui.rows[1].cells[2].text == ui.Coins(1000, true) and Has(ui.rows[1].cells[3].text, ui.Coins(vend[1].auction, true)) and
          ui.rows[1].cells[4].text == ui.Coins(vend[1].profit, true) and Has(ui.rows[1].cells[6].text, "Trader Tess"),
          "gold window: a visited vendor's item that sells for more shows up on Vendors")

    ----------------------------------------------------------------------
    -- Your bags: scrolling, items still loading, totals
    ----------------------------------------------------------------------
    W.bags[0] = {n = 20}
    for i = 1, 20 do
        W.items[50000 + i] = {name = ("Thing %02d"):format(i), stack = 20, sell = i * 10, class = 7, loaded = (i ~= 20) and true or false}
        W.bags[0][i] = {itemID = 50000 + i, stackCount = i, quality = 1}
    end
    W.bags[1] = {n = 2, [1] = {itemID = 14047, stackCount = 10, quality = 1}, [2] = {itemID = 14046, stackCount = 1, quality = 2, isBound = true}}
    W.Fire("BAG_UPDATE_DELAYED")
    Click(ui.tabs.bags)
    local bags = G.BagRows()
    check(ui.tab == "bags" and #bags == 22 and ui.rows[14].shown and ui.rows[1].row == bags[1] and ui.rows[14].row == bags[14] and
          ui.count.text == "1-14 of 22" and ui.slider.shown and ui.offset == 0,
          "gold window: Your bags lists the stacks, 14 at a time")
    local cloth, sack, loading
    for _, row in ipairs(bags) do
        if row.id == 14047 then cloth = row elseif row.id == 14046 then sack = row elseif row.id == 50020 then loading = row end
    end
    check(ui.rows[1].row == sack and Has(ui.rows[1].cells[1].text, "bound") and ui.rows[1].cells[2].text == "1" and
          ui.rows[1].cells[3].text == ui.Coins(20000, true) and ui.rows[1].cells[4].text == "" and
          ui.rows[1].cells[6].text == "Vendor " .. ui.Coins(20000, true),
          "gold window: a bound stack: its vendor price is its best")
    check(ui.rows[2].row == cloth and cloth.auction and ui.rows[2].cells[4].text == ui.Coins(cloth.auction, true) and
          ui.rows[2].cells[6].text == cloth.bestHow .. " " .. ui.Coins(cloth.best, true),
          "gold window: a priced stack: auction and best")
    local totals = G.BagTotals(bags, ui.ShortCoins)
    check(ui.foot.text == totals.text and Has(ui.foot.text, "Vendors " .. ui.Coins(totals.vendor, true)) and
          Has(ui.foot.text, "20 unpriced (Price my items)") and Has(ui.foot.text, "UI-GoldIcon"),
          "gold window: the totals line under the bags, with coins (" .. tostring(ui.foot.text) .. ")")
    -- the wheel and the slider
    RunScript(f, "OnMouseWheel", -1)
    check(ui.offset == 3 and ui.rows[1].row == bags[4] and ui.count.text == "4-17 of 22", "gold window: the wheel scrolls three rows")
    RunScript(f, "OnMouseWheel", -1)
    RunScript(f, "OnMouseWheel", -1)
    RunScript(f, "OnMouseWheel", -1)
    check(ui.offset == 8 and ui.rows[14].row == bags[22] and ui.count.text == "9-22 of 22", "gold window: ... and stops at the end")
    RunScript(ui.slider, "OnValueChanged", 2)
    check(ui.offset == 2 and ui.rows[1].row == bags[3], "gold window: the slider scrolls too")
    RunScript(ui.slider, "OnValueChanged", nil)
    RunScript(f, "OnMouseWheel", nil)
    check(ui.offset == 2 and #W.ns.errors == 0, "gold window: a slider or wheel that says nothing changes nothing")
    RunScript(f, "OnMouseWheel", 5)
    check(ui.offset == 0 and ui.rows[1].row == bags[1] and #W.ns.errors == 0, "gold window: ... and back to the top")
    -- sorted by count, the logic's list untouched
    Click(Head(ui, "Count"))
    check(ui.rows[1].row.count == 20 and ui.rows[2].row.count == 19 and G.BagRows()[1] == bags[1],
          "gold window: Your bags sorted by count")
    Click(Head(ui, "Count"), "RightButton")
    -- an item whose name hasn't loaded
    check(loading and loading.name == nil, "gold window: (one item's data hasn't arrived)")
    local lb
    for _, b in ipairs(ui.rows) do if b.row == loading then lb = b end end
    check(lb and Has(lb.cells[1].text, "item #50020"), "gold window: a row whose item hasn't loaded shows its number")
    Click(lb)
    check(ui.search:IsEnabled() == false and ui.search.tip == "Still loading this item's name",
          "gold window: Search waits for the item's name")
    advance(2)
    -- (named now, it sorts among the other things: further down)
    local named
    RunScript(f, "OnMouseWheel", -10)
    for _, b in ipairs(ui.rows) do if b.row and b.row.id == 50020 then named = b end end
    check(named and Has(named.cells[1].text, "Thing 20") and ui.selected == named.row and named.sel.shown and ui.search:IsEnabled(),
          "gold window: the name fills in when the data arrives, and Search is ready")
    -- the bags change while the window shows
    W.bags[1][1].stackCount = 15
    W.Fire("BAG_UPDATE_DELAYED")
    advance(0.5)
    local now
    for _, row in ipairs(ui.list) do if row.id == 14047 then now = row end end
    check(now and now.count == 15, "gold window: the bags changing refreshes Your bags")

    ----------------------------------------------------------------------
    -- Scan and Price my items from the window
    ----------------------------------------------------------------------
    W.ah.rows = {{id = 14047, count = 20, buyout = 2000, owner = "Someone"}, {id = 14048, count = 10, buyout = 7000, owner = "Someone"}}
    Click(ui.scan)
    check(G.State().state == "asked" and ui.scan:IsEnabled() == false and ui.check:IsEnabled() == false and
          ui.check.tip == "Wait for the scan to finish" and ui.status.text == "Asking the auction house for its list...",
          "gold scan button: a click asks for the list; both buttons wait and the window says what is happening")
    advance(5)
    check(G.State().state == "idle" and ui.scan.text == "Scan (in 15 min)" and ui.scan:IsEnabled() == false and
          ui.check:IsEnabled() and Has(ui.header.text, "full scan"),
          "gold scan button: after the scan it counts down the 15 minutes; Price my items stays ready (" .. tostring(ui.scan.text) .. ")")
    advance(120)
    check(ui.scan.text == "Scan (in 13 min)", "gold scan button: the countdown runs while the window shows (" .. tostring(ui.scan.text) .. ")")
    W.Slash("gold scan")
    Click(ui.scan)
    check(G.State().state == "idle", "gold scan button: (disabled, a click starts nothing)")
    -- the scan has just answered for everything the recipes, bags and vendors use
    Click(ui.check)
    check(G.State().state == "idle" and ui.status.text == "Everything was priced in the last 10 minutes" and
          Has(ui.check.tip, "About 0 seconds."),
          "gold check button: straight after a full scan there is nothing left to look up, and it says so (" .. tostring(ui.status.text) .. ")")
    W.timeShift = (W.timeShift or 0) + 601
    advance(1)
    Click(ui.check)
    check(G.State().state == "checking" and ui.check.text == "Stop" and ui.check:IsEnabled() and ui.scan:IsEnabled() == false and
          Has(ui.status.text, "Pricing"),
          "gold check button: Price my items starts the look-up and becomes Stop")
    advance(3)
    Click(ui.check)
    check(G.State().state == "idle" and ui.check.text == "Price my items" and Has(ui.status.text, "Price check stopped"),
          "gold check button: Stop stops it and the window says how it ended")
    W.timeShift = (W.timeShift or 0) + 900
    advance(2)
    check(ui.scan.text == "Scan" and ui.scan:IsEnabled(), "gold scan button: ready again after the wait")
    advance(10) -- (the stopped check's follow-up settles)
    idle = W.tick
    advance(30)
    check(W.tick <= idle + 1,
          "gold window: with no countdown and no job on screen, no timer of ours runs (but the once-a-minute refresh)")

    ----------------------------------------------------------------------
    -- Blizzard's frame untouched, getters that say nothing, off and on
    ----------------------------------------------------------------------
    check(Keys(ahf) == Keys(bare) and Keys(ahf.SearchBar) == Keys(bare.SearchBar) and W.env.UISpecialFrames == nil,
          "gold window: nothing was written into the auction house's frame")
    -- the window moved
    RunScript(ui.drag, "OnDragStart")
    local getPoint = f.GetPoint
    f.GetPoint = function() return nil end
    RunScript(ui.drag, "OnDragStop")
    check(W.ns.db.goldPos == nil and #W.ns.errors == 0, "gold window: a frame that can't say where it is: no position kept, no error")
    f.GetPoint = getPoint
    f:SetPoint("TOPLEFT", W.env.UIParent, "TOPLEFT", 120.4, -80.6)
    RunScript(ui.drag, "OnDragStop")
    local pos = W.ns.db.goldPos
    check(pos and pos[1] == "TOPLEFT" and pos[2] == "TOPLEFT" and pos[3] == 120 and pos[4] == -81,
          "gold window: dragged by its title, the place is kept")
    W.Slash("gold off")
    check(f.shown == false and ui.ahHolder.shown == false, "gold window: switched off: the window and the auction house tab hide")
    W.printed = {}
    W.Slash("gold")
    Click(W.optionsPanel.goldOpen)
    check(f.shown == false and Printed(W, "gold: switched off"), "gold window: ... and it doesn't open while off")
    W.Slash("gold on")
    check(ui.ahTab == ahb and ui.ahHolder.shown and ChildrenOf(W, ahf) == 1, "gold window: switched on: the same tab again")
    W.Slash("gold")
    check(f.shown and ui.frame == f and #W.ns.errors == 0, "gold window: ... and the window opens again, with no errors all along")

    -- a /reload: the window comes back where it was left
    W = Reload(W)
    table.insert(gone, W)
    ui = W.ns.Gold.ui
    W.Slash("gold")
    check(ui.frame and ui.frame.shown and ui.frame.point[1] == "TOPLEFT" and ui.frame.point[2] == W.env.UIParent and
          ui.frame.point[3] == "TOPLEFT" and ui.frame.point[4] == 120 and ui.frame.point[5] == -81,
          "gold window: after a /reload it opens where it was left")
    -- (the bag has sold out since: its last price is no proven one, and it comes after the bolt)
    check(#W.ns.Gold.CraftRows() == 2 and ui.rows[1].row and ui.rows[1].row.name == "Bolt of Runecloth" and ui.rows[2].row and
          ui.rows[2].row.name == "Runecloth Bag" and ui.rows[2].row.sells == 57000 and ui.rows[2].row.mark == "unproven",
          "gold window: ... with the recipes and prices it had")
    W.ns.db.goldPos = {"NOWHERE", 5, "x"}
    W = Reload(W)
    table.insert(gone, W)
    W.Slash("gold")
    check(W.ns.Gold.ui.frame.point[1] == "CENTER" and #W.ns.errors == 0, "gold window: a saved place that makes no sense: the middle")

    ----------------------------------------------------------------------
    -- review fixes: the window
    ----------------------------------------------------------------------
    do
        local X = Stock(GP("GoldWin2"))
        local GX = X.ns.Gold
        local ux = GX.ui
        setmetatable(X.ah.commodity, {__index = function() return true end})
        -- the options page's button opens (never closes), on top
        Click(X.optionsPanel.goldOpen)
        local fx = ux.frame
        check(fx and fx.shown and (fx.raised or 0) == 1, "gold window: opened, it is raised above what else is at its strata (the Settings panel)")
        Click(X.optionsPanel.goldOpen)
        check(fx and fx.shown and fx.raised == 2, "gold options: Open a second time leaves the window open, and raises it again")
        X.Slash("gold")
        check(fx.shown == false, "gold window: (/pqol gold still closes it)")
        X.Slash("gold")
        -- the lines under the list, and the buttons
        check(ux.status.wrap == true and ux.status.maxLines == 2 and ux.foot.wrap == false and ux.status.width == 676,
              "gold window: the status line may run to two lines")
        do
            local longest = "The auction house didn't send its list. A full scan may be limited to once every 15 minutes, or not offered here. Price my items still works." ..
                                " Your own auctions may be counted - open your Auctions tab once."
            -- (about 120 characters of this font fit the line's 676 px)
            check(#longest <= 2 * 120, "gold window: ... which the longest thing it says fits (" .. #longest .. " characters)")
        end
        check(ux.scan.point[1] == "BOTTOMLEFT" and ux.scan.point[5] >= 8 and ux.search.point[1] == "BOTTOMRIGHT" and
              ux.search.point[5] >= 8, "gold window: the buttons sit clear of the inset's bottom border")

        -- 22 stacks in the bags (one of them never loads), 18 vendor goods that sell for more
        local request = X.env.C_Item.RequestLoadItemDataByID
        X.env.C_Item.RequestLoadItemDataByID = function(id) if id ~= 50022 then return request(id) end end
        X.bags[0] = {n = 22}
        for i = 1, 22 do
            X.items[50000 + i] = {name = ("Thing %02d"):format(i), stack = 20, sell = i * 10, class = 7, loaded = (i ~= 22) and true or false}
            X.bags[0][i] = {itemID = 50000 + i, stackCount = i, quality = 1}
        end
        X.merchant = {}
        for i = 1, 18 do
            X.items[54000 + i] = {name = ("Ware %02d"):format(i), stack = 20, sell = 1, class = 7}
            X.merchant[i] = {id = 54000 + i, price = 100}
        end
        X.Fire("MERCHANT_SHOW")
        advance(0.5)
        X.OpenAH()
        for i = 1, 18 do Listed(X, 54000 + i, {{1000 + i, 5}, {1100 + i, 5}}) end
        X.Fire("BAG_UPDATE_DELAYED")
        Click(ux.tabs.bags)
        advance(0.5)
        check(#ux.list == 22 and ux.slider.min == 0 and ux.slider.max == 8 and ux.slider.value == 0 and ux.slider.shown,
              "gold window: the slider's range is the rows that don't fit (22 rows: 0 to 8)")
        -- the totals line fits, whatever the sums
        do
            local function Pixels(text)
                local icons = 0
                text = text:gsub("|T.-|t", function()
                    icons = icons + 1
                    return ""
                end)
                return #text * 5.5 + icons * 11
            end
            local rows = {{vendor = 12345678, auction = 23456789, best = 34567890, confident = true}}
            for i = 1, 12 do rows[i + 1] = {confident = false} end
            local worst = GX.BagTotals(rows, ux.ShortCoins).text
            check(Has(ux.foot.text, "22 unpriced (Price my items)") and
                  Has(worst, "12 unpriced (Price my items)") and Pixels(worst) <= ux.foot.width and Pixels(ux.foot.text) <= ux.foot.width,
                  "gold window: the bags' totals line fits its width with \"Price my items\" readable (about " ..
                  math.floor(Pixels(worst)) .. " of " .. tostring(ux.foot.width) .. " px at worst)")
        end
        -- the header's age moves with the clock
        do
            local before = ux.header.text
            X.timeShift = (X.timeShift or 0) + 1800
            advance(61)
            check(Has(before, "just now") and ux.header.text ~= before and Has(ux.header.text, "min ago"),
                  "gold window: left open, the header's \"how old\" is kept current (" .. tostring(ux.header.text) .. ")")
        end
        -- an item the game has no tooltip for
        do
            local unnamed
            for _, b in ipairs(ux.rows) do if b.row and b.row.id == 50022 then unnamed = b end end
            X.noTipData = true
            local text, tt = Hover(X, ux.rows[3])
            local row = ux.rows[3].row
            check(row.name and row.link and tt.owner == ux.rows[3] and tt.shown and tt.tried[1] == "SetHyperlink" and
                  tt.tried[2] == "SetItemByID" and tt.lines[1] == row.name and Has(text, row.bestText),
                  "gold window: the game has no tooltip for the item: ours all the same - its name, then how the row was worked out")
            text, tt = Hover(X, unnamed)
            check(unnamed and tt.owner == unnamed and tt.lines[1] == "item #50022" and #tt.lines >= 3,
                  "gold window: ... or its number, while the name hasn't loaded")
            X.noTipData = nil
        end
        -- the tooltip follows the row under the mouse
        do
            local list = ux.list
            local _, tt = Hover(X, ux.rows[2])
            check(tt.owner == ux.rows[2] and Has(tt.item, tostring(list[2].id)), "gold window: (hovering the second row)")
            RunScript(fx, "OnMouseWheel", -1)
            check(ux.rows[2].row == list[5] and tt.owner == ux.rows[2] and Has(tt.item, tostring(list[5].id)) and
                  not Has(tt.item, tostring(list[2].id)),
                  "gold window: the list scrolled under the mouse: the tooltip is the new row's")
            RunScript(ux.rows[2], "OnLeave")
        end
        -- an unproven price keeps its mark in the bags
        do
            Listed(X, 50001, {{500, 1}})
            advance(0.5)
            local marked
            for _, b in ipairs(ux.rows) do if b.row and b.row.id == 50001 then marked = b end end
            RunScript(fx, "OnMouseWheel", 10)
            for _, b in ipairs(ux.rows) do if b.row and b.row.id == 50001 then marked = b end end
            check(marked and marked.row.mark == "unproven" and Has(marked.cells[4].text, "|cffffd100*|r") and
                  Has(marked.cells[6].text, "Auction ") and Has(marked.cells[6].text, "|cffffd100*|r") and
                  Has(ux.foot.text, "1 unproven, not counted"),
                  "gold window: an unproven auction price is marked in Your bags, in Auction and in Best")
        end
        -- from a long list scrolled down to a shorter one that still scrolls: at its top
        RunScript(fx, "OnMouseWheel", -10)
        check(ux.offset == 8 and ux.slider.value == 8, "gold window: (the bags scrolled to the end)")
        Click(ux.tabs.vendors)
        check(#GX.VendorRows() == 18 and ux.offset == 0 and ux.count.text == "1-14 of 18" and ux.rows[1].row == GX.VendorRows()[1] and
              ux.slider.value == 0 and ux.slider.max == 4,
              "gold window: another tab opens at its top, wherever the last list was scrolled to (" .. tostring(ux.count.text) .. ")")
        ux.slider:SetValue(3)
        check(ux.offset == 3 and ux.rows[1].row == GX.VendorRows()[4], "gold window: (dragging the slider still scrolls)")
        ux.slider:SetValue(0)
        -- the selection belongs to its tab
        Click(ux.rows[2])
        check(ux.selected == ux.rows[2].row and ux.search:IsEnabled(), "gold window: (a vendor row selected)")
        Click(ux.tabs.bags)
        check(ux.selected == nil and ux.search:IsEnabled() == false and ux.search.tip == "Click a row first.",
              "gold window: another tab: nothing is selected, and Search waits for a click")

        -- a note doesn't outlive what it was about
        X.CloseAH()
        advance(0.5)
        Click(ux.rows[3])
        Click(ux.search)
        check(ux.status.text == "Open the auction house first", "gold search button: (the auction house closed: it says to open it)")
        X.OpenAH()
        check(ux.status.text ~= "Open the auction house first", "gold window: the auction house opened: the note asking for it is gone")
        advance(0.5)

        -- the list shrinks while it is scrolled down, with a row selected and one hovered
        RunScript(fx, "OnMouseWheel", -10)
        Click(ux.rows[14])
        local last = ux.rows[14].row
        local _, tt = Hover(X, ux.rows[10])
        check(ux.offset == 8 and ux.selected == last and last.id == 50021 and tt.owner == ux.rows[10], "gold window: (scrolled to the end, the last row selected)")
        local kept = X.bags[0][21]
        for i = 4, 22 do X.bags[0][i] = nil end
        X.bags[0].n = 3
        X.Fire("BAG_UPDATE_DELAYED")
        advance(0.5)
        do
            local hidden = true
            for i = 4, 14 do if ux.rows[i].shown then hidden = false end end
            check(#ux.list == 3 and ux.offset == 0 and ux.count.text == "1-3 of 3" and ux.rows[3].shown and hidden and
                  ux.rows[1].row == ux.list[1], "gold window: a list grown shorter is shown from its top, the rows past its end hidden")
            check(ux.slider.shown == false and ux.slider.max == 0 and ux.slider.value == 0, "gold window: ... with no slider when it all fits")
            check(ux.selected == nil and ux.search:IsEnabled() == false, "gold window: a selected row that is gone is no longer selected")
            check(tt.owner == nil and tt.shown == false, "gold window: the tooltip of a row that is gone is hidden")
        end
        X.bags[0].n, X.bags[0][4] = 4, kept
        X.Fire("BAG_UPDATE_DELAYED")
        advance(0.5)
        check(ux.selected and ux.selected.id == 50021 and ux.search:IsEnabled(),
              "gold window: ... and selected again when it comes back")

        -- the Enchants box clears the selection too
        Recipe(X, 1, "Runecloth Bag", 14046, {{14048, 5}})
        Recipe(X, 3, "Enchant Bracer", nil, {{10940, 2}}, {enchant = true})
        X.trade.prof = {professionID = 197, professionName = "Tailoring", skillLevel = 300, maxSkillLevel = 300}
        X.Fire("TRADE_SKILL_SHOW")
        advance(1)
        Click(ux.tabs.crafts)
        Click(ux.rows[1])
        check(ux.selected ~= nil, "gold window: (a craft selected)")
        ux.enchantCheck:SetChecked(true)
        Click(ux.enchantCheck)
        check(ux.view == "enchants" and ux.selected == nil and ux.offset == 0 and ux.search:IsEnabled() == false,
              "gold window: ticking Enchants starts that list with nothing selected")
        ux.enchantCheck:SetChecked(false)
        Click(ux.enchantCheck)

        -- Search pressed during a price check: the progress comes back
        Click(ux.tabs.bags)
        Click(ux.rows[2])
        Click(ux.check)
        check(GX.State().state == "checking" and Has(ux.status.text, "Pricing"), "gold window: (a price check running)")
        Click(ux.search)
        check(Has(ux.status.text, "is in the auction house's search box"), "gold window: (Search says where the name went)")
        advance(10)
        check(GX.State().state == "checking" and Has(ux.status.text, "Pricing") and ux.status.text == GX.State().message,
              "gold window: a note over a running job gives the line back to the job's progress (" .. tostring(ux.status.text) .. ")")
        Click(ux.check)
        check(GX.State().state == "idle" and Has(ux.status.text, "Price check stopped") and #X.ns.errors == 0,
              "gold window: ... and to how it ended")
        X.env.C_Item.RequestLoadItemDataByID = request
    end

    ----------------------------------------------------------------------
    -- second review: what each cell says, errors kept inside, the tick
    ----------------------------------------------------------------------
    do
        local Y = Stock(GP("GoldWin3"))
        local GY = Y.ns.Gold
        local uy = GY.ui
        Y.knowsDisenchant = true
        setmetatable(Y.ah.commodity, {__index = function() return true end})
        Y.items[14048].sell = 100
        Y.items[13856] = {name = "Runecloth Belt", quality = 2, ilvl = 51, sell = 5000, class = 4, bind = 2}
        Y.items[11176] = {name = "Dream Dust", stack = 20, class = 7, reagent = true}
        Y.items[16202] = {name = "Lesser Eternal Essence", stack = 10, class = 7, reagent = true}
        Y.items[50001] = {name = "Oddment", stack = 20, sell = 10, class = 7}
        Recipe(Y, 1, "Runecloth Bag", 14046, {{14048, 5}})
        Recipe(Y, 2, "Bolt of Runecloth", 14048, {{14047, 5}})
        Y.trade.recipes[2].cooldown = 60
        Y.trade.prof = {professionID = 197, professionName = "Tailoring", skillLevel = 300, maxSkillLevel = 300}
        Y.Fire("TRADE_SKILL_SHOW")
        advance(1)
        Y.OpenAH()
        -- three days of prices, then today's: bolts sold out, cloth cheap, a belt under its disenchant value
        for _ = 1, 3 do
            Listed(Y, 14048, {{900, 20}, {950, 5}})
            Listed(Y, 14047, {{1000, 10}})
            Y.timeShift = (Y.timeShift or 0) + 86400
        end
        Listed(Y, 14048, {})
        Listed(Y, 14047, {{700, 10}, {1000, 10}})
        Listed(Y, 11176, {{2000, 10}, {2100, 5}})
        Listed(Y, 16202, {{10000, 5}, {10500, 5}})
        Listed(Y, 13856, {{5000, 1}})
        Y.bags[0] = {n = 3, [1] = {itemID = 14047, stackCount = 10, quality = 1},
                     [2] = {itemID = 14047, stackCount = 5, quality = 1, isBound = true},
                     [3] = {itemID = 50001, stackCount = 2, quality = 1}}
        Y.Slash("gold")
        advance(1)
        local fy = uy.frame
        -- the button showing a row
        local function Shown(field, value, bound)
            for _, b in ipairs(uy.rows) do
                if b.shown and b.row and b.row[field] == value and (bound == nil or (b.row.bound or false) == bound) then return b end
            end
        end
        local GREY_STAR, GREY = "|cff808080*|r", "|cff808080"

        -- Crafts: a cooldown, a sold-out output at its usual price
        local bolt = Shown("id", 14048)
        check(bolt and bolt.row.mark == "none listed" and bolt.row.how == "Auction" and Has(bolt.cells[1].text, "cooldown") and
              bolt.cells[4].text == uy.Coins(bolt.row.sells, true) .. " " .. GREY_STAR and bolt.cells[7].text == "0",
              "gold window: a recipe on a cooldown says so beside its name; none listed now is a grey * beside what it sells for")
        check(Shown("id", 14046) and not Has(Shown("id", 14046).cells[1].text, "cooldown") and
              not Has(Shown("id", 14046).cells[1].text, "old"), "gold window: (a row with neither has neither)")

        -- Bargains: "Looking..." while the first pass runs, then the rows
        Click(uy.tabs.bargains)
        check(uy.empty.shown and uy.empty.text == "Looking through the prices for bargains...",
              "gold window: Bargains opened before the pass has run says it is looking")
        advance(0.5)
        local dis, mat = Shown("kind", "Disenchant"), Shown("kind", "Material")
        check(dis and dis.row.estimate and dis.cells[7].text == "~" .. uy.Coins(dis.row.profit, true) and uy.empty.shown == false,
              "gold window: an estimated profit is written with a ~")
        check(mat and mat.row.id == 14047 and Has(mat.cells[2].text, GREY .. "used by Bolt of Runecloth|r") and
              mat.cells[7].text == uy.Coins(mat.row.profit, true),
              "gold window: a bargain's note is beside its name, in grey; a profit that is no estimate has no ~")
        check(uy.foot.text == "", "gold window: (nothing under the Bargains list when the pass is done)")
        Y.Slash("gold cut 5")
        uy.Refresh()
        check(#uy.list > 0 and uy.foot.text == "still looking", "gold window: the pass running again under a list that shows: \"still looking\"")
        advance(0.5)
        check(uy.foot.text == "", "gold window: ... gone when it is done")

        -- Your bags: bound and unbound apart, a stack with no price in grey
        Y.Fire("BAG_UPDATE_DELAYED")
        Click(uy.tabs.bags)
        local free, bound, odd = Shown("id", 14047, false), Shown("id", 14047, true), Shown("id", 50001)
        check(#uy.list == 3 and free and bound and free ~= bound and uy.rows[1] == free and uy.rows[2] == bound and
              Has(bound.cells[1].text, "bound") and not Has(free.cells[1].text, "bound") and bound.cells[2].text == "5",
              "gold window: bound and unbound stacks of one item are two rows")
        check(odd and odd.row.confident == false and odd.cells[4].text == GREY .. "?|r" and
              odd.cells[6].text == GREY .. "Vendor " .. GY.Money(20) .. " - auction price unknown|r",
              "gold window: a stack with no auction price: a grey ? and a grey Best that claims nothing")
        Click(bound)
        Y.bags[0][2].stackCount = 6
        Y.Fire("BAG_UPDATE_DELAYED")
        advance(0.5)
        check(uy.selected and uy.selected.bound == true and uy.selected.count == 6 and uy.rows[2].sel.shown and
              not uy.rows[1].sel.shown, "gold window: the selection stays on the bound stack when the bags are read again")

        -- errors stay inside: a tooltip that throws, a click, a header, the refresh timer, the close button
        local errors = Errs(Y)
        Y.tipThrow = "SetHyperlink"
        local text, tt = Hover(Y, free)
        check(free.row.link and tt.tried[1] == "SetHyperlink" and tt.tried[2] == "SetItemByID" and tt.item == 14047 and
              tt.owner == free and Errs(Y) == errors,
              "gold window: the game's tooltip throwing on the item's link: its ID is tried instead, and no error is on record")
        Y.tipThrow = nil
        local function Broken(tbl, key, what, ...)
            local real, before = tbl[key], Errs(Y)
            tbl[key] = function() error("broken on purpose") end
            local ok = pcall(what, ...)
            tbl[key] = real
            return ok and Errs(Y) > before
        end
        check(Broken(GY, "Tip", RunScript, free, "OnEnter"), "gold window: an error while a row's tooltip is filled is recorded, not thrown")
        check(Broken(Y.env.GameTooltip, "SetOwner", RunScript, uy.scan, "OnEnter"),
              "gold window: ... and so is one in a button's tooltip")
        check(Broken(GY, "State", Click, free), "gold window: ... in a click on a row")
        check(Broken(GY, "CraftRows", Click, uy.tabs.crafts) and uy.tab == "crafts", "gold window: ... in a click on a tab")
        uy.Refresh()
        check(Broken(GY, "CraftRows", Click, Head(uy, "Cost")), "gold window: ... in a click on a column header")
        check(Broken(GY, "CraftRows", function()
            Listed(Y, 11176, {{2000, 10}, {2100, 6}})
            advance(0.5)
        end), "gold window: ... and in the refresh that follows a change, on its timer")
        check(Broken(fy, "Hide", Click, uy.close) and fy.shown, "gold window: ... and in the close button")
        Click(Head(uy, "Cost"), "RightButton")
        uy.Refresh()
        check(Shown("id", 14048) ~= nil, "gold window: (and the window still works afterwards)")

        -- the one-second tick: one of it while a countdown shows, none with the window closed
        Y.ah.rows = {{id = 14047, count = 20, buyout = 14000, owner = "Someone"}}
        Click(uy.scan)
        advance(15)
        check(uy.scan.text == "Scan (in 15 min)", "gold window: (a countdown on the Scan button)")
        local t0 = Y.tick
        for _ = 1, 10 do uy.Refresh() end
        advance(5)
        check(Y.tick - t0 >= 4 and Y.tick - t0 <= 7,
              "gold window: ten refreshes during a countdown still leave one tick a second (" .. (Y.tick - t0) .. " timers in 5 s)")
        Click(uy.close)
        advance(1.5)
        t0 = Y.tick
        advance(30)
        check(fy.shown == false and Y.tick - t0 <= 1,
              "gold window: closed during a countdown, the tick stops (" .. (Y.tick - t0) .. " timers in 30 s)")
        Y.Slash("gold")
        advance(240)
        check(uy.scan.text == "Scan (in 11 min)", "gold window: ... and runs again when it is opened (" .. tostring(uy.scan.text) .. ")")

        -- a price over 48 hours old: its age beside the name
        Y.timeShift = (Y.timeShift or 0) + 49 * 3600
        uy.Refresh()
        local old = Shown("id", 14048)
        check(old and GY.Old(old.row) == "2 d old" and Has(old.cells[1].text, GREY .. "cooldown, 2 d old|r") and
              old.cells[7].text == "?" and Shown("id", 14046) ~= nil,
              "gold window: a last-seen price shows its age in grey beside the name, and \"?\" listed")
    end
    -- the saved place can't be used after all: the middle, and the window still opens
    do
        local Z = Stock(GP("GoldWin4", {db = {goldPos = {"NOPE", "CENTER", 1, 1}}}))
        local create = Z.env.CreateFrame
        Z.env.CreateFrame = function(kind, name, parent, template)
            local w = create(kind, name, parent, template)
            if template == "BasicFrameTemplateWithInset" then
                local set = w.SetPoint
                w.SetPoint = function(self, point, ...)
                    if point == "NOPE" then error("SetPoint: unknown point") end
                    return set(self, point, ...)
                end
            end
            return w
        end
        Z.Slash("gold")
        local fz = Z.ns.Gold.ui.frame
        check(fz and fz.shown and fz.point[1] == "CENTER" and #Z.ns.errors == 0,
              "gold window: a saved place the game refuses: the window opens in the middle, with no error")
        Z.env.CreateFrame = create
    end
    -- money in a row's cell: two coins at most, so the narrowest column has room
    do
        local ui2 = W.ns.Gold.ui
        local G_, S_, C_ = "|TInterface\\MoneyFrame\\UI-GoldIcon:0|t", "|TInterface\\MoneyFrame\\UI-SilverIcon:0|t",
                           "|TInterface\\MoneyFrame\\UI-CopperIcon:0|t"
        check(ui2.Coins(78540, true) == "7" .. G_ .. " 85" .. S_ and ui2.Coins(9999, true) == "99" .. S_ .. " 99" .. C_ and
              ui2.Coins(10000, true) == "1" .. G_ and ui2.Coins(10099, true) == "1" .. G_ and
              ui2.Coins(9999999, true) == "999" .. G_ .. " 99" .. S_ and ui2.Coins(10009999, true) == "1,000" .. G_ and
              ui2.Coins(78540) == "7" .. G_ .. " 85" .. S_ .. " 40" .. C_ and ui2.Coins(10009999) == "1,000" .. G_ .. " 99" .. S_ .. " 99" .. C_,
              "gold window: in a row a price drops its copper from 1 gold up and its silver from 1,000 gold up; elsewhere it is whole")
        -- (digits about 6 px wide in the rows' small font, a space or a mark 4, a coin 12)
        local function Pixels(text)
            local icons = 0
            text = text:gsub("|T.-|t", function()
                icons = icons + 1
                return ""
            end)
            text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
            local digits = select(2, text:gsub("%d", ""))
            return digits * 6 + (#text - digits) * 4 + icons * 12
        end
        local widest = 0
        for _, copper in ipairs({99, 9999, 99999, 999999, 9999999, 99999999, 999999999, 78540, 123456}) do
            widest = math.max(widest, Pixels(ui2.Coins(copper, true)))
        end
        -- every column that shows money; marked: it may carry " *" too, or "~" and "-"
        local MONEY = {cost = 0, cheapest = 0, upTo = 0, worth = 0, vendor = 0, disenchant = 0, sells = 8, auction = 8, profit = 8}
        local tight, spare = nil, 1000
        for view, cols in pairs(ui2.COLUMNS) do
            for _, col in ipairs(cols) do
                local extra = MONEY[col[3]]
                -- (a cell is its column less 6 px)
                if extra and col.right and col[2] - 6 - widest - extra < spare then
                    tight, spare = view .. " / " .. col[1], col[2] - 6 - widest - extra
                end
            end
        end
        check(widest <= 60 and spare >= 4 and Pixels(ui2.Coins(99999, false)) > 66,
              "gold window: the widest price a row can show fits every money column with room to spare (" .. widest ..
              " px; least room: " .. tostring(tight) .. ", " .. spare .. " px)")
    end
    -- the options page doesn't scroll: it has to fit the Settings panel's 601 px
    do
        local function Visible(text) return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
        -- (as Options.lua lays it out; about 85 characters of the label's font to its 544 px, 12 px a line)
        local function Height(text, width) return math.max(30, math.ceil(#Visible(text) * (544 / 85) / width) * 12 + 12) end
        local ns, panel = W.ns, W.optionsPanel
        local y = -64
        for _, key in ipairs(ns.featureOrder) do
            y = y - Height(ns.features[key].label, 544)
            if key == "partypets" or key == "layout" or key == "gold" then y = y - 30 end
            if key == "gold" then y = y - Height(panel.goldScan.label.text, 516) end
            if key == "voice" then y = y - Height(panel.voiceShare.label.text, 516) end
        end
        local bottom = y - 12 - 12
        local label = Visible(ns.features.gold.label)
        check(#label <= 170 and Has(label, "/pqol gold") and Has(label, "never buys or posts for you"),
              "gold options: the feature's label is two lines at most (" .. #label .. " characters)")
        check(bottom >= -581, "gold options: the page ends about 20 px above the bottom of the Settings panel's 601 px (at " .. bottom .. ")")
    end

    ----------------------------------------------------------------------
    -- third review: the Best cell, the once-a-minute refresh, how long a
    -- click's note lasts, an empty bag list, Crafts and the bags
    ----------------------------------------------------------------------
    do
        local V = Stock(GP("GoldWin6"))
        local GV = V.ns.Gold
        local uv = GV.ui
        setmetatable(V.ah.commodity, {__index = function() return true end})
        Recipe(V, 1, "Runecloth Bag", 14046, {{14048, 5}})
        Recipe(V, 2, "Bolt of Runecloth", 14048, {{14047, 5}})
        V.trade.prof = {professionID = 197, professionName = "Tailoring", skillLevel = 300, maxSkillLevel = 300}
        V.Fire("TRADE_SKILL_SHOW")
        advance(1)
        V.OpenAH()
        Listed(V, 14047, {{100, 50}, {110, 40}})
        Listed(V, 14048, {{700, 30}, {720, 30}})
        Listed(V, 14046, {{60000, 3}, {65000, 2}})
        advance(1)
        -- how often the window works its lists out again
        local refreshes, realState = 0, GV.PriceState
        GV.PriceState = function(...)
            refreshes = refreshes + 1
            return realState(...)
        end
        V.Slash("gold")
        local fv = uv.frame
        check(fv and fv.shown and refreshes == 1 and uv.rows[2].shown, "gold window: (opened on Crafts, two rows)")

        -- the Best cell: the mark of an unproven auction price belongs to an auction Best only
        local Best = uv.COLUMNS.bags[6][4]
        check(uv.COLUMNS.bags[6][1] == "Best" and
              Best({confident = true, best = 2500, bestHow = "Vendor", mark = "unproven"}) == "Vendor " .. uv.Coins(2500, true) and
              Best({confident = true, best = 2500, bestHow = "Disenchant", mark = "none listed"}) == "Disenchant " .. uv.Coins(2500, true) and
              Best({confident = true, best = 2500, bestHow = "Auction", mark = "unproven"}) ==
                  "Auction " .. uv.Coins(2500, true) .. " |cffffd100*|r",
              "gold window: Best reads \"Vendor\" with no star when the vendor beats an unproven auction price; an auction Best keeps the star")

        -- Your bags with nothing in them
        Click(uv.tabs.bags)
        check(#uv.list == 0 and uv.empty.shown and uv.empty.text == "Your bags are empty." and uv.foot.text == "",
              "gold window: empty bags: the list says so, with no line of zero totals under it (\"" .. tostring(uv.foot.text) .. "\")")
        Click(uv.tabs.crafts)

        -- a click's note: gone when another row is clicked, when its 8 seconds are up, when the tab changes
        local NOTE = " is in the auction house's search box - click Search there."
        Click(uv.rows[1])
        Click(uv.search)
        local first = uv.status.text
        check(Has(first, NOTE), "gold window: (Search leaves its note: " .. tostring(first) .. ")")
        advance(5)
        Click(uv.rows[2])
        check(uv.status.text == "", "gold window: a click on another row clears the note about the last one at once")
        Click(uv.search)
        local second = uv.status.text
        check(Has(second, NOTE) and second ~= first, "gold window: (a second note, five seconds after the first)")
        advance(4)
        check(uv.status.text == second, "gold window: the first note's 8 seconds running out doesn't take the second note with it")
        refreshes = 0
        advance(4.1)
        check(uv.status.text == "" and refreshes == 0,
              "gold window: a note goes after its own 8 seconds, there and then - not at the window's next refresh")
        Click(uv.search)
        check(Has(uv.status.text, NOTE), "gold window: (a note again)")
        Click(uv.tabs.bargains)
        check(uv.status.text == "", "gold window: another tab clears the note")
        Click(uv.tabs.crafts)

        -- Crafts' "Can make" follows the bags
        local sack
        advance(2) -- (nothing else is on its way to refresh the window)
        V.counts[14048] = 10
        advance(2)
        for _, b in ipairs(uv.rows) do if b.row and b.row.id == 14046 then sack = b end end
        check(sack and sack.cells[8].text == "0", "gold window: (no bolts were in the bags: can make 0, until the bags say they changed)")
        V.Fire("BAG_UPDATE_DELAYED")
        advance(0.5)
        for _, b in ipairs(uv.rows) do if b.row and b.row.id == 14046 then sack = b end end
        check(sack and sack.cells[8].text == "2", "gold window: the bags changing refreshes an open Crafts tab (can make " ..
              tostring(sack and sack.cells[8].text) .. ")")

        -- the once-a-minute refresh goes on for as long as the window is open
        advance(60)
        check(GV.State().state == "idle" and uv.scan.text == "Scan", "gold window: (idle, no countdown)")
        refreshes = 0
        advance(185)
        check(refreshes == 3, "gold window: left open and idle, it refreshes once a minute, minute after minute (" .. refreshes ..
              " refreshes in 185 s)")
        Click(uv.close)
        refreshes = 0
        advance(100)
        check(refreshes == 0, "gold window: closed, it doesn't")
        V.Slash("gold")
        advance(10)
        V.Slash("gold")
        V.Slash("gold")
        refreshes = 0
        advance(185)
        check(refreshes == 3 and #V.ns.errors == 0,
              "gold window: closed and opened again and again, still one refresh a minute (" .. refreshes .. " in 185 s)")
        GV.PriceState = realState

        -- the status line: the warning about own auctions on its own, after a login
        V.ah.rows = {{id = 14047, count = 20, buyout = 2000}}
        Click(uv.scan)
        advance(5)
        check(uv.status.text == "Scan finished: 1 item. Your own auctions may be counted - open your Auctions tab once.",
              "gold window: (a scan that named no owner: " .. tostring(uv.status.text) .. ")")
        V = Reload(V)
        table.insert(gone, V)
        uv = V.ns.Gold.ui
        V.Slash("gold")
        check(uv.status.text == "", "gold window: after a login, away from the auction house, the status line is empty")
        V.OpenAH()
        advance(0.5)
        check(uv.status.text == "Your own auctions may be counted - open your Auctions tab once.",
              "gold window: at the auction house the warning shows on its own, with no job's message beside it")
        do
            local longest = "The scan was cut short - nothing was changed. The Scan button shows when the game allows the next one; Price my items works meanwhile." ..
                                " Your own auctions are still counted in 123 prices - press Price my items."
            check(#longest <= 2 * 120, "gold window: the longest status line still fits its two lines (" .. #longest .. " characters)")
        end
    end

    for _, R in ipairs(gone) do
        R.online = false
        players[R.name] = nil
    end
end

realPrint(("Pace's Quality of Life harness: %d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
