-- Adventure Plates - the plate window and its editor
--
-- One window: the character's model down the left, the card down the
-- right. The card shows the name in orange with the flavour title under
-- it in quotes, the guild and rank, "Level 14 Night Elf Druid" in the
-- class colour, the roles as the LFG role icons top right, up to four
-- playstyle tags with their icons, the two playtime rows (24 cells each,
-- lit for the hours they play, the current server hour outlined), and
-- the motto in a box. "Edit My Plate" turns the card into the editor:
-- a title box, role and tag checkboxes, clickable hour cells, a motto
-- box, Save and Cancel. Another player's plate shows the same card with
-- their model if they are in range (targeted, moused over, in the group)
-- and their class icon if not.

local addonName, ns = ...

local WIDTH, HEIGHT = 740, 520
local CARD_W = 372
local CELL, GAP = 10, 1
local CELL_ROWS = {{key = "weekdays", label = "Weekdays"}, {key = "weekends", label = "Weekends"}}
local GOLD = {1, 0.82, 0}
local ORANGE = {1, 0.5, 0}
local LIT = {0.95, 0.75, 0.1}
local DIM = {0.16, 0.16, 0.18}
local ROLE_SIZE = 20
local TITLE_ICON = "Interface\\Icons\\INV_Misc_Map02"
local CLASS_SHEET = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"

local BACKDROP = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = {left = 4, right = 4, top = 4, bottom = 4}
}
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

local function Backdrop(f, def, r, g, b, a)
    if not f.SetBackdrop then return end
    pcall(f.SetBackdrop, f, def)
    if f.SetBackdropColor then pcall(f.SetBackdropColor, f, r or 0, g or 0, b or 0, a or 0.9) end
end

local function Text(parent, font, layer)
    return parent:CreateFontString(nil, layer or "ARTWORK", font or "GameFontHighlight")
end

local function Line(parent, y)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.6)
    t:SetHeight(1)
    t:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, y)
    t:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -12, y)
    return t
end

local function ClassColor(classFile)
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    if c then return c.r, c.g, c.b end
    return GOLD[1], GOLD[2], GOLD[3]
end

-- server time: the hour now, and whether today is a weekend
local function ServerNow()
    local hour = Call(GetGameTime) or 0
    local weekend = false
    if C_DateAndTime and C_DateAndTime.GetCurrentCalendarTime then
        local t = Call(C_DateAndTime.GetCurrentCalendarTime)
        if type(t) == "table" and t.weekday then weekend = t.weekday == 1 or t.weekday == 7 end
    end
    return hour, weekend
end

--------------------------------------------------------------------------
-- building
--------------------------------------------------------------------------

local W -- the window

local function HourRow(parent, y, label)
    local row = {}
    row.label = Text(parent, "GameFontHighlightSmall")
    row.label:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, y)
    row.label:SetText(label)
    row.cells = {}
    for h = 0, 23 do
        local c = parent:CreateTexture(nil, "ARTWORK")
        c:SetSize(CELL, CELL)
        c:SetPoint("TOPLEFT", parent, "TOPLEFT", 80 + h * (CELL + GAP), y + 1)
        c:SetColorTexture(DIM[1], DIM[2], DIM[3], 1)
        row.cells[h] = c
    end
    row.now = parent:CreateTexture(nil, "OVERLAY")
    row.now:SetSize(CELL + 2, CELL + 2)
    row.now:SetColorTexture(1, 1, 1, 0.35)
    row.now:Hide()
    return row
end

local function BuildCard(win)
    local card = Frame("Frame", nil, win, "BackdropTemplate")
    card:SetSize(CARD_W, HEIGHT - 90)
    card:SetPoint("TOPRIGHT", win, "TOPRIGHT", -18, -58)
    Backdrop(card, INSET, 0.02, 0.02, 0.03, 0.85)

    card.name = Text(card, "GameFontNormalHuge")
    card.name:SetPoint("TOPLEFT", card, "TOPLEFT", 14, -12)
    card.name:SetTextColor(ORANGE[1], ORANGE[2], ORANGE[3])
    card.title = Text(card, "GameFontNormalSmall")
    card.title:SetPoint("TOPLEFT", card.name, "BOTTOMLEFT", 0, -2)
    card.guild = Text(card, "GameFontHighlight")
    card.guild:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -4)
    card.line = Text(card, "GameFontNormal")
    card.line:SetPoint("TOPLEFT", card.guild, "BOTTOMLEFT", 0, -4)
    card.roles = {}
    for i, r in ipairs(ns.ROLES) do
        local t = card:CreateTexture(nil, "ARTWORK")
        t:SetSize(ROLE_SIZE, ROLE_SIZE)
        t:SetTexture(ns.ROLE_ICON)
        t:SetTexCoord(r.coords[1], r.coords[2], r.coords[3], r.coords[4])
        t:SetPoint("TOPRIGHT", card, "TOPRIGHT", -14 - (i - 1) * (ROLE_SIZE + 4), -14)
        t:Hide()
        card.roles[r.key] = t
    end
    Line(card, -96)

    card.tagsHeader = Text(card, "GameFontNormal")
    card.tagsHeader:SetPoint("TOPLEFT", card, "TOPLEFT", 14, -104)
    card.tagsHeader:SetText("Playstyle & Focus")
    card.tags = {}
    for i = 1, ns.MAX_TAGS do
        local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
        local icon = card:CreateTexture(nil, "ARTWORK")
        icon:SetSize(18, 18)
        icon:SetPoint("TOPLEFT", card, "TOPLEFT", 14 + col * 176, -126 - row * 26)
        local label = Text(card, "GameFontHighlight")
        label:SetPoint("LEFT", icon, "RIGHT", 6, 0)
        card.tags[i] = {icon = icon, label = label}
    end
    Line(card, -184)

    card.hoursHeader = Text(card, "GameFontNormal")
    card.hoursHeader:SetPoint("TOPLEFT", card, "TOPLEFT", 14, -192)
    card.hoursHeader:SetText("Active Playtime (Server Time)")
    local marks = {{0, "12:00 a.m."}, {12, "12:00 p.m."}, {24, "24:00"}}
    card.marks = {}
    for i, m in ipairs(marks) do
        local t = Text(card, "GameFontDisableSmall")
        local x = 80 + m[1] * (CELL + GAP)
        if m[1] == 0 then t:SetPoint("TOPLEFT", card, "TOPLEFT", x, -212)
        elseif m[1] == 24 then t:SetPoint("TOPRIGHT", card, "TOPLEFT", x, -212)
        else t:SetPoint("TOP", card, "TOPLEFT", x, -212) end
        t:SetText(m[2])
        card.marks[i] = t
    end
    card.rows = {}
    for i, r in ipairs(CELL_ROWS) do
        card.rows[r.key] = HourRow(card, -228 - (i - 1) * 18, r.label)
    end
    Line(card, -272)

    card.mottoHeader = Text(card, "GameFontNormal")
    card.mottoHeader:SetPoint("TOPLEFT", card, "TOPLEFT", 14, -280)
    card.mottoHeader:SetText("Adventurer Motto")
    card.mottoBox = Frame("Frame", nil, card, "BackdropTemplate")
    card.mottoBox:SetPoint("TOPLEFT", card, "TOPLEFT", 12, -298)
    card.mottoBox:SetPoint("TOPRIGHT", card, "TOPRIGHT", -12, -298)
    card.mottoBox:SetHeight(72)
    Backdrop(card.mottoBox, INSET, 0.05, 0.05, 0.06, 0.9)
    card.motto = Text(card.mottoBox, "GameFontHighlight")
    card.motto:SetPoint("TOPLEFT", card.mottoBox, "TOPLEFT", 10, -8)
    card.motto:SetPoint("BOTTOMRIGHT", card.mottoBox, "BOTTOMRIGHT", -10, 8)
    card.motto:SetJustifyH("LEFT")
    card.motto:SetJustifyV("TOP")
    if card.motto.SetWordWrap then card.motto:SetWordWrap(true) end

    card.stamp = Text(card, "GameFontDisableSmall")
    card.stamp:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 14, 14)

    card.edit = Frame("Button", nil, card, "UIPanelButtonTemplate")
    card.edit:SetSize(130, 24)
    card.edit:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -14, 12)
    card.edit:SetText("Edit My Plate")
    card.edit:SetScript("OnClick", function() ns.ShowOwnPlate(true) end)

    card.ask = Frame("Button", nil, card, "UIPanelButtonTemplate")
    card.ask:SetSize(110, 24)
    card.ask:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -14, 12)
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
    local ed = Frame("Frame", nil, win, "BackdropTemplate")
    ed:SetSize(CARD_W, HEIGHT - 90)
    ed:SetPoint("TOPRIGHT", win, "TOPRIGHT", -18, -58)
    Backdrop(ed, INSET, 0.02, 0.02, 0.03, 0.9)
    if ed.SetFrameLevel and win.GetFrameLevel then ed:SetFrameLevel(win:GetFrameLevel() + 5) end

    local y = -12
    local titleLabel = Text(ed, "GameFontNormal")
    titleLabel:SetPoint("TOPLEFT", ed, "TOPLEFT", 14, y)
    titleLabel:SetText("Flavour title (shown under your name)")
    ed.title = Frame("EditBox", nil, ed, "InputBoxTemplate")
    ed.title:SetSize(CARD_W - 40, 20)
    ed.title:SetPoint("TOPLEFT", ed, "TOPLEFT", 20, y - 18)
    ed.title:SetAutoFocus(false)
    ed.title:SetMaxLetters(ns.MAX_TITLE)
    ed.title:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    ed.title:SetScript("OnTextChanged", function(self) W.draft.title = self:GetText() or "" end)
    y = y - 46

    local roleLabel = Text(ed, "GameFontNormal")
    roleLabel:SetPoint("TOPLEFT", ed, "TOPLEFT", 14, y)
    roleLabel:SetText("Roles")
    ed.roles = {}
    for i, r in ipairs(ns.ROLES) do
        local cb = Frame("CheckButton", nil, ed, "UICheckButtonTemplate")
        cb:SetSize(22, 22)
        cb:SetPoint("TOPLEFT", ed, "TOPLEFT", 70 + (i - 1) * 100, y + 4)
        local icon = ed:CreateTexture(nil, "ARTWORK")
        icon:SetSize(16, 16)
        icon:SetTexture(ns.ROLE_ICON)
        icon:SetTexCoord(r.coords[1], r.coords[2], r.coords[3], r.coords[4])
        icon:SetPoint("LEFT", cb, "RIGHT", 2, 0)
        local label = Text(ed, "GameFontHighlightSmall")
        label:SetPoint("LEFT", icon, "RIGHT", 3, 0)
        label:SetText(r.label)
        cb.key = r.key
        cb:SetScript("OnClick", function(self)
            W.draft.roles[self.key] = self:GetChecked() and true or nil
        end)
        ed.roles[r.key] = cb
    end
    y = y - 30

    local tagLabel = Text(ed, "GameFontNormal")
    tagLabel:SetPoint("TOPLEFT", ed, "TOPLEFT", 14, y)
    tagLabel:SetText(("Playstyle & Focus (up to %d)"):format(ns.MAX_TAGS))
    ed.tagCount = Text(ed, "GameFontDisableSmall")
    ed.tagCount:SetPoint("LEFT", tagLabel, "RIGHT", 8, 0)
    y = y - 18
    ed.tags = {}
    for i, t in ipairs(ns.TAGS) do
        local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
        local cb = Frame("CheckButton", nil, ed, "UICheckButtonTemplate")
        cb:SetSize(20, 20)
        cb:SetPoint("TOPLEFT", ed, "TOPLEFT", 14 + col * 176, y - row * 21)
        local icon = ed:CreateTexture(nil, "ARTWORK")
        icon:SetSize(14, 14)
        icon:SetTexture(t.icon)
        icon:SetPoint("LEFT", cb, "RIGHT", 1, 0)
        local label = Text(ed, "GameFontHighlightSmall")
        label:SetPoint("LEFT", icon, "RIGHT", 3, 0)
        label:SetText(t.label)
        cb.key = t.key
        cb.label = label
        cb:SetScript("OnClick", function(self)
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
    y = y - math.ceil(#ns.TAGS / 2) * 21 - 6

    local hoursLabel = Text(ed, "GameFontNormal")
    hoursLabel:SetPoint("TOPLEFT", ed, "TOPLEFT", 14, y)
    hoursLabel:SetText("Active Playtime (server time, click the hours)")
    y = y - 18
    ed.rows = {}
    for i, r in ipairs(CELL_ROWS) do
        local label = Text(ed, "GameFontHighlightSmall")
        label:SetPoint("TOPLEFT", ed, "TOPLEFT", 14, y - 2 - (i - 1) * 20)
        label:SetText(r.label)
        local cells = {}
        for h = 0, 23 do
            cells[h] = EditCell(ed, 80 + h * 12, y - (i - 1) * 20, r.key, h)
        end
        ed.rows[r.key] = cells
    end
    y = y - 44

    local mottoLabel = Text(ed, "GameFontNormal")
    mottoLabel:SetPoint("TOPLEFT", ed, "TOPLEFT", 14, y)
    mottoLabel:SetText("Adventurer Motto")
    ed.mottoCount = Text(ed, "GameFontDisableSmall")
    ed.mottoCount:SetPoint("LEFT", mottoLabel, "RIGHT", 8, 0)
    local box = Frame("Frame", nil, ed, "BackdropTemplate")
    box:SetPoint("TOPLEFT", ed, "TOPLEFT", 12, y - 18)
    box:SetPoint("TOPRIGHT", ed, "TOPRIGHT", -12, y - 18)
    box:SetHeight(58)
    Backdrop(box, INSET, 0.05, 0.05, 0.06, 0.9)
    ed.motto = Frame("EditBox", nil, box)
    ed.motto:SetPoint("TOPLEFT", box, "TOPLEFT", 8, -6)
    ed.motto:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -8, 6)
    ed.motto:SetMultiLine(true)
    ed.motto:SetAutoFocus(false)
    ed.motto:SetMaxLetters(ns.MAX_MOTTO)
    if ed.motto.SetFontObject then ed.motto:SetFontObject("GameFontHighlight") end
    ed.motto:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    ed.motto:SetScript("OnTextChanged", function(self)
        W.draft.motto = self:GetText() or ""
        ed.mottoCount:SetText(("%d/%d"):format(#W.draft.motto, ns.MAX_MOTTO))
    end)
    box:SetScript("OnMouseDown", function() if ed.motto.SetFocus then ed.motto:SetFocus() end end)

    ed.save = Frame("Button", nil, ed, "UIPanelButtonTemplate")
    ed.save:SetSize(100, 24)
    ed.save:SetPoint("BOTTOMRIGHT", ed, "BOTTOMRIGHT", -14, 12)
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

local function BuildWindow()
    local win = Frame("Frame", "AdventurePlatesFrame", UIParent, "BackdropTemplate")
    win:SetSize(WIDTH, HEIGHT)
    win:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    Backdrop(win, BACKDROP, 0.05, 0.04, 0.03, 0.95)
    if win.SetFrameStrata then win:SetFrameStrata("HIGH") end
    if win.SetMovable then win:SetMovable(true) end
    if win.EnableMouse then win:EnableMouse(true) end
    if win.RegisterForDrag then win:RegisterForDrag("LeftButton") end
    win:SetScript("OnDragStart", function(self) if self.StartMoving then self:StartMoving() end end)
    win:SetScript("OnDragStop", function(self) if self.StopMovingOrSizing then self:StopMovingOrSizing() end end)
    if win.SetClampedToScreen then win:SetClampedToScreen(true) end
    if UISpecialFrames then table.insert(UISpecialFrames, "AdventurePlatesFrame") end

    win.icon = win:CreateTexture(nil, "ARTWORK")
    win.icon:SetSize(34, 34)
    win.icon:SetPoint("TOPLEFT", win, "TOPLEFT", 16, -12)
    win.icon:SetTexture(TITLE_ICON)
    win.heading = Text(win, "GameFontNormalLarge")
    win.heading:SetPoint("TOPLEFT", win.icon, "TOPRIGHT", 8, -2)
    win.heading:SetText("Adventure Plates")
    win.sub = Text(win, "GameFontHighlightSmall")
    win.sub:SetPoint("TOPLEFT", win.heading, "BOTTOMLEFT", 0, -2)
    win.close = Frame("Button", nil, win, "UIPanelCloseButton")
    win.close:SetPoint("TOPRIGHT", win, "TOPRIGHT", -4, -4)
    win.close:SetScript("OnClick", function() win:Hide() end)

    -- the model down the left, with a class icon behind it for when the
    -- player is out of range
    local pane = Frame("Frame", nil, win, "BackdropTemplate")
    pane:SetPoint("TOPLEFT", win, "TOPLEFT", 18, -58)
    pane:SetSize(WIDTH - CARD_W - 54, HEIGHT - 90)
    Backdrop(pane, INSET, 0.02, 0.03, 0.05, 0.9)
    win.pane = pane
    win.classIcon = pane:CreateTexture(nil, "ARTWORK")
    win.classIcon:SetSize(128, 128)
    win.classIcon:SetPoint("CENTER", pane, "CENTER", 0, 30)
    win.classIcon:SetTexture(CLASS_SHEET)
    win.classNote = Text(pane, "GameFontDisableSmall")
    win.classNote:SetPoint("TOP", win.classIcon, "BOTTOM", 0, -8)
    win.classNote:SetText("out of range: no model")
    win.model = Frame("PlayerModel", nil, pane)
    win.model:SetPoint("TOPLEFT", pane, "TOPLEFT", 4, -4)
    win.model:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", -4, 4)

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

-- a unit whose name is this plate's, if one is in range
local function UnitFor(plate, hint)
    local units = {hint, "target", "mouseover", "focus", "party1", "party2", "party3", "party4"}
    for _, u in ipairs(units) do
        if u then
            local name = Call(UnitName, u)
            if name and name == plate.name and Call(UnitIsPlayer, u) then return u end
        end
    end
end

local function ShowModel(win, plate, own, hint)
    local unit = own and "player" or UnitFor(plate, hint)
    if unit and win.model.SetUnit then
        local ok = pcall(win.model.SetUnit, win.model, unit)
        if ok then
            win.model:Show()
            win.classIcon:Hide()
            win.classNote:Hide()
            return true
        end
    end
    win.model:Hide()
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

local function FillCard(card, plate, own, cachedAt)
    card.name:SetText(plate.name ~= "" and plate.name or "?")
    if plate.title ~= "" then
        card.title:SetText(("« %s »"):format(plate.title))
        card.title:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    elseif plate.gameTitle ~= "" then
        card.title:SetText(plate.gameTitle)
        card.title:SetTextColor(0.8, 0.8, 0.8)
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
    local hour, weekend = ServerNow()
    for _, r in ipairs(CELL_ROWS) do
        local row = card.rows[r.key]
        local s = ns.CleanHours(plate[r.key])
        for h = 0, 23 do
            local on = s:sub(h + 1, h + 1) == "1"
            if on then row.cells[h]:SetColorTexture(LIT[1], LIT[2], LIT[3], 1)
            else row.cells[h]:SetColorTexture(DIM[1], DIM[2], DIM[3], 1) end
        end
        local mine = (r.key == "weekends") == weekend
        if mine and row.cells[hour] then
            row.now:ClearAllPoints()
            row.now:SetPoint("CENTER", row.cells[hour], "CENTER", 0, 0)
            row.now:Show()
        else
            row.now:Hide()
        end
    end
    card.motto:SetText(plate.motto ~= "" and ('"%s"'):format(plate.motto) or "")
    if own then
        card.stamp:SetText("This is what other players see.")
        card.edit:Show()
        card.ask:Hide()
    else
        if cachedAt and cachedAt > 0 and date then
            card.stamp:SetText("as of " .. (Call(date, "%d %b %H:%M", cachedAt) or ""))
        else
            card.stamp:SetText("")
        end
        card.edit:Hide()
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
    win:Show()
    return win
end

function ns.ShowOwnPlate(edit)
    local plate = ns.MyPlate()
    ns.ShowPlate(plate, {own = true, key = ns.CharKey()})
    if edit then ns.OpenEditor() end
    return plate
end

--------------------------------------------------------------------------
-- the editor
--------------------------------------------------------------------------

local function CopyPlate(p)
    local d = ns.NewPlate()
    d.title, d.motto = p.title or "", p.motto or ""
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
    ed.mottoCount:SetText(("%d/%d"):format(#(d.motto or ""), ns.MAX_MOTTO))
end

function ns.OpenEditor()
    local win = Window()
    local plate = ns.MyPlate()
    W.draft = CopyPlate(plate)
    local ed = win.editor
    ed.title:SetText(W.draft.title)
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
    plate.tags, plate.roles = clean.tags, clean.roles
    plate.weekdays, plate.weekends = clean.weekdays, clean.weekends
    W.draft = nil
    ns.Print("plate saved")
    ns.ShowOwnPlate(false)
end

--------------------------------------------------------------------------
-- the entry on a player's right-click menu
--------------------------------------------------------------------------

local MENUS = {"MENU_UNIT_PLAYER", "MENU_UNIT_ENEMY_PLAYER", "MENU_UNIT_PARTY", "MENU_UNIT_RAID_PLAYER", "MENU_UNIT_FRIEND", "MENU_UNIT_GUILD", "MENU_UNIT_COMMUNITIES_GUILD_MEMBER"}

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
    ns.menuInstalled = true
end
