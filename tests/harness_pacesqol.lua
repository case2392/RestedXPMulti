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
    SendAddonMessageResult = {Success = 0, AddonMessageThrottle = 3, ChannelThrottle = 8, AddOnMessageLockdown = 11},
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
               bnetAccountId = opts.bnetAccountId, bnFriends = {}, voice = {}, selected = nil, locked = false,
               realm = "Forever"}
    nextGUID = nextGUID + 1
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
    env.WOW_PROJECT_ID = 99
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
                for _, R in pairs(players) do
                    if R.guild and R.guild == P.guild and R.online and R.prefix == prefix then
                        schedule(0.05, function() FireEvent(R, "CHAT_MSG_ADDON", prefix, msg, "GUILD", P.name .. "-" .. P.realm) end)
                    end
                end
            end
            return ENUM.SendAddonMessageResult.Success
        end,
        RequestCanLocalWhisperTarget = function(guid)
            P.whisperChecks = (P.whisperChecks or 0) + 1
            local R = playerByGUID(guid)
            local status = ENUM.ChatWhisperTargetStatus.Offline
            if R and R.online then
                status = R.faction == P.faction and ENUM.ChatWhisperTargetStatus.CanWhisper or ENUM.ChatWhisperTargetStatus.WrongFaction
            end
            schedule(0.05, function() FireEvent(P, "CAN_LOCAL_WHISPER_TARGET_RESPONSE", guid, status) end)
        end,
    }
    env.C_BattleNet = {
        SendGameData = function(gameAccountID, prefix, data)
            table.insert(P.sent, {kind = "BN", msg = data, to = gameAccountID})
            local R = playerByGameAccount(gameAccountID)
            if R and R.online and R.prefix == prefix then
                schedule(0.05, function() FireEvent(R, "BN_CHAT_MSG_ADDON", prefix, data, "WHISPER", P.gameAccountID) end)
            end
            return ENUM.SendAddonMessageResult.Success
        end,
        GetAccountInfoByID = function(bnetAccountId)
            local R
            for _, Q in pairs(players) do if Q.bnetAccountId == bnetAccountId then R = Q end end
            if not R or not P.bnFriends[R.name] then return nil end
            return {gameAccountInfo = {isOnline = R.online, gameAccountID = R.gameAccountID,
                                       clientProgram = "WoW", wowProjectID = 99}}
        end,
    }
    env.GetPlayerInfoByGUID = function(g)
        local R = playerByGUID(g)
        if R then return "Warrior", "WARRIOR", "Human", "Human", 2, R.name, R.realm end
    end

    -- communities
    env.C_Club = {
        GetClubInfo = function(id) local c = clubs[id]; if c then return {clubId = id, clubType = c.type} end end,
        GetClubMembers = function(id)
            local c = clubs[id]; if not c then return {} end
            local out = {}
            for i in ipairs(c.members) do out[i] = i end
            return out
        end,
        GetMemberInfo = function(id, memberId)
            local c = clubs[id]; local n = c and c.members[memberId]; local R = n and players[n]
            if not R then return nil end
            return {isSelf = R == P, memberId = memberId, presence = R.online and ENUM.ClubMemberPresence.Online or ENUM.ClubMemberPresence.Offline,
                    guid = R.guid, bnetAccountId = R.bnetAccountId, clubType = c.type, name = R.name}
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
        row.playerLocation = {GetGUID = function() return R.guid end}
        function row:GetMemberPlayerLocation() return self.playerLocation end
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
    env.IsInGroup = function() return false end
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

    if opts.beforeLoad then opts.beforeLoad(P, env) end
    local ns = {}
    P.ns = ns
    for _, file in ipairs(P.files or {"Core.lua", "Options.lua", "QuestLog.lua", "LFG.lua", "ZoneTracker.lua", "Voice.lua"}) do
        local chunk = assert(loadfile(ROOT .. "/PacesQualityOfLife/" .. file))
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
    check(P.ns.db.voice == true, "core: /pqol voice toggles back on")
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
    QuestLogOf(P, {{"Redridge Mountains", 7, onMap = true}, {"Ashenvale", 5}, {"Blackfathom Deeps", 4},
                   {"Darkshore", 6}, {"Dun Morogh", 6}, {"Duskwood", 6}})
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
    check(P.WatchCount() == 25 and Watched(P, 101, 107) == 7, "questlog: track all fills the game's 25, the zone on the map first")
    check(P.errorsShown[1] and P.errorsShown[1]:find("9 not tracked", 1, true),
          "questlog: and says how many didn't fit")
    P.watched = {}
    for id = 101, 125 do P.watched[id] = true end
    P.OpenQuestMap()
    master.scripts.OnClick(master)
    check(P.WatchCount() == 25, "questlog: at the cap, all-box click still can't pass 25")
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
    -- off: zone changes leave watches alone
    P.Slash("zonetracker off")
    local before = P.WatchCount()
    P.zone = "Redridge Mountains"
    P.Fire("ZONE_CHANGED_NEW_AREA")
    advance(2)
    check(P.WatchCount() == before and P.watched[112], "zone: off, nothing changes")
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
    check(healer ~= nil, "lfg: role buttons between Send Message and Group Invite")
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

realPrint(("Pace's Quality of Life harness: %d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
