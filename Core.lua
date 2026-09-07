-- RestedXP Party Sync (folder name: RestedXPMulti)
-- Companion addon for RestedXP (RXPGuides) that syncs guide progress between
-- party members: shows everyone's current step and can hold you on a step
-- until the whole group has finished it.

local addonName, ns = ...

local AceAddon = LibStub("AceAddon-3.0")
local Multi = AceAddon:NewAddon("RestedXPMulti", "AceEvent-3.0", "AceComm-3.0",
                                "AceSerializer-3.0")
ns.Multi = Multi

ns.VERSION = 4
ns.PREFIX = "RXPMulti"
ns.STALE_SECONDS = 90 -- partner counts as offline after this long without a message
ns.PRUNE_SECONDS = 600 -- partner removed from the window after this long
ns.INF_STEP = 2147483647 -- "past the last step" sentinel that serializes safely

function Multi:OnInitialize()
    RestedXPMultiDB = RestedXPMultiDB or {}
    local db = RestedXPMultiDB
    db.code = nil -- v1 sync codes replaced by sync prompts
    if db.lock == nil then db.lock = true end
    if db.show == nil then db.show = true end
    db.paired = db.paired or {} -- names we've agreed to sync with (persistent)
    if db.autoSkip == nil then db.autoSkip = false end
    db.autoSkipDelay = db.autoSkipDelay or 60
    ns.db = db
end

function ns.Print(msg, ...)
    print("|cFF66CCFFRXP Party Sync:|r " .. string.format(msg, ...))
end

function Multi:OnEnable()
    ns.RXP = AceAddon:GetAddon("RXPGuides", true)
    if not ns.RXP then
        ns.Print("|cFFFF6666RestedXP (RXPGuides) was not found - addon disabled.|r")
        return
    end

    ns.my = {} -- our own guide/step state, broadcast to partners
    ns.partners = {} -- partner name -> last reported state
    ns.sessionDeclined = {} -- names declined this session (don't re-prompt)
    ns.prompted = {} -- names we've already shown the sync popup for

    ns.InstallStepHook()
    ns.SetupSync()
    ns.SetupUI()
    ns.RefreshMyState()
    ns.RefreshMyProgress()
    ns.UpdateUI()
    ns.Print("loaded. Type |cFFFFCC00/rxpm help|r for commands.")
end

-- Read our current guide + step out of RestedXP. Returns true if it changed.
function ns.RefreshMyState()
    local my = ns.my
    if not my then return end
    local guide = ns.RXP.currentGuide
    local key = guide and guide.key or ""
    local gname = guide and (guide.displayname or guide.name) or ""
    local version = guide and tonumber(guide.version) or 0
    local step = RXPCData and RXPCData.currentStep or 0
    local steps = guide and guide.steps
    local total = steps and #steps or 0
    -- stepId encodes the step's position in the shared guide source, so it's
    -- identical for every class/race even when their step numbering differs
    local stepId = steps and steps[step] and steps[step].stepId or 0
    local nextStepId = steps and
                           (steps[step + 1] and steps[step + 1].stepId or
                               ns.INF_STEP) or 0

    local changed = key ~= my.key or step ~= my.step or total ~= my.total or
                        stepId ~= my.stepId
    if changed then
        -- moving to a new step (or guide) resets our "finished this step" flag
        my.done = false
        ns.lastBlockAnnounced = nil
    end
    my.key, my.guideName, my.version = key, gname, version
    my.step, my.total = step, total
    my.stepId, my.nextStepId = stepId, nextStepId
    -- RestedXP tags dungeon-route steps; partners use this to explain
    -- route divergence precisely
    local stepTable = steps and steps[step]
    my.dungeonTag = stepTable and stepTable.dungeon or nil
    my.level = UnitLevel("player")
    return changed
end

-- Are we actively syncing with this partner? (both sides accepted the prompt)
function ns.IsSynced(name, p)
    return (ns.db.paired[name] and p.pairedBack) and true or false
end

-- Partner on a differently-compiled route but the same step content as us?
function ns.SameStepContent(p)
    local mySig = ns.my and ns.my.contentSig
    return mySig and mySig ~= 0 and p.contentSig == mySig
end

-- Snapshot the live text lines of our current step, exactly as RestedXP
-- renders them (quest objectives keep their running "3/7" counts because
-- RestedXP rewrites element.text in place as you play). These are broadcast
-- so partners see our real progress - including steps their own guide
-- doesn't contain, like class quests.
local MAX_LINES = 6
local MAX_LINE_LEN = 90

-- cheap stable string hash (djb2), exact within Lua doubles
local function HashString(s)
    local h = 5381
    for i = 1, #s do h = (h * 33 + s:byte(i)) % 4294967296 end
    return h
end

function ns.CollectMyStepLines()
    local guide = ns.RXP.currentGuide
    local stepIdx = RXPCData and RXPCData.currentStep
    local step = guide and guide.steps and stepIdx and guide.steps[stepIdx]
    local lines, sig = {}, ""
    -- content fingerprint: step text with numbers masked (progress counts
    -- change as you play) plus quest ids - identical for the same step even
    -- across differently-compiled guide routes
    local content = {}
    if step then
        -- RestedXP keeps a step's tasks in step.elements
        for _, element in ipairs(step.elements or step) do
            if type(element.text) == "string" then
                local norm = element.text:gsub("|T.-|t", "")
                                 :gsub("|A.-|a", "")
                                 :gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
                                 :gsub("%d+", "#"):gsub("%s+", " ")
                table.insert(content, norm)
            end
            if element.questId then
                table.insert(content, "q" .. tostring(element.questId))
            end
        end
        for _, element in ipairs(step.elements or step) do
            if #lines >= MAX_LINES then break end
            local text = element.text
            if type(text) == "string" then
                -- strip texture/atlas markup; keep color codes
                text = text:gsub("|T.-|t", ""):gsub("|A.-|a", "")
                for line in text:gmatch("[^\n]+") do
                    line = line:gsub("^%s+", ""):gsub("%s+$", "")
                    if line ~= "" and line ~= " " and #lines < MAX_LINES then
                        if #line > MAX_LINE_LEN then
                            line = line:sub(1, MAX_LINE_LEN - 3):gsub(
                                       "|c?%x*$", "") .. "...|r"
                        end
                        local bullet = element.completed and "|cFF55EE55-|r " or
                                           "- "
                        table.insert(lines, bullet .. line)
                    end
                end
            end
        end
    end
    for _, l in ipairs(lines) do sig = sig .. l .. "\001" end
    local contentSig = #content > 0 and
                           HashString(table.concat(content, ";")) or 0
    return lines, sig, contentSig
end

-- Returns true when our step's visible text (objective counts etc.) changed.
function ns.RefreshMyProgress()
    local my = ns.my
    if not my then return end
    local lines, sig, contentSig = ns.CollectMyStepLines()
    if sig ~= my.stepSig or contentSig ~= my.contentSig then
        my.stepSig = sig
        my.stepLines = lines
        my.contentSig = contentSig
        return true
    end
end

-- Find which of MY steps corresponds to a partner's stepId (nil if my guide
-- doesn't contain that step - e.g. it's their class quest)
function ns.FindMyStepByStepId(stepId)
    local guide = ns.RXP and ns.RXP.currentGuide
    if not (guide and guide.steps) or not stepId or stepId == 0 then return end
    for i, s in ipairs(guide.steps) do
        if s.stepId == stepId then return i end
        if s.stepId and s.stepId > stepId then return nil end
    end
end

--------------------------------------------------------------------------
-- Step lock: wraps RestedXP's SetStep so the guide can't advance past a
-- step until every synced partner has finished it as well.
--------------------------------------------------------------------------

local origSetStep
local setStepDepth = 0

local function CallOrigSetStep(a1, a2, a3)
    setStepDepth = setStepDepth + 1
    local ok, result = pcall(origSetStep, a1, a2, a3)
    setStepDepth = setStepDepth - 1
    if not ok then error(result) end
    return result
end

function ns.InstallStepHook()
    local RXP = ns.RXP
    if origSetStep or type(RXP.SetStep) ~= "function" then return end
    origSetStep = RXP.SetStep
    RXP.SetStep = function(a1, a2, a3)
        -- nested calls are RestedXP's own internal routing: sticky hops and
        -- skipping over steps that don't apply (already done, level-locked).
        -- Those are not step completions - never gate them, and never let
        -- them mark our current step as "done". Only genuine top-level
        -- advances are gated.
        if setStepDepth > 0 then return origSetStep(a1, a2, a3) end
        local n = a1
        if type(n) == "table" then n = a2 end
        if type(n) == "number" then
            local blocked, waitingOn = ns.ShouldBlock(n)
            if blocked then
                ns.OnBlocked(n, waitingOn)
                return
            end
            -- keep a pending advance alive across same-step refreshes,
            -- clear it as soon as the guide genuinely moves
            if ns.pendingStep and RXPCData and n ~= RXPCData.currentStep then
                ns.pendingStep = nil
            end
        end
        return CallOrigSetStep(a1, a2, a3)
    end
end

-- Advance without re-checking the lock (used by /rxpm skip and TryRelease)
function ns.AdvanceNow(n)
    if not origSetStep then return end
    ns.pendingStep = nil
    ns.autoSkipArmed = nil
    CallOrigSetStep(n)
end

-- Auto-skip: when enabled, a held wait releases itself after the delay
function ns.ArmAutoSkip(target)
    if not (ns.db and ns.db.autoSkip) or not target then return end
    if ns.autoSkipArmed == target then return end
    ns.autoSkipArmed = target
    local delay = ns.db.autoSkipDelay or 60
    ns.autoSkipAt = GetTime() + delay
    C_Timer.After(delay, function()
        if ns.db and ns.db.autoSkip and ns.pendingStep and
            ns.pendingStep == target and ns.autoSkipArmed == target then
            ns.autoSkipArmed = nil
            ns.Print("auto-skipping the wait (%ds passed).", delay)
            ns.SkipWait()
        end
    end)
end

-- Is this partner far enough along for us to start step `targetIdx`?
-- Compared in stepId space (position in the shared guide source), so players
-- of different classes - whose guides omit each other's class steps - still
-- line up correctly: everyone waits while one player does a step the others
-- don't have, then advances together.
local function PartnerReady(p, targetIdx, targetId)
    if targetId and (p.stepId or 0) > 0 then
        return p.stepId >= targetId or
                   (p.done and (p.nextStepId or 0) >= targetId)
    end
    -- partner running an older RXP Multi: fall back to raw step numbers
    return p.step >= targetIdx or (p.step == targetIdx - 1 and p.done)
end

-- Should moving to step `target` be blocked? Returns blocked, {names...}
function ns.ShouldBlock(target)
    local db, my = ns.db, ns.my
    if not db.lock or not my then return false end
    if not IsInGroup() then return false end
    local guide = ns.RXP.currentGuide
    if not guide or not RXPCData then return false end

    local current = RXPCData.currentStep or 0
    if target <= current then return false end

    -- sticky steps auto-forward as part of RestedXP's own bookkeeping;
    -- gating them can wedge the guide, so let those hops through
    local prev = guide.steps and guide.steps[target - 1]
    if prev and prev.sticky then return false end

    local targetId = guide.steps and guide.steps[target] and
                         guide.steps[target].stepId

    local now = GetTime()
    local anyPartner = false
    local waitingOn
    for name, p in pairs(ns.partners) do
        local fresh = now - (p.lastSeen or 0) < ns.STALE_SECONDS
        if fresh and ns.IsSynced(name, p) then
            local eligible, ready
            if p.key ~= "" and p.key == my.key and
                (p.gv or 0) == (my.version or 0) then
                -- same guide, same revision: full positional lockstep
                eligible = true
                ready = PartnerReady(p, target, targetId)
            elseif ns.SameStepContent(p) then
                -- different guide/route, but the step CONTENT matches ours:
                -- demonstrably the same step, so hold until they finish it
                eligible = true
                ready = p.done
            end
            if eligible then
                anyPartner = true
                if not ready then
                    waitingOn = waitingOn or {}
                    table.insert(waitingOn, name)
                end
            end
        end
    end

    if not anyPartner or not waitingOn then return false end
    return true, waitingOn
end

function ns.OnBlocked(target, waitingOn)
    local my = ns.my
    ns.pendingStep = target
    if not my.done then
        -- the guide tried to advance, so our current step is finished:
        -- tell the group immediately so nobody waits on us
        my.done = true
        ns.BroadcastState(true)
    end
    if ns.lastBlockAnnounced ~= target then
        ns.lastBlockAnnounced = target
        ns.Print("finished with step %d! Waiting for: |cFFFFCC00%s|r (use /rxpm skip to move on anyway)",
                 (RXPCData and RXPCData.currentStep) or (target - 1),
                 table.concat(waitingOn, ", "))
    end
    ns.ArmAutoSkip(target)
    ns.UpdateUI()
end

-- Stop waiting on partners and advance now (slash command + window button)
function ns.SkipWait()
    if not ns.pendingStep then return end
    local target = ns.pendingStep
    ns.Print("skipping the wait - advancing to step %d.", target)
    ns.AdvanceNow(target)
    ns.RefreshMyState()
    ns.BroadcastState(true)
    ns.UpdateUI()
    return true
end

-- Called whenever partner state changes; advances if the block has cleared.
function ns.TryRelease()
    local pending = ns.pendingStep
    if not pending then return end
    if not ns.ShouldBlock(pending) then
        ns.Print("everyone is ready - moving on!")
        ns.AdvanceNow(pending)
        ns.RefreshMyState()
        ns.BroadcastState(true)
        ns.UpdateUI()
    end
end

--------------------------------------------------------------------------
-- Slash commands
--------------------------------------------------------------------------

local function ShowHelp()
    ns.Print("commands:")
    print("  |cFFFFCC00/rxpm|r - show/hide the partner window")
    print("  |cFFFFCC00/rxpm sync|r - offer to sync with everyone detected (also happens automatically)")
    print("  |cFFFFCC00/rxpm sync <name>|r - offer to sync with a specific player")
    print("  |cFFFFCC00/rxpm unsync <name>|r - stop syncing with a player (no name = everyone)")
    print("  |cFFFFCC00/rxpm lock|r - toggle the step lock (wait for partners before advancing)")
    print("  |cFFFFCC00/rxpm skip|r - stop waiting and advance to the next step now")
    print("  |cFFFFCC00/rxpm autoskip on|off|<seconds>|r - release held waits automatically (default 60s)")
    print("  |cFFFFCC00/rxpm status|r - print what your partners are doing")
end

-- case-insensitive match against detected partners
local function ResolveName(input)
    for name in pairs(ns.partners) do
        if name:lower() == input:lower() then return name end
    end
    for name in pairs(ns.db.paired) do
        if name:lower() == input:lower() then return name end
    end
    return input:sub(1, 1):upper() .. input:sub(2)
end

SLASH_RXPMULTI1 = "/rxpm"
SLASH_RXPMULTI2 = "/rxpmulti"
SlashCmdList["RXPMULTI"] = function(input)
    if not ns.db then return end
    input = (input or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local cmd, rest = input:match("^(%S*)%s*(.-)$")
    cmd = cmd:lower()

    if cmd == "" or cmd == "show" or cmd == "hide" then
        ns.ToggleUI(cmd)
    elseif cmd == "sync" then
        rest = rest:gsub("%s+", "")
        if rest ~= "" then
            ns.AcceptPair(ResolveName(rest))
        else
            local offered = 0
            for name in pairs(ns.partners) do
                if not ns.db.paired[name] then
                    offered = offered + 1
                    ns.AcceptPair(name)
                end
            end
            if offered == 0 then
                ns.Print("nobody new to sync with - partners appear here once they're in your party with the addon installed.")
            end
        end
    elseif cmd == "unsync" then
        rest = rest:gsub("%s+", "")
        if rest ~= "" then
            ns.Unpair(ResolveName(rest))
        else
            local had = false
            for name in pairs(ns.db.paired) do
                had = true
                ns.Unpair(name)
            end
            if not had then ns.Print("you aren't synced with anyone.") end
        end
    elseif cmd == "lock" then
        local arg = rest:lower()
        if arg == "on" then
            ns.db.lock = true
        elseif arg == "off" then
            ns.db.lock = false
        else
            ns.db.lock = not ns.db.lock
        end
        if ns.db.lock then
            ns.Print("step lock |cFF66FF66ON|r - the guide will wait for your partners on each step.")
        else
            ns.Print("step lock |cFFFF6666OFF|r - the guide will advance normally.")
            ns.TryRelease()
        end
        ns.UpdateUI()
    elseif cmd == "skip" then
        if not ns.SkipWait() then
            ns.Print("nothing to skip - you aren't waiting on anyone.")
        end
    elseif cmd == "autoskip" then
        local arg = rest:gsub("%s+", ""):lower()
        local secs = tonumber(arg)
        if arg == "off" then
            ns.db.autoSkip = false
            ns.autoSkipArmed = nil
            ns.Print("auto-skip |cFFFF6666OFF|r - waits hold until released or skipped.")
        elseif secs and secs >= 5 then
            ns.db.autoSkip = true
            ns.db.autoSkipDelay = math.floor(secs)
            ns.Print("auto-skip |cFF66FF66ON|r - waits release after %ds.",
                     ns.db.autoSkipDelay)
            ns.ArmAutoSkip(ns.pendingStep)
        elseif arg == "on" or arg == "" then
            ns.db.autoSkip = true
            ns.Print("auto-skip |cFF66FF66ON|r - waits release after %ds.",
                     ns.db.autoSkipDelay or 60)
            ns.ArmAutoSkip(ns.pendingStep)
        else
            ns.Print("usage: /rxpm autoskip on | off | <seconds>")
        end
        ns.UpdateUI()
    elseif cmd == "status" then
        ns.PrintStatus()
    else
        ShowHelp()
    end
end

function ns.PrintStatus()
    local my = ns.my
    if not my then return end
    ns.Print("you: %s - step %d/%d%s", my.guideName ~= "" and my.guideName or
                 "no guide", my.step or 0, my.total or 0,
             my.done and " |cFF66FF66(ready)|r" or "")
    local count = 0
    local now = GetTime()
    for name, p in pairs(ns.partners) do
        count = count + 1
        local note = ""
        if now - (p.lastSeen or 0) >= ns.STALE_SECONDS then
            note = " |cFF888888(offline?)|r"
        elseif not ns.IsSynced(name, p) then
            if p.theyDeclined then
                note = " |cFFFF6666(declined sync)|r"
            elseif ns.db.paired[name] then
                note = " |cFFFFCC00(waiting for them to accept)|r"
            else
                note = " |cFF888888(not synced - /rxpm sync " .. name .. ")|r"
            end
        elseif p.key ~= my.key then
            note = " |cFFFFCC00(different guide)|r"
        elseif (p.gv or 0) ~= (my.version or 0) then
            note = " |cFFFFCC00(different guide version)|r"
        elseif p.done then
            note = " |cFF66FF66(ready)|r"
        end
        print(string.format("  %s: %s - step %d/%d%s", name,
                            p.guideName ~= "" and p.guideName or "no guide",
                            p.step or 0, p.total or 0, note))
    end
    if count == 0 then
        print("  no partners found yet - both players need this addon and must be in the same party.")
    end
end
