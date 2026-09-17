-- Offline harness for the Forever Classic UI addon (Lua 5.1, no game needed).
--   lua5.1 tests/harness_classicui.lua .
-- Stubs just enough of the WoW API to load the addon and drives it through
-- the two client shapes it has to cope with: a Classic client that already
-- has the classic style (nothing to do) and a retail-style client that hides
-- it (CVar refused, Lua fallback + cast bar re-skin).

local root = arg and arg[1] or "."
local realPrint = print
local passed, failed = 0, 0
local lastNs
local function check(cond, label)
    if cond then
        passed = passed + 1
    else
        failed = failed + 1
        realPrint("FAIL: " .. label)
        if label:find("no errors") and lastNs then
            for _, e in ipairs(lastNs.errors) do realPrint("   error: " .. e) end
        end
    end
end

--------------------------------------------------------------------------
-- fake frames / regions
--------------------------------------------------------------------------

local function Region(kind, init)
    local r = {
        kind = kind, anchors = {}, shown = true, alpha = 1, width = 0,
        height = 0, texture = init and init.file, atlas = init and init.atlas
    }
    function r:SetTexture(t) self.texture = t; self.atlas = nil end
    function r:GetTexture() return self.texture end
    function r:SetAtlas(a) self.atlas = a; self.texture = nil end
    function r:GetAtlas() return self.atlas end
    function r:SetTexCoord(...) self.texcoord = {...} end
    function r:SetColorTexture(...) self.color = {...}; self.texture = nil; self.atlas = nil end
    function r:SetVertexColor(...) self.vertex = {...} end
    function r:SetBlendMode(m) self.blend = m end
    function r:SetSize(w, h) self.width, self.height = w, h end
    function r:SetWidth(w) self.width = w end
    function r:SetHeight(h) self.height = h end
    function r:GetWidth() return self.width end
    function r:GetHeight() return self.height end
    function r:ClearAllPoints() self.anchors = {} end
    function r:SetPoint(...) table.insert(self.anchors, {...}) end
    function r:SetAllPoints(rel) self.anchors = {{"ALL", rel}} end
    function r:Show() self.shown = true end
    function r:Hide() self.shown = false end
    function r:IsShown() return self.shown end
    function r:SetAlpha(a) self.alpha = a end
    function r:SetFontObject(f) self.font = f end
    function r:SetJustifyH(j) self.justify = j end
    function r:SetTextureSliceMargins() end
    function r:SetDrawLayer() end
    function r:SetText(t) self.text = t end
    function r:GetText() return self.text end
    function r:RemoveMaskTexture(m) self.maskRemoved = m end
    -- read-back API used by /cui dump
    function r:GetObjectType() return self.kind end
    function r:GetSize() return self.width, self.height end
    function r:GetName() return self.name end
    function r:GetNumPoints() return #self.anchors end
    function r:GetPoint(i) local a = self.anchors[i or 1]; if a then return unpack(a) end end
    function r:GetVertexColor() if self.vertex then return unpack(self.vertex) end return 1, 1, 1, 1 end
    function r:GetAlpha() return self.alpha end
    function r:GetDrawLayer() return "ARTWORK", 0 end
    return r
end

local function Frame(name)
    local f = Region("Frame")
    f.name = name
    f.events = {}
    function f:RegisterEvent(e) self.events[e] = true end
    function f:UnregisterEvent(e) self.events[e] = nil end
    function f:SetScript(k, fn) self.scripts = self.scripts or {}; self.scripts[k] = fn end
    function f:Fire(event, ...)
        if self.scripts and self.scripts.OnEvent then self.scripts.OnEvent(self, event, ...) end
    end
    function f:SetFrameStrata() end
    function f:SetMovable() end
    function f:EnableMouse() end
    function f:RegisterForDrag() end
    function f:SetBackdrop() end
    function f:CreateFontString() return Region("FontString") end
    function f:SetMultiLine() end
    function f:SetAutoFocus() end
    function f:SetScrollChild(c) self.child = c end
    function f:SetFocus() end
    function f:ClearFocus() end
    function f:HighlightText() end
    function f:CreateTexture() return Region("Texture") end
    function f:SetParent(p) self.parent = p end
    function f:UnregisterAllEvents() self.events = {} end
    function f:RegisterUnitEvent(e) self.events[e] = true end
    function f:GetAlpha() return self.alpha end
    function f:SetStatusBarTexture(tex) self.barTexture = tex end
    function f:GetStatusBarTexture() self.fill = self.fill or Region("Texture"); return self.fill end
    function f:SetStatusBarColor(...) self.barColor = {...} end
    function f:SetMaskTexture(m) self.mask = m end
    function f:SetFrameLevel(l) self.level = l end
    function f:GetFrameLevel() return self.level or 1 end
    function f:SetJustifyH(j) self.justify = j end
    function f:SetChecked(v) self.checked = v end
    function f:GetChecked() return self.checked end
    function f:Click() self.checked = not self.checked; self.scripts.OnClick(self) end
    function f:SetWidth(w) self.width = w end
    function f:GetMinMaxValues() return self.minmax and unpack(self.minmax) or 0, 0 end
    function f:GetValue() return self.value or 0 end
    -- children/regions are whatever tables hang off the frame by key
    function f:GetRegions()
        local t = {}
        for k, v in pairs(self) do
            if type(v) == "table" and v.kind and v.kind ~= "Frame" and type(k) == "string" then t[#t + 1] = v end
        end
        return unpack(t)
    end
    function f:GetChildren()
        local t = {}
        for k, v in pairs(self) do
            if type(v) == "table" and v.kind == "Frame" and type(k) == "string" and k ~= "parent" then t[#t + 1] = v end
        end
        return unpack(t)
    end
    return f
end

--------------------------------------------------------------------------
-- world builder
--------------------------------------------------------------------------

local printed = {}

local function ModernBar(name, classic)
    local bar = Frame(name)
    bar.classicStyleCastBar = classic or false
    bar.Border = Region("Texture", classic and {file = "Interface\\CastingBar\\UI-CastingBar-Border"} or {atlas = "ui-castingbar-frame"})
    bar.Flash = Region("Texture", {atlas = "ui-castingbar-full-glow-standard"})
    bar.Spark = Region("Texture", {atlas = "ui-castingbar-pip"})
    bar.BorderShield = Region("Texture", {atlas = "ui-castingbar-shield"})
    bar.Background = Region("Texture", {atlas = "ui-castingbar-background"})
    bar.Text = Region("FontString")
    bar.Icon = Region("Texture")
    if not classic then
        bar.TextBorder = Region("Texture", {atlas = "ui-castingbar-textbox"})
        bar.DropShadow = Region("Texture")
        bar.StandardGlow = Region("Texture")
        bar.Flakes01 = Region("Texture")
        bar.BorderMask = Region("MaskTexture")
    end
    bar.fill = Region("Texture")
    function bar:GetStatusBarTexture() return self.fill end
    function bar:SetStatusBarTexture(t) self.fill.texture = t end
    function bar:SetStatusBarColor(...) self.barColor = {...} end
    bar.lookCalls = 0
    function bar:SetLook(look)
        -- Blizzard re-applying its modern look
        self.lookCalls = self.lookCalls + 1
        self.Border:SetAtlas("ui-castingbar-frame")
        self.classicStyleCastBar = false
    end
    return bar
end

local function NewWorld(opts)
    opts = opts or {}
    for k in pairs(_G) do
        if k ~= "arg" and k ~= "check" and k ~= "print" and k ~= "pairs" and
            k ~= "ipairs" and k ~= "table" and k ~= "string" and k ~= "math" and
            k ~= "type" and k ~= "tostring" and k ~= "tonumber" and
            k ~= "select" and k ~= "pcall" and k ~= "assert" and
            k ~= "loadfile" and k ~= "setmetatable" and k ~= "getmetatable" and
            k ~= "unpack" and k ~= "error" and k ~= "next" and k ~= "_G" and
            k ~= "rawget" and k ~= "rawset" and k ~= "io" and k ~= "os" and
            k ~= "debug" and k ~= "_VERSION" and k ~= "collectgarbage" and
            k ~= "require" and k ~= "package" and k ~= "dofile" and
            k ~= "load" and k ~= "loadstring" and k ~= "xpcall" and
            k ~= "gcinfo" and k ~= "newproxy" and k ~= "module" and
            k ~= "coroutine" then
            _G[k] = nil
        end
    end

    printed = {}
    _G.print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
        table.insert(printed, table.concat(parts, " "))
    end

    local w = {cvars = {}, frames = {}, plateApplies = 0, sizes = {}}
    w.cvars.nameplateStyle = opts.style or "0"
    w.cvars.nameplateSize = "1"
    w.cvars.nameplateAuraScale = "1"
    w.cvars.nameplateDebuffPadding = "3"
    _G.C_CVar = {
        GetCVar = function(n) return w.cvars[n] end,
        SetCVar = function(n, v)
            v = tostring(v)
            if n == "nameplateStyle" and opts.maxStyle and tonumber(v) > opts.maxStyle then
                return false -- retail: value out of range, unchanged
            end
            w.cvars[n] = v
            return true
        end
    }
    _G.GetCVar = _G.C_CVar.GetCVar
    _G.SetCVar = _G.C_CVar.SetCVar

    _G.Enum = {
        NamePlateStyle = {Modern = 0, Thin = 1, Block = 2, HealthFocus = 3, CastFocus = 4, Legacy = 5},
        NamePlateSize = {Small = 0, Medium = 1, Large = 2}
    }
    if not opts.noClassicEnum then _G.Enum.NamePlateStyle.Classic = 6 end

    _G.CreateFrame = function(_, name)
        local f = Frame(name)
        table.insert(w.frames, f)
        return f
    end
    _G.UIParent = Frame("UIParent")
    _G.SlashCmdList = {}
    _G.Settings = {
        RegisterCanvasLayoutCategory = function(frame, name) return {ID = "cat_" .. name, frame = frame} end,
        RegisterAddOnCategory = function(cat) _G.__registeredCategory = cat end,
        OpenToCategory = function(id) _G.__openedCategory = id end
    }
    _G.hooksecurefunc = function(tbl, name, hook)
        if type(tbl) == "string" then tbl, name, hook = _G, tbl, name end
        local orig = tbl[name]
        tbl[name] = function(...)
            local r = orig(...)
            hook(...)
            return r
        end
    end
    _G.InCombatLockdown = function() return w.inCombat end
    _G.YELLOW_FONT_COLOR = {r = 1, g = 0.82, b = 0}
    _G.GetBuildInfo = function() return opts.version or "1.15.9", "69722", "Sep 1 2026", opts.toc or 11509 end
    _G.WOW_PROJECT_ID = 2
    _G.WOW_PROJECT_CLASSIC = 2
    _G.WOW_PROJECT_MAINLINE = 1
    _G.C_AddOns = {IsAddOnLoaded = function(n) return n == "Blizzard_NamePlates" end}
    _G.GetFileIDFromPath = function(p) if p:find("Nameplate") then return 130000 end end

    -- Blizzard nameplate globals (same shape on every client)
    _G.NamePlateConstants = {
        AURA_ITEM_HEIGHT = 25, CAST_BAR_FONT_HEIGHT = 10, HORIZONTAL_INSET = 12,
        LEVEL_ICON_HEIGHT = 15, LEVEL_ICON_WIDTH = 15, LEVEL_FONT_HEIGHT = 10,
        NAMEPLATE_WIDTH = 230, CLASSIC_BORDER_HEIGHT = 16, CLASSIC_BORDER_WIDTH = 128,
        CLASSIC_CAST_BAR_HEIGHT = 10, CLASSIC_CAST_BAR_ICON_HEIGHT = 14,
        CLASSIC_CAST_BAR_TO_HEALTH_BAR_SPACING = 4, CLASSIC_HEALTH_BAR_FONT_HEIGHT = 10,
        CLASSIC_HEALTH_BAR_HEIGHT = 10, CLASSIC_HEALTH_BAR_TO_NAME_ABOVE_SPACING = 4,
        CLASSIC_NAMEPLATE_WIDTH = 152,
        NAME_PLATE_SCALES_CLASSIC_STYLE = {
            [0] = {horizontal = 0.8, vertical = 0.8, classification = 0.8, aura = 0.8, aggroHighlight = 1},
            [1] = {horizontal = 1, vertical = 1, classification = 1, aura = 1, aggroHighlight = 1},
            [2] = {horizontal = 1.25, vertical = 1.25, classification = 1.25, aura = 1.25, aggroHighlight = 1.25}
        },
        NAME_ANCHOR_STYLES = {InsideHealthBar = 1, AboveHealthBar = 2, CenteredAboveHealthBar = 3}
    }
    local function ModernOptions()
        _G.NamePlateSetupOptions = _G.NamePlateSetupOptions or {}
        local o = _G.NamePlateSetupOptions
        o.useClassicHealthBar = false
        o.useClassicCastBar = false
        o.unitNameAnchorStyle = 1
        o.healthBarHeight = 20
        o.spellNameInsideCastBar = false
        _G.NamePlateEnemyFrameOptions = _G.NamePlateEnemyFrameOptions or {}
        _G.NamePlateFriendlyFrameOptions = _G.NamePlateFriendlyFrameOptions or {}
        _G.NamePlateEnemyFrameOptions.showLevel = false
        _G.NamePlateFriendlyFrameOptions.showLevel = false
    end
    ModernOptions()
    w.plates = {{ApplyFrameOptions = function() w.plateApplies = w.plateApplies + 1 end},
                {ApplyFrameOptions = function() w.plateApplies = w.plateApplies + 1 end}}
    _G.NamePlateDriverFrame = {
        UpdateNamePlateOptions = function(self)
            ModernOptions()
            w.sizes[#w.sizes + 1] = {230, 60}
        end,
        ForEachNamePlate = function(self, fn) for _, p in ipairs(w.plates) do fn(p) end end
    }
    _G.C_NamePlate = {SetNamePlateSize = function(wd, ht) w.sizes[#w.sizes + 1] = {wd, ht} end}

    -- cast bars
    _G.PlayerCastingBarFrame = ModernBar("PlayerCastingBarFrame", opts.classicBars)
    _G.TargetFrameSpellBar = ModernBar("TargetFrameSpellBar", opts.classicBars)

    -- combo points: classic client has Blizzard's ComboFrame only, a
    -- retail-style client has the modern bar (and keeps a hidden ComboFrame),
    -- Forever has ComboFrame only but gated behind comboPointLocation
    _G.TargetFrame = Frame("TargetFrame")
    _G.ComboFrame = Frame("ComboFrame")
    function _G.ComboFrame:IsEventRegistered(e) return self.events[e] == true end
    if opts.forever then
        w.cvars.comboPointLocation = "2"
        _G.ComboFrame.ComboPoints = {}
        for i = 1, 5 do local pt = Frame("ComboPoint" .. i); pt:SetPoint("TOPRIGHT", _G.ComboFrame, "TOPRIGHT", -39, 7); _G.ComboFrame.ComboPoints[i] = pt end
        _G.ComboFrame_OnLoad = function(f)
            if w.cvars.comboPointLocation ~= "1" then return end
            f:RegisterEvent("UNIT_POWER_FREQUENT"); w.comboLoaded = true
        end
    elseif not opts.classicBars then
        _G.RogueComboPointBarFrame = Frame("RogueComboPointBarFrame")
        _G.RogueComboPointBarFrame.events = {UNIT_POWER_FREQUENT = true}
    end
    _G.ReloadUI = function() w.reloaded = true end
    if opts.classicBars then
        -- classic client: the old frames exist by name
        _G.PlayerFrame = Frame("PlayerFrame"); _G.PlayerFrameTexture = Region("Texture")
        _G.MainMenuBarArtFrame = Frame("MainMenuBarArtFrame")
        _G.Minimap = Frame("Minimap"); _G.MinimapCluster = Frame("MinimapCluster"); _G.MinimapBorder = Region("Texture")
        _G.MinimapCompassTexture = Region("Texture", {file = "Interface\\Minimap\\CompassRing"})
    end
    if opts.forever then
        -- Forever: retail-style player/target frames, main action bar, minimap
        local pf = Frame("PlayerFrame")
        pf.PlayerFrameContainer = Frame("container")
        pf.PlayerFrameContainer.FrameTexture = Region("Texture", {atlas = "UI-HUD-UnitFrame-Player-PortraitOn"})
        pf.PlayerFrameContainer.FrameFlash = Region("Texture", {atlas = "flash"})
        pf.PlayerFrameContainer.AlternatePowerFrameTexture = Region("Texture")
        pf.PlayerFrameContainer.PlayerPortrait = Region("Texture")
        pf.PlayerFrameContainer.PlayerPortraitMask = Region("MaskTexture")
        local main = Frame("main")
        main.HealthBarsContainer = Frame("hc"); main.HealthBarsContainer.HealthBar = Frame("hb"); main.HealthBarsContainer.HealthBar.HealthBarMask = Region("MaskTexture")
        main.ManaBarArea = Frame("ma"); main.ManaBarArea.ManaBar = Frame("mb"); main.ManaBarArea.ManaBar.ManaBarMask = Region("MaskTexture")
        main.StatusTexture = Region("Texture", {atlas = "status"}); main.LevelBackgroundCircle = Region("Texture")
        pf.PlayerFrameContent = Frame("content"); pf.PlayerFrameContent.PlayerFrameContentMain = main
        pf.PlayerFrameContent.PlayerFrameContentContextual = Frame("ctx"); pf.PlayerFrameContent.PlayerFrameContentContextual.AttackIcon = Region("Texture"); pf.PlayerFrameContent.PlayerFrameContentContextual.PlayerPortraitCornerIcon = Region("Texture")
        _G.PlayerFrame = pf; _G.PlayerName = Region("FontString"); _G.PlayerLevelText = Region("FontString"); _G.GameNormalNumberFont = {}
        local function TargetLike(name, unit)
            local tf = Frame(name); tf.unit = unit
            tf.TargetFrameContainer = Frame("tcontainer")
            tf.TargetFrameContainer.FrameTexture = Region("Texture", {atlas = "UI-HUD-UnitFrame-Target-PortraitOn"})
            tf.TargetFrameContainer.Flash = Region("Texture"); tf.TargetFrameContainer.Portrait = Region("Texture"); tf.TargetFrameContainer.PortraitMask = Region("MaskTexture"); tf.TargetFrameContainer.BossPortraitFrameTexture = Region("Texture")
            local tmain = Frame("tmain"); tmain.ReputationColor = Region("Texture", {atlas = "type"}); tmain.Name = Region("FontString"); tmain.LevelText = Region("FontString"); tmain.LevelBackgroundCircle = Region("Texture")
            tmain.HealthBarsContainer = Frame("thc"); tmain.HealthBarsContainer.HealthBar = Frame("thb"); tmain.HealthBarsContainer.HealthBar.HealthBarMask = Region("MaskTexture")
            tmain.ManaBar = Frame("tmb"); tmain.ManaBar.ManaBarMask = Region("MaskTexture")
            tf.TargetFrameContent = Frame("tcontent"); tf.TargetFrameContent.TargetFrameContentMain = tmain
            tf.TargetFrameContent.TargetFrameContentContextual = Frame("tctx"); tf.TargetFrameContent.TargetFrameContentContextual.HighLevelTexture = Region("Texture")
            function tf:CheckClassification() self.TargetFrameContainer.FrameTexture:SetAtlas("UI-HUD-UnitFrame-Target-PortraitOn") end
            function tf:CheckFaction() end
            return tf
        end
        _G.TargetFrame = TargetLike("TargetFrame", "target"); _G.FocusFrame = TargetLike("FocusFrame", "focus")
        _G.UnitPowerType = function(u) return 0, "MANA" end
        _G.PowerBarColor = {MANA = {r = 0, g = 0, b = 1}, [0] = {r = 0, g = 0, b = 1}}
        _G.UnitClassification = function(u) return w.classification or "normal" end
        _G.UnitFrameManaBar_UpdateType = function(bar) bar:SetStatusBarTexture("UI-HUD-UnitFrame-Player-PortraitOn-Bar-Mana"); bar:SetStatusBarColor(1, 1, 1) end
        _G.PlayerFrame_ToPlayerArt = function() pf.PlayerFrameContainer.FrameTexture:SetAtlas("UI-HUD-UnitFrame-Player-PortraitOn") end
        -- action bar
        local bar = Frame("MainActionBar"); bar.BorderArt = Region("Texture", {atlas = "UI-HUD-ActionBar-Frame"})
        bar.EndCaps = {LeftEndCap = Frame("cap"), RightEndCap = Frame("cap")}
        for _, c in pairs(bar.EndCaps) do function c:SetVisibilitySetting(v) self.visibilitySetting = v end end
        _G.MainActionBar = bar
        _G.EditModeManagerFrame = {ExitEditMode = function() end}
        -- minimap
        _G.Minimap = Frame("Minimap"); _G.MinimapCluster = Frame("MinimapCluster"); _G.MinimapCluster.MinimapContainer = Frame("mc"); _G.MinimapCluster.BorderTop = Frame("BorderTop"); _G.MinimapCluster.DielFrame = Frame("Diel")
        _G.MinimapBackdrop = Frame("MinimapBackdrop"); _G.MinimapCompassTexture = Region("Texture", {atlas = "ui-hud-minimap-frame"}); _G.MinimapCompassTextureUnderlay = Region("Texture")
        -- Forever: level badge on every plate, Forever's constant names
        _G.NamePlateConstants.CLASSIC_NAMEPLATE_WIDTH = nil
        _G.NamePlateConstants.CLASSIC_NAME_PLATE_WIDTH = 152
        _G.NamePlateConstants.LEVEL_INDICATOR_WIDTH = 28
        _G.NamePlateConstants.SMALL_LEVEL_INDICATOR_HEIGHT = 16
        _G.NameplateLevelFrameMixin = {}
        for _, p in ipairs(w.plates) do
            local badge = Frame("badge"); badge.shown = true; badge:SetSize(23, 13)
            function badge:ShouldDisplay() return true end
            p.UnitFrame = {PlayerLevelDiffFrame = badge, anchorsUpdated = 0, HealthBarsContainer = Frame("hc"), CastBarsContainer = Frame("cc")}
            p.UnitFrame.HealthBarsContainer.healthBar = Frame("healthBar")
            p.UnitFrame.HealthBarsContainer.healthBar.bgTexture = Region("Texture", {file = "Interface\\Tooltips\\Nameplate-Border"})
            function p.UnitFrame:UpdateAnchors() self.anchorsUpdated = self.anchorsUpdated + 1 end
        end
        _G.NamePlateSetupOptions.castBarToHealthBarSpacing = 4
        _G.NamePlateSetupOptions.healthBarBorderWidth = 102.4
        _G.NamePlateSetupOptions.healthBarBorderHeight = 12.8
        _G.WOW_PROJECT_ID = 1 -- Forever reports itself as mainline
        _G.NamePlateDriverFrame.OnNamePlateAdded = function(self, token) w.added = token end
        _G.NamePlateDriverFrame.GetNamePlateForUnit = function(self, token) return w.plateByToken and w.plateByToken[token] end
        -- Forever protects unit values: an addon touching the nameplate code path is fatal
        _G.C_Secrets = {}
        _G.issecretvalue = function(v) return type(v) == "table" and v.__secret == true end
        _G.C_NamePlate.GetNamePlates = function() return w.plates end
        _G.C_NamePlate.GetNamePlateForUnit = function(token) return w.plateByToken and w.plateByToken[token] end
        _G.CastingBarTypeInfo = {
            [1] = {filling = "ui-castingbar-filling-standard", full = "ui-castingbar-full-standard", glow = "ui-castingbar-full-glow-standard", sparkFx = "StandardGlow",
                   classicFillColor = {GetRGB = function() return 1, 0.7, 0 end}, classicFullColor = {GetRGB = function() return 0, 1, 0 end}}
        }
        for _, bar in ipairs({PlayerCastingBarFrame, TargetFrameSpellBar}) do
            bar.barType = 1
            bar.StandardGlow = Frame("glow"); bar.StandardGlow:SetPoint("CENTER", bar, "CENTER", 0, 0)
            function bar:UpdateBarFillTexture(isFull)
                local info = CastingBarTypeInfo[self.barType]
                self:SetStatusBarTexture(isFull and info.full or info.filling)
                self:SetStatusBarColor(1, 1, 1)
            end
        end
    end
    w.combo = 0
    _G.GetComboPoints = function() return w.combo end
    _G.UnitPowerMax = function() return 5 end
    w.inCombat = opts.inCombat

    -- load the addon
    local ns = {}
    for _, file in ipairs({"Core.lua", "Nameplates.lua", "CastBar.lua", "Combo.lua", "UnitFrames.lua", "ActionBars.lua", "Minimap.lua", "Options.lua", "Probe.lua"}) do
        local chunk, err = loadfile(root .. "/ForeverClassicUI/" .. file)
        assert(chunk, err)
        chunk("ForeverClassicUI", ns)
    end
    w.ns = ns
    lastNs = ns
    -- login
    ns.eventFrame:Fire("ADDON_LOADED", "ForeverClassicUI")
    ns.eventFrame:Fire("PLAYER_LOGIN")
    w.slash = function(s) SlashCmdList["CLASSICUI"](s) end
    return w
end

local function Printed(pattern)
    for _, l in ipairs(printed) do if l:find(pattern, 1, true) then return true end end
    return false
end

--------------------------------------------------------------------------
-- 1. Classic Era style client: already classic, nothing to change
--------------------------------------------------------------------------
do
    local w = NewWorld({style = "6", classicBars = true})
    check(w.ns.modules.nameplates.mode == "cvar", "era: nameplates use the built-in style")
    check(w.cvars.nameplateStyle == "6", "era: cvar untouched")
    check(w.ns.db.savedNameplateStyle == nil, "era: nothing to restore")
    check(w.ns.modules.castbar.mode == "native", "era: cast bar recognised as classic already")
    check(PlayerCastingBarFrame.lookCalls == 0, "era: cast bar not touched")
    check(w.ns.modules.combo.mode == "native", "era: combo points left to Blizzard")
    check(w.ns.modules.unitframes.mode == "native" and w.ns.modules.actionbars.mode == "native" and w.ns.modules.minimap.mode == "native", "era: frames, bars and minimap left to Blizzard")
    check(w.ns.modules.combo.frame == nil and ComboFrame.parent == nil, "era: no combo frame built, Blizzard's untouched")
    check(#w.ns.errors == 0, "era: no errors")
end

--------------------------------------------------------------------------
-- 1b. Era reports the border texture as a file id, not a path
--------------------------------------------------------------------------
do
    local w = NewWorld({style = "6", classicBars = true})
    PlayerCastingBarFrame.Border.texture = 130874
    _G.GetFileIDFromPath = function(p) if p == "Interface\\CastingBar\\UI-CastingBar-Border" then return 130874 end end
    w.ns.modules.castbar.mode = "off"
    w.ns.modules.castbar:Enable()
    check(w.ns.modules.castbar.mode == "native", "era: classic cast bar recognised by file id")
end

--------------------------------------------------------------------------
-- 2. Client that accepts the CVar but had another style selected
--------------------------------------------------------------------------
do
    local w = NewWorld({style = "0", classicBars = true})
    check(w.ns.modules.nameplates.mode == "cvar", "switch: cvar path used")
    check(w.cvars.nameplateStyle == "6", "switch: cvar set to classic")
    check(w.ns.db.savedNameplateStyle == "0", "switch: previous style remembered")
    w.slash("nameplates off")
    check(w.cvars.nameplateStyle == "0", "switch: off restores the previous style")
    check(w.ns.db.nameplates == false, "switch: off is saved")
    w.slash("nameplates on")
    check(w.cvars.nameplateStyle == "6", "switch: on puts classic back")
end

--------------------------------------------------------------------------
-- 3. Retail-style client (what Forever may look like): CVar refused
--------------------------------------------------------------------------
do
    local w = NewWorld({style = "0", maxStyle = 5, noClassicEnum = true})
    local np = w.ns.modules.nameplates
    check(np.mode == "override", "retail: fell back to Lua override")
    check(w.cvars.nameplateStyle == "0", "retail: cvar left alone after refusal")
    local o = NamePlateSetupOptions
    check(o.useClassicHealthBar == true and o.useClassicCastBar == true, "retail: classic bars forced")
    check(o.unitNameAnchorStyle == 3, "retail: name centered above the bar")
    check(o.spellNameInsideCastBar == true and o.hideIconWhenNotInterruptible == false, "retail: classic cast bar options")
    check(o.healthBarBorderWidth == 128 and o.healthBarBorderHeight == 16, "retail: border art size")
    check(NamePlateEnemyFrameOptions.showLevel == true and NamePlateFriendlyFrameOptions.showLevel == true, "retail: level shown in the border")
    check(NamePlateEnemyFrameOptions.nameMouseoverColor == YELLOW_FONT_COLOR, "retail: yellow mouseover name")
    local last = w.sizes[#w.sizes]
    check(last and last[1] == 152 and last[2] == 25 + 3 + 10 + 10 + 10, "retail: plate size sent to the client")
    check(w.plateApplies == 2, "retail: every visible plate re-laid out")

    -- Blizzard re-runs its options (cvar change, resolution change)
    NamePlateDriverFrame:UpdateNamePlateOptions()
    check(NamePlateSetupOptions.useClassicHealthBar == true, "retail: hook re-applies after Blizzard resets")
    check(w.plateApplies == 4, "retail: plates re-laid out again")

    -- in combat the size call is deferred until combat ends
    w.inCombat = true
    local before = #w.sizes
    NamePlateDriverFrame:UpdateNamePlateOptions()
    check(#w.sizes == before + 1, "retail: no SetNamePlateSize in combat")
    w.inCombat = false
    for _, f in ipairs(w.frames) do if f.events["PLAYER_REGEN_ENABLED"] then f:Fire("PLAYER_REGEN_ENABLED") end end
    check(#w.sizes == before + 2 and w.sizes[#w.sizes][1] == 152, "retail: deferred size applied after combat")

    -- larger nameplate size setting scales the classic layout
    w.cvars.nameplateSize = "2"
    NamePlateDriverFrame:UpdateNamePlateOptions()
    check(math.abs(NamePlateSetupOptions.healthBarHeight - 12.5) < 0.001, "retail: nameplateSize Large scales bars")
    check(w.sizes[#w.sizes][1] == 190, "retail: width scales with size setting")

    -- cast bars re-skinned
    local cb = w.ns.modules.castbar
    check(cb.mode == "restyled", "retail: cast bars re-skinned")
    local bar = PlayerCastingBarFrame
    check(bar.classicStyleCastBar == false and bar.playCastFX == nil, "retail: no Lua fields written into Blizzard's cast bar (taint)")
    check(bar.Border.texture == "Interface\\CastingBar\\UI-CastingBar-Border", "retail: classic border art")
    check(bar.Flash.texture == "Interface\\CastingBar\\UI-CastingBar-Flash", "retail: classic flash art")
    check(bar.Spark.texture == "Interface\\CastingBar\\UI-CastingBar-Spark" and bar.Spark.offsetY == nil, "retail: classic spark")
    check(bar.width == 195 and bar.height == 13, "retail: classic player bar size")
    check(bar.TextBorder.shown == false and bar.DropShadow.shown == false and bar.StandardGlow.shown == false, "retail: modern art hidden")
    check(bar.fill.texture == "Interface\\TargetingFrame\\UI-StatusBar", "retail: classic fill texture")
    check(bar.fill.maskRemoved == bar.BorderMask, "retail: modern fill mask removed")
    check(bar.Background.color ~= nil, "retail: plain dark background")
    local tb = TargetFrameSpellBar
    check(tb.Border.texture == "Interface\\CastingBar\\UI-CastingBar-Border-Small", "retail: small border on the target bar")
    check(tb.width == 150 and tb.height == 10, "retail: target bar size")

    -- Blizzard re-applies its look (edit mode) -> we re-skin
    bar:SetLook("CLASSIC")
    check(bar.classicStyleCastBar == false and bar.Border.texture == "Interface\\CastingBar\\UI-CastingBar-Border", "retail: re-skin after Blizzard SetLook")

    -- probe report
    local text = w.ns.ShowProbe()
    check(type(text) == "string" and text:find("nameplateStyle cvar: 0", 1, true), "probe: reports the cvar")
    check(text:find("mode=override", 1, true) and text:find("mode=restyled", 1, true), "probe: reports module modes")
    check(text:find("nameplates: setting=on mode=override", 1, true) and text:find("minimap: setting=", 1, true), "probe: lists every part's saved setting and mode")
    check(text:find("UI-CastingBar-Border: MISSING", 1, true), "probe: flags textures the client lacks")
    check(text:find("Nameplate-Border: id 130000", 1, true), "probe: lists textures the client has")
    check(text:find("errors recorded", 1, true) and text:find("none", 1, true), "probe: no errors")
    check(Printed("probe window opened"), "probe: told the player what to do")
    check(text:find("RogueComboPointBarFrame (modern): yes", 1, true) and text:find("mode=restyled", 1, true), "probe: reports combo state")

    -- combo points
    local combo = w.ns.modules.combo
    check(combo.mode == "restyled", "retail: classic combo points drawn")
    local modern = RogueComboPointBarFrame
    check(modern.shown == false and modern.parent ~= nil and modern.parent.shown == false and next(modern.events) == nil, "retail: modern combo bar parked on a hidden frame")
    check(ComboFrame.parent ~= nil and ComboFrame.shown == false, "retail: Blizzard's leftover ComboFrame parked too")
    local cf = combo.frame
    check(cf ~= nil and cf.shown == false and #cf.points == 5, "retail: our five-dot frame exists, hidden")
    check(cf.width == 256 and cf.height == 32, "retail: frame is classic size")
    local function LastAnchor(region) return region.anchors[#region.anchors] end
    local a1, a5 = LastAnchor(cf.points[1]), LastAnchor(cf.points[5])
    check(a1[4] == 0 and a1[5] == 0 and a5[4] == 13 and a5[5] == -40, "retail: dots follow the classic arc offsets")
    local fa = LastAnchor(cf)
    check(fa[2] == TargetFrame and fa[4] == -26 and fa[5] == -13, "retail: frame anchored to the target frame at the classic offset")
    check(cf.points[1].Highlight.alpha == 0, "retail: dots start unlit")
    w.combo = 3
    cf:Fire("UNIT_POWER_FREQUENT", "player")
    check(cf.shown == true and cf.alpha == 1, "retail: frame shows with points")
    check(cf.points[1].Highlight.alpha == 1 and cf.points[3].Highlight.alpha == 1 and cf.points[4].Highlight.alpha == 0, "retail: three dots lit, two dark")
    cf:Fire("UNIT_POWER_FREQUENT", "target")
    check(cf.points[3].Highlight.alpha == 1, "retail: other units' power ignored")
    w.combo = 5
    cf:Fire("UNIT_POWER_FREQUENT", "player")
    check(cf.points[5].Highlight.alpha == 1, "retail: all five lit")
    w.combo = 0
    cf:Fire("PLAYER_TARGET_CHANGED")
    check(cf.shown == false and cf.points[5].Highlight.alpha == 0, "retail: hidden and cleared when points drop to zero")

    -- modern target frame gets the retail offset, nudged by the offset command
    TargetFrame.TargetFrameContainer = {}
    w.slash("combo offset 5 -3")
    check(w.ns.db.comboOffset.x == 5 and w.ns.db.comboOffset.y == -3, "combo offset saved")
    fa = LastAnchor(cf)
    check(fa[4] == -44 + 5 and fa[5] == -9 - 3, "combo offset applied on top of the modern-frame anchor")
    check(Printed("offset set to 5, -3"), "combo offset acknowledged")
    w.slash("combo offset")
    check(w.ns.db.comboOffset == nil and Printed("offset reset"), "combo offset reset")
    check(#w.ns.errors == 0, "retail: no errors")
end

--------------------------------------------------------------------------
-- 3b. Retail-style client logging in during combat: parking is deferred
--------------------------------------------------------------------------
do
    local w = NewWorld({style = "0", maxStyle = 5, inCombat = true})
    local modern = RogueComboPointBarFrame
    check(modern.parent == nil and modern.shown == true, "combat: protected bar left alone in combat")
    w.inCombat = false
    w.ns.modules.combo.frame:Fire("PLAYER_REGEN_ENABLED")
    check(modern.parent ~= nil and modern.shown == false, "combat: bar parked once combat ends")
    check(#w.ns.errors == 0, "combat: no errors")
end

--------------------------------------------------------------------------
-- 3c. WoW Forever (Camelot flavor): retail engine, no Classic enum, level
--     badges on plates, ComboFrame gated behind a CVar
--------------------------------------------------------------------------
do
    local w = NewWorld({style = "1", maxStyle = 5, noClassicEnum = true, forever = true})
    local np = w.ns.modules.nameplates
    -- the addon must not set the CVar or touch Blizzard's option tables here
    check(np.mode == "console", "forever: waits for the player to type the console command")
    check(w.cvars.nameplateStyle == "1", "forever: nameplateStyle left alone (an addon SetCVar taints the callback)")
    check(NamePlateSetupOptions.useClassicHealthBar == false, "forever: Blizzard's option tables untouched")
    check(Printed("/console nameplateStyle 6"), "forever: console command printed at login")
    for i, p in ipairs(w.plates) do
        check(p.UnitFrame.PlayerLevelDiffFrame.alpha == 1 and p.UnitFrame.anchorsUpdated == 0, "forever: plate " .. i .. " untouched while waiting")
    end
    -- the player types it: the CVar changes, the badge goes invisible
    printed = {}
    w.cvars.nameplateStyle = "6"
    np.watcher:Fire("CVAR_UPDATE", "nameplateStyle", "6")
    check(np.mode == "cvar" and Printed("classic style on"), "forever: switches to the CVar mode when the style arrives")
    for i, p in ipairs(w.plates) do
        local b = p.UnitFrame.PlayerLevelDiffFrame
        check(b.alpha == 0, "forever: level badge invisible on plate " .. i)
        check(b.width == 0, "forever: badge width zeroed on plate " .. i .. " so the layout reserves no room")
        b:SetSize(23, 13) -- Blizzard's ApplyFrameOptions sizing it again
        check(b.width == 0 and b.height == 13, "forever: secure hook zeroes the badge width again on plate " .. i)
        local a = p.UnitFrame.HealthBarsContainer.anchors[#p.UnitFrame.HealthBarsContainer.anchors]
        check(a and a[1] == "BOTTOMRIGHT" and a[2] == p.UnitFrame.CastBarsContainer and a[4] == 0 and a[5] == 4, "forever: health container given its full width back on plate " .. i)
        local bg = p.UnitFrame.HealthBarsContainer.healthBar.bgTexture
        check(bg.texcoord and bg.texcoord[2] == 136 / 256 and bg.texcoord[3] == 0.5 and math.abs(bg.width - 108.8) < 0.01 and bg.anchors[1][1] == "LEFT", "forever: retail border image cropped to its art and left-aligned on plate " .. i)
        bg:SetTexCoord(0, 1, 0.5, 1); bg:ClearAllPoints(); bg:SetPoint("CENTER", p.UnitFrame.HealthBarsContainer, "CENTER", 0, 0); bg:SetSize(102.4, 12.8) -- Blizzard re-laying out
        check(bg.texcoord[2] == 136 / 256 and math.abs(bg.width - 108.8) < 0.01 and bg.anchors[1][1] == "LEFT" and #bg.anchors == 1, "forever: border crop re-applied after Blizzard's SetSize on plate " .. i)
        check(p.UnitFrame.PlayerLevelDiffFrame.forevercuiPatched == nil and p.UnitFrame.PlayerLevelDiffFrame:ShouldDisplay() == true and p.UnitFrame.anchorsUpdated == 0, "forever: plate " .. i .. " Lua tables untouched")
    end
    -- a plate added later: only the badge alpha changes
    local late = {ApplyFrameOptions = function() end}
    local badge = Frame("badge"); badge:SetSize(23, 13)
    late.UnitFrame = {PlayerLevelDiffFrame = badge, anchorsUpdated = 0, HealthBarsContainer = Frame("hc"), CastBarsContainer = Frame("cc")}
    function late.UnitFrame:UpdateAnchors() self.anchorsUpdated = self.anchorsUpdated + 1 end
    w.plateByToken = {nameplate9 = late}
    table.insert(w.plates, late) -- C_NamePlate.GetNamePlates lists it from now on
    np.watcher:Fire("NAME_PLATE_UNIT_ADDED", "nameplate9")
    check(badge.alpha == 0 and badge.width == 0 and late.UnitFrame.anchorsUpdated == 0 and badge.forevercuiPatched == nil, "forever: late plate badge hidden and zero-width, no Lua fields, no Blizzard calls")
    -- Forever's settings page writes Thin back: no fighting it, tell the player
    printed = {}
    w.cvars.nameplateStyle = "1"
    np.watcher:Fire("CVAR_UPDATE", "nameplateStyle", "1")
    check(np.mode == "console" and w.cvars.nameplateStyle == "1", "forever: style change accepted, back to waiting")
    check(Printed("/console nameplateStyle 6"), "forever: console command printed again")
    check(badge.alpha == 1 and w.plates[1].UnitFrame.PlayerLevelDiffFrame.alpha == 1, "forever: badges restored while waiting")
    w.cvars.nameplateStyle = "6"
    np.watcher:Fire("CVAR_UPDATE", "nameplateStyle", "6")
    check(np.mode == "cvar" and badge.alpha == 0, "forever: back on when the player types it again")
    -- size: same rule, tell the player the console command
    _G.Enum.NamePlateSize.ExtraLarge = 3; _G.Enum.NamePlateSize.Huge = 4
    printed = {}
    w.slash("nameplates size large")
    check(w.cvars.nameplateSize == "1" and Printed("/console nameplateSize 2"), "forever: size command prints the console command instead of setting it")
    -- the Lua fallback is refused on this client
    printed = {}
    w.slash("nameplates force")
    check(np.mode == "cvar" and NamePlateSetupOptions.useClassicHealthBar == false and Printed("fallback unavailable"), "forever: Lua fallback refused")
    -- off: badges back, no CVar write
    w.slash("nameplates off")
    check(np.mode == "off" and badge.alpha == 1 and w.cvars.nameplateStyle == "6", "forever: off restores badges, leaves the CVar")
    w.slash("nameplates on")
    check(np.mode == "cvar" and badge.alpha == 0, "forever: on again")

    local combo = w.ns.modules.combo
    check(combo.mode == "native" and combo.enabledBlizzard == true, "forever: Blizzard's classic combo frame used, switched on")
    check(w.cvars.comboPointLocation == "1" and w.comboLoaded == true and ComboFrame:IsEventRegistered("UNIT_POWER_FREQUENT"), "forever: comboPointLocation set to 1 and ComboFrame_OnLoad re-run")
    check(combo.frame == nil, "forever: no duplicate combo frame drawn")
    local p1, p5 = ComboFrame.ComboPoints[1].anchors[1], ComboFrame.ComboPoints[5].anchors[1]
    check(p1[4] == 0 and p1[5] == 0 and p5[4] == 13 and p5[5] == -40 and #ComboFrame.ComboPoints[1].anchors == 1, "forever: Blizzard's dots moved onto Era's arc")
    check(ComboFrame.anchors[1][2] == TargetFrame and ComboFrame.anchors[1][4] == -26 and ComboFrame.anchors[1][5] == -13, "forever: ComboFrame at Era's anchor")
    w.slash("combo offset 2 -3")
    check(ComboFrame.ComboPoints[5].anchors[1][4] == 15 and ComboFrame.ComboPoints[5].anchors[1][5] == -43, "forever: offset nudges Blizzard's dots")
    w.slash("combo offset")
    check(ComboFrame.ComboPoints[5].anchors[1][4] == 13, "forever: offset reset")
    check(w.ns.modules.castbar.mode == "restyled" and PlayerCastingBarFrame.Border.texture == "Interface\\CastingBar\\UI-CastingBar-Border", "forever: cast bar re-skinned")
    local pcb = PlayerCastingBarFrame
    check(pcb.classicStyleCastBar == false and pcb.playCastFX == nil and pcb.Spark.offsetY == nil, "forever: no Lua fields written into Blizzard's cast bar")
    check(#pcb.TextBorder.anchors == 0 and pcb.TextBorder.alpha == 0 and #pcb.StandardGlow.anchors == 0, "forever: modern-only cast bar art left without anchors")
    check(pcb.fill.texture == "Interface\\TargetingFrame\\UI-StatusBar" and pcb.barColor[1] == 1 and pcb.barColor[2] == 0.7, "forever: classic yellow fill")
    pcb:UpdateBarFillTexture(true)
    check(pcb.fill.texture == "Interface\\TargetingFrame\\UI-StatusBar" and pcb.barColor[2] == 1 and pcb.barColor[1] == 0, "forever: Blizzard's fill atlas replaced by the classic green full fill")
    pcb.Flash:SetAtlas("ui-castingbar-full-glow-standard")
    check(pcb.Flash.texture == "Interface\\CastingBar\\UI-CastingBar-Flash" and pcb.Flash.atlas == nil, "forever: flash atlas replaced by the classic flash")
    pcb.Spark:SetAtlas("ui-castingbar-pip")
    check(pcb.Spark.texture == "Interface\\CastingBar\\UI-CastingBar-Spark" and pcb.Spark.width == 32, "forever: spark atlas replaced by the classic spark")
    TargetFrameSpellBar.Flash:SetAtlas("ui-castingbar-full-glow-standard")
    check(TargetFrameSpellBar.Flash.texture == "Interface\\CastingBar\\UI-CastingBar-Flash-Small", "forever: target bar keeps the small classic flash")

    -- unit frames
    local uf = w.ns.modules.unitframes
    check(uf.mode == "restyled", "forever: unit frames re-skinned")
    local pc = PlayerFrame.PlayerFrameContainer
    check(pc.FrameTexture.texture == "Interface\\TargetingFrame\\UI-TargetingFrame" and pc.FrameTexture.width == 193 and pc.FrameTexture.height == 77, "forever: player frame uses the classic (mirrored) art")
    local pm = PlayerFrame.PlayerFrameContent.PlayerFrameContentMain
    check(pm.HealthBarsContainer.width == 119 and pm.HealthBarsContainer.height == 12 and pm.HealthBarsContainer.HealthBar.barTexture == "Interface\\TargetingFrame\\UI-StatusBar", "forever: player health bar is 119x12 classic")
    check(pm.HealthBarsContainer.HealthBar.fill.maskRemoved == pm.HealthBarsContainer.HealthBar.HealthBarMask, "forever: retail health mask removed")
    local hmask = pm.HealthBarsContainer.HealthBar.HealthBarMask
    check(hmask.texture == "Interface\\Buttons\\WHITE8x8" and #hmask.anchors == 2 and hmask.shown == false, "forever: retail health mask made a harmless white square over the bar")
    check(pm.ManaBarArea.ManaBar.ManaBarMask.texture == "Interface\\Buttons\\WHITE8x8", "forever: retail mana mask neutralised too")
    check(pm.ManaBarArea.ManaBar.barTexture == "Interface\\TargetingFrame\\UI-StatusBar" and pm.ManaBarArea.ManaBar.barColor[3] == 1, "forever: mana bar classic texture, coloured by power type")
    check(pm.LevelBackgroundCircle.shown == false and pc.forevercuiBackdrop ~= nil, "forever: level circle hidden, dark backdrop added")
    local tc = TargetFrame.TargetFrameContainer
    check(tc.FrameTexture.texture == "Interface\\TargetingFrame\\UI-TargetingFrame" and tc.BossPortraitFrameTexture.shown == false, "forever: target frame classic art")
    local tm = TargetFrame.TargetFrameContent.TargetFrameContentMain
    check(tm.ReputationColor.texture == "Interface\\TargetingFrame\\UI-TargetingFrame-LevelBackground" and tm.HealthBarsContainer.width == 119, "forever: target name strip and health bar classic")
    check(FocusFrame.TargetFrameContainer.FrameTexture.texture == "Interface\\TargetingFrame\\UI-TargetingFrame", "forever: focus frame too")
    -- Blizzard redraws: elite target, mana type change, player art reset
    w.classification = "elite"
    TargetFrame:CheckClassification()
    check(tc.FrameTexture.texture == "Interface\\TargetingFrame\\UI-TargetingFrame-Elite", "forever: elite target gets the classic elite art after Blizzard's redraw")
    -- Blizzard's CheckClassification also resizes the health container to 126x20 and puts its atlas fill back
    tm.HealthBarsContainer:SetSize(126, 20); tm.HealthBarsContainer.HealthBar:SetStatusBarTexture("UI-HUD-UnitFrame-Target-PortraitOn-Bar-Health")
    TargetFrame:CheckClassification()
    check(tm.HealthBarsContainer.width == 119 and tm.HealthBarsContainer.height == 12 and tm.HealthBarsContainer.HealthBar.barTexture == "Interface\\TargetingFrame\\UI-StatusBar", "forever: classic bar size and fill restored after Blizzard's classification update")
    w.inCombat = true
    tm.HealthBarsContainer:SetSize(126, 20); tm.HealthBarsContainer.HealthBar:SetStatusBarTexture("atlas")
    TargetFrame:CheckClassification()
    check(tm.HealthBarsContainer.width == 126 and tm.HealthBarsContainer.HealthBar.barTexture == "Interface\\TargetingFrame\\UI-StatusBar", "forever: in combat only the fill changes, layout waits")
    w.inCombat = false
    uf.barWaiter:Fire("PLAYER_REGEN_ENABLED")
    check(tm.HealthBarsContainer.width == 119, "forever: layout applied once combat ends")
    UnitFrameManaBar_UpdateType(pm.ManaBarArea.ManaBar)
    check(pm.ManaBarArea.ManaBar.barTexture == "Interface\\TargetingFrame\\UI-StatusBar", "forever: mana texture restored after Blizzard's power-type update")
    PlayerFrame_ToPlayerArt()
    check(pc.FrameTexture.texture == "Interface\\TargetingFrame\\UI-TargetingFrame", "forever: player art restored after Blizzard's art swap")

    -- action bar + minimap
    check(w.ns.modules.actionbars.mode == "restyled" and MainActionBar.BorderArt.shown == false and w.ns.modules.actionbars.art ~= nil, "forever: retail bar border hidden, classic bar art added")
    check(MainActionBar.EndCaps.LeftEndCap.visibilitySetting == true, "forever: gryphons forced on")
    local tiles = w.ns.modules.actionbars.art.tiles
    check(tiles[1].texcoord[3] == 0.83203125 and tiles[1].texcoord[4] == 1.0 and tiles[2].texcoord[3] == 0.58203125 and tiles[2].texcoord[4] == 0.75, "forever: bar tiles use Era's two button-slot strips of the 256x256 image")
    check(w.ns.modules.minimap.mode == "restyled" and Minimap.width == 140 and MinimapCompassTexture.texture == "Interface\\Minimap\\UI-Minimap-Border", "forever: minimap 140px with the classic ring")
    check(w.ns.modules.minimap.header ~= nil and MinimapCluster.DielFrame.shown == false, "forever: classic header strip added, day/night dial hidden")

    -- options panel
    local panel = w.ns.optionsPanel
    check(panel ~= nil and panel.checks.unitframes ~= nil and panel.checks.minimap ~= nil, "forever: options panel lists every part")
    panel.Refresh()
    check(panel.checks.nameplates.checked == true, "forever: panel reflects settings")
    panel.checks.minimap:Click()
    check(w.ns.db.minimap == false and w.ns.modules.minimap.mode == "off", "forever: unticking a part turns it off")
    w.slash("options")
    check(_G.__openedCategory == "cat_Classic UI for Forever", "forever: /cui options opens the panel")
    check(#w.ns.errors == 0, "forever: no errors")
end

--------------------------------------------------------------------------
-- 3d. WoW Forever with the console command already typed on an earlier
--     login: straight to the CVar mode, plus the /cui dump diagnostic
--------------------------------------------------------------------------
do
    local w = NewWorld({style = "6", forever = true})
    local np = w.ns.modules.nameplates
    check(np.mode == "cvar" and w.cvars.nameplateStyle == "6", "beta: CVar mode straight away")
    check(not Printed("/console nameplateStyle 6"), "beta: no nag when the style is already classic")
    for i, p in ipairs(w.plates) do
        check(p.UnitFrame.PlayerLevelDiffFrame.alpha == 0 and p.UnitFrame.anchorsUpdated == 0, "beta: badge invisible on plate " .. i .. ", nothing else touched")
    end
    np.watcher:Fire("CVAR_UPDATE", "someOtherCVar", "x")
    check(np.mode == "cvar", "beta: unrelated CVars ignored")

    -- /cui dump lists the target frame's visible pieces with art and anchors
    w.slash("dump TargetFrame")
    local dump = w.ns.lastDump
    check(type(dump) == "string" and dump:find("dump of TargetFrame", 1, true), "beta: dump opens for TargetFrame")
    check(dump:find("FrameTexture", 1, true) and dump:find("UI-TargetingFrame", 1, true), "beta: dump shows the classic frame texture")
    check(dump:find("ReputationColor", 1, true) and dump:find("TOPRIGHT>", 1, true), "beta: dump shows anchors of restyled regions")
    check(dump:find("HealthBar  StatusBar", 1, true) or dump:find("HealthBar  Frame", 1, true), "beta: dump walks into child frames")
    w.slash("dump targetframe")
    check(w.ns.lastDump:find("dump of TargetFrame", 1, true), "beta: dump finds frames typed in the wrong case")
    w.slash("dump NoSuchFrame")
    check(Printed("no frame called NoSuchFrame"), "beta: dump reports unknown frames")
    -- the target's nameplate by unit token
    local plate = Frame("NamePlate7"); plate.UnitFrame = Frame("uf"); plate.UnitFrame.name = Region("FontString"); plate.UnitFrame.name:SetText("Young Wolf")
    w.plateByToken = {target = plate}
    w.slash("dump target")
    check(w.ns.lastDump:find("dump of NamePlate7 (target)", 1, true) and w.ns.lastDump:find('text="Young Wolf"', 1, true), "beta: dump target walks the target's nameplate")
    w.plateByToken = {}
    w.slash("dump target")
    check(Printed("no nameplate showing for target"), "beta: dump target with no plate says so")
    -- secret values: sizes and texts that cannot be read are marked, not fatal
    local secretRegion = TargetFrame.TargetFrameContent.TargetFrameContentMain.Name
    function secretRegion:GetSize() error("attempt to perform arithmetic on a secret value") end
    function secretRegion:GetText() return {__secret = true} end
    w.slash("dump TargetFrame")
    check(w.ns.lastDump:find("Name  FontString  <secret>", 1, true) and not Printed("dump hit an error"), "beta: dump survives secret values")
    check(#w.ns.errors == 0, "beta: no errors")
end

--------------------------------------------------------------------------
-- 4. Status, help and a module that explodes on an unknown client
--------------------------------------------------------------------------
do
    local w = NewWorld({style = "6", classicBars = true})
    w.slash("")
    check(Printed("nameplates:") and Printed("built-in Classic style"), "status lists nameplates")
    check(Printed("castbar:") and Printed("already draws the classic cast bar"), "status lists cast bar")
    w.slash("help")
    check(Printed("/cui probe"), "help mentions probe")

    -- castbar force on a classic client re-skins without errors
    w.slash("castbar force")
    check(Printed("re-skinned 2 bar(s)"), "force re-skins both bars")
    check(PlayerCastingBarFrame.Border.texture == "Interface\\CastingBar\\UI-CastingBar-Border", "force keeps classic art")

    -- nameplates force uses the override even though the cvar works
    w.slash("nameplates force")
    check(w.ns.modules.nameplates.mode == "override" and NamePlateSetupOptions.useClassicHealthBar == true, "force applies the override")

    -- combo force on a classic client swaps Blizzard's frame for ours
    w.slash("combo force")
    check(Printed("classic combo points drawn"), "combo force acknowledged")
    check(w.ns.modules.combo.frame ~= nil and ComboFrame.parent ~= nil, "combo force builds ours and parks Blizzard's")
end

do
    -- a broken module must not stop the others from loading
    local w
    local ok = pcall(function()
        w = NewWorld({style = "6", classicBars = true})
    end)
    check(ok, "world builds")
    w.ns.RegisterModule("boom", {Enable = function() error("no such frame") end})
    w.ns.db.boom = true
    w.ns.OnLogin()
    check(#w.ns.errors == 1 and w.ns.errors[1]:find("boom"), "error captured")
    check(Printed("recorded for /cui probe"), "error reported to chat")
    check(w.ns.modules.castbar.mode == "native", "other modules still ran")
end

--------------------------------------------------------------------------
-- 5. Client with no nameplate driver at all
--------------------------------------------------------------------------
do
    local w = NewWorld({style = "0", maxStyle = 5})
    _G.NamePlateDriverFrame = nil
    w.ns.modules.nameplates.hooked = nil
    w.ns.modules.nameplates:Enable()
    check(w.ns.modules.nameplates.mode == "unavailable", "no driver: reported unavailable")
    check(Printed("could not restyle"), "no driver: asks for a probe")
end

realPrint(("Forever Classic UI harness: %d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
