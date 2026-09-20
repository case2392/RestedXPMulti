-- Forever Classic UI - talents
--
-- Forever's talents page is retail's talent frame with Forever's own
-- trees on it: three trees side by side across a 1212px canvas inside the
-- 1618x883 spell window, square 40px nodes on a 60px grid, retail's thin
-- arrows between them and animated class art behind. Era's was a 384x512
-- frame showing one tree at a time: the tree's own painting behind the
-- talents, each talent in the quickslot ring with its rank in a little
-- box at the corner, gold branches and arrows running from a talent down
-- to the ones it unlocks (grey until the talent is learned), the three
-- trees as tabs along the bottom, "Talent Points: N" in the bar above the
-- tabs and the tree's name with its points spent in the box under the
-- title. Numbers come from Era's Blizzard_TalentUI.xml and TalentFrameBase.
--
-- Blizzard's talent buttons stay Blizzard's: clicking one still learns the
-- talent through Forever's own code and the tooltips are theirs. They are
-- moved, not rebuilt. Forever lays them out on its ButtonsParent from the
-- tree's own coordinates; this part reads those, sorts the nodes into
-- trees by column, and anchors the chosen tree's nodes onto Era's page
-- while the other trees are parked far outside it. ButtonsParent itself
-- is resized to Era's viewport and made to clip its children, so the
-- parked trees and anything scrolled out of view cannot be seen; a scroll
-- bar of ours moves the tree. Each node's retail art (the square border,
-- shadow, sheen, rank number) is faded and Era's drawn over it: the empty
-- slot, the quickslot ring, the rank box. Branches and arrows are ours,
-- cut from Era's UI-TalentBranches and UI-TalentArrows and drawn from the
-- node's own list of edges; retail's arrows are faded. The retail window
-- round it all is the shared shell (PlayerSpells.lua), claimed while the
-- talents page is up. Forever's "Apply Changes" button is kept and moved
-- into Era's points bar; its search box is faded and unclickable; other
-- buttons of Forever's (a Primary/Secondary pair, if that is what they
-- are) go to the right edge where Era 1.15 kept its spec tabs, and the
-- rest of Forever's furniture on the page is faded.
--
-- Rule as elsewhere: widget calls and hooksecurefunc only, nothing of
-- ours written into Blizzard's tables (M.own holds what hangs on them),
-- and everything remembered so /cui talents off puts it all back.

local addonName, ns = ...

local M = {mode = "off", tree = nil, scroll = 0}

local ART = {
    topLeft = "Interface\\PaperDollInfoFrame\\UI-Character-General-TopLeft",
    topRight = "Interface\\PaperDollInfoFrame\\UI-Character-General-TopRight",
    botLeft = "Interface\\TALENTFRAME\\UI-TalentFrame-BotLeft",
    botRight = "Interface\\TALENTFRAME\\UI-TalentFrame-BotRight",
    branches = "Interface\\TalentFrame\\UI-TalentBranches",
    arrows = "Interface\\TalentFrame\\UI-TalentArrows",
    rankBorder = "Interface\\TalentFrame\\TalentFrame-RankBorder",
    slot = "Interface\\Buttons\\UI-EmptySlot-White",
    quickslot = "Interface\\Buttons\\UI-Quickslot2",
    scrollBar = "Interface\\PaperDollInfoFrame\\UI-Character-ScrollBar",
    inputBorder = "Interface\\Common\\Common-Input-Border",
    knob = "Interface\\Buttons\\UI-ScrollBar-Knob",
    scrollUp = "Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-",
    scrollDown = "Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-",
    closeUp = "Interface\\Buttons\\UI-Panel-MinimizeButton-Up",
    closeDown = "Interface\\Buttons\\UI-Panel-MinimizeButton-Down",
    closeHighlight = "Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight",
    treeBase = "Interface\\TalentFrame\\"
}
M.ART = ART

-- Era's scroll frame: 296 wide from x=23, from y=-77 down to the points
-- bar (BOTTOM 81 + 26 tall), so 328 tall
local VIEW = {x = 23, y = -77, w = 296, h = 328}
-- the tree painting fills a 300x331 rect: TopLeft 256x256, TopRight 44
-- wide (44/64 of its file), the bottom pair 75 tall (75/128 of theirs)
local TREE_RIGHT_U, TREE_BOTTOM_V = 0.6875, 0.5859375
-- the first tier's centre sits 36px under the top of Era's page (20px
-- offset plus half a 32px button); the same margin closes the bottom
local TOP_PAD, BOTTOM_PAD = 36, 36
-- nodes further apart than this across the canvas are different trees:
-- Forever's columns are 60px apart (four to a tree, so at most 180px
-- between used columns), its trees at least 224px apart
local TREE_GAP = 200
-- Era's branch tiles are 32px; its arrow tile sits 5px above the button
local TILE, ARROW_LIFT = 32, 5
local MAX_TREES = 3
local TREE_FALLBACK = "Tree %d"

-- Era's tree paintings, in Era's tab order for each class
local TREE_ART = {
    DRUID = {"DruidBalance", "DruidFeralCombat", "DruidRestoration"},
    HUNTER = {"HunterBeastMastery", "HunterMarksmanship", "HunterSurvival"},
    MAGE = {"MageArcane", "MageFire", "MageFrost"},
    PALADIN = {"PaladinHoly", "PaladinProtection", "PaladinCombat"},
    PRIEST = {"PriestDiscipline", "PriestHoly", "PriestShadow"},
    ROGUE = {"RogueAssassination", "RogueCombat", "RogueSubtlety"},
    SHAMAN = {"ShamanElementalCombat", "ShamanEnhancement", "ShamanRestoration"},
    WARLOCK = {"WarlockCurses", "WarlockSummoning", "WarlockDestruction"},
    WARRIOR = {"WarriorArms", "WarriorFury", "WarriorProtection"}
}
M.TREE_ART = TREE_ART

-- Era's tree names, in the same order: what the tabs say when Forever's
-- spec names are not the trees' (Forever names a hunter's one spec
-- "Hunter", and the retail client has no name for the other two)
local TREE_NAMES = {
    DRUID = {"Balance", "Feral Combat", "Restoration"},
    HUNTER = {"Beast Mastery", "Marksmanship", "Survival"},
    MAGE = {"Arcane", "Fire", "Frost"},
    PALADIN = {"Holy", "Protection", "Retribution"},
    PRIEST = {"Discipline", "Holy", "Shadow"},
    ROGUE = {"Assassination", "Combat", "Subtlety"},
    SHAMAN = {"Elemental", "Enhancement", "Restoration"},
    WARLOCK = {"Affliction", "Demonology", "Destruction"},
    WARRIOR = {"Arms", "Fury", "Protection"}
}
M.TREE_NAMES = TREE_NAMES

-- Era's TALENT_BRANCH_TEXTURECOORDS / TALENT_ARROW_TEXTURECOORDS: [1] gold, [-1] grey
local BRANCH = {
    up = {[1] = {0.12890625, 0.25390625, 0, 0.484375}, [-1] = {0.12890625, 0.25390625, 0.515625, 1.0}},
    down = {[1] = {0, 0.125, 0, 0.484375}, [-1] = {0, 0.125, 0.515625, 1.0}},
    left = {[1] = {0.2578125, 0.3828125, 0, 0.5}, [-1] = {0.2578125, 0.3828125, 0.5, 1.0}},
    right = {[1] = {0.2578125, 0.3828125, 0, 0.5}, [-1] = {0.2578125, 0.3828125, 0.5, 1.0}},
    topright = {[1] = {0.515625, 0.640625, 0, 0.5}, [-1] = {0.515625, 0.640625, 0.5, 1.0}},
    topleft = {[1] = {0.640625, 0.515625, 0, 0.5}, [-1] = {0.640625, 0.515625, 0.5, 1.0}},
    bottomright = {[1] = {0.38671875, 0.51171875, 0, 0.5}, [-1] = {0.38671875, 0.51171875, 0.5, 1.0}},
    bottomleft = {[1] = {0.51171875, 0.38671875, 0, 0.5}, [-1] = {0.51171875, 0.38671875, 0.5, 1.0}}
}
local ARROW = {
    top = {[1] = {0, 0.5, 0, 0.5}, [-1] = {0, 0.5, 0.5, 1.0}},
    right = {[1] = {1.0, 0.5, 0, 0.5}, [-1] = {1.0, 0.5, 0.5, 1.0}},
    left = {[1] = {0.5, 1.0, 0, 0.5}, [-1] = {0.5, 1.0, 0.5, 1.0}}
}
M.BRANCH, M.ARROW = BRANCH, ARROW

-- retail's visual states, by number, so the buttons need not be asked twice
local STATE = {Normal = 1, Gated = 2, Disabled = 3, Locked = 4, Selectable = 5, Maxed = 6, Invisible = 7, RefundInvalid = 8, DisplayError = 9}

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

local function Guard(label, fn)
    return function(...)
        local ok, err = pcall(fn, ...)
        if not ok then ns.errors[#ns.errors + 1] = "talents " .. label .. ": " .. tostring(err) end
    end
end

local function ObjectType(f)
    if type(f) ~= "table" or not f.GetObjectType then return nil end
    local ok, kind = pcall(f.GetObjectType, f)
    return ok and kind or nil
end

local function Text(f)
    if type(f) ~= "table" or not f.GetText then return nil end
    local ok, t = pcall(f.GetText, f)
    if ok and type(t) == "string" then return t end
end

--------------------------------------------------------------------------
-- remember / restore: anchors, size and alpha of Blizzard's regions
--------------------------------------------------------------------------

local function Remember(region)
    if not region then return end
    local own = Own(region)
    if own.saved then return end
    local saved = {points = {}}
    if region.GetNumPoints and region.GetPoint then
        local ok, n = pcall(region.GetNumPoints, region)
        for i = 1, (ok and n) or 0 do
            local okp, a, b, c, d, e = pcall(region.GetPoint, region, i)
            if okp and a then saved.points[#saved.points + 1] = {a, b, c, d, e} end
        end
    end
    -- a FontString sizes itself to its text; pinning it to a remembered
    -- size would box Forever's rank numbers to whatever they were
    if region.GetSize and ObjectType(region) ~= "FontString" then
        local ok, w, h = pcall(region.GetSize, region)
        if ok then saved.width, saved.height = w, h end
    end
    if region.GetAlpha then
        local ok, a = pcall(region.GetAlpha, region)
        if ok then saved.alpha = a end
    end
    if region.IsMouseEnabled then
        local ok, m = pcall(region.IsMouseEnabled, region)
        if ok then saved.mouse = m end
    end
    own.saved = saved
end

local function Restore(region)
    local own = region and M.own[region]
    local saved = own and own.saved
    if not saved then return end
    if #saved.points > 0 and region.ClearAllPoints and region.SetPoint then
        region:ClearAllPoints()
        for _, p in ipairs(saved.points) do region:SetPoint(p[1], p[2], p[3], p[4], p[5]) end
    end
    if saved.width and region.SetSize then region:SetSize(saved.width, saved.height) end
    if saved.alpha and region.SetAlpha then region:SetAlpha(saved.alpha) end
    if saved.mouse ~= nil and region.EnableMouse then region:EnableMouse(saved.mouse) end
    own.saved = nil
end

local function Fade(region)
    if not region or not region.SetAlpha then return end
    Remember(region)
    region:SetAlpha(0)
end

local function Anchor(region, point, rel, relPoint, x, y, w, h)
    if not region then return end
    Remember(region)
    region:ClearAllPoints()
    region:SetPoint(point, rel, relPoint, x, y)
    if w then region:SetSize(w, h) end
end

--------------------------------------------------------------------------
-- Forever's frame
--------------------------------------------------------------------------

local function Window() return ns.PSF.Frame() end

-- Forever's TalentsFrame, told by the ButtonsParent the nodes hang off
local function TreeFrame()
    local psf = Window()
    local tf = psf and psf.TalentsFrame
    if type(tf) == "table" and type(tf.ButtonsParent) == "table" and tf.ButtonsParent.GetChildren then return tf, psf end
end

local function PageShown()
    local tf, psf = TreeFrame()
    if not tf or not psf then return false end
    if psf.IsShown and not psf:IsShown() then return false end
    -- inspecting another player: their trees, their name; retail's page
    -- is left as it is for that
    if psf.IsInspecting then
        local ok, inspecting = pcall(psf.IsInspecting, psf)
        if ok and inspecting then return false end
    end
    return tf.IsShown ~= nil and tf:IsShown() == true
end

local function Children(frame)
    if not frame or not frame.GetChildren then return {} end
    local ok, t = pcall(function() return {frame:GetChildren()} end)
    return ok and t or {}
end

local function Regions(frame)
    if not frame or not frame.GetRegions then return {} end
    local ok, t = pcall(function() return {frame:GetRegions()} end)
    return ok and t or {}
end

local function NodeInfo(node)
    if node.GetNodeInfo then
        local ok, info = pcall(node.GetNodeInfo, node)
        if ok and type(info) == "table" then return info end
    end
    local info = node.nodeInfo
    return type(info) == "table" and info or nil
end

local function NodeID(node)
    if node.GetNodeID then
        local ok, id = pcall(node.GetNodeID, node)
        if ok and id ~= nil then return id end
    end
    return node.nodeID
end

local function IsNode(f)
    return type(f) == "table" and f.Icon ~= nil and f.SpendText ~= nil and (f.GetNodeInfo ~= nil or f.nodeInfo ~= nil)
end

-- retail's arrows: frames under ButtonsParent that know their two buttons
local function IsEdge(f)
    return type(f) == "table" and not IsNode(f) and f.GetStartButton ~= nil and f.GetEndButton ~= nil
end

local function Shown(f)
    if not f or not f.IsShown then return true end
    local ok, s = pcall(f.IsShown, f)
    return ok and s == true
end

local function VisualState(node)
    if node.GetVisualState then
        local ok, s = pcall(node.GetVisualState, node)
        if ok and type(s) == "number" then return s end
    end
    return STATE.Normal
end

-- every talent button on the canvas, shown or waiting in Forever's pool
local function AllNodes(tf)
    local out = {}
    for _, child in ipairs(Children(tf.ButtonsParent)) do
        if IsNode(child) then out[#out + 1] = child end
    end
    return out
end

-- Forever re-anchors a node when it lays the tree out again (every
-- commit reloads the tree and hands the pooled buttons out afresh), and
-- what it anchored is what must be remembered, not what we did: so a
-- SetPoint that is not ours forgets the old memory
local function WatchNode(node)
    local own = Own(node)
    if own.watched or not hooksecurefunc then return end
    hooksecurefunc(node, "SetPoint", function()
        if not M.placing then
            local o = M.own[node]
            if o then o.saved = nil end
        end
    end)
    own.watched = true
end

-- the nodes on the page, with where Forever put them
local function Nodes(tf)
    local out = {}
    for _, child in ipairs(AllNodes(tf)) do
        if Shown(child) then
            local info = NodeInfo(child)
            if info and info.isVisible ~= false then
                WatchNode(child)
                Remember(child)
                local p = Own(child).saved.points[1]
                -- Forever anchors each node CENTER to ButtonsParent's TOPLEFT
                if p and type(p[4]) == "number" and type(p[5]) == "number" then
                    out[#out + 1] = {node = child, info = info, x = p[4], y = -p[5]}
                end
            end
        end
    end
    return out
end

local function Edges(tf)
    local out = {}
    for _, child in ipairs(Children(tf.ButtonsParent)) do
        if IsEdge(child) then out[#out + 1] = child end
    end
    return out
end

-- whatever else Forever hangs on the canvas (its tier gates, for one):
-- not Era's, so faded while the page is ours
local function Others(tf)
    local out = {}
    for _, child in ipairs(Children(tf.ButtonsParent)) do
        if not IsNode(child) and not IsEdge(child) and child ~= M.lines and child ~= M.arrows then
            out[#out + 1] = child
        end
    end
    return out
end

-- the trees: nodes sorted into columns of the canvas, left to right
local function Trees(tf)
    local pts = Nodes(tf)
    table.sort(pts, function(a, b) if a.x ~= b.x then return a.x < b.x end return a.y < b.y end)
    local trees, cur = {}, nil
    for _, p in ipairs(pts) do
        if not cur or p.x - cur.maxX > TREE_GAP then
            cur = {nodes = {}, minX = p.x, maxX = p.x, minY = p.y, maxY = p.y, byNode = {}}
            trees[#trees + 1] = cur
        end
        cur.nodes[#cur.nodes + 1] = p
        cur.byNode[p.node] = p
        if p.x > cur.maxX then cur.maxX = p.x end
        if p.y < cur.minY then cur.minY = p.y end
        if p.y > cur.maxY then cur.maxY = p.y end
    end
    for _, t in ipairs(trees) do
        table.sort(t.nodes, function(a, b) if a.y ~= b.y then return a.y < b.y end return a.x < b.x end)
        local spent = 0
        for _, p in ipairs(t.nodes) do spent = spent + (tonumber(p.info.ranksPurchased) or 0) end
        t.spent = spent
        t.height = TOP_PAD + (t.maxY - t.minY) + BOTTOM_PAD
    end
    return trees
end

local function NodeSize(node)
    if node.GetWidth then
        local ok, w = pcall(node.GetWidth, node)
        if ok and type(w) == "number" and w > 0 then return w end
    end
    return 40
end

--------------------------------------------------------------------------
-- names and art for the trees
--------------------------------------------------------------------------

local function PlayerClass()
    if not UnitClass then return nil, nil end
    local ok, _, file, id = pcall(UnitClass, "player")
    if ok then return file, id end
end

-- Era's painting whose name matches a tree's (Beast Mastery, Feral,
-- Elemental...), if any does
local function ArtByName(class, name)
    local set = class and TREE_ART[class]
    if not set or type(name) ~= "string" then return nil end
    local key = name:lower():gsub("[^%a]", "")
    if key == "" then return nil end
    for _, art in ipairs(set) do
        local body = art:lower():gsub("^" .. class:lower(), "")
        if body:find(key, 1, true) then return art end
    end
end

-- the trees' names: the client's spec names when they are the trees'
-- (they are localised, so they come first), Era's own names otherwise.
-- A spec name counts only if it names one of Era's paintings, which
-- drops a retail druid's Guardian and Forever's class-named single spec.
local function SpecNames()
    if M.names then return M.names end
    local class, classID = PlayerClass()
    local names = {}
    if classID and GetSpecializationInfoForClassID and class and TREE_ART[class] then
        local okn, count = pcall(GetNumSpecializationsForClassID or function() return MAX_TREES end, classID)
        count = (okn and tonumber(count)) or MAX_TREES
        local seen = {}
        for i = 1, math.max(count, MAX_TREES) do
            local ok, _, name = pcall(GetSpecializationInfoForClassID, classID, i)
            if ok and type(name) == "string" and name ~= "" then
                local art = ArtByName(class, name)
                if art and not seen[art] then
                    seen[art] = true
                    names[#names + 1] = name
                end
            end
        end
    end
    if #names < MAX_TREES then
        names = {}
        for k, n in ipairs(class and TREE_NAMES[class] or {}) do names[k] = n end
    end
    -- a full set is kept; anything less is looked up again next time
    if #names >= MAX_TREES then M.names = names end
    return names
end

local function TreeName(k)
    local names = SpecNames()
    return names[k] or TREE_FALLBACK:format(k)
end

-- Era's painting for the k-th tree: matched by name where the names
-- agree, by Era's tab order otherwise
local function TreeArt(k, name)
    local class = PlayerClass()
    local set = class and TREE_ART[class]
    if not set then return nil end
    return ArtByName(class, name) or set[k]
end

-- unspent points: Forever's frame keeps the tree's currencies on itself
local function Unspent(tf)
    local list = tf.treeCurrencyInfo
    if type(list) ~= "table" and C_Traits and C_Traits.GetTreeCurrencyInfo and tf.GetConfigID and tf.GetTalentTreeID then
        local okc, config = pcall(tf.GetConfigID, tf)
        local okt, tree = pcall(tf.GetTalentTreeID, tf)
        if okc and okt and config and tree then
            local ok, info = pcall(C_Traits.GetTreeCurrencyInfo, config, tree, false)
            if ok then list = info end
        end
    end
    if type(list) ~= "table" then return nil end
    local total = 0
    for _, c in ipairs(list) do
        local q = type(c) == "table" and tonumber(c.quantity)
        if q then total = total + q end
    end
    return total
end

--------------------------------------------------------------------------
-- our frame: Era's talent frame drawn on the window
--------------------------------------------------------------------------

local function Piece(parent, layer, path, w, h, point, rel, relPoint, x, y)
    local t = parent:CreateTexture(nil, layer)
    t:SetTexture(path)
    t:SetSize(w, h)
    t:SetPoint(point, rel, relPoint, x, y)
    return t
end

-- Era's scroll bar, built by hand: the client's UIPanelScrollBarTemplate
-- is not Era's any more (its OnValueChanged scrolls its parent, which it
-- expects to be a scroll frame, and errors on ours), so the slider, its
-- knob and the two arrow buttons are made plain, from Era's art
local SCROLL_STEP = 30

local function ScrollButton(s, up)
    local b = CreateFrame("Button", nil, s)
    b:SetSize(16, 16)
    local base = up and ART.scrollUp or ART.scrollDown
    b:SetNormalTexture(base .. "Up")
    b:SetPushedTexture(base .. "Down")
    if b.SetDisabledTexture then b:SetDisabledTexture(base .. "Disabled") end
    b:SetHighlightTexture(base .. "Highlight", "ADD")
    if up then b:SetPoint("BOTTOM", s, "TOP", 0, -2) else b:SetPoint("TOP", s, "BOTTOM", 0, 2) end
    b:SetScript("OnClick", function()
        local lo, hi = s:GetMinMaxValues()
        local v = s:GetValue() + (up and -SCROLL_STEP or SCROLL_STEP)
        s:SetValue(math.max(lo, math.min(hi, v)))
    end)
    return b
end

local function BuildSlider(controls, view)
    local s = CreateFrame("Slider", nil, controls)
    if s.SetOrientation then pcall(s.SetOrientation, s, "VERTICAL") end
    if s.SetThumbTexture then
        pcall(s.SetThumbTexture, s, ART.knob)
        local thumb = s.GetThumbTexture and select(2, pcall(s.GetThumbTexture, s))
        if type(thumb) == "table" and thumb.SetSize then
            thumb:SetSize(16, 24)
            if thumb.SetTexCoord then thumb:SetTexCoord(0.125, 0.875, 0.125, 0.875) end
        end
    end
    s:SetWidth(16)
    s:SetPoint("TOPLEFT", view, "TOPRIGHT", 6, -16)
    s:SetPoint("BOTTOMLEFT", view, "BOTTOMRIGHT", 6, 16)
    if s.SetValueStep then s:SetValueStep(1) end
    if s.SetObeyStepOnDrag then pcall(s.SetObeyStepOnDrag, s, true) end
    s:SetMinMaxValues(0, 0)
    s:SetValue(0)
    s.up = ScrollButton(s, true)
    s.down = ScrollButton(s, false)
    s:SetScript("OnValueChanged", function(self, value)
        if M.settingScroll then return end
        M.scroll = math.floor((tonumber(value) or 0) + 0.5)
        if M.applied then M.Reflow() end
    end)
    return s
end

local function BuildFrame(psf)
    local f = CreateFrame("Frame", "ForeverClassicUITalentFrame", psf)
    f:SetAllPoints(psf)
    f:SetFrameLevel(psf:GetFrameLevel() + 1)
    -- the player's portrait under the ring, as Era drew it
    f.portrait = f:CreateTexture(nil, "BACKGROUND")
    f.portrait:SetSize(60, 60)
    f.portrait:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -7)
    f.art = {
        Piece(f, "BORDER", ART.topLeft, 256, 256, "TOPLEFT", f, "TOPLEFT", 2, -1),
        Piece(f, "BORDER", ART.topRight, 128, 256, "TOPRIGHT", f, "TOPRIGHT", 2, -1),
        Piece(f, "BORDER", ART.botLeft, 256, 256, "BOTTOMLEFT", f, "BOTTOMLEFT", 2, -1),
        Piece(f, "BORDER", ART.botRight, 128, 256, "BOTTOMRIGHT", f, "BOTTOMRIGHT", 2, -1)
    }
    -- the viewport: Era's scroll frame, with the tree painting inside it
    local view = CreateFrame("Frame", nil, f)
    view:SetPoint("TOPLEFT", f, "TOPLEFT", VIEW.x, VIEW.y)
    view:SetSize(VIEW.w, VIEW.h)
    view:SetFrameLevel(f:GetFrameLevel() + 1)
    view.topLeft = Piece(view, "BACKGROUND", nil, 256, 256, "TOPLEFT", view, "TOPLEFT", 0, 0)
    view.topRight = Piece(view, "BACKGROUND", nil, 44, 256, "TOPRIGHT", view, "TOPRIGHT", 0, 0)
    view.topRight:SetTexCoord(0, TREE_RIGHT_U, 0, 1)
    view.bottomLeft = Piece(view, "BACKGROUND", nil, 256, 75, "BOTTOMLEFT", view, "BOTTOMLEFT", 0, 0)
    view.bottomLeft:SetTexCoord(0, 1, 0, TREE_BOTTOM_V)
    view.bottomRight = Piece(view, "BACKGROUND", nil, 44, 75, "BOTTOMRIGHT", view, "BOTTOMRIGHT", 0, 0)
    view.bottomRight:SetTexCoord(0, TREE_RIGHT_U, 0, TREE_BOTTOM_V)
    -- a plain floor under the painting, for a tree whose file is missing
    view.floor = view:CreateTexture(nil, "BACKGROUND", nil, -1)
    view.floor:SetAllPoints(view)
    view.floor:SetColorTexture(0.05, 0.05, 0.08, 1)
    f.view = view
    -- Era's scroll bar art down the right of the viewport
    f.scrollTop = Piece(f, "ARTWORK", ART.scrollBar, 31, 256, "TOPLEFT", view, "TOPRIGHT", -2, 5)
    f.scrollTop:SetTexCoord(0, 0.484375, 0, 1)
    f.scrollBottom = Piece(f, "ARTWORK", ART.scrollBar, 31, 106, "BOTTOMLEFT", view, "BOTTOMRIGHT", -2, -2)
    f.scrollBottom:SetTexCoord(0.515625, 1, 0, 0.4140625)

    -- the controls sit above Forever's page, which covers the window
    local controls = CreateFrame("Frame", "ForeverClassicUITalentControls", psf)
    controls:SetAllPoints(psf)
    controls:SetFrameLevel(f:GetFrameLevel() + 1)
    f.controls = controls
    controls.title = controls:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    controls.title:SetPoint("TOP", controls, "TOP", 0, -18)
    controls.title:SetText(Str("TALENTS", "Talents"))
    -- the box under the title: the tree's name and points spent
    local box = CreateFrame("Frame", nil, controls)
    box:SetSize(264, 20)
    box:SetPoint("TOPLEFT", controls, "TOPLEFT", 73, -46)
    box.left = Piece(box, "ARTWORK", ART.inputBorder, 8, 20, "LEFT", box, "LEFT", 0, 0)
    box.left:SetTexCoord(0, 0.0625, 0, 0.625)
    box.middle = Piece(box, "ARTWORK", ART.inputBorder, 248, 20, "LEFT", box.left, "RIGHT", 0, 0)
    box.middle:SetTexCoord(0.0625, 0.9375, 0, 0.625)
    box.right = Piece(box, "ARTWORK", ART.inputBorder, 8, 20, "LEFT", box.middle, "RIGHT", 0, 0)
    box.right:SetTexCoord(0.9375, 1, 0, 0.625)
    box.text = box:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    box.text:SetPoint("CENTER", box, "CENTER", 0, 0)
    controls.box = box
    -- the points bar above the tabs: "Talent Points: N", right aligned
    controls.points = controls:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    controls.points:SetJustifyH("RIGHT")
    controls.points:SetPoint("RIGHT", controls, "BOTTOMRIGHT", -128, 94)
    -- the trees as tabs along the bottom
    controls.tabs = {}
    for k = 1, MAX_TREES do
        local tab = ns.BuildEraTab(controls, TREE_FALLBACK:format(k))
        if k == 1 then
            tab:SetPoint("BOTTOMLEFT", controls, "BOTTOMLEFT", 20, 45)
        else
            tab:SetPoint("LEFT", controls.tabs[k - 1], "RIGHT", 4, 0)
        end
        tab.index = k
        tab:SetScript("OnClick", function(self)
            M.tree = self.index
            M.scroll = 0
            M.Apply()
        end)
        tab:Hide()
        controls.tabs[k] = tab
    end
    -- Era's X in the corner
    local close = CreateFrame("Button", nil, controls)
    close:SetSize(32, 32)
    close:SetPoint("CENTER", controls, "TOPRIGHT", -44, -25)
    close:SetNormalTexture(ART.closeUp)
    close:SetPushedTexture(ART.closeDown)
    close:SetHighlightTexture(ART.closeHighlight, "ADD")
    close:SetScript("OnClick", function() if HideUIPanel then HideUIPanel(psf) else psf:Hide() end end)
    controls.close = close
    -- the scroll bar, and the wheel over the page
    controls.slider = BuildSlider(controls, view)
    if controls.EnableMouseWheel then controls:EnableMouseWheel(true) end
    controls:SetScript("OnMouseWheel", function(_, delta)
        local s = controls.slider
        local lo, hi = s:GetMinMaxValues()
        local v = math.max(lo, math.min(hi, s:GetValue() - (delta or 0) * 30))
        s:SetValue(v)
    end)
    f:Hide()
    controls:Hide()
    return f
end

-- our branches live on ButtonsParent under the nodes, and the arrow
-- heads on a second frame over them, as Era's ArrowFrame sat over its
-- buttons; both are clipped and scrolled with the nodes
local ARROWS_ABOVE = 600   -- Forever's nodes sit some 500 levels above ButtonsParent

local function BuildLines(bp)
    local lines = CreateFrame("Frame", nil, bp)
    lines:SetAllPoints(bp)
    lines:SetFrameLevel(bp:GetFrameLevel() + 1)
    lines.branches, lines.arrows = {}, {}
    lines.usedBranches, lines.usedArrows = 0, 0
    local arrows = CreateFrame("Frame", nil, bp)
    arrows:SetAllPoints(bp)
    arrows:SetFrameLevel(bp:GetFrameLevel() + ARROWS_ABOVE)
    lines.arrowFrame = arrows
    M.arrows = arrows
    return lines
end

--------------------------------------------------------------------------
-- the nodes: moved onto Era's page and dressed in Era's art
--------------------------------------------------------------------------

-- Forever's own art on a node: everything but the icon, the masks, and
-- the pieces we drew on it ourselves (GetRegions returns those too)
local function NodeRegionsToFade(node)
    local own, out = M.own[node], {}
    for _, r in ipairs(Regions(node)) do
        local ours = own and (r == own.slot or r == own.ring or r == own.rankBorder or r == own.rank)
        if r ~= node.Icon and ObjectType(r) ~= "MaskTexture" and not ours then out[#out + 1] = r end
    end
    return out
end

local function SkinNode(node, on)
    local own = Own(node)
    if on then
        if not own.hooked and hooksecurefunc then
            for _, m in ipairs({"FullUpdate", "UpdateVisualState"}) do
                if type(node[m]) == "function" then hooksecurefunc(node, m, Guard(m, function() M.ApplyLater() end)) end
            end
            own.hooked = true
        end
        for _, r in ipairs(NodeRegionsToFade(node)) do Fade(r) end
        local size = NodeSize(node)
        local scale = size / 37
        if not own.slot then
            -- Era's TalentButtonTemplate: the empty slot behind, the
            -- quickslot ring over the icon, the rank box on the corner
            own.slot = node:CreateTexture(nil, "BACKGROUND", nil, -1)
            own.slot:SetTexture(ART.slot)
            own.slot:SetPoint("CENTER", node, "CENTER", 0, 0)
            own.ring = node:CreateTexture(nil, "ARTWORK", nil, 1)
            own.ring:SetTexture(ART.quickslot)
            own.ring:SetPoint("CENTER", node, "CENTER", 0, -1)
            own.rankBorder = node:CreateTexture(nil, "OVERLAY", nil, 0)
            own.rankBorder:SetTexture(ART.rankBorder)
            own.rankBorder:SetSize(32, 32)
            own.rankBorder:SetPoint("CENTER", node, "BOTTOMRIGHT", 0, 0)
            own.rank = node:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            own.rank:SetPoint("CENTER", own.rankBorder, "CENTER", 0, 0)
        end
        own.slot:SetSize(64 * scale, 64 * scale)
        own.ring:SetSize(64 * scale, 64 * scale)
        local info = NodeInfo(node) or {}
        local state = VisualState(node)
        local rank = tonumber(info.currentRank) or tonumber(info.ranksPurchased) or 0
        local maxRanks = tonumber(info.maxRanks) or 1
        local purchased = tonumber(info.ranksPurchased) or rank
        if state == STATE.Invisible then
            own.slot:Hide(); own.ring:Hide(); own.rankBorder:Hide(); own.rank:Hide()
            return
        end
        own.slot:Show(); own.ring:Show()
        own.rank:SetText(tostring(rank))
        local locked = state == STATE.Gated or state == STATE.Disabled or state == STATE.Locked
        if locked then
            -- Era: grey slot, and no rank box at all until a point is in it
            own.slot:SetVertexColor(0.5, 0.5, 0.5)
            if purchased > 0 then
                own.rankBorder:SetVertexColor(0.5, 0.5, 0.5)
                own.rank:SetTextColor(0.5, 0.5, 0.5)
                own.rankBorder:Show(); own.rank:Show()
            else
                own.rankBorder:Hide(); own.rank:Hide()
            end
        elseif state == STATE.Maxed or rank >= maxRanks then
            -- Era: a maxed talent gets the gold slot and gold rank
            own.slot:SetVertexColor(1, 0.82, 0)
            own.rankBorder:SetVertexColor(1, 1, 1)
            own.rank:SetTextColor(1, 0.82, 0)
            own.rankBorder:Show(); own.rank:Show()
        else
            -- Era: green while there are ranks still to buy
            own.slot:SetVertexColor(0.1, 1, 0.1)
            own.rankBorder:SetVertexColor(1, 1, 1)
            if state == STATE.RefundInvalid or state == STATE.DisplayError then
                own.rank:SetTextColor(1, 0.1, 0.1)
            else
                own.rank:SetTextColor(0.1, 1, 0.1)
            end
            own.rankBorder:Show(); own.rank:Show()
        end
    else
        for _, r in ipairs(NodeRegionsToFade(node)) do Restore(r) end
        if own.slot then own.slot:Hide(); own.ring:Hide(); own.rankBorder:Hide(); own.rank:Hide() end
    end
end

-- where a node of the chosen tree goes on the page; other trees are
-- parked a page-width or more outside the clipped viewport
local function Place(tree, p, selectedIndex, treeIndex)
    local offX = (VIEW.w - (tree.maxX - tree.minX)) / 2
    local x = offX + (p.x - tree.minX) + (treeIndex - selectedIndex) * 2000
    local y = TOP_PAD + (p.y - tree.minY) - M.scroll
    return x, y
end

local function PlaceNodes(bp, trees, selected)
    M.placing = true
    for k, tree in ipairs(trees) do
        for _, p in ipairs(tree.nodes) do
            local x, y = Place(tree, p, selected, k)
            local node = p.node
            node:ClearAllPoints()
            node:SetPoint("CENTER", bp, "TOPLEFT", x, -y)
            SkinNode(node, true)
        end
    end
    M.placing = nil
end

--------------------------------------------------------------------------
-- Era's branches and arrows, from each node's own list of edges
--------------------------------------------------------------------------

local function Branch(lines, kind, active, x, y, w, h)
    lines.usedBranches = lines.usedBranches + 1
    local t = lines.branches[lines.usedBranches]
    if not t then
        t = lines:CreateTexture(nil, "ARTWORK")
        t:SetTexture(ART.branches)
        lines.branches[lines.usedBranches] = t
    end
    local c = BRANCH[kind][active and 1 or -1]
    t:SetTexCoord(c[1], c[2], c[3], c[4])
    t:SetSize(w, h)
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", lines, "TOPLEFT", x, -y)
    t:Show()
end

local function Arrow(lines, kind, active, cx, cy)
    lines.usedArrows = lines.usedArrows + 1
    local t = lines.arrows[lines.usedArrows]
    if not t then
        local parent = lines.arrowFrame or lines
        t = parent:CreateTexture(nil, "OVERLAY")
        t:SetTexture(ART.arrows)
        t:SetSize(TILE, TILE)
        lines.arrows[lines.usedArrows] = t
    end
    local c = ARROW[kind][active and 1 or -1]
    t:SetTexCoord(c[1], c[2], c[3], c[4])
    t:ClearAllPoints()
    t:SetPoint("CENTER", lines, "TOPLEFT", cx, -cy)
    t:Show()
end

-- is any talent (other than the two ends) in the way of a run along a
-- row (y fixed, x0..x1) or down a column (x fixed, y0..y1)?
local function Blocked(tree, a, b, x0, y0, x1, y1, selected, k)
    local lo, hi = math.min(x0, x1) - 25, math.max(x0, x1) + 25
    local top, bottom = math.min(y0, y1) - 25, math.max(y0, y1) + 25
    for _, p in ipairs(tree.nodes) do
        if p ~= a and p ~= b then
            local px, py = Place(tree, p, selected, k)
            if px > lo and px < hi and py > top and py < bottom then return true end
        end
    end
    return false
end

-- one edge, from talent A down (or across) to talent B it unlocks
local function DrawEdge(lines, tree, a, b, active, selected, k)
    local ax, ay = Place(tree, a, selected, k)
    local bx, by = Place(tree, b, selected, k)
    local half = NodeSize(a.node) / 2
    local halfTile = TILE / 2
    if math.abs(ax - bx) < 2 then
        -- straight down: the bar from A's foot to B's head, the arrow over B's head
        if by > ay then
            local h = (by - half) - (ay + half)
            if h > 0 then Branch(lines, "down", active, ax - halfTile, ay + half, TILE, h) end
            Arrow(lines, "top", active, bx, by - half - ARROW_LIFT)
        else
            local h = (ay - half) - (by + half)
            if h > 0 then Branch(lines, "up", active, ax - halfTile, by + half, TILE, h) end
        end
        return 1
    end
    -- Era names its arrow tiles by the side of the talent they sit on:
    -- "left" is the tile on the dependent's left, pointing in at it
    if math.abs(ay - by) < 2 then
        -- across: the bar between them, the arrow at B's near side
        if bx > ax then
            local w = (bx - half) - (ax + half)
            if w > 0 then Branch(lines, "right", active, ax + half, ay - halfTile, w, TILE) end
            Arrow(lines, "left", active, bx - half - ARROW_LIFT, by)
        else
            local w = (ax - half) - (bx + half)
            if w > 0 then Branch(lines, "left", active, bx + half, ay - halfTile, w, TILE) end
            Arrow(lines, "right", active, bx + half + ARROW_LIFT, by)
        end
        return 1
    end
    if by > ay and not Blocked(tree, a, b, ax, ay, bx, ay, selected, k) and not Blocked(tree, a, b, bx, ay, bx, by, selected, k) then
        -- Era's way round a corner: along A's row to B's column, then down into B
        if bx > ax then
            local w = (bx - halfTile) - (ax + half)
            if w > 0 then Branch(lines, "right", active, ax + half, ay - halfTile, w, TILE) end
            Branch(lines, "topright", active, bx - halfTile, ay - halfTile, TILE, TILE)
        else
            local w = (ax - half) - (bx + halfTile)
            if w > 0 then Branch(lines, "left", active, bx + halfTile, ay - halfTile, w, TILE) end
            Branch(lines, "topleft", active, bx - halfTile, ay - halfTile, TILE, TILE)
        end
        local h = (by - half) - (ay + halfTile)
        if h > 0 then Branch(lines, "down", active, bx - halfTile, ay + halfTile, TILE, h) end
        Arrow(lines, "top", active, bx, by - half - ARROW_LIFT)
        return 1
    end
    if by > ay then
        -- that cell is taken: down A's column to B's row, then across into B
        local h = (by - halfTile) - (ay + half)
        if h > 0 then Branch(lines, "down", active, ax - halfTile, ay + half, TILE, h) end
        if bx > ax then
            Branch(lines, "bottomleft", active, ax - halfTile, by - halfTile, TILE, TILE)
            local w = (bx - half) - (ax + halfTile)
            if w > 0 then Branch(lines, "right", active, ax + halfTile, by - halfTile, w, TILE) end
            Arrow(lines, "left", active, bx - half - ARROW_LIFT, by)
        else
            Branch(lines, "bottomright", active, ax - halfTile, by - halfTile, TILE, TILE)
            local w = (ax - halfTile) - (bx + half)
            if w > 0 then Branch(lines, "left", active, bx + half, by - halfTile, w, TILE) end
            Arrow(lines, "right", active, bx + half + ARROW_LIFT, by)
        end
        return 1
    end
    return 0
end

local function ButtonFor(tf, id, byID)
    if byID[id] then return byID[id] end
    if tf.GetTalentButtonByNodeID then
        local ok, b = pcall(tf.GetTalentButtonByNodeID, tf, id)
        if ok and b then return b end
    end
end

local function DrawLines(tf, lines, tree, selected)
    lines.usedBranches, lines.usedArrows = 0, 0
    local drawn = 0
    if tree then
        local byID = {}
        for _, p in ipairs(tree.nodes) do
            local id = NodeID(p.node)
            if id ~= nil then byID[id] = p.node end
        end
        for _, a in ipairs(tree.nodes) do
            local edges = a.info.visibleEdges
            if type(edges) == "table" then
                for _, e in ipairs(edges) do
                    local target = type(e) == "table" and e.targetNode
                    local button = target ~= nil and ButtonFor(tf, target, byID)
                    local b = button and tree.byNode[button]
                    if b then
                        -- Era's gold ran only into a talent whose tier was
                        -- open too; a gated one gets the grey branch
                        local active = e.isActive == true and VisualState(b.node) ~= STATE.Gated
                        drawn = drawn + DrawEdge(lines, tree, a, b, active, selected, selected)
                    end
                end
            end
        end
    end
    for i = lines.usedBranches + 1, #lines.branches do lines.branches[i]:Hide() end
    for i = lines.usedArrows + 1, #lines.arrows do lines.arrows[i]:Hide() end
    return drawn
end

--------------------------------------------------------------------------
-- Forever's page: its canvas clipped to Era's viewport, its furniture
-- faded or moved
--------------------------------------------------------------------------

local function PlaceCanvas(tf, on)
    local bp = tf.ButtonsParent
    local own = Own(bp)
    if on then
        Remember(bp)
        if not own.hooked and hooksecurefunc then
            hooksecurefunc(bp, "SetPoint", function()
                if M.placing or M.applying or M.mode ~= "restyled" or not M.applied then return end
                M.ApplyLater()
            end)
            own.hooked = true
        end
        M.placing = true
        bp:ClearAllPoints()
        bp:SetPoint("TOPLEFT", M.frame.view, "TOPLEFT", 0, 0)
        bp:SetSize(VIEW.w, VIEW.h)
        M.placing = nil
        if bp.SetClipsChildren then
            if own.clip == nil then
                local ok, c = pcall(function() return bp.DoesClipChildren and bp:DoesClipChildren() end)
                own.clip = (ok and c == true) or false
            end
            bp:SetClipsChildren(true)
        end
    else
        Restore(bp)
        if bp.SetClipsChildren and own.clip ~= nil then bp:SetClipsChildren(own.clip) end
    end
end

local function ApplyText()
    return Str("TALENT_FRAME_APPLY_BUTTON_TEXT", "Apply Changes")
end

local function IsApplyButton(f)
    local t = Text(f)
    if not t then return false end
    return t == ApplyText() or t:lower():find("apply", 1, true) ~= nil
end

-- the buttons on Forever's page, this frame and one level down
local function PageButtons(tf)
    local buttons, holders = {}, {}
    for _, child in ipairs(Children(tf)) do
        if child ~= tf.ButtonsParent then
            if ObjectType(child) == "Button" then
                buttons[#buttons + 1] = child
            else
                for _, grand in ipairs(Children(child)) do
                    if ObjectType(grand) == "Button" and Text(grand) then
                        buttons[#buttons + 1] = grand
                        holders[child] = true
                    end
                end
            end
        end
    end
    return buttons, holders
end

local KEEP = {ButtonsParent = true, AnimationHolder = true, FxModelScene = true, SelectionChoiceFrame = true}

local function Furniture(tf, on)
    local buttons, holders = PageButtons(tf)
    local apply, others = nil, {}
    for _, b in ipairs(buttons) do
        if not apply and IsApplyButton(b) then apply = b
        elseif Text(b) and Text(b) ~= "" then others[#others + 1] = b end
    end
    M.applyButton, M.sideButtons = apply, others
    local faded, boxes = 0, 0
    local keepFrames = {}
    for key in pairs(KEEP) do if tf[key] then keepFrames[tf[key]] = true end end
    for _, child in ipairs(Children(tf)) do
        if not keepFrames[child] and not holders[child] and child ~= apply then
            local kind = ObjectType(child)
            if kind == "Button" and Text(child) and Text(child) ~= "" then
                -- a side button: placed below
            else
                -- faded, and dead to the mouse: alpha alone leaves a
                -- box or a button there to click on
                if on then
                    Fade(child)
                    if child.EnableMouse then child:EnableMouse(false) end
                    if kind == "EditBox" then boxes = boxes + 1 else faded = faded + 1 end
                else
                    Restore(child)
                end
            end
        end
    end
    -- the page's own art: backgrounds, dividers, labels
    for _, r in ipairs(Regions(tf)) do
        if ObjectType(r) ~= "MaskTexture" then
            if on then Fade(r); faded = faded + 1 else Restore(r) end
        end
    end
    M.faded, M.boxes = faded, boxes
    local controls = M.frame.controls
    if apply then
        if on then
            Remember(apply)
            apply:ClearAllPoints()
            apply:SetPoint("RIGHT", controls, "BOTTOMRIGHT", -120, 94)
            local w = Own(apply).saved.width
            if apply.SetSize then apply:SetSize((w and w <= 120) and w or 110, 22) end
        else
            Restore(apply)
        end
    end
    if on then
        controls.points:ClearAllPoints()
        if apply then
            controls.points:SetPoint("RIGHT", apply, "LEFT", -8, 0)
        else
            controls.points:SetPoint("RIGHT", controls, "BOTTOMRIGHT", -128, 94)
        end
    end
    -- Forever's other buttons (Primary/Secondary, if that is what they
    -- are) at the right edge, where Era 1.15 kept its spec tabs
    for i, b in ipairs(others) do
        if on then
            Anchor(b, "TOPLEFT", controls, "TOPRIGHT", -32, -65 - (i - 1) * 30)
        else
            Restore(b)
        end
    end
end

local function FadeEdges(tf, on)
    local n = 0
    for _, edge in ipairs(Edges(tf)) do
        local own = Own(edge)
        if on then
            if not own.hooked and hooksecurefunc and type(edge.UpdateState) == "function" then
                -- Forever sets an edge's alpha itself on every redraw
                hooksecurefunc(edge, "UpdateState", function(e)
                    if M.mode == "restyled" and M.applied and e.SetAlpha then e:SetAlpha(0) end
                end)
                own.hooked = true
            end
            Fade(edge)
            n = n + 1
        else
            Restore(edge)
        end
    end
    for _, other in ipairs(Others(tf)) do
        if on then Fade(other) else Restore(other) end
    end
    return n
end

--------------------------------------------------------------------------
-- applying and undoing
--------------------------------------------------------------------------

local function Retreat()
    if M.frame then M.frame:Hide(); M.frame.controls:Hide() end
    if M.lines then M.lines:Hide() end
end

-- everything back to Forever's, keeping our frames for next time. Our
-- hooks see the restoring (ButtonsParent's anchors going back is a
-- SetPoint) and must not answer it, hence the applying flag.
local function UndoInner()
    local tf = TreeFrame()
    if tf and M.applied then
        -- every button, the ones back in Forever's pool included: a
        -- pooled button keeps its dress until it is handed out again
        for _, node in ipairs(AllNodes(tf)) do
            Restore(node)
            SkinNode(node, false)
        end
        FadeEdges(tf, false)
        Furniture(tf, false)
        PlaceCanvas(tf, false)
    end
    M.applied = false
    Retreat()
    ns.PSF.Release("talents")
end

local function Undo()
    M.applying = true
    local ok, err = pcall(UndoInner)
    M.applying = nil
    if not ok then error(err, 0) end
end

local function UpdateTabs(trees)
    local controls = M.frame.controls
    for k, tab in ipairs(controls.tabs) do
        local tree = trees[k]
        if tree then
            tab.Text:SetText(TreeName(k))
            if tab.Text.GetStringWidth then tab:SetWidth(math.max(84, tab.Text:GetStringWidth() + 44)) end
            ns.SetEraTabSelected(tab, k == M.tree)
            tab:Show()
        else
            tab:Hide()
        end
    end
end

local function UpdateTexts(tf, trees, tree)
    local controls = M.frame.controls
    local name = TreeName(M.tree)
    controls.box.text:SetText(("%s: %d"):format(name, tree and tree.spent or 0))
    local unspent = Unspent(tf)
    if unspent then
        local ok, text = pcall(string.format, Str("UNSPENT_TALENT_POINTS", "Talent Points: %s"), unspent)
        if not ok then text = ("Talent Points: %s"):format(unspent) end
        controls.points:SetText(text)
        controls.points:Show()
    else
        controls.points:Hide()
    end
end

local function UpdateBackground()
    local view = M.frame.view
    local art = TreeArt(M.tree, TreeName(M.tree))
    local base = art and (ART.treeBase .. art .. "-")
    M.treeArt = art
    M.treeArtMissing = base ~= nil and not HasFile(base .. "TopLeft")
    for key, suffix in pairs({topLeft = "TopLeft", topRight = "TopRight", bottomLeft = "BottomLeft", bottomRight = "BottomRight"}) do
        local t = view[key]
        if base and not M.treeArtMissing then
            t:SetTexture(base .. suffix)
            t:Show()
        else
            t:Hide()
        end
    end
end

local function UpdateScroll(tree)
    local slider = M.frame.controls.slider
    local range = tree and math.max(0, tree.height - VIEW.h) or 0
    if M.scroll > range then M.scroll = range end
    if M.scroll < 0 then M.scroll = 0 end
    M.settingScroll = true
    slider:SetMinMaxValues(0, range)
    slider:SetValue(M.scroll)
    M.settingScroll = nil
    slider:SetShown(range > 0)
end

-- the tree Era would open on: the one with the most points in it
local function DefaultTree(trees)
    local best, bestSpent = 1, -1
    for k, t in ipairs(trees) do
        if t.spent > bestSpent then best, bestSpent = k, t.spent end
    end
    return best
end

-- a scroll or a tab change: only the positions move
function M.Reflow()
    local tf = TreeFrame()
    if not tf or not M.applied or not M.trees or M.applying then return end
    M.applying = true
    local ok, err = pcall(function()
        PlaceNodes(tf.ButtonsParent, M.trees, M.tree)
        M.branches = DrawLines(tf, M.lines, M.trees[M.tree], M.tree)
    end)
    M.applying = nil
    if not ok then error(err, 0) end
end

local function ApplyInner()
    local tf, psf = TreeFrame()
    if not tf then return end
    if not M.frame then M.frame = BuildFrame(psf) end
    if not PageShown() then
        if M.applied then Undo() else Retreat() end
        return
    end
    M.applying = true
    ns.PSF.Claim("talents", {portrait = false})
    -- from here on the page is ours, whatever happens next: an error
    -- part way through must still be undone in full
    M.applied = true
    local bp = tf.ButtonsParent
    if not M.lines or M.lines:GetParent() ~= bp then M.lines = BuildLines(bp) end
    -- the controls above Forever's page, which covers the whole window
    local level = math.max(tf:GetFrameLevel(), bp:GetFrameLevel()) + 50
    M.frame.controls:SetFrameLevel(level)
    M.lines:SetFrameLevel(bp:GetFrameLevel() + 1)
    if M.arrows then M.arrows:SetFrameLevel(bp:GetFrameLevel() + ARROWS_ABOVE) end
    Furniture(tf, true)
    PlaceCanvas(tf, true)
    M.edgesFaded = FadeEdges(tf, true)
    local trees = Trees(tf)
    M.trees = trees
    if #trees > MAX_TREES then
        for k = #trees, MAX_TREES + 1, -1 do trees[k] = nil end
    end
    if not M.tree or not trees[M.tree] then M.tree = DefaultTree(trees) end
    local tree = trees[M.tree]
    UpdateScroll(tree)
    PlaceNodes(bp, trees, M.tree)
    M.branches = DrawLines(tf, M.lines, tree, M.tree)
    UpdateTabs(trees)
    UpdateTexts(tf, trees, tree)
    UpdateBackground()
    if SetPortraitTexture then pcall(SetPortraitTexture, M.frame.portrait, "player") end
    M.frame:Show()
    M.frame.controls:Show()
    M.lines:Show()
end

-- the applying flag keeps our own hooks quiet while we move things, and
-- is cleared whatever happens, so one error cannot leave the part deaf
function M.Apply()
    if M.mode ~= "restyled" then return end
    if M.applying then return end
    local ok, err = pcall(ApplyInner)
    M.applying = nil
    if not ok then error(err, 0) end
end

function M.ApplyLater()
    if M.mode ~= "restyled" or M.applying then return end
    if C_Timer and C_Timer.After then
        if M.pending then return end
        M.pending = true
        C_Timer.After(0, Guard("later", function() M.pending = nil; M.Apply() end))
    else
        M.Apply()
    end
end

local TREE_METHODS = {"UpdateAllTalentButtonPositions", "UpdateTalentButtonPosition", "LoadTalentTreeInternal",
                      "UpdateAllButtons", "UpdateTreeCurrencyInfo", "UpdatePadding", "InstantiateTalentButton",
                      "AcquireEdge", "UpdateEdgesForButton", "RefreshGates"}

local function Hook()
    if M.hooked then return end
    local tf, psf = TreeFrame()
    if not tf or not hooksecurefunc then return end
    -- the window and the page coming and going: straight away, so the
    -- page never shows a frame of retail between the two looks. Blizzard's
    -- own OnShow has already run by the time a hooked script does.
    if psf.HookScript then
        psf:HookScript("OnShow", Guard("OnShow", M.Apply))
        psf:HookScript("OnHide", Guard("OnHide", Retreat))
    end
    if tf.HookScript then
        tf:HookScript("OnShow", Guard("page OnShow", M.Apply))
        tf:HookScript("OnHide", Guard("page OnHide", M.Apply))
    end
    -- Forever lays the nodes out again on every tree load and refresh
    for _, m in ipairs(TREE_METHODS) do
        if type(tf[m]) == "function" then hooksecurefunc(tf, m, Guard(m, M.ApplyLater)) end
    end
    M.hooked = true
end

--------------------------------------------------------------------------
-- module interface
--------------------------------------------------------------------------

local function IsForeverTalents()
    return TreeFrame() ~= nil
end

-- Forever's talents live in Blizzard_PlayerSpells, loaded on demand the
-- first time the window is opened, so at login there is nothing to hook
local function WatchForFrame()
    if M.watcher or not CreateFrame then return end
    local watcher = CreateFrame("Frame")
    watcher:RegisterEvent("ADDON_LOADED")
    pcall(watcher.RegisterEvent, watcher, "PLAYER_ENTERING_WORLD")
    watcher:SetScript("OnEvent", function(_, _, name)
        if M.mode ~= "waiting" then return end
        if name == "Blizzard_PlayerSpells" or IsForeverTalents() then
            if ns.SafeCall("talents", M.Enable, M) and M.mode == "restyled" then
                watcher:UnregisterAllEvents()
            end
        end
    end)
    M.watcher = watcher
end

function M:Enable()
    if G("PlayerTalentFrame") and not G("PlayerSpellsFrame") then
        self.mode = "native" -- classic client: Era's own talent frame
        return
    end
    if not IsForeverTalents() then
        self.mode = "waiting"
        WatchForFrame()
        return
    end
    self.missingArt = {}
    for _, key in ipairs({"topLeft", "topRight", "botLeft", "botRight", "branches", "arrows", "rankBorder", "slot", "quickslot"}) do
        if not HasFile(ART[key]) then self.missingArt[#self.missingArt + 1] = ART[key]:match("[^\\]+$") end
    end
    local _, psf = TreeFrame()
    ns.PSF.Init(psf)
    self.mode = "restyled"
    self.names = nil
    Hook()
    M.Apply()
end

function M:Force()
    if self.mode == "restyled" then M.Apply() end
end

function M:Disable()
    local was = self.mode
    self.mode = "off"
    if was == "restyled" then Undo() end
end

function M:Status()
    if self.mode == "restyled" then
        local trees = self.trees or {}
        local names = {}
        for k in ipairs(trees) do names[#names + 1] = ("%s (%d)"):format(TreeName(k), trees[k].spent) end
        local s = ("Era's talent frame: %d trees [%s], showing %d, %d branches drawn, %d of Forever's pieces faded"):format(
            #trees, table.concat(names, ", "), self.tree or 0, self.branches or 0, self.faded or 0)
        if self.treeArt then
            s = s .. (", tree painting %s%s"):format(self.treeArt, self.treeArtMissing and " (file missing, plain floor)" or "")
        end
        if self.missingArt and #self.missingArt > 0 then
            s = s .. " (art missing: " .. table.concat(self.missingArt, ", ") .. ")"
        end
        if not self.applied then s = s .. " (page not up)" end
        return s
    elseif self.mode == "native" then
        return "classic client, Era's own talent frame"
    elseif self.mode == "waiting" then
        return "waiting for Forever's talent window to load (it loads the first time the window is opened)"
    end
    return "off"
end

ns.RegisterModule("talents", M)
