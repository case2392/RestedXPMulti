-- Forever Classic UI - player / target / focus frames
--
-- Forever's unit frames are the retail (Dragonflight) layout: portrait in a
-- rounded frame atlas, wide health bar, mana strip, level in a small circle.
-- Classic drew both frames from one texture (UI-TargetingFrame, mirrored for
-- the player), a 119x12 health bar with a 119x12 mana bar under it, the
-- level in the frame's corner, and elite/rare variants of the target art.
--
-- The retail frame structure is kept (Blizzard's code keeps driving values
-- and events); only art, sizes and anchors are moved to the classic ones.
-- Classic clients already draw this and are left alone.

local addonName, ns = ...

local M = {mode = "off"}

local TF = "Interface\\TargetingFrame\\"
local FRAME_TEX = TF .. "UI-TargetingFrame"
local BAR_TEX = TF .. "UI-StatusBar"
local TARGET_ART = {
    normal = FRAME_TEX,
    minus = TF .. "UI-TargetingFrame-Minus",
    elite = TF .. "UI-TargetingFrame-Elite",
    rareelite = TF .. "UI-TargetingFrame-Rare-Elite",
    rare = TF .. "UI-TargetingFrame-Rare"
}

local function SetFile(tex, path, l, r, t, b)
    if not tex then return end
    if tex.SetTexture then tex:SetTexture(path) end
    if tex.SetTexCoord then
        if l then tex:SetTexCoord(l, r, t, b) else tex:SetTexCoord(0, 1, 0, 1) end
    end
end

-- Retail clips each bar to a rounded shape with a mask texture (attached at
-- load, re-pointed by Blizzard's art swaps). Detach it from the fill and,
-- in case it is still attached to anything, make it a solid white square
-- over the bar so it clips nothing.
local WHITE = "Interface\\Buttons\\WHITE8x8"
local function Unmask(bar, maskKey)
    local tex = bar and bar.GetStatusBarTexture and bar:GetStatusBarTexture()
    local mask = bar and bar[maskKey]
    if tex and mask and tex.RemoveMaskTexture then
        pcall(tex.RemoveMaskTexture, tex, mask)
    end
    if mask then
        if mask.SetTexture then pcall(mask.SetTexture, mask, WHITE) end
        if mask.ClearAllPoints and mask.SetPoint then
            mask:ClearAllPoints()
            mask:SetPoint("TOPLEFT", bar, "TOPLEFT", -4, 4)
            mask:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 4, -4)
        end
        if mask.Hide then mask:Hide() end
    end
end

local function Hide(region)
    if region then
        if region.Hide then region:Hide() end
        if region.SetAlpha then region:SetAlpha(0) end
    end
end

-- black 50% box behind the bars, like PlayerFrameBackground / TargetFrameBackground
local function Backdrop(frame, key, point, x, y)
    if frame[key] then return frame[key] end
    local tex = frame:CreateTexture(nil, "BACKGROUND", nil, -1)
    tex:SetColorTexture(0, 0, 0, 0.5)
    tex:SetSize(119, 41)
    tex:SetPoint(point, frame, point, x, y)
    frame[key] = tex
    return tex
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

function M.RestylePlayer()
    local pf = PlayerFrame
    local container = pf and pf.PlayerFrameContainer
    local content = pf and pf.PlayerFrameContent
    local main = content and content.PlayerFrameContentMain
    if not container or not main then return false end
    M.inRestyle = true

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
        SetFile(flash, TF .. "UI-TargetingFrame-Flash")
        flash:ClearAllPoints()
        flash:SetSize(242, 93)
        flash:SetPoint("TOPLEFT", pf, "TOPLEFT", -3, -4)
    end

    -- portrait
    local portrait = container.PlayerPortrait
    if portrait then
        portrait:ClearAllPoints()
        portrait:SetSize(64, 64)
        portrait:SetPoint("TOPLEFT", pf, "TOPLEFT", 24, -16)
    end
    if container.PlayerPortraitMask then
        container.PlayerPortraitMask:ClearAllPoints()
        container.PlayerPortraitMask:SetSize(64, 64)
        container.PlayerPortraitMask:SetPoint("TOPLEFT", pf, "TOPLEFT", 24, -16)
    end

    Backdrop(container, "forevercuiBackdrop", "TOPLEFT", 89.5, -26)

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
        if PlayerLevelText.SetFontObject and GameNormalNumberFont then
            PlayerLevelText:SetFontObject("GameNormalNumberFont")
        end
        if PlayerLevelText.SetJustifyH then PlayerLevelText:SetJustifyH("RIGHT") end
    end

    -- health
    local hc = main.HealthBarsContainer
    local hb = hc and hc.HealthBar
    if hc then
        hc:ClearAllPoints()
        hc:SetSize(119, 12)
        hc:SetPoint("TOPLEFT", pf, "TOPLEFT", 90, -45)
    end
    if hb then
        hb:ClearAllPoints()
        hb:SetSize(119, 12)
        hb:SetPoint("TOPLEFT", hc, "TOPLEFT", 0, 0)
        Unmask(hb, "HealthBarMask")
        hb:SetStatusBarTexture(BAR_TEX)
        hb:SetStatusBarColor(0, 1, 0)
    end

    -- mana
    local mb = main.ManaBarArea and main.ManaBarArea.ManaBar
    if mb then
        mb:ClearAllPoints()
        mb:SetSize(119, 12)
        mb:SetPoint("TOPLEFT", pf, "TOPLEFT", 90, -56)
        Unmask(mb, "ManaBarMask")
        mb:SetStatusBarTexture(BAR_TEX)
        ColorManaBar(mb, "player")
    end

    -- rested glow / combat icon / corner embellishment
    local status = main.StatusTexture
    if status then
        SetFile(status, "Interface\\CharacterFrame\\UI-Player-Status")
        status:ClearAllPoints()
        status:SetSize(190, 66)
        status:SetPoint("TOPLEFT", pf, "TOPLEFT", 19, -12)
        if status.SetBlendMode then status:SetBlendMode("ADD") end
    end
    local contextual = content.PlayerFrameContentContextual
    if contextual then
        local attack = contextual.AttackIcon
        if attack then
            SetFile(attack, "Interface\\CharacterFrame\\UI-StateIcon", 0.5, 1.0, 0, 0.484375)
            attack:ClearAllPoints()
            attack:SetSize(32, 32)
            attack:SetPoint("TOPLEFT", pf, "TOPLEFT", 20.5, -52)
        end
        Hide(contextual.PlayerPortraitCornerIcon)
    end

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
end

function M.RestyleTarget(frame)
    local container = frame and frame.TargetFrameContainer
    local content = frame and frame.TargetFrameContent
    local main = content and content.TargetFrameContentMain
    if not container or not main then return false end
    M.inRestyle = true

    M.RestyleTargetArt(frame)

    local flash = container.Flash
    if flash then
        SetFile(flash, TF .. "UI-TargetingFrame-Flash", 0, 0.9453125, 0, 0.181640625)
        flash:ClearAllPoints()
        flash:SetSize(242, 93)
        flash:SetPoint("TOPLEFT", frame, "TOPLEFT", -6, -3)
    end

    local portrait = container.Portrait
    if portrait then
        portrait:ClearAllPoints()
        portrait:SetSize(64, 64)
        portrait:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -24, -16)
    end
    if container.PortraitMask then
        container.PortraitMask:ClearAllPoints()
        container.PortraitMask:SetSize(64, 64)
        container.PortraitMask:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -24, -16)
    end

    Backdrop(container, "forevercuiBackdrop", "TOPRIGHT", -89.5, -26)

    -- coloured strip behind the name = classic level background
    local rep = main.ReputationColor
    if rep then
        SetFile(rep, TF .. "UI-TargetingFrame-LevelBackground")
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
        if level.SetFontObject and GameNormalNumberFont then
            level:SetFontObject("GameNormalNumberFont")
        end
    end
    local contextual = content.TargetFrameContentContextual
    local skull = contextual and contextual.HighLevelTexture
    if skull then
        SetFile(skull, TF .. "UI-TargetingFrame-Skull")
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
-- is re-applied from that hook. Sizes and anchors on the (protected) unit
-- frame wait for combat to end; the fill texture can change any time.
function M.RestyleTargetBars(frame)
    local content = frame and frame.TargetFrameContent
    local main = content and content.TargetFrameContentMain
    if not main then return end
    local hc = main.HealthBarsContainer
    local hb = hc and hc.HealthBar
    local mb = main.ManaBar
    if hb then
        Unmask(hb, "HealthBarMask")
        hb:SetStatusBarTexture(BAR_TEX)
        hb:SetStatusBarColor(0, 1, 0)
    end
    if mb then
        Unmask(mb, "ManaBarMask")
        mb:SetStatusBarTexture(BAR_TEX)
        ColorManaBar(mb, frame.unit)
    end
    if InCombatLockdown and InCombatLockdown() then
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

local function InstallCombatWaiter()
    if M.barWaiter or not CreateFrame then return end
    M.barWaiter = CreateFrame("Frame")
    M.barWaiter:RegisterEvent("PLAYER_REGEN_ENABLED")
    M.barWaiter:SetScript("OnEvent", function()
        if M.mode ~= "restyled" or not M.pendingBars then return end
        local pending = M.pendingBars
        M.pendingBars = nil
        for frame in pairs(pending) do M.RestyleTargetBars(frame) end
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
    if InCombatLockdown and InCombatLockdown() then
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
    if M.mode == "restyled" then return "(player/target re-skinned to classic art)" end
    if M.mode == "deferred" then return "(waiting for combat to end)" end
    if M.mode == "unavailable" then return "(unavailable on this client)" end
    return ""
end

ns.RegisterModule("unitframes", M)
