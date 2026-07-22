-- RestedXP Professions - window
-- Same look as RestedXP Party Sync: skinned live from RestedXP's active
-- theme when RestedXP is installed, plain dark tooltip style otherwise.

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

local function ApplySkin()
    local RXP = GetRXP()
    local theme = RXP and (RXP.colors or RXP.activeTheme)
    local backdrop = RXP and RXP.RXPFrame and RXP.RXPFrame.backdrop
    ns.appliedTheme = theme
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
    if RXP and RXP.GetTexture then
        tb.bg:SetTexture(RXP.GetTexture("rxp-banner"))
    end

    ns.skinFont = theme and theme.font
    if ns.skinFont then
        frame.title:SetFont(ns.skinFont, 11, "")
        for _, line in ipairs(lines) do
            line:SetFont(ns.skinFont, 10, "")
        end
    end
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
        local point, _, relPoint, x, y = self:GetPoint()
        ns.db.pos = {point, relPoint, x, y}
    end)

    if ns.db.pos then
        frame:SetPoint(ns.db.pos[1], UIParent, ns.db.pos[2], ns.db.pos[3],
                       ns.db.pos[4])
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 320, -120)
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
    frame.title:SetPoint("CENTER", tb, "CENTER", 0, 0)
    frame.title:SetText("RestedXP Professions")

    local close = CreateFrame("Button", nil, tb, "UIPanelCloseButton")
    close:SetPoint("RIGHT", 3, 0)
    close:SetScale(0.75)
    close:SetScript("OnClick", function()
        ns.db.show = false
        frame:Hide()
        ns.Print("window hidden. Type /rxpp to bring it back.")
    end)

    ApplySkin()
end

local function GetLine(i)
    local line = lines[i]
    if not line then
        line = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        line:SetWidth(WIDTH - PADDING * 2)
        line:SetJustifyH("LEFT")
        line:SetWordWrap(true)
        line:SetNonSpaceWrap(false)
        if line.SetMaxLines then line:SetMaxLines(2) end
        if ns.skinFont then line:SetFont(ns.skinFont, 10, "") end
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
    local tc = (currentTheme and currentTheme.textColor) or {1, 1, 1}

    for _, line in ipairs(lines) do line:Hide() end

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
        Line("No professions tracked.", "dim")
        Line("/rxpp setup to choose some", "dim")
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

local setupFrame

function ns.ShowSetup()
    if setupFrame then
        setupFrame:Show()
        return
    end

    local f = CreateFrame("Frame", "RXPProfessionsSetup", UIParent,
                          BackdropTemplateMixin and "BackdropTemplate" or nil)
    setupFrame = f
    f:SetWidth(260)
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

    local sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sub:SetPoint("TOP", 0, -30)
    sub:SetText("Which professions are you leveling?")

    local learned = ns.ScanSkills()
    local boxes = {}
    local yOff = -52
    for _, name in ipairs(ns.CHOOSABLE) do
        local cb = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
        cb:SetPoint("TOPLEFT", 24, yOff)
        cb:SetWidth(24)
        cb:SetHeight(24)
        local label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        label:SetPoint("LEFT", cb, "RIGHT", 4, 0)
        label:SetText(name .. (learned[name] and " |cFF66FF66(learned)|r" or ""))
        cb:SetChecked((ns.db.chosen and ns.db.chosen[name]) or
                          (not ns.db.chosen and learned[name] and true) or
                          false)
        boxes[name] = cb
        yOff = yOff - 26
    end

    yOff = yOff - 8
    local ahBox = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    ahBox:SetPoint("TOPLEFT", 24, yOff)
    ahBox:SetWidth(24)
    ahBox:SetHeight(24)
    local ahLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    ahLabel:SetPoint("LEFT", ahBox, "RIGHT", 4, 0)
    ahLabel:SetText("Use the Auction House for materials")
    ahBox:SetChecked(ns.db.useAH and true or false)

    local ok = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    ok:SetWidth(100)
    ok:SetHeight(22)
    ok:SetPoint("BOTTOM", 0, 12)
    ok:SetText("Save")
    ok:SetScript("OnClick", function()
        ns.db.chosen = {}
        for name, cb in pairs(boxes) do
            if cb:GetChecked() then ns.db.chosen[name] = true end
        end
        ns.db.useAH = ahBox:GetChecked() and true or false
        ns.db.setupDone = true
        f:Hide()
        ns.Print("saved. Change any time with /rxpp setup")
        ns.db.show = true
        ns.ToggleUI("show")
        ns.Refresh()
    end)

    f:SetHeight(-yOff + 70)
    f:Show()
end

function ns.SetupUI()
    CreateWindow()
    if ns.db.show then frame:Show() else frame:Hide() end
end
