-- Forever Classic UI - an Era-looking panel at any size
--
-- Era's window art (the spellbook book, the quest log book) is four fixed
-- quarters with the decoration baked into their corners. Stretching those
-- across a rectangle that is not Era's own 384x512 pulls the decoration
-- out of shape, which is exactly what went wrong when the quest log and
-- the Appearances window were first dressed up.
--
-- Era also has a look that does scale: the dialog frame. A parchment that
-- tiles (UI-DialogBox-Background) inside the gold border
-- (UI-DialogBox-Border, a 32px nine-slice) is what Era's own dialogs, the
-- talent frame background and every Era-styled addon panel use, and it is
-- right at any size. That is what this builds, so Forever's own windows
-- can be dressed in it whatever shape they happen to be.

local addonName, ns = ...

local DF = "Interface\\DialogFrame\\"
ns.ERA_PANEL = {
    background = DF .. "UI-DialogBox-Background",
    border = DF .. "UI-DialogBox-Border",
    edgeSize = 32,
    tileSize = 256,
    insets = {left = 11, right = 12, top = 12, bottom = 11}
}

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

-- a frame of ours, parchment inside Era's gold border. It is only the
-- backdrop: the caller anchors it and decides what it sits over.
function ns.BuildEraPanel(name, parent)
    if not CreateFrame then return nil end
    local ok, panel = pcall(CreateFrame, "Frame", name, parent, "BackdropTemplate")
    if not ok or not panel then
        ok, panel = pcall(CreateFrame, "Frame", name, parent)
        if not ok or not panel then return nil end
    end
    local art = ns.ERA_PANEL
    if panel.SetBackdrop then
        local applied = pcall(panel.SetBackdrop, panel, {
            bgFile = art.background,
            edgeFile = art.border,
            tile = true,
            tileSize = art.tileSize,
            edgeSize = art.edgeSize,
            insets = art.insets
        })
        panel.eraBackdrop = applied or nil
    end
    -- a plain dark fill underneath, so a client missing the dialog art
    -- still gets a solid panel instead of whatever was behind it
    if not panel.eraBackdrop and panel.CreateTexture then
        local fill = panel:CreateTexture(nil, "BACKGROUND")
        fill:SetAllPoints(panel)
        fill:SetColorTexture(0.09, 0.06, 0.03, 1)
        panel.fill = fill
    end
    panel:Hide()
    return panel
end
