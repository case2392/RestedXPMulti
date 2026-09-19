-- Forever Classic UI - an Era-looking panel at any size
--
-- Era's window art is four fixed quarters of a 384x512 page with the
-- decoration baked into their corners. Stretched whole across some other
-- rectangle the decoration pulls out of shape, which is why 0.7.1 and
-- 0.7.2 looked mangled.
--
-- The dialog frame (tiling UI-DialogBox-Background inside the gold
-- nine-slice UI-DialogBox-Border) would scale, and it is what 0.7.4 and
-- 0.7.5 used - but on this client GetFileIDFromPath resolves both files
-- (131071, 131072) and then nothing is drawn, so those panels were
-- invisible. 0.7.6 fell back to flat colour, which came out as a black
-- slab: Era has no black window.
--
-- Era's spellbook page does draw here - it is what the professions window
-- is built from, and that one looks right. So the panel is that page cut
-- into a nine-slice: the four corners at their own size, the four edges
-- stretched along each side, and a clean patch of parchment from the
-- middle of the page stretched over the inside. The decoration keeps its
-- proportions at any size because only plain parchment is ever stretched.
-- A solid parchment fill sits underneath in case the art ever fails.

local addonName, ns = ...

local SB = "Interface\\Spellbook\\UI-SpellbookPanel-"
ns.ERA_PANEL = {
    topLeft = SB .. "TopLeft",
    topRight = SB .. "TopRight",
    botLeft = SB .. "BotLeft",
    botRight = SB .. "BotRight"
}

-- Era's page is 384x512 drawn from four 256x256 quarters, so the right
-- quarters only use their left half (384-256 = 128 = half of 256) while
-- the bottom quarters use all of theirs. B is the decorated border as a
-- fraction of a quarter: 22 page pixels of frame.
local B = 22 / 256
local EDGE = 22          -- how wide that frame is drawn
-- a patch of plain page, clear of the frame and of the spine at u = 0.75
local PAPER = {0.12, 0.38, 0.12, 0.38}

local PARCHMENT = {0.32, 0.25, 0.16, 1}

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

-- one piece of the nine-slice: which quarter it comes from, the patch of
-- it to use, and where on the panel it goes
local function Piece(panel, path, coord, points, w, h)
    local t = panel:CreateTexture(nil, "BACKGROUND")
    t:SetTexture(path)
    t:SetTexCoord(coord[1], coord[2], coord[3], coord[4])
    if w then t:SetWidth(w) end
    if h then t:SetHeight(h) end
    for _, p in ipairs(points) do t:SetPoint(p[1], panel, p[2], p[3], p[4]) end
    return t
end

-- a frame of ours, Era's page at whatever size the caller anchors it to.
function ns.BuildEraPanel(name, parent)
    if not CreateFrame then return nil end
    local ok, panel = pcall(CreateFrame, "Frame", name, parent)
    if not ok or not panel then return nil end
    if not panel.CreateTexture then return panel end
    local art = ns.ERA_PANEL

    -- flat parchment under everything, so the panel is never a hole even
    -- if this client draws nothing for the page either
    local fill = panel:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints(panel)
    fill:SetColorTexture(PARCHMENT[1], PARCHMENT[2], PARCHMENT[3], PARCHMENT[4])
    panel.fill = fill

    local E = EDGE
    panel.art = {
        -- the page's own parchment, stretched over everything but the frame
        Piece(panel, art.topLeft, PAPER,
              {{"TOPLEFT", "TOPLEFT", E, -E}, {"BOTTOMRIGHT", "BOTTOMRIGHT", -E, E}}),
        -- the four corners, each at its own size
        Piece(panel, art.topLeft, {0, B, 0, B}, {{"TOPLEFT", "TOPLEFT", 0, 0}}, E, E),
        Piece(panel, art.topRight, {0.5 - B, 0.5, 0, B}, {{"TOPRIGHT", "TOPRIGHT", 0, 0}}, E, E),
        Piece(panel, art.botLeft, {0, B, 1 - B, 1}, {{"BOTTOMLEFT", "BOTTOMLEFT", 0, 0}}, E, E),
        Piece(panel, art.botRight, {0.5 - B, 0.5, 1 - B, 1}, {{"BOTTOMRIGHT", "BOTTOMRIGHT", 0, 0}}, E, E),
        -- and the four edges between them
        Piece(panel, art.topLeft, {B, 0.38, 0, B},
              {{"TOPLEFT", "TOPLEFT", E, 0}, {"TOPRIGHT", "TOPRIGHT", -E, 0}}, nil, E),
        Piece(panel, art.botLeft, {B, 0.38, 1 - B, 1},
              {{"BOTTOMLEFT", "BOTTOMLEFT", E, 0}, {"BOTTOMRIGHT", "BOTTOMRIGHT", -E, 0}}, nil, E),
        Piece(panel, art.topLeft, {0, B, B, 0.38},
              {{"TOPLEFT", "TOPLEFT", 0, -E}, {"BOTTOMLEFT", "BOTTOMLEFT", 0, E}}, E, nil),
        Piece(panel, art.topRight, {0.5 - B, 0.5, B, 0.38},
              {{"TOPRIGHT", "TOPRIGHT", 0, -E}, {"BOTTOMRIGHT", "BOTTOMRIGHT", 0, E}}, E, nil)
    }

    panel:Hide()
    return panel
end
