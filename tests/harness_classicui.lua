-- Offline harness for the Classic UI addon (Lua 5.1, no game needed).
--   lua5.1 tests/harness_classicui.lua .
-- Stubs just enough of the WoW API to load the addon and drives it through
-- the two client shapes it has to cope with: a Classic client that already
-- has the classic style (nothing to do) and a retail-style client that hides
-- it (CVar refused, Lua fallback + cast bar re-skin).

local root = arg and arg[1] or "."
local realPrint = print
local passed, failed = 0, 0
local function check(cond, label)
    if cond then
        passed = passed + 1
    else
        failed = failed + 1
        realPrint("FAIL: " .. label)
    end
end

--------------------------------------------------------------------------
-- fake frames / regions
--------------------------------------------------------------------------

local function Region(kind, init)
    local r = {
        kind = kind, points = {}, shown = true, alpha = 1, width = 0,
        height = 0, texture = init and init.file, atlas = init and init.atlas
    }
    function r:SetTexture(t) self.texture = t; self.atlas = nil end
    function r:GetTexture() return self.texture end
    function r:SetAtlas(a) self.atlas = a; self.texture = nil end
    function r:GetAtlas() return self.atlas end
    function r:SetTexCoord() end
    function r:SetColorTexture(...) self.color = {...}; self.texture = nil; self.atlas = nil end
    function r:SetVertexColor(...) self.vertex = {...} end
    function r:SetBlendMode(m) self.blend = m end
    function r:SetSize(w, h) self.width, self.height = w, h end
    function r:SetWidth(w) self.width = w end
    function r:SetHeight(h) self.height = h end
    function r:GetWidth() return self.width end
    function r:GetHeight() return self.height end
    function r:ClearAllPoints() self.points = {} end
    function r:SetPoint(...) table.insert(self.points, {...}) end
    function r:SetAllPoints(rel) self.points = {{"ALL", rel}} end
    function r:Show() self.shown = true end
    function r:Hide() self.shown = false end
    function r:IsShown() return self.shown end
    function r:SetAlpha(a) self.alpha = a end
    function r:SetFontObject(f) self.font = f end
    function r:SetText(t) self.text = t end
    function r:GetText() return self.text end
    function r:RemoveMaskTexture(m) self.maskRemoved = m end
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
    _G.hooksecurefunc = function(tbl, name, hook)
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

    -- load the addon
    local ns = {}
    for _, file in ipairs({"Core.lua", "Nameplates.lua", "CastBar.lua", "Probe.lua"}) do
        local chunk, err = loadfile(root .. "/ClassicUI/" .. file)
        assert(chunk, err)
        chunk("ClassicUI", ns)
    end
    w.ns = ns
    -- login
    ns.eventFrame:Fire("ADDON_LOADED", "ClassicUI")
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
    check(#w.ns.errors == 0, "era: no errors")
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
    check(bar.classicStyleCastBar == true, "retail: classic flag set so Blizzard code uses classic colors")
    check(bar.Border.texture == "Interface\\CastingBar\\UI-CastingBar-Border", "retail: classic border art")
    check(bar.Flash.texture == "Interface\\CastingBar\\UI-CastingBar-Flash", "retail: classic flash art")
    check(bar.Spark.texture == "Interface\\CastingBar\\UI-CastingBar-Spark" and bar.Spark.offsetY == 2, "retail: classic spark")
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
    check(bar.classicStyleCastBar == true and bar.Border.texture == "Interface\\CastingBar\\UI-CastingBar-Border", "retail: re-skin after Blizzard SetLook")

    -- probe report
    local text = w.ns.ShowProbe()
    check(type(text) == "string" and text:find("nameplateStyle cvar: 0", 1, true), "probe: reports the cvar")
    check(text:find("mode=override", 1, true) and text:find("mode=restyled", 1, true), "probe: reports module modes")
    check(text:find("UI-CastingBar-Border: MISSING", 1, true), "probe: flags textures the client lacks")
    check(text:find("Nameplate-Border: id 130000", 1, true), "probe: lists textures the client has")
    check(text:find("errors recorded", 1, true) and text:find("none", 1, true), "probe: no errors")
    check(Printed("probe window opened"), "probe: told the player what to do")
    check(#w.ns.errors == 0, "retail: no errors")
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

realPrint(("Classic UI harness: %d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
