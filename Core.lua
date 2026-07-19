-- RestedXP Multi
-- Companion addon for RestedXP (RXPGuides) that syncs guide progress between
-- party members: shows everyone's current step and can hold you on a step
-- until the whole group has finished it.

local addonName, ns = ...

local AceAddon = LibStub("AceAddon-3.0")
local Multi = AceAddon:NewAddon("RestedXPMulti", "AceEvent-3.0", "AceComm-3.0",
                                "AceSerializer-3.0")
ns.Multi = Multi

ns.VERSION = 1
ns.PREFIX = "RXPMulti"
ns.STALE_SECONDS = 90 -- partner counts as offline after this long without a message
ns.PRUNE_SECONDS = 600 -- partner removed from the window after this long

local defaults = {
    code = "", -- sync code; empty = sync with any party member running the addon
    lock = true, -- hold on each step until synced partners have finished it too
    show = true, -- show the partner window
    pos = nil -- saved window position
}

function Multi:OnInitialize()
    RestedXPMultiDB = RestedXPMultiDB or {}
    for k, v in pairs(defaults) do
        if RestedXPMultiDB[k] == nil then RestedXPMultiDB[k] = v end
    end
    ns.db = RestedXPMultiDB
end

function ns.Print(msg, ...)
    print("|cFF66CCFFRXP Multi:|r " .. string.format(msg, ...))
end

function Multi:OnEnable()
    ns.RXP = AceAddon:GetAddon("RXPGuides", true)
    if not ns.RXP then
        ns.Print("|cFFFF6666RestedXP (RXPGuides) was not found - addon disabled.|r")
        return
    end

    ns.my = {} -- our own guide/step state, broadcast to partners
    ns.partners = {} -- partner name -> last reported state

    ns.InstallStepHook()
    ns.SetupSync()
    ns.SetupUI()
    ns.RefreshMyState()
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
    local step = RXPCData and RXPCData.currentStep or 0
    local total = guide and guide.steps and #guide.steps or 0

    local changed = key ~= my.key or step ~= my.step or total ~= my.total
    if changed then
        -- moving to a new step (or guide) resets our "finished this step" flag
        my.done = false
        ns.lastBlockAnnounced = nil
    end
    my.key, my.guideName, my.step, my.total = key, gname, step, total
    my.level = UnitLevel("player")
    return changed
end

--------------------------------------------------------------------------
-- Step lock: wraps RestedXP's SetStep so the guide can't advance past a
-- step until every synced partner has finished it as well.
--------------------------------------------------------------------------

local origSetStep

function ns.InstallStepHook()
    local RXP = ns.RXP
    if origSetStep or type(RXP.SetStep) ~= "function" then return end
    origSetStep = RXP.SetStep
    RXP.SetStep = function(a1, a2, a3)
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
        return origSetStep(a1, a2, a3)
    end
end

-- Advance without re-checking the lock (used by /rxpm skip and TryRelease)
function ns.AdvanceNow(n)
    if not origSetStep then return end
    ns.pendingStep = nil
    origSetStep(n)
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

    local now = GetTime()
    local anyPartner = false
    local waitingOn
    for name, p in pairs(ns.partners) do
        local fresh = now - (p.lastSeen or 0) < ns.STALE_SECONDS
        if fresh and ns.CodeMatches(p) and p.key ~= "" and p.key == my.key then
            anyPartner = true
            local ready = p.step >= target or
                              (p.step == target - 1 and p.done)
            if not ready then
                waitingOn = waitingOn or {}
                table.insert(waitingOn, name)
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
        ns.Print("step %d done! Waiting for: |cFFFFCC00%s|r (use /rxpm skip to move on anyway)",
                 (RXPCData and RXPCData.currentStep) or (target - 1),
                 table.concat(waitingOn, ", "))
    end
    ns.UpdateUI()
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
    print("  |cFFFFCC00/rxpm code <word>|r - set a sync code (only players with the same code sync)")
    print("  |cFFFFCC00/rxpm code off|r - clear the code (sync with your whole party)")
    print("  |cFFFFCC00/rxpm lock|r - toggle the step lock (wait for partners before advancing)")
    print("  |cFFFFCC00/rxpm skip|r - stop waiting and advance to the next step now")
    print("  |cFFFFCC00/rxpm status|r - print what your partners are doing")
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
    elseif cmd == "code" then
        rest = rest:gsub("%s+", "")
        if rest == "" then
            if ns.db.code ~= "" then
                ns.Print("current sync code: |cFFFFCC00%s|r", ns.db.code)
            else
                ns.Print("no sync code set - syncing with any party member running RXP Multi.")
            end
        elseif rest:lower() == "off" or rest:lower() == "clear" then
            ns.db.code = ""
            ns.Print("sync code cleared - syncing with your whole party.")
            ns.BroadcastState(true)
            ns.TryRelease()
        else
            ns.db.code = rest:lower()
            ns.Print("sync code set to |cFFFFCC00%s|r - have your friend run: /rxpm code %s",
                     ns.db.code, ns.db.code)
            ns.BroadcastState(true)
            ns.TryRelease()
        end
        ns.UpdateUI()
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
        if ns.pendingStep then
            local target = ns.pendingStep
            ns.Print("skipping the wait - advancing to step %d.", target)
            ns.AdvanceNow(target)
            ns.RefreshMyState()
            ns.BroadcastState(true)
            ns.UpdateUI()
        else
            ns.Print("nothing to skip - you aren't waiting on anyone.")
        end
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
             my.done and " |cFF66FF66(done)|r" or "")
    local count = 0
    local now = GetTime()
    for name, p in pairs(ns.partners) do
        count = count + 1
        local note = ""
        if now - (p.lastSeen or 0) >= ns.STALE_SECONDS then
            note = " |cFF888888(offline?)|r"
        elseif not ns.CodeMatches(p) then
            note = " |cFFFF6666(different sync code)|r"
        elseif p.key ~= my.key then
            note = " |cFFFFCC00(different guide)|r"
        elseif p.done then
            note = " |cFF66FF66(done)|r"
        end
        print(string.format("  %s: %s - step %d/%d%s", name,
                            p.guideName ~= "" and p.guideName or "no guide",
                            p.step or 0, p.total or 0, note))
    end
    if count == 0 then
        print("  no partners found yet - both players need RXP Multi and must be in the same party.")
    end
end
