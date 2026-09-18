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
    "Interface\\TargetingFrame\\UI-TargetingFrame-Elite",
    "Interface\\TargetingFrame\\UI-TargetingFrame-Rare-Elite",
    "Interface\\TargetingFrame\\UI-TargetingFrame-Minus",
    "Interface\\TargetingFrame\\UI-TargetingFrame-Flash",
    "Interface\\TargetingFrame\\UI-TargetingFrame-LevelBackground",
    "Interface\\TargetingFrame\\UI-SmallTargetingFrame",
    "Interface\\TargetingFrame\\UI-PartyFrame-Flash",
    "Interface\\TargetingFrame\\UI-Player-AttackStatus",
    "Interface\\CharacterFrame\\UI-Player-Status",
    "Interface\\CharacterFrame\\UI-StateIcon",
    "Interface\\PaperDollInfoFrame\\UI-Character-General-TopLeft",
    "Interface\\PaperDollInfoFrame\\UI-Character-General-TopRight",
    "Interface\\PaperDollInfoFrame\\UI-Character-General-BottomLeft",
    "Interface\\PaperDollInfoFrame\\UI-Character-General-BottomRight",
    "Interface\\PaperDollInfoFrame\\UI-Character-StatBackground",
    "Interface\\PaperDollInfoFrame\\UI-Character-ResistanceIcons",
    "Interface\\PaperDollInfoFrame\\UI-Character-CharacterTab-L1",
    "Interface\\PaperDollInfoFrame\\UI-Character-CharacterTab-R1",
    "Interface\\PaperDollInfoFrame\\UI-Character-CharacterTab-BottomLeft",
    "Interface\\PaperDollInfoFrame\\UI-Character-CharacterTab-BottomRight",
    "Interface\\PaperDollInfoFrame\\UI-Character-AmmoSlot",
    "Interface\\PaperDollInfoFrame\\UI-Character-Tab-Highlight",
    "Interface\\PaperDollInfoFrame\\UI-Character-ActiveTab",
    "Interface\\PaperDollInfoFrame\\UI-Character-InActiveTab",
    "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar",
    "Interface\\PaperDollInfoFrame\\UI-Character-Skills-BarBorder",
    "Interface\\PaperDollInfoFrame\\UI-Character-Skills-BarBorderHighlight",
    "Interface\\PaperDollInfoFrame\\SkillFrame-BotLeft",
    "Interface\\PaperDollInfoFrame\\SkillFrame-BotRight",
    "Interface\\PaperDollInfoFrame\\UI-Character-ReputationBar",
    "Interface\\PaperDollInfoFrame\\UI-Character-ReputationBar-Highlight",
    "Interface\\PaperDollInfoFrame\\UI-Character-Reputation-DetailBackground",
    "Interface\\PaperDollInfoFrame\\UI-Character-ScrollBar",
    "Interface\\ClassTrainerFrame\\UI-ClassTrainer-HorizontalBar",
    "Interface\\ClassTrainerFrame\\UI-ClassTrainer-ScrollBar",
    -- Era's trade skill window (the crafting page), for the next phase
    "Interface\\ClassTrainerFrame\\UI-ClassTrainer-TopLeft",
    "Interface\\ClassTrainerFrame\\UI-ClassTrainer-TopRight",
    "Interface\\TradeSkillFrame\\UI-TradeSkill-BotLeft",
    "Interface\\ClassTrainerFrame\\UI-ClassTrainer-BotRight",
    "Interface\\TradeSkillFrame\\UI-TradeSkill-SkillBorder",
    "Interface\\ClassTrainerFrame\\UI-ClassTrainer-ExpandTab-Left",
    "Interface\\ClassTrainerFrame\\UI-ClassTrainer-DetailHeaderLeft",
    "Interface\\ClassTrainerFrame\\UI-ClassTrainer-DetailHeaderRight",
    "Interface\\Buttons\\UI-Listbox-Highlight2",
    "Interface\\Common\\Common-Input-Border",
    "Interface\\QuestFrame\\UI-QuestLogSortTab-Left",
    "Interface\\Buttons\\CancelButton-Up",
    "Interface\\Buttons\\UI-CheckBox-SwordCheck",
    "Interface\\DialogFrame\\UI-DialogBox-Corner",
    "Interface\\TargetingFrame\\UI-PartyFrame",
    "Interface\\PaperDollInfoFrame\\UI-Character-Honor-TopLeft",
    "Interface\\PvPRankBadges\\PvPRank01",
    "Interface\\Buttons\\UI-PlusButton-Up",
    "Interface\\Buttons\\UI-MinusButton-Up",
    "Interface\\Buttons\\UI-Panel-MinimizeButton-Up",
    "Interface\\CharacterFrame\\Char-Paperdoll-Parts",
    "Interface\\Buttons\\UI-Quickslot2",
    "Interface\\Buttons\\UI-EmptySlot",
    "Interface\\Spellbook\\UI-SpellbookPanel-TopLeft",
    "Interface\\Spellbook\\UI-SpellbookPanel-TopRight",
    "Interface\\Spellbook\\UI-SpellbookPanel-BotLeft",
    "Interface\\Spellbook\\UI-SpellbookPanel-BotRight",
    "Interface\\Spellbook\\UI-Spellbook-SpellBackground",
    "Interface\\Spellbook\\Spellbook-Icon",
    "Interface\\SpellBook\\SpellBook-SkillLineTab",
    "Interface\\SpellBook\\UI-SpellBook-Tab-Unselected",
    "Interface\\SpellBook\\UI-SpellBook-Tab1-Selected",
    "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up",
    "Interface\\TALENTFRAME\\UI-TalentFrame-BotLeft",
    "Interface\\TALENTFRAME\\UI-TalentFrame-BotRight",
    "Interface\\Buttons\\UI-Button-Borders2",
    "Interface\\TargetingFrame\\UI-PartyFrame-Flash",
    "Interface\\QuestFrame\\UI-QuestLog-Left",
    "Interface\\FriendsFrame\\UI-FriendsFrame-Left",
    "Interface\\Minimap\\UI-Minimap-Border",
    "Interface\\MainMenuBar\\UI-MainMenuBar-Dwarf",
    "Interface\\MainMenuBar\\UI-MainMenuBar-EndCap-Dwarf",
    "Interface\\MainMenuBar\\UI-MainMenuBar-MaxLevel",
    "Interface\\MainMenuBar\\UI-ExhaustionTickNormal",
    "Interface\\MainMenuBar\\UI-MainMenu-ScrollUpButton-Up",
    "Interface\\Buttons\\UI-Quickslot-Depress",
    "Interface\\Buttons\\ButtonHilight-Square",
    "Interface\\Buttons\\CheckButtonHilight",
    "Interface\\Buttons\\UI-Button-KeyRing",
    "Interface\\QuestFrame\\UI-QuestTitleHighlight",
    "Interface\\Buttons\\UI-MicroButtonCharacter-Up",
    "Interface\\Buttons\\UI-MicroButton-Spellbook-Up",
    "Interface\\Buttons\\UI-MicroButton-Talents-Up",
    "Interface\\Buttons\\UI-MicroButton-Quest-Up",
    "Interface\\Buttons\\UI-MicroButton-Socials-Up",
    "Interface\\Buttons\\UI-MicroButton-LFG-Up",
    "Interface\\Buttons\\UI-MicroButton-Mounts-Up",
    "Interface\\Buttons\\UI-MicroButton-EJ-Up",
    "Interface\\Buttons\\UI-MicroButton-Abilities-Up",
    "Interface\\Buttons\\UI-MicroButton-Achievement-Up",
    "Interface\\Buttons\\UI-MicroButton-World-Up",
    "Interface\\Buttons\\UI-MicroButton-Help-Up",
    "Interface\\Buttons\\UI-MicroButton-BStore-Up",
    "Interface\\Buttons\\UI-MicroButton-MainMenu-Up",
    "Interface\\Buttons\\UI-MicroButton-Hilight",
    "Interface\\Buttons\\UI-Debuff-Overlays"
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
    line("-- settings (saved) and module state")
    line("addon folder: %s", tostring(addonName))
    line("saved file found at login: %s  logins counted in it: %s  (a /reload should raise the count; if not, the client is not writing ForeverClassicUI.lua)",
         yn(ns.dbLoaded), tostring(ns.db and ns.db.logins))
    line("settings came from: %s", tostring(ns.dbSource))
    for _, name in ipairs(ns.moduleOrder) do
        local mod = ns.modules[name]
        line("%s: setting=%s mode=%s", name,
             (ns.db and ns.db[name] == false) and "off" or "on",
             tostring(mod and mod.mode))
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
    -- the professions window: which of the retail names Forever uses
    local profNames = {}
    for _, n in ipairs({"ProfessionsBookFrame", "ProfessionsBook", "ProfessionsFrame", "SpellBookProfessionFrame", "PrimaryProfession1", "SecondaryProfession1", "ToggleProfessionsBook", "Blizzard_ProfessionsBook", "Blizzard_Professions"}) do
        local v = _G[n]
        local loaded = false
        if n:find("^Blizzard_") then
            local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
            local ok, l = pcall(function() return isLoaded and isLoaded(n) end)
            loaded = ok and l
            v = nil
        end
        if v ~= nil or loaded then
            local shown = type(v) == "table" and v.IsShown and v:IsShown()
            profNames[#profNames + 1] = n .. (type(v) == "function" and " (function)" or (loaded and " (loaded)" or (shown and " (shown)" or "")))
        end
    end
    line("professions window: %s", #profNames > 0 and table.concat(profNames, ", ") or "none of the retail names found")
    if ProfessionMicroButton and ProfessionMicroButton.GetScript then
        local ok, fn = pcall(ProfessionMicroButton.GetScript, ProfessionMicroButton, "OnClick")
        line("ProfessionMicroButton OnClick: %s", ok and fn and "set" or "none")
    end
    -- the crafting page (a profession's recipe list): what it is built on
    local page = ProfessionsFrame and ProfessionsFrame.CraftingPage
    if page then
        line("crafting page: %s  RecipeList: %s  SchematicForm: %s  RankBar: %s",
             page.IsShown and yn(page:IsShown()) or "?", yn(page.RecipeList),
             yn(page.SchematicForm), yn(page.RankBar))
    end
    if C_TradeSkillUI then
        local keys = {}
        for k in pairs(C_TradeSkillUI) do keys[#keys + 1] = tostring(k) end
        table.sort(keys)
        line("C_TradeSkillUI: %s", table.concat(keys, ", "))
        local okIDs, ids = pcall(function()
            return C_TradeSkillUI.GetFilteredRecipeIDs and C_TradeSkillUI.GetFilteredRecipeIDs()
        end)
        local count = (okIDs and type(ids) == "table") and #ids or 0
        line("recipes in the open list: %d", count)
        if count > 0 then
            local okInfo, fields = pcall(function()
                local info = C_TradeSkillUI.GetRecipeInfo and C_TradeSkillUI.GetRecipeInfo(ids[1])
                if type(info) ~= "table" then return nil end
                local out = {}
                for k, v in pairs(info) do out[#out + 1] = tostring(k) .. "=" .. tostring(v) end
                table.sort(out)
                return table.concat(out, " ")
            end)
            line("first recipe: %s", (okInfo and fields) or "could not be read")
        end
    else
        line("C_TradeSkillUI: none")
    end
    local craftGlobals = {}
    for _, n in ipairs({"GetNumTradeSkills", "GetTradeSkillInfo", "GetTradeSkillLine",
                        "GetTradeSkillNumReagents", "GetTradeSkillReagentInfo", "DoTradeSkill",
                        "TradeSkillFrame", "CraftFrame"}) do
        if _G[n] ~= nil then craftGlobals[#craftGlobals + 1] = n end
    end
    line("classic trade skill globals: %s", #craftGlobals > 0 and table.concat(craftGlobals, ", ") or "none")

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

function ns.ShowText(text)
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

function ns.ShowProbe()
    return ns.ShowText(ns.BuildProbe())
end

--------------------------------------------------------------------------
-- /cui dump <FrameName>: every visible texture, font string and child frame
-- of a Blizzard frame with size, anchor, art and colour - for finding
-- stray pieces on a client we cannot see.
--------------------------------------------------------------------------

local MAX_DEPTH = 6

local function KeyOf(parent, child)
    if type(parent) ~= "table" then return nil end
    for k, v in pairs(parent) do
        if v == child and type(k) == "string" then return k end
    end
end

-- secret values (Forever, retail) cannot be formatted or concatenated;
-- every piece is built in its own pcall and replaced by "<secret>" on failure
local function IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v)
end

local function Piece(fn)
    local ok, r = pcall(fn)
    if not ok then return "<secret>" end
    if r == nil then return nil end
    if IsSecret(r) then return "<secret>" end
    return r
end

local function Describe(obj, label)
    local parts = {label}
    local function add(fn)
        local v = Piece(fn)
        if v ~= nil then parts[#parts + 1] = tostring(v) end
    end
    local kind = Piece(function() return obj.GetObjectType and obj:GetObjectType() end) or "?"
    parts[#parts + 1] = tostring(kind)
    if obj.GetSize then
        add(function()
            local w, h = obj:GetSize()
            return ("%dx%d"):format(math.floor((w or 0) + 0.5), math.floor((h or 0) + 0.5))
        end)
    end
    if obj.GetPoint then
        add(function()
            local point, rel, relPoint, x, y = obj:GetPoint(1)
            if not point then return "no-anchor" end
            local relName = rel and rel.GetName and rel:GetName() or (rel and "parent") or "nil"
            return ("%s>%s.%s %+.1f,%+.1f"):format(point, relName, tostring(relPoint), x or 0, y or 0)
        end)
    end
    add(function()
        if obj.GetAtlas and obj:GetAtlas() then return "atlas=" .. tostring(obj:GetAtlas()) end
        if obj.GetTexture and obj:GetTexture() then return "tex=" .. tostring(obj:GetTexture()) end
    end)
    if obj.GetVertexColor then
        add(function()
            local r, g, b = obj:GetVertexColor()
            if r and (r < 0.99 or g < 0.99 or b < 0.99) then
                return ("rgb=%.2f,%.2f,%.2f"):format(r, g, b)
            end
        end)
    end
    if obj.GetAlpha then
        add(function()
            local a = obj:GetAlpha()
            if a and a < 0.99 then return ("alpha=%.2f"):format(a) end
        end)
    end
    if obj.GetDrawLayer then
        add(function() local layer = obj:GetDrawLayer(); return layer and tostring(layer) end)
    end
    if obj.GetTexCoord and (kind == "Texture" or kind == "MaskTexture") then
        add(function()
            local ulx, uly, llx, lly, urx, ury, lrx, lry = obj:GetTexCoord()
            if ulx == nil then return end
            if ulx ~= 0 or uly ~= 0 or urx ~= 1 or lry ~= 1 or llx ~= 0 or lly ~= 1 or lrx ~= 1 or ury ~= 0 then
                return ("coord=%.4f,%.4f,%.4f,%.4f"):format(ulx, urx, uly, lly) -- left,right,top,bottom
            end
        end)
    end
    if obj.GetBlendMode then
        add(function() local m = obj:GetBlendMode(); if m and m ~= "BLEND" then return "blend=" .. tostring(m) end end)
    end
    if kind == "FontString" and obj.GetFont then
        add(function()
            local path, size, flags = obj:GetFont()
            if path then
                return ("font=%s/%s%s"):format(tostring(path):match("[^\\/]+$") or tostring(path), tostring(math.floor((size or 0) + 0.5)), (flags and flags ~= "") and ("/" .. flags) or "")
            end
        end)
    end
    if obj.GetFrameLevel and obj.GetFrameStrata then
        add(function() return ("lvl=%s/%s"):format(tostring(obj:GetFrameStrata()), tostring(obj:GetFrameLevel())) end)
    end
    if obj.IsShown and not obj:IsShown() then parts[#parts + 1] = "(hidden)" end
    if kind == "FontString" and obj.GetText then
        add(function() local t = obj:GetText(); return t and ("text=%q"):format(tostring(t)) end)
    end
    if kind == "StatusBar" then
        if obj.GetStatusBarTexture then
            add(function()
                local fill = obj:GetStatusBarTexture()
                if not fill then return end
                local r, g, b = fill:GetVertexColor()
                local tex = (fill.GetAtlas and fill:GetAtlas()) or (fill.GetTexture and fill:GetTexture())
                return ("fill=%.2f,%.2f,%.2f filltex=%s"):format(r or 1, g or 1, b or 1, tostring(tex))
            end)
        end
        if obj.GetMinMaxValues and obj.GetValue then
            add(function()
                local lo, hi = obj:GetMinMaxValues()
                return ("value=%s/%s..%s"):format(tostring(obj:GetValue()), tostring(lo), tostring(hi))
            end)
        end
    end
    -- a secret string can slip through tostring(); drop it rather than fail
    for i = #parts, 1, -1 do
        if IsSecret(parts[i]) then parts[i] = "<secret>" end
    end
    return table.concat(parts, "  ")
end

local function Walk(frame, label, depth, out, seen, includeHidden)
    if depth > MAX_DEPTH or seen[frame] then return end
    seen[frame] = true
    out[#out + 1] = ("%s%s"):format(("  "):rep(depth), Describe(frame, label))
    if frame.GetRegions then
        local regions = {pcall(frame.GetRegions, frame)}
        if regions[1] then
            for i = 2, #regions do
                local r = regions[i]
                if type(r) == "table" and (includeHidden or not r.IsShown or r:IsShown()) then
                    local key = KeyOf(frame, r) or (r.GetName and r:GetName()) or ("region" .. (i - 1))
                    out[#out + 1] = ("%s%s"):format(("  "):rep(depth + 1), Describe(r, key))
                end
            end
        end
    end
    if frame.GetChildren then
        local children = {pcall(frame.GetChildren, frame)}
        if children[1] then
            for i = 2, #children do
                local c = children[i]
                if type(c) == "table" and (includeHidden or not c.IsShown or c:IsShown()) then
                    local key = KeyOf(frame, c) or (c.GetName and c:GetName()) or ("child" .. (i - 1))
                    Walk(c, key, depth + 1, out, seen, includeHidden)
                end
            end
        end
    end
end

function ns.BuildDump(name, includeHidden)
    local frame = _G[name]
    -- "target", "focus", "mouseover": that unit's nameplate
    local unitName = tostring(name):lower()
    if unitName == "target" or unitName == "focus" or unitName == "mouseover" then
        local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and
                          C_NamePlate.GetNamePlateForUnit(unitName)
        if type(plate) ~= "table" then
            return nil, ("no nameplate showing for %s"):format(unitName)
        end
        frame = plate
        name = ((plate.GetName and plate:GetName()) or "NamePlate") .. " (" .. unitName .. ")"
    end
    if type(frame) ~= "table" then
        -- typed in the wrong case? one scan of the globals
        local wanted = tostring(name):lower()
        for k, v in pairs(_G) do
            if type(k) == "string" and type(v) == "table" and k:lower() == wanted and v.GetObjectType then
                frame, name = v, k
                break
            end
        end
    end
    if type(frame) ~= "table" then
        return nil, ("no frame called %s"):format(tostring(name))
    end
    local out = {("Classic UI for Forever %s - dump of %s (%s)"):format(ns.VERSION, name, includeHidden and "all parts, hidden ones marked" or "visible parts only")}
    Walk(frame, name, 0, out, {}, includeHidden)
    return table.concat(out, "\n")
end

function ns.DumpFrame(name, includeHidden)
    local text, why = ns.BuildDump(name, includeHidden)
    if not text then
        ns.Print("dump: %s", why)
        return
    end
    ns.lastDump = text
    return ns.ShowText(text)
end

--------------------------------------------------------------------------
-- /cui report: everything at once - the probe, a dump of every frame the
-- addon touches (and the target's nameplate if one is showing), and the
-- last Lua errors the client raised, addon or not.
--------------------------------------------------------------------------

local REPORT_FRAMES = {
    "PlayerFrame", "TargetFrame", "PetFrame", "target", "PlayerCastingBarFrame",
    "TargetFrameSpellBar", "ComboFrame", "MainActionBar", "MinimapCluster",
    "ObjectiveTrackerFrame"
}

-- classic clients name their pieces differently; both sets are tried
local REPORT_FRAMES_CLASSIC = {"FocusFrame", "TargetFrameToT", "PartyFrame", "PartyMemberFrame1", "MainMenuBar", "MainMenuBarArtFrame", "QuestWatchFrame", "MinimapBorder", "MinimapZoneTextButton",
    "ForeverClassicUIMainMenuBar", "MicroMenuContainer", "MicroMenu", "BagsBar", "StatusTrackingBarManager", "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarRight", "MultiBarLeft"}
-- panels: dumped only while open, so a report taken with the character
-- sheet (or spellbook, quest log, friends list) open captures its layout
local REPORT_FRAMES_OPEN = {"CharacterFrame", "PlayerSpellsFrame", "SpellBookFrame", "PlayerTalentFrame", "ProfessionsBookFrame", "ProfessionsBook", "ProfessionsFrame", "SpellBookProfessionFrame", "QuestLogFrame", "FriendsFrame", "CommunitiesFrame", "ContainerFrame1"}

function ns.BuildReport(includeHidden)
    local parts = {ns.BuildProbe()}
    local names = {}
    for _, n in ipairs(REPORT_FRAMES) do names[#names + 1] = n end
    for _, n in ipairs(REPORT_FRAMES_CLASSIC) do if _G[n] then names[#names + 1] = n end end
    for _, n in ipairs(REPORT_FRAMES_OPEN) do
        local f = _G[n]
        if type(f) == "table" and f.IsShown and f:IsShown() then names[#names + 1] = n end
    end
    for _, name in ipairs(names) do
        local text, why = ns.BuildDump(name, includeHidden)
        parts[#parts + 1] = text or ("-- " .. name .. ": " .. tostring(why))
    end
    local errs = {"-- Lua errors this session (last " .. #(ns.luaErrors or {}) .. ", newest last)"}
    for _, e in ipairs(ns.luaErrors or {}) do
        errs[#errs + 1] = ("[%s] x%d %s"):format(e.time, e.count, e.msg)
        if e.stack and e.stack ~= "" then errs[#errs + 1] = e.stack end
    end
    if #errs == 1 then errs[#errs + 1] = "none" end
    parts[#parts + 1] = table.concat(errs, "\n")
    return table.concat(parts, "\n\n")
end

function ns.ShowReport(includeHidden)
    local text = ns.BuildReport(includeHidden)
    ns.lastReport = text
    return ns.ShowText(text)
end
