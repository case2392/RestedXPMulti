-- Pace's Quality of Life - the volume you set for each person in voice,
-- kept, and set again whenever they're in voice with you (later sessions
-- included)
--
-- The game's slider (right-click someone in a voice channel: the volume
-- under their name) sets that person's volume "across all channels"
-- (C_VoiceChat.SetMemberVolume), but the game does not keep it.
--   * Seeing a change: the slider takes C_VoiceChat.SetMemberVolume as its
--     setter when its menu is first built (UnitPopupCustomControls.lua),
--     which is after this file has hooked it, and calls it on a change of
--     the mouse only (PropertySlider.lua) - never for the game's own resets.
--     So the hook sees what you set and nothing else. (The volume event,
--     VOICE_CHAT_CHANNEL_MEMBER_VOLUME_CHANGED, can't tell a reset from a
--     change, and isn't used.)
--   * Who a person is: the GUID the voice channel or the roster row gives -
--     a character's, or in a Battle.net community the Battle.net account's -
--     and, in a Battle.net community, their membership of it as well (club
--     and member id), which still says who they are should the account's
--     GUID not last from one session to the next.
--   * Setting it again: when they join a channel you're in, or you join
--     theirs, and once more a few seconds later (should the game set its
--     own as they finish joining). Nothing is set when it already matches.
-- Voice members are secret in the chat lockdown: nothing is read or set
-- then; the channel is looked at once it lifts.

local addonName, ns = ...

local M = {}
ns.VoiceVolume = M

local KEEP = 500           -- names remembered, at most (the oldest change goes first)
local RECHECK = 3          -- a volume set as someone joins is looked at again this much later
local SAME = 0.5           -- volumes closer than this are the same
local LOCK_POLL = 5        -- in the lockdown, look this often for its end
local CLUB_FRESH = 30      -- a member not found in a club's list: read it again after this
local CLUB_MAX = 500       -- members walked to match a voice member to the club, at most

local applying = false     -- our own set: not a change of yours
local clubs = {}           -- club -> {at=, byGuid = {guid -> memberId}}
local rechecks = {}        -- guid -> true: a look again is waiting
local lockPoll
local stats = {saved = 0, applied = 0, same = 0, unseen = 0}

local function Now() return GetTime() end

local function Plain(v)
    if v == nil or ns.IsSecret(v) then return nil end
    return v
end

local function Locked()
    if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown then
        local ok, locked = pcall(C_ChatInfo.InChatMessagingLockdown)
        return ok and locked and true or false
    end
    return false
end

local function Active() return ns.IsOn("voicevolume") end

local function Store(make)
    if not ns.db then return end
    local t = ns.db.voiceVolumes
    if type(t) ~= "table" then
        if not make then return end
        t = {}
        ns.db.voiceVolumes = t
    end
    return t
end

local function IsBattleNetGUID(guid)
    if type(guid) ~= "string" then return false end
    if C_AccountInfo and C_AccountInfo.IsGUIDBattleNetAccountType then
        local ok, yes = pcall(C_AccountInfo.IsGUIDBattleNetAccountType, guid)
        if ok and not ns.IsSecret(yes) then return yes == true end
    end
    return guid:find("^BNetAccount%-") ~= nil
end

local function IsBattleNetClub(clubId)
    if clubId == nil or not (C_Club and C_Club.GetClubInfo) then return false end
    local ok, info = pcall(C_Club.GetClubInfo, clubId)
    local kind = ok and type(info) == "table" and Plain(info.clubType)
    local bn = Enum and Enum.ClubType and Enum.ClubType.BattleNet or 0
    return kind == bn
end

-- a voice channel's community, if it is a community's
local function ChannelClub(channelID)
    if channelID == nil or not (C_VoiceChat and C_VoiceChat.GetChannel) then return end
    local ok, ch = pcall(C_VoiceChat.GetChannel, channelID)
    if not ok or type(ch) ~= "table" then return end
    local communities = Enum and Enum.ChatChannelType and Enum.ChatChannelType.Communities or 4
    if Plain(ch.channelType) ~= communities then return end
    return Plain(ch.clubId)
end

local function ActiveChannel()
    if not (C_VoiceChat and C_VoiceChat.GetActiveChannelID) then return end
    local ok, id = pcall(C_VoiceChat.GetActiveChannelID)
    if ok then return Plain(id) end
end

-- a club's members by GUID: read once, and again when the club's list
-- changes or a GUID isn't in it (at most every CLUB_FRESH seconds)
local function ClubBook(clubId, guid)
    if clubId == nil or not (C_Club and C_Club.GetClubMembers and C_Club.GetMemberInfo) then return end
    local key = tostring(clubId)
    local book = clubs[key]
    if book and not book.dirty and (guid == nil or book.byGuid[guid] ~= nil or Now() - book.at < CLUB_FRESH) then
        return book
    end
    book = {at = Now(), byGuid = {}, list = {}}
    clubs[key] = book
    local ok, list = pcall(C_Club.GetClubMembers, clubId)
    if ok and type(list) == "table" then
        for _, memberId in ipairs(list) do
            local okM, m = pcall(C_Club.GetMemberInfo, clubId, memberId)
            local g = okM and type(m) == "table" and Plain(m.guid)
            local id = Plain(memberId)
            if type(g) == "string" and g ~= "" and id ~= nil then
                book.byGuid[g] = id
                if #book.list < CLUB_MAX then book.list[#book.list + 1] = g end
            end
        end
    end
    return book
end

local function ClubKey(clubId, memberId) return "club:" .. tostring(clubId) .. ":" .. tostring(memberId) end

-- the names one person is remembered under: the GUID, and in a Battle.net
-- community the club membership too
local function Keys(guid, clubId)
    local keys = {guid}
    if clubId ~= nil and IsBattleNetGUID(guid) then
        local book = ClubBook(clubId, guid)
        local memberId = book and book.byGuid[guid]
        if memberId ~= nil then keys[2] = ClubKey(clubId, memberId) end
    end
    return keys
end

-- the latest volume remembered under any of these names
local function Lookup(keys)
    local store = Store()
    if not store then return end
    local best
    for _, k in ipairs(keys) do
        local e = store[k]
        if type(e) == "table" and type(e.v) == "number" and (not best or (e.at or 0) > (best.at or 0)) then best = e end
    end
    return best
end

-- the oldest go once there are too many
local function Prune(store)
    local n, oldest, oldestAt = 0, nil, nil
    for k, e in pairs(store) do
        n = n + 1
        local at = type(e) == "table" and e.at or 0
        if not oldestAt or at < oldestAt then oldest, oldestAt = k, at end
    end
    if n > KEEP and oldest ~= nil then
        store[oldest] = nil
        if n - 1 > KEEP then Prune(store) end
    end
end

local function Remember(guid, clubId, volume)
    local store = Store(true)
    if not store then return end
    local added = false
    for _, k in ipairs(Keys(guid, clubId)) do
        if store[k] == nil then added = true end
        store[k] = {v = volume, at = time and time() or 0}
    end
    stats.saved = stats.saved + 1
    if added then Prune(store) end
end

--------------------------------------------------------------------------
-- seeing a change: the slider's calls
--------------------------------------------------------------------------

-- the GUID a player location names, and the voice channel when it says
local function GuidOf(loc)
    if type(loc) ~= "table" then return end
    if loc.IsVoiceID and loc.GetVoiceID then
        local okV, isVoice = pcall(loc.IsVoiceID, loc)
        if okV and isVoice == true then
            local ok, memberID, channelID = pcall(loc.GetVoiceID, loc)
            memberID, channelID = ok and Plain(memberID), ok and Plain(channelID)
            if memberID ~= nil and memberID ~= false and channelID ~= nil and channelID ~= false then
                local okG, g = pcall(C_VoiceChat.GetMemberGUID, memberID, channelID)
                g = okG and Plain(g)
                if type(g) == "string" and g ~= "" then return g, channelID end
            end
            return
        end
    end
    if loc.GetGUID then
        local ok, g = pcall(loc.GetGUID, loc)
        g = ok and Plain(g)
        if type(g) == "string" and g ~= "" then return g end
    end
    if loc.GetUnit and UnitGUID then
        local ok, unit = pcall(loc.GetUnit, loc)
        unit = ok and Plain(unit)
        if type(unit) == "string" then
            local okG, g = pcall(UnitGUID, unit)
            g = okG and Plain(g)
            if type(g) == "string" and g ~= "" then return g end
        end
    end
end

-- the community a Battle.net account GUID belongs to here: the one whose
-- voice we're in, else the one Chat Channels shows
local function ClubFor(guid, channelID)
    if not IsBattleNetGUID(guid) then return end
    for _, id in ipairs({channelID or false, ActiveChannel() or false}) do
        local clubId = id and ChannelClub(id)
        local book = clubId ~= nil and ClubBook(clubId, guid)
        if book and book.byGuid[guid] ~= nil then return clubId end
    end
    local list = ChannelFrame and ChannelFrame.GetList and ChannelFrame:GetList()
    local sel = list and list.GetSelectedChannelButton and list:GetSelectedChannelButton()
    local clubId = sel and Plain(sel.clubId)
    local book = clubId ~= nil and ClubBook(clubId, guid)
    if book and book.byGuid[guid] ~= nil then return clubId end
end

local function OnSet(loc, volume)
    if applying or not Active() then return end
    volume = Plain(volume)
    if type(volume) ~= "number" then return end
    local guid, channelID = GuidOf(loc)
    if not guid then
        stats.unseen = stats.unseen + 1
        return
    end
    Remember(guid, ClubFor(guid, channelID), volume)
end

-- (at load: before any menu with the slider can be built)
if C_VoiceChat and C_VoiceChat.SetMemberVolume and hooksecurefunc then
    M.hooked = pcall(hooksecurefunc, C_VoiceChat, "SetMemberVolume", function(loc, volume)
        ns.SafeCall("voicevolume", OnSet, loc, volume)
    end)
end

--------------------------------------------------------------------------
-- setting it again
--------------------------------------------------------------------------

local ReadAfterLockdown

-- one member of a voice channel: their remembered volume, if it isn't set
local function ApplyFor(memberID, channelID, again)
    if not Active() then return end
    if Locked() or ns.IsSecret(memberID) or ns.IsSecret(channelID) then
        -- (secret: the lockdown, or its last moment - look once it's over)
        ReadAfterLockdown()
        return
    end
    if memberID == nil or channelID == nil or not (C_VoiceChat and C_VoiceChat.GetMemberGUID) then return end
    if C_VoiceChat.IsMemberLocalPlayer then
        local ok, me = pcall(C_VoiceChat.IsMemberLocalPlayer, memberID, channelID)
        if ok and Plain(me) == true then return end
    end
    local okG, guid = pcall(C_VoiceChat.GetMemberGUID, memberID, channelID)
    guid = okG and Plain(guid) or nil
    if type(guid) ~= "string" or guid == "" then return end
    local keys, target = {guid}, guid
    local clubId = ChannelClub(channelID)
    -- (a guild's or WoW community's members are characters, whose GUIDs last:
    -- the membership is only needed in a Battle.net community)
    if clubId ~= nil and IsBattleNetClub(clubId) then
        local book = ClubBook(clubId, guid)
        local memberId = book and book.byGuid[guid]
        if memberId == nil and book and C_VoiceChat.GetMemberID then
            -- (the voice channel may name them by their character, the
            -- club by their Battle.net account: the game matches the two
            -- as its roster does, C_VoiceChat.GetMemberID)
            for _, g in ipairs(book.list) do
                local ok, id = pcall(C_VoiceChat.GetMemberID, channelID, g)
                if ok and Plain(id) ~= nil and id == memberID then
                    memberId, target = book.byGuid[g], g
                    keys[#keys + 1] = g
                    break
                end
            end
        end
        if memberId ~= nil and IsBattleNetGUID(target) then keys[#keys + 1] = ClubKey(clubId, memberId) end
    end
    local saved = Lookup(keys)
    if not saved or not (PlayerLocation and PlayerLocation.CreateFromGUID) then return end
    local okL, loc = pcall(PlayerLocation.CreateFromGUID, PlayerLocation, target)
    if not okL or type(loc) ~= "table" then return end
    local okV, now = pcall(C_VoiceChat.GetMemberVolume, loc)
    now = okV and Plain(now) or nil
    if type(now) == "number" and math.abs(now - saved.v) < SAME then
        stats.same = stats.same + 1
        return
    end
    applying = true
    local ok = pcall(C_VoiceChat.SetMemberVolume, loc, saved.v)
    applying = false
    if ok then stats.applied = stats.applied + 1 end
    -- (once more in a moment: the game may set its own as they finish joining)
    if not again and not rechecks[target] then
        rechecks[target] = true
        C_Timer.After(RECHECK, ns.Guard("voicevolume", function()
            rechecks[target] = nil
            ApplyFor(memberID, channelID, true)
        end))
    end
end

-- everyone in a voice channel
local function Sweep(channelID)
    if not Active() or channelID == nil then return end
    if Locked() then
        ReadAfterLockdown()
        return
    end
    local ok, ch = pcall(C_VoiceChat.GetChannel, channelID)
    if not ok or type(ch) ~= "table" or type(ch.members) ~= "table" or ns.IsSecret(ch.members) then return end
    for _, m in ipairs(ch.members) do
        local id = type(m) == "table" and Plain(m.memberID)
        if id ~= nil then ApplyFor(id, channelID) end
    end
end

ReadAfterLockdown = function()
    if lockPoll then return end
    lockPoll = C_Timer.NewTicker(LOCK_POLL, ns.Guard("voicevolume", function()
        if Locked() then return end
        if lockPoll then lockPoll:Cancel() end
        lockPoll = nil
        Sweep(ActiveChannel())
    end))
end

local function OnEvent(_, event, ...)
    if event == "VOICE_CHAT_CHANNEL_ACTIVATED" then
        Sweep((...))
    elseif event == "VOICE_CHAT_CHANNEL_JOINED" then
        local _, channelID = ...
        Sweep(channelID)
    elseif event == "VOICE_CHAT_CHANNEL_MEMBER_ADDED" or event == "VOICE_CHAT_CHANNEL_MEMBER_GUID_UPDATED" then
        local memberID, channelID = ...
        ApplyFor(memberID, channelID)
    elseif event == "VOICE_CHAT_CHANNEL_MEMBER_ACTIVE_STATE_CHANGED" then
        local memberID, channelID, isActive = ...
        if ns.IsSecret(isActive) then
            ApplyFor(memberID, channelID) -- (in the lockdown: it waits for the end)
        elseif isActive then
            ApplyFor(memberID, channelID)
        end
    elseif event == "CLUB_MEMBERS_UPDATED" or event == "CLUB_MEMBER_ADDED" or event == "CLUB_MEMBER_UPDATED" then
        local clubId = Plain((...))
        local book = clubId ~= nil and clubs[tostring(clubId)]
        if book then book.dirty = true end
    end
end

function M:Init()
    local f = CreateFrame("Frame")
    for _, event in ipairs({"VOICE_CHAT_CHANNEL_ACTIVATED", "VOICE_CHAT_CHANNEL_JOINED",
                            "VOICE_CHAT_CHANNEL_MEMBER_ADDED", "VOICE_CHAT_CHANNEL_MEMBER_GUID_UPDATED",
                            "VOICE_CHAT_CHANNEL_MEMBER_ACTIVE_STATE_CHANGED",
                            "CLUB_MEMBERS_UPDATED", "CLUB_MEMBER_ADDED", "CLUB_MEMBER_UPDATED"}) do
        pcall(f.RegisterEvent, f, event)
    end
    f:SetScript("OnEvent", ns.Guard("voicevolume", OnEvent))
    M.eventFrame = f
end

function M:Apply(on)
    -- (already in voice - after a /reload, or switched on: no event says so)
    if on then Sweep(ActiveChannel()) end
end

--------------------------------------------------------------------------
-- /pqol voicevolume [forget]
--------------------------------------------------------------------------

-- people kept: one GUID each (a membership is a second name for the same)
local function Count()
    local n = 0
    for k in pairs(Store() or {}) do
        if type(k) == "string" and not k:find("^club:") then n = n + 1 end
    end
    return n
end

function M:Status()
    return ("(%d people's volume kept; this session %d change(s) of yours kept, %d set again%s%s)"):format(
               Count(), stats.saved, stats.applied,
               stats.unseen > 0 and ("; %d change(s) named nobody the add-on could tell"):format(stats.unseen) or "",
               M.hooked and "" or "; the game's volume slider could NOT be watched, so nothing new is kept")
end

function M:Command(arg)
    if arg == "forget" then
        if ns.db then ns.db.voiceVolumes = nil end
        ns.Print("voicevolume: every remembered volume forgotten (the volumes set now stay until you change them)")
        return true
    end
    return false
end

ns.RegisterFeature("voicevolume",
    "Voice chat: remember the volume you set for each person (right-click them in voice) and set it again whenever they're in voice with you, next session too. |cFFFFCC00/pqol voicevolume forget|r forgets them all",
    M)
