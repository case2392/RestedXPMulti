-- Offline simulation harness for RestedXP Party Sync (Lua 5.1).
-- Stubs the WoW API + Ace3 surface the addon uses, loads the real addon
-- files for several simulated players, cross-wires their comms, and runs
-- scenarios. Run:  lua5.1 tests/harness_partysync.lua

local ADDON_DIR = arg[1] or "."

local clock = 0
local timers = {}

local function schedule(delay, fn, period)
    table.insert(timers, {at = clock + delay, fn = fn, period = period})
end

local function advanceTime(dt)
    local target = clock + dt
    while true do
        local best, bestIdx
        for i, t in ipairs(timers) do
            if t.at <= target and (not best or t.at < best.at) then
                best, bestIdx = t, i
            end
        end
        if not best then break end
        clock = best.at
        if best.period then
            best.at = clock + best.period
        else
            table.remove(timers, bestIdx)
        end
        best.fn()
    end
    clock = target
end

local players = {}
local failures = 0

local function check(cond, label)
    if cond then
        print("PASS: " .. label)
    else
        failures = failures + 1
        print("FAIL: " .. label)
    end
end

local function makeFontString()
    local fs = {shown = true, text = ""}
    local noop = function() end
    for _, m in ipairs({
        "SetWidth", "SetJustifyH", "SetWordWrap", "SetNonSpaceWrap",
        "SetMaxLines", "SetFont", "ClearAllPoints", "SetPoint",
        "SetTextColor", "SetHeight"
    }) do fs[m] = noop end
    function fs:Show() self.shown = true end
    function fs:Hide() self.shown = false end
    function fs:SetText(t) self.text = t end
    function fs:GetStringHeight() return 12 end
    return fs
end

local function makeTexture()
    local t = {}
    local noop = function() end
    for _, m in ipairs({"SetPoint", "SetAllPoints", "SetVertexColor",
                        "SetTexCoord", "Show", "Hide", "SetHeight",
                        "SetAlpha"}) do
        t[m] = noop
    end
    function t:SetTexture(tex) self.tex = tex end
    function t:SetColorTexture(r, g, b, a) self.color = {r, g, b, a} end
    return t
end

local function makeFrame(ftype, fname, template)
    local f = {shown = false, checked = false, scripts = {}, ftype = ftype,
               fname = fname, template = template, backdropCalls = 0}
    local noop = function() end
    for _, m in ipairs({
        "SetWidth", "SetHeight", "SetFrameStrata", "SetClampedToScreen",
        "EnableMouse", "SetMovable", "RegisterForDrag",
        "SetBackdropColor", "SetBackdropBorderColor",
        "SetPoint", "StartMoving", "StopMovingOrSizing", "ClearBackdrop",
        "SetScale", "ClearAllPoints", "RegisterEvent", "SetAllPoints"
    }) do f[m] = noop end
    function f:SetScript(k, fn) self.scripts[k] = fn end
    function f:SetBackdrop(b) self.backdropCalls = self.backdropCalls + 1 end
    function f:SetText(t) self.text = t end
    function f:GetPoint() return "CENTER", nil, "CENTER", 0, 0 end
    function f:Show() self.shown = true end
    function f:Hide() self.shown = false end
    function f:IsShown() return self.shown end
    function f:CreateFontString() return makeFontString() end
    function f:CreateTexture() return makeTexture() end
    function f:SetChecked(v) self.checked = v end
    function f:GetChecked() return self.checked end
    return f
end

-- stepLines: guide-source line numbers, one per step this player's parse has
-- idShift: this player's copy of the guide file has that many extra lines
-- before every step (same content, different stepIds), as when a guide is
-- edited without its version bumped
-- the player a name or wire name (the sender other clients see) belongs to
local function findPlayer(n)
    if players[n] then return players[n] end
    for _, other in pairs(players) do
        if other.wire == n then return other end
    end
end

-- opts: wire = the sender name others see (WoW Forever: "First Surname"),
-- surname = UnitName's second return there, savedDB = saved variables kept
-- over a reload, oldTexture = RestedXP's pre-rename GetTexture, eui =
-- "login" (EllesmereUI skin callback fired by the test) or "late" (fired
-- the moment we register, as for a registration after login)
local function makePlayer(name, stepLines, guideVersion, guideKey, idShift, opts)
    opts = opts or {}
    local P = {name = name, sent = {}, printed = {}, popups = {}, fontStrings = {},
               frames = {}, allFrames = {}, stepLines = stepLines, opts = opts,
               wire = opts.wire or name}
    players[name] = P

    local env = {}
    P.env = env
    for _, k in ipairs({
        "string", "table", "math", "pairs", "ipairs", "type", "tostring",
        "tonumber", "select", "unpack", "error", "pcall", "setmetatable",
        "next"
    }) do env[k] = _G[k] end
    env._G = env
    env.print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do
            parts[#parts + 1] = tostring(select(i, ...))
        end
        local line = table.concat(parts, " ")
        table.insert(P.printed, line)
        print("  [" .. name .. "] " .. line)
    end

    env.GetTime = function() return clock end
    env.UnitName = function() return name, opts.surname end
    env.UnitLevel = function() return P.level or 20 end
    -- "short" drops a -Realm suffix, as the game does
    env.Ambiguate = function(s, mode)
        if mode == "short" then return (s:gsub("%-.*$", "")) end
        return s
    end
    env.LE_PARTY_CATEGORY_INSTANCE = 2
    env.IsInGroup = function(cat)
        if cat then return false end
        return P.inGroup
    end
    env.IsInRaid = function() return false end
    -- a name with a -Suffix is found only by its full name, as the game
    -- needs Name-Realm for a cross-realm member
    env.UnitInParty = function(n)
        local other
        for _, o in pairs(players) do
            if o.wire == n or (o.name == n and not o.wire:find("-", 1, true)) then
                other = o
            end
        end
        return other and other.inGroup and P.inGroup
    end
    env.UnitInRaid = function() return nil end
    env.GetRealmName = function() return "TestRealm" end
    env.UnitXP = function() return P.xp or 0 end
    env.UnitXPMax = function() return P.xpMax or 1000 end
    env.GetNumQuestLogEntries = function() return #(P.questLog or {}) end
    env.GetQuestLogTitle = function(i)
        local q = P.questLog[i]
        return q.title, q.level, q.tag, q.header or false, false,
               q.complete or false, 0, q.id
    end
    env.GetQuestTagInfo = function(id)
        for _, q in ipairs(P.questLog or {}) do
            if q.id == id and q.tagID then return q.tagID, q.tagName end
        end
    end
    env.C_Timer = {
        After = function(d, fn) schedule(d, fn) end,
        NewTicker = function(period, fn) schedule(period, fn, period) end
    }
    env.CreateFrame = function(ftype, fname, parent, template)
        local f = makeFrame(ftype, fname, template)
        if fname then P.frames[fname] = f end
        table.insert(P.allFrames, f)
        -- every line the window draws, so a test can read the window
        local orig = f.CreateFontString
        f.CreateFontString = function(self)
            local fs = orig(self)
            table.insert(P.fontStrings, fs)
            return fs
        end
        return f
    end
    P.windowText = function()
        local parts = {}
        for _, fs in ipairs(P.fontStrings) do
            if fs.shown and fs.text ~= "" then table.insert(parts, fs.text) end
        end
        return table.concat(parts, "\n")
    end
    env.BackdropTemplateMixin = {}
    env.UIParent = makeFrame()
    env.SlashCmdList = {}
    -- StaticPopup model, after Blizzard's StaticPopup.lua: P.popups holds
    -- the dialogs on screen; a hide of any kind runs the dialog's OnHide
    env.StaticPopupDialogs = {}
    local function hideDialog(d)
        for i, shown in ipairs(P.popups) do
            if shown == d then
                table.remove(P.popups, i)
                local info = env.StaticPopupDialogs[d.which]
                if info and info.OnHide then info.OnHide(d, d.data) end
                return
            end
        end
    end
    local function copy(t)
        local c = {}
        for i, v in ipairs(t) do c[i] = v end
        return c
    end
    -- the game's own popups on screen (P.gamePopups) share the four
    -- frames StaticPopup1-4 with ours
    P.gamePopups = {}
    P.showCalls = 0
    local function framesUsed() return #P.popups + #P.gamePopups end
    P.gamePopup = function(which)
        if framesUsed() >= 4 then return false end
        table.insert(P.gamePopups, {which = which})
        return true
    end
    env.StaticPopup_ForEachShownDialog = function(fn)
        for _, d in ipairs(copy(P.popups)) do fn(d) end
        for _, d in ipairs(copy(P.gamePopups)) do fn(d) end
    end
    env.StaticPopup_Show = function(which, arg1, arg2, data)
        P.showCalls = P.showCalls + 1
        local info = env.StaticPopupDialogs[which]
        if not info.multiple then
            -- one dialog per kind: a new show replaces the old one
            for _, d in ipairs(copy(P.popups)) do
                if d.which == which then
                    if info.OnCancel then info.OnCancel(d, d.data, "override") end
                    hideDialog(d)
                end
            end
        end
        if framesUsed() >= 4 then
            -- no free frame: refused, OnCancel(nil, data)
            if info.OnCancel then info.OnCancel(nil, data) end
            return nil
        end
        local d = {which = which, data = data, hideOnEscape = info.hideOnEscape}
        table.insert(P.popups, d)
        return d
    end
    env.StaticPopup_FindVisible = function(which, data)
        local info = env.StaticPopupDialogs[which]
        for _, d in ipairs(P.popups) do
            if d.which == which and (not info.multiple or d.data == data) then
                return d
            end
        end
    end
    env.StaticPopup_Hide = function(which, data)
        for _, d in ipairs(copy(P.popups)) do
            if d.which == which and (not data or d.data == data) then
                hideDialog(d)
            end
        end
    end
    -- a click: OnAccept/OnCancel("clicked"), then the hide
    P.answerPopup = function(accept)
        local d = P.popups[1]
        assert(d, name .. " has no pending popup")
        local info = env.StaticPopupDialogs[d.which]
        if accept then
            info.OnAccept(d, d.data)
        else
            info.OnCancel(d, d.data, "clicked")
        end
        hideDialog(d)
    end
    -- Escape, as StaticPopup_EscapePressed: a "clicked" cancel
    P.pressEscape = function()
        local closed = false
        for i = #P.popups, 1, -1 do
            local d = P.popups[i]
            if d.hideOnEscape then
                local info = env.StaticPopupDialogs[d.which]
                if info.OnCancel and not info.noCancelOnEscape then
                    info.OnCancel(d, d.data, "clicked")
                end
                hideDialog(d)
                closed = true
            end
        end
        return closed
    end
    -- another addon's StaticPopup1:Hide(), as RestedXP's set-hearthstone
    -- automation does: no OnCancel, only the frame's OnHide
    P.silentHide = function()
        local d = P.popups[1]
        if d then hideDialog(d) end
    end

    -- fake RestedXP guide; stepIds derive from shared source line numbers,
    -- element text is letter-distinct per line so the digit-masking content
    -- fingerprint still distinguishes different steps
    local GUIDE_ID = 5000
    local guide = {
        key = guideKey or "G1",
        name = "Test Guide",
        version = guideVersion or "3",
        steps = {}
    }
    for i, lineNum in ipairs(stepLines) do
        guide.steps[i] = {
            index = i,
            stepId = GUIDE_ID + lineNum + (idShift or 0),
            elements = {{text = "Do the thing at line " .. lineNum .. " " ..
                             string.rep("z", lineNum % 97)}}
        }
    end
    P.guide = guide
    env.RXPCData = {currentStep = 1}

    local messageBus = {}
    local function FireMessage(msg, ...)
        for _, cb in ipairs(messageBus[msg] or {}) do cb(msg, ...) end
    end
    P.FireMessage = FireMessage

    local RXP = {
        currentGuide = guide,
        colors = {
            background = {0.1, 0, 0, 1},
            textColor = {1, 1, 1},
            font = "Fonts/FRIZQT__.TTF"
        },
        RXPFrame = {backdrop = {edge = {}, guideName = {}}}
    }
    -- RestedXP renamed GetTexture to GetV1Texture in 2026
    if opts.oldTexture then
        RXP.GetTexture = function(n) return "tex/" .. n end
    else
        RXP.GetV1Texture = function(n) return "tex/" .. n end
    end
    P.RXP = RXP
    RXP.SetStep = function(n)
        if n > #guide.steps then return end
        env.RXPCData.currentStep = n
        print("  [" .. name .. "] >> guide advanced to step " .. n ..
                  " (line " .. stepLines[n] .. ")")
        FireMessage("RXP_STEP_ACTIVATED", guide.steps[n], guide)
        if guide.steps[n].autoskip then
            return RXP.SetStep(n + 1) -- RestedXP-style internal skip
        end
    end

    local Multi = {}
    P.Multi = Multi
    function Multi:RegisterComm(prefix, cb) P.commCallback = cb end
    function Multi:RegisterMessage(msg, cb)
        messageBus[msg] = messageBus[msg] or {}
        table.insert(messageBus[msg], cb)
    end
    Multi.RegisterEvent = function(self, event, cb)
        P.events = P.events or {}
        P.events[event] = cb
    end
    local function deepcopy(t)
        local copy = {}
        for k, v in pairs(t) do
            copy[k] = type(v) == "table" and deepcopy(v) or v
        end
        return copy
    end
    function Multi:Serialize(t) return deepcopy(t) end
    function Multi:Deserialize(t) return true, deepcopy(t) end
    function Multi:SendCommMessage(prefix, payload, channel, target)
        if P.silent then return end -- disconnected, still in the party
        table.insert(P.sent, payload)
        if channel == "WHISPER" and P.dropWhispers then return end
        for otherName, other in pairs(players) do
            local isTarget = channel ~= "WHISPER" or otherName == target or
                                 other.wire == target
            if otherName ~= name and isTarget and other.inGroup and
                P.inGroup and other.commCallback then
                local cb = other.commCallback
                schedule(0.1,
                         function() cb(prefix, payload, channel, P.wire) end)
            end
        end
        -- the game hands a party/raid broadcast back to its sender too
        if channel ~= "WHISPER" and P.inGroup and P.commCallback then
            local cb = P.commCallback
            schedule(0.1, function() cb(prefix, payload, channel, P.wire) end)
        end
    end

    env.LibStub = function(lib)
        if lib == "AceAddon-3.0" then
            return {
                NewAddon = function() return Multi end,
                GetAddon = function(_, n)
                    if n == "RXPGuides" then return RXP end
                end
            }
        end
        error("unexpected LibStub: " .. tostring(lib))
    end

    -- EllesmereUI's skin API: S records every call it gets
    if opts.eui then
        P.euiLog = {}
        local S = {apiVersion = 4}
        for _, fn in ipairs({"Panel", "Font", "CloseButton", "Checkbox",
                             "Button", "WhiteButtonLabel", "OnLooksChanged"}) do
            S[fn] = function(obj, ...)
                table.insert(P.euiLog, {fn = fn, obj = obj, args = {...}})
            end
        end
        S.GetAccentColor = function() return 0.05, 0.82, 0.62 end
        S.IsEnabled = function() return true end
        P.euiS = S
        env.EllesmereUI = {
            RegisterSkin = function(n, fn)
                P.euiName, P.euiCallback = n, fn
                if opts.eui == "late" then fn(S) end
                return true
            end
        }
    end

    local ns = {}
    P.ns = ns
    for _, file in ipairs({"Core.lua", "Sync.lua", "Duo.lua", "UI.lua"}) do
        local chunk, err = loadfile(ADDON_DIR .. "/RestedXPMulti/" .. file)
        assert(chunk, err)
        setfenv(chunk, env)
        chunk("RestedXPMulti", ns)
    end

    P.inGroup = true
    if opts.savedDB then env.RestedXPMultiDB = opts.savedDB end
    Multi:OnInitialize()
    Multi:OnEnable()
    return P
end

--------------------------------------------------------------------------

print("=== setup: Alice (extra class step at line 35) + Bob ===")
local A = makePlayer("Alice", {10, 20, 30, 35, 40, 50, 60, 70, 80, 90, 100})
local B = makePlayer("Bob", {10, 20, 30, 40, 50, 60, 70, 80, 90, 100})
A.events["PLAYER_ENTERING_WORLD"]("PLAYER_ENTERING_WORLD")
B.events["PLAYER_ENTERING_WORLD"]("PLAYER_ENTERING_WORLD")
advanceTime(10)
check(#A.popups == 1 and #B.popups == 1, "both got the sync popup")
A.answerPopup(true)
advanceTime(1)
B.answerPopup(true)
advanceTime(1)
check(A.ns.IsSynced("Bob", A.ns.partners["Bob"]), "Alice synced with Bob")
check(B.ns.IsSynced("Alice", B.ns.partners["Alice"]), "Bob synced with Alice")

print("\n=== lockstep: hold then release ===")
A.RXP.SetStep(2)
check(A.env.RXPCData.currentStep == 1, "Alice held on step 1")
advanceTime(1)
check(B.ns.partners["Alice"].done == true, "Bob sees Alice as ready")
B.RXP.SetStep(2)
check(B.env.RXPCData.currentStep == 2, "Bob advances (Alice was ready)")
advanceTime(1)
check(A.env.RXPCData.currentStep == 2, "Alice released to step 2")
check(A.ns.my.done == false, "Alice's ready flag reset on new step")

print("\n=== simultaneous completion: no deadlock ===")
A.RXP.SetStep(3)
B.RXP.SetStep(3)
advanceTime(2)
check(A.env.RXPCData.currentStep == 3 and B.env.RXPCData.currentStep == 3,
      "both advanced together")

print("\n=== class quest: stepId alignment across different parses ===")
-- march to Alice's class step boundary (her step 4 = line 35, Bob lacks it)
B.RXP.SetStep(4) -- Bob tries line 40: Alice not done with line 30 yet
check(B.env.RXPCData.currentStep == 3, "Bob waits at line 30 for Alice")
advanceTime(1)
A.RXP.SetStep(4) -- Alice enters her class step (line 35)
check(A.env.RXPCData.currentStep == 4,
      "Alice entered her class step without waiting")
advanceTime(1)
check(B.env.RXPCData.currentStep == 3,
      "Bob still held while Alice does her class step")
A.RXP.SetStep(5) -- Alice finishes class step -> line 40
advanceTime(1)
check(A.env.RXPCData.currentStep == 5 and B.env.RXPCData.currentStep == 4,
      "both land on line 40 together")
check(A.guide.steps[5].stepId == B.guide.steps[4].stepId,
      "stepIds agree on the shared step")

print("\n=== live step text with objective counts ===")
local aStep = A.guide.steps[A.env.RXPCData.currentStep]
aStep.elements[2] = {text = "Webwood Ichor: 0/7"}
A.ns.RefreshMyProgress()
A.ns.BroadcastState(true)
advanceTime(1)
local function linesHave(p, needle)
    for _, l in ipairs(p.stepLines or {}) do
        if l:find(needle, 1, true) then return true end
    end
    return false
end
check(linesHave(B.ns.partners["Alice"], "Webwood Ichor: 0/7"),
      "Bob sees Alice's live objective count")
aStep.elements[2].text = "Webwood Ichor: 4/7"
A.ns.RefreshMyProgress()
A.ns.BroadcastState(true)
advanceTime(1)
check(linesHave(B.ns.partners["Alice"], "Webwood Ichor: 4/7"),
      "count updates as Alice loots")
aStep.elements[2] = nil
A.ns.RefreshMyProgress()

print("\n=== /rxpm skip button path ===")
A.RXP.SetStep(6)
check(A.env.RXPCData.currentStep == 5, "Alice held again")
A.env.SlashCmdList["RXPMULTI"]("skip")
check(A.env.RXPCData.currentStep == 6, "skip advanced Alice")
advanceTime(1)

print("\n=== auto-skip releases the wait after the delay ===")
A.env.SlashCmdList["RXPMULTI"]("autoskip 10")
A.RXP.SetStep(7)
check(A.ns.pendingStep ~= nil, "Alice held waiting on Bob")
local heldStep = A.env.RXPCData.currentStep
advanceTime(5)
check(A.env.RXPCData.currentStep == heldStep, "still held before the delay")
advanceTime(7)
check(A.env.RXPCData.currentStep == heldStep + 1 and A.ns.pendingStep == nil,
      "auto-skip advanced Alice after ~10s")
A.env.SlashCmdList["RXPMULTI"]("autoskip off")
check(A.ns.db.autoSkip == false, "autoskip off persists")

print("\n=== internal auto-skips are never gated ===")
-- Bob's guide auto-skips line 60 (his step 6); catch up Bob first
B.RXP.SetStep(5)
advanceTime(1)
B.guide.steps[6].autoskip = true
B.RXP.SetStep(6)
check(B.env.RXPCData.currentStep == 7,
      "Bob skipped through the inapplicable step ungated")
check(B.ns.my.done == false, "no false ready flag from the skip")
advanceTime(2)

print("\n=== cross-route content lockstep (different keys/versions) ===")
A.inGroup = false
B.inGroup = false
local Pam = makePlayer("Pam", {10, 20, 30, 40}, "3", "ROUTE-A")
local Quinn = makePlayer("Quinn", {5, 10, 20, 30, 40}, "4", "ROUTE-B")
Pam.events["PLAYER_ENTERING_WORLD"]("PLAYER_ENTERING_WORLD")
Quinn.events["PLAYER_ENTERING_WORLD"]("PLAYER_ENTERING_WORLD")
advanceTime(10)
while #Pam.popups > 0 do Pam.answerPopup(true) end
while #Quinn.popups > 0 do Quinn.answerPopup(true) end
advanceTime(10)
check(not Pam.ns.SameStepContent(Pam.ns.partners["Quinn"]),
      "different content steps do not match")
Pam.RXP.SetStep(2)
check(Pam.env.RXPCData.currentStep == 2,
      "Pam free-runs while Quinn is on a route-only step")
advanceTime(10)
Quinn.RXP.SetStep(2)
Quinn.RXP.SetStep(3) -- Quinn reaches line 20 = Pam's current step
advanceTime(10)
check(Pam.ns.SameStepContent(Pam.ns.partners["Quinn"]),
      "matching step content detected across routes")
Pam.RXP.SetStep(3)
check(Pam.env.RXPCData.currentStep == 2,
      "Pam held on the shared step until Quinn finishes")
advanceTime(1)
Quinn.RXP.SetStep(4)
check(Quinn.env.RXPCData.currentStep == 4, "Quinn advances (Pam was ready)")
advanceTime(2)
check(Pam.env.RXPCData.currentStep == 3, "Pam released to the next step")

print("\n=== partner leaving releases waits ===")
Pam.RXP.SetStep(4)
check(Pam.env.RXPCData.currentStep == 3, "Pam held again")
Quinn.inGroup = false
Pam.events["GROUP_ROSTER_UPDATE"]("GROUP_ROSTER_UPDATE")
advanceTime(9)
check(Pam.env.RXPCData.currentStep == 4, "Pam released after Quinn left")

print("\n=== lock off: never held, sync keeps flowing ===")
Quinn.inGroup = true
Pam.events["GROUP_ROSTER_UPDATE"]("GROUP_ROSTER_UPDATE")
advanceTime(10)
Pam.env.SlashCmdList["RXPMULTI"]("lock off")
-- Quinn is behind Pam; Pam must advance freely anyway
Pam.RXP.SetStep(3)
Pam.RXP.SetStep(4)
check(Pam.env.RXPCData.currentStep == 4,
      "lock off: Pam never held despite Quinn being behind")
-- and visibility sync still updates
Quinn.RXP.SetStep(5)
advanceTime(2)
check(Pam.ns.partners["Quinn"].step == 5,
      "lock off: partner info still syncs")
Pam.env.SlashCmdList["RXPMULTI"]("lock on")

print("\n=== duo layer: XP telemetry per chapter ===")
Pam.xp, Pam.xpMax = 100, 1000
Pam.ns.xpLast, Pam.ns.xpLastMax, Pam.ns.xpLastLevel = 100, 1000, 20
Pam.xp = 400
Pam.ns.OnXPUpdate()
Pam.level, Pam.xp, Pam.xpMax = 21, 50, 1200 -- level-up: 600 left + 50 new
Pam.ns.OnXPUpdate()
Pam.ns.OnDeath()
advanceTime(120) -- ~15 ticks of 8s
local ch = Pam.ns.stats.chapters["Test Guide"]
check(ch and ch.xp == 300 + 650, "XP gained tracked across a level-up (950)")
check(ch and ch.deaths == 1, "death counted")
check(ch and ch.seconds >= 100, "time accrues per chapter")
check(Pam.ns.CurrentXPH() > 0, "XP/hour computed")
advanceTime(10)
check((Quinn.ns.partners["Pam"].xph or 0) > 0, "partner receives XP/hr")

print("\n=== duo layer: group quests the solo route skips ===")
Pam.questLog = {
    {title = "Zone Header", header = true},
    {title = "Solo Errand", level = 22, tag = 0, id = 501},
    {title = "Elite Beast", level = 24, tag = 2, id = 502, tagID = 1,
     tagName = "Group"},
    {title = "Route Elite", level = 23, tag = 2, id = 503, tagID = 1,
     tagName = "Group"},
    {title = "Deadmines", level = 20, tag = 0, id = 504, tagID = 81,
     tagName = "Dungeon", complete = true}
}
-- the route turns in 503 later on; 502 and 504 are off-route bonuses
Pam.guide.steps[4].elements[2] = {tag = "turnin", questId = 503}
Pam.ns.ScanGroupQuests()
local found = {}
for _, q in ipairs(Pam.ns.duoQuests) do found[q.title] = q end
check(found["Elite Beast"] and found["Elite Beast"].kind == "Group",
      "off-route group quest surfaced")
check(found["Deadmines"] and found["Deadmines"].complete,
      "dungeon quest surfaced, flagged ready to turn in")
check(found["Route Elite"] == nil, "group quest the route turns in is not listed")
check(found["Solo Errand"] == nil, "ordinary quests are not listed")
-- Forever's engine has no GetQuestLogTitle: the same log read through C_QuestLog
do
    local env = Pam.env
    local oldN, oldT, oldTag = env.GetNumQuestLogEntries, env.GetQuestLogTitle, env.GetQuestTagInfo
    env.GetNumQuestLogEntries, env.GetQuestLogTitle, env.GetQuestTagInfo = nil, nil, nil
    env.C_QuestLog = {
        GetNumQuestLogEntries = function() return #Pam.questLog, 4 end,
        GetInfo = function(i)
            local q = Pam.questLog[i]
            return {title = q.title, level = q.level or 0, questID = q.id, isHeader = q.header or false, suggestedGroup = q.tag or 0}
        end,
        IsComplete = function(id) for _, q in ipairs(Pam.questLog) do if q.id == id then return q.complete or false end end end,
        GetQuestTagInfo = function(id) for _, q in ipairs(Pam.questLog) do if q.id == id and q.tagID then return {tagID = q.tagID, tagName = q.tagName} end end end
    }
    Pam.ns.ScanGroupQuests()
    local f2 = {}
    for _, q in ipairs(Pam.ns.duoQuests) do f2[q.title] = q end
    check(f2["Elite Beast"] and f2["Elite Beast"].kind == "Group" and f2["Deadmines"] and f2["Deadmines"].complete and f2["Route Elite"] == nil and f2["Solo Errand"] == nil,
          "forever: the party-bonus quests are read through C_QuestLog with the same result")
    env.GetNumQuestLogEntries, env.GetQuestLogTitle, env.GetQuestTagInfo, env.C_QuestLog = oldN, oldT, oldTag, nil
    Pam.ns.ScanGroupQuests()
end
Pam.guide.steps[Pam.env.RXPCData.currentStep].elements[2] = {tag = "xp"}
check(Pam.ns.CurrentStepIsGrind(), "grind step detected")
Pam.ns.UpdateUI()
Pam.env.SlashCmdList["RXPMULTI"]("stats")
Pam.env.SlashCmdList["RXPMULTI"]("duo")
check(true, "party bonus section + stats/duo commands render without error")

print("\n=== same guide, files that differ by a few lines (stepIds off) ===")
-- the report: two players on the very same step, one shown "(behind)" with
-- "(their class/race step - not in your guide)". RestedXP's stepId is the
-- step's line number in the guide file, and Dana's copy has ten lines
-- fewer before every step than Carl's: so each of Dana's ids from step 2
-- on is the id of the step BEFORE it in Carl's guide (the second report:
-- the same step, still "(behind)", by that coincidence)
Pam.inGroup = false
Quinn.inGroup = false
local Carl = makePlayer("Carl", {10, 20, 30, 40, 50}, "7", "TANARIS")
local Dana = makePlayer("Dana", {10, 20, 30, 40, 50}, "7", "TANARIS", -10)
Carl.events["PLAYER_ENTERING_WORLD"]("PLAYER_ENTERING_WORLD")
Dana.events["PLAYER_ENTERING_WORLD"]("PLAYER_ENTERING_WORLD")
advanceTime(10)
while #Carl.popups > 0 do Carl.answerPopup(true) end
while #Dana.popups > 0 do Dana.answerPopup(true) end
advanceTime(10)
local danaAsCarlSees = Carl.ns.partners["Dana"]
check(danaAsCarlSees.stepId ~= Carl.ns.my.stepId,
      "the two copies disagree on the step's id")
local idx, how = Carl.ns.FindMyStep(danaAsCarlSees)
check(idx == 1 and how == "content", "Carl places Dana on his own step 1 by its content")
Carl.ns.UpdateUI()
local text = Carl.windowText()
check(text:find("Dana  -  step 1/5", 1, true) ~= nil and not text:find("(behind)", 1, true) and
      not text:find("(ahead)", 1, true) and not text:find("not in your guide", 1, true),
      "the window shows Dana on the same step, no (behind), no 'not in your guide'")
-- the lock: Carl finishes first and must be released when Dana finishes
Carl.RXP.SetStep(2)
check(Carl.env.RXPCData.currentStep == 1, "Carl held on step 1 (Dana not done)")
advanceTime(1)
Dana.RXP.SetStep(2)
check(Dana.env.RXPCData.currentStep == 2, "Dana advances (Carl was ready)")
advanceTime(2)
check(Carl.env.RXPCData.currentStep == 2, "Carl released when Dana reached the step, ids or no ids")
Carl.ns.UpdateUI()
text = Carl.windowText()
check(text:find("Dana  -  step 2/5", 1, true) ~= nil and not text:find("(behind)", 1, true),
      "still no (behind) once both are on step 2")
-- Dana's step-2 id IS Carl's step-1 id: the content places her, not the id
check(danaAsCarlSees.stepId == Carl.guide.steps[1].stepId, "her id collides with Carl's step 1")
idx, how = Carl.ns.FindMyStep(danaAsCarlSees)
check(idx == 2 and how == "content", "and Carl still places her on step 2 by content")
-- a partner on an older Party Sync sends no fingerprint: the id is used as before
local sigWas = danaAsCarlSees.contentSig
danaAsCarlSees.contentSig = 0
check(Carl.ns.FindMyStep(danaAsCarlSees) == 1, "without a fingerprint the id is all there is")
danaAsCarlSees.contentSig = sigWas
-- Dana ahead for real: the marker says so, by position not by id
Dana.RXP.SetStep(3)
advanceTime(2)
Carl.ns.UpdateUI()
text = Carl.windowText()
check(Dana.env.RXPCData.currentStep == 2 and text:find("Dana  -  step 2/5 |cFF66FF66(ready)", 1, true) ~= nil,
      "Dana finishing ahead reads as (ready), not (ahead) by a stale id")
Carl.RXP.SetStep(3)
advanceTime(2)
check(Carl.env.RXPCData.currentStep == 3 and Dana.env.RXPCData.currentStep == 3, "both on step 3")
Dana.inGroup = false
Carl.inGroup = false
Pam.inGroup = true
Quinn.inGroup = true

print("\n=== slash commands run clean ===")
Pam.env.SlashCmdList["RXPMULTI"]("status")
Pam.env.SlashCmdList["RXPMULTI"]("help")
Pam.env.SlashCmdList["RXPMULTI"]("autoskip banana")
check(true, "status/help/bad-args ran without errors")

--------------------------------------------------------------------------
-- Pairing: the "waiting for their accept" report and its causes
--------------------------------------------------------------------------

local function soloAll()
    for _, P in pairs(players) do P.inGroup = false end
end
local function enter(...)
    for _, P in ipairs({...}) do
        P.events["PLAYER_ENTERING_WORLD"]("PLAYER_ENTERING_WORLD")
    end
    advanceTime(10)
end
local function synced(P, Q)
    local key = Q.wire:gsub("%-.*$", "")
    return P.ns.IsSynced(key, P.ns.partners[key] or {})
end
local function findButton(P, text)
    for _, f in ipairs(P.allFrames) do
        if f.shown and f.text == text then return f end
    end
end
-- a /reload: same name and saved variables, fresh session
local function reload(P)
    P.inGroup = false
    local db = P.env.RestedXPMultiDB
    local opts = {}
    for k, v in pairs(P.opts) do opts[k] = v end
    opts.savedDB = db
    local Q = makePlayer(P.name, P.stepLines, nil, nil, nil, opts)
    Q.events["PLAYER_ENTERING_WORLD"]("PLAYER_ENTERING_WORLD")
    return Q
end

print("\n=== sync popup closed by another addon comes back (RestedXP .home) ===")
soloAll()
local Eve = makePlayer("Eve", {10, 20, 30})
local Finn = makePlayer("Finn", {10, 20, 30})
enter(Eve, Finn)
check(#Eve.popups == 1 and #Finn.popups == 1, "both asked once")
Eve.answerPopup(true)
advanceTime(1)
-- RestedXP's set-hearthstone automation: StaticPopup1:Hide() on CONFIRM_BINDER
Finn.silentHide()
check(#Finn.popups == 0 and not Finn.ns.prompted["Eve"],
      "Finn's popup closed unanswered, and he can be asked again")
Eve.ns.UpdateUI()
local eveText = Eve.windowText()
check(eveText:find("Finn  -  |cFFFFCC00waiting for their accept|r", 1, true) and
          eveText:find("/rxpm sync Eve", 1, true),
      "Eve's window says what Finn has to do")
Finn.ns.UpdateUI()
check(Finn.windowText():find("Eve  -  |cFF66FF66wants to sync with you|r", 1, true) and
          findButton(Finn, "Sync with Eve"),
      "Finn's window: Eve wants to sync, with a Sync button")
advanceTime(30)
check(#Finn.popups == 1, "the popup came back on Eve's next message")
Finn.answerPopup(true)
advanceTime(1)
check(synced(Eve, Finn) and synced(Finn, Eve), "Eve and Finn sync")
check(Eve.frames["$parentTitle"].bg.tex == "tex/rxp-banner",
      "title banner drawn through RestedXP's current GetV1Texture")

print("\n=== the window's Sync button answers the question too ===")
soloAll()
local Gil = makePlayer("Gil", {10, 20, 30}, nil, nil, nil, {oldTexture = true})
local Hana = makePlayer("Hana", {10, 20, 30})
enter(Gil, Hana)
check(Gil.frames["$parentTitle"].bg.tex == "tex/rxp-banner",
      "title banner still drawn on a RestedXP with the old GetTexture name")
Gil.answerPopup(true)
advanceTime(1)
Hana.ns.UpdateUI()
local button = findButton(Hana, "Sync with Gil")
check(button ~= nil, "Hana has a 'Sync with Gil' button")
if button then button.scripts.OnClick(button) end
advanceTime(1)
check(#Hana.popups == 0, "clicking it closed her popup")
check(synced(Gil, Hana) and synced(Hana, Gil), "Gil and Hana sync")
Hana.ns.UpdateUI()
check(not findButton(Hana, "Sync with Gil"), "the button goes once synced")

print("\n=== Escape leaves the popup alone; a lost decline still arrives ===")
soloAll()
local Ida = makePlayer("Ida", {10, 20, 30})
local Jon = makePlayer("Jon", {10, 20, 30})
enter(Ida, Jon)
Ida.answerPopup(true)
advanceTime(1)
check(not Jon.pressEscape() and #Jon.popups == 1 and not Jon.ns.sessionDeclined["Ida"],
      "Escape (closing bags) neither closes nor declines the sync popup")
Jon.dropWhispers = true
Jon.answerPopup(false) -- "Not now", and the DECLINE whisper is lost
Jon.dropWhispers = false
advanceTime(25)
check(Ida.ns.partners["Jon"].theyDeclined,
      "Ida learns of the decline from Jon's broadcasts")
Ida.ns.UpdateUI()
check(Ida.windowText():find("Jon  -  |cFFFF6666declined sync|r", 1, true) ~= nil,
      "Ida's window says declined, not waiting")
local Jon2 = reload(Jon) -- a decline lasts one session
advanceTime(10)
check(#Jon2.popups == 1, "after a reload Jon is asked again")
check(not Ida.ns.partners["Jon"].theyDeclined, "and Ida's window drops 'declined'")
Jon2.answerPopup(true)
advanceTime(1)
check(synced(Ida, Jon2) and synced(Jon2, Ida), "Ida and Jon sync")

print("\n=== three players: one question at a time, each its own ===")
soloAll()
local Kai = makePlayer("Kai", {10, 20, 30})
local Lea = makePlayer("Lea", {10, 20, 30})
local Max = makePlayer("Max", {10, 20, 30})
enter(Kai, Lea, Max)
check(#Kai.popups == 1 and #Lea.popups == 1 and #Max.popups == 1,
      "one sync popup each, not one per partner")
advanceTime(120)
check(#Kai.popups == 1 and #Lea.popups == 1 and #Max.popups == 1,
      "no extra popups while it is up")
local first = Kai.popups[1].data
Kai.answerPopup(true)
advanceTime(1)
check(#Kai.popups == 1 and Kai.popups[1].data ~= first,
      "the next partner's question follows right after")
for _ = 1, 4 do
    for _, P in ipairs({Kai, Lea, Max}) do
        while #P.popups > 0 do P.answerPopup(true) end
    end
    advanceTime(1)
end
check(synced(Kai, Lea) and synced(Kai, Max) and synced(Lea, Max) and
          synced(Lea, Kai) and synced(Max, Kai) and synced(Max, Lea),
      "all three pairs sync")

print("\n=== the partner on screen leaves or goes quiet: the next is asked ===")
for _, how in ipairs({"leaves", "goes quiet"}) do
    soloAll()
    local Kim = makePlayer("Kim", {10, 20, 30})
    local Lou = makePlayer("Lou", {10, 20, 30})
    local Mo = makePlayer("Mo", {10, 20, 30})
    enter(Kim, Lou, Mo)
    local gone = players[Kim.popups[1].data]
    local stays = gone == Lou and Mo or Lou
    if how == "leaves" then
        gone.inGroup = false
        Kim.events["GROUP_ROSTER_UPDATE"]("GROUP_ROSTER_UPDATE")
        advanceTime(2)
    else
        gone.silent = true
        advanceTime(100)
    end
    check(#Kim.popups == 1 and Kim.popups[1].data == stays.name,
          "the partner on screen " .. how .. ": Kim is asked about " .. stays.name .. " instead")
    gone.silent = nil
end

print("\n=== five players: the game's popups still get frames ===")
soloAll()
local five = {}
for _, n in ipairs({"Ann", "Ben", "Cat", "Dan", "Eli"}) do
    table.insert(five, makePlayer(n, {10, 20, 30}))
end
enter(unpack(five))
advanceTime(30)
local oneEach = true
for _, P in ipairs(five) do
    if #P.popups ~= 1 then oneEach = false end
end
check(oneEach, "a full party: one sync popup on each screen")
check(five[1].gamePopup("DEATH") and five[1].gamePopup("RESURRECT") and
          five[1].gamePopup("CONFIRM_SUMMON"),
      "Release Spirit, a resurrection and a summon still get frames")
five[1].gamePopups = {}
for _ = 1, 12 do
    for _, P in ipairs(five) do
        while #P.popups > 0 do P.answerPopup(true) end
    end
    advanceTime(1)
end
local allPairs = true
for _, P in ipairs(five) do
    for _, Q in ipairs(five) do
        if P ~= Q and not synced(P, Q) then allPairs = false end
    end
end
check(allPairs, "answering one by one syncs all ten pairs")

print("\n=== every frame busy: one retry per partner, no pile-up ===")
soloAll()
local Rae = makePlayer("Rae", {10, 20, 30})
local Sol = makePlayer("Sol", {10, 20, 30})
for _, which in ipairs({"A", "B", "C", "D"}) do Sol.gamePopup(which) end
enter(Rae, Sol)
check(#Sol.popups == 0, "no frame free: no sync popup yet")
advanceTime(60)
local timersAt, callsAt = #timers, Sol.showCalls
advanceTime(600)
check(#timers - timersAt <= 2, "pending timers don't grow while the frames stay full")
check(Sol.showCalls - callsAt <= 200, "show attempts stay at the message and retry rate")
Sol.gamePopups = {}
advanceTime(6)
check(#Sol.popups == 1, "a frame frees up: the popup shows within a retry")

print("\n=== partner leaves and rejoins while the popup is up ===")
soloAll()
local Ned = makePlayer("Ned", {10, 20, 30})
local Ola = makePlayer("Ola", {10, 20, 30})
enter(Ned, Ola)
check(#Ola.popups == 1, "Ola asked about Ned")
Ned.inGroup = false
Ola.events["GROUP_ROSTER_UPDATE"]("GROUP_ROSTER_UPDATE")
Ned.inGroup = true
Ola.events["GROUP_ROSTER_UPDATE"]("GROUP_ROSTER_UPDATE")
advanceTime(30)
check(#Ola.popups == 1, "still one popup, not a second copy")

print("\n=== /rxpm sync with a realm suffix or an accented name ===")
soloAll()
local Pia = makePlayer("Pia", {10, 20, 30})
local Elo = makePlayer("\195\137lodie", {10, 20, 30})
local Quo = makePlayer("Quo", {10, 20, 30})
-- the game's case-blind UTF-8 compare (string.lower only folds A-Z)
Quo.env.strcmputf8i = function(a, b)
    local function fold(x) return (x:gsub("\195\137", "\195\169"):lower()) end
    return fold(a) == fold(b) and 0 or 1
end
enter(Pia, Elo, Quo)
Quo.env.SlashCmdList["RXPMULTI"]("sync pia-OtherRealm")
Quo.env.SlashCmdList["RXPMULTI"]("sync \195\169lodie")
check(Quo.ns.db.paired["Pia"] and not Quo.ns.db.paired["Pia-OtherRealm"] and
          not Quo.ns.db.paired["pia-OtherRealm"],
      "'/rxpm sync pia-OtherRealm' stores Pia the way she's filed")
check(Quo.ns.db.paired["\195\137lodie"] and not Quo.ns.db.paired["\195\169lodie"],
      "'/rxpm sync \195\169lodie' finds \195\137lodie")

print("\n=== WoW Forever two-part names ===")
for _, form in ipairs({" ", "-"}) do
    soloAll()
    local Bane = makePlayer("Bane", {10, 20, 30}, nil, nil, nil,
                            {wire = "Bane" .. form .. "Battlehammer",
                             surname = "Battlehammer"})
    local Cora = makePlayer("Cora", {10, 20, 30}, nil, nil, nil,
                            {wire = "Cora" .. form .. "Stonefist",
                             surname = "Stonefist"})
    enter(Bane, Cora)
    local label = form == " " and "'First Surname'" or "'First-Surname'"
    check(Bane.ns.partners[Bane.wire] == nil and Bane.ns.partners["Bane"] == nil,
          label .. ": Bane doesn't list himself as a partner")
    check(#Bane.popups == 1 and #Cora.popups == 1, label .. ": each asked once")
    Bane.answerPopup(true)
    advanceTime(1)
    Bane.ns.UpdateUI()
    check(Bane.windowText():find("/rxpm sync " .. (form == " " and "Bane Battlehammer" or "Bane"), 1, true) ~= nil,
          label .. ": the waiting hint names Bane the way Cora files him")
    Cora.answerPopup(true)
    advanceTime(1)
    check(synced(Bane, Cora) and synced(Cora, Bane), label .. ": they sync")
    Bane.events["GROUP_ROSTER_UPDATE"]("GROUP_ROSTER_UPDATE")
    check(synced(Bane, Cora), label .. ": a roster update keeps Cora (found by her full name)")
end

print("\n=== older clients call OnCancel() bare ===")
do
    local info = Quo.env.StaticPopupDialogs["RXPMULTI_PAIR"]
    check(pcall(info.OnCancel) and pcall(info.OnAccept) and pcall(info.OnHide),
          "OnCancel()/OnAccept()/OnHide() with no arguments raise no error")
end

print("\n=== EllesmereUI skin ===")
local function logged(P, fn, obj)
    for _, c in ipairs(P.euiLog) do
        if c.fn == fn and (obj == nil or c.obj == obj) then return c end
    end
end
local function count(P, fn)
    local n = 0
    for _, c in ipairs(P.euiLog) do if c.fn == fn then n = n + 1 end end
    return n
end
soloAll()
local Uma = makePlayer("Uma", {10, 20, 30}, nil, nil, nil, {eui = "login"})
local umaFrame = Uma.frames["RXPMultiFrame"]
check(Uma.euiName == "RestedXPMulti", "registers with EllesmereUI under its folder name")
check(umaFrame.backdropCalls > 0 and #Uma.euiLog == 0,
      "RestedXP's theme until EllesmereUI calls back")
Uma.euiCallback(Uma.euiS) -- EllesmereUI at PLAYER_LOGIN
local umaTitle = Uma.frames["$parentTitle"]
check(logged(Uma, "Panel", umaFrame) and logged(Uma, "Panel", umaTitle),
      "window and title bar get EllesmereUI panels")
check(umaTitle.bg.tex == nil, "RestedXP's banner is cleared")
do
    local c = logged(Uma, "Panel", umaTitle)
    check(c and not (c.args[1] and c.args[1].noBorder),
          "the title bar keeps a border, so the window's outline runs over it")
end
check(logged(Uma, "CloseButton") and count(Uma, "Checkbox") == 2,
      "close button and both checkboxes skinned")
local skipLogged = false
for _, c in ipairs(Uma.euiLog) do
    if c.fn == "Button" and c.obj.text == "Skip wait" then skipLogged = true end
end
check(skipLogged, "Skip wait button skinned")
check(logged(Uma, "OnLooksChanged") ~= nil, "accent line follows live accent changes")
local backdropsBefore = umaFrame.backdropCalls
Uma.RXP.colors = {background = {0, 0, 1, 1}, textColor = {1, 0, 0}, font = "x.ttf"}
Uma.ns.UpdateUI()
check(umaFrame.backdropCalls == backdropsBefore,
      "a RestedXP theme change doesn't paint over EllesmereUI's look")
local Vic = makePlayer("Vic", {10, 20, 30})
enter(Uma, Vic)
Uma.ns.UpdateUI()
local fonted = {}
for _, c in ipairs(Uma.euiLog) do if c.fn == "Font" then fonted[c.obj] = true end end
local allFonted = true
for _, fs in ipairs(Uma.fontStrings) do
    if not fonted[fs] then allFonted = false end
end
check(allFonted, "every text in the window uses EllesmereUI's font")
local vicButton = findButton(Uma, "Sync with Vic")
check(vicButton and logged(Uma, "Button", vicButton),
      "Sync buttons made later are skinned too")
soloAll()
local Wes = makePlayer("Wes", {10, 20, 30}, nil, nil, nil, {eui = "late"})
check(logged(Wes, "Panel", Wes.frames["RXPMultiFrame"]) ~= nil,
      "callback before the window exists: the window is skinned when made")
do
    local fontedWes = {}
    for _, c in ipairs(Wes.euiLog) do if c.fn == "Font" then fontedWes[c.obj] = true end end
    local all = #Wes.fontStrings > 0
    for _, fs in ipairs(Wes.fontStrings) do
        if not fontedWes[fs] then all = false end
    end
    check(all, "and every line it makes later uses EllesmereUI's font")
end

print(string.format("\n==== %s ====", failures == 0 and "ALL TESTS PASSED" or
                        failures .. " FAILURES"))
os.exit(failures == 0 and 0 or 1)
