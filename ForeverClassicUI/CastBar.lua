-- Forever Classic UI - cast bars
--
-- The player cast bar and the target's spell bar share one Lua mixin on every
-- client; only the XML art differs. Classic clients build them from the old
-- UI-CastingBar-Border / -Flash / -Spark textures and flag the bar with
-- classicStyleCastBar = true. Retail-style clients (Forever) build the modern
-- atlas-based bar (glow, flakes, text box...) with the flag off.
--
-- Forever protects enemy cast times with "secret values", so the bar's Lua
-- tables must stay untouched: writing the classic flag into the frame would
-- taint Blizzard's code and make it error on the next enemy cast. Instead the
-- classic textures and anchors are applied with plain widget calls, the
-- modern-only art is left without anchors (so it never draws, whatever
-- Blizzard's animations do to it), and hooksecurefunc re-applies the classic
-- fill, flash and spark every time Blizzard's modern code sets its atlases.

local addonName, ns = ...

local M = {mode = "off", bars = {}, hooked = {}}

local ART = "Interface\\CastingBar\\"
local FILL = "Interface\\TargetingFrame\\UI-StatusBar"
local MODERN_ONLY = {
    "DropShadow", "TextBorder", "InterruptGlow", "ChargeGlow", "EnergyGlow",
    "Flakes01", "Flakes02", "Flakes03", "BaseGlow", "WispGlow", "Sparkles01",
    "Sparkles02", "Shine", "StandardGlow", "CraftGlow", "CraftingGlow",
    "ChannelShadow", "ChargeFlash", "ChannelGlow", "StandardFinish"
}
local CLASSIC_YELLOW = {1.0, 0.7, 0.0}
local CLASSIC_GREEN = {0.0, 1.0, 0.0}

local function SetFile(region, path)
    if region and region.SetTexture then
        region:SetTexture(path)
        if region.SetTexCoord then region:SetTexCoord(0, 1, 0, 1) end
    end
end

-- a region with no anchors has no rectangle and is never drawn
local function Unanchor(region)
    if not region then return end
    if region.ClearAllPoints then region:ClearAllPoints() end
    if region.SetAlpha then region:SetAlpha(0) end
    if region.Hide then region:Hide() end
end

local function IsClassicAlready(bar)
    if not bar or not bar.classicStyleCastBar then return false end
    local border = bar.Border
    local tex = border and border.GetTexture and border:GetTexture()
    -- classic XML uses the file texture; GetTexture returns its path on some
    -- clients and its file id on others (Era 1.15.9 returns the id)
    if type(tex) == "string" then
        return tex:lower():find("castingbar") ~= nil
    end
    if type(tex) == "number" and GetFileIDFromPath then
        return tex == GetFileIDFromPath(ART .. "UI-CastingBar-Border")
    end
    return false
end

-- Forever hands enemy cast bars secret values: bar.barType cannot be used
-- as a table key and the isFull flag cannot be used in a condition from
-- addon code. Both raise an error the C layer throws straight past pcall,
-- so a secret value has to be recognised before it is used, never caught
-- afterwards. issecretvalue is safe to call on one.
local function Secret(v)
    if v == nil or not issecretvalue then return false end
    local ok, secret = pcall(issecretvalue, v)
    return (not ok) or secret == true
end
M.Secret = Secret

-- classic fill: UI-StatusBar coloured by bar type (yellow while casting,
-- green when full/channeling), the same colours Blizzard's classic path
-- uses. When either value is secret the classic yellow stands in: it is
-- what Era shows for the whole cast.
local function FillColor(bar, isFull)
    local barType = bar and bar.barType
    local typeSafe, fullSafe = not Secret(barType), not Secret(isFull)
    if typeSafe and fullSafe and barType ~= nil and CastingBarTypeInfo then
        local ok, r, g, b = pcall(function()
            local info = CastingBarTypeInfo[barType]
            local color = isFull and info.classicFullColor or info.classicFillColor
            return color:GetRGB()
        end)
        if ok and r then return r, g, b end
    end
    -- a secret flag cannot be a condition either: yellow, as Era casts are
    local c = (fullSafe and isFull) and CLASSIC_GREEN or CLASSIC_YELLOW
    return c[1], c[2], c[3]
end

local function ApplyFill(bar, isFull)
    if not bar.SetStatusBarTexture then return end
    bar:SetStatusBarTexture(FILL)
    bar:SetStatusBarColor(FillColor(bar, isFull))
    local fill = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
    if fill and bar.BorderMask and fill.RemoveMaskTexture then
        pcall(fill.RemoveMaskTexture, fill, bar.BorderMask)
    end
end

local function ApplyFlash(flash)
    if not flash then return end
    SetFile(flash, M.flashFile[flash] or ART .. "UI-CastingBar-Flash")
    if flash.SetVertexColor then flash:SetVertexColor(1.0, 0.7, 0.0) end
    if flash.SetBlendMode then flash:SetBlendMode("ADD") end
end

local function ApplySpark(spark)
    if not spark then return end
    SetFile(spark, ART .. "UI-CastingBar-Spark")
    spark:SetSize(32, 32)
    if spark.SetBlendMode then spark:SetBlendMode("ADD") end
end

M.flashFile = setmetatable({}, {__mode = "k"})

-- look: "CLASSIC" = big player bar, "UNITFRAME" = small bar under a unit frame
function M.Restyle(bar, look)
    if not bar then return false end
    local inner = M.restyling
    M.restyling = true

    for _, key in ipairs(MODERN_ONLY) do Unanchor(bar[key]) end
    if CastingBarTypeInfo then
        for _, info in pairs(CastingBarTypeInfo) do
            if info.sparkFx then Unanchor(bar[info.sparkFx]) end
        end
    end

    local bg = bar.Background
    if bg and bg.SetColorTexture then
        if bg.SetAtlas then pcall(bg.SetAtlas, bg, nil) end
        bg:SetColorTexture(0, 0, 0, 0.5)
        bg:ClearAllPoints()
        bg:SetAllPoints(bar)
    end

    local border, shield, flash, spark, text, icon = bar.Border,
                                                     bar.BorderShield,
                                                     bar.Flash, bar.Spark,
                                                     bar.Text, bar.Icon

    if look == "UNITFRAME" then
        bar:SetSize(150, 10)
        if border then
            SetFile(border, ART .. "UI-CastingBar-Border-Small")
            border:ClearAllPoints()
            border:SetHeight(56)
            border:SetPoint("TOPLEFT", bar, "TOPLEFT", -23, 23)
            border:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 23, 23)
            border:Show()
        end
        if shield then
            SetFile(shield, ART .. "UI-CastingBar-Small-Shield")
            shield:ClearAllPoints()
            shield:SetHeight(56)
            shield:SetPoint("TOPLEFT", bar, "TOPLEFT", -28, 23)
            shield:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 18, 23)
        end
        if flash then
            M.flashFile[flash] = ART .. "UI-CastingBar-Flash-Small"
            flash:ClearAllPoints()
            flash:SetHeight(56)
            flash:SetPoint("TOPLEFT", bar, "TOPLEFT", -23, 23)
            flash:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 23, 23)
        end
        if text then
            text:ClearAllPoints()
            text:SetHeight(16)
            text:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 4)
            text:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 4)
            if text.SetFontObject then text:SetFontObject("SystemFont_Shadow_Small") end
            text:Show()
        end
    else
        bar:SetSize(195, 13)
        if border then
            SetFile(border, ART .. "UI-CastingBar-Border")
            border:ClearAllPoints()
            border:SetSize(256, 64)
            border:SetPoint("TOP", bar, "TOP", 0, 28)
            border:Show()
        end
        if shield then
            SetFile(shield, ART .. "UI-CastingBar-Small-Shield")
            shield:ClearAllPoints()
            shield:SetSize(256, 64)
            shield:SetPoint("TOP", bar, "TOP", 0, 28)
        end
        if flash then
            M.flashFile[flash] = ART .. "UI-CastingBar-Flash"
            flash:ClearAllPoints()
            flash:SetSize(256, 64)
            flash:SetPoint("TOP", bar, "TOP", 0, 28)
        end
        if text then
            text:ClearAllPoints()
            text:SetSize(185, 16)
            text:SetPoint("TOP", bar, "TOP", 0, 5)
            if text.SetFontObject then text:SetFontObject("GameFontHighlight") end
            text:Show()
        end
    end

    ApplyFlash(flash)
    ApplySpark(spark)
    ApplyFill(bar, false)
    if icon then
        icon:ClearAllPoints()
        icon:SetSize(18, 18)
        icon:SetPoint("RIGHT", bar, "LEFT", -3.5, 1)
    end

    M.restyling = inner
    return true
end

local function Attach(bar, look)
    if not bar then return end
    M.bars[bar] = look
    M.Restyle(bar, look)
    if hooksecurefunc and not M.hooked[bar] then
        M.hooked[bar] = true
        -- Blizzard (edit mode, unit frame layout) re-applies its look later;
        -- re-skin after it does
        if bar.SetLook then
            hooksecurefunc(bar, "SetLook", function(self, newLook)
                if M.restyling or M.mode == "off" then return end
                M.Restyle(self, newLook == "UNITFRAME" and "UNITFRAME" or "CLASSIC")
            end)
        end
        -- every cast: modern fill atlas -> classic fill
        if bar.UpdateBarFillTexture then
            hooksecurefunc(bar, "UpdateBarFillTexture", function(self, isFull)
                if M.mode == "off" then return end
                ApplyFill(self, isFull)
            end)
        end
        -- finish/interrupt: modern glow atlas on the flash -> classic flash
        if bar.Flash and bar.Flash.SetAtlas then
            hooksecurefunc(bar.Flash, "SetAtlas", function(self)
                if M.mode == "off" then return end
                ApplyFlash(self)
            end)
        end
        -- each cast: modern pip atlas on the spark -> classic spark
        if bar.Spark and bar.Spark.SetAtlas then
            hooksecurefunc(bar.Spark, "SetAtlas", function(self)
                if M.mode == "off" then return end
                ApplySpark(self)
            end)
        end
    end
end

local function Targets()
    return {
        {PlayerCastingBarFrame, "CLASSIC"},
        {TargetFrameSpellBar, "UNITFRAME"},
        {FocusFrameSpellBar, "UNITFRAME"}
    }
end

function M:Enable()
    local player = PlayerCastingBarFrame
    if not player then
        M.mode = "unavailable"
        ns.Print("castbar: no PlayerCastingBarFrame on this client. Run /cui probe and send me the report.")
        return
    end
    if IsClassicAlready(player) then
        M.mode = "native"
        return
    end
    M.mode = "restyled"
    for _, t in ipairs(Targets()) do Attach(t[1], t[2]) end
end

-- testing aid: re-skin regardless of what the client already uses
function M:Force()
    M.mode = "restyled"
    local n = 0
    for _, t in ipairs(Targets()) do
        if t[1] then
            Attach(t[1], t[2])
            n = n + 1
        end
    end
    ns.Print("castbar: re-skinned %d bar(s).", n)
end

function M:Disable()
    M.mode = "off"
    ns.Print("castbar: type /reload to restore Blizzard's cast bar art.")
end

function M:Status()
    if M.mode == "native" then
        return "(client already draws the classic cast bar)"
    elseif M.mode == "restyled" then
        return "(re-skinned to classic art)"
    elseif M.mode == "unavailable" then
        return "(unavailable on this client)"
    end
    return ""
end

ns.RegisterModule("castbar", M)
