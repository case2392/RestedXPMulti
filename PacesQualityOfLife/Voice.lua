-- Pace's Quality of Life - who's in a community voice channel, before you
-- join it
--
-- Forever's Chat Channels window (Blizzard_Channels, Mainline files on
-- camelot) shows a voice channel's members only while you are in it. The
-- game itself has no voice roster for a community stream until you join
-- it, and every way of joining also activates (ChannelFrame.lua
-- TryJoinCommunityStreamChannel -> C_VoiceChat.
-- RequestJoinAndActivateCommunityStreamChannel), so no API answers "who's
-- in there?" for a channel you never joined. Two sources fill the gap:
--   * a channel you joined this session and then left with the headset
--     stays joined but inactive (the headset calls DeactivateChannel);
--     the game keeps its members' isActive, and we show that.
--   * everyone else: Pace's QoL users tell each other. Opening Chat
--     Channels on a community stream asks that community's online
--     members "who's in voice here?" (Q); the ones in it answer (J) and
--     say when they leave (L). So you only ever see people who also run
--     Pace's QoL - nothing else can know.
-- Messages are addon messages (invisible): GUILD for a guild's own club,
-- otherwise a whisper to each online member the game says we can reach
-- (C_ChatInfo.RequestCanLocalWhisperTarget, so no "no player named"
-- spam), or Battle.net game data for Battle.net friends playing Forever.
-- Nothing is sent during the game's chat lockdown, when values go secret.
--
-- The microphone goes on the member's roster row, where Blizzard's own
-- voice buttons sit while you are in the channel; ours hides as soon as
-- you join (Blizzard's take over).

local addonName, ns = ...

local M = {}
ns.Voice = M

local PREFIX = "PQoLVoice"
local MIC_ATLAS = "voicechat-icon-mic"
local SEEN_TTL = 200       -- an answer counts this long (seconds)
local WATCH_TTL = 200      -- we tell an asker about joins/leaves this long
local ASK_EVERY = 90       -- re-ask while the window stays on a stream
local MAX_TARGETS = 60     -- whispers per question, at most (the rest next time)
local REASK_GAP = 60       -- a member isn't asked again sooner than this
local SEND_GAP = 0.2       -- seconds between queued messages
local WHISPER_OK_TTL = 300 -- how long a "can whisper" answer is trusted

local seen = {}            -- guid -> {club=, stream=, exp=}
local watchers = {}        -- key -> {to=, club=, stream=, exp=}
local whisperOK = {}       -- guid -> {ok=bool, exp=}
local pending = {}         -- guid -> {messages waiting for the whisper check}
local myVoice              -- {channelID=, club=, stream=, guild=bool}
local asked = {}           -- "club:stream" -> {target key -> time asked}
local cursor = {}          -- clubId -> where the last question stopped
local icons = setmetatable({}, {__mode = "k"})
local hooked = setmetatable({}, {__mode = "k"})
local askTicker

local function Now() return GetTime() end

local function Locked()
    if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown then
        local ok, locked = pcall(C_ChatInfo.InChatMessagingLockdown)
        return ok and locked and true or false
    end
    return false
end

local function Active() return ns.IsOn("voice") end
local function Sharing() return Active() and ns.db.voiceShare end

local function MyGUID() return UnitGUID and UnitGUID("player") end

local ONLINE = {}
if Enum and Enum.ClubMemberPresence then
    ONLINE[Enum.ClubMemberPresence.Online] = true
    ONLINE[Enum.ClubMemberPresence.Away] = true
    ONLINE[Enum.ClubMemberPresence.Busy] = true
end

--------------------------------------------------------------------------
-- sending: a small queue, so a community of sixty is not sixty messages
-- in one frame
--------------------------------------------------------------------------

local queue, pumping = {}, false

local function SendNow(item)
    if Locked() then return true end -- dropped; asked again later anyway
    local ok, result
    if item.to.guild then
        ok, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, item.msg, "GUILD")
    elseif item.to.bn then
        if not (C_BattleNet and C_BattleNet.SendGameData) then return true end
        ok, result = pcall(C_BattleNet.SendGameData, item.to.bn, PREFIX, item.msg)
    elseif item.to.name then
        ok, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, item.msg, "WHISPER", item.to.name)
    end
    local codes = Enum and Enum.SendAddonMessageResult
    if ok and codes and (result == codes.AddonMessageThrottle or result == codes.ChannelThrottle) then
        return false -- throttled: try this one again shortly
    end
    return true
end

local function Pump()
    local item = queue[1]
    if not item then
        pumping = false
        return
    end
    if SendNow(item) then
        table.remove(queue, 1)
        C_Timer.After(SEND_GAP, Pump)
    else
        C_Timer.After(1, Pump)
    end
end

local function Enqueue(msg, to)
    if msg:sub(1, 1) == "Q" then
        if #queue >= 300 then return end
        table.insert(queue, {msg = msg, to = to})
    else
        -- answers and join/leave news go ahead of any questions waiting
        local at = 1
        while queue[at] and queue[at].msg:sub(1, 1) ~= "Q" do at = at + 1 end
        table.insert(queue, at, {msg = msg, to = to})
    end
    if not pumping then
        pumping = true
        C_Timer.After(0, Pump)
    end
end

-- a whisper only once the game says that player can be reached
-- (online, same faction, a connected realm)
local function Send(msg, to)
    if not to.guid or to.guild or to.bn or
        not (C_ChatInfo and C_ChatInfo.RequestCanLocalWhisperTarget) then
        Enqueue(msg, to)
        return
    end
    local known = whisperOK[to.guid]
    if known and known.exp > Now() then
        if known.ok then Enqueue(msg, to) end
        return
    end
    local list = pending[to.guid]
    if not list then
        list = {}
        pending[to.guid] = list
        pcall(C_ChatInfo.RequestCanLocalWhisperTarget, to.guid)
    end
    if #list < 5 then table.insert(list, {msg = msg, to = to}) end
end

local function OnWhisperCheck(guid, status)
    if ns.IsSecret(guid) or ns.IsSecret(status) then return end
    local codes = Enum and Enum.ChatWhisperTargetStatus
    local ok = codes and (status == codes.CanWhisper or status == codes.CanWhisperGuild) or false
    whisperOK[guid] = {ok = ok, exp = Now() + WHISPER_OK_TTL}
    local list = pending[guid]
    pending[guid] = nil
    if ok and list then
        for _, item in ipairs(list) do Enqueue(item.msg, item.to) end
    end
end

--------------------------------------------------------------------------
-- who to ask: a community's online members
--------------------------------------------------------------------------

local function ClubType(clubId)
    local ok, info = pcall(C_Club.GetClubInfo, clubId)
    return ok and info and info.clubType
end

local function IsGuildClub(clubId)
    return Enum and Enum.ClubType and ClubType(clubId) == Enum.ClubType.Guild
end

-- a Battle.net friend playing Forever, by their game account
local function BattleNetTarget(bnetAccountId)
    if not (bnetAccountId and C_BattleNet and C_BattleNet.GetAccountInfoByID) or
        ns.IsSecret(bnetAccountId) then
        return
    end
    local ok, account = pcall(C_BattleNet.GetAccountInfoByID, bnetAccountId)
    local game = ok and account and account.gameAccountInfo
    if game and game.isOnline and game.gameAccountID and
        game.clientProgram == BNET_CLIENT_WOW and
        (not game.wowProjectID or not WOW_PROJECT_ID or game.wowProjectID == WOW_PROJECT_ID) then
        return {bn = game.gameAccountID}
    end
end

function M.Targets(clubId)
    if IsGuildClub(clubId) then return {{guild = true}} end
    local out = {}
    local ok, members = pcall(C_Club.GetClubMembers, clubId)
    if not ok or type(members) ~= "table" then return out end
    local me = MyGUID()
    for _, memberId in ipairs(members) do
        local okInfo, m = pcall(C_Club.GetMemberInfo, clubId, memberId)
        if okInfo and m and not m.isSelf and not ns.IsSecret(m.presence) and
            ONLINE[m.presence] then
            local target = BattleNetTarget(m.bnetAccountId)
            if not target and m.guid and not ns.IsSecret(m.guid) and m.guid ~= me then
                local name, realm
                if GetPlayerInfoByGUID then
                    local okName, _, _, _, _, _, n, r = pcall(GetPlayerInfoByGUID, m.guid)
                    if okName then name, realm = n, r end
                end
                if (not name or name == "") and m.clubType == Enum.ClubType.Character and
                    type(m.name) == "string" and not ns.IsSecret(m.name) then
                    name = m.name
                end
                if name and name ~= "" then
                    if realm and realm ~= "" and not name:find("-", 1, true) then
                        name = name .. "-" .. realm
                    end
                    target = {name = name, guid = m.guid}
                end
            end
            if target then out[#out + 1] = target end
        end
    end
    return out
end

--------------------------------------------------------------------------
-- the roster: our microphone on the rows of people in voice
--------------------------------------------------------------------------

local function SelectedStream()
    local list = ChannelFrame and ChannelFrame.GetList and ChannelFrame:GetList()
    local sel = list and list.GetSelectedChannelButton and list:GetSelectedChannelButton()
    if sel and sel.clubId and sel.streamId then return sel, sel.clubId, sel.streamId end
    return sel
end

-- joined this session, then left with the headset: the game still knows
-- who's active in it
local function InactiveVoiceChannel(clubId, streamId)
    if not (C_VoiceChat and C_VoiceChat.GetChannelForCommunityStream) then return end
    local ok, channel = pcall(C_VoiceChat.GetChannelForCommunityStream, clubId, streamId)
    if ok and channel and not channel.isActive then return channel.channelID end
end

local function DirectlyInVoice(channelID, guid)
    local ok, memberID = pcall(C_VoiceChat.GetMemberID, channelID, guid)
    if not ok or not memberID or ns.IsSecret(memberID) then return false end
    local okInfo, info = pcall(C_VoiceChat.GetMemberInfo, memberID, channelID)
    if not okInfo or not info or ns.IsSecret(info.isActive) then return false end
    local okMe, isMe = pcall(C_VoiceChat.IsMemberLocalPlayer, memberID, channelID)
    return info.isActive and not (okMe and isMe) and true or false
end

local function SeenInVoice(guid, clubId, streamId)
    local e = seen[guid]
    return e and e.exp > Now() and e.club == tostring(clubId) and
               e.stream == tostring(streamId) or false
end

function M.Decorate(button)
    if not button then return end
    local show = false
    if Active() and not Locked() then
        local sel, clubId, streamId = SelectedStream()
        local loc = button.GetMemberPlayerLocation and button:GetMemberPlayerLocation()
        local okGuid, guid = false, nil
        if loc and loc.GetGUID then okGuid, guid = pcall(loc.GetGUID, loc) end
        local channelActive = button.IsChannelActive and button:IsChannelActive()
        if clubId and okGuid and guid and not ns.IsSecret(guid) and not channelActive and
            guid ~= MyGUID() then
            local channelID = InactiveVoiceChannel(clubId, streamId)
            show = (channelID and DirectlyInVoice(channelID, guid)) or
                       SeenInVoice(guid, clubId, streamId)
        end
    end
    local icon = icons[button]
    if show and not icon then
        icon = button:CreateTexture(nil, "OVERLAY")
        icon:SetAtlas(MIC_ATLAS)
        icon:SetSize(14, 14)
        -- on the row, where Blizzard's voice buttons sit while you're in
        icon:SetPoint("RIGHT", button, "RIGHT", -14, 0)
        icons[button] = icon
    end
    if icon then icon:SetShown(show and true or false) end
    -- room for the icon: Blizzard sets the name's width (and puts the
    -- owner/moderator rank after it) on every update, before this hook
    if button.Name and (show or icons[button]) then
        local width = show and (button.showRank and 110 or 124) or nil
        if not show and not (button.IsChannelActive and button:IsChannelActive()) then width = 140 end
        if width then
            button.Name:SetWidth(width)
            if button.showRank and button.Rank and button.Name.GetStringWidth then
                local okW, w = pcall(button.Name.GetStringWidth, button.Name)
                if okW and type(w) == "number" and not ns.IsSecret(w) then
                    button.Rank:ClearAllPoints()
                    button.Rank:SetPoint("LEFT", button.Name, "LEFT", math.min(w, width) + 4, 0)
                end
            end
        end
    end
end

function M.Refresh()
    local roster = ChannelFrame and ChannelFrame.ChannelRoster
    local box = roster and roster.ScrollBox
    if not (box and ChannelFrame:IsShown()) then return end
    for _, frame in box:EnumerateFrames() do M.Decorate(frame) end
end

local function HookRow(frame)
    if not frame or hooked[frame] then return end
    hooked[frame] = true
    if frame.Update then
        hooksecurefunc(frame, "Update", ns.Guard("voice row", M.Decorate))
    end
end

--------------------------------------------------------------------------
-- asking, answering
--------------------------------------------------------------------------

local function TargetKey(to)
    return to.guild and "guild" or to.bn and ("bn" .. tostring(to.bn)) or to.name
end

-- ask the selected stream's online members who's in its voice. Nobody is
-- asked twice within REASK_GAP (the window's OnShow and its re-select
-- both land here; so does the member list arriving), and a big
-- community is asked MAX_TARGETS at a time, carrying on where the last
-- question stopped.
function M.Ask()
    if not Active() or Locked() then return end
    local _, clubId, streamId = SelectedStream()
    if not clubId then return end
    local streamKey = tostring(clubId) .. ":" .. tostring(streamId)
    local msg = ("Q:%s:%s:%s"):format(tostring(clubId), tostring(streamId), MyGUID() or "")
    local targets = M.Targets(clubId)
    local n = #targets
    if n == 0 then return end
    local now = Now()
    local done = asked[streamKey] or {}
    asked[streamKey] = done
    local start = (cursor[clubId] or 0) % n
    local sent = 0
    for step = 1, n do
        local i = (start + step - 1) % n + 1
        local to = targets[i]
        local key = TargetKey(to)
        if not (done[key] and now - done[key] < REASK_GAP) then
            done[key] = now
            Send(msg, to)
            sent = sent + 1
            if sent >= MAX_TARGETS then
                cursor[clubId] = i
                return
            end
        end
    end
    cursor[clubId] = nil
end

-- drop questions not yet sent (window closed, feature off)
local function DropQuestions()
    for i = #queue, 1, -1 do
        if queue[i].msg:sub(1, 1) == "Q" then table.remove(queue, i) end
    end
end

local function Announce(kind)
    if not myVoice or Locked() then return end
    local msg = ("%s:%s:%s:%s"):format(kind, myVoice.club, myVoice.stream, MyGUID() or "")
    if myVoice.guild then Send(msg, {guild = true}) end
    local now = Now()
    for key, w in pairs(watchers) do
        if w.exp < now then
            watchers[key] = nil
        elseif w.club == myVoice.club and w.stream == myVoice.stream then
            Send(msg, w.to)
        end
    end
end

-- our own voice channel changed
local function OnMyVoice(event, channelID)
    if event == "VOICE_CHAT_CHANNEL_ACTIVATED" then
        local ok, channel = pcall(C_VoiceChat.GetChannel, channelID)
        if ok and channel and Enum.ChatChannelType and
            channel.channelType == Enum.ChatChannelType.Communities then
            myVoice = {channelID = channelID, club = tostring(channel.clubId),
                       stream = tostring(channel.streamId),
                       guild = IsGuildClub(channel.clubId)}
            if Sharing() then Announce("J") end
        end
    elseif myVoice and (event == "VOICE_CHAT_LOGOUT" or event == "PLAYER_LOGOUT" or
        channelID == myVoice.channelID) then
        if Sharing() then Announce("L") end
        myVoice = nil
    end
end

local function Receive(text, replyTo)
    if not Active() or Locked() or type(text) ~= "string" then return end
    local kind, club, stream, guid = text:match("^(%a):([^:]*):([^:]*):(.*)$")
    if not kind or guid == MyGUID() then return end
    if kind == "Q" then
        if not Sharing() or replyTo.guild then return end
        -- remember who's looking, so a join or leave of ours reaches them
        -- at once rather than at their next question
        local key = replyTo.bn and ("bn" .. tostring(replyTo.bn)) or replyTo.name
        watchers[key] = {to = replyTo, club = club, stream = stream, exp = Now() + WATCH_TTL}
        if myVoice and myVoice.club == club and myVoice.stream == stream then
            Send(("J:%s:%s:%s"):format(club, stream, MyGUID() or ""), replyTo)
        end
    elseif kind == "J" and guid ~= "" then
        seen[guid] = {club = club, stream = stream, exp = Now() + SEEN_TTL}
        M.Refresh()
    elseif kind == "L" and guid ~= "" then
        local e = seen[guid]
        if e and e.club == club and e.stream == stream then seen[guid] = nil end
        M.Refresh()
    end
end

local function OnAddonMessage(event, prefix, text, channel, sender)
    if prefix ~= PREFIX then return end
    if event == "BN_CHAT_MSG_ADDON" then
        Receive(text, {bn = sender}) -- BN: the sender's game account ID
    elseif channel == "GUILD" then
        -- a guild asker gets the answer by whisper, the way it was asked
        local kind = type(text) == "string" and text:sub(1, 1)
        if kind == "Q" then
            local guid = text:match(":([^:]*)$")
            Receive(text, {name = sender, guid = guid ~= "" and guid or nil})
        else
            Receive(text, {guild = true})
        end
    else
        local guid = type(text) == "string" and text:match("^Q:[^:]*:[^:]*:(.*)$")
        Receive(text, {name = sender, guid = guid})
    end
end

--------------------------------------------------------------------------

local function StartAsking()
    if askTicker then askTicker:Cancel() end
    askTicker = nil
    M.Refresh()
    if not Active() then return end
    M.Ask()
    askTicker = C_Timer.NewTicker(ASK_EVERY, function() ns.SafeCall("voice ask", M.Ask) end)
end

local function StopAsking()
    if askTicker then askTicker:Cancel() end
    askTicker = nil
    DropQuestions()
end

-- the community's members (and who's online) load after the stream is
-- picked: ask the ones not asked yet once they're in
local reaskArmed = false
local function OnClubMembers(clubId)
    if not Active() or reaskArmed or not (ChannelFrame and ChannelFrame:IsShown()) then return end
    local _, selClub = SelectedStream()
    if not selClub or ns.IsSecret(clubId) or tostring(clubId) ~= tostring(selClub) then return end
    reaskArmed = true
    C_Timer.After(2, function()
        reaskArmed = false
        ns.SafeCall("voice ask", M.Ask)
    end)
end

local function SetupChannelFrame()
    local roster = ChannelFrame and ChannelFrame.ChannelRoster
    local box = roster and roster.ScrollBox
    if not box then return end
    if ScrollUtil and ScrollUtil.AddInitializedFrameCallback then
        ScrollUtil.AddInitializedFrameCallback(box, function(_, frame)
            HookRow(frame)
            ns.SafeCall("voice row", M.Decorate, frame)
        end, M)
    end
    for _, frame in box:EnumerateFrames() do HookRow(frame) end
    if ChannelFrame.OnUserSelectedChannel then
        hooksecurefunc(ChannelFrame, "OnUserSelectedChannel", ns.Guard("voice ask", StartAsking))
    end
    ChannelFrame:HookScript("OnShow", ns.Guard("voice ask", StartAsking))
    ChannelFrame:HookScript("OnHide", StopAsking)
end

function M:Init()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
    end
    local f = CreateFrame("Frame")
    for _, event in ipairs({"CHAT_MSG_ADDON", "BN_CHAT_MSG_ADDON",
                            "CAN_LOCAL_WHISPER_TARGET_RESPONSE",
                            "VOICE_CHAT_CHANNEL_ACTIVATED", "VOICE_CHAT_CHANNEL_DEACTIVATED",
                            "VOICE_CHAT_CHANNEL_REMOVED", "VOICE_CHAT_LOGOUT", "PLAYER_LOGOUT",
                            "VOICE_CHAT_CHANNEL_JOINED", "VOICE_CHAT_CHANNEL_MEMBER_ADDED",
                            "VOICE_CHAT_CHANNEL_MEMBER_REMOVED",
                            "VOICE_CHAT_CHANNEL_MEMBER_ACTIVE_STATE_CHANGED",
                            "CLUB_MEMBERS_UPDATED", "CLUB_MEMBER_PRESENCE_UPDATED"}) do
        pcall(f.RegisterEvent, f, event)
    end
    f:SetScript("OnEvent", ns.Guard("voice", function(_, event, ...)
        if event == "CHAT_MSG_ADDON" or event == "BN_CHAT_MSG_ADDON" then
            OnAddonMessage(event, ...)
        elseif event == "CAN_LOCAL_WHISPER_TARGET_RESPONSE" then
            OnWhisperCheck(...)
        elseif event == "CLUB_MEMBERS_UPDATED" or event == "CLUB_MEMBER_PRESENCE_UPDATED" then
            OnClubMembers((...))
        else
            if event == "VOICE_CHAT_CHANNEL_ACTIVATED" or event == "VOICE_CHAT_CHANNEL_DEACTIVATED" or
                event == "VOICE_CHAT_CHANNEL_REMOVED" or event == "VOICE_CHAT_LOGOUT" or
                event == "PLAYER_LOGOUT" then
                OnMyVoice(event, ...)
            end
            M.Refresh()
        end
    end))
    M.eventFrame = f
    ns.OnAddOnLoaded("Blizzard_Channels", function() ns.SafeCall("voice", SetupChannelFrame) end)
    -- already in a community's voice (a /reload doesn't end it): no
    -- ACTIVATED event comes, so read it now
    if C_VoiceChat and C_VoiceChat.GetActiveChannelID then
        local ok, id = pcall(C_VoiceChat.GetActiveChannelID)
        if ok and id and not ns.IsSecret(id) then OnMyVoice("VOICE_CHAT_CHANNEL_ACTIVATED", id) end
    end
end

function M:Apply(on)
    if on then
        if ChannelFrame and ChannelFrame:IsShown() then StartAsking() end
    else
        StopAsking()
        DropQuestions()
    end
    M.Refresh()
end

-- the share box was switched: say so to the people asking right now
function ns.VoiceShareChanged()
    if not myVoice or not Active() then return end
    Announce(ns.db.voiceShare and "J" or "L")
end

function M:Status()
    local n = 0
    for _, e in pairs(seen) do if e.exp > Now() then n = n + 1 end end
    return ("(%d in voice heard from other Pace's QoL users; sharing %s)"):format(
               n, ns.db.voiceShare and "on" or "off")
end

ns.RegisterFeature("voice",
    "Chat Channels: show who's in a community's voice channel before you join it (a microphone on their name; works for people who also run Pace's QoL)",
    M)
