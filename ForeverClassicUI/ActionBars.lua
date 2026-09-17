-- Forever Classic UI - main action bar art
--
-- Forever keeps the gryphon end caps (its Camelot flavor restores them) but
-- frames the main bar with the retail "UI-HUD-ActionBar-Frame" border and
-- nothing under the buttons. Classic had the dwarf-stone bar art running
-- under the buttons between the gryphons. This hides the retail border and
-- lays the classic bar texture under the main action bar; end caps are
-- forced visible.

local addonName, ns = ...

local M = {mode = "off"}

local BAR_ART = "Interface\\MainMenuBar\\UI-MainMenuBar-Dwarf"

local function Hide(region)
    if region then
        if region.Hide then region:Hide() end
        if region.SetAlpha then region:SetAlpha(0) end
    end
end

function M.Apply()
    local bar = MainActionBar or MainMenuBar
    if not bar or not bar.CreateTexture then return false end
    if bar.BorderArt then Hide(bar.BorderArt) end

    if not M.art then
        local art = CreateFrame("Frame", "ForeverClassicUIBarArt", bar)
        art:SetFrameLevel(math.max((bar:GetFrameLevel() or 1) - 1, 0))
        art:SetPoint("TOPLEFT", bar, "TOPLEFT", -8, 8)
        art:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 8, -8)
        -- the classic bar tile is 256 wide; three tiles cover a 12-button bar
        art.tiles = {}
        for i = 1, 3 do
            local t = art:CreateTexture(nil, "BACKGROUND")
            t:SetTexture(BAR_ART)
            t:SetTexCoord(0, 1, 0, 43 / 64)
            t:SetHeight(43)
            art.tiles[i] = t
        end
        art.tiles[1]:SetPoint("BOTTOMLEFT", art, "BOTTOMLEFT", 0, 0)
        art.tiles[1]:SetPoint("BOTTOMRIGHT", art, "BOTTOM", 0, 0)
        art.tiles[2]:SetPoint("BOTTOMLEFT", art, "BOTTOM", 0, 0)
        art.tiles[2]:SetPoint("BOTTOMRIGHT", art, "BOTTOMRIGHT", 0, 0)
        art.tiles[3]:Hide()
        M.art = art
    end
    M.art:Show()

    local caps = bar.EndCaps
    if caps then
        for _, key in ipairs({"LeftEndCap", "RightEndCap"}) do
            local cap = caps[key]
            if cap then
                if cap.SetVisibilitySetting then
                    pcall(cap.SetVisibilitySetting, cap, true)
                elseif cap.Show then
                    cap:Show()
                end
            end
        end
    end
    return true
end

local function IsNative()
    return MainMenuBarArtFrame ~= nil and MainActionBar == nil
end

function M:Enable()
    if IsNative() then
        M.mode = "native"
        return
    end
    if not (MainActionBar or MainMenuBar) then
        M.mode = "unavailable"
        return
    end
    if M.Apply() then
        M.mode = "restyled"
        if hooksecurefunc and not M.hooked and EditModeManagerFrame and
            EditModeManagerFrame.ExitEditMode then
            M.hooked = true
            hooksecurefunc(EditModeManagerFrame, "ExitEditMode", function()
                if M.mode == "restyled" then M.Apply() end
            end)
        end
    else
        M.mode = "unavailable"
    end
end

function M:Force()
    M:Enable()
    ns.Print("action bars: classic bar art %s.", M.mode)
end

function M:Disable()
    if M.art then M.art:Hide() end
    M.mode = "off"
    ns.Print("action bars: type /reload to restore Blizzard's bar art.")
end

function M:Status()
    if M.mode == "native" then return "(client already draws the classic bar)" end
    if M.mode == "restyled" then return "(classic bar art under the main bar, gryphons on)" end
    if M.mode == "unavailable" then return "(unavailable on this client)" end
    return ""
end

ns.RegisterModule("actionbars", M)
