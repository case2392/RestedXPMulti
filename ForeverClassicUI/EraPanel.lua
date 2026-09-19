-- Forever Classic UI - an Era-looking panel at any size
--
-- Era's window art (the spellbook book, the quest log book) is four fixed
-- quarters with the decoration baked into their corners. Stretching those
-- across a rectangle that is not Era's own 384x512 pulls the decoration
-- out of shape, so they cannot be used to frame Forever's own windows.
--
-- The obvious substitute is Era's dialog frame - the tiling parchment
-- UI-DialogBox-Background inside the gold nine-slice UI-DialogBox-Border.
-- On this client that turns out not to work: GetFileIDFromPath resolves
-- both files (131071 and 131072), but nothing is drawn, so 0.7.4 and
-- 0.7.5 put invisible panels on the quest log, the Appearances window and
-- the guild window - the windows went see-through instead of parchment.
--
-- So the panel is built by hand out of things that cannot fail to draw:
-- a solid parchment fill and a gold frame, both plain colour, with Era's
-- parchment laid over the fill on top. On a client where the parchment
-- file really does draw (Classic Era itself) it covers the flat colour
-- and the panel is Era's own; where it does not, the flat parchment
-- stands in and the window still reads as Era rather than as a hole.

local addonName, ns = ...

local DF = "Interface\\DialogFrame\\"
ns.ERA_PANEL = {
    background = DF .. "UI-DialogBox-Background",
    border = DF .. "UI-DialogBox-Border",
    edgeSize = 32,
    tileSize = 256,
    insets = {left = 11, right = 12, top = 12, bottom = 11}
}

-- Era's parchment, its gold frame and the dark line outside it
local PARCHMENT = {0.09, 0.07, 0.05, 1}
local GOLD = {0.42, 0.33, 0.17, 1}
local OUTLINE = {0.02, 0.02, 0.01, 1}
local GOLD_W, OUTLINE_W = 3, 1

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
local function Frame4(panel, layer, width, inset, colour, into)
    local sides = {
        {"TOPLEFT", inset, -inset, "TOPRIGHT", -inset, -inset, nil, width},          -- top
        {"BOTTOMLEFT", inset, inset, "BOTTOMRIGHT", -inset, inset, nil, width},      -- bottom
        {"TOPLEFT", inset, -inset, "BOTTOMLEFT", inset, inset, width, nil},          -- left
        {"TOPRIGHT", -inset, -inset, "BOTTOMRIGHT", -inset, inset, width, nil}       -- right
    }
    for i, s in ipairs(sides) do
        local t = panel:CreateTexture(nil, layer)
        t:SetColorTexture(colour[1], colour[2], colour[3], colour[4])
        if s[7] then t:SetWidth(s[7]) end
        if s[8] then t:SetHeight(s[8]) end
        t:SetPoint(s[1], panel, s[1], s[2], s[3])
        t:SetPoint(s[4], panel, s[4], s[5], s[6])
        into[#into + 1] = t
    end
end

-- a frame of ours, parchment inside Era's gold border. It is only the
-- backdrop: the caller anchors it and decides what it sits over.
function ns.BuildEraPanel(name, parent)
    if not CreateFrame then return nil end
    local ok, panel = pcall(CreateFrame, "Frame", name, parent)
    if not ok or not panel then return nil end
    if not panel.CreateTexture then return panel end
    local art = ns.ERA_PANEL

    -- the parchment: flat colour first so the panel is never a hole, then
    -- Era's own parchment over it for clients where that file draws
    local fill = panel:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints(panel)
    fill:SetColorTexture(PARCHMENT[1], PARCHMENT[2], PARCHMENT[3], PARCHMENT[4])
    panel.fill = fill

    local paper = panel:CreateTexture(nil, "BACKGROUND")
    paper:SetAllPoints(panel)
    pcall(paper.SetTexture, paper, art.background, "REPEAT", "REPEAT")
    if paper.SetHorizTile then pcall(paper.SetHorizTile, paper, true) end
    if paper.SetVertTile then pcall(paper.SetVertTile, paper, true) end
    panel.paper = paper

    -- the frame: a dark line round the outside, Era's gold inside it
    panel.edges = {}
    Frame4(panel, "BORDER", OUTLINE_W, 0, OUTLINE, panel.edges)
    Frame4(panel, "BORDER", GOLD_W, OUTLINE_W, GOLD, panel.edges)

    panel:Hide()
    return panel
end
