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

-- Retail clips portraits and bars with MaskTextures (attached at load and
-- re-attached by Blizzard's art swaps). A mask cannot be detached from
-- everything it clips without writing into Blizzard's tables, so instead it
-- is turned into a plain white square over the region it clips: white means
-- "show", and the mask's clamp-to-black wrap keeps it from revealing
-- anything outside that square.
local function Whiten(mask, region, pad)
    if not mask or not region then return end
    if mask.SetTexture then pcall(mask.SetTexture, mask, WHITE) end
    if mask.ClearAllPoints and mask.SetPoint then
        mask:ClearAllPoints()
        mask:SetPoint("TOPLEFT", region, "TOPLEFT", -pad, pad)
        mask:SetPoint("BOTTOMRIGHT", region, "BOTTOMRIGHT", pad, -pad)
    end
    if mask.Show then mask:Show() end
end

local function Unmask(bar, mask)
    local tex = bar and bar.GetStatusBarTexture and bar:GetStatusBarTexture()
    if tex and mask and tex.RemoveMaskTexture then
        pcall(tex.RemoveMaskTexture, tex, mask)
    end
    Whiten(mask, bar, 4)
end

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

-- Classic draws the frame art over the bars: the bevel around each bar is
-- part of the art and the bar ends disappear under it. Retail draws the
-- bars over the art. On Forever the art lives on the *Container child
-- (unit frame level + 1) and the bars on *ContentMain (level + 2); moving
-- the bar frames down to the unit frame's own level puts them under the art
-- while the name and level texts on *ContentMain stay on top, exactly the
-- Era order (HealthBar level 2, PlayerFrameTexture and texts level 3).
local function LowerBars(frame, ...)
    if not frame.GetFrameLevel then return end
    local level = frame:GetFrameLevel()
    for i = 1, select("#", ...) do
        local f = select(i, ...)
        if f and f.GetFrameLevel and f.SetFrameLevel and f:GetFrameLevel() ~= level then
            f:SetFrameLevel(level)
        end
    end
end

-- power-type colour for a UI-StatusBar mana bar (retail draws typed atlases)
local function ColorManaBar(bar, unit)
    if not bar or not unit or not UnitPowerType then return end
    local powerType, powerToken = UnitPowerType(unit)
    local info = PowerBarColor and (PowerBarColor[powerToken] or PowerBarColor[powerType])
    if info and info.r then bar:SetStatusBarColor(info.r, info.g, info.b) end
end

-- classic level text: GameFontNormalSmall, gold. Blizzard's update paints
-- the player's white on every level change (Forever's PlayerFrame_GetLevelRGBA);
-- the target's keeps Blizzard's difficulty colour.
local function ClassicLevelFont(fs)
    if not fs then return end
    if fs.SetFontObject and GameFontNormalSmall then fs:SetFontObject("GameFontNormalSmall") end
    if fs.SetJustifyH then fs:SetJustifyH("CENTER") end
end

local function GoldLevel(fs)
    if not fs or not fs.GetVertexColor then return end
    local ok, r, g, b = pcall(fs.GetVertexColor, fs)
    if ok and r == 1 and g == 1 and b == 1 and fs.SetVertexColor then
        fs:SetVertexColor(1, 0.82, 0)
    end
end

--------------------------------------------------------------------------
-- player
--------------------------------------------------------------------------

-- the classic "Zzz" rest icon (Forever plays a flipbook animation there)
local function RestIcon(pf)
    local own = Own(pf)
    if own.rest or not CreateFrame then return end
    local f = CreateFrame("Frame", nil, pf)
    f:SetSize(31, 33)
    f:SetPoint("TOPLEFT", pf, "TOPLEFT", 19.5, -52)
    if f.SetFrameLevel and pf.GetFrameLevel then f:SetFrameLevel(pf:GetFrameLevel() + 4) end
    local tex = f:CreateTexture(nil, "OVERLAY")
    tex:SetAllPoints(f)
    SetFile(tex, STATE_ICON_TEX, 0, 0.5, 0, 0.421875)
    f.tex = tex
    local function Update()
        f:SetAlpha((IsResting and IsResting()) and 1 or 0)
    end
    f:RegisterEvent("PLAYER_UPDATE_RESTING")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:SetScript("OnEvent", Update)
    Update()
    own.rest = f
end

function M.RestylePlayer()
    local pf = PlayerFrame
    local container = pf and pf.PlayerFrameContainer
    local content = pf and pf.PlayerFrameContent
    local main = content and content.PlayerFrameContentMain
    if not container or not main then return false end
    M.inRestyle = true
    -- frames under the (protected) player frame only move out of combat
    local layout = not InCombat()
    if not layout then M.pendingPlayer = true end

    -- frame art: classic player frame is the target texture mirrored
    local art = container.FrameTexture
    if art then
        SetFile(art, FRAME_TEX, 0.85546875, 0.1015625, 0.0625, 0.6640625)
        art:ClearAllPoints()
        art:SetSize(193, 77)
        art:SetPoint("CENTER", pf, "CENTER", 0, 0)
        art:Show()
    end
    Hide(container.AlternatePowerFrameTexture)
    local flash = container.FrameFlash
    if flash then
        -- mirrored: the same red glow as the target frame, flipped
        SetFile(flash, FLASH_TEX, 0.9453125, 0, 0, 0.181640625)
        flash:ClearAllPoints()
        flash:SetSize(242, 93)
        flash:SetPoint("TOPLEFT", pf, "TOPLEFT", -3, -4)
    end

    -- portrait: a plain 64x64 square, the art above it rounds it off
    local portrait = container.PlayerPortrait
    if portrait then
        portrait:ClearAllPoints()
        portrait:SetSize(64, 64)
        portrait:SetPoint("TOPLEFT", pf, "TOPLEFT", 24, -16)
        Whiten(container.PlayerPortraitMask, portrait, 0)
    end

    Backdrop(pf, "TOPLEFT", 89.5, -26, 41)

    -- name / level
    if PlayerName then
        PlayerName:ClearAllPoints()
        PlayerName:SetSize(100, 12)
        PlayerName:SetPoint("CENTER", pf, "CENTER", 34, 15)
        if PlayerName.SetJustifyH then PlayerName:SetJustifyH("CENTER") end
    end
    Hide(main.LevelBackgroundCircle)
    if PlayerLevelText then
        PlayerLevelText:ClearAllPoints()
        PlayerLevelText:SetPoint("CENTER", pf, "BOTTOMLEFT", 35.25, 30)
        ClassicLevelFont(PlayerLevelText)
        GoldLevel(PlayerLevelText)
    end

    -- bars: fill any time, size / anchor / draw order out of combat
    local hc = main.HealthBarsContainer
    local hb = hc and hc.HealthBar
    local mb = main.ManaBarArea and main.ManaBarArea.ManaBar
    if hb then
        Unmask(hb, hc.HealthBarMask)
        hb:SetStatusBarTexture(BAR_TEX)
        hb:SetStatusBarColor(0, 1, 0)
    end
    if hc then
        -- retail's red "health just lost" trail and temp-max-health bar
        Fade(hc.PlayerFrameHealthBarAnimatedLoss)
        Fade(hc.PlayerFrameTempMaxHealthLoss)
    end
    if mb then
        Unmask(mb, mb.ManaBarMask)
        mb:SetStatusBarTexture(BAR_TEX)
        ColorManaBar(mb, "player")
    end
    if layout then
        if hc then
            hc:ClearAllPoints()
            hc:SetSize(119, 12)
            hc:SetPoint("TOPLEFT", pf, "TOPLEFT", 90, -45)
        end
        if hb then
            hb:ClearAllPoints()
            hb:SetSize(119, 12)
            hb:SetPoint("TOPLEFT", hc, "TOPLEFT", 0, 0)
        end
        if mb then
            mb:ClearAllPoints()
            mb:SetSize(119, 12)
            mb:SetPoint("TOPLEFT", pf, "TOPLEFT", 90, -56)
        end
        LowerBars(pf, hc, main.ManaBarArea)
    end

    -- rested / combat glow around the frame, combat icon, rest icon
    local status = main.StatusTexture
    if status then
        SetFile(status, STATUS_TEX, 0, 0.74609375, 0, 0.53125)
        status:ClearAllPoints()
        status:SetSize(190, 66)
        status:SetPoint("TOPLEFT", pf, "TOPLEFT", 19, -12)
        if status.SetBlendMode then status:SetBlendMode("ADD") end
    end
    local contextual = content.PlayerFrameContentContextual
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
    RestIcon(pf)

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
    if not container then return end
    local art = container.FrameTexture
    if art then
        local kind = Classification(frame.unit)
        SetFile(art, TARGET_ART[kind] or FRAME_TEX, 0.1015625, 1.0, 0.0078125, 0.78125)
        art:ClearAllPoints()
        art:SetSize(230, 99)
        art:SetPoint("CENTER", frame, "CENTER", 18.5, -4)
        art:Show()
    end
    Hide(container.BossPortraitFrameTexture)
    -- Blizzard's CheckClassification also puts the retail combat flash atlas
    -- back (with the atlas size) on every target change
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
    M.inRestyle = true

    M.RestyleTargetArt(frame)

    local portrait = container.Portrait
    if portrait then
        portrait:ClearAllPoints()
        portrait:SetSize(64, 64)
        portrait:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -24, -16)
        Whiten(container.PortraitMask, portrait, 0)
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
        name:SetSize(100, 12)
        name:SetPoint("CENTER", frame, "CENTER", -34, 15)
        if name.SetJustifyH then name:SetJustifyH("CENTER") end
    end
    Hide(main.LevelBackgroundCircle)
    local level = main.LevelText
    if level then
        level:ClearAllPoints()
        level:SetPoint("CENTER", frame, "BOTTOMRIGHT", -35.25, 30)
        ClassicLevelFont(level)
    end
    local contextual = content.TargetFrameContentContextual
    local skull = contextual and contextual.HighLevelTexture
    if skull then
        SetFile(skull, SKULL_TEX)
        skull:ClearAllPoints()
        skull:SetSize(16, 16)
        if level then skull:SetPoint("CENTER", level, "CENTER", 0, 0) end
    end

    M.RestyleTargetBars(frame)

    M.inRestyle = false
    return true
end

-- Blizzard's CheckClassification (every target change) resizes the health
-- container to the retail 126x20 and puts the atlas fill back, so this part
-- is re-applied from that hook. Sizes, anchors and draw order on the
-- (protected) unit frame wait for combat to end; the fill can change any time.
function M.RestyleTargetBars(frame)
    local content = frame and frame.TargetFrameContent
    local main = content and content.TargetFrameContentMain
    if not main then return end
    local hc = main.HealthBarsContainer
    local hb = hc and hc.HealthBar
    local mb = main.ManaBar
    if hb then
        Unmask(hb, hc.HealthBarMask)
        hb:SetStatusBarTexture(BAR_TEX)
        hb:SetStatusBarColor(0, 1, 0)
    end
    if hc then Fade(hc.TempMaxHealthLoss) end
    if mb then
        Unmask(mb, mb.ManaBarMask)
        mb:SetStatusBarTexture(BAR_TEX)
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
    if hb then
        hb:ClearAllPoints()
        hb:SetSize(119, 12)
        hb:SetPoint("TOPLEFT", hc, "TOPLEFT", 0, 0)
    end
    if mb then
        mb:ClearAllPoints()
        mb:SetSize(119, 12)
        mb:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -90, -56)
    end
    LowerBars(frame, hc, mb)
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
        if f.SetFrameLevel and pet.GetFrameLevel then f:SetFrameLevel(pet:GetFrameLevel() + 2) end
        local tex = f:CreateTexture(nil, "BORDER")
        SetFile(tex, PET_TEX)
        tex:SetSize(128, 64)
        tex:SetPoint("TOPLEFT", pet, "TOPLEFT", 0, -2)
        f.tex = tex
        own.art = f
    end
    Hide(PetFrameTexture)

    if PetPortrait then
        PetPortrait:ClearAllPoints()
        PetPortrait:SetSize(37, 37)
        PetPortrait:SetPoint("TOPLEFT", pet, "TOPLEFT", 7, -6)
        Whiten(pet.PortraitMask, PetPortrait, 0)
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
    hb:SetStatusBarTexture(BAR_TEX)
    hb:SetStatusBarColor(0, 1, 0)
    if mb then
        Unmask(mb, PetFrameManaBarMask)
        mb:SetStatusBarTexture(BAR_TEX)
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
    -- Blizzard paints the player's level white on every level update
    if PlayerFrame_UpdateLevel then
        hooksecurefunc("PlayerFrame_UpdateLevel", function()
            if M.mode == "restyled" then GoldLevel(PlayerLevelText) end
        end)
    end
    -- retail re-textures mana bars per power type; put ours back with a colour
    if UnitFrameManaBar_UpdateType then
        hooksecurefunc("UnitFrameManaBar_UpdateType", function(bar)
            if M.mode ~= "restyled" or M.inRestyle then return end
            local ours, unit = IsOurBar(bar)
            if ours then
                bar:SetStatusBarTexture(BAR_TEX)
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
