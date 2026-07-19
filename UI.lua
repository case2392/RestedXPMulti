-- RestedXP Multi - partner window
-- Small movable frame showing your step and each partner's step, plus a
-- "waiting for..." banner while the step lock is holding the guide.

local addonName, ns = ...

local frame
local lines = {}

local WIDTH = 230
local LINE_GAP = 3
local PADDING = 10

-- First readable line of text from step `index` of OUR loaded guide
-- (partners on the same guide have identical steps, so this is their text too)
function ns.GetStepText(index)
    local guide = ns.RXP and ns.RXP.currentGuide
    local step = guide and guide.steps and guide.steps[index]
    if not step then return end
    for _, element in ipairs(step) do
        local text = element.text
        if type(text) == "string" and text ~= "" and text ~= " " then
            text = text:gsub("\n.*", "")
            text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
            if #text > 60 then text = text:sub(1, 57) .. "..." end
            return text
        end
    end
end

local function CreateWindow()
    frame = CreateFrame("Frame", "RXPMultiFrame", UIParent,
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

    if frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile = "Interface/Tooltips/UI-Tooltip-Background",
            edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
            edgeSize = 12,
            insets = {left = 3, right = 3, top = 3, bottom = 3}
        })
        frame:SetBackdropColor(0.05, 0.05, 0.08, 0.88)
        frame:SetBackdropBorderColor(0.4, 0.6, 0.9, 0.9)
    end

    if ns.db.pos then
        frame:SetPoint(ns.db.pos[1], UIParent, ns.db.pos[2], ns.db.pos[3],
                       ns.db.pos[4])
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 320, 120)
    end

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.title:SetPoint("TOPLEFT", PADDING, -8)
    frame.title:SetText("|cFF66CCFFRXP Multi|r")

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    close:SetScript("OnClick", function()
        ns.db.show = false
        frame:Hide()
        ns.Print("window hidden. Type /rxpm to bring it back.")
    end)
end

local function GetLine(i)
    local line = lines[i]
    if not line then
        line = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        line:SetWidth(WIDTH - PADDING * 2)
        line:SetJustifyH("LEFT")
        line:SetWordWrap(false)
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
    local my = ns.my
    if not my then return end

    for _, line in ipairs(lines) do line:Hide() end

    local i = 0
    local y = 28
    local function Line(text, r, g, b)
        i = i + 1
        y = AddLine(i, y, text, r, g, b)
    end

    -- our own row
    if my.total and my.total > 0 then
        Line(string.format("You  -  step %d/%d %s", my.step or 0, my.total,
                           my.done and "|cFF66FF66(done)|r" or ""), 1, 1, 1)
    else
        Line("You  -  no guide loaded", 0.6, 0.6, 0.6)
    end

    -- partner rows
    local now = GetTime()
    local names = {}
    for name in pairs(ns.partners) do table.insert(names, name) end
    table.sort(names)

    if #names == 0 then
        Line("No partners found yet.", 0.6, 0.6, 0.6)
        Line("(friend needs RXP Multi + same party)", 0.5, 0.5, 0.5)
    end

    for _, name in ipairs(names) do
        local p = ns.partners[name]
        local stale = now - (p.lastSeen or 0) >= ns.STALE_SECONDS
        if stale then
            Line(string.format("%s  -  |cFF888888offline?|r", name), 0.55,
                 0.55, 0.55)
        elseif not ns.CodeMatches(p) then
            Line(string.format("%s  -  |cFFFF6666different sync code|r", name),
                 0.8, 0.5, 0.5)
        elseif p.key == "" then
            Line(string.format("%s  -  no guide loaded", name), 0.7, 0.7, 0.7)
        elseif p.key ~= my.key then
            Line(string.format("%s  -  |cFFFFCC00other guide:|r %s", name,
                               p.guideName), 0.9, 0.85, 0.6)
            Line(string.format("    step %d/%d", p.step or 0, p.total or 0),
                 0.6, 0.6, 0.6)
        else
            local marker = ""
            if p.done then
                marker = " |cFF66FF66(done)|r"
            elseif (p.step or 0) < (my.step or 0) then
                marker = " |cFFFF9933(behind)|r"
            elseif (p.step or 0) > (my.step or 0) then
                marker = " |cFF66CCFF(ahead)|r"
            end
            Line(string.format("%s  -  step %d/%d%s", name, p.step or 0,
                               p.total or 0, marker), 1, 1, 1)
            local stepText = ns.GetStepText(p.step)
            if stepText then
                Line("    " .. stepText, 0.6, 0.6, 0.6)
            end
        end
    end

    -- waiting banner
    if ns.pendingStep then
        local _, waitingOn = ns.ShouldBlock(ns.pendingStep)
        if waitingOn then
            Line(string.format("|cFFFFAA00Waiting for: %s|r",
                               table.concat(waitingOn, ", ")), 1, 0.7, 0.2)
        end
    end

    -- footer
    local codeText = ns.db.code ~= "" and ns.db.code or "none"
    local lockText = ns.db.lock and "|cFF66FF66on|r" or "|cFFFF6666off|r"
    Line(string.format("code: %s   lock: %s", codeText, lockText), 0.45, 0.45,
         0.5)

    frame:SetHeight(y + PADDING - LINE_GAP)
end

function ns.SetupUI()
    CreateWindow()
    if ns.db.show then frame:Show() else frame:Hide() end
end
