-- Forever Classic UI - /cui probe
-- Builds a plain-text report of everything that decides how this addon has
-- to behave on a given client (build, which Blizzard UI pieces are loaded,
-- nameplate style support, cast bar art, whether the classic textures still
-- exist) and shows it in a copyable window. Send that report when something
-- looks wrong - it's how the addon gets adjusted for a new client build
-- without guessing.

local addonName, ns = ...

local CLASSIC_TEXTURES = {
    "Interface\\Tooltips\\Nameplate-Border",
    "Interface\\Tooltips\\Nameplate-Border-Castbar",
    "Interface\\TargetingFrame\\UI-TargetingFrame-BarFill",
    "Interface\\TargetingFrame\\UI-StatusBar",
    "Interface\\TargetingFrame\\UI-TargetingFrame-Skull",
    "Interface\\CastingBar\\UI-CastingBar-Border",
    "Interface\\CastingBar\\UI-CastingBar-Border-Small",
    "Interface\\CastingBar\\UI-CastingBar-Flash",
    "Interface\\CastingBar\\UI-CastingBar-Flash-Small",
    "Interface\\CastingBar\\UI-CastingBar-Spark",
    "Interface\\CastingBar\\UI-CastingBar-Small-Shield",
    "Interface\\ComboFrame\\ComboPoint",
    "Interface\\TargetingFrame\\UI-TargetingFrame",
    "Interface\\TargetingFrame\\UI-TargetingFrame-Rare",
    "Interface\\Minimap\\UI-Minimap-Border",
    "Interface\\MainMenuBar\\UI-MainMenuBar-Dwarf"
}

local BLIZZ_ADDONS = {
    "Blizzard_NamePlates", "Blizzard_UnitFrame", "Blizzard_UIPanels_Game",
    "Blizzard_EditMode", "Blizzard_Minimap", "Blizzard_ActionBar",
    "Blizzard_ObjectiveTracker", "Blizzard_CooldownViewer"
}

local function yn(v)
    if v then return "yes" end
    return "no"
end

local function has(global) return _G[global] ~= nil end

local function TextureOf(region)
    if not region then return "n/a" end
    local atlas = region.GetAtlas and region:GetAtlas()
    if atlas then return "atlas " .. tostring(atlas) end
    local tex = region.GetTexture and region:GetTexture()
    return "file " .. tostring(tex)
end

local function AddOnLoaded(name)
    if C_AddOns and C_AddOns.IsAddOnLoaded then
        return C_AddOns.IsAddOnLoaded(name)
    elseif IsAddOnLoaded then
        return IsAddOnLoaded(name)
    end
end

function ns.BuildProbe()
    local out = {}
    local function line(fmt, ...)
        if select("#", ...) > 0 then fmt = fmt:format(...) end
        out[#out + 1] = fmt
    end

    line("Classic UI for Forever %s probe", ns.VERSION)
    if GetBuildInfo then
        local version, build, date, toc = GetBuildInfo()
        line("client: version %s build %s (%s) toc %s", tostring(version),
             tostring(build), tostring(date), tostring(toc))
    end
    line("project id: %s (classic era = %s, mainline = %s)",
         tostring(WOW_PROJECT_ID), tostring(WOW_PROJECT_CLASSIC),
         tostring(WOW_PROJECT_MAINLINE))
    if C_GameRules then
        local okMode, mode = pcall(function() return C_GameRules.GetActiveGameMode and C_GameRules.GetActiveGameMode() end)
        local okInfo, info = pcall(function() return C_GameRules.GetCurrentGameModeDisplayInfo and C_GameRules.GetCurrentGameModeDisplayInfo() end)
        line("game mode: %s / %s", okMode and tostring(mode) or "?",
             okInfo and info and tostring(info.name or info.displayName or "?") or "?")
        local keys = {}
        for k in pairs(C_GameRules) do keys[#keys + 1] = tostring(k) end
        table.sort(keys)
        line("C_GameRules: %s", table.concat(keys, ", "))
    else
        line("C_GameRules: none")
    end

    line("")
    line("-- loaded Blizzard UI")
    for _, name in ipairs(BLIZZ_ADDONS) do
        line("%s: %s", name, tostring(AddOnLoaded(name)))
    end
    line("EditModeManagerFrame: %s", yn(has("EditModeManagerFrame")))

    line("")
    line("-- nameplates")
    local style = (C_CVar and C_CVar.GetCVar and C_CVar.GetCVar("nameplateStyle")) or
                      (GetCVar and GetCVar("nameplateStyle"))
    line("nameplateStyle cvar: %s", tostring(style))
    local function cvar(name)
        return tostring((C_CVar and C_CVar.GetCVar and C_CVar.GetCVar(name)) or
                            (GetCVar and GetCVar(name)))
    end
    line("nameplates shown: enemies=%s friends=%s (V toggles enemies)",
         cvar("nameplateShowEnemies"), cvar("nameplateShowFriends"))
    line("nameplateSize=%s nameplateShowAll=%s", cvar("nameplateSize"),
         cvar("nameplateShowAll"))
    line("Enum.NamePlateStyle.Classic: %s",
         tostring(Enum and Enum.NamePlateStyle and Enum.NamePlateStyle.Classic))
    line("NamePlateDriverFrame: %s", yn(has("NamePlateDriverFrame")))
    line("NamePlateSetupOptions: %s", yn(has("NamePlateSetupOptions")))
    if NamePlateSetupOptions then
        line("  useClassicHealthBar=%s useClassicCastBar=%s nameAnchor=%s",
             tostring(NamePlateSetupOptions.useClassicHealthBar),
             tostring(NamePlateSetupOptions.useClassicCastBar),
             tostring(NamePlateSetupOptions.unitNameAnchorStyle))
    end
    line("NamePlateConstants classic width: %s (Era name) / %s (Forever name)",
         tostring(NamePlateConstants and NamePlateConstants.CLASSIC_NAMEPLATE_WIDTH),
         tostring(NamePlateConstants and NamePlateConstants.CLASSIC_NAME_PLATE_WIDTH))
    line("nameplate level badge (Forever): %s", yn(NameplateLevelFrameMixin))
    line("C_NamePlate.SetNamePlateSize: %s",
         yn(C_NamePlate and C_NamePlate.SetNamePlateSize))
    local np = ns.modules.nameplates
    line("module: mode=%s cvar=%s override=%s", tostring(np and np.mode),
         tostring(np and np.cvarReason), tostring(np and np.overrideReason))

    line("")
    line("-- cast bars")
    local bar = PlayerCastingBarFrame
    line("PlayerCastingBarFrame: %s", yn(bar))
    if bar then
        line("  classicStyleCastBar=%s size=%sx%s",
             tostring(bar.classicStyleCastBar),
             tostring(bar.GetWidth and math.floor(bar:GetWidth() + 0.5)),
             tostring(bar.GetHeight and math.floor(bar:GetHeight() + 0.5)))
        line("  Border: %s", TextureOf(bar.Border))
        line("  Flash: %s", TextureOf(bar.Flash))
        line("  Spark: %s", TextureOf(bar.Spark))
        line("  TextBorder: %s  DropShadow: %s", yn(bar.TextBorder),
             yn(bar.DropShadow))
    end
    line("TargetFrameSpellBar: %s  FocusFrameSpellBar: %s",
         yn(has("TargetFrameSpellBar")), yn(has("FocusFrameSpellBar")))
    local cb = ns.modules.castbar
    line("module: mode=%s", tostring(cb and cb.mode))

    line("")
    line("-- combo points")
    line("ComboFrame (classic): %s  RogueComboPointBarFrame (modern): %s  DruidComboPointBarFrame: %s",
         yn(has("ComboFrame")), yn(has("RogueComboPointBarFrame")),
         yn(has("DruidComboPointBarFrame")))
    line("ComboFrame registered: %s", yn(ComboFrame and ComboFrame.IsEventRegistered and ComboFrame:IsEventRegistered("UNIT_POWER_FREQUENT")))
    line("GetComboPoints: %s  UnitPower: %s  comboPointLocation cvar: %s",
         yn(GetComboPoints), yn(UnitPower),
         tostring((C_CVar and C_CVar.GetCVar and C_CVar.GetCVar("comboPointLocation")) or
                      (GetCVar and GetCVar("comboPointLocation"))))
    local combo = ns.modules.combo
    line("module: mode=%s", tostring(combo and combo.mode))

    line("")
    line("-- other frames (for later phases)")
    line("PlayerFrame: %s  PlayerFrame.PlayerFrameContainer (modern): %s  PlayerFrameTexture (classic): %s",
         yn(has("PlayerFrame")),
         yn(PlayerFrame and PlayerFrame.PlayerFrameContainer),
         yn(has("PlayerFrameTexture")))
    line("TargetFrame: %s  TargetFrame.TargetFrameContainer (modern): %s  TargetFrameTextureFrame (classic): %s",
         yn(has("TargetFrame")),
         yn(TargetFrame and TargetFrame.TargetFrameContainer),
         yn(has("TargetFrameTextureFrame")))
    line("MinimapCluster: %s  MinimapCluster.BorderTop (modern): %s  MinimapBorder (classic): %s",
         yn(has("MinimapCluster")),
         yn(MinimapCluster and MinimapCluster.BorderTop),
         yn(has("MinimapBorder")))
    line("MainMenuBar: %s  MainMenuBarArtFrame (classic): %s  MainMenuBar.EndCaps (modern): %s",
         yn(has("MainMenuBar")), yn(has("MainMenuBarArtFrame")),
         yn(MainMenuBar and MainMenuBar.EndCaps))
    line("ObjectiveTrackerFrame: %s  QuestWatchFrame (classic): %s",
         yn(has("ObjectiveTrackerFrame")), yn(has("QuestWatchFrame")))

    line("")
    line("-- classic textures still in the client")
    for _, path in ipairs(CLASSIC_TEXTURES) do
        local id
        if GetFileIDFromPath then id = GetFileIDFromPath(path) end
        line("%s: %s", path, id and ("id " .. tostring(id)) or
                 (GetFileIDFromPath and "MISSING" or "unknown"))
    end

    line("")
    line("-- errors recorded this session")
    if #ns.errors == 0 then
        line("none")
    else
        for _, e in ipairs(ns.errors) do line(e) end
    end

    return table.concat(out, "\n")
end

local probeFrame

local function CreateProbeFrame()
    local f = CreateFrame("Frame", "ForeverClassicUIProbeFrame", UIParent,
                          "BackdropTemplate")
    f:SetSize(620, 440)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    if f.SetBackdrop then
        f:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = {left = 11, right = 12, top = 12, bottom = 11}
        })
    end

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -16)
    title:SetText("Classic UI for Forever probe - Ctrl+A, Ctrl+C, then paste it to me")

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)

    local scroll = CreateFrame("ScrollFrame", "ForeverClassicUIProbeScroll", f,
                               "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 20, -40)
    scroll:SetPoint("BOTTOMRIGHT", -40, 20)

    local edit = CreateFrame("EditBox", "ForeverClassicUIProbeEdit", scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject("ChatFontNormal")
    edit:SetWidth(540)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    scroll:SetScrollChild(edit)
    f.edit = edit
    return f
end

function ns.ShowProbe()
    local text = ns.BuildProbe()
    if CreateFrame and UIParent then
        probeFrame = probeFrame or CreateProbeFrame()
        probeFrame.edit:SetText(text)
        probeFrame:Show()
        probeFrame.edit:SetFocus()
        probeFrame.edit:HighlightText()
    end
    ns.lastProbe = text
    ns.Print("probe window opened - copy the text and send it over.")
    return text
end
