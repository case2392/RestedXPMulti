-- Forever Classic UI - nameplates
--
-- Blizzard's current nameplate code (shared by Classic Era, retail and WoW
-- Forever's "Camelot" flavor) contains a complete "Classic" style: the old
-- rounded Nameplate-Border art, level in the border, name centered above the
-- bar, the small classic cast bar with its spark. On Classic clients it is
-- exposed as the nameplateStyle CVar (value 6) and shown in Options >
-- Nameplates. Forever (checked on the beta) accepts the CVar too but hides
-- the option, keeps its own level badge next to every plate, and its
-- settings page writes one of its own styles back. Plain retail refuses 6.
--
-- So we try the cheap path first (set the CVar and let Blizzard do the work,
-- hide the badge, guard the CVar), and if the client refuses we hook the
-- nameplate driver and force the classic layout values ourselves - the
-- drawing code for that layout is still there, it just never gets selected.

local addonName, ns = ...

local M = {mode = "off"}

local CLASSIC_STYLE = (Enum and Enum.NamePlateStyle and
                          Enum.NamePlateStyle.Classic) or 6
local MEDIUM_SIZE = (Enum and Enum.NamePlateSize and Enum.NamePlateSize.Medium) or
                        1

local function GetCVarSafe(name)
    if C_CVar and C_CVar.GetCVar then return C_CVar.GetCVar(name) end
    if GetCVar then return GetCVar(name) end
end

local function SetCVarSafe(name, value)
    if C_CVar and C_CVar.SetCVar then return C_CVar.SetCVar(name, value) end
    if SetCVar then return SetCVar(name, value) end
end

--------------------------------------------------------------------------
-- path 1: the built-in classic style
--------------------------------------------------------------------------

-- returns true when the client is now on the classic style
local function TryCVar()
    local current = GetCVarSafe("nameplateStyle")
    if current == nil then return false, "client has no nameplateStyle CVar" end
    if tonumber(current) == CLASSIC_STYLE then return true end
    -- remember what the player had so /cui nameplates off can put it back
    if ns.db and ns.db.savedNameplateStyle == nil then
        ns.db.savedNameplateStyle = tostring(current)
    end
    pcall(SetCVarSafe, "nameplateStyle", CLASSIC_STYLE)
    if tonumber(GetCVarSafe("nameplateStyle")) == CLASSIC_STYLE then
        return true
    end
    return false, ("client refused nameplateStyle=%d (has %s)"):format(
               CLASSIC_STYLE, tostring(GetCVarSafe("nameplateStyle")))
end

--------------------------------------------------------------------------
-- path 2: force the classic layout through Blizzard's option tables
--------------------------------------------------------------------------

local function Const(name, default, altName)
    local v = NamePlateConstants and NamePlateConstants[name]
    if v == nil and altName then v = NamePlateConstants and NamePlateConstants[altName] end
    if v == nil then return default end
    return v
end

-- Forever's nameplates carry a level badge to the right of the health bar
-- (PlayerLevelDiffFrame) on every unit. The classic border has its own level
-- slot, so the badge is switched off per plate while the part is on;
-- UpdateAnchors then lays out without it. Works in both the CVar and the
-- Lua paths - Forever keeps the badge even on its built-in classic style.
local function PatchPlate(namePlateFrameBase)
    local uf = namePlateFrameBase and namePlateFrameBase.UnitFrame
    local badge = uf and uf.PlayerLevelDiffFrame
    if badge and not badge.forevercuiPatched then
        badge.forevercuiPatched = true
        local orig = badge.ShouldDisplay
        badge.ShouldDisplay = function(self, unit)
            if not M.enabled and orig then return orig(self, unit) end
            return false
        end
    end
    if badge and M.enabled and badge.Hide then badge:Hide() end
end

-- patch every plate that exists now and every plate acquired later
local function InstallPlateHooks()
    local driver = NamePlateDriverFrame
    if not driver then return end
    if driver.ForEachNamePlate then
        pcall(driver.ForEachNamePlate, driver, function(frame)
            PatchPlate(frame)
            if frame.UnitFrame and frame.UnitFrame.UpdateAnchors then
                pcall(frame.UnitFrame.UpdateAnchors, frame.UnitFrame)
            end
        end)
    end
    if not M.plateHooked and hooksecurefunc and driver.OnNamePlateAdded then
        M.plateHooked = true
        hooksecurefunc(driver, "OnNamePlateAdded", function(drv, unitToken)
            if not M.enabled then return end
            local frame = drv.GetNamePlateForUnit and drv:GetNamePlateForUnit(unitToken)
            if frame and frame.UnitFrame and frame.UnitFrame.PlayerLevelDiffFrame and
                not frame.UnitFrame.PlayerLevelDiffFrame.forevercuiPatched then
                PatchPlate(frame)
                if frame.UnitFrame.UpdateAnchors then
                    pcall(frame.UnitFrame.UpdateAnchors, frame.UnitFrame)
                end
            end
        end)
    end
end

-- Forever's Options > Nameplates page only lists its own styles; opening it
-- or picking one writes the CVar back. While this part is on, the classic
-- style is put back, with a note the first time.
local function InstallCVarWatcher()
    if M.watcher or not CreateFrame then return end
    M.watcher = CreateFrame("Frame")
    M.watcher:RegisterEvent("CVAR_UPDATE")
    M.watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
    M.watcher:SetScript("OnEvent", function(_, event, name)
        if M.mode ~= "cvar" then return end
        if event == "CVAR_UPDATE" and name ~= "nameplateStyle" then return end
        if tonumber(GetCVarSafe("nameplateStyle")) == CLASSIC_STYLE then return end
        local function reapply()
            if M.mode ~= "cvar" then return end
            pcall(SetCVarSafe, "nameplateStyle", CLASSIC_STYLE)
            InstallPlateHooks()
            if not M.notedReset then
                M.notedReset = true
                ns.Print("nameplates: kept the classic style. Untick 'Classic nameplates' in Options > AddOns > Classic UI for Forever to use Blizzard's styles.")
            end
        end
        if C_Timer and C_Timer.After then C_Timer.After(0, reapply) else reapply() end
    end)
end

local function ClassicScale()
    local size = tonumber(GetCVarSafe("nameplateSize")) or MEDIUM_SIZE
    local scales = NamePlateConstants and
                       NamePlateConstants.NAME_PLATE_SCALES_CLASSIC_STYLE
    local s = scales and (scales[size] or scales[MEDIUM_SIZE])
    return s or {
        horizontal = 1, vertical = 1, classification = 1, aura = 1,
        aggroHighlight = 1
    }
end

local applying = false
local pendingSize

-- mirrors NamePlateDriverMixin:UpdateNamePlateOptions for the Classic style
function M.ApplyOverride()
    if applying then return end
    local o = NamePlateSetupOptions
    if not o then return false end
    applying = true

    local sc = ClassicScale()
    local h, v = sc.horizontal, sc.vertical

    o.horizontalScale = h
    o.verticalScale = v

    o.healthBarHeight = Const("CLASSIC_HEALTH_BAR_HEIGHT", 10) * v
    o.healthBarFontHeight = Const("CLASSIC_HEALTH_BAR_FONT_HEIGHT", 10) * v
    o.useClassicHealthBar = true
    o.healthBarToNameAboveSpacing =
        Const("CLASSIC_HEALTH_BAR_TO_NAME_ABOVE_SPACING", 4) * v

    o.castBarHeight = Const("CLASSIC_CAST_BAR_HEIGHT", 10) * v
    o.castBarFontHeight = Const("CAST_BAR_FONT_HEIGHT", 10) * v
    o.useClassicCastBar = true
    o.castBarToHealthBarSpacing =
        Const("CLASSIC_CAST_BAR_TO_HEALTH_BAR_SPACING", 4) * v

    o.castBarShieldWidth = 10 * v
    o.castBarShieldHeight = 12 * v
    o.castIconWidth = Const("CLASSIC_CAST_BAR_ICON_HEIGHT", 14) * v
    o.castIconHeight = o.castIconWidth
    o.hideIconWhenNotInterruptible = false -- classic keeps the icon

    local anchors = NamePlateConstants and NamePlateConstants.NAME_ANCHOR_STYLES
    o.unitNameAnchorStyle = (anchors and anchors.CenteredAboveHealthBar) or 3
    o.spellNameInsideCastBar = true

    o.classificationScale = sc.classification
    -- Forever-only fields (harmless elsewhere)
    o.playerLevelDiffWidth = Const("LEVEL_INDICATOR_WIDTH", 28) * sc.classification
    o.playerLevelDiffHeight = Const("SMALL_LEVEL_INDICATOR_HEIGHT", 16) * sc.classification
    o.nameJustificationWhenAboveHealthBar = "CENTER"
    o.useOutlinedNameWhenAboveHealthBar = false
    o.levelFontHeight = Const("LEVEL_FONT_HEIGHT", 10) * v
    o.levelIconWidth = Const("LEVEL_ICON_WIDTH", 15) * h
    o.levelIconHeight = Const("LEVEL_ICON_HEIGHT", 15) * v
    o.insetWidth = Const("HORIZONTAL_INSET", 12) * h

    o.healthBarBorderWidth = Const("CLASSIC_BORDER_WIDTH", 128) * h
    o.healthBarBorderHeight = Const("CLASSIC_BORDER_HEIGHT", 16) * v
    o.castBarBorderWidth = o.healthBarBorderWidth
    o.castBarBorderHeight = o.healthBarBorderHeight

    for _, fo in ipairs({NamePlateEnemyFrameOptions, NamePlateFriendlyFrameOptions}) do
        if fo then
            fo.colorNameBySelection = false
            fo.nameMouseoverColor = YELLOW_FONT_COLOR
            fo.showLevel = true
            fo.colorHealthWithExtendedColors = false
            fo.displaySelectionHighlight = true
            fo.displaySelectionHighlightOnMouseover = true
        end
    end

    -- plate size the C++ side stacks plates with (same math as
    -- NamePlateDriverMixin:GetNamePlateHeight for the classic style)
    local auraScale = tonumber(GetCVarSafe("nameplateAuraScale")) or 1
    local debuffPadding = tonumber(GetCVarSafe("nameplateDebuffPadding")) or 3
    local height = Const("AURA_ITEM_HEIGHT", 25) * auraScale * sc.aura +
                       debuffPadding + o.healthBarFontHeight +
                       o.healthBarHeight + o.castBarHeight
    local width = Const("CLASSIC_NAMEPLATE_WIDTH", 152, "CLASSIC_NAME_PLATE_WIDTH") * h
    M.size = {width = width, height = height}
    if C_NamePlate and C_NamePlate.SetNamePlateSize then
        if InCombatLockdown and InCombatLockdown() then
            pendingSize = true
        else
            pcall(C_NamePlate.SetNamePlateSize, width, height)
        end
    end

    -- re-run the per-plate layout with the new values
    local driver = NamePlateDriverFrame
    if driver and driver.ForEachNamePlate then
        pcall(driver.ForEachNamePlate, driver, function(frame)
            PatchPlate(frame)
            if frame.ApplyFrameOptions then frame:ApplyFrameOptions() end
        end)
    end

    applying = false
    return true
end

local function InstallOverride()
    if not NamePlateSetupOptions or not NamePlateDriverFrame then
        return false, "no NamePlateDriverFrame/NamePlateSetupOptions on this client"
    end
    if not M.hooked and hooksecurefunc then
        hooksecurefunc(NamePlateDriverFrame, "UpdateNamePlateOptions",
                       function() M.ApplyOverride() end)
        -- plates acquired later pick up NamePlateSetupOptions on their own;
        -- they only need the level badge switched off and one re-layout
        InstallPlateHooks()
        M.hooked = true
        if CreateFrame then
            local f = CreateFrame("Frame")
            f:RegisterEvent("PLAYER_REGEN_ENABLED")
            f:SetScript("OnEvent", function()
                if pendingSize and M.size and C_NamePlate and
                    C_NamePlate.SetNamePlateSize then
                    pendingSize = nil
                    pcall(C_NamePlate.SetNamePlateSize, M.size.width,
                          M.size.height)
                end
            end)
        end
    end
    M.ApplyOverride()
    return true
end

--------------------------------------------------------------------------
-- module interface
--------------------------------------------------------------------------

function M:Enable()
    M.enabled = true
    local ok, why = TryCVar()
    if ok then
        M.mode = "cvar"
        -- Blizzard draws the classic plates; only Forever's extra level
        -- badge needs to go, and the style has to survive its settings page
        InstallPlateHooks()
        InstallCVarWatcher()
        return
    end
    M.cvarReason = why
    local installed, why2 = InstallOverride()
    if installed then
        M.mode = "override"
    else
        M.mode = "unavailable"
        M.overrideReason = why2
        ns.Print("nameplates: could not restyle (%s). Run /cui probe and send me the report.",
                 tostring(why2))
    end
end

-- testing aid: skip the CVar and use the Lua fallback right now
function M:Force()
    M.enabled = true
    local installed, why = InstallOverride()
    if installed then
        M.mode = "override"
        ns.Print("nameplates: Lua fallback applied.")
    else
        ns.Print("nameplates: fallback unavailable (%s).", tostring(why))
    end
end

function M:Disable()
    local wasCVar = M.mode == "cvar"
    M.enabled = false
    M.mode = "off" -- before the CVar goes back, so the watcher lets it
    if wasCVar and ns.db and ns.db.savedNameplateStyle then
        pcall(SetCVarSafe, "nameplateStyle", ns.db.savedNameplateStyle)
        ns.db.savedNameplateStyle = nil
    end
    ns.Print("nameplates: type /reload to fully restore Blizzard's layout.")
end

-- /cui nameplates size small|medium|large|xl|huge  (Blizzard's nameplateSize)
local SIZES = {
    small = "Small", medium = "Medium", large = "Large",
    xl = "ExtraLarge", extralarge = "ExtraLarge", huge = "Huge"
}
function M:Command(arg)
    local what, value = arg:match("^(%S+)%s*(%S*)$")
    if what ~= "size" then return false end
    local key = SIZES[value]
    local enum = Enum and Enum.NamePlateSize
    if not key or not enum or enum[key] == nil then
        local names = {}
        for _, k in ipairs({"small", "medium", "large", "xl", "huge"}) do
            if enum and enum[SIZES[k]] ~= nil then names[#names + 1] = k end
        end
        ns.Print("nameplates: size is %s (now %s).", table.concat(names, "|"),
                 tostring(GetCVarSafe("nameplateSize")))
        return true
    end
    pcall(SetCVarSafe, "nameplateSize", enum[key])
    ns.Print("nameplates: size %s.", value)
    return true
end

function M:Status()
    if M.mode == "cvar" then
        return "(Blizzard's built-in Classic style, Forever level badge hidden)"
    elseif M.mode == "override" then
        return "(Lua fallback: " .. tostring(M.cvarReason) .. ")"
    elseif M.mode == "unavailable" then
        return "(unavailable: " .. tostring(M.overrideReason) .. ")"
    end
    return ""
end

ns.RegisterModule("nameplates", M)
