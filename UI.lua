-- RestedXP Multi - partner window
-- Small movable frame showing your step and each partner's step, plus a
-- "waiting for..." banner while the step lock is holding the guide.
-- Skinned at runtime with RestedXP's own active theme (borders, banner
-- texture, colors, font) so it matches the guide window exactly.

local addonName, ns = ...

local frame
local lines = {}

local WIDTH = 230
local LINE_GAP = 3
local PADDING = 10
local TITLE_HEIGHT = 21

-- First readable line of text from step `index` of OUR loaded guide
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

-- Pull RestedXP's current theme onto our frame; falls back to a plain dark
-- tooltip look if anything is missing.
local function ApplySkin()
    local RXP = ns.RXP
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

    if ns.db.pos then
        frame:SetPoint(ns.db.pos[1], UIParent, ns.db.pos[2], ns.db.pos[3],
                       ns.db.pos[4])
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 320, 120)
    end

    -- title bar styled like RestedXP's guide-name banner
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
    frame.title:SetText("RestedXP Multi")

    local close = CreateFrame("Button", nil, tb, "UIPanelCloseButton")
    close:SetPoint("RIGHT", 3, 0)
    close:SetScale(0.75)
    close:SetScript("OnClick", function()
        ns.db.show = false
        frame:Hide()
        ns.Print("window hidden. Type /rxpm to bring it back.")
    end)

    -- shown only while the step lock is holding us on a finished step
    local skip = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.skipButton = skip
    skip:SetWidth(110)
    skip:SetHeight(20)
    skip:SetText("Skip wait")
    skip:SetScript("OnClick", function() ns.SkipWait() end)
    skip:Hide()

    ApplySkin()
end

local function GetLine(i)
    local line = lines[i]
    if not line then
        line = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        line:SetWidth(WIDTH - PADDING * 2)
        line:SetJustifyH("LEFT")
        line:SetWordWrap(false)
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
    local my = ns.my
    if not my then return end

    -- restyle if RestedXP's theme changed since we last drew
    local currentTheme = ns.RXP and (ns.RXP.colors or ns.RXP.activeTheme)
    if currentTheme ~= ns.appliedTheme then ApplySkin() end
    local tc = (currentTheme and currentTheme.textColor) or {1, 1, 1}

    for _, line in ipairs(lines) do line:Hide() end

    local i = 0
    local y = TITLE_HEIGHT + 6
    local function Line(text, r, g, b)
        i = i + 1
        y = AddLine(i, y, text, r, g, b)
    end

    -- our own row
    if my.total and my.total > 0 then
        Line(string.format("You  -  step %d/%d %s", my.step or 0, my.total,
                           my.done and "|cFF66FF66(done)|r" or ""), tc[1],
             tc[2], tc[3])
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
        if not stale and (p.version or 0) > 0 and p.version ~= ns.VERSION then
            if p.version < ns.VERSION then
                Line(string.format(
                         "|cFFFF9933%s's RXP Multi is outdated - have them update|r",
                         name), 0.95, 0.6, 0.2)
            else
                Line("|cFFFF9933your RXP Multi is outdated - update it|r", 0.95,
                     0.6, 0.2)
            end
        end
        if stale then
            Line(string.format("%s  -  |cFF888888offline?|r", name), 0.55,
                 0.55, 0.55)
        elseif not ns.IsSynced(name, p) then
            if p.theyDeclined then
                Line(string.format("%s  -  |cFFFF6666declined sync|r", name),
                     0.7, 0.55, 0.55)
            elseif ns.db.paired[name] then
                Line(string.format(
                         "%s  -  |cFFFFCC00waiting for their accept|r", name),
                     0.9, 0.85, 0.6)
            else
                Line(string.format("%s  -  |cFF888888not synced|r", name),
                     0.65, 0.65, 0.65)
                Line("    /rxpm sync " .. name .. " to sync up", 0.5, 0.5, 0.5)
            end
        elseif p.key == "" then
            Line(string.format("%s  -  no guide loaded", name), 0.7, 0.7, 0.7)
        elseif p.key ~= my.key then
            Line(string.format("%s  -  |cFFFFCC00other guide:|r %s", name,
                               p.guideName), 0.9, 0.85, 0.6)
            Line(string.format("    step %d/%d", p.step or 0, p.total or 0),
                 0.6, 0.6, 0.6)
            if p.stepLines then
                for _, stepLine in ipairs(p.stepLines) do
                    Line("    " .. stepLine, 0.75, 0.75, 0.75)
                end
            end
        elseif (p.gv or 0) ~= (my.version or 0) then
            Line(string.format("%s  -  step %d/%d", name, p.step or 0,
                               p.total or 0), tc[1], tc[2], tc[3])
            Line("    |cFFFF9933guide version differs - update addons|r", 0.9,
                 0.6, 0.3)
        else
            -- fully synced, same guide: compare positions via stepId so
            -- class-specific steps don't skew the picture
            local marker = ""
            local myId, theirId = my.stepId or 0, p.stepId or 0
            if p.done then
                marker = " |cFF66FF66(done)|r"
            elseif theirId > 0 and myId > 0 and theirId < myId then
                marker = " |cFFFF9933(behind)|r"
            elseif theirId > 0 and myId > 0 and theirId > myId then
                marker = " |cFF66CCFF(ahead)|r"
            end
            Line(string.format("%s  -  step %d/%d%s", name, p.step or 0,
                               p.total or 0, marker), tc[1], tc[2], tc[3])
            if p.stepLines then
                -- live step text as THEIR RestedXP renders it, running
                -- objective counts included - works even for steps our own
                -- guide doesn't contain (their class quests etc.)
                for _, stepLine in ipairs(p.stepLines) do
                    Line("    " .. stepLine, 0.8, 0.8, 0.8)
                end
                local myIdx = ns.FindMyStepByStepId(theirId)
                if not myIdx and theirId > 0 then
                    Line("    |cFFFFCC00(their class/race step - not in your guide)|r",
                         0.7, 0.65, 0.45)
                end
            else
                -- partner on an older RXP Multi that doesn't broadcast step
                -- text: fall back to looking the step up in our own guide
                local myIdx = ns.FindMyStepByStepId(theirId)
                if myIdx then
                    local stepText = ns.GetStepText(myIdx)
                    if stepText then
                        Line("    " .. stepText, 0.6, 0.6, 0.6)
                    end
                elseif theirId > 0 then
                    Line("    (a step your guide doesn't have - class quest?)",
                         0.6, 0.6, 0.6)
                end
            end
        end
    end

    -- waiting banner + skip button
    if ns.pendingStep then
        local _, waitingOn = ns.ShouldBlock(ns.pendingStep)
        if waitingOn then
            Line(string.format("|cFFFFAA00Waiting for: %s|r",
                               table.concat(waitingOn, ", ")), 1, 0.7, 0.2)
        end
        frame.skipButton:ClearAllPoints()
        frame.skipButton:SetPoint("TOPLEFT", PADDING, -y)
        frame.skipButton:Show()
        y = y + 24
    else
        frame.skipButton:Hide()
    end

    -- footer
    local lockText = ns.db.lock and "|cFF66FF66on|r" or "|cFFFF6666off|r"
    Line(string.format("lock: %s   /rxpm help", lockText), 0.45, 0.45, 0.5)

    frame:SetHeight(y + PADDING - LINE_GAP)
end

function ns.SetupUI()
    CreateWindow()
    if ns.db.show then frame:Show() else frame:Hide() end
end
