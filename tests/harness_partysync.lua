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
    for _, m in ipairs({"SetTexture", "SetPoint", "SetAllPoints",
                        "SetVertexColor", "SetTexCoord", "Show", "Hide"}) do
        t[m] = noop
    end
    return t
end

local function makeFrame()
    local f = {shown = false, checked = false}
    local noop = function() end
    for _, m in ipairs({
        "SetWidth", "SetHeight", "SetFrameStrata", "SetClampedToScreen",
        "EnableMouse", "SetMovable", "RegisterForDrag", "SetScript",
        "SetBackdrop", "SetBackdropColor", "SetBackdropBorderColor",
        "SetPoint", "StartMoving", "StopMovingOrSizing", "ClearBackdrop",
        "SetScale", "SetText", "ClearAllPoints", "RegisterEvent"
    }) do f[m] = noop end
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
local function makePlayer(name, stepLines, guideVersion, guideKey)
    local P = {name = name, sent = {}, printed = {}, popups = {}}
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
    env.UnitName = function() return name end
    env.UnitLevel = function() return P.level or 20 end
    env.Ambiguate = function(s) return s end
    env.LE_PARTY_CATEGORY_INSTANCE = 2
    env.IsInGroup = function(cat)
        if cat then return false end
        return P.inGroup
    end
    env.IsInRaid = function() return false end
    env.UnitInParty = function(n)
        local other = players[n]
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
    env.CreateFrame = function() return makeFrame() end
    env.BackdropTemplateMixin = {}
    env.UIParent = makeFrame()
    env.SlashCmdList = {}
    env.StaticPopupDialogs = {}
    env.StaticPopup_Show = function(which, arg1, arg2, data)
        table.insert(P.popups, {which = which, data = data})
        return {}
    end
    P.answerPopup = function(accept)
        local popup = table.remove(P.popups, 1)
        assert(popup, name .. " has no pending popup")
        local dialog = env.StaticPopupDialogs[popup.which]
        if accept then
            dialog.OnAccept(nil, popup.data)
        else
            dialog.OnCancel(nil, popup.data, "clicked")
        end
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
            stepId = GUIDE_ID + lineNum,
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
        RXPFrame = {backdrop = {edge = {}, guideName = {}}},
        GetTexture = function(n) return "tex/" .. n end
    }
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
        table.insert(P.sent, payload)
        for otherName, other in pairs(players) do
            local isTarget = channel ~= "WHISPER" or otherName == target
            if otherName ~= name and isTarget and other.inGroup and
                P.inGroup and other.commCallback then
                local cb = other.commCallback
                schedule(0.1,
                         function() cb(prefix, payload, channel, name) end)
            end
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

    local ns = {}
    P.ns = ns
    for _, file in ipairs({"Core.lua", "Sync.lua", "Duo.lua", "UI.lua"}) do
        local chunk, err = loadfile(ADDON_DIR .. "/" .. file)
        assert(chunk, err)
        setfenv(chunk, env)
        chunk("RestedXPMulti", ns)
    end

    P.inGroup = true
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
Pam.guide.steps[Pam.env.RXPCData.currentStep].elements[2] = {tag = "xp"}
check(Pam.ns.CurrentStepIsGrind(), "grind step detected")
Pam.ns.UpdateUI()
Pam.env.SlashCmdList["RXPMULTI"]("stats")
Pam.env.SlashCmdList["RXPMULTI"]("duo")
check(true, "party bonus section + stats/duo commands render without error")

print("\n=== slash commands run clean ===")
Pam.env.SlashCmdList["RXPMULTI"]("status")
Pam.env.SlashCmdList["RXPMULTI"]("help")
Pam.env.SlashCmdList["RXPMULTI"]("autoskip banana")
check(true, "status/help/bad-args ran without errors")

print(string.format("\n==== %s ====", failures == 0 and "ALL TESTS PASSED" or
                        failures .. " FAILURES"))
os.exit(failures == 0 and 0 or 1)
