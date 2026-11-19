-- Pace's Quality of Life - Edit Mode: each computer's own layout
--
-- Edit Mode's layouts are the account's, kept by the game's servers, and so
-- is which one each character has on: log in on another computer (a laptop)
-- and the character comes up with the layout last picked on the first (the
-- PC). This keeps a layout for this computer and switches every character
-- to it as it logs in here.
--   * This computer: the add-on's saved settings are a file in this
--     computer's own WoW folder (WTF\Account\...\SavedVariables), never sent
--     to the game's servers, so a layout kept there is this computer's.
--     (Copy or sync that folder between computers and they can't be told
--     apart.)
--   * The switch: C_EditMode.SetActiveLayout, then a reload at once. The
--     game applies a layout inside the call that switches it (it fires
--     EDIT_MODE_LAYOUTS_UPDATED from within it: EditModeManager.lua's
--     SelectLayout reads the new layout's name right after calling it), so
--     from an add-on the whole layout - the action bars and frames it places
--     - would be applied as add-on code, which can leave them unable to
--     change in combat for the rest of the session. The reload throws that
--     UI away before anything else happens: the next one applies the layout
--     afresh, as the game's own. So a switch costs one reload, and only when
--     the character's layout isn't this computer's already. (Should the game
--     apply it later instead, outside the call, it is its own and no reload
--     is needed.)
--   * Once per login, a moment after the world is entered and the game has
--     its layouts, and never in combat (it waits for the fight to end). A
--     switch the game didn't take, or that didn't last across its reload,
--     isn't tried again - no reload after reload - until this computer's
--     layout is chosen again (/pqol layout use, or the options page).

local addonName, ns = ...

local M = {}
ns.Layout = M

local SETTLE = 1           -- once the world is entered and the layouts are known, wait this long
local FRESH = 300          -- a switch made longer ago than this isn't the one this reload follows

local entered = false      -- PLAYER_ENTERING_WORLD seen by this UI
local done = false         -- this login's look taken
local soon = false         -- a look scheduled
local hinted = false       -- "another layout is on" said this session

local function Active() return ns.IsOn("layout") end
local function Clock() return time and time() or 0 end
local function InCombat() return InCombatLockdown and InCombatLockdown() and true or false end

local function LayoutType(name, default)
    return Enum and Enum.EditModeLayoutType and Enum.EditModeLayoutType[name] or default
end
local PRESET = LayoutType("Preset", 0)

-- the layouts as the game's own Edit Mode lists them - its presets, then the
-- saved ones, by the index C_EditMode.SetActiveLayout takes - and the index
-- of the one on; nothing until it has them (EditModeManager.lua)
local function List()
    local em = EditModeManagerFrame
    if type(em) ~= "table" then return end
    local info = em.layoutInfo
    if type(info) ~= "table" or type(info.layouts) ~= "table" then return end
    local active = info.activeLayout
    if type(active) ~= "number" or ns.IsSecret(active) then return end
    return info.layouts, active
end

-- the game's own word on which layout is on
local function ActiveNow()
    if not (C_EditMode and C_EditMode.GetLayouts) then return end
    local ok, info = pcall(C_EditMode.GetLayouts)
    local active = ok and type(info) == "table" and info.activeLayout
    if type(active) == "number" and not ns.IsSecret(active) then return active end
end

-- what is kept of a layout: {name =, preset = the preset's number} or
-- {name =, kind = its layout type (account, character)}
local function Record(layout)
    if type(layout) ~= "table" then return end
    local name, kind = layout.layoutName, layout.layoutType
    if type(name) ~= "string" or name == "" or ns.IsSecret(name) or type(kind) ~= "number" then return end
    if kind == PRESET then
        if type(layout.layoutIndex) ~= "number" then return end
        return {name = name, preset = layout.layoutIndex}
    end
    return {name = name, kind = kind}
end

local function Valid(r)
    return type(r) == "table" and type(r.name) == "string" and r.name ~= "" and
               (type(r.preset) == "number" or type(r.kind) == "number")
end

-- this computer's layout, if one is kept
local function Here()
    local r = ns.db and ns.db.layoutHere
    if Valid(r) then return r end
end

-- a switch to it the game didn't take, or that didn't last across its
-- reload: not tried again until the layout is chosen again
local function GaveUp(want)
    local f = ns.db and ns.db.layoutFailed
    return want ~= nil and type(f) == "table" and f.name == want.name
end

local function GiveUp(want, why)
    ns.db.layoutFailed = {name = want.name, at = Clock()}
    ns.Print("Edit Mode: %s - not tried again; pick it in Edit Mode yourself, or |cFFFFCC00/pqol layout use|r with it on to try again at your next login",
             why)
end

-- where a kept layout is in the game's list now: a preset by its number, a
-- saved one by its name (of its own kind first: an account's and a
-- character's layout may share one)
local function Find(list, want)
    if not (list and want) then return end
    if want.preset then
        for i, l in ipairs(list) do
            if type(l) == "table" and l.layoutType == PRESET and l.layoutIndex == want.preset then return i end
        end
        return
    end
    local other
    for i, l in ipairs(list) do
        if type(l) == "table" and l.layoutType ~= PRESET and l.layoutName == want.name then
            if l.layoutType == want.kind then return i end
            other = other or i
        end
    end
    return other
end

local function Label(r)
    if not r then return "none" end
    if r.preset then
        local fmt = type(HUD_EDIT_MODE_PRESET_LAYOUT) == "string" and HUD_EDIT_MODE_PRESET_LAYOUT or "%s (Preset)"
        local ok, text = pcall(string.format, fmt, r.name)
        return ok and text or r.name
    end
    return r.name
end

-- the layout on now
local function Current()
    local list, active = List()
    if list then return Record(list[active]) end
end

local function CanReload() return ReloadUI ~= nil or (C_UI ~= nil and C_UI.Reload ~= nil) end
local function Reload()
    if ReloadUI then ReloadUI() elseif C_UI and C_UI.Reload then C_UI.Reload() end
end

-- Edit Mode open: the player is picking a layout (a reload would throw away
-- what they haven't saved) - left to them
local function EditModeOpen()
    local em = EditModeManagerFrame
    if type(em) ~= "table" or type(em.IsShown) ~= "function" then return false end
    local ok, shown = pcall(em.IsShown, em)
    return ok and shown == true
end

-- the game's own rules: no Edit Mode (a game rule, a new player's first
-- steps) - nothing switched
local function EditModeAllowed()
    if C_GameRules and C_GameRules.IsGameRuleActive and Enum and Enum.GameRule and Enum.GameRule.EditModeDisabled then
        local ok, off = pcall(C_GameRules.IsGameRuleActive, Enum.GameRule.EditModeDisabled)
        if ok and off == true then return false end
    end
    if C_PlayerInfo and C_PlayerInfo.IsPlayerNPERestricted then
        local ok, nope = pcall(C_PlayerInfo.IsPlayerNPERestricted)
        if ok and nope == true then return false end
    end
    return true
end

--------------------------------------------------------------------------
-- at login: switch to this computer's layout
--------------------------------------------------------------------------

local function Look()
    soon = false
    if done or not entered then return end
    local want = Active() and Here()
    if not want or GaveUp(want) then
        -- (switched on, or a layout chosen, later: from the next login)
        done = true
        ns.db.layoutSwitch = nil
        return
    end
    if InCombat() then return end -- (PLAYER_REGEN_ENABLED looks again)
    local list, active = List()
    if not list then return end -- (EDIT_MODE_LAYOUTS_UPDATED looks again)
    done = true
    -- (a switch made just before this reload)
    local pending = ns.db.layoutSwitch
    ns.db.layoutSwitch = nil
    if type(pending) ~= "table" or type(pending.at) ~= "number" or Clock() - pending.at >= FRESH then pending = nil end
    if not EditModeAllowed() or EditModeOpen() then return end
    local i = Find(list, want)
    if not i then
        ns.Print("Edit Mode: this computer's layout, %s, isn't one this character has (renamed or deleted?) - nothing switched; |cFFFFCC00/pqol layout|r",
                 Label(want))
        return
    end
    if i == active then
        if pending then ns.Print("Edit Mode: this computer's layout, %s, is on (switched as you logged in)", Label(want)) end
        return
    end
    if pending then
        GiveUp(want, ("the switch to this computer's layout, %s, didn't last across the reload"):format(Label(want)))
        return
    end
    if not (C_EditMode and C_EditMode.SetActiveLayout) or not CanReload() then return end
    ns.db.layoutSwitch = {name = want.name, at = Clock()}
    local ok, err = pcall(C_EditMode.SetActiveLayout, i)
    local _, applied = List()
    if applied == i then
        -- (applied inside that call, as add-on code: thrown away at once)
        Reload()
        return
    end
    ns.db.layoutSwitch = nil
    if ActiveNow() == i then
        -- (switched, and left to the game to apply as its own)
        ns.Print("Edit Mode: this computer's layout, %s, is on (switched as you logged in)", Label(want))
    elseif not ok then
        error(err, 0)
    else
        GiveUp(want, ("the game didn't take the switch to this computer's layout, %s"):format(Label(want)))
    end
end

local function Soon()
    if soon or done then return end
    soon = true
    C_Timer.After(SETTLE, ns.Guard("layout", Look))
end

local function OnEvent(_, event)
    if event == "PLAYER_ENTERING_WORLD" then entered = true end
    Soon()
end

-- a layout picked in Edit Mode that isn't this computer's: it lasts until
-- logout - say so, once a session (the first time ever, when this computer
-- has none, how to keep it)
local function OnPicked()
    if not Active() then return end
    local cur = Current()
    if not cur then return end
    local want = Here()
    if want then
        local list, active = List()
        if hinted or Find(list, want) == active then return end
        hinted = true
        ns.Print("Edit Mode: %s is on until you log out - this computer switches to %s as you log in (|cFFFFCC00/pqol layout use|r makes %s this computer's)",
                 Label(cur), Label(want), Label(cur))
    elseif not ns.db.layoutHinted then
        ns.db.layoutHinted = true
        ns.Print("Edit Mode: to have this computer switch to %s whenever you log in on it, type |cFFFFCC00/pqol layout use|r", Label(cur))
    end
end

--------------------------------------------------------------------------
-- choosing it
--------------------------------------------------------------------------

-- the layout on now becomes this computer's
function M.UseCurrent()
    local cur = Current()
    if not cur then return "Edit Mode: the game hasn't said which layout is on yet - try again in a moment" end
    ns.db.layoutHere = cur
    ns.db.layoutSwitch, ns.db.layoutFailed = nil, nil
    local wasOff = not Active()
    if wasOff then ns.db.layout = true end
    if ns.RefreshOptions then ns.RefreshOptions() end
    return ("Edit Mode: %s is this computer's layout - every character is switched to it as it logs in here (the UI reloads once when it does)%s"):format(
               Label(cur), wasOff and "; switched on" or "")
end

function M.Forget()
    ns.db.layoutHere = nil
    ns.db.layoutSwitch, ns.db.layoutFailed = nil, nil
    if ns.RefreshOptions then ns.RefreshOptions() end
    return "Edit Mode: this computer's layout forgotten - nothing is switched as you log in"
end

-- the options page's line under the switch
function M.Note()
    local want = Here()
    if want and GaveUp(want) then
        return ("This computer: %s - but the last switch to it didn't take, so it isn't tried again. Pick it in Edit Mode, then press the button to try again."):format(
                   Label(want))
    end
    if want then
        return ("This computer: %s - every character is switched to it as it logs in here (the UI reloads once when it does). The button makes the layout on now this computer's instead."):format(
                   Label(want))
    end
    return "This computer: none yet. Pick its layout in Edit Mode, then press the button: it's switched to whenever you log in on this computer."
end

function M:Init()
    local f = CreateFrame("Frame")
    for _, event in ipairs({"PLAYER_ENTERING_WORLD", "EDIT_MODE_LAYOUTS_UPDATED", "PLAYER_REGEN_ENABLED"}) do
        pcall(f.RegisterEvent, f, event)
    end
    f:SetScript("OnEvent", ns.Guard("layout", OnEvent))
    M.eventFrame = f
    -- (after the game's own: the layout picked in its menu)
    if type(EditModeManagerFrame) == "table" and type(EditModeManagerFrame.SelectLayout) == "function" and hooksecurefunc then
        M.hooked = pcall(hooksecurefunc, EditModeManagerFrame, "SelectLayout", function()
            ns.SafeCall("layout", OnPicked)
        end)
    end
end

function M:Status()
    local want, cur = Here(), Current()
    local now = cur and Label(cur) or "not known yet"
    if not want then
        return ("(this computer: none yet; on now: %s - |cFFFFCC00/pqol layout use|r makes it this computer's)"):format(now)
    end
    return ("(this computer: %s%s; on now: %s; |cFFFFCC00/pqol layout use|r makes the one on now this computer's, |cFFFFCC00/pqol layout forget|r forgets it)"):format(
               Label(want), GaveUp(want) and ", not switched to: the last switch didn't take" or "", now)
end

function M:Command(arg)
    if arg == "use" then
        ns.Print("%s", M.UseCurrent())
        return true
    elseif arg == "forget" then
        ns.Print("%s", M.Forget())
        return true
    end
    return false
end

ns.RegisterFeature("layout",
    "Edit Mode: each computer its own layout - switched to whenever you log in on it (the game keeps one layout for all your computers)",
    M)
