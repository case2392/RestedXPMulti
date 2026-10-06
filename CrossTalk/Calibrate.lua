-- CrossTalk (Forever) - finding the letter table
--
-- Two players, one of each faction, both running CrossTalk, standing in
-- /say range. The SENDER is the one whose table is wanted (an Alliance
-- player for the Common table). They click "Send probe" and each probe
-- goes out in /say: a batch of single characters from the shared pool.
-- The LISTENER (a Horde player, who cannot read Common) has typed
-- "/ct listen <sender>"; their copy reads what each character turned into
-- and keeps every one that came out as a single letter. When enough
-- letters are in, the listener's window shows a share code; the sender
-- pastes it into "/ct import" (pass it over a Battle.net whisper, which
-- crosses factions, or anything else).
--
-- The listener has to know which probe it is looking at without being
-- told (it can't read the sender's words, that is the point). Every probe
-- has a different number of words, three apart, so the word count names
-- the probe; a character the server swallowed changes the count to one
-- no probe has, and that probe is simply set aside. The first word of
-- every probe is a fixed filler that is never read: some clients
-- capitalise a message's first word, which would pass a lowercase letter
-- off as a capital.

local addonName, ns = ...

local FILLER = "X"
local FIRST_SIZE, STEP = 40, 3   -- words per probe, filler included

-- the probes: lists of pool indexes, the same in every copy of the pool
-- version. The last one is topped up from the start of the pool so its
-- size stays on the three-apart ladder.
function ns.Probes()
    if ns.probes then return ns.probes end
    local probes, sizeIndex = {}, {}
    local pool = ns.POOL
    local i, size = 1, FIRST_SIZE
    while i <= #pool do
        local p = {}
        for _ = 1, size - 1 do
            local idx = i
            if idx > #pool then idx = (idx - 1) % #pool + 1 end
            p[#p + 1] = idx
            i = i + 1
        end
        probes[#probes + 1] = p
        sizeIndex[size] = #probes
        size = size + STEP
    end
    ns.probes, ns.probeBySize = probes, sizeIndex
    return probes
end

function ns.ProbeText(n)
    local p = ns.Probes()[n]
    if not p then return nil end
    local parts = {FILLER}
    for _, idx in ipairs(p) do parts[#parts + 1] = ns.POOL[idx] end
    return table.concat(parts, " ")
end

--------------------------------------------------------------------------
-- sender
--------------------------------------------------------------------------

-- send probe n (or the next one); must be called from a click or a slash
-- command, like every /say an addon makes on Forever
function ns.SendProbe(n)
    local probes = ns.Probes()
    n = n or ns.db.probeNext or 1
    if n > #probes then n = 1 end
    local text = ns.ProbeText(n)
    if not ns.SendRaw(text, "SAY") then return false end
    ns.db.probeNext = n + 1
    ns.Print("probe %d of %d sent.", n, #probes)
    if ns.RefreshCalibrate then ns.RefreshCalibrate() end
    return true
end

--------------------------------------------------------------------------
-- listener
--------------------------------------------------------------------------

function ns.StartListening(name)
    local target = ns.ShortName(name)
    if not target or target == "" then
        ns.Print("type the sender's name: |cFFFFCC00/ct listen Name|r")
        return
    end
    ns.Probes()
    ns.listen = {
        target = target, display = name,
        letters = {}, lowers = {}, index = {}, outByIndex = {},
        seen = {}, ignored = 0, conflicts = 0, lang = nil
    }
    ns.Print("listening to %s. Ask them to open |cFFFFCC00/ct calibrate|r and click Send probe while standing next to you.", name)
    if ns.ShowListen then ns.ShowListen() end
end

function ns.StopListening()
    ns.listen = nil
    if ns.RefreshListen then ns.RefreshListen() end
end

-- one /say from the sender, in a language this player cannot read.
-- Returns true when it was a probe.
function ns.Observe(text, languageID)
    local L = ns.listen
    if not L then return false end
    local words = ns.Words(text)
    local n = ns.probeBySize[#words]
    if not n then
        L.ignored = L.ignored + 1
        if ns.RefreshListen then ns.RefreshListen() end
        return false
    end
    L.lang = L.lang or languageID
    L.seen[n] = true
    local probe = ns.Probes()[n]
    for j = 2, #words do
        local idx = probe[j - 1]
        local ch = ns.POOL[idx]
        local out = words[j]
        -- the same character must always come out the same; if it does
        -- not, the game mixes in more than the word and tables won't hold
        local before = L.outByIndex[idx]
        if before and before ~= out then L.conflicts = L.conflicts + 1 end
        L.outByIndex[idx] = out
        if out:match("^%u$") then
            if not L.letters[out] then
                L.letters[out] = ch
                L.index[ch] = idx
            end
        elseif out:match("^%l$") then
            if not L.lowers[out] then
                L.lowers[out] = ch
                L.index[ch] = idx
            end
        end
    end
    if ns.RefreshListen then ns.RefreshListen() end
    return true
end

-- what the listener has found, as a table and a share code
function ns.ListenResult()
    local L = ns.listen
    if not L or not next(L.letters) then return nil end
    local t = {build = ns.Build(), letters = L.letters, lowers = L.lowers, index = L.index}
    return L.lang or ns.COMMON, t, ns.ShareCode(L.lang or ns.COMMON, t)
end

function ns.ListenSummary()
    local L = ns.listen
    if not L then return "not listening" end
    local probes = ns.Probes()
    local seen = 0
    for _ in pairs(L.seen) do seen = seen + 1 end
    local _, t = ns.ListenResult()
    local sep = t and ns.Separator(t)
    local s = ("probes read: %d of %d   letters: %s   word break: %s"):format(
        seen, #probes, t and ns.LetterList(t) ~= "" and ns.LetterList(t) or "none yet",
        sep and ("'" .. sep .. "'") or "none yet")
    if L.ignored > 0 then
        s = s .. ("\n%d message(s) from them were not a probe (or lost a character) and were set aside"):format(L.ignored)
    end
    if L.conflicts > 0 then
        s = s .. "\n|cFFFF6666the same character came out as different letters - the game is mixing in more than the word, so a table may not hold|r"
    end
    return s
end
