-- Forever Classic UI - player / target / focus / pet frames
--
-- Forever's unit frames are the retail (Dragonflight) layout: portrait in a
-- rounded frame atlas, wide health bar, mana strip, level in a small circle.
-- Classic drew both frames from one texture (UI-TargetingFrame, mirrored for
-- the player), a 119x12 health bar with a 119x12 mana bar under it, the
-- level in the frame's corner, and elite/rare variants of the target art.
--
-- The retail frame structure is kept (Blizzard's code keeps driving values
-- and events); only art, sizes, anchors and draw order are moved to the
-- classic ones. Every number here comes from a `/cui report all` taken on
-- Classic Era 1.15.9. Classic clients already draw this and are left alone.
--
-- Draw order is the part retail got backwards for this art: Classic draws
-- the frame texture *over* the bars (the bevel around each bar is part of
-- the art, the bar ends vanish under it) and the level text and the
-- health / mana numbers over the art. Forever draws the art on the
-- *Container child under the bars, and the bar frames are locked to their
-- parent's frame level (useParentLevel), so they cannot be moved down.
-- Instead the classic art goes on a "skin" frame of ours at the bars' own
-- frame level, on the BORDER layer: the bar fills are on BACKGROUND (the
-- health bars are already, the mana bars are put there), so the art draws
-- over them, and the bars' text is on OVERLAY, so it draws over the art -
-- as Classic did. A copy of the level text lives on the skin too (the art
-- is opaque where the level sits; the name area is transparent so
-- Blizzard's name shows through), and the contextual icons (combat, skull,
-- raid marks, auras) are raised above everything.
--
-- The bars are anchored by both corners to the unit frame itself, never
-- to Blizzard's bars container: Blizzard resizes and re-anchors that
-- container on every target change (also in combat, when the protected
-- bars cannot be laid out again), and a bar hanging off its corner
-- would start a few pixels left of the art's recess until combat ended.
--
-- Rule (Forever wraps unit health in secret values): no Lua field writes
-- into Blizzard's frames, no calls into Blizzard's unit frame functions.
-- Widget calls and hooksecurefunc only. Anything of ours that hangs off a
-- Blizzard frame is kept in M.own, keyed by the frame.

local addonName, ns = ...

local M = {mode = "off"}

local TF = "Interface\\TargetingFrame\\"
local CF = "Interface\\CharacterFrame\\"
local FRAME_TEX = TF .. "UI-TargetingFrame"
local BAR_TEX = TF .. "UI-StatusBar"
local FLASH_TEX = TF .. "UI-TargetingFrame-Flash"
local LEVEL_BG_TEX = TF .. "UI-TargetingFrame-LevelBackground"
local SKULL_TEX = TF .. "UI-TargetingFrame-Skull"
local PET_TEX = TF .. "UI-SmallTargetingFrame"
local PET_FLASH_TEX = TF .. "UI-PartyFrame-Flash"
local PET_ATTACK_TEX = TF .. "UI-Player-AttackStatus"
local STATUS_TEX = CF .. "UI-Player-Status"
local STATE_ICON_TEX = CF .. "UI-StateIcon"
local WHITE = "Interface\\Buttons\\WHITE8x8"
local TARGET_ART = {
    normal = FRAME_TEX,
    minus = TF .. "UI-TargetingFrame-Minus",
    elite = TF .. "UI-TargetingFrame-Elite",
    rareelite = TF .. "UI-TargetingFrame-Rare-Elite",
    rare = TF .. "UI-TargetingFrame-Rare"
}

-- our own textures / frames hung on Blizzard frames, keyed by that frame
M.own = setmetatable({}, {__mode = "k"})
local function Own(frame)
    local t = M.own[frame]
    if not t then
        t = {}
        M.own[frame] = t
    end
    return t
end

local function InCombat()
    return InCombatLockdown and InCombatLockdown()
end

local function SetFile(tex, path, l, r, t, b)
    if not tex then return end
    if tex.SetTexture then tex:SetTexture(path) end
    if tex.SetTexCoord then
        if l then tex:SetTexCoord(l, r, t, b) else tex:SetTexCoord(0, 1, 0, 1) end
    end
end

-- regions: hidden and transparent (Blizzard may Show() it again, alpha stays)
local function Hide(region)
    if region then
        if region.Hide then region:Hide() end
        if region.SetAlpha then region:SetAlpha(0) end
    end
end

-- frames under a unit frame are protected: only alpha, never Hide()
local function Fade(frame)
    if frame and frame.SetAlpha then frame:SetAlpha(0) end
end

-- Retail clips the bars with MaskTextures (attached at load and re-attached
-- by Blizzard's art swaps). A mask cannot be detached from everything it
-- clips without writing into Blizzard's tables, so instead it is turned
-- into a plain white square over the bar: white means "show", and the
-- mask's clamp-to-black wrap keeps it from revealing anything outside.
local function Unmask(bar, mask)
    local tex = bar and bar.GetStatusBarTexture and bar:GetStatusBarTexture()
    if tex and mask and tex.RemoveMaskTexture then
        pcall(tex.RemoveMaskTexture, tex, mask)
    end
    if not mask then return end
    if mask.SetTexture then pcall(mask.SetTexture, mask, WHITE) end
    if mask.ClearAllPoints and mask.SetPoint then
        mask:ClearAllPoints()
        mask:SetPoint("TOPLEFT", bar, "TOPLEFT", -4, 4)
        mask:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 4, -4)
    end
    if mask.Show then mask:Show() end
end

-- Portraits stay round: the classic art is transparent at the portrait's
-- corners (Classic's own portrait renders were round). The plain circle
-- mask, the full size of the portrait, fills the art's ring edge to edge;
-- Forever's player-specific mask is smaller and left a dark gap.
local function RoundPortrait(mask, portrait)
    if not mask or not portrait then return end
    if mask.SetAtlas then pcall(mask.SetAtlas, mask, "CircleMask") end
    if mask.ClearAllPoints and mask.SetPoint then
        mask:ClearAllPoints()
        mask:SetPoint("TOPLEFT", portrait, "TOPLEFT", 0, 0)
        mask:SetPoint("BOTTOMRIGHT", portrait, "BOTTOMRIGHT", 0, 0)
    end
    if mask.Show then mask:Show() end
end

-- Era's bars: 119x12, both corners on the unit frame (x, y is the top
-- corner named; the other corner follows from the size)
local BAR_W, BAR_H = 119, 12
local function Corners(bar, frame, corner, x, y)
    bar:ClearAllPoints()
    bar:SetSize(BAR_W, BAR_H)
    if corner == "TOPRIGHT" then
        bar:SetPoint("TOPLEFT", frame, "TOPRIGHT", x, y)
        bar:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", x + BAR_W, y - BAR_H)
    else
        bar:SetPoint("TOPLEFT", frame, "TOPLEFT", x, y)
        bar:SetPoint("BOTTOMRIGHT", frame, "TOPLEFT", x + BAR_W, y - BAR_H)
    end
end

-- The health numbers live on Blizzard's bars container, not on the bar:
-- anchored to the bar instead (regions may move any time), so they stay
-- over it however Blizzard resizes the container in combat
local BAR_TEXT = {HealthBarText = {"CENTER", 0}, LeftText = {"LEFT", 2}, RightText = {"RIGHT", -2}}
local function BarText(hc, hb)
    if not hc or not hb then return end
    for key, where in pairs(BAR_TEXT) do
        local text = hc[key]
        if text and text.ClearAllPoints and text.SetPoint then
            text:ClearAllPoints()
            text:SetPoint(where[1], hb, where[1], where[2], 0)
        end
    end
end

-- Era's name box: the whole transparent strip of the art, 116 of the
-- strip's 119 (Forever's names run longer than Era's)
local NAME_WIDTH = 116

-- black 50% box behind the bars, like PlayerFrameBackground /
-- TargetFrameBackground: on the unit frame itself so it sits under the bars
local function Backdrop(frame, point, x, y, height)
    local own = Own(frame)
    local tex = own.backdrop
    if not tex then
        tex = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
        tex:SetColorTexture(0, 0, 0, 0.5)
        own.backdrop = tex
    end
    tex:SetSize(119, height)
    tex:ClearAllPoints()
    tex:SetPoint(point, frame, point, x, y)
    return tex
end

-- The skin frame: ours, at the bars' frame level (they are locked to the
-- *ContentMain child's level), carrying the classic art on BORDER - over
-- the bar fills on BACKGROUND, under the bars' OVERLAY text - and a copy
-- of the level text. Re-levelled on every restyle in case Blizzard moved.
local function Skin(frame, main)
    local own = Own(frame)
    local skin = own.skin
    if not skin then
        if not CreateFrame then return end
        skin = CreateFrame("Frame", nil, frame)
        skin:SetAllPoints(frame)
        skin.art = skin:CreateTexture(nil, "BORDER")
        skin.glow = skin:CreateTexture(nil, "ARTWORK")
        skin.glow:SetAlpha(0)
        skin.levelText = skin:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        -- a fixed, centred box: an auto-sized string came out a couple of
        -- pixels left of the art's circle on Forever. The box is taller
        -- than the line so MIDDLE centring has no rounding to do.
        skin.levelText:SetSize(40, 14)
        if skin.levelText.SetJustifyH then skin.levelText:SetJustifyH("CENTER") end
        if skin.levelText.SetJustifyV then skin.levelText:SetJustifyV("MIDDLE") end
        own.skin = skin
    end
    if skin.SetFrameLevel and main and main.GetFrameLevel then
        skin:SetFrameLevel(main:GetFrameLevel())
    end
    return skin
end

-- the classic fill on a bar, under the art: the health bars' fill is on
-- BACKGROUND already (Forever's XML), the mana bars' is on ARTWORK and
-- would draw over the art's bevel at the same frame level
local function ClassicFill(bar)
    if not bar then return end
    bar:SetStatusBarTexture(BAR_TEX)
    local tex = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
    if tex and tex.SetDrawLayer then tex:SetDrawLayer("BACKGROUND") end
end

-- icons that Classic drew over the art (combat icon, skull, raid mark,
-- auras) live on the *ContentContextual child: put it above the skin
local function RaiseContextual(contextual, main)
    if contextual and contextual.SetFrameLevel and main and main.GetFrameLevel then
        local want = main:GetFrameLevel() + 2
        if contextual:GetFrameLevel() ~= want then contextual:SetFrameLevel(want) end
    end
end

-- Keep a region of ours in step with one of Blizzard's: text, colour,
-- alpha and shown state are copied now and again after every Blizzard
-- call that changes them (hooksecurefunc on the widget methods). White
-- level text (Forever's choice for the player) becomes classic gold.
local function Sync(src)
    local dst = Own(src).mirror
    if not dst then return end
    if src.GetText and dst.SetText then
        local ok, text = pcall(src.GetText, src)
        if ok then dst:SetText(text or "") end
    end
    if src.GetVertexColor and dst.SetVertexColor then
        local ok, r, g, b = pcall(src.GetVertexColor, src)
        if ok and r then
            if r == 1 and g == 1 and b == 1 then dst:SetVertexColor(1, 0.82, 0)
            else dst:SetVertexColor(r, g, b) end
        end
    end
    local isText = src.GetObjectType and src:GetObjectType() == "FontString"
    if src.GetAlpha and dst.SetAlpha and not isText then
        local ok, a = pcall(src.GetAlpha, src)
        if ok and a then dst:SetAlpha(a) end
    elseif isText and src.GetAlpha and src.SetAlpha then
        -- a mirrored text is Blizzard's copy, faded because ours stands in
        -- for it: whatever brings it back (a report showed the player's
        -- level shining through at the frame's centre, a second "17"),
        -- it goes again. SetAlpha is hooked, so the nested call sees 0
        -- and stops.
        local ok, a = pcall(src.GetAlpha, src)
        if ok and a and a ~= 0 then src:SetAlpha(0) end
    end
    if src.IsShown then
        if src:IsShown() then dst:Show() else dst:Hide() end
    end
end

local MIRROR_METHODS = {"SetText", "SetFormattedText", "SetVertexColor", "SetTextColor", "SetAlpha", "Show", "Hide", "SetShown"}
local function Mirror(src, dst)
    if not src or not dst then return end
    local own = Own(src)
    local first = own.mirror == nil
    own.mirror = dst
    if first and hooksecurefunc then
        for _, m in ipairs(MIRROR_METHODS) do
            if src[m] then hooksecurefunc(src, m, function() Sync(src) end) end
        end
    end
    Sync(src)
end

-- power-type colour for a UI-StatusBar mana bar (retail draws typed atlases)
local function ColorManaBar(bar, unit)
    if not bar or not unit or not UnitPowerType then return end
    local powerType, powerToken = UnitPowerType(unit)
    local info = PowerBarColor and (PowerBarColor[powerToken] or PowerBarColor[powerType])
    if info and info.r then bar:SetStatusBarColor(info.r, info.g, info.b) end
end

--------------------------------------------------------------------------
-- player
--------------------------------------------------------------------------

-- the classic "Zzz" rest icon on the skin (Forever plays a flipbook there)
local function RestIcon(pf, skin)
    if skin.rest then return end
    local tex = skin:CreateTexture(nil, "OVERLAY")
    tex:SetSize(31, 33)
    tex:SetPoint("TOPLEFT", pf, "TOPLEFT", 19.5, -52)
    SetFile(tex, STATE_ICON_TEX, 0, 0.5, 0, 0.421875)
    skin.rest = tex
    local function Update()
        tex:SetAlpha((IsResting and IsResting()) and 1 or 0)
    end
    skin:RegisterEvent("PLAYER_UPDATE_RESTING")
    skin:RegisterEvent("PLAYER_ENTERING_WORLD")
    skin:SetScript("OnEvent", Update)
    Update()
end

function M.RestylePlayer()
    local pf = PlayerFrame
    local container = pf and pf.PlayerFrameContainer
    local content = pf and pf.PlayerFrameContent
    local main = content and content.PlayerFrameContentMain
    if not container or not main then return false end
    local skin = Skin(pf, main)
    if not skin then return false end
    M.inRestyle = true
    -- frames under the (protected) player frame only move out of combat
    local layout = not InCombat()
    if not layout then M.pendingPlayer = true end

    -- frame art: classic player frame is the target texture mirrored, on
    -- the skin above the bars; Blizzard's copy under them goes transparent
    SetFile(skin.art, FRAME_TEX, 0.85546875, 0.1015625, 0.0625, 0.6640625)
    skin.art:ClearAllPoints()
    skin.art:SetSize(193, 77)
    skin.art:SetPoint("CENTER", pf, "CENTER", 0, 0)
    Hide(container.FrameTexture)
    Hide(container.AlternatePowerFrameTexture)
    local flash = container.FrameFlash
    if flash then
        -- mirrored: the same red glow as the target frame, flipped
        SetFile(flash, FLASH_TEX, 0.9453125, 0, 0, 0.181640625)
        flash:ClearAllPoints()
        flash:SetSize(242, 93)
        flash:SetPoint("TOPLEFT", pf, "TOPLEFT", -3, -4)
    end

    -- portrait: 64x64 round, filling the art's ring
    local portrait = container.PlayerPortrait
    if portrait then
        portrait:ClearAllPoints()
        portrait:SetSize(64, 64)
        portrait:SetPoint("TOPLEFT", pf, "TOPLEFT", 24, -16)
        RoundPortrait(container.PlayerPortraitMask, portrait)
    end

    Backdrop(pf, "TOPLEFT", 89.5, -26, 41)

    -- name shows through the art's transparent strip, the whole strip
    -- (Forever's names run longer than Era's); the level sits on the
    -- art's opaque corner circle, so a copy of it lives on the skin
    if PlayerName then
        PlayerName:ClearAllPoints()
        PlayerName:SetSize(NAME_WIDTH, 12)
        PlayerName:SetPoint("CENTER", pf, "CENTER", 34, 15)
        if PlayerName.SetJustifyH then PlayerName:SetJustifyH("CENTER") end
    end
    Hide(main.LevelBackgroundCircle)
    skin.levelText:ClearAllPoints()
    -- whole pixels: the quarter pixel put the digit left of the circle
    skin.levelText:SetPoint("CENTER", pf, "BOTTOMLEFT", 36, 31)
    if PlayerLevelText then
        Mirror(PlayerLevelText, skin.levelText)
        Fade(PlayerLevelText)
    end

    -- bars: fill any time, size / anchor out of combat
    local hc = main.HealthBarsContainer
    local hb = hc and hc.HealthBar
    local mb = main.ManaBarArea and main.ManaBarArea.ManaBar
    if hb then
        Unmask(hb, hc.HealthBarMask)
        ClassicFill(hb)
        hb:SetStatusBarColor(0, 1, 0)
    end
    if hc then
        -- retail's red "health just lost" trail and temp-max-health bar
        Fade(hc.PlayerFrameHealthBarAnimatedLoss)
        Fade(hc.PlayerFrameTempMaxHealthLoss)
        BarText(hc, hb)
    end
    if mb then
        Unmask(mb, mb.ManaBarMask)
        ClassicFill(mb)
        ColorManaBar(mb, "player")
    end
    local contextual = content.PlayerFrameContentContextual
    if layout then
        if hc then
            hc:ClearAllPoints()
            hc:SetSize(119, 12)
            hc:SetPoint("TOPLEFT", pf, "TOPLEFT", 90, -45)
        end
        -- both corners on the player frame: Blizzard's art swaps resize
        -- the container (and the temp-max-health code the bar itself), and
        -- neither may then move the bar out of the art's recess
        if hb then Corners(hb, pf, "TOPLEFT", 90, -45) end
        if mb then Corners(mb, pf, "TOPLEFT", 90, -56) end
        RaiseContextual(contextual, main)
    end

    -- rested / combat glow around the frame: Classic draws it over the art,
    -- so ours on the skin follows Blizzard's (shown, colour, pulse alpha)
    -- and Blizzard's, under the art, loses its image
    local status = main.StatusTexture
    if status then
        SetFile(skin.glow, STATUS_TEX, 0, 0.74609375, 0, 0.53125)
        skin.glow:ClearAllPoints()
        skin.glow:SetSize(190, 66)
        skin.glow:SetPoint("TOPLEFT", pf, "TOPLEFT", 19, -12)
        if skin.glow.SetBlendMode then skin.glow:SetBlendMode("ADD") end
        Mirror(status, skin.glow)
        if status.SetTexture then status:SetTexture(nil) end
    end
    if contextual then
        local attack = contextual.AttackIcon
        if attack then
            SetFile(attack, STATE_ICON_TEX, 0.5, 1.0, 0, 0.484375)
            attack:ClearAllPoints()
            attack:SetSize(32, 32)
            attack:SetPoint("TOPLEFT", pf, "TOPLEFT", 20.5, -52)
        end
        Hide(contextual.PlayerPortraitCornerIcon)
        Fade(contextual.PlayerRestLoop)
    end
    RestIcon(pf, skin)

    M.inRestyle = false
    return true
end

--------------------------------------------------------------------------
-- target / focus (same template)
--------------------------------------------------------------------------

local function Classification(unit)
    if not UnitClassification or not unit then return "normal" end
    local c = UnitClassification(unit)
    if c == "worldboss" or c == "elite" then return "elite" end
    if c == "rareelite" then return "rareelite" end
    if c == "rare" then return "rare" end
    if c == "minus" then return "minus" end
    return "normal"
end

function M.RestyleTargetArt(frame)
    local container = frame and frame.TargetFrameContainer
    local content = frame and frame.TargetFrameContent
    local main = content and content.TargetFrameContentMain
    if not container or not main then return end
    local skin = Skin(frame, main)
    if not skin then return end
    local kind = Classification(frame.unit)
    SetFile(skin.art, TARGET_ART[kind] or FRAME_TEX, 0.1015625, 1.0, 0.0078125, 0.78125)
    skin.art:ClearAllPoints()
    skin.art:SetSize(230, 99)
    skin.art:SetPoint("CENTER", frame, "CENTER", 18.5, -4)
    -- Blizzard's CheckClassification puts its atlas back on every target
    -- change; it stays transparent under the bars
    Hide(container.FrameTexture)
    Hide(container.BossPortraitFrameTexture)
    -- ...and the retail combat flash atlas (with the atlas size)
    local flash = container.Flash
    if flash then
        SetFile(flash, FLASH_TEX, 0, 0.9453125, 0, 0.181640625)
        flash:ClearAllPoints()
        flash:SetSize(242, 93)
        flash:SetPoint("TOPLEFT", frame, "TOPLEFT", -6, -3)
    end
end

function M.RestyleTarget(frame)
    local container = frame and frame.TargetFrameContainer
    local content = frame and frame.TargetFrameContent
    local main = content and content.TargetFrameContentMain
    if not container or not main then return false end
    local skin = Skin(frame, main)
    if not skin then return false end
    M.inRestyle = true

    M.RestyleTargetArt(frame)

    local portrait = container.Portrait
    if portrait then
        portrait:ClearAllPoints()
        portrait:SetSize(64, 64)
        portrait:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -24, -16)
        RoundPortrait(container.PortraitMask, portrait)
    end

    Backdrop(frame, "TOPRIGHT", -89.5, -26, 25)

    -- coloured strip behind the name = classic level background
    local rep = main.ReputationColor
    if rep then
        SetFile(rep, LEVEL_BG_TEX)
        rep:ClearAllPoints()
        rep:SetSize(119, 19)
        rep:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -90, -26)
        rep:Show()
    end
    local name = main.Name
    if name then
        name:ClearAllPoints()
        name:SetSize(NAME_WIDTH, 12)
        name:SetPoint("CENTER", frame, "CENTER", -34, 15)
        if name.SetJustifyH then name:SetJustifyH("CENTER") end
    end
    Hide(main.LevelBackgroundCircle)
    skin.levelText:ClearAllPoints()
    skin.levelText:SetPoint("CENTER", frame, "BOTTOMRIGHT", -36, 31)
    local level = main.LevelText
    if level then
        Mirror(level, skin.levelText)
        Fade(level)
    end
    local contextual = content.TargetFrameContentContextual
    local skull = contextual and contextual.HighLevelTexture
    if skull then
        SetFile(skull, SKULL_TEX)
        skull:ClearAllPoints()
        skull:SetSize(16, 16)
        skull:SetPoint("CENTER", skin.levelText, "CENTER", 0, 0)
    end

    M.RestyleTargetBars(frame)

    M.inRestyle = false
    return true
end

-- Blizzard's CheckClassification (every target change) resizes the health
-- container to the retail 126x20, hangs it off a new corner and puts the
-- atlas fill back, so this part is re-applied from that hook. Sizes,
-- anchors and frame levels on the (protected) unit frame wait for combat
-- to end; the fill can change any time. The bars themselves are anchored
-- by both corners to the target frame, so what Blizzard does to the
-- container in combat does not move them.
function M.RestyleTargetBars(frame)
    local content = frame and frame.TargetFrameContent
    local main = content and content.TargetFrameContentMain
    if not main then return end
    local hc = main.HealthBarsContainer
    local hb = hc and hc.HealthBar
    local mb = main.ManaBar
    if hb then
        Unmask(hb, hc.HealthBarMask)
        ClassicFill(hb)
        hb:SetStatusBarColor(0, 1, 0)
    end
    if hc then
        Fade(hc.TempMaxHealthLoss)
        BarText(hc, hb)
    end
    if mb then
        Unmask(mb, mb.ManaBarMask)
        ClassicFill(mb)
        ColorManaBar(mb, frame.unit)
    end
    if InCombat() then
        M.pendingBars = M.pendingBars or {}
        M.pendingBars[frame] = true
        return
    end
    if hc then
        hc:ClearAllPoints()
        hc:SetSize(119, 12)
        hc:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -90, -45)
    end
    if hb then Corners(hb, frame, "TOPRIGHT", -209, -45) end
    if mb then
        Corners(mb, frame, "TOPRIGHT", -209, -56)
        -- Forever's target mana bar sits one level above the rest: down to
        -- the bars' level, so the art's bevel draws over its fill too
        if mb.SetFrameLevel and main.GetFrameLevel and mb:GetFrameLevel() ~= main:GetFrameLevel() then
            mb:SetFrameLevel(main:GetFrameLevel())
        end
    end
    RaiseContextual(content.TargetFrameContentContextual, main)
end

--------------------------------------------------------------------------
-- pet
--------------------------------------------------------------------------

-- Classic: UI-SmallTargetingFrame (128x64) drawn over a 37px portrait and
-- two 69x8 bars; Forever draws the retail target-of-target atlas under its
-- bars. The classic art goes on a frame of ours above the bars (Blizzard's
-- texture region sits on the pet frame itself, under them) and Blizzard's
-- is faded out.
function M.RestylePet()
    local pet = PetFrame
    if not pet or not PetFrameTexture or not PetFrameHealthBar then return false end
    local own = Own(pet)
    local layout = not InCombat()
    if not layout then M.pendingPet = true end

    if not own.art and CreateFrame then
        local f = CreateFrame("Frame", nil, pet)
        f:SetAllPoints(pet)
        local tex = f:CreateTexture(nil, "BORDER")
        SetFile(tex, PET_TEX)
        tex:SetSize(128, 64)
        tex:SetPoint("TOPLEFT", pet, "TOPLEFT", 0, -2)
        f.tex = tex
        own.art = f
    end
    -- at the bars' level (pet + 1): art over their BACKGROUND fills, under
    -- their OVERLAY numbers, like the big frames
    if own.art.SetFrameLevel and pet.GetFrameLevel then own.art:SetFrameLevel(pet:GetFrameLevel() + 1) end
    Hide(PetFrameTexture)

    if PetPortrait then
        PetPortrait:ClearAllPoints()
        PetPortrait:SetSize(37, 37)
        PetPortrait:SetPoint("TOPLEFT", pet, "TOPLEFT", 7, -6)
        RoundPortrait(pet.PortraitMask, PetPortrait)
    end
    if PetName then
        PetName:ClearAllPoints()
        PetName:SetPoint("BOTTOMLEFT", pet, "BOTTOMLEFT", 52, 33)
        if PetName.SetWidth then PetName:SetWidth(0) end
        if PetName.SetJustifyH then PetName:SetJustifyH("LEFT") end
    end
    if PetFrameFlash then
        SetFile(PetFrameFlash, PET_FLASH_TEX, 0, 1, 1, 0)
        PetFrameFlash:ClearAllPoints()
        PetFrameFlash:SetSize(128, 64)
        PetFrameFlash:SetPoint("TOPLEFT", pet, "TOPLEFT", -4, 11)
    end
    if PetAttackModeTexture then
        SetFile(PetAttackModeTexture, PET_ATTACK_TEX, 0.703125, 1, 0, 1)
        PetAttackModeTexture:ClearAllPoints()
        PetAttackModeTexture:SetSize(76, 64)
        PetAttackModeTexture:SetPoint("TOPLEFT", pet, "TOPLEFT", 6, -9)
        if PetAttackModeTexture.SetBlendMode then PetAttackModeTexture:SetBlendMode("ADD") end
    end

    local hb, mb = PetFrameHealthBar, PetFrameManaBar
    Unmask(hb, PetFrameHealthBarMask)
    ClassicFill(hb)
    hb:SetStatusBarColor(0, 1, 0)
    if mb then
        Unmask(mb, PetFrameManaBarMask)
        ClassicFill(mb)
        ColorManaBar(mb, "pet")
    end
    if layout then
        pet:SetSize(128, 53)
        hb:ClearAllPoints()
        hb:SetSize(69, 8)
        hb:SetPoint("TOPLEFT", pet, "TOPLEFT", 47, -22)
        if mb then
            mb:ClearAllPoints()
            mb:SetSize(69, 8)
            mb:SetPoint("TOPLEFT", pet, "TOPLEFT", 47, -29)
        end
    end
    return true
end

--------------------------------------------------------------------------
-- keep it classic when Blizzard redraws
--------------------------------------------------------------------------

local function IsOurBar(bar)
    if not bar then return false end
    local pf = PlayerFrame
    if pf and pf.PlayerFrameContent and pf.PlayerFrameContent.PlayerFrameContentMain and
        pf.PlayerFrameContent.PlayerFrameContentMain.ManaBarArea and
        bar == pf.PlayerFrameContent.PlayerFrameContentMain.ManaBarArea.ManaBar then
        return true, "player"
    end
    if PetFrameManaBar and bar == PetFrameManaBar then return true, "pet" end
    for _, f in ipairs({TargetFrame, FocusFrame}) do
        local main = f and f.TargetFrameContent and f.TargetFrameContent.TargetFrameContentMain
        if main and bar == main.ManaBar then return true, f.unit end
    end
    return false
end

local function InstallHooks()
    if M.hooked or not hooksecurefunc then return end
    M.hooked = true
    -- vehicle / player art swaps and the alternate-power art
    for _, fname in ipairs({"PlayerFrame_ToPlayerArt", "PlayerFrame_ToVehicleArt", "PlayerFrame_UpdateArt", "PlayerFrame_UpdatePlayerNameTextAnchor"}) do
        if _G[fname] then
            hooksecurefunc(fname, function()
                if M.mode == "restyled" and not M.inRestyle then M.RestylePlayer() end
            end)
        end
    end
    -- retail re-textures mana bars per power type; put ours back with a colour
    if UnitFrameManaBar_UpdateType then
        hooksecurefunc("UnitFrameManaBar_UpdateType", function(bar)
            if M.mode ~= "restyled" or M.inRestyle then return end
            local ours, unit = IsOurBar(bar)
            if ours then
                ClassicFill(bar)
                ColorManaBar(bar, unit)
            end
        end)
    end
    -- elite / rare art on the target and focus frames
    for _, f in ipairs({TargetFrame, FocusFrame}) do
        if f then
            if f.CheckClassification then
                hooksecurefunc(f, "CheckClassification", function(frame)
                    if M.mode == "restyled" and not M.inRestyle then
                        M.RestyleTargetArt(frame)
                        M.RestyleTargetBars(frame)
                    end
                end)
            end
            if f.CheckFaction then
                hooksecurefunc(f, "CheckFaction", function(frame)
                    if M.mode == "restyled" and not M.inRestyle then M.RestyleTargetArt(frame) end
                end)
            end
        end
    end
end

--------------------------------------------------------------------------
-- module interface
--------------------------------------------------------------------------

local function IsNative()
    -- classic clients: the old named textures exist, the retail containers don't
    return PlayerFrameTexture ~= nil and not (PlayerFrame and PlayerFrame.PlayerFrameContainer)
end

-- layout deferred by combat is applied once it ends
local function InstallCombatWaiter()
    if M.barWaiter or not CreateFrame then return end
    M.barWaiter = CreateFrame("Frame")
    M.barWaiter:RegisterEvent("PLAYER_REGEN_ENABLED")
    M.barWaiter:SetScript("OnEvent", function()
        if M.mode ~= "restyled" then return end
        if M.pendingPlayer then
            M.pendingPlayer = nil
            M.RestylePlayer()
        end
        if M.pendingPet then
            M.pendingPet = nil
            M.RestylePet()
        end
        local pending = M.pendingBars
        M.pendingBars = nil
        if pending then
            for frame in pairs(pending) do M.RestyleTargetBars(frame) end
        end
    end)
end

function M:Enable()
    if not PlayerFrame then
        M.mode = "unavailable"
        return
    end
    InstallCombatWaiter()
    if IsNative() then
        M.mode = "native"
        return
    end
    if InCombat() then
        M.mode = "deferred"
        if CreateFrame and not M.waiter then
            M.waiter = CreateFrame("Frame")
            M.waiter:RegisterEvent("PLAYER_REGEN_ENABLED")
            M.waiter:SetScript("OnEvent", function()
                if M.mode == "deferred" then M:Enable() end
            end)
        end
        return
    end
    local did = M.RestylePlayer()
    if TargetFrame then did = M.RestyleTarget(TargetFrame) or did end
    if FocusFrame then M.RestyleTarget(FocusFrame) end
    M.RestylePet()
    if did then
        M.mode = "restyled"
        InstallHooks()
    else
        M.mode = "unavailable"
        ns.Print("unit frames: this client's player frame has an unknown layout. Run /cui probe and send me the report.")
    end
end

function M:Force()
    if IsNative() then
        ns.Print("unit frames: this client already draws the classic frames.")
        return
    end
    M.mode = "off"
    M.hooked = nil
    M:Enable()
    ns.Print("unit frames: re-skinned (%s).", M.mode)
end

function M:Disable()
    M.mode = "off"
    ns.Print("unit frames: type /reload to restore Blizzard's frames.")
end

function M:Status()
    if M.mode == "native" then return "(client already draws the classic frames)" end
    if M.mode == "restyled" then return "(player/target/pet re-skinned to classic art)" end
    if M.mode == "deferred" then return "(waiting for combat to end)" end
    if M.mode == "unavailable" then return "(unavailable on this client)" end
    return ""
end

ns.RegisterModule("unitframes", M)
