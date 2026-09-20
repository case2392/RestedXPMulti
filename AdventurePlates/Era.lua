-- Adventure Plates - Classic Era furniture
--
-- The plate is drawn on Era's spellbook page: the four UI-SpellbookPanel
-- quarters cut into a nine-slice whose numbers were read off the texture
-- files (the page is a 384x512 canvas of which the drawn book is the
-- top-left 352x445: an 88px stone header band with the round portrait
-- hole centred at 41.5,41.5, bevelled sides 88px and 48px wide, a torn
-- foot 45px tall, plain parchment between). Corners are drawn at their
-- own size, edges stretch along their run, and the middle is a patch of
-- plain parchment stretched over the inside. A dark disc sits behind the
-- portrait hole and the plate puts a portrait in it. This is the same
-- cut Classic UI for Forever uses; it lives here too so this addon needs
-- nothing else installed.

local addonName, ns = ...

local SB = "Interface\\Spellbook\\"
ns.ERA = {
    topLeft = SB .. "UI-SpellbookPanel-TopLeft",
    topRight = SB .. "UI-SpellbookPanel-TopRight",
    botLeft = SB .. "UI-SpellbookPanel-BotLeft",
    botRight = SB .. "UI-SpellbookPanel-BotRight",
    disc = "Interface\\Minimap\\UI-Minimap-Background",
    closeUp = "Interface\\Buttons\\UI-Panel-MinimizeButton-Up",
    closeDown = "Interface\\Buttons\\UI-Panel-MinimizeButton-Down",
    closeHighlight = "Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight",
    rotateLeftUp = "Interface\\Buttons\\UI-RotationLeft-Button-Up",
    rotateLeftDown = "Interface\\Buttons\\UI-RotationLeft-Button-Down",
    rotateRightUp = "Interface\\Buttons\\UI-RotationRight-Button-Up",
    rotateRightDown = "Interface\\Buttons\\UI-RotationRight-Button-Down",
    rotateHighlight = "Interface\\Buttons\\UI-Common-MouseHilight",
    -- the text colours of an Era page: gold headings, brown body
    gold = {1, 0.82, 0},
    brown = {0.35, 0.2, 0},
    ink = {0.2, 0.1, 0}
}

local P = {X1 = 88, X2 = 304, XEND = 352, Y1 = 88, Y2 = 400, YEND = 445, RING_X = 41.5, RING_Y = 41.5, RING_HOLE = 66, RING_DISC = 64, RIGHT_W = 128}
ns.ERA_PAGE = P
local LEFT_W, RIGHT_W = P.X1, P.XEND - P.X2
local HEAD_H, FOOT_H = P.Y1, P.YEND - P.Y2
local FLOOR = {0.25, 0.20, 0.13, 1}

function ns.HasFile(path)
    if not GetFileIDFromPath then return true end
    local ok, id = pcall(GetFileIDFromPath, path)
    return ok and id ~= nil
end

local function Coords(x0, y0, x1, y1)
    local file, u0, u1, v0, v1
    if y0 < 256 then
        v0, v1 = y0 / 256, y1 / 256
        if x0 < 256 then file, u0, u1 = ns.ERA.topLeft, x0 / 256, x1 / 256
        else file, u0, u1 = ns.ERA.topRight, (x0 - 256) / P.RIGHT_W, (x1 - 256) / P.RIGHT_W end
    else
        v0, v1 = (y0 - 256) / 256, (y1 - 256) / 256
        if x0 < 256 then file, u0, u1 = ns.ERA.botLeft, x0 / 256, x1 / 256
        else file, u0, u1 = ns.ERA.botRight, (x0 - 256) / P.RIGHT_W, (x1 - 256) / P.RIGHT_W end
    end
    return file, u0, u1, v0, v1
end

local function Piece(panel, x0, y0, x1, y1)
    local t = panel:CreateTexture(nil, "BACKGROUND", nil, -1)
    local file, u0, u1, v0, v1 = Coords(x0, y0, x1, y1)
    t:SetTexture(file)
    t:SetTexCoord(u0, u1, v0, v1)
    return t
end

-- a frame dressed as Era's page, with the header band and the ring
function ns.BuildEraPage(name, parent)
    local panel = CreateFrame("Frame", name, parent)
    local fill = panel:CreateTexture(nil, "BACKGROUND", nil, -3)
    fill:SetAllPoints(panel)
    fill:SetColorTexture(FLOOR[1], FLOOR[2], FLOOR[3], FLOOR[4])
    panel.fill = fill
    local pc = {}
    pc.topLeft = Piece(panel, 0, 0, P.X1, P.Y1)
    pc.topRight = Piece(panel, P.X2, 0, P.XEND, P.Y1)
    pc.top = Piece(panel, P.X1, 0, 256, P.Y1)
    pc.bottomLeft = Piece(panel, 0, P.Y2, P.X1, P.YEND)
    pc.bottomRight = Piece(panel, P.X2, P.Y2, P.XEND, P.YEND)
    pc.bottom = Piece(panel, P.X1, P.Y2, 256, P.YEND)
    pc.left = Piece(panel, 0, 256, P.X1, P.Y2)
    pc.right = Piece(panel, P.X2, 256, P.XEND, P.Y2)
    pc.center = Piece(panel, P.X1, 256, 256, P.Y2)
    pc.topLeft:SetSize(LEFT_W, HEAD_H)
    pc.topLeft:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    pc.topRight:SetSize(RIGHT_W, HEAD_H)
    pc.topRight:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, 0)
    pc.bottomLeft:SetSize(LEFT_W, FOOT_H)
    pc.bottomLeft:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 0, 0)
    pc.bottomRight:SetSize(RIGHT_W, FOOT_H)
    pc.bottomRight:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)
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
    local disc = panel:CreateTexture(nil, "BACKGROUND", nil, -2)
    disc:SetTexture(ns.ERA.disc)
    disc:SetSize(P.RING_DISC, P.RING_DISC)
    disc:SetPoint("CENTER", panel, "TOPLEFT", P.RING_X, -P.RING_Y)
    panel.disc = disc
    -- what goes in the ring
    local portrait = panel:CreateTexture(nil, "BACKGROUND", nil, 0)
    portrait:SetSize(P.RING_HOLE - 8, P.RING_HOLE - 8)
    portrait:SetPoint("CENTER", panel, "TOPLEFT", P.RING_X, -P.RING_Y)
    panel.portrait = portrait
    panel.ring = {x = P.RING_X, y = -P.RING_Y, size = P.RING_HOLE - 8}
    panel.header = HEAD_H
    panel.foot = FOOT_H
    return panel
end

-- Era's X, in the corner where every Era window had it
function ns.EraCloseButton(parent, onClick)
    local close = CreateFrame("Button", nil, parent)
    close:SetSize(32, 32)
    close:SetPoint("CENTER", parent, "TOPRIGHT", -44, -25)
    close:SetNormalTexture(ns.ERA.closeUp)
    close:SetPushedTexture(ns.ERA.closeDown)
    close:SetHighlightTexture(ns.ERA.closeHighlight, "ADD")
    close:SetScript("OnClick", onClick)
    return close
end

function ns.EraArtMissing()
    local missing = {}
    for _, key in ipairs({"topLeft", "topRight", "botLeft", "botRight"}) do
        if not ns.HasFile(ns.ERA[key]) then missing[#missing + 1] = ns.ERA[key]:match("[^\\]+$") end
    end
    return missing
end
