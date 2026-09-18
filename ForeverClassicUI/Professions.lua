-- Forever Classic UI - the professions window
--
-- Forever's professions window is `ProfessionsFrame` (Blizzard_Professions):
-- a 673x594 frame with an overview page (`BookPage`, its five profession
-- cards under `ProfessionsContentFrame`: PrimaryProfession1/2 and
-- SecondaryProfession1-3, each with the profession name, the two
-- profession spell buttons, a rank bar and an unlearn button) and a
-- crafting page for the open profession, with side tabs down the right
-- edge switching between them. Era had no such window (professions lived
-- in the Skills tab), so the classic reference is the pre-retail
-- spellbook's Professions page: the same 384x512 book as the spellbook,
-- the professions as rows down the page.
--
-- What this part does while the overview page is up:
--   * the frame is resized to 384x512 (Blizzard's own SetSize is undone,
--     as the spellbook part does) and its retail shell (background,
--     nine-slice, title, close button) faded; the Era book art goes on a
--     frame of ours, with the book icon in the corner and "Professions"
--     over the top edge;
--   * Blizzard's five cards stay the live frames (their spell buttons
--     cast and drag, the unlearn button works): they are resized to
--     340x62 rows and re-anchored down the page, their card art faded,
--     the name and the two spell buttons re-anchored into the row with
--     the classic quickslot ring round each icon;
--   * Blizzard's animated rank bar is faded and a classic skill bar of
--     ours (Era's blue skill-bar fill in the skills bevel, "rank/max")
--     drawn in its place, filled from GetProfessionInfo;
--   * the side tabs become Era's 32px skill line tabs down the right
--     edge of the book.
-- On the crafting page the retail size and shell come back (that page
-- gets its classic version separately).
-- Rule as elsewhere: widget calls and hooksecurefunc only; nothing of
-- ours written into Blizzard's tables (M.own holds what hangs on them).

local addonName, ns = ...

local M = {mode = "off"}

local SB = "Interface\\Spellbook\\"
local PD = "Interface\\PaperDollInfoFrame\\"
local ART = {
    topLeft = SB .. "UI-SpellbookPanel-TopLeft",
    topRight = SB .. "UI-SpellbookPanel-TopRight",
    bottomLeft = SB .. "UI-SpellbookPanel-BotLeft",
    bottomRight = SB .. "UI-SpellbookPanel-BotRight",
    skillTab = "Interface\\SpellBook\\SpellBook-SkillLineTab",
    ring = "Interface\\Buttons\\UI-Quickslot2",
    bar = PD .. "UI-Character-Skills-Bar",
    barBorder = PD .. "UI-Character-Skills-BarBorder",
    highlight = "Interface\\Buttons\\ButtonHilight-Square",
    checked = "Interface\\Buttons\\CheckButtonHilight",
    closeUp = "Interface\\Buttons\\UI-Panel-MinimizeButton-Up",
    closeDown = "Interface\\Buttons\\UI-Panel-MinimizeButton-Down",
    closeHighlight = "Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight"
}
M.ART = ART

local FRAME_NAME = "ProfessionsFrame"
local BLIZZARD_ADDON = "Blizzard_Professions"
local FRAME_WIDTH, FRAME_HEIGHT = 384, 512
local PANEL_WIDTH = 400
-- the rows: 340x62 down the page from x=22
local ROW_W, ROW_H, ROW_X = 340, 62, 22
local ROWS = {
    {name = "PrimaryProfession1", y = -70, slot = 1},
    {name = "PrimaryProfession2", y = -138, slot = 2},
    -- GetProfessions returns prof1, prof2, archaeology, fishing, cooking, first aid
    {name = "SecondaryProfession1", y = -206, slot = 5},
    {name = "SecondaryProfession2", y = -274, slot = 4},
    {name = "SecondaryProfession3", y = -342, slot = 6}
}
-- inside a row: name top left, the two spell buttons under it, the rank
-- bar top right with the unlearn button past its end
local NAME_X, NAME_Y = 8, -4
local BUTTON_Y = -24
local BUTTON_X = {8, 175}
-- the bar is the reputation tab's 137px bar in the same 147px bevel box
local BAR_W, BAR_H = 137, 13
local BAR_X, BAR_Y = -30, -6
local BEVEL_W, BEVEL_IMAGE_W = 74, 281
local ICON_SIZE = 40
local RING_SIZE = 64 * ICON_SIZE / 37
-- Era's skill line tabs: 32px, the first at (-32,-65) off the book's top right, 17px apart
local TAB_SIZE, TAB_X, TAB_Y, TAB_GAP = 32, -32, -65, 17
local TAB_NAMES = {"ProfessionsOverviewTab", "Professions1Tab", "Professions2Tab", "Professions3Tab", "Professions4Tab", "Professions5Tab"}
local PARCHMENT_TEXT = {0.25, 0.12, 0}
local BROWN_TEXT = {0.5, 0.35, 0.05}
local REFRESH_EVENTS = {"SKILL_LINES_CHANGED", "TRADE_SKILL_LIST_UPDATE", "SPELLS_CHANGED", "PLAYER_ENTERING_WORLD", "LEARNED_SPELL_IN_TAB"}

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

local function Fade(frame, on)
    if frame and frame.SetAlpha then frame:SetAlpha(on and 0 or 1) end
end

local function Mouse(frame, on)
    if frame and frame.EnableMouse then frame:EnableMouse(on) end
end

local function Guard(label, fn)
    return function(...)
        local ok, err = pcall(fn, ...)
        if not ok then ns.errors[#ns.errors + 1] = "professions " .. label .. ": " .. tostring(err) end
    end
end

-- what a Blizzard region looked like before we touched it
local function Remember(region)
    local own = Own(region)
    if own.saved then return end
    local saved = {points = {}}
    if region.GetNumPoints and region.GetPoint then
        for i = 1, region:GetNumPoints() do saved.points[i] = {region:GetPoint(i)} end
    end
    if region.GetSize then saved.width, saved.height = region:GetSize() end
    if region.GetScale then saved.scale = region:GetScale() end
    if region.GetTextColor then
        local ok, r, g, b = pcall(region.GetTextColor, region)
        if ok and r then saved.color = {r, g, b} end
    end
    if region.GetFrameLevel then saved.level = region:GetFrameLevel() end
    own.saved = saved
end

local function Restore(region)
    local own = region and M.own[region]
    local saved = own and own.saved
    if not saved then return end
    if region.ClearAllPoints and region.SetPoint then
        region:ClearAllPoints()
        for _, p in ipairs(saved.points) do
            if p[1] then region:SetPoint(p[1], p[2], p[3], p[4], p[5]) end
        end
    end
    if saved.width and region.SetSize then region:SetSize(saved.width, saved.height) end
    if saved.scale and region.SetScale then region:SetScale(saved.scale) end
    if saved.color and region.SetTextColor then region:SetTextColor(saved.color[1], saved.color[2], saved.color[3]) end
    if saved.level and region.SetFrameLevel then region:SetFrameLevel(saved.level) end
end

local function Anchor(region, point, rel, relPoint, x, y, w, h)
    if not region then return end
    Remember(region)
    region:ClearAllPoints()
    region:SetPoint(point, rel, relPoint, x, y)
    if w then region:SetSize(w, h) end
end

local function Colour(region, rgb)
    if not region or not region.SetTextColor then return end
    Remember(region)
    region:SetTextColor(rgb[1], rgb[2], rgb[3])
end

--------------------------------------------------------------------------
-- finding Blizzard's pieces
--------------------------------------------------------------------------

local function Page(psf) return psf and psf.BookPage end

local function Content(psf)
    local page = Page(psf)
    return (page and page.ProfessionsContentFrame) or (psf and psf.ProfessionsContentFrame)
end

-- a card by its key on the content frame, or by global name
local function Row(psf, name)
    local content = Content(psf)
    local row = content and content[name]
    if row then return row end
    return G(name)
end

local function PageShown(psf)
    local page = Page(psf)
    if not page then return psf.IsShown and psf:IsShown() == true end
    return page.IsShown ~= nil and page:IsShown() == true
end

-- the side tabs, in order down the edge
local function Tabs(psf)
    local out = {}
    for _, name in ipairs(TAB_NAMES) do
        local tab = psf[name] or G(name)
        if tab and tab.Icon then out[#out + 1] = tab end
    end
    if #out == 0 and psf.GetChildren then
        for _, child in ipairs({psf:GetChildren()}) do
            if child.Icon and child.SelectedTexture and child.TabGlow then out[#out + 1] = child end
        end
    end
    return out
end

--------------------------------------------------------------------------
-- our book: the Era art, title, close button
--------------------------------------------------------------------------

local function BuildBook(psf)
    local book = CreateFrame("Frame", "ForeverClassicUIProfessionsBook", psf)
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
    book.title:SetText(Str("TRADE_SKILLS", "Professions"))
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
-- the rank bar of ours: Era's skill bar (blue fill in the skills bevel)
--------------------------------------------------------------------------

local function Bevel(bar, layer, file)
    local l = bar:CreateTexture(nil, layer)
    l:SetTexture(file)
    l:SetSize(BEVEL_W, 32)
    l:SetTexCoord(0, BEVEL_W / BEVEL_IMAGE_W, 0, 1)
    l:SetPoint("LEFT", bar, "LEFT", -5, 0)
    local r = bar:CreateTexture(nil, layer)
    r:SetTexture(file)
    r:SetSize(BEVEL_W, 32)
    r:SetTexCoord(1 - BEVEL_W / BEVEL_IMAGE_W, 1, 0, 1)
    r:SetPoint("RIGHT", bar, "RIGHT", 5, 0)
    return l, r
end

local function SkillBar(row)
    local bar = CreateFrame("StatusBar", nil, row)
    bar:SetSize(BAR_W, BAR_H)
    bar:SetPoint("TOPRIGHT", row, "TOPRIGHT", BAR_X, BAR_Y)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    bar:SetStatusBarTexture(ART.bar)
    bar:SetStatusBarColor(0.25, 0.25, 0.75)
    bar.Background = bar:CreateTexture(nil, "BACKGROUND")
    bar.Background:SetColorTexture(0, 0, 0, 0.5)
    bar.Background:SetAllPoints(bar)
    bar.Left, bar.Right = Bevel(bar, "ARTWORK", ART.barBorder)
    bar.Rank = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.Rank:SetPoint("CENTER", bar, "CENTER", 0, 0)
    return bar
end

-- the profession behind a card: GetProfessionInfo matched by the card's
-- name, else by the card's slot in GetProfessions, else Blizzard's own
-- rank text ("Skinning 1/75")
local function ProfessionInfo(row, spec)
    local infos = {}
    if GetProfessions and GetProfessionInfo then
        local ids = {GetProfessions()}
        for slot = 1, 6 do
            local id = ids[slot]
            if id then
                local ok, name, _, rank, max, _, _, _, modifier = pcall(GetProfessionInfo, id)
                if ok and name then
                    infos[#infos + 1] = {name = name, rank = tonumber(rank) or 0, max = tonumber(max) or 0, modifier = tonumber(modifier) or 0, slot = slot}
                end
            end
        end
    end
    local label = row.ProfessionName
    local wanted = label and label.GetText and label:GetText()
    local ok, match = pcall(function()
        if type(wanted) ~= "string" or wanted == "" then return nil end
        for _, info in ipairs(infos) do
            if info.name == wanted then return info end
        end
    end)
    if ok and match then return match end
    for _, info in ipairs(infos) do
        if info.slot == spec.slot then return info end
    end
    local blizzard = row.StatusBar and row.StatusBar.Rank
    local text = blizzard and blizzard.Text and blizzard.Text.GetText and blizzard.Text:GetText()
    local okText, rank, max = pcall(function()
        if type(text) ~= "string" then return nil end
        return text:match("(%d+)%s*/%s*(%d+)")
    end)
    if okText and rank then return {rank = tonumber(rank), max = tonumber(max), modifier = 0} end
end

local function FillBar(bar, row, spec)
    local live = row.StatusBar and row.StatusBar.IsShown and row.StatusBar:IsShown() == true
    local info = live and ProfessionInfo(row, spec)
    if not info then bar:Hide(); return end
    local max = info.max > 0 and info.max or 1
    bar:SetMinMaxValues(0, max)
    bar:SetValue(math.min(info.rank, max))
    if info.modifier > 0 then
        bar.Rank:SetText(("%d (+%d)/%d"):format(info.rank, info.modifier, info.max))
    else
        bar.Rank:SetText(("%d/%d"):format(info.rank, info.max))
    end
    bar:Show()
end

--------------------------------------------------------------------------
-- Blizzard's cards made classic
--------------------------------------------------------------------------

-- a profession spell button: retail's square frame faded, the classic
-- quickslot ring round the 40px icon (a texture of ours on the button),
-- name gold and rank line brown on the parchment
local function SkinSpellButton(btn, row, x)
    if not btn then return end
    local own = Own(btn)
    Anchor(btn, "TOPLEFT", row, "TOPLEFT", x, BUTTON_Y, ICON_SIZE, ICON_SIZE)
    Fade(btn.IconTextureOverlay, true)
    if not own.ring and btn.CreateTexture then
        local ring = btn:CreateTexture(nil, "OVERLAY")
        ring:SetTexture(ART.ring)
        ring:SetSize(RING_SIZE, RING_SIZE)
        ring:SetPoint("CENTER", btn, "CENTER", 0, -1)
        own.ring = ring
    end
    if own.ring then own.ring:Show() end
    Colour(btn.spellString, {1, 0.82, 0})
    Colour(btn.subSpellString, BROWN_TEXT)
end

local function UnskinSpellButton(btn)
    if not btn then return end
    local own = M.own[btn]
    Restore(btn)
    Fade(btn.IconTextureOverlay, false)
    if own and own.ring then own.ring:Hide() end
    Restore(btn.spellString)
    Restore(btn.subSpellString)
end

local function SkinRow(psf, spec, on)
    local row = Row(psf, spec.name)
    if not row then return false end
    local own = Own(row)
    if on then
        Anchor(row, "TOPLEFT", psf, "TOPLEFT", ROW_X, spec.y, ROW_W, ROW_H)
        Fade(row.Background, true)
        Anchor(row.ProfessionName, "TOPLEFT", row, "TOPLEFT", NAME_X, NAME_Y)
        Anchor(row.missingHeader, "TOPLEFT", row, "TOPLEFT", NAME_X, NAME_Y)
        Anchor(row.missingText, "TOPLEFT", row, "TOPLEFT", NAME_X, BUTTON_Y, ROW_W - 2 * NAME_X - 2, ROW_H + BUTTON_Y)
        if row.missingText and row.missingText.SetJustifyH then row.missingText:SetJustifyH("LEFT") end
        Colour(row.missingText, PARCHMENT_TEXT)
        SkinSpellButton(row.SpellButton1, row, BUTTON_X[1])
        SkinSpellButton(row.SpellButton2, row, BUTTON_X[2])
        Fade(row.StatusBar, true)
        if not own.bar then own.bar = SkillBar(row) end
        FillBar(own.bar, row, spec)
        Anchor(row.UnlearnButton, "LEFT", own.bar, "RIGHT", 8, 0)
    else
        Restore(row)
        Fade(row.Background, false)
        Restore(row.ProfessionName)
        Restore(row.missingHeader)
        Restore(row.missingText)
        UnskinSpellButton(row.SpellButton1)
        UnskinSpellButton(row.SpellButton2)
        Fade(row.StatusBar, false)
        if own.bar then own.bar:Hide() end
        Restore(row.UnlearnButton)
    end
    return true
end

-- a side tab as an Era skill line tab: 32px icon in the 64x64 tab art
local function SkinTab(psf, tab, i, on)
    local own = Own(tab)
    local icon = tab.Icon
    if on then
        Anchor(tab, "TOPLEFT", psf, "TOPRIGHT", TAB_X, TAB_Y - (i - 1) * (TAB_SIZE + TAB_GAP), TAB_SIZE, TAB_SIZE)
        if tab.SetFrameLevel and M.book then tab:SetFrameLevel(M.book:GetFrameLevel() + 2) end
        Anchor(icon, "TOPLEFT", tab, "TOPLEFT", 0, 0, TAB_SIZE, TAB_SIZE)
        if icon and tab.Mask and icon.RemoveMaskTexture then pcall(icon.RemoveMaskTexture, icon, tab.Mask) end
        Fade(tab.Background, true)
        Fade(tab.SelectedTexture, true)
        Fade(tab.TabGlow, true)
        Fade(tab.HighlightTexture, true)
        if not own.bg and tab.CreateTexture then
            own.bg = tab:CreateTexture(nil, "BACKGROUND")
            own.bg:SetTexture(ART.skillTab)
            own.bg:SetSize(64, 64)
            own.bg:SetPoint("TOPLEFT", tab, "TOPLEFT", -3, 11)
            own.checked = tab:CreateTexture(nil, "OVERLAY")
            own.checked:SetTexture(ART.checked)
            own.checked:SetBlendMode("ADD")
            own.checked:SetAllPoints(tab)
            own.highlight = tab:CreateTexture(nil, "HIGHLIGHT")
            own.highlight:SetTexture(ART.highlight)
            own.highlight:SetBlendMode("ADD")
            own.highlight:SetAllPoints(tab)
        end
        if own.bg then
            own.bg:Show()
            own.highlight:Show()
            local selected = tab.SelectedTexture and tab.SelectedTexture.IsShown and tab.SelectedTexture:IsShown() == true
            own.checked:SetShown(selected)
        end
    else
        Restore(tab)
        Restore(icon)
        if icon and tab.Mask and icon.AddMaskTexture then pcall(icon.AddMaskTexture, icon, tab.Mask) end
        Fade(tab.Background, false)
        Fade(tab.SelectedTexture, false)
        Fade(tab.TabGlow, false)
        Fade(tab.HighlightTexture, false)
        if own.bg then own.bg:Hide(); own.checked:Hide(); own.highlight:Hide() end
    end
end

local function SkinTabs(psf, on)
    local tabs = Tabs(psf)
    for i, tab in ipairs(tabs) do SkinTab(psf, tab, i, on) end
    M.tabs = #tabs
end

--------------------------------------------------------------------------
-- Blizzard's frame: shell on/off
--------------------------------------------------------------------------

local function Shell(psf, classic)
    Fade(psf.NineSlice, classic)
    Fade(psf.Bg, classic)
    Fade(psf.TopTileStreaks, classic)
    Fade(psf.Inset, classic)
    Fade(psf.CloseButton, classic)
    Mouse(psf.CloseButton, not classic)
    Fade(psf.TitleContainer, classic)
    Fade(psf.MainHelpButton, classic)
    Mouse(psf.MainHelpButton, not classic)
    -- anything else drawn straight on the frame
    if psf.GetRegions then
        for _, region in ipairs({psf:GetRegions()}) do
            if region.SetAlpha then region:SetAlpha(classic and 0 or 1) end
        end
    end
    local portrait = psf.PortraitContainer and psf.PortraitContainer.portrait
    local mask = psf.PortraitContainer and psf.PortraitContainer.CircleMask
    if classic then
        -- Era: the book icon 58x58 in the corner
        Anchor(portrait, "TOPLEFT", psf, "TOPLEFT", 10, -8, 58, 58)
        if mask then
            Remember(mask)
            mask:ClearAllPoints()
            mask:SetPoint("TOPLEFT", portrait, "TOPLEFT", 0, 0)
            mask:SetPoint("BOTTOMRIGHT", portrait, "BOTTOMRIGHT", 0, 0)
        end
    else
        Restore(portrait)
        Restore(mask)
    end
    M.rows = 0
    for _, spec in ipairs(ROWS) do
        if SkinRow(psf, spec, classic) then M.rows = M.rows + 1 end
    end
    SkinTabs(psf, classic)
end

local function Rows(psf)
    for _, spec in ipairs(ROWS) do SkinRow(psf, spec, true) end
    SkinTabs(psf, true)
end

function M.Apply()
    if M.mode ~= "restyled" then return end
    local psf = G(FRAME_NAME)
    if not psf then return end
    local classic = PageShown(psf)
    if classic ~= M.applied then
        Shell(psf, classic)
        M.applied = classic
    elseif classic then
        -- Blizzard's refresh puts its art and layout back on the cards
        Rows(psf)
    end
    if classic then
        M.resizing = true
        psf:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
        M.resizing = nil
        if SetUIPanelAttribute then pcall(SetUIPanelAttribute, psf, "width", PANEL_WIDTH) end
        M.book:Show()
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

-- Blizzard lays the cards out in the same update we are hooked to, so
-- ours runs again a frame later as well
local function ApplyLater()
    M.Apply()
    if C_Timer and C_Timer.After then C_Timer.After(0, Guard("later", M.Apply)) end
end

local function Undo()
    local psf = G(FRAME_NAME)
    if not psf then return end
    Shell(psf, false)
    M.applied = false
    if M.book then M.book:Hide() end
    if M.savedSize and M.savedSize[1] then
        M.resizing = true
        psf:SetSize(M.savedSize[1], M.savedSize[2])
        M.resizing = nil
    end
    if SetUIPanelAttribute and M.savedPanelWidth then pcall(SetUIPanelAttribute, psf, "width", M.savedPanelWidth) end
end

local function HookMethod(frame, name)
    if frame and type(frame[name]) == "function" then
        hooksecurefunc(frame, name, Guard(name, ApplyLater))
    end
end

local function Hook()
    if M.hooked then return end
    local psf = G(FRAME_NAME)
    if not psf or not hooksecurefunc then return end
    hooksecurefunc(psf, "SetSize", Guard("SetSize", function(_, w, h)
        if M.resizing or M.mode ~= "restyled" then return end
        if PageShown(psf) then
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
        psf:HookScript("OnShow", Guard("OnShow", ApplyLater))
        psf:HookScript("OnHide", Guard("OnHide", function() if M.book then M.book:Hide() end end))
    end
    local page = Page(psf)
    if page and page.HookScript then
        page:HookScript("OnShow", Guard("page OnShow", ApplyLater))
        page:HookScript("OnHide", Guard("page OnHide", M.Apply))
    end
    -- Blizzard fills the cards again on every update
    for _, name in ipairs({"Update", "Refresh", "UpdateTabs", "UpdateProfessions"}) do
        HookMethod(psf, name)
        HookMethod(page, name)
        HookMethod(Content(psf), name)
    end
    if type(ProfessionsBook_Update) == "function" then hooksecurefunc("ProfessionsBook_Update", Guard("ProfessionsBook_Update", ApplyLater)) end
    if not M.events and CreateFrame then
        local ev = CreateFrame("Frame")
        for _, e in ipairs(REFRESH_EVENTS) do pcall(ev.RegisterEvent, ev, e) end
        ev:SetScript("OnEvent", Guard("event", function()
            if psf.IsShown and psf:IsShown() then ApplyLater() end
        end))
        M.events = ev
    end
    M.hooked = true
end

--------------------------------------------------------------------------
-- module interface
--------------------------------------------------------------------------

local function IsForeverBook()
    local psf = G(FRAME_NAME)
    return psf ~= nil and Row(psf, "PrimaryProfession1") ~= nil
end

-- the window may be load-on-demand: finish enabling once it exists
local function WatchForBook()
    if M.watcher or not CreateFrame then return end
    local watcher = CreateFrame("Frame")
    watcher:RegisterEvent("ADDON_LOADED")
    pcall(watcher.RegisterEvent, watcher, "PLAYER_ENTERING_WORLD")
    watcher:SetScript("OnEvent", function()
        if M.mode ~= "waiting" then return end
        if IsForeverBook() then
            if ns.SafeCall("professions", M.Enable, M) and M.mode == "restyled" then
                watcher:UnregisterAllEvents()
            end
        end
    end)
    M.watcher = watcher
end

function M:Enable()
    if G("SpellBookFrame") and not G("PlayerSpellsFrame") then
        self.mode = "native" -- classic client: professions in the skills tab, no window
        return
    end
    if not IsForeverBook() then
        self.mode = "waiting"
        WatchForBook()
        if self.watcher then self.watcher:RegisterEvent("ADDON_LOADED") end
        return
    end
    self.missingArt = {}
    for _, key in ipairs({"topLeft", "topRight", "bottomLeft", "bottomRight", "ring", "bar", "barBorder", "skillTab"}) do
        if not HasFile(ART[key]) then self.missingArt[#self.missingArt + 1] = ART[key]:match("[^\\]+$") end
    end
    local psf = G(FRAME_NAME)
    if not self.savedSize and psf.GetSize then self.savedSize = {psf:GetSize()} end
    if not self.savedPanelWidth and GetUIPanelAttribute then
        local ok, w = pcall(GetUIPanelAttribute, psf, "width")
        if ok and type(w) == "number" then self.savedPanelWidth = w end
    end
    if not self.book then self.book = BuildBook(psf) end
    self.mode = "restyled"
    self.applied = nil
    Hook()
    if psf.IsShown and psf:IsShown() then M.Apply() end
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
        local s = ("classic 384x512 book, %d profession rows down the page, %d side tabs as skill line tabs"):format(self.rows or 0, self.tabs or 0)
        if self.applied == false then s = s .. " (crafting page up: retail size until it gets its classic version)" end
        if self.missingArt and #self.missingArt > 0 then
            s = s .. " (art missing: " .. table.concat(self.missingArt, ", ") .. ")"
        end
        return s
    elseif self.mode == "native" then
        return "classic client, no professions window"
    elseif self.mode == "waiting" then
        return "waiting for Blizzard's professions window (ProfessionsFrame) to exist"
    end
    return "off"
end

ns.RegisterModule("professions", M)
