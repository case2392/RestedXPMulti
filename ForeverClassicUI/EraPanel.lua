-- Forever Classic UI - an Era-looking panel at any size
--
-- This is Era's spellbook page - the art the professions window draws on
-- this client, so it is known to be here and known to be Era's - cut into
-- a nine-slice whose numbers were read off the texture files themselves
-- rather than guessed. Four attempts before this went wrong, and each one
-- taught something that is now built in:
--
--  * 0.7.1/0.7.2 stretched the four quarters whole. The decoration (the
--    portrait ring, the header tab, the torn corners) is baked into the
--    corners of a 384x512 page and pulls out of shape at any other size.
--  * 0.7.4/0.7.5 used the dialog backdrop (UI-DialogBox-Background and
--    -Border). That is Era's stone-and-rope on an Era client, but Forever
--    runs the retail engine and its copies of those two files are a 64px
--    black tile at 60% alpha and a hairline border. The panels drew
--    exactly that: a faint dark tint the world showed through, which is
--    why they looked see-through. Nothing was invisible; it was black.
--  * 0.7.6/0.7.8 fell back to flat colour, which is not a window at all.
--  * 0.7.7 cut this very page into a nine-slice but guessed where the
--    plain paper was: it took the top-left quarter's pixels 31..97 in
--    both axes, which is the portrait ring and the header band, hence the
--    swooping curves.
--
-- The geometry below comes from the files. The page is four quarters -
-- TopLeft and BotLeft 256x256, TopRight and BotRight 128x256 (the right
-- quarters are 128 wide on this client, as the spellbook module draws
-- them) - laid out as a 384x512 canvas of which the drawn book is the
-- top-left 352x445. Inside that: a dark stone header band 88px tall with
-- the round portrait hole centred at 41.5,41.5 (66px across) and a small
-- tab at the top right; a bevelled frame down each side; a torn lower
-- edge 45px tall; and between them, plain parchment. The corners are
-- drawn at their own size, the four edges are stretched along their run
-- (each is uniform along it), and the centre is a 168x144 patch of plain
-- parchment from the bottom-left quarter stretched over the inside.
-- Stretching soft parchment reads as parchment; every other way of
-- filling the middle (tiling, mirrored tiling) was rendered from the
-- files and looked worse.
--
-- Every piece comes from ONE quarter file, so each texcoord is a plain
-- fraction of 256 or 128 and nothing straddles a seam. A panel can be
-- built without the header (opts.header = false): then the bottom pieces
-- are flipped upside down to serve as the top, which makes a bevelled
-- sheet with no ring - the right thing for a list that lives inside
-- another window. A dark disc sits behind the portrait hole so the hole
-- never shows the world; a module can put the window's own portrait in
-- it with ns.EraPanelRing. A plain fill sits under everything so that if
-- a file ever fails to draw the window is still a window.

local addonName, ns = ...

local SB = "Interface\\Spellbook\\"
ns.ERA_PANEL = {
    topLeft = SB .. "UI-SpellbookPanel-TopLeft",
    topRight = SB .. "UI-SpellbookPanel-TopRight",
    botLeft = SB .. "UI-SpellbookPanel-BotLeft",
    botRight = SB .. "UI-SpellbookPanel-BotRight",
    -- behind the portrait hole: the minimap's dark round backdrop, which
    -- the map window's tracking pin draws on this client
    disc = "Interface\\Minimap\\UI-Minimap-Background"
}

-- the page, in pixels of the 384x512 canvas (see the header comment)
ns.ERA_PAGE = {
    X1 = 88, X2 = 304, XEND = 352,     -- column cuts and where the book ends
    Y1 = 88, Y2 = 400, YEND = 445,     -- row cuts and where the book ends
    RING_X = 41.5, RING_Y = 41.5, RING_HOLE = 66, RING_DISC = 64,
    RIGHT_FILE_W = 128                 -- the -Right quarters' width
}
local P = ns.ERA_PAGE
local LEFT_W, RIGHT_W = P.X1, P.XEND - P.X2          -- 88, 48
local HEAD_H, FOOT_H = P.Y1, P.YEND - P.Y2           -- 88, 45
local FLOOR = {0.25, 0.20, 0.13, 1}

-- keep the fill and disc under the art: lower sublevels draw first
local SUB_FLOOR, SUB_DISC, SUB_ART = -3, -2, -1

local function HasFile(path)
    if not GetFileIDFromPath then return true end
    local ok, id = pcall(GetFileIDFromPath, path)
    return ok and id ~= nil
end

function ns.EraPanelArtMissing()
    local missing = {}
    for _, key in ipairs({"topLeft", "topRight", "botLeft", "botRight"}) do
        local path = ns.ERA_PANEL[key]
        if not HasFile(path) then missing[#missing + 1] = path:match("[^\\]+$") end
    end
    return missing
end

-- page pixel rect -> the quarter file it lives in and its UVs there
local function Coords(x0, y0, x1, y1)
    local file, u0, u1, v0, v1
    if y0 < 256 then
        v0, v1 = y0 / 256, y1 / 256
        if x0 < 256 then file, u0, u1 = ns.ERA_PANEL.topLeft, x0 / 256, x1 / 256
        else file, u0, u1 = ns.ERA_PANEL.topRight, (x0 - 256) / P.RIGHT_FILE_W, (x1 - 256) / P.RIGHT_FILE_W end
    else
        v0, v1 = (y0 - 256) / 256, (y1 - 256) / 256
        if x0 < 256 then file, u0, u1 = ns.ERA_PANEL.botLeft, x0 / 256, x1 / 256
        else file, u0, u1 = ns.ERA_PANEL.botRight, (x0 - 256) / P.RIGHT_FILE_W, (x1 - 256) / P.RIGHT_FILE_W end
    end
    return file, u0, u1, v0, v1
end

local function Piece(panel, x0, y0, x1, y1, flipV)
    local t = panel:CreateTexture(nil, "BACKGROUND", nil, SUB_ART)
    local file, u0, u1, v0, v1 = Coords(x0, y0, x1, y1)
    t:SetTexture(file)
    if flipV then
        -- the eight-number form: UL, LL, UR, LR - top and bottom swapped
        t:SetTexCoord(u0, v1, u0, v0, u1, v1, u1, v0)
    else
        t:SetTexCoord(u0, u1, v0, v1)
    end
    return t
end

-- name, parent, and opts.header (default true): the stone header band
-- with the portrait ring across the top, or a plain bevelled top
function ns.BuildEraPanel(name, parent, opts)
    if not CreateFrame then return nil end
    local ok, panel = pcall(CreateFrame, "Frame", name, parent)
    if not ok or not panel then return nil end
    if not panel.CreateTexture then return panel end
    local header = not (opts and opts.header == false)
    panel.header = header

    local fill = panel:CreateTexture(nil, "BACKGROUND", nil, SUB_FLOOR)
    fill:SetAllPoints(panel)
    fill:SetColorTexture(FLOOR[1], FLOOR[2], FLOOR[3], FLOOR[4])
    panel.fill = fill

    local topH = header and HEAD_H or FOOT_H
    local pc = {}
    -- corners at their own size; without the header the bottom corners
    -- are flipped to make the top ones
    if header then
        pc.topLeft = Piece(panel, 0, 0, P.X1, P.Y1)
        pc.topRight = Piece(panel, P.X2, 0, P.XEND, P.Y1)
        pc.top = Piece(panel, P.X1, 0, 256, P.Y1)
    else
        pc.topLeft = Piece(panel, 0, P.Y2, P.X1, P.YEND, true)
        pc.topRight = Piece(panel, P.X2, P.Y2, P.XEND, P.YEND, true)
        pc.top = Piece(panel, P.X1, P.Y2, 256, P.YEND, true)
    end
    pc.bottomLeft = Piece(panel, 0, P.Y2, P.X1, P.YEND)
    pc.bottomRight = Piece(panel, P.X2, P.Y2, P.XEND, P.YEND)
    pc.bottom = Piece(panel, P.X1, P.Y2, 256, P.YEND)
    pc.left = Piece(panel, 0, 256, P.X1, P.Y2)
    pc.right = Piece(panel, P.X2, 256, P.XEND, P.Y2)
    pc.center = Piece(panel, P.X1, 256, 256, P.Y2)

    pc.topLeft:SetSize(LEFT_W, topH)
    pc.topLeft:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    pc.topRight:SetSize(RIGHT_W, topH)
    pc.topRight:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, 0)
    pc.bottomLeft:SetSize(LEFT_W, FOOT_H)
    pc.bottomLeft:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 0, 0)
    pc.bottomRight:SetSize(RIGHT_W, FOOT_H)
    pc.bottomRight:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)
    -- the edges run between the corners, so they stretch with the panel
    pc.top:SetPoint("TOPLEFT", pc.topLeft, "TOPRIGHT", 0, 0)
    pc.top:SetPoint("BOTTOMRIGHT", pc.topRight, "BOTTOMLEFT", 0, 0)
    pc.bottom:SetPoint("TOPLEFT", pc.bottomLeft, "TOPRIGHT", 0, 0)
    pc.bottom:SetPoint("BOTTOMRIGHT", pc.bottomRight, "BOTTOMLEFT", 0, 0)
    pc.left:SetPoint("TOPLEFT", pc.topLeft, "BOTTOMLEFT", 0, 0)
    pc.left:SetPoint("BOTTOMRIGHT", pc.bottomLeft, "TOPRIGHT", 0, 0)
    pc.right:SetPoint("TOPLEFT", pc.topRight, "BOTTOMLEFT", 0, 0)
    pc.right:SetPoint("BOTTOMRIGHT", pc.bottomRight, "TOPRIGHT", 0, 0)
    pc.center:SetPoint("TOPLEFT", pc.topLeft, "BOTTOMRIGHT", 0, 0)
    pc.center:SetPoint("BOTTOMRIGHT", pc.bottomRight, "TOPLEFT", 0, 0)
    panel.pieces = pc
    panel.art = {pc.topLeft, pc.topRight, pc.bottomLeft, pc.bottomRight,
                 pc.top, pc.bottom, pc.left, pc.right, pc.center}

    if header then
        local disc = panel:CreateTexture(nil, "BACKGROUND", nil, SUB_DISC)
        disc:SetTexture(ns.ERA_PANEL.disc)
        disc:SetSize(P.RING_DISC, P.RING_DISC)
        disc:SetPoint("CENTER", panel, "TOPLEFT", P.RING_X, -P.RING_Y)
        panel.disc = disc
        panel.ring = {x = P.RING_X, y = -P.RING_Y, size = P.RING_HOLE - 8}
    end

    panel:Hide()
    return panel
end

--------------------------------------------------------------------------
-- the window's own portrait in the ring. Era put a portrait or an icon in
-- every window's ring; Forever's windows still carry one (the map's is
-- Era's quest log book icon), the modules just fade it with the rest of
-- the retail shell. This moves it into the ring and back again. What it
-- had is kept on our side, keyed by the texture, never written into it.
--------------------------------------------------------------------------

local saved = setmetatable({}, {__mode = "k"})

--------------------------------------------------------------------------
-- Era's bottom tab (the spellbook's and the talent frame's). Era's own
-- spellbook tab files are not Era's on Forever (its copy of
-- UI-SpellBook-Tab-Unselected draws as a retail metal box), so the tab is
-- built from the character sheet's tab art, which the client still
-- renders right: cut into three (20px ends of a 64px image) so the middle
-- stretches to whatever the label needs.
--------------------------------------------------------------------------

local TAB_ART = "Interface\\PaperDollInfoFrame\\UI-Character-InActiveTab"
local TAB_GLOW = "Interface\\PaperDollInfoFrame\\UI-Character-Tab-Highlight"
local TAB_HEIGHT, TAB_END, TAB_PAD, TAB_MIN = 32, 20, 44, 84

local function TabPiece(tab, l, r)
    local t = tab:CreateTexture(nil, "BACKGROUND")
    t:SetTexture(TAB_ART)
    t:SetSize(TAB_END, TAB_HEIGHT)
    t:SetTexCoord(l, r, 0, 1)
    return t
end

function ns.BuildEraTab(parent, text)
    local t = CreateFrame("Button", nil, parent)
    t:SetHeight(TAB_HEIGHT)
    t:SetFrameLevel(parent:GetFrameLevel() + 2)
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
    if HasFile(TAB_GLOW) then
        t:SetHighlightTexture(TAB_GLOW, "ADD")
        local hl = t:GetHighlightTexture()
        if hl then
            hl:ClearAllPoints()
            hl:SetPoint("TOPLEFT", t, "TOPLEFT", 3, 5)
            hl:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", -3, 0)
        end
    end
    return t
end

-- Era lifted the selected tab onto its own art; that file is one of the
-- ones Forever did not keep, so the selected tab is told apart the other
-- Era way (white text, button disabled), as the character sheet does.
function ns.SetEraTabSelected(tab, selected)
    tab.selected = selected
    if selected then
        if tab.Disable then tab:Disable() end
        tab.Text:SetTextColor(1, 1, 1)
    else
        if tab.Enable then tab:Enable() end
        tab.Text:SetTextColor(1, 0.82, 0)
    end
end

function ns.EraPanelRing(panel, tex, on)
    if not tex or not tex.SetPoint or not panel or not panel.ring then return end
    if on then
        if not saved[tex] then
            local s = {points = {}}
            if tex.GetNumPoints and tex.GetPoint then
                local ok, n = pcall(tex.GetNumPoints, tex)
                for i = 1, (ok and n) or 0 do
                    local okp, a, b, c, d, e = pcall(tex.GetPoint, tex, i)
                    if okp and a then s.points[#s.points + 1] = {a, b, c, d, e} end
                end
            end
            if tex.GetSize then
                local ok, w, h = pcall(tex.GetSize, tex)
                if ok then s.width, s.height = w, h end
            end
            if tex.GetAlpha then
                local ok, a = pcall(tex.GetAlpha, tex)
                if ok then s.alpha = a end
            end
            saved[tex] = s
        end
        tex:ClearAllPoints()
        tex:SetPoint("CENTER", panel, "TOPLEFT", panel.ring.x, panel.ring.y)
        if tex.SetSize then tex:SetSize(panel.ring.size, panel.ring.size) end
        if tex.SetAlpha then tex:SetAlpha(1) end
    else
        local s = saved[tex]
        if not s then return end
        tex:ClearAllPoints()
        for _, p in ipairs(s.points) do tex:SetPoint(p[1], p[2], p[3], p[4], p[5]) end
        if s.width and tex.SetSize then tex:SetSize(s.width, s.height) end
        if s.alpha and tex.SetAlpha then tex:SetAlpha(s.alpha) end
        saved[tex] = nil
    end
end
