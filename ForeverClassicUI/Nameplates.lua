-- Forever Classic UI - nameplates
--
-- Blizzard's current nameplate code (shared by Classic Era, retail and WoW
-- Forever's "Camelot" flavor) contains a complete "Classic" style: the old
-- rounded Nameplate-Border art, level in the border, name centered above the
-- bar, the small classic cast bar with its spark. It is selected by the
-- nameplateStyle CVar (value 6). Classic Era shows it in Options >
-- Nameplates; Forever accepts the value but hides the option and keeps its
-- own level badge next to every plate.
--
-- Forever (like retail) protects unit health behind "secret values": only
-- untainted Blizzard code may compare them. Anything an addon writes into
-- the nameplate tables, and any Blizzard nameplate function an addon calls
-- (including the CVar callback triggered by SetCVar), taints that code and
-- every plate then errors out half-built. So on those clients this part
--   * never sets nameplateStyle itself - the player types
--     /console nameplateStyle 6 once (chat commands run untainted, and the
--     CVar is saved with the character),
--   * hides Forever's level badge with a widget call (SetAlpha) from its
--     own NAME_PLATE_UNIT_ADDED handler, no hooks, no table writes.
-- Clients without secret values keep the cheap path (set the CVar) and the
-- Lua fallback that forces the classic layout through Blizzard's option
-- tables when the CVar is refused.

local addonName, ns = ...

local M = {mode = "off"}

local CLASSIC_STYLE = (Enum and Enum.NamePlateStyle and
                          Enum.NamePlateStyle.Classic) or 6
local MEDIUM_SIZE = (Enum and Enum.NamePlateSize and Enum.NamePlateSize.Medium) or
                        1
M.CONSOLE_COMMAND = "/console nameplateStyle " .. CLASSIC_STYLE

local function GetCVarSafe(name)
    if C_CVar and C_CVar.GetCVar then return C_CVar.GetCVar(name) end
    if GetCVar then return GetCVar(name) end
end

local function SetCVarSafe(name, value)
    if C_CVar and C_CVar.SetCVar then return C_CVar.SetCVar(name, value) end
    if SetCVar then return SetCVar(name, value) end
end

-- clients with secret values (Forever, retail): addon-driven changes to the
-- nameplate code path are fatal there
local function HasSecrets()
    return C_Secrets ~= nil or issecretvalue ~= nil
end
M.HasSecrets = HasSecrets

local function OnClassicStyle()
    return tonumber(GetCVarSafe("nameplateStyle")) == CLASSIC_STYLE
end

--------------------------------------------------------------------------
-- path 1: the built-in classic style (set the CVar - non-secret clients only)
--------------------------------------------------------------------------

-- returns true when the client is now on the classic style
local function TryCVar()
    local current = GetCVarSafe("nameplateStyle")
    if current == nil then return false, "client has no nameplateStyle CVar" end
    if tonumber(current) == CLASSIC_STYLE then return true end
    if HasSecrets() then
        return false, "needs " .. M.CONSOLE_COMMAND
    end
    -- remember what the player had so /cui nameplates off can put it back
    if ns.db and ns.db.savedNameplateStyle == nil then
        ns.db.savedNameplateStyle = tostring(current)
    end
    pcall(SetCVarSafe, "nameplateStyle", CLASSIC_STYLE)
    if OnClassicStyle() then return true end
    return false, ("client refused nameplateStyle=%d (has %s)"):format(
               CLASSIC_STYLE, tostring(GetCVarSafe("nameplateStyle")))
end

--------------------------------------------------------------------------
-- Forever's level badge (PlayerLevelDiffFrame on every plate)
--------------------------------------------------------------------------

-- The classic border has its own level slot, so the badge is made invisible.
-- Only widget calls: SetAlpha leaves no taint on the plate's Lua tables and
-- Blizzard never sets the badge's alpha itself.
local function SetBadgeAlpha(plate, alpha)
    local uf = plate and plate.UnitFrame
    local badge = uf and uf.PlayerLevelDiffFrame
    if badge and badge.SetAlpha then badge:SetAlpha(alpha) end
end

local function ForAllPlates(fn)
    if C_NamePlate and C_NamePlate.GetNamePlates then
        local ok, plates = pcall(C_NamePlate.GetNamePlates)
        if ok and type(plates) == "table" then
            for _, plate in ipairs(plates) do fn(plate) end
        end
    end
end

local function InstallWatcher()
    if M.watcher or not CreateFrame then return end
    M.watcher = CreateFrame("Frame")
    M.watcher:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    M.watcher:RegisterEvent("CVAR_UPDATE")
    M.watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
    M.watcher:SetScript("OnEvent", function(_, event, arg)
        if not M.enabled then return end
        if event == "NAME_PLATE_UNIT_ADDED" then
            if M.mode == "cvar" and C_NamePlate and C_NamePlate.GetNamePlateForUnit then
                local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, arg)
                if ok then SetBadgeAlpha(plate, 0) end
            end
        elseif event == "CVAR_UPDATE" and arg ~= "nameplateStyle" then
            return
        else
            -- the style changed under us (Forever's Options > Nameplates
            -- page writes its own styles back) or came back
            if OnClassicStyle() then
                if M.mode == "console" then
                    M.mode = "cvar"
                    ForAllPlates(function(plate) SetBadgeAlpha(plate, 0) end)
                    ns.Print("nameplates: classic style on.")
                end
            elseif M.mode == "cvar" then
                if HasSecrets() then
                    M.mode = "console"
                    ForAllPlates(function(plate) SetBadgeAlpha(plate, 1) end)
                    ns.Print("nameplates: the style was changed. Type  %s  to get the classic plates back.",
                             M.CONSOLE_COMMAND)
                else
                    local function reapply()
                        if M.enabled and M.mode == "cvar" then TryCVar() end
                    end
                    if C_Timer and C_Timer.After then C_Timer.After(0, reapply) else reapply() end
                end
            end
        end
    end)
end

--------------------------------------------------------------------------
-- path 2: force the classic layout through Blizzard's option tables
--          (clients without secret values that refuse the CVar)
--------------------------------------------------------------------------

local function Const(name, default, altName)
    local v = NamePlateConstants and NamePlateConstants[name]
    if v == nil and altName then v = NamePlateConstants and NamePlateConstants[altName] end
    if v == nil then return default end
    return v
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
            SetBadgeAlpha(frame, 0)
            if frame.ApplyFrameOptions then frame:ApplyFrameOptions() end
        end)
    end

    applying = false
    return true
end

local function InstallOverride()
    if HasSecrets() then
        return false, "this client protects nameplate values; " .. M.CONSOLE_COMMAND
    end
    if not NamePlateSetupOptions or not NamePlateDriverFrame then
        return false, "no NamePlateDriverFrame/NamePlateSetupOptions on this client"
    end
    if not M.hooked and hooksecurefunc then
        hooksecurefunc(NamePlateDriverFrame, "UpdateNamePlateOptions",
                       function() M.ApplyOverride() end)
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
    InstallWatcher()
    local ok, why = TryCVar()
    if ok then
        M.mode = "cvar"
        ForAllPlates(function(plate) SetBadgeAlpha(plate, 0) end)
        return
    end
    M.cvarReason = why
    if HasSecrets() then
        M.mode = "console"
        ns.Print("nameplates: type  %s  once to switch to the classic plates (this client only lets you change it, not an addon).",
                 M.CONSOLE_COMMAND)
        return
    end
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
    M.mode = "off"
    ForAllPlates(function(plate) SetBadgeAlpha(plate, 1) end)
    if wasCVar and HasSecrets() then
        ns.Print("nameplates: pick a style in Options > Nameplates (or type /console nameplateStyle 1) to leave the classic plates.")
    elseif wasCVar and ns.db and ns.db.savedNameplateStyle then
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
    if HasSecrets() then
        -- same rule: the size CVar re-runs the nameplate layout
        ns.Print("nameplates: type  /console nameplateSize %d  (an addon setting it would break the plates on this client).",
                 enum[key])
        return true
    end
    pcall(SetCVarSafe, "nameplateSize", enum[key])
    ns.Print("nameplates: size %s.", value)
    return true
end

function M:Status()
    if M.mode == "cvar" then
        if HasSecrets() then
            return "(Blizzard's built-in Classic style, Forever level badge hidden)"
        end
        return "(using Blizzard's built-in Classic style)"
    elseif M.mode == "console" then
        return "(waiting: type  " .. M.CONSOLE_COMMAND .. "  once)"
    elseif M.mode == "override" then
        return "(Lua fallback: " .. tostring(M.cvarReason) .. ")"
    elseif M.mode == "unavailable" then
        return "(unavailable: " .. tostring(M.overrideReason) .. ")"
    end
    return ""
end

ns.RegisterModule("nameplates", M)
