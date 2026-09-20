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
-- Nothing goes out unasked: a plate is only sent to someone who asked
-- for it, and only if the settings allow them (everyone, or friends,
-- guildmates and party members, or nobody). A whisper to the same
-- player is not repeated within a few seconds.

local addonName, ns = ...

local CHUNK = 240          -- bytes of plate text per message
local REPLY_GAP = 5        -- seconds before answering the same player again
local WAIT = 6             -- seconds before giving up on a request

local runID = 0
local replies = {}         -- name -> time of last plate sent
local inbox = {}           -- sender -> {id, n, parts}
local pending = {}         -- name -> {unit, asked}

local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c = pcall(fn, ...)
    if ok then return a, b, c end
end

local function Now()
    return Call(GetTime) or 0
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

local FIELDS = {"v", "name", "realm", "level", "race", "class", "classFile", "guild", "rank", "gameTitle", "faction", "updated", "title", "motto", "weekdays", "weekends"}

function ns.Encode(plate)
    local parts = {}
    for _, key in ipairs(FIELDS) do
        local v = plate[key]
        if v ~= nil and v ~= "" then parts[#parts + 1] = key .. "=" .. Escape(v) end
    end
    if type(plate.tags) == "table" and #plate.tags > 0 then
        parts[#parts + 1] = "tags=" .. Escape(table.concat(plate.tags, ","))
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
-- sending
--------------------------------------------------------------------------

local function Send(text, target)
    local api = C_ChatInfo and C_ChatInfo.SendAddonMessage or SendAddonMessage
    if not api then return false end
    local ok = pcall(api, ns.PREFIX, text, "WHISPER", target)
    return ok
end

function ns.RegisterComm()
    local api = C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix or RegisterAddonMessagePrefix
    if api then pcall(api, ns.PREFIX) end
end

-- may this player have our plate?
function ns.MayShareWith(name)
    local mode = ns.db and ns.db.settings.share or "everyone"
    if mode == "off" then return false end
    if mode == "everyone" then return true end
    local short = name:match("^([^%-]+)") or name
    if Call(UnitInParty, short) or Call(UnitInRaid, short) then return true end
    if Call(IsInGuild) and GetNumGuildMembers and GetGuildRosterInfo then
        for i = 1, Call(GetNumGuildMembers) or 0 do
            local member = Call(GetGuildRosterInfo, i)
            if type(member) == "string" and (member == name or member:match("^([^%-]+)") == short) then return true end
        end
    end
    if C_FriendList and C_FriendList.GetNumFriends and C_FriendList.GetFriendInfoByIndex then
        for i = 1, Call(C_FriendList.GetNumFriends) or 0 do
            local info = Call(C_FriendList.GetFriendInfoByIndex, i)
            local friend = type(info) == "table" and info.name
            if type(friend) == "string" and (friend == name or friend:match("^([^%-]+)") == short) then return true end
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
    if name == ns.CharKey() then
        ns.ShowOwnPlate()
        return true
    end
    pending[name] = {unit = unit, asked = Now()}
    -- show what we have straight away, and refresh it when the reply comes
    local cached, seen = ns.Cached(name)
    if cached and ns.ShowPlate then ns.ShowPlate(cached, {key = name, unit = unit, cached = seen}) end
    if not Send("Q" .. ns.FORMAT, name) then
        ns.Print("could not ask %s for their plate", name)
        return false
    end
    if not cached then ns.Print("asking %s for their plate...", name) end
    if C_Timer and C_Timer.After then
        C_Timer.After(WAIT, function()
            local p = pending[name]
            if p and p.asked and Now() - p.asked >= WAIT - 0.5 then
                pending[name] = nil
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
    if sender == ns.CharKey() then return end
    if text:sub(1, 1) == "Q" then
        if not ns.MayShareWith(sender) then return end
        local last = replies[sender]
        if last and Now() - last < REPLY_GAP then return end
        replies[sender] = Now()
        ns.SendPlate(sender)
        if ns.db.settings.greet then ns.Print("%s looked at your plate", sender) end
    elseif text:sub(1, 1) == "P" then
        local whole = Assemble(sender, text)
        if not whole then return end
        local plate = ns.Decode(whole)
        if not plate then return end
        if plate.name == "" then plate.name = sender:match("^([^%-]+)") or sender end
        ns.Remember(sender, plate)
        local p = pending[sender]
        pending[sender] = nil
        if ns.ShowPlate then ns.ShowPlate(plate, {key = sender, unit = p and p.unit, fresh = true}) end
    end
end

-- for the harness
ns._comm = {pending = pending, replies = replies, inbox = inbox}
