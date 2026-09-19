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
-- Era's own stride is as close as the 29px art goes: it interlocks by 3px
-- and no more. Packing tighter than this buries each button's right edge
-- under the next one, which is what made the character button look gone,
-- so when the row will not fit it is scaled down instead of squeezed.
local MICRO_MIN_STRIDE = MICRO_STRIDE
local XP_H, XP_TOP_H = 13, 8
local BOTTOM_BAR_X, BOTTOM_BAR_Y = 6, 52
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
        art.leftCap = art:CreateTexture(nil, "OVERLAY", nil, 5)
        art.leftCap:SetTexture(END_CAP)
        art.leftCap:SetSize(128, 128)
        art.leftCap:SetPoint("BOTTOM", art, "BOTTOM", -544, 0)
        art.rightCap = art:CreateTexture(nil, "OVERLAY", nil, 5)
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
-- buttons stay packed the way Era packs them
local function LayoutBar(bar, horizontal)
    if not bar or type(bar.actionButtons) ~= "table" then return 0 end
    local shown = 0
    for _, btn in ipairs(bar.actionButtons) do
        SkinButton(btn)
        local c = btn.container
        if c and c.SetPoint then
            if c.SetScale then c:SetScale(BUTTON_SCALE) end
            if not c.IsShown or c:IsShown() then
                if horizontal then
                    Anchor(c, "BOTTOMLEFT", bar, "BOTTOMLEFT", shown * STRIDE, 0)
                else
                    Anchor(c, "TOPLEFT", bar, "TOPLEFT", 0, -shown * STRIDE)
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
    pn:SetSize(42, 36)
    pn:ClearAllPoints()
    pn:SetPoint("BOTTOMLEFT", art, "BOTTOMLEFT", PAGE_X, PAGE_Y)
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
end

local function SkinMicroButton(btn, name)
    if not btn or not btn.SetNormalTexture then return false end
    local up, down, disabled = MicroFiles(name)
    if not HasFile(up) then return false end
    local own = Own(btn)
    M.inSkin = true
    -- 31 wide: the menu lays its children out with a -5 overlap, so 31
    -- gives Era's 26px stride; the 29px art is centred in it
    btn:SetSize(MICRO_W + 2, MICRO_H)
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

-- Era: 552 + 26 per button. Forever has more buttons than Era's nine (and
-- the keyring and reagent bag to the right), so the row always spans the
-- room between the page arrows and the bag cluster: at Era's stride when
-- that fits, and is scaled down when it does not: never packed closer,
-- because at Era's stride the art already interlocks as far as it goes.
local function LayoutMicroMenu(art)
    local container = G("MicroMenuContainer")
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
    -- only the menu's own children count: Forever keeps a few more micro
    -- buttons as globals parked elsewhere (shown, but not in the row)
    local skinned, row = 0, {}
    for _, gname in ipairs(MICRO_ORDER) do
        local btn = G(gname)
        if btn and SkinMicroButton(btn, MICRO_ART[gname]) then
            skinned = skinned + 1
            local inMenu = menu == nil or (btn.GetParent and btn:GetParent() == menu)
            if inMenu and (not btn.IsShown or btn:IsShown()) then row[#row + 1] = btn end
        end
    end
    local shown = #row
    M.microSkinned = skinned
    M.microShown = shown
    local room = BAR_W + BAGS_X - (M.bagsWidth or 0) - SMALL_PAD - MICRO_X
    local stride = MICRO_STRIDE
    local function Width(s) return math.max(shown - 1, 0) * s + MICRO_W + 2 end
    local natural, scale = Width(stride), 1
    if natural > room and room > 0 then
        if shown > 1 then stride = math.max(MICRO_MIN_STRIDE, (room - MICRO_W - 2) / (shown - 1)) end
        natural = Width(stride)
        if natural > room then scale = room / natural end
    end
    M.microStride, M.microScale = stride, scale
    for i, btn in ipairs(row) do
        if menu and btn.SetPoint then Anchor(btn, "BOTTOMLEFT", menu, "BOTTOMLEFT", (i - 1) * stride, 0) end
    end
    if menu and menu.SetSize then
        menu:SetSize(natural, MICRO_H)
        if menu.SetScale then menu:SetScale(scale) end
        if container then
            menu:ClearAllPoints()
            menu:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", 0, 0)
        end
    end
    if container and container.SetPoint then
        container:SetSize(natural * scale, MICRO_H * scale)
        container:ClearAllPoints()
        container:SetPoint("BOTTOMLEFT", art, "BOTTOMLEFT", MICRO_X, MICRO_Y)
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
    btn:SetSize(size, size)
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
    btn:SetSize(KEYRING_W, KEYRING_H)
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

local function LayoutBags(art)
    local bar = G("BagsBar")
    if not bar or not bar.SetPoint then return end
    bar:ClearAllPoints()
    bar:SetPoint("BOTTOMRIGHT", art, "BOTTOMRIGHT", BAGS_X, BAGS_Y)
    Hide(bar.BorderArt)
    BagDividers(bar, 0)
    local prev, width = nil, 0
    for _, gname in ipairs(BAG_BUTTONS) do
        local btn = G(gname)
        if btn then
            SkinBagButton(btn, BAG_SIZE)
            btn:ClearAllPoints()
            if prev then
                btn:SetPoint("RIGHT", prev, "LEFT", -BAG_PAD, 0)
                width = width + BAG_PAD + BAG_SIZE
            else
                btn:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
                width = BAG_SIZE
            end
            prev = btn
        end
    end
    local reagent = G(REAGENT_BUTTON)
    if reagent and reagent.SetPoint and prev then
        SkinBagButton(reagent, REAGENT_SIZE)
        reagent:ClearAllPoints()
        reagent:SetPoint("RIGHT", prev, "LEFT", -SMALL_PAD, 0)
        width = width + SMALL_PAD + REAGENT_SIZE
        prev = reagent
    end
    local keyring = G(KEYRING_BUTTON)
    if keyring and keyring.SetPoint and prev and SkinKeyRing(keyring) then
        keyring:ClearAllPoints()
        keyring:SetPoint("RIGHT", prev, "LEFT", -SMALL_PAD, 0)
        local w = keyring.GetWidth and keyring:GetWidth() or KEYRING_W
        width = width + SMALL_PAD + w
        prev = keyring
    end
    Hide(G("BagBarExpandToggle"))
    M.bagsWidth = width
    bar:SetSize(width, BAG_SIZE)
end

--------------------------------------------------------------------------
-- experience / reputation bar in the top of the stone bar
--------------------------------------------------------------------------

local function SkinStatusBar(bar)
    if not bar then return end
    local sb = bar.StatusBar
    if sb then
        sb:ClearAllPoints()
        sb:SetAllPoints(bar)
        if sb.SetStatusBarTexture then sb:SetStatusBarTexture(STATUS_BAR) end
        if sb.Background and sb.Background.SetColorTexture then sb.Background:SetColorTexture(0, 0, 0, 0.5) end
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
    local own = Own(bar)
    if not own.hooked and hooksecurefunc then
        own.hooked = true
        -- Forever swaps in a coloured atlas fill for rested / normal XP
        if type(bar.UpdateStatusBarTextures) == "function" then
            hooksecurefunc(bar, "UpdateStatusBarTextures", function(b, isRested)
                if M.mode ~= "restyled" or not b.StatusBar then return end
                if b.StatusBar.SetStatusBarTexture then b.StatusBar:SetStatusBarTexture(STATUS_BAR) end
                if b.isExpBar and b.StatusBar.SetStatusBarColor then
                    if isRested then b.StatusBar:SetStatusBarColor(0, 0.39, 0.88, 1)
                    else b.StatusBar:SetStatusBarColor(0.58, 0, 0.55, 1) end
                end
            end)
        end
    end
end

-- the stone ledge over the bar, on a child of the container so it comes
-- and goes (and fades) with it
local function Ledge(container)
    local own = Own(container)
    if own.ledge or not CreateFrame then return end
    local f = CreateFrame("Frame", nil, container)
    f:SetAllPoints(container)
    if f.SetFrameLevel and container.GetFrameLevel then f:SetFrameLevel(container:GetFrameLevel() + 2) end
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
end

-- Forever's twenty segment dividers along the bar (pooled frames holding a
-- BarDividerTexture); Era's bar had none
local function StatusDividers(container, alpha)
    if not container or not container.GetChildren then return end
    for _, child in ipairs({container:GetChildren()}) do
        if child.BarDividerTexture then FadeDivider(child, alpha) end
    end
end

local function LayoutStatusBars(art)
    local main = G("MainStatusTrackingBarContainer")
    local second = G("SecondaryStatusTrackingBarContainer")
    for _, container in ipairs({main, second}) do
        if container and container.SetPoint then
            Hide(container.BarFrameTexture)
            StatusDividers(container, 0)
            if container == main then
                container:SetSize(BAR_W, XP_H)
                container:ClearAllPoints()
                container:SetPoint("TOP", art, "TOP", 0, 0)
                Ledge(container)
            else
                container:SetSize(BAR_W, XP_TOP_H)
                container:ClearAllPoints()
                container:SetPoint("BOTTOM", art, "TOP", 0, -3)
            end
            if type(container.bars) == "table" then
                for _, bar in pairs(container.bars) do
                    if bar.SetAllPoints then bar:ClearAllPoints(); bar:SetAllPoints(container) end
                    SkinStatusBar(bar)
                end
            end
        end
    end
end

--------------------------------------------------------------------------
-- the whole layout
--------------------------------------------------------------------------

local function ProtectedLayout(art)
    -- action bars are protected: anchors and sizes only out of combat
    local main = G("MainActionBar")
    if main then
        main:ClearAllPoints()
        main:SetPoint("BOTTOMLEFT", art, "BOTTOMLEFT", MAIN_BAR_X, MAIN_BAR_Y)
    end
    for _, spec in ipairs(BARS) do
        local bar = G(spec.name)
        if bar and bar.SetSize then
            local count = M.counts[spec.name] or 12
            bar:SetSize(BarSize(count, spec.horizontal))
        end
    end
    -- Era: the bottom bars either side of the screen centre, above the bar
    local lift = BOTTOM_BAR_Y
    local second = G("SecondaryStatusTrackingBarContainer")
    if second and second.IsShown and second:IsShown() then lift = lift + 9 end
    local bl, br = G("MultiBarBottomLeft"), G("MultiBarBottomRight")
    if bl and (not bl.IsInDefaultPosition or bl:IsInDefaultPosition()) then
        bl:ClearAllPoints()
        bl:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOM", -BOTTOM_BAR_X, lift)
    end
    if br and (not br.IsInDefaultPosition or br:IsInDefaultPosition()) then
        br:ClearAllPoints()
        br:SetPoint("BOTTOMLEFT", UIParent, "BOTTOM", BOTTOM_BAR_X, lift)
    end
end

function M.Layout()
    local art = BuildArt()
    if not art then return false end
    M.inLayout = true
    art:Show()
    local main = G("MainActionBar")
    if main then
        Hide(main.BorderArt)
        if art.leftCap then Fade(main.EndCaps) end
    end
    M.counts = {}
    for _, spec in ipairs(BARS) do
        local bar = G(spec.name)
        if bar then M.counts[spec.name] = LayoutBar(bar, spec.horizontal) end
    end
    M.HideDividers()
    LayoutPageNumber(art)
    LayoutBags(art)        -- first: the micro menu is scaled to the room left of the bags
    LayoutMicroMenu(art)
    LayoutStatusBars(art)
    if InCombat() then
        M.pending = true
    else
        M.pending = nil
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

local function Again()
    if M.mode == "restyled" and not M.inLayout then M.Layout() end
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
    for _, name in ipairs({"MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer"}) do
        HookMethod(G(name), "ApplySystemAnchor")
        HookMethod(G(name), "UpdateSystemSetting")
        HookMethod(G(name), "Layout")
    end
    HookMethod(G("StatusTrackingBarManager"), "UpdateBarVisuals")
    HookMethod(G("StatusTrackingBarManager"), "UpdateBarsShown")
end

local function InstallCombatWaiter()
    if M.waiter or not CreateFrame then return end
    M.waiter = CreateFrame("Frame")
    M.waiter:RegisterEvent("PLAYER_REGEN_ENABLED")
    M.waiter:SetScript("OnEvent", function()
        if M.mode == "restyled" and M.pending then M.Layout() end
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
    ns.Print("action bars: type /reload to restore Blizzard's bars.")
end

function M:Status()
    if M.mode == "native" then return "(client already draws the classic bar)" end
    if M.mode == "restyled" then
        local s = "(Era bottom bar: stone art, 36px buttons, page arrows, micro buttons and bags on the bar, XP bar in the bar"
        if M.microShown then
            s = s .. ("; %d micro buttons"):format(M.microShown)
            if M.microStride and M.microStride < MICRO_STRIDE then s = s .. (" %dpx apart"):format(M.microStride + 0.5) end
            if M.microScale and M.microScale < 1 then s = s .. (" at %d%%"):format(M.microScale * 100 + 0.5) end
            if (M.microStride and M.microStride < MICRO_STRIDE) or (M.microScale and M.microScale < 1) then s = s .. " to fill the room before the bags" end
        end
        if M.pending then s = s .. "; bar anchors wait for combat to end" end
        return s .. ")"
    end
    if M.mode == "unavailable" then return "(unavailable on this client)" end
    return ""
end

ns.RegisterModule("actionbars", M)
