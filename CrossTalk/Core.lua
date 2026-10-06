-- CrossTalk (Forever) - core
--
-- How the game hides the other faction's speech: every word said in a
-- language you do not know is swapped for a word of the same length from
-- that language's word list, picked by a hash of the original word. A
-- one-character word therefore always comes out as a one-letter word, and
-- which input character gives which letter is fixed - for a given language
-- on a given game build. So the right single characters, sent one per
-- word, spell out capital letters on the other side: "R I P r B O Z O".
-- (The technique is the one the Hermes addon published; this is its own
-- code.)
--
-- The catch is that the mapping changes from patch to patch: Hermes's
-- Common table changed every letter but one with a single Wrath Classic
-- patch. No table for WoW Forever has been published, so this addon finds
-- its own: one player sends "probes" (batches of single characters in
-- /say) and a player of the other faction running CrossTalk reads what
-- they turned into and gives back a short share code. See Calibrate.lua.
--
-- Rules shared with the other addons in this repo: no writes into
-- Blizzard's tables, everything a client might hand back secret read
-- under pcall.

local addonName, ns = ...

do
    local meta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local ok, v = pcall(function() return meta and meta(addonName, "Version") end)
    ns.VERSION = (ok and type(v) == "string" and v ~= "" and v) or "1.0.0"
end

ns.NAME = "CrossTalk"
ns.COMMON, ns.ORCISH = 7, 1
-- longest message the server takes in /say, in bytes
ns.MAX_BYTES = 255

function ns.Print(fmt, ...)
    local msg = fmt
    if select("#", ...) > 0 then msg = fmt:format(...) end
    print("|cFF66CCFFCrossTalk|r: " .. msg)
end

--------------------------------------------------------------------------
-- languages
--------------------------------------------------------------------------

local LANGUAGE_NAMES = {[1] = "Orcish", [7] = "Common", [33] = "Gutterspeak",
                        [3] = "Taurahe", [14] = "Zandali", [10] = "Thalassian",
                        [2] = "Darnassian", [6] = "Dwarvish", [13] = "Gnomish",
                        [35] = "Draenei"}

function ns.LanguageName(id)
    return LANGUAGE_NAMES[id] or ("language " .. tostring(id))
end

-- the language the player speaks by default: Common for the Alliance,
-- Orcish for the Horde. The default is what the whole other faction
-- cannot read, and it is the one every probe and phrase goes out in.
function ns.MyLanguage()
    if GetDefaultLanguage then
        local ok, name, id = pcall(GetDefaultLanguage, "player")
        if ok and type(id) == "number" then return id, name end
    end
    local faction = UnitFactionGroup and UnitFactionGroup("player")
    if faction == "Horde" then return ns.ORCISH, "Orcish" end
    return ns.COMMON, "Common"
end

-- can the player read this language? Unknown languages are what the
-- decoder and the listener look at.
function ns.Speaks(languageID, languageName)
    if type(languageID) ~= "number" or languageID == 0 then
        return languageName == nil or languageName == ""
    end
    local api = C_ChatInfo
    if api and api.CanPlayerSpeakLanguage then
        local ok, can = pcall(api.CanPlayerSpeakLanguage, languageID)
        if ok and type(can) == "boolean" then return can end
    end
    if GetNumLanguages and GetLanguageByIndex then
        for i = 1, GetNumLanguages() or 0 do
            local _, id = GetLanguageByIndex(i)
            if id == languageID then return true end
        end
        return false
    end
    return languageID == (ns.MyLanguage())
end

function ns.Build()
    if GetBuildInfo then
        local _, build = GetBuildInfo()
        return tostring(build or "?")
    end
    return "?"
end

--------------------------------------------------------------------------
-- strings: UTF-8 without a utf8 library (the client's Lua is 5.1)
--------------------------------------------------------------------------

function ns.Utf8(cp)
    if cp < 0x80 then return string.char(cp) end
    if cp < 0x800 then
        return string.char(0xC0 + math.floor(cp / 0x40), 0x80 + cp % 0x40)
    end
    return string.char(0xE0 + math.floor(cp / 0x1000),
                       0x80 + math.floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
end

-- split on runs of whitespace
function ns.Words(text)
    local out = {}
    for w in tostring(text):gmatch("%S+") do out[#out + 1] = w end
    return out
end

-- read a chat argument that a secret-value client may hand back hidden:
-- the plain string, or nil when it cannot be used
function ns.Plain(v)
    if type(v) ~= "string" then return nil end
    local ok, copy = pcall(function() return v .. "" end)
    if ok and type(copy) == "string" then return copy end
end

function ns.ShortName(name)
    name = ns.Plain(name)
    if not name then return nil end
    if Ambiguate then
        local ok, short = pcall(Ambiguate, name, "short")
        if ok and type(short) == "string" then name = short end
    end
    return (name:match("^([^%-]+)") or name):lower()
end

--------------------------------------------------------------------------
-- the probe pool: every single character a probe may try. Built in a
-- fixed order so two copies of the same pool version agree on what index
-- N is - share codes carry indexes, not the characters.
--------------------------------------------------------------------------

ns.POOL_VERSION = 1

local function BuildPool()
    local pool = {}
    local function Range(a, b, skip)
        for cp = a, b do
            if not (skip and skip[cp]) then pool[#pool + 1] = ns.Utf8(cp) end
        end
    end
    -- digits and ASCII letters first: the likeliest to be taken as words.
    -- Hermes's tables were mostly digits and accented letters.
    Range(0x30, 0x39)
    Range(0x41, 0x5A)
    Range(0x61, 0x7A)
    -- Latin-1 supplement (no soft hyphen), Latin Extended-A, Greek, Cyrillic
    Range(0xA1, 0xFF, {[0xAD] = true})
    Range(0x100, 0x17F)
    Range(0x391, 0x3C9, {[0x3A2] = true})
    Range(0x410, 0x44F)
    -- ASCII punctuation last: the server may keep it as it is or drop it,
    -- and a dropped character costs the whole probe it is in
    Range(0x21, 0x2F)
    Range(0x3A, 0x40)
    Range(0x5B, 0x60)
    Range(0x7B, 0x7E, {[0x7C] = true})
    return pool
end
ns.POOL = BuildPool()

--------------------------------------------------------------------------
-- saved data
--------------------------------------------------------------------------

ns.DEFAULT_PHRASES = {
    "RIP BOZO", "GOOD LUCK", "LOSER", "GG", "LOL", "NICE TRY",
    "HELLO", "BYE", "THANKS", "WELL PLAYED", "SORRY", "RUN"
}

function ns.InitDB()
    CrossTalkDB = CrossTalkDB or {}
    local db = CrossTalkDB
    db.tables = db.tables or {}
    if db.phrases == nil then
        db.phrases = {}
        for i, p in ipairs(ns.DEFAULT_PHRASES) do db.phrases[i] = p end
    end
    if db.show == nil then db.show = true end
    if db.decode == nil then db.decode = true end
    ns.db = db
end

-- the letter table for a language: {letters = {A = "x", ...},
-- lowers = {r = "y", ...}, build = "...", count = n}, or nil
function ns.Table(languageID)
    return ns.db and ns.db.tables[languageID]
end

-- is the table for this language from the build the game is on now?
function ns.TableCurrent(t)
    return t and t.build == ns.Build()
end

--------------------------------------------------------------------------
-- encoding: text -> the characters to send, and what the other side sees
--------------------------------------------------------------------------

-- a letter the language cannot make is swapped for the nearest sound it
-- can; each option is tried in order and must be makeable in full
ns.SUBSTITUTES = {
    A = {"E"}, B = {"P", "V"}, C = {"K", "S"}, D = {"T"}, E = {"I", "A"},
    F = {"PH", "V"}, G = {"K"}, H = {}, I = {"Y", "E"}, J = {"G", "Y"},
    K = {"C", "Q"}, L = {}, M = {"N"}, N = {"M"}, O = {"U"}, P = {"B"},
    Q = {"K", "C"}, R = {}, S = {"Z", "C"}, T = {"D"}, U = {"OO", "O", "V"},
    V = {"F", "W", "B"}, W = {"VV", "UU", "V", "U"}, X = {"KS", "CS", "S"},
    Y = {"I", "IE"}, Z = {"S"}
}

local DIGITS = {["0"] = "ZERO", ["1"] = "ONE", ["2"] = "TWO", ["3"] = "THREE",
                ["4"] = "FOUR", ["5"] = "FIVE", ["6"] = "SIX", ["7"] = "SEVEN",
                ["8"] = "EIGHT", ["9"] = "NINE"}

-- the separator between words: a lowercase letter, so it stands apart
-- from the capitals around it. Letters that read like capitals or like
-- each other are the last choice.
local SEPARATOR_PREFERENCE = {"r", "n", "x", "a", "e", "u", "m", "h", "k", "t",
                              "d", "g", "b", "f", "s", "z", "q", "j", "p",
                              "y", "w", "v", "c", "o", "i", "l"}

function ns.Separator(t)
    if not t or not t.lowers then return nil end
    for _, l in ipairs(SEPARATOR_PREFERENCE) do
        if t.lowers[l] then return l, t.lowers[l] end
    end
end

-- the spelled form of one letter: a list of letters the table can make,
-- or nil when no substitute works
local function Spell(letter, letters, depth)
    if letters[letter] then return {letter} end
    if (depth or 0) > 1 then return nil end
    for _, alt in ipairs(ns.SUBSTITUTES[letter] or {}) do
        local out = {}
        for c in alt:gmatch(".") do
            local part = Spell(c, letters, (depth or 0) + 1)
            if not part then out = nil; break end
            for _, p in ipairs(part) do out[#out + 1] = p end
        end
        if out then return out end
    end
end

-- Returns send, preview, info:
--   send    - what to hand SendChatMessage (single characters, one per word)
--   preview - what the other faction will read, e.g. "R I P r B O Z O"
--   info    - {dropped = {letters that could not be made}, swapped = {X = "KS"},
--              bytes = n, tooLong = bool}
-- nil, reason when there is no table to encode with.
function ns.Encode(text, t)
    if not t or not t.letters or not next(t.letters) then
        return nil, "no letter table"
    end
    local sepLetter, sepChar = ns.Separator(t)
    local sendParts, seeParts = {}, {}
    local info = {dropped = {}, swapped = {}}
    local pendingBreak = false
    local function Break()
        if #seeParts > 0 then pendingBreak = true end
    end
    local function Emit(letter)
        if pendingBreak then
            if sepChar then
                sendParts[#sendParts + 1] = sepChar
                seeParts[#seeParts + 1] = sepLetter
            end
            pendingBreak = false
        end
        sendParts[#sendParts + 1] = t.letters[letter]
        seeParts[#seeParts + 1] = letter
    end
    local upper = tostring(text):upper()
    -- digits become words first
    upper = upper:gsub("%d", function(d) return " " .. DIGITS[d] .. " " end)
    for ch in upper:gmatch(".") do
        if ch:match("%u") then
            local spelled = Spell(ch, t.letters)
            if spelled then
                if #spelled ~= 1 or spelled[1] ~= ch then
                    info.swapped[ch] = table.concat(spelled)
                end
                for _, l in ipairs(spelled) do Emit(l) end
            else
                info.dropped[ch] = true
            end
        elseif ch:match("[%s%p]") then
            Break()
        end
        -- anything else (bytes of non-Latin text) is left out
    end
    local send = table.concat(sendParts, " ")
    info.bytes = #send
    info.tooLong = #send > ns.MAX_BYTES
    return send, table.concat(seeParts, " "), info
end

--------------------------------------------------------------------------
-- decoding: a spelled message from the other faction, read back
--------------------------------------------------------------------------

-- "R I P r B O Z O" -> "RIP BOZO". Only for text that is mostly single
-- letters, which ordinary scrambled speech never is (its words are of
-- every length). Two- and three-letter capital words join the word they
-- sit in; a single lowercase letter is a word break.
function ns.Despell(text)
    local words = ns.Words(text)
    if #words < 3 then return nil end
    local single = 0
    for _, w in ipairs(words) do
        if w:match("^%a$") then single = single + 1 end
    end
    if single < #words * 0.7 then return nil end
    local out, cur = {}, {}
    local function Flush()
        if #cur > 0 then out[#out + 1] = table.concat(cur); cur = {} end
    end
    for _, w in ipairs(words) do
        if w:match("^%u%u?%u?$") then
            cur[#cur + 1] = w
        elseif w:match("^%l$") then
            Flush()
        else
            Flush()
            out[#out + 1] = w
        end
    end
    Flush()
    if #out == 0 then return nil end
    return table.concat(out, " ")
end

--------------------------------------------------------------------------
-- share codes: a table as text, to pass to the player who will use it
--   CT1:7:70009:A12,B88,E3:r140,n33
--   version : language : build : capitals : lowercase
-- Indexes point into the probe pool of that version.
--------------------------------------------------------------------------

function ns.ShareCode(languageID, t)
    if not t then return nil end
    local function Part(map)
        local keys = {}
        for k in pairs(map or {}) do keys[#keys + 1] = k end
        table.sort(keys)
        local parts = {}
        for _, k in ipairs(keys) do
            local idx = t.index and t.index[map[k]]
            if idx then parts[#parts + 1] = k .. idx end
        end
        return table.concat(parts, ",")
    end
    return ("CT%d:%d:%s:%s:%s"):format(ns.POOL_VERSION, languageID,
                                       tostring(t.build or "?"),
                                       Part(t.letters), Part(t.lowers))
end

-- Returns languageID, table or nil, reason
function ns.ParseShareCode(code)
    code = tostring(code or ""):gsub("%s", "")
    local ver, lang, build, caps, lows = code:match("^CT(%d+):(%d+):([^:]*):([^:]*):?([^:]*)$")
    if not ver then return nil, "that is not a CrossTalk code" end
    if tonumber(ver) ~= ns.POOL_VERSION then
        return nil, ("that code is from a different CrossTalk version (pool %s, this is %d) - both of you update"):format(ver, ns.POOL_VERSION)
    end
    local t = {build = build, letters = {}, lowers = {}, index = {}}
    local function Fill(text, map, pattern)
        for letter, idx in text:gmatch(pattern) do
            local ch = ns.POOL[tonumber(idx)]
            if ch then
                map[letter] = ch
                t.index[ch] = tonumber(idx)
            end
        end
    end
    Fill(caps, t.letters, "(%u)(%d+)")
    Fill(lows, t.lowers, "(%l)(%d+)")
    if not next(t.letters) then return nil, "that code has no letters in it" end
    return tonumber(lang), t
end

-- every letter a table can make, for status lines
function ns.LetterList(t)
    local keys = {}
    for k in pairs(t and t.letters or {}) do keys[#keys + 1] = k end
    table.sort(keys)
    return table.concat(keys, "")
end

function ns.StoreTable(languageID, t, source)
    t.source = source
    t.count = 0
    for _ in pairs(t.letters) do t.count = t.count + 1 end
    ns.db.tables[languageID] = t
    if ns.RefreshUI then ns.RefreshUI() end
end

--------------------------------------------------------------------------
-- sending
--------------------------------------------------------------------------

-- Forever's SendChatMessage takes /say and /yell from a key press or a
-- click only (out in the world), so every send here happens right inside
-- a slash command or a button's OnClick, never from a timer.
function ns.SendRaw(text, chatType)
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    if not send then return false end
    local lang = ns.MyLanguage()
    local ok, err = pcall(send, text, chatType or "SAY", lang)
    if not ok then ns.Print("the game refused the message: %s", tostring(err)) end
    return ok
end

-- encode and send; prints what they will see. Returns true when sent.
function ns.Say(text, chatType)
    local lang = ns.MyLanguage()
    local t = ns.Table(lang)
    if not t then
        ns.Print("no letter table for %s yet - it has to be found once with a player of the other faction. Type |cFFFFCC00/ct calibrate|r for how.", ns.LanguageName(lang))
        return false
    end
    local send, preview, info = ns.Encode(text, t)
    if not send or send == "" then
        ns.Print("nothing in that can be spelled.")
        return false
    end
    if info.tooLong then
        ns.Print("too long to send in one message (%d of %d bytes) - split it up.", info.bytes, ns.MAX_BYTES)
        return false
    end
    if not ns.SendRaw(send, chatType) then return false end
    ns.Print("they see: |cFFFF6666%s|r", preview)
    local dropped = {}
    for l in pairs(info.dropped) do dropped[#dropped + 1] = l end
    if #dropped > 0 then
        table.sort(dropped)
        ns.Print("left out (no way to make them): %s", table.concat(dropped, " "))
    end
    if not ns.TableCurrent(t) then
        ns.Print("|cFFFFAA00this table was found on game build %s and you are on %s: if they read gibberish, calibrate again.|r", tostring(t.build), ns.Build())
    end
    return true
end
