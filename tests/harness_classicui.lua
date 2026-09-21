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
        height = 0, texture = init and init.file, atlas = init and init.atlas,
        layer = init and init.layer
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
    function r:GetFontObject() return self.font end
    function r:SetJustifyH(j) self.justify = j end
    function r:SetTextureSliceMargins() end
    function r:SetDrawLayer(l) self.layer = l end
    function r:SetText(t) self.text = t end
    function r:GetText() return self.text end
    function r:SetTextColor(...) self.textColor = {...} end
    function r:GetTextColor() if self.textColor then return unpack(self.textColor) end return 1, 1, 1, 1 end
    function r:SetJustifyV(j) self.justifyV = j end
    function r:SetWordWrap() end
    function r:GetStringWidth() return self.text and (#tostring(self.text) * 6) or 0 end
    function r:RemoveMaskTexture(m) self.maskRemoved = m end
    function r:SetShown(v) self.shown = v and true or false end
    -- read-back API used by /cui dump
    function r:GetObjectType() return self.objectType or self.kind end
    function r:GetSize() return self.width, self.height end
    function r:GetName() return self.name end
    function r:GetNumPoints() return #self.anchors end
    function r:GetPoint(i) local a = self.anchors[i or 1]; if a then return unpack(a) end end
    function r:GetVertexColor() if self.vertex then return unpack(self.vertex) end return 1, 1, 1, 1 end
    function r:GetAlpha() return self.alpha end
    function r:GetDrawLayer() return self.layer or "ARTWORK", 0 end
    function r:GetTexCoord() local c = self.texcoord; if c then return c[1], c[3], c[1], c[4], c[2], c[3], c[2], c[4] end return 0, 0, 0, 1, 1, 0, 1, 1 end
    function r:GetBlendMode() return self.blend or "BLEND" end
    function r:GetFont() return "Fonts\\FRIZQT__.TTF", 12, "" end
    return r
end

-- protected frames (unit frames, the spell window and its page): in the
-- client, sizing or anchoring one in combat is blocked and reported to
-- the player as an addon fault. Here every such call on a frame marked
-- protectedFrame while InCombatLockdown() is counted, Blizzard's own
-- included (the tests reset the count after standing in for Blizzard).
local blocked = 0
local function Frame(name)
    local f = Region("Frame")
    f.name = name
    f.events = {}
    for _, m in ipairs({"SetSize", "SetWidth", "SetHeight", "SetPoint", "ClearAllPoints", "SetAllPoints"}) do
        local orig = f[m]
        f[m] = function(self, ...)
            if self.protectedFrame and _G.InCombatLockdown and _G.InCombatLockdown() then blocked = blocked + 1 end
            return orig(self, ...)
        end
    end
    function f:RegisterEvent(e) self.events[e] = true end
    function f:UnregisterEvent(e) self.events[e] = nil end
    function f:SetScript(k, fn) self.scripts = self.scripts or {}; self.scripts[k] = fn end
    function f:HookScript(k, fn)
        self.scripts = self.scripts or {}
        local prev = self.scripts[k]
        self.scripts[k] = function(...) if prev then prev(...) end fn(...) end
    end
    function f:GetScript(k) return self.scripts and self.scripts[k] end
    function f:SetNormalTexture(t) self.NormalTexture = self.NormalTexture or Region("Texture"); self.NormalTexture:SetTexture(t) end
    function f:SetPushedTexture(t) self.PushedTexture = self.PushedTexture or Region("Texture"); self.PushedTexture:SetTexture(t) end
    function f:SetHighlightTexture(t, blend) self.HighlightTexture = self.HighlightTexture or Region("Texture"); self.HighlightTexture:SetTexture(t); self.HighlightTexture.blend = blend end
    function f:GetNormalTexture() return self.NormalTexture end
    function f:GetHighlightTexture() return self.HighlightTexture end
    function f:SetID(id) self.id = id end
    function f:GetID() return self.id or 0 end
    function f:GetParent() return self.parent end
    function f:IsVisible() return self.shown end
    function f:IsMouseEnabled() return self.mouse ~= false end
    function f:Fire(event, ...)
        if self.scripts and self.scripts.OnEvent then self.scripts.OnEvent(self, event, ...) end
    end
    function f:SetFrameStrata() end
    function f:SetMovable() end
    function f:EnableMouse(on) self.mouse = on end
    function f:RegisterForDrag() end
    function f:SetBackdrop(b) self.backdrop = b end
    function f:GetBackdrop() return self.backdrop end
    -- regions an addon creates on a Blizzard frame come back from
    -- GetRegions in the real client too
    function f:CreateFontString() local r = Region("FontString"); self.created = self.created or {}; table.insert(self.created, r); return r end
    function f:SetMultiLine() end
    function f:SetAutoFocus() end
    function f:SetScrollChild(c) self.child = c end
    function f:SetFocus() end
    function f:ClearFocus() end
    function f:HighlightText() end
    function f:CreateTexture(_, layer) local r = Region("Texture"); r.layer = layer; self.created = self.created or {}; table.insert(self.created, r); return r end
    function f:SetParent(p) self.parent = p end
    function f:UnregisterAllEvents() self.events = {} end
    function f:RegisterUnitEvent(e) self.events[e] = true end
    function f:GetAlpha() return self.alpha end
    function f:SetStatusBarTexture(tex) self.barTexture = tex end
    function f:GetStatusBarTexture() self.fill = self.fill or Region("Texture"); return self.fill end
    function f:SetStatusBarColor(...) self.barColor = {...} end
    function f:SetMaskTexture(m) self.mask = m end
    -- Forever locks useParentLevel frames to their parent's level: SetFrameLevel is ignored
    function f:SetFrameLevel(l) if not self.useParentLevel then self.level = l end end
    function f:SetShown(v) self.shown = v and true or false end
    function f:GetFrameLevel() return self.level or 1 end
    function f:GetFrameStrata() return "MEDIUM" end
    function f:SetJustifyH(j) self.justify = j end
    function f:SetChecked(v) self.checked = v end
    function f:GetChecked() return self.checked end
    function f:Click() self.checked = not self.checked; self.scripts.OnClick(self) end
    function f:SetWidth(w) self.width = w end
    function f:GetPoint(i)
        local a = self.anchors and self.anchors[i or 1]
        if not a then return nil end
        return a[1], a[2], a[3], a[4], a[5]
    end
    function f:GetMinMaxValues() if self.minmax then return self.minmax[1], self.minmax[2] end return 0, 0 end
    function f:GetValue() return self.value or 0 end
    function f:SetMinMaxValues(a, b) self.minmax = {a, b} end
    function f:SetValue(v) self.value = v end
    function f:SetValueStep() end
    function f:SetHitRectInsets(...) self.hitRect = {...} end
    function f:SetCursorPosition(p) self.cursor = p end
    function f:GetEffectiveScale() return 1 end
    function f:GetCenter() return 70, 70 end
    function f:LockHighlight() self.highlightLocked = true end
    function f:UnlockHighlight() self.highlightLocked = false end
    function f:SetCheckedTexture(t) self.CheckedTexture = self.CheckedTexture or Region("Texture"); self.CheckedTexture:SetTexture(t) end
    function f:GetCheckedTexture() return self.CheckedTexture end
    function f:Enable() self.enabled = true end
    function f:Disable() self.enabled = false end
    function f:IsEnabled() return self.enabled ~= false end
    function f:SetText(t) self.text = t end
    function f:GetText() return self.text end
    function f:SetAttribute(k, v) self.attributes = self.attributes or {}; self.attributes[k] = v end
    function f:SetFrameRef(label, ref) self.refs = self.refs or {}; self.refs[label] = ref end
    function f:GetAttribute(k) return self.attributes and self.attributes[k] end
    function f:SetEnabled(on) self.enabled = on and true or false end
    function f:SetDisabledTexture(t) self.DisabledTexture = self.DisabledTexture or Region("Texture"); self.DisabledTexture:SetTexture(t) end
    function f:GetPushedTexture() return self.PushedTexture end
    function f:GetDisabledTexture() return self.DisabledTexture end
    function f:SetNormalAtlas(a) self.NormalTexture = self.NormalTexture or Region("Texture"); self.NormalTexture:SetAtlas(a) end
    function f:SetPushedAtlas(a) self.PushedTexture = self.PushedTexture or Region("Texture"); self.PushedTexture:SetAtlas(a) end
    function f:SetDisabledAtlas(a) self.DisabledTexture = self.DisabledTexture or Region("Texture"); self.DisabledTexture:SetAtlas(a) end
    function f:SetHighlightAtlas(a, blend) self.HighlightTexture = self.HighlightTexture or Region("Texture"); self.HighlightTexture:SetAtlas(a); self.HighlightTexture.blend = blend end
    function f:SetScale(s) self.scale = s end
    function f:GetScale() return self.scale or 1 end
    function f:SetCooldown(s, d) self.cooldown = {s, d} end
    function f:RegisterForClicks(...) self.clicks = {...} end
    function f:SetClipsChildren(v) self.clips = v and true or false end
    function f:DoesClipChildren() return self.clips == true end
    function f:EnableMouseWheel(v) self.wheel = v end
    -- children/regions are whatever tables hang off the frame by key
    function f:GetRegions()
        local t = {}
        for k, v in pairs(self) do
            if type(v) == "table" and v.kind and v.kind ~= "Frame" and type(k) == "string" and k ~= "created" then t[#t + 1] = v end
        end
        for _, r in ipairs(self.created or {}) do
            local seen
            for _, s in ipairs(t) do if s == r then seen = true end end
            if not seen then t[#t + 1] = r end
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
            k ~= "load" and k ~= "loadstring" and k ~= "xpcall" and k ~= "setfenv" and k ~= "getfenv" and
            k ~= "gcinfo" and k ~= "newproxy" and k ~= "module" and
            k ~= "coroutine" then
            _G[k] = nil
        end
    end
    -- what the client hands back from the SavedVariables file on the next login
    if opts.savedDB then _G.ForeverClassicUIDB = opts.savedDB end

    printed = {}
    _G.print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
        table.insert(printed, table.concat(parts, " "))
    end

    local w = {cvars = {}, frames = {}, plateApplies = 0, sizes = {}}
    blocked = 0
    function w.Blocked() return blocked end
    function w.ResetBlocked() blocked = 0 end
    w.cvars.nameplateStyle = opts.style or "0"
    w.cvars.nameplateSize = "1"
    w.cvars.nameplateAuraScale = "1"
    w.cvars.nameplateDebuffPadding = "3"
    if opts.cvars then for k, v in pairs(opts.cvars) do w.cvars[k] = v end end
    _G.C_CVar = {
        RegisterCVar = function(n, default) if w.cvars[n] == nil then w.cvars[n] = tostring(default or "") end end,
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

    _G.CreateFrame = function(_, name, parent, template)
        local f = Frame(name)
        f.template = template
        table.insert(w.frames, f)
        -- a parented frame is a child the dump's GetChildren walk can see
        if type(parent) == "table" then f.parent = parent; parent["ownchild" .. #w.frames] = f end
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
    -- secure handlers: a state driver is remembered, and w.FireState runs the
    -- handler's snippet the way the restricted environment would, with self
    -- a handle whose "$parent" is the bar's parent
    _G.RegisterStateDriver = function(frame, state, cond) frame.drivers = frame.drivers or {}; frame.drivers[state] = cond end
    _G.UnregisterStateDriver = function(frame, state) if frame.drivers then frame.drivers[state] = nil end end
    local function Handle(f)
        return {
            GetAttribute = function(_, k) return f:GetAttribute(k) end,
            GetFrameRef = function(_, label) local r = f.refs and f.refs[label]; return r and Handle(r) end,
            IsProtected = function() return f.protected ~= false end,
            ClearAllPoints = function() f:ClearAllPoints() end,
            SetPoint = function(_, point, rel, relPoint, x, y)
                if rel == "$parent" then rel = f.parent end
                f:SetPoint(point, rel, relPoint, x, y)
            end
        }
    end
    function w.FireState(frame, state, value)
        frame:SetAttribute("state-" .. state, value)
        local body = frame:GetAttribute("_onstate-" .. state)
        if not body then return false end
        local fn = assert(loadstring(body, "snippet"))
        setfenv(fn, {self = Handle(frame), ipairs = ipairs, tonumber = tonumber, math = math})
        fn()
        return true
    end
    _G.Screenshot = function() w.screenshots = (w.screenshots or 0) + 1 end
    _G.GetCursorPosition = function() return w.cursorX or 0, w.cursorY or 0 end
    _G.YELLOW_FONT_COLOR = {r = 1, g = 0.82, b = 0}
    _G.GetBuildInfo = function() return opts.version or "1.15.9", "69722", "Sep 1 2026", opts.toc or 11509 end
    _G.WOW_PROJECT_ID = 2
    _G.WOW_PROJECT_CLASSIC = 2
    _G.WOW_PROJECT_MAINLINE = 1
    _G.C_AddOns = {IsAddOnLoaded = function(n) return n == "Blizzard_NamePlates" end}
    _G.GetFileIDFromPath = function(p) if p:find("Nameplate") then return 130000 end if p:find("MainMenuBar") or p:find("Interface\\Buttons\\UI%-") then return 136407 end end

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
    w.blizzErrors = {}
    _G.geterrorhandler = function() return function(msg) w.blizzErrors[#w.blizzErrors + 1] = msg end end
    _G.seterrorhandler = function(fn) w.errorHandler = fn end
    _G.debugstack = function() return "stack line 1\nstack line 2" end
    _G.date = function() return "12:00:00" end
    if opts.classicBars then
        -- classic client: the old frames exist by name
        _G.QuestWatchFrame = Frame("QuestWatchFrame")
        _G.PlayerFrame = Frame("PlayerFrame"); _G.PlayerFrameTexture = Region("Texture")
        _G.MainMenuBarArtFrame = Frame("MainMenuBarArtFrame")
        _G.PartyMemberFrame1 = Frame("PartyMemberFrame1")
        _G.Minimap = Frame("Minimap"); _G.MinimapCluster = Frame("MinimapCluster"); _G.MinimapBorder = Region("Texture")
        _G.MinimapCompassTexture = Region("Texture", {file = "Interface\\Minimap\\CompassRing"})
    end
    if opts.forever then
        -- Forever: retail-style player/target frames, main action bar, minimap
        -- frame levels as on Forever: unit frame L, *Container and *Content L+1, *ContentMain and its bars L+2
        local pf = Frame("PlayerFrame"); pf.level = 10; pf.protectedFrame = true
        pf.PlayerFrameContainer = Frame("container"); pf.PlayerFrameContainer.level = 11
        pf.PlayerFrameContainer.FrameTexture = Region("Texture", {atlas = "UI-HUD-UnitFrame-Player-PortraitOn"})
        pf.PlayerFrameContainer.FrameFlash = Region("Texture", {atlas = "flash"})
        pf.PlayerFrameContainer.AlternatePowerFrameTexture = Region("Texture")
        pf.PlayerFrameContainer.PlayerPortrait = Region("Texture")
        pf.PlayerFrameContainer.PlayerPortraitMask = Region("MaskTexture", {atlas = "UI-HUD-UnitFrame-Player-Portrait-Mask"})
        local main = Frame("main"); main.level = 12; main.protectedFrame = true
        -- masks live where Forever puts them: the health one on the bars container, the mana one on the bar
        main.HealthBarsContainer = Frame("hc"); main.HealthBarsContainer.level = 12; main.HealthBarsContainer.useParentLevel = true; main.HealthBarsContainer.protectedFrame = true
        main.HealthBarsContainer.HealthBar = Frame("hb"); main.HealthBarsContainer.HealthBar.level = 12; main.HealthBarsContainer.HealthBar.useParentLevel = true; main.HealthBarsContainer.HealthBar.protectedFrame = true
        main.HealthBarsContainer.HealthBarMask = Region("MaskTexture", {atlas = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Health-Mask"})
        -- the health numbers live on the container (Forever's XML), anchored to its centre and ends
        main.HealthBarsContainer.HealthBarText = Region("FontString"); main.HealthBarsContainer.LeftText = Region("FontString"); main.HealthBarsContainer.RightText = Region("FontString")
        main.HealthBarsContainer.HealthBarText:SetPoint("CENTER", main.HealthBarsContainer, "CENTER", 0, 0)
        main.HealthBarsContainer.PlayerFrameHealthBarAnimatedLoss = Frame("loss"); main.HealthBarsContainer.PlayerFrameTempMaxHealthLoss = Frame("temploss")
        main.ManaBarArea = Frame("ma"); main.ManaBarArea.level = 12; main.ManaBarArea.useParentLevel = true; main.ManaBarArea.ManaBar = Frame("mb"); main.ManaBarArea.ManaBar.level = 12; main.ManaBarArea.ManaBar.ManaBarMask = Region("MaskTexture"); main.ManaBarArea.ManaBar.protectedFrame = true
        main.StatusTexture = Region("Texture", {atlas = "status"}); main.StatusTexture.shown = false; main.LevelBackgroundCircle = Region("Texture")
        pf.PlayerFrameContent = Frame("content"); pf.PlayerFrameContent.level = 11; pf.PlayerFrameContent.PlayerFrameContentMain = main
        pf.PlayerFrameContent.PlayerFrameContentContextual = Frame("ctx"); pf.PlayerFrameContent.PlayerFrameContentContextual.level = 12; pf.PlayerFrameContent.PlayerFrameContentContextual.AttackIcon = Region("Texture"); pf.PlayerFrameContent.PlayerFrameContentContextual.PlayerPortraitCornerIcon = Region("Texture")
        pf.PlayerFrameContent.PlayerFrameContentContextual.PlayerRestLoop = Frame("restloop")
        _G.PlayerFrame = pf; _G.PlayerName = Region("FontString"); _G.PlayerLevelText = Region("FontString"); _G.GameNormalNumberFont = {}; _G.GameFontNormalSmall = {}; _G.GameFontGreenSmall = {}; _G.GameFontHighlightSmall = {}
        _G.PlayerLevelText.vertex = {1, 1, 1, 1}; _G.PlayerLevelText.text = "2"
        _G.PlayerFrame_UpdateLevel = function() PlayerLevelText:SetVertexColor(1, 1, 1, 1); PlayerLevelText:SetText("3") end
        _G.IsResting = function() return w.resting end
        local function TargetLike(name, unit)
            local tf = Frame(name); tf.unit = unit; tf.level = 500; tf.protectedFrame = true
            tf.TargetFrameContainer = Frame("tcontainer"); tf.TargetFrameContainer.level = 501
            tf.TargetFrameContainer.FrameTexture = Region("Texture", {atlas = "UI-HUD-UnitFrame-Target-PortraitOn"})
            tf.TargetFrameContainer.Flash = Region("Texture"); tf.TargetFrameContainer.Portrait = Region("Texture"); tf.TargetFrameContainer.PortraitMask = Region("MaskTexture", {atlas = "CircleMask"}); tf.TargetFrameContainer.BossPortraitFrameTexture = Region("Texture")
            local tmain = Frame("tmain"); tmain.level = 502; tmain.protectedFrame = true; tmain.ReputationColor = Region("Texture", {atlas = "type"}); tmain.Name = Region("FontString"); tmain.LevelText = Region("FontString"); tmain.LevelBackgroundCircle = Region("Texture")
            tmain.HealthBarsContainer = Frame("thc"); tmain.HealthBarsContainer.level = 502; tmain.HealthBarsContainer.useParentLevel = true; tmain.HealthBarsContainer.protectedFrame = true
            tmain.HealthBarsContainer.HealthBar = Frame("thb"); tmain.HealthBarsContainer.HealthBar.level = 502; tmain.HealthBarsContainer.HealthBar.useParentLevel = true; tmain.HealthBarsContainer.HealthBar.protectedFrame = true
            tmain.HealthBarsContainer.HealthBarMask = Region("MaskTexture")
            tmain.HealthBarsContainer.HealthBarText = Region("FontString"); tmain.HealthBarsContainer.LeftText = Region("FontString"); tmain.HealthBarsContainer.RightText = Region("FontString")
            tmain.HealthBarsContainer.HealthBarText:SetPoint("CENTER", tmain.HealthBarsContainer, "CENTER", 0, 0)
            tmain.HealthBarsContainer.TempMaxHealthLoss = Frame("ttemploss")
            -- Forever's target mana bar is a plain child of the content frame: one level above the rest
            tmain.ManaBar = Frame("tmb"); tmain.ManaBar.level = 503; tmain.ManaBar.ManaBarMask = Region("MaskTexture"); tmain.ManaBar.protectedFrame = true
            tmain.LevelText.text = "1"; tmain.LevelText.vertex = {1, 0.82, 0, 1}
            tf.TargetFrameContent = Frame("tcontent"); tf.TargetFrameContent.TargetFrameContentMain = tmain
            tf.TargetFrameContent.TargetFrameContentContextual = Frame("tctx"); tf.TargetFrameContent.TargetFrameContentContextual.level = 502; tf.TargetFrameContent.TargetFrameContentContextual.HighLevelTexture = Region("Texture")
            function tf:CheckClassification() self.TargetFrameContainer.FrameTexture:SetAtlas("UI-HUD-UnitFrame-Target-PortraitOn") end
            function tf:CheckFaction() end
            return tf
        end
        _G.TargetFrame = TargetLike("TargetFrame", "target"); _G.FocusFrame = TargetLike("FocusFrame", "focus")
        -- pet frame: retail target-of-target atlas, named globals like Era
        local pet = Frame("PetFrame"); pet.level = 6; pet.PortraitMask = Region("MaskTexture", {atlas = "CircleMask"})
        _G.PetFrame = pet
        _G.PetFrameTexture = Region("Texture", {atlas = "UI-HUD-UnitFrame-TargetofTarget-PortraitOn"})
        _G.PetPortrait = Region("Texture"); _G.PetName = Region("FontString")
        _G.PetFrameFlash = Region("Texture", {atlas = "UI-HUD-UnitFrame-TargetofTarget-PortraitOn-InCombat"})
        _G.PetAttackModeTexture = Region("Texture", {atlas = "UI-HUD-UnitFrame-TargetofTarget-PortraitOn-Status"})
        _G.PetFrameHealthBar = Frame("pethb"); _G.PetFrameManaBar = Frame("petmb")
        _G.PetFrameHealthBarMask = Region("MaskTexture"); _G.PetFrameManaBarMask = Region("MaskTexture")
        _G.UnitPowerType = function(u) if u == "pet" then return 2, "FOCUS" end return 0, "MANA" end
        _G.PowerBarColor = {MANA = {r = 0, g = 0, b = 1}, [0] = {r = 0, g = 0, b = 1}, FOCUS = {r = 1, g = 0.5, b = 0.25}}
        _G.UnitClassification = function(u) return w.classification or "normal" end
        _G.UnitFrameManaBar_UpdateType = function(bar) bar:SetStatusBarTexture("UI-HUD-UnitFrame-Player-PortraitOn-Bar-Mana"); bar:SetStatusBarColor(1, 1, 1) end
        _G.PlayerFrame_ToPlayerArt = function() pf.PlayerFrameContainer.FrameTexture:SetAtlas("UI-HUD-UnitFrame-Player-PortraitOn") end
        -- action bars: Forever's retail layout (45px buttons 47 apart in scaled containers, atlas art)
        local function ActionBar(name, buttonPrefix, horizontal)
            local bar = Frame(name)
            bar.parent = _G.UIParent
            bar.actionButtons = {}
            for i = 1, 12 do
                local c = Frame(name .. "ButtonContainer" .. i); c.parent = bar; c:SetSize(45, 45)
                local b = Frame(buttonPrefix .. i); b.parent = c; b.container = c; b:SetSize(45, 45)
                b.icon = Region("Texture"); b.IconMask = Region("MaskTexture", {atlas = "UI-HUD-ActionBar-IconFrame-Mask"})
                b.SlotArt = Region("Texture", {atlas = "ui-hud-actionbar-iconframe-slot"}); b.SlotBackground = Region("Texture", {atlas = "UI-HUD-ActionBar-IconFrame-Background"})
                b:SetNormalAtlas("UI-HUD-ActionBar-IconFrame"); b:SetPushedAtlas("UI-HUD-ActionBar-IconFrame-Down"); b:SetHighlightAtlas("UI-HUD-ActionBar-IconFrame-Mouseover")
                function b:UpdateButtonArt() self.SlotArt:Show(); self.SlotArt.alpha = 1; self:SetNormalAtlas("UI-HUD-ActionBar-IconFrame"); self.NormalTexture:SetSize(46, 45); self:SetPushedAtlas("UI-HUD-ActionBar-IconFrame-Down") end
                _G[buttonPrefix .. i] = b; _G[c.name] = c
                bar.actionButtons[i] = b
            end
            function bar:UpdateGridLayout()
                for i, b in ipairs(self.actionButtons) do
                    b.container:SetScale(1); b.container:ClearAllPoints()
                    if horizontal then b.container:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", (i - 1) * 47, 0) else b.container:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -(i - 1) * 47) end
                end
                if horizontal then self:SetSize(562, 45) else self:SetSize(45, 562) end
            end
            function bar:UpdateSystemSettingIconSize() for _, b in ipairs(self.actionButtons) do b.container:SetScale(1) end end
            function bar:ApplySystemAnchor() self:ClearAllPoints(); self:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0) end
            function bar:IsInDefaultPosition() return self.moved ~= true end
            bar:UpdateGridLayout()
            _G[name] = bar
            return bar
        end
        local bar = ActionBar("MainActionBar", "ActionButton", true)
        bar.BorderArt = Region("Texture", {atlas = "UI-HUD-ActionBar-Frame"})
        bar.EndCaps = Frame("EndCaps"); bar.EndCaps.LeftEndCap = Frame("cap"); bar.EndCaps.RightEndCap = Frame("cap")
        for _, c in pairs({bar.EndCaps.LeftEndCap, bar.EndCaps.RightEndCap}) do function c:SetVisibilitySetting(v) self.visibilitySetting = v end end
        local pn = Frame("ActionBarPageNumber"); pn.Text = Region("FontString"); pn.UpButton = Frame("UpButton"); pn.DownButton = Frame("DownButton")
        pn.UpButton:SetNormalAtlas("ui-hud-actionbar-pageuparrow-up"); pn.DownButton:SetNormalAtlas("ui-hud-actionbar-pagedownarrow-up")
        bar.ActionBarPageNumber = pn
        local function Pool() local p = {active = {}}; function p:EnumerateActive() local i = 0; return function() i = i + 1; return self.active[i] end end; return p end
        bar.HorizontalDividersPool = Pool(); bar.VerticalDividersPool = Pool()
        function bar:UpdateDividers() self.HorizontalDividersPool.active = {Frame("div1"), Frame("div2")}; for _, d in ipairs(self.HorizontalDividersPool.active) do d:Show(); d.alpha = 1 end end
        bar:UpdateDividers()
        ActionBar("MultiBarBottomLeft", "MultiBarBottomLeftButton", true)
        ActionBar("MultiBarBottomRight", "MultiBarBottomRightButton", true)
        ActionBar("MultiBarRight", "MultiBarRightButton", false)
        _G.EditModeManagerFrame = {ExitEditMode = function() end, UpdateBottomActionBarPositions = function() MainActionBar:ClearAllPoints(); MainActionBar:SetPoint("BOTTOMRIGHT", MicroMenuContainer, "BOTTOMLEFT", -4.5, -4); MultiBarBottomLeft:ClearAllPoints(); MultiBarBottomLeft:SetPoint("BOTTOMLEFT", MainActionBar, "BOTTOMLEFT", 22, 57); MultiBarBottomRight:ClearAllPoints(); MultiBarBottomRight:SetPoint("BOTTOMLEFT", MainActionBar, "BOTTOMLEFT", 606, 57) end}
        _G.C_Texture = {GetAtlasInfo = function() return nil end}
        -- micro menu and bags, retail style (atlas art, grid layout)
        _G.MicroMenuContainer = Frame("MicroMenuContainer"); function MicroMenuContainer:ApplySystemAnchor() self:ClearAllPoints(); self:SetPoint("BOTTOM", UIParent, "BOTTOM", 116.5, 6) end
        _G.MicroMenu = Frame("MicroMenu"); MicroMenu.BorderArt = Region("Texture", {atlas = "UI-HUD-ActionBar-Frame"}); MicroMenu.BackgroundArt = Region("Texture"); function MicroMenu:Layout() end
        local function Micro(name)
            local b = Frame(name); b:SetSize(32, 40); b.Background = Region("Texture", {atlas = "UI-HUD-MicroMenu-ButtonBG-Up"}); b.PushedBackground = Region("Texture", {atlas = "UI-HUD-MicroMenu-ButtonBG-Down"})
            b:SetNormalAtlas("UI-HUD-MicroMenu-" .. name .. "-Up"); b:SetPushedAtlas("UI-HUD-MicroMenu-" .. name .. "-Down"); b:SetDisabledAtlas("UI-HUD-MicroMenu-" .. name .. "-Disabled"); b:SetHighlightAtlas("UI-HUD-MicroMenu-" .. name .. "-Mouseover")
            function b:SetPushed() self.Background:Hide(); self.PushedBackground:Show(); self.PushedBackground.alpha = 1 end
            function b:SetNormal() self.Background:Show(); self.PushedBackground:Hide() end
            b.parent = MicroMenu
            _G[name] = b
            return b
        end
        -- a micro button Forever keeps as a global outside the menu (shown, parked elsewhere)
        Micro("AchievementMicroButton").parent = UIParent
        local cm = Micro("CharacterMicroButton"); cm.Portrait = Region("Texture"); cm.PortraitMask = Region("MaskTexture", {atlas = "UI-HUD-MicroMenu-Portrait-Mask"}); cm.Shadow = Region("Texture")
        -- Forever's eleven: Era's six plus professions, legacy, group finder, collections and a disabled Store
        Micro("ProfessionMicroButton"); Micro("SpellbookMicroButton"); Micro("TalentMicroButton"); Micro("LegacyMicroButton"); Micro("QuestLogMicroButton"); Micro("GuildMicroButton")
        Micro("LFDMicroButton"); Micro("CollectionsMicroButton"); Micro("StoreMicroButton"):Disable(); Micro("MainMenuMicroButton")
        _G.UpdateMicroButtons = function() StoreMicroButton:Show(); StoreMicroButton.alpha = 0.5 end
        _G.BagsBar = Frame("BagsBar"); BagsBar.BorderArt = Region("Texture", {atlas = "UI-HUD-ActionBar-Frame"})
        function BagsBar:ApplySystemAnchor() self:ClearAllPoints(); self:SetPoint("BOTTOMLEFT", MicroMenuContainer, "BOTTOMRIGHT", 7, -4) end
        function BagsBar:Layout() MainMenuBarBackpackButton:ClearAllPoints(); MainMenuBarBackpackButton:SetPoint("RIGHT", self, "RIGHT"); CharacterBag0Slot:ClearAllPoints(); CharacterBag0Slot:SetPoint("RIGHT", MainMenuBarBackpackButton, "LEFT", -2, 0); self.div1:Show(); self.div1.alpha = 1 end
        for _, n in ipairs({"MainMenuBarBackpackButton", "CharacterBag0Slot", "CharacterBag1Slot", "CharacterBag2Slot", "CharacterBag3Slot", "CharacterReagentBag0Slot", "KeyRingButton"}) do
            local b = Frame(n); b:SetSize(n == "MainMenuBarBackpackButton" and 50 or 30, n == "MainMenuBarBackpackButton" and 50 or 30); b.icon = Region("Texture"); b.IconBorder = Region("Texture"); b.SquareMask = Region("MaskTexture", {atlas = "UI-HUD-ActionBar-IconFrame-Mask"}); b:SetNormalAtlas("bag-border"); _G[n] = b
        end
        -- the divider strips between the slots (pooled frames)
        BagsBar.div1 = Frame("div"); BagsBar.div1.TopEdge = Region("Texture"); BagsBar.div1.BottomEdge = Region("Texture"); BagsBar.div1.Center = Region("Texture")
        -- experience bar: retail framed strip, atlas fill, segment dividers
        _G.StatusTrackingBarManager = Frame("StatusTrackingBarManager"); function StatusTrackingBarManager:UpdateBarVisuals() end
        local function StatusContainer(name)
            local c = Frame(name); c:SetSize(571, 17); c.BarFrameTexture = Region("Texture", {atlas = "UI-HUD-ExperienceBar-Frame"})
            c.div1 = Frame("div"); c.div1.BarDividerTexture = Region("Texture", {atlas = "UI-HUD-ExperienceBar-Divider"})
            local xp = Frame(name .. "Exp"); xp.isExpBar = true; xp.StatusBar = Frame("sb"); xp.StatusBar.Background = Region("Texture", {atlas = "UI-HUD-ExperienceBar-Background"})
            xp.ExhaustionTick = Frame("tick"); xp.ExhaustionTick:SetNormalAtlas("UI-HUD-ExperienceBar-Frame-Pip")
            function xp:UpdateStatusBarTextures(isRested) self.StatusBar:SetStatusBarTexture(isRested and "UI-HUD-ExperienceBar-Fill-Rested" or "UI-HUD-ExperienceBar-Fill-Experience") end
            c.bars = {[1] = xp}
            function c:ApplySystemAnchor() self:ClearAllPoints(); self:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 60); self:SetSize(571, 17) end
            function c:UpdateSystemSetting() end
            _G[name] = c
            return c
        end
        StatusContainer("MainStatusTrackingBarContainer")
        local second = StatusContainer("SecondaryStatusTrackingBarContainer"); second.shown = false
        -- party frames: retail layout (atlas art, masked bars), Blizzard's art refresh
        local pfr = Frame("PartyFrame"); _G.PartyFrame = pfr
        for i = 1, 2 do
            local m = Frame("MemberFrame" .. i); m.parent = pfr; m:SetSize(120, 53); m:SetPoint("TOPLEFT", pfr, "TOPLEFT", 0, -(i - 1) * 63)
            m.Texture = Region("Texture", {atlas = "UI-HUD-UnitFrame-Party-PortraitOn"}); m.VehicleTexture = Region("Texture"); m.Flash = Region("Texture", {atlas = "ui-hud-unitframe-party-portraiton-incombat"})
            m.Portrait = Region("Texture"); m.PortraitMask = Region("MaskTexture", {atlas = "CircleMask"}); m.Name = Region("FontString")
            m.PartyMemberOverlay = Frame("PartyMemberOverlay"); m.PartyMemberOverlay.parent = m
            for _, k in ipairs({"Status", "LeaderIcon", "GuideIcon", "PVPIcon", "Disconnect", "RoleIcon"}) do m.PartyMemberOverlay[k] = Region("Texture") end
            m.HealthBarContainer = Frame("HealthBarContainer"); m.HealthBarContainer.HealthBar = Frame("HealthBar"); m.HealthBarContainer.HealthBarMask = Region("MaskTexture", {atlas = "UI-HUD-UnitFrame-Party-PortraitOn-Bar-Health-Mask"})
            m.ManaBar = Frame("ManaBar"); m.ManaBar.ManaBarMask = Region("MaskTexture")
            m.PetFrame = Frame("PetFrame"); m.PetFrame:SetSize(64, 23); m.PetFrame.Texture = Region("Texture", {atlas = "ui-hud-unitframe-party-portraiton"}); m.PetFrame.Texture.scale = 0.5
            function m.PetFrame.Texture:SetScale(s) self.scale = s end
            m.PetFrame.Portrait = Region("Texture"); m.PetFrame.PortraitMask = Region("MaskTexture"); m.PetFrame.Name = Region("FontString"); m.PetFrame.HealthBar = Frame("PetHealthBar")
            m.NotPresentIcon = Region("Texture")
            function m:UpdateArt()
                self.Texture:Show(); self.Texture.alpha = 1; self.Texture:SetAtlas("UI-HUD-UnitFrame-Party-PortraitOn")
                self.HealthBarContainer:ClearAllPoints(); self.HealthBarContainer:SetPoint("TOPLEFT", self, "TOPLEFT", 45, -19); self.HealthBarContainer:SetWidth(70)
                self.HealthBarContainer.HealthBarMask:SetAtlas("UI-HUD-UnitFrame-Party-PortraitOn-Bar-Health-Mask")
                self.ManaBar:ClearAllPoints(); self.ManaBar:SetPoint("TOPLEFT", self, "TOPLEFT", 41, -30); self.ManaBar:SetWidth(74)
            end
            m:UpdateArt()
            pfr["MemberFrame" .. i] = m
        end
        -- objective tracker (retail)
        local tracker = Frame("ObjectiveTrackerFrame")
        tracker.Header = Frame("Header"); tracker.Header.Background = Region("Texture", {atlas = "ui-questtracker-primary-objective-header"})
        local questModule = Frame("QuestObjectiveTracker"); questModule.Header = Frame("Header"); questModule.Header.Background = Region("Texture", {atlas = "UI-QuestTracker-Secondary-Objective-Header"})
        tracker.modules = {questModule}
        function tracker:Update() self.Header.Background:SetAlpha(1); questModule.Header.Background:SetAlpha(1) end
        _G.ObjectiveTrackerFrame = tracker
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
            p.UnitFrame.LevelFrame = Frame("LevelFrame")
            function p.UnitFrame:UpdateAnchors() self.anchorsUpdated = self.anchorsUpdated + 1 end
        end
        -- character sheet: Forever's Camelot CharacterFrame (631x484 shell, side tabs, stats list)
        do
            local cf = Frame("CharacterFrame"); cf.level = 1; cf:SetSize(631, 484)
            cf.NineSlice = Frame("NineSlice"); cf.NineSlice.level = 500
            cf.PortraitContainer = Frame("PortraitContainer"); cf.PortraitContainer.portrait = Region("Texture"); cf.PortraitContainer.CircleMask = Region("MaskTexture")
            cf.PortraitContainer.portrait:SetPoint("TOPLEFT", cf.PortraitContainer, "TOPLEFT", -5, 7); cf.PortraitContainer.portrait:SetSize(62, 62)
            cf.PortraitContainer.CircleMask:SetPoint("TOPLEFT", cf.PortraitContainer.portrait, "TOPLEFT", 2, 0); cf.PortraitContainer.CircleMask:SetSize(58, 58)
            cf.TitleContainer = Frame("TitleContainer"); cf.TitleContainer:SetPoint("TOPLEFT", cf, "TOPLEFT", 58, -1); cf.TitleContainer:SetSize(549, 20); cf.TitleContainer.TitleText = Region("FontString")
            cf.CloseButton = Frame("CloseButton")
            cf.LeftPaneHost = Frame("LeftPaneHost"); cf.LeftPaneHost:SetSize(398, 464)
            cf.RightPaneHost = Frame("RightPaneHost"); cf.RightPaneHost:SetSize(233, 464)
            cf.RightPaneToggleButton = Frame("RightPaneToggleButton")
            cf.ModeTabs = Frame("ModeTabs"); cf.ModeTabs.Tabs = {}
            for i = 1, 6 do local t = Frame("ModeTab" .. i); t.mouse = true; cf.ModeTabs.Tabs[i] = t; cf.ModeTabs["tab" .. i] = t end
            cf.width = 631; cf.height = 484
            w.panelWidth = nil
            _G.SetUIPanelAttribute = function(frame, name, value) if frame == cf and name == "width" then w.panelWidth = value end end
            function cf:IsRightPaneCollapsed() return false end
            function cf:UpdateSize() self:SetSize(631, 484); w.blizzSizes = (w.blizzSizes or 0) + 1 end
            function cf:UpdatePortrait() end
            function cf:UpdateTitle() end
            function cf:UpdateRightPaneHeader() end
            function cf:SetSelectedModeTabByFrame(name) self.selectedFrame = name end
            function cf:SetUIPanelAttribute() SetUIPanelAttribute(self, "width", self.width + 82) end
            function cf:ShouldShowCurrencyTab() return w.currencyTab ~= false end
            function cf:RefreshDisplay()
                self:UpdateSize(); self:UpdatePortrait(); self:UpdateTitle(); self:UpdateRightPaneHeader(); self:SetSelectedModeTabByFrame(self.activeSubframe)
            end
            function cf:Expand()
                self.Expanded = true
                PaperDollSidebarTabs:Show(); PaperDollLevelInfo:Show(); CharacterStatsPaneScrollBox:Show()
                self:RefreshDisplay()
            end
            function cf:Collapse() self.Expanded = false; self:RefreshDisplay() end
            function cf:RefreshRightPane() if PaperDollFrame:IsShown() then self:Expand() end; self:SetUIPanelAttribute() end
            local subframes = {"PaperDollFrame", "ReputationFrame", "SkillsFrame", "PVPRankFrame", "TokenFrame", "StatisticsFrame"}
            function cf:ShowSubFrame(name)
                self.activeSubframe = name
                for _, n in ipairs(subframes) do if n ~= name then _G[n]:Hide() end end
                for _, n in ipairs(subframes) do if n == name then _G[n]:Show() end end
            end
            _G.CharacterFrame = cf
            for _, n in ipairs(subframes) do
                local f = Frame(n); f.parent = cf; f:SetAllPoints(cf); f.level = 1; f.useParentLevel = true
                f:Hide()
                _G[n] = f
            end
            -- Forever's retail list pieces on the reputation and skills tabs
            local rep, sk = _G.ReputationFrame, _G.SkillsFrame
            rep.ScrollBox = Frame("ScrollBox"); rep.ScrollBar = Frame("ScrollBar"); rep.ReputationDetailFrame = Frame("ReputationDetailFrame"); rep.filterDropdown = Frame("filterDropdown")
            sk.ScrollBox = Frame("ScrollBox"); sk.ScrollBar = Frame("ScrollBar"); sk.SkillDetailFrame = Frame("SkillDetailFrame")
            -- Forever's currency and statistics tabs: retail scroll boxes and a background of their own
            local tok, st = _G.TokenFrame, _G.StatisticsFrame
            tok.ScrollBox = Frame("ScrollBox"); tok.ScrollBox:Show(); tok.ScrollBar = Frame("ScrollBar"); tok.ScrollBar:Show(); tok.Background = Region("Texture")
            st.ScrollBox = Frame("ScrollBox"); st.ScrollBox:Show(); st.DetailFrame = Frame("DetailFrame"); st.DetailFrame:Show()
            w.currencies = {
                {name = "Miscellaneous", isHeader = true, isHeaderExpanded = true},
                {name = "Honor Points", quantity = 120, iconFileID = 1455894, isShowInBackpack = true},
                {name = "Player vs. Player", isHeader = true, isHeaderExpanded = false}
            }
            w.currencyExpanded, w.currencyBackpack = {}, {}
            _G.C_CurrencyInfo = {
                GetCurrencyListSize = function() return #w.currencies end,
                GetCurrencyListInfo = function(i) local d = w.currencies[i]; if d then local c = {}; for k, v in pairs(d) do c[k] = v end; return c end end,
                ExpandCurrencyList = function(i, expand) w.currencyExpanded[#w.currencyExpanded + 1] = {i, expand}; w.currencies[i].isHeaderExpanded = expand end,
                SetCurrencyBackpack = function(i, on) w.currencyBackpack[#w.currencyBackpack + 1] = {i, on}; w.currencies[i].isShowInBackpack = on end
            }
            w.statCategories = {[1] = {"Player vs Player", -1}, [2] = {"Dungeons & Raids", -1}, [3] = {"Classic", 2}}
            w.statAchievements = {[1] = {{101, "Honorable kills"}, {102, "Deaths"}}, [2] = {}, [3] = {{103, "Deadmines runs"}}}
            _G.GetStatisticsCategoryList = function() return {1, 2, 3} end
            _G.GetCategoryInfo = function(id) local c = w.statCategories[id]; return c[1], c[2], 0 end
            _G.GetCategoryNumAchievements = function(id) return #(w.statAchievements[id] or {}) end
            _G.GetAchievementInfo = function(id, i) local a = w.statAchievements[id][i]; return a[1], a[2] end
            _G.GetStatistic = function(aid) return ({[101] = "12", [102] = "3", [103] = "--"})[aid] end
            -- Era's faux scroll helpers, still shipped by Forever
            _G.FauxScrollFrame_Update = function(frame, numItems, numToDisplay) frame.fauxItems = numItems; return numItems > numToDisplay end
            _G.FauxScrollFrame_GetOffset = function(frame) return frame.fauxOffset or 0 end
            _G.FauxScrollFrame_OnVerticalScroll = function(frame, offset, itemHeight, fn) frame.fauxOffset = math.floor(offset / itemHeight + 0.5); fn() end
            _G.UnitSex = function() return 2 end
            _G.GetText = function(key) return _G[key] end
            _G.FACTION_STANDING_LABEL4 = "Neutral"; _G.FACTION_STANDING_LABEL5 = "Friendly"; _G.FACTION_STANDING_LABEL6 = "Honored"; _G.FACTION_STANDING_LABEL8 = "Exalted"
            _G.FACTION_BAR_COLORS = {[4] = {r = 0.9, g = 0.7, b = 0}, [5] = {r = 0, g = 0.6, b = 0.1}, [6] = {r = 0, g = 0.6, b = 0.1}, [8] = {r = 0, g = 0.6, b = 0.1}}
            _G.MAX_REPUTATION_REACTION = 8
            _G.SOUNDKIT = {IG_MAINMENU_OPTION_CHECKBOX_ON = 1, IG_MAINMENU_OPTION_CHECKBOX_OFF = 2}
            _G.PlaySound = function() end
            _G.BACKDROP_DIALOG_32_32 = {}
            -- factions: a header with three children, one at war and watched, plus a collapsed header
            w.factions = {
                {factionID = 1, name = "Alliance", isHeader = true, isCollapsed = false, reaction = 4, currentReactionThreshold = 0, nextReactionThreshold = 1, currentStanding = 0},
                {factionID = 72, name = "Stormwind", reaction = 6, currentReactionThreshold = 9000, nextReactionThreshold = 21000, currentStanding = 15000, isWatched = true, canToggleAtWar = false},
                {factionID = 47, name = "Ironforge", reaction = 8, currentReactionThreshold = 42000, nextReactionThreshold = 43000, currentStanding = 42999},
                {factionID = 21, name = "Booty Bay", reaction = 4, currentReactionThreshold = 0, nextReactionThreshold = 3000, currentStanding = 1949, atWarWith = true, canToggleAtWar = true, description = "Pirates.", canSetInactive = true},
                {factionID = 2, name = "Other", isHeader = true, isCollapsed = true, reaction = 4, currentReactionThreshold = 0, nextReactionThreshold = 1, currentStanding = 0}
            }
            w.selectedFaction, w.expanded, w.collapsed, w.atWarToggled, w.watched, w.factionActive = 0, {}, {}, {}, nil, {}
            _G.C_Reputation = {
                GetNumFactions = function() return #w.factions end,
                GetFactionDataByIndex = function(i) local d = w.factions[i]; if d then local c = {}; for k, v in pairs(d) do c[k] = v end; return c end end,
                GetSelectedFaction = function() return w.selectedFaction end,
                SetSelectedFaction = function(i) w.selectedFaction = i end,
                ExpandFactionHeader = function(i) w.expanded[#w.expanded + 1] = i; w.factions[i].isCollapsed = false end,
                CollapseFactionHeader = function(i) w.collapsed[#w.collapsed + 1] = i; w.factions[i].isCollapsed = true end,
                ToggleFactionAtWar = function(i) w.atWarToggled[#w.atWarToggled + 1] = i; w.factions[i].atWarWith = not w.factions[i].atWarWith end,
                SetWatchedFactionByIndex = function(i) w.watched = i end,
                IsFactionActive = function(i) return w.factionActive[i] ~= false end,
                SetFactionActive = function(i, on) w.factionActive[i] = on end
            }
            -- skills: class skills header (hidden by Forever too), weapon skills with a collapsed header
            w.skills = {
                {skillID = 7, name = "Class Skills", isHeader = true, isCollapsed = false, parentSkillLineID = 0, rank = 0, maxRank = 0, modifier = 0},
                {skillID = 613, name = "Discipline", parentSkillLineID = 0, skillLineCategoryID = 7, rank = 195, maxRank = 195, modifier = 0},
                {skillID = 9, name = "Weapon Skills", isHeader = true, isCollapsed = false, parentSkillLineID = 0, rank = 0, maxRank = 0, modifier = 0},
                {skillID = 173, name = "Daggers", parentSkillLineID = 0, skillLineCategoryID = 9, rank = 1, maxRank = 195, modifier = 0, description = "Daggers.", tempPoints = 0},
                {skillID = 95, name = "Defense", parentSkillLineID = 0, skillLineCategoryID = 9, rank = 187, maxRank = 195, modifier = 0, tempPoints = 0},
                {skillID = 8, name = "Secondary Skills", isHeader = true, isCollapsed = true, parentSkillLineID = 0, rank = 0, maxRank = 0, modifier = 0},
                {skillID = 185, name = "Cooking", parentSkillLineID = 0, skillLineCategoryID = 8, rank = 65, maxRank = 150, modifier = 5, isAbandonable = true, description = "Cooking.", costType = 2, tempPoints = 0}
            }
            w.selectedSkill, w.skillExpanded, w.skillCollapsed = 0, {}, {}
            _G.C_SkillInfo = {
                GetNumSkillLines = function() return #w.skills end,
                GetSkillLineInfo = function(i) local d = w.skills[i]; if d then local c = {}; for k, v in pairs(d) do c[k] = v end; return c end end,
                GetSelectedSkill = function() return w.selectedSkill end,
                SetSelectedSkill = function(i) w.selectedSkill = i end,
                ExpandSkillHeader = function(i) w.skillExpanded[#w.skillExpanded + 1] = i; w.skills[i].isCollapsed = false end,
                CollapseSkillHeader = function(i) w.skillCollapsed[#w.skillCollapsed + 1] = i; w.skills[i].isCollapsed = true end
            }
            _G.UnitDefenseSkill = function() return 187, 3 end
            -- honor: Forever's rank-points track (a renown-style faction)
            local pvp = _G.PVPRankFrame
            pvp.MainInfoFrame = Frame("MainInfoFrame"); pvp.DetailFrame = Frame("DetailFrame"); pvp.SeasonTimerField = Region("FontString")
            pvp.RewardsPane = Frame("RewardsPane") -- Forever's reward text that floats right of the sheet (a key the addon does not know)
            _G.UnitFactionGroup = function() return "Alliance" end
            _G.GetCurrentArenaSeason = function() return 1 end
            _G.Enum.PvPRanks = {Rank_1 = 5}
            _G.PVP_RANK_0_NAME = "Civilian"; _G.PVP_RANK_6_1 = "Corporal"; _G.PVP_RANK_NUMBER = "Rank %d"
            _G.PVP_RANK_CURRENT_PROGRESS = "Rank Points: %d / %d"; _G.PVP_RANK_NEXT_REWARD = "Next Rewards at Rank %d"
            _G.C_MajorFactions = {
                GetMajorFactionProgressionInfo = function(id) return {renownLevel = 2, renownReputationEarned = 300, renownLevelThreshold = 1500, maxLevel = 14, currentWeekProgressiveMaxLevel = 3, previousWeekProgressiveMaxLevel = 2} end,
                GetTotalReputationForRenownLevel = function(id, level) return level * 1000 end,
                GetRenownRewardsForLevel = function(id, level) if level == 4 then return {{icon = 135026, description = "Faction Tabard"}} end return {} end
            }
            _G.C_SeasonInfo = {GetTimeUntilCurrentPVPSeasonEnd = function() return 3 * 86400 end}
            -- spellbook: Forever's PlayerSpellsFrame (retail) with its spellbook page and C_SpellBook.
            -- The frame lives in Blizzard_PlayerSpells, loaded on demand when the book is first
            -- opened, so it does not exist at login: w.LoadPlayerSpells() stands in for that load.
            function w.LoadPlayerSpells()
            -- the window holds the secure spell buttons: it and its spellbook page are protected
            local psf = Frame("PlayerSpellsFrame"); psf:SetSize(809, 720); psf.level = 1; psf.protectedFrame = true
            psf.NineSlice = Frame("NineSlice"); psf.Bg = Region("Texture"); psf.TopTileStreaks = Region("Texture")
            psf.CloseButton = Frame("CloseButton"); psf.TabSystem = Frame("TabSystem")
            psf.MaximizeMinimizeButton = Frame("MaximizeMinimizeButton"); psf.MaximizeMinimizeButton.MaximizeButton = Frame("MaximizeButton"); psf.MaximizeMinimizeButton.MinimizeButton = Frame("MinimizeButton")
            psf.PortraitContainer = Frame("PortraitContainer"); psf.PortraitContainer.portrait = Region("Texture"); psf.PortraitContainer.CircleMask = Region("MaskTexture")
            psf.PortraitContainer.portrait:SetPoint("TOPLEFT", psf.PortraitContainer, "TOPLEFT", -5, 7); psf.PortraitContainer.portrait:SetSize(62, 62)
            psf.TitleContainer = Frame("TitleContainer")
            psf.SpellBookFrame = Frame("SpellBookFrame"); psf.SpellBookFrame.parent = psf; psf.SpellBookFrame:SetPoint("BOTTOMLEFT", psf, "BOTTOMLEFT", 0, 4); psf.SpellBookFrame:SetSize(806, 702); psf.SpellBookFrame.protectedFrame = true
            psf.TalentsFrame = Frame("TalentsFrame"); psf.TalentsFrame:Hide()
            local page = psf.SpellBookFrame
            function page:Show() if not self.shown then self.shown = true; if self.scripts and self.scripts.OnShow then self.scripts.OnShow(self) end end end
            function page:Hide() if self.shown then self.shown = false; if self.scripts and self.scripts.OnHide then self.scripts.OnHide(self) end end end
            function psf:Show() if not self.shown then self.shown = true; if self.scripts and self.scripts.OnShow then self.scripts.OnShow(self) end end end
            function psf:Hide() if self.shown then self.shown = false; if self.scripts and self.scripts.OnHide then self.scripts.OnHide(self) end end end
            psf:Hide()
            _G.PlayerSpellsFrame = psf
            -- UIParent's panel attributes: set from addon code they taint the panel, which then
            -- cannot be shown in combat, so any call from the addon is a fault
            _G.GetUIPanelAttribute = function(frame, name) if frame == psf and name == "width" then return 809 end end
            _G.SetUIPanelAttribute = function(frame, name, value) w.panelTainted = (w.panelTainted or 0) + 1 end
            return psf
            end
            -- Forever's talents page: retail's talent frame (TalentFrameBase, C_Traits nodes with
            -- edges) laid out as three trees side by side on a 1212px canvas, 40px nodes on a 60px
            -- grid. Positions and children are from a 0.7.14 report of a level 10 orc hunter.
            function w.LoadTalents(psf)
            local tf = Frame("TalentsFrame"); tf.parent = psf; tf:SetSize(1212, 681); tf:SetPoint("BOTTOM", psf, "BOTTOM", 0, 4); tf.level = 100
            tf.Background = Region("Texture", {atlas = "Talents-Background-c60", layer = "BACKGROUND"})
            tf.ClassBackground = Region("Texture", {atlas = "talent-background-hunter", layer = "BACKGROUND"})
            tf.BackgroundBorder = Region("Texture", {atlas = "Talents-inner-frame-c60", layer = "OVERLAY"})
            tf.FullMask = Region("MaskTexture", {atlas = "talents-animations-mask-full"})
            tf.UnspentText = Region("FontString"); tf.UnspentText:SetText("Unspent Talents [3]")
            tf.AnimationHolder = Frame("AnimationHolder"); tf.AnimationHolder.parent = tf
            local bp = Frame("ButtonsParent"); bp.parent = tf; bp.level = 1098
            bp:SetPoint("TOPLEFT", tf, "TOPLEFT", 0, 0); bp:SetPoint("BOTTOMRIGHT", tf, "BOTTOMRIGHT", 0, 40); bp:SetSize(1212, 641)
            tf.ButtonsParent = bp
            tf.SearchBox = Frame("SearchBox"); tf.SearchBox.objectType = "EditBox"; tf.SearchBox.parent = tf
            tf.ApplyButton = Frame("ApplyButton"); tf.ApplyButton.objectType = "Button"; tf.ApplyButton.parent = tf
            tf.ApplyButton:SetText("Apply Changes"); tf.ApplyButton:SetSize(140, 30); tf.ApplyButton:SetPoint("BOTTOM", tf, "BOTTOM", 0, 10)
            tf.SpecTabs = Frame("SpecTabs"); tf.SpecTabs.parent = tf
            for i, name in ipairs({"Primary", "Secondary"}) do
                local b = Frame(name); b.objectType = "Button"; b.parent = tf.SpecTabs; b:SetText(name); b:SetSize(90, 24)
                b:SetPoint("TOPLEFT", tf.SpecTabs, "TOPLEFT", (i - 1) * 92, 0)
                tf.SpecTabs[name] = b
            end
            tf.Header1 = Frame("Header1"); tf.Header1.parent = tf; tf.Header1.Name = Region("FontString"); tf.Header1.Name:SetText("Beast Mastery")
            tf.byID = {}
            local function Node(name, id, x, y, opts)
                local b = Frame(name); b.objectType = "Button"; b.parent = bp; b:SetSize(40, 40)
                b:SetPoint("CENTER", bp, "TOPLEFT", x, -y)
                b.Icon = Region("Texture", {file = opts.icon or 136076, layer = "BORDER"})
                b.Shadow = Region("Texture", {atlas = "talents-node-square-shadow", layer = "BACKGROUND"})
                b.StateBorder = Region("Texture", {atlas = opts.state == 5 and "talents-node-square-green" or "talents-node-square-locked", layer = "ARTWORK"})
                b.SpendText = Region("FontString"); b.SpendText:SetText(opts.rank and opts.rank > 0 and tostring(opts.rank) or "")
                b.SpendTextShadow1 = Region("FontString"); b.BorderSheenMask = Region("MaskTexture")
                b.nodeInfo = {ID = id, posX = x * 10, posY = y * 10, currentRank = opts.rank or 0, maxRanks = opts.max or 1,
                              ranksPurchased = opts.rank or 0, isVisible = true, visibleEdges = {}}
                b.nodeID = id
                function b:GetNodeInfo() return self.nodeInfo end
                function b:GetNodeID() return self.nodeID end
                b.state = opts.state or 2
                function b:GetVisualState() return self.state end
                b.updates = 0
                function b:FullUpdate() self.updates = self.updates + 1 end
                bp[name] = b; tf.byID[id] = b
                return b
            end
            local n = {}
            -- Beast Mastery, as the report had it
            n.DA = Node("Deadly Aspects", 101, 173, 220, {state = 6, rank = 1, max = 1})
            n.IRP = Node("Improved Revive Pet", 102, 293, 280, {state = 5, rank = 0, max = 1, icon = 132163})
            n.BS = Node("Bestial Swiftness", 103, 173, 340, {state = 5, rank = 0, max = 3})
            n.UF = Node("Unleashed Fury", 104, 233, 340, {state = 5, rank = 0, max = 5})
            n.IMP = Node("Improved Mend Pet", 105, 113, 400, {state = 4})
            n.FER = Node("Ferocity", 106, 233, 400, {state = 2, max = 5})
            n.SH = Node("Summon Hawk", 107, 293, 400, {state = 2})
            n.SB = Node("Spirit Bond", 108, 113, 460, {state = 2})
            n.INT = Node("Intimidation", 109, 173, 460, {state = 2})
            n.BD = Node("Bestial Discipline", 110, 293, 460, {state = 2})
            n.FRZ = Node("Frenzy", 111, 233, 520, {state = 2, icon = 134296})
            n.BW = Node("Bestial Wrath", 112, 173, 580, {state = 2, icon = 132127})
            -- Marksmanship and Survival, further right on the same canvas
            n.MM1 = Node("Lethal Shots", 201, 517, 220, {state = 5, max = 5})
            n.MM2 = Node("Efficiency", 202, 577, 340, {state = 2})
            n.MM3 = Node("Aimed Shot", 203, 637, 340, {state = 2})
            n.SV1 = Node("Monster Slaying", 301, 921, 220, {state = 5})
            n.SV2 = Node("Savage Strikes", 302, 981, 280, {state = 2})
            tf.nodes = n
            tf.edges = {}
            local function Edge(a, b, active)
                local e = Frame(nil); e.parent = bp; e.objectType = "Frame"
                e.Line = Region("Line", {atlas = "talents-arrow-line-gray"}); e.ArrowHead = Region("Texture", {atlas = "talents-arrow-head-gray"})
                function e:GetStartButton() return a end
                function e:GetEndButton() return b end
                function e:UpdateState() self.alpha = 1; self.stateUpdates = (self.stateUpdates or 0) + 1 end
                table.insert(a.nodeInfo.visibleEdges, {targetNode = b.nodeID, type = 0, visualStyle = 1, isActive = active})
                bp["edge" .. #tf.edges + 1] = e; tf.edges[#tf.edges + 1] = e
                return e
            end
            Edge(n.DA, n.BS, true); Edge(n.DA, n.IRP, true); Edge(n.BS, n.UF, false); Edge(n.BS, n.INT, false)
            Edge(n.UF, n.FER, false); Edge(n.FER, n.FRZ, false); Edge(n.INT, n.BW, false); Edge(n.IRP, n.SH, false)
            Edge(n.FER, n.SH, false) -- along a row, the unlocked talent to the right
            Edge(n.MM1, n.MM2, false); Edge(n.SV1, n.SV2, false)
            tf.treeCurrencyInfo = {{traitCurrencyID = 1, quantity = 3, maxQuantity = 4, spent = 1}}
            function tf:GetTalentButtonByNodeID(id) return self.byID[id] end
            function tf:UpdateAllTalentButtonPositions()
                for _, b in pairs(self.nodes) do b:ClearAllPoints(); b:SetPoint("CENTER", bp, "TOPLEFT", b.nodeInfo.posX / 10, -b.nodeInfo.posY / 10) end
            end
            function tf:UpdatePadding() bp:ClearAllPoints(); bp:SetPoint("TOPLEFT", tf, "TOPLEFT", 0, 0); bp:SetPoint("BOTTOMRIGHT", tf, "BOTTOMRIGHT", 0, 40) end
            function tf:UpdateTreeCurrencyInfo() self.currencyUpdates = (self.currencyUpdates or 0) + 1 end
            function tf:UpdateAllButtons() for _, b in pairs(self.nodes) do b:FullUpdate() end end
            function tf:LoadTalentTreeInternal() self:UpdateAllTalentButtonPositions() end
            function tf:InstantiateTalentButton() end
            function tf:Show() if not self.shown then self.shown = true; if self.scripts and self.scripts.OnShow then self.scripts.OnShow(self) end end end
            function tf:Hide() if self.shown then self.shown = false; if self.scripts and self.scripts.OnHide then self.scripts.OnHide(self) end end end
            tf.shown = false
            psf.TalentsFrame = tf
            _G.UnitClass = function() return "Hunter", "HUNTER", 3 end
            _G.GetSpecializationInfoForClassID = function(classID, i) local names = {"Beast Mastery", "Marksmanship", "Survival"}; if names[i] then return 250 + i, names[i], "", 132000 + i end end
            _G.SetPortraitTexture = function(tex, unit) tex.portraitUnit = unit end
            local prevFile = _G.GetFileIDFromPath
            _G.GetFileIDFromPath = function(p)
                if p:find("HunterSurvival") then return nil end
                if p:find("TalentFrame") or p:find("TALENTFRAME") or p:find("Common%-Input") then return 136900 end
                return prevFile(p)
            end
            return tf
            end
            -- professions window: Forever's ProfessionsFrame (overview page with five cards, crafting page, side tabs)
            function w.LoadProfessionsBook()
            local pb = Frame("ProfessionsFrame"); pb:SetSize(673, 594); pb.level = 1
            pb.NineSlice = Frame("NineSlice"); pb.Bg = Region("Texture", {atlas = "Profession-Background-Overview"})
            pb.CloseButton = Frame("CloseButton"); pb.TitleContainer = Frame("TitleContainer"); pb.TitleContainer.TitleText = Region("FontString")
            pb.PortraitContainer = Frame("PortraitContainer"); pb.PortraitContainer.portrait = Region("Texture"); pb.PortraitContainer.CircleMask = Region("MaskTexture")
            pb.PortraitContainer.portrait:SetPoint("TOPLEFT", pb.PortraitContainer, "TOPLEFT", -5, 7); pb.PortraitContainer.portrait:SetSize(62, 62)
            pb.BookPage = Frame("BookPage"); pb.BookPage:SetSize(673, 594); pb.BookPage.level = 100; pb.BookPage.parent = pb
            pb.CraftingPage = Frame("CraftingPage"); pb.CraftingPage.parent = pb; pb.CraftingPage.shown = false
            pb.BookPage.ProfessionsContentFrame = Frame("ProfessionsContentFrame"); pb.BookPage.ProfessionsContentFrame.level = 101
            local content = pb.BookPage.ProfessionsContentFrame
            local function SpellButton(row, key, x, y, name, sub)
                local b = Frame(nil); b:SetSize(40, 40); b:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", x, y); b.parent = row
                b.IconTexture = Region("Texture"); b.IconTextureOverlay = Region("Texture", {atlas = "Profession-square-frame"}); b.IconTextureOverlay:SetSize(48, 48)
                b.spellString = Region("FontString"); b.spellString:SetText(name); b.spellString.textColor = {1, 0.82, 0}
                function b.spellString:GetTextColor() return unpack(self.textColor) end
                b.subSpellString = Region("FontString"); b.subSpellString:SetText(sub); b.subSpellString.textColor = {0.82, 0.70, 0.54}
                function b.subSpellString:GetTextColor() return unpack(self.textColor) end
                row[key] = b
                return b
            end
            local function Card(key, w, h, profession)
                local r = Frame(nil); r:SetSize(w, h); r:SetPoint("TOPLEFT", content, "TOPLEFT", 5, -41); r.parent = content; r.level = 102
                r.Background = Region("Texture", {atlas = "Profession-overview-Card-" .. (profession or "generic")})
                r.ProfessionName = Region("FontString"); r.ProfessionName:SetPoint("TOPLEFT", r, "TOPLEFT", 20, -24); r.ProfessionName:SetText(profession)
                r.ProfessionName.textColor = {1, 0.82, 0}; function r.ProfessionName:GetTextColor() return unpack(self.textColor) end
                r.missingHeader = Region("FontString"); r.missingText = Region("FontString"); r.missingText:SetSize(485, 22); r.missingText.textColor = {1, 1, 1}
                r.missingText:SetFontObject("ProfessionsCardParagraph")
                function r.missingText:GetTextColor() return unpack(self.textColor) end
                SpellButton(r, "SpellButton1", 15, 60, profession and "Tanning" or "", ""); SpellButton(r, "SpellButton2", 15, 10, profession or "", "Apprentice")
                r.StatusBar = Frame(nil); r.StatusBar:SetSize(441, 18); r.StatusBar.parent = r; r.StatusBar.Fill = Region("Texture", {atlas = "Skillbar_Fill_Flipbook_Skinning"})
                r.StatusBar.Rank = Frame(nil); r.StatusBar.Rank.Text = Region("FontString"); r.StatusBar.Rank.Text:SetText(profession and (profession .. " 1/75") or "")
                r.UnlearnButton = Frame(nil); r.UnlearnButton:SetSize(20, 20); r.UnlearnButton:SetPoint("LEFT", r.StatusBar, "RIGHT", 1, -4); r.UnlearnButton.parent = r
                if not profession then r.StatusBar.shown = false; r.SpellButton1.shown = false; r.SpellButton2.shown = false; r.UnlearnButton.shown = false; r.ProfessionName.shown = false
                else r.missingHeader.shown = false; r.missingText.shown = false end
                content[key] = r
                return r
            end
            Card("PrimaryProfession1", 664, 142, "Skinning"); Card("PrimaryProfession2", 664, 142)
            Card("SecondaryProfession1", 225, 275, "Cooking"); Card("SecondaryProfession2", 225, 275); Card("SecondaryProfession3", 225, 275)
            content.PrimaryProfession2.missingHeader:SetText("Second Profession"); content.PrimaryProfession2.missingText:SetText("You can learn a second primary profession.")
            local function SideTab(key, i)
                local t = Frame(key); t:SetSize(55, 55); t.parent = pb; t.level = 3
                t:SetPoint("TOPLEFT", pb, "TOPRIGHT", 0, -60 - (i - 1) * 55)
                t.Background = Region("Texture", {atlas = "common-sidetab"}); t.Icon = Region("Texture"); t.Icon:SetSize(50, 50); t.Icon:SetPoint("CENTER", t, "CENTER", 0, 0)
                t.Mask = Region("MaskTexture"); t.SelectedTexture = Region("Texture"); t.SelectedTexture.shown = i == 1; t.TabGlow = Region("Texture"); t.HighlightTexture = Region("Texture")
                function t.Icon:AddMaskTexture(m) self.maskAdded = m end
                pb[key] = t
                return t
            end
            SideTab("ProfessionsOverviewTab", 1); SideTab("Professions1Tab", 2)
            pb.updates = 0
            function pb:Update()
                -- Blizzard's refresh: card art and layout back
                self.updates = self.updates + 1
                local p1 = content.PrimaryProfession1
                p1:ClearAllPoints(); p1:SetPoint("TOPLEFT", content, "TOPLEFT", 5, -41); p1:SetSize(664, 142)
                p1.SpellButton1.IconTextureOverlay:SetAlpha(1); p1.StatusBar:SetAlpha(1); p1.Background:SetAlpha(1)
            end
            function pb:Show() if not self.shown then self.shown = true; if self.scripts and self.scripts.OnShow then self.scripts.OnShow(self) end end end
            function pb:Hide() if self.shown then self.shown = false; if self.scripts and self.scripts.OnHide then self.scripts.OnHide(self) end end end
            local page = pb.BookPage
            function page:Show() if not self.shown then self.shown = true; if self.scripts and self.scripts.OnShow then self.scripts.OnShow(self) end end end
            function page:Hide() if self.shown then self.shown = false; if self.scripts and self.scripts.OnHide then self.scripts.OnHide(self) end end end
            pb:Hide()
            _G.ProfessionsFrame = pb
            -- Skinning (prof1) and Cooking (slot 5); the other slots empty
            _G.GetProfessions = function() return 11, nil, nil, nil, 15 end
            _G.GetProfessionInfo = function(id)
                if id == 11 then return "Skinning", 134366, 1, 75, 2, 0, 393, 0 end
                if id == 15 then return "Cooking", 133971, 42, 75, 2, 0, 185, 5 end
            end
            return pb
            end
            -- Forever's merged map window: the quest log docked down its side
            function w.LoadQuestMap()
            local map = Frame("WorldMapFrame"); map:SetSize(1035, 534); map.level = 1
            map.WorldMapFrameBg = Region("Texture", {layer = "BACKGROUND"})
            map.BorderFrame = Frame("BorderFrame"); map.BorderFrame.parent = map
            map.BorderFrame.InsetBorderTop = Region("Texture", {atlas = "_UI-Frame-InnerTopTile", layer = "BACKGROUND"})
            map.BorderFrame.NineSlice = Frame("NineSlice")
            map.BorderFrame.NineSlice.TopEdge = Region("Texture", {atlas = "_UI-Frame-Metal-EdgeTop"})
            map.BorderFrame.PortraitContainer = Frame("PortraitContainer")
            map.BorderFrame.PortraitContainer.portrait = Region("Texture")
            map.BorderFrame.TitleContainer = Frame("TitleContainer")
            map.BorderFrame.TitleContainer.TitleText = Region("FontString"); map.BorderFrame.TitleContainer.TitleText:SetText("Map & Quest Log")
            map.BorderFrame.CloseButton = Frame("CloseButton")
            local side = Frame("QuestMapFrame"); side:SetSize(330, 506); side.parent = map; side.level = 2
            side.Background = Region("Texture", {atlas = "QuestLogBackground", layer = "BACKGROUND"})
            local scroll = Frame("QuestScrollFrame"); scroll:SetSize(308, 468); scroll.parent = side; scroll.level = 4
            scroll.Background = Region("Texture", {atlas = "QuestLog-empty-quest-background", layer = "BACKGROUND"})
            scroll.EmptyText = Region("FontString"); scroll.EmptyText:SetText("No quests available"); scroll.EmptyText.textColor = {1, 1, 1}
            -- retail's quest panel art lives on a frame of its own
            scroll.BorderFrame = Frame("BorderFrame"); scroll.BorderFrame.parent = scroll
            scroll.BorderFrame.Border = Region("Texture", {atlas = "QuestLog-frame", layer = "BORDER"})
            scroll.BorderFrame.TopDetail = Region("Texture", {atlas = "QuestLog-frame-filigree", layer = "ARTWORK"})
            scroll.BorderFrame.Shadow = Region("Texture", {atlas = "QuestLog-Frame-Gradient-bottom", layer = "BACKGROUND"})
            scroll.Contents = Frame("Contents"); scroll.Contents.parent = scroll
            local function QuestRow(key, title)
                local b = Frame(nil); b:SetSize(300, 16); b.parent = scroll.Contents
                b.Text = Region("FontString"); b.Text:SetText(title); b.Text:SetFontObject("QuestFont_Enormous")
                b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestLogTitleHighlightRetail")
                scroll.Contents[key] = b
                return b
            end
            QuestRow("Quest1", "Wolves Across the Border"); QuestRow("Quest2", "Kobold Candles")
            side.shown = false
            function side:Show() if not self.shown then self.shown = true; if self.scripts and self.scripts.OnShow then self.scripts.OnShow(self) end end end
            function side:Hide() if self.shown then self.shown = false; if self.scripts and self.scripts.OnHide then self.scripts.OnHide(self) end end end
            side.QuestsFrame = scroll
            map.QuestMapFrame = side
            _G.WorldMapFrame = map; _G.QuestMapFrame = side; _G.QuestScrollFrame = scroll
            return side
            end
            -- Forever's Appearances window: retail's CollectionsJournal, which Era never had
            function w.LoadCollections()
            local cj = Frame("CollectionsJournal"); cj:SetSize(830, 600); cj.level = 1; cj.selectedTab = 2
            cj.Bg = Region("Texture", {atlas = "collections-background", layer = "BACKGROUND"})
            cj.NineSlice = Frame("NineSlice"); cj.NineSlice.TopEdge = Region("Texture", {atlas = "nineslice-top"})
            cj.PortraitContainer = Frame("PortraitContainer"); cj.PortraitContainer.portrait = Region("Texture")
            cj.CloseButton = Frame("CloseButton")
            cj.TitleContainer = Frame("TitleContainer"); cj.TitleContainer.TitleText = Region("FontString"); cj.TitleContainer.TitleText:SetText("Appearances")
            -- the dark page inside: the wardrobe's own activeFrame art
            local wardrobe = Frame("WardrobeCollectionFrame"); wardrobe.parent = cj
            local page = Frame("activeFrame"); page.parent = wardrobe
            page.Bg = Region("Texture", {layer = "BACKGROUND"})
            page.BackgroundTile = Region("Texture", {atlas = "collections-background-tile", layer = "BACKGROUND"})
            page.ShadowCornerTopLeft = Region("Texture", {atlas = "collections-background-shadow-large", layer = "BORDER"})
            page.NineSlice = Frame("NineSlice"); page.NineSlice.TopEdge = Region("Texture", {atlas = "UI-Frame-InnerTopTile"})
            wardrobe.activeFrame = page
            cj.WardrobeCollectionFrame = wardrobe
            _G.WardrobeCollectionFrame = wardrobe
            cj.shown = false
            function cj:Show() if not self.shown then self.shown = true; if self.scripts and self.scripts.OnShow then self.scripts.OnShow(self) end end end
            function cj:Hide() if self.shown then self.shown = false; if self.scripts and self.scripts.OnHide then self.scripts.OnHide(self) end end end
            _G.CollectionsJournal = cj
            _G.PanelTemplates_GetSelectedTab = function(f) return f.selectedTab end
            _G.CollectionsJournal_SetTab = function(f, n) f.selectedTab = n end
            return cj
            end
            -- Forever's guild window: retail's CommunitiesFrame, where Era
            -- had a tab on the friends window
            function w.LoadGuild()
            local cf = Frame("CommunitiesFrame"); cf:SetSize(814, 426); cf.level = 1
            cf.Bg = Region("Texture", {layer = "BACKGROUND"})
            cf.TopTileStreaks = Region("Texture", {atlas = "_UI-Frame-TopTileStreaks", layer = "BORDER"})
            cf.NineSlice = Frame("NineSlice")
            cf.NineSlice.TopLeftCorner = Region("Texture", {atlas = "UI-Frame-PortraitMetal-CornerTopLeft"})
            cf.NineSlice.TopEdge = Region("Texture", {atlas = "UI-Frame-Metal-EdgeTop"})
            cf.PortraitContainer = Frame("PortraitContainer"); cf.PortraitContainer.portrait = Region("Texture")
            cf.PortraitOverlay = Frame("PortraitOverlay"); cf.PortraitOverlay.Portrait = Region("Texture")
            cf.CloseButton = Frame("CloseButton")
            cf.TitleContainer = Frame("TitleContainer")
            cf.TitleContainer.TitleText = Region("FontString"); cf.TitleContainer.TitleText:SetText("Guild & Communities")
            -- the sidebar: its own dark page, filigree and inset nine-slice
            local list = Frame("CommunitiesList"); list:SetSize(171, 374); list.parent = cf
            list.Bg = Region("Texture", {layer = "BACKGROUND"})
            list.TopFiligree = Region("Texture")
            list.BottomFiligree = Region("Texture")
            list.FilligreeOverlay = Frame("FilligreeOverlay")
            list.FilligreeOverlay.LeftBar = Region("Texture")
            list.FilligreeOverlay.TopBar = Region("Texture")
            list.InsetFrame = Frame("InsetFrame")
            list.InsetFrame.NineSlice = Frame("NineSlice")
            list.InsetFrame.NineSlice.TopEdge = Region("Texture", {atlas = "UI-Frame-InnerTopTile"})
            list.ScrollBox = Frame("ScrollBox"); list.ScrollBox.parent = list
            cf.CommunitiesList = list
            _G.CommunitiesList = list
            -- the guild finder page, dark art of its own again
            local finder = Frame("ClubFinderGuildFinderFrame"); finder:SetSize(611, 314); finder.parent = cf
            finder.DisabledFrame = Frame("DisabledFrame")
            finder.DisabledFrame.Bg = Region("Texture", {layer = "BACKGROUND"})
            finder.DisabledFrame.WideBackground = Region("Texture", {atlas = "communities-widebackground"})
            finder.DisabledFrame.NineSlice = Frame("NineSlice")
            finder.DisabledFrame.NineSlice.TopEdge = Region("Texture", {atlas = "UI-Frame-InnerTopTile"})
            finder.Title = Region("FontString"); finder.Title:SetText("Guild")
            cf.GuildFinderFrame = finder
            _G.ClubFinderGuildFinderFrame = finder
            cf.displayMode = 1
            function cf:SetDisplayMode(m) self.displayMode = m end
            cf.shown = false
            function cf:Show() if not self.shown then self.shown = true; if self.scripts and self.scripts.OnShow then self.scripts.OnShow(self) end end end
            function cf:Hide() if self.shown then self.shown = false; if self.scripts and self.scripts.OnHide then self.scripts.OnHide(self) end end end
            _G.CommunitiesFrame = cf
            return cf
            end
            _G.Enum.SpellBookSpellBank = {Player = 0, Pet = 1}
            _G.Enum.SpellBookItemType = {None = 0, Spell = 1, FutureSpell = 2, PetAction = 3, Flyout = 4}
            _G.PAGE_NUMBER = "Page %d"; _G.SPELLBOOK = "Spellbook"; _G.PET = "Pet"
            -- two skill lines: General (3 spells, one passive, one future), Holy (14 spells over two pages)
            w.spellItems = {
                {actionID = 6603, spellID = 6603, itemType = 1, name = "Attack", iconID = 135641},
                {actionID = 20600, spellID = 20600, itemType = 1, name = "Perception", subName = "Racial", iconID = 136090},
                {actionID = 20599, spellID = 20599, itemType = 1, name = "Diplomacy", subName = "Racial Passive", iconID = 134328, isPassive = true},
                {actionID = 1, spellID = 1, itemType = 2, name = "Future", iconID = 1}
            }
            for i = 1, 14 do w.spellItems[#w.spellItems + 1] = {actionID = 1000 + i, spellID = 1000 + i, itemType = 1, name = "Holy " .. i, subName = "Rank " .. i, iconID = 2000 + i} end
            w.petSpells = 0; w.pickedUp = nil
            _G.C_SpellBook = {
                GetNumSpellBookSkillLines = function() return 2 end,
                GetSpellBookSkillLineInfo = function(i) if i == 1 then return {name = "General", iconID = 626005, itemIndexOffset = 0, numSpellBookItems = 4} elseif i == 2 then return {name = "Holy", iconID = 135920, itemIndexOffset = 4, numSpellBookItems = 14} end end,
                GetSpellBookItemInfo = function(slot, bank) local d = w.spellItems[slot]; if d and bank == 0 then local c = {}; for k, v in pairs(d) do c[k] = v end; return c end end,
                HasPetSpells = function() if w.petSpells > 0 then return w.petSpells, "PET" end end,
                PickupSpellBookItem = function(slot, bank) w.pickedUp = {slot, bank} end
            }
            _G.C_Spell = {GetSpellCooldown = function(id) if id == 6603 then return {startTime = 100, duration = 5} end return {startTime = 0, duration = 0} end}
            _G.StaticPopupDialogs = {UNLEARN_SKILL = {}}
            _G.StaticPopup_Show = function(which, a, b, data) w.popup = {which, a, data} end
            -- Show/Hide of the paper doll fire its scripts like the client does
            local pd = _G.PaperDollFrame
            function pd:Show() if not self.shown then self.shown = true; if self.scripts and self.scripts.OnShow then self.scripts.OnShow(self) end end end
            function pd:Hide() if self.shown then self.shown = false; if self.scripts and self.scripts.OnHide then self.scripts.OnHide(self) end end end
            pd:SetScript("OnShow", function(self) PaperDollFrame_SetSidebar(PaperDollSidebarTabs, 1); CharacterFrame:Expand() end)
            pd:SetScript("OnHide", function(self) CharacterFrame:Collapse(); PaperDollSidebarTabs:Hide() end)
            _G.CharacterStatsPaneScrollBox = Frame("CharacterStatsPaneScrollBox"); _G.CharacterStatsPaneScrollBox.ScrollBox = Frame("ScrollBox")
            _G.PaperDollSidebarTabs = Frame("PaperDollSidebarTabs")
            for i = 1, 3 do _G["PaperDollSidebarTab" .. i] = Frame("PaperDollSidebarTab" .. i) end
            _G.PaperDollLevelInfo = Frame("PaperDollLevelInfo")
            _G.PaperDollFrame_ShowSidebar = function(frame) w.sidebarShown = frame end
            _G.PaperDollFrame_SetSidebar = function(tabs, index) CharacterStatsPaneScrollBox:Show(); PaperDollFrame_ShowSidebar(CharacterStatsPaneScrollBox) end
            local model = Frame("CharacterModelScene"); model:SetPoint("TOPLEFT", cf.LeftPaneHost, "TOPLEFT", 0, 0); model:SetPoint("BOTTOMRIGHT", cf.LeftPaneHost, "BOTTOMRIGHT", 0, 0); model:SetSize(398, 464)
            for _, k in ipairs({"BackgroundTopLeft", "BackgroundTopRight", "BackgroundBotLeft", "BackgroundBotRight", "BackgroundOverlay"}) do model[k] = Region("Texture") end
            _G.CharacterModelScene = model
            local function Slot(name, point, rel, relPoint, x, y)
                local s = Frame(name); s:SetSize(37, 37); s:SetPoint(point, rel, relPoint, x, y); s.level = 101
                s.BorderFrame = Frame("BorderFrame"); s.icon = Region("Texture")
                _G[name] = s
                return s
            end
            local left = {"CharacterHeadSlot", "CharacterNeckSlot", "CharacterShoulderSlot", "CharacterBackSlot", "CharacterChestSlot", "CharacterShirtSlot", "CharacterTabardSlot", "CharacterWristSlot"}
            local right = {"CharacterHandsSlot", "CharacterWaistSlot", "CharacterLegsSlot", "CharacterFeetSlot", "CharacterFinger0Slot", "CharacterFinger1Slot", "CharacterTrinket0Slot", "CharacterTrinket1Slot"}
            local prev
            for _, n in ipairs(left) do prev = Slot(n, prev and "TOPLEFT" or "TOPLEFT", prev or cf.LeftPaneHost, prev and "BOTTOMLEFT" or "TOPLEFT", prev and 0 or 24, prev and -6 or -60) end
            prev = nil
            for _, n in ipairs(right) do prev = Slot(n, prev and "TOPLEFT" or "TOPRIGHT", prev or cf.LeftPaneHost, prev and "BOTTOMLEFT" or "TOPRIGHT", prev and 0 or -20, prev and -6 or -60) end
            local main = Slot("CharacterMainHandSlot", "BOTTOM", cf.LeftPaneHost, "BOTTOM", -60, 30)
            local off = Slot("CharacterSecondaryHandSlot", "TOPLEFT", main, "TOPRIGHT", 6, 0)
            local ranged = Slot("CharacterRangedSlot", "TOPLEFT", off, "TOPRIGHT", 6, 0)
            local ammo = Slot("CharacterAmmoSlot", "LEFT", ranged, "RIGHT", 19, 0); ammo:SetSize(27, 27)
            ammo.gearSlotSmall = Region("Texture", {atlas = "UI-Character-Info-GearSlotSmall"})
            ammo.arrowHolder = Frame("arrowHolder"); ammo.arrowHolder.arrow = Region("Texture", {atlas = "UI-Character-Info-GearSlot-Arrow"})
            _G.ToggleCharacter = function(tab, onlyShow)
                w.toggled = tab
                if CharacterFrame:IsShown() then
                    if not _G[tab]:IsShown() then CharacterFrame:ShowSubFrame(tab) end
                else
                    CharacterFrame:ShowSubFrame(tab)
                    CharacterFrame:Show(); CharacterFrame:RefreshRightPane()
                end
                CharacterFrame:RefreshDisplay()
            end
            _G.HideUIPanel = function(f) f:Hide() end
            cf:ShowSubFrame("PaperDollFrame")
            cf:Hide()
            -- unit stat API
            _G.UnitLevel = function() return 39 end
            _G.UnitRace = function() return "Human", "Human" end
            _G.UnitClass = function() return "Priest", "PRIEST" end
            _G.GetGuildInfo = function() return "Guild Name", "Member" end
            _G.UnitStat = function(unit, i) return 20 + i, 25 + i, 5, 0 end
            _G.UnitArmor = function() return 300, 350, 300, 50, 0 end
            _G.UnitAttackBothHands = function() return 195, 0 end
            _G.UnitAttackPower = function() return 100, 20, -5 end
            _G.UnitDamage = function() return 40, 60, 0, 0, 0, 0, 1 end
            _G.UnitAttackSpeed = function() return 2.5 end
            _G.GetInventoryItemTexture = function(unit, slot) if slot == 18 then return w.rangedTexture end end
            _G.UnitRangedAttack = function() return 150, 0 end
            _G.UnitRangedAttackPower = function() return 60, 0, 0 end
            _G.UnitRangedDamage = function() return 2.0, 30, 50, 0, 0, 1 end
            _G.UnitResistance = function(unit, id) if id == 2 then return 10, 15, 5, 0 elseif id == 5 then return 0, -3, 0, -3 end return 0, 0, 0, 0 end
            _G.PaperDollFrame_GetArmorReduction = function(armor, level) return 12.5 end
            _G.GameTooltip = Frame("GameTooltip"); _G.GameTooltip.lines = {}
            function _G.GameTooltip:SetOwner() self.lines = {} end
            function _G.GameTooltip:SetText(t) self.lines[#self.lines + 1] = t end
            function _G.GameTooltip:AddLine(t) self.lines[#self.lines + 1] = t end
            function _G.GameTooltip:AddDoubleLine(a, b) self.lines[#self.lines + 1] = a .. " " .. tostring(b) end
            function _G.GameTooltip:SetSpellBookItem(slot, bank) self.spellBookItem = {slot, bank} end
            _G.GetFileIDFromPath = function(p) if p:find("Nameplate") then return 130000 end if p:find("PaperDollInfoFrame") or p:find("MinimizeButton") then return 136500 end if p:find("MainMenuBar") or p:find("Interface\\Buttons\\UI%-") then return 136407 end end
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
                -- Blizzard's secure code may index with a secret bar type; the addon's may not
                local info = type(self.barType) == "table" and CastingBarTypeInfo[1] or CastingBarTypeInfo[self.barType]
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
    for _, file in ipairs({"Core.lua", "EraPanel.lua", "PlayerSpells.lua", "Nameplates.lua", "CastBar.lua", "Combo.lua", "UnitFrames.lua", "PartyFrames.lua", "CharacterSheet.lua", "CharacterLists.lua", "SpellBook.lua", "Talents.lua", "Professions.lua", "QuestLog.lua", "Collections.lua", "Guild.lua", "ActionBars.lua", "Minimap.lua", "Tracker.lua", "Options.lua", "Probe.lua", "Feedback.lua"}) do
        local chunk, err = loadfile(root .. "/ForeverClassicUI/" .. file)
        assert(chunk, err)
        chunk("ForeverClassicUI", ns)
    end
    w.ns = ns
    lastNs = ns
    -- the "coming soon" hold: nothing is held back right now, but the
    -- mechanism stays, so a world can hold a part to test it (opts.hold)
    -- or lift every hold (opts.unhold)
    if opts.hold then for _, k in ipairs(opts.hold) do ns.COMING_SOON[k] = true end end
    if opts.unhold then for k in pairs(ns.COMING_SOON) do ns.COMING_SOON[k] = nil end end
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
    check(w.ns.modules.tracker.mode == "native", "era: classic quest watch left alone")
    check(w.ns.db.savedNameplateStyle == nil, "era: nothing to restore")
    check(w.ns.modules.castbar.mode == "native", "era: cast bar recognised as classic already")
    check(PlayerCastingBarFrame.lookCalls == 0, "era: cast bar not touched")
    check(w.ns.modules.combo.mode == "native", "era: combo points left to Blizzard")
    check(w.ns.modules.unitframes.mode == "native" and w.ns.modules.party.mode == "native" and w.ns.modules.actionbars.mode == "native" and w.ns.modules.minimap.mode == "native", "era: frames, party, bars and minimap left to Blizzard")
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
        local lv = p.UnitFrame.LevelFrame
        check(#lv.anchors == 1 and lv.anchors[1][2] == bg and lv.anchors[1][3] == "RIGHT" and math.abs(lv.anchors[1][4] + 12.4) < 0.01, "forever: level centred in the longer slot on plate " .. i)
        lv:ClearAllPoints(); lv:SetPoint("CENTER", bg, "RIGHT", -8.8, 0) -- Blizzard's own anchor
        check(#lv.anchors == 1 and math.abs(lv.anchors[1][4] + 12.4) < 0.01, "forever: level anchor re-applied after Blizzard's SetPoint on plate " .. i)
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
    -- enemy casts: Forever makes barType a secret value, which errors as a table key from addon code
    local tsb = TargetFrameSpellBar
    local realInfo = CastingBarTypeInfo
    _G.CastingBarTypeInfo = setmetatable({}, {__index = function(_, k)
        if type(k) == "table" then error("attempted to index a table that cannot be indexed with secret keys") end
        return realInfo[k]
    end})
    tsb.barType = {__secret = true}
    local okFill = pcall(tsb.UpdateBarFillTexture, tsb, false)
    check(okFill and tsb.barColor[1] == 1 and tsb.barColor[2] == 0.7 and tsb.fill.texture == "Interface\\TargetingFrame\\UI-StatusBar", "forever: secret bar type on an enemy cast: classic yellow fill, no error")
    okFill = pcall(tsb.UpdateBarFillTexture, tsb, true)
    check(okFill and tsb.barColor[1] == 0 and tsb.barColor[2] == 1, "forever: full fill still green when only the bar type is secret")
    tsb.barType = 1; _G.CastingBarTypeInfo = realInfo

    -- unit frames
    local uf = w.ns.modules.unitframes
    check(uf.mode == "restyled", "forever: unit frames re-skinned")
    local pc = PlayerFrame.PlayerFrameContainer
    local pm = PlayerFrame.PlayerFrameContent.PlayerFrameContentMain
    local own = uf.own[PlayerFrame]
    local skin = own and own.skin
    check(skin and skin.art.texture == "Interface\\TargetingFrame\\UI-TargetingFrame" and skin.art.width == 193 and skin.art.height == 77 and skin.art.texcoord[1] == 0.85546875, "forever: player frame uses the classic (mirrored) art, on the skin frame")
    check(skin.level == 12 and pm.level == 12 and pm.HealthBarsContainer.level == 12 and pc.FrameTexture.alpha == 0, "forever: skin at the (locked) bars' own level, Blizzard's art under them transparent")
    -- draw order at that level: bar fills BACKGROUND < art BORDER < the bars' OVERLAY numbers (Classic had the numbers over the art)
    check(skin.art.layer == "BORDER" and pm.HealthBarsContainer.HealthBar.fill.layer == "BACKGROUND" and pm.ManaBarArea.ManaBar.fill.layer == "BACKGROUND", "forever: bar fills on BACKGROUND under the art, so the health and mana numbers (OVERLAY) draw over it")
    check(PlayerFrame.PlayerFrameContent.PlayerFrameContentContextual.level == 14, "forever: contextual icons raised above the skin")
    -- the bars hang off the player frame by both corners, not off Blizzard's container
    local phb, pmb = pm.HealthBarsContainer.HealthBar, pm.ManaBarArea.ManaBar
    check(#phb.anchors == 2 and phb.anchors[1][2] == PlayerFrame and phb.anchors[1][4] == 90 and phb.anchors[1][5] == -45 and phb.anchors[2][1] == "BOTTOMRIGHT" and phb.anchors[2][3] == "TOPLEFT" and phb.anchors[2][4] == 209 and phb.anchors[2][5] == -57, "forever: player health bar anchored by both corners to the player frame (119x12 at 90,-45)")
    check(#pmb.anchors == 2 and pmb.anchors[1][5] == -56 and pmb.anchors[2][4] == 209 and pmb.anchors[2][5] == -68, "forever: player mana bar likewise, under it")
    check(pm.HealthBarsContainer.HealthBarText.anchors[1][2] == phb and pm.HealthBarsContainer.LeftText.anchors[1][2] == phb and pm.HealthBarsContainer.LeftText.anchors[1][4] == 2, "forever: health numbers (on Blizzard's container) anchored to the bar itself")
    check(PlayerName.width == 116 and PlayerName.justify == "CENTER" and PlayerName.anchors[1][4] == 34, "forever: name box the width of the art's strip (Forever's longer names), still centred")
    check(pc.FrameFlash.texture == "Interface\\TargetingFrame\\UI-TargetingFrame-Flash" and pc.FrameFlash.texcoord[1] == 0.9453125 and pc.FrameFlash.texcoord[4] == 0.181640625 and pc.FrameFlash.width == 242, "forever: player combat flash cut from the right part of its image, mirrored")
    TargetFrame.TargetFrameContainer.Flash:SetAtlas("UI-HUD-UnitFrame-Target-PortraitOn-InCombat"); TargetFrame:CheckClassification()
    local tfl = TargetFrame.TargetFrameContainer.Flash
    check(tfl.texture == "Interface\\TargetingFrame\\UI-TargetingFrame-Flash" and tfl.texcoord[2] == 0.9453125 and tfl.width == 242, "forever: target combat flash restored after Blizzard's classification update")
    check(pm.HealthBarsContainer.width == 119 and pm.HealthBarsContainer.height == 12 and pm.HealthBarsContainer.HealthBar.barTexture == "Interface\\TargetingFrame\\UI-StatusBar", "forever: player health bar is 119x12 classic")
    check(pm.HealthBarsContainer.HealthBar.fill.maskRemoved == pm.HealthBarsContainer.HealthBarMask, "forever: retail health mask (on the bars container) removed from the fill")
    local hmask = pm.HealthBarsContainer.HealthBarMask
    check(hmask.texture == "Interface\\Buttons\\WHITE8x8" and hmask.atlas == nil and #hmask.anchors == 2 and hmask.anchors[1][2] == pm.HealthBarsContainer.HealthBar and hmask.shown == true, "forever: retail health mask made a white square over the bar (shown, so anything still masked stays visible)")
    check(pm.ManaBarArea.ManaBar.ManaBarMask.texture == "Interface\\Buttons\\WHITE8x8" and pm.ManaBarArea.ManaBar.fill.maskRemoved == pm.ManaBarArea.ManaBar.ManaBarMask, "forever: retail mana mask neutralised too")
    check(pm.ManaBarArea.ManaBar.barTexture == "Interface\\TargetingFrame\\UI-StatusBar" and pm.ManaBarArea.ManaBar.barColor[3] == 1, "forever: mana bar classic texture, coloured by power type")
    local pmask = pc.PlayerPortraitMask
    check(pmask.atlas == "CircleMask" and pmask.anchors[1][2] == pc.PlayerPortrait and pmask.anchors[1][4] == 0 and #pmask.anchors == 2, "forever: portrait keeps a plain full-size circle mask (the classic art is open at the corners)")
    check(pm.LevelBackgroundCircle.shown == false and own.backdrop and own.backdrop.height == 41 and own.backdrop.anchors[1][2] == PlayerFrame and pc.forevercuiBackdrop == nil, "forever: level circle hidden, 119x41 dark backdrop on the player frame itself (no field written into Blizzard's frame)")
    check(pm.HealthBarsContainer.PlayerFrameHealthBarAnimatedLoss.alpha == 0 and pm.HealthBarsContainer.PlayerFrameTempMaxHealthLoss.alpha == 0, "forever: retail red health-loss trail faded out")
    -- level text: Blizzard's copy under the art goes transparent, ours on the skin mirrors it in gold
    local lvl = skin.levelText
    check(PlayerLevelText.alpha == 0 and lvl.text == "2" and lvl.vertex[1] == 1 and lvl.vertex[2] == 0.82 and lvl.anchors[1][3] == "BOTTOMLEFT" and lvl.anchors[1][4] == 36 and lvl.anchors[1][5] == 31, "forever: player level copied onto the skin in gold, on whole pixels in the frame corner")
    check(lvl.width == 40 and lvl.height == 14 and lvl.justify == "CENTER" and lvl.justifyV == "MIDDLE" and #lvl.anchors == 1 and lvl.anchors[1][1] == "CENTER", "forever: level copy is a fixed centred box on the art's circle")
    PlayerFrame_UpdateLevel()
    check(lvl.text == "3" and lvl.vertex[2] == 0.82, "forever: level copy follows Blizzard's update and stays gold after its white repaint")
    PlayerLevelText:Hide()
    check(lvl.shown == false, "forever: level copy hides with Blizzard's")
    PlayerLevelText:Show()
    check(lvl.shown == true, "forever: ...and shows again")
    -- status glow: ours on the skin follows Blizzard's shown/colour/pulse, Blizzard's loses its image
    check(skin.glow.texture == "Interface\\CharacterFrame\\UI-Player-Status" and skin.glow.texcoord[2] == 0.74609375 and skin.glow.texcoord[4] == 0.53125 and skin.glow.blend == "ADD" and skin.glow.shown == false and pm.StatusTexture.texture == nil, "forever: rest/combat glow on the skin, cut like Era, hidden like Blizzard's")
    pm.StatusTexture:SetVertexColor(1, 0, 0, 1); pm.StatusTexture:Show(); pm.StatusTexture:SetAlpha(0.6)
    check(skin.glow.shown == true and skin.glow.vertex[1] == 1 and skin.glow.vertex[2] == 0 and skin.glow.alpha == 0.6, "forever: glow copy turns red, shows and pulses with Blizzard's")
    pm.StatusTexture:Hide()
    check(skin.glow.shown == false, "forever: glow copy hides with Blizzard's")
    check(PlayerFrame.PlayerFrameContent.PlayerFrameContentContextual.PlayerRestLoop.alpha == 0 and skin.rest and skin.rest.texture == "Interface\\CharacterFrame\\UI-StateIcon" and skin.rest.alpha == 0, "forever: retail rest flipbook faded, classic rest icon added (hidden while not resting)")
    w.resting = true; skin:Fire("PLAYER_UPDATE_RESTING")
    check(skin.rest.alpha == 1, "forever: rest icon shows when resting")
    w.resting = false; skin:Fire("PLAYER_UPDATE_RESTING")
    check(skin.rest.alpha == 0, "forever: rest icon hides again")
    local tc = TargetFrame.TargetFrameContainer
    local tskin = uf.own[TargetFrame].skin
    check(tskin and tskin.art.texture == "Interface\\TargetingFrame\\UI-TargetingFrame" and tskin.art.width == 230 and tskin.level == 502 and tc.FrameTexture.alpha == 0 and tc.BossPortraitFrameTexture.shown == false, "forever: target frame classic art on its skin at the bars' level")
    check(TargetFrame.TargetFrameContent.TargetFrameContentContextual.level == 504, "forever: target contextual icons (skull, marks, auras) raised above the skin")
    local tm = TargetFrame.TargetFrameContent.TargetFrameContentMain
    check(tm.ReputationColor.texture == "Interface\\TargetingFrame\\UI-TargetingFrame-LevelBackground" and tm.HealthBarsContainer.width == 119, "forever: target name strip and health bar classic")
    local thb, tmb = tm.HealthBarsContainer.HealthBar, tm.ManaBar
    check(#thb.anchors == 2 and thb.anchors[1][1] == "TOPLEFT" and thb.anchors[1][2] == TargetFrame and thb.anchors[1][3] == "TOPRIGHT" and thb.anchors[1][4] == -209 and thb.anchors[1][5] == -45 and thb.anchors[2][1] == "BOTTOMRIGHT" and thb.anchors[2][4] == -90 and thb.anchors[2][5] == -57, "forever: target health bar anchored by both corners to the target frame (119x12, right edge at -90)")
    check(#tmb.anchors == 2 and tmb.anchors[1][5] == -56 and tmb.anchors[2][5] == -68 and tmb.level == 502 and tmb.fill.layer == "BACKGROUND", "forever: target mana bar likewise, brought down to the bars' level with its fill under the art")
    check(tm.HealthBarsContainer.HealthBarText.anchors[1][2] == thb and tm.HealthBarsContainer.RightText.anchors[1][4] == -2, "forever: target health numbers anchored to the bar")
    check(tm.Name.width == 116 and tm.Name.anchors[1][4] == -34, "forever: target name box the width of the strip")
    check(tm.HealthBarsContainer.HealthBar.fill.maskRemoved == tm.HealthBarsContainer.HealthBarMask and tm.HealthBarsContainer.HealthBarMask.texture == "Interface\\Buttons\\WHITE8x8" and tc.PortraitMask.atlas == "CircleMask", "forever: target bar mask neutralised, portrait round")
    check(uf.own[TargetFrame].backdrop.height == 25 and uf.own[TargetFrame].backdrop.anchors[1][1] == "TOPRIGHT", "forever: target backdrop is Era's 119x25")
    local tlvl = tskin.levelText
    check(tm.LevelText.alpha == 0 and tlvl.text == "1" and tlvl.vertex[2] == 0.82 and tlvl.anchors[1][3] == "BOTTOMRIGHT", "forever: target level copied onto the skin")
    tm.LevelText:SetText("7"); tm.LevelText:SetVertexColor(1, 1, 0)
    check(tlvl.text == "7" and tlvl.vertex[1] == 1 and tlvl.vertex[2] == 1 and tlvl.vertex[3] == 0, "forever: target level copy follows Blizzard's text and difficulty colour")
    tm.LevelText:Hide()
    check(tlvl.shown == false and TargetFrame.TargetFrameContent.TargetFrameContentContextual.HighLevelTexture.anchors[1][2] == tlvl, "forever: level copy hides for skull targets, skull centred on it")
    check(uf.own[FocusFrame].skin.art.texture == "Interface\\TargetingFrame\\UI-TargetingFrame", "forever: focus frame too")
    -- pet frame
    local petOwn = uf.own[PetFrame]
    check(petOwn and petOwn.art and petOwn.art.tex.texture == "Interface\\TargetingFrame\\UI-SmallTargetingFrame" and petOwn.art.tex.width == 128 and petOwn.art.level == 7 and PetFrameManaBar.fill.layer == "BACKGROUND", "forever: classic small pet frame art on a frame at the pet bars' level, fills under it")
    check(PetFrameTexture.alpha == 0 and PetFrame.width == 128 and PetFrame.height == 53, "forever: retail pet art faded, pet frame Era-sized")
    check(PetPortrait.width == 37 and PetPortrait.anchors[1][4] == 7 and PetFrame.PortraitMask.atlas == "CircleMask", "forever: pet portrait 37px, round")
    check(PetFrameHealthBar.width == 69 and PetFrameHealthBar.height == 8 and PetFrameHealthBar.anchors[1][5] == -22 and PetFrameHealthBar.barTexture == "Interface\\TargetingFrame\\UI-StatusBar" and PetFrameHealthBar.fill.maskRemoved == PetFrameHealthBarMask, "forever: pet health bar 69x8 classic, unmasked")
    check(PetFrameManaBar.anchors[1][5] == -29 and PetFrameManaBar.barColor[1] == 1 and PetFrameManaBar.barColor[2] == 0.5, "forever: pet mana bar under it, coloured by the pet's power type")
    check(PetFrameFlash.texture == "Interface\\TargetingFrame\\UI-PartyFrame-Flash" and PetFrameFlash.texcoord[3] == 1 and PetAttackModeTexture.texture == "Interface\\TargetingFrame\\UI-Player-AttackStatus" and PetAttackModeTexture.blend == "ADD", "forever: pet flash and attack glow classic")
    check(PetName.anchors[1][1] == "BOTTOMLEFT" and PetName.anchors[1][4] == 52 and PetName.anchors[1][5] == 33, "forever: pet name in the classic spot")
    UnitFrameManaBar_UpdateType(PetFrameManaBar)
    check(PetFrameManaBar.barTexture == "Interface\\TargetingFrame\\UI-StatusBar" and PetFrameManaBar.barColor[2] == 0.5, "forever: pet mana texture restored after Blizzard's power-type update")
    -- Blizzard redraws: elite target, mana type change, player art reset
    w.classification = "elite"
    TargetFrame:CheckClassification()
    check(tskin.art.texture == "Interface\\TargetingFrame\\UI-TargetingFrame-Elite" and tc.FrameTexture.alpha == 0, "forever: elite target gets the classic elite art after Blizzard's redraw")
    -- Blizzard's CheckClassification also resizes the health container to 126x20 and puts its atlas fill back
    tm.HealthBarsContainer:SetSize(126, 20); tm.HealthBarsContainer.HealthBar:SetStatusBarTexture("UI-HUD-UnitFrame-Target-PortraitOn-Bar-Health")
    TargetFrame:CheckClassification()
    check(tm.HealthBarsContainer.width == 119 and tm.HealthBarsContainer.height == 12 and tm.HealthBarsContainer.HealthBar.barTexture == "Interface\\TargetingFrame\\UI-StatusBar", "forever: classic bar size and fill restored after Blizzard's classification update")
    w.inCombat = true
    -- a target change in combat: Blizzard (secure) resizes the container and hangs it off a new
    -- corner; the bar, anchored to the frame itself, does not move, and nothing of ours touches
    -- a protected frame (that would be blocked and blamed on the addon)
    tm.HealthBarsContainer:SetSize(126, 20); tm.HealthBarsContainer:SetPoint("BOTTOMRIGHT", tc, "LEFT", 149, -10); tm.HealthBarsContainer.HealthBar:SetStatusBarTexture("atlas")
    w.ResetBlocked()
    TargetFrame:CheckClassification()
    check(tm.HealthBarsContainer.width == 126 and tm.HealthBarsContainer.HealthBar.barTexture == "Interface\\TargetingFrame\\UI-StatusBar", "forever: in combat only the fill changes, layout waits")
    check(w.Blocked() == 0 and #thb.anchors == 2 and thb.anchors[1][2] == TargetFrame and thb.anchors[1][4] == -209 and uf.pendingBars[TargetFrame] == true, "forever: the health bar keeps its own corners on the frame while Blizzard's container moves in combat, no protected call made")
    -- Blizzard's art swap in combat: textures change now, the player's layout waits too
    pm.HealthBarsContainer:SetSize(126, 20); PlayerFrame.PlayerFrameContent.PlayerFrameContentContextual.level = 12
    pc.FrameTexture:SetAtlas("UI-HUD-UnitFrame-Player-PortraitOn"); pc.FrameTexture.alpha = 1
    w.ResetBlocked()
    PlayerFrame_ToPlayerArt()
    check(pc.FrameTexture.alpha == 0 and pm.HealthBarsContainer.width == 126 and PlayerFrame.PlayerFrameContent.PlayerFrameContentContextual.level == 12 and uf.pendingPlayer == true, "forever: in combat Blizzard's art is faded again at once, bars and frame levels wait")
    check(w.Blocked() == 0 and #phb.anchors == 2 and phb.anchors[1][2] == PlayerFrame, "forever: no protected call on the player frame in combat, its bars keep their corners")
    w.inCombat = false
    uf.barWaiter:Fire("PLAYER_REGEN_ENABLED")
    check(tm.HealthBarsContainer.width == 119, "forever: layout applied once combat ends")
    check(pm.HealthBarsContainer.width == 119 and PlayerFrame.PlayerFrameContent.PlayerFrameContentContextual.level == 14 and uf.pendingPlayer == nil, "forever: player bars re-laid out and contextual re-raised once combat ends")
    UnitFrameManaBar_UpdateType(pm.ManaBarArea.ManaBar)
    check(pm.ManaBarArea.ManaBar.barTexture == "Interface\\TargetingFrame\\UI-StatusBar", "forever: mana texture restored after Blizzard's power-type update")
    pc.FrameTexture:SetAtlas("UI-HUD-UnitFrame-Player-PortraitOn"); pc.FrameTexture.alpha = 1; pm.StatusTexture:SetAtlas("UI-HUD-UnitFrame-Player-PortraitOn-Status")
    PlayerFrame_ToPlayerArt()
    check(pc.FrameTexture.alpha == 0 and skin.art.texture == "Interface\\TargetingFrame\\UI-TargetingFrame" and pm.StatusTexture.texture == nil and pm.StatusTexture.atlas == nil, "forever: player art and glow restored after Blizzard's art swap")

    -- party frames
    local pm = w.ns.modules.party
    local m1 = PartyFrame.MemberFrame1
    local pown = pm.own[m1]
    check(pm.mode == "restyled" and pown and pown.art and pown.art.texture == "Interface\\TargetingFrame\\UI-PartyFrame" and pown.art.width == 128 and pown.art.height == 64 and pown.art.anchors[1][5] == -2, "forever: classic party art on the overlay, 128x64 at 0,-2")
    check(m1.Texture.alpha == 0 and m1.PartyMemberOverlay.RoleIcon.alpha == 0 and m1.Flash.texture == "Interface\\TargetingFrame\\UI-PartyFrame-Flash", "forever: retail party atlas and role icon faded, classic flash")
    local hc1 = m1.HealthBarContainer
    check(hc1.width == 70 and hc1.height == 8 and hc1.anchors[1][4] == 47 and hc1.anchors[1][5] == -12 and hc1.HealthBar.barTexture == "Interface\\TargetingFrame\\UI-StatusBar" and hc1.HealthBarMask.texture == "Interface\\Buttons\\WHITE8x8", "forever: party health bar 70x8 at 47,-12, classic fill, mask neutralised")
    check(m1.ManaBar.width == 70 and m1.ManaBar.anchors[1][5] == -21 and m1.Name.anchors[1][1] == "BOTTOMLEFT" and m1.Name.anchors[1][4] == 50 and m1.Name.anchors[1][5] == 43 and m1.Portrait.width == 37 and m1.width == 128, "forever: party mana bar, name and portrait at Era's spots, frame 128 wide")
    local pet1 = m1.PetFrame
    check(pet1.Texture.texture == "Interface\\TargetingFrame\\UI-PartyFrame" and pet1.Texture.scale == 1 and pet1.Texture.width == 64 and pet1.HealthBar.width == 35 and pet1.HealthBar.height == 4 and pet1.HealthBar.anchors[1][4] == 23 and pet1.height == 26, "forever: party pet frame classic art, 35x4 bar, 64x26")
    m1:UpdateArt()
    check(m1.Texture.alpha == 0 and hc1.anchors[1][4] == 47 and hc1.anchors[1][5] == -12 and hc1.HealthBarMask.texture == "Interface\\Buttons\\WHITE8x8", "forever: party frame re-skinned after Blizzard's art refresh")
    w.inCombat = true
    m1:UpdateArt()
    check(m1.Texture.alpha == 0 and hc1.anchors[1][4] == 45 and pm.pending == true, "forever: in combat only party textures change, anchors wait")
    w.inCombat = false
    pm.waiter:Fire("PLAYER_REGEN_ENABLED")
    check(hc1.anchors[1][4] == 47 and pm.pending == nil, "forever: party anchors applied once combat ends")

    -- action bars: Era's bottom bar
    local ab = w.ns.modules.actionbars
    local art = ab.art
    check(ab.mode == "restyled" and art ~= nil and art.width == 1024 and art.height == 53 and art.anchors[1][1] == "BOTTOM", "forever: 1024x53 stone bar at the bottom of the screen")
    check(art.strips[1].texcoord[3] == 0.83203125 and art.strips[1].anchors[1][4] == -384 and art.strips[4].texcoord[3] == 0.08203125 and art.strips[4].anchors[1][4] == 384, "forever: the four Dwarf strips in Era's order")
    check(art.leftCap and art.leftCap.texture == "Interface\\MainMenuBar\\UI-MainMenuBar-EndCap-Dwarf" and art.rightCap.anchors[1][4] == 544 and art.rightCap.texcoord[1] == 1 and MainActionBar.EndCaps.alpha == 0, "forever: classic gryphons on the art, Forever's faded")
    check(MainActionBar.BorderArt.shown == false, "forever: retail bar border hidden")
    check(MainActionBar.anchors[1][1] == "BOTTOMLEFT" and MainActionBar.anchors[1][2] == art and MainActionBar.anchors[1][4] == 8 and MainActionBar.anchors[1][5] == 4 and MainActionBar.width == 498 and MainActionBar.height == 36, "forever: main bar 498x36 at 8,4 on the art")
    local c2 = ActionButton2.container
    check(math.abs(c2.scale - 0.8) < 0.001 and c2.anchors[1][1] == "BOTTOMLEFT" and math.abs(c2.anchors[1][4] - 42 / 0.8) < 0.001, "forever: button containers scaled to 36px, 42 apart")
    check(ActionButton1.NormalTexture.texture == "Interface\\Buttons\\UI-Quickslot2" and ActionButton1.NormalTexture.alpha == 0.5 and ActionButton1.NormalTexture.width == 50 and ActionButton1.SlotArt.alpha == 0 and ActionButton1.icon.maskRemoved == ActionButton1.IconMask, "forever: classic quickslot ring, retail slot art and icon mask gone")
    check(ActionButton1.PushedTexture.texture == "Interface\\Buttons\\UI-Quickslot-Depress" and ActionButton1.HighlightTexture.texture == "Interface\\Buttons\\ButtonHilight-Square" and ActionButton1.CheckedTexture.texture == "Interface\\Buttons\\CheckButtonHilight", "forever: classic pushed, highlight and checked textures")
    ActionButton1:UpdateButtonArt()
    check(ActionButton1.NormalTexture.texture == "Interface\\Buttons\\UI-Quickslot2" and ActionButton1.SlotArt.alpha == 0, "forever: button re-skinned after Blizzard's art refresh")
    MainActionBar:UpdateGridLayout()
    check(math.abs(c2.scale - 0.8) < 0.001 and math.abs(c2.anchors[1][4] - 42 / 0.8) < 0.001 and MainActionBar.width == 498, "forever: containers re-laid out after Blizzard's grid layout")
    local pn = MainActionBar.ActionBarPageNumber
    check(pn.anchors[1][2] == art and pn.anchors[1][4] == 506 and pn.anchors[1][5] == 3 and pn.Text.anchors[1][4] == 15 and pn.UpButton.NormalTexture.texture == "Interface\\MainMenuBar\\UI-MainMenu-ScrollUpButton-Up" and pn.UpButton.anchors[1][5] == 10, "forever: page number and classic arrows right of the buttons")
    -- the buttons sit at Era's 552 on the art; the container is placed to
    -- suit Blizzard's arithmetic, not to be looked at
    check(MicroMenu.anchors[1][2] == art and MicroMenu.anchors[1][4] == 552 and MicroMenu.anchors[1][5] == 2 and MicroMenu.BorderArt.alpha == 0, "forever: micro buttons on the bar's floor at 552, retail border gone")
    -- Forever sets MainActionBar.BOTTOMRIGHT = MicroMenuContainer.BOTTOMLEFT -4.5,-4.
    -- Put the container where that sum lands the bar on Era's 8,4 and the
    -- two layouts agree, so nothing has to move when combat forbids it.
    local cx, cy = MicroMenuContainer.anchors[1][4], MicroMenuContainer.anchors[1][5]
    check(MicroMenuContainer.anchors[1][2] == art and math.abs((cx - 4.5 - 498) - 8) < 0.001 and math.abs((cy - 4) - 4) < 0.001, "forever: the container sits where Blizzard's own sum puts the main bar exactly on Era's spot")
    check(CharacterMicroButton.width == 31 and CharacterMicroButton.NormalTexture.texture == "Interface\\Buttons\\UI-MicroButtonCharacter-Up" and CharacterMicroButton.NormalTexture.texcoord[3] == 0.359375 and CharacterMicroButton.Background.alpha == 0 and CharacterMicroButton.Portrait.width == 18, "forever: character micro button classic with the small portrait")
    check(SpellbookMicroButton.NormalTexture.texture == "Interface\\Buttons\\UI-MicroButton-Spellbook-Up" and SpellbookMicroButton.HighlightTexture.texture == "Interface\\Buttons\\UI-MicroButton-Hilight" and ab.microSkinned == 12, "forever: every micro button classic")
    check(AchievementMicroButton.anchors == nil or #AchievementMicroButton.anchors == 0, "forever: a micro button parked outside the menu is not pulled into the row")
    -- Forever fades a micro button's icon out under the mouse and cross-fades
    -- its own hover art in; with Era's glow in its place the icon just vanished
    LFDMicroButton.NormalTexture:SetAlpha(0)
    check(LFDMicroButton.NormalTexture.alpha == 1, "forever: the micro button icon is held visible when Forever fades it on hover")
    SpellbookMicroButton:SetSize(32, 40); SpellbookMicroButton.scripts.OnSizeChanged(SpellbookMicroButton)
    check(SpellbookMicroButton.width == 31 and SpellbookMicroButton.height == 37, "forever: micro button re-skinned when Blizzard's layout resizes it")
    -- room left of the bag cluster: 1024-6-261-4-552 = 201; ten buttons at
    -- Era's 26 need 265, so they pack to (201-31)/9 = 18.89 apart and stay
    -- full size - above the 16 floor, so nothing is scaled down
    local packed = (201 - 31) / 9
    check(StoreMicroButton.shown == false and ab.microShown == 10 and ProfessionMicroButton.anchors[1][2] == MicroMenu and math.abs(ProfessionMicroButton.anchors[1][4] - packed) < 0.001 and math.abs(MainMenuMicroButton.anchors[1][4] - 9 * packed) < 0.001, "forever: disabled Store button hidden, the ten others packed to fit the room")
    check(math.abs(MicroMenu.width - 201) < 0.01 and MicroMenu.height == 37 and MicroMenu.scale == 1 and MicroMenuContainer.height == 37, "forever: the row fills the room at Era's full height rather than being scaled down")
    -- the container is widened leftwards, so its right edge is still where
    -- the row really ends and the bag bar hangs off the same place as before
    check(math.abs((MicroMenuContainer.anchors[1][4] + MicroMenuContainer.width) - (552 + 201)) < 0.01, "forever: the container still ends where the micro row ends, so the bags are no worse off")
    check(CharacterMicroButton.level > ProfessionMicroButton.level and ProfessionMicroButton.level > MainMenuMicroButton.level, "forever: packed buttons stack left over right, so only trailing edges go under")
    UpdateMicroButtons()
    check(StoreMicroButton.shown == false and ab.microShown == 10, "forever: Store hidden again after Blizzard's micro button refresh")
    MainMenuMicroButton:SetNormalAtlas("UI-HUD-MicroMenu-MainMenu-Up")
    check(MainMenuMicroButton.NormalTexture.texture == "Interface\\Buttons\\UI-MicroButton-MainMenu-Up", "forever: micro button re-skinned after Blizzard's atlas swap")
    CharacterMicroButton:SetPushed()
    check(CharacterMicroButton.PushedBackground.alpha == 0, "forever: pushed micro background stays hidden")
    check(BagsBar.anchors[1][1] == "BOTTOMRIGHT" and BagsBar.anchors[1][2] == art and BagsBar.anchors[1][4] == -6 and BagsBar.anchors[1][5] == 2, "forever: bag bar at the bar's right end")
    check(MainMenuBarBackpackButton.width == 37 and MainMenuBarBackpackButton.NormalTexture.texture == "Interface\\Buttons\\UI-Quickslot2" and MainMenuBarBackpackButton.NormalTexture.width == 64 and CharacterBag0Slot.anchors[1][2] == MainMenuBarBackpackButton and CharacterBag0Slot.anchors[1][4] == -5, "forever: 37px bag slots 5 apart with the quickslot ring")
    check(MainMenuBarBackpackButton.icon.maskRemoved == MainMenuBarBackpackButton.SquareMask and BagsBar.BorderArt.alpha == 0 and BagsBar.div1.alpha == 0, "forever: retail icon mask, bag border and slot dividers gone")
    local reagent, keyring = CharacterReagentBag0Slot, KeyRingButton
    check(reagent.width == 30 and reagent.anchors[1][2] == CharacterBag3Slot and reagent.anchors[1][4] == -4 and reagent.NormalTexture.texture == "Interface\\Buttons\\UI-Quickslot2" and reagent.NormalTexture.width == 52, "forever: reagent bag 30px beside the bags with a smaller ring")
    check(keyring.width == 18 and keyring.height == 39 and keyring.NormalTexture.texture == "Interface\\Buttons\\UI-Button-KeyRing" and keyring.NormalTexture.texcoord[2] == 0.5625 and keyring.NormalTexture.texcoord[4] == 0.609375 and keyring.anchors[1][2] == reagent and keyring.icon.alpha == 0, "forever: Era's 18x39 keyring left of the reagent bag, retail slot art faded")
    check(BagsBar.width == 261 and ab.bagsWidth == 261, "forever: bag cluster 261 wide (five bags, reagent bag, keyring)")
    BagsBar:Layout()
    check(CharacterBag0Slot.anchors[1][4] == -5 and CharacterBag0Slot.width == 37 and BagsBar.div1.alpha == 0, "forever: bag slots re-laid out after Blizzard's layout, dividers faded again")
    CharacterBag1Slot:SetSize(45, 45); CharacterBag1Slot.scripts.OnSizeChanged(CharacterBag1Slot)
    keyring:SetSize(33, 45); keyring.scripts.OnSizeChanged(keyring)
    check(CharacterBag1Slot.width == 37 and CharacterBag1Slot.NormalTexture.texture == "Interface\\Buttons\\UI-Quickslot2" and keyring.width == 18, "forever: bag slot and keyring re-skinned when Blizzard resizes them")
    BagsBar.div1.alpha = 1; BagsBar.div1.scripts.OnShow(BagsBar.div1)
    check(BagsBar.div1.alpha == 0, "forever: a bag divider shown again by its pool is faded on show")
    local xpc = MainStatusTrackingBarContainer
    local xp = xpc.bars[1]
    check(xpc.anchors[1][1] == "TOP" and xpc.anchors[1][2] == art and xpc.width == 1024 and xpc.height == 13 and xpc.BarFrameTexture.alpha == 0 and xpc.div1.alpha == 0, "forever: experience bar 1024x13 in the top of the stone bar, retail frame and segment dividers gone")
    xpc.div1.alpha = 1; xpc.div1.scripts.OnShow(xpc.div1)
    check(xpc.div1.alpha == 0, "forever: an XP divider shown again by its pool is faded on show")
    check(xp.StatusBar.barTexture == "Interface\\TargetingFrame\\UI-StatusBar" and xp.StatusBar.anchors[1][1] == "ALL" and xp.ExhaustionTick.NormalTexture.texture == "Interface\\MainMenuBar\\UI-ExhaustionTickNormal" and xp.ExhaustionTick.width == 32, "forever: classic XP fill and rest tick")
    xp:UpdateStatusBarTextures(true)
    check(xp.StatusBar.barTexture == "Interface\\TargetingFrame\\UI-StatusBar" and xp.StatusBar.barColor[2] == 0.39, "forever: rested XP colour after Blizzard's fill swap")
    local ledge = ab.own[xpc].ledge
    check(ledge and ledge.tiles[1].texcoord[3] == 0.79296875 and ledge.tiles[4].anchors[1][4] == 768 and ledge.parent == xpc, "forever: stone ledge over the XP bar, on the container")
    check(MultiBarBottomLeft.anchors[1][1] == "BOTTOMRIGHT" and MultiBarBottomLeft.anchors[1][4] == -6 and MultiBarBottomLeft.anchors[1][5] == 52 and MultiBarBottomRight.anchors[1][4] == 6, "forever: bottom bars either side of the screen centre")
    check(MultiBarRight.width == 36 and MultiBarRight.height == 498 and math.abs(MultiBarRightButton2.container.anchors[1][5] + 42 / 0.8) < 0.001, "forever: right bar vertical, 42 apart")
    -- Blizzard's layout apply in combat: containers and art at once, bar anchors wait
    w.inCombat = true
    EditModeManagerFrame:UpdateBottomActionBarPositions()
    check(MainActionBar.anchors[1][2] == MicroMenuContainer and ab.pending == true and math.abs(c2.scale - 0.8) < 0.001, "forever: in combat Blizzard's bar anchor stands, layout pending")
    -- the two upper bars went to Blizzard's +22/+606: the secure handler puts them back on the next state tick
    check(MultiBarBottomLeft.anchors[1][2] == MainActionBar and MultiBarBottomLeft.anchors[1][4] == 22 and MultiBarBottomRight.anchors[1][4] == 606, "forever: Blizzard's combat layout moved the bottom bars to its own offsets")
    local holder = ab.holder
    check(holder ~= nil and holder.template == "SecureHandlerStateTemplate" and holder.drivers.cuicombat == "[combat] 1; 0" and holder.drivers.cuipet == "[pet] 1; 0" and holder.drivers.cuiform ~= nil and holder.drivers.cuivehicle ~= nil, "forever: a secure handler with state drivers for combat, pet, form and vehicle")
    check(holder.refs["cui-bl"] == MultiBarBottomLeft and holder.refs["cui-br"] == MultiBarBottomRight and holder:GetAttribute("cui-bl") == true and holder:GetAttribute("cui-lift") == 52 and holder:GetAttribute("cui-gap") == 6, "forever: the handler was handed the bars, the lift and the gap out of combat")
    check(w.FireState(holder, "cuicombat", 1), "forever: entering combat runs the handler's snippet")
    check(MultiBarBottomLeft.anchors[1][1] == "BOTTOMRIGHT" and MultiBarBottomLeft.anchors[1][2] == UIParent and MultiBarBottomLeft.anchors[1][3] == "BOTTOM" and MultiBarBottomLeft.anchors[1][4] == -6 and MultiBarBottomLeft.anchors[1][5] == 52, "forever: the snippet puts the bottom-left bar back either side of centre, in combat")
    check(MultiBarBottomRight.anchors[1][1] == "BOTTOMLEFT" and MultiBarBottomRight.anchors[1][2] == UIParent and MultiBarBottomRight.anchors[1][4] == 6 and MultiBarBottomRight.anchors[1][5] == 52, "forever: and the bottom-right bar")
    EditModeManagerFrame:UpdateBottomActionBarPositions()
    w.FireState(holder, "cuipet", 0)
    check(MultiBarBottomLeft.anchors[1][4] == -6 and MultiBarBottomRight.anchors[1][4] == 6, "forever: the pet dying mid-fight moves them again, the pet state tick puts them back")
    check(ab:Status():find("secure handler holds the bottom bars", 1, true) ~= nil, "forever: the status says so")
    -- and standing is now fine: Blizzard's own anchor puts it on Era's spot
    local bx = MicroMenuContainer.anchors[1][4] + MainActionBar.anchors[1][4] - 498
    local by = MicroMenuContainer.anchors[1][5] + MainActionBar.anchors[1][5]
    check(math.abs(bx - 8) < 0.001 and math.abs(by - 4) < 0.001, "forever: Blizzard's in-combat anchor lands the bar on Era's 8,4 - the mid-fight jump is gone")
    -- nobody can type a command mid-fight, so where Blizzard put the bars
    -- is written down and carried in the report instead
    check(ab.combatAnchors ~= nil and ab.combatAnchors.MainActionBar == "BOTTOMRIGHT>MicroMenuContainer.BOTTOMLEFT -4.5,-4.0" and ab.combatAnchors.MultiBarBottomLeft ~= nil, "forever: the anchor Blizzard moved the bars to in combat is recorded")
    check(ab:Status():find("moved in combat to", 1, true) and ab:Status():find("MicroMenuContainer", 1, true), "forever: and it goes into the report through the status line")
    w.slash("probe")
    check(w.ns.lastProbe:find("moved in combat to", 1, true) and w.ns.lastProbe:find("MicroMenuContainer.BOTTOMLEFT", 1, true), "forever: the report itself carries it, so it can be read off a report taken after the fight")
    -- the micro buttons are protected too: moving, sizing or re-levelling
    -- one in combat is refused and prints "Interface action failed"
    local anchorsBefore = #CharacterMicroButton.anchors
    local xBefore, levelBefore = CharacterMicroButton.anchors[1][4], CharacterMicroButton.level
    CharacterMicroButton:SetSize(99, 99)
    MicroMenuContainer:ClearAllPoints()
    ab.Layout()
    check(CharacterMicroButton.width == 99 and #MicroMenuContainer.anchors == 0, "forever: in combat the micro row is left alone, not resized or re-anchored")
    CharacterMicroButton.scripts.OnEnter(CharacterMicroButton)
    check(CharacterMicroButton.width == 99 and ab.pending == true, "forever: hovering a micro button in combat does not resize it either")
    w.inCombat = false
    ab.Layout()
    check(CharacterMicroButton.width == 31 and math.abs(CharacterMicroButton.anchors[1][4] - xBefore) < 0.001 and #MicroMenuContainer.anchors > 0, "forever: the micro row is put back the moment combat ends")
    w.inCombat = false
    ab.waiter:Fire("PLAYER_REGEN_ENABLED")
    check(MainActionBar.anchors[1][2] == art and ab.pending == nil and MultiBarBottomLeft.anchors[1][1] == "BOTTOMRIGHT", "forever: bar anchors back on the art once combat ends")
    -- a bar the player moved in Edit Mode is nobody's to place: not ours, not the handler's
    MultiBarBottomRight.moved = true
    MultiBarBottomRight:ClearAllPoints(); MultiBarBottomRight:SetPoint("CENTER", UIParent, "CENTER", 100, 100)
    ab.Layout()
    check(MultiBarBottomRight.anchors[1][1] == "CENTER" and holder:GetAttribute("cui-br") == false and holder:GetAttribute("cui-bl") == true, "forever: a bar moved in Edit Mode keeps its place, and the handler is told to leave it")
    w.FireState(holder, "cuicombat", 1)
    check(MultiBarBottomRight.anchors[1][1] == "CENTER" and MultiBarBottomRight.anchors[1][4] == 100, "forever: the snippet leaves a moved bar where the player put it")
    MultiBarBottomRight.moved = nil
    ab.Layout()
    check(MultiBarBottomRight.anchors[1][4] == 6 and holder:GetAttribute("cui-br") == true, "forever: back in its default position, it is placed again")
    local divs = MainActionBar.HorizontalDividersPool.active
    check(divs[1].alpha == 0 and divs[2].alpha == 0, "forever: retail button dividers faded out")
    MainActionBar:UpdateDividers()
    check(MainActionBar.HorizontalDividersPool.active[1].alpha == 0, "forever: dividers faded again after Blizzard's refresh")
    local tr = w.ns.modules.tracker
    check(tr.mode == "restyled" and ObjectiveTrackerFrame.Header.Background.alpha == 0 and ObjectiveTrackerFrame.modules[1].Header.Background.alpha == 0, "forever: tracker header boxes faded out")
    ObjectiveTrackerFrame:Update()
    check(ObjectiveTrackerFrame.Header.Background.alpha == 0 and ObjectiveTrackerFrame.modules[1].Header.Background.alpha == 0, "forever: tracker header boxes faded again after Blizzard's update")
    w.slash("tracker off")
    check(tr.mode == "off" and ObjectiveTrackerFrame.Header.Background.alpha == 1, "forever: tracker off restores the boxes")
    w.slash("tracker on")
    check(w.ns.modules.minimap.mode == "restyled" and Minimap.width == 140 and MinimapCompassTexture.texture == "Interface\\Minimap\\UI-Minimap-Border", "forever: minimap 140px with the classic ring")
    check(w.ns.modules.minimap.header ~= nil and MinimapCluster.DielFrame.shown == false, "forever: classic header strip added, day/night dial hidden")

    -- options panel
    local panel = w.ns.optionsPanel
    check(panel ~= nil and panel.checks.unitframes ~= nil and panel.checks.minimap ~= nil, "forever: options panel lists every part")
    -- a held-back part (none right now) is left out of both buttons
    local function Every(value)
        for _, key in ipairs(w.ns.moduleOrder) do
            if not w.ns.IsComingSoon(key) and w.ns.db[key] ~= value then return false end
        end
        return true
    end
    panel.deselectAll:Click()
    check(Every(false) and w.ns.modules.unitframes.mode == "off" and panel.checks.minimap.checked == false, "forever: Deselect all switches every part off and unticks the boxes")
    panel.selectAll:Click()
    check(Every(true) and w.ns.modules.unitframes.mode == "restyled" and panel.checks.minimap.checked == true and panel.checks.questlog.checked == true, "forever: Select all switches every part back on")
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
    check(not dump:find("FrameTexture", 1, true) and dump:find("art  Texture", 1, true) and dump:find("UI-TargetingFrame", 1, true), "beta: dump shows the classic frame texture on the skin (Blizzard's hidden one skipped)")
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
    -- /cui report: probe + every frame + Lua errors in one window
    w.errorHandler("Interface/AddOns/Blizzard_NamePlates/x.lua:1: attempt to compare a secret number value")
    w.errorHandler("Interface/AddOns/Blizzard_NamePlates/x.lua:1: attempt to compare a secret number value")
    w.errorHandler("something else broke")
    check(#w.blizzErrors == 3 and #w.ns.luaErrors == 2 and w.ns.luaErrors[1].count == 2, "beta: Lua errors logged (repeats folded) and passed on to Blizzard's handler")
    w.plateByToken = {target = plate}
    w.slash("report")
    local rep = w.ns.lastReport
    check(rep and rep:find("probe", 1, true) and rep:find("dump of PlayerFrame", 1, true) and rep:find("dump of TargetFrame", 1, true) and rep:find("dump of NamePlate7 (target)", 1, true), "beta: report bundles the probe and the frame dumps")
    check(rep:find("dump of MinimapCluster", 1, true) and rep:find("dump of ObjectiveTrackerFrame", 1, true), "beta: report covers every frame it should")
    check(rep:find("x2 Interface/AddOns/Blizzard_NamePlates/x.lua:1", 1, true) and rep:find("stack line 1", 1, true) and rep:find("something else broke", 1, true), "beta: report includes the Lua error log with stacks")
    check(rep:find("coord=0.1016,1.0000,0.0078,0.781", 1, true) and rep:find("font=FRIZQT__.TTF/12", 1, true) and rep:find("lvl=MEDIUM/", 1, true), "beta: dumps carry texture crops, fonts and frame levels")
    check(rep:find("(hidden)", 1, true) == nil, "beta: plain report lists visible pieces only")
    w.slash("report all")
    check(w.ns.lastReport:find("all parts, hidden ones marked", 1, true) and w.ns.lastReport:find("LevelBackgroundCircle  Texture", 1, true) and w.ns.lastReport:find("(hidden)", 1, true), "beta: report all includes hidden pieces, marked")
    w.slash("dump TargetFrame all")
    check(w.ns.lastDump:find("(hidden)", 1, true), "beta: dump <frame> all includes hidden pieces")
    -- secret values: sizes and texts that cannot be read are marked, not fatal
    local secretRegion = TargetFrame.TargetFrameContent.TargetFrameContentMain.Name
    function secretRegion:GetSize() error("attempt to perform arithmetic on a secret value") end
    function secretRegion:GetText() return {__secret = true} end
    w.slash("dump TargetFrame")
    check(w.ns.lastDump:find("Name  FontString  <secret>", 1, true) and not Printed("dump hit an error"), "beta: dump survives secret values")
    -- a secret boolean does not test false, it throws, so reading a shown
    -- state can blow up where nothing else does: one unguarded
    -- `if f:IsShown()` took a whole live report down. Plain Lua has no
    -- way to make a value throw on a truth test, so the throw is put in
    -- IsShown itself, which fails in the same place for the same reason.
    function secretRegion:IsShown() error("attempt to perform boolean test on a secret boolean value") end
    function TargetFrame:IsShown() error("attempt to perform boolean test on a secret boolean value") end
    w.slash("dump TargetFrame")
    check(w.ns.lastDump:find("TargetFrame", 1, true) and w.ns.lastDump:find("Name  FontString", 1, true) and not Printed("dump hit an error"), "beta: a frame whose shown state is secret is still listed, not dropped and not fatal")
    w.slash("report")
    check(w.ns.lastReport ~= nil and w.ns.lastReport:find("Classic UI for Forever bug report", 1, true) and not Printed("report hit an error"), "beta: the whole report survives a secret shown state")
    secretRegion.IsShown, TargetFrame.IsShown = nil, nil
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
-- 3d. Forever character sheet: Era layout on the Character tab, Blizzard's
--     layout on the other tabs, everything undone by "off"
--------------------------------------------------------------------------
do
    local w = NewWorld({style = "6", forever = true})
    local cs = w.ns.modules.charsheet
    local cf = CharacterFrame
    check(cs.mode == "restyled", "sheet: re-skinned on Forever")
    check(cf.width == 384 and cf.height == 512, "sheet: frame is Era's 384x512 while the paper doll shows")
    -- UIParent's panel width is Blizzard's to set: set from the addon it taints the panel and the
    -- frame cannot be shown in combat ("Interface action failed because of an AddOn")
    check(w.panelWidth ~= 400, "sheet: UIParent's panel width left to Blizzard (an addon-set width taints the panel out of combat use)")
    check(cf.NineSlice.alpha == 0 and cf.LeftPaneHost.alpha == 0 and cf.RightPaneHost.alpha == 0, "sheet: retail shell faded")
    check(cf.RightPaneToggleButton.alpha == 0 and cf.RightPaneToggleButton.mouse == false and cf.CloseButton.alpha == 0 and cf.CloseButton.mouse == false, "sheet: collapse and close buttons faded and unclickable")
    check(cf.ModeTabs.alpha == 0 and cf.ModeTabs.Tabs[1].mouse == false and cf.ModeTabs.Tabs[6].mouse == false, "sheet: side tabs faded and unclickable")
    local sheet = cs.sheet
    check(sheet.shown == true and sheet.art[1].texture == "Interface\\PaperDollInfoFrame\\UI-Character-CharacterTab-L1" and sheet.art[4].anchors[1][4] == 256 and sheet.art[4].anchors[1][5] == -256, "sheet: four-piece Era art in place")
    check(sheet.close.NormalTexture.texture == "Interface\\Buttons\\UI-Panel-MinimizeButton-Up" and sheet.close.anchors[1][2] == cf and sheet.close.anchors[1][4] == -44, "sheet: classic close button in the corner")
    check(sheet.levelText.text == "Level 39 Human Priest" and sheet.guildText.text == "Member of Guild Name", "sheet: level and guild lines")
    local p = cf.PortraitContainer.portrait
    check(p.anchors[1][1] == "TOPLEFT" and p.anchors[1][2] == cf and p.anchors[1][4] == 7 and p.anchors[1][5] == -6 and p.width == 60, "sheet: portrait in Era's corner")
    check(cf.TitleContainer.anchors[1][1] == "TOP" and cf.TitleContainer.anchors[1][4] == 7 and cf.TitleContainer.anchors[1][5] == -14 and cf.TitleContainer.width == 300, "sheet: name centred at the top")
    local head, wrist, hands = CharacterHeadSlot.anchors[1], CharacterWristSlot.anchors[1], CharacterHandsSlot.anchors[1]
    check(head[2] == PaperDollFrame and head[4] == 21 and head[5] == -74 and wrist[5] == -74 - 7 * 41 and hands[4] == 306 and hands[5] == -74, "sheet: slot columns at Era's positions")
    local main, ammo = CharacterMainHandSlot.anchors[1], CharacterAmmoSlot.anchors[1]
    check(main[1] == "TOPLEFT" and main[3] == "BOTTOMLEFT" and main[4] == 122 and main[5] == 127 and CharacterSecondaryHandSlot.anchors[1][2] == CharacterMainHandSlot and ammo[2] == CharacterRangedSlot and ammo[4] == 15, "sheet: weapon row along the bottom")
    check(CharacterHeadSlot.BorderFrame.alpha == 0 and CharacterAmmoSlot.gearSlotSmall.alpha == 0 and CharacterAmmoSlot.arrowHolder.alpha == 0, "sheet: retail slot rings and ammo arrow faded")
    check(sheet.ammoUnder ~= nil and sheet.ammoUnder.level == 100 and sheet.ammoOver.level == 102, "sheet: classic ammo plate under the slot, bracket over it")
    local m = CharacterModelScene
    check(m.anchors[1][2] == PaperDollFrame and m.anchors[1][4] == 65 and m.anchors[1][5] == -78 and m.width == 233 and m.height == 224 and m.BackgroundTopLeft.alpha == 0 and m.BackgroundOverlay.alpha == 0, "sheet: model in Era's window, race backdrop faded")
    check(CharacterStatsPaneScrollBox.shown == false and CharacterStatsPaneScrollBox.alpha == 0 and PaperDollSidebarTabs.alpha == 0 and PaperDollLevelInfo.alpha == 0, "sheet: retail stats list, sidebar tabs and level banner gone")
    local rows = sheet.rows
    check(rows.STRENGTH.Value.text == "|cff20ff2026|r" and rows.STRENGTH.tooltip:find("26", 1, true) and rows.STRENGTH.tooltip:find("+5", 1, true), "sheet: buffed stat shown green with the formula in the tooltip")
    check(rows.ARMOR.Value.text == "|cff20ff20350|r" and rows.ARMOR.tooltip2:find("12.50", 1, true), "sheet: armor with the reduction line")
    -- Forever hands unit numbers back as secret values once addon code has
    -- tainted the call: arithmetic on one is fatal, so the row is left alone
    local savedStat, savedArmor = _G.UnitStat, _G.UnitArmor
    local secret = setmetatable({__secret = true}, {__index = function() error("secret value used") end})
    _G.UnitStat = function(unit, i) return 20 + i, secret, 5, 0 end
    _G.UnitArmor = function() return secret, secret, 0, 0, 0 end
    local beforeErrors = #w.ns.errors
    sheet.scripts.OnEvent(sheet, "UNIT_STATS", "player")
    check(#w.ns.errors == beforeErrors and rows.STRENGTH.Value.text == "|cff20ff2026|r" and rows.ARMOR.Value.text == "|cff20ff20350|r", "sheet: a secret stat leaves the row as it was instead of erroring")
    check(w.ns.charsheet.secretReads >= 2, "sheet: secret reads counted for the report")
    -- Forever's own unit calls return fewer values than Era's did: the
    -- missing ones read as zero instead of blowing up the row
    _G.UnitStat = function(unit, i) return 20 + i, 25 + i end
    _G.UnitArmor = function() return 300, 350, 300, 50 end
    sheet.scripts.OnEvent(sheet, "UNIT_STATS", "player")
    check(#w.ns.errors == beforeErrors and rows.STRENGTH.Value.text == "26" and rows.ARMOR.Value.text == "|cff20ff20350|r", "sheet: a short unit return fills the missing numbers with zero")
    _G.UnitStat, _G.UnitArmor = savedStat, savedArmor
    sheet.scripts.OnEvent(sheet, "UNIT_STATS", "player")
    check(rows.STRENGTH.Value.text == "|cff20ff2026|r" and #w.ns.errors == beforeErrors, "sheet: plain numbers fill the rows again")
    check(rows.ATTACK.Value.text == 195 and rows.ATTACK_POWER.Value.text == "|cffff2020115|r", "sheet: weapon skill and attack power (debuffed: red)")
    -- Forever has no UnitAttackBothHands: the weapon skill comes off the skills list for the equipped weapon
    local savedBothHands = _G.UnitAttackBothHands
    _G.UnitAttackBothHands = nil
    _G.GetInventoryItemID = function(unit, slot) if slot == 16 then return 2092 end end
    _G.C_Item = {GetItemInfoInstant = function(id) return id, "Weapon", "Daggers", "INVTYPE_WEAPON", 135641, 2, 15 end}
    sheet.scripts.OnEvent(sheet, "SKILL_LINES_CHANGED")
    check(rows.ATTACK.Value.text == 1 and rows.ATTACK.tooltip == "Weapon Skill", "sheet: without UnitAttackBothHands the dagger skill rank comes from C_SkillInfo")
    _G.GetInventoryItemID = function() return nil end
    w.skills[#w.skills + 1] = {skillID = 162, name = "Unarmed", parentSkillLineID = 0, skillLineCategoryID = 9, rank = 12, maxRank = 195, modifier = 2, tempPoints = 0}
    sheet.scripts.OnEvent(sheet, "SKILL_LINES_CHANGED")
    check(rows.ATTACK.Value.text == "|cff20ff2014|r", "sheet: no weapon -> Unarmed, modifier shown green")
    table.remove(w.skills)
    _G.UnitAttackBothHands = savedBothHands
    _G.GetInventoryItemID = nil; _G.C_Item = nil
    sheet.scripts.OnEvent(sheet, "SKILL_LINES_CHANGED")
    check(rows.DAMAGE.Value.text == "40 - 60" and rows.DAMAGE.dps == 20 and rows.DAMAGE.attackSpeed == 2.5, "sheet: melee damage and dps")
    check(rows.RANGED_ATTACK.Value.text == "N/A" and rows.RANGED_DAMAGE.Value.text == "N/A", "sheet: no ranged weapon -> N/A")
    w.rangedTexture = 12345
    sheet.scripts.OnEvent(sheet, "PLAYER_EQUIPMENT_CHANGED")
    check(rows.RANGED_ATTACK.Value.text == 150 and rows.RANGED_DAMAGE.Value.text == "30 - 50" and rows.RANGED_DAMAGE.dps == 20, "sheet: ranged lines fill in once a weapon is equipped")
    local res = sheet.resistances
    check(res[1].id == 6 and res[1].Value.text == 0 and res[2].Value.text == "|cff20ff2015|r" and res[5].Value.text == "|cffff2020-3|r", "sheet: resistance column, coloured like Era")
    check(res[2].tooltip:find("Fire", 1, true) or res[2].tooltip:find("FIRE", 1, true), "sheet: resistance tooltip names the school")
    rows.DAMAGE.scripts.OnEnter(rows.DAMAGE)
    check(GameTooltip.lines[1] == "Main Hand" and GameTooltip.lines[3] == "Damage: 40 - 60", "sheet: damage tooltip like Era's")
    -- bottom tabs
    local tabs = cs.tabs
    check(tabs.shown == true and #tabs.list == 6 and tabs.list[1].shown and tabs.list[5].shown, "sheet: six text tabs along the bottom (Forever has currency and statistics too)")
    local t1, t2 = tabs.list[1], tabs.list[2]
    check(t1.anchors[1][1] == "CENTER" and t1.anchors[1][2] == cf and t1.anchors[1][3] == "BOTTOMLEFT" and t1.anchors[1][4] == 60 and t1.anchors[1][5] == 62, "sheet: first tab at Era's spot")
    check(t2.anchors[1][1] == "LEFT" and t2.anchors[1][2] == t1 and t2.anchors[1][4] == -16, "sheet: tabs overlap by 16 like Era")
    check(t1.selected == true and t1.Left.texture == "Interface\\PaperDollInfoFrame\\UI-Character-InActiveTab" and t1.Left.anchors[1][5] == 0 and t1.Text.anchors[1][5] == 2 and t1.Text.textColor[1] == 1 and t1.Text.textColor[2] == 1 and t1.enabled == false, "sheet: selected tab keeps the tab art in place, white text, button disabled")
    check(t2.selected == false and t2.Left.texture == "Interface\\PaperDollInfoFrame\\UI-Character-InActiveTab" and t2.Text.textColor[2] == 0.82 and t2.enabled ~= false, "sheet: other tabs gold text, clickable")
    check(tabs.padding == 22 and t1.width == 54 + 22, "sheet: six tabs would not fit at Era's padding, so it is tightened")
    w.currencyTab = false
    cs:Force()
    check(tabs.list[5].shown == false and tabs.padding == 32, "sheet: currency tab only when Forever would show it, padding relaxed")
    -- currency tab: Era-style list inside the classic sheet
    w.currencyTab = true
    cs:Force()
    local t5 = tabs.list[5]
    t5.scripts.OnClick(t5)
    local cur = cs.panels[4]
    check(w.toggled == "TokenFrame" and TokenFrame.shown == true and PaperDollFrame.shown == false and cur.frameName == "TokenFrame" and cur.built == true, "currency: tab click opens the currency frame, panel built")
    check(cf.width == 384 and sheet.shown == true and sheet.doll.shown == false and sheet.art[1].texture == "Interface\\PaperDollInfoFrame\\UI-Character-General-TopLeft" and t5.selected == true and t1.selected == false, "currency: classic sheet with the General art, currency tab active")
    check(TokenFrame.ScrollBox.shown == false and TokenFrame.ScrollBar.shown == false and TokenFrame.Background.alpha == 0 and cur.list.shown == true and cur.list.parent == TokenFrame and cur.list.LeftLabel.text == "Currency", "currency: Blizzard's list and art hidden, ours up with the column labels")
    local c1, c2, c3, c4 = cur.rows[1], cur.rows[2], cur.rows[3], cur.rows[4]
    check(c1.shown == false and c1.header.shown == true and c1.header.Text.text == "Miscellaneous" and c1.header.NormalTexture.texture == "Interface\\Buttons\\UI-MinusButton-Up", "currency: expanded header with the minus button")
    check(c2.shown == true and c2.Name.text == "Honor Points" and c2.Value.text == "120" and c2.Icon.texture == 1455894 and c2.Icon.shown == true and c2.Check.shown == true, "currency: entry with its amount, icon and the backpack check mark")
    check(c3.header.shown == true and c3.header.NormalTexture.texture == "Interface\\Buttons\\UI-PlusButton-Up" and c4.shown == false and c4.header.shown == false and cur.list.Empty.shown == false, "currency: collapsed header, nothing after it")
    check(c1.anchors[1][4] == 22 and c1.anchors[1][5] == -79 and c2.anchors[1][5] == -97 and cur.scroll.anchors[1][4] == -66 and cur.scroll.anchors[1][5] == -76, "currency: Era row positions and the classic scroll bar")
    c3.header.scripts.OnClick(c3.header)
    check(w.currencyExpanded[1][1] == 3 and w.currencyExpanded[1][2] == true and c3.header.collapsed == false, "currency: header click expands through C_CurrencyInfo")
    c2.scripts.OnClick(c2)
    check(w.currencyBackpack[1][1] == 2 and w.currencyBackpack[1][2] == false and c2.Check.shown == false, "currency: click stops showing the currency on the backpack, check mark goes")
    -- statistics tab
    local t6 = tabs.list[6]
    t6.scripts.OnClick(t6)
    local st = cs.panels[5]
    check(st.built == true and StatisticsFrame.shown == true and cur.list.shown == false and TokenFrame.ScrollBox.shown == true and cf.width == 384, "statistics: panel up, currency list gone and Blizzard's currency pieces back, classic size kept")
    check(StatisticsFrame.ScrollBox.shown == false and StatisticsFrame.DetailFrame.shown == false and st.list.shown == true and st.list.LeftLabel.text == "Statistics", "statistics: Blizzard's list and detail pane hidden, ours up")
    local s1, s2, s3 = st.rows[1], st.rows[2], st.rows[3]
    check(s1.header.shown == true and s1.header.Text.text == "Player vs Player" and s1.header.collapsed == true and s2.header.Text.text == "Dungeons & Raids" and s3.shown == false and s3.header.shown == false, "statistics: top categories collapsed, nothing else listed")
    s1.header.scripts.OnClick(s1.header)
    check(s1.header.collapsed == false and s2.shown == true and s2.Name.text == "Honorable kills" and s2.Value.text == "12" and s3.Name.text == "Deaths" and st.rows[4].header.Text.text == "Dungeons & Raids", "statistics: expanding a category lists its statistics with their values")
    st.rows[4].header.scripts.OnClick(st.rows[4].header)
    check(st.rows[5].header.shown == true and st.rows[5].header.Text.text == "Classic" and st.rows[5].header.anchors[1][4] == 15 and st.rows[6].shown == false, "statistics: child category indented under its parent, collapsed")
    st.rows[5].header.scripts.OnClick(st.rows[5].header)
    check(st.rows[6].shown == true and st.rows[6].Name.text == "Deadmines runs" and st.rows[6].Value.text == "--" and st.rows[6].Name.anchors[1][4] == 40, "statistics: the child category's statistics, indented")
    -- reputation tab: classic list inside the classic sheet
    t2.scripts.OnClick(t2)
    local rep = cs.panels[1]
    check(rep.frameName == "ReputationFrame" and rep.built == true and ReputationFrame.shown == true, "reputation: panel built and its Blizzard frame is the one shown")
    check(cf.width == 384 and sheet.shown == true and sheet.doll.shown == false and sheet.art[1].texture == "Interface\\PaperDollInfoFrame\\UI-Character-General-TopLeft" and sheet.art[1].anchors[1][4] == 2 and sheet.art[1].anchors[1][5] == -1, "reputation: classic sheet with the General art, paper doll pieces hidden")
    check(ReputationFrame.ScrollBox.shown == false and ReputationFrame.ScrollBar.shown == false and ReputationFrame.ReputationDetailFrame.shown == false and ReputationFrame.filterDropdown.shown == false, "reputation: Blizzard's scroll box and detail pane hidden")
    check(rep.list.shown == true and rep.list.parent == ReputationFrame and rep.list.FactionLabel.anchors[1][4] == 70 and rep.list.StandingLabel.anchors[1][4] == 215, "reputation: our list on the frame with Era's column labels")
    local b1, b2, b3, b4, b5 = rep.bars[1], rep.bars[2], rep.bars[3], rep.bars[4], rep.bars[5]
    check(b1.shown == false and b1.header.shown == true and b1.header.Text.text == "Alliance" and b1.header.NormalTexture.texture == "Interface\\Buttons\\UI-MinusButton-Up", "reputation: header row with the minus button")
    check(b1.anchors[1][4] == 150 and b1.anchors[1][5] == -86 and b2.anchors[1][5] == -86 - 23 and b1.header.anchors[1][2] == b1 and b1.header.anchors[1][4] == -125, "reputation: Era row positions")
    check(b2.shown == true and b2.Name.text == "Stormwind" and b2.Standing.text == "Honored" and b2.minmax[2] == 12000 and b2.value == 6000 and b2.barColor[2] == 0.6, "reputation: bar filled and coloured by standing")
    check(b2.Check.shown == true and b2.Name.width == 100 and b3.Check.shown == false, "reputation: watched faction gets the check mark")
    check(b3.minmax[2] == 1 and b3.value == 1 and b3.Standing.text == "Exalted", "reputation: exalted shows a full bar")
    check(b4.AtWar.shown == true and b2.AtWar.shown == false, "reputation: at-war swords on the faction at war")
    check(b5.header.shown == true and b5.header.NormalTexture.texture == "Interface\\Buttons\\UI-PlusButton-Up" and b5.header.collapsed == true, "reputation: collapsed header shows the plus button")
    check(b1.Left.texture == "Interface\\PaperDollInfoFrame\\UI-Character-Skills-BarBorder" and b1.Left.width == 74 and b1.Left.anchors[1][4] == -5 and math.abs(b1.Left.texcoord[2] - 74 / 281) < 0.0001 and b1.Right.anchors[1][1] == "RIGHT" and b1.Right.anchors[1][4] == 5 and math.abs(b1.Right.texcoord[1] - (1 - 74 / 281)) < 0.0001 and b1.barTexture == "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar", "reputation: bar boxed by the two ends of the skills bevel (Forever's reputation-bar file is retail's)")
    check(b1.Highlight1.texture == "Interface\\PaperDollInfoFrame\\UI-Character-Skills-BarBorderHighlight" and b1.Highlight1.blend == "ADD" and b1.width == 137, "reputation: highlight is the bevel's glow, bar still 137 wide")
    b2.scripts.OnEnter(b2)
    check(b2.Standing.text == "|cffffffff 6000 / 12000|r" and b2.Highlight1.shown == true, "reputation: hover shows the numbers and the highlight")
    b2.scripts.OnLeave(b2)
    check(b2.Standing.text == "Honored" and b2.Highlight1.shown == false, "reputation: leave puts the standing back")
    b5.header.scripts.OnClick(b5.header)
    check(w.expanded[1] == 5 and b5.header.collapsed == false, "reputation: header click expands through C_Reputation")
    b4.scripts.OnMouseUp(b4)
    check(w.selectedFaction == 4 and rep.detail.shown == true and rep.detail.Name.text == "Booty Bay" and rep.detail.Description.text == "Pirates." and b4.Highlight1.shown == true, "reputation: click selects the faction and opens the Era detail popup")
    check(rep.detail.AtWar.checked == true and rep.detail.AtWar.enabled == true and rep.detail.Inactive.checked == false and rep.detail.Watch.checked == false, "reputation: detail checkboxes reflect the faction")
    check(rep.detail.anchors[1][2] == ReputationFrame and rep.detail.anchors[1][3] == "TOPRIGHT" and rep.detail.anchors[1][4] == -33 and rep.detail.width == 212, "reputation: popup hangs off the frame's right edge like Era")
    rep.detail.AtWar.checked = false; rep.detail.AtWar.scripts.OnClick(rep.detail.AtWar)
    check(w.atWarToggled[1] == 4 and b4.AtWar.shown == false, "reputation: at-war box toggles through the API and the swords go")
    rep.detail.Watch.checked = true; rep.detail.Watch.scripts.OnClick(rep.detail.Watch)
    check(w.watched == 4, "reputation: show-as-experience box sets the watched faction")
    rep.detail.Inactive.checked = true; rep.detail.Inactive.scripts.OnClick(rep.detail.Inactive)
    check(w.factionActive[4] == false and rep.detail.Inactive.checked == true, "reputation: inactive box moves the faction")
    b4.scripts.OnMouseUp(b4)
    check(rep.detail.shown == false and w.selectedFaction == 0 and b4.Highlight1.shown == false, "reputation: second click closes the popup and clears the selection")
    -- skills tab
    local t3 = tabs.list[3]
    t3.scripts.OnClick(t3)
    local sk = cs.panels[2]
    check(sk.built == true and SkillsFrame.shown == true and rep.list.shown == false and cf.width == 384, "skills: panel up, reputation list gone, classic size kept")
    check(sheet.art[3].texture == "Interface\\PaperDollInfoFrame\\SkillFrame-BotLeft" and SkillsFrame.ScrollBox.shown == false and SkillsFrame.SkillDetailFrame.shown == false, "skills: skill-frame bottom art, Blizzard's list hidden")
    local r1, r2, r3, r4 = sk.rows[1], sk.rows[2], sk.rows[3], sk.rows[4]
    check(r1.shown == false and r1.header.shown == true and r1.header.Text.text == "Weapon Skills" and r1.header.index == 3, "skills: class skills hidden like Forever, weapon header first")
    check(r2.shown == true and r2.Name.text == "Daggers" and r2.Rank.text == "1/195" and r2.minmax[2] == 195 and r2.value == 1 and r2.barColor[3] == 1, "skills: skill bar with rank text, blue")
    check(r3.Name.text == "Defense" and r3.Rank.text == "187 (|cff20ff20+3|r)/195", "skills: defense modifier from UnitDefenseSkill")
    check(r4.shown == false and r4.header.shown == true and r4.header.NormalTexture.texture == "Interface\\Buttons\\UI-PlusButton-Up", "skills: collapsed secondary header")
    check(r1.anchors[1][4] == 38 and r1.anchors[1][5] == -79 and r2.anchors[1][5] == -97 and r1.header.anchors[1][4] == 22 and r1.header.anchors[1][5] == -86, "skills: Era row positions")
    check(r2.Border.NormalTexture.texture == "Interface\\PaperDollInfoFrame\\UI-Character-Skills-BarBorder" and r2.Border.width == 281, "skills: bevel border around each bar")
    check(sk.allButton.collapsed == true and sk.detail.bar.shown == false, "skills: All button shows plus while a header is collapsed, no detail yet")
    sk.allButton.scripts.OnClick(sk.allButton)
    check(w.skillExpanded[1] == 6 and w.skillExpanded[2] == 3 and w.skillExpanded[3] == 1 and sk.allButton.collapsed == false, "skills: All expands every header, last first")
    check(sk.rows[5].Name.text == "Cooking" and sk.rows[5].barColor[1] == 0.75 and sk.rows[5].barColor[2] == 0.75, "skills: expanded header's skill listed, secondary colour")
    sk.rows[5].Border.scripts.OnClick(sk.rows[5].Border)
    check(w.selectedSkill == 7 and sk.rows[5].Border.highlightLocked == true and sk.detail.bar.shown == true and sk.detail.bar.Name.text == "Cooking" and sk.detail.Description.text == "Cooking.", "skills: click selects and fills the detail bar")
    check(sk.detail.bar.Unlearn.shown == true, "skills: abandonable skill shows the unlearn button")
    sk.detail.bar.Unlearn.scripts.OnClick(sk.detail.bar.Unlearn)
    check(w.popup and w.popup[1] == "UNLEARN_SKILL" and w.popup[3] == 185, "skills: unlearn goes through Blizzard's confirmation popup")
    sk.allButton.scripts.OnClick(sk.allButton)
    check(#w.skillCollapsed == 3 and w.skillCollapsed[1] == 6, "skills: All collapses every header")
    -- honor tab
    local t4 = tabs.list[4]
    t4.scripts.OnClick(t4)
    local hn = cs.panels[3]
    check(hn.built == true and PVPRankFrame.shown == true and sk.list.shown == false and cf.width == 384 and sheet.art[1].texture == "Interface\\PaperDollInfoFrame\\UI-Character-General-TopLeft", "honor: panel up in the classic sheet with the General art")
    check(PVPRankFrame.MainInfoFrame.shown == false and PVPRankFrame.DetailFrame.shown == false and PVPRankFrame.SeasonTimerField.alpha == 0, "honor: Blizzard's rank display and detail pane hidden")
    check(PVPRankFrame.RewardsPane.shown == false and hn.panel.shown == true, "honor: every other child of Blizzard's frame hidden too, ours left up")
    local hp = hn.panel
    check(hp.title.text == "Corporal" and hp.rank.text == "(Rank 2)" and hp.bar.minmax[2] == 1500 and hp.bar.value == 300 and hp.bar.anchors[1][4] == 22 and hp.bar.anchors[1][5] == -77, "honor: rank title and Era's 315x29 rank bar filled from the rank points")
    local s1, s2, s3, s4, s5 = hp.sections[1], hp.sections[2], hp.sections[3], hp.sections[4], hp.sections[5]
    check(s1.Title.anchors[1][4] == 36 and s1.Title.anchors[1][5] == -112 and s2.Title.anchors[1][5] == -165 and s3.Title.anchors[1][5] == -220 and s4.Title.anchors[1][5] == -274 and s5.Title.anchors[1][5] == -350, "honor: five section titles on Era's HonorFrame grid")
    check(s1.rows[1].anchors[1][2] == s1.Title and s1.rows[1].anchors[1][4] == 10 and s1.rows[1].anchors[1][5] == -3 and s1.rows[2].anchors[1][2] == s1.rows[1] and s1.rows[1].width == 278 and s1.rows[1].height == 12 and #s5.rows == 3, "honor: 278x12 rows 10px in under each title, three in the last box")
    check(s1.Title.text == "Season 1" and s1.rows[1].Label.text == "Rank Points" and s1.rows[1].Value.text == "300 / 1500" and s1.rows[2].Label.text == "Season Total" and s1.rows[2].Value.text == "2300 / 3000", "honor: season box: rank points and season total as label/value rows")
    check(s1.rows[1].Value.font == GameFontGreenSmall and s1.rows[2].Value.font == GameFontNormalSmall and s2.rows[2].Value.font == GameFontGreenSmall, "honor: earned values green like Era's honorable kills, the rest gold")
    check(s2.Title.text == "This Week" and s2.rows[1].Value.text == "3000 (Rank 3)" and s2.rows[2].Label.text == "Cap Increase" and s2.rows[2].Value.text == "+1000", "honor: this-week box: cap and its rise")
    check(s3.Title.text == "Next Rewards at Rank 4" and s3.rows[1].Label.text == "Faction Tabard" and s3.rows[1].Icon.texture == 135026 and s3.rows[1].Icon.shown == true and s3.rows[1].Label.anchors[1][4] == 16 and s3.rows[2].Label.text:find("Stormwind", 1, true) and s3.rows[2].Icon.shown == false, "honor: reward box: 12px icon before the reward, vendor line under it")
    check(s4.Title.text == "Season" and s4.rows[1].Value.text == "3d" and s4.rows[2].Value.text == "14000 (Rank 14)" and hp.levelText.text == "Level 39 Human Priest", "honor: season box: time left and the season maximum, level line")
    check(s5.Title.text == "Rank Points" and s5.Text.text:find("14000", 1, true) and s5.Text.anchors[1][2] == s5.rows[1] and s5.Text.width == 278, "honor: the cap paragraph wrapped over the three-row box")
    -- and back
    t1.scripts.OnClick(t1)
    check(PaperDollFrame.shown == true and cf.width == 384 and sheet.shown == true and t1.selected == true, "sheet: character tab restores the classic layout")
    check(CharacterStatsPaneScrollBox.shown == false and w.sidebarShown == CharacterStatsPaneScrollBox and PaperDollSidebarTabs.alpha == 0 and PaperDollLevelInfo.alpha == 0, "sheet: Blizzard's Expand/SetSidebar showed its panes again, hooks hid them")
    -- off: everything back
    w.slash("charsheet off")
    check(cs.mode == "off" and cf.width == 631 and cf.NineSlice.alpha == 1 and cf.ModeTabs.alpha == 1 and cf.ModeTabs.Tabs[1].mouse == true, "off: Blizzard's frame size, shell and side tabs back")
    check(sheet.shown == false and tabs.shown == false, "off: our sheet and tabs hidden")
    check(ReputationFrame.ScrollBox.shown == true and SkillsFrame.SkillDetailFrame.shown == true and rep.list.shown == false and sk.list.shown == false, "off: Blizzard's reputation and skills lists back")
    check(StatisticsFrame.ScrollBox.shown == true and StatisticsFrame.DetailFrame.shown == true and st.list.shown == false and cur.list.shown == false and TokenFrame.Background.alpha == 1, "off: Blizzard's currency and statistics pieces back")
    check(PVPRankFrame.MainInfoFrame.shown == true and PVPRankFrame.RewardsPane.shown == true and PVPRankFrame.SeasonTimerField.alpha == 1 and hn.panel.shown == false, "off: Blizzard's honor display back")
    local h = CharacterHeadSlot.anchors[1]
    check(h[2] == cf.LeftPaneHost and h[4] == 24 and h[5] == -60 and CharacterHeadSlot.BorderFrame.alpha == 1 and CharacterModelScene.anchors[1][2] == cf.LeftPaneHost and CharacterModelScene.width == 398, "off: slots and model back on Blizzard's anchors")
    check(CharacterStatsPaneScrollBox.shown == true and CharacterStatsPaneScrollBox.alpha == 1 and PaperDollSidebarTabs.alpha == 1, "off: Blizzard's stats list back")
    check(CharacterAmmoSlot.gearSlotSmall.alpha == 1 and CharacterAmmoSlot.arrowHolder.alpha == 1, "off: ammo slot art back")
    w.slash("charsheet on")
    check(cs.mode == "restyled" and cf.width == 384 and sheet.shown == true and CharacterHeadSlot.anchors[1][4] == 21, "on: classic layout again")
    w.slash("probe")
    check(w.ns.lastProbe:find("charsheet: setting=on mode=restyled", 1, true), "sheet: probe reports the part")
    check(#w.ns.errors == 0 and #w.blizzErrors == 0, "sheet: no errors")
end

--------------------------------------------------------------------------
-- 3e. Forever spellbook: Era's 384x512 book on Blizzard's PlayerSpellsFrame
--------------------------------------------------------------------------
do
    -- the quest log, appearances and guild parts are held back as coming
    -- soon (section 8); the hold is lifted here so their code is still tested
    local w = NewWorld({style = "6", forever = true, unhold = true})
    local sb = w.ns.modules.spellbook
    check(sb.mode == "waiting" and PlayerSpellsFrame == nil and sb.watcher ~= nil, "book: nothing to hook at login, module waits for Blizzard_PlayerSpells")
    w.slash("spellbook")
    check(Printed("waiting for Blizzard's spell window"), "book: status says so")
    sb.watcher:Fire("ADDON_LOADED", "Blizzard_SomethingElse")
    check(sb.mode == "waiting", "book: other addons loading change nothing")
    local psf = w.LoadPlayerSpells()
    sb.watcher:Fire("ADDON_LOADED", "Blizzard_PlayerSpells")
    check(sb.mode == "restyled" and sb.book ~= nil and sb.book.parent == psf, "book: re-skinned once Blizzard's window loads, book built on it")
    psf:Show()
    check(psf.width == 384 and psf.height == 512, "book: window is Era's 384x512 once open")
    check(psf.NineSlice.alpha == 0 and psf.Bg.alpha == 0 and psf.TopTileStreaks.alpha == 0 and psf.CloseButton.alpha == 0 and psf.CloseButton.mouse == false and psf.MaximizeMinimizeButton.alpha == 0, "book: retail shell faded, close and maximize unclickable")
    local page = psf.SpellBookFrame
    check(page.alpha == 0 and page.anchors[1][3] == "BOTTOMLEFT" and page.anchors[1][5] == -5000, "book: retail page transparent and moved out of reach")
    local p = psf.PortraitContainer.portrait
    check(p.anchors[1][2] == psf and p.anchors[1][4] == 10 and p.anchors[1][5] == -8 and p.width == 58 and psf.TitleContainer.alpha == 0, "book: book icon in Era's corner, retail title faded")
    local book = sb.book
    check(book.shown == true and book.art[1].texture == "Interface\\Spellbook\\UI-SpellbookPanel-TopLeft" and book.art[4].anchors[1][1] == "BOTTOMRIGHT" and book.title.text == "Spellbook", "book: four-piece Era art and the title")
    local b = book.buttons
    check(b[1].anchors[1][4] == 34 and b[1].anchors[1][5] == -85 and b[2].anchors[1][2] == b[1] and b[2].anchors[1][4] == 157 and b[3].anchors[1][2] == b[1] and b[3].anchors[1][5] == -14, "book: twelve buttons in Era's two columns")
    check(b[1].item.name == "Attack" and b[1].Icon.texture == 135641 and b[1].SpellName.text == "Attack" and b[1].SpellSubName.text == "", "book: first spell on the first button")
    check(b[3].item.name == "Perception" and b[3].SpellSubName.text == "Racial" and b[5].item.name == "Diplomacy", "book: left column reads down (Era's button order)")
    check(b[5].item.passive and b[5].NormalTexture.vertex[1] == 0 and b[5].SpellName.textColor[1] == 0.77 and b[3].NormalTexture.vertex[1] == 1, "book: passive gets the black ring and dim gold name")
    check(b[7].item == nil and b[7].Icon.shown == false and b[2].item == nil, "book: future spell left out, right column empty on a short page")
    check(b[1].attributes.type == "spell" and b[1].attributes.spell == 6603 and b[5].attributes.type == nil, "book: secure cast attributes on castable spells only")
    check(b[1].Cooldown.cooldown[1] == 100 and b[1].Cooldown.cooldown[2] == 5, "book: cooldown from C_Spell")
    -- SPELL_UPDATE_COOLDOWN storms in combat - every cast, every global
    -- cooldown - and was sweeping all twelve buttons with the book shut
    local swept = 0
    local cd1 = b[1].Cooldown
    local realUpdate = cd1.SetCooldown
    function cd1:SetCooldown(st, d) swept = swept + 1; return realUpdate(self, st, d) end
    book:Hide()
    book:Fire("SPELL_UPDATE_COOLDOWN")
    check(swept == 0, "book: no cooldown work while the book is shut, however hard the event fires")
    book:Show()
    book:Fire("SPELL_UPDATE_COOLDOWN")
    check(swept == 1, "book: the swirls are redrawn again once it is open")
    cd1.SetCooldown = realUpdate
    -- Forever keeps cooldown times secret, and SetCooldown throws on one:
    -- the swirl goes off for the session instead of erroring every update
    local before = #w.ns.errors
    _G.C_Spell = {GetSpellCooldown = function() return {startTime = {__secret = true}, duration = {__secret = true}} end}
    local cd = b[1].Cooldown
    function cd:SetCooldown() error("bad argument #1 to 'SetCooldown': Secret values are only allowed during untainted execution") end
    function cd:Clear() self.cleared = true end
    sb:Force()
    check(#w.ns.errors == before and sb.cooldownsBlocked == true and cd.cleared == true, "book: a secret cooldown turns the swirl off rather than erroring")
    check(Printed("cooldown swirl stays off") and sb:Status():find("cooldown swirl off", 1, true), "book: it says so once, and the status carries it for the report")
    local said = #printed
    sb:Force()
    check(#w.ns.errors == before and #printed == said, "book: it does not say so again, or error, on the next update")
    check(book.pageText.text == "Page 1" and book.prev.enabled == false and book.next.enabled == false, "book: one page for General")
    local t1, t2, t3 = book.skillTabs[1], book.skillTabs[2], book.skillTabs[3]
    check(t1.shown and t1.Icon.texture == 626005 and t1.checked == true and t2.shown and t2.checked == false and t3.shown == false, "book: skill line tabs down the right edge, General checked")
    check(t1.anchors[1][1] == "TOPLEFT" and t1.anchors[1][3] == "TOPRIGHT" and t1.anchors[1][4] == -32 and t1.anchors[1][5] == -65 and t2.anchors[1][5] == -17, "book: Era tab positions")
    local bt = book.tabSpells
    check(bt.anchors[1][1] == "BOTTOMLEFT" and bt.anchors[1][4] == 20 and bt.anchors[1][5] == 45 and bt.height == 32 and bt.width == math.max(84, bt.Text:GetStringWidth() + 44) and book.tabPet.shown == false, "book: bottom tab sized to its label at the foot of the book, no pet tab without a pet")
    check(bt.Left.texture == "Interface\\PaperDollInfoFrame\\UI-Character-InActiveTab" and bt.Middle.anchors[2][1] == "BOTTOMRIGHT" and bt.Text.anchors[1][1] == "CENTER" and bt.Text.anchors[1][5] == 2 and bt.Text.textColor[1] == 1 and bt.Text.textColor[2] == 1 and bt.enabled == false, "book: tab art three-sliced from the character sheet's, label centred, selected tab white and disabled")
    check(t1.CheckedTexture.blend == "ADD" and t1.CheckedTexture.texture == "Interface\\Buttons\\CheckButtonHilight", "book: checked skill tab glows instead of painting the icon black")
    b[1].scripts.OnEnter(b[1])
    check(GameTooltip.spellBookItem[1] == 1 and GameTooltip.spellBookItem[2] == 0, "book: tooltip from the spell book slot")
    b[1].scripts.OnDragStart(b[1])
    check(w.pickedUp[1] == 1 and w.pickedUp[2] == 0, "book: drag picks the spell up")
    -- second skill line: 14 spells, two pages
    t2.scripts.OnClick(t2)
    check(sb.currentLine == 2 and b[1].item.name == "Holy 1" and b[2].item.name == "Holy 7" and b[12].item.name == "Holy 12" and book.pageText.text == "Page 1" and book.next.enabled == true and book.prev.enabled == false, "book: Holy page 1, next page available")
    book.next.scripts.OnClick(book.next)
    check(sb.page == 2 and b[1].item.name == "Holy 13" and b[3].item.name == "Holy 14" and b[5].item == nil and book.pageText.text == "Page 2" and book.next.enabled == false, "book: page 2 holds the last two spells")
    book.next.scripts.OnClick(book.next)
    check(sb.page == 2, "book: no page past the last")
    -- combat: attributes wait for the fight to end
    w.inCombat = true
    book.prev.scripts.OnClick(book.prev)
    check(sb.page == 1 and b[1].item.name == "Holy 1" and b[1].attributes.spell == 1013 and sb.attributesDirty == true, "book: paging in combat shows the spells but keeps the old cast attributes")
    w.inCombat = false
    book.scripts.OnEvent(book, "PLAYER_REGEN_ENABLED")
    check(b[1].attributes.spell == 1001 and sb.attributesDirty == nil, "book: attributes caught up after combat")
    -- pet tab appears with a pet
    w.petSpells = 2
    book.scripts.OnEvent(book, "UNIT_PET")
    check(book.tabPet.shown == true, "book: pet tab shows when the player has a pet")
    -- talents page: Blizzard's size back
    page:Hide()
    check(psf.width == 809 and psf.height == 720 and book.shown == false and psf.NineSlice.alpha == 1 and page.alpha == 1 and page.anchors[1][5] == 4 and psf.TitleContainer.alpha == 1, "book: retail window back while the talents page is up")
    page:Show()
    check(psf.width == 384 and book.shown == true, "book: classic again on the spellbook page")
    psf:SetSize(809, 720)
    check(psf.width == 384, "book: Blizzard's own resize undone while the book is up")
    w.slash("spellbook off")
    check(sb.mode == "off" and psf.width == 809 and psf.NineSlice.alpha == 1 and book.shown == false and page.alpha == 1 and p.anchors[1][4] == -5, "off: everything back")
    w.slash("spellbook on")
    check(sb.mode == "restyled" and psf.width == 384 and book.shown == true, "on: classic book again")
    check(w.panelTainted == nil, "book: UIParent's panel width never set by the addon (it taints the panel: the book would not open in combat)")
    -- combat: the window and its retail page hold the secure spell buttons and are protected,
    -- so neither may be moved or sized in a fight (blocked, and blamed on the addon).
    -- Opened in combat, the book stays Blizzard's until the fight ends and is dressed then.
    page:Hide()
    check(sb.applied == false and psf.width == 809, "book: talents page up out of combat: retail window back")
    w.inCombat = true
    w.ResetBlocked()
    page:Show()
    check(page.alpha == 1 and page.anchors[1][5] == 4 and psf.width == 809 and book.shown == false and sb.combatPending == true and w.Blocked() == 0, "book: opened in combat, Blizzard's page and window are left alone (no protected call)")
    w.inCombat = false
    book:Fire("PLAYER_REGEN_ENABLED")
    check(psf.width == 384 and page.alpha == 0 and page.anchors[1][5] == -5000 and book.shown == true and sb.combatPending == nil and sb.applied == true, "book: dressed as Era's once combat ends")
    -- Blizzard sizing the window in combat while the book is up: undone after combat, not during
    w.inCombat = true
    w.ResetBlocked()
    psf:SetSize(809, 720)
    check(psf.width == 809 and w.ns.PSF.pendingSize == true and w.Blocked() == 1, "book: Blizzard's own combat resize stands (only its call touched the window), ours waits")
    w.inCombat = false
    w.ns.PSF.waiter:Fire("PLAYER_REGEN_ENABLED")
    check(psf.width == 384 and w.ns.PSF.pendingSize == nil, "book: Era's size back once combat ends")
    -- the page going away in combat: our book goes at once, the protected page and window wait
    w.inCombat = true
    w.ResetBlocked()
    page:Hide()
    check(book.shown == false and page.anchors[1][5] == -5000 and psf.width == 384 and psf.NineSlice.alpha == 1 and w.ns.PSF.pendingSize == true and sb.combatPending == true and w.Blocked() == 0, "book: page hidden in combat: book gone, shell back, page and size wait")
    w.inCombat = false
    w.ns.PSF.waiter:Fire("PLAYER_REGEN_ENABLED")
    book:Fire("PLAYER_REGEN_ENABLED")
    check(psf.width == 809 and page.alpha == 1 and page.anchors[1][5] == 4 and sb.applied == false, "book: window and page back after combat")
    page:Show()
    check(psf.width == 384 and book.shown == true, "book: classic again")
    check(#w.ns.errors == 0 and #w.blizzErrors == 0, "book: no errors")

    -- professions window: Era's book round Blizzard's five cards
    local pr = w.ns.modules.professions
    check(pr.mode == "waiting" and ProfessionsFrame == nil and pr.watcher ~= nil, "professions: waits for Blizzard's ProfessionsFrame")
    local pb = w.LoadProfessionsBook()
    pr.watcher:Fire("ADDON_LOADED", "Blizzard_Professions")
    check(pr.mode == "restyled" and pr.book ~= nil and pr.book.parent == pb and pr.book.shown == false, "professions: re-skinned once the window exists, book built and kept hidden until it opens")
    pb:Show()
    check(pb.width == 384 and pb.height == 512 and pr.book.shown == true and pr.book.title.text == "Professions" and pr.book.art[1].texture == "Interface\\Spellbook\\UI-SpellbookPanel-TopLeft", "professions: Era's 384x512 book with the title once open")
    check(pb.NineSlice.alpha == 0 and pb.Bg.alpha == 0 and pb.CloseButton.mouse == false and pb.TitleContainer.alpha == 0 and pb.PortraitContainer.portrait.width == 58, "professions: retail shell faded, the book icon in the corner")
    local content = pb.BookPage.ProfessionsContentFrame
    local p1, p2, s1, s3 = content.PrimaryProfession1, content.PrimaryProfession2, content.SecondaryProfession1, content.SecondaryProfession3
    check(p1.anchors[1][2] == pb and p1.anchors[1][4] == 34 and p1.anchors[1][5] == -68 and p1.width == 316 and p1.height == 68, "professions: first card is a 316x68 row in Era's page band")
    check(p2.anchors[1][5] == -139 and s1.anchors[1][5] == -210 and s3.anchors[1][5] == -352 and s3.width == 316 and pr.rows == 5 and p1.anchors[1][4] + p1.width == 350, "professions: five rows down the page, even margin either side")
    check(p1.Background.alpha == 0 and p1.ProfessionName.anchors[1][4] == 0 and p1.ProfessionName.anchors[1][5] == -4, "professions: card art faded, the name top left of the row")
    local b1, b2 = p1.SpellButton1, p1.SpellButton2
    check(b1.anchors[1][2] == p1 and b1.anchors[1][4] == 0 and b1.anchors[1][5] == -24 and b2.anchors[1][4] == 167 and b1.IconTextureOverlay.alpha == 0, "professions: the two spell buttons under the name, retail square frame faded")
    check(pr.own[b1].ring.texture == "Interface\\Buttons\\UI-Quickslot2" and math.abs(pr.own[b1].ring.width - 64 * 40 / 37) < 0.01 and b1.subSpellString.textColor[1] == 0.5, "professions: classic quickslot ring round each icon, rank line brown")
    local bar = pr.own[p1].bar
    check(p1.StatusBar.alpha == 0 and p1.StatusBar.mouse == false and bar ~= nil and bar.shown == true and bar.barTexture == "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar" and bar.barColor[3] == 0.75 and bar.width == 137, "professions: Blizzard's rank bar faded and silenced, Era's blue skill bar in its place")
    check(bar.anchors[1][3] == "TOPRIGHT" and bar.anchors[1][4] == -28 and bar.minmax[2] == 75 and bar.value == 1 and bar.Rank.text == "1/75" and bar.Left.texture == "Interface\\PaperDollInfoFrame\\UI-Character-Skills-BarBorder", "professions: skill bar in from the page edge, filled from GetProfessionInfo in the skills bevel")
    check(pr.own[s1].bar.Rank.text == "42 (+5)/75" and pr.own[p2].bar.shown == false, "professions: skill modifier shown, no bar on an empty card")
    check(p1.UnlearnButton.anchors[1][2] == bar and p1.UnlearnButton.anchors[1][3] == "RIGHT" and p1.UnlearnButton.anchors[1][4] == 6, "professions: unlearn button just past the end of our bar")
    check(p2.missingText.anchors[1][4] == 0 and p2.missingText.anchors[1][5] == -20 and p2.missingText.width == 316 and p2.missingText.textColor[1] == 0.25 and p2.missingText.font == GameFontHighlightSmall and p2.missingHeader.anchors[1][5] == -4, "professions: empty card's text in the book's small font, wrapped in the row in parchment brown")
    local t1, t2 = pb.ProfessionsOverviewTab, pb.Professions1Tab
    check(t1.width == 32 and t1.anchors[1][2] == pb and t1.anchors[1][3] == "TOPRIGHT" and t1.anchors[1][4] == -32 and t1.anchors[1][5] == -65 and t2.anchors[1][5] == -114 and pr.tabs == 2, "professions: side tabs are Era's 32px skill line tabs down the right edge")
    check(t1.Background.alpha == 0 and t1.SelectedTexture.alpha == 0 and pr.own[t1].bg.texture == "Interface\\SpellBook\\SpellBook-SkillLineTab" and pr.own[t1].checked.shown == true and pr.own[t2].checked.shown == false and t1.Icon.maskRemoved == t1.Mask and t1.Icon.width == 32, "professions: retail tab art faded, classic tab art and checked glow, icon square")
    pb:Update()
    check(pb.updates == 1 and p1.width == 316 and p1.anchors[1][2] == pb and b1.IconTextureOverlay.alpha == 0 and p1.StatusBar.alpha == 0, "professions: re-skinned after Blizzard's update")
    pb:SetSize(673, 594)
    check(pb.width == 384, "professions: Blizzard's own resize undone")
    pb.BookPage:Hide()
    check(pb.width == 673 and pr.book.shown == false and pr.applied == false and p1.width == 664 and p1.anchors[1][2] == content and t1.width == 55 and pb.NineSlice.alpha == 1 and pr.own[p1].bar.shown == false, "professions: crafting page up: retail window and cards back")
    check(pr:Status():find("crafting page up") ~= nil, "professions: status says the crafting page is up")
    pb.BookPage:Show()
    check(pb.width == 384 and pr.book.shown == true and p1.width == 316 and pr.applied == true, "professions: classic again on the overview page")
    w.slash("professions off")
    check(pr.mode == "off" and pb.width == 673 and pb.NineSlice.alpha == 1 and pr.book.shown == false and p1.width == 664 and p1.anchors[1][2] == content and b1.IconTextureOverlay.alpha == 1 and pr.own[b1].ring.shown == false and b1.subSpellString.textColor[1] == 0.82, "professions off: Blizzard's window, cards and art back")
    check(p2.missingText.textColor[1] == 1 and p2.missingText.width == 485 and p2.missingText.font == "ProfessionsCardParagraph" and t1.Icon.maskAdded == t1.Mask and t1.Background.alpha == 1 and pr.own[t1].bg.shown == false and p1.StatusBar.alpha == 1 and p1.StatusBar.mouse ~= false, "professions off: text colours, fonts, tab masks and rank bars back")
    w.slash("professions on")
    check(pr.mode == "restyled" and pb.width == 384 and pr.book.shown == true, "professions on: classic again")
    check(#w.ns.errors == 0 and #w.blizzErrors == 0, "professions: no errors")

    -- the quest list inside Forever's merged map window
    local ql = w.ns.modules.questlog
    check(ql.mode == "waiting" and QuestMapFrame == nil and ql.watcher ~= nil, "questlog: waits for Forever's QuestMapFrame")
    local side = w.LoadQuestMap()
    ql.watcher:Fire("PLAYER_ENTERING_WORLD")
    check(ql.mode == "restyled" and ql.panel ~= nil and ql.panel.parent == QuestScrollFrame and ql.panel.shown == false, "questlog: panel built once the quest list exists, hidden until it opens")
    -- a texcoord check: the 4-number form or the 8-number (flipped) form
    local function Coords(t, ...)
        local want, got = {...}, t.texcoord
        if not got or #got ~= #want then return false end
        for i = 1, #want do if math.abs(got[i] - want[i]) > 1e-9 then return false end end
        return true
    end
    local ART = w.ns.ERA_PANEL
    -- the map window's portrait, where Blizzard hangs it
    local portrait = WorldMapFrame.BorderFrame.PortraitContainer.portrait
    portrait:SetPoint("TOPLEFT", WorldMapFrame.BorderFrame.PortraitContainer, "TOPLEFT", -5, 7); portrait:SetSize(62, 62)
    side:Show()
    local panel, border = ql.panel, QuestScrollFrame.BorderFrame
    check(panel.shown == true and panel.level == 4, "questlog: the Era panel is level with the list so the quest rows draw on top")
    check(panel.header == false and panel.disc == nil and panel.ring == nil and #panel.art == 9 and panel.fill ~= nil and panel.fill.color ~= nil and panel.fill.color[4] == 1, "questlog: a headerless Era page over a solid floor, so the quest list is never see-through")
    local pc = panel.pieces
    check(pc.topLeft.texture == ART.botLeft and Coords(pc.topLeft, 0, 0.73828125, 0, 0.5625, 0.34375, 0.73828125, 0.34375, 0.5625) and pc.topLeft.width == 88 and pc.topLeft.height == 45, "questlog: its top corners are the page's torn bottom corners turned over, so no ring on a list")
    check(pc.topRight.texture == ART.botRight and Coords(pc.topRight, 0.375, 0.73828125, 0.375, 0.5625, 0.75, 0.73828125, 0.75, 0.5625) and pc.top.texture == ART.botLeft and Coords(pc.top, 0.34375, 0.73828125, 0.34375, 0.5625, 1, 0.73828125, 1, 0.5625), "questlog: the top edge and right corner turned over the same way")
    check(pc.bottomLeft.texture == ART.botLeft and Coords(pc.bottomLeft, 0, 0.34375, 0.5625, 0.73828125) and pc.bottomRight.texture == ART.botRight and Coords(pc.bottomRight, 0.375, 0.75, 0.5625, 0.73828125) and pc.bottomRight.width == 48 and pc.bottomRight.height == 45, "questlog: the bottom corners cut from the quarter files at their own size")
    check(pc.left.texture == ART.botLeft and Coords(pc.left, 0, 0.34375, 0, 0.5625) and pc.right.texture == ART.botRight and Coords(pc.right, 0.375, 0.75, 0, 0.5625) and pc.center.texture == ART.botLeft and Coords(pc.center, 0.34375, 1, 0, 0.5625), "questlog: the bevelled sides and the plain parchment in the middle come from the bottom quarters")
    check(pc.top.anchors[1][2] == pc.topLeft and pc.top.anchors[1][3] == "TOPRIGHT" and pc.top.anchors[2][2] == pc.topRight and pc.left.anchors[1][2] == pc.topLeft and pc.left.anchors[2][2] == pc.bottomLeft and pc.center.anchors[1][2] == pc.topLeft and pc.center.anchors[1][3] == "BOTTOMRIGHT" and pc.center.anchors[2][2] == pc.bottomRight and pc.center.anchors[2][3] == "TOPLEFT", "questlog: the edges and the middle run between the corners, so they stretch with the panel")
    check(panel.anchors[1][4] == -3 and panel.anchors[1][5] == 7 and panel.anchors[2][4] == 3 and panel.anchors[2][5] == -6, "questlog: the panel takes exactly the rect retail's quest panel filled")
    check(side.Background.alpha == 0 and QuestScrollFrame.Background.alpha == 0 and border.Border.alpha == 0 and border.TopDetail.alpha == 0 and border.Shadow.alpha == 0, "questlog: retail's quest panel, filigree and shadow faded")
    local mapw, mpanel = WorldMapFrame, ql.mapPanel
    check(mpanel ~= nil and mpanel.shown == true and mpanel.parent == mapw and mpanel.level == 0 and mpanel.header == true and #mpanel.art == 9, "questlog: a second Era panel behind the whole map window, this one with the header band")
    local mc = mpanel.pieces
    check(mc.topLeft.texture == ART.topLeft and Coords(mc.topLeft, 0, 0.34375, 0, 0.34375) and mc.topLeft.width == 88 and mc.topLeft.height == 88 and mc.topRight.texture == ART.topRight and Coords(mc.topRight, 0.375, 0.75, 0, 0.34375) and mc.topRight.width == 48 and mc.topRight.height == 88, "questlog: the map page's top corners are the stone header with the ring and the tab")
    check(mc.top.texture == ART.topLeft and Coords(mc.top, 0.34375, 1, 0, 0.34375) and mc.bottomLeft.texture == ART.botLeft and Coords(mc.bottomLeft, 0, 0.34375, 0.5625, 0.73828125), "questlog: the header band between them, the torn corners below")
    check(mpanel.disc ~= nil and mpanel.disc.texture == ART.disc and ART.disc == "Interface\\Minimap\\UI-Minimap-Background" and mpanel.disc.width == 64 and mpanel.disc.anchors[1][1] == "CENTER" and mpanel.disc.anchors[1][2] == mpanel and mpanel.disc.anchors[1][3] == "TOPLEFT" and mpanel.disc.anchors[1][4] == 41.5 and mpanel.disc.anchors[1][5] == -41.5, "questlog: a dark disc behind the portrait hole so it never shows the world")
    check(mapw.WorldMapFrameBg.alpha == 0 and mapw.BorderFrame.InsetBorderTop.alpha == 0 and mapw.BorderFrame.NineSlice.TopEdge.alpha == 0, "questlog: the map window's dark backdrop, inset line and metal shell faded")
    check(portrait.alpha == 1 and #portrait.anchors == 1 and portrait.anchors[1][1] == "CENTER" and portrait.anchors[1][2] == mpanel and portrait.anchors[1][3] == "TOPLEFT" and portrait.anchors[1][4] == 41.5 and portrait.anchors[1][5] == -41.5 and portrait.width == 58, "questlog: the map window's own portrait moved into the ring")
    check(mapw.BorderFrame.TitleContainer.TitleText.alpha == 1 and mapw.BorderFrame.CloseButton.alpha == 1, "questlog: Forever's title and close button on the map window left alone")
    check(QuestScrollFrame.EmptyText.textColor[1] == 0.85, "questlog: the 'no quests' text re-coloured for parchment")
    local q1 = QuestScrollFrame.Contents.Quest1
    check(q1.Text.font == GameFontNormal and q1.HighlightTexture.texture == "Interface\\QuestFrame\\UI-QuestLogTitleHighlight" and q1.HighlightTexture.blend == "ADD" and ql.rows == 2, "questlog: quest titles in Era's font under Era's highlight")
    side:Hide()
    check(panel.shown == false and mpanel.shown == false and portrait.alpha == 0 and portrait.anchors[1][1] == "TOPLEFT" and portrait.anchors[1][4] == -5 and portrait.width == 62, "questlog: both panels go with the window, and the portrait leaves the ring for its own corner")
    side:Show()
    check(mpanel.shown == true and portrait.alpha == 1 and portrait.anchors[1][2] == mpanel and portrait.width == 58, "questlog: and is back in the ring when the window opens again")
    w.slash("questlog off")
    check(ql.mode == "off" and panel.shown == false and mpanel.shown == false and border.Border.alpha == 1 and mapw.WorldMapFrameBg.alpha == 1 and mapw.BorderFrame.NineSlice.TopEdge.alpha == 1 and QuestScrollFrame.EmptyText.textColor[1] == 1 and q1.Text.font == "QuestFont_Enormous", "questlog off: retail's map window, quest panel, fonts and colours back")
    check(portrait.alpha == 1 and #portrait.anchors == 1 and portrait.anchors[1][1] == "TOPLEFT" and portrait.anchors[1][2] == mapw.BorderFrame.PortraitContainer and portrait.anchors[1][4] == -5 and portrait.anchors[1][5] == 7 and portrait.width == 62, "questlog off: the portrait back where Blizzard had it, at its own size and alpha")
    w.slash("questlog on")
    check(ql.mode == "restyled" and panel.shown == true, "questlog on: the Era panel again")

    -- the Appearances window: Era furniture round a window Era never had
    local co = w.ns.modules.collections
    check(co.mode == "waiting" and CollectionsJournal == nil, "collections: waits for Forever's CollectionsJournal")
    local cj = w.LoadCollections()
    co.watcher:Fire("ADDON_LOADED", "Blizzard_Collections")
    check(co.mode == "restyled" and co.panel ~= nil and co.panel.shown == false, "collections: framed once the window exists, kept hidden until it opens")
    local cport = cj.PortraitContainer.portrait
    cport:SetPoint("TOPLEFT", cj.PortraitContainer, "TOPLEFT", -5, 7); cport:SetSize(62, 62)
    cj:Show()
    local cpanel = co.panel
    local page = WardrobeCollectionFrame.activeFrame
    check(cpanel.shown == true and cpanel.header == true and #cpanel.art == 9 and cpanel.fill ~= nil and cpanel.fill.color ~= nil and cpanel.fill.color[4] == 1, "collections: the Era page behind the window, header band and all, over a solid floor")
    check(cpanel.pieces.topLeft.texture == ART.topLeft and Coords(cpanel.pieces.topLeft, 0, 0.34375, 0, 0.34375) and cpanel.pieces.center.texture == ART.botLeft and Coords(cpanel.pieces.center, 0.34375, 1, 0, 0.5625) and cpanel.disc ~= nil and cpanel.disc.texture == ART.disc, "collections: cut from Era's spellbook page, the dark disc behind the ring")
    check(cpanel.anchors[1][1] == "ALL" and cpanel.anchors[1][2] == cj and cpanel.level == 0, "collections: the page fills the window from just underneath it")
    check(cj.Bg.alpha == 0 and cj.NineSlice.TopEdge.alpha == 0, "collections: retail's shell faded")
    check(cport.alpha == 1 and cport.anchors[1][1] == "CENTER" and cport.anchors[1][2] == cpanel and cport.anchors[1][4] == 41.5 and cport.anchors[1][5] == -41.5 and cport.width == 58, "collections: the window's own portrait moved into the ring")
    check(page.Bg.alpha == 0 and page.BackgroundTile.alpha == 0 and page.ShadowCornerTopLeft.alpha == 0 and page.NineSlice.TopEdge.alpha == 0, "collections: the dark page inside the window faded too")
    check(cj.CloseButton.alpha == 1 and cj.CloseButton.mouse ~= false and cj.TitleContainer.TitleText.alpha == 1, "collections: Forever's own title and close button left alone")
    w.slash("collections off")
    check(co.mode == "off" and cpanel.shown == false and cj.Bg.alpha == 1 and cj.NineSlice.TopEdge.alpha == 1 and page.Bg.alpha == 1 and page.NineSlice.TopEdge.alpha == 1, "collections off: retail's window back")
    check(cport.alpha == 1 and cport.anchors[1][1] == "TOPLEFT" and cport.anchors[1][2] == cj.PortraitContainer and cport.anchors[1][4] == -5 and cport.width == 62, "collections off: the portrait back in its corner")
    w.slash("collections on")
    check(co.mode == "restyled" and cpanel.shown == true, "collections on: Era framing again")

    -- the guild window: Era's guild was a friends tab, so this is furniture too
    local gu = w.ns.modules.guild
    check(gu.mode == "waiting" and CommunitiesFrame == nil, "guild: waits for Forever's CommunitiesFrame")
    local cf = w.LoadGuild()
    gu.watcher:Fire("ADDON_LOADED", "Blizzard_Communities")
    check(gu.mode == "restyled" and gu.panel ~= nil and gu.panel.shown == false, "guild: framed once the window exists, kept hidden until it opens")
    local gport = cf.PortraitContainer.portrait
    gport:SetPoint("TOPLEFT", cf.PortraitContainer, "TOPLEFT", -5, 7); gport:SetSize(62, 62)
    cf:Show()
    local gpanel = gu.panel
    local list, finder = CommunitiesList, ClubFinderGuildFinderFrame
    check(gpanel.shown == true and gpanel.header == true and #gpanel.art == 9 and gpanel.fill ~= nil and gpanel.fill.color ~= nil and gpanel.fill.color[4] == 1 and gpanel.pieces.topRight.texture == ART.topRight and Coords(gpanel.pieces.topRight, 0.375, 0.75, 0, 0.34375) and gpanel.disc ~= nil, "guild: Era's page behind the window, header band and ring, over a solid floor")
    check(gpanel.anchors[1][1] == "ALL" and gpanel.anchors[1][2] == cf and gpanel.level == 0, "guild: the page fills the window from just underneath it")
    check(cf.Bg.alpha == 0 and cf.TopTileStreaks.alpha == 0 and cf.NineSlice.TopEdge.alpha == 0 and cf.PortraitOverlay.Portrait.alpha == 0, "guild: retail's metal shell, streaks and portrait overlay faded")
    check(gport.alpha == 1 and gport.anchors[1][1] == "CENTER" and gport.anchors[1][2] == gpanel and gport.anchors[1][4] == 41.5 and gport.anchors[1][5] == -41.5 and gport.width == 58, "guild: the window's own portrait moved into the ring")
    check(list.Bg.alpha == 0 and list.TopFiligree.alpha == 0 and list.BottomFiligree.alpha == 0 and list.FilligreeOverlay.LeftBar.alpha == 0 and list.InsetFrame.NineSlice.TopEdge.alpha == 0, "guild: the sidebar's dark page, filigree and inset faded")
    check(finder.DisabledFrame.Bg.alpha == 0 and finder.DisabledFrame.WideBackground.alpha == 0 and finder.DisabledFrame.NineSlice.TopEdge.alpha == 0, "guild: the guild finder page faded too")
    check(cf.CloseButton.alpha == 1 and cf.TitleContainer.TitleText.alpha == 1 and finder.Title.alpha == 1 and list.ScrollBox.alpha == 1, "guild: Forever's title, close button and the roster itself left alone")
    cf:SetDisplayMode(2)
    check(gpanel.shown == true and list.Bg.alpha == 0 and gport.alpha == 1 and gport.anchors[1][2] == gpanel and #gport.anchors == 1, "guild: the panel and the portrait in its ring survive a tab switch")
    w.slash("guild off")
    check(gu.mode == "off" and gpanel.shown == false and cf.Bg.alpha == 1 and cf.NineSlice.TopEdge.alpha == 1 and list.Bg.alpha == 1 and list.TopFiligree.alpha == 1 and finder.DisabledFrame.NineSlice.TopEdge.alpha == 1, "guild off: retail's window back")
    check(gport.alpha == 1 and gport.anchors[1][1] == "TOPLEFT" and gport.anchors[1][2] == cf.PortraitContainer and gport.anchors[1][4] == -5 and gport.width == 62, "guild off: the portrait back in its corner")
    w.slash("guild on")
    check(gu.mode == "restyled" and gpanel.shown == true, "guild on: Era framing again")
    check(#w.ns.errors == 0 and #w.blizzErrors == 0, "questlog, collections and guild: no errors")
end

--------------------------------------------------------------------------
-- 5b. Talents: Era's talent frame on Forever's talents page
--------------------------------------------------------------------------
do
    local w = NewWorld({style = "6", forever = true})
    local ta, sb = w.ns.modules.talents, w.ns.modules.spellbook
    check(ta.mode == "waiting" and ta.watcher ~= nil, "talents: waits for Blizzard_PlayerSpells like the book")
    local psf = w.LoadPlayerSpells()
    local tf = w.LoadTalents(psf)
    ta.watcher:Fire("ADDON_LOADED", "Blizzard_PlayerSpells")
    sb.watcher:Fire("ADDON_LOADED", "Blizzard_PlayerSpells")
    check(ta.mode == "restyled" and sb.mode == "restyled" and ta.frame ~= nil and ta.frame.parent == psf and ta.frame.shown == false, "talents: built once Forever's talent frame exists, hidden until the page is up")
    local bp, n = tf.ButtonsParent, tf.nodes
    -- the window opens on the talents page
    psf.SpellBookFrame:Hide()
    tf:Show()
    psf:Show()
    local frame, controls = ta.frame, ta.frame.controls
    check(ta.applied == true and frame.shown == true and controls.shown == true and w.ns.PSF.Owner() == "talents", "talents: the page claims the window")
    check(psf.width == 384 and psf.height == 512 and psf.NineSlice.alpha == 0 and psf.TitleContainer.alpha == 0 and psf.CloseButton.mouse == false, "talents: Era's 384x512 window, retail shell faded")
    check(psf.PortraitContainer.portrait.alpha == 0 and frame.portrait.portraitUnit == "player" and frame.portrait.width == 60 and frame.portrait.anchors[1][4] == 8 and frame.portrait.anchors[1][5] == -7, "talents: retail's spec icon faded, the player's own portrait in the ring as Era had it")
    check(frame.art[1].texture == "Interface\\PaperDollInfoFrame\\UI-Character-General-TopLeft" and frame.art[3].texture == "Interface\\TALENTFRAME\\UI-TalentFrame-BotLeft" and frame.art[3].anchors[1][1] == "BOTTOMLEFT" and frame.art[3].anchors[1][4] == 2 and frame.art[3].anchors[1][5] == -1, "talents: Era's frame art, the character sheet's top and the talent frame's bottom")
    check(controls.title.text == "Talents" and controls.title.anchors[1][5] == -18 and controls.close.anchors[1][3] == "TOPRIGHT" and controls.close.anchors[1][4] == -44, "talents: Era's title and close button")
    -- three trees, sorted out of one canvas, the one with points in it up first
    check(#ta.trees == 3 and ta.tree == 1 and #ta.trees[1].nodes == 12 and #ta.trees[2].nodes == 3 and #ta.trees[3].nodes == 2, "talents: three trees told apart by column, Beast Mastery (with the point in it) shown first")
    local t1, t2, t3 = controls.tabs[1], controls.tabs[2], controls.tabs[3]
    check(t1.shown and t1.Text.text == "Beast Mastery" and t2.Text.text == "Marksmanship" and t3.Text.text == "Survival" and t1.enabled == false and t1.Text.textColor[1] == 1 and t1.Text.textColor[2] == 1 and t2.enabled ~= false, "talents: the trees as Era's bottom tabs, the shown one white and disabled")
    check(t1.anchors[1][1] == "BOTTOMLEFT" and t1.anchors[1][4] == 20 and t1.anchors[1][5] == 45 and t2.anchors[1][2] == t1 and t2.anchors[1][4] == 4, "talents: tabs along the foot of the frame")
    check(controls.box.text.text == "Beast Mastery: 1" and controls.box.anchors[1][4] == 73 and controls.box.anchors[1][5] == -46 and controls.box.left.texture == "Interface\\Common\\Common-Input-Border", "talents: the tree's name and points spent in Era's box under the title")
    check(controls.points.text == "Talent Points: 3" and controls.points.shown ~= false, "talents: unspent points from Forever's tree currency")
    -- the canvas becomes Era's viewport and clips
    check(bp.anchors[1][1] == "TOPLEFT" and bp.anchors[1][2] == frame.view and bp.width == 296 and bp.height == 328 and bp.clips == true, "talents: ButtonsParent resized to Era's 296x328 viewport and clipping its children")
    check(frame.view.anchors[1][4] == 23 and frame.view.anchors[1][5] == -77 and frame.view.width == 296 and frame.view.height == 328, "talents: the viewport where Era's scroll frame was")
    check(frame.view.topLeft.texture == "Interface\\TalentFrame\\HunterBeastMastery-TopLeft" and frame.view.topRight.texture == "Interface\\TalentFrame\\HunterBeastMastery-TopRight" and frame.view.topRight.width == 44 and frame.view.bottomLeft.height == 75 and frame.view.topLeft.shown ~= false, "talents: the tree's own painting behind it, cut as Era cut it")
    -- nodes on Era's grid: the tree centred in the viewport, first tier 36px down
    local da, bw, mm1 = n.DA, n.BW, n.MM1
    check(da.anchors[1][1] == "CENTER" and da.anchors[1][2] == bp and da.anchors[1][3] == "TOPLEFT" and da.anchors[1][4] == 118 and da.anchors[1][5] == -36, "talents: the first talent centred on its column 36px under the top")
    check(bw.anchors[1][4] == 118 and bw.anchors[1][5] == -396 and n.IRP.anchors[1][4] == 238 and n.IRP.anchors[1][5] == -96, "talents: Forever's 60px grid kept, the tree just moved")
    check(mm1.anchors[1][4] == 2088 and n.SV1.anchors[1][4] > 4000, "talents: the other trees parked outside the clipped viewport")
    -- each node in Era's dress
    local oda, obs, ofrz = ta.own[da], ta.own[n.BS], ta.own[n.FRZ]
    check(da.StateBorder.alpha == 0 and da.Shadow.alpha == 0 and da.SpendText.alpha == 0 and da.SpendTextShadow1.alpha == 0 and da.Icon.alpha == 1, "talents: retail's square border, shadow and rank number faded, the icon kept")
    check(oda.slot.texture == "Interface\\Buttons\\UI-EmptySlot-White" and oda.ring.texture == "Interface\\Buttons\\UI-Quickslot2" and math.abs(oda.ring.width - 64 * 40 / 37) < 0.01 and oda.rankBorder.texture == "Interface\\TalentFrame\\TalentFrame-RankBorder" and oda.rankBorder.anchors[1][3] == "BOTTOMRIGHT", "talents: Era's empty slot, quickslot ring and rank box on each talent")
    check(oda.rank.text == "1" and oda.rank.textColor[1] == 1 and oda.rank.textColor[2] == 0.82 and oda.slot.vertex[1] == 1 and oda.slot.vertex[2] == 0.82, "talents: a maxed talent: gold rank, gold slot")
    check(obs.rank.text == "0" and obs.rank.textColor[2] == 1 and obs.rank.textColor[1] == 0.1 and obs.slot.vertex[2] == 1 and obs.rankBorder.shown == true, "talents: a talent with ranks to buy: green rank and slot")
    check(ofrz.slot.vertex[1] == 0.5 and ofrz.rankBorder.shown == false and ofrz.rank.shown == false, "talents: a locked talent: grey slot and no rank box until a point is in it")
    -- Era's branches and arrows from the nodes' own edges, retail's arrows faded
    local lines = ta.lines
    check(lines ~= nil and lines.parent == bp and lines.usedBranches == 11 and lines.usedArrows == 9 and ta.branches == 9, "talents: nine edges drawn: bars between the talents, an arrow into each unlocked one, a corner for the diagonal")
    local gold, grey = 0, 0
    for i = 1, lines.usedArrows do if lines.arrows[i].texcoord[3] == 0 then gold = gold + 1 else grey = grey + 1 end end
    check(gold == 2 and grey == 7 and lines.arrows[1].texture == "Interface\\TalentFrame\\UI-TalentArrows" and lines.branches[1].texture == "Interface\\TalentFrame\\UI-TalentBranches", "talents: gold where the talent is learned, grey where it is not, from Era's two files")
    -- the arrow into Summon Hawk from Ferocity on its left: Era's "left" tile (the one on the dependent's left side, pointing right at it)
    local sideArrow
    for i = 1, lines.usedArrows do local a = lines.arrows[i]; if a.anchors[1][5] == -216 and a.anchors[1][4] == 238 - 20 - 5 then sideArrow = a end end
    check(sideArrow ~= nil and sideArrow.texcoord[1] == 0.5 and sideArrow.texcoord[2] == 1.0, "talents: an arrow along a row sits on the unlocked talent's near side and points at it")
    check(lines.arrowFrame ~= nil and lines.arrowFrame.level > bp.level + 500, "talents: arrows drawn over the talents, as Era's are")
    local vertical
    for i = 1, lines.usedBranches do local b = lines.branches[i]; if b.width == 32 and b.height == 80 and b.anchors[1][4] == 102 and b.anchors[1][5] == -56 then vertical = b end end
    check(vertical ~= nil and vertical.texcoord[1] == 0 and vertical.texcoord[2] == 0.125, "talents: the bar from the first talent's foot to the next tier, 32 wide like Era's tile")
    check(tf.edges[1].alpha == 0 and tf.edges[3].alpha == 0, "talents: retail's arrows faded")
    tf.edges[1]:UpdateState()
    check(tf.edges[1].alpha == 0 and tf.edges[1].stateUpdates == 1, "talents: and faded again after Blizzard redraws one")
    -- Forever's furniture: page art faded, search box dead, Apply Changes kept in Era's bar
    check(tf.Background.alpha == 0 and tf.ClassBackground.alpha == 0 and tf.BackgroundBorder.alpha == 0 and tf.UnspentText.alpha == 0 and tf.Header1.alpha == 0, "talents: Forever's backgrounds, borders, labels and tree headers faded")
    check(tf.SearchBox.alpha == 0 and tf.SearchBox.mouse == false and tf.SpecTabs.alpha == 1 and tf.AnimationHolder.alpha == 1, "talents: the search box faded and unclickable, the tab strip and animation holder left alone")
    local ab = tf.ApplyButton
    check(ab.alpha == 1 and ab.anchors[1][1] == "RIGHT" and ab.anchors[1][2] == controls and ab.anchors[1][3] == "BOTTOMRIGHT" and ab.anchors[1][4] == -120 and ab.anchors[1][5] == 94 and ab.width == 110 and ab.height == 22, "talents: Apply Changes moved into Era's points bar and sized to fit")
    check(controls.points.anchors[1][2] == ab and controls.points.anchors[1][3] == "LEFT" and controls.points.anchors[1][4] == -8, "talents: the points text to its left")
    local pri, sec = tf.SpecTabs.Primary, tf.SpecTabs.Secondary
    check(pri.anchors[1][2] == controls and pri.anchors[1][3] == "TOPRIGHT" and pri.anchors[1][4] == -32 and (pri.anchors[1][5] == -65 or pri.anchors[1][5] == -95) and sec.anchors[1][3] == "TOPRIGHT" and sec.anchors[1][5] ~= pri.anchors[1][5], "talents: Forever's Primary/Secondary buttons at the right edge, where Era 1.15 kept its spec tabs")
    -- scrolling: the tree is taller than the viewport
    local slider = controls.slider
    check(slider.minmax[1] == 0 and slider.minmax[2] == 104 and slider.shown ~= false, "talents: a scroll bar for the 104px the tree overruns Era's viewport by")
    check(slider.template == nil and slider.up ~= nil and slider.up.NormalTexture.texture == "Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Up" and slider.down.NormalTexture.texture == "Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up" and slider.up.anchors[1][1] == "BOTTOM" and slider.up.anchors[1][3] == "TOP" and slider.up.anchors[1][5] == 0, "talents: the scroll bar is Era's own, built plain with its arrow buttons, not the client's template")
    check(slider.up.width == 18 and slider.up.height == 16 and slider.up.NormalTexture.texcoord[1] == 0.2 and slider.up.NormalTexture.texcoord[4] == 0.75 and slider.up.PushedTexture.texcoord[2] == 0.8 and slider.down.DisabledTexture.texcoord[3] == 0.25, "talents: the arrows cropped from their files as Era's template crops them")
    check(slider.up.enabled == false and slider.down.enabled ~= false, "talents: at the top, the up arrow is greyed")
    slider.down.scripts.OnClick(slider.down)
    slider.scripts.OnValueChanged(slider, slider.value)
    check(slider.value == 30 and slider.up.enabled ~= false and slider.down.enabled ~= false, "talents: the down arrow scrolls a step, both arrows live")
    slider.down.scripts.OnClick(slider.down); slider.down.scripts.OnClick(slider.down); slider.down.scripts.OnClick(slider.down)
    slider.scripts.OnValueChanged(slider, slider.value)
    check(slider.value == 104 and slider.down.enabled == false, "talents: and stops at the end, the down arrow greyed")
    slider.up.scripts.OnClick(slider.up)
    check(slider.value == 74, "talents: the up arrow scrolls back")
    slider:SetValue(0)
    slider.scripts.OnValueChanged(slider, 50)
    check(ta.scroll == 50 and da.anchors[1][5] == 14 and bw.anchors[1][5] == -346, "talents: scrolling moves the tree up under the clip")
    slider.scripts.OnValueChanged(slider, 0)
    -- Blizzard laying the nodes out again, and a node redrawing itself
    tf:UpdateAllTalentButtonPositions()
    check(da.anchors[1][4] == 118 and da.anchors[1][5] == -36 and mm1.anchors[1][4] == 2088, "talents: Forever's own relayout undone")
    tf:UpdatePadding()
    check(bp.anchors[1][2] == frame.view and bp.width == 296, "talents: and its own re-anchoring of the canvas")
    n.BS.state = 6; n.BS.nodeInfo.currentRank = 3; n.BS.nodeInfo.ranksPurchased = 3
    n.BS:FullUpdate()
    check(obs.rank.text == "3" and obs.slot.vertex[1] == 1 and obs.slot.vertex[2] == 0.82 and controls.box.text.text == "Beast Mastery: 4", "talents: a talent maxed out goes gold and the points spent follow")
    check(oda.slot.alpha ~= 0 and oda.ring.alpha ~= 0 and oda.rankBorder.alpha ~= 0 and oda.rank.alpha ~= 0 and obs.slot.alpha ~= 0, "talents: Era's own slot, ring and rank box survive the second pass over the node's regions")
    -- a commit reloads the tree: Forever hands the pooled buttons out afresh, so the
    -- frame that showed Deadly Aspects now shows Bestial Wrath and is anchored there
    da.nodeInfo, bw.nodeInfo = bw.nodeInfo, da.nodeInfo
    da.nodeID, bw.nodeID = bw.nodeID, da.nodeID
    tf.byID[da.nodeID], tf.byID[bw.nodeID] = da, bw
    tf:LoadTalentTreeInternal()
    check(da.anchors[1][4] == 118 and da.anchors[1][5] == -396 and bw.anchors[1][5] == -36, "talents: after a reload each button is placed by the talent it now holds, not the one it held")
    tf:Hide()
    check(da.anchors[1][4] == 173 and da.anchors[1][5] == -580 and bw.anchors[1][5] == -220, "talents: and leaving the page gives it back Forever's newer anchor")
    tf:Show()
    da.nodeInfo, bw.nodeInfo = bw.nodeInfo, da.nodeInfo
    da.nodeID, bw.nodeID = bw.nodeID, da.nodeID
    tf.byID[da.nodeID], tf.byID[bw.nodeID] = da, bw
    tf:LoadTalentTreeInternal()
    check(da.anchors[1][5] == -36 and bw.anchors[1][5] == -396, "talents: swapped back, the layout follows again")
    -- another tree
    t3.scripts.OnClick(t3)
    check(ta.tree == 3 and controls.box.text.text == "Survival: 0" and t3.enabled == false and t1.enabled ~= false and n.SV1.anchors[1][4] == 118 and n.SV1.anchors[1][5] == -36 and da.anchors[1][4] < -1000, "talents: the Survival tab brings its tree in and parks Beast Mastery")
    check(ta.treeArt == "HunterSurvival" and ta.treeArtMissing == true and frame.view.topLeft.shown == false and frame.view.floor ~= nil and ta:Status():find("file missing", 1, true), "talents: a tree whose painting this client lacks gets the plain floor, and the status says so")
    check(lines.usedBranches == 3 and lines.usedArrows == 1 and slider.minmax[2] == 0, "talents: one diagonal edge in the small tree (a bar, a corner, a bar, an arrow), nothing to scroll")
    t2.scripts.OnClick(t2)
    check(ta.tree == 2 and frame.view.topLeft.texture == "Interface\\TalentFrame\\HunterMarksmanship-TopLeft" and frame.view.topLeft.shown == true and n.MM1.anchors[1][4] == 88, "talents: Marksmanship with its own painting, its narrower tree centred")
    t1.scripts.OnClick(t1)
    -- the page changes: everything of Forever's back, the book takes the window
    tf:Hide()
    check(ta.applied == false and frame.shown == false and controls.shown == false and w.ns.PSF.Owner() == nil and psf.width == 809 and psf.NineSlice.alpha == 1, "talents: leaving the page puts the window back")
    check(da.anchors[1][2] == bp and da.anchors[1][4] == 173 and da.anchors[1][5] == -220 and da.StateBorder.alpha == 1 and da.SpendText.alpha == 1 and oda.slot.shown == false and oda.rankBorder.shown == false, "talents: the nodes back where Forever had them, in Forever's dress")
    check(bp.anchors[1][2] == tf and bp.anchors[2][1] == "BOTTOMRIGHT" and bp.width == 1212 and bp.clips == false and tf.Background.alpha == 1 and tf.SearchBox.alpha == 1 and tf.SearchBox.mouse ~= false and tf.edges[1].alpha == 1, "talents: the canvas, page art, search box and retail arrows back")
    check(ab.anchors[1][2] == tf and ab.anchors[1][1] == "BOTTOM" and ab.width == 140 and pri.anchors[1][2] == tf.SpecTabs and psf.PortraitContainer.portrait.alpha == 1, "talents: Apply Changes, the spec buttons and the portrait back")
    psf.SpellBookFrame:Show()
    check(w.ns.PSF.Owner() == "spellbook" and psf.width == 384 and sb.book.shown == true and psf.PortraitContainer.portrait.width == 58, "talents: the book page claims the window in turn")
    psf.SpellBookFrame:Hide()
    tf:Show()
    check(w.ns.PSF.Owner() == "talents" and psf.width == 384 and frame.shown == true and psf.PortraitContainer.portrait.alpha == 0 and da.anchors[1][4] == 118, "talents: and hands it back when the talents page returns")
    -- off and on
    w.slash("talents off")
    check(ta.mode == "off" and frame.shown == false and w.ns.PSF.Owner() == nil and psf.width == 809 and da.anchors[1][4] == 173 and bp.clips == false and ab.width == 140, "talents off: Forever's page as it was")
    w.slash("talents on")
    check(ta.mode == "restyled" and frame.shown == true and psf.width == 384 and da.anchors[1][4] == 118 and w.ns.PSF.Owner() == "talents", "talents on: Era's frame again")
    -- Forever names a hunter's one spec "Hunter" and has no name for the others: the tabs say what Era's said
    local specs = _G.GetSpecializationInfoForClassID
    _G.GetSpecializationInfoForClassID = function(classID, i) if i == 1 then return 251, "Hunter", "", 132001 end end
    w.slash("talents off")
    w.slash("talents on")
    check(t1.Text.text == "Beast Mastery" and t2.Text.text == "Marksmanship" and t3.Text.text == "Survival" and controls.box.text.text == "Beast Mastery: 4" and ta:Status():find("Survival (0)", 1, true) ~= nil, "talents: Forever's spec names are not the trees', so Era's names are used")
    _G.GetSpecializationInfoForClassID = function(classID, i) local names = {"Beast Mastery", "Guardian", "Marksmanship", "Survival"}; if names[i] then return 250 + i, names[i], "", 132000 + i end end
    w.slash("talents off")
    w.slash("talents on")
    check(t1.Text.text == "Beast Mastery" and t2.Text.text == "Marksmanship" and t3.Text.text == "Survival", "talents: a spec with no Era painting is skipped, the rest keep the client's names")
    -- a German client: its own names, told apart by spec ID
    _G.GetSpecializationInfoForClassID = function(classID, i) local specs = {{253, "Tierherrschaft"}, {254, "Treffsicherheit"}, {255, "\195\156berleben"}}; if specs[i] then return specs[i][1], specs[i][2], "", 132000 + i end end
    w.slash("talents off")
    w.slash("talents on")
    check(t1.Text.text == "Tierherrschaft" and t3.Text.text == "\195\156berleben" and frame.view.topLeft.texture == "Interface\\TalentFrame\\HunterBeastMastery-TopLeft", "talents: a client in another language keeps its own spec names, the paintings by spec")
    _G.GetSpecializationInfoForClassID = specs
    w.slash("talents off")
    w.slash("talents on")
    check(ta:Status():find("3 trees", 1, true) and ta:Status():find("Beast Mastery (4)", 1, true), "talents: status names the trees and their points")
    check(#w.ns.errors == 0 and #w.blizzErrors == 0, "talents: no errors")
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

--------------------------------------------------------------------------
-- 6. Settings survive a /reload (the saved table comes back from the client)
--------------------------------------------------------------------------
do
    local w = NewWorld({style = "6", forever = true})
    check(w.ns.dbLoaded == false and w.ns.db.logins == 1, "first login: no saved file yet, one login counted")
    w.ns.optionsPanel.deselectAll:Click()
    w.slash("castbar on")
    local saved = w.ns.db  -- the client writes this table to ForeverClassicUI.lua
    local cvarCopy = w.cvars.ForeverClassicUI_settings
    w = NewWorld({style = "6", forever = true, savedDB = saved})
    check(w.ns.dbLoaded == true and w.ns.db.logins == 2, "reload: saved file found, login count raised")
    check(w.ns.db.unitframes == false and w.ns.modules.unitframes.mode == "off" and w.ns.modules.minimap.mode == "off", "reload: parts turned off stay off")
    check(w.ns.db.castbar == true and w.ns.modules.castbar.mode == "restyled", "reload: the part turned back on is on")
    check(Printed("off (saved): nameplates, combo, unitframes, party, charsheet, spellbook, talents, professions, questlog, collections, guild, actionbars, minimap, tracker"), "reload: login line names the parts that are off")
    check(not Printed("coming soon"), "reload: nothing is held back, so the login line does not say so")
    check(w.ns.optionsPanel.checks.unitframes.checked == false and w.ns.optionsPanel.checks.castbar.checked == true, "reload: options boxes match the saved settings")
    w.slash("probe")
    check(w.ns.lastProbe and w.ns.lastProbe:find("saved file found at login: yes  logins counted in it: 2", 1, true) and w.ns.lastProbe:find("settings came from: saved file", 1, true), "reload: probe reports the saved file and login count")
    -- the same on a client that never writes the SavedVariables file: the CVar copy carries the settings
    check(cvarCopy == "nameplates=0,castbar=1,combo=0,unitframes=0,party=0,charsheet=0,spellbook=0,talents=0,professions=0,questlog=0,collections=0,guild=0,actionbars=0,minimap=0,tracker=0,bugbutton=1,welcomed=0", "reload: every change is also written to the settings CVar, with the feedback flags")
    w = NewWorld({style = "6", forever = true, cvars = {ForeverClassicUI_settings = cvarCopy}})
    check(w.ns.dbLoaded == false and w.ns.db.unitframes == false and w.ns.db.castbar == true and w.ns.modules.unitframes.mode == "off" and w.ns.modules.castbar.mode == "restyled", "no saved file: settings restored from the CVar copy")
    check(w.ns.dbSource:find("cvar fallback", 1, true) and w.ns.optionsPanel.checks.minimap.checked == false, "no saved file: probe names the fallback, boxes match")
    w.slash("minimap on")
    check(w.cvars.ForeverClassicUI_settings:find("minimap=1", 1, true) and w.ns.db.minimap == true, "no saved file: slash changes go to the CVar copy too")
    w = NewWorld({style = "6", forever = true, cvars = {ForeverClassicUI_settings = w.cvars.ForeverClassicUI_settings}})
    check(w.ns.modules.minimap.mode == "restyled" and w.ns.modules.unitframes.mode == "off", "no saved file: second reload keeps the change")
end

--------------------------------------------------------------------------
-- 7. Reporting a bug: welcome window, minimap button, error notice
--------------------------------------------------------------------------
do
    local w = NewWorld({style = "6", forever = true})
    local ns = w.ns
    -- first run on an account: the welcome window is up and says how to send one
    local welcome = ns.welcomeFrame
    check(welcome ~= nil and welcome.shown == true and ns.db.welcomed == false, "feedback: the welcome window opens on a first run")
    check(welcome.body.text:find("/cui report", 1, true) and welcome.body.text:find("screenshot", 1, true) and welcome.body.text:find("still the modern one", 1, true), "feedback: it covers both a broken look and a window not built yet")
    check(welcome.link.text == ns.FEEDBACK_URL and ns.FEEDBACK_URL:find("curseforge", 1, true), "feedback: the page to paste it on is in a box to copy")
    -- the report can run past what a comment will take, so there is an address too
    check(welcome.mail ~= nil and welcome.mail.text == ns.FEEDBACK_EMAIL and ns.FEEDBACK_EMAIL == "classicuiforforever@gmail.com", "feedback: the email address is in a box of its own to copy")
    check(welcome.body.text:find("too long for a comment", 1, true) ~= nil, "feedback: the window says why the email is there")
    welcome.shot.scripts.OnClick(welcome.shot)
    check(w.screenshots == 1, "feedback: the screenshot button takes one")
    welcome.report.scripts.OnClick(welcome.report)
    check(ns.lastProbe ~= nil and ns.lastProbe:find("Paste this", 1, true) and ns.lastProbe:find(ns.FEEDBACK_URL, 1, true), "feedback: the report says on its own first lines where it goes")
    check(ns.lastProbe:find(ns.FEEDBACK_EMAIL, 1, true) and ns.lastProbe:find("length limit", 1, true), "feedback: and that it can be emailed if it will not fit in a comment")
    welcome.close.scripts.OnClick(welcome.close)
    check(welcome.shown == false and ns.db.welcomed == true and w.cvars.ForeverClassicUI_settings:find("welcomed=1", 1, true), "feedback: closing it is remembered, in the file and the CVar copy")
    -- the minimap button
    local button = ns.minimapButton
    check(button ~= nil and button.shown ~= false and button.parent == Minimap and button.icon.texture == "Interface\\Spellbook\\Spellbook-Icon", "feedback: a minimap button with the book icon")
    check(button.anchors[1][2] == Minimap and button.anchors[1][1] == "CENTER", "feedback: it sits on the minimap ring")
    button.scripts.OnEnter(button)
    check(GameTooltip.lines[1] == "Classic UI for Forever" and GameTooltip.lines[2]:find("bug report", 1, true), "feedback: its tooltip says what it does")
    ns.lastProbe = nil
    button.scripts.OnClick(button, "LeftButton")
    check(ns.lastProbe ~= nil and ns.lastProbe:find("Classic UI for Forever bug report", 1, true), "feedback: left click opens the report")
    -- dragging round the ring keeps the angle
    button.scripts.OnDragStart(button)
    w.cursorX, w.cursorY = 70, 150
    button.scripts.OnUpdate(button)
    button.scripts.OnDragStop(button)
    check(math.abs(ns.db.minimapAngle - 90) < 0.01 and math.abs(button.anchors[1][5] - 80) < 0.01, "feedback: dragging it moves it round the ring and the angle is kept")
    -- the first error of a session says so, once
    check(ns.errorNotice == nil, "feedback: no notice before anything goes wrong")
    ns.errors[#ns.errors + 1] = "castbar: something went wrong"
    check(ns.errorNotice ~= nil and ns.errorNotice.shown == true and #ns.errors == 1, "feedback: an error raises the notice, and the list is still a plain list")
    ns.errorNotice.report.scripts.OnClick(ns.errorNotice.report)
    check(ns.errorNotice.shown == false, "feedback: the notice opens the report and goes away")
    ns.errors[#ns.errors + 1] = "castbar: and another"
    check(ns.errorNotice.shown == false and #ns.errors == 2, "feedback: it does not come back a second time in one session")
    -- turning the button off
    w.slash("button off")
    check(button.shown == false and ns.db.bugbutton == false and w.cvars.ForeverClassicUI_settings:find("bugbutton=0", 1, true), "feedback: /cui button off hides it and is remembered")
    check(ns.optionsPanel.bugButton ~= nil and ns.optionsPanel.bugButton.checked == false, "feedback: the options box follows")
    w.slash("welcome")
    check(ns.welcomeFrame.shown == true, "feedback: /cui welcome opens it again")
    check(#w.blizzErrors == 0, "feedback: no errors")
    w.slash("link")
    check(Printed(ns.FEEDBACK_EMAIL) and Printed(ns.FEEDBACK_URL), "feedback: /cui link prints both the page and the address")
end

--------------------------------------------------------------------------
-- 8. The "coming soon" hold: a part that is built but not ready is kept,
--    shown, and not switchable. Nothing is held in this version, so the
--    mechanism is tested by holding a part that is ready.
--------------------------------------------------------------------------
do
    local w = NewWorld({style = "6", forever = true})
    check(next(w.ns.COMING_SOON) == nil and not w.ns.IsComingSoon("questlog") and not w.ns.IsComingSoon("collections") and not w.ns.IsComingSoon("guild"), "coming soon: nothing is held back in this version")
    check(w.ns.modules.questlog.mode ~= "off" and w.ns.modules.collections.mode ~= "off" and w.ns.modules.guild.mode ~= "off" and not Printed("coming soon"), "coming soon: the three parts held in 0.7.9 are back on, and the login line does not mention a hold")
    w = NewWorld({style = "6", forever = true, hold = {"minimap"}})
    local ns = w.ns
    check(ns.IsComingSoon("minimap") and not ns.IsComingSoon("charsheet"), "coming soon: a held part is held, the rest are not")
    check(ns.modules.minimap.mode ~= "restyled", "coming soon: it does not enable at login")
    check(Printed("coming soon, so off for now: minimap"), "coming soon: login says which part is held")
    -- and it stays off however hard it is pushed
    w.slash("minimap on")
    check(ns.modules.minimap.mode ~= "restyled" and Printed("minimap: coming soon"), "coming soon: the slash command says so rather than turning it on")
    check(ns.SetPart("minimap", true) == false and ns.modules.minimap.mode ~= "restyled", "coming soon: SetPart refuses to turn one on")
    -- a saved 'on' does not let it back in, and is not overwritten either
    local saved = ns.db
    saved.minimap = true
    w = NewWorld({style = "6", forever = true, savedDB = saved, hold = {"minimap"}})
    check(w.ns.modules.minimap.mode ~= "restyled", "coming soon: a saved 'on' does not bring it back")
    check(w.ns.db.minimap == true, "coming soon: but the saved setting is kept, for when the part returns")
    -- the options panel shows it, greyed and dead
    local panel = w.ns.optionsPanel
    local box = panel.checks.minimap
    check(box ~= nil and box.checked == false and box.enabled == false and box.label.text:find("Coming soon", 1, true), "coming soon: the options box is there, unticked, greyed and disabled")
    box:Click()
    check(box.checked == false and w.ns.modules.minimap.mode ~= "restyled", "coming soon: clicking the box does nothing")
    panel.RefreshStatus()
    check(panel.status.text:find("minimap: coming soon", 1, true), "coming soon: the options panel status says so too")
    check(#w.ns.errors == 0 and #w.blizzErrors == 0, "coming soon: no errors")
    -- lifting the hold brings the part back with the setting it kept
    w = NewWorld({style = "6", forever = true, savedDB = saved})
    check(w.ns.modules.minimap.mode == "restyled" and w.ns.optionsPanel.checks.minimap.checked == true and w.ns.optionsPanel.checks.minimap.enabled ~= false, "coming soon: lifting the hold brings the part back on, with its box live")
end

realPrint(("Forever Classic UI harness: %d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
