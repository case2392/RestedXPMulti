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
--     change, and isn't used.) One drag of the slider is one change.
--   * Who a person is: one person goes by several names, and a volume is
--     kept under all of them that can be told, the newest winning: the GUID
--     a voice channel or roster row gives (a character's - a party frame's,
--     party voice - or in a Battle.net community the Battle.net account's),
--     their membership of each Battle.net community you share (club and
--     member id: it still says who they are should the account's GUID not
--     last from one session to the next), and for a Battle.net friend in
--     such a community both the account and the character they play. So the
--     party frame's slider and the community roster's set one volume. (A
--     friend you share no Battle.net community with is known by the
--     character alone: nothing gives an add-on a lasting name for the
--     account.)
--   * Setting it again: when they join a channel you're in, or you join
--     theirs, and once more a few seconds later (should the game set its
--     own as they finish joining). Nothing is set when it already matches.
-- The chat lockdown (dungeons, raids): voice members and community lists
-- are secret, so nothing is set and no list is read. A change made then is
-- kept under what can be told - the GUID when the row still gives one; the
-- rest of the person's names once the lockdown lifts. When the game can't
-- say whose a change was (a row drawn in the lockdown), what was set is
-- noted, and once the lockdown lifts a person found at exactly that volume
-- keeps it: it is taken as yours, not undone - a first change for someone
-- too. Not at the slider's top, where the game starts everyone: who is
-- there can't be told from who was set there, so it is set back as usual.

local addonName, ns = ...

local M = {}
ns.VoiceVolume = M

local KEEP = 1000          -- names remembered, at most (the oldest change goes first)
local RECHECK = 3          -- a volume set as someone joins is looked at again this much later
local SAME = 0.5           -- volumes closer than this are the same
local LOCK_POLL = 5        -- in the lockdown, look this often for its end
local CLUB_FRESH = 30      -- a member not found in the channel's community: read its list again after this
local CLUB_MAX = 500       -- members walked to match a voice member to the club, at most
local DRAG = 2             -- slider moves of one person closer together than this are one change
local TOP = 100            -- the slider's top (UnitPopupCustomControls.xml), where the game starts everyone
local UNSEEN_MAX = 20      -- changes that named nobody, noted at most

local applying = false     -- our own set: not a change of yours
local clubs = {}           -- club -> {at=, byGuid = {guid -> memberId}, byAccount = {account -> guid}, list = {guid}}
local bnClubs = {list = {}} -- your Battle.net communities: {at=, list = {clubId}}
local rechecks = {}        -- guid -> true: a look again is waiting
local lockPoll
local waiting = {}         -- guid -> {v=, at=}: changed in the lockdown, the other names to fill in
local unseen = {}          -- changes the game didn't say whose: {v=, at=, taken = true once someone kept it}
local last                 -- the last change seen: {guid=, loc=, t=} (one drag, one change)
local stats = {saved = 0, applied = 0, same = 0, unseen = 0, adopted = 0}

local function Now() return GetTime() end
local function Clock() return time and time() or 0 end

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

local function BattleNetType() return Enum and Enum.ClubType and Enum.ClubType.BattleNet or 0 end

local function IsBattleNetGUID(guid)
    if type(guid) ~= "string" then return false end
    if C_AccountInfo and C_AccountInfo.IsGUIDBattleNetAccountType then
        local ok, yes = pcall(C_AccountInfo.IsGUIDBattleNetAccountType, guid)
        if ok and not ns.IsSecret(yes) then return yes == true end
    end
    return guid:find("^BNetAccount%-") ~= nil
end

-- the Battle.net account (this session's id for it) behind a GUID: a
-- Battle.net account GUID's own, or the account of the Battle.net friend
-- playing that character
local function AccountOf(guid, bn)
    if type(guid) ~= "string" then return end
    local id
    if bn then
        if C_AccountInfo and C_AccountInfo.GetIDFromBattleNetAccountGUID then
            local ok, v = pcall(C_AccountInfo.GetIDFromBattleNetAccountGUID, guid)
            id = ok and Plain(v) or nil
        end
    elseif C_BattleNet and C_BattleNet.GetAccountInfoByGUID then
        local ok, a = pcall(C_BattleNet.GetAccountInfoByGUID, guid)
        id = ok and type(a) == "table" and Plain(a.bnetAccountID) or nil
    end
    if type(id) == "number" and id > 0 then return id end
end

-- the characters a Battle.net friend plays on WoW Forever now
local function CharactersOf(account)
    local out = {}
    local walk = ns.Voice and ns.Voice.ForeverAccounts
    if not walk then return out end
    local ok, list = pcall(walk, account)
    if not ok or type(list) ~= "table" then return out end
    for _, g in ipairs(list) do
        local guid = type(g) == "table" and g.guid
        if type(guid) == "string" and guid ~= "" and not IsBattleNetGUID(guid) then out[#out + 1] = guid end
    end
    return out
end

-- your Battle.net communities (read again every CLUB_FRESH seconds, never
-- in the lockdown)
local function BattleNetClubs()
    local fresh = bnClubs.at ~= nil and Now() - bnClubs.at < CLUB_FRESH
    if fresh or Locked() or not (C_Club and C_Club.GetSubscribedClubs) then return bnClubs.list end
    local list = {}
    local ok, all = pcall(C_Club.GetSubscribedClubs)
    if ok and type(all) == "table" and not ns.IsSecret(all) then
        pcall(function()
            for _, c in ipairs(all) do
                local id = type(c) == "table" and Plain(c.clubId)
                if id ~= nil and Plain(c.clubType) == BattleNetType() then list[#list + 1] = id end
            end
        end)
    end
    bnClubs = {at = Now(), list = list}
    return list
end

local function IsBattleNetClub(clubId)
    if clubId == nil then return false end
    for _, id in ipairs(BattleNetClubs()) do if id == clubId then return true end end
    if Locked() or not (C_Club and C_Club.GetClubInfo) then return false end
    local ok, info = pcall(C_Club.GetClubInfo, clubId)
    local kind = ok and type(info) == "table" and Plain(info.clubType)
    return kind == BattleNetType()
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

-- one member of a club, as the game has them now, into its book (false
-- when the game gives nothing to go by)
local function AddMember(book, clubId, memberId)
    local id = Plain(memberId)
    local okM, m = pcall(C_Club.GetMemberInfo, clubId, memberId)
    local g = okM and type(m) == "table" and Plain(m.guid)
    if id == nil or type(g) ~= "string" or g == "" then return false end
    local new = book.byGuid[g] == nil
    book.byGuid[g] = id
    -- (the account id is nilable: then it is read from the GUID)
    local account = Plain(m.bnetAccountId)
    if type(account) ~= "number" or account <= 0 then account = AccountOf(g, IsBattleNetGUID(g)) end
    if account ~= nil then book.byAccount[account] = g end
    if new and #book.list < CLUB_MAX then book.list[#book.list + 1] = g end
    return true
end

-- a club's members: read once, and again when the game says its list
-- changed, or - given a GUID to find, for the channel's community - when it
-- isn't in it (at most every CLUB_FRESH seconds). In the lockdown nothing
-- is read: the list as it was, if any.
local function ClubBook(clubId, guid)
    if clubId == nil then return end
    local key = tostring(clubId)
    local book = clubs[key]
    if Locked() or not (C_Club and C_Club.GetClubMembers and C_Club.GetMemberInfo) then return book end
    if book and not book.dirty and (guid == nil or book.byGuid[guid] ~= nil or Now() - book.at < CLUB_FRESH) then
        return book
    end
    book = {at = Now(), byGuid = {}, byAccount = {}, list = {}}
    local ok, list = pcall(C_Club.GetClubMembers, clubId)
    if ok and type(list) == "table" and not ns.IsSecret(list) then
        pcall(function()
            for _, memberId in ipairs(list) do AddMember(book, clubId, memberId) end
        end)
    end
    clubs[key] = book
    return book
end

local function ClubKey(clubId, memberId) return "club:" .. tostring(clubId) .. ":" .. tostring(memberId) end

local function HasClub(names, clubId)
    local prefix = "club:" .. tostring(clubId) .. ":"
    for _, k in ipairs(names) do if k:sub(1, #prefix) == prefix then return true end end
    return false
end

-- the communities to look in first: the channel's, the one whose voice
-- you're in, the one Chat Channels or the Communities window shows (then
-- every Battle.net community of yours)
local function Hints(channelID)
    local out = {}
    if Locked() then return out end
    for _, id in ipairs({channelID or false, ActiveChannel() or false}) do
        local clubId = id and ChannelClub(id)
        if clubId ~= nil then out[#out + 1] = clubId end
    end
    local list = ChannelFrame and ChannelFrame.GetList and ChannelFrame:GetList()
    local sel = list and list.GetSelectedChannelButton and list:GetSelectedChannelButton()
    if sel and Plain(sel.clubId) ~= nil then out[#out + 1] = Plain(sel.clubId) end
    if CommunitiesFrame and CommunitiesFrame.GetSelectedClubId then
        local ok, id = pcall(CommunitiesFrame.GetSelectedClubId, CommunitiesFrame)
        if ok and Plain(id) ~= nil then out[#out + 1] = Plain(id) end
    end
    return out
end

-- every name one person can be told by (see the top of the file)
local function Names(guid, hints)
    local names, seen = {}, {}
    local function add(k)
        if type(k) == "string" and k ~= "" and not seen[k] then
            seen[k] = true
            names[#names + 1] = k
        end
    end
    add(guid)
    local bn = IsBattleNetGUID(guid)
    local account = AccountOf(guid, bn)
    if bn or account ~= nil then
        local order, done, hinted = {}, {}, {}
        for _, id in ipairs(hints or {}) do
            if IsBattleNetClub(id) then
                order[#order + 1] = id
                hinted[tostring(id)] = true
            end
        end
        for _, id in ipairs(BattleNetClubs()) do order[#order + 1] = id end
        for _, clubId in ipairs(order) do
            local key = tostring(clubId)
            if not done[key] then
                done[key] = true
                -- (missing from the community the channel or window points
                -- at, they may have just joined it: its list is read again.
                -- In your other communities they usually just aren't a
                -- member: a list there is read again only when the game
                -- says it changed)
                local book = ClubBook(clubId, (bn and hinted[key]) and guid or nil)
                local g
                if book then
                    if bn and book.byGuid[guid] ~= nil then g = guid elseif account ~= nil then g = book.byAccount[account] end
                end
                local memberId = g and book.byGuid[g]
                if memberId ~= nil then
                    add(g)
                    add(ClubKey(clubId, memberId))
                end
            end
        end
    end
    if bn and account ~= nil and not Locked() then
        for _, c in ipairs(CharactersOf(account)) do add(c) end
    end
    return names
end

-- the latest volume remembered under any of these names
local function Lookup(names)
    local store = Store()
    if not store then return end
    local best
    for _, k in ipairs(names) do
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

-- the name a person is counted by: a community membership (it lasts), else
-- the Battle.net account, else the GUID
local function Leader(names)
    local best
    for _, k in ipairs(names) do
        if k:find("^club:") and (best == nil or k < best) then best = k end
    end
    if best then return best end
    for _, k in ipairs(names) do if IsBattleNetGUID(k) then return k end end
    return names[1]
end

-- keep a volume under every name of one person (a newer one stays)
local function Write(names, volume, at)
    local store = Store(true)
    if not store or #names == 0 then return end
    local p = Leader(names)
    local added = false
    for _, k in ipairs(names) do
        local e = store[k]
        if type(e) ~= "table" or type(e.at) ~= "number" or e.at <= at then
            if e == nil then added = true end
            store[k] = {v = volume, at = at, p = p}
        end
    end
    if added then Prune(store) end
end

--------------------------------------------------------------------------
-- seeing a change: the slider's calls
--------------------------------------------------------------------------

local ReadAfterLockdown

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

-- (a slider drag calls the setter at every step: one person's steps close
-- together are one change. When the game doesn't say whose, the menu tells
-- one person from the next: its slider passes the menu's own location at
-- every step, and each menu opened makes a new one - UnitPopupShared.lua,
-- UnitPopupCustomControls.lua)
local function NewChange(guid, loc)
    local t = Now()
    local same = last ~= nil and last.guid == guid and (guid ~= nil or last.loc == loc) and t - last.t < DRAG
    last = {guid = guid, loc = loc, t = t}
    return not same
end

local function OnSet(loc, volume)
    if applying or not Active() then return end
    volume = Plain(volume)
    if type(volume) ~= "number" then return end
    local guid, channelID = GuidOf(loc)
    local new = NewChange(guid, loc)
    if not guid then
        -- (the game doesn't say whose - a row drawn in the lockdown: what was
        -- set is noted, to know it as yours once someone is found at it)
        if new or #unseen == 0 then
            stats.unseen = stats.unseen + 1
            unseen[#unseen + 1] = {v = volume, at = Clock()}
            if #unseen > UNSEEN_MAX then table.remove(unseen, 1) end
        else
            unseen[#unseen].v, unseen[#unseen].at = volume, Clock()
        end
        -- (looked for once the lockdown is over - or in a moment, for a row
        -- drawn in it and moved after it)
        ReadAfterLockdown()
        return
    end
    if new then stats.saved = stats.saved + 1 end
    local at = Clock()
    Write(Names(guid, Hints(channelID)), volume, at)
    if Locked() then
        -- (no community list is read in the lockdown: the other names once it's over)
        waiting[guid] = {v = volume, at = at}
        ReadAfterLockdown()
    end
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

-- a change the game didn't say whose, newer than what is kept, that set
-- someone to this volume. (Never the slider's top: the game starts everyone
-- there, so who is at it can't be told from who was set to it.)
local function UnseenAt(volume, after)
    if math.abs(volume - TOP) < SAME then return end
    for i = #unseen, 1, -1 do
        local u = unseen[i]
        if u.at >= after and math.abs(u.v - volume) < SAME then return u end
    end
end

-- one member of a voice channel: their remembered volume, if it isn't set
local function ApplyFor(memberID, channelID, again)
    if not Active() then return end
    if Locked() or ns.IsSecret(memberID) or ns.IsSecret(channelID) then
        -- (secret: the lockdown, or its last moment - look once it's over)
        ReadAfterLockdown()
        return
    end
    local store = Store()
    -- (nothing kept, and no change waiting to be told whose: nothing to look up)
    if (not store or next(store) == nil) and #unseen == 0 then return end
    if memberID == nil or channelID == nil or not (C_VoiceChat and C_VoiceChat.GetMemberGUID) then return end
    if C_VoiceChat.IsMemberLocalPlayer then
        local ok, me = pcall(C_VoiceChat.IsMemberLocalPlayer, memberID, channelID)
        if ok and Plain(me) == true then return end
    end
    local okG, guid = pcall(C_VoiceChat.GetMemberGUID, memberID, channelID)
    guid = okG and Plain(guid) or nil
    if type(guid) ~= "string" or guid == "" then return end
    local clubId = ChannelClub(channelID)
    -- (a guild's or WoW community's members are characters, whose GUIDs
    -- last: their lists are never read for this)
    if clubId ~= nil and not IsBattleNetClub(clubId) then clubId = nil end
    local names = Names(guid, {clubId})
    if clubId ~= nil and not HasClub(names, clubId) and C_VoiceChat.GetMemberID then
        -- (the voice channel may name them by their character, the club by
        -- their Battle.net account, with nothing saying whose character it
        -- is: the game matches the two as its roster does,
        -- C_VoiceChat.GetMemberID)
        local book = ClubBook(clubId)
        for _, g in ipairs(book and book.list or {}) do
            local ok, id = pcall(C_VoiceChat.GetMemberID, channelID, g)
            if ok and Plain(id) ~= nil and id == memberID then
                local seen = {}
                for _, k in ipairs(names) do seen[k] = true end
                for _, k in ipairs(Names(g, {clubId})) do
                    if not seen[k] then names[#names + 1] = k end
                end
                break
            end
        end
    end
    local saved = Lookup(names)
    if (not saved and #unseen == 0) or not (PlayerLocation and PlayerLocation.CreateFromGUID) then return end
    local okL, loc = pcall(PlayerLocation.CreateFromGUID, PlayerLocation, guid)
    if not okL or type(loc) ~= "table" then return end
    local okV, now = pcall(C_VoiceChat.GetMemberVolume, loc)
    now = okV and Plain(now) or nil
    if saved and type(now) == "number" and math.abs(now - saved.v) < SAME then
        stats.same = stats.same + 1
        return
    end
    -- (a change of yours the game didn't say whose, made since, left them at
    -- just this volume: it was this one, and it is newer - kept, not undone;
    -- the first one for them too)
    local u = type(now) == "number" and UnseenAt(now, saved and saved.at or 0)
    if u then
        Write(names, now, u.at)
        if not u.taken then
            u.taken = true
            stats.adopted = stats.adopted + 1
        end
        return
    end
    if not saved then return end
    applying = true
    local ok = pcall(C_VoiceChat.SetMemberVolume, loc, saved.v)
    applying = false
    if ok then stats.applied = stats.applied + 1 end
    -- (once more in a moment: the game may set its own as they finish joining)
    if not again and not rechecks[guid] then
        rechecks[guid] = true
        C_Timer.After(RECHECK, ns.Guard("voicevolume", function()
            rechecks[guid] = nil
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

-- changes made in the lockdown: the names that couldn't be read then
local function FillIn()
    local list = waiting
    waiting = {}
    for guid, w in pairs(list) do Write(Names(guid, Hints()), w.v, w.at) end
end

ReadAfterLockdown = function()
    if lockPoll then return end
    lockPoll = C_Timer.NewTicker(LOCK_POLL, ns.Guard("voicevolume", function()
        -- (over - and no slider still being dragged: a person is looked for
        -- at the volume it ends at)
        if Locked() or (last ~= nil and Now() - last.t < DRAG) then return end
        if lockPoll then lockPoll:Cancel() end
        lockPoll = nil
        FillIn()
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
    elseif event == "CLUB_ADDED" or event == "CLUB_REMOVED" then
        bnClubs.at = nil
    elseif event == "CLUB_MEMBER_ADDED" or event == "CLUB_MEMBER_UPDATED" then
        -- (one member: read into the club's list there and then - in the
        -- lockdown, the whole list is read again after it)
        local clubId, memberId = ...
        clubId = Plain(clubId)
        local book = clubId ~= nil and clubs[tostring(clubId)]
        if book and (Locked() or not (C_Club and C_Club.GetMemberInfo) or not AddMember(book, clubId, memberId)) then
            book.dirty = true
        end
    elseif event == "CLUB_MEMBERS_UPDATED" or event == "CLUB_MEMBER_REMOVED" then
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
                            "CLUB_ADDED", "CLUB_REMOVED", "CLUB_MEMBERS_UPDATED", "CLUB_MEMBER_ADDED",
                            "CLUB_MEMBER_UPDATED", "CLUB_MEMBER_REMOVED"}) do
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

-- people kept: each name says whose it is (see Leader)
local function Count()
    local people, n = {}, 0
    for k, e in pairs(Store() or {}) do
        local who = type(e) == "table" and type(e.p) == "string" and e.p or k
        if not people[who] then
            people[who] = true
            n = n + 1
        end
    end
    return n
end

function M:Status()
    local n = Count()
    return ("(%s kept; this session %d change(s) of yours kept, %d set again%s%s)"):format(
               n == 1 and "1 person's volume" or ("%d people's volumes"):format(n),
               stats.saved, stats.applied,
               stats.unseen > 0 and ("; %d change(s) the game didn't say whose (in a dungeon or raid), %d of them kept after it"):format(
                   stats.unseen, stats.adopted) or "",
               M.hooked and "" or "; the game's volume slider could NOT be watched, so nothing new is kept")
end

function M:Command(arg)
    if arg == "forget" then
        if ns.db then ns.db.voiceVolumes = nil end
        waiting, unseen = {}, {}
        ns.Print("voicevolume: every remembered volume forgotten (the volumes set now stay until you change them)")
        return true
    end
    return false
end

ns.RegisterFeature("voicevolume",
    "Voice chat: remember the volume you set for each person (right-click them in voice) and set it again whenever they're in voice with you, next session too. |cFFFFCC00/pqol voicevolume forget|r forgets them all",
    M)
