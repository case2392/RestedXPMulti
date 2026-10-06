-- Offline harness for CrossTalk (Lua 5.1).
--   lua5.1 tests/harness_crosstalk.lua .
--
-- Two players on one simulated Forever server: Ally (Alliance, Common)
-- and Hordie (Horde, Orcish), each with their own copy of the addon. The
-- server's scrambler is simulated the way the game behaves: each word in
-- a language the listener does not know becomes a word of the same
-- length from that language's list, picked by a hash of the word and the
-- game build; a lowercase input gives a lowercase word; the first word of
-- a message is capitalised; ASCII punctuation passes unchanged and a
-- backtick is swallowed. Common's one-letter list lacks C J P Q X Z and
-- Orcish's lacks more, as Hermes found on the clients it covered.
local root = arg and arg[1] or "."
local realPrint = print
local passed, failed = 0, 0
local function check(cond, label)
    if cond then passed = passed + 1 else failed = failed + 1; realPrint("FAIL: " .. label) end
end

--------------------------------------------------------------------------
-- the simulated scrambler
--------------------------------------------------------------------------

local WORDS = {
    [7] = {  -- Common
        [1] = {"A", "B", "D", "E", "F", "G", "H", "I", "K", "L", "M", "N", "O", "R", "S", "T", "U", "V", "W", "Y"},
        [2] = {"RE", "TI", "VA", "KO", "ME", "RU", "AN", "SE", "LU", "VR", "AG", "VO"},
        [3] = {"ASH", "BUR", "NUD", "RAS", "HIR", "LON", "VER", "WOS", "GOL", "THO"}
    },
    [1] = {  -- Orcish
        [1] = {"A", "D", "G", "H", "I", "K", "L", "M", "N", "O", "R", "T", "U", "Z"},
        [2] = {"KA", "GI", "IL", "HA", "KO", "MU", "MA", "NO", "TH", "OG"},
        [3] = {"AAZ", "DAL", "GES", "KEK", "LOK", "MOG", "NUK", "ZUG", "THU", "TAR"}
    }
}

local function Utf8Chars(s)
    local out = {}
    for ch in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do out[#out + 1] = ch end
    return out
end

local function Codepoint(ch)
    local b1, b2, b3 = ch:byte(1, 3)
    if b1 < 0x80 then return b1 end
    if b1 < 0xE0 then return (b1 - 0xC0) * 0x40 + (b2 - 0x80) end
    return (b1 - 0xE0) * 0x1000 + (b2 - 0x80) * 0x40 + (b3 - 0x80)
end

local function IsLowerInput(ch)
    local cp = Codepoint(ch)
    if cp >= 0x61 and cp <= 0x7A then return true end
    if cp >= 0xE0 and cp <= 0xFF and cp ~= 0xF7 then return true end
    if cp >= 0x100 and cp <= 0x17F then return cp % 2 == 1 end
    if cp >= 0x3B1 and cp <= 0x3C9 then return true end
    if cp >= 0x430 and cp <= 0x44F then return true end
    return false
end

local seedOffset = 0
local function Hash(word, build)
    local h = 5381 + tonumber(build) + seedOffset
    for i = 1, #word do h = (h * 33 + word:byte(i)) % 4294967296 end
    return h
end

-- what a listener who does not know `lang` reads
local function Scramble(text, lang, build)
    local out = {}
    for word in text:gmatch("%S+") do
        word = word:gsub("`", "")
        if word ~= "" then
            if word:match("^%p+$") then
                out[#out + 1] = word
            else
                local chars = Utf8Chars(word)
                local list = WORDS[lang][math.min(#chars, 3)]
                local w = list[Hash(word, build) % #list + 1]
                if IsLowerInput(chars[1]) then w = w:lower() end
                out[#out + 1] = w
            end
        end
    end
    if out[1] then out[1] = out[1]:sub(1, 1):upper() .. out[1]:sub(2) end
    return table.concat(out, " ")
end

--------------------------------------------------------------------------
-- two clients
--------------------------------------------------------------------------

local players = {}
local server = {build = "70009", log = {}}

local function Widget(kind, name)
    local w = {kind = kind, name = name, shown = true, scripts = {}, text = "", points = {}}
    setmetatable(w, {__index = function(_, k)
        if type(k) == "string" and k:match("^%u") then return function() end end
    end})
    function w:Show() self.shown = true end
    function w:Hide() self.shown = false end
    function w:IsShown() return self.shown end
    function w:SetShown(v) self.shown = v and true or false end
    function w:SetScript(k, fn) self.scripts[k] = fn end
    function w:GetScript(k) return self.scripts[k] end
    function w:HookScript(k, fn) local p = self.scripts[k]; self.scripts[k] = function(...) if p then p(...) end fn(...) end end
    function w:SetText(t) self.text = t end
    function w:GetText() return self.text end
    function w:GetName() return self.name end
    function w:GetStringHeight() local n = 1; for _ in tostring(self.text):gmatch("\n") do n = n + 1 end; return n * 12 end
    function w:SetPoint(...) self.points[#self.points + 1] = {...} end
    function w:ClearAllPoints() self.points = {} end
    function w:GetPoint() return "CENTER", nil, "CENTER", 0, 0 end
    function w:SetHeight(h) self.height = h end
    function w:SetSize(a, b) self.width, self.height = a, b end
    function w:CreateFontString() return Widget("FontString") end
    function w:CreateTexture() return Widget("Texture") end
    function w:RegisterEvent(e) self.events = self.events or {}; self.events[e] = true end
    function w:SetFocus() self.focused = true end
    function w:ClearFocus() self.focused = false end
    function w:Click(button)
        local fn = self.scripts.OnClick
        if fn then fn(self, button or "LeftButton") end
    end
    return w
end

local function NewPlayer(name, faction, lang)
    local P = {name = name, faction = faction, lang = lang, printed = {}, sent = {}, frames = {}}
    local env = setmetatable({}, {__index = _G})
    P.env = env
    env.print = function(...)
        local t = {}
        for i = 1, select("#", ...) do t[i] = tostring(select(i, ...)) end
        table.insert(P.printed, table.concat(t, " "))
    end
    env.CreateFrame = function(kind, fname, parent, template)
        local f = Widget(kind, fname)
        f.parent, f.template = parent, template
        table.insert(P.frames, f)
        if fname then env[fname] = f end
        return f
    end
    env.UIParent = Widget("Frame", "UIParent")
    env.UISpecialFrames = {}
    env.SlashCmdList = {}
    env.GameTooltip = Widget("GameTooltip")
    env.GameTooltip.lines = {}
    function env.GameTooltip:SetText(t) self.lines = {t} end
    function env.GameTooltip:AddLine(t) table.insert(self.lines, t) end
    env.BackdropTemplateMixin = {}
    env.GetDefaultLanguage = function() return lang == 7 and "Common" or "Orcish", lang end
    env.UnitFactionGroup = function() return faction end
    env.GetBuildInfo = function() return "1.60.2", server.build, "Oct 1 2026", 16001 end
    env.UnitExists = function(u) return u == "target" and P.target ~= nil end
    env.UnitIsPlayer = function(u) return u == "target" and P.target ~= nil end
    env.UnitName = function(u) if u == "player" then return name end if u == "target" then return P.target end end
    env.Ambiguate = function(n) return (n:match("^([^%-]+)")) end
    env.IsControlKeyDown = function() return P.ctrl == true end
    env.C_ChatInfo = {
        CanPlayerSpeakLanguage = function(id) return id == lang end,
        -- out in the world /say and /yell need a key press or a click
        SendChatMessage = function(msg, chatType, language)
            if not P.hardware then error("ADDON_ACTION_BLOCKED: SendChatMessage needs a hardware event") end
            assert(#msg <= 255, "message over 255 bytes")
            table.insert(P.sent, {msg = msg, chatType = chatType, lang = language})
            table.insert(server.log, {from = P, msg = msg, chatType = chatType, lang = language})
            for _, other in pairs(players) do
                other.Receive(P, msg, chatType or "SAY", language)
            end
        end
    }
    env.CrossTalkDB = nil

    -- the addon
    local ns = {}
    for _, file in ipairs({"Core.lua", "Calibrate.lua", "UI.lua", "Main.lua"}) do
        local chunk = assert(loadfile(root .. "/CrossTalk/" .. file))
        setfenv(chunk, env)
        chunk("CrossTalk", ns)
    end
    P.ns = ns
    P.eventFrame = ns.eventFrame

    function P.Fire(event, ...) P.eventFrame.scripts.OnEvent(P.eventFrame, event, ...) end
    -- what this player's chat shows from someone: their own language
    -- plain, anything else scrambled
    P.heard = {}
    function P.Receive(from, msg, chatType, language)
        local text = msg
        if language ~= lang then text = Scramble(msg, language, server.build) end
        if P.secretChat then text = setmetatable({}, {__concat = function() error("attempt to concatenate a secret value") end}) end
        table.insert(P.heard, {from = from.name, text = text, lang = language})
        P.Fire(chatType == "YELL" and "CHAT_MSG_YELL" or "CHAT_MSG_SAY", text, from.name .. "-Forever",
               language == 7 and "Common" or "Orcish", "", "", "", 0, 0, "", language, 1, "Player-1", 0, false, false, false, false)
    end
    -- a key press or a click around fn
    function P.Hardware(fn, ...)
        P.hardware = true
        local ok, err = pcall(fn, ...)
        P.hardware = false
        if not ok then error(err, 2) end
    end
    function P.Slash(text) P.Hardware(env.SlashCmdList.CROSSTALK, text) end
    function P.Printed(pat)
        for _, l in ipairs(P.printed) do if l:find(pat, 1, true) then return l end end
    end
    function P.LastHeard() return P.heard[#P.heard] end

    P.Fire("ADDON_LOADED", "CrossTalk")
    P.Fire("PLAYER_LOGIN")
    players[name] = P
    return P
end

local A = NewPlayer("Ally", "Alliance", 7)
local H = NewPlayer("Hordie", "Horde", 1)
local ans, hns = A.ns, H.ns

--------------------------------------------------------------------------
-- the pool and the probes
--------------------------------------------------------------------------
do
    local seen, dup, bad = {}, false, false
    for _, ch in ipairs(ans.POOL) do
        if seen[ch] then dup = true end
        seen[ch] = true
        if ch:find("[%s|]") then bad = true end
    end
    check(#ans.POOL > 400 and not dup and not bad, "pool: over 400 single characters, no repeats, no space or escape bar")
    check(ans.POOL[1] == "0" and ans.POOL[11] == "A" and ans.POOL[37] == "a", "pool: digits, then capitals, then lowercase first")
    local probes = ans.Probes()
    local sizes, ok, maxBytes, covered = {}, true, 0, {}
    for n, p in ipairs(probes) do
        local size = #p + 1
        for _, s in ipairs(sizes) do if math.abs(s - size) < 3 then ok = false end end
        sizes[#sizes + 1] = size
        maxBytes = math.max(maxBytes, #ans.ProbeText(n))
        for _, idx in ipairs(p) do covered[idx] = true end
    end
    local all = true
    for i = 1, #ans.POOL do if not covered[i] then all = false end end
    check(ok and all, "probes: every one a different size, three or more apart, and together they cover the pool")
    check(maxBytes <= 255, "probes: each fits in one /say (" .. maxBytes .. " bytes)")
    check(ans.ProbeText(1):sub(1, 2) == "X ", "probes: a filler word first")
end

--------------------------------------------------------------------------
-- before calibration
--------------------------------------------------------------------------
do
    A.Slash("rip bozo")
    check(#A.sent == 0 and A.Printed("no letter table for Common yet"), "uncalibrated: nothing sent, says to calibrate")
    check(A.env.CrossTalkFrame and A.env.CrossTalkFrame.shown and A.env.CrossTalkFrame.status.text:find("No Common letter table yet", 1, true), "uncalibrated: the board says so")
    check(#A.env.CrossTalkFrame.buttons == 12 and A.env.CrossTalkFrame.buttons[1].text == "RIP BOZO", "board: the twelve default phrases, RIP BOZO first")
end

--------------------------------------------------------------------------
-- calibration: Ally sends probes, Hordie listens
--------------------------------------------------------------------------
do
    H.target = "Ally"
    H.Hardware(function() H.env.CrossTalkFrame.listen:Click() end)
    check(hns.listen and hns.listen.target == "ally" and H.env.CrossTalkListen.shown, "listen: Hordie listens to the targeted Ally")
    A.Slash("calibrate")
    local cal = A.env.CrossTalkCalibrate
    check(cal.shown and cal.send.text == "Send probe 1 of " .. #ans.Probes(), "calibrate: window shows the first probe button")
    -- a probe outside a click would be blocked by the game: it only goes out from the button
    local okNoClick = pcall(ans.SendProbe)
    check(not okNoClick or #A.sent == 0, "calibrate: a probe without a click is refused by the game (nothing sent)")
    for i = 1, 4 do A.Hardware(function() cal.send:Click() end) end
    check(#A.sent == 4 and A.sent[1].lang == 7 and A.sent[1].chatType == "SAY", "calibrate: four probes said in Common")
    check(cal.send.text == "Send probe 5 of " .. #ans.Probes(), "calibrate: the button moves on to the next probe")
    -- Hordie read them
    local L = hns.listen
    local seen = 0
    for _ in pairs(L.seen) do seen = seen + 1 end
    check(seen == 4 and L.ignored == 0 and L.conflicts == 0, "listen: all four probes recognised by their word count")
    local lang, t, code = hns.ListenResult()
    check(lang == 7 and t and hns.LetterList(t) == "ABDEFGHIKLMNORSTUVWY", "listen: every letter Common can make found (" .. tostring(t and hns.LetterList(t)) .. ")")
    check(hns.Separator(t) ~= nil, "listen: a lowercase word break found")
    check(type(code) == "string" and code:match("^CT1:7:70009:A%d+,B%d+") ~= nil, "listen: a share code for Common on this build")
    check(H.env.CrossTalkListen.code.text == code and H.env.CrossTalkListen.code.shown, "listen: the code is shown to copy")
    -- typing into the code box does not change it
    local box = H.env.CrossTalkListen.code
    box.text = "garbage"; box.scripts.OnTextChanged(box, true)
    check(box.text == code, "listen: the code box is read only")
    -- the filler word, capitalised by position, was never read as a letter
    check(L.outByIndex[0] == nil, "listen: the first word of each probe is never read")
    A.code = code
end

--------------------------------------------------------------------------
-- Ally imports the code and talks
--------------------------------------------------------------------------
do
    A.Hardware(function() A.env.CrossTalkCalibrate.import:Click() end)
    local box = A.env.CrossTalkCode
    check(box.shown and box.mode == "import" and box.edit.focused, "import: the paste box opens with focus")
    box.edit.text = A.code
    A.Hardware(function() box.go:Click() end)
    local t = ans.Table(7)
    check(t and t.count == 20 and t.build == "70009" and t.source == "imported" and not box.shown, "import: Ally has the 20-letter Common table")
    check(A.env.CrossTalkFrame.status.text:find("Common: 20 letters", 1, true), "board: status shows the table")

    -- the board's RIP BOZO, left click: /say. Common has no P or Z: B and S stand in
    local b = A.env.CrossTalkFrame.buttons[1]
    local before = #A.sent
    A.Hardware(function() b:Click("LeftButton") end)
    local sent = A.sent[#A.sent]
    check(#A.sent == before + 1 and sent.chatType == "SAY" and sent.lang == 7, "say: RIP BOZO said in Common")
    local heard = H.LastHeard().text
    local sep = ans.Separator(t)
    check(heard == "R I B " .. sep .. " B O S O", "say: Hordie reads 'R I B " .. sep .. " B O S O' (got '" .. heard .. "')")
    check(A.Printed("they see: |cFFFF6666R I B " .. sep .. " B O S O"), "say: Ally is told what they see")
    check(H.Printed("Ally spelled: |cFFFFFF00RIB BOSO"), "decode: Hordie's chat reads it back as words")
    -- the tooltip previews the same
    b.scripts.OnEnter(b)
    check(A.env.GameTooltip.lines[2] == "They see: R I B " .. sep .. " B O S O", "board: the tooltip previews it")
    -- right click yells
    A.Hardware(function() A.env.CrossTalkFrame.buttons[2]:Click("RightButton") end)
    check(A.sent[#A.sent].chatType == "YELL" and H.LastHeard().text == "G O O D " .. sep .. " L U K K" and H.Printed("Ally spelled: |cFFFFFF00GOOD LUKK"), "yell: GOOD LUCK yelled, C becomes K")
    -- free text with digits and punctuation
    A.Slash("say gg 2 ez!")
    check(H.LastHeard().text == "G G " .. sep .. " T W O " .. sep .. " E S", "say: digits spelled out, punctuation a word break")
    -- anything after /ct is a message
    A.Slash("loser")
    check(H.LastHeard().text == "L O S E R", "say: /ct <text> says it")
    -- Ally's own Alliance friends read Common: nothing to decode for them
    check(not A.Printed("Ally spelled"), "decode: nothing printed for a language you speak")
end

--------------------------------------------------------------------------
-- limits
--------------------------------------------------------------------------
do
    local before = #A.sent
    A.Slash("say " .. string.rep("ABCDEFGHIJ ", 12))
    check(#A.sent == before and A.Printed("too long to send in one message"), "limits: an over-long message is refused, nothing sent")
    -- ordinary scrambled speech is not mistaken for spelling
    check(ans.Despell("Ras ash nud bur hir") == nil and ans.Despell("A B") == nil, "decode: ordinary gibberish and two-word scraps left alone")
    check(ans.Despell("T H A N K n Y O U") == "THANK YOU", "decode: Hermes-style spelling read too")
    -- the board: add and remove phrases
    A.env.CrossTalkFrame.input.text = "  well met  "
    A.Hardware(function() A.env.CrossTalkFrame.add:Click() end)
    check(ans.db.phrases[13] == "WELL MET" and A.env.CrossTalkFrame.buttons[13].shown, "board: a phrase added")
    A.ctrl = true
    A.Hardware(function() A.env.CrossTalkFrame.buttons[13]:Click("LeftButton") end)
    A.ctrl = false
    check(#ans.db.phrases == 12 and not A.env.CrossTalkFrame.buttons[13].shown, "board: ctrl-click removes it")
end

--------------------------------------------------------------------------
-- a new patch, secret chat, a swallowed character, an unstable scrambler
--------------------------------------------------------------------------
do
    server.build = "70100"
    A.Slash("gg")
    check(A.Printed("found on game build 70009 and you are on 70100"), "patch: a table from another build warns after sending")
    A.Slash("status")
    check(A.Printed("not this build"), "patch: status flags it")
    server.build = "70009"

    H.secretChat = true
    local ok = pcall(A.Slash, "gg")
    H.secretChat = false
    check(ok, "secret: a hidden chat line on Hordie's side is skipped without an error")

    -- the last probe holds the backtick, which the server swallows: set aside, not misread
    local probes = ans.Probes()
    local last = #probes
    local hasTick = false
    for _, idx in ipairs(probes[last]) do if ans.POOL[idx] == "`" then hasTick = true end end
    local ignoredBefore = hns.listen.ignored
    A.Slash("probe " .. last)
    check(hasTick and hns.listen.ignored == ignoredBefore + 1 and not hns.listen.seen[last], "listen: a probe that lost a character is set aside")
    -- non-probe chat from the sender is set aside too
    A.Slash("hello")
    check(hns.listen.ignored == ignoredBefore + 2, "listen: ordinary messages from the sender are not read as probes")

    -- a scrambler that changes between messages: the listener says the table may not hold
    seedOffset = 7
    A.Slash("probe 1")
    seedOffset = 0
    check(hns.listen.conflicts > 0 and hns.ListenSummary():find("may not hold", 1, true), "listen: the same character turning into different letters is reported")
end

--------------------------------------------------------------------------
-- the other way round: Hordie's Orcish table, Ally listening
--------------------------------------------------------------------------
do
    H.Slash("stop")
    check(hns.listen == nil, "listen: stopped")
    A.Slash("listen Hordie")
    for i = 1, 5 do H.Hardware(function() hns.SendProbe(i) end) end
    local lang, t, code = ans.ListenResult()
    check(lang == 1 and ans.LetterList(t) == "ADGHIKLMNORTUZ", "orcish: Ally finds every letter Orcish can make (" .. tostring(t and ans.LetterList(t)) .. ")")
    H.Slash("import " .. code)
    check(hns.Table(1) and hns.Table(1).count == 14, "orcish: Hordie imports it")
    H.Slash("say good luck")
    local sep = hns.Separator(hns.Table(1))
    -- Orcish has no C, E or Y: K and I stand in
    check(A.LastHeard().text == "G O O D " .. sep .. " L U K K", "orcish: Ally reads 'G O O D " .. sep .. " L U K K'")
    A.Slash("stop")
    H.Slash("say thank you")
    check(A.Printed("Hordie spelled: |cFFFFFF00THANK IOU"), "orcish: Ally's chat reads Hordie back")
    -- a code for the wrong language warns on import
    A.Slash("import " .. code)
    check(A.Printed("that is a Orcish table and you speak Common"), "import: a code for the other faction's language warns")
    ans.db.tables[1] = nil
end

--------------------------------------------------------------------------
-- share codes
--------------------------------------------------------------------------
do
    local lang, t = ans.ParseShareCode("CT9:7:1:A1:")
    check(lang == nil and tostring(t):find("different CrossTalk version", 1, true), "code: another pool version is refused")
    check(ans.ParseShareCode("hello") == nil, "code: junk refused")
    A.Slash("code")
    local box = A.env.CrossTalkCode
    check(box.mode == "export" and box.edit.text == ans.ShareCode(7, ans.Table(7)) and box.edit.text:match("^CT1:7:"), "code: /ct code shows your table to pass to friends")
    -- a friend of the same faction imports it and gets the same letters
    local F = NewPlayer("Friend", "Alliance", 7)
    F.Slash("import " .. box.edit.text)
    check(F.ns.LetterList(F.ns.Table(7)) == ans.LetterList(ans.Table(7)), "code: a friend's copy has the same table")
    F.Slash("rip bozo")
    local sep = F.ns.Separator(F.ns.Table(7))
    check(H.LastHeard().text == "R I B " .. sep .. " B O S O", "code: and Hordie reads the friend too")
    players.Friend = nil
end

realPrint(("CrossTalk harness: %d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
