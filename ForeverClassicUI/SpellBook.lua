-- Forever Classic UI - spellbook
--
-- Forever's spellbook is the retail one: an 809x720 window with the spells
-- laid out as a three-column list on a parchment page, picture tabs for
-- the skill lines along the top and a search box. Era's is a 384x512
-- book: four pieces of "UI-SpellbookPanel" art, twelve spell buttons in
-- two columns (icon, name in gold, rank/sub-name in brown), the skill line
-- tabs down the right edge, "Page N" and the two page arrows along the
-- bottom, "Spellbook" over the top edge next to the book icon.
--
-- The retail window (PlayerSpellsFrame) stays the frame that is shown and
-- closed, so keybinds, the micro button and Blizzard's own logic keep
-- working; while its spellbook page is up it is resized to 384x512, its
-- shell faded and its page moved out of reach, and a book of ours drawn
-- on it from C_SpellBook. Spell buttons are secure action buttons (left
-- click casts, drag picks the spell up); their attributes are only set
-- out of combat. When the talents page is up the retail size is put back.
--
-- Numbers come from Era's SpellBookFrame.xml and a `/cui report all`
-- taken on Classic Era 1.15.9 with the book open.

local addonName, ns = ...

local M = {mode = "off"}

local SB = "Interface\\Spellbook\\"
local ART = {
    topLeft = SB .. "UI-SpellbookPanel-TopLeft",
    topRight = SB .. "UI-SpellbookPanel-TopRight",
    bottomLeft = SB .. "UI-SpellbookPanel-BotLeft",
    bottomRight = SB .. "UI-SpellbookPanel-BotRight",
    slot = SB .. "UI-Spellbook-SpellBackground",
    icon = SB .. "Spellbook-Icon",
    skillTab = "Interface\\SpellBook\\SpellBook-SkillLineTab",
    -- Era's own spellbook tab files are not Era's on Forever (its copy of
    -- UI-SpellBook-Tab-Unselected draws as a retail metal box with the
    -- label low and left in it), so the bottom tabs are built from the
    -- character sheet's tab art, which the client still renders right
    tabArt = "Interface\\PaperDollInfoFrame\\UI-Character-InActiveTab",
    tabGlow = "Interface\\PaperDollInfoFrame\\UI-Character-Tab-Highlight",
    quickslot = "Interface\\Buttons\\UI-Quickslot2",
    quickslotDown = "Interface\\Buttons\\UI-Quickslot-Depress",
    highlight = "Interface\\Buttons\\ButtonHilight-Square",
    passiveHighlight = "Interface\\Buttons\\UI-PassiveHighlight",
    checked = "Interface\\Buttons\\CheckButtonHilight",
    prevUp = "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up",
    prevDown = "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Down",
    prevDisabled = "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Disabled",
    nextUp = "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up",
    nextDown = "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Down",
    nextDisabled = "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Disabled",
    mouseHighlight = "Interface\\Buttons\\UI-Common-MouseHilight",
    closeUp = "Interface\\Buttons\\UI-Panel-MinimizeButton-Up",
    closeDown = "Interface\\Buttons\\UI-Panel-MinimizeButton-Down",
    closeHighlight = "Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight"
}
M.ART = ART

local FRAME_WIDTH, FRAME_HEIGHT = 384, 512
local PANEL_WIDTH = 400
local SPELLS_PER_PAGE = 12
local MAX_SKILL_TABS = 8
-- Era's SpellButton order: button i shows page slot ORDER[i] (left column 1-6, right column 7-12)
local ORDER = {1, 7, 2, 8, 3, 9, 4, 10, 5, 11, 6, 12}

M.own = setmetatable({}, {__mode = "k"})
local function Own(frame)
    local t = M.own[frame]
    if not t then t = {}; M.own[frame] = t end
    return t
end

local function G(name) return _G[name] end

local function Str(key, fallback)
    local v = _G[key]
    if type(v) == "string" and v ~= "" then return v end
    return fallback
end

local function HasFile(path)
    if not GetFileIDFromPath then return true end
    local ok, id = pcall(GetFileIDFromPath, path)
    return ok and id ~= nil
end

local function InCombat()
    return InCombatLockdown and InCombatLockdown()
end

local function Fade(frame, on)
    if frame and frame.SetAlpha then frame:SetAlpha(on and 0 or 1) end
end

local function Mouse(frame, on)
    if frame and frame.EnableMouse then frame:EnableMouse(on) end
end

local function Guard(label, fn)
    return function(...)
        local ok, err = pcall(fn, ...)
        if not ok then ns.errors[#ns.errors + 1] = "spellbook " .. label .. ": " .. tostring(err) end
    end
end

local function Remember(region)
    local own = Own(region)
    if own.saved then return end
    local saved = {points = {}}
    if region.GetNumPoints and region.GetPoint then
        for i = 1, region:GetNumPoints() do saved.points[i] = {region:GetPoint(i)} end
    end
    if region.GetSize then saved.width, saved.height = region:GetSize() end
    own.saved = saved
end

local function Restore(region)
    local own = M.own[region]
    local saved = own and own.saved
    if not saved then return end
    if region.ClearAllPoints and region.SetPoint then
        region:ClearAllPoints()
        for _, p in ipairs(saved.points) do
            if p[1] then region:SetPoint(p[1], p[2], p[3], p[4], p[5]) end
        end
    end
    if saved.width and region.SetSize then region:SetSize(saved.width, saved.height) end
end

local function Anchor(region, point, rel, relPoint, x, y, w, h)
    if not region then return end
    Remember(region)
    region:ClearAllPoints()
    region:SetPoint(point, rel, relPoint, x, y)
    if w then region:SetSize(w, h) end
end

--------------------------------------------------------------------------
-- spell data (C_SpellBook, retail-style; the classic globals as fallback)
--------------------------------------------------------------------------

local function PlayerBank()
    return Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
end

local function PetBank()
    return Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Pet or 1
end

local function ItemTypes()
    local t = Enum and Enum.SpellBookItemType or {}
    return t.Spell or 1, t.FutureSpell or 2, t.PetAction or 3, t.Flyout or 4
end

local function API()
    return C_SpellBook and C_SpellBook.GetSpellBookItemInfo and C_SpellBook
end

-- the skill lines the book shows (tabs down the right edge)
local function SkillLines()
    local api = API()
    local lines = {}
    if not api or not api.GetNumSpellBookSkillLines then return lines end
    for i = 1, api.GetNumSpellBookSkillLines() or 0 do
        local info = api.GetSpellBookSkillLineInfo(i)
        if info and not info.shouldHide then
            lines[#lines + 1] = {index = i, name = info.name, icon = info.iconID, offset = info.itemIndexOffset or 0, count = info.numSpellBookItems or 0}
        end
    end
    return lines
end

-- the items of one line the classic book lists: known spells and pet actions only
local function LineItems(line, bank)
    local api = API()
    local items = {}
    if not api then return items end
    local spell, future, petAction, flyout = ItemTypes()
    for slot = line.offset + 1, line.offset + line.count do
        local info = api.GetSpellBookItemInfo(slot, bank)
        if info and info.itemType ~= future and not info.isOffSpec then
            items[#items + 1] = {slot = slot, bank = bank, spellID = info.spellID, actionID = info.actionID, itemType = info.itemType,
                                 name = info.name, subName = info.subName, icon = info.iconID, passive = info.isPassive == true,
                                 flyout = info.itemType == flyout}
        end
    end
    return items
end

local function PetLine()
    local api = API()
    if not api or not api.HasPetSpells then return nil end
    local ok, num = pcall(api.HasPetSpells)
    if ok and num and num > 0 then
        return {index = 0, name = Str("PET", "Pet"), offset = 0, count = num, pet = true}
    end
end

--------------------------------------------------------------------------
-- our book
--------------------------------------------------------------------------

local function HideTooltip()
    if GameTooltip then GameTooltip:Hide() end
end

local function SpellTooltip(button)
    local item = button.item
    if not item or not GameTooltip then return end
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    if GameTooltip.SetSpellBookItem then
        local ok = pcall(GameTooltip.SetSpellBookItem, GameTooltip, item.slot, item.bank)
        if not ok and item.spellID and GameTooltip.SetSpellByID then pcall(GameTooltip.SetSpellByID, GameTooltip, item.spellID) end
    elseif item.spellID and GameTooltip.SetSpellByID then
        pcall(GameTooltip.SetSpellByID, GameTooltip, item.spellID)
    end
    GameTooltip:Show()
end

local function Pickup(button)
    local item = button.item
    local api = API()
    if not item or InCombat() then return end
    if api and api.PickupSpellBookItem then
        pcall(api.PickupSpellBookItem, item.slot, item.bank)
    elseif C_Spell and C_Spell.PickupSpell and item.spellID then
        pcall(C_Spell.PickupSpell, item.spellID)
    end
end

-- one of the twelve spell buttons (Era SpellButtonTemplate, 37x37)
local function SpellButton(book, i)
    local b = CreateFrame("CheckButton", "ForeverClassicUISpellButton" .. i, book, "SecureActionButtonTemplate")
    b:SetSize(37, 37)
    b:SetFrameLevel(book:GetFrameLevel() + 2)
    if b.RegisterForClicks then b:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    if b.RegisterForDrag then b:RegisterForDrag("LeftButton") end
    b.EmptySlot = b:CreateTexture(nil, "BACKGROUND")
    b.EmptySlot:SetTexture(ART.slot)
    b.EmptySlot:SetSize(64, 64)
    b.EmptySlot:SetPoint("TOPLEFT", b, "TOPLEFT", -3, 3)
    b.Icon = b:CreateTexture(nil, "BORDER")
    b.Icon:SetAllPoints(b)
    b.SpellName = b:CreateFontString(nil, "BORDER", "GameFontNormal")
    b.SpellName:SetSize(103, 0)
    b.SpellName:SetJustifyH("LEFT")
    b.SpellName:SetPoint("LEFT", b, "RIGHT", 5, 3)
    b.SpellSubName = b:CreateFontString(nil, "BORDER", "GameFontNormalSmall")
    b.SpellSubName:SetSize(79, 18)
    b.SpellSubName:SetJustifyH("LEFT")
    b.SpellSubName:SetPoint("TOPLEFT", b.SpellName, "BOTTOMLEFT", 0, -2)
    b.SpellSubName:SetTextColor(0.35, 0.2, 0)
    b:SetNormalTexture(ART.quickslot)
    local nt = b:GetNormalTexture()
    if nt then
        nt:SetSize(64, 64)
        nt:ClearAllPoints()
        nt:SetPoint("CENTER", b, "CENTER", 0, 0)
    end
    b:SetPushedTexture(ART.quickslotDown)
    b:SetHighlightTexture(ART.highlight, "ADD")
    if b.SetCheckedTexture then b:SetCheckedTexture(ART.checked) end
    b.Cooldown = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    b.Cooldown:SetAllPoints(b)
    b:SetScript("OnEnter", SpellTooltip)
    b:SetScript("OnLeave", HideTooltip)
    b:SetScript("OnDragStart", Pickup)
    b:SetScript("OnReceiveDrag", Pickup)
    b:SetScript("OnHide", function(self) if self.SetChecked then self:SetChecked(false) end end)
    return b
end

local function SkillTab(book, i)
    local t = CreateFrame("CheckButton", nil, book)
    t:SetSize(32, 32)
    t:SetFrameLevel(book:GetFrameLevel() + 2)
    local bg = t:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture(ART.skillTab)
    bg:SetSize(64, 64)
    bg:SetPoint("TOPLEFT", t, "TOPLEFT", -3, 11)
    t.Icon = t:CreateTexture(nil, "ARTWORK")
    t.Icon:SetAllPoints(t)
    t:SetHighlightTexture(ART.highlight, "ADD")
    if t.SetCheckedTexture then
        t:SetCheckedTexture(ART.checked)
        -- Era: alphaMode="ADD". CheckButtonHilight is a glow on black with
        -- no alpha, so in the default blend mode it covers the icon black.
        local checked = t.GetCheckedTexture and t:GetCheckedTexture()
        if checked then
            if checked.SetBlendMode then checked:SetBlendMode("ADD") end
            if checked.SetAllPoints then checked:SetAllPoints(t) end
        end
    end
    t:SetScript("OnClick", function(self)
        M.currentLine = self.lineIndex
        M.Update()
    end)
    t:SetScript("OnEnter", function(self)
        if GameTooltip and self.lineName then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.lineName)
            GameTooltip:Show()
        end
    end)
    t:SetScript("OnLeave", HideTooltip)
    return t
end

-- bottom tabs: Spellbook, and Pet when the player has one. The tab art is
-- the character sheet's, cut into three (10px ends of a 64px image) so the
-- middle stretches to whatever the label needs.
local TAB_HEIGHT, TAB_END, TAB_PAD, TAB_MIN = 32, 20, 44, 84

local function TabPiece(tab, l, r)
    local t = tab:CreateTexture(nil, "BACKGROUND")
    t:SetTexture(ART.tabArt)
    t:SetSize(TAB_END, TAB_HEIGHT)
    t:SetTexCoord(l, r, 0, 1)
    return t
end

local function BookTab(book, text)
    local t = CreateFrame("Button", nil, book)
    t:SetHeight(TAB_HEIGHT)
    t:SetFrameLevel(book:GetFrameLevel() + 2)
    t.Left = TabPiece(t, 0, 0.15625)
    t.Middle = TabPiece(t, 0.15625, 0.84375)
    t.Right = TabPiece(t, 0.84375, 1)
    t.Left:SetPoint("TOPLEFT", t, "TOPLEFT", 0, 0)
    t.Right:SetPoint("TOPRIGHT", t, "TOPRIGHT", 0, 0)
    t.Middle:ClearAllPoints()
    t.Middle:SetPoint("TOPLEFT", t.Left, "TOPRIGHT", 0, 0)
    t.Middle:SetPoint("BOTTOMRIGHT", t.Right, "BOTTOMLEFT", 0, 0)
    t.Text = t:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    t.Text:SetPoint("CENTER", t, "CENTER", 0, 2)
    t.Text:SetText(text)
    local width = TAB_MIN
    if t.Text.GetStringWidth then width = math.max(TAB_MIN, t.Text:GetStringWidth() + TAB_PAD) end
    t:SetWidth(width)
    if HasFile(ART.tabGlow) then
        t:SetHighlightTexture(ART.tabGlow, "ADD")
        local hl = t:GetHighlightTexture()
        if hl then
            hl:ClearAllPoints()
            hl:SetPoint("TOPLEFT", t, "TOPLEFT", 3, 5)
            hl:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", -3, 0)
        end
    end
    return t
end

local function PageButton(book, prev)
    local b = CreateFrame("Button", nil, book)
    b:SetSize(32, 32)
    b:SetFrameLevel(book:GetFrameLevel() + 2)
    b:SetNormalTexture(prev and ART.prevUp or ART.nextUp)
    b:SetPushedTexture(prev and ART.prevDown or ART.nextDown)
    if b.SetDisabledTexture then b:SetDisabledTexture(prev and ART.prevDisabled or ART.nextDisabled) end
    b:SetHighlightTexture(ART.mouseHighlight, "ADD")
    b:SetScript("OnClick", function()
        M.SetPage((M.page or 1) + (prev and -1 or 1))
    end)
    return b
end

local function BuildBook()
    local psf = G("PlayerSpellsFrame")
    local book = CreateFrame("Frame", "ForeverClassicUISpellBook", psf)
    book:SetAllPoints(psf)
    book:SetFrameLevel(psf:GetFrameLevel() + 1)
    local function Piece(path, w, h, point, x, y)
        local t = book:CreateTexture(nil, "ARTWORK")
        t:SetTexture(path)
        t:SetSize(w, h)
        t:SetPoint(point, book, point, x, y)
        return t
    end
    book.art = {
        Piece(ART.topLeft, 256, 256, "TOPLEFT", 0, 0),
        Piece(ART.topRight, 128, 256, "TOPRIGHT", 0, 0),
        Piece(ART.bottomLeft, 256, 256, "BOTTOMLEFT", 0, 0),
        Piece(ART.bottomRight, 128, 256, "BOTTOMRIGHT", 0, 0)
    }
    book.title = book:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    book.title:SetPoint("CENTER", book, "CENTER", 6, 230)
    book.title:SetText(Str("SPELLBOOK", "Spellbook"))
    book.pageText = book:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    book.pageText:SetSize(102, 0)
    book.pageText:SetJustifyH("RIGHT")
    book.pageText:SetPoint("BOTTOMRIGHT", book, "BOTTOMRIGHT", -110, 38)
    book.pageText:SetTextColor(0.25, 0.12, 0)
    book.prev = PageButton(book, true)
    book.prev:SetPoint("CENTER", book, "BOTTOMLEFT", 50, 105)
    book.next = PageButton(book, false)
    book.next:SetPoint("CENTER", book, "BOTTOMLEFT", 314, 105)
    book.buttons = {}
    for i = 1, SPELLS_PER_PAGE do
        local b = SpellButton(book, i)
        if i == 1 then
            b:SetPoint("TOPLEFT", book, "TOPLEFT", 34, -85)
        elseif i % 2 == 0 then
            b:SetPoint("TOPLEFT", book.buttons[i - 1], "TOPLEFT", 157, 0)
        else
            b:SetPoint("TOPLEFT", book.buttons[i - 2], "BOTTOMLEFT", 0, -14)
        end
        book.buttons[i] = b
    end
    book.skillTabs = {}
    for i = 1, MAX_SKILL_TABS do
        local t = SkillTab(book, i)
        if i == 1 then
            t:SetPoint("TOPLEFT", book, "TOPRIGHT", -32, -65)
        else
            t:SetPoint("TOPLEFT", book.skillTabs[i - 1], "BOTTOMLEFT", 0, -17)
        end
        t:Hide()
        book.skillTabs[i] = t
    end
    book.tabSpells = BookTab(book, Str("SPELLBOOK", "Spellbook"))
    book.tabSpells:SetPoint("BOTTOMLEFT", book, "BOTTOMLEFT", 20, 45)
    book.tabSpells:SetScript("OnClick", function() M.bank = "player"; M.currentLine = nil; M.Update() end)
    book.tabPet = BookTab(book, Str("PET", "Pet"))
    book.tabPet:SetPoint("LEFT", book.tabSpells, "RIGHT", 4, 0)
    book.tabPet:SetScript("OnClick", function() M.bank = "pet"; M.Update() end)
    book.tabPet:Hide()
    local close = CreateFrame("Button", nil, book)
    close:SetSize(32, 32)
    close:SetPoint("CENTER", book, "TOPRIGHT", -44, -25)
    close:SetFrameLevel(book:GetFrameLevel() + 3)
    close:SetNormalTexture(ART.closeUp)
    close:SetPushedTexture(ART.closeDown)
    close:SetHighlightTexture(ART.closeHighlight, "ADD")
    close:SetScript("OnClick", function() if HideUIPanel then HideUIPanel(psf) else psf:Hide() end end)
    book.close = close
    book:Hide()
    return book
end

--------------------------------------------------------------------------
-- filling the page
--------------------------------------------------------------------------

-- Era lifted the selected tab onto its own art; that file is one of the
-- ones Forever did not keep, so the selected tab is told apart the other
-- Era way (white text, button disabled), as the character sheet does.
local function SetTabSelected(tab, selected)
    tab.selected = selected
    if selected then
        if tab.Disable then tab:Disable() end
        tab.Text:SetTextColor(1, 1, 1)
    else
        if tab.Enable then tab:Enable() end
        tab.Text:SetTextColor(1, 0.82, 0)
    end
end

-- secure attributes: left click casts; only out of combat, re-done after combat
local function SetCastAttributes(button, item)
    if not button.SetAttribute then return end
    if InCombat() then
        M.attributesDirty = true
        return
    end
    if item and item.spellID and not item.passive and not item.flyout then
        button:SetAttribute("type", "spell")
        button:SetAttribute("spell", item.spellID)
    else
        button:SetAttribute("type", nil)
        button:SetAttribute("spell", nil)
    end
end

local function UpdateCooldown(button)
    local item = button.item
    if not item or not item.spellID or not button.Cooldown or not button.Cooldown.SetCooldown then return end
    local start, duration = 0, 0
    if C_Spell and C_Spell.GetSpellCooldown then
        local ok, info = pcall(C_Spell.GetSpellCooldown, item.spellID)
        if ok and info then start, duration = info.startTime or 0, info.duration or 0 end
    elseif GetSpellCooldown then
        local ok, s, d = pcall(GetSpellCooldown, item.spellID)
        if ok then start, duration = s or 0, d or 0 end
    end
    button.Cooldown:SetCooldown(start, duration)
end

local function FillButton(button, item)
    button.item = item
    if not item then
        button.Icon:SetTexture(nil)
        button.Icon:Hide()
        button.SpellName:SetText("")
        button.SpellSubName:SetText("")
        button:SetHighlightTexture(ART.highlight, "ADD")
        local nt = button:GetNormalTexture()
        if nt then nt:SetVertexColor(1, 1, 1) end
        SetCastAttributes(button, nil)
        if button.Cooldown and button.Cooldown.SetCooldown then button.Cooldown:SetCooldown(0, 0) end
        return
    end
    button.Icon:SetTexture(item.icon)
    button.Icon:Show()
    button.SpellName:SetText(item.name or "")
    button.SpellSubName:SetText(item.subName or "")
    local nt = button:GetNormalTexture()
    if item.passive then
        -- Era: passives get a black slot ring, dim gold name and the passive highlight
        button.SpellName:SetTextColor(0.77, 0.64, 0)
        if nt then nt:SetVertexColor(0, 0, 0) end
        if HasFile(ART.passiveHighlight) then button:SetHighlightTexture(ART.passiveHighlight, "ADD") end
    else
        button.SpellName:SetTextColor(1, 0.82, 0)
        if nt then nt:SetVertexColor(1, 1, 1) end
        button:SetHighlightTexture(ART.highlight, "ADD")
    end
    SetCastAttributes(button, item)
    UpdateCooldown(button)
end

function M.CurrentItems()
    local book = M.book
    local lines = SkillLines()
    M.lines = lines
    if M.bank == "pet" then
        local pet = PetLine()
        if not pet then M.bank = "player" else return LineItems(pet, PetBank()), pet, lines end
    end
    local line
    for _, l in ipairs(lines) do
        if l.index == M.currentLine then line = l end
    end
    line = line or lines[1]
    if line then M.currentLine = line.index end
    return line and LineItems(line, PlayerBank()) or {}, line, lines
end

function M.SetPage(page)
    M.page = page
    M.Update()
end

function M.Update()
    local book = M.book
    if not book or not book:IsShown() then return end
    local items, line, lines = M.CurrentItems()
    local numPages = math.max(1, math.ceil(#items / SPELLS_PER_PAGE))
    local page = math.max(1, math.min(M.page or 1, numPages))
    M.page, M.numPages = page, numPages
    for i = 1, SPELLS_PER_PAGE do
        local slot = (page - 1) * SPELLS_PER_PAGE + ORDER[i]
        FillButton(book.buttons[i], items[slot])
    end
    book.pageText:SetText(Str("PAGE_NUMBER", "Page %d"):format(page))
    if book.prev.SetEnabled then
        book.prev:SetEnabled(page > 1)
        book.next:SetEnabled(page < numPages)
    end
    -- skill line tabs down the right edge
    for i, tab in ipairs(book.skillTabs) do
        local l = lines[i]
        if l then
            tab.lineIndex, tab.lineName = l.index, l.name
            tab.Icon:SetTexture(l.icon)
            if tab.SetChecked then tab:SetChecked(M.bank ~= "pet" and l.index == M.currentLine) end
            tab:Show()
        else
            tab:Hide()
        end
    end
    -- bottom tabs
    local pet = PetLine()
    book.tabPet:SetShown(pet ~= nil)
    SetTabSelected(book.tabSpells, M.bank ~= "pet")
    SetTabSelected(book.tabPet, M.bank == "pet")
end

--------------------------------------------------------------------------
-- Blizzard's window: classic while its spellbook page is up
--------------------------------------------------------------------------

local function SpellPageShown()
    local psf = G("PlayerSpellsFrame")
    local page = psf and psf.SpellBookFrame
    return page ~= nil and page.IsShown ~= nil and page:IsShown() == true
end

local function Shell(psf, classic)
    Fade(psf.NineSlice, classic)
    Fade(psf.Bg, classic)
    Fade(psf.TopTileStreaks, classic)
    Fade(psf.CloseButton, classic)
    Mouse(psf.CloseButton, not classic)
    Fade(psf.MaximizeMinimizeButton, classic)
    Mouse(psf.MaximizeMinimizeButton, not classic)
    if psf.MaximizeMinimizeButton then
        Mouse(psf.MaximizeMinimizeButton.MaximizeButton, not classic)
        Mouse(psf.MaximizeMinimizeButton.MinimizeButton, not classic)
    end
    Fade(psf.TabSystem, classic)
    Mouse(psf.TabSystem, not classic)
    local portrait = psf.PortraitContainer and psf.PortraitContainer.portrait
    local mask = psf.PortraitContainer and psf.PortraitContainer.CircleMask
    if classic then
        -- Era: the book icon 58x58 at 10,-8; "Spellbook" over the top edge (our title draws it)
        Anchor(portrait, "TOPLEFT", psf, "TOPLEFT", 10, -8, 58, 58)
        if mask then
            Remember(mask)
            mask:ClearAllPoints()
            mask:SetPoint("TOPLEFT", portrait, "TOPLEFT", 0, 0)
            mask:SetPoint("BOTTOMRIGHT", portrait, "BOTTOMRIGHT", 0, 0)
        end
        Fade(psf.TitleContainer, true)
    else
        Restore(portrait)
        Restore(mask)
        Fade(psf.TitleContainer, false)
    end
    -- the retail page: transparent and moved out of reach while ours is up
    local page = psf.SpellBookFrame
    if page then
        Fade(page, classic)
        if classic then
            Anchor(page, "TOPLEFT", psf, "BOTTOMLEFT", 0, -5000)
        else
            Restore(page)
        end
    end
end

function M.Apply()
    if M.mode ~= "restyled" then return end
    local psf = G("PlayerSpellsFrame")
    if not psf then return end
    local classic = SpellPageShown()
    if classic ~= M.applied then
        Shell(psf, classic)
        M.applied = classic
    end
    if classic then
        M.resizing = true
        psf:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
        M.resizing = nil
        if SetUIPanelAttribute then pcall(SetUIPanelAttribute, psf, "width", PANEL_WIDTH) end
        M.book:Show()
        M.Update()
    else
        M.book:Hide()
        if M.savedSize and M.savedSize[1] then
            M.resizing = true
            psf:SetSize(M.savedSize[1], M.savedSize[2])
            M.resizing = nil
        end
        if SetUIPanelAttribute and M.savedPanelWidth then pcall(SetUIPanelAttribute, psf, "width", M.savedPanelWidth) end
    end
end

local function Undo()
    local psf = G("PlayerSpellsFrame")
    if not psf then return end
    Shell(psf, false)
    M.applied = false
    if M.book then M.book:Hide() end
    if M.savedSize and M.savedSize[1] then psf:SetSize(M.savedSize[1], M.savedSize[2]) end
    if SetUIPanelAttribute and M.savedPanelWidth then pcall(SetUIPanelAttribute, psf, "width", M.savedPanelWidth) end
end

local function Hook()
    if M.hooked then return end
    local psf = G("PlayerSpellsFrame")
    if not psf or not hooksecurefunc then return end
    -- Blizzard sizes the window itself (show, maximize/minimize): re-apply ours after it
    hooksecurefunc(psf, "SetSize", Guard("SetSize", function(_, w, h)
        if M.resizing or M.mode ~= "restyled" then return end
        if SpellPageShown() then
            if w ~= FRAME_WIDTH or h ~= FRAME_HEIGHT then
                M.resizing = true
                psf:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
                M.resizing = nil
            end
        else
            M.savedSize = {w, h}
        end
    end))
    if psf.HookScript then
        psf:HookScript("OnShow", Guard("OnShow", M.Apply))
        psf:HookScript("OnHide", Guard("OnHide", function() if M.book then M.book:Hide() end end))
    end
    local page = psf.SpellBookFrame
    if page and page.HookScript then
        page:HookScript("OnShow", Guard("page OnShow", M.Apply))
        page:HookScript("OnHide", Guard("page OnHide", M.Apply))
    end
    M.hooked = true
end

--------------------------------------------------------------------------
-- module interface
--------------------------------------------------------------------------

local BOOK_EVENTS = {"SPELLS_CHANGED", "LEARNED_SPELL_IN_TAB", "PET_BAR_UPDATE", "UNIT_PET", "PLAYER_ENTERING_WORLD"}

local function IsForeverBook()
    local psf = G("PlayerSpellsFrame")
    return psf ~= nil and psf.SpellBookFrame ~= nil and API() ~= nil
end

-- Forever's spell window lives in Blizzard_PlayerSpells, which is loaded on
-- demand the first time the book is opened, so at login there is nothing to
-- hook yet. Watch ADDON_LOADED and finish enabling once the frame exists.
local function WatchForBook()
    if M.watcher or not CreateFrame then return end
    local watcher = CreateFrame("Frame")
    watcher:RegisterEvent("ADDON_LOADED")
    watcher:SetScript("OnEvent", function(_, _, name)
        if M.mode ~= "waiting" then return end
        if name == "Blizzard_PlayerSpells" or IsForeverBook() then
            if ns.SafeCall("spellbook", M.Enable, M) and M.mode == "restyled" then
                watcher:UnregisterEvent("ADDON_LOADED")
            end
        end
    end)
    M.watcher = watcher
end

function M:Enable()
    if G("SpellBookFrame") and not G("PlayerSpellsFrame") then
        self.mode = "native" -- classic client: its own book
        return
    end
    if not IsForeverBook() then
        if API() ~= nil and not G("PlayerSpellsFrame") then
            self.mode = "waiting"
            WatchForBook()
            if self.watcher then self.watcher:RegisterEvent("ADDON_LOADED") end
        else
            self.mode = "off"
        end
        return
    end
    self.missingArt = {}
    for _, key in ipairs({"topLeft", "topRight", "bottomLeft", "bottomRight", "slot", "skillTab", "tabArt"}) do
        if not HasFile(ART[key]) then self.missingArt[#self.missingArt + 1] = ART[key]:match("[^\\]+$") end
    end
    local psf = G("PlayerSpellsFrame")
    if not self.savedSize and psf.GetSize then self.savedSize = {psf:GetSize()} end
    if not self.savedPanelWidth and GetUIPanelAttribute then
        local ok, w = pcall(GetUIPanelAttribute, psf, "width")
        if ok and type(w) == "number" then self.savedPanelWidth = w end
    end
    if not self.book then
        self.book = BuildBook()
        local ev = self.book
        -- Forever lacks some of Era's events (LEARNED_SPELL_IN_TAB): skip the unknown ones
        for _, e in ipairs(BOOK_EVENTS) do pcall(ev.RegisterEvent, ev, e) end
        ev:RegisterEvent("SPELL_UPDATE_COOLDOWN")
        ev:RegisterEvent("PLAYER_REGEN_ENABLED")
        ev:SetScript("OnEvent", Guard("event", function(_, event)
            if event == "SPELL_UPDATE_COOLDOWN" then
                for _, b in ipairs(M.book.buttons) do UpdateCooldown(b) end
            elseif event == "PLAYER_REGEN_ENABLED" then
                if M.attributesDirty then M.attributesDirty = nil; M.Update() end
            else
                M.Update()
            end
        end))
    end
    self.bank = self.bank or "player"
    self.page = self.page or 1
    self.mode = "restyled"
    self.applied = nil
    Hook()
    M.Apply()
end

function M:Force()
    if self.mode == "restyled" then
        self.applied = nil
        M.Apply()
    end
end

function M:Disable()
    local was = self.mode
    self.mode = "off"
    if was == "restyled" then Undo() end
end

function M:Status()
    if self.mode == "restyled" then
        local s = "classic 384x512 book, 12 spells a page, skill line tabs on the right"
        if self.missingArt and #self.missingArt > 0 then
            s = s .. " (art missing: " .. table.concat(self.missingArt, ", ") .. ")"
        end
        return s
    elseif self.mode == "native" then
        return "classic client, Blizzard's book left alone"
    elseif self.mode == "waiting" then
        return "waiting for Blizzard's spell window to load (it loads the first time the book is opened)"
    end
    return "off"
end

ns.RegisterModule("spellbook", M)
