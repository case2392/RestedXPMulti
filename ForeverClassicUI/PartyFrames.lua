-- Forever Classic UI - party member frames
--
-- Forever draws the four party frames the retail way: a rounded portrait
-- atlas, a 70x10 health bar with the name over it, a mana strip, the role
-- icon in the corner. Classic Era drew each member from the UI-PartyFrame
-- texture (128x64 over a 128x53 frame), a 37x37 round portrait, the name
-- in the small gold font over two 70x8 bars (green health, blue mana),
-- the leader crown on the top-left corner, and the pet as a 64x26 strip
-- under the member with its own tiny portrait and 35x4 health bar.
--
-- Same approach as the player/target frames: Blizzard's frames keep
-- running (values, events, clicks, auras); only art, sizes and anchors
-- move to Era's numbers, which come from Era's PartyFrameTemplates.xml
-- and a `/cui report all` taken on Classic Era while grouped. Blizzard's
-- own art refreshes (ToPlayerArt on every roster update, vehicle art) are
-- re-skinned as they happen.
--
-- The classic art is a texture of ours on Blizzard's PartyMemberOverlay:
-- that frame sits above the bars and under the overlay's own icons, which
-- is exactly where Era's copy of the texture lives. The party frames are
-- protected unit frames: anchors and sizes are only touched out of combat
-- and caught up when combat ends; textures and alpha change at once.
--
-- Rule (Forever wraps unit health in secret values): no Lua field writes
-- into Blizzard's frames, no calls into Blizzard's unit frame functions.
-- Widget calls and hooksecurefunc only. Anything of ours that hangs off a
-- Blizzard frame is kept in M.own, keyed by the frame.

local addonName, ns = ...

local M = {mode = "off"}

local TF = "Interface\\TargetingFrame\\"
local PARTY_TEX = TF .. "UI-PartyFrame"
local FLASH_TEX = TF .. "UI-PartyFrame-Flash"
local BAR_TEX = TF .. "UI-StatusBar"
local STATUS_TEX = "Interface\\Buttons\\UI-Debuff-Overlays"
local WHITE = "Interface\\Buttons\\WHITE8x8"
local MAX_MEMBERS = 4

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

local function Hide(region)
    if region then
        if region.Hide then region:Hide() end
        if region.SetAlpha then region:SetAlpha(0) end
    end
end

local function Fade(region)
    if region and region.SetAlpha then region:SetAlpha(0) end
end

-- see UnitFrames.lua: the retail mask becomes a plain white square over the bar
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

local function ColorManaBar(bar, unit)
    if not bar or not unit or not UnitPowerType then return end
    local powerType, powerToken = UnitPowerType(unit)
    local info = PowerBarColor and (PowerBarColor[powerToken] or PowerBarColor[powerType])
    if info and info.r then bar:SetStatusBarColor(info.r, info.g, info.b) end
end

local function Place(region, point, rel, relPoint, x, y, w, h)
    if not region then return end
    region:ClearAllPoints()
    region:SetPoint(point, rel, relPoint, x, y)
    if w then region:SetSize(w, h) end
end

--------------------------------------------------------------------------
-- one member
--------------------------------------------------------------------------

local function RestylePet(pet, layout)
    if not pet then return end
    local tex = pet.Texture
    if tex then
        if tex.SetScale then tex:SetScale(1) end   -- Forever draws its atlas at half scale
        SetFile(tex, PARTY_TEX)
        Place(tex, "TOPLEFT", pet, "TOPLEFT", 0, -1, 64, 32)
        tex:SetAlpha(1)
    end
    if pet.Portrait then
        Place(pet.Portrait, "TOPLEFT", pet, "TOPLEFT", 3, -3, 18, 18)
        RoundPortrait(pet.PortraitMask, pet.Portrait)
    end
    if pet.Name then
        Place(pet.Name, "BOTTOMLEFT", pet, "BOTTOMLEFT", 25, 21)
        if pet.Name.SetJustifyH then pet.Name:SetJustifyH("LEFT") end
    end
    local hb = pet.HealthBar
    if hb then
        Unmask(hb, hb.HealthBarMask or pet.HealthBarMask)
        hb:SetStatusBarTexture(BAR_TEX)
        hb:SetStatusBarColor(0, 1, 0)
        if layout then Place(hb, "TOPLEFT", pet, "TOPLEFT", 23, -6, 35, 4) end
    end
    if pet.threatIndicator then Fade(pet.threatIndicator) end
    if layout then pet:SetSize(64, 26) end
end

function M.RestyleMember(frame, index)
    if not frame or not frame.PartyMemberOverlay then return false end
    local own = Own(frame)
    local unit = "party" .. index
    local layout = not InCombat()
    if not layout then M.pending = true end
    local ov = frame.PartyMemberOverlay

    -- the classic art, on the overlay under its icons; Blizzard's atlas
    -- and vehicle art faded (Blizzard Show()s them, alpha stays)
    if not own.art and ov.CreateTexture then
        local tex = ov:CreateTexture(nil, "BORDER")
        SetFile(tex, PARTY_TEX)
        tex:SetSize(128, 64)
        tex:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -2)
        own.art = tex
    end
    Fade(frame.Texture)
    Fade(frame.VehicleTexture)
    if frame.Flash then
        SetFile(frame.Flash, FLASH_TEX)
        Place(frame.Flash, "TOPLEFT", frame, "TOPLEFT", -3, 2, 128, 64)
    end
    -- black box behind the bars (Era's Background)
    if not own.backdrop and frame.CreateTexture then
        local bg = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
        bg:SetColorTexture(0, 0, 0, 0.5)
        bg:SetSize(72, 20)
        bg:SetPoint("TOPLEFT", frame, "TOPLEFT", 45, -11)
        own.backdrop = bg
    end

    if frame.Portrait then
        Place(frame.Portrait, "TOPLEFT", frame, "TOPLEFT", 7, -6, 37, 37)
        RoundPortrait(frame.PortraitMask, frame.Portrait)
    end
    if frame.Name then
        Place(frame.Name, "BOTTOMLEFT", frame, "BOTTOMLEFT", 50, 43)
        if frame.Name.SetWidth then frame.Name:SetWidth(73) end
        if frame.Name.SetJustifyH then frame.Name:SetJustifyH("LEFT") end
        if GameFontNormalSmall and frame.Name.SetFontObject then frame.Name:SetFontObject(GameFontNormalSmall) end
    end

    -- overlay pieces: Era's status ring round the portrait, the leader
    -- crown in the corner, pvp icon off the left edge; no role icon
    if ov.Status then
        SetFile(ov.Status, STATUS_TEX, 0, 0.2734375, 0, 0.5625)
        Place(ov.Status, "CENTER", frame.Portrait or frame, "CENTER", 0, 0, 36, 36)
    end
    if ov.LeaderIcon then Place(ov.LeaderIcon, "TOPLEFT", frame, "TOPLEFT", 0, 0, 16, 16) end
    if ov.GuideIcon then Place(ov.GuideIcon, "TOPLEFT", frame, "TOPLEFT", 0, 0, 19, 19) end
    if ov.PVPIcon then Place(ov.PVPIcon, "TOPLEFT", frame, "TOPLEFT", -9, -15, 32, 32) end
    if ov.Disconnect then Place(ov.Disconnect, "LEFT", frame, "LEFT", -7, -1, 64, 64) end
    Fade(ov.RoleIcon)
    if frame.NotPresentIcon then Place(frame.NotPresentIcon, "LEFT", frame, "RIGHT", -7, 5, 25, 25) end

    -- bars: 70x8 green over 70x8 mana, classic fill, no retail masks
    local hc = frame.HealthBarContainer
    local hb = hc and hc.HealthBar
    if hb then
        Unmask(hb, hc.HealthBarMask)
        hb:SetStatusBarTexture(BAR_TEX)
        hb:SetStatusBarColor(0, 1, 0)
        if layout then
            Place(hc, "TOPLEFT", frame, "TOPLEFT", 47, -12, 70, 8)
            hb:ClearAllPoints()
            hb:SetAllPoints(hc)
        end
    end
    local mb = frame.ManaBar
    if mb then
        Unmask(mb, mb.ManaBarMask)
        mb:SetStatusBarTexture(BAR_TEX)
        ColorManaBar(mb, unit)
        if layout then Place(mb, "TOPLEFT", frame, "TOPLEFT", 47, -21, 70, 8) end
    end
    if layout then frame:SetSize(128, 53) end

    RestylePet(frame.PetFrame, layout)

    if not own.hooked and hooksecurefunc then
        own.hooked = true
        -- Blizzard puts the retail art, masks and anchors back on every
        -- roster update (UpdateMember -> UpdateArt -> ToPlayerArt)
        if type(frame.UpdateArt) == "function" then
            hooksecurefunc(frame, "UpdateArt", function(f)
                if M.mode == "restyled" and not M.inRestyle then
                    M.inRestyle = true
                    M.RestyleMember(f, index)
                    M.inRestyle = nil
                end
            end)
        end
    end
    return true
end

--------------------------------------------------------------------------
-- module interface
--------------------------------------------------------------------------

local function Members()
    local pf = PartyFrame
    if not pf then return {} end
    local list = {}
    for i = 1, MAX_MEMBERS do
        local m = pf["MemberFrame" .. i]
        if m then list[i] = m end
    end
    return list
end

local function IsNative()
    -- Era keeps the classic texture on the overlay itself
    local m = PartyFrame and PartyFrame.MemberFrame1
    if not m then return PartyMemberFrame1 ~= nil end
    return m.PartyMemberOverlay ~= nil and m.PartyMemberOverlay.Texture ~= nil
end

local function IsOurBar(bar)
    for i, m in pairs(Members()) do
        if m.ManaBar == bar then return true, "party" .. i end
    end
    return false
end

local function InstallHooks()
    if M.hooked or not hooksecurefunc then return end
    M.hooked = true
    if UnitFrameManaBar_UpdateType then
        hooksecurefunc("UnitFrameManaBar_UpdateType", function(bar)
            if M.mode ~= "restyled" then return end
            local ours, unit = IsOurBar(bar)
            if ours then
                bar:SetStatusBarTexture(BAR_TEX)
                ColorManaBar(bar, unit)
            end
        end)
    end
end

local function InstallCombatWaiter()
    if M.waiter or not CreateFrame then return end
    M.waiter = CreateFrame("Frame")
    M.waiter:RegisterEvent("PLAYER_REGEN_ENABLED")
    M.waiter:SetScript("OnEvent", function()
        if M.mode ~= "restyled" or not M.pending then return end
        M.pending = nil
        M.RestyleAll()
    end)
end

function M.RestyleAll()
    local did = false
    M.inRestyle = true
    for i, m in pairs(Members()) do
        if M.RestyleMember(m, i) then did = true end
    end
    M.inRestyle = nil
    return did
end

function M:Enable()
    if not PartyFrame and not PartyMemberFrame1 then
        M.mode = "unavailable"
        return
    end
    if IsNative() then
        M.mode = "native"
        return
    end
    InstallCombatWaiter()
    if M.RestyleAll() then
        M.mode = "restyled"
        InstallHooks()
    else
        M.mode = "unavailable"
        ns.Print("party frames: this client's party frame has an unknown layout. Run /cui report all while grouped and send me the report.")
    end
end

function M:Force()
    if IsNative() then
        ns.Print("party frames: this client already draws the classic frames.")
        return
    end
    M.mode = "off"
    M:Enable()
    ns.Print("party frames: re-skinned (%s).", M.mode)
end

function M:Disable()
    M.mode = "off"
    ns.Print("party frames: type /reload to restore Blizzard's party frames.")
end

function M:Status()
    if M.mode == "native" then return "(client already draws the classic party frames)" end
    if M.mode == "restyled" then
        if M.pending then return "(party frames re-skinned; sizes wait for combat to end)" end
        return "(party frames re-skinned to classic art)"
    end
    if M.mode == "unavailable" then return "(unavailable on this client)" end
    return ""
end

ns.RegisterModule("party", M)
