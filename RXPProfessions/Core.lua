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

-- A number the addon may use. Forever hands some values back "secret":
-- type() still says number, but comparing one from addon code throws.
-- Such a value counts as unknown rather than taking the scan down.
local function Plain(v)
    if type(v) ~= "number" then return nil end
    local ok = pcall(function() return v == 0 end)
    if ok then return v end
end

-- Three clients, three skill APIs:
--   Classic Era / TBC / Mists: GetNumSkillLines + GetSkillLineInfo
--   Forever (Camelot engine): C_SkillInfo.GetSkillLineInfo(i) -> a table
--   retail-style:            GetProfessions() ids + GetProfessionInfo(id)
-- Every one the client has is read and the results merged, so a
-- profession one of them misses is still found by another. Where two
-- disagree the higher number wins: a skill only goes up, and a source
-- that lags behind must not hold it down. (0.6.1 let the first source
-- win and read GetProfessions first; a report had Skinning stuck at 61
-- after levelling it to 105, reload or not.) Each source's reading is
-- kept for /rxpp status.
local function Record(found, name, rank, maxRank, source)
    if not (name and ns.TRACKED[name]) then return end
    rank, maxRank = Plain(rank) or 0, Plain(maxRank) or 0
    local p = found[name]
    if not p then
        p = {rank = rank, maxRank = maxRank, kind = ns.TRACKED[name], sources = {}}
        found[name] = p
    else
        if rank > p.rank then p.rank = rank end
        if maxRank > p.maxRank then p.maxRank = maxRank end
    end
    p.sources[source] = rank .. "/" .. maxRank
end

-- The skill-line lists only hold what the skills tab shows: a skill under
-- a folded header (the player clicked "Professions" shut once) is not
-- listed at all, and a trained profession read as never learned - a
-- report: "even by talking to the trainers addon doesn't seem to see I'm
-- already trained". Folded headers are opened for the pass and folded
-- back after, bottom up so the indexes above stay put.
--   src.count() -> n;  src.line(i) -> name, isHeader, isFolded, rank, maxRank
--   src.expand(i), src.collapse(i)
local function ScanSkillLines(src, found, source)
    local folded = {}
    for i = src.count() or 0, 1, -1 do
        local name, isHeader, isFolded = src.line(i)
        if isHeader and isFolded and name then
            folded[name] = true
            if src.expand then pcall(src.expand, i) end
        end
    end
    for i = 1, src.count() or 0 do
        local name, isHeader, _, rank, maxRank = src.line(i)
        if not isHeader then Record(found, name, rank, maxRank, source) end
    end
    if next(folded) and src.collapse then
        for i = src.count() or 0, 1, -1 do
            local name, isHeader = src.line(i)
            if isHeader and name and folded[name] then pcall(src.collapse, i) end
        end
    end
end

local function ClassicSkillLines()
    if not (GetNumSkillLines and GetSkillLineInfo) then return end
    return {
        count = GetNumSkillLines,
        line = function(i)
            local name, isHeader, isExpanded, rank, _, _, maxRank = GetSkillLineInfo(i)
            return name, isHeader, isHeader and not isExpanded, rank, maxRank
        end,
        expand = ExpandSkillHeader,
        collapse = CollapseSkillHeader
    }
end

local function ForeverSkillLines()
    local api = C_SkillInfo
    if not (api and api.GetNumSkillLines and api.GetSkillLineInfo) then return end
    return {
        count = api.GetNumSkillLines,
        line = function(i)
            local ok, info = pcall(api.GetSkillLineInfo, i)
            if not ok or type(info) ~= "table" then return end
            return info.name, info.isHeader, info.isCollapsed, info.rank, info.maxRank
        end,
        expand = api.ExpandSkillHeader,
        collapse = api.CollapseSkillHeader
    }
end

-- Opening and closing a folded header raises SKILL_LINES_CHANGED, and
-- on Forever that event runs on the spot, inside the call: unguarded, the
-- scan's own fold-back started a new scan, which opened the header again,
-- and so on. ns.scanning makes the handler ignore the events the scan
-- causes itself.
function ns.ScanSkills()
    local found = {}
    local used = {}
    ns.scanning = true
    local ok, err = pcall(function()
        local classic = ClassicSkillLines()
        if classic then
            ScanSkillLines(classic, found, "skill lines")
            used[#used + 1] = "skill lines"
        end
        local forever = ForeverSkillLines()
        if forever then
            ScanSkillLines(forever, found, "C_SkillInfo")
            used[#used + 1] = "C_SkillInfo"
        end
        -- the profession list: does not depend on the skills tab
        if GetProfessions and GetProfessionInfo then
            for _, id in ipairs({GetProfessions()}) do
                local okP, name, _, rank, maxRank = pcall(GetProfessionInfo, id)
                if okP then Record(found, name, rank, maxRank, "GetProfessions") end
            end
            used[#used + 1] = "GetProfessions"
        end
    end)
    ns.scanning = false
    if not ok then ns.lastError = tostring(err) end
    ns.skillAPI = #used > 0 and table.concat(used, " + ") or "none"
    return found
end

--------------------------------------------------------------------------
-- Known-recipe tracking: the game only exposes your recipe list while a
-- profession window is open, so we scan and remember it whenever one is.
--------------------------------------------------------------------------

-- a recipe's skill-up colour as one word: optimal (orange), medium
-- (yellow), easy (green), trivial (grey). Classic hands the word back from
-- GetTradeSkillInfo / GetCraftInfo; Forever an
-- Enum.TradeskillRelativeDifficulty number.
local DIFFICULTY_BY_NUMBER = {[0] = "optimal", [1] = "medium", [2] = "easy", [3] = "trivial"}
local function Difficulty(v)
    if type(v) == "string" then return v end
    if type(v) == "number" then return DIFFICULTY_BY_NUMBER[v] or "unknown" end
    return "unknown"
end
-- colours in order, best first, and the words players use for them
local ORDER = {optimal = 0, medium = 1, easy = 2, trivial = 3}
local BY_ORDER = {[0] = "optimal", [1] = "medium", [2] = "easy", [3] = "trivial"}
ns.COLOR_WORD = {optimal = "orange", medium = "yellow", easy = "green", trivial = "grey"}
local NOT_RECIPE = {header = true, subheader = true}

-- Recipe names are matched loosely: a later client may write
-- "Enchant Bracers - Minor Stamina" where the route says "Enchant Bracer
-- - Minor Stamina" (a report: "some of the enchant titles no longer
-- match"). Exact key: letters and digits only, lowercase. Loose key: the
-- same without the word "enchant" and without a plural s on each word.
local function Key(name)
    return (tostring(name):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):lower():gsub("[^%w]", ""))
end
local function LooseKey(name)
    local words = {}
    for w in tostring(name):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):lower():gmatch("%a+") do
        if w ~= "enchant" then
            if #w > 3 then w = w:gsub("s$", "") end
            words[#words + 1] = w
        end
    end
    return table.concat(words)
end
ns.RecipeKey, ns.RecipeLooseKey = Key, LooseKey

--------------------------------------------------------------------------
-- Live recipe colours.
--
-- The craft routes in Data.lua are Classic Era's, and a later game
-- version can move a recipe's skill-up range: a report had Linen Bag no
-- longer giving skill-ups at 63 Tailoring and Enchant Bracer - Minor
-- Stamina likewise, "last week's patch". The game itself knows: every
-- open profession window colours each recipe orange, yellow, green or
-- grey. Each sighting is kept with the skill it was seen at, and because
-- a recipe's colour only ever gets worse as skill rises, one sighting
-- also bounds it at other skills: orange at 60 means at best orange
-- below 60, grey at 70 means grey from 70 up. The route is then checked
-- against what the game said, and the game wins.
--
--   ns.db.recipeColors[prof][recipe] = {
--       seen = {optimal = {min = r, max = r}, ...},  -- skills seen at, per colour
--       last = "optimal", lastRank = r }
-- A sighting that contradicts older ones (the patch changed the recipe)
-- drops the older ones; a new game build starts the colours afresh.
--------------------------------------------------------------------------

local function ColorStore(prof)
    local db = ns.db
    local build = GetBuildInfo and select(2, GetBuildInfo()) or nil
    if build and db.recipeColorsBuild ~= build then
        db.recipeColors = {}
        db.recipeColorsBuild = build
    end
    db.recipeColors = db.recipeColors or {}
    db.recipeColors[prof] = db.recipeColors[prof] or {}
    return db.recipeColors[prof]
end

local function NoteColor(store, recipe, diff, rank)
    local o = ORDER[diff]
    if not o or type(rank) ~= "number" then return end
    local r = store[recipe]
    if not r then
        r = {seen = {}}
        store[recipe] = r
    end
    -- drop older sightings this one proves wrong: a better colour at the
    -- same or a higher skill, or a worse colour at the same or a lower one
    for c, s in pairs(r.seen) do
        local oc = ORDER[c]
        if (oc < o and s.max >= rank) or (oc > o and s.min <= rank) then
            r.seen[c] = nil
        end
    end
    local s = r.seen[diff] or {}
    s.min = math.min(s.min or rank, rank)
    s.max = math.max(s.max or rank, rank)
    r.seen[diff] = s
    r.last, r.lastRank = diff, rank
end

-- Records one window's worth: list = {{name, diff, learned}, ...};
-- complete = the list holds unlearned recipes too (Forever), so a name
-- missing from it is not on this game version at all.
local function RecordWindow(prof, rank, list, complete)
    local known, all = {}, {}
    local store = ColorStore(prof)
    for _, e in ipairs(list) do
        all[e.name] = true
        if e.learned ~= false then
            known[e.name] = e.diff
            NoteColor(store, e.name, e.diff, rank)
        end
    end
    ns.db.knownRecipes = ns.db.knownRecipes or {}
    ns.db.knownRecipes[prof] = known
    ns.db.allRecipes = ns.db.allRecipes or {}
    ns.db.allRecipes[prof] = complete and all or nil
    ns.db.recipeRank = ns.db.recipeRank or {}
    ns.db.recipeRank[prof] = rank
    -- the window's skill is the freshest there is: a skill-up while
    -- crafting reaches it before the skills list, so the advice moves on
    -- with the colours it was given
    local p = ns.profs and ns.profs[prof]
    if p and type(rank) == "number" and rank > p.rank then p.rank = rank end
end

-- the profession's skill now, for a scan that the window did not give
local function RankOf(prof, given)
    if type(given) == "number" then
        local ok = pcall(function() return given == 0 end)
        if ok then return given end
    end
    local p = ns.profs and ns.profs[prof]
    return p and p.rank
end

-- Forever (and retail) keep recipes behind C_TradeSkillUI: the open
-- profession's name from GetChildProfessionInfo, every recipe id the
-- window knows (unlearned ones too), a learned flag and the colour on each
local function ScanTradeSkillUI()
    local api = C_TradeSkillUI
    if not (api and api.GetAllRecipeIDs and api.GetRecipeInfo) then return end
    local okP, info = pcall(function()
        return (api.GetChildProfessionInfo and api.GetChildProfessionInfo()) or
                   (api.GetBaseProfessionInfo and api.GetBaseProfessionInfo())
    end)
    local prof = okP and type(info) == "table" and info.professionName
    if type(prof) ~= "string" or not ns.TRACKED[prof] then return end
    local okIds, ids = pcall(api.GetAllRecipeIDs)
    if not okIds or type(ids) ~= "table" then return end
    local list, any = {}, false
    for _, id in ipairs(ids) do
        local okR, r = pcall(api.GetRecipeInfo, id)
        if okR and type(r) == "table" and type(r.name) == "string" then
            local diff = Difficulty(r.relativeDifficulty)
            -- a learned recipe the game says cannot skill up is grey
            if r.learned and r.canSkillUp == false then diff = "trivial" end
            list[#list + 1] = {name = r.name, diff = diff, learned = r.learned and true or false}
            if r.learned then any = true end
        end
    end
    -- the list arrives empty on the first event of an opening window;
    -- nothing known is not the same as nothing learned, so wait for the
    -- next one rather than wipe what was remembered
    if not any then return end
    RecordWindow(prof, RankOf(prof, info.skillLevel), list, true)
    ns.UpdateUI()
    return true
end

function ns.ScanOpenTradeSkill()
    if not (GetTradeSkillLine and GetNumTradeSkills) then
        return ScanTradeSkillUI()
    end
    local prof, rank = GetTradeSkillLine()
    if not prof or prof == "UNKNOWN" or not ns.TRACKED[prof] then return end
    local list = {}
    for i = 1, GetNumTradeSkills() or 0 do
        local rname, rtype = GetTradeSkillInfo(i)
        if rname and not NOT_RECIPE[rtype] then
            list[#list + 1] = {name = rname, diff = Difficulty(rtype)}
        end
    end
    if #list == 0 then return end
    RecordWindow(prof, RankOf(prof, rank), list, false)
    ns.UpdateUI()
end

-- The trainer window is the one place the game states what skill a
-- recipe needs, learned or not: GetTrainerServiceSkillReq(i) gives the
-- skill line and the level. Every tracked profession's services are
-- remembered, so a route row that is wrong by a tier (a report: told to
-- craft gloves the trainer sells at 55 while at 30, and the next row
-- was a tier ahead too) is corrected from what the trainer said.
function ns.ScanTrainer()
    if not (GetNumTrainerServices and GetTrainerServiceInfo and GetTrainerServiceSkillReq) then return end
    local okN, n = pcall(GetNumTrainerServices)
    if not okN or type(n) ~= "number" then return end
    local reqs = ns.db.recipeReq or {}
    local seen = 0
    for i = 1, n do
        local okI, name, _, category = pcall(GetTrainerServiceInfo, i)
        local okR, skill, level = pcall(GetTrainerServiceSkillReq, i)
        if okI and okR and type(name) == "string" and category ~= "header" and
            type(skill) == "string" and ns.TRACKED[skill] and type(level) == "number" then
            reqs[skill] = reqs[skill] or {}
            reqs[skill][name] = level
            seen = seen + 1
        end
    end
    if seen == 0 then return end
    ns.db.recipeReq = reqs
    ns.UpdateUI()
    return seen
end

-- the name a profession's own lists use for a route recipe, looked up
-- exactly first and loosely second; nil when no list has it
local function Resolve(map, recipe)
    if not map then return nil end
    if map[recipe] ~= nil then return recipe end
    local k, lk = Key(recipe), LooseKey(recipe)
    local loose
    for name in pairs(map) do
        if Key(name) == k then return name end
        if not loose and LooseKey(name) == lk then loose = name end
    end
    return loose
end
ns.ResolveRecipe = Resolve

-- what the trainer said a recipe needs, if a trainer has been visited
function ns.RecipeRequirement(prof, recipe)
    local reqs = ns.db and ns.db.recipeReq and ns.db.recipeReq[prof]
    local name = Resolve(reqs, recipe)
    return name and reqs[name]
end

function ns.ScanOpenCraft() -- Enchanting uses the separate Craft API on older clients
    if not (GetCraftDisplaySkillLine and GetNumCrafts) then return end
    local prof, rank = GetCraftDisplaySkillLine()
    if not prof or not ns.TRACKED[prof] then return end
    local list = {}
    for i = 1, GetNumCrafts() or 0 do
        local rname, _, rtype = GetCraftInfo(i)
        if rname and not NOT_RECIPE[rtype] then
            list[#list + 1] = {name = rname, diff = Difficulty(rtype)}
        end
    end
    if #list == 0 then return end
    RecordWindow(prof, RankOf(prof, rank), list, false)
    ns.UpdateUI()
end

function ns.GetKnownRecipes(prof)
    return ns.db and ns.db.knownRecipes and ns.db.knownRecipes[prof]
end

-- A recipe's colour at a given skill, from everything the game has shown.
-- Returns colour, sure, seenColour, seenRank:
--   colour - the best estimate ("optimal".."trivial"), nil when never seen
--   sure   - true when the sightings pin it down exactly at this skill
--   seenColour, seenRank - the sighting the estimate leans on, for wording
function ns.RecipeColor(prof, recipe, rank)
    local store = ns.db and ns.db.recipeColors and ns.db.recipeColors[prof]
    local name = Resolve(store, recipe)
    local r = name and store[name]
    if not r or type(rank) ~= "number" then return nil end
    -- seen at or below this skill: it is now that colour or worse
    -- seen at or above it: it is now that colour or better
    local lower, upper
    for c, s in pairs(r.seen) do
        local o = ORDER[c]
        if s.min <= rank and (not lower or o > lower) then lower = o end
        if s.max >= rank and (not upper or o < upper) then upper = o end
    end
    if lower and upper and lower == upper then return BY_ORDER[lower], true, BY_ORDER[lower], rank end
    -- nothing is better than orange or worse than grey: orange seen at a
    -- higher skill, or grey at a lower one, settles it
    if upper == 0 and not lower then return "optimal", true, "optimal", rank end
    if lower == 3 then return "trivial", true, "trivial", rank end
    if lower then
        -- the sighting it leans on: the highest skill seen at that colour
        return BY_ORDER[lower], false, BY_ORDER[lower], r.seen[BY_ORDER[lower]].max
    end
    if upper then
        return BY_ORDER[upper], false, BY_ORDER[upper], r.seen[BY_ORDER[upper]].min
    end
    return nil
end

-- "orange", or "orange at 60" when the colour is from a lower skill
function ns.ColorText(prof, recipe, rank)
    local c, sure, seenC, seenRank = ns.RecipeColor(prof, recipe, rank)
    if not c then return nil end
    if sure or seenRank == rank then return ns.COLOR_WORD[c] end
    return string.format("%s at %d", ns.COLOR_WORD[seenC], seenRank)
end

-- the skill a route row really needs: the trainer's word for its recipe
-- (any of the alternatives) when there is one, else the row's own number
function ns.RouteRowNeeds(prof, row)
    local need = row[1]
    for alt in tostring(row[2]):gmatch("[^/]+") do
        alt = alt:gsub("^%s+", ""):gsub("%s+$", "")
        local said = ns.RecipeRequirement(prof, alt)
        if said and said > need then need = said end
    end
    return need
end

-- Of the recipes the player knows, the one most likely to skill up at
-- this skill: orange first, then yellow, then green; never grey. Among
-- equals, a recipe the route uses wins (its mats are listed), then the
-- name. Returns name, colour, the route row it is on (if any).
function ns.BestKnownRecipe(prof, rank)
    local known = ns.GetKnownRecipes(prof)
    if not known then return end
    rank = rank or (ns.profs[prof] and ns.profs[prof].rank)
    local rowOf = {}
    local craft = ns.CRAFT[prof]
    for _, row in ipairs(craft and craft.route or {}) do
        for alt in tostring(row[2]):gmatch("[^/]+") do
            alt = alt:gsub("^%s+", ""):gsub("%s+$", "")
            local name = Resolve(known, alt)
            if name then rowOf[name] = row end
        end
    end
    local best, bestO, bestRow
    for recipe, diff in pairs(known) do
        local c = ns.RecipeColor(prof, recipe, rank) or (type(diff) == "string" and diff)
        local o = ORDER[c]
        if o and o < 3 then
            local row = rowOf[recipe]
            local better = not bestO or o < bestO or
                               (o == bestO and row and not bestRow) or
                               (o == bestO and (row ~= nil) == (bestRow ~= nil) and recipe < best)
            if better then best, bestO, bestRow = recipe, o, row end
        end
    end
    return best, best and BY_ORDER[bestO], bestRow
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

-- resolve {A=..., H=...} tables to the player's faction
local function ForFaction(value)
    if type(value) == "table" then
        local faction = UnitFactionGroup and UnitFactionGroup("player")
        return faction == "Horde" and value.H or value.A
    end
    return value
end

-- Notes with req/gate show only when actionable (rank >= req) and not yet
-- done (maxRank <= gate - a raised cap proves the rank-up already happened).
-- Notes without them use the old approach-window behavior.
local function NoteVisible(note, rank, maxRank)
    if note.req or note.gate then
        if note.req and rank < note.req then return false end
        if note.gate and maxRank > note.gate then return false end
        return true
    end
    return rank >= note[1] - 40 and rank < note[1] + 15
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
            -- a row whose recipe the trainer sells only at a higher skill
            -- than the row claims is a tier early: step back to the last
            -- row the player can actually have learned
            local tooEarly
            while current and ns.RouteRowNeeds(name, current) > p.rank do
                tooEarly = tooEarly or current
                local prev
                for _, tier in ipairs(route) do
                    if tier == current then break end
                    prev = tier
                end
                if not prev then break end
                nextUp = current
                current = prev
            end
            if current then
                local knownMap = ns.GetKnownRecipes(name)
                local allMap = ns.db and ns.db.allRecipes and ns.db.allRecipes[name]
                -- the row's alternatives the player knows, the best-coloured
                -- one first, with its colour at the skill they are at now
                local routeName, routeColor, anyKnown, inGame = nil, nil, false, false
                for alt in current[2]:gmatch("[^/]+") do
                    alt = alt:gsub("^%s+", ""):gsub("%s+$", "")
                    local known = ns.ResolveRecipe(knownMap, alt)
                    if known then
                        local c = ns.RecipeColor(name, known, p.rank) or
                                      (type(knownMap[known]) == "string" and knownMap[known] or nil)
                        if not anyKnown or (ORDER[c] or 9) < (ORDER[routeColor] or 9) then
                            routeName, routeColor = known, c
                        end
                        anyKnown = true
                    end
                    if ns.ResolveRecipe(allMap, alt) then inGame = true end
                end
                local display = routeName or current[2]
                local routeO = ORDER[routeColor]
                -- The game outranks the route: when it shows the route's
                -- recipe grey (no skill-ups), or green while the player knows
                -- something orange or yellow, the better recipe is the one
                -- to craft. (A report: Linen Bag at 63 Tailoring and Enchant
                -- Bracer - Minor Stamina at 63 Enchanting, both past their
                -- skill-ups after a patch, still recommended.)
                local best, bestColor, bestRow = ns.BestKnownRecipe(name, p.rank)
                local takeBest = anyKnown and routeO and best and best ~= routeName and
                                     (routeO == 3 or (routeO == 2 and ORDER[bestColor] <= 1))
                if takeBest then
                    add(string.format("Craft: %s (%s)", best, ns.ColorText(name, best, p.rank) or ns.COLOR_WORD[bestColor]), "normal")
                    add(string.format("(%s is %s for you now - the game moved it, so this beats the route)",
                                      routeName, ns.ColorText(name, routeName, p.rank) or ns.COLOR_WORD[routeColor]), "dim")
                    if bestRow and bestRow[3] then add("Mats: " .. bestRow[3], "dim") end
                else
                    local colorText = routeName and ns.ColorText(name, routeName, p.rank)
                    add(string.format("Craft: %s%s", display, colorText and (" (" .. colorText .. ")") or ""), "normal")
                    if routeO == 3 then
                        add("It gives no skill-ups any more, and you know nothing better - check your trainer for new recipes", "warn")
                    elseif routeO == 2 then
                        add("Green: it only skills up some of the time", "dim")
                    end
                    if tooEarly then
                        add(string.format("(%s needs %d - your trainer said so)", tooEarly[2],
                                          ns.RouteRowNeeds(name, tooEarly)), "dim")
                    end
                    -- the route's recipe is not known, but one that is still
                    -- gives skill-ups: say so rather than send them shopping
                    if knownMap and not anyKnown and best then
                        add(string.format("Meanwhile: %s (%s)", best, ns.ColorText(name, best, p.rank) or ns.COLOR_WORD[bestColor]), "good")
                    end
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
                        local need = ns.RecipeRequirement(name, display)
                        if allMap and not inGame then
                            -- Forever lists every recipe, learned or not:
                            -- one missing from the list is not in this game
                            add(string.format("%s isn't in your %s list - this game version may not have it", display, name), "warn")
                        elseif need and need > p.rank then
                            add(string.format("Learn it at %d from your trainer", need), "warn")
                        else
                            add("You don't know this recipe yet!", "warn")
                            add("Get it: " ..
                                    (source or "check your trainer / recipe vendors"),
                                "warn")
                        end
                    elseif not knownMap then
                        if source then
                            add("Recipe: " .. source, "dim")
                        end
                        add(string.format("(open your %s window once so I can check these recipes against your game)",
                                          name), "dim")
                    end
                end
            end
            if nextUp then
                add(string.format("At %d: %s", nextUp[1], nextUp[2]), "dim")
            end
            for _, note in ipairs(craft.notes or {}) do
                if NoteVisible(note, p.rank, p.maxRank) then
                    add(ForFaction(note[2]), "warn")
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
                add(string.format("Later (Cooking %d): %s", nextUp[1],
                                  nextUp.fish), "dim")
            end
        else
            add("Fish anywhere - each catch can skill up", "normal")
            add("Higher-level zones need higher skill (use lures)", "dim")
        end
        -- fish escape when the zone needs more skill than you have; escaped
        -- catches give no skill, so this is the one real fishing mistake
        local zone = (GetRealZoneText and GetRealZoneText()) or ""
        local waters = ns.ZONE_WATERS[zone]
        if waters and waters.minskill then
            if p.rank < waters.minskill then
                add(string.format("Fish escape here! %s needs ~%d skill (you: %d)",
                                  zone, waters.minskill, p.rank), "warn")
            else
                add(string.format("Skill OK for %s (needs %d)", zone,
                                  waters.minskill), "dim")
            end
        end
        for _, note in ipairs(ns.FISHING_NOTES) do
            if NoteVisible(note, p.rank, p.maxRank) then
                add(ForFaction(note[2]), "warn")
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

-- Not every client has every event: Forever's engine has no
-- TRADE_SKILL_UPDATE or CRAFT_* (its profession window raises
-- TRADE_SKILL_LIST_UPDATE instead), and registering an unknown event
-- throws - a report: "Attempt to register unknown event
-- TRADE_SKILL_UPDATE" at every login, and the addon never started. Each
-- one is tried on its own; the ones the client lacks are skipped and
-- listed for /rxpp status.
local EVENTS = {
    "PLAYER_ENTERING_WORLD", "SKILL_LINES_CHANGED", "CHAT_MSG_SKILL",
    "ZONE_CHANGED_NEW_AREA", "TRADE_SKILL_SHOW", "TRADE_SKILL_UPDATE",
    "TRADE_SKILL_LIST_UPDATE", "CRAFT_SHOW", "CRAFT_UPDATE",
    "TRAINER_SHOW", "TRAINER_UPDATE"
}
ns.missingEvents = {}
for _, event in ipairs(EVENTS) do
    local ok = pcall(eventFrame.RegisterEvent, eventFrame, event)
    if not ok then table.insert(ns.missingEvents, event) end
end
local TRADE_EVENTS = {TRADE_SKILL_SHOW = true, TRADE_SKILL_UPDATE = true, TRADE_SKILL_LIST_UPDATE = true}
eventFrame:SetScript("OnEvent", function(_, event)
    if TRADE_EVENTS[event] then
        if ns.db then ns.ScanOpenTradeSkill() end
        return
    elseif event == "TRAINER_SHOW" or event == "TRAINER_UPDATE" then
        if ns.db then ns.ScanTrainer() end
        return
    elseif event == "CRAFT_SHOW" or event == "CRAFT_UPDATE" then
        if ns.db then ns.ScanOpenCraft() end
        return
    end
    if event == "SKILL_LINES_CHANGED" and ns.scanning then return end
    if event == "CHAT_MSG_SKILL" and C_Timer and C_Timer.After then
        -- "Your skill in Skinning has increased to 62" can arrive before
        -- the skill list holds 62: look again a moment later as well
        C_Timer.After(1, function() if ns.db then ns.Refresh() end end)
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
    elseif input == "status" then
        ns.Refresh()
        local names = {}
        for name, p in pairs(ns.profs) do
            -- when the sources disagree, say what each one said
            local readings, seen, differ = {}, nil, false
            for source, r in pairs(p.sources or {}) do
                readings[#readings + 1] = source .. " " .. r
                if seen and seen ~= r then differ = true end
                seen = r
            end
            table.sort(readings)
            local line = string.format("%s %d/%d", name, p.rank, p.maxRank)
            if differ then line = line .. " (" .. table.concat(readings, "; ") .. ")" end
            table.insert(names, line)
        end
        table.sort(names)
        ns.Print("skills read through %s: %s", tostring(ns.skillAPI),
                 #names > 0 and table.concat(names, ", ") or "none tracked")
        if ns.lastError then ns.Print("last error: %s", ns.lastError) end
        -- when each profession's recipe list was last read from its window
        local read = {}
        for prof, rank in pairs(ns.db.recipeRank or {}) do
            local n = 0
            for _ in pairs(ns.GetKnownRecipes(prof) or {}) do n = n + 1 end
            read[#read + 1] = string.format("%s %d recipes at skill %d", prof, n, rank)
        end
        table.sort(read)
        ns.Print("recipe colours read: %s", #read > 0 and table.concat(read, ", ")
                     or "none yet - open a profession window once")
        if #ns.missingEvents > 0 then
            ns.Print("events this client lacks (skipped): %s", table.concat(ns.missingEvents, ", "))
        end
    else
        ns.Print("commands: |cFFFFCC00/rxpp|r toggle the window, |cFFFFCC00/rxpp setup|r choose professions, |cFFFFCC00/rxpp status|r what the client gives us")
    end
end
