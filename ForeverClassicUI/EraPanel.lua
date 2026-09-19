-- Forever Classic UI - an Era-looking panel at any size
--
-- This one has been got wrong repeatedly, so the reasoning is written
-- down. Three things have been tried:
--
--  * Era's page art stretched whole (0.7.1, 0.7.2). It is four fixed
--    quarters of a 384x512 page with the decoration baked into their
--    corners; stretched across any other rectangle the decoration pulls
--    out of shape. Mangled.
--  * Era's dialog frame (0.7.4, 0.7.5): tiling UI-DialogBox-Background
--    inside the nine-slice UI-DialogBox-Border. That scales properly and
--    is the right answer on a real client - but on Forever both files
--    resolve to file IDs (131071, 131072) and then draw nothing, so the
--    panels were invisible and the windows went see-through.
--  * Era's page cut into a nine-slice (0.7.7). Sound in principle, but
--    it needs to know where the decoration ends and the plain parchment
--    begins inside each quarter, and those numbers were guessed. They
--    were wrong: the "plain" patch was filigree and bevel, and the guild
--    window came out as swooping curves and checkerboard.
--
-- The lesson is that nothing here may depend on guessing what is inside
-- a texture. So the panel is drawn from plain colour, which always
-- works: Era's parchment brown with its gold frame and a dark line
-- outside it. It is not Era's own art, but it is Era's colours and it is
-- the same at any size. 0.7.6 did this and read as a black box only
-- because the brown chosen then was nearly black.
--
-- If a scalable piece of classic art is confirmed to draw on this client
-- - /cui report lists candidates - this is the one place to swap in.

local addonName, ns = ...

-- kept so the probe and the modules can still name what Era would use
local DF = "Interface\\DialogFrame\\"
ns.ERA_PANEL = {
    background = DF .. "UI-DialogBox-Background",
    border = DF .. "UI-DialogBox-Border"
}

-- Era's parchment is a warm mid brown - light enough to read as
-- parchment, dark enough for Blizzard's pale text to sit on it. The
-- inner tone is a shade lighter so the panel is not one flat slab.
local PARCHMENT = {0.25, 0.20, 0.13, 1}
local INNER = {0.31, 0.25, 0.16, 1}
local GOLD = {0.55, 0.44, 0.22, 1}
local OUTLINE = {0.06, 0.05, 0.03, 1}
local OUTLINE_W, GOLD_W, INNER_INSET = 1, 3, 6

local function HasFile(path)
    if not GetFileIDFromPath then return true end
    local ok, id = pcall(GetFileIDFromPath, path)
    return ok and id ~= nil
end

function ns.EraPanelArtMissing()
    local missing = {}
    for _, key in ipairs({"background", "border"}) do
        local path = ns.ERA_PANEL[key]
        if not HasFile(path) then missing[#missing + 1] = path:match("[^\\]+$") end
    end
    return missing
end

-- four plain-colour bars making a frame `inset` in from the panel's edge
local function Frame4(panel, width, inset, colour, into)
    local sides = {
        {"TOPLEFT", inset, -inset, "TOPRIGHT", -inset, -inset, nil, width},
        {"BOTTOMLEFT", inset, inset, "BOTTOMRIGHT", -inset, inset, nil, width},
        {"TOPLEFT", inset, -inset, "BOTTOMLEFT", inset, inset, width, nil},
        {"TOPRIGHT", -inset, -inset, "BOTTOMRIGHT", -inset, inset, width, nil}
    }
    for _, s in ipairs(sides) do
        local t = panel:CreateTexture(nil, "BORDER")
        t:SetColorTexture(colour[1], colour[2], colour[3], colour[4])
        if s[7] then t:SetWidth(s[7]) end
        if s[8] then t:SetHeight(s[8]) end
        t:SetPoint(s[1], panel, s[1], s[2], s[3])
        t:SetPoint(s[4], panel, s[4], s[5], s[6])
        into[#into + 1] = t
    end
end

-- a frame of ours, Era's parchment inside Era's gold. It is only the
-- backdrop: the caller anchors it and decides what it sits over.
function ns.BuildEraPanel(name, parent)
    if not CreateFrame then return nil end
    local ok, panel = pcall(CreateFrame, "Frame", name, parent)
    if not ok or not panel then return nil end
    if not panel.CreateTexture then return panel end

    local fill = panel:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints(panel)
    fill:SetColorTexture(PARCHMENT[1], PARCHMENT[2], PARCHMENT[3], PARCHMENT[4])
    panel.fill = fill

    -- the page inside the frame, a shade lighter than the border band
    local inner = panel:CreateTexture(nil, "BACKGROUND")
    inner:SetPoint("TOPLEFT", panel, "TOPLEFT", INNER_INSET, -INNER_INSET)
    inner:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -INNER_INSET, INNER_INSET)
    inner:SetColorTexture(INNER[1], INNER[2], INNER[3], INNER[4])
    panel.inner = inner

    panel.edges = {}
    Frame4(panel, OUTLINE_W, 0, OUTLINE, panel.edges)
    Frame4(panel, GOLD_W, OUTLINE_W, GOLD, panel.edges)

    panel:Hide()
    return panel
end
