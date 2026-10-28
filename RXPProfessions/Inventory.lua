-- RestedXP Professions - item tooltips: what your profession plan needs
--
-- Hovering an item shows, for each profession whose route uses it, one
-- line per skill span: the span you are in ("Now", counted from your
-- skill) and the spans after it, each with how many of what you have go
-- to it against what it needs - "70-100 · 19 (bags 4 · bank 15) of ~69 ·
-- Woolen Cape". What you have goes to "Now" first, then to the spans
-- after it, bags before bank; a last line gives the total and what is to
-- spare or short. Only the professions you picked in /rxpp setup count;
-- with /rxpp tooltip others the rest show in a grey section of their own,
-- with what they need and nothing handed out.
--
-- A span is a row of the route (Data.lua), for as long as the window
-- shows that row. The spans are read through ns.RoutePosition, as the
-- window reads the route: "Now" at your skill, each later span at the
-- skill the one before it ends at. So the tooltip and the window always
-- name the same row, and a row the trainer moved past the rows after it
-- is skipped exactly as the window skips it. Counts assume one craft per
-- skill point, which orange recipes give, so they are marked "~".
--
-- A reagent the route itself makes (Bolt of Woolen Cloth for Woolen Cape,
-- Heavy Grinding Stone for Green Iron Leggings) is followed down to what
-- it is made of: Wool Cloth shows the Woolen Cape span too, "via" the
-- bolt. What an earlier span makes, and what you already have of it, is
-- used first, so nothing is counted twice. A reagent another profession
-- you picked makes on its own route (Forever's Elixir of Defense, which
-- Leatherworking uses) is taken from what that route makes before what
-- it is made of is counted again. The route's own mats text ("1 Bolt of
-- Woolen Cloth + 1 Fine Thread") names its reagents in the order of the
-- item IDs, which is how a row is known to make one.
--
-- The plan is built when a tooltip first needs it and kept until what it
-- is built from changes: your skills, your picks, the recipes and trainer
-- data the window keeps (ns.dataVersion), the options, and how many you
-- have of a reagent the routes make. A hover in between costs a few
-- reads, not a rebuild.

local addonName, ns = ...
local L = ns.L

-- spans after "Now" listed per profession; the rest are summed on one line
ns.TOOLTIP_MAX_SPANS = 5
local ROUTE_END = 300  -- the routes run to 300 (Data.lua)
local DEPTH = 3        -- how far a made reagent is followed down

local COLOR = {
    head = {0.4, 0.8, 1},
    prof = {1, 0.82, 0},
    now = {0.45, 0.95, 0.45},
    later = {0.85, 0.85, 0.85},
    dim = {0.55, 0.55, 0.55},
    warn = {1, 0.65, 0.2}
}

--------------------------------------------------------------------------
-- Settings: the tooltips and their later spans are on until switched
-- off, the professions you did not pick off until switched on
--------------------------------------------------------------------------

local function Setting(key, default)
    local db = ns.db
    if not db or db[key] == nil then return default end
    return db[key] and true or false
end
function ns.TooltipOn() return Setting("tooltip", true) end
function ns.TooltipLater() return Setting("tooltipLater", true) end
function ns.TooltipOthers() return Setting("tooltipOthers", false) end

function ns.ToggleTooltipSetting(input)
    local db = ns.db
    if not db then return end
    if input == "tooltip" then
        db.tooltip = not ns.TooltipOn()
        ns.Print(db.tooltip and L["item tooltips on"] or L["item tooltips off"])
    elseif input == "tooltiplater" then
        db.tooltipLater = not ns.TooltipLater()
        ns.Print(db.tooltipLater and L["item tooltips show the spans after the one you are in"] or
                     L["item tooltips show only the span you are in"])
    elseif input == "tooltipothers" then
        db.tooltipOthers = not ns.TooltipOthers()
        ns.Print(db.tooltipOthers and L["item tooltips also show the professions you did not pick, apart"] or
                     L["item tooltips show only the professions you picked"])
    end
end

--------------------------------------------------------------------------
-- The route's data, read for the tooltips
--------------------------------------------------------------------------

-- A row's reagents as a list of alternatives, each a list of {itemID,
-- count}: one for a plain row, one per recipe for "A / B". TBC's own
-- where they differ; a fish-cooking row's fish.
function ns.RowReagentLists(row)
    if row.fishItem then return {{{row.fishItem, 1}}} end
    local reag = (ns.IS_TBC and row.tbcReagents) or row.reagents
    if type(reag) ~= "table" or type(reag[1]) ~= "table" then return {} end
    if type(reag[1][1]) == "table" then return reag end
    return {reag}
end

local function Trim(text)
    return (tostring(text):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- the English names a row's mats text gives its reagents, by item ID:
-- "1 Bolt of Woolen Cloth + 1 Fine Thread" lines up with {{2997, 1},
-- {2321, 1}}; an alternative without mats of its own shares the first's
local function MatsNames(row, out)
    local text = (ns.IS_TBC and row.tbcMats) or row[3]
    if type(text) ~= "string" then return end
    local parts = {}
    for part in text:gmatch("[^/]+") do parts[#parts + 1] = part end
    for k, list in ipairs(ns.RowReagentLists(row)) do
        local part = parts[k] or parts[1]
        if part then
            local names = {}
            part = part:gsub("%(makes [^)]*%)", "")
            for item in part:gmatch("[^+]+") do
                names[#names + 1] = Trim((item:gsub("^%s*%d+%s+", "")))
            end
            if #names == #list then
                for i, r in ipairs(list) do out[r[1]] = out[r[1]] or names[i] end
            end
        end
    end
end

-- Which route row makes which reagent: a row whose recipe has the name of
-- a reagent some row uses (Tailoring's "Bolt of Woolen Cloth" row makes
-- item 2997, which Woolen Cape uses). And which professions make a
-- reagent another profession's route uses (ns.producers), so those are
-- built first. Built once; the routes do not change after loading.
local function Products()
    if ns.productOf then return ns.productOf end
    -- in a fixed order, so that where two rows could claim a name the same
    -- one wins on every client
    local profs = {}
    for prof in pairs(ns.CRAFT) do profs[#profs + 1] = prof end
    table.sort(profs)
    local english = {}
    for _, prof in ipairs(profs) do
        for _, row in ipairs(ns.CRAFT[prof].route) do MatsNames(row, english) end
    end
    local ids = {}
    for id in pairs(english) do ids[#ids + 1] = id end
    table.sort(ids)
    local byName = {}
    for _, id in ipairs(ids) do
        local key = ns.Fold(english[id])
        byName[key] = byName[key] or id
    end
    local productOf, rowMakes = {}, {}
    for _, prof in ipairs(profs) do
        local craft = ns.CRAFT[prof]
        for _, row in ipairs(craft.route) do
            local lists = ns.RowReagentLists(row)
            local k = 0
            for recipe in (((ns.IS_TBC and row.tbc) or row[2]) or ""):gmatch("[^/]+") do
                k = k + 1
                local id = byName[ns.Fold(Trim(recipe))]
                if id and not productOf[id] and (lists[k] or lists[1]) then
                    local made = {id = id, prof = prof, list = lists[k] or lists[1], makes = tonumber(row.makes) or 1}
                    productOf[id] = made
                    rowMakes[row] = rowMakes[row] or {}
                    rowMakes[row][k] = made
                end
            end
        end
    end
    -- what the professions make from what you gather (Data.lua's REFINE),
    -- where no route row makes it
    for _, r in ipairs(ns.REFINE or {}) do
        local id = r[1]
        english[id] = english[id] or r[2]
        if not productOf[id] then productOf[id] = {id = id, prof = r[3], list = r[4], makes = r.makes or 1, refine = true} end
    end
    local producers = {}
    for prof, craft in pairs(ns.CRAFT) do
        for _, row in ipairs(craft.route) do
            for _, list in ipairs(ns.RowReagentLists(row)) do
                for _, r in ipairs(list) do
                    local made = productOf[r[1]]
                    if made and made.prof ~= prof then producers[made.prof] = true end
                end
            end
        end
    end
    ns.productOf, ns.rowMakes, ns.itemEnglish, ns.producers = productOf, rowMakes, english, producers
    return productOf
end

-- every item a route names, whoever's: the bank count kept at a visit
-- covers them all, picked or not
local function AllItems()
    if ns.allItems then return ns.allItems end
    local all = {}
    local function add(row)
        for _, list in ipairs(ns.RowReagentLists(row)) do
            for _, r in ipairs(list) do all[r[1]] = true end
        end
    end
    for _, craft in pairs(ns.CRAFT) do
        for _, row in ipairs(craft.route) do add(row) end
    end
    for _, row in ipairs(ns.FISH_COOKING or {}) do add(row) end
    for _, r in ipairs(ns.REFINE or {}) do
        for _, m in ipairs(r[4]) do all[m[1]] = true end
    end
    ns.allItems = all
    return all
end

--------------------------------------------------------------------------
-- What you have: bags (with the reagent bag) and bank
--------------------------------------------------------------------------

-- the client's count, or nil (no API, an error, or a secret value)
local function Count(id, ...)
    local api = (C_Item and C_Item.GetItemCount) or GetItemCount
    if not api then return nil end
    local ok, n = pcall(api, id, ...)
    return ok and ns.Plain(n) or nil
end

-- bags + bank, read the same way everywhere (includeBank, includeUses,
-- includeReagentBank where the client has a reagent bank)
local function CountAll(id)
    return Count(id, true, false, true) or Count(id, true)
end

-- Bags and bank, each a number, and whether the bank number is the one
-- counted at your last bank visit. Away from the bank, a client that
-- does not see it (or sees less of it than was there) is answered from
-- that count. Once the client has been seen counting the closed bank
-- (more than none of something), its own count stands for the rest of
-- the session: a client that crafts from the bank can take things out
-- of it while it is closed.
function ns.ItemCounts(id)
    local bags = Count(id) or 0
    local all = CountAll(id) or bags
    local bank, fromVisit = math.max(0, all - bags), false
    if not ns.bankOpen then
        if bank > 0 then ns.bankSeenClosed = true end
        local seen = not ns.bankSeenClosed and ns.db and type(ns.db.bankSeen) == "table" and ns.db.bankSeen[id]
        if type(seen) == "number" and seen > bank then bank, fromVisit = seen, true end
    end
    return bags, bank, fromVisit
end

-- While the bank is open: what it holds of every item a route names.
-- full = something moved at the bank, and the count replaces the last
-- one, none included. Otherwise (the bank opening or closing, when the
-- client may not have its contents yet, or any more) a count only adds
-- to what was seen and never wipes it.
function ns.RecordBank(full)
    local db = ns.db
    if not db then return end
    local seen = type(db.bankSeen) == "table" and db.bankSeen or {}
    for id in pairs(AllItems()) do
        local bags = Count(id) or 0
        local n = math.max(0, (CountAll(id) or bags) - bags)
        if n > 0 then
            seen[id] = n
        elseif full then
            seen[id] = nil
        end
    end
    db.bankSeen = seen
end

--------------------------------------------------------------------------
-- The plan's needs
--------------------------------------------------------------------------

-- ns.RouteRowNeeds, remembered until the trainer data or the recipes'
-- names change (ns.dataVersion, ns.namesVersion): reading the route at
-- every span asks it about every row many times over, and it looks
-- recipe names up in what the trainers said
local needsMemo, memoVersion, memoNames, memoDb = {}, nil, nil, nil
local function Needs(prof, row)
    local byProf = needsMemo[prof]
    if not byProf then
        byProf = {}
        needsMemo[prof] = byProf
    end
    local n = byProf[row]
    if n == nil then
        n = ns.RouteRowNeeds(prof, row)
        byProf[row] = n
    end
    return n
end
local function FreshNeeds()
    local v, names = ns.dataVersion or 0, ns.namesVersion or 0
    if memoVersion ~= v or memoNames ~= names or memoDb ~= ns.db then
        needsMemo, memoVersion, memoNames, memoDb = {}, v, names, ns.db
    end
end

-- The spans the window will show, in order: the one you are in ("now",
-- from your skill, with the recipe the window names), then each row the
-- window moves on to, read with ns.RoutePosition at the skill the span
-- before it ends at. Each span is {row, from, to, now, picked, items}:
-- picked = the alternatives of the row it counts - for a later row of
-- alternatives ("A / B") the ones you know already, as the window would
-- pick them, else all of them.
local function Spans(name, p)
    local pos = ns.RoutePosition(name, p, Needs)
    if not pos then return nil end
    local known = ns.GetKnownRecipes(name)
    local spans = {}
    local function Span(row, from, to, now, recipe)
        if not row or not from or not to or to <= from then return end
        local picked = {}
        local alts = ns.RowAlts(row)
        if recipe then
            for k, alt in ipairs(alts) do
                if alt == recipe or ns.ResolveRecipe({[recipe] = true}, alt) then picked[#picked + 1] = k end
            end
        elseif known and #alts > 1 then
            for k, alt in ipairs(alts) do
                if ns.ResolveRecipe(known, alt) then picked[#picked + 1] = k end
            end
        end
        if #picked == 0 then
            for k in ipairs(ns.RowReagentLists(row)) do picked[#picked + 1] = k end
        end
        spans[#spans + 1] = {row = row, from = from, to = to, now = now, picked = picked, items = {}}
    end
    if pos.current and not p.unlearned then
        -- the recipe the window says to craft: the route's, or a better
        -- one you know (and only then its mats, when the route has them)
        local craft = ns.CraftNow(name, p, pos.current)
        local row, recipe = pos.current, craft.routeName
        if craft.takeBest then row, recipe = craft.bestRow, craft.best end
        Span(row, math.max(p.rank, Needs(name, pos.current)), math.min(pos.nextAt or ROUTE_END, ROUTE_END), true, recipe)
    end
    -- (the routes end at 300: a row a trainer put past it ends there too)
    local at, steps = pos.nextAt, 0
    while at and at < ROUTE_END and steps <= #pos.route do
        steps = steps + 1
        local q = ns.RoutePosition(name, {rank = at, maxRank = p.maxRank}, Needs)
        if not q or not q.current then break end
        local to = q.nextAt
        if not to or to <= at or to > ROUTE_END then to = ROUTE_END end
        local last = spans[#spans]
        if last and not last.now and last.row == q.current and last.to == at then
            last.to = to -- the same row goes on
        else
            Span(q.current, math.max(at, Needs(name, q.current)), to, false)
        end
        at = to
    end
    return spans
end
ns.PlanSpans = Spans -- for the offline tests

-- One profession's spans, each item it needs in them added to `out` as
--   {item, prof, chosen, unlearned, now, from, to, row, alts, need,
--    direct, via}
-- need = all of it in that span; direct = the part the row itself uses;
-- via[id] = a made reagent it goes into (the rest of need).
-- shared, across one build:
--   spare[id]  = what a picked profession's route leaves of a reagent it
--                makes: what you have, plus what its spans make, less
--                what they use; another profession that uses it takes it
--                from there first
--   stockIds   = the made reagents whose count the plan read (ns.stockIds)
local function ProfessionNeeds(name, p, chosen, out, shared)
    if ns.IsFinalCap(p) then return end
    local spans = Spans(name, p)
    if not spans then return end
    local productOf, rowMakes = Products(), ns.rowMakes

    -- what you have of a made reagent, then what the spans make and use
    local stock = {}
    local function Have(id)
        if stock[id] == nil then
            local bags, bank = ns.ItemCounts(id)
            stock[id] = (bags or 0) + (bank or 0)
            if not shared.seen[id] then
                shared.seen[id] = true
                shared.stockIds[#shared.stockIds + 1] = id
            end
        end
        return stock[id]
    end

    local function Add(id, span, count, alts, via)
        if count <= 0 then return end
        local e = span.items[id]
        if not e then
            e = {item = id, prof = name, chosen = chosen, unlearned = p.unlearned and true or false,
                 now = span.now, from = span.from, to = span.to, row = span.row, alts = alts,
                 need = 0, direct = 0, via = {}}
            span.items[id] = e
            out[#out + 1] = e
        end
        e.need = e.need + count
        if via then e.via[via] = true else e.direct = e.direct + count end
    end

    -- `count` of item `id` in a span, and what it is made of when this
    -- profession (or another one you picked) makes it and you lack it
    local function Use(id, count, span, alts, via, depth)
        Add(id, span, count, alts, via)
        local made = productOf[id]
        if not made or depth >= DEPTH then return end
        local left = count
        local spare = made.prof ~= name and shared.spare[id]
        if made.prof ~= name and not ns.IsTrackedName(made.prof) then
            return
        elseif spare then
            -- another profession you picked makes it on its route
            local take = math.min(spare, left)
            if chosen then shared.spare[id] = spare - take end
            left = left - take
        else
            local fromStock = math.min(Have(id), left)
            stock[id] = Have(id) - fromStock
            left = left - fromStock
        end
        if left <= 0 then return end
        local crafts = math.ceil(left / made.makes)
        for _, r in ipairs(made.list) do
            Use(r[1], crafts * r[2], span, alts, via or id, depth + 1)
        end
    end

    for _, span in ipairs(spans) do
        local crafts = span.to - span.from
        local lists = ns.RowReagentLists(span.row)
        -- an item in two alternatives counts once, at its larger count,
        -- naming the alternatives it is in
        local per, altsOf, ids = {}, {}, {}
        for _, k in ipairs(span.picked) do
            for _, r in ipairs(lists[k] or lists[1] or {}) do
                if not per[r[1]] then ids[#ids + 1] = r[1]; altsOf[r[1]] = {} end
                per[r[1]] = math.max(per[r[1]] or 0, r[2])
                table.insert(altsOf[r[1]], k)
            end
        end
        table.sort(ids)
        for _, id in ipairs(ids) do Use(id, crafts * per[id], span, altsOf[id], nil, 0) end
        -- what this span makes is there for the spans after it
        for _, k in ipairs(span.picked) do
            local made = rowMakes[span.row] and rowMakes[span.row][k]
            if made then stock[made.id] = Have(made.id) + crafts * made.makes end
        end
    end

    -- what this route leaves of what it makes, for the professions after
    -- it (only a profession you picked levels by making it)
    if chosen then
        for id, made in pairs(productOf) do
            if made.prof == name and stock[id] ~= nil then shared.spare[id] = stock[id] end
        end
    end
end

-- what the plan is built from, in one string: while it is the one the
-- index was built from, the index stands
local CRAFT_NAMES
local function PlanKey()
    if not CRAFT_NAMES then
        CRAFT_NAMES = {}
        for name in pairs(ns.CRAFT) do CRAFT_NAMES[#CRAFT_NAMES + 1] = name end
        table.sort(CRAFT_NAMES)
    end
    local tracked = ns.GetTracked()
    local parts = {tostring(ns.db), ns.dataVersion or 0, ns.namesVersion or 0, ns.TooltipOthers() and "others" or "",
                   ns.FishCookCombo() and "fish" or ""}
    for _, name in ipairs(CRAFT_NAMES) do
        local p = tracked[name] or (ns.profs and ns.profs[name])
        parts[#parts + 1] = (tracked[name] and "+" or "-") ..
                                (p and (tostring(p.rank) .. "/" .. tostring(p.maxRank) .. (p.unlearned and "u" or "")) or "")
    end
    for _, id in ipairs(ns.stockIds or {}) do
        local bags, bank = ns.ItemCounts(id)
        parts[#parts + 1] = bags + bank
    end
    return table.concat(parts, ",")
end

-- item ID -> its entries: the professions you picked, and with /rxpp
-- tooltip others the rest too. The ones that make what another one uses
-- go first, so what they make is there for it.
function ns.BuildNeedIndex()
    FreshNeeds()
    Products()
    local tracked = ns.GetTracked()
    local others = ns.TooltipOthers()
    local names = {}
    for name, kind in pairs(ns.TRACKED) do
        if kind == "craft" and ns.CRAFT[name] and (tracked[name] or others) then names[#names + 1] = name end
    end
    local producers = ns.producers or {}
    table.sort(names, function(a, b)
        local pa, pb = producers[a] and 0 or 1, producers[b] and 0 or 1
        if pa ~= pb then return pa < pb end
        return a < b
    end)
    local entries, shared = {}, {spare = {}, seen = {}, stockIds = {}}
    for _, name in ipairs(names) do
        local p = tracked[name] or ns.profs[name] or {rank = 0, maxRank = 0, kind = "craft", unlearned = true}
        local ok, err = pcall(ProfessionNeeds, name, p, tracked[name] ~= nil, entries, shared)
        if not ok then ns.lastError = "item tooltips: " .. tostring(err) end
    end
    local index = {}
    for _, e in ipairs(entries) do
        local list = index[e.item] or {}
        list[#list + 1] = e
        index[e.item] = list
    end
    ns.needIndex, ns.planDirty, ns.stockIds = index, false, shared.stockIds
    ns.needKey = PlanKey()
    return index
end

function ns.NeedIndex()
    if ns.needIndex and not ns.planDirty and ns.needKey == PlanKey() then return ns.needIndex end
    return ns.BuildNeedIndex()
end

--------------------------------------------------------------------------
-- The tooltip's lines
--------------------------------------------------------------------------

-- the row's recipe (the alternatives the item is in), and the made
-- reagent it goes into when the row does not use it itself: "Woolen
-- Cape (via Bolt of Woolen Cloth)"
local function RecipeText(e)
    local names, recipe = ns.RowAlts(e.row), {}
    for _, k in ipairs(e.alts or {}) do recipe[#recipe + 1] = names[k] end
    local what = #recipe > 0 and table.concat(recipe, " / ") or ns.RowName(e.row)
    if e.direct == 0 then
        for id in pairs(e.via) do
            local via = ns.ItemName(id) or (ns.itemEnglish and ns.itemEnglish[id])
            if via then return string.format(L["%s (via %s)"], what, via) end
        end
    end
    return what
end

-- where what a span gets lies: "bags 4 · bank 15", "bags 21", "bank 4"
local function Where(bags, bank)
    if bags > 0 and bank > 0 then return string.format(L["bags %d · bank %d"], bags, bank) end
    if bank > 0 then return string.format(L["bank %d"], bank) end
    return string.format(L["bags %d"], bags)
end

-- One span's line: "Now 63-70 · 21 (bags 21) of ~21 · Bolt of Woolen
-- Cloth", "110-120 · 0 of ~90 · Double-Stitched Woolen Shoulders (via
-- Bolt of Woolen Cloth)". got = {bags, bank} handed to the span; nil for
-- a profession you did not pick, which gets what it needs alone
-- ("80-115 · ~35 · Wool Bandage").
local function SpanText(e, got)
    local recipe = RecipeText(e)
    if not got then
        return string.format(e.now and L["Now %d-%d · ~%d · %s"] or L["%d-%d · ~%d · %s"], e.from, e.to, e.need, recipe)
    end
    local n = got[1] + got[2]
    if n == 0 then
        return string.format(e.now and L["Now %d-%d · %d of ~%d · %s"] or L["%d-%d · %d of ~%d · %s"], e.from, e.to, 0,
                             e.need, recipe)
    end
    return string.format(e.now and L["Now %d-%d · %d (%s) of ~%d · %s"] or L["%d-%d · %d (%s) of ~%d · %s"], e.from,
                         e.to, n, Where(got[1], got[2]), e.need, recipe)
end

-- {text, color} lines for an item, or an empty list when the plan does
-- not name it (or none of what names it is shown)
function ns.TooltipLines(id)
    local out = {}
    if not ns.db or not ns.TooltipOn() then return out end
    local entries = ns.NeedIndex()[id]
    if not entries then return out end
    local showLater, showOthers = ns.TooltipLater(), ns.TooltipOthers()

    -- by profession: the ones you picked first, then the others, each
    -- with "Now" first; with the later spans off, a profession with
    -- nothing now shows nothing
    local groups, byProf = {}, {}
    for _, e in ipairs(entries) do
        if (e.chosen or showOthers) and (e.now or showLater) then
            local g = byProf[e.prof]
            if not g then
                g = {prof = e.prof, label = ns.ProfLabel(e.prof), chosen = e.chosen, unlearned = e.unlearned, spans = {}}
                byProf[e.prof] = g
                groups[#groups + 1] = g
            end
            table.insert(g.spans, e)
        end
    end
    if #groups == 0 then return out end
    table.sort(groups, function(a, b)
        if a.chosen ~= b.chosen then return a.chosen end
        return a.label < b.label
    end)
    for _, g in ipairs(groups) do
        table.sort(g.spans, function(a, b)
            if a.now ~= b.now then return a.now end
            return a.from < b.from
        end)
    end

    -- what you have, handed out over the picked spans as they stand in
    -- the tooltip: every "Now" first, then the rest from the top down;
    -- the bags first, then the bank
    local bags, bank, fromVisit = ns.ItemCounts(id)
    local got, total, nowShort = {}, 0, false
    local leftBags, leftBank = bags, bank
    for _, nowPass in ipairs({true, false}) do
        for _, g in ipairs(groups) do
            if g.chosen then
                for _, e in ipairs(g.spans) do
                    if e.now == nowPass then
                        local b = math.min(leftBags, e.need)
                        local k = math.min(leftBank, e.need - b)
                        leftBags, leftBank = leftBags - b, leftBank - k
                        got[e] = {b, k}
                        total = total + e.need
                        if e.now and b + k < e.need then nowShort = true end
                    end
                end
            end
        end
    end

    local function add(text, color) out[#out + 1] = {text = text, color = color} end
    local function group(g)
        local dim = not g.chosen
        add(g.unlearned and string.format(L["%s (not learned yet)"], g.label) or g.label, dim and COLOR.dim or COLOR.prof)
        local shown, restCount, restNeed, restGot = 0, 0, 0, 0
        for _, e in ipairs(g.spans) do
            local mine = got[e]
            if e.now or shown < ns.TOOLTIP_MAX_SPANS then
                if not e.now then shown = shown + 1 end
                local color = COLOR.dim
                if mine then
                    color = mine[1] + mine[2] >= e.need and COLOR.now or (e.now and COLOR.warn or COLOR.later)
                end
                add("  " .. SpanText(e, mine), color)
            else
                restCount, restNeed = restCount + 1, restNeed + e.need
                if mine then restGot = restGot + mine[1] + mine[2] end
            end
        end
        if restCount > 0 then
            -- (two keys only for English's plural: the other languages
            -- word both alike)
            local text
            if g.chosen then
                text = restCount == 1 and string.format(L["+1 more span · %d of ~%d"], restGot, restNeed) or
                           string.format(L["+%d more spans · %d of ~%d"], restCount, restGot, restNeed)
            else
                text = restCount == 1 and string.format(L["+1 more span · ~%d"], restNeed) or
                           string.format(L["+%d more spans · ~%d"], restCount, restNeed)
            end
            add("  " .. text, dim and COLOR.dim or COLOR.later)
        end
    end

    add(" ", COLOR.later)
    add("RXP Professions", COLOR.head)
    local anyMine, othersHead = false, false
    for _, g in ipairs(groups) do
        if g.chosen then
            group(g)
            anyMine = true
        end
    end
    if anyMine then
        -- the total, and what is to spare (yours to sell) or short
        local have = bags + bank
        if have > total then
            add(string.format(L["You have %d (bags %d · bank %d) · ~%d to spare"], have, bags, bank, have - total), COLOR.now)
        elseif have < total then
            add(string.format(L["You have %d (bags %d · bank %d) · ~%d short"], have, bags, bank, total - have),
                nowShort and COLOR.warn or COLOR.later)
        else
            add(string.format(L["You have %d (bags %d · bank %d) · just enough"], have, bags, bank), COLOR.now)
        end
        if fromVisit then add(L["(bank as counted at your last visit)"], COLOR.dim) end
    end
    for _, g in ipairs(groups) do
        if not g.chosen then
            if not othersHead then
                othersHead = true
                add(L["Other professions (not in your setup)"], COLOR.dim)
            end
            group(g)
        end
    end
    return out
end

--------------------------------------------------------------------------
-- Hooking the tooltips
--------------------------------------------------------------------------

local function LinkID(link)
    local n = type(link) == "string" and link:match("item:(%d+)")
    return n and tonumber(n)
end

-- the item a tooltip shows: the data's ID, else its link, else the
-- tooltip's own item (TooltipUtil on modern clients, GetItem on older)
local function ItemID(tooltip, data)
    local id = data and ns.Plain(data.id)
    if id then return id end
    id = data and LinkID(data.hyperlink)
    if id then return id end
    if tooltip and TooltipUtil and TooltipUtil.GetDisplayedItem then
        local ok, _, link, itemID = pcall(TooltipUtil.GetDisplayedItem, tooltip)
        id = ok and (ns.Plain(itemID) or LinkID(link))
        if id then return id end
    end
    if tooltip and tooltip.GetItem then
        local ok, _, link = pcall(tooltip.GetItem, tooltip)
        if ok then return LinkID(link) end
    end
end

-- what the hooks saw, for /rxpp status: calls, the ones on a tooltip we
-- decorate, the ones with no item ID, the ones that got lines, the last
-- item and tooltip
ns.tipStats = {calls = 0, wanted = 0, noID = 0, lines = 0}

-- The tooltips a player reads an item in: the game's own and the chat
-- link's. Not the comparison ones beside them (the item you wear), not a
-- forbidden one, and not the hidden ones addons scan items with: lines
-- added there cost time and can confuse what those addons read.
local function Wanted(tooltip)
    if not tooltip or (tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip) then return false end
    if tooltip.IsForbidden then
        local ok, forbidden = pcall(tooltip.IsForbidden, tooltip)
        if not ok or forbidden then return false end
    end
    return true
end

local function Decorate(tooltip, data)
    local stats = ns.tipStats
    stats.wanted = stats.wanted + 1
    local id = ItemID(tooltip, data)
    stats.lastID = id
    if not id then
        stats.noID = stats.noID + 1
        return false
    end
    local lines = ns.TooltipLines(id)
    for _, l in ipairs(lines) do tooltip:AddLine(l.text, l.color[1], l.color[2], l.color[3]) end
    if #lines > 0 then stats.lines = stats.lines + 1 end
    return #lines > 0
end

-- /rxpp need <item link or ID>: what the tooltip would say, in chat
function ns.PrintNeeds(input)
    local id = LinkID(input) or tonumber(tostring(input):match("(%d+)"))
    if not id then
        ns.Print("/rxpp need <item link or item ID>")
        return
    end
    local lines = ns.TooltipLines(id)
    if #lines == 0 then
        local picked = {}
        for name in pairs(ns.GetTracked()) do
            if ns.CRAFT[name] then picked[#picked + 1] = name end
        end
        table.sort(picked)
        ns.Print("item %d: the plan names nothing (craft professions picked: %s)", id,
                 #picked > 0 and table.concat(picked, ", ") or "none")
        return
    end
    ns.Print("item %d:", id)
    for _, l in ipairs(lines) do
        if l.text ~= " " then print(l.text) end
    end
end

-- for /rxpp status
function ns.TooltipStatus()
    local stats, n = ns.tipStats, 0
    local ok, index = pcall(ns.NeedIndex)
    for _ in pairs(ok and index or {}) do n = n + 1 end
    local tooltip = stats.lastTooltip
    return string.format("item tooltips: %s through %s; %d item tooltips seen, %d ours, %d without an item ID, %d with lines; last item %s on %s; the plan names %d items",
                         ns.TooltipOn() and "on" or "off", tostring(ns.tooltipAPI), stats.calls, stats.wanted, stats.noID,
                         stats.lines, tostring(stats.lastID), tostring(tooltip), n)
end

local function Safely(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then ns.lastError = "item tooltips: " .. tostring(err) end
    return ok and err
end

-- Modern clients (WoW Forever, retail) hand every item tooltip to
-- TooltipDataProcessor after it is filled; older ones raise
-- OnTooltipSetItem, which can fire twice for one showing, hence the
-- note of which tooltips have their lines (kept here, not on the game's
-- frames) that OnTooltipCleared clears. Every hook is tried on its own:
-- a client that refuses one leaves the addon running, without item
-- tooltips.
do
    local tdp = TooltipDataProcessor
    local itemType = Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item
    ns.tooltipAPI = "none"
    if tdp and tdp.AddTooltipPostCall and itemType ~= nil and
        pcall(tdp.AddTooltipPostCall, itemType, function(tooltip, data)
            local stats = ns.tipStats
            stats.calls = stats.calls + 1
            local okName, name = pcall(function() return tooltip and tooltip.GetName and tooltip:GetName() end)
            stats.lastTooltip = okName and name or "?"
            if Wanted(tooltip) and Safely(Decorate, tooltip, data) and tooltip.Show then
                pcall(tooltip.Show, tooltip) -- fit the new lines
            end
        end) then
        ns.tooltipAPI = "TooltipDataProcessor"
    else
        local done = setmetatable({}, {__mode = "k"})
        for _, name in ipairs({"GameTooltip", "ItemRefTooltip"}) do
            local tooltip = _G[name]
            if tooltip and tooltip.HookScript then
                -- without OnTooltipCleared the note could never be cleared:
                -- then lines at every call rather than once a session
                local once = false
                local hooked = pcall(tooltip.HookScript, tooltip, "OnTooltipSetItem", function(self)
                    ns.tipStats.calls = ns.tipStats.calls + 1
                    ns.tipStats.lastTooltip = name
                    if (once and done[self]) or not Wanted(self) then return end
                    if Safely(Decorate, self) then
                        done[self] = true
                        if self.Show then self:Show() end -- fit the new lines
                    end
                end)
                if hooked then
                    once = pcall(tooltip.HookScript, tooltip, "OnTooltipCleared", function(self) done[self] = nil end)
                    ns.tooltipAPI = "OnTooltipSetItem"
                end
            end
        end
    end
end

--------------------------------------------------------------------------
-- Events: the bank is counted while it is open; a recipe's name the
-- game hands over late moves the plan (it looks recipes up by name)
--------------------------------------------------------------------------

local frame = CreateFrame("Frame")
for _, event in ipairs({"PLAYER_ENTERING_WORLD", "BAG_UPDATE_DELAYED", "BANKFRAME_OPENED", "BANKFRAME_CLOSED",
                        "PLAYERBANKSLOTS_CHANGED", "PLAYERREAGENTBANKSLOTS_CHANGED",
                        "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE",
                        "SPELL_DATA_LOAD_RESULT"}) do
    pcall(frame.RegisterEvent, frame, event)
end

-- something moved at the bank: count it all again once, a moment later
-- (sorting a bank raises an event per slot)
local recountSoon = false
local function Recount()
    if not (C_Timer and C_Timer.After) then
        Safely(ns.RecordBank, true)
    elseif not recountSoon then
        recountSoon = true
        C_Timer.After(0.2, function()
            if recountSoon and ns.bankOpen then Safely(ns.RecordBank, true) end
            recountSoon = false
        end)
    end
end

frame:SetScript("OnEvent", function(_, event, kind)
    if event == "SPELL_DATA_LOAD_RESULT" then
        ns.namesVersion = (ns.namesVersion or 0) + 1
        return
    end
    if event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" or event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
        local banker = Enum and Enum.PlayerInteractionType and Enum.PlayerInteractionType.Banker
        if banker == nil or kind ~= banker then return end
        event = event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" and "BANKFRAME_OPENED" or "BANKFRAME_CLOSED"
    end
    if event == "PLAYER_ENTERING_WORLD" then
        -- a loading screen closes any bank, a missed close included
        ns.bankOpen = false
        return
    end
    if not ns.db then return end
    if event == "BANKFRAME_OPENED" then
        ns.bankOpen = true
        Safely(ns.RecordBank, false)
        -- the contents can arrive a moment after the window: count again
        if C_Timer and C_Timer.After then
            C_Timer.After(1, function() if ns.bankOpen then Safely(ns.RecordBank, false) end end)
        end
    elseif event == "BANKFRAME_CLOSED" then
        -- (adding only: the client may have let go of the contents by now,
        -- and a count of none must not wipe the last one)
        if ns.bankOpen then Safely(ns.RecordBank, false) end
        recountSoon = false
        ns.bankOpen = false
    elseif ns.bankOpen then
        Recount()
    end
end)
