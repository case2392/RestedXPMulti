-- RestedXP Party Sync - Duo/Trio layer
-- RestedXP's speedrun routes are tuned for one player. In a party, kill XP
-- splits between members but quest XP doesn't, and group/elite/dungeon
-- quests become worth doing. This layer measures your real XP/hour per
-- guide chapter and surfaces party-specific opportunities from live game
-- data (no made-up quest tables).

local addonName, ns = ...

local function CharKey()
    local realm = (GetRealmName and GetRealmName()) or ""
    return ((UnitName and UnitName("player")) or "?") .. "-" .. realm
end

--------------------------------------------------------------------------
-- XP telemetry per guide chapter
--------------------------------------------------------------------------

local function CurrentChapter()
    local name = ns.my and ns.my.guideName
    if not name or name == "" or not ns.stats then return end
    local c = ns.stats.chapters[name]
    if not c then
        c = {seconds = 0, xp = 0, deaths = 0}
        ns.stats.chapters[name] = c
    end
    return c
end

function ns.OnXPUpdate()
    local cur = (UnitXP and UnitXP("player")) or 0
    local max = (UnitXPMax and UnitXPMax("player")) or 0
    local lvl = (UnitLevel and UnitLevel("player")) or 0
    local gained
    if lvl > (ns.xpLastLevel or lvl) then
        -- crossed a level: finish the old bar, then whatever's on the new one
        gained = ((ns.xpLastMax or 0) - (ns.xpLast or 0)) + cur
    else
        gained = cur - (ns.xpLast or cur)
    end
    ns.xpLast, ns.xpLastMax, ns.xpLastLevel = cur, max, lvl
    if gained and gained > 0 then
        local c = CurrentChapter()
        if c then c.xp = c.xp + gained end
    end
end

function ns.OnDeath()
    local c = CurrentChapter()
    if c then c.deaths = c.deaths + 1 end
end

function ns.CurrentXPH()
    local c = CurrentChapter()
    if not c or c.seconds < 60 then return 0 end
    return math.floor(c.xp / c.seconds * 3600)
end

-- called from the 8s ticker
function ns.TickStats(seconds)
    local c = CurrentChapter()
    if c then c.seconds = c.seconds + seconds end
    if ns.my then ns.my.xph = ns.CurrentXPH() end
end

function ns.FormatXP(n)
    n = n or 0
    if n >= 1000 then return string.format("%.1fk", n / 1000) end
    return tostring(n)
end

function ns.PrintStats()
    if not ns.stats then return end
    local current = ns.my and ns.my.guideName
    local names = {}
    for name in pairs(ns.stats.chapters) do table.insert(names, name) end
    table.sort(names, function(a, b)
        if a == current then return true end
        if b == current then return false end
        return a < b
    end)
    if #names == 0 then
        ns.Print("no chapter stats yet - they build up as you play.")
        return
    end
    ns.Print("XP per guide chapter (this character):")
    for _, name in ipairs(names) do
        local c = ns.stats.chapters[name]
        local xph = c.seconds >= 60 and math.floor(c.xp / c.seconds * 3600) or 0
        print(string.format("  %s%s: %s XP in %d min = |cFFFFCC00%s XP/hr|r, %d deaths",
                            name == current and "|cFF66FF66>|r " or "", name,
                            ns.FormatXP(c.xp), math.floor(c.seconds / 60),
                            ns.FormatXP(xph), c.deaths))
    end
end

--------------------------------------------------------------------------
-- Party opportunities from live game data
--------------------------------------------------------------------------

-- quest ids the remaining route will turn in
local function RouteTurnins()
    local set = {}
    local guide = ns.RXP and ns.RXP.currentGuide
    local steps = guide and guide.steps
    if not steps then return set end
    local from = (RXPCData and RXPCData.currentStep) or 1
    for i = from, #steps do
        local step = steps[i]
        for _, el in ipairs(step.elements or step) do
            if el.tag == "turnin" and el.questId then set[el.questId] = true end
        end
    end
    return set
end

-- Group/elite/dungeon quests sitting in the quest log that the solo route
-- never turns in: exactly the ones a party can cash in.
function ns.ScanGroupQuests()
    ns.duoQuests = {}
    if not (GetNumQuestLogEntries and GetQuestLogTitle) then return end
    local n = GetNumQuestLogEntries() or 0
    if n == 0 then return end
    local turnins = RouteTurnins()
    for i = 1, n do
        local title, level, tag, isHeader, _, isComplete, _, questID =
            GetQuestLogTitle(i)
        if title and not isHeader then
            local kind
            if type(tag) == "string" and tag ~= "" then
                kind = tag
            elseif type(tag) == "number" and tag > 0 then
                kind = "Group"
            end
            if GetQuestTagInfo and questID then
                local tid, tname = GetQuestTagInfo(questID)
                if type(tid) == "table" then
                    tname, tid = tid.tagName, tid.tagID
                end
                if tid then kind = tname or kind or "Group" end
            end
            if kind and not (questID and turnins[questID]) then
                table.insert(ns.duoQuests, {
                    title = title,
                    level = level or 0,
                    kind = kind,
                    complete = isComplete and true or false
                })
            end
        end
    end
end

-- RestedXP grind steps ('.xp' elements): kill XP splits in a party
function ns.CurrentStepIsGrind()
    local guide = ns.RXP and ns.RXP.currentGuide
    local step = guide and guide.steps and RXPCData and
                     guide.steps[RXPCData.currentStep]
    if not step then return false end
    for _, el in ipairs(step.elements or step) do
        if el.tag == "xp" then return true end
    end
    return false
end

function ns.PrintDuo()
    if not IsInGroup() then
        ns.Print("party bonuses show while you're grouped.")
        return
    end
    ns.ScanGroupQuests()
    local quests = ns.duoQuests or {}
    if ns.CurrentStepIsGrind() then
        ns.Print("current step is a grind step - kill XP splits between party members, quest XP doesn't.")
    end
    if #quests == 0 then
        ns.Print("no group/elite/dungeon quests in your log that the route skips.")
        return
    end
    ns.Print("group quests in your log that your solo route skips:")
    for _, q in ipairs(quests) do
        print(string.format("  %s (lvl %d, %s)%s", q.title, q.level, q.kind,
                            q.complete and " |cFF66FF66- ready to turn in|r" or ""))
    end
end

--------------------------------------------------------------------------

function ns.SetupDuo()
    ns.db.stats = ns.db.stats or {}
    local key = CharKey()
    ns.db.stats[key] = ns.db.stats[key] or {chapters = {}}
    ns.stats = ns.db.stats[key]
    ns.xpLast = (UnitXP and UnitXP("player")) or 0
    ns.xpLastMax = (UnitXPMax and UnitXPMax("player")) or 0
    ns.xpLastLevel = (UnitLevel and UnitLevel("player")) or 0
    ns.duoQuests = {}

    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_XP_UPDATE")
    f:RegisterEvent("PLAYER_DEAD")
    f:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_XP_UPDATE" then
            ns.OnXPUpdate()
        elseif event == "PLAYER_DEAD" then
            ns.OnDeath()
        end
    end)
end
