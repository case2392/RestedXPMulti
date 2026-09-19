-- Forever Classic UI - the quest log inside Forever's map window
--
-- Era kept these apart: the quest log was its own 384x512 parchment book
-- (QuestLogFrame: a 300x93 list of quest titles up top, the selected
-- quest's text in a 300x260 scroll below it), and the map was the map.
-- Forever ships retail's merged window instead - WorldMapFrame with the
-- quest log docked down its left side as QuestMapFrame - and one addon
-- cannot pull the two apart without taking the map's own panel handling
-- with it. So this part reskins the quest log side in place:
--   * retail's quest panel (the QuestLog-frame border, its filigree and
--     its shadow, which hang off QuestScrollFrame.BorderFrame, plus the
--     flat background behind the list) is faded, and Era's quest log
--     parchment (UI-QuestLog-TopLeft and the three pieces that go with
--     it, stretched over exactly the rect that panel filled) is drawn in
--     its place. The search box and quest count above it are Forever's
--     and are left where they are;
--   * every quest title in the list gets Era's font and Era's
--     UI-QuestLogTitleHighlight under the mouse, in place of retail's
--     flat highlight bar, and the "no quests" text is re-coloured to
--     Era's parchment brown so it can be read on the new background;
--   * the map itself is left alone - it is the same map either way.
-- Rule as elsewhere: widget calls and hooksecurefunc only, nothing of
-- ours written into Blizzard's tables (M.own holds what hangs on them),
-- and everything we change is remembered so /cui questlog off puts it
-- back.

local addonName, ns = ...

local M = {mode = "off"}

local QF = "Interface\\QuestFrame\\"
local ART = {
    topLeft = QF .. "UI-QuestLog-TopLeft",
    topRight = QF .. "UI-QuestLog-TopRight",
    bottomLeft = QF .. "UI-QuestLog-BotLeft",
    bottomRight = QF .. "UI-QuestLog-BotRight",
    titleHighlight = QF .. "UI-QuestLogTitleHighlight"
}
M.ART = ART

-- Era's book is 384 wide (a 256 left page and a 128 right one) and 512
-- tall (256 top, 256 bottom); the four pieces keep those fractions at
-- whatever size Forever's quest panel happens to be
local ART_LEFT, ART_TOP = 256 / 384, 256 / 512
-- retail's QuestLog-frame border sits 3px out either side of the scroll
-- frame, 7px above it and 6px below; the parchment takes exactly that rect
local PAD_L, PAD_T, PAD_R, PAD_B = 3, 7, 3, 6
-- Era's body text on parchment
local PARCHMENT_TEXT = {0.25, 0.12, 0}

M.own = setmetatable({}, {__mode = "k"})
local function Own(frame)
    local t = M.own[frame]
    if not t then t = {}; M.own[frame] = t end
    return t
end

local function G(name) return _G[name] end

local function Str(key, fallback)
    local v = _G[key]
    if type(v) == "string" and v ~= "" then return v end
    return fallback
end

local function HasFile(path)
    if not GetFileIDFromPath then return true end
    local ok, id = pcall(GetFileIDFromPath, path)
    return ok and id ~= nil
end

local function Guard(label, fn)
    return function(...)
        local ok, err = pcall(fn, ...)
        if not ok then ns.errors[#ns.errors + 1] = "questlog " .. label .. ": " .. tostring(err) end
    end
end

--------------------------------------------------------------------------
-- remember / restore, so switching the part off is a clean undo
--------------------------------------------------------------------------

local function Remember(region)
    if not region then return nil end
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
    if on then
        Remember(region)
        region:SetAlpha(0)
    else
        Restore(region)
    end
end

--------------------------------------------------------------------------
-- finding the pieces of Forever's window
--------------------------------------------------------------------------

local function Sidebar()
    local f = G("QuestMapFrame")
    if type(f) == "table" and f.GetObjectType then return f end
end

local function ScrollFrame()
    local f = G("QuestScrollFrame")
    if type(f) == "table" and f.GetObjectType then return f end
    local side = Sidebar()
    return side and side.QuestsFrame
end

-- the pooled quest rows live under the scroll frame's Contents; anything
-- with a Text font string is a title Era would have drawn in its book
local function TitleRows()
    local scroll = ScrollFrame()
    local contents = scroll and scroll.Contents
    if not contents or not contents.GetChildren then return {} end
    local out = {}
    local ok, children = pcall(function() return {contents:GetChildren()} end)
    if not ok then return out end
    for _, child in ipairs(children) do
        if type(child) == "table" and child.Text and child.Text.SetFontObject then
            out[#out + 1] = child
        end
    end
    return out
end

-- retail's quest panel art hangs off a frame of its own inside the scroll
-- frame, so fading the scroll frame's own regions is not enough
local function BorderFrame()
    local scroll = ScrollFrame()
    local border = scroll and scroll.BorderFrame
    if type(border) == "table" and border.GetRegions then return border end
end

local function Textures(frame, anyLayer)
    if not frame or not frame.GetRegions then return {} end
    local out = {}
    local ok, regions = pcall(function() return {frame:GetRegions()} end)
    if not ok then return out end
    for _, region in ipairs(regions) do
        local okType, kind = pcall(function() return region:GetObjectType() end)
        if okType and kind == "Texture" then
            if anyLayer then
                out[#out + 1] = region
            elseif region.GetDrawLayer then
                local okLayer, layer = pcall(region.GetDrawLayer, region)
                if okLayer and (layer == "BACKGROUND" or layer == "BORDER") then
                    out[#out + 1] = region
                end
            end
        end
    end
    return out
end

-- the retail panel: the flat background behind the list, the sidebar's own
-- background, and every piece of the QuestLog-frame border
local function ShellRegions()
    local out = {}
    for _, region in ipairs(Textures(Sidebar())) do out[#out + 1] = region end
    for _, region in ipairs(Textures(ScrollFrame())) do out[#out + 1] = region end
    -- the border frame is nothing but retail's panel art, so all of it goes
    for _, region in ipairs(Textures(BorderFrame(), true)) do out[#out + 1] = region end
    return out
end

--------------------------------------------------------------------------
-- our parchment: Era's four book pieces behind the sidebar
--------------------------------------------------------------------------

-- the parchment takes the rect retail's panel border filled, so it lines up
-- with the list and leaves the search box and quest count above it alone
local function BuildBook(scroll)
    local book = CreateFrame("Frame", "ForeverClassicUIQuestBook", scroll)
    book:SetPoint("TOPLEFT", scroll, "TOPLEFT", -PAD_L, PAD_T)
    book:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", PAD_R, -PAD_B)
    -- the list's own Contents frame sits a level above the scroll frame, so
    -- ours stays level with the scroll frame and the quest rows draw over it
    local level = scroll.GetFrameLevel and scroll:GetFrameLevel() or 1
    book:SetFrameLevel(level)
    local function Piece(path, point)
        local t = book:CreateTexture(nil, "BACKGROUND")
        t:SetTexture(path)
        t:SetPoint(point, book, point, 0, 0)
        return t
    end
    book.topLeft = Piece(ART.topLeft, "TOPLEFT")
    book.topRight = Piece(ART.topRight, "TOPRIGHT")
    book.bottomLeft = Piece(ART.bottomLeft, "BOTTOMLEFT")
    book.bottomRight = Piece(ART.bottomRight, "BOTTOMRIGHT")
    book:Hide()
    return book
end

-- Era's pieces split the book two thirds / one third across and in half
-- down; the panel is whatever size Forever made it, so they are sized from
-- it every time it changes
local function SizeBook(book, scroll)
    if not book or not scroll or not scroll.GetSize then return end
    local ok, sw, sh = pcall(scroll.GetSize, scroll)
    if not ok or not sw or sw <= 0 or sh <= 0 then return end
    local w, h = sw + PAD_L + PAD_R, sh + PAD_T + PAD_B
    local lw, rw = math.floor(w * ART_LEFT + 0.5), math.ceil(w * (1 - ART_LEFT))
    local th, bh = math.floor(h * ART_TOP + 0.5), math.ceil(h * (1 - ART_TOP))
    book.topLeft:SetSize(lw, th)
    book.topRight:SetSize(rw, th)
    book.bottomLeft:SetSize(lw, bh)
    book.bottomRight:SetSize(rw, bh)
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
    -- Era's highlight is a parchment-coloured bar, not retail's grey one
    local highlight = row.GetHighlightTexture and row:GetHighlightTexture()
    if highlight and highlight.SetTexture then
        local own = Own(row)
        if on then
            if own.highlight == nil then
                local okPath, path = pcall(highlight.GetTexture, highlight)
                own.highlight = (okPath and path) or false
            end
            highlight:SetTexture(ART.titleHighlight)
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
    -- "No quests available" is white, which is unreadable on parchment
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
    local side = Sidebar()
    local scroll = ScrollFrame()
    if not side or not scroll then return end
    if not M.book then M.book = BuildBook(scroll) end
    local shown = side.IsShown and side:IsShown()
    if shown then
        Shell(true)
        SizeBook(M.book, scroll)
        M.book:Show()
        Rows(true)
    else
        M.book:Hide()
    end
end

local function ApplyLater()
    M.Apply()
    if C_Timer and C_Timer.After then C_Timer.After(0, Guard("later", M.Apply)) end
end

local function Undo()
    Shell(false)
    Rows(false)
    if M.book then M.book:Hide() end
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
        side:HookScript("OnHide", Guard("OnHide", function() if M.book then M.book:Hide() end end))
        side:HookScript("OnSizeChanged", Guard("OnSizeChanged", function()
            if M.mode == "restyled" and M.book then SizeBook(M.book, ScrollFrame()) end
        end))
    end
    local scroll = ScrollFrame()
    if scroll and scroll.HookScript then
        scroll:HookScript("OnSizeChanged", Guard("scroll OnSizeChanged", function()
            if M.mode == "restyled" and M.book then SizeBook(M.book, ScrollFrame()) end
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
    self.missingArt = {}
    for _, key in ipairs({"topLeft", "topRight", "bottomLeft", "bottomRight", "titleHighlight"}) do
        if not HasFile(ART[key]) then self.missingArt[#self.missingArt + 1] = ART[key]:match("[^\\]+$") end
    end
    self.mode = "restyled"
    Hook()
    M.Apply()
end

function M:Force()
    if self.mode == "restyled" then M.Apply() end
end

function M:Disable()
    local was = self.mode
    self.mode = "off"
    if was == "restyled" then Undo() end
end

function M:Status()
    if self.mode == "restyled" then
        local s = ("Era quest log parchment over Forever's quest panel (%d retail pieces faded), %d quest titles in Era's font"):format(self.faded or 0, self.rows or 0)
        if self.missingArt and #self.missingArt > 0 then
            s = s .. " (art missing: " .. table.concat(self.missingArt, ", ") .. ")"
        end
        s = s .. " (the map itself is left alone)"
        return s
    elseif self.mode == "native" then
        return "classic client, Era's own quest log"
    elseif self.mode == "waiting" then
        return "waiting for Forever's map quest log (QuestMapFrame) to exist"
    end
    return "off"
end

ns.RegisterModule("questlog", M)
