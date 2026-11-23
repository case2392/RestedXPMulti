-- Pace's Quality of Life - the /pqol status window: what's on and any
-- errors this session (Core.lua's ns.StatusText), all selected in a text
-- box so that Ctrl+C copies it, ready to send on. The options page has a
-- button for it too. A frame of our own, built the first time it's asked
-- for, the same way as Classic UI (Forever)'s report window.

local addonName, ns = ...

local WIDTH, HEIGHT = 620, 440
local win

local function Build()
    local f = CreateFrame("Frame", "PacesQoLStatusFrame", UIParent, "BackdropTemplate")
    f:SetSize(WIDTH, HEIGHT)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
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
    title:SetText("Pace's Quality of Life - status")
    f.title = title

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)
    f.close = close

    local scroll = CreateFrame("ScrollFrame", "PacesQoLStatusScroll", f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 20, -40)
    scroll:SetPoint("BOTTOMRIGHT", -40, 48)

    local edit = CreateFrame("EditBox", "PacesQoLStatusEdit", scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject("ChatFontNormal")
    edit:SetWidth(WIDTH - 80)
    edit:SetScript("OnEscapePressed", ns.Guard("status", function() f:Hide() end))
    -- (read only: whatever is typed into it, the text goes back as it was)
    edit:SetScript("OnTextChanged", ns.Guard("status", function(self, typed)
        if typed and f.text and self:GetText() ~= f.text then
            self:SetText(f.text)
            self:HighlightText()
        end
    end))
    scroll:SetScrollChild(edit)
    f.edit = edit
    -- (the keyboard goes back to the game with the window)
    f:SetScript("OnHide", ns.Guard("status", function() edit:ClearFocus() end))

    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("BOTTOMLEFT", 24, 22)
    hint:SetText("It's all selected: Ctrl+C copies it, ready to paste into a message.")
    f.hint = hint

    local all = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    all:SetSize(100, 22)
    all:SetPoint("BOTTOMRIGHT", -126, 16)
    all:SetText("Select all")
    all:SetScript("OnClick", ns.Guard("status", function()
        edit:SetFocus()
        edit:HighlightText()
    end))
    f.selectAll = all

    local again = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    again:SetSize(100, 22)
    again:SetPoint("BOTTOMRIGHT", -20, 16)
    again:SetText("Refresh")
    again:SetScript("OnClick", ns.Guard("status", function() ns.ShowStatus() end))
    f.refresh = again
    return f
end

-- /pqol status and the options page's Status button: the window, its text
-- as of now, all selected
function ns.ShowStatus()
    win = win or Build()
    ns.statusFrame = win
    local text = ns.StatusText()
    win.text = text
    win.edit:SetText(text)
    win:Show()
    win.edit:SetFocus()
    win.edit:HighlightText()
    return true
end
