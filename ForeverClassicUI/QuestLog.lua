-- Forever Classic UI - the quest log inside Forever's map window
--
-- Era kept these apart: the quest log was its own parchment book and the
-- map was the map. Forever ships retail's merged window instead
-- (WorldMapFrame with the quest log docked down its right side as
-- QuestMapFrame), and that stays merged - the two cannot be pulled apart
-- without taking the map's own panel handling with them. What changes is
-- how the quest side looks:
--   * retail's quest panel - the QuestLog-frame border, its filigree and
--     its shadow, which hang off QuestScrollFrame.BorderFrame rather than
--     the scroll frame, plus the flat background behind the list - is
--     faded, and an Era panel is drawn over exactly the rect that panel
--     filled. Era's book art is not used here: it is four fixed quarters
--     with the decoration baked in, and stretching it into a tall narrow
--     panel is what made this look wrong before.
--   * the window round both halves is dressed the same way: its flat
--     dark backdrop, the inset line under the title and retail's metal
--     nine-slice and portrait are faded and a second Era panel is drawn
--     behind the lot, so the map side matches the quest side. The title,
--     the close button and the maximise button are left alone.
--   * every quest title gets Era's font and UI-QuestLogTitleHighlight
--     under the mouse in place of retail's flat bar, and the "no quests"
--     text is re-coloured so it reads on parchment.
-- The search box and quest count above the list are Forever's and stay
-- where they are; the map half is untouched.
-- Rule as elsewhere: widget calls and hooksecurefunc only, nothing of
-- ours written into Blizzard's tables, and everything remembered so
-- /cui questlog off puts it back.

local addonName, ns = ...

local M = {mode = "off"}

local TITLE_HIGHLIGHT = "Interface\\QuestFrame\\UI-QuestLogTitleHighlight"
-- retail's QuestLog-frame border sits 3px out either side of the scroll
-- frame, 7 above and 6 below; the Era panel takes exactly that rect
local PAD_L, PAD_T, PAD_R, PAD_B = 3, 7, 3, 6
local PARCHMENT_TEXT = {0.85, 0.78, 0.62}

M.own = setmetatable({}, {__mode = "k"})
local function Own(frame)
    local t = M.own[frame]
    if not t then t = {}; M.own[frame] = t end
    return t
end

local function G(name) return _G[name] end

local function Guard(label, fn)
    return function(...)
        local ok, err = pcall(fn, ...)
        if not ok then ns.errors[#ns.errors + 1] = "questlog " .. label .. ": " .. tostring(err) end
    end
end

--------------------------------------------------------------------------
-- remember / restore
--------------------------------------------------------------------------

local function Remember(region)
    if not region then return end
    local own = Own(region)
    if own.saved then return own.saved end
    local saved = {}
    if region.GetAlpha then saved.alpha = region:GetAlpha() end
    if region.GetFontObject then
        local ok, font = pcall(region.GetFontObject, region)
        if ok then saved.font = font end
    end
    if region.GetTextColor then
        local ok, r, g, b, a = pcall(region.GetTextColor, region)
        if ok and r then saved.color = {r, g, b, a} end
    end
    own.saved = saved
    return saved
end

local function Restore(region)
    local own = M.own[region]
    local saved = own and own.saved
    if not saved then return end
    if saved.alpha and region.SetAlpha then region:SetAlpha(saved.alpha) end
    if saved.font and region.SetFontObject then pcall(region.SetFontObject, region, saved.font) end
    if saved.color and region.SetTextColor then
        pcall(region.SetTextColor, region, saved.color[1], saved.color[2], saved.color[3], saved.color[4])
    end
end

local function Fade(region, on)
    if not region or not region.SetAlpha then return end
    if on then Remember(region); region:SetAlpha(0) else Restore(region) end
end

--------------------------------------------------------------------------
-- the pieces of Forever's window
--------------------------------------------------------------------------

local function Sidebar()
    local f = G("QuestMapFrame")
    if type(f) == "table" and f.GetObjectType then return f end
end

local function MapWindow()
    local f = G("WorldMapFrame")
    if type(f) == "table" and f.GetRegions then return f end
end

local function ScrollFrame()
    local f = G("QuestScrollFrame")
    if type(f) == "table" and f.GetObjectType then return f end
    local side = Sidebar()
    return side and side.QuestsFrame
end

local function BorderFrame()
    local scroll = ScrollFrame()
    local border = scroll and scroll.BorderFrame
    if type(border) == "table" and border.GetRegions then return border end
end

local function Textures(frame, anyLayer)
    local out = {}
    if not frame or not frame.GetRegions then return out end
    local ok, regions = pcall(function() return {frame:GetRegions()} end)
    if not ok then return out end
    for _, region in ipairs(regions) do
        local okType, kind = pcall(function() return region:GetObjectType() end)
        if okType and kind == "Texture" then
            if anyLayer then
                out[#out + 1] = region
            elseif region.GetDrawLayer then
                local okLayer, layer = pcall(region.GetDrawLayer, region)
                if okLayer and (layer == "BACKGROUND" or layer == "BORDER") then out[#out + 1] = region end
            end
        end
    end
    return out
end

local function ShellRegions()
    local out = {}
    for _, r in ipairs(Textures(Sidebar())) do out[#out + 1] = r end
    for _, r in ipairs(Textures(ScrollFrame())) do out[#out + 1] = r end
    -- the border frame is nothing but retail's panel art, so all of it goes
    for _, r in ipairs(Textures(BorderFrame(), true)) do out[#out + 1] = r end
    -- and the window round both halves: its flat dark backdrop, the inset
    -- line under the title, retail's metal nine-slice and the portrait.
    -- The title, the close button and the maximise button hang off the
    -- same border frame and are left alone.
    local map = MapWindow()
    if map then
        for _, r in ipairs(Textures(map)) do out[#out + 1] = r end
        local border = map.BorderFrame
        if type(border) == "table" then
            for _, r in ipairs(Textures(border)) do out[#out + 1] = r end
            for _, key in ipairs({"NineSlice", "PortraitContainer"}) do
                local child = border[key]
                if type(child) == "table" then
                    for _, r in ipairs(Textures(child, true)) do out[#out + 1] = r end
                end
            end
        end
    end
    return out
end

-- the pooled quest rows: anything under the list's Contents with a Text
local function TitleRows()
    local scroll = ScrollFrame()
    local contents = scroll and scroll.Contents
    local out = {}
    if not contents or not contents.GetChildren then return out end
    local ok, children = pcall(function() return {contents:GetChildren()} end)
    if not ok then return out end
    for _, child in ipairs(children) do
        if type(child) == "table" and child.Text and child.Text.SetFontObject then out[#out + 1] = child end
    end
    return out
end

--------------------------------------------------------------------------
-- the Era panel
--------------------------------------------------------------------------

local function BuildPanel(scroll)
    local panel = ns.BuildEraPanel("ForeverClassicUIQuestPanel", scroll)
    if not panel then return nil end
    panel:SetPoint("TOPLEFT", scroll, "TOPLEFT", -PAD_L, PAD_T)
    panel:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", PAD_R, -PAD_B)
    -- the list's Contents sits a level above the scroll frame, so ours
    -- stays level with it and the quest rows draw on top
    local level = scroll.GetFrameLevel and scroll:GetFrameLevel() or 1
    panel:SetFrameLevel(level)
    return panel
end

-- and one behind the whole window, so the map half is framed in Era too
local function BuildMapPanel(map)
    local panel = ns.BuildEraPanel("ForeverClassicUIMapPanel", map)
    if not panel then return nil end
    panel:SetAllPoints(map)
    local level = map.GetFrameLevel and map:GetFrameLevel() or 1
    panel:SetFrameLevel(math.max(level - 1, 0))
    return panel
end

--------------------------------------------------------------------------
-- the quest titles
--------------------------------------------------------------------------

local function SkinRow(row, on)
    local text = row.Text
    if on then
        Remember(text)
        if text.SetFontObject then pcall(text.SetFontObject, text, GameFontNormal) end
    else
        Restore(text)
    end
    local highlight = row.GetHighlightTexture and row:GetHighlightTexture()
    if highlight and highlight.SetTexture then
        local own = Own(row)
        if on then
            if own.highlight == nil then
                local okPath, path = pcall(highlight.GetTexture, highlight)
                own.highlight = (okPath and path) or false
            end
            highlight:SetTexture(TITLE_HIGHLIGHT)
            if highlight.SetBlendMode then highlight:SetBlendMode("ADD") end
        elseif own.highlight ~= nil then
            if own.highlight then highlight:SetTexture(own.highlight) end
            own.highlight = nil
        end
    end
end

local function Rows(on)
    local rows = TitleRows()
    for _, row in ipairs(rows) do SkinRow(row, on) end
    M.rows = #rows
    return #rows
end

--------------------------------------------------------------------------
-- applying and undoing
--------------------------------------------------------------------------

local function Shell(on)
    M.faded = 0
    for _, region in ipairs(ShellRegions()) do
        Fade(region, on)
        M.faded = M.faded + 1
    end
    -- "No quests available" is white on retail's dark panel; on parchment
    -- it wants Era's pale body colour
    local scroll = ScrollFrame()
    local empty = scroll and scroll.EmptyText
    if empty and empty.SetTextColor then
        if on then
            Remember(empty)
            empty:SetTextColor(PARCHMENT_TEXT[1], PARCHMENT_TEXT[2], PARCHMENT_TEXT[3])
        else
            Restore(empty)
        end
    end
end

function M.Apply()
    if M.mode ~= "restyled" then return end
    local side, scroll = Sidebar(), ScrollFrame()
    if not side or not scroll then return end
    if not M.panel then M.panel = BuildPanel(scroll) end
    if not M.panel then return end
    local map = MapWindow()
    if map and not M.mapPanel then M.mapPanel = BuildMapPanel(map) end
    if side.IsShown and side:IsShown() then
        Shell(true)
        M.panel:Show()
        if M.mapPanel then M.mapPanel:Show() end
        Rows(true)
    else
        M.panel:Hide()
        if M.mapPanel then M.mapPanel:Hide() end
    end
end

local function ApplyLater()
    M.Apply()
    if C_Timer and C_Timer.After then C_Timer.After(0, Guard("later", M.Apply)) end
end

local function Undo()
    Shell(false)
    Rows(false)
    if M.panel then M.panel:Hide() end
    if M.mapPanel then M.mapPanel:Hide() end
end

local function HookMethod(frame, name)
    if frame and type(frame[name]) == "function" then
        hooksecurefunc(frame, name, Guard(name, ApplyLater))
    end
end

local function Hook()
    if M.hooked then return end
    local side = Sidebar()
    if not side or not hooksecurefunc then return end
    if side.HookScript then
        side:HookScript("OnShow", Guard("OnShow", ApplyLater))
        side:HookScript("OnHide", Guard("OnHide", function()
            if M.panel then M.panel:Hide() end
            if M.mapPanel then M.mapPanel:Hide() end
        end))
    end
    -- the rows are pooled: Blizzard hands a row to a different quest on
    -- every refresh, so ours runs again after each one
    HookMethod(side, "Refresh")
    HookMethod(ScrollFrame(), "Update")
    if type(QuestMapFrame_UpdateAll) == "function" then
        hooksecurefunc("QuestMapFrame_UpdateAll", Guard("QuestMapFrame_UpdateAll", ApplyLater))
    end
    if type(QuestLogQuests_Update) == "function" then
        hooksecurefunc("QuestLogQuests_Update", Guard("QuestLogQuests_Update", ApplyLater))
    end
    if not M.events and CreateFrame then
        local ev = CreateFrame("Frame")
        for _, e in ipairs({"QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED", "PLAYER_ENTERING_WORLD"}) do
            pcall(ev.RegisterEvent, ev, e)
        end
        ev:SetScript("OnEvent", Guard("event", function()
            local s = Sidebar()
            if s and s.IsShown and s:IsShown() then ApplyLater() end
        end))
        M.events = ev
    end
    M.hooked = true
end

--------------------------------------------------------------------------
-- module interface
--------------------------------------------------------------------------

local function WatchForFrame()
    if M.watcher or not CreateFrame then return end
    local watcher = CreateFrame("Frame")
    watcher:RegisterEvent("ADDON_LOADED")
    pcall(watcher.RegisterEvent, watcher, "PLAYER_ENTERING_WORLD")
    watcher:SetScript("OnEvent", function()
        if M.mode ~= "waiting" then return end
        if Sidebar() then
            if ns.SafeCall("questlog", M.Enable, M) and M.mode == "restyled" then
                watcher:UnregisterAllEvents()
            end
        end
    end)
    M.watcher = watcher
end

function M:Enable()
    -- a real classic client already has Era's own QuestLogFrame
    if G("QuestLogFrame") and not G("QuestMapFrame") then
        self.mode = "native"
        return
    end
    if not Sidebar() then
        self.mode = "waiting"
        WatchForFrame()
        return
    end
    self.missingArt = ns.EraPanelArtMissing and ns.EraPanelArtMissing() or {}
    self.mode = "restyled"
    Hook()
    M.Apply()
end

function M:Force() if self.mode == "restyled" then M.Apply() end end

function M:Disable()
    local was = self.mode
    self.mode = "off"
    if was == "restyled" then Undo() end
end

function M:Status()
    if self.mode == "restyled" then
        local s = ("Era panels over Forever's map window and its quest list (%d retail pieces faded), %d quest titles in Era's font"):format(self.faded or 0, self.rows or 0)
        if self.missingArt and #self.missingArt > 0 then
            s = s .. " (art missing: " .. table.concat(self.missingArt, ", ") .. ")"
        end
        return s .. " (the map itself, the title and the buttons are left alone)"
    elseif self.mode == "native" then
        return "classic client, Era's own quest log"
    elseif self.mode == "waiting" then
        return "waiting for Forever's map quest log (QuestMapFrame) to exist"
    end
    return "off"
end

ns.RegisterModule("questlog", M)
