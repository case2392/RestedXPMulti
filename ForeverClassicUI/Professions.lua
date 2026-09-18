-- Forever Classic UI - the professions window
--
-- Forever's professions window is retail's "professions book"
-- (Blizzard_ProfessionsBook, opened by the professions micro button): a
-- 550x525 metal frame with two primary rows (icon, name, rank bar, the
-- two profession spell buttons) and three secondary boxes. Era had no
-- such window at all (professions lived in the Skills tab), so the
-- classic reference is the pre-retail spellbook's Professions page: the
-- same 384x512 book as the spellbook, the professions as rows down the
-- page.
--
-- What this part does while the window is up:
--   * the frame is resized to 384x512 (Blizzard's own SetSize is undone,
--     as the spellbook part does) and its retail shell (nine-slice, page
--     art, title, close button, inset) faded; the Era book art goes on a
--     frame of ours, with the book icon in the corner and "Professions"
--     over the top edge;
--   * Blizzard's five rows (PrimaryProfession1/2, SecondaryProfession1-3)
--     stay the live frames: their spell buttons cast and drag, the rank
--     bar and unlearn button keep working. They are scaled to fit the
--     book's width and re-anchored down the page; their retail art (icon
--     ring, name plates behind the spell buttons, bar art) is faded and
--     the classic quickslot ring and skill-bar fill drawn instead.
-- Rule as elsewhere: widget calls and hooksecurefunc only; nothing of
-- ours written into Blizzard's tables (M.own holds what hangs on them).

local addonName, ns = ...

local M = {mode = "off"}

local SB = "Interface\\Spellbook\\"
local ART = {
    topLeft = SB .. "UI-SpellbookPanel-TopLeft",
    topRight = SB .. "UI-SpellbookPanel-TopRight",
    bottomLeft = SB .. "UI-SpellbookPanel-BotLeft",
    bottomRight = SB .. "UI-SpellbookPanel-BotRight",
    ring = "Interface\\Buttons\\UI-Quickslot2",
    bar = "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar",
    closeUp = "Interface\\Buttons\\UI-Panel-MinimizeButton-Up",
    closeDown = "Interface\\Buttons\\UI-Panel-MinimizeButton-Down",
    closeHighlight = "Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight"
}

local FRAME_WIDTH, FRAME_HEIGHT = 384, 512
local PANEL_WIDTH = 400
-- retail rows are 437 wide; the book's page is 340: scale them to fit
local ROW_SCALE = 340 / 437
local ROW_X = 22
-- rows down the page, top edges (book units): two primaries (81 tall
-- scaled to 63) and three secondaries (46 -> 36)
local ROWS = {
    {name = "PrimaryProfession1", y = -70},
    {name = "PrimaryProfession2", y = -143},
    {name = "SecondaryProfession1", y = -226},
    {name = "SecondaryProfession2", y = -282},
    {name = "SecondaryProfession3", y = -338}
}
local FRAME_NAME = "ProfessionsBookFrame"
local BLIZZARD_ADDON = "Blizzard_ProfessionsBook"

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

local function Remember(region)
    local own = Own(region)
    if own.saved then return end
    local saved = {points = {}}
    if region.GetNumPoints and region.GetPoint then
        for i = 1, region:GetNumPoints() do saved.points[i] = {region:GetPoint(i)} end
    end
    if region.GetSize then saved.width, saved.height = region:GetSize() end
    if region.GetScale then saved.scale = region:GetScale() end
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
    if saved.scale and region.SetScale then region:SetScale(saved.scale) end
end

local function Anchor(region, point, rel, relPoint, x, y, w, h)
    if not region then return end
    Remember(region)
    region:ClearAllPoints()
    region:SetPoint(point, rel, relPoint, x, y)
    if w then region:SetSize(w, h) end
end

-- a row by its retail global name, or by key on the content frame
local function Row(psf, name)
    local row = G(name)
    if row then return row end
    local content = psf and psf.ProfessionsContentFrame
    return content and content[name]
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
-- Blizzard's rows made classic
--------------------------------------------------------------------------

-- a profession spell button: retail's name plate art faded, the classic
-- quickslot ring round the 40px icon (a texture of ours on the button)
local function SkinSpellButton(btn)
    if not btn then return end
    local own = Own(btn)
    local nameFrame = btn.GetName and G(btn:GetName() .. "NameFrame")
    Fade(nameFrame, true)
    if not own.ring and btn.CreateTexture then
        local ring = btn:CreateTexture(nil, "OVERLAY")
        ring:SetTexture(ART.ring)
        ring:SetSize(68, 68)
        ring:SetPoint("CENTER", btn, "CENTER", 0, -1)
        own.ring = ring
    end
    if own.ring then own.ring:Show() end
    -- retail's spell names are white and grey on the dark page; on the
    -- parchment they read as the book's gold and brown
    if btn.spellString and btn.spellString.SetTextColor then btn.spellString:SetTextColor(1, 0.82, 0) end
    if btn.subSpellString and btn.subSpellString.SetTextColor then btn.subSpellString:SetTextColor(0.5, 0.35, 0.05) end
end

local function UnskinSpellButton(btn)
    if not btn then return end
    local own = M.own[btn]
    local nameFrame = btn.GetName and G(btn:GetName() .. "NameFrame")
    Fade(nameFrame, false)
    if own and own.ring then own.ring:Hide() end
    if btn.spellString and btn.spellString.SetTextColor then btn.spellString:SetTextColor(1, 1, 1) end
    if btn.subSpellString and btn.subSpellString.SetTextColor then btn.subSpellString:SetTextColor(0.5, 0.5, 0.5) end
end

-- the rank bar: Era's blue skill-bar fill over a dark backing; retail's
-- rounded bar art faded
local function SkinBar(bar, on)
    if not bar then return end
    local own = Own(bar)
    local name = bar.GetName and bar:GetName()
    for _, suffix in ipairs({"Left", "BGLeft", "BGRight", "BGMiddle"}) do
        Fade(name and G(name .. suffix), on)
    end
    Fade(bar.capRight, on)
    if on then
        if not own.backing and bar.CreateTexture then
            own.backing = bar:CreateTexture(nil, "BACKGROUND")
            own.backing:SetColorTexture(0, 0, 0, 0.5)
            own.backing:SetAllPoints(bar)
        end
        if own.backing then own.backing:Show() end
        if bar.SetStatusBarTexture and HasFile(ART.bar) then
            bar:SetStatusBarTexture(ART.bar)
            if bar.SetStatusBarColor then bar:SetStatusBarColor(0.25, 0.25, 0.75) end
        end
    elseif own.backing then
        own.backing:Hide()
    end
end

local function SkinRow(psf, spec, on)
    local row = Row(psf, spec.name)
    if not row then return false end
    local name = row.GetName and row:GetName() or spec.name
    if on then
        Anchor(row, "TOPLEFT", psf, "TOPLEFT", ROW_X / ROW_SCALE, spec.y / ROW_SCALE)
        if row.SetScale then row:SetScale(ROW_SCALE) end
        Fade(G(name .. "IconBorder"), true)
        SkinSpellButton(row.SpellButton1)
        SkinSpellButton(row.SpellButton2)
        SkinBar(row.statusBar, true)
        -- retail's white rank text on the parchment: the page's brown
        if row.rank and row.rank.SetTextColor then row.rank:SetTextColor(0.25, 0.12, 0) end
    else
        Restore(row)
        Fade(G(name .. "IconBorder"), false)
        UnskinSpellButton(row.SpellButton1)
        UnskinSpellButton(row.SpellButton2)
        SkinBar(row.statusBar, false)
        if row.rank and row.rank.SetTextColor then row.rank:SetTextColor(1, 1, 1) end
    end
    return true
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
    -- the retail page art (two textures on the frame) and anything else drawn on it
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
end

function M.Apply()
    if M.mode ~= "restyled" then return end
    local psf = G(FRAME_NAME)
    if not psf then return end
    if M.applied ~= true then
        Shell(psf, true)
        M.applied = true
    else
        -- Blizzard's refresh puts its art back on the rows
        for _, spec in ipairs(ROWS) do SkinRow(psf, spec, true) end
    end
    M.resizing = true
    psf:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
    M.resizing = nil
    if SetUIPanelAttribute then pcall(SetUIPanelAttribute, psf, "width", PANEL_WIDTH) end
    M.book:Show()
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

local function Hook()
    if M.hooked then return end
    local psf = G(FRAME_NAME)
    if not psf or not hooksecurefunc then return end
    hooksecurefunc(psf, "SetSize", Guard("SetSize", function(_, w, h)
        if M.resizing or M.mode ~= "restyled" then return end
        if w ~= FRAME_WIDTH or h ~= FRAME_HEIGHT then
            M.resizing = true
            psf:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
            M.resizing = nil
        end
    end))
    if psf.HookScript then
        psf:HookScript("OnShow", Guard("OnShow", M.Apply))
        psf:HookScript("OnHide", Guard("OnHide", function() if M.book then M.book:Hide() end end))
    end
    -- Blizzard fills the rows again on every update
    if type(psf.Update) == "function" then hooksecurefunc(psf, "Update", Guard("Update", M.Apply)) end
    if type(ProfessionsBook_Update) == "function" then hooksecurefunc("ProfessionsBook_Update", Guard("ProfessionsBook_Update", M.Apply)) end
    M.hooked = true
end

--------------------------------------------------------------------------
-- module interface
--------------------------------------------------------------------------

local function IsForeverBook()
    local psf = G(FRAME_NAME)
    return psf ~= nil and Row(psf, "PrimaryProfession1") ~= nil
end

local function WatchForBook()
    if M.watcher or not CreateFrame then return end
    local watcher = CreateFrame("Frame")
    watcher:RegisterEvent("ADDON_LOADED")
    watcher:SetScript("OnEvent", function(_, _, name)
        if M.mode ~= "waiting" then return end
        if name == BLIZZARD_ADDON or IsForeverBook() then
            if IsForeverBook() then
                watcher:UnregisterEvent("ADDON_LOADED")
                ns.SafeCall("professions", M.Enable, M)
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
        -- retail keeps the professions book load-on-demand: wait for it
        self.mode = "waiting"
        WatchForBook()
        if self.watcher then self.watcher:RegisterEvent("ADDON_LOADED") end
        return
    end
    self.missingArt = {}
    for _, key in ipairs({"topLeft", "topRight", "bottomLeft", "bottomRight", "ring", "bar"}) do
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
        local s = ("classic 384x512 book, %d profession rows scaled onto the page"):format(self.rows or 0)
        if self.missingArt and #self.missingArt > 0 then
            s = s .. " (art missing: " .. table.concat(self.missingArt, ", ") .. ")"
        end
        return s
    elseif self.mode == "native" then
        return "classic client, no professions window"
    elseif self.mode == "waiting" then
        return "waiting for Blizzard's professions window to load (it loads the first time it is opened)"
    end
    return "off"
end

ns.RegisterModule("professions", M)
