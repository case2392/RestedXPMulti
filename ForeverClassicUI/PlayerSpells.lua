-- Forever Classic UI - the shell of Forever's spell window, shared
--
-- Forever's spellbook and talents live in one retail window,
-- PlayerSpellsFrame, with a tab strip to switch pages. Two parts of this
-- addon dress that window - the spellbook part while the book page is up,
-- the talents part while the talents page is - and they must not fight
-- over it. So the window has one owner at a time: the part whose page is
-- up claims it, and the shell (retail's metal nine-slice, its flat
-- backdrop and streaks, the title, the close and maximise buttons, the tab
-- strip and the portrait) is faded and remembered exactly once, then put
-- back exactly once when the owner lets go. The window is Era's 384x512
-- while it is owned; Blizzard's own sizing of it (on show, on maximise)
-- is undone by a hook for as long as a claim holds, and recorded as the
-- size to go back to when none does.
--
-- The window holds the secure spell buttons, which makes it a protected
-- frame: sizing it is blocked in combat, and reported to the player as an
-- addon fault ("Interface action failed because of an AddOn"). So a size
-- change asked for in combat waits for PLAYER_REGEN_ENABLED.
--
-- UIParent's panel width for the window (SetUIPanelAttribute) is left to
-- Blizzard. Set from addon code it taints the panel's layout attributes,
-- and the secure panel manager, reading them to show the window, then
-- cannot show it in combat at all: the book would not open in a fight.
-- The cost is a gap when a second panel opens beside the book (UIParent
-- reserves retail's width), which is cosmetic.
--
-- Rule as elsewhere: widget calls and hooksecurefunc only, nothing of
-- ours written into Blizzard's tables, and everything remembered.

local addonName, ns = ...

local PSF = {owner = nil, applied = false}
ns.PSF = PSF

PSF.WIDTH, PSF.HEIGHT = 384, 512

local function InCombat()
    return InCombatLockdown and InCombatLockdown()
end

local own = setmetatable({}, {__mode = "k"})
local function Own(region)
    local t = own[region]
    if not t then t = {}; own[region] = t end
    return t
end

local function Fade(frame, on)
    if frame and frame.SetAlpha then frame:SetAlpha(on and 0 or 1) end
end

local function Mouse(frame, on)
    if frame and frame.EnableMouse then frame:EnableMouse(on) end
end

local function Remember(region)
    if not region then return end
    local o = Own(region)
    if o.saved then return end
    local saved = {points = {}}
    if region.GetNumPoints and region.GetPoint then
        for i = 1, region:GetNumPoints() do saved.points[i] = {region:GetPoint(i)} end
    end
    if region.GetSize then saved.width, saved.height = region:GetSize() end
    if region.GetAlpha then saved.alpha = region:GetAlpha() end
    o.saved = saved
end

local function Restore(region)
    local o = region and own[region]
    local saved = o and o.saved
    if not saved then return end
    if region.ClearAllPoints and region.SetPoint then
        region:ClearAllPoints()
        for _, p in ipairs(saved.points) do
            if p[1] then region:SetPoint(p[1], p[2], p[3], p[4], p[5]) end
        end
    end
    if saved.width and region.SetSize then region:SetSize(saved.width, saved.height) end
    if saved.alpha and region.SetAlpha then region:SetAlpha(saved.alpha) end
    o.saved = nil
end

function PSF.Frame()
    local f = _G.PlayerSpellsFrame
    if type(f) == "table" and f.SetSize then return f end
end

local function Portrait(psf)
    local pc = psf.PortraitContainer
    if type(pc) ~= "table" then return nil, nil end
    return pc.portrait, pc.CircleMask
end

-- retail's shell round the page: faded while a claim holds
local function Shell(psf, classic)
    Fade(psf.NineSlice, classic)
    Fade(psf.Bg, classic)
    Fade(psf.TopTileStreaks, classic)
    Fade(psf.CloseButton, classic)
    Mouse(psf.CloseButton, not classic)
    Fade(psf.MaximizeMinimizeButton, classic)
    Mouse(psf.MaximizeMinimizeButton, not classic)
    if psf.MaximizeMinimizeButton then
        Mouse(psf.MaximizeMinimizeButton.MaximizeButton, not classic)
        Mouse(psf.MaximizeMinimizeButton.MinimizeButton, not classic)
    end
    Fade(psf.TabSystem, classic)
    Mouse(psf.TabSystem, not classic)
    Fade(psf.TitleContainer, classic)
    if not classic then
        local portrait, mask = Portrait(psf)
        Restore(portrait)
        Restore(mask)
    end
end

-- where the owner wants Blizzard's portrait: {x, y, size} puts it in
-- Era's corner at that size (the spellbook's book icon), false fades it
-- (the talents page draws the player's own portrait instead)
local function PlacePortrait(psf, where)
    local portrait, mask = Portrait(psf)
    if not portrait then return end
    Remember(portrait)
    Remember(mask)
    if type(where) == "table" then
        portrait:ClearAllPoints()
        portrait:SetPoint("TOPLEFT", psf, "TOPLEFT", where[1], where[2])
        if portrait.SetSize then portrait:SetSize(where[3], where[3]) end
        if portrait.SetAlpha then portrait:SetAlpha(1) end
        if mask and mask.ClearAllPoints then
            mask:ClearAllPoints()
            mask:SetPoint("TOPLEFT", portrait, "TOPLEFT", 0, 0)
            mask:SetPoint("BOTTOMRIGHT", portrait, "BOTTOMRIGHT", 0, 0)
        end
    elseif where == false then
        Fade(portrait, true)
    end
end

-- protected in combat: the size waits for the fight to end
local function Resize(psf, w, h)
    if InCombat() then
        PSF.pendingSize = true
        return false
    end
    PSF.resizing = true
    psf:SetSize(w, h)
    PSF.resizing = nil
    return true
end

-- a size that had to wait: the owner's while a claim holds, Blizzard's
-- otherwise (the one recorded while nobody owned the window)
function PSF.Flush()
    if not PSF.pendingSize then return false end
    PSF.pendingSize = nil
    local psf = PSF.Frame()
    if not psf then return false end
    if PSF.owner then
        return Resize(psf, PSF.WIDTH, PSF.HEIGHT)
    elseif PSF.savedSize and PSF.savedSize[1] then
        return Resize(psf, PSF.savedSize[1], PSF.savedSize[2])
    end
    return false
end

local function Waiter()
    if PSF.waiter or not CreateFrame then return end
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    f:SetScript("OnEvent", function()
        local ok, err = pcall(PSF.Flush)
        if not ok and ns.errors then ns.errors[#ns.errors + 1] = "spell window: " .. tostring(err) end
    end)
    PSF.waiter = f
end

-- Blizzard sizes the window itself (show, maximize/minimize): while a
-- claim holds ours is put back; otherwise the size is the one to restore
local function Hook(psf)
    if PSF.hooked == psf or not hooksecurefunc then return end
    -- Blizzard sizes the window by SetSize on show and by SetWidth when it
    -- minimises and maximises: all three are watched
    local function Sized()
        if PSF.resizing then return end
        local ok, w, h = pcall(psf.GetSize, psf)
        if not ok then return end
        if PSF.owner then
            if w ~= PSF.WIDTH or h ~= PSF.HEIGHT then Resize(psf, PSF.WIDTH, PSF.HEIGHT) end
        else
            PSF.savedSize = {w, h}
        end
    end
    for _, method in ipairs({"SetSize", "SetWidth", "SetHeight"}) do
        if type(psf[method]) == "function" then hooksecurefunc(psf, method, Sized) end
    end
    PSF.hooked = psf
end

-- called by each owner as soon as the window exists: records the retail
-- size once, and installs the size hook and the combat waiter
function PSF.Init(psf)
    psf = psf or PSF.Frame()
    if not psf then return end
    if not PSF.savedSize and psf.GetSize then PSF.savedSize = {psf:GetSize()} end
    Hook(psf)
    Waiter()
end

-- the page named takes the window: Era's size and a faded shell. A
-- second claim (the other page coming up) just changes hands.
function PSF.Claim(name, opts)
    local psf = PSF.Frame()
    if not psf then return false end
    PSF.Init(psf)
    PSF.owner = name
    if not PSF.applied then
        Shell(psf, true)
        PSF.applied = true
    end
    PlacePortrait(psf, opts and opts.portrait)
    Resize(psf, PSF.WIDTH, PSF.HEIGHT)
    return true
end

-- the page named lets go; nothing happens unless it is the owner, so a
-- page that was never the owner (or was superseded) cannot undo the
-- other page's window
function PSF.Release(name)
    if PSF.owner ~= name then return false end
    PSF.owner = nil
    local psf = PSF.Frame()
    if not psf then return true end
    if PSF.applied then
        Shell(psf, false)
        PSF.applied = false
    end
    if PSF.savedSize and PSF.savedSize[1] then Resize(psf, PSF.savedSize[1], PSF.savedSize[2]) end
    return true
end

function PSF.Owner()
    return PSF.owner
end
