-- Pace's Quality of Life - who's in a community voice channel, before you
-- join it
--
-- Forever's Chat Channels window (Blizzard_Channels, Mainline files on
-- camelot) shows a voice channel's members only while you are in it, and no
-- API says who is in a channel you never joined (every way of joining also
-- activates: ChannelFrame.lua TryJoinCommunityStreamChannel). Two sources
-- fill the gap:
--   * a channel you joined this session and then left with the headset
--     stays joined but inactive; the game keeps its members' isActive, and
--     we show that.
--   * everyone else: Pace's QoL users tell each other. Opening Chat
--     Channels on a community stream asks who's in its voice (Q). Those in
--     it answer (J); those who aren't say they're there (P, so a test can
--     tell "never arrived" from "not in voice"); joins and leaves are told
--     at once to whoever asked lately (J, L).
--
-- Who a roster row is: the club's own GUID for that member
-- (ChannelRoster.lua: SetMemberPlayerLocationFromGuid(memberInfo.guid)). In a
-- guild or a WoW (character) community that is the character's GUID; in a
-- Battle.net community it is the member's Battle.net account GUID, and the
-- row has no character at all. So an answer names the sender the way the
-- club does (C_Club.GetMemberInfoForSelf), and the asker also pins each
-- answer on the member it asked by that route. (1.0.0 answered with the
-- character's GUID, which never matched a Battle.net community's rows.)
--
-- How messages travel - invisible add-on messages, nothing in chat:
--   * a guild's own club: one question over GUILD, answered over GUILD.
--   * any other community: one question over GUILD (guildmates who are in
--     it) and one to the party or raid, then each online member the game
--     gives a way to: Battle.net game data to every WoW Forever game account
--     of a Battle.net friend, and in a WoW community a whisper to members of
--     your faction. Answers go back the way the question came.
--   * a Battle.net community member who is none of those (not a friend, not
--     in your guild or group) cannot be reached by an add-on at all.
-- A whisper waits for the game's "can whisper" check, but not for ever.
-- Nothing is sent during the game's chat lockdown, when values go secret;
-- a join or leave made in it goes out once it lifts.
-- A /reload keeps voice, and the people asking keep seeing you: the leave
-- goes out only at a real logout, and the reloaded UI takes over who asked
-- (PLAYER_LOGOUT comes for both, so ReloadUI tells them apart).
-- /pqol voice prints what was sent, heard and refused, without names.
--
-- The microphone goes on the member's roster row, where Blizzard's own
-- voice buttons sit while you are in the channel; ours hides as soon as
-- you join (Blizzard's take over).

local addonName, ns = ...

local M = {}
ns.Voice = M

local PREFIX = "PQoLVoice"
local MIC_ATLAS = "voicechat-icon-mic"
local HEARD_TTL = 200      -- an answer counts this long (seconds)
local WATCH_TTL = 200      -- we tell an asker about joins/leaves this long
local ASK_EVERY = 60       -- re-ask while the window stays on a stream
local ASK_AGAIN = 10       -- one follow-up this soon after the first question
local MAX_TARGETS = 60     -- questions per round, at most (the rest next round)
local REASK_GAP = 50       -- a target isn't asked again sooner than this
local SEND_GAP = 0.2       -- seconds between queued messages
local CHECK_WAIT = 4       -- a whisper check unanswered this long: send anyway
local CHECK_TRUST = 300    -- how long a whisper check's answer is kept
local CHECK_GIVE_UP = 3    -- this many checks unanswered, none ever: stop asking the game
local GUILD_J_GAP = 20     -- a guild stream's answer over GUILD at most this often
local REPLY_GAP = 10       -- one answer per asker, route and stream this often
local HERE_GAP = 10        -- "here, not in voice" to one asker at most this often
local LOCK_POLL = 5        -- after a voice change in the lockdown, look this often for its end
local RELOAD_WINDOW = 5    -- ReloadUI this soon before PLAYER_LOGOUT: a /reload
local HANDOFF_MAX = 120    -- a reload's saved askers are taken over if it took less than this
local GRACE = 10           -- after a /reload, voice not readable yet isn't "left" for this long
local LOG_SIZE = 12

local heard = {}           -- "club:stream" -> {guid = {}, member = {}}; entry {exp=, inVoice=, src=, at=}
local known = {}           -- "club|memberId" -> true: answered before (asked first)
local books = {}           -- club -> what the asker knows of its members (see M.Targets)
local reach = {}           -- club -> counts from the last look at who can be asked
local watchers = {}        -- key -> {to=, club=, stream=, asker=, exp=}
local replied = {}         -- key -> when an answer last went out
local deferred = {}        -- key -> true: an answer held back by its gap goes when the gap ends
local checks = {}          -- guid -> {ok=, exp=}: whisper checks answered
local pending = {}         -- guid -> {items = {...}}: messages waiting for a whisper check
local asked = {}           -- "club:stream" -> {target key -> when asked}
local icons = setmetatable({}, {__mode = "k"})
local hooked = setmetatable({}, {__mode = "k"})
local myVoice              -- the community stream we're active in, as last read and told
local askTicker, lockPoll, expiryAt
local againToken = 0
local checksAnswered, checksSilent = 0, 0
local stats = {sent = {}, failed = {}, recv = {}, echo = {},
               checks = {asked = 0, yes = 0, no = 0, silent = 0, skipped = 0}}
local log = {}

local function Now() return GetTime() end

local function Locked()
    if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown then
        local ok, locked = pcall(C_ChatInfo.InChatMessagingLockdown)
        return ok and locked and true or false
    end
    return false
end

local function Active() return ns.IsOn("voice") end
local function Sharing() return Active() and ns.db.voiceShare and true or false end
local function MyGUID() return UnitGUID and UnitGUID("player") end

-- a value we may keep and compare: nil when missing or secret
local function Plain(v)
    if v == nil or ns.IsSecret(v) then return nil end
    return v
end

local function Bump(t, k) t[k] = (t[k] or 0) + 1 end

local function Problem(text)
    stats.problem, stats.problemAt = text, Now()
end

-- a GUID as its kind and last four characters, for the readout
local function Short(guid)
    if type(guid) ~= "string" or guid == "" then return "-" end
    local kind = guid:match("^(%a+)%-")
    local letter = kind == "Player" and "P" or kind == "BNetAccount" and "B" or
                       (kind and kind:sub(1, 1)) or "?"
    return letter .. ".." .. guid:sub(-4)
end

local function Log(dir, path, msg, result)
    table.insert(log, 1, {at = Now(), dir = dir, path = path, msg = msg, result = result})
    if #log > LOG_SIZE then table.remove(log) end
end

local function StreamKey(club, stream) return tostring(club) .. ":" .. tostring(stream) end

-- a club id as the C_Club functions take it (messages carry it as text)
local function ClubArg(club) return tonumber(club) or club end

local function NameKey(name)
    if type(name) ~= "string" then return "" end
    return (name:lower():gsub("%s+", "-"))
end

local ONLINE = {}
do
    local p = Enum and Enum.ClubMemberPresence or {}
    ONLINE[p.Online or 1] = true
    ONLINE[p.Away or 4] = true
    ONLINE[p.Busy or 5] = true
end

local CODES = Enum and Enum.SendAddonMessageResult or {}
local SUCCESS = CODES.Success or 0
local THROTTLED = {[CODES.AddonMessageThrottle or 3] = true, [CODES.ChannelThrottle or 8] = true}

--------------------------------------------------------------------------
-- sending: a small queue, so a community of sixty is not sixty messages
-- in one frame
--------------------------------------------------------------------------

local function PathOf(to)
    if to.guild then return "GUILD" end
    if to.group then return to.group end
    if to.bn then return "BN" end
    return "WHISPER"
end

-- one message out now: "ok", "throttle", or what went wrong
local function SendNow(item)
    if Locked() then return "lockdown" end
    local to, msg = item.to, item.msg
    local ok, result
    if to.guild or to.group then
        ok, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, to.guild and "GUILD" or to.group)
    elseif to.bn then
        if not (C_BattleNet and C_BattleNet.SendGameData) then return "no Battle.net" end
        ok, result = pcall(C_BattleNet.SendGameData, to.bn, PREFIX, msg)
    elseif to.name then
        ok, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, "WHISPER", to.name)
    else
        return "no target"
    end
    if not ok then return "error", result end
    if result == nil or result == true or result == SUCCESS then return "ok" end
    if THROTTLED[result] then return "throttle" end
    return "code " .. tostring(result)
end

-- a question that did not go out may be asked again at once
local function Unstamp(item)
    local s = item.stamp
    if s and asked[s[1]] then asked[s[1]][s[2]] = nil end
end

local function Settle(item, outcome, err)
    local path, kind = PathOf(item.to), item.msg:sub(1, 1)
    if outcome == "ok" then
        Bump(stats.sent, path .. " " .. kind)
    else
        Bump(stats.failed, path .. " " .. outcome)
        Problem(("%s %s not sent: %s"):format(path, kind, err and tostring(err) or outcome))
        Unstamp(item)
    end
    Log("out", path, item.msg, outcome)
end

local queue, pumping, lastPump = {}, false, 0

-- (every step under pcall: one bad send can't stop the queue for good)
local function Pump()
    lastPump = Now()
    local item = queue[1]
    if not item then
        pumping = false
        return
    end
    local ok, outcome, err = pcall(SendNow, item)
    if ok and outcome == "throttle" then
        C_Timer.After(1, Pump)
        return
    end
    table.remove(queue, 1)
    if not ok then outcome, err = "error", outcome end
    pcall(Settle, item, outcome, err)
    C_Timer.After(SEND_GAP, Pump)
end

local function Enqueue(msg, to, stamp)
    local item = {msg = msg, to = to, stamp = stamp}
    if msg:sub(1, 1) == "Q" then
        if #queue >= 300 then
            Unstamp(item)
            return
        end
        table.insert(queue, item)
    else
        -- answers and join/leave news go ahead of any questions waiting
        local at = 1
        while queue[at] and queue[at].msg:sub(1, 1) ~= "Q" do at = at + 1 end
        table.insert(queue, at, item)
    end
    -- (a pump that has not run for a while is gone: start another)
    if not pumping or Now() - lastPump > 10 then
        pumping, lastPump = true, Now()
        C_Timer.After(0, Pump)
    end
end

-- straight out, no queue: at logout no timer runs again
local function SendDirect(msg, to)
    local item = {msg = msg, to = to}
    local ok, outcome, err = pcall(SendNow, item)
    if not ok then outcome, err = "error", outcome end
    pcall(Settle, item, outcome, err)
end

--------------------------------------------------------------------------
-- the game's "can whisper" check: asked before our own questions go to a
-- name (no "no player named" errors), but never waited on for ever - only
-- Blizzard's crafting orders use it, and they work without an answer
--------------------------------------------------------------------------

local function CanWhisper(status)
    local codes = Enum and Enum.ChatWhisperTargetStatus or {}
    return status == (codes.CanWhisper or 0) or status == (codes.CanWhisperGuild or 1)
end

local function Release(guid, send)
    local p = pending[guid]
    pending[guid] = nil
    if not p then return end
    for _, item in ipairs(p.items) do
        if not send then
            stats.checks.skipped = stats.checks.skipped + 1
        elseif item.msg:sub(1, 1) == "Q" and not M.asking then
            Unstamp(item) -- the window closed meanwhile
        else
            Enqueue(item.msg, item.to, item.stamp)
        end
    end
end

local function Send(msg, to, stamp)
    local check = C_ChatInfo and C_ChatInfo.RequestCanLocalWhisperTarget
    if not (to.name and to.guid and check) or (checksAnswered == 0 and checksSilent >= CHECK_GIVE_UP) then
        Enqueue(msg, to, stamp)
        return
    end
    local answer = checks[to.guid]
    if answer and answer.exp > Now() then
        if answer.ok then
            Enqueue(msg, to, stamp)
        else
            stats.checks.skipped = stats.checks.skipped + 1
        end
        return
    end
    local item = {msg = msg, to = to, stamp = stamp}
    local p = pending[to.guid]
    if p then
        if #p.items < 5 then table.insert(p.items, item) end
        return
    end
    -- (the message is waiting before the game is asked: an answer that
    -- comes inside the call still finds it)
    p = {items = {item}}
    local guid = to.guid
    pending[guid] = p
    stats.checks.asked = stats.checks.asked + 1
    C_Timer.After(CHECK_WAIT, ns.Guard("voice", function()
        if pending[guid] ~= p then return end
        checksSilent = checksSilent + 1
        stats.checks.silent = stats.checks.silent + 1
        Release(guid, true)
    end))
    pcall(check, guid)
end

local function OnWhisperCheck(guid, status)
    if guid == nil or ns.IsSecret(guid) or ns.IsSecret(status) then return end
    checksAnswered = checksAnswered + 1
    local ok = CanWhisper(status)
    checks[guid] = {ok = ok, exp = Now() + CHECK_TRUST}
    if pending[guid] then
        if ok then
            stats.checks.yes = stats.checks.yes + 1
        else
            stats.checks.no = stats.checks.no + 1
        end
    end
    Release(guid, ok)
end

--------------------------------------------------------------------------
-- who to ask: the club's online members, by every route the game gives
--------------------------------------------------------------------------

local function ClubType(clubId)
    local ok, info = pcall(C_Club.GetClubInfo, clubId)
    return ok and type(info) == "table" and Plain(info.clubType) or nil
end

local function IsGuildClub(clubId)
    return Enum and Enum.ClubType and ClubType(clubId) == Enum.ClubType.Guild or false
end

-- the GUID the club lists us under: in a Battle.net community that is our
-- Battle.net account's, which is what the other members' rows carry. Nil
-- while the club can't say (its data not loaded yet).
local function SelfGUID(clubId)
    if C_Club and C_Club.GetMemberInfoForSelf and clubId ~= nil then
        local ok, info = pcall(C_Club.GetMemberInfoForSelf, ClubArg(clubId))
        local guid = ok and type(info) == "table" and Plain(info.guid)
        if type(guid) == "string" and guid ~= "" then return guid end
    end
end

local function ClubGUID(clubId) return SelfGUID(clubId) or MyGUID() end

-- what our voice is told as - the club's GUID for us, and whether it is the
-- guild's own club - read again whenever the club can say (it may not have
-- been able to when we joined, or at login after a /reload)
local function Identity(v)
    local kind = ClubType(v.clubId)
    if kind ~= nil then v.guild = Enum and Enum.ClubType and kind == Enum.ClubType.Guild or false end
    v.guid = SelfGUID(v.clubId) or v.guid
end

-- our own character or our own Battle.net account (a message of ours
-- coming back over GUILD or the party)
local function IsMe(guid)
    if type(guid) ~= "string" or guid == "" then return false end
    if guid == MyGUID() then return true end
    if C_AccountInfo and C_AccountInfo.IsGUIDRelatedToLocalAccount then
        local ok, me = pcall(C_AccountInfo.IsGUIDRelatedToLocalAccount, guid)
        if ok and me == true then return true end
    end
    return false
end

local function MyFaction()
    if UnitFactionGroup then
        local ok, f = pcall(UnitFactionGroup, "player")
        if ok and type(f) == "string" then return f end
    end
end

local function MemberFaction(m)
    local f = Plain(m.faction)
    if f == nil or type(PLAYER_FACTION_GROUP) ~= "table" then return end
    return PLAYER_FACTION_GROUP[f]
end

-- the name to whisper a WoW community member by: the name the club gives
-- (what Blizzard's own Whisper uses), else the game's name for the GUID
local function WhisperName(m)
    local name = Plain(m.name)
    if type(name) == "string" and name ~= "" then return name end
    if GetPlayerInfoByGUID and m.guid then
        local ok, _, _, _, _, _, n, r = pcall(GetPlayerInfoByGUID, m.guid)
        if ok and type(n) == "string" and n ~= "" and not ns.IsSecret(n) then
            if type(r) == "string" and r ~= "" and not ns.IsSecret(r) and not n:find("-", 1, true) then
                return n .. "-" .. r
            end
            return n
        end
    end
end

-- every online WoW Forever game account of a Battle.net friend. The
-- account's own gameAccountInfo is only the focused one, and that can be
-- the Battle.net app; Blizzard's invite code walks them all the same way.
local function ForeverAccounts(account)
    local out, taken = {}, {}
    if account == nil or not C_BattleNet then return out end
    local function Take(g)
        if type(g) ~= "table" then return end
        local id = Plain(g.gameAccountID)
        if id == nil or taken[id] or g.isOnline == false then return end
        if BNET_CLIENT_WOW and g.clientProgram ~= BNET_CLIENT_WOW then return end
        local project = Plain(g.wowProjectID)
        if project and WOW_PROJECT_ID and project ~= WOW_PROJECT_ID then return end
        taken[id] = true
        out[#out + 1] = {id = id, guid = Plain(g.playerGuid)}
    end
    local index
    if BNGetFriendIndex then
        local ok, i = pcall(BNGetFriendIndex, account)
        if ok then index = Plain(i) end
    end
    if index and C_BattleNet.GetFriendNumGameAccounts and C_BattleNet.GetFriendGameAccountInfo then
        local ok, n = pcall(C_BattleNet.GetFriendNumGameAccounts, index)
        if ok and type(n) == "number" and not ns.IsSecret(n) then
            for j = 1, n do
                local okG, g = pcall(C_BattleNet.GetFriendGameAccountInfo, index, j)
                if okG then Take(g) end
            end
        end
    end
    if #out == 0 and C_BattleNet.GetAccountInfoByID then
        local ok, a = pcall(C_BattleNet.GetAccountInfoByID, account)
        if ok and type(a) == "table" then Take(a.gameAccountInfo) end
    end
    return out
end

-- The Battle.net account behind a Battle.net community member's GUID. The
-- club's member info may carry no account id (bnetAccountId is nilable);
-- Blizzard's own menus then read it from the GUID like this
-- (UnitPopupSharedUtil.GetBNetIDAccount).
local function AccountFromGUID(guid)
    if type(guid) ~= "string" or not (C_AccountInfo and C_AccountInfo.IsGUIDBattleNetAccountType and
                                          C_AccountInfo.GetIDFromBattleNetAccountGUID) then
        return
    end
    local ok, isBN = pcall(C_AccountInfo.IsGUIDBattleNetAccountType, guid)
    if not ok or ns.IsSecret(isBN) or isBN ~= true then return end
    local okID, id = pcall(C_AccountInfo.GetIDFromBattleNetAccountGUID, guid)
    id = okID and Plain(id) or nil
    if type(id) == "number" and id > 0 then return id end
end

local function GroupChannel()
    if LE_PARTY_CATEGORY_INSTANCE and IsInGroup and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
        return "INSTANCE_CHAT"
    end
    if IsInRaid and IsInRaid() then return "RAID" end
    if IsInGroup and IsInGroup() then return "PARTY" end
end

-- Who can be asked about a club's streams, and how. Also writes down what
-- the asker knows of the club's members - their GUIDs, Battle.net accounts
-- and the route each was asked by - so an answer finds its row whatever
-- GUID it carries.
function M.Targets(clubId)
    local club = tostring(clubId)
    local out = {}
    local book = {byGuid = {}, byAccount = {}, route = {}, guidOf = {}}
    local counts = {members = 0, online = 0, bn = 0, whisper = 0, faction = 0, none = 0, viaGuid = 0}
    books[club], reach[club] = book, counts
    local clubType = ClubType(clubId)
    counts.clubType = clubType
    local types = Enum and Enum.ClubType or {}
    local guildClub = clubType ~= nil and clubType == types.Guild
    local myFaction = MyFaction()
    local ok, list = pcall(C_Club.GetClubMembers, clubId)
    if ok and type(list) == "table" then
        for _, memberId in ipairs(list) do
            local okInfo, m = pcall(C_Club.GetMemberInfo, clubId, memberId)
            if okInfo and type(m) == "table" then
                counts.members = counts.members + 1
                local guid, account = Plain(m.guid), Plain(m.bnetAccountId)
                local viaGuid = false
                if account == nil and not m.isSelf then
                    account = AccountFromGUID(guid)
                    viaGuid = account ~= nil
                end
                if guid then
                    book.byGuid[guid] = memberId
                    book.guidOf[memberId] = guid
                end
                if account then book.byAccount[account] = memberId end
                local presence = Plain(m.presence)
                local online = not m.isSelf and presence and ONLINE[presence]
                if online then counts.online = counts.online + 1 end
                -- (a guild's own club: the one GUILD question below reaches them)
                if online and not guildClub then
                    local found = false
                    for _, g in ipairs(ForeverAccounts(account)) do
                        local key = "bn:" .. tostring(g.id)
                        book.route[key] = memberId
                        -- (a friend's character: an older Pace's QoL answers with it)
                        if g.guid and book.byGuid[g.guid] == nil then book.byGuid[g.guid] = memberId end
                        out[#out + 1] = {bn = g.id, key = key, memberId = memberId}
                        found = true
                    end
                    if found then
                        counts.bn = counts.bn + 1
                        if viaGuid then counts.viaGuid = counts.viaGuid + 1 end
                    end
                    if clubType ~= nil and clubType == types.Character then
                        local faction = MemberFaction(m)
                        if faction and myFaction and faction ~= myFaction then
                            counts.faction = counts.faction + 1
                        else
                            local name = WhisperName(m)
                            if name then
                                local key = "w:" .. NameKey(name)
                                book.route[key] = memberId
                                out[#out + 1] = {name = name, guid = guid, key = key, memberId = memberId}
                                counts.whisper = counts.whisper + 1
                                found = true
                            end
                        end
                    end
                    if not found then counts.none = counts.none + 1 end
                end
            end
        end
    end
    -- one question to a whole guild or group reaches the members in it
    if guildClub then
        table.insert(out, 1, {guild = true, key = "guild"})
        counts.guild = true
    else
        if IsInGuild and IsInGuild() then
            table.insert(out, 1, {guild = true, key = "guild"})
            counts.guild = true
        end
        local group = GroupChannel()
        if group then
            table.insert(out, 1, {group = group, key = "group:" .. group})
            counts.group = group
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

-- the row's member: its GUID (the club's GUID for that member, nil when the
-- club gives none) and its member id
local function RowIdentity(button)
    local guid, memberId
    local loc = button.GetMemberPlayerLocation and button:GetMemberPlayerLocation()
    if loc and loc.GetGUID then
        local ok, g = pcall(loc.GetGUID, loc)
        if ok and type(g) == "string" and not ns.IsSecret(g) then guid = g end
    end
    if button.GetMemberID then
        local ok, id = pcall(button.GetMemberID, button)
        if ok then memberId = Plain(id) end
    end
    return guid, memberId
end

-- Blizzard's own test (it knows our Battle.net account's GUID too)
local function IsLocalRow(button, guid)
    if button.IsLocalPlayer then
        local ok, me = pcall(button.IsLocalPlayer, button)
        if ok and me ~= nil and not ns.IsSecret(me) then return me and true or false end
    end
    return guid ~= nil and guid == MyGUID()
end

local function Lit(e, now) return e and e.inVoice and e.exp > now end

local function HeardFor(clubId, streamId, guid, memberId)
    local h = heard[StreamKey(clubId, streamId)]
    if not h then return false end
    local now = Now()
    return Lit(guid and h.guid[guid], now) or Lit(memberId ~= nil and h.member[memberId], now) or false
end

-- Blizzard greys a row whose member is offline (RosterButton.lua,
-- IsConnected): someone who crashed or lost connection sent no leave
local function Offline(button)
    if not button.IsConnected then return false end
    local ok, connected = pcall(button.IsConnected, button)
    if not ok or ns.IsSecret(connected) then return false end
    return connected == false
end

-- The selected club says this row's member is offline - not just a row
-- still showing another club's member: on a stream switch Blizzard refills
-- the rows a moment after the selection changes, and member ids are the
-- club's own.
local function ClubSaysOffline(clubId, memberId, guid)
    if memberId == nil or not (C_Club and C_Club.GetMemberInfo) then return false end
    local ok, m = pcall(C_Club.GetMemberInfo, clubId, memberId)
    if not ok or type(m) ~= "table" or Plain(m.guid) ~= guid then return false end
    local offline = Enum and Enum.ClubMemberPresence and Enum.ClubMemberPresence.Offline or 3
    return Plain(m.presence) == offline
end

-- What was heard from a member before they went offline is over: logging
-- back in is not being in voice. An answer that comes while the row is
-- grey stands (Battle.net's "Appear Offline": still in voice, answering).
local greySince = {}       -- "club|member" -> when the row was first seen offline
local function Forget(clubId, streamId, guid, memberId, since)
    local h = heard[StreamKey(clubId, streamId)]
    if not h then return end
    for _, slot in ipairs({{h.guid, guid}, {h.member, memberId}}) do
        local t, k = slot[1], slot[2]
        if k ~= nil and t[k] and (t[k].at or 0) < since then t[k] = nil end
    end
end

function M.Decorate(button)
    if not button then return end
    local show = false
    if Active() and not Locked() then
        local _, clubId, streamId = SelectedStream()
        local guid, memberId = RowIdentity(button)
        local channelActive = button.IsChannelActive and button:IsChannelActive()
        if clubId and (guid or memberId ~= nil) and not channelActive and not IsLocalRow(button, guid) then
            local key = tostring(clubId) .. "|" .. tostring(memberId or guid)
            if not Offline(button) then
                greySince[key] = nil
            elseif ClubSaysOffline(clubId, memberId, guid) then
                greySince[key] = greySince[key] or Now()
                Forget(clubId, streamId, guid, memberId, greySince[key])
            end
            local channelID = guid and InactiveVoiceChannel(clubId, streamId)
            show = (channelID and DirectlyInVoice(channelID, guid)) or
                       HeardFor(clubId, streamId, guid, memberId)
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

-- redraw once more when the first answer on screen runs out (a member who
-- stopped answering loses the microphone then, not a round later)
local function WatchExpiry()
    local _, clubId, streamId = SelectedStream()
    local h = clubId and heard[StreamKey(clubId, streamId)]
    if not h then return end
    local now, soonest = Now(), nil
    for _, t in ipairs({h.guid, h.member}) do
        for _, e in pairs(t) do
            if e.inVoice and e.exp > now and (not soonest or e.exp < soonest) then soonest = e.exp end
        end
    end
    if soonest and not (expiryAt and expiryAt > now and expiryAt <= soonest) then
        expiryAt = soonest
        C_Timer.After(soonest - now + 0.1, ns.Guard("voice", function()
            if expiryAt == soonest then expiryAt = nil end
            M.Refresh()
        end))
    end
end

function M.Refresh()
    local roster = ChannelFrame and ChannelFrame.ChannelRoster
    local box = roster and roster.ScrollBox
    if not (box and ChannelFrame:IsShown()) then return end
    for _, frame in box:EnumerateFrames() do M.Decorate(frame) end
    WatchExpiry()
end

local function HookRow(frame)
    if not frame or hooked[frame] then return end
    hooked[frame] = true
    if frame.Update then
        hooksecurefunc(frame, "Update", ns.Guard("voice row", M.Decorate))
    end
end

--------------------------------------------------------------------------
-- asking
--------------------------------------------------------------------------

-- Ask the selected stream's members who's in its voice. A target isn't
-- asked twice within REASK_GAP, and a round asks MAX_TARGETS at most: the
-- guild and group first, then members who answered before, then whoever
-- has waited longest - so a big community is covered round by round and
-- the people who run Pace's QoL are asked every time.
function M.Ask()
    if not Active() or Locked() then return end
    local _, clubId, streamId = SelectedStream()
    if not clubId then return end
    local club = tostring(clubId)
    local sk = StreamKey(clubId, streamId)
    local msg = ("Q:%s:%s:%s"):format(club, tostring(streamId), MyGUID() or "")
    local targets = M.Targets(clubId)
    if #targets == 0 then return end
    local now = Now()
    local done = asked[sk] or {}
    asked[sk] = done
    local candidates = {}
    for i, t in ipairs(targets) do
        local last = done[t.key]
        if not (last and now - last < REASK_GAP) then
            t.order, t.last = i, last or 0
            t.prio = (t.guild or t.group) and 0 or
                         (t.memberId ~= nil and known[club .. "|" .. tostring(t.memberId)]) and 1 or 2
            candidates[#candidates + 1] = t
        end
    end
    table.sort(candidates, function(a, b)
        if a.prio ~= b.prio then return a.prio < b.prio end
        if a.last ~= b.last then return a.last < b.last end
        return a.order < b.order
    end)
    for i = 1, math.min(#candidates, MAX_TARGETS) do
        local t = candidates[i]
        done[t.key] = now
        Send(msg, t, {sk, t.key})
    end
end

-- drop questions not yet sent (window closed, feature off); they may be
-- asked again at once next time
local function DropQuestions()
    for i = #queue, 1, -1 do
        local item = queue[i]
        if item.msg:sub(1, 1) == "Q" then
            Unstamp(item)
            table.remove(queue, i)
        end
    end
    for _, p in pairs(pending) do
        for i = #p.items, 1, -1 do
            if p.items[i].msg:sub(1, 1) == "Q" then
                Unstamp(p.items[i])
                table.remove(p.items, i)
            end
        end
    end
end

--------------------------------------------------------------------------
-- our own voice: read from the game, not remembered
--------------------------------------------------------------------------

-- the community stream the game says we're active in now (nil when none),
-- and the channel type of any other voice channel we're in
local function GameVoice()
    if not (C_VoiceChat and C_VoiceChat.GetActiveChannelID and C_VoiceChat.GetChannel) then return end
    local ok, id = pcall(C_VoiceChat.GetActiveChannelID)
    if not ok or id == nil or ns.IsSecret(id) then return end
    local okC, channel = pcall(C_VoiceChat.GetChannel, id)
    if not okC or type(channel) ~= "table" then return nil, "?" end
    local communities = Enum and Enum.ChatChannelType and Enum.ChatChannelType.Communities or 4
    local kind = Plain(channel.channelType)
    local clubId, streamId = Plain(channel.clubId), Plain(channel.streamId)
    if kind ~= communities or clubId == nil or streamId == nil then return nil, kind end
    return {channelID = id, clubId = clubId, club = tostring(clubId), stream = tostring(streamId)}
end

-- J or L about one stream: over GUILD for the guild's own stream, and to
-- everyone who asked about it lately
local function Announce(kind, v, direct)
    if not v then return end
    Identity(v)
    local msg = ("%s:%s:%s:%s"):format(kind, v.club, v.stream, v.guid or MyGUID() or "")
    local send = direct and SendDirect or Enqueue
    if v.guild then send(msg, {guild = true}) end
    local now = Now()
    for key, w in pairs(watchers) do
        if w.exp < now then
            watchers[key] = nil
        elseif w.club == v.club and w.stream == v.stream then
            send(msg, w.to)
        end
    end
end

-- in the lockdown nothing can be told: look for its end, then read again
-- (a leave made in a dungeon is still news once out of it)
local function ReadAfterLockdown()
    if lockPoll then return end
    lockPoll = C_Timer.NewTicker(LOCK_POLL, ns.Guard("voice", function()
        if Locked() then return end
        if lockPoll then lockPoll:Cancel() end
        lockPoll = nil
        M.ReadVoice()
    end))
end

-- read our voice channel from the game; a change is told to whoever needs
-- to know (a stream switch says L for the old one first). myVoice is what
-- they were last told, so a change the lockdown kept us from telling is
-- told after it.
function M.ReadVoice()
    if Locked() then
        ReadAfterLockdown()
        return
    end
    local now, other = GameVoice()
    M.otherVoice = other
    local old = myVoice
    -- (just reloaded: the game may not report the channel yet)
    if now == nil and old and M.voiceGrace and Now() < M.voiceGrace then return end
    M.voiceGrace = nil
    if old and now and old.club == now.club and old.stream == now.stream then
        Identity(old)
        return
    end
    if now then
        now.guild = IsGuildClub(now.clubId)
        now.guid = SelfGUID(now.clubId)
    end
    myVoice = now
    if Sharing() then
        if old then Announce("L", old) end
        if now then Announce("J", now) end
    end
end

--------------------------------------------------------------------------
-- answering, and hearing answers
--------------------------------------------------------------------------

-- where an answer to a question goes: back the way it came. A Battle.net
-- sender the game does not know is reached through the character that
-- asked, if that is a friend's.
local function ReplyRoute(replyTo, askerGuid)
    if replyTo.bn then
        if C_BattleNet and C_BattleNet.GetGameAccountInfoByID then
            local ok, g = pcall(C_BattleNet.GetGameAccountInfoByID, replyTo.bn)
            if ok and type(g) == "table" then return replyTo end
        end
        if askerGuid and C_BattleNet and C_BattleNet.GetGameAccountInfoByGUID then
            local ok, g = pcall(C_BattleNet.GetGameAccountInfoByGUID, askerGuid)
            local id = ok and type(g) == "table" and Plain(g.gameAccountID)
            if id then return {bn = id, key = "bn:" .. tostring(id)} end
        end
        return replyTo
    end
    -- (they just reached us: no whisper check for the way back)
    return {name = replyTo.name, key = replyTo.key}
end

local replyCount = 0
local function Answer(kind, club, stream, to, gapKey, gap, again)
    local now = Now()
    local last = replied[gapKey]
    if last and now - last < gap then
        -- asked again inside the gap (by someone who reloaded, or a
        -- guildmate who missed the last answer over GUILD): answer once
        -- more as the gap ends, not a round later. (Not when the answer
        -- went a moment ago: that is the same round's question by another
        -- route - GUILD and party - and it has the answer.)
        if again and not deferred[gapKey] and now - last >= 2 then
            deferred[gapKey] = true
            C_Timer.After(gap - (now - last) + 0.1, ns.Guard("voice", function()
                deferred[gapKey] = nil
                again()
            end))
        end
        return
    end
    replied[gapKey] = now
    replyCount = replyCount + 1
    if replyCount % 50 == 0 then
        for k, t in pairs(replied) do
            if now - t > 120 then replied[k] = nil end
        end
    end
    Enqueue(("%s:%s:%s:%s"):format(kind, club, stream, ClubGUID(club) or ""), to)
end

local function OnQuestion(club, stream, askerGuid, path, replyTo)
    if not Sharing() or Locked() then return end
    M.ReadVoice() -- what the game says now, not what we last heard
    local inIt = myVoice and myVoice.club == club and myVoice.stream == stream
    -- (the same question once more, for an answer its gap held back)
    local function again() OnQuestion(club, stream, askerGuid, path, replyTo) end
    if path == "GUILD" and IsGuildClub(ClubArg(club)) then
        -- the guild's own stream: one answer over GUILD serves every
        -- guildmate looking, and joins and leaves go over GUILD anyway
        if inIt then Answer("J", club, stream, {guild = true}, "guild|" .. club .. ":" .. stream, GUILD_J_GAP, again) end
        return
    end
    local to = ReplyRoute(replyTo, askerGuid)
    -- remember the asker for a while, so a join or leave reaches them at once
    watchers[to.key .. "|" .. club .. ":" .. stream] = {to = to, club = club, stream = stream, asker = askerGuid,
                                                         exp = Now() + WATCH_TTL}
    local who = (to.bn and "bn" or "w") .. "|" .. (askerGuid or to.key) .. "|" .. club .. ":" .. stream
    if inIt then
        Answer("J", club, stream, to, who .. "|J", REPLY_GAP, again)
    elseif path == "BN" or path == "WHISPER" then
        -- (a question to the whole guild or group is not answered by
        -- everyone who isn't in that voice)
        Answer("P", club, stream, to, who .. "|P", HERE_GAP, again)
    end
end

-- which member of the club an answer is from: by the GUID it carries, by
-- the route we asked that member by, or by the Battle.net account behind a
-- friend's character (an older Pace's QoL answers with the character)
local function Resolve(club, guid, replyTo)
    local book = books[club]
    if not book and C_Club then
        pcall(M.Targets, ClubArg(club))
        book = books[club]
    end
    if not book then return end
    if guid and book.byGuid[guid] ~= nil then return book.byGuid[guid] end
    if replyTo and replyTo.key then
        local id = book.route[replyTo.key]
        if id == nil then
            -- (a sender with a realm after the name we whispered)
            local short = replyTo.key:match("^(w:.+)%-[^%-]+$")
            if short then id = book.route[short] end
        end
        if id ~= nil then return id end
    end
    if guid and C_BattleNet and C_BattleNet.GetAccountInfoByGUID then
        local ok, a = pcall(C_BattleNet.GetAccountInfoByGUID, guid)
        local account = ok and type(a) == "table" and Plain(a.bnetAccountID)
        if account and book.byAccount[account] ~= nil then return book.byAccount[account] end
    end
end

-- the client (character) a message came from, as far as its route says:
-- a whisper, GUILD or party sender's name, or the character on the
-- Battle.net game account that sent it; nil when the game can't say
local function ClientOf(src)
    if type(src) ~= "string" then return end
    local name = src:match("^w:(.+)$")
    if name then return name end
    local id = tonumber(src:match("^bn:(%d+)$"))
    if id and C_BattleNet and C_BattleNet.GetGameAccountInfoByID then
        local ok, g = pcall(C_BattleNet.GetGameAccountInfoByID, id)
        local n = ok and type(g) == "table" and g.characterName
        if type(n) == "string" and n ~= "" and not ns.IsSecret(n) then return NameKey(n) end
    end
end

-- (a sender's name comes with its realm, a game account's character without)
local function SameClient(a, b)
    if not (a and b) then return false end
    return a == b or a:sub(1, #b + 1) == b .. "-" or b:sub(1, #a + 1) == a .. "-"
end

-- One Battle.net account can run two Forever clients, one in voice and one
-- not: both are the same club member, with the same GUID. An "in voice"
-- stands against "not in voice" (P or L) from the account's other client;
-- only the client that said it, or time, takes it back. The same client
-- may answer by more than one route (Battle.net game data, a whisper):
-- the same character, or the same name behind the route, is the same
-- client. (Telling them apart by route alone kept a 1.0.0 friend's real
-- leave from clearing his microphone.)
local function Holds(e, src, guid, now)
    if not (e and e.inVoice and e.exp > now and e.src ~= nil and src ~= nil and e.src ~= src) then return false end
    if guid and e.guid == guid and guid:find("^Player%-") then return false end
    return not SameClient(e.client, ClientOf(src))
end

local function OnAnswer(kind, club, stream, guid, replyTo)
    local memberId = Resolve(club, guid, replyTo)
    local sk = StreamKey(club, stream)
    local h = heard[sk]
    if not h then
        h = {guid = {}, member = {}}
        heard[sk] = h
    end
    local now, src = Now(), replyTo and replyTo.key
    if kind == "L" then
        local book = books[club]
        local g = memberId ~= nil and book and book.guidOf[memberId]
        for _, slot in ipairs({{h.guid, guid}, {h.member, memberId}, {h.guid, g}}) do
            local t, k = slot[1], slot[2]
            if k and t[k] and not Holds(t[k], src, guid, now) then t[k] = nil end
        end
    else
        local entry = {exp = now + HEARD_TTL, inVoice = kind == "J", src = src, at = now, guid = guid,
                       client = ClientOf(src)}
        if guid and not (kind == "P" and Holds(h.guid[guid], src, guid, now)) then h.guid[guid] = entry end
        if memberId ~= nil then
            if not (kind == "P" and Holds(h.member[memberId], src, guid, now)) then h.member[memberId] = entry end
            known[club .. "|" .. tostring(memberId)] = true
        end
    end
    M.Refresh()
end

local GROUP = {PARTY = true, RAID = true, INSTANCE_CHAT = true}

local function OnAddonMessage(event, prefix, text, channel, sender)
    if prefix ~= PREFIX or type(text) ~= "string" or ns.IsSecret(text) or
        sender == nil or ns.IsSecret(sender) then
        return
    end
    if not Active() or Locked() then return end
    local path, replyTo
    if event == "BN_CHAT_MSG_ADDON" then
        -- (the sender's game account id)
        path, replyTo = "BN", {bn = sender, key = "bn:" .. tostring(sender)}
    else
        path = channel == "GUILD" and "GUILD" or GROUP[channel] and channel or "WHISPER"
        replyTo = {name = sender, key = "w:" .. NameKey(sender)}
    end
    local kind, club, stream, guid = text:match("^(%a):([^:]*):([^:]*):([^:]*)")
    if not kind then return end
    stats.lastIn = Now()
    if guid == "" then guid = nil end
    if guid and IsMe(guid) then
        Bump(stats.echo, path) -- our own GUILD or party message coming back
        return
    end
    Bump(stats.recv, path .. " " .. kind)
    Log("in", path, text, "")
    if kind == "Q" then
        OnQuestion(club, stream, guid, path, replyTo)
    elseif kind == "J" or kind == "L" or kind == "P" then
        OnAnswer(kind, club, stream, guid, replyTo)
    end
end

--------------------------------------------------------------------------

local function StartAsking()
    if askTicker then askTicker:Cancel() end
    askTicker = nil
    againToken = againToken + 1
    M.Refresh()
    if not Active() then
        M.asking = false
        return
    end
    M.asking = true
    M.Ask()
    -- once more shortly (questions that could not go, a member list that
    -- came late), then every minute while the window stays on the stream
    local token = againToken
    C_Timer.After(ASK_AGAIN, ns.Guard("voice ask", function()
        if token == againToken and M.asking then M.Ask() end
    end))
    askTicker = C_Timer.NewTicker(ASK_EVERY, ns.Guard("voice ask", function()
        M.Ask()
        M.Refresh() -- (and answers that ran out lose their microphone)
    end))
end

local function StopAsking()
    if askTicker then askTicker:Cancel() end
    askTicker = nil
    againToken = againToken + 1
    M.asking = false
    DropQuestions()
end

-- the community's members (and who's online) load after the stream is
-- picked: ask the ones not asked yet once they're in
local reaskArmed = false
local function OnClubMembers(clubId)
    if not Active() or reaskArmed or not M.asking or not (ChannelFrame and ChannelFrame:IsShown()) then return end
    local _, selClub = SelectedStream()
    if not selClub or ns.IsSecret(clubId) or tostring(clubId) ~= tostring(selClub) then return end
    reaskArmed = true
    local token = againToken
    C_Timer.After(2, function()
        reaskArmed = false
        -- (not if the window closed meanwhile: closing dropped those questions)
        if token == againToken and M.asking then ns.SafeCall("voice ask", M.Ask) end
    end)
end

local function SetupChannelFrame()
    if M.hooked then return end
    local roster = ChannelFrame and ChannelFrame.ChannelRoster
    local box = roster and roster.ScrollBox
    if not box then return end
    M.hooked = true
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
    ChannelFrame:HookScript("OnHide", ns.Guard("voice ask", StopAsking))
end

--------------------------------------------------------------------------
-- logout and /reload
--------------------------------------------------------------------------

-- PLAYER_LOGOUT comes for a /reload as well as a logout, and doesn't say
-- which; ReloadUI (what /reload, the add-on list and Blizzard's dialogs
-- call) tells them apart. A logout ends voice: the people asking hear the
-- leave there and then (no timer runs after this event). A reload keeps
-- it: nobody is told anything, and the reloaded UI takes over who asked.
-- (a reload that switches the add-on off - the add-on list, /disableaddons,
-- the "too many errors" dialog - ends our part as a logout does: the
-- people asking would hear nothing from us again)
local function LoadsAgain()
    if not (C_AddOns and C_AddOns.GetAddOnEnableState) then return true end
    -- (Blizzard's add-on list asks with the character's GUID)
    local ok, state = pcall(C_AddOns.GetAddOnEnableState, addonName, MyGUID())
    if not ok or type(state) ~= "number" or ns.IsSecret(state) then return true end
    return state > 0 -- Enum.AddOnEnableState.None = 0
end

function M.Logout()
    local reloading = M.reloadAt ~= nil and Now() - M.reloadAt < RELOAD_WINDOW and LoadsAgain()
    local saidL = false
    if myVoice and Sharing() and not Locked() and not reloading then
        Announce("L", myVoice, true)
        saidL = true
    end
    if not ns.db then return end
    local list, now = {}, Now()
    for key, w in pairs(watchers) do
        if w.exp > now and #list < 100 then
            list[#list + 1] = {key = key, to = w.to, club = w.club, stream = w.stream, asker = w.asker,
                               left = w.exp - now}
        end
    end
    local v = myVoice
    ns.db.voiceHandoff = {char = MyGUID(), at = time and time() or nil, clock = now, saidL = saidL,
                          voice = v and {club = v.club, stream = v.stream, guid = v.guid, guild = v.guild,
                                          channelID = v.channelID} or nil,
                          watchers = list}
end

-- after a /reload: the people who asked, and what they were last told
local function TakeHandoff()
    local h = ns.db and ns.db.voiceHandoff
    if ns.db then ns.db.voiceHandoff = nil end
    if type(h) ~= "table" or h.char ~= MyGUID() then return end
    local elapsed
    if h.at and time then
        elapsed = time() - h.at
    else
        elapsed = Now() - (tonumber(h.clock) or -1e9)
    end
    if type(elapsed) ~= "number" or elapsed < 0 or elapsed > HANDOFF_MAX then return end
    local now = Now()
    for _, w in ipairs(type(h.watchers) == "table" and h.watchers or {}) do
        local to, left = w.to, (tonumber(w.left) or 0) - elapsed
        if left > 0 and type(w.key) == "string" and type(to) == "table" and type(to.key) == "string" and
            (type(to.bn) == "number" or type(to.name) == "string") then
            watchers[w.key] = {to = to, club = w.club, stream = w.stream, asker = w.asker, exp = now + left}
        end
    end
    local v = h.voice
    if type(v) ~= "table" or type(v.club) ~= "string" or type(v.stream) ~= "string" then return end
    if not h.saidL then
        -- they still have us in voice: only a change since then is news
        myVoice = {club = v.club, stream = v.stream, clubId = ClubArg(v.club), guid = v.guid, guild = v.guild,
                   channelID = v.channelID}
        M.voiceGrace = now + GRACE
    end
    -- (and once more when the game has had time to report voice: after a
    -- reload taken for a logout, that is when they hear we're still in)
    C_Timer.After(GRACE + 0.5, ns.Guard("voice", M.ReadVoice))
end

local VOICE_EVENTS = {
    VOICE_CHAT_CHANNEL_ACTIVATED = true, VOICE_CHAT_CHANNEL_DEACTIVATED = true,
    VOICE_CHAT_CHANNEL_REMOVED = true, VOICE_CHAT_CHANNEL_JOINED = true,
    VOICE_CHAT_LOGIN = true, VOICE_CHAT_LOGOUT = true,
}

function M:Init()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        local ok, result = pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
        M.prefixResult = ok and result or "error"
    end
    local f = CreateFrame("Frame")
    for _, event in ipairs({"CHAT_MSG_ADDON", "BN_CHAT_MSG_ADDON",
                            "CAN_LOCAL_WHISPER_TARGET_RESPONSE",
                            "VOICE_CHAT_CHANNEL_ACTIVATED", "VOICE_CHAT_CHANNEL_DEACTIVATED",
                            "VOICE_CHAT_CHANNEL_REMOVED", "VOICE_CHAT_CHANNEL_JOINED",
                            "VOICE_CHAT_LOGIN", "VOICE_CHAT_LOGOUT", "PLAYER_LOGOUT",
                            "VOICE_CHAT_CHANNEL_MEMBER_ADDED",
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
        elseif event == "PLAYER_LOGOUT" then
            M.Logout()
        else
            if VOICE_EVENTS[event] then
                -- (our channel going inactive is the game reporting now: no
                -- grace after a reload for that)
                local id = ...
                if M.voiceGrace and (event == "VOICE_CHAT_CHANNEL_DEACTIVATED" or event == "VOICE_CHAT_CHANNEL_REMOVED") and
                    not ns.IsSecret(id) and (myVoice == nil or myVoice.channelID == nil or id == myVoice.channelID) then
                    M.voiceGrace = nil
                end
                M.ReadVoice()
                -- and once more a moment later, should the game update
                -- after its own event
                C_Timer.After(1, ns.Guard("voice", M.ReadVoice))
            end
            M.Refresh()
        end
    end))
    M.eventFrame = f
    if ChannelFrame and ChannelFrame.ChannelRoster then ns.SafeCall("voice", SetupChannelFrame) end
    ns.OnAddOnLoaded("Blizzard_Channels", function() ns.SafeCall("voice", SetupChannelFrame) end)
    -- (a /reload goes through ReloadUI and C_UI.Reload, a logout through
    -- neither: see M.Logout. C_UI.Reload as well, for the reloads that
    -- call it directly or hold an older ReloadUI)
    local function Reloading() M.reloadAt = Now() end
    if type(ReloadUI) == "function" then
        pcall(hooksecurefunc, "ReloadUI", ns.Guard("voice", Reloading))
    end
    if C_UI and type(C_UI.Reload) == "function" then
        pcall(hooksecurefunc, C_UI, "Reload", ns.Guard("voice", Reloading))
    end
    ns.SafeCall("voice", TakeHandoff)
    -- already in a community's voice (a /reload doesn't end it): no event
    -- comes for that, so read it now
    if Active() then M.ReadVoice() end
end

function M:Apply(on)
    if on then
        M.wasOn = true
        if ChannelFrame and ChannelFrame.IsShown and ChannelFrame:IsShown() then StartAsking() end
    else
        -- the people who asked hear we're gone rather than wait it out
        if M.wasOn and myVoice and ns.db.voiceShare and not Locked() then Announce("L", myVoice) end
        M.wasOn = false
        StopAsking()
    end
    M.Refresh()
end

-- the share box was switched: say so to the people asking right now
function ns.VoiceShareChanged()
    if not Active() or Locked() then return end
    M.ReadVoice()
    if myVoice then Announce(ns.db.voiceShare and "J" or "L", myVoice) end
end

--------------------------------------------------------------------------
-- /pqol status, /pqol voice, /pqol voice log
--------------------------------------------------------------------------

-- people heard from about one stream: in voice, and here but not in it
local function Tally(h, now)
    local inVoice, here, seen = 0, 0, {}
    for _, t in ipairs({h.guid, h.member}) do
        for _, e in pairs(t) do
            if not seen[e] and e.exp > now then
                seen[e] = true
                if e.inVoice then inVoice = inVoice + 1 else here = here + 1 end
            end
        end
    end
    return inVoice, here
end

function M:Status()
    local now, inVoice, here = Now(), 0, 0
    for _, h in pairs(heard) do
        local a, b = Tally(h, now)
        inVoice, here = inVoice + a, here + b
    end
    return ("(%d in voice heard from other Pace's QoL users, %d more not in voice; sharing %s; /pqol voice for details)"):format(
               inVoice, here, ns.db.voiceShare and "on" or "off")
end

local CLUB_KIND = {[0] = "Battle.net community", [1] = "WoW community", [2] = "guild", [3] = "other club"}

local function Counts(t)
    local parts = {}
    for k, n in pairs(t) do parts[#parts + 1] = k .. " " .. n end
    table.sort(parts)
    return #parts > 0 and table.concat(parts, ", ") or "none"
end

local function PrefixState()
    if C_ChatInfo and C_ChatInfo.IsAddonMessagePrefixRegistered then
        local ok, yes = pcall(C_ChatInfo.IsAddonMessagePrefixRegistered, PREFIX)
        if ok then return yes and "on" or ("NOT registered (" .. tostring(M.prefixResult) .. ")") end
    end
    return "?"
end

local function RowsOnScreen()
    local r = {n = 0, B = 0, P = 0, none = 0, lit = 0, own = false}
    local box = ChannelFrame and ChannelFrame.ChannelRoster and ChannelFrame.ChannelRoster.ScrollBox
    if not (box and box.EnumerateFrames) then return r end
    for _, frame in box:EnumerateFrames() do
        r.n = r.n + 1
        local guid = RowIdentity(frame)
        local letter = Short(guid):sub(1, 1)
        if letter == "B" then
            r.B = r.B + 1
        elseif letter == "P" then
            r.P = r.P + 1
        else
            r.none = r.none + 1
        end
        if IsLocalRow(frame, guid) then r.own = true end
        local icon = icons[frame]
        if icon and icon.IsShown and icon:IsShown() then r.lit = r.lit + 1 end
    end
    return r
end

-- the people told about our voice as it changes: those who asked lately
-- about the stream we're in, each once however many ways they asked
local function Telling()
    local v = myVoice
    if not v then return 0 end
    local n, seen, now = 0, {}, Now()
    for _, w in pairs(watchers) do
        local who = w.asker or (w.to and w.to.key)
        if w.exp >= now and w.club == v.club and w.stream == v.stream and who and not seen[who] then
            seen[who] = true
            n = n + 1
        end
    end
    return n
end

-- Everything one in-game test needs to say where a microphone was lost:
-- run it on both sides (the one looking, with Chat Channels on the stream,
-- and the one in voice). No names, BattleTags or community names: people
-- show as a GUID's kind and last four characters (P..3F2A a character,
-- B..9C01 a Battle.net account).
function M.Report()
    local function Line(fmt, ...) print("  " .. fmt:format(...)) end
    local open = ChannelFrame and ChannelFrame.IsShown and ChannelFrame:IsShown()
    ns.Print("voice v%s: %s, sharing %s, chat lockdown %s, messages %s, Chat Channels %s",
             ns.VERSION, Active() and "on" or "OFF", ns.db.voiceShare and "on" or "OFF",
             Locked() and "YES (nothing is sent or shown)" or "no", PrefixState(),
             M.hooked and (open and "hooked, open" or "hooked, closed") or "NOT hooked")
    local game, other = GameVoice()
    local later = Locked() and " (the add-on tells the others once the lockdown ends)"
    if game then
        local missed = not (myVoice and myVoice.club == game.club and myVoice.stream == game.stream)
        Line("me: in voice in club %s stream %s%s; that club knows me as %s, my character is %s",
             game.club, game.stream, missed and (later or " (the add-on had not noticed: it has now)") or "",
             Short(ClubGUID(game.clubId)), Short(MyGUID()))
    else
        local grace = M.voiceGrace and Now() < M.voiceGrace and " (just reloaded: it looks again in a few seconds)"
        local note = myVoice and (later or grace or " (the add-on thought I was: fixed)") or ""
        if other ~= nil then
            Line("me: in a voice channel of type %s - only a community stream's voice is shared%s", tostring(other), note)
        else
            Line("me: not in voice%s", note)
        end
    end
    M.ReadVoice() -- (what the next lines count is then up to date)
    local _, clubId, streamId = SelectedStream()
    local rows
    if clubId then
        local club = tostring(clubId)
        pcall(M.Targets, clubId) -- fresh counts; sends nothing
        local c = reach[club] or {}
        rows = RowsOnScreen()
        Line("looking at: %s %s, stream %s; %d members, %d online; rows on screen %d (Battle.net account %d, character %d, none %d)%s",
             CLUB_KIND[c.clubType] or ("club type " .. tostring(c.clubType)), club, tostring(streamId),
             c.members or 0, c.online or 0, rows.n, rows.B, rows.P, rows.none,
             rows.n > 0 and not rows.own and "; my own row is not among them" or "")
        Line("can ask: guild %s, group %s, Battle.net friends on Forever %d, by whisper %d, other faction %d, no way to reach %d%s",
             c.guild and "yes" or "no", c.group or "no", c.bn or 0, c.whisper or 0, c.faction or 0, c.none or 0,
             (c.viaGuid or 0) > 0 and ("; for %d of those friends the community gave no account, read from the GUID"):format(c.viaGuid) or "")
    else
        Line("looking at: no community stream selected in Chat Channels")
    end
    Line("sent: %s | not sent: %s", Counts(stats.sent), Counts(stats.failed))
    local ch = stats.checks
    Line("whisper checks: asked %d, yes %d, no %d, no answer %d, skipped %d",
         ch.asked, ch.yes, ch.no, ch.silent, ch.skipped)
    Line("received: %s | my own coming back: %s | last %s", Counts(stats.recv), Counts(stats.echo),
         stats.lastIn and (math.floor(Now() - stats.lastIn) .. "s ago") or "never")
    if clubId then
        local h = heard[StreamKey(clubId, streamId)]
        local inVoice, here = 0, 0
        if h then inVoice, here = Tally(h, Now()) end
        Line("heard about this stream: %d in voice (%d microphones on screen), %d with the add-on but not in voice",
             inVoice, rows and rows.lit or 0, here)
    end
    Line("telling %d asker(s) about my voice%s; last problem: %s", Telling(),
         myVoice and myVoice.guild and " (and the guild, over GUILD)" or "",
         stats.problem and ("%s (%ds ago)"):format(stats.problem, math.floor(Now() - stats.problemAt)) or "none")
end

function M.ReportLog()
    ns.Print("voice: the last %d messages, newest first (age, in/out, route, kind, club:stream, GUID, result)", #log)
    local now = Now()
    for _, e in ipairs(log) do
        local kind, club, stream, guid = e.msg:match("^(%a):([^:]*):([^:]*):([^:]*)")
        print(("  %ds %s %s %s %s:%s %s %s"):format(math.floor(now - e.at), e.dir, e.path, kind or "?",
                                                   club or "?", stream or "?", Short(guid), e.result or ""))
    end
end

-- /pqol voice [log]
function M:Command(arg)
    if arg == nil or arg == "" or arg == "status" then
        M.Report()
        return true
    elseif arg == "log" then
        M.ReportLog()
        return true
    end
    return false
end

ns.RegisterFeature("voice",
    "Chat Channels: show who's in a community's voice channel before you join it (a microphone on their name). Works between Pace's QoL users the game lets the add-on reach: Battle.net friends playing Forever, your guild and group, and members of your faction in a WoW community",
    M)
