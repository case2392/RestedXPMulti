-- Forever Classic UI - minimap
--
-- Forever's minimap is the retail one with a Camelot skin: a 198px map in
-- a large atlas frame, a nine-slice header with the zone name, and a
-- day/night indicator. Classic had a 140px round map, the ring border from
-- UI-Minimap-Border, and the zone name on a 176x28 strip above it. Sizes
-- and art are moved over; Blizzard keeps driving buttons and text.

local addonName, ns = ...

local M = {mode = "off"}

local BORDER = "Interface\\Minimap\\UI-Minimap-Border"

local function Hide(region)
    if region then
        if region.Hide then region:Hide() end
        if region.SetAlpha then region:SetAlpha(0) end
    end
end

function M.Apply()
    local cluster = MinimapCluster
    local map = Minimap
    if not cluster or not map then return false end
    M.inApply = true

    -- round 140px map
    map:SetSize(140, 140)
    if map.SetMaskTexture then
        pcall(map.SetMaskTexture, map, "Interface\\CharacterFrame\\TempPortraitAlphaMask")
    end
    if cluster.MinimapContainer then cluster.MinimapContainer:SetSize(140, 140) end
    if MinimapBackdrop then MinimapBackdrop:SetSize(192, 192) end

    -- ring border (the classic MinimapBorder sat 8 left / 24 down of the map)
    local ring = MinimapCompassTexture
    if ring then
        ring:SetTexture(BORDER)
        ring:SetTexCoord(0.25, 1.0, 0.125, 0.875)
        ring:ClearAllPoints()
        ring:SetSize(192, 192)
        ring:SetPoint("CENTER", map, "CENTER", -8, -24)
        ring:Show()
    end
    Hide(MinimapCompassTextureUnderlay)

    -- header strip with the zone name
    local top = cluster.BorderTop
    if top then
        if top.SetAlpha then top:SetAlpha(0) end -- nine-slice pieces stay for layout
        if not M.header then
            local tex = cluster:CreateTexture(nil, "ARTWORK")
            tex:SetTexture(BORDER)
            tex:SetTexCoord(0.3125, 1.0, 0.0, 0.109375)
            tex:SetSize(176, 28)
            M.header = tex
        end
        M.header:ClearAllPoints()
        M.header:SetPoint("CENTER", top, "CENTER", 0, 0)
        M.header:Show()
    end

    -- classic had no day/night dial
    if cluster.DielFrame then Hide(cluster.DielFrame) end

    M.inApply = false
    return true
end

local function IsNative()
    return MinimapBorder ~= nil and not (MinimapCluster and MinimapCluster.MinimapContainer and MinimapCompassTexture and MinimapCompassTexture.GetAtlas and MinimapCompassTexture:GetAtlas())
end

function M:Enable()
    if not Minimap or not MinimapCluster then
        M.mode = "unavailable"
        return
    end
    if IsNative() then
        M.mode = "native"
        return
    end
    if M.Apply() then
        M.mode = "restyled"
        if CreateFrame and not M.watcher then
            M.watcher = CreateFrame("Frame")
            M.watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
            M.watcher:RegisterEvent("CVAR_UPDATE")
            M.watcher:SetScript("OnEvent", function(_, event, name)
                if M.mode ~= "restyled" or M.inApply then return end
                if event == "CVAR_UPDATE" and name ~= "rotateMinimap" then return end
                M.Apply()
            end)
        end
    else
        M.mode = "unavailable"
    end
end

function M:Force()
    M:Enable()
    ns.Print("minimap: classic minimap %s.", M.mode)
end

function M:Disable()
    if M.header then M.header:Hide() end
    M.mode = "off"
    ns.Print("minimap: type /reload to restore Blizzard's minimap.")
end

function M:Status()
    if M.mode == "native" then return "(client already draws the classic minimap)" end
    if M.mode == "restyled" then return "(140px round map, classic ring and header)" end
    if M.mode == "unavailable" then return "(unavailable on this client)" end
    return ""
end

ns.RegisterModule("minimap", M)
