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
    function w:Enable() self.enabled = true end
    function w:Disable() self.enabled = false end
    function w:IsEnabled() return self.enabled ~= false end
    function w:GetParent() return self.parent end
    function w:CreateTexture() local t = Widget("Texture", nil, self); table.insert(self.regions, t); return t end
    function w:CreateFontString() local t = Widget("FontString", nil, self); table.insert(self.regions, t); return t end
    function w:GetStringHeight() return 14 end
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
local clubs = {}            -- clubId -> {type=, members = {name...}, guild=}
local ENUM = {
    ClubMemberPresence = {Unknown = 0, Online = 1, OnlineMobile = 2, Offline = 3, Away = 4, Busy = 5},
    ClubType = {BattleNet = 0, Character = 1, Guild = 2, Other = 3},
    ChatWhisperTargetStatus = {CanWhisper = 0, CanWhisperGuild = 1, Offline = 2, WrongFaction = 3},
    SendAddonMessageResult = {Success = 0, AddonMessageThrottle = 3, ChannelThrottle = 8, GeneralError = 9,
                              NotInGuild = 10, AddOnMessageLockdown = 11, TargetOffline = 12},
    ChatChannelType = {None = 0, Custom = 1, PrivateParty = 2, PublicParty = 3, Communities = 4},
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
    end
    if opts.strictLockdown then P.strictLockdown = true end
    if opts.cvarSecure then P.cvarSecure = true end
    if opts.cvarReadOnly then P.cvarReadOnly = true end
    if opts.cvarLocked then P.cvarLocked = true end
    players[name] = P
    local env = {}
    P.env = env
    for _, k in ipairs({"string", "table", "math", "pairs", "ipairs", "type", "tostring", "tonumber",
                        "select", "unpack", "error", "pcall", "setmetatable", "next", "rawget"}) do
        env[k] = _G[k]
    end
    env._G = env
    env.print = function(...)
        local t = {}
        for i = 1, select("#", ...) do t[#t + 1] = tostring(select(i, ...)) end
        table.insert(P.printed, table.concat(t, " "))
    end
    env.Enum = ENUM
    env.GetTime = function() return clock end
    env.time = function() return math.floor(clock) end
    -- /reload goes through ReloadUI, which calls C_UI.Reload (InterfaceUtil.lua)
    env.C_UI = {Reload = function() P.reloadAsked = true end}
    env.ReloadUI = function() env.C_UI.Reload() end
    env.UnitGUID = function(u) if u == "player" then return P.guid end end
    env.UnitName = function(u) if u == "player" then return P.name end end
    env.BNET_CLIENT_WOW = "WoW"
    env.WOW_PROJECT_ID = 18 -- WOW_PROJECT_CAMELOT
    env.PLAYER_FACTION_GROUP = {[0] = "Horde", [1] = "Alliance", Horde = 0, Alliance = 1}
    env.UnitFactionGroup = function(u) if u == "player" then return P.faction end end
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
        After = function(d, fn) schedule(d, fn, nil, P) end,
        NewTicker = function(d, fn)
            local t = schedule(d, fn, d, P)
            return {Cancel = function() t.cancelled = true end}
        end,
    }
    env.CreateFrame = function(kind, fname, parent, template)
        local f = Widget(kind, fname, parent)
        f.template = template
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
    P.Slash("status")
    check(Printed(P, "no errors this session"), "core: /pqol status")
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

realPrint(("Pace's Quality of Life harness: %d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
