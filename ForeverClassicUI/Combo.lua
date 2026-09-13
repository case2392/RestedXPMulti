-- Forever Classic UI - combo points
--
-- Classic draws combo points as five red dots arcing down the right side of
-- the target frame (Interface\ComboFrame\ComboPoint, with a highlight that
-- fades in and a quick shine per point). Retail-style clients replace that
-- with a bar of charged/uncharged pips under the player frame
-- (RogueComboPointBarFrame / DruidComboPointBarFrame) and only keep the old
-- target-frame version behind a CVar.
--
-- We draw our own copy of the classic frame (same art, same offsets, same
-- fade/shine timings) and tuck the modern bars away. Classic clients that
-- still draw the original are left alone.

local addonName, ns = ...

local M = {mode = "off"}

local TEXTURE = "Interface\\ComboFrame\\ComboPoint"
local POWER_COMBO = (Enum and Enum.PowerType and Enum.PowerType.ComboPoints) or 4
local MAX_POINTS = 5

-- ComboFrame.xml: classic target frame vs the retail-style one
local ANCHOR_CLASSIC = {x = -26, y = -13}
local ANCHOR_MODERN = {x = -44, y = -9}
local POINT_OFFSETS = {
    {0, 0}, {7, -8}, {12, -18}, {14, -29}, {13, -40}
}

local FADE_IN, HIGHLIGHT_FADE_IN, SHINE_FADE_IN, SHINE_FADE_OUT = 0.3, 0.4,
                                                                  0.3, 0.4

local hiddenParent
local pendingKills = {}
local lastPoints = 0

--------------------------------------------------------------------------
-- helpers
--------------------------------------------------------------------------

local function CurrentPoints()
    if GetComboPoints then return GetComboPoints("player", "target") or 0 end
    if UnitPower then return UnitPower("player", POWER_COMBO) or 0 end
    return 0
end

local function MaxPoints()
    local max = UnitPowerMax and UnitPowerMax("player", POWER_COMBO)
    if not max or max < 1 then max = MAX_POINTS end
    return math.min(max, MAX_POINTS)
end

local function Fade(region, mode, time, finished, arg)
    if UIFrameFade then
        UIFrameFade(region, {
            mode = mode, timeToFade = time, finishedFunc = finished,
            finishedArg1 = arg
        })
    else
        region:SetAlpha(mode == "IN" and 1 or 0)
        if finished then finished(arg) end
    end
end

local function ShineOut(shine) Fade(shine, "OUT", SHINE_FADE_OUT) end
local function ShineIn(shine) Fade(shine, "IN", SHINE_FADE_IN, ShineOut, shine) end

-- park a Blizzard frame where it can never show again (out of combat only:
-- unit frame children are protected)
local function Kill(frame)
    if not frame then return end
    if InCombatLockdown and InCombatLockdown() then
        pendingKills[#pendingKills + 1] = frame
        return
    end
    if not hiddenParent and CreateFrame then
        hiddenParent = CreateFrame("Frame")
        hiddenParent:Hide()
    end
    if frame.UnregisterAllEvents then pcall(frame.UnregisterAllEvents, frame) end
    if frame.Hide then pcall(frame.Hide, frame) end
    if hiddenParent and frame.SetParent then
        pcall(frame.SetParent, frame, hiddenParent)
    end
    frame.classicUIKilled = true
end

--------------------------------------------------------------------------
-- our frame
--------------------------------------------------------------------------

local function MakePoint(parent, index)
    local point = CreateFrame("Frame", nil, parent)
    point:SetSize(12, 12)
    local base = point:CreateTexture(nil, "BACKGROUND")
    base:SetTexture(TEXTURE)
    base:SetSize(12, 16)
    base:SetPoint("TOPLEFT", point, "TOPLEFT", 0, 0)
    base:SetTexCoord(0, 0.375, 0, 1)
    local highlight = point:CreateTexture(nil, "ARTWORK")
    highlight:SetTexture(TEXTURE)
    highlight:SetSize(8, 16)
    highlight:SetPoint("TOPLEFT", point, "TOPLEFT", 2, 0)
    highlight:SetTexCoord(0.375, 0.5625, 0, 1)
    highlight:SetAlpha(0)
    local shine = point:CreateTexture(nil, "OVERLAY")
    shine:SetTexture(TEXTURE)
    shine:SetSize(14, 16)
    shine:SetPoint("TOPLEFT", point, "TOPLEFT", 0, 4)
    shine:SetTexCoord(0.5625, 1, 0, 1)
    shine:SetAlpha(0)
    if shine.SetBlendMode then shine:SetBlendMode("ADD") end
    point.Highlight, point.Shine = highlight, shine
    local off = POINT_OFFSETS[index]
    point:SetPoint("TOPRIGHT", parent, "TOPRIGHT", off[1], off[2])
    return point
end

function M.Anchor()
    local f = M.frame
    if not f or not TargetFrame then return end
    local a = (TargetFrame.TargetFrameContainer and ANCHOR_MODERN) or
                  ANCHOR_CLASSIC
    local off = (ns.db and ns.db.comboOffset) or {x = 0, y = 0}
    f:ClearAllPoints()
    f:SetPoint("TOPRIGHT", TargetFrame, "TOPRIGHT", a.x + (off.x or 0),
               a.y + (off.y or 0))
end

function M.Update()
    local f = M.frame
    if not f then return end
    local points = CurrentPoints()
    if points > 0 then
        if not f:IsShown() then
            f:Show()
            if UIFrameFadeIn then
                UIFrameFadeIn(f, FADE_IN)
            else
                f:SetAlpha(1)
            end
        end
        local max = MaxPoints()
        for i = 1, MAX_POINTS do
            local p = f.points[i]
            if i <= max then
                p:Show()
                if i <= points then
                    if i > lastPoints then
                        Fade(p.Highlight, "IN", HIGHLIGHT_FADE_IN, ShineIn,
                             p.Shine)
                    end
                else
                    p.Highlight:SetAlpha(0)
                    p.Shine:SetAlpha(0)
                end
            else
                p:Hide()
            end
        end
    else
        for i = 1, MAX_POINTS do
            f.points[i].Highlight:SetAlpha(0)
            f.points[i].Shine:SetAlpha(0)
        end
        f:Hide()
    end
    lastPoints = points
end

local function Build()
    if M.frame then return M.frame end
    local f = CreateFrame("Frame", "ForeverClassicUIComboFrame", UIParent)
    f:SetSize(256, 32)
    f:SetFrameStrata("MEDIUM")
    f:SetAlpha(0)
    f:Hide()
    f.points = {}
    for i = 1, MAX_POINTS do f.points[i] = MakePoint(f, i) end
    f:RegisterEvent("PLAYER_TARGET_CHANGED")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    if f.RegisterUnitEvent then
        f:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
        f:RegisterUnitEvent("UNIT_MAXPOWER", "player")
    else
        f:RegisterEvent("UNIT_POWER_FREQUENT")
        f:RegisterEvent("UNIT_MAXPOWER")
    end
    f:SetScript("OnEvent", function(self, event, unit)
        if event == "PLAYER_REGEN_ENABLED" then
            local kills = pendingKills
            pendingKills = {}
            for _, frame in ipairs(kills) do Kill(frame) end
            return
        end
        if (event == "UNIT_POWER_FREQUENT" or event == "UNIT_MAXPOWER") and
            unit ~= "player" then return end
        if event == "PLAYER_ENTERING_WORLD" then M.Anchor() end
        M.Update()
    end)
    M.frame = f
    M.Anchor()
    M.Update()
    return f
end

local function ModernBars()
    return {RogueComboPointBarFrame, DruidComboPointBarFrame}
end

local function IsNative()
    -- a Classic client: Blizzard's own target-frame combo frame, no modern bar
    return ComboFrame ~= nil and RogueComboPointBarFrame == nil
end

local function Activate()
    for _, bar in ipairs(ModernBars()) do Kill(bar) end
    -- retail keeps a copy of the old frame too; never show two sets of dots
    if ComboFrame then Kill(ComboFrame) end
    Build()
end

--------------------------------------------------------------------------
-- module interface
--------------------------------------------------------------------------

function M:Enable()
    if not TargetFrame then
        M.mode = "unavailable"
        ns.Print("combo: no TargetFrame on this client. Run /cui probe and send me the report.")
        return
    end
    if IsNative() then
        M.mode = "native"
        return
    end
    Activate()
    M.mode = "restyled"
end

-- testing aid: draw ours even on a client that already has the classic frame
function M:Force()
    if not TargetFrame then
        ns.Print("combo: no TargetFrame on this client.")
        return
    end
    Activate()
    M.mode = "restyled"
    ns.Print("combo: classic combo points drawn on the target frame.")
end

function M:Disable()
    if M.frame then
        M.frame:Hide()
        if M.frame.UnregisterAllEvents then M.frame:UnregisterAllEvents() end
    end
    M.mode = "off"
    ns.Print("combo: type /reload to restore Blizzard's combo points.")
end

-- /cui combo offset <x> <y>   nudge the dots (saved)
function M:Command(arg)
    local x, y = arg:match("^offset%s+(-?%d+)%s+(-?%d+)$")
    if x then
        ns.db.comboOffset = {x = tonumber(x), y = tonumber(y)}
        M.Anchor()
        ns.Print("combo: offset set to %s, %s.", x, y)
        return true
    elseif arg == "offset" then
        ns.db.comboOffset = nil
        M.Anchor()
        ns.Print("combo: offset reset.")
        return true
    end
    return false
end

function M:Status()
    if M.mode == "native" then
        return "(client already draws classic combo points)"
    elseif M.mode == "restyled" then
        return "(classic dots on the target frame; /cui combo offset x y to nudge)"
    elseif M.mode == "unavailable" then
        return "(unavailable on this client)"
    end
    return ""
end

ns.RegisterModule("combo", M)
