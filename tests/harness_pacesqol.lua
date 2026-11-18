-- Offline harness for Pace's Quality of Life (Lua 5.1).
--   lua5.1 tests/harness_pacesqol.lua .
-- Several simulated players, each loading the real addon files into an
-- environment of its own, with a stub of the Forever API the addon uses
-- and a message bus between them (addon whispers, GUILD, Battle.net game
-- data). Sections per feature further down.

local ROOT = arg and arg[1] or "."
local realPrint = print
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
                                      hasFocus = not opts.appFocused, forever = true})
    end
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
    env.UnitGUID = function(u) if u == "player" then return P.guid end end
    env.UnitName = function(u) if u == "player" then return P.name end end
    env.BNET_CLIENT_WOW = "WoW"
    env.WOW_PROJECT_ID = 18 -- WOW_PROJECT_CAMELOT
    env.PLAYER_FACTION_GROUP = {[0] = "Horde", [1] = "Alliance", Horde = 0, Alliance = 1}
    env.UnitFactionGroup = function(u) if u == "player" then return P.faction end end
    env.RegionalUniqueNamesEnabled = function() return true end
    env.C_AccountInfo = {IsGUIDRelatedToLocalAccount = function(g) return g == P.guid or g == P.accountGUID end}
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
            if R and R.online then
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
    local function GameAccountInfo(R, g)
        return {gameAccountID = g.gameAccountID, clientProgram = g.clientProgram, wowProjectID = g.wowProjectID,
                isOnline = R.online, hasFocus = g.hasFocus, playerGuid = g.forever and R.guid or nil,
                characterName = g.forever and R.name or nil}
    end
    local function AccountInfo(R)
        local focused = {gameAccountID = 0, clientProgram = "", isOnline = false, hasFocus = false}
        for _, g in ipairs(R.gameAccounts) do if g.hasFocus then focused = GameAccountInfo(R, g) end end
        return {bnetAccountID = R.bnetAccountId, isFriend = true, gameAccountInfo = focused}
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
        GetGameAccountInfoByID = function(id)
            for _, n in ipairs(Friends()) do
                for _, g in ipairs(players[n].gameAccounts) do
                    if g.gameAccountID == id then return GameAccountInfo(players[n], g) end
                end
            end
        end,
        GetGameAccountInfoByGUID = function(guid)
            for _, n in ipairs(Friends()) do
                local R = players[n]
                if R.guid == guid then
                    for _, g in ipairs(R.gameAccounts) do if g.forever then return GameAccountInfo(R, g) end end
                end
            end
        end,
        GetAccountInfoByGUID = function(guid)
            for _, n in ipairs(Friends()) do
                if players[n].guid == guid then return AccountInfo(players[n]) end
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
        return {isSelf = R == P, memberId = memberId,
                presence = R.online and ENUM.ClubMemberPresence.Online or ENUM.ClubMemberPresence.Offline,
                guid = guid, bnetAccountId = R.bnetAccountId, clubType = c.type,
                name = bn and (R.bnName or R.name) or R.name, faction = R.faction == "Horde" and 0 or 1}
    end
    env.C_Club = {
        GetClubInfo = function(id) local c = clubs[id]; if c then return {clubId = id, clubType = c.type} end end,
        GetClubMembers = function(id)
            local c = clubs[id]; if not c or c.notReady then return {} end
            local out = {}
            for i in ipairs(c.members) do out[i] = i end
            return out
        end,
        GetMemberInfo = function(id, memberId)
            local c = clubs[id]; local n = c and c.members[memberId]; local R = n and players[n]
            if not R then return nil end
            return MemberInfo(c, memberId, R)
        end,
        GetMemberInfoForSelf = function(id)
            local c = clubs[id]
            if not c then return nil end
            for i, n in ipairs(c.members) do if n == P.name then return MemberInfo(c, i, P) end end
        end,
    }

    -- voice: P.voice[channelID] = {clubId=, streamId=, isActive=, members = {guid -> isActive}}
    env.C_VoiceChat = {
        GetChannel = function(id)
            local v = P.voice[id]
            if v then return {channelID = id, channelType = ENUM.ChatChannelType.Communities, clubId = v.clubId,
                              streamId = v.streamId, isActive = v.isActive} end
        end,
        GetChannelForCommunityStream = function(clubId, streamId)
            for id, v in pairs(P.voice) do
                if v.clubId == clubId and v.streamId == streamId then
                    return {channelID = id, channelType = ENUM.ChatChannelType.Communities, clubId = clubId,
                            streamId = streamId, isActive = v.isActive}
                end
            end
        end,
        GetMemberID = function(channelID, guid)
            local v = P.voice[channelID]
            if v and v.members[guid] ~= nil then return guid end
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
        function row:Update()
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
    for _, file in ipairs(P.files or {"Core.lua", "Options.lua", "QuestLog.lua", "LFG.lua", "ZoneTracker.lua", "Voice.lua"}) do
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

--------------------------------------------------------------------------
-- core: options page, slash command, saved settings
--------------------------------------------------------------------------
do
    local P = makePlayer("Coretest")
    check(P.ns.db and P.ns.db.voice == true and P.ns.db.voiceShare == true, "core: every feature on by default")
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
    local named = false
    for _, l in ipairs(justin.printed) do
        for _, R in ipairs({justin, logan, stranger, appy, plain, idle}) do
            if l:find(R.name, 1, true) or (R.bnName and l:find(R.bnName, 1, true)) then named = true end
        end
    end
    check(not named, "readout: no names or Battle.net names in it")
    justin.printed = {}
    justin.Slash("voice log")
    check(Printed(justin, "out BN Q B1:BS P.."), "readout: /pqol voice log lists the last messages")

    -- leaves and joins reach the asker at once
    logan.LeaveVoice(70)
    advance(1)
    check(not justin.RowMic(logan), "bn club: Logan leaves voice, the microphone goes")
    logan.JoinVoice(70, "B1", "BS")
    advance(1)
    check(justin.RowMic(logan), "bn club: and comes back when he rejoins")

    -- a friend still on 1.0.0 answers with the character's GUID: pinned on the member asked
    local old = makePlayer("OldLoganB", {gameAccountID = 606, bnetAccountId = 9106, voiceFile = OLD})
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

    -- logging out in voice: the leave goes out there and then
    local before = SentCount(logan)
    logan.Fire("PLAYER_LOGOUT")
    check(SentCount(logan) > before and SentCount(logan, function(x) return x.msg:sub(1, 2) == "L:" end) >= 2,
          "logout: the leave goes to the people who asked at once (no timer runs after logout)")

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
    ga.guild, gb.guild = "GX", "GX"
    clubs["B2"] = {type = ENUM.ClubType.BattleNet, members = {"GuildA", "GuildB"}}
    ga.AddRosterRow(gb)
    gb.JoinVoice(80, "B2", "BS2")
    ga.OpenChannels("B2", "BS2")
    advance(3)
    check(ga.RowMic(gb), "guild: guildmates who aren't Battle.net friends find each other (one question over GUILD)")
    check(Msgs(gb, "WHISPER", "J:B2:BS2:") >= 1 and Msgs(gb, "GUILD", "J:") == 0,
          "guild: (answered by whisper: a Battle.net community's GUIDs aren't told to the whole guild)")
    ga.printed = {}
    ga.Slash("voice")
    check(Printed(ga, "my own coming back: GUILD 1"), "readout: our own GUILD question coming back is counted (GUILD messages flow)")
    ga.CloseChannels()

    local pa = makePlayer("PartyA", {gameAccountID = 621, bnetAccountId = 9121})
    local pb = makePlayer("PartyB", {gameAccountID = 622, bnetAccountId = 9122})
    pa.group, pb.group = "grp", "grp"
    clubs["B3"] = {type = ENUM.ClubType.BattleNet, members = {"PartyA", "PartyB"}}
    pa.AddRosterRow(pb)
    pb.JoinVoice(81, "B3", "BS3")
    pa.OpenChannels("B3", "BS3")
    advance(3)
    check(pa.RowMic(pb), "group: party members who aren't Battle.net friends find each other (one question to the party)")
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

    for _, R in ipairs({ga, gb, pa, pb, na, nb, fa, fb}) do R.online = false; players[R.name] = nil end
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
    advance(1)
    closer.CloseChannels()
    closer.OpenChannels("C10", "S10")
    advance(6)
    check(closer.RowMic(endOne), "window: questions dropped on closing are asked again at once on reopening")
    closer.CloseChannels()

    for _, R in ipairs({sa, sb, ya, yb, fh, late, asker, sw, sv, g1, g2, gt, closer, endOne}) do R.online = false; players[R.name] = nil end
    for _, F in ipairs(quiet) do F.online = false; players[F.name] = nil end
end

realPrint(("Pace's Quality of Life harness: %d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
