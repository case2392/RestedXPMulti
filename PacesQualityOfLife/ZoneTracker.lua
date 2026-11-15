-- Pace's Quality of Life - the objective tracker follows your zone
--
-- Forever's objective tracker (retail's Blizzard_ObjectiveTracker) shows
-- exactly the tracked ("watched") quests, so "only this zone's quests" is
-- done by changing the watches: on entering a zone, every quest under the
-- quest log's header for that zone is tracked and the others are
-- untracked. It runs once per zone entry - anything you track or untrack
-- by hand afterwards stays until you enter another zone.
--
-- The zone is matched by name: the quest log headers are the game's own
-- area names, compared with GetRealZoneText(), GetZoneText() and the
-- player's map (and its parents up to the zone), so a dungeon's header
-- ("Blackfathom Deeps") matches inside the dungeon.
--
-- Kept tracked always: the quest you have super-tracked (its arrow). A
-- zone with none of your quests (a city, a road) leaves the tracker as is.
-- Skipped: passes in combat and on a flight path wait until they end; up
-- to 25 quests can be tracked (the game's cap). Only the differences are
-- changed, removals first, so the tracker and quest log rebuild as little
-- as possible.

local addonName, ns = ...

local M = {}
ns.ZoneTracker = M

local lastKey
local pending, timerArmed

local function Cap()
    local ok, cap = pcall(function() return Constants.QuestWatchConsts.MAX_QUEST_WATCHES end)
    return ok and type(cap) == "number" and cap or 25
end

local function IsWatched(questID)
    local ok, kind = pcall(C_QuestLog.GetQuestWatchType, questID)
    return ok and kind ~= nil
end

local function Add(set, name)
    if type(name) == "string" and name ~= "" and not ns.IsSecret(name) then set[name] = true end
end

-- the names the current zone goes by
function M.ZoneNames()
    local names = {}
    if GetRealZoneText then Add(names, GetRealZoneText()) end
    if GetZoneText then Add(names, GetZoneText()) end
    local okMap, mapID = false, nil
    if C_Map and C_Map.GetBestMapForUnit then okMap, mapID = pcall(C_Map.GetBestMapForUnit, "player") end
    local zoneType = Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3
    local guard = 0
    while okMap and mapID and guard < 6 do
        guard = guard + 1
        local okInfo, info = pcall(C_Map.GetMapInfo, mapID)
        if not okInfo or not info then break end
        if info.mapType and info.mapType < zoneType then break end -- continent and up
        Add(names, info.name)
        if info.mapType == zoneType then break end
        mapID = info.parentMapID
    end
    return names
end

local function ZoneKey()
    local okMap, mapID = false, nil
    if C_Map and C_Map.GetBestMapForUnit then okMap, mapID = pcall(C_Map.GetBestMapForUnit, "player") end
    local zone = GetRealZoneText and GetRealZoneText() or ""
    return tostring(zone) .. "|" .. tostring(okMap and mapID or "")
end

local function SuperTracked()
    if C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID then
        local ok, id = pcall(C_SuperTrack.GetSuperTrackedQuestID)
        if ok and id and id ~= 0 then return id end
    end
end

local function Blocked()
    if InCombatLockdown and InCombatLockdown() then return true end
    if UnitOnTaxi and UnitOnTaxi("player") then return true end
    if QuestUtil and QuestUtil.CanRemoveQuestWatch then
        local ok, can = pcall(QuestUtil.CanRemoveQuestWatch)
        if ok and not can then return true end
    end
    local ok, _, numQuests = pcall(C_QuestLog.GetNumQuestLogEntries)
    if ok and numQuests == 0 then return true end -- log not read in yet
    return false
end

-- one pass: track this zone's quests, untrack the others
function M.Run(force)
    if not ns.IsOn("zonetracker") then return end
    local names = M.ZoneNames()
    if not next(names) then return end -- a loading screen: no zone yet
    local key = ZoneKey()
    if key == lastKey and not force then return end
    if Blocked() then
        pending = true
        return
    end
    pending = false
    lastKey = key

    local headers, all = ns.QuestLog.ReadLog()
    local want, wantList = {}, {}
    for _, h in ipairs(headers) do
        if names[h.title] then
            for _, q in ipairs(h.quests) do
                if not want[q.questID] then
                    want[q.questID] = true
                    table.insert(wantList, q.questID)
                end
            end
        end
    end
    if #wantList == 0 then
        -- no quests here (a city, a road between zones): leave the tracker
        -- as it is rather than empty it
        M.last = {zone = key, tracked = 0, untracked = 0, left = 0, none = true}
        return
    end
    local keep = SuperTracked()
    -- collect first: removing a watch shifts the watch indices
    local remove = {}
    for _, q in ipairs(all) do
        if IsWatched(q.questID) and not want[q.questID] and q.questID ~= keep then
            table.insert(remove, q.questID)
        end
    end
    for _, id in ipairs(remove) do pcall(C_QuestLog.RemoveQuestWatch, id) end
    local cap, left = Cap(), 0
    for _, id in ipairs(wantList) do
        if not IsWatched(id) then
            local okN, n = pcall(C_QuestLog.GetNumQuestWatches)
            if okN and type(n) == "number" and n >= cap then
                left = left + 1
            else
                pcall(C_QuestLog.AddQuestWatch, id)
            end
        end
    end
    M.last = {zone = key, tracked = #wantList - left, untracked = #remove, left = left}
    if left > 0 then
        ns.Print("%d quests in this zone didn't fit on the tracker (the game tracks up to %d).", left, cap)
    end
end

local function Schedule(delay)
    if timerArmed then return end
    timerArmed = true
    C_Timer.After(delay or 1, function()
        timerArmed = false
        ns.SafeCall("zonetracker", M.Run)
    end)
end

function M:Init()
    local f = CreateFrame("Frame")
    for _, event in ipairs({"PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "PLAYER_REGEN_ENABLED",
                            "PLAYER_CONTROL_GAINED", "QUEST_LOG_UPDATE"}) do
        pcall(f.RegisterEvent, f, event)
    end
    f:SetScript("OnEvent", ns.Guard("zonetracker", function(_, event, isLogin, isReload)
        if not ns.IsOn("zonetracker") then return end
        if event == "PLAYER_ENTERING_WORLD" and isReload then
            -- a /reload is not entering a zone: keep what you tracked here
            lastKey = ZoneKey()
            return
        end
        if event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
            Schedule(1)
        elseif pending then
            -- out of combat, off the flight path, or the quest log came in
            Schedule(0.5)
        end
    end))
    M.eventFrame = f
    M.initialized = true
end

-- switched on from the options or /pqol: apply to the zone you're in now
-- (at login the PLAYER_ENTERING_WORLD pass does that)
function M:Apply(on)
    if on and M.switchedOff then
        lastKey = nil
        Schedule(0.1)
    end
    M.switchedOff = not on
end

function M:Status()
    local l = M.last
    if not l then return "(waiting for a zone change)" end
    if l.none then return "(no quests in this zone: tracker left as it was)" end
    return ("(last zone: %d tracked, %d untracked%s)"):format(l.tracked, l.untracked,
        l.left > 0 and (", " .. l.left .. " didn't fit") or "")
end

ns.RegisterFeature("zonetracker",
    "Objective tracker follows your zone: entering a zone tracks that zone's quests and untracks the rest (what you change by hand stays until the next zone)",
    M)
