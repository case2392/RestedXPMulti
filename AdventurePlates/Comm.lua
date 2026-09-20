-- Adventure Plates - plates over the addon message channel
--
-- Two messages: "Q" asks a player for their plate, "P" carries one. An
-- addon message holds 255 bytes, a plate can run past that, so a plate is
-- split into numbered chunks (P, a 3-digit run id, 2-digit index, 2-digit
-- count, then the text) and put back together on the other side. The
-- plate itself is key=value pairs joined by "~", with "%", "~", "=" and
-- control characters escaped the URL way. Everything received is put
-- through CleanPlate before it is shown or kept.
--
-- Nothing goes out unasked, and nothing comes in unasked: a plate is only
-- sent to someone who whispered for it and whom the settings allow
-- (everyone, or friends, guildmates and group members, or nobody), and a
-- plate is only shown if it answers a request we made. Whose plate it is
-- comes from the server's word on who sent it, not from the plate. A
-- request from the same player is not answered again within a few
-- seconds, and everything outgoing passes through one slow queue so a
-- burst of requests cannot make the client flood the channel.

local addonName, ns = ...

local CHUNK = 240          -- bytes of plate text per message
local REPLY_GAP = 5        -- seconds before answering the same player again
local WAIT = 6             -- seconds before giving up on a request
local RATE, BURST = 3, 6   -- outgoing messages per second, and at once
local OUTBOX_MAX = 60      -- messages waiting to go, beyond which the oldest are dropped

local runID = 0
local replies = {}         -- name -> time of last plate sent
local inbox = {}           -- sender -> {id, n, parts}
local pending = {}         -- lowercased name -> {name, unit, asked}
local outbox = {}          -- messages waiting for the channel

local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c = pcall(fn, ...)
    if ok then return a, b, c end
end

local function Now()
    return Call(GetTime) or 0
end

local function Key(name)
    return type(name) == "string" and name:lower() or ""
end

-- "Name" -> "Name-OurRealm"; "Name-Realm" as it is
local function Qualify(name)
    if not name:find("-", 1, true) then return name .. "-" .. ns.RealmName() end
    return name
end

--------------------------------------------------------------------------
-- encoding
--------------------------------------------------------------------------

local function Escape(s)
    return (tostring(s):gsub("[%c%%~=]", function(c) return ("%%%02X"):format(c:byte()) end))
end

local function Unescape(s)
    return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

local FIELDS = {"v", "name", "realm", "level", "race", "class", "classFile", "guild", "rank", "gameTitle", "faction", "updated", "title", "motto", "weekdays", "weekends", "looking", "main"}

function ns.Encode(plate)
    local parts = {}
    for _, key in ipairs(FIELDS) do
        local v = plate[key]
        if v ~= nil and v ~= "" then parts[#parts + 1] = key .. "=" .. Escape(v) end
    end
    if type(plate.tags) == "table" and #plate.tags > 0 then
        parts[#parts + 1] = "tags=" .. Escape(table.concat(plate.tags, ","))
    end
    if type(plate.profs) == "table" and #plate.profs > 0 then
        parts[#parts + 1] = "profs=" .. Escape(ns.ProfsText(plate.profs))
    end
    local roles = {}
    if type(plate.roles) == "table" then
        for _, r in ipairs(ns.ROLES) do if plate.roles[r.key] then roles[#roles + 1] = r.key end end
    end
    if #roles > 0 then parts[#parts + 1] = "roles=" .. table.concat(roles, ",") end
    return table.concat(parts, "~")
end

function ns.Decode(text)
    if type(text) ~= "string" then return nil end
    local raw = {}
    for pair in text:gmatch("[^~]+") do
        local k, v = pair:match("^([%w_]+)=(.*)$")
        if k then raw[k] = Unescape(v) end
    end
    if raw.tags then
        local list = {}
        for key in raw.tags:gmatch("[^,]+") do list[#list + 1] = key end
        raw.tags = list
    end
    if raw.roles then
        local set = {}
        for key in raw.roles:gmatch("[^,]+") do set[key] = true end
        raw.roles = set
    end
    -- profs stays a string: CleanPlate parses and checks it
    return ns.CleanPlate(raw)
end

function ns.Chunks(text)
    runID = (runID + 1) % 1000
    local n = math.max(1, math.ceil(#text / CHUNK))
    local out = {}
    for i = 1, n do
        local piece = text:sub((i - 1) * CHUNK + 1, i * CHUNK)
        out[i] = ("P%03d%02d%02d%s"):format(runID, i, n, piece)
    end
    return out
end

--------------------------------------------------------------------------
-- sending: one queue, a few messages a second
--------------------------------------------------------------------------

local function Api()
    return C_ChatInfo and C_ChatInfo.SendAddonMessage or SendAddonMessage
end

-- the client's word on a send: newer clients return a result code, older
-- ones nothing
local THROTTLED = (Enum and Enum.SendAddonMessageResult and Enum.SendAddonMessageResult.AddonMessageThrottle) or 3

local function Transmit(text, target)
    local api = Api()
    if not api then return "failed" end
    local ok, result = pcall(api, ns.PREFIX, text, "WHISPER", target)
    if not ok then return "failed" end
    if result == nil or result == 0 or result == true then return "sent" end
    if result == THROTTLED then return "throttled" end
    return "failed"
end

local tokens, filled = BURST, nil
local pumpArmed

local function Refill()
    local now = Now()
    if filled and now > filled then tokens = math.min(BURST, tokens + (now - filled) * RATE) end
    filled = now
end

local Pump

local function Tick()
    pumpArmed = nil
    Pump()
end

Pump = function()
    Refill()
    while outbox[1] and tokens >= 1 do
        local m = outbox[1]
        m.result = Transmit(m.text, m.target)
        if m.result == "throttled" then
            -- the client says slow down: the message stays at the head
            m.result = nil
            tokens = 0
            break
        end
        table.remove(outbox, 1)
        tokens = tokens - 1
        ns.sentCount = (ns.sentCount or 0) + 1
    end
    if outbox[1] then
        if C_Timer and C_Timer.After then
            if not pumpArmed then
                pumpArmed = true
                C_Timer.After(1 / RATE, Tick)
            end
        else
            -- no timer to wait on: out it goes, the client will throttle
            while outbox[1] do
                local m = table.remove(outbox, 1)
                m.result = Transmit(m.text, m.target)
            end
        end
    end
end

-- false only when the message could not be sent at all; a queued message
-- counts as sent
local function Send(text, target)
    if not Api() then return false end
    local m = {text = text, target = target}
    outbox[#outbox + 1] = m
    while #outbox > OUTBOX_MAX do table.remove(outbox, 1) end
    Pump()
    return m.result ~= "failed"
end

function ns.RegisterComm()
    local api = C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix or RegisterAddonMessagePrefix
    if api then ns.commRegistered = pcall(api, ns.PREFIX) end
end

-- may this player (Name-Realm, as the server names them) have our plate?
-- In friends mode the whole name counts: a stranger on another realm who
-- shares a guildmate's first name is not that guildmate.
function ns.MayShareWith(name)
    local mode = ns.db and ns.db.settings.share or "everyone"
    if mode == "off" then return false end
    if mode == "everyone" then return true end
    if type(name) ~= "string" then return false end
    local want = Key(Qualify(name))
    local members = Call(GetNumGroupMembers) or 0
    local prefix = Call(IsInRaid) and "raid" or "party"
    for i = 1, members do
        local uname, urealm = Call(UnitName, prefix .. i)
        if type(uname) == "string" then
            local full = (type(urealm) == "string" and urealm ~= "") and (uname .. "-" .. urealm) or Qualify(uname)
            if Key(full) == want then return true end
        end
    end
    if Call(IsInGuild) and GetNumGuildMembers and GetGuildRosterInfo then
        for i = 1, Call(GetNumGuildMembers) or 0 do
            local member = Call(GetGuildRosterInfo, i)
            if type(member) == "string" and Key(Qualify(member)) == want then return true end
        end
    end
    if C_FriendList and C_FriendList.GetNumFriends and C_FriendList.GetFriendInfoByIndex then
        for i = 1, Call(C_FriendList.GetNumFriends) or 0 do
            local info = Call(C_FriendList.GetFriendInfoByIndex, i)
            local friend = type(info) == "table" and info.name
            if type(friend) == "string" and Key(Qualify(friend)) == want then return true end
        end
    end
    return false
end

function ns.SendPlate(target)
    local plate = ns.MyPlate()
    local text = ns.Encode(plate)
    local chunks = ns.Chunks(text)
    for _, c in ipairs(chunks) do
        if not Send(c, target) then return false end
    end
    return #chunks
end

function ns.RequestPlate(name, unit)
    if not name then
        ns.Print("whose plate? /plate <name>, or /plate target")
        return false
    end
    if ns.SameName(name, ns.CharKey()) then
        ns.ShowOwnPlate()
        return true
    end
    local key = Key(name)
    pending[key] = {name = name, unit = unit, asked = Now()}
    -- show what we have straight away, and refresh it when the reply comes
    local cached, seen = ns.Cached(name)
    if cached and ns.ShowPlate then ns.ShowPlate(cached, {key = name, unit = unit, cached = seen}) end
    if not Send("Q" .. ns.FORMAT, name) then
        pending[key] = nil
        ns.Print("could not ask %s for their plate", name)
        return false
    end
    if not cached then ns.Print("asking %s for their plate...", name) end
    if C_Timer and C_Timer.After then
        C_Timer.After(WAIT, function()
            local p = pending[key]
            if p and p.asked and Now() - p.asked >= WAIT - 0.5 then
                pending[key] = nil
                if not cached then ns.Print("no plate from %s (they need Adventure Plates too, and to be online)", name) end
            end
        end)
    end
    return true
end

--------------------------------------------------------------------------
-- receiving
--------------------------------------------------------------------------

local function Assemble(sender, text)
    local id, i, n, piece = text:match("^P(%d%d%d)(%d%d)(%d%d)(.*)$")
    if not id then return nil end
    i, n = tonumber(i), tonumber(n)
    if n < 1 or i < 1 or i > n then return nil end
    local box = inbox[sender]
    -- pieces of an old run that never finished are not stitched to a new one
    if box and Now() - box.started > WAIT * 2 then box = nil end
    if not box or box.id ~= id or box.n ~= n then
        box = {id = id, n = n, parts = {}, count = 0, started = Now()}
        inbox[sender] = box
    end
    if not box.parts[i] then box.count = box.count + 1 end
    box.parts[i] = piece
    if box.count < n then return nil end
    inbox[sender] = nil
    return table.concat(box.parts)
end

function ns.OnAddonMessage(prefix, text, channel, sender)
    if prefix ~= ns.PREFIX or type(text) ~= "string" or type(sender) ~= "string" then return end
    if ns.SameName(sender, ns.CharKey()) then return end
    -- plates travel by whisper only: a request shouted at a group or guild
    -- would have everyone in it whisper back at once
    if channel ~= nil and channel ~= "WHISPER" then return end
    if text:sub(1, 1) == "Q" then
        local last = replies[sender]
        if last and Now() - last < REPLY_GAP then return end
        if not ns.MayShareWith(sender) then return end
        replies[sender] = Now()
        ns.SendPlate(sender)
        if ns.db.settings.greet then ns.Print("%s looked at your plate", sender) end
    elseif text:sub(1, 1) == "P" then
        -- only an answer to something we asked
        local p = pending[Key(sender)]
        if not p then return end
        local whole = Assemble(sender, text)
        if not whole then return end
        local plate = ns.Decode(whole)
        if not plate then return end
        -- whose it is comes from the server, whatever the plate says
        local sname, srealm = sender:match("^([^%-]+)%-?(.*)$")
        plate.name = sname or sender
        plate.realm = (srealm and srealm ~= "") and srealm or ns.RealmName()
        pending[Key(sender)] = nil
        ns.Remember(sender, plate)
        if ns.ShowPlate then ns.ShowPlate(plate, {key = sender, unit = p.unit, fresh = true}) end
    end
end

-- for the harness and the report
ns._comm = {pending = pending, replies = replies, inbox = inbox, outbox = outbox}
