-- Forever Classic UI - cast bars
--
-- The player cast bar and the target's spell bar share one Lua mixin on every
-- client; only the XML art differs. Classic clients build them from the old
-- UI-CastingBar-Border / -Flash / -Spark textures and flag the bar with
-- classicStyleCastBar = true. Retail-style clients build the modern
-- atlas-based bar (glow, flakes, text box...) with the flag off.
--
-- We flip the flag (so Blizzard's own code uses the classic fill colors and
-- static spark), hide the modern-only art, and put the classic textures and
-- anchors back - the same values the classic XML uses.

local addonName, ns = ...

local M = {mode = "off", bars = {}}

local ART = "Interface\\CastingBar\\"
local MODERN_ONLY = {
    "DropShadow", "TextBorder", "InterruptGlow", "ChargeGlow", "EnergyGlow",
    "Flakes01", "Flakes02", "Flakes03", "BaseGlow", "WispGlow", "Sparkles01",
    "Sparkles02", "Shine", "StandardGlow", "CraftGlow", "ChannelShadow",
    "ChargeFlash"
}

local function SetFile(region, path)
    if region and region.SetTexture then
        region:SetTexture(path)
        if region.SetTexCoord then region:SetTexCoord(0, 1, 0, 1) end
    end
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

-- look: "CLASSIC" = big player bar, "UNITFRAME" = small bar under a unit frame
function M.Restyle(bar, look)
    if not bar then return false end
    local inner = M.restyling
    M.restyling = true

    bar.classicStyleCastBar = true
    bar.playCastFX = false

    for _, key in ipairs(MODERN_ONLY) do
        local r = bar[key]
        if r then
            if r.Hide then r:Hide() end
            if r.SetAlpha then r:SetAlpha(0) end
        end
    end

    -- the modern bar masks its fill to a rounded shape; drop that
    local fill = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
    if fill and bar.BorderMask and fill.RemoveMaskTexture then
        pcall(fill.RemoveMaskTexture, fill, bar.BorderMask)
    end
    if bar.SetStatusBarTexture then
        bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    end
    if bar.SetStatusBarColor then bar:SetStatusBarColor(1.0, 0.7, 0.0) end

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
            SetFile(flash, ART .. "UI-CastingBar-Flash-Small")
            flash:ClearAllPoints()
            flash:SetHeight(56)
            flash:SetPoint("TOPLEFT", bar, "TOPLEFT", -23, 23)
            flash:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 23, 23)
        end
        if spark then
            SetFile(spark, ART .. "UI-CastingBar-Spark")
            spark:SetSize(32, 32)
            spark.offsetY = 0
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
            SetFile(flash, ART .. "UI-CastingBar-Flash")
            flash:ClearAllPoints()
            flash:SetSize(256, 64)
            flash:SetPoint("TOP", bar, "TOP", 0, 28)
        end
        if spark then
            SetFile(spark, ART .. "UI-CastingBar-Spark")
            spark:SetSize(32, 32)
            spark.offsetY = 2
        end
        if text then
            text:ClearAllPoints()
            text:SetSize(185, 16)
            text:SetPoint("TOP", bar, "TOP", 0, 5)
            if text.SetFontObject then text:SetFontObject("GameFontHighlight") end
            text:Show()
        end
    end

    if flash then
        if flash.SetVertexColor then flash:SetVertexColor(1.0, 0.7, 0.0) end
        if flash.SetBlendMode then flash:SetBlendMode("ADD") end
    end
    if spark and spark.SetBlendMode then spark:SetBlendMode("ADD") end
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
    if hooksecurefunc and not bar.classicUIHooked then
        bar.classicUIHooked = true
        -- Blizzard (edit mode, unit frame layout) may re-apply its look
        -- later; re-skin after it does
        hooksecurefunc(bar, "SetLook", function(self, newLook)
            if M.restyling or M.mode == "off" then return end
            M.Restyle(self, newLook == "UNITFRAME" and "UNITFRAME" or
                          "CLASSIC")
        end)
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
