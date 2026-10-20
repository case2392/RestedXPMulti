-- RestedXP Professions - track profession skills and recommend what to do
-- right now: what to gather at your current skill, when to visit a trainer,
-- which bandage to craft. Reads live skill levels from the skill line API.

local addonName, ns = ...

local eventFrame = CreateFrame("Frame")

-- Which game this is, from the interface number: WoW Forever (16001) moved
-- most skill-up ranges, trainer levels and recipe names, so it has routes
-- of its own (Data.lua foreverRoute / foreverNotes, ns.FOREVER); TBC
-- renamed and re-costed a few recipes and teaches more at its trainers (a
-- route row's `tbc` / `tbcMats` / `tbcSource`). ns.CLIENT names the game
-- for data that differs: "era", "forever", "tbc" or "later" (Mists).
do
    local toc = GetBuildInfo and select(4, GetBuildInfo())
    toc = type(toc) == "number" and toc or 0
    ns.IS_FOREVER = toc >= 16000 and toc < 20000
    ns.IS_TBC = toc >= 20000 and toc < 30000
    ns.CLIENT = ns.IS_FOREVER and "forever" or ns.IS_TBC and "tbc" or toc >= 30000 and "later" or "era"
    ns.HAS_MASTER = toc >= 20000 -- Classic Era and Forever stop at Artisan
    ns.HAS_LATER_RANKS = toc >= 30000 -- Grand Master and up
    -- before patch 3.1, Expert and Artisan First Aid, Cooking and Fishing
    -- came from books and quests, not trainers
    ns.BOOK_RANKS = toc < 30000
end
-- names this client writes differently from Classic Era (Locales.lua)
for _, set in ipairs({{"NODE_NAMES", "NODE_NAMES_FOR"}, {"RANK_NAMES", "RANK_NAMES_FOR"}}) do
    local over = ns[set[2]] and ns[set[2]][ns.CLIENT] and ns[set[2]][ns.CLIENT][ns.LOCALE]
    if over then
        local names = ns[set[1]][ns.LOCALE] or {}
        ns[set[1]][ns.LOCALE] = names
        for key, name in pairs(over) do names[key] = name end
    end
end
if ns.IS_FOREVER then
    for _, craft in pairs(ns.CRAFT) do
        craft.route = craft.foreverRoute or craft.route
        craft.notes = craft.foreverNotes or craft.notes
    end
    for key, value in pairs(ns.FOREVER or {}) do ns[key] = value end
    -- its new village trainers fill gaps, never replace an entry
    for race, extra in pairs(ns.FOREVER_VILLAGE or {}) do
        local villages = ns.VILLAGE_TRAINERS[race] or {}
        ns.VILLAGE_TRAINERS[race] = villages
        for prof, text in pairs(extra) do villages[prof] = villages[prof] or text end
    end
end
--------------------------------------------------------------------------
-- Names in the player's language. The data is written in English; the
-- game names recipes and items itself, in its own language, by spell and
-- item ID, so the advice reads in French on a French client and matches
-- what the profession window and the trainer list (a report: "my
-- professions are not detected because I play in French"). Professions,
-- ranks and mining nodes come from Locales.lua, the addon's own sentences
-- from ns.L.
--------------------------------------------------------------------------

local L = ns.L

-- lowercase A-Z only: Lua's lower() and its character classes know only
-- ASCII, and one client was seen to mangle Cyrillic in lower()
function ns.Fold(text)
    return (tostring(text):gsub("[A-Z]", function(c) return string.char(c:byte() + 32) end))
end

local function Split(text)
    local out = {}
    for part in tostring(text or ""):gmatch("[^/]+") do
        out[#out + 1] = part:gsub("^%s+", ""):gsub("%s+$", "")
    end
    return out
end

-- a spell's name (any spell, known or not, from the client's own data)
local function SpellName(id)
    if type(id) ~= "number" then return nil end
    local api = C_Spell
    if api and api.GetSpellName then
        local ok, name = pcall(api.GetSpellName, id)
        if ok and type(name) == "string" and name ~= "" then return name end
    end
    if GetSpellInfo then
        local ok, name = pcall(GetSpellInfo, id)
        if ok and type(name) == "string" and name ~= "" then return name end
    end
    -- not loaded yet: ask (SPELL_DATA_LOAD_RESULT redraws the window)
    if api and api.RequestLoadSpellData then pcall(api.RequestLoadSpellData, id) end
end

-- an item's name; nil until the client has it cached - it is asked for,
-- and GET_ITEM_INFO_RECEIVED redraws the window when it arrives
local function ItemName(id)
    if type(id) ~= "number" then return nil end
    local api = C_Item
    local name
    if api and api.GetItemNameByID then
        local ok, n = pcall(api.GetItemNameByID, id)
        if ok and type(n) == "string" and n ~= "" then name = n end
    end
    -- (Forever has no GetItemInfo global, only C_Item's; on a cache miss
    -- it returns nothing at all)
    local getInfo = (api and api.GetItemInfo) or GetItemInfo
    if not name and getInfo then
        local ok, n = pcall(getInfo, id)
        if ok and type(n) == "string" and n ~= "" then name = n end
    end
    if not name and api and api.RequestLoadItemDataByID then
        pcall(api.RequestLoadItemDataByID, id)
    end
    return name
end
ns.SpellName, ns.ItemName = SpellName, ItemName

-- Professions are keyed by their English names. The game names them in
-- its own language: by skill-line ID where an API gives one, else by any
-- name it may use (every language's, so a client set to one language
-- with another's data still matches).
local profByName
local function ProfNames()
    if profByName then return profByName end
    profByName = {}
    local function add(name, key)
        if type(name) == "string" and name ~= "" then
            profByName[name] = key
            profByName[ns.Fold(name)] = key
        end
    end
    for key in pairs(ns.TRACKED) do add(key, key) end
    for _, names in pairs(ns.PROF_NAMES or {}) do
        for key, name in pairs(names) do add(name, key) end
    end
    -- the other spellings the clients use (TBC's and Mists' differ in places)
    for _, aliases in pairs(ns.PROF_ALIASES or {}) do
        for key, list in pairs(aliases) do
            for _, name in ipairs(list) do add(name, key) end
        end
    end
    -- and the client's own name for each skill line, whatever its language
    local display = C_TradeSkillUI and C_TradeSkillUI.GetTradeSkillDisplayName
    if display then
        for id, key in pairs(ns.SKILL_LINES) do
            local ok, name = pcall(display, id)
            if ok then add(name, key) end
        end
    end
    return profByName
end
function ns.ProfKey(name, id)
    if id ~= nil then
        local ok, key = pcall(function() return ns.SKILL_LINES[id] end)
        if ok and key then return key end
    end
    if type(name) ~= "string" then return nil end
    local names = ProfNames()
    return names[name] or names[ns.Fold(name)]
end
-- a profession, a rank, as this client writes them: the name the game
-- gave for it in a scan, else the one it gives for the skill line, else
-- Locales.lua's for this client (a profession not learned yet has no scan)
ns.profLabels = {}
function ns.ProfLabel(key)
    if ns.profLabels[key] then return ns.profLabels[key] end
    local display = C_TradeSkillUI and C_TradeSkillUI.GetTradeSkillDisplayName
    if display then
        for id, k in pairs(ns.SKILL_LINES) do
            if k == key then
                local ok, name = pcall(display, id)
                if ok and type(name) == "string" and name ~= "" then return name end
            end
        end
    end
    local client = ns.PROF_NAMES_FOR and ns.PROF_NAMES_FOR[ns.CLIENT]
    local names = client and client[ns.LOCALE]
    if names and names[key] then return names[key] end
    names = ns.PROF_NAMES[ns.LOCALE]
    return names and names[key] or key
end
function ns.RankLabel(rank)
    local names = ns.RANK_NAMES[ns.LOCALE]
    return names and names[rank] or rank
end

-- a gathering tier on this client: the node names Locales.lua has, else
-- the herb's item name from the game, else the English (Forever's starter
-- nodes are named in English only)
function ns.TierName(tier)
    local nodes = ns.NODE_NAMES[ns.LOCALE]
    if ns.LOCALE == "enUS" then
        if ns.IS_FOREVER and tier.forever then return tier.forever end
        -- only renames (Mists: Plaguebloom is Sorrowmoss)
        if not nodes then return tier[2] end
    end
    local names = Split(tier[2])
    for i, name in ipairs(names) do
        names[i] = (nodes and nodes[name]) or (ns.LOCALE ~= "enUS" and tier.items and ItemName(tier.items[i])) or name
    end
    return table.concat(names, " / ")
end

-- A route row's recipes - its " / " alternatives - as this game names
-- them: through their spells, else the English (TBC's where it differs)
function ns.RowAlts(row)
    local names = Split((ns.IS_TBC and row.tbc) or row[2])
    local ids = row.spell
    if type(ids) == "number" then ids = {ids} end
    if type(ids) == "table" then
        for i, id in ipairs(ids) do names[i] = SpellName(id) or names[i] end
    end
    return names
end
function ns.RowName(row)
    return table.concat(ns.RowAlts(row), " / ")
end

local function Reagents(list)
    local parts = {}
    for _, r in ipairs(list) do
        local name = ItemName(r[1])
        if not name then return nil end
        parts[#parts + 1] = r[2] .. " " .. name
    end
    return table.concat(parts, " + ")
end
-- A row's mats, named by the game (the English text until the items are
-- cached); for a row of alternatives and a chosen recipe, only that
-- recipe's part; alternatives with the same mats are written once
function ns.RowMats(row, recipe, known)
    local reag = (ns.IS_TBC and row.tbcReagents) or row.reagents
    local parts
    if type(reag) == "table" and type(reag[1]) == "table" then
        local lists = type(reag[1][1]) == "table" and reag or {reag}
        parts = {}
        for i, list in ipairs(lists) do
            parts[i] = Reagents(list)
            if not parts[i] then parts = nil break end
        end
        if parts and row.makes and #parts == 1 then
            parts[1] = parts[1] .. " " .. string.format(L["(makes %s)"], tostring(row.makes))
        end
    end
    if not parts then
        local text = (ns.IS_TBC and row.tbcMats) or row[3]
        if not text then return nil end
        parts = Split(text)
    end
    local alts = ns.RowAlts(row)
    if recipe and #parts > 1 and #parts == #alts then
        for i, a in ipairs(alts) do
            if a == recipe or (known and ns.ResolveRecipe(known, a) == recipe) then return parts[i] end
        end
    end
    local out, seen = {}, {}
    for _, m in ipairs(parts) do
        if not seen[m] then seen[m] = true; out[#out + 1] = m end
    end
    return table.concat(out, " / ")
end
-- Where to get a row's recipe; TBC's trainers teach some that Era sells
-- (tbcSource = "" means the trainer has it, nothing to say)
function ns.RowSource(row)
    local source = row.source or row.recipe
    if ns.IS_TBC and row.tbcSource ~= nil then source = row.tbcSource end
    if source == "" then return nil end
    return source
end
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
ns.Plain = Plain

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
local function Record(found, name, rank, maxRank, source, id)
    local shown = name
    name = ns.ProfKey(name, id)
    if not (name and ns.TRACKED[name]) then return end
    if type(shown) == "string" and shown ~= "" then ns.profLabels[name] = shown end
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
--   src.count() -> n;  src.line(i) -> name, isHeader, isFolded, rank, maxRank, id
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
        local name, isHeader, _, rank, maxRank, id = src.line(i)
        if not isHeader then Record(found, name, rank, maxRank, source, id) end
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
            return info.name, info.isHeader, info.isCollapsed, info.rank, info.maxRank, info.skillID
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
            -- nil where a slot is empty (no second profession, no
            -- archaeology): every slot is read, not up to the first gap
            local ids = {GetProfessions()}
            for slot = 1, 6 do
                local id = ids[slot]
                if id then
                    local okP, name, _, rank, maxRank, _, _, skillLine = pcall(GetProfessionInfo, id)
                    if okP then Record(found, name, rank, maxRank, "GetProfessions", skillLine) end
                end
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
-- match"). Exact key: lowercase, without spaces and punctuation. Loose
-- key: also without the word "enchant" and a plural s on each word.
-- Lua's character classes know only ASCII: "[^%w]" also threw away every
-- letter of a Russian or Chinese name (all keys came out "", so any recipe
-- matched any), hence only ASCII spaces and punctuation go, and names
-- with other letters are matched exactly.
local function Key(name)
    local plain = tostring(name):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    -- ASCII spaces and punctuation only (by byte, not by class)
    return (ns.Fold(plain):gsub("[%z\1-\47\58-\64\91-\96\123-\127]", ""))
end
local function LooseKey(name)
    local plain = tostring(name):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    if plain:find("[\128-\255]") then return Key(plain) end
    local words = {}
    for w in ns.Fold(plain):gmatch("[a-z]+") do
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
-- The craft routes in Data.lua are written for each game, but a patch can
-- move a recipe's skill-up range: a report had Linen Bag no longer giving
-- skill-ups at 63 Tailoring and Enchant Bracer - Minor Stamina likewise,
-- "last week's patch" (it was WoW Forever, then on Classic Era's route,
-- where Linen Bag greys at 65). The game itself knows: every
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

-- Records one window's worth: list = {{name, diff, learned}, ...}.
-- A window can show only part of what is known: a folded header, "Have
-- Materials", a name search, Forever's skill-up and slot filters. So what
-- it shows is added to what was known, never put in its place (else the
-- route's recipe would drop out and read as "You don't know this recipe
-- yet!"). A lower skill than last time, in the window's own words, means
-- the profession was dropped and learned again: then the list starts
-- over. (Only its own words: the skills list can lag a point behind.)
-- given = the skill the window states; without one (or a secret one, or
-- 0 while it loads) the skills list's is used.
local function RecordWindow(prof, given, list)
    local own = Plain(given)
    if own and own <= 0 then own = nil end
    local rank = own or (ns.profs and ns.profs[prof] and ns.profs[prof].rank)
    local db = ns.db
    db.knownRecipes = db.knownRecipes or {}
    db.recipeRank = db.recipeRank or {}
    local known, last = db.knownRecipes[prof], db.recipeRank[prof]
    if type(known) ~= "table" or (own and type(last) == "number" and own < last) then
        known = {}
    end
    local store = ColorStore(prof)
    for _, e in ipairs(list) do
        if e.learned ~= false then
            known[e.name] = e.diff
            NoteColor(store, e.name, e.diff, rank)
        end
    end
    db.knownRecipes[prof] = known
    db.allRecipes = nil -- 1.0.0 dropped the "not in this game" list
    db.recipeRank[prof] = rank
    -- the window's skill is the freshest there is: a skill-up while
    -- crafting reaches it before the skills list, so the advice moves on
    -- with the colours it was given
    local p = ns.profs and ns.profs[prof]
    if p and type(rank) == "number" and rank > p.rank then p.rank = rank end
    -- the item tooltips (Inventory.lua) build their plan again
    ns.dataVersion = (ns.dataVersion or 0) + 1
end

-- true when an optional game function exists and says yes
local function Says(fn)
    if type(fn) ~= "function" then return false end
    local ok, v = pcall(fn)
    return ok and v == true
end

-- The window shows someone else's recipes (a linked profession, a guild
-- list, an NPC crafting for you): reading it would overwrite the player's
-- own. Classic clients have the global; Forever the C_TradeSkillUI ones.
local function ForeignWindow()
    local api = C_TradeSkillUI
    return Says(IsTradeSkillLinked) or
               (api and (Says(api.IsTradeSkillLinked) or Says(api.IsTradeSkillGuild) or Says(api.IsNPCCrafting))) or false
end

-- the open profession's name on Forever: GetChildProfessionInfo always
-- hands a table back, an empty one (professionID 0) when there is no
-- child, and Blizzard then reads GetBaseProfessionInfo; the name players
-- see is parentProfessionName, else professionName
local function OpenProfession(api)
    local ok, prof, info = pcall(function()
        local i = api.GetChildProfessionInfo and api.GetChildProfessionInfo()
        if type(i) ~= "table" or i.professionID == 0 then
            i = api.GetBaseProfessionInfo and api.GetBaseProfessionInfo()
        end
        if type(i) ~= "table" then return end
        -- by skill-line ID first (the base line, e.g. 197), then by name
        local key = ns.ProfKey(i.parentProfessionName, i.parentProfessionID) or
                        ns.ProfKey(i.professionName, i.professionID)
        if key and ns.TRACKED[key] then return key, i end
    end)
    if ok then return prof, info end
end

-- Forever (and retail) keep recipes behind C_TradeSkillUI. GetAllRecipeIDs
-- lists every recipe of the open profession, learned or not, whatever the
-- window's filters (measured in game on Forever 1.60.1); Blizzard's window
-- draws GetFilteredRecipeIDs instead, which leaves out what the player's
-- "has skill up" / "makeable" / slot filters and search hide - a known
-- recipe missing from it read as "You don't know this recipe yet!". So the
-- full list first, the filtered one only where a client lacks it (and then
-- RecordWindow's adding, never replacing, keeps what was seen before).
-- Each recipe carries a learned flag and its colour.
local function ScanTradeSkillUI()
    local api = C_TradeSkillUI
    if not (api and api.GetRecipeInfo and (api.GetFilteredRecipeIDs or api.GetAllRecipeIDs)) then return end
    -- a list still being built is skipped, as Blizzard's window does
    if api.IsTradeSkillReady and not Says(api.IsTradeSkillReady) then return end
    if Says(api.IsDataSourceChanging) or ForeignWindow() then return end
    local prof, info = OpenProfession(api)
    if not prof then return end
    local ids
    for _, source in ipairs({"GetAllRecipeIDs", "GetFilteredRecipeIDs"}) do
        if not ids and api[source] then
            local okIds, got = pcall(api[source])
            if okIds and type(got) == "table" and #got > 0 then
                ids = got
                ns.recipeAPI = source
            end
        end
    end
    if not ids then return end
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
    ns.db.recipeFiltered = ns.db.recipeFiltered or {}
    ns.db.recipeFiltered[prof] = ns.recipeAPI == "GetFilteredRecipeIDs" or nil
    RecordWindow(prof, info.skillLevel, list)
    ns.UpdateUI()
    return true
end

function ns.ScanOpenTradeSkill()
    -- Forever's window is C_TradeSkillUI's, whatever old globals linger
    if ns.IS_FOREVER or not (GetTradeSkillLine and GetNumTradeSkills) then
        return ScanTradeSkillUI()
    end
    if ForeignWindow() then return end
    local line, rank = GetTradeSkillLine()
    local prof = ns.ProfKey(line)
    if not prof or not ns.TRACKED[prof] then return end
    local list = {}
    for i = 1, GetNumTradeSkills() or 0 do
        local rname, rtype = GetTradeSkillInfo(i)
        if rname and not NOT_RECIPE[rtype] then
            list[#list + 1] = {name = rname, diff = Difficulty(rtype)}
        end
    end
    if #list == 0 then return end
    ns.recipeAPI = "GetTradeSkillInfo"
    RecordWindow(prof, rank, list)
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
        -- Classic: name, subText, serviceType, isExpanded
        -- Forever: name, serviceType, texture, reqLevel, subText, category
        local okI, name, second, third = pcall(GetTrainerServiceInfo, i)
        local serviceType = ns.IS_FOREVER and second or third
        local okR, skill, level = pcall(GetTrainerServiceSkillReq, i)
        level = okR and Plain(level)
        skill = okR and ns.ProfKey(skill)
        if okI and okR and type(name) == "string" and serviceType ~= "header" and
            type(skill) == "string" and ns.TRACKED[skill] and level then
            reqs[skill] = reqs[skill] or {}
            reqs[skill][name] = level
            seen = seen + 1
        end
    end
    if seen == 0 then return end
    ns.db.recipeReq = reqs
    ns.dataVersion = (ns.dataVersion or 0) + 1 -- the item tooltips' plan too
    ns.UpdateUI()
    return seen
end

-- the name a profession's own lists use for a route recipe, looked up
-- exactly first and loosely second; nil when no list has it
local function Resolve(map, recipe)
    if not map then return nil end
    if map[recipe] ~= nil then return recipe end
    local k, lk = Key(recipe), LooseKey(recipe)
    if k == "" then return nil end
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
    local line, rank = GetCraftDisplaySkillLine()
    local prof = ns.ProfKey(line)
    if not prof or not ns.TRACKED[prof] then return end
    local list = {}
    for i = 1, GetNumCrafts() or 0 do
        local rname, _, rtype = GetCraftInfo(i)
        if rname and not NOT_RECIPE[rtype] then
            list[#list + 1] = {name = rname, diff = Difficulty(rtype)}
        end
    end
    if #list == 0 then return end
    ns.recipeAPI = "GetCraftInfo"
    RecordWindow(prof, rank, list)
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
    if sure or seenRank == rank then return L[ns.COLOR_WORD[c]] end
    return string.format(L["%s at %d"], L[ns.COLOR_WORD[seenC]], seenRank)
end

-- the skill a route row really needs: the row's own number, unless the
-- trainer said every one of its alternatives needs more - then the least
-- of those (either alternative will do, so the cheapest to reach counts)
function ns.RouteRowNeeds(prof, row)
    local lowest
    for _, alt in ipairs(ns.RowAlts(row)) do
        local said = ns.RecipeRequirement(prof, alt)
        if not said then return row[1] end
        if not lowest or said < lowest then lowest = said end
    end
    return math.max(row[1], lowest or row[1])
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
        for _, alt in ipairs(ns.RowAlts(row)) do
            local name = Resolve(known, alt)
            if name then rowOf[name] = row end
        end
    end
    -- only a colour that holds now: pinned down at this skill, or seen at
    -- most 5 points back (orange seen at 20 says nothing about 98)
    local best, bestO, bestRow
    for recipe in pairs(known) do
        local c, sure, _, seenRank = ns.RecipeColor(prof, recipe, rank)
        local o = c and (sure or (type(rank) == "number" and rank - seenRank <= 5)) and ORDER[c]
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
            return string.format(L["finishing %s"], gname)
        end
    end
    local zone = (GetRealZoneText and GetRealZoneText()) or
                     (GetZoneText and GetZoneText())
    if zone and zone ~= "" then return string.format(L["leaving %s"], zone) end
    return L["moving on"]
end

-- "In Redridge Mountains: Lake Everstill" - but only when the current zone
-- has the right kind of water AND the fish actually lives at this zone's
-- level (no catfish in starter-zone lakes)
-- The ZONE_WATERS entry for where the player is, and the zone's name as
-- the game writes it: by map ID (any language), else by English zone name.
function ns.CurrentZone()
    local api = C_Map
    if api and api.GetBestMapForUnit then
        local ok, map = pcall(api.GetBestMapForUnit, "player")
        -- a sub-zone map (a cave, a starting area) is walked up to its zone
        for _ = 1, 4 do
            if not (ok and map) then break end
            for key, waters in pairs(ns.ZONE_WATERS) do
                if waters.map == map then
                    local okI, info = pcall(api.GetMapInfo, map)
                    return key, waters, okI and type(info) == "table" and info.name or key
                end
            end
            local okP, info = pcall(api.GetMapInfo, map)
            map = okP and type(info) == "table" and info.parentMapID
        end
    end
    local zone = (GetRealZoneText and GetRealZoneText()) or ""
    if ns.ZONE_WATERS[zone] then return zone, ns.ZONE_WATERS[zone], zone end
end

-- a zone's name as this game writes it: by its map ID (Mists numbers
-- its maps otherwise, so the English there), else the English
function ns.ZoneName(key)
    if ns.LOCALE == "enUS" or ns.CLIENT == "later" then return key end
    local map = (ns.ZONE_WATERS[key] and ns.ZONE_WATERS[key].map) or (ns.ZONE_MAPS and ns.ZONE_MAPS[key])
    local api = C_Map
    if map and api and api.GetMapInfo then
        local ok, info = pcall(api.GetMapInfo, map)
        if ok and type(info) == "table" and type(info.name) == "string" and info.name ~= "" then return info.name end
    end
    return key
end

-- where a fish is caught, in the player's language
function ns.FishWhere(entry)
    local zones = {}
    for i, key in ipairs(entry.whereZones or {}) do zones[i] = ns.ZoneName(key) end
    local text = L[entry.where]
    if #zones > 0 then text = string.format(text, table.concat(zones, ", ")) end
    return text
end

function ns.ZoneWaterSpot(entry)
    local zone, waters, label = ns.CurrentZone()
    if not waters then return end
    local spot = entry.water and waters[entry.water]
    if not spot then return end
    if entry.zones and not entry.zones[zone] then return end
    -- the spot names are English; elsewhere just "the inland waters"
    if ns.LOCALE ~= "enUS" then spot = entry.water == "coast" and L["the coast"] or L["the inland waters"] end
    if entry.band and waters.lvl then
        if waters.lvl < entry.band[1] or waters.lvl > entry.band[2] then
            return
        end
    end
    return string.format(L["In %s: %s"], label, spot)
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
    if note.clients and not note.clients[ns.CLIENT] then return false end
    if note.req or note.gate then
        if note.req and rank < note.req then return false end
        if note.gate and maxRank > note.gate then return false end
        return true
    end
    return rank >= note[1] - 40 and rank < note[1] + 15
end

local function RankInfo(maxRank)
    for _, r in ipairs(ns.RANKS) do
        if maxRank <= r.cap then
            -- no Master on Classic Era or Forever (Artisan is the last
            -- rank), no Grand Master on TBC
            if (r.fromTBC and not ns.HAS_MASTER) or (r.later and not ns.HAS_LATER_RANKS) then return {cap = r.cap} end
            return r
        end
    end
end

-- what the next rank asks besides skill: {level = n} for a trainer's
-- character level, {how = "book" | "quest", skill = n} where it is not a
-- trainer's to give (First Aid, Cooking, Fishing)
function ns.RankRule(name, kind, nextRank)
    local this = ns.RANK_RULES_FOR[ns.CLIENT]
    local rule = this and this[name] and this[name][nextRank]
    if rule then return rule end
    local own = ns.RANK_RULES[name]
    if own then return ns.BOOK_RANKS and own[nextRank] or {} end
    local rules = kind == "craft" and ns.RANK_RULES.craft
    return rules and rules[nextRank] or {}
end

-- Capped at the last rank this game has: nothing is left to skill up.
function ns.IsFinalCap(p)
    local rank = RankInfo(p.maxRank)
    return p.rank >= p.maxRank and rank ~= nil and not rank.nextRank
end

-- Where the player stands on a profession's craft route: the row to craft
-- now, the next row they can learn and the skill it starts at, and a row
-- the trainer said comes later than the route claims. The window and the
-- item tooltips (Inventory.lua) both read this, so they never disagree.
-- nil for a profession without a craft route (gathering, Fishing).
--   {route, current, nextUp, nextAt, tooEarly, fishCombo}
-- needs = ns.RouteRowNeeds or a stand-in for it (the tooltips pass one
-- that remembers its answers while they walk the route)
function ns.RoutePosition(name, p, needs)
    local Needs = needs or ns.RouteRowNeeds
    local craft = ns.CRAFT[name]
    if not craft then return nil end
    local route = craft.route
    local fishCombo = name == "Cooking" and ns.FishCookCombo()
    if fishCombo then route = ns.FISH_COOKING end
    local current, nextUp = CurrentAndNext(route, p.rank)
    -- a row whose recipe the trainer sells only at a higher skill
    -- than the row claims is a tier early: step back to the last
    -- row the player can actually have learned
    local tooEarly
    while current and Needs(name, current) > p.rank do
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
    -- the next row the player can learn, at the skill the trainer named
    -- if it named one; after a step-back a later row can come sooner than
    -- the stepped-back one
    local nextAt
    if nextUp then
        nextAt = Needs(name, nextUp)
        local after = current == nil
        for _, tier in ipairs(route) do
            if after then
                local n = Needs(name, tier)
                if n > p.rank and n < nextAt then nextUp, nextAt = tier, n end
            end
            if tier == current then after = true end
        end
    end
    return {route = route, current = current, nextUp = nextUp, nextAt = nextAt, tooEarly = tooEarly,
            fishCombo = fishCombo}
end

-- What to craft at the route's current row. The row's alternatives the
-- player knows, the best-coloured one first, with its colour at the skill
-- they are at now. And whether the game outranks the route: when it shows
-- the route's recipe grey (no skill-ups), or green while the player knows
-- something orange or yellow, the better recipe is the one to craft. (A
-- report: Linen Bag at 63 Tailoring and Enchant Bracer - Minor Stamina at
-- 63 Enchanting, both past their skill-ups after a patch, still
-- recommended.) The window and the item tooltips both read this.
function ns.CraftNow(name, p, current)
    local now = {knownMap = ns.GetKnownRecipes(name), anyKnown = false}
    for _, alt in ipairs(ns.RowAlts(current)) do
        local known = ns.ResolveRecipe(now.knownMap, alt)
        if known then
            local c = ns.RecipeColor(name, known, p.rank)
            if not now.anyKnown or (ORDER[c] or 9) < (ORDER[now.routeColor] or 9) then
                now.routeName, now.routeColor = known, c
            end
            now.anyKnown = true
        end
    end
    now.routeO = ORDER[now.routeColor]
    now.best, now.bestColor, now.bestRow = ns.BestKnownRecipe(name, p.rank)
    now.takeBest = (now.anyKnown and now.routeO and now.best and now.best ~= now.routeName and
                       (now.routeO == 3 or (now.routeO == 2 and ORDER[now.bestColor] <= 1))) and true or false
    return now
end

-- Returns a list of {text, style} lines for one profession.
-- style: "head" | "normal" | "good" | "warn" | "dim"
function ns.BuildProfLines(name, p)
    local lines = {}
    local function add(text, style)
        table.insert(lines, {text = text, style = style or "normal"})
    end

    local label = ns.ProfLabel(name)
    if p.unlearned then
        add(label, "head")
        add(L["Not learned yet - train with:"], "warn")
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
            if capital then add(string.format(L["or: %s"], capital), "dim") end
        elseif capital then
            add(capital, "normal")
        end
        add(L["(any city guard can mark trainers on your map)"], "dim")
        return lines
    end

    add(string.format("%s  %d/%d", label, p.rank, p.maxRank), "head")

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
                    milestone, milestoneName = nextUp[1], ns.TierName(nextUp)
                end
            else
                local craftDef = ns.CRAFT[name]
                local route = craftDef and craftDef.route
                if name == "Cooking" and ns.FishCookCombo() then
                    route = ns.FISH_COOKING
                end
                local _, nextUp = route and CurrentAndNext(route, p.rank)
                if nextUp then
                    milestone, milestoneName = nextUp[1], ns.RowName(nextUp)
                end
            end
            local context = GuideContext()
            if milestone and milestone <= pace then
                add(string.format(L["Aim for %d (%s) before %s"], milestone,
                                  milestoneName, context), "warn")
            else
                add(string.format(L["Catch up toward ~%d before %s"], pace,
                                  context), "warn")
            end
        end
    end

    -- trainer / cap advice: the next rank at its skill and character
    -- level, from a trainer - or from a book or a quest (First Aid,
    -- Cooking, Fishing), which the notes below name
    local rank = RankInfo(p.maxRank)
    local capped = p.rank >= p.maxRank
    local nextRank = rank and rank.nextRank
    local rule = nextRank and ns.RankRule(name, p.kind, nextRank) or {}
    local trainAt = rule.skill or (rank and rank.trainAt)
    local rankLabel = nextRank and ns.RankLabel(nextRank)
    local tooLow = rule.level and level < rule.level and
                       string.format(L[" - needs character level %d (you're %d)"], rule.level, level) or ""
    -- each sentence whole, so it can be translated whole
    local fromItem = rule.how == "book" and string.format(L["%s %s comes from a book - see below"], rankLabel, label) or
                         rule.how == "quest" and string.format(L["%s %s comes from a quest - see below"], rankLabel, label) or nil
    local atTrainer = name:find("^[AEIOU]") and L["Train %s at an %s trainer"] or L["Train %s at a %s trainer"]
    -- the last rank there is on this game, and capped at it
    local finalCap = capped and rank ~= nil and not nextRank
    if nextRank and p.rank >= (trainAt or math.huge) then
        if capped then
            add(string.format(L["Capped! %s"], fromItem or string.format(atTrainer, rankLabel, label)) .. tooLow, "warn")
        elseif tooLow ~= "" then
            add(string.format(L["%s at %d"], rankLabel, trainAt) .. tooLow, "warn")
        else
            add(fromItem or string.format(L["Can train %s now (%d needed)"], rankLabel, trainAt), "good")
        end
    elseif capped then
        add(L["Skill capped for this expansion"], "dim")
    elseif nextRank and p.maxRank - p.rank <= 10 then
        local soon = rule.how == "book" and L["Cap soon - %s comes from a book at %d"] or
                         rule.how == "quest" and L["Cap soon - %s comes from a quest at %d"] or L["Cap soon - train %s at %d"]
        add(string.format(soon, rankLabel, trainAt) .. tooLow, "warn")
    end

    -- what to do right now
    if p.kind == "gather" then
        local gather = ns.GATHER[name]
        local current, nextUp = CurrentAndNext(gather.tiers, p.rank)
        if current then
            add(string.format(L[gather.verb .. ": %s"], ns.TierName(current)), "normal")
        end
        if nextUp then
            add(string.format(L["At %d: %s"], nextUp[1], ns.TierName(nextUp)), "dim")
        end
    elseif p.kind == "craft" then
        local craft = ns.CRAFT[name]
        if craft and finalCap then
            add(L["Nothing left to skill up here - craft only what you need"], "dim")
        elseif craft then
            -- where the player stands on the route, the same answer the
            -- item tooltips give (Inventory.lua)
            local pos = ns.RoutePosition(name, p)
            local current, nextUp, tooEarly, fishCombo = pos.current, pos.nextUp, pos.tooEarly, pos.fishCombo
            if fishCombo then
                add(L["Combo: cooking your Fishing catches"], "good")
            end
            if current then
                local now = ns.CraftNow(name, p, current)
                local knownMap, routeName, routeColor, anyKnown = now.knownMap, now.routeName, now.routeColor, now.anyKnown
                local display = routeName or ns.RowName(current)
                local routeO = now.routeO
                local best, bestColor, bestRow = now.best, now.bestColor, now.bestRow
                local takeBest = now.takeBest
                if takeBest then
                    add(string.format(L["Craft: %s (%s)"], best, ns.ColorText(name, best, p.rank) or L[ns.COLOR_WORD[bestColor]]), "normal")
                    -- grey: the game moved it; green: it only skills up some
                    -- of the time (many rows end on a few green points)
                    add(string.format(routeO == 3 and L["(%s is %s for you now - the game moved it, so this beats the route)"] or
                                          L["(%s is %s for you now and only skills up some of the time, so this beats the route)"],
                                      routeName, ns.ColorText(name, routeName, p.rank) or L[ns.COLOR_WORD[routeColor]]), "dim")
                    local bestMats = bestRow and ns.RowMats(bestRow, best, knownMap)
                    if bestMats then add(string.format(L["Mats: %s"], bestMats), "dim") end
                else
                    local colorText = routeName and ns.ColorText(name, routeName, p.rank)
                    add(colorText and string.format(L["Craft: %s (%s)"], display, colorText) or string.format(L["Craft: %s"], display), "normal")
                    if routeO == 3 then
                        add(L["It gives no skill-ups any more, and you know nothing better - check your trainer for new recipes"], "warn")
                    elseif routeO == 2 then
                        add(L["Green: it only skills up some of the time"], "dim")
                    end
                    if tooEarly then
                        add(string.format(L["(%s needs %d - your trainer said so)"], ns.RowName(tooEarly),
                                          ns.RouteRowNeeds(name, tooEarly)), "dim")
                    end
                    -- the route's recipe is not known, but one that is still
                    -- gives skill-ups: say so rather than send them shopping
                    if knownMap and not anyKnown and best then
                        add(string.format(L["Meanwhile: %s (%s)"], best, ns.ColorText(name, best, p.rank) or L[ns.COLOR_WORD[bestColor]]), "good")
                    end
                    if fishCombo then
                        add(string.format(L["Mats: %s"], ItemName(current.fishItem) or current.fish), "dim")
                        local spot = ns.ZoneWaterSpot(current)
                        if spot then
                            add(spot, "good")
                        else
                            add(string.format(L["(fish: %s)"], ns.FishWhere(current)), "dim")
                        end
                    elseif ns.RowMats(current) then
                        add(string.format(L["Mats: %s"], ns.RowMats(current, routeName, knownMap)), "dim")
                    end
                    local source = ns.RowSource(current)
                    if type(source) == "table" then
                        local faction = UnitFactionGroup and
                                            UnitFactionGroup("player")
                        source = faction == "Horde" and source.H or source.A
                    end
                    if knownMap and not anyKnown then
                        local need = ns.RecipeRequirement(name, display)
                        if need and need > p.rank then
                            add(string.format(L["Learn it at %d from your trainer"], need), "warn")
                        elseif ns.db.recipeFiltered and ns.db.recipeFiltered[name] then
                            -- the list came through the window's filters
                            add(L["Not in your window's list - if you know it, clear the window's filters once"], "warn")
                            add(string.format(L["Get it: %s"], source or L["check your trainer / recipe vendors"]), "dim")
                        else
                            add(L["You don't know this recipe yet!"], "warn")
                            add(string.format(L["Get it: %s"], source or L["check your trainer / recipe vendors"]), "warn")
                        end
                    elseif not knownMap then
                        if source then
                            add(string.format(L["Get it: %s"], source), "dim")
                        end
                        add(string.format(L["(open your %s window once so I can check these recipes against your game)"],
                                          label), "dim")
                    end
                end
            end
            if nextUp then
                add(string.format(L["At %d: %s"], pos.nextAt, ns.RowName(nextUp)), "dim")
            end
            for _, note in ipairs(craft.notes or {}) do
                if NoteVisible(note, p.rank, p.maxRank) then
                    add(ForFaction(note[2]), "warn")
                end
            end
            if craft.primary and ns.db and ns.db.useAH then
                add(L["Tip: buy missing mats from the Auction House"], "dim")
            end
        end
    elseif p.kind == "fishing" then
        if ns.FishCookCombo() then
            -- steer the fishing spot by what Cooking needs next
            local cooking = ns.profs["Cooking"] or {rank = 0}
            local current, nextUp = CurrentAndNext(ns.FISH_COOKING,
                                                   cooking.rank)
            if current then
                add(string.format(L["Catch: %s"], ItemName(current.fishItem) or current.fish), "normal")
                local spot = ns.ZoneWaterSpot(current)
                if spot then
                    add(spot, "good")
                else
                    add(string.format(L["Where: %s"], ns.FishWhere(current)), "dim")
                end
                add(L["(feeds your Cooking bracket)"], "dim")
            end
            if nextUp then
                add(string.format(L["Later (Cooking %d): %s"], nextUp[1],
                                  ItemName(nextUp.fishItem) or nextUp.fish), "dim")
            end
        elseif finalCap then
            add(L["Fishing is maxed - fish wherever your catches are"], "normal")
        else
            add(L["Fish anywhere - each catch can skill up"], "normal")
            add(L["Higher-level zones need higher skill (use lures)"], "dim")
        end
        -- fish escape when the zone needs more skill than you have; escaped
        -- catches give no skill, so this is the one real fishing mistake
        -- (until patch 3.1: on Mists every cast lands something)
        local _, waters, zoneLabel = ns.CurrentZone()
        if waters and waters.minskill and ns.CLIENT ~= "later" then
            if p.rank < waters.minskill then
                add(string.format(L["Fish escape here! %s needs ~%d skill (you: %d)"],
                                  zoneLabel, waters.minskill, p.rank), "warn")
            else
                add(string.format(L["Skill OK for %s (needs %d)"], zoneLabel,
                                  waters.minskill), "dim")
            end
        end
        for _, note in ipairs(ns.FISHING_NOTES) do
            if NoteVisible(note, p.rank, p.maxRank) then
                add(ForFaction(note[2]), "warn")
            end
        end
    elseif p.kind == "skinning" then
        -- the highest beast you can skin: level 10 + skill/10 below skill
        -- 100, skill/5 from there (Classic's rule; a report would tell if
        -- Forever's differs)
        local maxLevel = p.rank < 100 and 10 + math.floor(p.rank / 10) or math.floor(p.rank / 5)
        add(string.format(L["Skin your kills (up to ~level %d mobs)"], maxLevel),
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
                    ns.Print(L["|cFF66FF66%s unlocked:|r you can now gather %s!"],
                             ns.ProfLabel(name), ns.TierName(tier))
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
    "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_DATA_SOURCE_CHANGED", "CRAFT_SHOW", "CRAFT_UPDATE",
    "TRAINER_SHOW", "TRAINER_UPDATE", "GET_ITEM_INFO_RECEIVED", "SPELL_DATA_LOAD_RESULT"
}
ns.missingEvents = {}
for _, event in ipairs(EVENTS) do
    local ok = pcall(eventFrame.RegisterEvent, eventFrame, event)
    if not ok then table.insert(ns.missingEvents, event) end
end
-- (on Forever the list event can come while the window's data is still
-- being swapped: the scan then waits, as Blizzard's window does, for a
-- later one - or for TRADE_SKILL_DATA_SOURCE_CHANGED, which ends the swap)
local TRADE_EVENTS = {TRADE_SKILL_SHOW = true, TRADE_SKILL_UPDATE = true, TRADE_SKILL_LIST_UPDATE = true,
                      TRADE_SKILL_DATA_SOURCE_CHANGED = true}
eventFrame:SetScript("OnEvent", function(_, event)
    if event == "GET_ITEM_INFO_RECEIVED" or event == "SPELL_DATA_LOAD_RESULT" then
        -- an item or spell name the window asked for has arrived: redraw
        -- once, a moment later, however many arrive together
        if ns.db and not ns.itemRedraw then
            ns.itemRedraw = true
            local function redraw() ns.itemRedraw = nil; ns.UpdateUI() end
            if C_Timer and C_Timer.After then C_Timer.After(0.3, redraw) else redraw() end
        end
        return
    elseif TRADE_EVENTS[event] then
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
    elseif input == "tooltip" or input == "tooltiplater" or input == "tooltipothers" then
        ns.ToggleTooltipSetting(input)
    elseif input:sub(1, 4) == "need" and ns.PrintNeeds then
        ns.PrintNeeds(input:sub(5))
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
        ns.Print("client language: %s", tostring(ns.LOCALE))
        -- when each profession's recipe list was last read from its window
        local read = {}
        for prof, rank in pairs(ns.db.recipeRank or {}) do
            local n = 0
            for _ in pairs(ns.GetKnownRecipes(prof) or {}) do n = n + 1 end
            read[#read + 1] = string.format("%s %d recipes at skill %d", prof, n, rank)
        end
        table.sort(read)
        ns.Print("recipe colours read: %s%s", #read > 0 and table.concat(read, ", ")
                     or "none yet - open a profession window once",
                 ns.recipeAPI and (" (last through " .. ns.recipeAPI .. ")") or "")
        if #ns.missingEvents > 0 then
            ns.Print("events this client lacks (skipped): %s", table.concat(ns.missingEvents, ", "))
        end
        if ns.TooltipStatus then ns.Print("%s", ns.TooltipStatus()) end
    else
        ns.Print(L["commands: |cFFFFCC00/rxpp|r toggle the window, |cFFFFCC00/rxpp setup|r choose professions, |cFFFFCC00/rxpp status|r what the client gives us"])
        ns.Print(L["item tooltips: |cFFFFCC00/rxpp tooltip|r on or off, |cFFFFCC00/rxpp tooltip later|r the spans after the one you are in, |cFFFFCC00/rxpp tooltip others|r the professions you did not pick"])
    end
end
