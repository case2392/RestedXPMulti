-- Forever Classic UI - the classic bottom bar
--
-- Classic Era draws one 1024x53 "MainMenuBar" along the bottom of the
-- screen: four 256x43 strips of dwarf stone (UI-MainMenuBar-Dwarf) with
-- gryphon end caps, twelve 36x36 action buttons 42px apart in the stone
-- slots from x=8, the page number and its two arrows right of them, the
-- micro buttons (29x37, 3px overlap) from x=552, the bag slots (37x37,
-- 5px apart) ending 6px from the right edge, and the experience bar in the
-- top 13px of the bar with a 10px stone ledge over it. The extra bars sit
-- above it: bottom-left and bottom-right bars either side of the screen
-- centre, the right bars vertical against the right edge.
--
-- Forever (Camelot flavor) keeps the gryphons but everything else is the
-- retail layout: 45px buttons 47px apart in a "UI-HUD-ActionBar-Frame"
-- border, the micro menu and bag bar floating right of the bar, the
-- experience bar as its own framed strip above. Every one of those pieces
-- is an Edit Mode system that Blizzard re-anchors and re-sizes whenever a
-- layout is applied, so this module owns one frame (the stone bar art)
-- and re-applies the classic sizes and anchors after each of Blizzard's
-- refreshes (hooksecurefunc on the layout methods). The button containers
-- are scaled 36/45 instead of resizing the (protected) buttons, so every
-- piece of button art shrinks with them. Action bars are protected frames:
-- their anchors and sizes are only touched out of combat; a change that
-- lands in combat is applied when combat ends.
--
-- Forever lays the bottom bars out again on the way into combat (every
-- bar's PLAYER_REGEN_DISABLED handler calls its UpdateVisibility, which
-- calls EditMode's UpdateBottomActionBarPositions) and whenever the pet
-- or stance bar comes and goes, and that puts the two upper bars at its
-- own fixed offsets from the main bar (+22 and +606) - mid-fight, when a
-- protected frame cannot be anchored back by addon code. So a secure
-- handler frame holds their Era anchors: its snippet runs in Blizzard's
-- restricted environment, where a protected frame may be anchored in
-- combat, and state drivers run it just after each of the state changes
-- that make Blizzard re-lay (combat, pet, form, vehicle). Everything the
-- snippet needs (the bars, the lift, whether each bar is still in its
-- default position) is handed to it out of combat.
--
-- Rule (shared with the rest of the addon): no Lua field writes into
-- Blizzard's frames, no calls into Blizzard's layout functions; widget
-- calls and hooksecurefunc only. Classic clients draw all of this already
-- and are left alone.

local addonName, ns = ...

local M = {mode = "off"}

local MMB = "Interface\\MainMenuBar\\"
local BUTTONS = "Interface\\Buttons\\"
local BAR_ART = MMB .. "UI-MainMenuBar-Dwarf"
local END_CAP = MMB .. "UI-MainMenuBar-EndCap-Dwarf"
local QUICKSLOT = BUTTONS .. "UI-Quickslot2"
local QUICKSLOT_DOWN = BUTTONS .. "UI-Quickslot-Depress"
local HILIGHT_SQUARE = BUTTONS .. "ButtonHilight-Square"
local CHECK_HILIGHT = BUTTONS .. "CheckButtonHilight"
local MICRO_HILIGHT = BUTTONS .. "UI-MicroButton-Hilight"
local EXHAUSTION_TICK = MMB .. "UI-ExhaustionTickNormal"
local EXHAUSTION_TICK_HL = MMB .. "UI-ExhaustionTickHighlight"
local STATUS_BAR = "Interface\\TargetingFrame\\UI-StatusBar"

-- Era's classic geometry (MainMenuBar.xml, MainActionBar.xml, the Classic
-- Edit Mode preset, MainMenuBarMicroButtons.xml, MainMenuBarBagButtons.xml)
local BAR_W, BAR_H = 1024, 53
local BUTTON, STRIDE = 36, 42
local BUTTON_SCALE = 36 / 45     -- Forever's buttons are 45px
local MAIN_BAR_X, MAIN_BAR_Y = 8, 4
local PAGE_X, PAGE_Y = 506, 3    -- ActionBarPageNumber (42x36) from the art's bottom left
local MICRO_X, MICRO_Y = 552, 2  -- first micro button from the art's bottom left
local MICRO_W, MICRO_H = 29, 37
local MICRO_STRIDE = 26
local BAGS_X, BAGS_Y = -6, 2     -- backpack from the art's bottom right
local BAG_SIZE, BAG_PAD = 37, 5
-- Forever's extra bag pieces. Era had the 18x39 keyring left of the bags;
-- the reagent bag is Forever's and goes beside it, smaller than a bag so
-- the row still fits between the micro buttons and the bags.
local REAGENT_SIZE, SMALL_PAD = 30, 4
local KEYRING_W, KEYRING_H = 18, 39
local KEYRING_TEX = BUTTONS .. "UI-Button-KeyRing"
local KEYRING_COORDS = {0, 0.5625, 0, 0.609375}
local REAGENT_BUTTON, KEYRING_BUTTON = "CharacterReagentBag0Slot", "KeyRingButton"
-- Era had nine micro buttons; Forever has ten or eleven, plus a reagent bag
-- slot, in the same 466px run of bar between the page arrows and the bar's
-- right end. Eleven at Era's 26px stride need 291px and, with Era's bag
-- cluster, the keyring and the reagent slot beside them, there are 201.
-- Packing the row closer piled the buttons on each other (a report of ten
-- at 19), and scaling it down to fit left them small in their band of bar
-- with an empty strip above (a report of eleven at 74%: "the icons appear
-- small within their area"). So the row keeps Era's full 37px height and
-- the room comes from the bag side instead, a step at a time, the least
-- noticeable first and no more of each than is needed (PlanRow):
--   1. Era as it is: 26 apart, 37px bags 5 apart
--   2. the buttons packed to 24, where their faces touch (the 29px art
--      has two or three transparent pixels each side)
--   3. the reagent bag's slot leaves the bar while no reagent bag is in it
--   4. the bag slots close up, from 5 apart to as little as 1
--   5. the buttons packed to 22, their edges just overlapping
--   6. the four bag slots are drawn smaller, down to 28px beside the 37px
--      backpack: what Blizzard did itself when the micro row grew (its
--      Wrath constants: BAGS_BAR_SLOT_SIZE = 28, backpack 37)
--   7. only then is the row scaled down
-- Eleven buttons with the keyring and an empty reagent slot stop at 5:
-- 22 apart, the bags 1 apart, and nothing drawn smaller than Era drew it.
-- Packed buttons are stacked left over right (see LayoutMicroMenu) so it
-- is each one's right edge that goes under its neighbour, the way Era's
-- own art interlocks.
local MICRO_MIN_STRIDE = 24
local MICRO_HARD_STRIDE = 22
local MIN_BAG_PAD, SMALL_BAG_SIZE = 1, 28
-- the run the micro buttons and the bag cluster share
local RUN = BAR_W + BAGS_X - MICRO_X
-- Era draws the bar in UI units (1024 wide, 36px buttons) and Forever's
-- own buttons are 45, so beside Forever's bar Era's is four fifths the
-- size (a report: "much smaller than the original UI and can be hard to
-- see"). The bar size setting scales the whole bottom bar; 100 is Era's.
local SCALE_MIN, SCALE_MAX = 0.6, 1.5
-- Forever positions the main action bar off the micro menu's container:
--   MainActionBar.BOTTOMRIGHT = MicroMenuContainer.BOTTOMLEFT -4.5,-4
-- (read straight off a live client - the report records it). It re-applies
-- that during combat, when a protected frame cannot be anchored back, which
-- is why the bar jumped right mid-fight and stayed there until the fight
-- ended. The container is ours to place, so it is put where that sum lands
-- the bar exactly on Era's spot, and Blizzard's own layout then agrees with
-- ours instead of fighting it.
--
-- The micro buttons do not move with it: MicroMenu is anchored to the bar
-- art directly, so the container is only the hook Blizzard's arithmetic
-- hangs off and has no look of its own. That also means these two numbers
-- being wrong on some other build costs nothing visible - the bar would
-- simply jump as it used to.
local BLIZZ_MAIN_GAP_X, BLIZZ_MAIN_GAP_Y = -4.5, -4
-- the gryphons' frame level: Era's and Forever's own EndCaps frames
local CAPS_LEVEL = 100
-- Era's status bars (StatusTrackingBar.xml, Classic): each is 1024x13 and
-- so is its fill (the template's 8 is resized to the container on load,
-- StatusTrackingManagerOverrides.lua); the frame art over it leaves the
-- middle showing. The first sits in the top of the stone bar under the
-- ledge; a second one stands on the bar, 10 higher, in the reputation
-- watch bar's own frame.
local STATUS_H = 13
local STATUS_UP = -3             -- the upper bar's bottom edge from the art's top
-- Era's bottom bars sit 52 up, and rise for the status bars
-- (UIParentPanelManagerOverrides.lua, Classic): 5 when one is shown, in
-- the stone bar, and 15 when a second stands on it
local BOTTOM_BAR_X, BOTTOM_BAR_Y = 6, 52
local STATUS_LIFT_ONE, STATUS_LIFT_TWO = 5, 15
-- Era's fills (ExpBarOverrides.lua, Classic; FACTION_BAR_COLORS)
local XP_RESTED, XP_NORMAL = {0.0, 0.39, 0.88}, {0.58, 0.0, 0.55}
local REST_AREA_ALPHA = 0.15
local REP_COLORS = {
    {0.8, 0.3, 0.22}, {0.8, 0.3, 0.22}, {0.75, 0.27, 0}, {0.9, 0.7, 0},
    {0, 0.6, 0.1}, {0, 0.6, 0.1}, {0, 0.6, 0.1}, {0, 0.6, 0.1}
}
local REP_BLUE = {0.0, 0.5, 0.9}
-- the reputation watch bar's frame (Era's StandaloneFrameTexture1..5): the
-- first 16px are cut from the image's left edge, as Era cuts them
local WATCH_ART = "Interface\\PaperDollInfoFrame\\UI-ReputationWatchBar"
local WATCH_TILES = {
    {16, 0.01171875, 0.0625, 0.03125, 0.171875},
    {240, 0.0625, 1.0, 0.03125, 0.171875},
    {256, 0, 1.0, 0.203125, 0.34375},
    {256, 0, 1.0, 0.375, 0.515625},
    {256, 0, 1.0, 0.546875, 0.6875}
}
-- the four stone strips: rows of the 256x256 image (Era's MainMenuBarTexture0..3)
local STRIPS = {
    {x = -384, top = 0.83203125, bottom = 1.0},
    {x = -128, top = 0.58203125, bottom = 0.75},
    {x = 128, top = 0.33203125, bottom = 0.5},
    {x = 384, top = 0.08203125, bottom = 0.25}
}
-- the 10px ledge over the experience bar (Era's MainMenuBarFrameTexture1..4)
local LEDGES = {
    {0.79296875, 0.83203125}, {0.54296875, 0.58203125},
    {0.29296875, 0.33203125}, {0.04296875, 0.08203125}
}
-- Forever's micro buttons and the classic art for each. Forever has a few
-- Classic never had (professions, housing, the legacy tree): those borrow
-- the nearest classic icon so the row stays uniform.
local MICRO_ART = {
    CharacterMicroButton = "Character",   -- special: UI-MicroButtonCharacter-* + portrait
    SpellbookMicroButton = "Spellbook",
    PlayerSpellsMicroButton = "Spellbook",
    TalentMicroButton = "Talents",
    ProfessionMicroButton = "Abilities",
    QuestLogMicroButton = "Quest",
    SocialsMicroButton = "Socials",
    GuildMicroButton = "Socials",
    LFDMicroButton = "LFG",
    CollectionsMicroButton = "Mounts",
    EJMicroButton = "EJ",
    AchievementMicroButton = "Achievement",
    LegacyMicroButton = "Achievement",
    HousingMicroButton = "World",
    WorldMapMicroButton = "World",
    HelpMicroButton = "Help",
    StoreMicroButton = "BStore",
    MainMenuMicroButton = "MainMenu"
}
local MICRO_ORDER = {
    "CharacterMicroButton", "ProfessionMicroButton", "SpellbookMicroButton", "PlayerSpellsMicroButton",
    "TalentMicroButton", "LegacyMicroButton", "QuestLogMicroButton", "SocialsMicroButton",
    "HousingMicroButton", "GuildMicroButton", "LFDMicroButton", "CollectionsMicroButton",
    "AchievementMicroButton", "EJMicroButton", "WorldMapMicroButton", "HelpMicroButton",
    "StoreMicroButton", "MainMenuMicroButton"
}
local MICRO_COORDS = {0, 1, 0.359375, 1}   -- the 32x64 images hold the button in the lower part
local BAG_BUTTONS = {"MainMenuBarBackpackButton", "CharacterBag0Slot", "CharacterBag1Slot", "CharacterBag2Slot", "CharacterBag3Slot"}
-- bars and how they lay out (Era: 12 buttons, 42 apart)
local BARS = {
    {name = "MainActionBar", horizontal = true},
    {name = "MultiBarBottomLeft", horizontal = true},
    {name = "MultiBarBottomRight", horizontal = true},
    {name = "MultiBarRight", horizontal = false},
    {name = "MultiBarLeft", horizontal = false},
    {name = "MultiBar5", horizontal = true},
    {name = "MultiBar6", horizontal = true},
    {name = "MultiBar7", horizontal = true}
}

-- our own pieces hung on Blizzard frames, keyed by that frame
M.own = setmetatable({}, {__mode = "k"})
local function Own(frame)
    local t = M.own[frame]
    if not t then
        t = {}
        M.own[frame] = t
    end
    return t
end

local function G(name) return _G[name] end

local function InCombat()
    return InCombatLockdown and InCombatLockdown()
end

local function HasFile(path)
    return GetFileIDFromPath and GetFileIDFromPath(path) ~= nil
end

local function HasAtlas(name)
    return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil
end

local function Hide(region)
    if region then
        if region.Hide then region:Hide() end
        if region.SetAlpha then region:SetAlpha(0) end
    end
end

local function Fade(frame)
    if frame and frame.SetAlpha then frame:SetAlpha(0) end
end

-- a frame's anchor, with the offsets given in the *parent's* units: a
-- scaled frame reads SetPoint offsets in its own scale
local function Anchor(frame, point, rel, relPoint, x, y)
    if not frame or not rel then return end
    local scale = (frame.GetScale and frame:GetScale()) or 1
    if not scale or scale <= 0 then scale = 1 end
    frame:ClearAllPoints()
    frame:SetPoint(point, rel, relPoint, (x or 0) / scale, (y or 0) / scale)
end

--------------------------------------------------------------------------
-- bar size
--------------------------------------------------------------------------

-- the scale the bottom bar is drawn at: the saved percentage, held to the
-- range the setting offers and to what the screen can show (the stone
-- bar is 1024 wide, as wide as a 4:3 screen at Era's size)
function M.WantedScale()
    local pct = ns.db and tonumber(ns.db.barscale) or 100
    local s = pct / 100
    if s ~= s then s = 1 end
    s = math.max(SCALE_MIN, math.min(SCALE_MAX, s))
    local width = UIParent and UIParent.GetWidth and UIParent:GetWidth()
    if type(width) == "number" and width > 0 and s > 1 then
        s = math.max(1, math.min(s, width / BAR_W))
    end
    return s
end

-- the scale the bar was last laid out at (it only changes out of combat)
local function S()
    return M.scale or 1
end

--------------------------------------------------------------------------
-- the stone bar
--------------------------------------------------------------------------

local function BuildArt()
    if M.art or not CreateFrame then return M.art end
    local art = CreateFrame("Frame", "ForeverClassicUIMainMenuBar", UIParent)
    art:SetSize(BAR_W, BAR_H)
    art:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 0)
    if art.SetFrameStrata then art:SetFrameStrata("MEDIUM") end
    if art.SetFrameLevel then art:SetFrameLevel(1) end
    art.strips = {}
    for i, s in ipairs(STRIPS) do
        local t = art:CreateTexture(nil, "BACKGROUND")
        t:SetTexture(BAR_ART)
        t:SetTexCoord(0, 1, s.top, s.bottom)
        t:SetSize(256, 43)
        t:SetPoint("BOTTOM", art, "BOTTOM", s.x, 0)
        art.strips[i] = t
    end
    if HasFile(END_CAP) then
        -- Era and Forever both keep the gryphons on a frame at level 100,
        -- over the bars and their buttons (MainActionBar.xml: EndCaps
        -- frameLevel="100"); on the art at level 1 they went under every
        -- bar that crossed them (a report: "gryphons behind the action bar")
        local caps = CreateFrame("Frame", nil, art)
        caps:SetAllPoints(art)
        if caps.SetFrameStrata then caps:SetFrameStrata("MEDIUM") end
        if caps.SetFrameLevel then caps:SetFrameLevel(CAPS_LEVEL) end
        art.caps = caps
        art.leftCap = caps:CreateTexture(nil, "OVERLAY", nil, 5)
        art.leftCap:SetTexture(END_CAP)
        art.leftCap:SetSize(128, 128)
        art.leftCap:SetPoint("BOTTOM", art, "BOTTOM", -544, 0)
        art.rightCap = caps:CreateTexture(nil, "OVERLAY", nil, 5)
        art.rightCap:SetTexture(END_CAP)
        art.rightCap:SetTexCoord(1, 0, 0, 1)
        art.rightCap:SetSize(128, 128)
        art.rightCap:SetPoint("BOTTOM", art, "BOTTOM", 544, 0)
    end
    M.art = art
    return art
end

--------------------------------------------------------------------------
-- action buttons
--------------------------------------------------------------------------

-- classic button art: square icon, the UI-Quickslot2 ring at half alpha
-- (Era's NormalTexture), the classic pushed / highlight / checked textures.
-- Sizes are in the button's own 45-unit space (the container is scaled to
-- 36px), so Era's 40px ring is 50 units here.
local function SkinButton(btn)
    if not btn or not btn.SetNormalTexture then return end
    local own = Own(btn)
    Hide(btn.SlotArt)
    Hide(btn.SlotBackground)
    if btn.icon and btn.IconMask and btn.icon.RemoveMaskTexture then
        pcall(btn.icon.RemoveMaskTexture, btn.icon, btn.IconMask)
    end
    M.inSkin = true
    btn:SetNormalTexture(QUICKSLOT)
    local nt = btn.GetNormalTexture and btn:GetNormalTexture()
    if nt then
        nt:SetTexCoord(0.1875, 0.796875, 0.1875, 0.796875)
        nt:ClearAllPoints()
        nt:SetSize(50, 50)
        nt:SetPoint("CENTER", btn, "CENTER", 0, 0)
        if nt.SetDrawLayer then nt:SetDrawLayer("OVERLAY") end
        nt:SetAlpha(0.5)
    end
    btn:SetPushedTexture(QUICKSLOT_DOWN)
    local pt = btn.GetPushedTexture and btn:GetPushedTexture()
    if pt then
        pt:SetTexCoord(0, 1, 0, 1)
        pt:ClearAllPoints()
        pt:SetAllPoints(btn)
    end
    btn:SetHighlightTexture(HILIGHT_SQUARE, "ADD")
    local ht = btn.GetHighlightTexture and btn:GetHighlightTexture()
    if ht then
        ht:SetTexCoord(0, 1, 0, 1)
        ht:ClearAllPoints()
        ht:SetAllPoints(btn)
    end
    if btn.SetCheckedTexture then
        btn:SetCheckedTexture(CHECK_HILIGHT)
        local ct = btn.GetCheckedTexture and btn:GetCheckedTexture()
        if ct then
            if ct.SetBlendMode then ct:SetBlendMode("ADD") end
            ct:ClearAllPoints()
            ct:SetAllPoints(btn)
        end
    end
    M.inSkin = nil
    if not own.hooked and hooksecurefunc then
        own.hooked = true
        -- Blizzard puts its atlases back on every art refresh
        if type(btn.UpdateButtonArt) == "function" then
            hooksecurefunc(btn, "UpdateButtonArt", function(b)
                if M.mode == "restyled" and not M.inSkin then SkinButton(b) end
            end)
        end
    end
end

-- 36px buttons 42px apart: the containers (plain frames Blizzard lays
-- out) are scaled and re-anchored; hidden ones are skipped so the shown
-- buttons stay packed the way Era packs them. The containers hold the
-- action buttons and are protected with them: scaling or anchoring one
-- in combat is refused and printed as "ADDON BLOCKED" (a report, dozens
-- of lines per kill), so with combat on only the art is touched and the
-- geometry waits for the end of the fight.
local function LayoutBar(bar, horizontal, combat)
    if not bar or type(bar.actionButtons) ~= "table" then return 0 end
    local shown = 0
    local s = S()
    for _, btn in ipairs(bar.actionButtons) do
        SkinButton(btn)
        local c = btn.container
        if c and c.SetPoint then
            if not combat and c.SetScale then c:SetScale(BUTTON_SCALE * s) end
            if not c.IsShown or c:IsShown() then
                if not combat then
                    if horizontal then
                        Anchor(c, "BOTTOMLEFT", bar, "BOTTOMLEFT", shown * STRIDE * s, 0)
                    else
                        Anchor(c, "TOPLEFT", bar, "TOPLEFT", 0, -shown * STRIDE * s)
                    end
                end
                shown = shown + 1
            end
        end
    end
    return shown
end

local function BarSize(count, horizontal)
    local long = math.max(count * STRIDE - (STRIDE - BUTTON), BUTTON)
    if horizontal then return long, BUTTON end
    return BUTTON, long
end

--------------------------------------------------------------------------
-- page number and arrows
--------------------------------------------------------------------------

local function SkinPageButton(btn, dir)
    if not btn then return end
    local atlas = "hud-MainMenuBar-arrow" .. dir:lower()
    if btn.SetNormalAtlas and HasAtlas(atlas .. "-up") then
        btn:SetSize(19, 17)
        btn:SetNormalAtlas(atlas .. "-up")
        btn:SetPushedAtlas(atlas .. "-down")
        btn:SetDisabledAtlas(atlas .. "-disabled")
        btn:SetHighlightAtlas(atlas .. "-highlight", "ADD")
        return
    end
    local file = MMB .. "UI-MainMenu-Scroll" .. dir .. "Button-"
    if HasFile(file .. "Up") then
        btn:SetSize(32, 32)
        btn:SetNormalTexture(file .. "Up")
        btn:SetPushedTexture(file .. "Down")
        if btn.SetDisabledTexture then btn:SetDisabledTexture(file .. "Disabled") end
        btn:SetHighlightTexture(file .. "Highlight", "ADD")
        for _, get in ipairs({"GetNormalTexture", "GetPushedTexture", "GetDisabledTexture", "GetHighlightTexture"}) do
            local t = btn[get] and btn[get](btn)
            if t then t:ClearAllPoints(); t:SetAllPoints(btn) end
        end
    end
end

local function LayoutPageNumber(art)
    local bar = G("MainActionBar")
    local pn = bar and bar.ActionBarPageNumber
    if not pn then return end
    local s = S()
    pn:SetSize(42, 36)
    if pn.SetScale then pn:SetScale(s) end
    Anchor(pn, "BOTTOMLEFT", art, "BOTTOMLEFT", PAGE_X * s, PAGE_Y * s)
    if pn.Text then
        pn.Text:ClearAllPoints()
        pn.Text:SetPoint("CENTER", pn, "CENTER", 15, 0)
        if GameFontNormalSmall and pn.Text.SetFontObject then pn.Text:SetFontObject(GameFontNormalSmall) end
    end
    if pn.UpButton then
        SkinPageButton(pn.UpButton, "Up")
        pn.UpButton:ClearAllPoints()
        pn.UpButton:SetPoint("CENTER", pn, "CENTER", -6, 10)
    end
    if pn.DownButton then
        SkinPageButton(pn.DownButton, "Down")
        pn.DownButton:ClearAllPoints()
        pn.DownButton:SetPoint("CENTER", pn, "CENTER", -6, -10)
    end
end

--------------------------------------------------------------------------
-- micro buttons
--------------------------------------------------------------------------

local function MicroFiles(name)
    if name == "Character" then
        return BUTTONS .. "UI-MicroButtonCharacter-Up", BUTTONS .. "UI-MicroButtonCharacter-Down", nil
    end
    local prefix = BUTTONS .. "UI-MicroButton-" .. name
    return prefix .. "-Up", prefix .. "-Down", prefix .. "-Disabled"
end

local function PlacePortrait(btn)
    local p = btn.Portrait
    if not p then return end
    if btn.PortraitMask and p.RemoveMaskTexture then pcall(p.RemoveMaskTexture, p, btn.PortraitMask) end
    p:ClearAllPoints()
    p:SetSize(18, 25)
    p:SetPoint("CENTER", btn, "CENTER", 0, -1)
    -- Era draws the face over the button's frame, and Forever's portrait
    -- sits on ARTWORK like the frame does - but ours is set second, so it
    -- landed on top and the character button came out as an empty plate.
    -- The portrait goes a layer up, where Era has it.
    if p.SetDrawLayer then pcall(p.SetDrawLayer, p, "OVERLAY") end
end

local function SkinMicroButton(btn, name)
    if not btn or not btn.SetNormalTexture then return false end
    local up, down, disabled = MicroFiles(name)
    if not HasFile(up) then return false end
    local own = Own(btn)
    M.inSkin = true
    -- A micro button is a protected frame: its art can be changed at any
    -- time, but its size cannot be touched in combat. This runs from the
    -- hover and pushed hooks too, which fire mid-fight, so the resize
    -- waits and the row is laid out again when combat ends.
    -- 31 wide: the menu lays its children out with a -5 overlap, so 31
    -- gives Era's 26px stride; the 29px art is centred in it
    if InCombat() then
        M.pending = true
    else
        btn:SetSize(MICRO_W + 2, MICRO_H)
    end
    btn:SetNormalTexture(up)
    btn:SetPushedTexture(down)
    if disabled and btn.SetDisabledTexture then btn:SetDisabledTexture(disabled) end
    btn:SetHighlightTexture(MICRO_HILIGHT, "ADD")
    for _, get in ipairs({"GetNormalTexture", "GetPushedTexture", "GetDisabledTexture", "GetHighlightTexture"}) do
        local t = btn[get] and btn[get](btn)
        if t then
            t:SetTexCoord(unpack(MICRO_COORDS))
            t:ClearAllPoints()
            t:SetSize(MICRO_W, MICRO_H)
            t:SetPoint("CENTER", btn, "CENTER", 0, 0)
        end
    end
    Hide(btn.Background)
    Hide(btn.PushedBackground)
    Fade(btn.Shadow)
    Fade(btn.PushedShadow)
    Fade(btn.FlashContent)
    PlacePortrait(btn)
    M.inSkin = nil
    -- Forever fades the icon out under the mouse and cross-fades its own
    -- modern hover art in; ours is Era's glow, so the fade just made the
    -- icon vanish. The normal art is held at full alpha.
    local normal = btn.GetNormalTexture and btn:GetNormalTexture()
    if normal and hooksecurefunc then
        local mine = Own(normal)
        if not mine.alphaHooked then
            mine.alphaHooked = true
            hooksecurefunc(normal, "SetAlpha", function(t, a)
                if M.mode ~= "restyled" or M.inAlpha then return end
                if type(a) == "number" and a < 1 then
                    M.inAlpha = true
                    t:SetAlpha(1)
                    M.inAlpha = nil
                end
            end)
        end
        normal:SetAlpha(1)
    end
    if not own.hooked and hooksecurefunc then
        own.hooked = true
        local function Again(b) if M.mode == "restyled" and not M.inSkin then SkinMicroButton(b, name) end end
        if btn.HookScript then
            btn:HookScript("OnEnter", Again)
            btn:HookScript("OnLeave", Again)
        end
        for _, m in ipairs({"SetNormalAtlas", "SetPushedAtlas", "SetDisabledAtlas", "SetHighlightAtlas"}) do
            if type(btn[m]) == "function" then hooksecurefunc(btn, m, Again) end
        end
        -- Blizzard's menu layout puts the retail 32x40 size back
        if btn.HookScript then btn:HookScript("OnSizeChanged", Again) end
        for _, m in ipairs({"SetPushed", "SetNormal"}) do
            if type(btn[m]) == "function" then
                hooksecurefunc(btn, m, function(b)
                    if M.mode == "restyled" and not M.inSkin then Hide(b.Background); Hide(b.PushedBackground); PlacePortrait(b) end
                end)
            end
        end
    end
    return true
end

-- Forever's Store button is disabled on this client (no shop): it is
-- hidden so it does not take a slot. It comes back the moment it is enabled.
local function StoreWanted()
    local store = G("StoreMicroButton")
    if not store then return true end
    if store.IsEnabled and not store:IsEnabled() then return false end
    return true
end

-- the micro buttons that stand in the row, in Era's order. Only the menu's
-- own children count: Forever keeps a few more micro buttons as globals
-- parked elsewhere (shown, but not in the row).
local function MicroRow()
    local menu = G("MicroMenu")
    if menu then
        Hide(menu.BorderArt)
        Hide(menu.BackgroundArt)
    end
    local store = G("StoreMicroButton")
    if store then
        if StoreWanted() then
            if store.SetAlpha then store:SetAlpha(1) end
        else
            Hide(store)
        end
    end
    local skinned, row = 0, {}
    for _, gname in ipairs(MICRO_ORDER) do
        local btn = G(gname)
        if btn and SkinMicroButton(btn, MICRO_ART[gname]) then
            skinned = skinned + 1
            local inMenu = menu == nil or (btn.GetParent and btn:GetParent() == menu)
            if inMenu and (not btn.IsShown or btn:IsShown()) then row[#row + 1] = btn end
        end
    end
    M.microSkinned = skinned
    M.microShown = #row
    return row
end

local function MicroWidth(count, stride)
    return math.max(count - 1, 0) * stride + MICRO_W + 2
end

-- is there a reagent bag in the reagent bag's slot? nil when the client
-- will not say (then the slot stays, as it would with one in it)
local function ReagentBagEquipped()
    if not (C_Container and C_Container.GetContainerNumSlots) then return nil end
    local index = (Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag) or 5
    local ok, slots = pcall(C_Container.GetContainerNumSlots, index)
    if ok and type(slots) == "number" then return slots > 0 end
    return nil
end

-- Forever hides the keyring on a character the game says has no use for
-- one (C_ActionBar.ShouldShowKeyring): then it takes no room on the bar
local function KeyringOnBar()
    local keyring = G(KEYRING_BUTTON)
    return keyring ~= nil and (not keyring.IsShown or keyring:IsShown()) and true or false
end

-- the reagent bag's slot counts while it is shown, or hidden by this
-- addon (see Stow); one that something else has hidden is left alone
local function ReagentOnBar()
    local reagent = G(REAGENT_BUTTON)
    if not reagent then return false end
    if M.own[reagent] and M.own[reagent].stowed then return true end
    return (not reagent.IsShown or reagent:IsShown()) and true or false
end

-- How the micro row and the bag cluster share the run of bar between the
-- page arrows and the bar's right end (see the steps by MICRO_MIN_STRIDE).
-- Returns the plan both layouts follow: the micro buttons' stride and
-- scale, the bag slots' size and spacing, whether the reagent slot stays.
local function PlanRow(count)
    local bags = 0
    for _, gname in ipairs(BAG_BUTTONS) do
        if G(gname) then bags = bags + 1 end
    end
    local gaps = math.max(bags - 1, 0)      -- the bag slots beside the backpack
    local hasReagent = bags > 0 and ReagentOnBar()
    local hasKeyring = bags > 0 and KeyringOnBar()
    -- (without Era's keyring art the keyring is drawn as a small slot)
    local keyringWidth = HasFile(KEYRING_TEX) and KEYRING_W or REAGENT_SIZE
    -- (asked whenever there is a slot, so the bag events below can tell a
    -- change of the answer from one more loot)
    local equipped = nil
    if G(REAGENT_BUTTON) then equipped = ReagentBagEquipped() end
    M.reagentKnown = equipped
    local plan = {stride = MICRO_STRIDE, scale = 1, bagSize = BAG_SIZE, bagPad = BAG_PAD, hasReagent = hasReagent,
                  reagent = hasReagent, reagentSize = REAGENT_SIZE, keyring = hasKeyring, step = 1}
    local function Room()
        local width = 0
        if bags > 0 then width = BAG_SIZE + gaps * (plan.bagPad + plan.bagSize) end
        -- the reagent slot is the small one: never bigger than a bag slot
        plan.reagentSize = math.min(REAGENT_SIZE, plan.bagSize)
        if plan.reagent then width = width + SMALL_PAD + plan.reagentSize end
        if hasKeyring then width = width + SMALL_PAD + keyringWidth end
        return RUN - width - SMALL_PAD
    end
    -- the widest stride, from Era's down to the floor, the room allows
    local function Fit(floor)
        local room = Room()
        if MicroWidth(count, MICRO_STRIDE) <= room then return MICRO_STRIDE end
        if count > 1 then
            local stride = (room - MICRO_W - 2) / (count - 1)
            if stride >= floor then return stride end
        end
        return nil
    end
    -- how much room the row is short of at a stride, shared between the gaps
    local function Short(stride)
        return gaps > 0 and math.max(MicroWidth(count, stride) - Room(), 0) / gaps or 0
    end
    local stride = Fit(MICRO_STRIDE)
    if not stride then
        stride = Fit(MICRO_MIN_STRIDE)
        plan.step = 2
    end
    if not stride and hasReagent and equipped == false then
        plan.reagent = false
        stride = Fit(MICRO_MIN_STRIDE)
        plan.step = 3
    end
    if not stride and gaps > 0 then
        plan.bagPad = math.max(MIN_BAG_PAD, math.floor(BAG_PAD - Short(MICRO_MIN_STRIDE)))
        stride = Fit(MICRO_MIN_STRIDE)
        plan.step = 4
    end
    if not stride then
        stride = Fit(MICRO_HARD_STRIDE)
        plan.step = 5
    end
    if not stride and gaps > 0 then
        plan.bagSize = math.max(SMALL_BAG_SIZE, math.floor(BAG_SIZE - Short(MICRO_HARD_STRIDE)))
        stride = Fit(MICRO_HARD_STRIDE)
        plan.step = 6
    end
    if not stride then
        stride = MICRO_HARD_STRIDE
        local room = Room()
        if room > 0 then plan.scale = math.min(1, room / MicroWidth(count, stride)) end
        plan.step = 7
    end
    plan.stride = stride
    plan.room = Room()
    return plan
end

-- Era: 552 + 26 per button. The row keeps Era's height and takes the
-- stride and (as the last resort) the scale the plan worked out.
local function LayoutMicroMenu(art, row, plan)
    local container = G("MicroMenuContainer")
    local menu = G("MicroMenu")
    local s = S()
    local shown = #row
    local stride, scale = plan.stride, plan.scale
    local natural = MicroWidth(shown, stride)
    M.microStride, M.microScale = stride, scale
    -- packed closer than Era, the buttons overlap. Blizzard's own order
    -- draws each one over the one to its left, which buries the left
    -- button's face; the row reads right stacking the other way, so the
    -- levels descend and only the trailing edges go under.
    local base = (menu and menu.GetFrameLevel and menu:GetFrameLevel() or 1) + 1
    -- ...and all of them above the bag slots. Mid-fight Blizzard's own bag
    -- layout (an item lifted or dropped) spreads the slots 2 apart and
    -- puts the keyring back to its 33px, and nothing may undo that until
    -- the fight ends: the keyring then reaches under the last micro button
    -- instead of over it, and the button still takes the click.
    local bags = G("BagsBar")
    if bags and bags.GetFrameLevel then base = math.max(base, bags:GetFrameLevel() + 2) end
    for i, btn in ipairs(row) do
        if menu and btn.SetPoint then Anchor(btn, "BOTTOMLEFT", menu, "BOTTOMLEFT", (i - 1) * stride, 0) end
        if btn.SetFrameLevel then pcall(btn.SetFrameLevel, btn, base + shown - i) end
    end
    if menu and menu.SetSize then
        menu:SetSize(natural, MICRO_H)
        if menu.SetScale then menu:SetScale(scale * s) end
        -- on the art, not on the container: the container is moved to suit
        -- Blizzard's arithmetic and the buttons must not follow it
        Anchor(menu, "BOTTOMLEFT", art, "BOTTOMLEFT", MICRO_X * s, MICRO_Y * s)
    end
    if container and container.SetPoint then
        -- the left edge Blizzard measures the main bar from (its gap is in
        -- the main bar's own units, which the bar size does not scale)...
        local mainWidth = BarSize(M.counts and M.counts.MainActionBar or 12, true)
        local left = (MAIN_BAR_X + mainWidth) * s - BLIZZ_MAIN_GAP_X
        local bottom = MAIN_BAR_Y * s - BLIZZ_MAIN_GAP_Y
        -- ...and a width that keeps its right edge where the row really
        -- ends, so the bag bar, which Blizzard hangs off that edge, is no
        -- worse off in combat than it was before
        local right = (MICRO_X + natural * scale) * s
        container:SetSize(math.max(right - left, 1), MICRO_H * scale * s)
        container:ClearAllPoints()
        container:SetPoint("BOTTOMLEFT", art, "BOTTOMLEFT", left, bottom)
        M.microAnchor = left
    end
end

--------------------------------------------------------------------------
-- bag slots
--------------------------------------------------------------------------

local function SkinBagButton(btn, size)
    if not btn or not btn.SetNormalTexture then return end
    local own = Own(btn)
    size = size or own.size or BAG_SIZE
    own.size = size
    M.inSkin = true
    -- this runs from the slot's OnSizeChanged hook too, and Blizzard lays
    -- the bag bar out mid-fight (an item lifted or dropped): a resize
    -- there waits for the fight to end, like the micro buttons'
    if InCombat() then
        M.pending = true
    else
        btn:SetSize(size, size)
    end
    -- Era's ItemButtonTemplate: the 64x64 quickslot ring centred a pixel low
    btn:SetNormalTexture(QUICKSLOT)
    local nt = btn.GetNormalTexture and btn:GetNormalTexture()
    if nt then
        local ring = math.floor(64 * size / BAG_SIZE + 0.5)
        nt:SetTexCoord(0, 1, 0, 1)
        nt:ClearAllPoints()
        nt:SetSize(ring, ring)
        nt:SetPoint("CENTER", btn, "CENTER", 0, -1)
        nt:SetAlpha(1)
    end
    btn:SetPushedTexture(QUICKSLOT_DOWN)
    local pt = btn.GetPushedTexture and btn:GetPushedTexture()
    if pt then pt:SetTexCoord(0, 1, 0, 1); pt:ClearAllPoints(); pt:SetAllPoints(btn) end
    btn:SetHighlightTexture(HILIGHT_SQUARE, "ADD")
    local ht = btn.GetHighlightTexture and btn:GetHighlightTexture()
    if ht then ht:SetTexCoord(0, 1, 0, 1); ht:ClearAllPoints(); ht:SetAllPoints(btn) end
    local icon = btn.icon or (btn.GetName and G(btn:GetName() .. "IconTexture"))
    if icon then
        -- Forever masks the icon to the retail slot shape (SquareMask / IconMask)
        for _, key in ipairs({"IconMask", "CircleMask", "SquareMask"}) do
            if btn[key] and icon.RemoveMaskTexture then pcall(icon.RemoveMaskTexture, icon, btn[key]) end
        end
        icon:ClearAllPoints()
        icon:SetAllPoints(btn)
    end
    Hide(btn.SlotBackground)
    Hide(btn.SlotArt)
    Fade(btn.IconBorder)
    -- Forever's own overlays on the slot (the gold frame while that bag's
    -- window is open, the search and context dimmers, keybind glow) are
    -- sized for its 48px slot: a report showed them hanging off the top
    -- left of the 37px one. They fit the button.
    for _, key in ipairs({"SlotHighlightTexture", "ItemContextOverlay", "SearchOverlay", "QuickKeybindHighlightTexture", "IconOverlay", "IconOverlay2"}) do
        local t = btn[key]
        if t and t.ClearAllPoints and t.SetAllPoints then
            t:ClearAllPoints()
            t:SetAllPoints(btn)
        end
    end
    M.inSkin = nil
    if not own.hooked and hooksecurefunc then
        own.hooked = true
        local function Again(b) if M.mode == "restyled" and not M.inSkin then SkinBagButton(b) end end
        for _, m in ipairs({"SetNormalAtlas", "SetPushedAtlas"}) do
            if type(btn[m]) == "function" then hooksecurefunc(btn, m, Again) end
        end
        -- Blizzard's bag layout puts the retail slot size back
        if btn.HookScript then btn:HookScript("OnSizeChanged", Again) end
    end
end

-- Era's keyring: the narrow 18x39 button (UI-Button-KeyRing, the upper
-- left of a 32x64 image), no icon. Forever's is a 33x45 retail slot.
local function SkinKeyRing(btn)
    if not btn or not btn.SetNormalTexture then return false end
    if not HasFile(KEYRING_TEX) then
        SkinBagButton(btn, REAGENT_SIZE)
        return true
    end
    local own = Own(btn)
    M.inSkin = true
    -- Blizzard's bag layout puts the keyring back to its 33x45 every time
    -- (KeyRingMixin:UpdateOrientation), in combat too
    if InCombat() then
        M.pending = true
    else
        btn:SetSize(KEYRING_W, KEYRING_H)
    end
    btn:SetNormalTexture(KEYRING_TEX)
    btn:SetPushedTexture(KEYRING_TEX .. "-Down")
    btn:SetHighlightTexture(KEYRING_TEX .. "-Highlight", "ADD")
    for _, get in ipairs({"GetNormalTexture", "GetPushedTexture", "GetHighlightTexture"}) do
        local t = btn[get] and btn[get](btn)
        if t then
            t:SetTexCoord(unpack(KEYRING_COORDS))
            t:ClearAllPoints()
            t:SetAllPoints(btn)
        end
    end
    -- the retail slot art sits on the icon; the classic button has none
    local icon = btn.icon or (btn.GetName and G(btn:GetName() .. "IconTexture"))
    Fade(icon)
    Fade(btn.IconBorder)
    Hide(btn.SlotBackground)
    Hide(btn.SlotArt)
    M.inSkin = nil
    if not own.hooked and hooksecurefunc then
        own.hooked = true
        local function Again(b) if M.mode == "restyled" and not M.inSkin then SkinKeyRing(b) end end
        for _, m in ipairs({"SetNormalAtlas", "SetPushedAtlas"}) do
            if type(btn[m]) == "function" then hooksecurefunc(btn, m, Again) end
        end
        if btn.HookScript then btn:HookScript("OnSizeChanged", Again) end
    end
    return true
end

-- Forever draws divider strips between the bag slots (pooled frames with
-- TopEdge / BottomEdge / Center) and the retail border round the bar
-- a pooled divider frame: faded now, and again whenever Blizzard shows it
local function FadeDivider(child, alpha)
    if not child.SetAlpha then return end
    child:SetAlpha(alpha)
    local own = Own(child)
    if not own.hooked and child.HookScript then
        own.hooked = true
        child:HookScript("OnShow", function(c) if M.mode == "restyled" then c:SetAlpha(0) end end)
    end
end

local function BagDividers(bar, alpha)
    if not bar or not bar.GetChildren then return end
    for _, child in ipairs({bar:GetChildren()}) do
        if child.TopEdge and child.BottomEdge and child.Center then FadeDivider(child, alpha) end
    end
end

-- A slot that is not wanted on the bar is hidden. Not faded: on this
-- client SetAlpha on an item button is Blizzard's own function
-- (ItemButtonMixin:SetAlpha) and fades the icon, leaving the slot's frame
-- drawn. Hidden, it is also skipped by Blizzard's bag layout, which
-- arranges the shown slots only. (Out of combat only, like the rest of
-- the bag layout.) Only a slot this addon hid is shown again.
local function Stow(btn)
    if not btn or not btn.Hide then return end
    Own(btn).stowed = true
    btn:Hide()
end

local function Unstow(btn)
    if not btn then return end
    local own = Own(btn)
    if own.stowed then
        own.stowed = nil
        if btn.Show then btn:Show() end
    end
end

local function LayoutBags(art, plan)
    local bar = G("BagsBar")
    if not bar or not bar.SetPoint then return end
    local s = S()
    if bar.SetScale then bar:SetScale(s) end
    Anchor(bar, "BOTTOMRIGHT", art, "BOTTOMRIGHT", BAGS_X * s, BAGS_Y * s)
    Hide(bar.BorderArt)
    BagDividers(bar, 0)
    local prev, width = nil, 0
    for _, gname in ipairs(BAG_BUTTONS) do
        local btn = G(gname)
        if btn then
            btn:ClearAllPoints()
            if prev then
                -- the four bag slots: Era's 37px 5 apart, closer and then
                -- smaller when the micro row needs the room (the backpack
                -- keeps its size either way)
                SkinBagButton(btn, plan.bagSize)
                btn:SetPoint("RIGHT", prev, "LEFT", -plan.bagPad, 0)
                width = width + plan.bagPad + plan.bagSize
            else
                SkinBagButton(btn, BAG_SIZE)
                btn:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
                width = BAG_SIZE
            end
            prev = btn
        end
    end
    local reagent = G(REAGENT_BUTTON)
    local stowed = nil
    if reagent and reagent.SetPoint and prev and plan.hasReagent then
        if plan.reagent then
            Unstow(reagent)
            SkinBagButton(reagent, plan.reagentSize)
            reagent:ClearAllPoints()
            reagent:SetPoint("RIGHT", prev, "LEFT", -SMALL_PAD, 0)
            width = width + SMALL_PAD + plan.reagentSize
            prev = reagent
        else
            -- no reagent bag and no room: the empty slot leaves the bar
            -- (it is back the moment a reagent bag is equipped)
            Stow(reagent)
            stowed = true
        end
    end
    M.reagentStowed = stowed
    local keyring = G(KEYRING_BUTTON)
    if keyring and keyring.SetPoint and prev and plan.keyring and SkinKeyRing(keyring) then
        keyring:ClearAllPoints()
        keyring:SetPoint("RIGHT", prev, "LEFT", -SMALL_PAD, 0)
        local w = keyring.GetWidth and keyring:GetWidth() or KEYRING_W
        width = width + SMALL_PAD + w
        prev = keyring
    end
    Hide(G("BagBarExpandToggle"))
    M.bagsWidth = width
    M.bagSize, M.bagPad = plan.bagSize, plan.bagPad
    bar:SetSize(width, BAG_SIZE)
end

--------------------------------------------------------------------------
-- experience / reputation bars: one in the top of the stone bar, a second
-- standing on it
--------------------------------------------------------------------------

-- Forever fills its bars with coloured atlases; Era's are the grey
-- UI-StatusBar gradient tinted by SetStatusBarColor. The tint Era gives a
-- bar, or nil for a bar Era never had (honor, artifact power...), whose
-- fill is left the way Forever draws it.
local function WatchedReaction()
    if not (C_Reputation and C_Reputation.GetWatchedFactionData) then return nil end
    local ok, data = pcall(C_Reputation.GetWatchedFactionData)
    if ok and type(data) == "table" and type(data.reaction) == "number" then return data.reaction end
    return nil
end

local function IsReputationBar(bar)
    return not bar.isExpBar and type(bar.UpdateBarTextures) == "function"
end

local function FillColor(bar)
    local own = Own(bar)
    if bar.isExpBar then
        local rested = own.rested
        if rested == nil and GetRestState then
            local ok, state = pcall(GetRestState)
            rested = ok and state == 1
        end
        return rested and XP_RESTED or XP_NORMAL
    end
    if IsReputationBar(bar) then
        -- Forever's "blue bar" factions (renown, paragon): Era had none
        if own.blue then return REP_BLUE end
        local reaction = own.reaction or WatchedReaction()
        local global = type(FACTION_BAR_COLORS) == "table" and reaction and FACTION_BAR_COLORS[reaction]
        if type(global) == "table" and type(global.r) == "number" and type(global.g) == "number" and type(global.b) == "number" then
            return {global.r, global.g, global.b}
        end
        return REP_COLORS[reaction] or REP_COLORS[4]
    end
    return nil
end

-- textures and colours only: safe at any time, combat included
local function ApplyFill(bar)
    local sb = bar and bar.StatusBar
    if not sb or not sb.SetStatusBarTexture then return end
    local ok, color = pcall(FillColor, bar)
    if not ok or type(color) ~= "table" then return end
    sb:SetStatusBarTexture(STATUS_BAR)
    ns.PlainFill(sb)    -- Forever's atlas left its nine-slice on the fill
    if sb.SetStatusBarColor then sb:SetStatusBarColor(color[1], color[2], color[3], 1) end
    -- the rested stretch ahead of the fill: Era's is a flat wash of the
    -- bar's colour at 15%, Forever's a solid dark blue atlas
    local rest = bar.ExhaustionLevelFillBar
    if rest and rest.SetColorTexture then
        rest:SetColorTexture(1, 1, 1, 1)
        if rest.SetVertexColor then rest:SetVertexColor(color[1], color[2], color[3], REST_AREA_ALPHA) end
    end
    local tick = bar.ExhaustionTick
    local glow = tick and tick.GetHighlightTexture and tick:GetHighlightTexture()
    if glow and glow.SetVertexColor then glow:SetVertexColor(color[1], color[2], color[3]) end
end

local function SkinStatusBar(bar)
    if not bar then return end
    local own = Own(bar)
    local sb = bar.StatusBar
    if sb then
        -- Era: the fill is the whole 13px bar (Forever resizes it to 3
        -- short of its container). The stone strip hides its bottom 3px
        -- in the stone bar, and the frame art its edges.
        sb:ClearAllPoints()
        sb:SetAllPoints(bar)
        -- Era's half-black behind the fill. It goes on the bar itself and
        -- Forever's own background (a texture of the fill's frame, which
        -- draws over the bar's) is emptied, or it would sit on top of the
        -- rested stretch and all but hide it.
        if sb.Background and sb.Background.SetColorTexture then sb.Background:SetColorTexture(0, 0, 0, 0) end
        if not own.back and bar.CreateTexture then
            own.back = bar:CreateTexture(nil, "BACKGROUND")
            own.back:SetColorTexture(0, 0, 0, 0.5)
        end
        if own.back then
            own.back:ClearAllPoints()
            own.back:SetPoint("TOPLEFT", sb, "TOPLEFT", 0, 0)
            own.back:SetPoint("BOTTOMRIGHT", sb, "BOTTOMRIGHT", 0, 0)
        end
    end
    -- the rested stretch is the fill's height (Forever's is a fixed 11px)
    local rest = bar.ExhaustionLevelFillBar
    if rest and rest.ClearAllPoints and sb then
        rest:ClearAllPoints()
        rest:SetPoint("TOPLEFT", sb, "TOPLEFT", 0, 0)
        rest:SetPoint("BOTTOMLEFT", sb, "BOTTOMLEFT", 0, 0)
    end
    local tick = bar.ExhaustionTick
    if tick and tick.SetNormalTexture and HasFile(EXHAUSTION_TICK) then
        tick:SetSize(32, 32)
        tick:SetNormalTexture(EXHAUSTION_TICK)
        tick:SetHighlightTexture(EXHAUSTION_TICK_HL, "ADD")
        for _, get in ipairs({"GetNormalTexture", "GetHighlightTexture"}) do
            local t = tick[get] and tick[get](tick)
            if t then t:ClearAllPoints(); t:SetAllPoints(tick) end
        end
    end
    if not own.hooked and hooksecurefunc then
        own.hooked = true
        -- Forever swaps in a coloured atlas fill for rested / normal XP...
        if type(bar.UpdateStatusBarTextures) == "function" then
            hooksecurefunc(bar, "UpdateStatusBarTextures", function(b, isRested)
                Own(b).rested = isRested and true or false
                if M.mode == "restyled" then ApplyFill(b) end
            end)
        end
        -- ...and one by standing for the reputation bar. That one it only
        -- queues (deferUntilNextLevel), then applies whenever the bar is
        -- next reset, so the fill is put back from both ends: here, when
        -- the standing is known, and below, when the atlas really lands.
        if IsReputationBar(bar) then
            hooksecurefunc(bar, "UpdateBarTextures", function(b, reaction, blue)
                local o = Own(b)
                if type(reaction) == "number" then o.reaction = reaction end
                o.blue = blue and true or false
                if M.mode == "restyled" then ApplyFill(b) end
            end)
        end
        if sb and type(sb.SetBarTexture) == "function" then
            hooksecurefunc(sb, "SetBarTexture", function(_, _, deferred)
                if M.mode == "restyled" and not deferred then ApplyFill(bar) end
            end)
        end
    end
    ApplyFill(bar)
end

-- Our frame art goes at the container's own level. That is over the fill
-- (Forever's bars are in the LOW strata) and under the bar's text and the
-- rested tick, which Forever puts one and two levels above the container:
-- two levels up, where the ledge used to be, it was drawn across the
-- text and the tick's head (a report's screenshots show both). Era draws
-- the same art on the container itself.
local function ArtLevel(f, container)
    if f and f.SetFrameLevel and container.GetFrameLevel then f:SetFrameLevel(container:GetFrameLevel()) end
end

-- the stone ledge over the bar in the top of the stone bar, on a child of
-- the container so it comes and goes (and fades) with it
local function Ledge(container)
    local own = Own(container)
    if own.ledge or not CreateFrame then return own.ledge end
    local f = CreateFrame("Frame", nil, container)
    f:SetAllPoints(container)
    ArtLevel(f, container)
    f.tiles = {}
    for i, c in ipairs(LEDGES) do
        local t = f:CreateTexture(nil, "OVERLAY")
        t:SetTexture(BAR_ART)
        t:SetTexCoord(0, 1, c[1], c[2])
        t:SetSize(256, 10)
        t:SetPoint("TOPLEFT", f, "TOPLEFT", (i - 1) * 256, 0)
        f.tiles[i] = t
    end
    own.ledge = f
    return f
end

-- the frame round the bar that stands on the stone bar: the reputation
-- watch bar's own art, five pieces end to end, as Era draws a status bar
-- that is not in the bar
local function WatchFrame(container)
    local own = Own(container)
    if own.watch or not CreateFrame or not HasFile(WATCH_ART) then return own.watch end
    local f = CreateFrame("Frame", nil, container)
    f:SetAllPoints(container)
    ArtLevel(f, container)
    f.tiles = {}
    local x = 0
    for i, c in ipairs(WATCH_TILES) do
        local t = f:CreateTexture(nil, "OVERLAY")
        t:SetTexture(WATCH_ART)
        t:SetTexCoord(c[2], c[3], c[4], c[5])
        t:SetSize(c[1], STATUS_H)
        t:SetPoint("LEFT", f, "LEFT", x, 0)
        x = x + c[1]
        f.tiles[i] = t
    end
    own.watch = f
    return f
end

-- Forever's twenty segment dividers along the bar (pooled frames holding a
-- BarDividerTexture); Era's bar had none
local function StatusDividers(container, alpha)
    if not container or not container.GetChildren then return end
    for _, child in ipairs({container:GetChildren()}) do
        if child.BarDividerTexture then FadeDivider(child, alpha) end
    end
end

-- the bar a container is showing, or nil
local function ShownBar(container)
    if not container or (container.IsShown and not container:IsShown()) then return nil end
    local bars = container.bars
    if type(bars) ~= "table" then return nil end
    local index = container.shownBarIndex
    local bar = index ~= nil and bars[index] or nil
    if bar == nil and index == nil then
        for _, b in pairs(bars) do
            if not b.IsShown or b:IsShown() then return b end
        end
    end
    return bar
end

-- Which container goes in the stone bar and which stands on it. Era's
-- experience bar is the one in the bar, with the reputation bar above it;
-- Forever's manager hands its first container the reputation bar instead
-- (its priorities put reputation over experience), so going by container
-- put the reputation bar in the experience bar's place and the experience
-- bar on top (a report). It goes by what each one is showing: the
-- experience bar takes the place in the bar, and a bar on its own does too
-- (Era's reputation bar dropped into it at the level cap).
local function StatusPlaces()
    local main = G("MainStatusTrackingBarContainer")
    local second = G("SecondaryStatusTrackingBarContainer")
    local mainBar, secondBar = ShownBar(main), ShownBar(second)
    local inBar, onTop = main, second
    if secondBar and (mainBar == nil or (secondBar.isExpBar and not mainBar.isExpBar)) then
        inBar, onTop = second, main
    end
    return inBar, onTop
end

-- The status containers are not protected (nothing protected hangs off
-- them: Blizzard anchors them to the main bar, not the reverse), so unlike
-- the action bars they can be put back mid-fight, after Blizzard's restack
-- has moved them 8 right and 4 or 6 up - a pet dying is enough. That is
-- done with the widget's own methods. The ones on the frame are Edit
-- Mode's wrappers, which keep books (what the frame is snapped to, a
-- dirty flag) that Blizzard's restack reads just before it moves the
-- protected bars; during a fight those stay exactly as Blizzard wrote
-- them. A container something protected does hang off (a bar the player
-- snapped to it in Edit Mode) waits for the fight to end like the rest.
local function FreeInCombat(frame)
    if not frame.IsProtected then return true end
    local ok, protected = pcall(frame.IsProtected, frame)
    return ok and not protected
end

local function AnchorInCombat(frame, point, rel, relPoint, x, y)
    local clear = frame.ClearAllPointsBase or frame.ClearAllPoints
    local set = frame.SetPointBase or frame.SetPoint
    local scale = (frame.GetScale and frame:GetScale()) or 1
    if not scale or scale <= 0 then scale = 1 end
    clear(frame)
    set(frame, point, rel, relPoint, (x or 0) / scale, (y or 0) / scale)
end

-- combat: places and fills only. The bar's size (the containers' scale)
-- and the bottom bars' rise wait for the fight to end.
local function LayoutStatusBars(art, combat)
    local inBar, onTop = StatusPlaces()
    local s = S()
    M.statusIn, M.statusTop = inBar, onTop
    local containers = {}
    if inBar then containers[#containers + 1] = inBar end
    if onTop then containers[#containers + 1] = onTop end
    for _, container in ipairs(containers) do
        local bars = type(container.bars) == "table" and container.bars or nil
        if container.SetPoint and (not combat or FreeInCombat(container)) then
            Hide(container.BarFrameTexture)
            StatusDividers(container, 0)
            local place = combat and AnchorInCombat or Anchor
            if not combat and container.SetScale then container:SetScale(s) end
            container:SetSize(BAR_W, STATUS_H)
            local ledge, watch = Ledge(container), WatchFrame(container)
            ArtLevel(ledge, container)
            ArtLevel(watch, container)
            if container == inBar then
                place(container, "TOP", art, "TOP", 0, 0)
            else
                place(container, "BOTTOM", art, "TOP", 0, STATUS_UP * s)
            end
            if ledge then ledge:SetShown(container == inBar) end
            if watch then watch:SetShown(container ~= inBar) end
            if bars then
                for _, bar in pairs(bars) do
                    if bar.SetAllPoints then bar:ClearAllPoints(); bar:SetAllPoints(container) end
                    SkinStatusBar(bar)
                end
            end
        elseif bars then
            -- held where it is: its fills alone (textures and colours)
            for _, bar in pairs(bars) do
                if M.own[bar] and M.own[bar].hooked then ApplyFill(bar) end
            end
        end
    end
end

--------------------------------------------------------------------------
-- the secure handler that holds the bottom bars in combat
--------------------------------------------------------------------------

-- the snippet: runs in the restricted environment with self = the handler.
-- "$parent" is the bar's parent, UIParent, so the anchors are the same as
-- ProtectedLayout's below. A bar the player moved in Edit Mode (not in its
-- default position) is left alone, as it is there.
local HOLD_SNIPPET = [=[
    local gap = self:GetAttribute("cui-gap") or 6
    local lift = self:GetAttribute("cui-lift") or 52
    local bl = self:GetFrameRef("cui-bl")
    if bl and self:GetAttribute("cui-bl") and bl:IsProtected() then
        bl:ClearAllPoints()
        bl:SetPoint("BOTTOMRIGHT", "$parent", "BOTTOM", -gap, lift)
    end
    local br = self:GetFrameRef("cui-br")
    if br and self:GetAttribute("cui-br") and br:IsProtected() then
        br:ClearAllPoints()
        br:SetPoint("BOTTOMLEFT", "$parent", "BOTTOM", gap, lift)
    end
]=]

-- the state changes after which Blizzard lays the bottom bars out again
local HOLD_STATES = {
    {"cuicombat", "[combat] 1; 0"},
    {"cuipet", "[pet] 1; 0"},
    {"cuiform", "[form:1] 1; [form:2] 2; [form:3] 3; [form:4] 4; [form:5] 5; [form:6] 6; 0"},
    {"cuivehicle", "[vehicleui] 1; [overridebar] 2; [possessbar] 3; 0"}
}

-- Forever's client builds no restricted snippets at all: the loader the
-- restricted environment compiles them with (loadstring_untainted) is
-- gone, so every state tick of a handler threw "attempt to call a nil
-- value" from RestrictedExecution.lua and placed nothing. Without the
-- loader there is no handler; the bars are laid out again after combat.
local function SnippetsAvailable()
    if type(loadstring_untainted) == "function" then return true end
    M.holdUnavailable = "this client has no restricted snippets (loadstring_untainted is missing)"
    return false
end

local function InstallHoldHandler()
    if M.holder or not CreateFrame or not RegisterStateDriver then return nil end
    if not SnippetsAvailable() then return nil end
    local ok, h = pcall(CreateFrame, "Frame", "ForeverClassicUIBarHolder", UIParent, "SecureHandlerStateTemplate")
    if not ok or not h or type(h.SetFrameRef) ~= "function" then return nil end
    for _, st in ipairs(HOLD_STATES) do
        h:SetAttribute("_onstate-" .. st[1], HOLD_SNIPPET)
    end
    M.holder = h
    for _, st in ipairs(HOLD_STATES) do
        pcall(RegisterStateDriver, h, st[1], st[2])
    end
    return h
end

-- out of combat only (attributes on a secure frame are locked in combat):
-- hands the handler the bars, the lift and which bars are still Blizzard's
-- to place
local function ArmHoldHandler(gap, lift, bl, br)
    local h = M.holder or InstallHoldHandler()
    if not h then return end
    h:SetAttribute("cui-gap", gap)
    h:SetAttribute("cui-lift", lift)
    if bl then
        h:SetFrameRef("cui-bl", bl)
        h:SetAttribute("cui-bl", (not bl.IsInDefaultPosition or bl:IsInDefaultPosition()) and true or false)
    end
    if br then
        h:SetFrameRef("cui-br", br)
        h:SetAttribute("cui-br", (not br.IsInDefaultPosition or br:IsInDefaultPosition()) and true or false)
    end
    M.holding = true
end

--------------------------------------------------------------------------
-- the whole layout
--------------------------------------------------------------------------

local function ProtectedLayout(art)
    -- action bars are protected: anchors and sizes only out of combat
    -- (the bars themselves are not scaled: their button containers are,
    -- so the offsets and sizes here are in the screen's units)
    local s = S()
    local main = G("MainActionBar")
    if main then
        main:ClearAllPoints()
        main:SetPoint("BOTTOMLEFT", art, "BOTTOMLEFT", MAIN_BAR_X * s, MAIN_BAR_Y * s)
    end
    for _, spec in ipairs(BARS) do
        local bar = G(spec.name)
        if bar and bar.SetSize then
            local count = M.counts[spec.name] or 12
            local w, h = BarSize(count, spec.horizontal)
            bar:SetSize(w * s, h * s)
        end
    end
    -- Era: the bottom bars either side of the screen centre, above the
    -- bar: 57 up over the status bar in it, 67 when a second stands on it
    local lift = BOTTOM_BAR_Y
    local top, inBar = M.statusTop, M.statusIn
    if top and top.IsShown and top:IsShown() then
        lift = lift + STATUS_LIFT_TWO
    elseif inBar and inBar.IsShown and inBar:IsShown() then
        lift = lift + STATUS_LIFT_ONE
    end
    lift = lift * s
    local gap = BOTTOM_BAR_X * s
    local bl, br = G("MultiBarBottomLeft"), G("MultiBarBottomRight")
    if bl and (not bl.IsInDefaultPosition or bl:IsInDefaultPosition()) then
        bl:ClearAllPoints()
        bl:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOM", -gap, lift)
    end
    if br and (not br.IsInDefaultPosition or br:IsInDefaultPosition()) then
        br:ClearAllPoints()
        br:SetPoint("BOTTOMLEFT", UIParent, "BOTTOM", gap, lift)
    end
    -- and the same anchors for the secure handler to put back mid-fight
    ArmHoldHandler(gap, lift, bl, br)
end

-- When Blizzard's layout moves a bar during a fight there is nothing to be
-- done about it there and then: a protected frame cannot be anchored from
-- addon code under lockdown, so the bar sits where Blizzard put it until
-- combat ends. What can be done is write down where that was. The Era bar
-- could then be lined up so Blizzard's own layout lands the buttons in the
-- right place and nothing needs to move mid-fight - but that needs the real
-- anchor from a real client, and nobody can type a command while fighting.
-- So it is captured here and carried in the report.
local COMBAT_WATCH = {"MainActionBar", "MultiBarBottomLeft", "MultiBarBottomRight"}

local function RecordCombatAnchors()
    M.combatAnchors = M.combatAnchors or {}
    for _, name in ipairs(COMBAT_WATCH) do
        local bar = G(name)
        if bar and bar.GetPoint then
            local ok, point, rel, relPoint, x, y = pcall(bar.GetPoint, bar, 1)
            if ok and point then
                local relName = rel
                if type(rel) == "table" and rel.GetName then relName = rel:GetName() end
                local fine, text = pcall(string.format, "%s>%s.%s %+.1f,%+.1f",
                                         tostring(point), tostring(relName),
                                         tostring(relPoint), tonumber(x) or 0, tonumber(y) or 0)
                M.combatAnchors[name] = fine and text or "<unreadable>"
            end
        end
    end
end

-- Blizzard lays the bars out again mid-fight (the pet bar hiding when the
-- pet dies, every bar's own combat handler), and our hooks run inside
-- that. Nearly everything on the bar is protected then: the action
-- buttons and their containers, the bag and micro buttons, the page
-- number on the main bar - and the stone art itself, since the main bar
-- is anchored to it (even Show() on it is refused, a report). So in
-- combat the pass is textures and alpha only: button art, faded
-- dividers, the status bars' fills. Everything with a size, anchor,
-- scale or level waits, and the regen waiter runs the full pass the
-- moment the fight ends. The one exception is the two status bar
-- containers, which are not protected: they are put back in their
-- places (see LayoutStatusBars).
function M.Layout()
    local art = BuildArt()
    if not art then return false end
    M.inLayout = true
    local combat = InCombat()
    if not combat then
        -- the bar size: the art, and through S() everything laid out on it
        M.scale = M.WantedScale()
        if art.SetScale then art:SetScale(M.scale) end
        if not (art.IsShown and art:IsShown()) then art:Show() end
    end
    local main = G("MainActionBar")
    if main then
        Hide(main.BorderArt)
        if art.leftCap then Fade(main.EndCaps) end
    end
    M.counts = {}
    for _, spec in ipairs(BARS) do
        local bar = G(spec.name)
        if bar then M.counts[spec.name] = LayoutBar(bar, spec.horizontal, combat) end
    end
    M.HideDividers()
    if combat then
        M.pending = true
        RecordCombatAnchors()
        LayoutStatusBars(art, true)
    else
        M.pending = nil
        LayoutPageNumber(art)
        -- the micro buttons and the bags share one run of bar: count the
        -- buttons, settle who gets how much, then lay both out
        local row = MicroRow()
        local plan = PlanRow(#row)
        M.plan = plan
        LayoutBags(art, plan)
        LayoutStatusBars(art)
        LayoutMicroMenu(art, row, plan)
        ProtectedLayout(art)
    end
    M.inLayout = nil
    return true
end

-- Forever draws retail divider strips between the buttons over the bar art
-- (pooled frames laid out by MainActionBarMixin:UpdateDividers), between
-- the bag slots and along the experience bar. Fade them out after every
-- refresh; Blizzard shows them, alpha 0 keeps them unseen.
function M.HideDividers(alpha)
    alpha = alpha or 0
    local bar = G("MainActionBar")
    if bar then
        for _, key in ipairs({"HorizontalDividersPool", "VerticalDividersPool"}) do
            local pool = bar[key]
            if pool and pool.EnumerateActive then
                for divider in pool:EnumerateActive() do
                    if divider.SetAlpha then divider:SetAlpha(alpha) end
                end
            end
        end
    end
    BagDividers(G("BagsBar"), alpha)
    StatusDividers(G("MainStatusTrackingBarContainer"), alpha)
    StatusDividers(G("SecondaryStatusTrackingBarContainer"), alpha)
end

--------------------------------------------------------------------------
-- keep it classic when Blizzard re-lays out
--------------------------------------------------------------------------

-- Our hooks run inside Blizzard's own calls - Edit Mode applies a layout
-- under a pcall and asserts on any failure, so an error of ours there
-- surfaced as "EditMode: Error updating layout info" with the real
-- message swallowed, and left Edit Mode half applied. Errors stay ours:
-- caught here, recorded for the report, never handed up.
local function Again()
    if M.mode ~= "restyled" or M.inLayout then return end
    local ok, err = pcall(M.Layout)
    if not ok then
        M.inLayout = nil
        ns.errors[#ns.errors + 1] = "actionbars layout: " .. tostring(err)
    end
end

local function HookMethod(frame, method)
    if frame and type(frame[method]) == "function" then hooksecurefunc(frame, method, Again) end
end

local function InstallHooks()
    if M.hooked or not hooksecurefunc then return end
    M.hooked = true
    local em = G("EditModeManagerFrame")
    HookMethod(em, "ExitEditMode")
    HookMethod(em, "UpdateBottomActionBarPositions")
    HookMethod(em, "UpdateRightActionBarPositions")
    for _, spec in ipairs(BARS) do
        local bar = G(spec.name)
        HookMethod(bar, "UpdateGridLayout")
        HookMethod(bar, "UpdateSystemSettingIconSize")
        HookMethod(bar, "UpdateSystemSettingIconPadding")
        HookMethod(bar, "ApplySystemAnchor")
    end
    local main = G("MainActionBar")
    if main and type(main.UpdateDividers) == "function" then
        hooksecurefunc(main, "UpdateDividers", function() if M.mode == "restyled" then M.HideDividers() end end)
    end
    HookMethod(main, "UpdateEndCaps")
    HookMethod(G("MicroMenuContainer"), "ApplySystemAnchor")
    HookMethod(G("MicroMenuContainer"), "UpdateSystemSetting")
    HookMethod(G("MicroMenuContainer"), "Layout")
    HookMethod(G("MicroMenu"), "Layout")
    -- Blizzard shows the Store button again from here
    if type(UpdateMicroButtons) == "function" then hooksecurefunc("UpdateMicroButtons", Again) end
    HookMethod(G("BagsBar"), "ApplySystemAnchor")
    HookMethod(G("BagsBar"), "Layout")
    -- Blizzard lays the bag bar out again whenever an item is lifted or
    -- dropped (the bag manager's "expand" state follows the cursor), and
    -- does it through a callback holding the Layout function it had at
    -- load: the hook above never sees that call. The manager's own method
    -- is what runs it, so that is hooked too.
    HookMethod(G("MainMenuBarBagManager"), "OnExpandBarChanged")
    for _, name in ipairs({"MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer"}) do
        HookMethod(G(name), "ApplySystemAnchor")
        HookMethod(G(name), "UpdateSystemSetting")
        HookMethod(G(name), "Layout")
        -- a container changes the bar it shows at the end of its fade,
        -- not when the manager decides: the bars swap places then
        HookMethod(G(name), "ApplyPendingBarToShow")
        HookMethod(G(name), "UpdateShownState")
    end
    HookMethod(G("StatusTrackingBarManager"), "UpdateBarVisuals")
    HookMethod(G("StatusTrackingBarManager"), "UpdateBarsShown")
end

local function InstallCombatWaiter()
    if M.waiter or not CreateFrame then return end
    M.waiter = CreateFrame("Frame")
    M.waiter:RegisterEvent("PLAYER_REGEN_ENABLED")
    -- a bag put in or taken out of a bag slot: the reagent bag's slot
    -- comes and goes with its bag. Whichever of the bag events says so,
    -- only a change of that answer lays the bar out again (the delayed
    -- one fires on every loot).
    for _, event in ipairs({"BAG_CONTAINER_UPDATE", "BAG_UPDATE_DELAYED"}) do
        pcall(M.waiter.RegisterEvent, M.waiter, event)
    end
    M.waiter:SetScript("OnEvent", function(_, event)
        if M.mode ~= "restyled" then return end
        if event == "PLAYER_REGEN_ENABLED" then
            if M.pending then M.Layout() end
        elseif G(REAGENT_BUTTON) and ReagentBagEquipped() ~= M.reagentKnown then
            if InCombat() then M.pending = true else Again() end
        end
    end)
end

--------------------------------------------------------------------------
-- module interface
--------------------------------------------------------------------------

local function IsNative()
    return MainMenuBarArtFrame ~= nil and MainActionBar == nil
end

function M:Enable()
    if IsNative() then
        M.mode = "native"
        return
    end
    local main = G("MainActionBar")
    if not main or type(main.actionButtons) ~= "table" then
        M.mode = "unavailable"
        return
    end
    InstallCombatWaiter()
    if M.Layout() then
        M.mode = "restyled"
        InstallHooks()
    else
        M.mode = "unavailable"
    end
end

function M:Force()
    M.mode = "off"
    M:Enable()
    ns.Print("action bars: classic bottom bar %s.", M.mode)
end

function M:Disable()
    if M.art then M.art:Hide() end
    M.HideDividers(1)
    M.mode = "off"
    -- a reagent bag slot this addon took off the bar goes back on it
    if not InCombat() then
        Unstow(G(REAGENT_BUTTON))
        M.reagentStowed = nil
    end
    -- the handler stops placing the bars (an attribute write on a secure
    -- frame is refused in combat; then it stops at the next chance)
    if M.holder and not InCombat() then
        pcall(M.holder.SetAttribute, M.holder, "cui-bl", false)
        pcall(M.holder.SetAttribute, M.holder, "cui-br", false)
        M.holding = nil
    end
    ns.Print("action bars: type /reload to restore Blizzard's bars.")
end

-- /cui barsize <percent> (and the options slider): the bottom bar's size.
-- 100 is Era's own; a value up to 3 is read as a factor (1.25 = 125).
-- Returns the percentage saved, or nil when the value is not a number.
function M.SetSize(value)
    local pct = tonumber(value)
    if not pct or pct ~= pct or pct <= 0 then return nil end
    if pct <= 3 then pct = pct * 100 end
    pct = math.floor(math.max(SCALE_MIN * 100, math.min(SCALE_MAX * 100, pct)) + 0.5)
    if ns.db then
        ns.db.barscale = pct
        if ns.SaveFallback then ns.SaveFallback() end
    end
    if M.mode == "restyled" then
        if InCombat() then M.pending = true else Again() end
    end
    return pct
end

-- /cui actionbars size <percent>
function M:Command(arg)
    local what, value = tostring(arg or ""):match("^(%S+)%s*(.-)$")
    if what ~= "size" and what ~= "scale" then return false end
    value = ((value or ""):gsub("%%", "")):gsub(",", ".")
    if value == "" then
        ns.Print("bottom bar size: %d%%. Era's own size is 100; /cui barsize <%d-%d> changes it.",
                 tonumber(ns.db and ns.db.barscale) or 100, SCALE_MIN * 100, SCALE_MAX * 100)
        return true
    end
    local pct = M.SetSize(value)
    if not pct then
        ns.Print("bottom bar size: give a percentage from %d to %d, for example /cui barsize 125.", SCALE_MIN * 100, SCALE_MAX * 100)
        return true
    end
    local fits = math.floor(M.WantedScale() * 100 + 0.5)
    local note = ""
    if fits < pct then note = (" This screen has room for %d%%, so that is what is drawn."):format(fits) end
    if M.mode ~= "restyled" then
        note = note .. " It applies while the classic bottom bar is on."
    elseif InCombat() then
        note = note .. " It changes when combat ends."
    end
    ns.Print("bottom bar size %d%%.%s", pct, note)
    if ns.optionsPanel and ns.optionsPanel.Refresh then ns.optionsPanel.Refresh() end
    return true
end

function M:Status()
    if M.mode == "native" then return "(client already draws the classic bar)" end
    if M.mode == "restyled" then
        local s = "(Era bottom bar: stone art, 36px buttons, page arrows, micro buttons and bags on the bar, XP bar in the bar"
        if M.scale and math.abs(M.scale - 1) > 0.001 then s = s .. ("; bar size %d%%"):format(M.scale * 100 + 0.5) end
        if M.microShown then
            s = s .. ("; %d micro buttons"):format(M.microShown)
            if M.microStride and M.microStride < MICRO_STRIDE then
                local tenths = math.floor(M.microStride * 10 + 0.5)
                s = s .. ((tenths % 10 == 0) and " %dpx apart" or " %.1fpx apart"):format(tenths / 10)
            end
            if M.microScale and M.microScale < 1 then s = s .. (" at %d%%"):format(M.microScale * 100 + 0.5) end
            if (M.microStride and M.microStride < MICRO_STRIDE) or (M.microScale and M.microScale < 1) then s = s .. " to fill the room before the bags" end
            -- what the bag side gave up for them
            if M.reagentStowed then s = s .. "; empty reagent bag slot off the bar" end
            if M.bagPad and M.bagPad < BAG_PAD then s = s .. ("; bag slots %dpx apart"):format(M.bagPad) end
            if M.bagSize and M.bagSize < BAG_SIZE then s = s .. ("; bag slots at %dpx"):format(M.bagSize) end
        end
        local top = M.statusTop
        if top and top.IsShown and top:IsShown() then
            s = s .. "; a second status bar stands on the bar"
            if top == G("MainStatusTrackingBarContainer") then s = s .. " (Forever's first container: its experience bar is in the second)" end
        end
        if M.pending then s = s .. "; bar anchors wait for combat to end" end
        if M.holding then s = s .. "; a secure handler holds the bottom bars in combat" end
        if M.holdUnavailable then s = s .. "; the bottom bars are laid out again after combat (" .. M.holdUnavailable .. ")" end
        -- carried into the report: where Blizzard put the bars mid-fight
        if M.combatAnchors then
            local seen = {}
            for _, name in ipairs(COMBAT_WATCH) do
                if M.combatAnchors[name] then
                    seen[#seen + 1] = name .. "=" .. M.combatAnchors[name]
                end
            end
            if #seen > 0 then s = s .. "; moved in combat to " .. table.concat(seen, ", ") end
        end
        return s .. ")"
    end
    if M.mode == "unavailable" then return "(unavailable on this client)" end
    return ""
end

ns.RegisterModule("actionbars", M)
