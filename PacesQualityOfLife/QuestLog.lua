-- Pace's Quality of Life - track or untrack many quests at once in the
-- Map & Quest Log
--
-- Forever's quest list is retail's QuestMapFrame (Blizzard_UIPanels_Game,
-- Mainline files on camelot). Each quest row has a tracking checkbox; we
-- add the same kind of checkbox to every zone header (track or untrack
-- every quest in that zone; a faded tick when only some are tracked) and
-- one to the "Quests: 34/40" box above the list for the whole log. The
-- list's gear menu gets "Track all quests" / "Untrack all quests" too.
--
-- The game tracks at most 25 quests (Constants.QuestWatchConsts.
-- MAX_QUEST_WATCHES) out of a 40-quest log, so "track all" fills up to
-- 25 - the zone you're in first - and says how many didn't fit.
--
-- Hooks: hooksecurefunc("QuestLogQuests_Update"), which runs after every
-- rebuild of the list (Blizzard rebuilds it itself on every watch change,
-- so ticks stay right). Our checkboxes are our own frames parented to the
-- header buttons; nothing of ours is written into Blizzard's tables, and
-- Blizzard's own SetHeaderQuestsTracked is never called (it writes a flag
-- on QuestMapFrame).

local addonName, ns = ...

local M = {}
ns.QuestLog = M

local TICK_BOX = "questlog-icon-ticksquare"
local TICK = "questlog-icon-checkmark-yellow"
local PARTIAL_ALPHA = 0.4

local boxes = setmetatable({}, {__mode = "k"}) -- header frame -> our box
local master
local menuAdded

local function Cap()
    local ok, cap = pcall(function() return Constants.QuestWatchConsts.MAX_QUEST_WATCHES end)
    return ok and type(cap) == "number" and cap or 25
end

local function IsWatched(questID)
    local ok, kind = pcall(C_QuestLog.GetQuestWatchType, questID)
    return ok and kind ~= nil
end

local function CanRemove()
    if QuestUtil and QuestUtil.CanRemoveQuestWatch then
        local ok, can = pcall(QuestUtil.CanRemoveQuestWatch)
        if ok then return can and true or false end
    end
    return true
end

-- a quest the tracker would show: Blizzard's own list skips the rest
local function Trackable(info)
    if not info or info.isHeader or not info.questID or info.questID == 0 then return false end
    if info.isHidden or info.isTask or info.isBounty then return false end
    if C_QuestLog.IsQuestDisabledForSession then
        local ok, off = pcall(C_QuestLog.IsQuestDisabledForSession, info.questID)
        if ok and off then return false end
    end
    return true
end

-- the quest log as headers with their quests (collapsed headers' quests
-- are still in C_QuestLog's index list)
function M.ReadLog()
    local headers, all = {}, {}
    local current
    local ok, n = pcall(C_QuestLog.GetNumQuestLogEntries)
    if not ok or type(n) ~= "number" then return headers, all end
    for i = 1, n do
        local okInfo, info = pcall(C_QuestLog.GetInfo, i)
        if okInfo and info then
            if info.isHeader then
                current = {index = i, title = info.title, isOnMap = info.isOnMap, quests = {}}
                table.insert(headers, current)
            elseif Trackable(info) then
                local q = {questID = info.questID, index = i, header = current}
                table.insert(all, q)
                if current then table.insert(current.quests, q) end
            end
        end
    end
    return headers, all
end

local function Counts(quests)
    local watched = 0
    for _, q in ipairs(quests) do
        if IsWatched(q.questID) then watched = watched + 1 end
    end
    return watched, #quests
end

local function TooMany(left)
    local msg = OBJECTIVES_WATCH_TOO_MANY or "You are already tracking the maximum number of quests."
    if left and left > 0 then
        msg = ("%s (%d not tracked)"):format(msg, left)
    end
    if UIErrorsFrame and UIErrorsFrame.AddMessage then
        UIErrorsFrame:AddMessage(msg, 1, 0.1, 0.1, 1)
    else
        ns.Print("%s", msg)
    end
end

-- track every quest in the list given, up to the game's cap
function M.TrackQuests(quests)
    local cap, left = Cap(), 0
    for _, q in ipairs(quests) do
        if not IsWatched(q.questID) then
            local okN, n = pcall(C_QuestLog.GetNumQuestWatches)
            if okN and type(n) == "number" and n >= cap then
                left = left + 1
            else
                pcall(C_QuestLog.AddQuestWatch, q.questID)
            end
        end
    end
    if left > 0 then TooMany(left) end
    return left
end

function M.UntrackQuests(quests)
    if not CanRemove() then return end
    for _, q in ipairs(quests) do
        if IsWatched(q.questID) then pcall(C_QuestLog.RemoveQuestWatch, q.questID) end
    end
end

local function Sound(on)
    if PlaySound and SOUNDKIT then
        pcall(PlaySound, on and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
    end
end

-- every quest: the zones on the open map first, so they win the 25 places
function M.TrackAll()
    local headers, all = M.ReadLog()
    local ordered = {}
    for _, h in ipairs(headers) do
        if h.isOnMap then for _, q in ipairs(h.quests) do table.insert(ordered, q) end end
    end
    for _, q in ipairs(all) do
        if not (q.header and q.header.isOnMap) then table.insert(ordered, q) end
    end
    Sound(true)
    return M.TrackQuests(ordered)
end

function M.UntrackAll()
    local _, all = M.ReadLog()
    Sound(false)
    M.UntrackQuests(all)
end

--------------------------------------------------------------------------
-- our checkboxes
--------------------------------------------------------------------------

local function MakeBox(parent)
    local box = CreateFrame("Button", nil, parent)
    box:SetSize(14, 14)
    box:EnableMouse(true)
    if box.RegisterForClicks then box:RegisterForClicks("LeftButtonUp") end
    local bg = box:CreateTexture(nil, "BACKGROUND")
    bg:SetAtlas(TICK_BOX, true)
    bg:SetPoint("CENTER")
    local tick = box:CreateTexture(nil, "ARTWORK")
    tick:SetAtlas(TICK, true)
    tick:SetPoint("CENTER", 1, 1)
    local hl = box:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAtlas(TICK_BOX, true)
    hl:SetPoint("CENTER")
    hl:SetBlendMode("ADD")
    hl:SetAlpha(0.4)
    box.tick = tick
    box:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    return box
end

-- all / some / none tracked
local function ShowState(box, watched, total)
    box.allTracked = total > 0 and watched == total
    if watched == 0 then
        box.tick:Hide()
    else
        box.tick:Show()
        box.tick:SetAlpha(watched == total and 1 or PARTIAL_ALPHA)
    end
    box.watched, box.total = watched, total
end

local function Tooltip(box, title)
    if not GameTooltip then return end
    GameTooltip:SetOwner(box, "ANCHOR_RIGHT")
    GameTooltip:SetText(title or "")
    local action = box.allTracked and "Click: untrack all of them" or
                       ("Click: track all of them (the game tracks up to %d)"):format(Cap())
    GameTooltip:AddLine(("%d of %d tracked"):format(box.watched or 0, box.total or 0), 1, 1, 1)
    GameTooltip:AddLine(action, 0.6, 0.8, 1)
    GameTooltip:Show()
end

-- the quests under the header at this log index, read fresh at click time
-- (header frames are pooled and indices shift as quests come and go)
local function QuestsUnder(index)
    local okInfo, info = pcall(C_QuestLog.GetInfo, index)
    if not okInfo or not info or not info.isHeader then return nil end
    local headers = M.ReadLog()
    for _, h in ipairs(headers) do
        if h.index == index then return h.quests, h.title end
    end
end

local function HeaderBox(header)
    local box = boxes[header]
    if not box then
        box = MakeBox(header)
        local anchor = header.CollapseButton
        if anchor then
            box:SetPoint("RIGHT", anchor, "LEFT", -4, 0)
        else
            box:SetPoint("RIGHT", header, "RIGHT", -30, 0)
        end
        box:SetScript("OnClick", ns.Guard("questlog", function(self)
            local quests = QuestsUnder(header.questLogIndex)
            if not quests then return end
            local watched, total = Counts(quests)
            if total > 0 and watched == total then
                Sound(false)
                M.UntrackQuests(quests)
            else
                Sound(true)
                M.TrackQuests(quests)
            end
        end))
        box:SetScript("OnEnter", ns.Guard("questlog", function(self)
            local _, title = QuestsUnder(header.questLogIndex)
            Tooltip(self, title)
        end))
        boxes[header] = box
    end
    return box
end

local function MasterBox()
    if master or not QuestLogCount then return master end
    master = MakeBox(QuestScrollFrame or QuestLogCount)
    master:SetPoint("LEFT", QuestLogCount, "LEFT", 5, 0)
    local level = (QuestLogCount.GetFrameLevel and QuestLogCount:GetFrameLevel()) or 1
    if master.SetFrameLevel then master:SetFrameLevel(level + 5) end
    master:SetScript("OnClick", ns.Guard("questlog", function(self)
        if self.allTracked then M.UntrackAll() else M.TrackAll() end
    end))
    master:SetScript("OnEnter", ns.Guard("questlog", function(self)
        Tooltip(self, "All quests")
    end))
    return master
end

-- after every rebuild of Blizzard's list: one box per visible zone header
function M.Sync()
    local on = ns.IsOn("questlog")
    local pool = QuestScrollFrame and QuestScrollFrame.headerFramePool
    local headers, all = M.ReadLog()
    local byIndex = {}
    for _, h in ipairs(headers) do byIndex[h.index] = h end
    local seen = {}
    if pool and pool.EnumerateActive then
        for header in pool:EnumerateActive() do
            local box = HeaderBox(header)
            seen[box] = true
            local h = on and byIndex[header.questLogIndex]
            if h and #h.quests > 0 then
                ShowState(box, Counts(h.quests))
                box:Show()
            else
                box:Hide()
            end
        end
    end
    for _, box in pairs(boxes) do
        if not seen[box] then box:Hide() end
    end
    local m = MasterBox()
    if m then
        if on and #all > 0 and QuestLogCount:IsShown() then
            ShowState(m, Counts(all))
            m:Show()
        else
            m:Hide()
        end
    end
end

local function AddMenu()
    if menuAdded or not (Menu and Menu.ModifyMenu) then return end
    menuAdded = true
    Menu.ModifyMenu("MENU_QUEST_MAP_FRAME_SETTINGS", function(owner, root)
        if not ns.IsOn("questlog") then return end
        if QuestScrollFrame and owner ~= QuestScrollFrame.SettingsDropdown then return end
        root:CreateDivider()
        root:CreateButton("Track all quests", function() ns.SafeCall("questlog", M.TrackAll) end)
        root:CreateButton("Untrack all quests", function() ns.SafeCall("questlog", M.UntrackAll) end)
    end)
end

local function Setup()
    if M.ready then return end
    if type(QuestLogQuests_Update) ~= "function" or not QuestScrollFrame then return end
    M.ready = true
    hooksecurefunc("QuestLogQuests_Update", ns.Guard("questlog", M.Sync))
    ns.SafeCall("questlog", AddMenu)
end

function M:Init()
    Setup()
    if not M.ready then
        -- the quest log should exist at login; if not, try once the world
        -- is entered
        local f = CreateFrame("Frame")
        f:RegisterEvent("PLAYER_ENTERING_WORLD")
        f:SetScript("OnEvent", function(self)
            Setup()
            if M.ready then self:UnregisterEvent("PLAYER_ENTERING_WORLD") end
        end)
    end
end

function M:Apply()
    if M.ready then ns.SafeCall("questlog", M.Sync) end
end

function M:Status()
    local _, all = M.ReadLog()
    local watched = Counts(all)
    return ("(%d of %d quests tracked; the game tracks up to %d)"):format(watched, #all, Cap())
end

ns.RegisterFeature("questlog",
    "Quest log: a tracking checkbox on every zone header (track or untrack the whole zone) and one for all quests, plus Track all / Untrack all in the list's gear menu",
    M)
