-- Adventure Plates - the plate window, its editor, the welcome, the
-- minimap button
--
-- The window is Era's page (Era.lua): the stone header band with the
-- character's portrait in the ring and "Adventure Plates" over it, then
-- the model down the left in a dark inset and the card down the right on
-- the parchment. The card: the name in orange with the flavour title in
-- quotes under it, the guild and rank, "Level 14 Night Elf Druid" in the
-- class colour, the roles as the LFG role icons top right, up to four
-- playstyle tags with their icons, the two playtime rows (24 cells each,
-- lit for the hours they play, the current server hour outlined), and
-- the motto in a box. "Edit My Plate" turns the card into the editor.
-- The model turns like the character screen's: drag it, use the wheel,
-- or hold Era's rotate buttons under it. Another player's plate shows
-- their model if they are in range and their class icon if not.

local addonName, ns = ...

local WIDTH, HEIGHT = 740, 620
local CARD_W = 372
local TOP = -100                      -- content starts under the header band
local CELL, GAP = 10, 1
local CELL_ROWS = {{key = "weekdays", label = "Weekdays"}, {key = "weekends", label = "Weekends"}}
local ORANGE = {1, 0.5, 0}
local LIT = {0.95, 0.75, 0.1}
local DIM = {0.55, 0.47, 0.34}
local BOTH = {0.45, 0.8, 0.35}          -- an hour you and they both play
local ROLE_SIZE = 20
local CLASS_SHEET = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"
local ROTATE_SPEED = 2.5              -- radians a second while a rotate button is held
local DRAG_SPEED = 0.012              -- radians a pixel while dragging the model
local ZOOM_MIN, ZOOM_MAX = 0.6, 1.8

local INSET = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = {left = 3, right = 3, top = 3, bottom = 3}
}

local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c = pcall(fn, ...)
    if ok then return a, b, c end
end

local function Frame(kind, name, parent, template)
    local ok, f = pcall(CreateFrame, kind, name, parent, template)
    if ok and f then return f end
    return CreateFrame(kind, name, parent)
end

local function Backdrop(f, def, r, g, b, a, br, bg, bb)
    if not f.SetBackdrop then return end
    pcall(f.SetBackdrop, f, def)
    if f.SetBackdropColor then pcall(f.SetBackdropColor, f, r or 0, g or 0, b or 0, a or 0.9) end
    if br and f.SetBackdropBorderColor then pcall(f.SetBackdropBorderColor, f, br, bg, bb, 1) end
end

local function Text(parent, font, layer)
    return parent:CreateFontString(nil, layer or "ARTWORK", font or "GameFontHighlight")
end

local function Ink(fs)
    local c = ns.ERA.brown
    fs:SetTextColor(c[1], c[2], c[3])
    return fs
end

local function Line(parent, y)
    local t = parent:CreateTexture(nil, "ARTWORK")
    local c = ns.ERA.gold
    t:SetColorTexture(c[1], c[2], c[3], 0.7)
    t:SetHeight(1)
    t:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, y)
    t:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -4, y)
    return t
end

local function ClassColor(classFile)
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    if c then return c.r, c.g, c.b end
    return ns.ERA.brown[1], ns.ERA.brown[2], ns.ERA.brown[3]
end

local function Cursor()
    local x, y = Call(GetCursorPosition)
    local scale = UIParent and UIParent.GetEffectiveScale and Call(UIParent.GetEffectiveScale, UIParent) or 1
    if type(x) ~= "number" then return nil end
    return x / (scale or 1), y / (scale or 1)
end

--------------------------------------------------------------------------
-- building
--------------------------------------------------------------------------

local W -- the window

local function HourRow(parent, y, label)
    local row = {}
    row.label = Ink(Text(parent, "GameFontNormalSmall"))
    row.label:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, y)
    row.label:SetText(label)
    row.cells = {}
    for h = 0, 23 do
        local c = parent:CreateTexture(nil, "ARTWORK")
        c:SetSize(CELL, CELL)
        c:SetPoint("TOPLEFT", parent, "TOPLEFT", 72 + h * (CELL + GAP), y + 1)
        c:SetColorTexture(DIM[1], DIM[2], DIM[3], 1)
        row.cells[h] = c
    end
    row.now = parent:CreateTexture(nil, "OVERLAY")
    row.now:SetSize(CELL + 4, CELL + 4)
    row.now:SetColorTexture(0.2, 0.1, 0, 0.6)
    row.now:Hide()
    return row
end

local function BuildCard(win)
    local card = Frame("Frame", nil, win)
    card:SetSize(CARD_W, HEIGHT + TOP - 60)
    card:SetPoint("TOPLEFT", win, "TOPLEFT", WIDTH - CARD_W - 28, TOP)

    card.name = Text(card, "GameFontNormalHuge")
    card.name:SetPoint("TOPLEFT", card, "TOPLEFT", 4, -2)
    card.name:SetTextColor(ORANGE[1], ORANGE[2], ORANGE[3])
    card.title = Text(card, "GameFontNormalSmall")
    card.title:SetPoint("TOPLEFT", card.name, "BOTTOMLEFT", 0, -1)
    card.guild = Ink(Text(card, "GameFontHighlight"))
    card.guild:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -3)
    card.line = Text(card, "GameFontNormal")
    card.line:SetPoint("TOPLEFT", card.guild, "BOTTOMLEFT", 0, -3)
    card.profs = Ink(Text(card, "GameFontHighlightSmall"))
    card.profs:SetPoint("TOPLEFT", card.line, "BOTTOMLEFT", 0, -3)
    card.roles = {}
    for i, r in ipairs(ns.ROLES) do
        local t = card:CreateTexture(nil, "ARTWORK")
        t:SetSize(ROLE_SIZE, ROLE_SIZE)
        t:SetTexture(ns.ROLE_ICON)
        t:SetTexCoord(r.coords[1], r.coords[2], r.coords[3], r.coords[4])
        t:SetPoint("TOPRIGHT", card, "TOPRIGHT", -4 - (i - 1) * (ROLE_SIZE + 4), -4)
        t:Hide()
        card.roles[r.key] = t
    end
    -- "Alt of Name": click to ask for the main's plate
    card.alt = Frame("Button", nil, card)
    card.alt:SetSize(150, 16)
    card.alt:SetPoint("TOPRIGHT", card, "TOPRIGHT", -4, -30)
    card.alt.text = Text(card.alt, "GameFontNormalSmall")
    card.alt.text:SetPoint("RIGHT", card.alt, "RIGHT", 0, 0)
    card.alt.text:SetTextColor(ns.ERA.gold[1], ns.ERA.gold[2], ns.ERA.gold[3])
    card.alt:SetScript("OnClick", function() if W.mainKey then ns.RequestPlate(W.mainKey) end end)
    card.alt:SetScript("OnEnter", function(self)
        if GameTooltip and W.mainKey then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText("Click for " .. W.mainKey .. "'s plate")
            GameTooltip:Show()
        end
    end)
    card.alt:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    card.alt:Hide()
    Line(card, -98)

    card.tagsHeader = Text(card, "GameFontNormal")
    card.tagsHeader:SetPoint("TOPLEFT", card, "TOPLEFT", 4, -106)
    card.tagsHeader:SetText("Playstyle & Focus")
    card.tags = {}
    for i = 1, ns.MAX_TAGS do
        local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
        local icon = card:CreateTexture(nil, "ARTWORK")
        icon:SetSize(18, 18)
        icon:SetPoint("TOPLEFT", card, "TOPLEFT", 4 + col * 184, -126 - row * 24)
        local label = Ink(Text(card, "GameFontHighlight"))
        label:SetPoint("LEFT", icon, "RIGHT", 6, 0)
        card.tags[i] = {icon = icon, label = label}
    end
    card.lookingLabel = Text(card, "GameFontNormalSmall")
    card.lookingLabel:SetPoint("TOPLEFT", card, "TOPLEFT", 4, -176)
    card.lookingLabel:SetText("Looking for:")
    card.looking = Ink(Text(card, "GameFontHighlightSmall"))
    card.looking:SetPoint("LEFT", card.lookingLabel, "RIGHT", 6, 0)
    card.looking:SetWidth(CARD_W - 84)
    card.looking:SetJustifyH("LEFT")
    if card.looking.SetWordWrap then card.looking:SetWordWrap(false) end
    Line(card, -194)

    card.hoursHeader = Text(card, "GameFontNormal")
    card.hoursHeader:SetPoint("TOPLEFT", card, "TOPLEFT", 4, -202)
    card.hoursHeader:SetText("Active Playtime (Server Time)")
    card.overlap = Text(card, "GameFontHighlightSmall")
    card.overlap:SetPoint("TOPRIGHT", card, "TOPRIGHT", -4, -204)
    card.overlap:SetTextColor(BOTH[1], BOTH[2], BOTH[3])
    card.overlap:SetText("green: hours you both play")
    card.overlap:Hide()
    local marks = {{0, "12:00 a.m."}, {12, "12:00 p.m."}, {24, "24:00"}}
    card.marks = {}
    for i, m in ipairs(marks) do
        local t = Ink(Text(card, "GameFontNormalSmall"))
        local x = 72 + m[1] * (CELL + GAP)
        if m[1] == 0 then t:SetPoint("TOPLEFT", card, "TOPLEFT", x, -220)
        elseif m[1] == 24 then t:SetPoint("TOPRIGHT", card, "TOPLEFT", x, -220)
        else t:SetPoint("TOP", card, "TOPLEFT", x, -220) end
        t:SetText(m[2])
        card.marks[i] = t
    end
    card.rows = {}
    for i, r in ipairs(CELL_ROWS) do
        card.rows[r.key] = HourRow(card, -236 - (i - 1) * 18, r.label)
    end
    Line(card, -280)

    card.mottoHeader = Text(card, "GameFontNormal")
    card.mottoHeader:SetPoint("TOPLEFT", card, "TOPLEFT", 4, -288)
    card.mottoHeader:SetText("Adventurer Motto")
    card.mottoBox = Frame("Frame", nil, card, "BackdropTemplate")
    card.mottoBox:SetPoint("TOPLEFT", card, "TOPLEFT", 2, -306)
    card.mottoBox:SetPoint("TOPRIGHT", card, "TOPRIGHT", -2, -306)
    card.mottoBox:SetHeight(64)
    Backdrop(card.mottoBox, INSET, 0.93, 0.87, 0.72, 0.9, 0.6, 0.45, 0.15)
    card.motto = Ink(Text(card.mottoBox, "GameFontHighlight"))
    card.motto:SetPoint("TOPLEFT", card.mottoBox, "TOPLEFT", 10, -8)
    card.motto:SetPoint("BOTTOMRIGHT", card.mottoBox, "BOTTOMRIGHT", -10, 8)
    card.motto:SetJustifyH("LEFT")
    card.motto:SetJustifyV("TOP")
    if card.motto.SetWordWrap then card.motto:SetWordWrap(true) end

    card.stamp = Ink(Text(card, "GameFontNormalSmall"))
    card.stamp:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 4, 32)

    card.edit = Frame("Button", nil, card, "UIPanelButtonTemplate")
    card.edit:SetSize(130, 24)
    card.edit:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -4, 2)
    card.edit:SetText("Edit My Plate")
    card.edit:SetScript("OnClick", function() ns.ShowOwnPlate(true) end)

    -- a link to the plate, into the chat box
    card.share = Frame("Button", nil, card, "UIPanelButtonTemplate")
    card.share:SetSize(120, 24)
    card.share:SetPoint("RIGHT", card.edit, "LEFT", -6, 0)
    card.share:SetText("Share in Chat")
    card.share:SetScript("OnClick", function() ns.ShareInChat() end)

    card.ask = Frame("Button", nil, card, "UIPanelButtonTemplate")
    card.ask:SetSize(110, 24)
    card.ask:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -4, 2)
    card.ask:SetText("Ask Again")
    card.ask:SetScript("OnClick", function() if W.key then ns.RequestPlate(W.key, W.unit) end end)
    return card
end

local function EditCell(parent, x, y, rowKey, hour)
    local b = Frame("Button", nil, parent)
    b:SetSize(11, 16)
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    b.fill = b:CreateTexture(nil, "ARTWORK")
    b.fill:SetAllPoints(b)
    b.fill:SetColorTexture(DIM[1], DIM[2], DIM[3], 1)
    b.rowKey, b.hour = rowKey, hour
    b:SetScript("OnClick", function(self)
        local s = W.draft[self.rowKey]
        local on = s:sub(self.hour + 1, self.hour + 1) == "1"
        W.draft[self.rowKey] = s:sub(1, self.hour) .. (on and "0" or "1") .. s:sub(self.hour + 2)
        ns.RefreshEditor()
    end)
    b:SetScript("OnEnter", function(self)
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(("%02d:00 - %02d:00"):format(self.hour, self.hour + 1))
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    return b
end

local function BuildEditor(win)
    local ed = Frame("Frame", nil, win)
    ed:SetSize(CARD_W, HEIGHT + TOP - 60)
    ed:SetPoint("TOPLEFT", win, "TOPLEFT", WIDTH - CARD_W - 28, TOP)
    if ed.SetFrameLevel and win.GetFrameLevel then ed:SetFrameLevel(win:GetFrameLevel() + 5) end

    local y = -2
    local titleLabel = Text(ed, "GameFontNormal")
    titleLabel:SetPoint("TOPLEFT", ed, "TOPLEFT", 4, y)
    titleLabel:SetText("Nickname (shown under your name)")
    ed.title = Frame("EditBox", nil, ed, "InputBoxTemplate")
    ed.title:SetSize(CARD_W - 20, 20)
    ed.title:SetPoint("TOPLEFT", ed, "TOPLEFT", 10, y - 18)
    ed.title:SetAutoFocus(false)
    ed.title:SetMaxLetters(ns.MAX_TITLE)
    ed.title:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    ed.title:SetScript("OnTextChanged", function(self) if W.draft then W.draft.title = self:GetText() or "" end end)
    y = y - 44

    local lookingLabel = Text(ed, "GameFontNormal")
    lookingLabel:SetPoint("TOPLEFT", ed, "TOPLEFT", 4, y)
    lookingLabel:SetText("Looking for")
    ed.looking = Frame("EditBox", nil, ed, "InputBoxTemplate")
    ed.looking:SetSize(CARD_W / 2 - 14, 20)
    ed.looking:SetPoint("TOPLEFT", ed, "TOPLEFT", 10, y - 18)
    ed.looking:SetAutoFocus(false)
    ed.looking:SetMaxLetters(ns.MAX_LOOKING)
    ed.looking:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    ed.looking:SetScript("OnTextChanged", function(self) if W.draft then W.draft.looking = self:GetText() or "" end end)
    local mainLabel = Text(ed, "GameFontNormal")
    mainLabel:SetPoint("TOPLEFT", ed, "TOPLEFT", CARD_W / 2 + 4, y)
    mainLabel:SetText("My main (if this is an alt)")
    ed.main = Frame("EditBox", nil, ed, "InputBoxTemplate")
    ed.main:SetSize(CARD_W / 2 - 20, 20)
    ed.main:SetPoint("TOPLEFT", ed, "TOPLEFT", CARD_W / 2 + 10, y - 18)
    ed.main:SetAutoFocus(false)
    ed.main:SetMaxLetters(ns.MAX_MAIN)
    ed.main:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    ed.main:SetScript("OnTextChanged", function(self) if W.draft then W.draft.main = self:GetText() or "" end end)
    y = y - 44

    local roleLabel = Text(ed, "GameFontNormal")
    roleLabel:SetPoint("TOPLEFT", ed, "TOPLEFT", 4, y)
    roleLabel:SetText("Roles")
    ed.roles = {}
    for i, r in ipairs(ns.ROLES) do
        local cb = Frame("CheckButton", nil, ed, "UICheckButtonTemplate")
        cb:SetSize(22, 22)
        cb:SetPoint("TOPLEFT", ed, "TOPLEFT", 60 + (i - 1) * 100, y + 4)
        local icon = ed:CreateTexture(nil, "ARTWORK")
        icon:SetSize(16, 16)
        icon:SetTexture(ns.ROLE_ICON)
        icon:SetTexCoord(r.coords[1], r.coords[2], r.coords[3], r.coords[4])
        icon:SetPoint("LEFT", cb, "RIGHT", 2, 0)
        local label = Ink(Text(ed, "GameFontHighlightSmall"))
        label:SetPoint("LEFT", icon, "RIGHT", 3, 0)
        label:SetText(r.label)
        cb.key = r.key
        cb:SetScript("OnClick", function(self)
            if W.draft then W.draft.roles[self.key] = self:GetChecked() and true or nil end
        end)
        ed.roles[r.key] = cb
    end
    y = y - 28

    local tagLabel = Text(ed, "GameFontNormal")
    tagLabel:SetPoint("TOPLEFT", ed, "TOPLEFT", 4, y)
    tagLabel:SetText(("Playstyle & Focus (up to %d)"):format(ns.MAX_TAGS))
    ed.tagCount = Ink(Text(ed, "GameFontNormalSmall"))
    ed.tagCount:SetPoint("LEFT", tagLabel, "RIGHT", 8, 0)
    y = y - 18
    ed.tags = {}
    for i, t in ipairs(ns.TAGS) do
        local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
        local cb = Frame("CheckButton", nil, ed, "UICheckButtonTemplate")
        cb:SetSize(20, 20)
        cb:SetPoint("TOPLEFT", ed, "TOPLEFT", 4 + col * 184, y - row * 21)
        local icon = ed:CreateTexture(nil, "ARTWORK")
        icon:SetSize(14, 14)
        icon:SetTexture(t.icon)
        icon:SetPoint("LEFT", cb, "RIGHT", 1, 0)
        local label = Ink(Text(ed, "GameFontHighlightSmall"))
        label:SetPoint("LEFT", icon, "RIGHT", 3, 0)
        label:SetText(t.label)
        cb.key = t.key
        cb.label = label
        cb:SetScript("OnClick", function(self)
            if not W.draft then return end
            local list = W.draft.tags
            for k = #list, 1, -1 do if list[k] == self.key then table.remove(list, k) end end
            if self:GetChecked() then
                if #list >= ns.MAX_TAGS then
                    self:SetChecked(false)
                    ns.Print("up to %d tags", ns.MAX_TAGS)
                else
                    list[#list + 1] = self.key
                end
            end
            ns.RefreshEditor()
        end)
        ed.tags[t.key] = cb
    end
    y = y - math.ceil(#ns.TAGS / 2) * 21 - 4

    local hoursLabel = Text(ed, "GameFontNormal")
    hoursLabel:SetPoint("TOPLEFT", ed, "TOPLEFT", 4, y)
    hoursLabel:SetText("Active Playtime (server time)")
    -- fill the rows from the hours the addon has seen this account logged in
    ed.learned = Frame("Button", nil, ed, "UIPanelButtonTemplate")
    ed.learned:SetSize(96, 18)
    ed.learned:SetPoint("TOPRIGHT", ed, "TOPRIGHT", -4, y + 2)
    ed.learned:SetText("Use my hours")
    ed.learned:SetScript("OnClick", function()
        local learned, samples = ns.LearnedHours()
        if not W.draft then return end
        if not learned then
            ns.Print("not enough seen yet: %d of %d samples (one every ten minutes logged in)", samples or 0, ns.LEARN_MIN)
            return
        end
        W.draft.weekdays, W.draft.weekends = learned.weekdays, learned.weekends
        ns.RefreshEditor()
    end)
    ed.learned:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        local learned, samples = ns.LearnedHours()
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Use my hours")
        if learned then
            GameTooltip:AddLine(("Lights the hours this account has been logged in, from %d samples (one every ten minutes). You can still click cells afterwards."):format(samples), 1, 1, 1, true)
        else
            GameTooltip:AddLine(("Not enough seen yet: %d of %d samples (one every ten minutes logged in)."):format(samples or 0, ns.LEARN_MIN), 1, 1, 1, true)
        end
        GameTooltip:Show()
    end)
    ed.learned:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    y = y - 18
    ed.rows = {}
    for i, r in ipairs(CELL_ROWS) do
        local label = Ink(Text(ed, "GameFontHighlightSmall"))
        label:SetPoint("TOPLEFT", ed, "TOPLEFT", 4, y - 2 - (i - 1) * 20)
        label:SetText(r.label)
        local cells = {}
        for h = 0, 23 do
            cells[h] = EditCell(ed, 72 + h * 12, y - (i - 1) * 20, r.key, h)
        end
        ed.rows[r.key] = cells
    end
    y = y - 44

    local mottoLabel = Text(ed, "GameFontNormal")
    mottoLabel:SetPoint("TOPLEFT", ed, "TOPLEFT", 4, y)
    mottoLabel:SetText("Adventurer Motto")
    ed.mottoCount = Ink(Text(ed, "GameFontNormalSmall"))
    ed.mottoCount:SetPoint("LEFT", mottoLabel, "RIGHT", 8, 0)
    local box = Frame("Frame", nil, ed, "BackdropTemplate")
    box:SetPoint("TOPLEFT", ed, "TOPLEFT", 2, y - 18)
    box:SetPoint("TOPRIGHT", ed, "TOPRIGHT", -2, y - 18)
    box:SetHeight(64)
    Backdrop(box, INSET, 0.93, 0.87, 0.72, 0.9, 0.6, 0.45, 0.15)
    ed.motto = Frame("EditBox", nil, box)
    ed.motto:SetPoint("TOPLEFT", box, "TOPLEFT", 8, -6)
    ed.motto:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -8, 6)
    ed.motto:SetMultiLine(true)
    ed.motto:SetAutoFocus(false)
    ed.motto:SetMaxLetters(ns.MAX_MOTTO)
    if ed.motto.SetFontObject then ed.motto:SetFontObject("GameFontHighlight") end
    if ed.motto.SetTextColor then ed.motto:SetTextColor(ns.ERA.ink[1], ns.ERA.ink[2], ns.ERA.ink[3]) end
    ed.motto:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    ed.motto:SetScript("OnTextChanged", function(self)
        if not W.draft then return end
        W.draft.motto = self:GetText() or ""
        ed.mottoCount:SetText(("%d/%d"):format(ns.Utf8Len(W.draft.motto), ns.MAX_MOTTO))
    end)
    box:SetScript("OnMouseDown", function() if ed.motto.SetFocus then ed.motto:SetFocus() end end)

    ed.save = Frame("Button", nil, ed, "UIPanelButtonTemplate")
    ed.save:SetSize(100, 24)
    ed.save:SetPoint("BOTTOMRIGHT", ed, "BOTTOMRIGHT", -4, 2)
    ed.save:SetText("Save")
    ed.save:SetScript("OnClick", function() ns.SaveDraft() end)
    ed.cancel = Frame("Button", nil, ed, "UIPanelButtonTemplate")
    ed.cancel:SetSize(100, 24)
    ed.cancel:SetPoint("RIGHT", ed.save, "LEFT", -8, 0)
    ed.cancel:SetText("Cancel")
    ed.cancel:SetScript("OnClick", function() ns.ShowOwnPlate(false) end)
    ed:Hide()
    return ed
end

-- the model: drag to turn it, wheel to zoom, or hold Era's rotate buttons
local function Rotate(win, delta)
    win.facing = (win.facing or 0) + delta
    if win.model.SetFacing then pcall(win.model.SetFacing, win.model, win.facing) end
end

local function Zoom(win, delta)
    win.zoom = math.max(ZOOM_MIN, math.min(ZOOM_MAX, (win.zoom or 1) + delta))
    if win.model.SetCamDistanceScale then pcall(win.model.SetCamDistanceScale, win.model, win.zoom) end
end

local function RotateButton(win, pane, left)
    local b = Frame("Button", nil, pane)
    b:SetSize(32, 32)
    local up = left and ns.ERA.rotateLeftUp or ns.ERA.rotateRightUp
    local down = left and ns.ERA.rotateLeftDown or ns.ERA.rotateRightDown
    if ns.HasFile(up) then
        b:SetNormalTexture(up)
        b:SetPushedTexture(down)
        b:SetHighlightTexture(ns.ERA.rotateHighlight, "ADD")
    else
        b:SetText(left and "<" or ">")
    end
    b.dir = left and 1 or -1
    b:SetScript("OnMouseDown", function(self)
        self:SetScript("OnUpdate", function(_, elapsed) Rotate(win, self.dir * ROTATE_SPEED * (elapsed or 0)) end)
    end)
    b:SetScript("OnMouseUp", function(self) self:SetScript("OnUpdate", nil) end)
    b:SetScript("OnHide", function(self) self:SetScript("OnUpdate", nil) end)
    return b
end

local function BuildModelPane(win)
    local pane = Frame("Frame", nil, win, "BackdropTemplate")
    pane:SetPoint("TOPLEFT", win, "TOPLEFT", 24, TOP)
    pane:SetSize(WIDTH - CARD_W - 60, HEIGHT + TOP - 60)
    Backdrop(pane, INSET, 0.04, 0.05, 0.08, 0.95, 0.6, 0.45, 0.15)
    win.pane = pane
    win.classIcon = pane:CreateTexture(nil, "ARTWORK")
    win.classIcon:SetSize(128, 128)
    win.classIcon:SetPoint("CENTER", pane, "CENTER", 0, 30)
    win.classIcon:SetTexture(CLASS_SHEET)
    win.classNote = Text(pane, "GameFontDisableSmall")
    win.classNote:SetPoint("TOP", win.classIcon, "BOTTOM", 0, -8)
    win.classNote:SetText("out of range: no model")
    local model = Frame("PlayerModel", nil, pane)
    model:SetPoint("TOPLEFT", pane, "TOPLEFT", 4, -4)
    model:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", -4, 4)
    if model.EnableMouse then model:EnableMouse(true) end
    if model.EnableMouseWheel then model:EnableMouseWheel(true) end
    model:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        local x = Cursor()
        if not x then return end
        self.dragX = x
        self:SetScript("OnUpdate", function(s)
            local nx = Cursor()
            if nx and s.dragX then
                Rotate(win, (nx - s.dragX) * DRAG_SPEED)
                s.dragX = nx
            end
        end)
    end)
    model:SetScript("OnMouseUp", function(self) self.dragX = nil; self:SetScript("OnUpdate", nil) end)
    model:SetScript("OnHide", function(self) self.dragX = nil; self:SetScript("OnUpdate", nil) end)
    model:SetScript("OnMouseWheel", function(_, delta) Zoom(win, -(delta or 0) * 0.1) end)
    win.model = model
    win.rotateLeft = RotateButton(win, pane, true)
    win.rotateLeft:SetPoint("BOTTOMLEFT", pane, "BOTTOMLEFT", 8, 6)
    win.rotateRight = RotateButton(win, pane, false)
    win.rotateRight:SetPoint("LEFT", win.rotateLeft, "RIGHT", -6, 0)
    if win.rotateLeft.SetFrameLevel and model.GetFrameLevel then
        win.rotateLeft:SetFrameLevel(model:GetFrameLevel() + 2)
        win.rotateRight:SetFrameLevel(model:GetFrameLevel() + 2)
    end
    return pane
end

local function BuildWindow()
    local win = ns.BuildEraPage("AdventurePlatesFrame", UIParent)
    win:SetSize(WIDTH, HEIGHT)
    win:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    if win.SetFrameStrata then win:SetFrameStrata("HIGH") end
    if win.SetMovable then win:SetMovable(true) end
    if win.EnableMouse then win:EnableMouse(true) end
    if win.RegisterForDrag then win:RegisterForDrag("LeftButton") end
    win:SetScript("OnDragStart", function(self) if self.StartMoving then self:StartMoving() end end)
    win:SetScript("OnDragStop", function(self) if self.StopMovingOrSizing then self:StopMovingOrSizing() end end)
    if win.SetClampedToScreen then win:SetClampedToScreen(true) end
    if UISpecialFrames then table.insert(UISpecialFrames, "AdventurePlatesFrame") end

    win.heading = Text(win, "GameFontNormal")
    win.heading:SetPoint("TOP", win, "TOP", 0, -18)
    win.heading:SetText("Adventure Plates")
    win.sub = Text(win, "GameFontHighlightSmall")
    win.sub:SetPoint("TOP", win.heading, "BOTTOM", 0, -4)
    win.close = ns.EraCloseButton(win, function() win:Hide() end)

    BuildModelPane(win)
    win.card = BuildCard(win)
    win.editor = BuildEditor(win)
    win:Hide()
    return win
end

local function Window()
    if not W then
        W = BuildWindow()
        ns.window = W
    end
    return W
end

--------------------------------------------------------------------------
-- filling the card
--------------------------------------------------------------------------

-- a unit who is this plate's player (name and realm), if one is in range
local function UnitFor(plate, hint)
    local units = {hint, "target", "mouseover", "focus", "party1", "party2", "party3", "party4"}
    local want = ((plate.name or "") .. "-" .. (plate.realm ~= "" and plate.realm or ns.RealmName())):lower()
    for _, u in ipairs(units) do
        if u then
            local name, realm = Call(UnitName, u)
            if type(name) == "string" and Call(UnitIsPlayer, u) then
                local full = name .. "-" .. ((type(realm) == "string" and realm ~= "") and realm or ns.RealmName())
                if full:lower() == want then return u end
            end
        end
    end
end

local function ShowModel(win, plate, own, hint)
    local unit = own and "player" or UnitFor(plate, hint)
    win.facing, win.zoom = 0, 1
    if unit and win.model.SetUnit then
        local ok = pcall(win.model.SetUnit, win.model, unit)
        if ok then
            Rotate(win, 0)
            Zoom(win, 0)
            win.model:Show()
            win.rotateLeft:Show()
            win.rotateRight:Show()
            win.classIcon:Hide()
            win.classNote:Hide()
            return true
        end
    end
    win.model:Hide()
    win.rotateLeft:Hide()
    win.rotateRight:Hide()
    local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[plate.classFile]
    if coords then
        win.classIcon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
        win.classIcon:Show()
    else
        win.classIcon:Hide()
    end
    win.classNote:Show()
    return false
end

-- the ring on the header band: the player's own face, or the class icon
local function ShowRing(win, plate, own)
    local p = win.portrait
    if own and SetPortraitTexture then
        if pcall(SetPortraitTexture, p, "player") then
            p:SetTexCoord(0, 1, 0, 1)
            p:Show()
            return
        end
    end
    local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[plate.classFile]
    if coords then
        p:SetTexture(CLASS_SHEET)
        p:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
        p:Show()
    else
        p:Hide()
    end
end

local function FillCard(card, plate, own, cachedAt)
    card.name:SetText(plate.name ~= "" and plate.name or "?")
    if plate.title ~= "" then
        card.title:SetText(("« %s »"):format(plate.title))
        card.title:SetTextColor(ns.ERA.gold[1], ns.ERA.gold[2], ns.ERA.gold[3])
    elseif plate.gameTitle ~= "" then
        card.title:SetText(plate.gameTitle)
        card.title:SetTextColor(ns.ERA.brown[1], ns.ERA.brown[2], ns.ERA.brown[3])
    else
        card.title:SetText(" ")
    end
    if plate.guild ~= "" then
        card.guild:SetText(("<%s>%s"):format(plate.guild, plate.rank ~= "" and (" - " .. plate.rank) or ""))
    else
        card.guild:SetText("No guild")
    end
    local parts = {}
    if plate.level and plate.level > 0 then parts[#parts + 1] = "Level " .. plate.level end
    if plate.race ~= "" then parts[#parts + 1] = plate.race end
    if plate.class ~= "" then parts[#parts + 1] = plate.class end
    card.line:SetText(table.concat(parts, " "))
    card.line:SetTextColor(ClassColor(plate.classFile))
    local profs = {}
    for _, p in ipairs(plate.profs or {}) do
        profs[#profs + 1] = p.max and p.max > 0 and ("%s %d/%d"):format(p.name, p.skill or 0, p.max) or p.name
    end
    card.profs:SetText(#profs > 0 and table.concat(profs, "  -  ") or "")
    if plate.main and plate.main ~= "" then
        local main = plate.main
        if not main:find("-", 1, true) then main = main .. "-" .. (plate.realm ~= "" and plate.realm or ns.RealmName()) end
        W.mainKey = ns.FullName(main)
        card.alt.text:SetText("Alt of " .. plate.main)
        card.alt:Show()
    else
        W.mainKey = nil
        card.alt:Hide()
    end
    for _, r in ipairs(ns.ROLES) do
        if plate.roles and plate.roles[r.key] then card.roles[r.key]:Show() else card.roles[r.key]:Hide() end
    end
    for i = 1, ns.MAX_TAGS do
        local key = plate.tags and plate.tags[i]
        local tag = key and ns.TAG_BY_KEY[key]
        local slot = card.tags[i]
        if tag then
            slot.icon:SetTexture(tag.icon)
            slot.icon:Show()
            slot.label:SetText(tag.label)
        else
            slot.icon:Hide()
            slot.label:SetText(i == 1 and "(nothing picked yet)" or "")
        end
    end
    card.looking:SetText(plate.looking ~= "" and plate.looking or "-")
    local hour, weekend = ns.ServerNow()
    -- on someone else's plate, the hours you both play are green
    local mine = not own and ns.db and ns.db.plates[ns.CharKey()]
    local overlap = false
    for _, r in ipairs(CELL_ROWS) do
        local row = card.rows[r.key]
        local s = ns.CleanHours(plate[r.key])
        local m = mine and ns.CleanHours(mine[r.key])
        for h = 0, 23 do
            local on = s:sub(h + 1, h + 1) == "1"
            local both = on and m and m:sub(h + 1, h + 1) == "1"
            if both then row.cells[h]:SetColorTexture(BOTH[1], BOTH[2], BOTH[3], 1); overlap = true
            elseif on then row.cells[h]:SetColorTexture(LIT[1], LIT[2], LIT[3], 1)
            else row.cells[h]:SetColorTexture(DIM[1], DIM[2], DIM[3], 1) end
        end
        local today = (r.key == "weekends") == weekend
        if today and row.cells[hour] then
            row.now:ClearAllPoints()
            row.now:SetPoint("CENTER", row.cells[hour], "CENTER", 0, 0)
            row.now:Show()
        else
            row.now:Hide()
        end
    end
    if overlap then card.overlap:Show() else card.overlap:Hide() end
    card.motto:SetText(plate.motto ~= "" and ('"%s"'):format(plate.motto) or "")
    if own then
        card.stamp:SetText("This is what other players see.")
        card.edit:Show()
        card.share:Show()
        card.ask:Hide()
    else
        if cachedAt and cachedAt > 0 and date then
            card.stamp:SetText("as of " .. (Call(date, "%d %b %H:%M", cachedAt) or ""))
        else
            card.stamp:SetText("")
        end
        card.edit:Hide()
        card.share:Hide()
        card.ask:Show()
    end
end

function ns.ShowPlate(plate, opts)
    opts = opts or {}
    local win = Window()
    local own = opts.own == true
    W.key, W.unit, W.own = opts.key, opts.unit, own
    win.editor:Hide()
    win.card:Show()
    win.sub:SetText(("%s - %s"):format(plate.name ~= "" and plate.name or "?", plate.realm ~= "" and plate.realm or ns.RealmName()))
    FillCard(win.card, plate, own, opts.cached)
    ShowModel(win, plate, own, opts.unit)
    ShowRing(win, plate, own)
    win:Show()
    return win
end

function ns.ShowOwnPlate(edit)
    local plate = ns.MyPlate()
    ns.ShowPlate(plate, {own = true, key = ns.CharKey()})
    if edit then ns.OpenEditor() end
    return plate
end

function ns.TogglePlate()
    if W and W.shown and W:IsShown() and W.own then W:Hide() else ns.ShowOwnPlate() end
end

--------------------------------------------------------------------------
-- the editor
--------------------------------------------------------------------------

local function CopyPlate(p)
    local d = ns.NewPlate()
    d.title, d.motto = p.title or "", p.motto or ""
    d.looking, d.main = p.looking or "", p.main or ""
    d.weekdays, d.weekends = ns.CleanHours(p.weekdays), ns.CleanHours(p.weekends)
    for _, k in ipairs(p.tags or {}) do d.tags[#d.tags + 1] = k end
    for k, v in pairs(p.roles or {}) do d.roles[k] = v end
    return d
end

function ns.RefreshEditor()
    local win = Window()
    local ed, d = win.editor, W.draft
    if not d then return end
    local picked = {}
    for _, k in ipairs(d.tags) do picked[k] = true end
    for key, cb in pairs(ed.tags) do cb:SetChecked(picked[key] == true) end
    ed.tagCount:SetText(("%d/%d"):format(#d.tags, ns.MAX_TAGS))
    for key, cb in pairs(ed.roles) do cb:SetChecked(d.roles[key] == true) end
    for _, r in ipairs(CELL_ROWS) do
        local s = d[r.key]
        for h = 0, 23 do
            local on = s:sub(h + 1, h + 1) == "1"
            local c = ed.rows[r.key][h].fill
            if on then c:SetColorTexture(LIT[1], LIT[2], LIT[3], 1) else c:SetColorTexture(DIM[1], DIM[2], DIM[3], 1) end
        end
    end
    ed.mottoCount:SetText(("%d/%d"):format(ns.Utf8Len(d.motto or ""), ns.MAX_MOTTO))
    -- the button stays live either way (a disabled button shows no tooltip); it says why when it cannot
    local learned = ns.LearnedHours()
    ed.learned:SetText(learned and "Use my hours" or "Use my hours?")
end

function ns.OpenEditor()
    local win = Window()
    local plate = ns.MyPlate()
    W.draft = CopyPlate(plate)
    local ed = win.editor
    ed.title:SetText(W.draft.title)
    ed.looking:SetText(W.draft.looking)
    ed.main:SetText(W.draft.main)
    ed.motto:SetText(W.draft.motto)
    ns.RefreshEditor()
    win.card:Hide()
    ed:Show()
    win:Show()
end

function ns.SaveDraft()
    local d = W and W.draft
    if not d then return end
    local plate = ns.MyPlate()
    local clean = ns.CleanPlate(d)
    plate.title, plate.motto = clean.title, clean.motto
    plate.looking, plate.main = clean.looking, clean.main
    plate.tags, plate.roles = clean.tags, clean.roles
    plate.weekdays, plate.weekends = clean.weekdays, clean.weekends
    W.draft = nil
    ns.Print("plate saved")
    ns.ShowOwnPlate(false)
end

--------------------------------------------------------------------------
-- the entry on a player's right-click menu, and on your own portrait
--------------------------------------------------------------------------

-- not the enemy player menu: addon whispers do not cross factions
local MENUS = {"MENU_UNIT_PLAYER", "MENU_UNIT_PARTY", "MENU_UNIT_RAID_PLAYER", "MENU_UNIT_FRIEND", "MENU_UNIT_GUILD", "MENU_UNIT_COMMUNITIES_GUILD_MEMBER"}
local SELF_MENUS = {"MENU_UNIT_SELF"}

function ns.InstallMenu()
    if ns.menuInstalled or not ns.db.settings.menu then return end
    if not (Menu and Menu.ModifyMenu) then return end
    for _, tag in ipairs(MENUS) do
        pcall(Menu.ModifyMenu, tag, function(owner, root, context)
            if not (ns.db and ns.db.settings.menu) or type(context) ~= "table" then return end
            local name = context.name
            if type(name) ~= "string" or name == "" then return end
            if type(context.server) == "string" and context.server ~= "" then name = name .. "-" .. context.server end
            if root.CreateDivider then root:CreateDivider() end
            root:CreateButton("View Adventure Plate", function()
                ns.RequestPlate(ns.FullName(name), context.unit)
            end)
        end)
    end
    for _, tag in ipairs(SELF_MENUS) do
        pcall(Menu.ModifyMenu, tag, function(owner, root)
            if not (ns.db and ns.db.settings.menu) then return end
            if root.CreateDivider then root:CreateDivider() end
            root:CreateButton("View My Adventure Plate", function() ns.ShowOwnPlate() end)
            root:CreateButton("Edit My Adventure Plate", function() ns.ShowOwnPlate(true) end)
        end)
    end
    ns.menuInstalled = true
end

--------------------------------------------------------------------------
-- the welcome, the first time the addon runs on an account
--------------------------------------------------------------------------

local WELCOME = {
    "Thank you for installing Adventure Plates.",
    "",
    "An adventurer plate is a card about your character: who you are, what you like doing in Azeroth, when you are usually on, and a line of your own. Anyone with the addon can open yours, and you can open theirs.",
    "",
    "|cffffd100/plate|r opens your plate and |cffffd100Edit My Plate|r fills it in. Right-click your own portrait for the same.",
    "|cffffd100/plate <name>|r, |cffffd100/plate target|r, or |cffffd100View Adventure Plate|r on a player's right-click menu shows someone else's.",
    "The minimap button opens your plate with a left click and the settings with a right click.",
    "|cffffd100Share in Chat|r puts a link to your plate in the chat box; anyone with the addon can click it.",
    "The addon notes the hours you are logged in, so |cffffd100Use my hours|r in the editor can fill the playtime rows for you (off in the settings if you would rather not).",
    "",
    "Who may look at your plate is up to you: everyone, only friends, guildmates and your group, or nobody. It is in the settings.",
    "",
    "Something wrong, or an idea? |cffffd100/plate report|r opens a report to paste as a comment on the CurseForge page, or to email to |cffffd100classicuiforforever@gmail.com|r. Suggestions are welcome the same way.",
    "",
    "Inspired by Final Fantasy XIV's adventurer plates, and by the streamer Shobek (@Shobektv) asking for them in World of Warcraft Forever."
}
ns.WELCOME_LINES = WELCOME

local function BuildWelcome()
    local f = ns.BuildEraPage("AdventurePlatesWelcome", UIParent)
    f:SetSize(500, 560)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    if f.SetFrameStrata then f:SetFrameStrata("DIALOG") end
    if f.SetMovable then f:SetMovable(true) end
    if f.EnableMouse then f:EnableMouse(true) end
    if f.RegisterForDrag then f:RegisterForDrag("LeftButton") end
    f:SetScript("OnDragStart", function(self) if self.StartMoving then self:StartMoving() end end)
    f:SetScript("OnDragStop", function(self) if self.StopMovingOrSizing then self:StopMovingOrSizing() end end)
    if UISpecialFrames then table.insert(UISpecialFrames, "AdventurePlatesWelcome") end
    f.heading = Text(f, "GameFontNormal")
    f.heading:SetPoint("TOP", f, "TOP", 0, -18)
    f.heading:SetText("Adventure Plates")
    if SetPortraitTexture then
        if pcall(SetPortraitTexture, f.portrait, "player") then f.portrait:Show() else f.portrait:Hide() end
    end
    f.body = Ink(Text(f, "GameFontHighlight"))
    f.body:SetPoint("TOPLEFT", f, "TOPLEFT", 28, TOP)
    f.body:SetWidth(444)
    f.body:SetJustifyH("LEFT")
    f.body:SetJustifyV("TOP")
    if f.body.SetWordWrap then f.body:SetWordWrap(true) end
    f.body:SetText(table.concat(WELCOME, "\n"))
    f.open = Frame("Button", nil, f, "UIPanelButtonTemplate")
    f.open:SetSize(130, 24)
    f.open:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 28, 56)
    f.open:SetText("Open my plate")
    f.open:SetScript("OnClick", function() ns.ShowOwnPlate(true) end)
    f.report = Frame("Button", nil, f, "UIPanelButtonTemplate")
    f.report:SetSize(110, 24)
    f.report:SetPoint("LEFT", f.open, "RIGHT", 8, 0)
    f.report:SetText("Report a bug")
    f.report:SetScript("OnClick", function() ns.ShowReport() end)
    f.close = Frame("Button", nil, f, "UIPanelButtonTemplate")
    f.close:SetSize(100, 24)
    f.close:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -44, 56)
    f.close:SetText("Got it")
    f.close:SetScript("OnClick", function()
        ns.db.settings.welcomed = true
        f:Hide()
    end)
    f.x = ns.EraCloseButton(f, function() ns.db.settings.welcomed = true; f:Hide() end)
    return f
end

function ns.ShowWelcome()
    if not (CreateFrame and UIParent) then return end
    ns.welcomeFrame = ns.welcomeFrame or BuildWelcome()
    ns.welcomeFrame:Show()
    return ns.welcomeFrame
end

--------------------------------------------------------------------------
-- the minimap button
--------------------------------------------------------------------------

local ICON = "Interface\\Icons\\INV_Misc_Map02"
local RING = "Interface\\Minimap\\MiniMap-TrackingBorder"
local RING_FALLBACK = "Interface\\Minimap\\UI-Minimap-Border"
local HIGHLIGHT = "Interface\\Buttons\\ButtonHilight-Square"
local DEFAULT_ANGLE = 160
local RADIUS = 80

local function Angle()
    return tonumber(ns.db and ns.db.settings.minimapAngle) or DEFAULT_ANGLE
end

local function PlaceButton(button)
    local a = math.rad(Angle())
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", RADIUS * math.cos(a), RADIUS * math.sin(a))
end

local function DragUpdate(button)
    if not (GetCursorPosition and Minimap and Minimap.GetCenter) then return end
    local mx, my = Minimap:GetCenter()
    local cx, cy = Cursor()
    if not (mx and cx) then return end
    ns.db.settings.minimapAngle = math.deg(math.atan2(cy - my, cx - mx))
    PlaceButton(button)
end

local function BuildMinimapButton()
    if not (CreateFrame and Minimap) then return end
    local b = CreateFrame("Button", "AdventurePlatesMinimapButton", Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    if b.SetFrameLevel and Minimap.GetFrameLevel then b:SetFrameLevel(Minimap:GetFrameLevel() + 8) end
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetTexture(ICON)
    b.icon:SetSize(20, 20)
    b.icon:SetPoint("CENTER", b, "CENTER", 0, 1)
    b.ring = b:CreateTexture(nil, "OVERLAY")
    b.ring:SetTexture(ns.HasFile(RING) and RING or RING_FALLBACK)
    b.ring:SetSize(53, 53)
    b.ring:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
    b:SetHighlightTexture(HIGHLIGHT, "ADD")
    b:SetScript("OnClick", ns.Guard("minimap click", function(_, mouse)
        if mouse == "RightButton" then
            if ns.OpenOptions then ns.OpenOptions() end
        else
            ns.TogglePlate()
        end
    end))
    b:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", ns.Guard("minimap drag", DragUpdate))
    end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    b:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Adventure Plates")
        GameTooltip:AddLine("Left click: your plate")
        GameTooltip:AddLine("Right click: settings")
        GameTooltip:AddLine("Drag: move me round the minimap")
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    PlaceButton(b)
    return b
end

function ns.SetMinimapButton(on)
    if ns.db then ns.db.settings.minimap = on and true or false end
    if ns.optionsPanel and ns.optionsPanel.Refresh then ns.optionsPanel.Refresh() end
    if on then
        ns.minimapButton = ns.minimapButton or BuildMinimapButton()
        if ns.minimapButton then
            PlaceButton(ns.minimapButton)
            ns.minimapButton:Show()
        end
    elseif ns.minimapButton then
        ns.minimapButton:Hide()
    end
    return ns.minimapButton
end
