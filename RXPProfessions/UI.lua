-- RestedXP Professions - window
-- Same look as RestedXP Party Sync: EllesmereUI's look when EllesmereUI is
-- installed, else skinned live from RestedXP's active theme when RestedXP
-- is installed, plain dark tooltip style otherwise.

local addonName, ns = ...

local frame
local lines = {}

local WIDTH = 220
local LINE_GAP = 3
local PADDING = 10
local TITLE_HEIGHT = 21

local STYLE_COLORS = {
    head = nil, -- theme text color
    normal = {0.85, 0.85, 0.85},
    good = {0.45, 0.95, 0.45},
    warn = {1, 0.65, 0.2},
    dim = {0.55, 0.55, 0.55}
}

local function GetRXP()
    if LibStub then
        local AceAddon = LibStub("AceAddon-3.0", true)
        return AceAddon and AceAddon:GetAddon("RXPGuides", true)
    end
end

local setupFrame

--------------------------------------------------------------------------
-- EllesmereUI look. EllesmereUI (retail 12.1+ and WoW Forever) has a skin
-- API for other addons: once the player is logged in it hands us its skin
-- functions, unless they turned third-party skins off for us in its
-- options. The windows then take EllesmereUI's flat panel, font, close
-- button, checkboxes and accent color instead of RestedXP's theme.
--------------------------------------------------------------------------

-- one skin call, never allowed to break the window
local function EUI(fnName, ...)
    local S = ns.euiSkin
    local fn = S and S[fnName]
    if fn then pcall(fn, ...) end
end

local function ApplyEUISkin()
    if not (ns.euiSkin and frame) or frame.euiSkinned then return end
    frame.euiSkinned = true
    ns.skinFont = nil
    local tb = frame.titleBar
    if frame.ClearBackdrop then frame:ClearBackdrop() end
    if tb.ClearBackdrop then tb:ClearBackdrop() end
    tb.bg:SetTexture(nil)
    EUI("Panel", frame)
    -- the title bar is a child frame drawn over the window's own border,
    -- so it carries a border of its own that lines up with it
    EUI("Panel", tb, {inset = true})
    -- a 1px line in the player's accent color under the title. On a child
    -- frame of its own: EllesmereUI re-fades the textures of the frames it
    -- skinned now and then, and this one has to stay.
    local holder = CreateFrame("Frame", nil, tb)
    holder:SetAllPoints(tb)
    local accent = holder:CreateTexture(nil, "ARTWORK")
    accent:SetHeight(1)
    accent:SetPoint("BOTTOMLEFT", tb, "BOTTOMLEFT", 1, 0)
    accent:SetPoint("BOTTOMRIGHT", tb, "BOTTOMRIGHT", -1, 0)
    frame.euiAccent = accent
    local function Recolor()
        local S = ns.euiSkin
        local ok, r, g, b = pcall(S.GetAccentColor)
        if ok and r then accent:SetColorTexture(r, g, b, 1) end
    end
    Recolor()
    EUI("OnLooksChanged", Recolor)
    EUI("Font", frame.title, 1, 1, 1)
    EUI("CloseButton", frame.closeButton)
    ns.SkinMinButtonEUI(frame.minButton)
    for _, line in ipairs(lines) do EUI("Font", line) end
end

-- the first-launch setup dialog, whenever it exists
local function SkinSetupEUI()
    local f = setupFrame
    if not (ns.euiSkin and f) or f.euiSkinned then return end
    f.euiSkinned = true
    if f.ClearBackdrop then f:ClearBackdrop() end
    EUI("Panel", f)
    for _, fs in ipairs(f.texts) do EUI("Font", fs) end
    for _, cb in ipairs(f.checks) do EUI("Checkbox", cb) end
    EUI("Button", f.okButton)
    EUI("WhiteButtonLabel", f.okButton)
end

-- RestedXP renamed its texture lookup (GetTexture became GetV1Texture in
-- 2026): try both, so the title banner draws on old and new versions
local function RXPTexture(RXP, name)
    local get = RXP and (RXP.GetV1Texture or RXP.GetTexture)
    if not get then return false end
    local ok, tex = pcall(get, name)
    return true, ok and tex or nil
end

local function ApplySkin()
    local RXP = GetRXP()
    local theme = RXP and (RXP.colors or RXP.activeTheme)
    local backdrop = RXP and RXP.RXPFrame and RXP.RXPFrame.backdrop
    ns.appliedTheme = theme
    -- EllesmereUI's look replaces RestedXP's theme entirely
    if ns.euiSkin then return ApplyEUISkin() end
    local bgColor = theme and theme.background or {0.05, 0.05, 0.08, 0.92}

    if frame.SetBackdrop then
        if frame.ClearBackdrop then frame:ClearBackdrop() end
        if backdrop and backdrop.edge then
            frame:SetBackdrop(backdrop.edge)
        else
            frame:SetBackdrop({
                bgFile = "Interface/BUTTONS/WHITE8X8",
                edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
                edgeSize = 12,
                insets = {left = 3, right = 3, top = 3, bottom = 3}
            })
        end
        frame:SetBackdropColor(unpack(bgColor))
    end

    local tb = frame.titleBar
    if tb.SetBackdrop then
        if tb.ClearBackdrop then tb:ClearBackdrop() end
        if backdrop and backdrop.guideName then
            tb:SetBackdrop(backdrop.guideName)
            tb:SetBackdropColor(unpack(bgColor))
        end
    end
    local found, banner = RXPTexture(RXP, "rxp-banner")
    if found then tb.bg:SetTexture(banner) end

    ns.skinFont = theme and theme.font
    if ns.skinFont then
        frame.title:SetFont(ns.skinFont, 11, "")
        for _, line in ipairs(lines) do
            line:SetFont(ns.skinFont, 10, "")
        end
    end
end

--------------------------------------------------------------------------
-- Minimize (the window folds up to its title bar) and opacity
--------------------------------------------------------------------------

-- Pin the window by its top-left corner, so a change of height (folding
-- up, a line more or less) leaves the title bar where it is. Positions
-- saved by older versions are converted the first time this runs.
local function AnchorTop()
    local left, top = frame:GetLeft(), frame:GetTop()
    if not (left and top) then return end
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    ns.db.pos = {"TOPLEFT", "BOTTOMLEFT", left, top}
end

-- the game's own minimize/expand art, as on its world map: Forever's red
-- buttons (an atlas, like its close button), the classic clients' files
local function HasAtlas(name)
    if not (C_Texture and C_Texture.GetAtlasInfo) then return false end
    local ok, info = pcall(C_Texture.GetAtlasInfo, name)
    return ok and info ~= nil
end

local function SetMinButtonLook(button, minimized)
    if button.euiBar then
        -- EllesmereUI: a "-" glyph, "+" while folded
        button.euiBar2:SetShown(minimized and true or false)
    elseif button.useAtlas then
        local base = minimized and "RedButton-Expand" or "RedButton-Condense"
        button:SetNormalAtlas(base)
        button:SetPushedAtlas(base .. "-Pressed")
    else
        local base = minimized and "Interface\\Buttons\\UI-Panel-BiggerButton" or
                         "Interface\\Buttons\\UI-Panel-SmallerButton"
        button:SetNormalTexture(base .. "-Up")
        button:SetPushedTexture(base .. "-Down")
    end
end

-- EllesmereUI has no minimize glyph of its own: draw one like its close X
-- (white at 75%, full on hover). The bars sit on the button itself, which
-- EllesmereUI never re-fades (we don't hand it this button).
function ns.SkinMinButtonEUI(button)
    if not button or button.euiBar then return end
    button:SetNormalTexture("")
    button:SetPushedTexture("")
    button:SetHighlightTexture("")
    local function Bar(w, h)
        local bar = button:CreateTexture(nil, "OVERLAY")
        bar:SetColorTexture(1, 1, 1, 1)
        bar:SetSize(w, h)
        bar:SetPoint("CENTER", 0, 0)
        bar:SetAlpha(0.75)
        return bar
    end
    button.euiBar, button.euiBar2 = Bar(11, 2), Bar(2, 11)
    button:HookScript("OnEnter", function()
        button.euiBar:SetAlpha(1)
        button.euiBar2:SetAlpha(1)
    end)
    button:HookScript("OnLeave", function()
        button.euiBar:SetAlpha(0.75)
        button.euiBar2:SetAlpha(0.75)
    end)
    SetMinButtonLook(button, ns.db and ns.db.minimized)
end

local function ApplyAlpha()
    local alpha = tonumber(ns.db.alpha) or 1
    frame:SetAlpha(alpha)
    -- a window you can't see must not catch clicks meant for the world
    local clickable = alpha > 0
    frame:EnableMouse(clickable)
    frame.closeButton:EnableMouse(clickable)
    frame.minButton:EnableMouse(clickable)
end

-- the setup dialog's slider shows the window's opacity, however it was set
local function SyncAlphaSlider()
    local slider = setupFrame and setupFrame.alphaSlider
    if not slider then return end
    local alpha = tonumber(ns.db.alpha) or 1
    -- SetValue fires OnValueChanged: not a change of ours to make
    slider.syncing = true
    slider:SetValue(alpha)
    slider.syncing = nil
    slider.Label(alpha)
end

-- opacity from 0 to 1, in steps of 0.01; returns what was set
function ns.SetWindowAlpha(value, fromSlider)
    value = math.max(0, math.min(1, tonumber(value) or 1))
    value = math.floor(value * 100 + 0.5) / 100
    ns.db.alpha = value
    if frame then ApplyAlpha() end
    if not fromSlider then SyncAlphaSlider() end
    return value
end

function ns.ToggleMinimize()
    if not frame then return end
    ns.db.minimized = not ns.db.minimized
    AnchorTop()
    if ns.db.minimized and not frame:IsShown() then
        -- folding a hidden window up shows it folded: that's the point
        ns.db.show = true
        frame:Show()
    end
    SetMinButtonLook(frame.minButton, ns.db.minimized)
    ns.UpdateUI()
end

local function CreateWindow()
    frame = CreateFrame("Frame", "RXPProfessionsFrame", UIParent,
                        BackdropTemplateMixin and "BackdropTemplate" or nil)
    frame:SetWidth(WIDTH)
    frame:SetHeight(60)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        AnchorTop()
    end)

    if ns.db.pos then
        frame:SetPoint(ns.db.pos[1], UIParent, ns.db.pos[2], ns.db.pos[3],
                       ns.db.pos[4])
    else
        -- by its top, so it grows downward from a title bar that stays put
        frame:SetPoint("TOP", UIParent, "CENTER", 320, -90)
    end

    local tb = CreateFrame("Frame", "$parentTitle", frame,
                           BackdropTemplateMixin and "BackdropTemplate" or nil)
    frame.titleBar = tb
    tb:SetPoint("TOPLEFT", 0, 0)
    tb:SetPoint("TOPRIGHT", 0, 0)
    tb:SetHeight(TITLE_HEIGHT)
    tb.bg = tb:CreateTexture(nil, "BACKGROUND")
    tb.bg:SetPoint("TOPLEFT", 4, -2)
    tb.bg:SetPoint("BOTTOMRIGHT", -2, 2)

    frame.title = tb:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    -- a little left of centre: two buttons sit on the right
    frame.title:SetPoint("CENTER", tb, "CENTER", -8, 0)
    frame.title:SetText("RestedXP Professions")

    local close = CreateFrame("Button", nil, tb, "UIPanelCloseButton")
    frame.closeButton = close
    close:SetPoint("RIGHT", 3, 0)
    close:SetScale(0.75)
    close:SetScript("OnClick", function()
        ns.db.show = false
        frame:Hide()
        ns.Print(ns.L["window hidden. Type /rxpp to bring it back."])
    end)

    -- minimize: fold up to the title bar and back (the window keeps
    -- running; only its lines are put away)
    local minButton = CreateFrame("Button", nil, tb)
    frame.minButton = minButton
    minButton:SetScale(0.75)
    -- the red atlas buttons only where the close button is one of them
    -- (Forever), so the pair always matches
    local closeTex = close.GetNormalTexture and close:GetNormalTexture()
    local okAtlas, closeAtlas = false, nil
    if closeTex and closeTex.GetAtlas then
        okAtlas, closeAtlas = pcall(closeTex.GetAtlas, closeTex)
    end
    minButton.useAtlas = okAtlas and type(closeAtlas) == "string" and
                             closeAtlas:lower():find("redbutton", 1, true) ~= nil and
                             HasAtlas("RedButton-Condense")
    if minButton.useAtlas then
        minButton:SetSize(24, 24)
        minButton:SetHighlightAtlas("RedButton-Highlight", "ADD")
        minButton:SetPoint("RIGHT", close, "LEFT", 0, 0)
    else
        minButton:SetSize(32, 32)
        minButton:SetHitRectInsets(5, 5, 5, 5)
        minButton:SetHighlightTexture(
            "Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight", "ADD")
        minButton:SetPoint("RIGHT", close, "LEFT", 12, 0)
    end
    SetMinButtonLook(minButton, ns.db.minimized)
    minButton:SetScript("OnClick", function() ns.ToggleMinimize() end)
    minButton:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(ns.db.minimized and ns.L["Expand"] or
                                ns.L["Minimize"])
        GameTooltip:Show()
    end)
    minButton:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)

    ApplySkin()
    ApplyAlpha()
end

local function GetLine(i)
    local line = lines[i]
    if not line then
        line = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        line:SetWidth(WIDTH - PADDING * 2)
        line:SetJustifyH("LEFT")
        -- fully wrap: no max-line cap, height auto-sizes and AddLine stacks
        -- by the real rendered height
        line:SetWordWrap(true)
        line:SetNonSpaceWrap(false)
        line:SetHeight(0)
        if ns.euiSkin then
            EUI("Font", line)
        elseif ns.skinFont then
            line:SetFont(ns.skinFont, 10, "")
        end
        lines[i] = line
    end
    line:Show()
    return line
end

local function AddLine(index, yOffset, text, r, g, b)
    local line = GetLine(index)
    line:ClearAllPoints()
    line:SetPoint("TOPLEFT", PADDING, -yOffset)
    line:SetText(text)
    line:SetTextColor(r or 1, g or 1, b or 1)
    return yOffset + line:GetStringHeight() + LINE_GAP
end

function ns.ToggleUI(cmd)
    if not frame then return end
    if cmd == "show" then
        ns.db.show = true
    elseif cmd == "hide" then
        ns.db.show = false
    else
        ns.db.show = not ns.db.show
    end
    if ns.db.show then
        frame:Show()
        ns.UpdateUI()
    else
        frame:Hide()
    end
end

function ns.UpdateUI()
    if not frame or not frame:IsShown() then return end

    local RXP = GetRXP()
    local currentTheme = RXP and (RXP.colors or RXP.activeTheme)
    if currentTheme ~= ns.appliedTheme then ApplySkin() end
    local tc = (not ns.euiSkin and currentTheme and currentTheme.textColor) or
                   {1, 1, 1}

    for _, line in ipairs(lines) do line:Hide() end
    SetMinButtonLook(frame.minButton, ns.db.minimized)
    if ns.db.minimized then
        frame:SetHeight(TITLE_HEIGHT)
        return
    end

    local i = 0
    local y = TITLE_HEIGHT + 6
    local function Line(text, style)
        i = i + 1
        local c = STYLE_COLORS[style or "normal"] or tc
        y = AddLine(i, y, text, c[1], c[2], c[3])
    end

    local tracked = ns.GetTracked()
    local names = {}
    for name in pairs(tracked) do table.insert(names, name) end
    table.sort(names)

    if #names == 0 then
        Line(ns.L["No professions tracked."], "dim")
        Line(ns.L["/rxpp setup to choose some"], "dim")
    end

    for idx, name in ipairs(names) do
        if idx > 1 then
            i = i + 1
            y = AddLine(i, y, " ", 1, 1, 1) -- spacer
        end
        for _, entry in ipairs(ns.BuildProfLines(name, tracked[name])) do
            Line(entry.text, entry.style)
        end
    end

    frame:SetHeight(y + PADDING - LINE_GAP)
end

--------------------------------------------------------------------------
-- First-launch setup: pick professions to track + Auction House question
--------------------------------------------------------------------------

function ns.ShowSetup()
    if setupFrame then
        SyncAlphaSlider()
        setupFrame:Show()
        return
    end

    local f = CreateFrame("Frame", "RXPProfessionsSetup", UIParent,
                          BackdropTemplateMixin and "BackdropTemplate" or nil)
    setupFrame = f
    f.texts, f.checks = {}, {}
    f:SetWidth(320)
    f:SetFrameStrata("DIALOG")
    f:SetPoint("CENTER")
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    if f.SetBackdrop then
        f:SetBackdrop({
            bgFile = "Interface/BUTTONS/WHITE8X8",
            edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
            edgeSize = 12,
            insets = {left = 3, right = 3, top = 3, bottom = 3}
        })
        f:SetBackdropColor(0.05, 0.05, 0.08, 0.95)
    end

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -12)
    title:SetText("|cFF66CCFFRestedXP Professions|r")
    table.insert(f.texts, title)

    local sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sub:SetPoint("TOP", 0, -30)
    sub:SetText(ns.L["Which professions are you leveling?"])
    table.insert(f.texts, sub)

    local learned = ns.ScanSkills()
    local boxes = {}
    local perColumn = math.ceil(#ns.CHOOSABLE / 2)
    local bottomY = 0
    for idx, name in ipairs(ns.CHOOSABLE) do
        local col = (idx > perColumn) and 1 or 0
        local row = (idx - 1) % perColumn
        local yOff = -52 - row * 26
        local cb = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
        cb:SetPoint("TOPLEFT", 20 + col * 150, yOff)
        cb:SetWidth(24)
        cb:SetHeight(24)
        local label = f:CreateFontString(nil, "OVERLAY",
                                         "GameFontHighlightSmall")
        label:SetPoint("LEFT", cb, "RIGHT", 2, 0)
        label:SetText(ns.ProfLabel(name) .. (learned[name] and " |cFF66FF66*|r" or ""))
        cb:SetChecked((ns.db.chosen and ns.db.chosen[name]) or
                          (not ns.db.chosen and learned[name] and true) or
                          false)
        boxes[name] = cb
        table.insert(f.checks, cb)
        table.insert(f.texts, label)
        if yOff < bottomY then bottomY = yOff end
    end
    local yOff = bottomY - 26

    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", 24, yOff)
    hint:SetText(ns.L["|cFF66FF66*|r = already learned"])
    table.insert(f.texts, hint)
    yOff = yOff - 22
    local ahBox = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    ahBox:SetPoint("TOPLEFT", 24, yOff)
    ahBox:SetWidth(24)
    ahBox:SetHeight(24)
    local ahLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    ahLabel:SetPoint("LEFT", ahBox, "RIGHT", 4, 0)
    ahLabel:SetText(ns.L["Use the Auction House for materials"])
    ahBox:SetChecked(ns.db.useAH and true or false)
    table.insert(f.checks, ahBox)
    table.insert(f.texts, ahLabel)

    -- window opacity, live while dragging (also /rxpp alpha <0-1>)
    local slider
    for _, template in ipairs({"UISliderTemplateWithLabels", "OptionsSliderTemplate"}) do
        local made, s = pcall(CreateFrame, "Slider", nil, f, template)
        if made and s then
            slider = s
            break
        end
    end
    if slider then
        yOff = yOff - 46
        f.alphaSlider = slider
        slider:SetPoint("TOPLEFT", 30, yOff)
        slider:SetWidth(260)
        slider:SetHeight(17)
        slider:SetMinMaxValues(0, 1)
        slider:SetValueStep(0.05)
        if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
        if slider.Low then slider.Low:SetText("0%") end
        if slider.High then slider.High:SetText("100%") end
        local function Label(value)
            if slider.Text then
                slider.Text:SetText(string.format(ns.L["Window opacity: %d%%"],
                                                  math.floor(value * 100 + 0.5)))
            end
        end
        slider.Label = Label
        slider:SetValue(tonumber(ns.db.alpha) or 1)
        Label(tonumber(ns.db.alpha) or 1)
        slider:SetScript("OnValueChanged", function(self, value)
            if self.syncing then return end
            Label(ns.SetWindowAlpha(value, true))
        end)
        if slider.Text then table.insert(f.texts, slider.Text) end
        yOff = yOff - 14
    end

    local ok = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.okButton = ok
    ok:SetWidth(100)
    ok:SetHeight(22)
    ok:SetPoint("BOTTOM", 0, 12)
    ok:SetText(ns.L["Save"])
    ok:SetScript("OnClick", function()
        ns.db.chosen = {}
        for name, cb in pairs(boxes) do
            if cb:GetChecked() then ns.db.chosen[name] = true end
        end
        ns.db.useAH = ahBox:GetChecked() and true or false
        ns.db.setupDone = true
        f:Hide()
        ns.Print(ns.L["saved. Change any time with /rxpp setup"])
        ns.db.show = true
        ns.ToggleUI("show")
        ns.Refresh()
    end)

    f:SetHeight(-yOff + 70)
    SkinSetupEUI()
    f:Show()
end

function ns.SetupUI()
    CreateWindow()
    if ns.db.show then frame:Show() else frame:Hide() end
end

-- Registered at load: EllesmereUI calls back at login (or right away if
-- it's already past that), before or after our windows exist
if EllesmereUI and EllesmereUI.RegisterSkin then
    EllesmereUI.RegisterSkin(addonName, function(S)
        ns.euiSkin = S
        SkinSetupEUI()
        if frame then
            ApplyEUISkin()
            ns.UpdateUI()
        end
    end)
end
