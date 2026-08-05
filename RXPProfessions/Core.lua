-- RestedXP Professions - track profession skills and recommend what to do
-- right now: what to gather at your current skill, when to visit a trainer,
-- which bandage to craft. Reads live skill levels from the skill line API.

local addonName, ns = ...

local eventFrame = CreateFrame("Frame")
ns.profs = {} -- name -> {rank, maxRank, kind}

function ns.Print(msg, ...)
    print("|cFF66CCFFRXP Professions:|r " .. string.format(msg, ...))
end

--------------------------------------------------------------------------
-- Skill scanning
--------------------------------------------------------------------------

function ns.ScanSkills()
    local found = {}
    if not GetNumSkillLines then return found end
    for i = 1, GetNumSkillLines() do
        local name, isHeader, _, rank, _, _, maxRank = GetSkillLineInfo(i)
        if name and not isHeader and ns.TRACKED[name] then
            found[name] = {
                rank = rank or 0,
                maxRank = maxRank or 0,
                kind = ns.TRACKED[name]
            }
        end
    end
    return found
end

--------------------------------------------------------------------------
-- Known-recipe tracking: the game only exposes your recipe list while a
-- profession window is open, so we scan and remember it whenever one is.
--------------------------------------------------------------------------

function ns.ScanOpenTradeSkill()
    if not (GetTradeSkillLine and GetNumTradeSkills) then return end
    local prof = GetTradeSkillLine()
    if not prof or prof == "UNKNOWN" or not ns.TRACKED[prof] then return end
    local known = {}
    for i = 1, GetNumTradeSkills() do
        local rname, rtype = GetTradeSkillInfo(i)
        if rname and rtype ~= "header" then known[rname] = true end
    end
    ns.db.knownRecipes = ns.db.knownRecipes or {}
    ns.db.knownRecipes[prof] = known
    ns.UpdateUI()
end

function ns.ScanOpenCraft() -- Enchanting uses the separate Craft API
    if not (GetCraftDisplaySkillLine and GetNumCrafts) then return end
    local prof = GetCraftDisplaySkillLine()
    if not prof or not ns.TRACKED[prof] then return end
    local known = {}
    for i = 1, GetNumCrafts() do
        local rname, _, rtype = GetCraftInfo(i)
        if rname and rtype ~= "header" then known[rname] = true end
    end
    ns.db.knownRecipes = ns.db.knownRecipes or {}
    ns.db.knownRecipes[prof] = known
    ns.UpdateUI()
end

function ns.GetKnownRecipes(prof)
    return ns.db and ns.db.knownRecipes and ns.db.knownRecipes[prof]
end

--------------------------------------------------------------------------
-- Recommendations
--------------------------------------------------------------------------

-- current entry and next unlock from an ascending {skill, text} list
local function CurrentAndNext(tiers, skill)
    local current, nextUp
    for _, tier in ipairs(tiers) do
        if skill >= tier[1] then
            current = tier
        elseif not nextUp then
            nextUp = tier
        end
    end
    return current, nextUp
end

-- "finishing 19-20 Redridge" when a RestedXP guide is loaded, otherwise
-- "leaving <zone>" - a city name makes no sense as a gathering deadline,
-- but the guide chapter always does.
local function GuideContext()
    if LibStub then
        local ace = LibStub("AceAddon-3.0", true)
        local rxp = ace and ace:GetAddon("RXPGuides", true)
        local guide = rxp and rxp.currentGuide
        local gname = guide and (guide.displayname or guide.name)
        if type(gname) == "string" and gname ~= "" then
            gname = gname:gsub("\n.*", ""):gsub("|c%x%x%x%x%x%x%x%x", "")
                         :gsub("|r", "")
            return "finishing " .. gname
        end
    end
    local zone = (GetRealZoneText and GetRealZoneText()) or
                     (GetZoneText and GetZoneText())
    if zone and zone ~= "" then return "leaving " .. zone end
    return "moving on"
end

-- "In Redridge Mountains: Lake Everstill" - but only when the current zone
-- has the right kind of water AND the fish actually lives at this zone's
-- level (no catfish in starter-zone lakes)
function ns.ZoneWaterSpot(entry)
    local zone = (GetRealZoneText and GetRealZoneText()) or ""
    local waters = ns.ZONE_WATERS[zone]
    if not waters then return end
    local spot = entry.water and waters[entry.water]
    if not spot then return end
    if entry.band and waters.lvl then
        if waters.lvl < entry.band[1] or waters.lvl > entry.band[2] then
            return
        end
    end
    return string.format("In %s: %s", zone, spot)
end

local function RankInfo(maxRank)
    for _, r in ipairs(ns.RANKS) do
        if maxRank <= r.cap then return r end
    end
end

-- Returns a list of {text, style} lines for one profession.
-- style: "head" | "normal" | "good" | "warn" | "dim"
function ns.BuildProfLines(name, p)
    local lines = {}
    local function add(text, style)
        table.insert(lines, {text = text, style = style or "normal"})
    end

    if p.unlearned then
        add(name, "head")
        add("Not learned yet - train with:", "warn")
        local trainers = ns.TRAINERS[name]
        local faction = UnitFactionGroup and UnitFactionGroup("player")
        local capital = trainers and
                            (faction == "Horde" and trainers.H or trainers.A)
        -- while still low level, the starting-village trainer is far closer
        -- than the capital
        local race = UnitRace and select(2, UnitRace("player"))
        local level = UnitLevel and UnitLevel("player") or 0
        local villages = race and ns.VILLAGE_TRAINERS[race]
        local nearby = villages and villages[name]
        if nearby and level <= 14 then
            add(nearby, "normal")
            if capital then add("or: " .. capital, "dim") end
        elseif capital then
            add(capital, "normal")
        end
        add("(any city guard can mark trainers on your map)", "dim")
        return lines
    end

    add(string.format("%s  %d/%d", name, p.rank, p.maxRank), "head")

    -- pace check: rough classic rule of thumb is ~5 skill per character
    -- level; warn when falling well behind so you catch up before moving on.
    -- The goal shown is the next unlock/bracket - a fixed, achievable
    -- milestone - not the ever-climbing level*5 number.
    local isPrimary = p.kind == "gather" or
                          (p.kind == "craft" and ns.CRAFT[name] and
                              ns.CRAFT[name].primary)
    local level = UnitLevel and UnitLevel("player") or 0
    if level > 5 and isPrimary then
        local pace = math.min(level * 5, 300)
        if p.rank < pace - 25 then
            local milestone, milestoneName
            if p.kind == "gather" then
                local _, nextUp = CurrentAndNext(ns.GATHER[name].tiers, p.rank)
                if nextUp then
                    milestone, milestoneName = nextUp[1], nextUp[2]
                end
            else
                local craftDef = ns.CRAFT[name]
                local route = craftDef and craftDef.route
                if name == "Cooking" and ns.FishCookCombo() then
                    route = ns.FISH_COOKING
                end
                local _, nextUp = route and CurrentAndNext(route, p.rank)
                if nextUp then
                    milestone, milestoneName = nextUp[1], nextUp[2]
                end
            end
            local context = GuideContext()
            if milestone and milestone <= pace then
                add(string.format("Aim for %d (%s) before %s", milestone,
                                  milestoneName, context), "warn")
            else
                add(string.format("Catch up toward ~%d before %s", pace,
                                  context), "warn")
            end
        end
    end

    -- trainer / cap advice
    local rank = RankInfo(p.maxRank)
    local capped = p.rank >= p.maxRank
    if rank and rank.nextRank and p.rank >= (rank.trainAt or math.huge) then
        if capped then
            add(string.format("Capped! Train %s at a %s trainer", rank.nextRank,
                              name), "warn")
        else
            add(string.format("Can train %s now (%d needed)", rank.nextRank,
                              rank.trainAt), "good")
        end
    elseif capped then
        add("Skill capped for this expansion", "dim")
    elseif rank and rank.nextRank and p.maxRank - p.rank <= 10 then
        add(string.format("Cap soon - train %s at %d", rank.nextRank,
                          rank.trainAt), "warn")
    end

    -- what to do right now
    if p.kind == "gather" then
        local gather = ns.GATHER[name]
        local current, nextUp = CurrentAndNext(gather.tiers, p.rank)
        if current then
            add(string.format("%s: %s", gather.verb, current[2]), "normal")
        end
        if nextUp then
            add(string.format("At %d: %s", nextUp[1], nextUp[2]), "dim")
        end
    elseif p.kind == "craft" then
        local craft = ns.CRAFT[name]
        if craft then
            local route = craft.route
            local fishCombo = name == "Cooking" and ns.FishCookCombo()
            if fishCombo then route = ns.FISH_COOKING end
            local current, nextUp = CurrentAndNext(route, p.rank)
            if fishCombo then
                add("Combo: cooking your Fishing catches", "good")
            end
            if current then
                -- prefer an alternative the player actually knows; warn
                -- with the recipe source when none of them are known
                local knownMap = ns.GetKnownRecipes(name)
                local display = current[2]
                local anyKnown = false
                if knownMap then
                    for alt in current[2]:gmatch("[^/]+") do
                        alt = alt:gsub("^%s+", ""):gsub("%s+$", "")
                        if knownMap[alt] then
                            if not anyKnown then display = alt end
                            anyKnown = true
                        end
                    end
                end
                add(string.format("Craft: %s", display), "normal")
                if fishCombo then
                    add(string.format("Mats: %s", current.fish), "dim")
                    local spot = ns.ZoneWaterSpot(current)
                    if spot then
                        add(spot, "good")
                    else
                        add(string.format("(fish: %s)", current.where), "dim")
                    end
                elseif current[3] then
                    add("Mats: " .. current[3], "dim")
                end
                local source = current.source or current.recipe
                if type(source) == "table" then
                    local faction = UnitFactionGroup and
                                        UnitFactionGroup("player")
                    source = faction == "Horde" and source.H or source.A
                end
                if knownMap and not anyKnown then
                    add("You don't know this recipe yet!", "warn")
                    add("Get it: " ..
                            (source or "check your trainer / recipe vendors"),
                        "warn")
                elseif not knownMap then
                    if source then
                        add("Recipe: " .. source, "dim")
                    end
                    add(string.format("(open your %s window once so I can track your recipes)",
                                      name), "dim")
                end
            end
            if nextUp then
                add(string.format("At %d: %s", nextUp[1], nextUp[2]), "dim")
            end
            for _, note in ipairs(craft.notes or {}) do
                -- surface milestone notes early enough to plan the trip,
                -- drop them once comfortably past
                if p.rank >= note[1] - 40 and p.rank < note[1] + 15 then
                    add(note[2], "warn")
                end
            end
            if craft.primary and ns.db and ns.db.useAH then
                add("Tip: buy missing mats from the Auction House", "dim")
            end
        end
    elseif p.kind == "fishing" then
        if ns.FishCookCombo() then
            -- steer the fishing spot by what Cooking needs next
            local cooking = ns.profs["Cooking"] or {rank = 0}
            local current, nextUp = CurrentAndNext(ns.FISH_COOKING,
                                                   cooking.rank)
            if current then
                add(string.format("Catch: %s", current.fish), "normal")
                local spot = ns.ZoneWaterSpot(current)
                if spot then
                    add(spot, "good")
                else
                    add(string.format("Where: %s", current.where), "dim")
                end
                add("(feeds your Cooking bracket)", "dim")
            end
            if nextUp then
                add(string.format("At Cooking %d: %s", nextUp[1], nextUp.fish),
                    "dim")
            end
        else
            add("Fish anywhere - each catch can skill up", "normal")
            add("Higher-level zones need higher skill (use lures)", "dim")
        end
        for _, note in ipairs(ns.FISHING_NOTES) do
            if p.rank >= note[1] - 40 and p.rank < note[1] + 15 then
                add(note[2], "warn")
            end
        end
    elseif p.kind == "skinning" then
        -- max skinnable mob level is roughly skill/5 (min 10)
        local maxLevel = math.max(10, math.floor(p.rank / 5))
        add(string.format("Skin your kills (up to ~level %d mobs)", maxLevel),
            "normal")
    end

    return lines
end

-- Is this profession being tracked (per setup choices, or learned pre-setup)?
function ns.IsTrackedName(name)
    local chosen = ns.db and ns.db.setupDone and ns.db.chosen
    if chosen then return chosen[name] and true or false end
    return ns.profs[name] ~= nil
end

-- Both Fishing and Cooking tracked -> level them together off your catches
function ns.FishCookCombo()
    return ns.IsTrackedName("Cooking") and ns.IsTrackedName("Fishing")
end

-- The setup choices decide what's displayed: checked professions show
-- (learned or not), unchecked ones stay hidden even if the character has
-- the skill. Before setup has run, everything learned shows.
function ns.GetTracked()
    local merged = {}
    local chosen = ns.db and ns.db.setupDone and ns.db.chosen
    if chosen then
        for name in pairs(chosen) do
            if ns.TRACKED[name] then
                merged[name] = ns.profs[name] or {
                    rank = 0,
                    maxRank = 0,
                    kind = ns.TRACKED[name],
                    unlearned = true
                }
            end
        end
    else
        for name, p in pairs(ns.profs) do merged[name] = p end
    end
    return merged
end

--------------------------------------------------------------------------
-- Refresh loop: rescan on skill events, announce unlocks
--------------------------------------------------------------------------

function ns.Refresh()
    local fresh = ns.ScanSkills()

    -- announce newly crossed gathering unlocks (tracked professions only)
    local chosen = ns.db and ns.db.setupDone and ns.db.chosen
    for name, p in pairs(fresh) do
        local old = ns.profs[name]
        if (not chosen or chosen[name]) and old and p.kind == "gather" and
            p.rank > old.rank then
            for _, tier in ipairs(ns.GATHER[name].tiers) do
                if old.rank < tier[1] and p.rank >= tier[1] and tier[1] > 1 then
                    ns.Print("|cFF66FF66%s unlocked:|r you can now gather %s!",
                             name, tier[2])
                end
            end
        end
    end

    ns.profs = fresh
    ns.UpdateUI()
end

--------------------------------------------------------------------------
-- Events + slash command
--------------------------------------------------------------------------

eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("SKILL_LINES_CHANGED")
eventFrame:RegisterEvent("CHAT_MSG_SKILL")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
eventFrame:RegisterEvent("TRADE_SKILL_SHOW")
eventFrame:RegisterEvent("TRADE_SKILL_UPDATE")
eventFrame:RegisterEvent("CRAFT_SHOW")
eventFrame:RegisterEvent("CRAFT_UPDATE")
eventFrame:SetScript("OnEvent", function(_, event)
    if event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_UPDATE" then
        if ns.db then ns.ScanOpenTradeSkill() end
        return
    elseif event == "CRAFT_SHOW" or event == "CRAFT_UPDATE" then
        if ns.db then ns.ScanOpenCraft() end
        return
    end
    if event == "PLAYER_ENTERING_WORLD" then
        RXPProfessionsDB = RXPProfessionsDB or {}
        if RXPProfessionsDB.show == nil then RXPProfessionsDB.show = true end
        ns.db = RXPProfessionsDB
        if not ns.uiReady then
            ns.SetupUI()
            ns.uiReady = true
            -- light refresh so guide-chapter context stays current even
            -- without a skill event (RestedXP guide switches, etc.)
            if C_Timer and C_Timer.NewTicker then
                C_Timer.NewTicker(15, function()
                    if ns.db then ns.UpdateUI() end
                end)
            end
        end
        if not ns.db.setupDone then ns.ShowSetup() end
    end
    if ns.db then ns.Refresh() end
end)

SLASH_RXPPROFESSIONS1 = "/rxpp"
SLASH_RXPPROFESSIONS2 = "/rxpprofessions"
SlashCmdList["RXPPROFESSIONS"] = function(input)
    if not ns.db then return end
    input = (input or ""):gsub("%s+", ""):lower()
    if input == "" or input == "show" or input == "hide" then
        ns.ToggleUI(input)
    elseif input == "setup" then
        ns.ShowSetup()
    else
        ns.Print("commands: |cFFFFCC00/rxpp|r toggle the window, |cFFFFCC00/rxpp setup|r choose professions")
    end
end
