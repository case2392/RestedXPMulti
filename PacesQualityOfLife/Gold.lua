-- Pace's Quality of Life - Gold finder: "what makes me gold right now"
--
-- This file is everything but the window (GoldUI.lua): what is remembered,
-- how prices are read, and the sums behind the window's four tabs.
--   * Recipes are read from your own profession windows as you open them
--     (Forever changed some recipes, so none are built in); merchants' prices
--     as you visit them.
--   * Prices are the add-on's own: a full scan of the auction house (the
--     game allows one about every 15 minutes), "Price my items" (a look-up,
--     one item a second, of just what your recipes and bags use), and what
--     you browse yourself. Auctionator's prices are read when it is there
--     and ours are missing. A whole scan also answers "none listed" for
--     what the recipes, bags and vendors use and it didn't see.
--   * Our own auctions never count: left out by owner name, by what the
--     Auctions tab listed, or by a look-up (which always tells). A scan
--     that could do neither is remembered as such (book.noOwners), and the
--     window says what to press.
--   * Nothing is ever bought, bid on, posted or cancelled, and no query of
--     ours goes out while you are buying or selling: Blizzard's own panels
--     listen to every search answer.
--   * A job that takes more than a moment runs in small batches off a timer.
--     Each batch runs under pcall and carries the number of the job it
--     belongs to (S.gen), so an error or a closed auction house ends the job
--     cleanly (Abort) and a late timer does nothing.
--   * Values from the game are used only after Plain()/PlainStr(): Forever
--     hands some numbers back "secret" (type() says number, comparing one
--     throws), and those count as missing.
--
-- ---------------------------------------------------------------------------
-- ns.Gold: what the window (GoldUI.lua) may call. Money is whole copper.
-- Nothing here creates or touches a frame of the window.
--
-- The window tells this file about itself:
--   Gold.ui = {Toggle = function() end,   called by Gold.Toggle() (/pqol gold)
--              Open = function() end}     called by Gold.Open() (the options
--                                         page's Open button)
--   Gold.Listen(fn)   fn(what, arg) is called (under ns.SafeCall) with
--        "apply", on    the feature was switched on / off (off: hide the
--                       window and the auction house button)
--        "ah", open     the auction house opened / closed
--        "bags"         the bags changed (BAG_UPDATE_DELAYED)
--        "change"       anything a tab or the header shows may have changed
--                       (prices, recipes, vendors, item names, a job's
--                       progress); at most once per timer tick - the window
--                       should still debounce its refresh
--
-- Rows. Each *Rows() returns an array of plain tables in the tab's default
-- order; the lists are kept until the data changes (Gold.version), so a
-- refresh may call them freely and must not change them except through
-- Gold.Sort. Every row has:
--   id        itemID (enchant rows: nil)
--   key       the price book's key: itemID, or "itemID:suffix" for gear with
--             a random suffix
--   name, icon, quality, link   from the item cache; nil until the item has
--             loaded (show "item #id"; a "change" follows when it arrives)
--   t         time() of the price data behind the row, or nil
--   tip, act  arrays of strings: our tooltip lines. Use Gold.Tip(row), which
--             returns tip, then the data's age, then act, as one array.
-- Gold.Old(row) -> "3 d old" when the row's price is over 48 hours old (show
-- it in grey in the row), else nil.
-- Gold.Sort(rows, field, descending) sorts in place by one field; rows whose
-- field is nil always come last. Each *Text field has its number beside it
-- to sort by.
--
-- Gold.CraftRows() -> rows, one per recipe that makes an item:
--   recipe    the recipe's name          by     "Tailoring" or "Tailoring - Name"
--   mine      true for the character logged in
--   cooldown  true when the recipe has shown a cooldown (show "cooldown")
--   cost      one craft's materials, or nil (costWhy says why: "X: none listed")
--   sells     what one craft's output brings, or nil
--   how       "Auction" | "Vendor" | "Disenchant" (which of the three sells is)
--   mark      "unproven" | "none listed" | nil: the small mark beside Sells for
--   estimate  true when how is Disenchant
--   profit    sells - cost, or nil
--   listed, listedText   units on the auction house now; "12", "12+", "?"
--   canMake, canMakeText  crafts the bags allow; "-" for other characters
--   rank      1 proven, 2 unproven, 3 unknown profit (the default order:
--             rank, then profit, highest first)
-- Gold.EnchantRows() -> rows, one per enchant: name (the enchant), recipe,
--   by, mine, cooldown, cost, costWhy. Footer: Gold.ENCHANT_FOOTER.
-- Gold.BargainRows() -> rows, meta. Built by a background pass, not by this
--   call (the first call of a session starts the pass; a "change" follows).
--   kind      "Vendor" | "Disenchant" | "Resell" | "Material" | "Essence"
--   cheapest  the lowest unit price listed      upTo   buy up to this price
--   worth     what one is worth (see the tip)   units  how many qualify
--   profit    over those units                  estimate  true / nil
--   note      "may need skill 125" / "used by Runecloth Bag (+2 more)" / nil
--   meta = {loading = items left out because their data is still loading,
--           working = the pass is running, empty = the text to show when
--           there are no rows}
-- Gold.VendorRows() -> rows: vendor (unit price), auction (what it sells
--   for), mark, profit (each), listed, listedText, where, limited, seed
--   (true: a built-in price no merchant has confirmed yet).
-- Gold.BagRows() -> rows, one per item in the bags (bound and unbound
--   apart): count, bound, vendor, auction, auctionText ("?" when it could be
--   auctioned but has no price, else nil), disenchant, best, bestHow,
--   bestText, confident (false: show bestText in grey), mark ("unproven" |
--   "none listed" | nil: the mark beside Auction, as on Crafts - for an
--   enchanter's essence valued as its other size, that size's price's mark),
--   keep (the craft that uses it, or nil). Totals are nil where there is
--   nothing to show.
-- Gold.BagTotals(rows, money) -> {vendor, auction, best, unpriced, unproven,
--   text}: a stack's unproven auction price is never in `auction`; when
--   that price is also its Best the stack is counted in `unproven` and not
--   in `best`, else its vendor or disenchant Best is in `best` (money: the
--   window's own way of writing a price into text; else Gold.Money)
--
-- The header and the buttons (ask for the tab's rows first: the header then
-- knows whether any shown price was Auctionator's):
-- Gold.PriceState(tab) -> text, old   the header line ("Prices: 3,210 items
--   - full scan 25 min ago, your items looked up 3 min ago") and whether to
--   show it orange; tab is "crafts", "bargains", "vendors" or "bags"
-- Gold.Empty(tab) -> text or nil   what to show in place of an empty list
-- Gold.State() -> {state = "idle" | "asked" | "reading" | "checking",
--   ahOpen, neutral, paused, message (progress, or how the last job ended,
--   or that a scan never finished, or nil), hint (own auctions may be, or
--   still are, counted - only with the auction house open - or nil),
--   auctionator (some shown prices are Auctionator's),
--   scan = {enabled, label, tip}, check = {enabled, label, tip}}
-- Gold.StartScan() -> ok, why      Gold.StartCheck() -> ok, why (pressed
--   while a check runs it stops it)  Gold.StopCheck()  Gold.Abort(reason)
-- Gold.Search(name) -> hint   the Search button: Auctionator's exact search
--   when it is there, else the name into the auction house's search box
--   (the player then clicks Search there); the hint is what to show the
--   player. Call it only from a click.
-- Gold.Forget() -> n   forgets the current realm's prices (n: the items
--   that had one, as the header counted them)
-- Gold.Toggle()   opens / closes the window through Gold.ui.Toggle
-- Gold.Open()     opens it (Gold.ui.Open), never closes it
-- Gold.Note() -> the options page's line under the checkbox
--
-- Prices (all for a book key; nil plus a reason when unknown):
-- Gold.Now(key) -> price, age in seconds, source ("f" scan, "c" check, "b"
--   browsed, "a" Auctionator) | nil, reason
-- Gold.Usual(key) -> price | nil (UsualDeep: from days with 5+ listed only)
-- Gold.SellPrice(key) -> price, flag ("unproven" | "none listed" | nil),
--   cheaper units passed over as a dumped lot (0: none) | nil, reason
-- Gold.AfterCut(price)  Gold.Cut()  Gold.VendorBuy(itemID) -> price, "vendor" | "seed"
-- Gold.Cost(itemID, qty) -> copper, from ("auction", "vendor", "vendor,
--   price not confirmed", "your own craft" ...), flag | nil, reason
-- Gold.DisenchantValue(key) -> copper, skill needed | nil
-- Gold.Info(itemID, front) -> {name, link, quality, ilvl, stack, icon, sell,
--   class, sub, bind, reagent} or nil while it loads (front = true for rows
--   on screen: loaded first)
-- Gold.Money(copper) -> "1g 20s 5c"   Gold.Ago(seconds) -> "25 min ago"
-- Gold.Count(n) -> "3,210"            Gold.version: goes up with every change
-- Gold.Plain(v), Gold.PlainStr(v): a number / string the add-on may use, or nil
-- ---------------------------------------------------------------------------

local addonName, ns = ...

-- M is ns.Gold; L holds the file's own functions and S its state (tables,
-- not locals: a Lua function can only reach 60 outer locals)
local M, L, S = {}, {on = {}}, {}
ns.Gold = M
local D = ns.GoldData or {}

local HOUR, DAY = 3600, 86400
local FRESH = HOUR            -- a listing older than this raises no bargain
local RECENT = 48 * HOUR      -- a price older than this is "last seen", not "now"
local SCAN_WAIT = 900         -- between full scans
local SKIP_CHECK = 600        -- an item priced this recently isn't asked again
local CHECK_CAP = 300         -- items per "Price my items"
local SEND_GAP = 1.0          -- seconds between our queries
local ANSWER_WAIT = 5         -- how long one query may go unanswered
local ROWS_PER_ANSWER = 200
local SCAN_BATCH = 250
local RECIPE_BATCH = 40
local ANALYSIS_BATCH = 250
local BROWSE_BATCH = 500
local LOADS_PER_TICK = 20
local QUEUE_CAP = 2000
local LOAD_WAIT = 3           -- how long "Price my items" waits for an item's data
local LOAD_HOLD = 600         -- an item the game said it can't load is left alone this long
local HISTORY_DAYS = 14
local CALLER = "PacesQualityOfLife" -- who we tell Auctionator we are
local SILVER = 100

M.version = 1
M.ENCHANT_FOOTER = "This is what the materials cost you. Charge at least this, plus your fee."

S.on = false             -- the feature switched on
S.state = "idle"         -- idle | asked | reading | checking
S.gen = 0                -- the job a timer belongs to
S.ahOpen = false
S.ahTok = 0              -- goes up as the auction house opens and closes
S.neutral = false        -- this auction house session is a neutral house's
S.listeners = {}
S.info, S.waiting, S.class = {}, {}, {}      -- the item cache
S.front, S.queue, S.qHead, S.queued, S.asked = {}, {}, 1, {}, {} -- the load queue
S.qTail = 0              -- (the queue is S.queue[S.qHead .. S.qTail])
S.qGen = 0
S.own = {}               -- our own auctions, as the Auctions tab listed them
S.debounce = {}
S.rGen, S.aGen = 0, 0    -- the recipe read's and the analysis pass's own job numbers
S.foreign = -100         -- GetTime() of the last search answer that wasn't ours
S.nextSend = 0
S.aucFails = 0

--------------------------------------------------------------------------
-- small things
--------------------------------------------------------------------------

function L.IsZero(v) return v == 0 end
function L.IsEmpty(v) return v == "" end
function L.IsTrue(v) return v == true end
function L.IsFalse(v) return v == false end

-- a number the add-on may compare, add and keep; else nil
function M.Plain(v)
    if type(v) ~= "number" then return nil end
    if not pcall(L.IsZero, v) then return nil end
    if ns.IsSecret(v) or v ~= v then return nil end
    return v
end
local Plain = M.Plain

-- the same for a string (an empty one counts as none)
function M.PlainStr(v)
    if type(v) ~= "string" then return nil end
    local ok, empty = pcall(L.IsEmpty, v)
    if not ok or empty or ns.IsSecret(v) then return nil end
    return v
end
local PlainStr = M.PlainStr

-- true only for a plain true
function L.True(v)
    local ok, yes = pcall(L.IsTrue, v)
    return ok and yes or false
end

-- fn(...) under pcall: its first result, or nil
function L.Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, ...)
    if ok then return v end
end
function L.CallStr(fn, ...) return PlainStr(L.Call(fn, ...)) end
function L.CallNum(fn, ...) return Plain(L.Call(fn, ...)) end

function L.Later(delay, fn) C_Timer.After(delay, ns.Guard("gold", fn)) end

-- run fn once, `delay` after the last call under this name
function L.Debounce(name, delay, fn)
    local tok = (S.debounce[name] or 0) + 1
    S.debounce[name] = tok
    L.Later(delay, function() if S.on and S.debounce[name] == tok then fn() end end)
end

function L.Tell(what, arg)
    for _, fn in ipairs(S.listeners) do ns.SafeCall("gold", fn, what, arg) end
end
function M.Listen(fn) if type(fn) == "function" then table.insert(S.listeners, fn) end end

-- something on screen may have changed: told once per tick
function L.Changed()
    if S.changePending then return end
    S.changePending = true
    L.Later(0, function()
        S.changePending = false
        L.Tell("change")
        if ns.RefreshOptions then ns.RefreshOptions() end
    end)
end

-- the data changed: everything worked out from it is worked out again
function L.Bump()
    M.version = M.version + 1
    L.Changed()
end

-- 3210 -> "3,210"
function M.Count(n)
    local s = tostring(math.floor(tonumber(n) or 0))
    local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return (out:gsub("^,", ""))
end

-- 1 -> "1 item", 3210 -> "3,210 items"
function L.Items(n) return M.Count(n) .. (n == 1 and " item" or " items") end

-- copper -> "1g 20s 5c" (never %d on a raw price: whole numbers only)
function M.Money(copper)
    copper = tonumber(copper)
    if not copper then return "?" end
    local sign = copper < 0 and "-" or ""
    copper = math.floor(math.abs(copper))
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = M.Count(g) .. "g" end
    if s > 0 then parts[#parts + 1] = s .. "s" end
    if c > 0 or #parts == 0 then parts[#parts + 1] = c .. "c" end
    return sign .. table.concat(parts, " ")
end

-- seconds -> "25 min", "3 h", "2 d"
function L.Span(sec)
    sec = math.max(0, tonumber(sec) or 0)
    if sec < 60 then return "under a minute" end
    if sec < HOUR then return math.floor(sec / 60) .. " min" end
    if sec < RECENT then return math.floor(sec / HOUR) .. " h" end
    return math.floor(sec / DAY) .. " d"
end
function M.Ago(sec)
    if (tonumber(sec) or 0) < 60 then return "just now" end
    return L.Span(sec) .. " ago"
end

function L.Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

--------------------------------------------------------------------------
-- saved data: which book, the records in it
--------------------------------------------------------------------------

function L.Realm()
    if not S.realm then S.realm = L.CallStr(GetNormalizedRealmName) or L.CallStr(GetRealmName) end
    return S.realm
end
function L.Faction()
    if not S.faction then S.faction = L.CallStr(UnitFactionGroup, "player") end
    return S.faction
end

-- realm-faction, worked out when first needed; nil while the game can't say
function L.BookKey()
    local realm, faction = L.Realm(), L.Faction()
    if not (realm and faction) then return nil end
    return realm .. "-" .. (S.neutral and "Neutral" or faction)
end

function L.Book(create)
    local key = ns.db and L.BookKey()
    if not key then return nil end
    if type(ns.db.goldBook) ~= "table" then
        if not create then return nil end
        ns.db.goldBook = {}
    end
    local book = ns.db.goldBook[key]
    if type(book) ~= "table" or type(book.items) ~= "table" then
        if not create then return nil end
        book = {items = {}}
        ns.db.goldBook[key] = book
    end
    return book
end

function L.Recipes()
    local t = ns.db and ns.db.goldRecipes
    return type(t) == "table" and t or {}
end
function L.Vendors()
    local t = ns.db and ns.db.goldVendors
    return type(t) == "table" and t or {}
end

function L.ValidRec(rec)
    return type(rec) == "table" and type(rec.m) == "number" and type(rec.q) == "number" and type(rec.t) == "number" and
               (rec.z == nil or type(rec.z) == "number")
end
function L.Rec(key)
    local book = L.Book()
    local rec = book and book.items[key]
    if L.ValidRec(rec) then return rec end
end

function L.KeyItem(key)
    if type(key) == "number" then return key end
    return tonumber((tostring(key):match("^(%d+)")))
end

-- the random suffix in an item link (the 7th field of its item string), or nil
function L.Suffix(link)
    link = PlainStr(link)
    local s = link and link:match("item:([%-%d:]+)")
    if not s then return nil end
    local n = 0
    for field in (s .. ":"):gmatch("([^:]*):") do
        n = n + 1
        if n == 7 then
            local suffix = tonumber(field)
            if suffix and suffix ~= 0 then return suffix end
            return nil
        end
    end
end
function L.KeyFor(id, link, keySuffix)
    local suffix = L.Suffix(link)
    if not suffix then
        suffix = Plain(keySuffix)
        if suffix == 0 then suffix = nil end
    end
    if suffix then return id .. ":" .. suffix end
    return id
end

-- "price:units,price:units" -> {{price, units}, ...}
function L.ParsePoints(l)
    local out = {}
    for p, n in l:gmatch("(%d+):(%d+)") do out[#out + 1] = {tonumber(p), tonumber(n)} end
    return out
end

-- a record's price points, cheapest first; none when nothing is listed
function L.Points(rec)
    if rec.q <= 0 then return {} end
    if type(rec.l) == "string" then
        local pts = L.ParsePoints(rec.l)
        if #pts > 0 then return pts end
    end
    return {{rec.m, rec.q}}
end

function L.Today() return math.floor(time() / DAY) end

-- "day:value,day:value+" -> {{day, value, deep}, ...}, the last 14 days only
function L.History(h, today)
    local out = {}
    if type(h) ~= "string" then return out end
    for d, v, plus in h:gmatch("(%d+):(%d+)(%+?)") do
        d = tonumber(d)
        if d > today - HISTORY_DAYS and d <= today then out[#out + 1] = {d, tonumber(v), plus == "+"} end
    end
    return out
end
function L.FormatHistory(list)
    local parts = {}
    for _, e in ipairs(list) do parts[#parts + 1] = e[1] .. ":" .. e[2] .. (e[3] and "+" or "") end
    if #parts > 0 then return table.concat(parts, ",") end
end
-- today's value into a history; keep = leave a value already there for today
function L.AddHistory(h, value, deep, keep)
    local today = L.Today()
    local list = L.History(h, today)
    local last = list[#list]
    if last and last[1] == today then
        if keep then return L.FormatHistory(list) end
        last[2], last[3] = value, deep
    else
        list[#list + 1] = {today, value, deep}
    end
    return L.FormatHistory(list)
end

-- {[unit price] = units} -> lowest, units, typical (the price a quarter of
-- the way into the units), the cheapest price points as text
function L.Summary(map)
    local prices, q = {}, 0
    for price, n in pairs(map) do
        if n > 0 then
            prices[#prices + 1] = price
            q = q + n
        end
    end
    if q <= 0 then return nil end
    table.sort(prices)
    local need, seen, v = math.max(1, q * 0.25), 0, prices[1]
    for _, price in ipairs(prices) do
        seen = seen + map[price]
        if seen >= need then
            v = price
            break
        end
    end
    local l
    if #prices >= 2 then
        local parts = {}
        for i = 1, math.min(6, #prices) do parts[i] = prices[i] .. ":" .. map[prices[i]] end
        l = table.concat(parts, ",")
    end
    return prices[1], q, v, l
end

-- the record a set of listings makes (old: the record it replaces, for its history)
function L.MakeRecord(old, map, source, now, partial)
    local m, q, v, l = L.Summary(map)
    if not m then return nil end
    return {m = m, q = q, t = now, v = v, l = l, p = partial and true or nil, s = source,
            h = L.AddHistory(old and old.h, v, q >= 5)}
end

-- known to have none listed: the last price seen stays (m = 0: never seen).
-- t is when that was last checked; z when it was last seen listed (or first
-- found gone) - what the 30-day prune goes by, so that a sold-out record
-- isn't kept alive by every scan that doesn't see it. A record made anew
-- (MakeRecord, a browse row) has no z.
function L.MarkNone(book, key, now, source)
    local rec = book.items[key]
    if not L.ValidRec(rec) then
        rec = {m = 0}
        book.items[key] = rec
    end
    local z = rec.z or ((rec.q or 0) > 0 and rec.t) or now
    rec.q, rec.l, rec.p, rec.t, rec.s, rec.z = 0, nil, nil, now, source, z
end

-- drop what is too old to mean anything; returns how many records are left
function L.PruneBook(book, now)
    local today, left = math.floor(now / DAY), 0
    for key, rec in pairs(book.items) do
        if not L.ValidRec(rec) or now - (rec.q == 0 and rec.z or rec.t) > 30 * DAY then
            book.items[key] = nil
        else
            left = left + 1
            if rec.h ~= nil then rec.h = L.FormatHistory(L.History(rec.h, today)) end
        end
    end
    return left
end

function L.PruneAll()
    local db, now = ns.db, time()
    if type(db.goldBook) == "table" then
        for key, book in pairs(db.goldBook) do
            local keep = type(book) == "table" and type(book.items) == "table"
            if keep and L.PruneBook(book, now) == 0 then
                keep = type(book.fullAsked) == "number" and now - book.fullAsked < SCAN_WAIT
            end
            if not keep then db.goldBook[key] = nil end
        end
    end
    if type(db.goldRecipes) == "table" then
        for guid, ch in pairs(db.goldRecipes) do
            if type(ch) ~= "table" or type(ch.at) ~= "number" or now - ch.at > 180 * DAY or type(ch.profs) ~= "table" then
                db.goldRecipes[guid] = nil
            end
        end
    end
    if type(db.goldVendors) == "table" then
        local ids = {}
        for id, v in pairs(db.goldVendors) do
            if type(v) ~= "table" or type(v.p) ~= "number" or type(v.t) ~= "number" then
                db.goldVendors[id] = nil
            else
                ids[#ids + 1] = id
            end
        end
        if #ids > 3000 then
            table.sort(ids, function(a, b) return db.goldVendors[a].t > db.goldVendors[b].t end)
            for i = 3001, #ids do db.goldVendors[ids[i]] = nil end
        end
    end
end

--------------------------------------------------------------------------
-- item data: a session cache, and a queue asking the game for the rest
--------------------------------------------------------------------------

function L.Pump()
    if S.pumping then return end
    if not (C_Item and type(C_Item.RequestLoadItemDataByID) == "function") then return end
    S.pumping = true
    local g = S.qGen
    L.Later(0.1, function() L.PumpTick(g) end)
end

function L.NextQueued()
    local id = table.remove(S.front)
    if id then return id end
    id = S.queue[S.qHead]
    if id then
        S.queue[S.qHead] = nil
        S.qHead = S.qHead + 1
    end
    -- (run dry: from the start again)
    if S.qHead > S.qTail then S.qHead, S.qTail = 1, 0 end
    return id
end

function L.PumpTick(g)
    if g ~= S.qGen then return end
    S.pumping = false
    for _ = 1, LOADS_PER_TICK do
        local id = L.NextQueued()
        if not id then return end
        S.queued[id] = nil
        S.asked[id] = true
        pcall(C_Item.RequestLoadItemDataByID, id)
    end
    if #S.front > 0 or S.queue[S.qHead] then L.Pump() end
end

-- ask the game for an item's data: once a session, rows on screen first
function L.Queue(id, front)
    if S.asked[id] or S.queued[id] or not S.on then return end
    if front then
        table.insert(S.front, id)
    else
        -- (the tail is counted, never "#": the head of the table is emptied as it is read)
        if S.qTail - S.qHead + 1 >= QUEUE_CAP then return end
        S.qTail = S.qTail + 1
        S.queue[S.qTail] = id
    end
    S.queued[id] = true
    L.Pump()
end

function L.StopQueue()
    S.qGen = S.qGen + 1
    S.pumping = false
    S.front, S.queue, S.qHead, S.qTail, S.queued = {}, {}, 1, 0, {}
end

function M.Info(id, front)
    local c = S.info[id]
    if c then return c end
    if type(id) ~= "number" then return nil end
    -- (asked for under 5 seconds ago - or, stamped ahead by L.ItemArrived,
    -- an item the game couldn't load: not yet again)
    local now, asked = GetTime(), S.waiting[id]
    if asked and now - asked < 5 then return nil end
    if not (C_Item and type(C_Item.GetItemInfo) == "function") then return nil end
    local r = {pcall(C_Item.GetItemInfo, id)}
    local name = r[1] and PlainStr(r[2])
    if not name then
        S.waiting[id] = now
        L.Queue(id, front)
        return nil
    end
    c = {name = name, link = PlainStr(r[3]), quality = Plain(r[4]), ilvl = Plain(r[5]), stack = Plain(r[9]),
         icon = Plain(r[11]) or PlainStr(r[11]), sell = Plain(r[12]), class = Plain(r[13]), sub = Plain(r[14]),
         bind = Plain(r[15]), reagent = L.True(r[18])}
    S.info[id] = c
    S.waiting[id] = nil
    return c
end
L.Info = M.Info

function L.Name(id)
    local info = L.Info(id)
    return info and info.name or ("item #" .. tostring(id))
end

-- the item's class (2 weapon, 4 armor, 12 quest ...): known without loading
function L.ClassOf(id)
    local c = S.class[id]
    if c then return c end
    local info = S.info[id]
    c = info and info.class
    if not c and C_Item and type(C_Item.GetItemInfoInstant) == "function" then
        c = Plain((select(7, pcall(C_Item.GetItemInfoInstant, id))))
    end
    S.class[id] = c
    return c
end
function L.IsGear(id)
    local c = L.ClassOf(id)
    return c == 2 or c == 4
end

-- the item events only note that something arrived: ITEM_DATA_LOAD_RESULT
-- can fire inside our own RequestLoadItemDataByID. An item the game says it
-- couldn't load changes nothing on screen, and isn't read again for ten
-- minutes: asking again at once could only bring the same answer, for ever
function L.ItemArrived(id, success)
    id = Plain(id)
    if not id or not (S.waiting[id] or S.asked[id]) then return end
    local ok, failed = pcall(L.IsFalse, success)
    if ok and failed then
        S.waiting[id] = GetTime() + LOAD_HOLD - 5
        return
    end
    S.waiting[id] = nil
    if S.itemsPending then return end
    S.itemsPending = true
    L.Later(0.3, function()
        S.itemsPending = false
        if not S.on then return end
        L.Bump()
        if (S.leftOut or 0) > 0 then L.Debounce("analysis", 2, L.StartAnalysis) end
    end)
end
L.on.ITEM_DATA_LOAD_RESULT = L.ItemArrived
L.on.GET_ITEM_INFO_RECEIVED = L.ItemArrived

--------------------------------------------------------------------------
-- what is worked out from the data, kept until the data changes
--------------------------------------------------------------------------

-- a table that lasts as long as the data it was worked out from (and no
-- longer than a minute: "within 48 hours" moves with the clock)
function L.Memo(name)
    local now = time()
    if S.memoVer ~= M.version or now - S.memoAt >= 60 or now < S.memoAt then
        S.memo, S.memoVer, S.memoAt = {}, M.version, now
        S.usedAuctionator = false
    end
    local t = S.memo[name]
    if not t then
        t = {}
        S.memo[name] = t
    end
    return t
end

function L.ParseReagents(r)
    local out = {}
    if type(r) == "string" then
        for id, n in r:gmatch("(%d+):(%d+)") do out[#out + 1] = {tonumber(id), tonumber(n)} end
    end
    return out
end

function L.KnowsDisenchant()
    return L.True(L.Call(C_SpellBook and C_SpellBook.ContainsAnyDisenchantSpell))
end

-- every recorded recipe, and who can enchant:
-- {list, makes[itemID] = recipes, uses[itemID] = recipe names, chars,
--  enchanters[guid], enchanter, skill = the best Enchanting skill known}
function L.Index()
    local x = L.Memo("index")
    if x.list then return x end
    x.list, x.makes, x.uses, x.enchanters, x.chars = {}, {}, {}, {}, 0
    local me, realm = L.CallStr(UnitGUID, "player"), L.Realm()
    x.me = me
    for guid, ch in pairs(L.Recipes()) do
        -- (a character of another realm can't craft for, or disenchant on, this one)
        local here = not (type(ch.realm) == "string" and realm and ch.realm ~= realm)
        if here then x.chars = x.chars + 1 end
        for pname, prof in pairs(here and type(ch.profs) == "table" and ch.profs or {}) do
            local enchants = pname == "Enchanting"
            for rid, r in pairs(type(prof.list) == "table" and prof.list or {}) do
                if type(r) == "table" then
                    local a, b = tonumber(r.a) or 1, tonumber(r.b) or 1
                    local e = {id = rid, n = r.n or ("recipe " .. tostring(rid)), o = r.o, avg = math.max(1, (a + b) / 2),
                               e = r.e, c = r.c, reagents = L.ParseReagents(r.r), guid = guid, prof = pname,
                               char = ch.name, mine = guid == me}
                    x.list[#x.list + 1] = e
                    if r.e then enchants = true end
                    if e.o and not e.e then L.IndexRecipe(x, e) end
                end
            end
            if enchants then
                x.enchanters[guid] = true
                local skill = tonumber(prof.skill)
                if skill and (not x.skill or skill > x.skill) then x.skill = skill end
            end
        end
    end
    if me and L.KnowsDisenchant() then x.enchanters[me] = true end
    x.enchanter = next(x.enchanters) ~= nil
    table.sort(x.list, function(p, q)
        if p.guid ~= q.guid then return p.guid < q.guid end
        if p.prof ~= q.prof then return p.prof < q.prof end
        return tostring(p.id) < tostring(q.id)
    end)
    return x
end
function L.IndexRecipe(x, e)
    local makes = x.makes[e.o] or {}
    x.makes[e.o] = makes
    local known = false
    for _, other in ipairs(makes) do if other.id == e.id then known = true end end
    if not known then makes[#makes + 1] = e end
    for _, reagent in ipairs(e.reagents) do
        local uses = x.uses[reagent[1]] or {}
        x.uses[reagent[1]] = uses
        local listed = false
        for _, n in ipairs(uses) do if n == e.n then listed = true end end
        if not listed then uses[#uses + 1] = e.n end
    end
end

-- essence pairs by either item: {other = the partner, lesser = this is the lesser}
L.essence = {}
for _, pair in ipairs(D.essences or {}) do
    L.essence[pair[1]] = {other = pair[2], lesser = true}
    L.essence[pair[2]] = {other = pair[1], lesser = false}
end

--------------------------------------------------------------------------
-- Auctionator, when it is there: read-only, and only where we know nothing
--------------------------------------------------------------------------

function L.AuctionatorAPI()
    local a = Auctionator
    local api = type(a) == "table" and type(a.API) == "table" and a.API.v1
    if type(api) == "table" then return api end
end

-- three failures in a row: left alone for the session
function L.AuctionatorFailed()
    S.aucFails = S.aucFails + 1
    if S.aucFails >= 3 then S.aucDead = true end
end

-- its lowest price for one, and that price's age in days
function L.AuctionatorPrice(id)
    if S.aucDead or type(id) ~= "number" then return nil end
    local memo = L.Memo("auctionator")
    local c = memo[id]
    if c then return c[1], c[2] end
    c = {}
    memo[id] = c
    local api = L.AuctionatorAPI()
    if not api or type(api.GetAuctionPriceByItemID) ~= "function" or type(api.GetAuctionAgeByItemID) ~= "function" then
        return nil
    end
    if L.IsGear(id) then return nil end -- (it can't tell "of the Bear" from "of the Whale")
    local ok, price = pcall(api.GetAuctionPriceByItemID, CALLER, id)
    local ok2, age
    if ok then ok2, age = pcall(api.GetAuctionAgeByItemID, CALLER, id) end
    if not (ok and ok2) then
        L.AuctionatorFailed()
        return nil
    end
    S.aucFails = 0
    price, age = Plain(price), Plain(age)
    if price and age and price > 0 and price < math.huge and age >= 0 and age <= 2 then
        c[1], c[2] = math.floor(price), age
    end
    return c[1], c[2]
end

--------------------------------------------------------------------------
-- prices
--------------------------------------------------------------------------

function M.Cut()
    local cut = L.Clamp(tonumber(ns.db and ns.db.goldCut) or 5, 0, 30)
    if S.neutral then cut = math.max(cut, 15) end
    return cut
end

-- what a sale leaves after the auction house's cut (rounded down)
function M.AfterCut(price)
    if not price then return nil end
    return math.floor(price * (100 - M.Cut()) / 100)
end

-- the lowest price listed now
function M.Now(key)
    local memo = L.Memo("now")
    local c = memo[key]
    if not c then
        c = {L.NowOf(key)}
        memo[key] = c
    end
    if c[3] == "a" then S.usedAuctionator = true end
    return c[1], c[2], c[3]
end
function L.NowOf(key)
    local rec, now = L.Rec(key), time()
    if rec and now - rec.t <= RECENT then
        if rec.q > 0 then return rec.m, now - rec.t, rec.s end
        return nil, "none listed"
    end
    local price, days = L.AuctionatorPrice(key)
    if price then return price, math.floor(days * DAY), "a" end
    if rec then return nil, ("price is %d d old"):format(math.floor((now - rec.t) / DAY)) end
    return nil, "no price yet"
end

function L.Median(values)
    table.sort(values)
    local n = #values
    if n % 2 == 1 then return values[(n + 1) / 2] end
    return math.floor((values[n / 2] + values[n / 2 + 1]) / 2)
end
function L.UsualOf(key, deepOnly)
    local rec = L.Rec(key)
    if not rec then return nil end
    local values = {}
    for _, e in ipairs(L.History(rec.h, L.Today())) do
        if e[3] or not deepOnly then values[#values + 1] = e[2] end
    end
    if #values < 3 then return nil end
    return L.Median(values)
end

-- the going rate: the middle of the last days' typical prices (three days
-- at least: one scan can't tell a bargain from the going rate)
function M.Usual(key)
    local memo = L.Memo("usual")
    local c = memo[key]
    if not c then
        c = {L.UsualOf(key, false)}
        memo[key] = c
    end
    return c[1]
end
-- the same, from days with at least 5 listed only
function M.UsualDeep(key)
    local memo = L.Memo("deep")
    local c = memo[key]
    if not c then
        c = {L.UsualOf(key, true)}
        memo[key] = c
    end
    return c[1]
end

-- what one sells for. One hopeful listing far above the going rate is not
-- it, and neither is one dumped lot far below it. The third result is how
-- many cheaper units were passed over as such a lot (0: none)
function M.SellPrice(key)
    local memo = L.Memo("sell")
    local c = memo[key]
    if not c then
        c = {L.SellOf(key)}
        memo[key] = c
    end
    return c[1], c[2], c[3]
end

-- the price a sale can go by, of a record with units listed: the lowest
-- one, passing over a cheap lot - units listed for less than a vendor pays,
-- or at 70% or less of the usual price (days with 5 or more listed), as
-- long as they are a quarter of what is listed at most. Those are what
-- Bargains tells the player to buy out; they are nobody's selling price.
-- -> the price, the units passed over, units and price points from it up
function L.GoingRate(key, rec)
    local points = L.Points(rec)
    local info = L.Info(L.KeyItem(key))
    local floor, deep = info and info.sell or 0, M.UsualDeep(key)
    local cap, skipped, first = math.max(1, math.floor(rec.q / 4)), 0, 1
    for i, p in ipairs(points) do
        local cheap = p[1] < floor or (deep and p[1] * 10 <= deep * 7) or false
        -- (the last price point kept is never passed over: what lies beyond it isn't known)
        if not cheap or skipped + p[2] > cap or i == #points then break end
        skipped, first = skipped + p[2], i + 1
    end
    return points[first][1], skipped, rec.q - skipped, #points - first + 1
end

function L.SellOf(key)
    local now, why, source = M.Now(key)
    local usual = M.Usual(key)
    local rec = now and source ~= "a" and L.Rec(key) or nil
    local skipped, units, prices = 0, nil, nil
    if rec then now, skipped, units, prices = L.GoingRate(key, rec) end
    if now and usual then
        -- (one or two units, on no day ever five: still one seller's hope,
        -- however many days it has been seen)
        if rec and units <= 2 and not M.UsualDeep(key) then return math.min(now, usual), "unproven", skipped end
        return math.min(now, usual), nil, skipped
    end
    if now then
        if not rec or units <= 2 or prices < 2 then return now, "unproven", skipped end
        return now, nil, skipped
    end
    if why == "none listed" and usual then return usual, "none listed", 0 end
    return nil, why, 0
end

-- what to say of an unproven price: only what was really seen
function L.UnprovenLine(key)
    local rec = L.Rec(key)
    if not rec or rec.s == "b" or time() - rec.t > RECENT then
        -- (a browse row or Auctionator's price: a lowest price and no more)
        return "Lowest price only - how many sell at it isn't known."
    end
    local _, skipped, units = L.GoingRate(key, rec)
    local beside = skipped > 0 and " besides the cheap lot" or ""
    if units <= 2 then
        return ("Only %d%s listed%s - this is one seller's asking price, not proof it sells."):format(units, rec.p and "+" or "", beside)
    end
    if skipped > 0 then return ("The %s besides the cheap lot are listed at one price - it may be one seller."):format(M.Count(units)) end
    return ("All %s are listed at one price - it may be one seller."):format(M.Count(units))
end

-- the tooltip's line when a cheap lot was passed over
function L.CheapLine(unit, skipped)
    return ("Valued at %s each - %s cheaper unit%s listed below the going rate."):format(M.Money(unit), M.Count(skipped),
               skipped == 1 and " is" or "s are")
end

-- what a vendor charges for one: a merchant's own unlimited price, else the
-- built-in one
function M.VendorBuy(id)
    local v = L.Vendors()[id]
    if type(v) == "table" and type(v.p) == "number" and not v.lim then return v.p, "vendor" end
    local seed = D.seed and D.seed[id]
    if seed then return seed, "seed" end
end

-- buying qty from the auction house and the vendor, whichever is cheaper
-- unit by unit
L.SEED = "vendor, price not confirmed"
function L.BuyCost(id, qty)
    local vendor, kind = M.VendorBuy(id)
    -- (a built-in price no merchant has shown yet is said to be one)
    local shop = kind == "seed" and L.SEED or "vendor"
    local now, why, source = M.Now(id)
    if not now then
        if vendor then return vendor * qty, shop end
        return nil, L.Name(id) .. ": " .. why
    end
    local rec = source ~= "a" and L.Rec(id)
    local points = rec and L.Points(rec) or {{now, qty}}
    local left, cost, last, bought = qty, 0, now, 0
    for _, p in ipairs(points) do
        if left <= 0 or (vendor and vendor <= p[1]) then break end
        local take = math.min(left, p[2])
        cost, left, last, bought = cost + take * p[1], left - take, p[1], bought + take
    end
    if left <= 0 then return cost, "auction" end
    if vendor then
        return cost + left * vendor, bought > 0 and ("auction + " .. shop) or shop
    end
    -- deeper than what is listed, or than the price points kept: the rest
    -- at the last price seen - a guess, and said to be one
    local flag
    if rec then flag = qty > rec.q and ("only %d listed"):format(rec.q) or ("last %d at a guessed price"):format(left) end
    return cost + left * last, "auction", flag
end

L.GUESSED = "materials partly at a guessed price"

-- the reagents of `crafts` crafts, bought together (the tenth craft's cloth
-- may cost more than the first's); nil and why when one has no price. The
-- third result says that one of them was priced past what is listed
function L.ReagentCost(recipe, visiting, depth, crafts)
    local total, guessed = 0, nil
    for _, reagent in ipairs(recipe.reagents) do
        if visiting[reagent[1]] then return nil, "made from itself" end
        local c, why, flag = L.CostOf(reagent[1], reagent[2] * crafts, visiting, depth)
        if not c then return nil, why end
        if flag then guessed = L.GUESSED end
        total = total + c
    end
    return total, nil, guessed
end

function L.CostOf(id, qty, visiting, depth)
    local best, from, flag = L.BuyCost(id, qty)
    local why = from
    visiting[id] = true
    if depth < 3 then
        local x = L.Index()
        for _, recipe in ipairs(x.makes[id] or {}) do
            -- (enough crafts for qty at the average output; what they make
            -- over is left over: qty pays its share)
            local crafts = math.ceil(qty / recipe.avg)
            local all, _, guessed = L.ReagentCost(recipe, visiting, depth + 1, crafts)
            local c = all and math.ceil(all * qty / (crafts * recipe.avg))
            if c and (not best or c < best) then best, from, flag = c, "your own craft", guessed end
        end
        local pair = x.enchanter and L.essence[id]
        if pair and not visiting[pair.other] then
            local c, how, guessed, _
            if pair.lesser then
                local n, greater = math.ceil(qty / 3), nil
                greater, _, guessed = L.CostOf(pair.other, n, visiting, depth + 1)
                c, how = greater and math.ceil(greater * qty / (3 * n)), "buy Greater and split"
            else
                c, _, guessed = L.CostOf(pair.other, 3 * qty, visiting, depth + 1)
                how = "buy 3 Lesser and combine"
            end
            if c and (not best or c < best) then best, from, flag = c, how, guessed and L.GUESSED or nil end
        end
    end
    visiting[id] = nil
    if best then return best, from, flag end
    return nil, why
end

-- the cheapest way to get qty of an item: copper, where from, a flag
function M.Cost(id, qty)
    qty = qty or 1
    local memo = L.Memo("cost")
    local k = id .. "x" .. qty
    local c = memo[k]
    if not c then
        c = {L.CostOf(id, qty, {}, 0)}
        memo[k] = c
    end
    return c[1], c[2], c[3]
end

-- what a material sells for; an essence also as its other size (3 lesser
-- <-> 1 greater), whichever pays more.
-- -> the value, its flag, and - when the other size was what paid more -
-- the pair and that size's own price for one
function L.MatValue(id)
    local own, flag = M.SellPrice(id)
    local pair = L.essence[id]
    local other, otherFlag
    if pair then other, otherFlag = M.SellPrice(pair.other) end
    if other then
        local alt = pair.lesser and math.floor(other / 3) or other * 3
        if not own or alt > own then return alt, otherFlag, pair, other end
    end
    return own, flag
end

-- what disenchanting gives: {{itemID, chance, average quantity, needed}, ...}
function L.Outcomes(quality, weapon, ilvl)
    local function Band(list)
        for _, b in ipairs(list or {}) do if ilvl >= b[1] and ilvl <= b[2] then return b end end
    end
    if quality == 2 then
        local b = Band(D.uncommon)
        if not b then return nil end
        local o = weapon and 13 or 10
        local out = {{b[3], b[o], (b[4] + b[5]) / 2, true}, {b[6], b[o + 1], (b[7] + b[8]) / 2, true}}
        if b[9] then out[3] = {b[9], b[o + 2], 1, false} end
        return out
    elseif quality == 3 then
        local b = Band(D.rare)
        if not b then return nil end
        local out = {{b[3], b[4], 1, true}}
        if b[5] then out[2] = {b[5], b[6], 1, false} end
        return out
    elseif quality == 4 then
        local b = Band(D.epic)
        return b and {{b[3], 1, (b[4] + b[5]) / 2, true}} or nil
    end
end
function L.SkillFor(ilvl)
    for _, s in ipairs(D.skill or {}) do if ilvl <= s[1] then return s[2] end end
end

-- what disenchanting one is worth on average, after the cut on the materials
function M.DisenchantValue(key)
    local memo = L.Memo("disenchant")
    local c = memo[key]
    if not c then
        c = {L.DisenchantOf(key)}
        memo[key] = c
    end
    return c[1], c[2]
end
function L.DisenchantOf(key)
    local info = L.Info(L.KeyItem(key))
    if not info or not info.quality or not info.ilvl or (info.class ~= 2 and info.class ~= 4) then return nil end
    local outcomes = L.Outcomes(info.quality, info.class == 2, info.ilvl)
    if not outcomes then return nil end
    local total = 0
    for _, o in ipairs(outcomes) do
        local value = L.MatValue(o[1])
        if value then
            total = total + o[2] * o[3] * M.AfterCut(value)
        elseif o[4] then
            return nil
        end
    end
    total = math.floor(total)
    if total <= 0 then return nil end
    return total, L.SkillFor(info.ilvl)
end

-- units listed now: a number and how to write it
function L.Listed(key)
    local rec = L.Rec(key)
    if not rec or time() - rec.t > RECENT then return nil, "?" end
    return rec.q, rec.p and (rec.q .. "+") or tostring(rec.q)
end

--------------------------------------------------------------------------
-- recording: recipes (your own profession windows only)
--------------------------------------------------------------------------

-- a yes/no from C_TradeSkillUI: `missing` when this client hasn't got the
-- function, nil when it threw
function L.TradeFlag(name, missing)
    local fn = C_TradeSkillUI[name]
    if type(fn) ~= "function" then return missing end
    local ok, v = pcall(fn)
    if not ok then return nil end
    return L.True(v)
end

-- the window open is this character's own, and has its list
function L.TradeOurs()
    if type(C_TradeSkillUI) ~= "table" then return false end
    if L.TradeFlag("IsTradeSkillReady", true) ~= true then return false end
    if L.TradeFlag("IsDataSourceChanging", false) ~= false then return false end
    for _, name in ipairs({"IsTradeSkillLinked", "IsTradeSkillGuild", "IsNPCCrafting"}) do
        if L.TradeFlag(name, false) ~= false then return false end
    end
    return true
end

-- the profession the window shows: name, skill, max (skill only when plain)
function L.Profession()
    local T = C_TradeSkillUI
    local info = L.Call(T.GetChildProfessionInfo)
    if type(info) ~= "table" or (Plain(info.professionID) or 0) == 0 then info = L.Call(T.GetBaseProfessionInfo) end
    if type(info) ~= "table" then return nil end
    local name = PlainStr(info.parentProfessionName) or PlainStr(info.professionName)
    local skill, max = Plain(info.skillLevel), Plain(info.maxSkillLevel)
    if skill == 0 then skill = nil end
    if max == 0 then max = nil end
    return name, skill, max
end

-- one recipe into job.out; a recipe that can't be read is left out
function L.ReadRecipe(job, id)
    local T = C_TradeSkillUI
    local info = T.GetRecipeInfo(id)
    if type(info) ~= "table" or not L.True(info.learned) then return end
    if L.True(info.isDummyRecipe) or L.True(info.isGatheringRecipe) or L.True(info.isSalvageRecipe) then return end
    job.learned = job.learned + 1
    local sch = T.GetRecipeSchematic(id, false)
    if type(sch) ~= "table" then return end
    local out = Plain(sch.outputItemID)
    if out == 0 then out = nil end
    local a, b = Plain(sch.quantityMin), Plain(sch.quantityMax)
    if not a or a <= 0 then a = 1 end
    if not b or b < a then b = a end
    local parts = {}
    for _, slot in ipairs(type(sch.reagentSlotSchematics) == "table" and sch.reagentSlotSchematics or {}) do
        if Plain(slot.reagentType) == L.BASIC and slot.required ~= false then
            local first = type(slot.reagents) == "table" and slot.reagents[1]
            local rid = type(first) == "table" and Plain(first.itemID)
            if rid then -- (no item: a currency)
                local qty = Plain(slot.quantityRequired)
                if not qty or qty <= 0 then return end
                parts[#parts + 1] = rid .. ":" .. qty
            end
        end
    end
    local enchant = L.True(info.isEnchantingRecipe) or Plain(sch.recipeType) == 3 or not out
    if not out and #parts == 0 then return end
    local cooldown = L.CallNum(T.GetRecipeCooldown, id)
    job.out[id] = {n = PlainStr(info.name) or PlainStr(sch.name) or ("recipe " .. tostring(id)), o = out, a = a, b = b,
                   e = enchant or nil, c = (cooldown and cooldown > 0) and true or nil, r = table.concat(parts, ",")}
end

function L.FinishRecipes(job, g)
    -- (the first event of an opening window lists nothing learned yet)
    if g ~= S.rGen or job.learned == 0 or not L.TradeOurs() then return end
    local guid, realm, faction = L.CallStr(UnitGUID, "player"), L.Realm(), L.Faction()
    if not (guid and realm and faction and ns.db) then return end
    if type(ns.db.goldRecipes) ~= "table" then ns.db.goldRecipes = {} end
    local ch = ns.db.goldRecipes[guid]
    if type(ch) ~= "table" or type(ch.profs) ~= "table" then
        ch = {profs = {}}
        ns.db.goldRecipes[guid] = ch
    end
    local now = time()
    ch.name, ch.realm, ch.faction, ch.at = L.CallStr(UnitName, "player") or "?", realm, faction, now
    local old = ch.profs[job.name]
    local oldList = type(old) == "table" and type(old.list) == "table" and old.list or {}
    for id, r in pairs(job.out) do
        if type(oldList[id]) == "table" and oldList[id].c then r.c = true end
    end
    ch.profs[job.name] = {skill = job.skill, max = job.max, at = now, list = job.out}
    L.Bump()
end

function L.RecipeBatch(job, g)
    if g ~= S.rGen then return end
    for _ = 1, RECIPE_BATCH do
        job.i = job.i + 1
        local id = job.ids[job.i]
        if id == nil then return L.FinishRecipes(job, g) end
        if not pcall(L.ReadRecipe, job, id) then job.bad = job.bad + 1 end
    end
    L.Later(0, function() L.RecipeBatch(job, g) end)
end

function L.StartRecipeRead()
    S.rGen = S.rGen + 1
    if not L.TradeOurs() then return end
    local T = C_TradeSkillUI
    local name, skill, max = L.Profession()
    if not name then return end
    local ids = L.Call(T.GetAllRecipeIDs)
    if type(ids) ~= "table" then ids = L.Call(T.GetFilteredRecipeIDs) end
    if type(ids) ~= "table" then return end
    L.BASIC = Enum and Enum.CraftingReagentType and Enum.CraftingReagentType.Basic or 1
    L.RecipeBatch({ids = ids, i = 0, out = {}, learned = 0, bad = 0, name = name, skill = skill, max = max}, S.rGen)
end

-- a new event restarts a read that is under way
function L.TradeEvent()
    S.rGen = S.rGen + 1
    L.Debounce("recipes", 0.5, L.StartRecipeRead)
end
L.on.TRADE_SKILL_SHOW = L.TradeEvent
L.on.TRADE_SKILL_LIST_UPDATE = L.TradeEvent
L.on.TRADE_SKILL_DATA_SOURCE_CHANGED = L.TradeEvent
L.on.NEW_RECIPE_LEARNED = L.TradeEvent
L.on.TRADE_SKILL_CLOSE = function() S.rGen = S.rGen + 1 end

--------------------------------------------------------------------------
-- recording: what merchants sell
--------------------------------------------------------------------------

-- prices carry this character's reputation discount, so the lowest seen
-- wins, and a price anyone can always buy at wins over a limited one
function L.KeepVendor(vendors, id, p, lim, who, zone, now)
    local old = vendors[id]
    if type(old) == "table" and type(old.p) == "number" and type(old.t) == "number" and now - old.t < 30 * DAY then
        local oldLim = old.lim and true or false
        if p == old.p and lim == oldLim then
            old.t = now
            return false
        end
        if not (p < old.p or (p <= old.p and not lim and oldLim)) then return false end
    end
    vendors[id] = {p = p, w = who, z = zone, lim = lim or nil, t = now}
    return true
end

function L.ReadMerchantItem(i, vendors, who, zone, now)
    local info = C_MerchantFrame.GetItemInfo(i)
    local id = L.CallNum(GetMerchantItemID, i)
    if type(info) ~= "table" or not id then return false end
    local price = Plain(info.price)
    if not price or price <= 0 or L.True(info.hasExtendedCost) or info.isPurchasable == false then return false end
    local p = math.ceil(price / math.max(1, Plain(info.stackCount) or 1))
    local lim = (Plain(info.numAvailable) or -1) >= 0
    return L.KeepVendor(vendors, id, p, lim, who, zone, now)
end

function L.ReadMerchant()
    if not (ns.db and L.BookKey()) then return end
    if not (C_MerchantFrame and type(C_MerchantFrame.GetItemInfo) == "function") then return end
    local n = L.CallNum(GetMerchantNumItems) or 0
    if n <= 0 then return end
    if type(ns.db.goldVendors) ~= "table" then ns.db.goldVendors = {} end
    local who, zone, now = L.CallStr(UnitName, "npc") or "a vendor", L.CallStr(GetZoneText) or "", time()
    local changed = false
    for i = 1, n do
        local ok, kept = pcall(L.ReadMerchantItem, i, ns.db.goldVendors, who, zone, now)
        if ok and kept then changed = true end
    end
    if changed then L.Bump() end
end

function L.MerchantEvent() L.Debounce("merchant", 0.3, L.ReadMerchant) end
L.on.MERCHANT_SHOW = L.MerchantEvent
L.on.MERCHANT_UPDATE = L.MerchantEvent

--------------------------------------------------------------------------
-- jobs: one at a time, and always able to end
--------------------------------------------------------------------------

-- how each ending reads in the window's header
L.ENDINGS = {
    closed = "The scan was cut short - nothing was changed. The Scan button shows when the game allows the next one; Price my items works meanwhile.",
    timeout = "The auction house didn't send its list. A full scan may be limited to once every 15 minutes, or not offered here. Price my items still works.",
    error = "Something went wrong reading the auction house - nothing was changed. /pqol status has the error."
}

function L.CountKeys(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

-- end whatever job is running: late timers find a newer S.gen and do nothing
function M.Abort(reason)
    local was, chk = S.state, S.chk
    S.gen = S.gen + 1
    S.scan, S.chk, S.state, S.paused = nil, nil, "idle", false
    if was == "reading" then S.lastRead = GetTime() end
    if was == "checking" and chk then
        -- (what was answered is already in the book)
        local n = L.CountKeys(chk.answered)
        S.message = reason == "error" and L.ENDINGS.error or
                        ("Price check stopped: priced %s item%s."):format(M.Count(n), n == 1 and "" or "s")
        if n > 0 then
            L.Bump()
            L.OwnSettle()
            if S.on then L.StartAnalysis() end
        end
    elseif was ~= "idle" then
        S.message = L.ENDINGS[reason]
    end
    if reason == "off" then S.message = nil end
    L.Changed()
end

-- a batch or handler threw: on record once, and the job ends
function L.Fail(err)
    ns.SafeCall("gold", error, tostring(err), 0)
    M.Abort("error")
end

function L.Panel(name)
    local ah = AuctionHouseFrame
    local f = type(ah) == "table" and ah[name]
    if type(f) ~= "table" then return false end
    local ok, shown = pcall(f.IsShown, f)
    return ok and shown and true or false
end

L.on.AUCTION_HOUSE_SHOW = function()
    S.ahOpen, S.ahTok = true, S.ahTok + 1
    -- a neutral house (the auctioneer's faction isn't ours) keeps its own book
    local npc, mine = L.CallStr(UnitFactionGroup, "npc"), L.Faction()
    local neutral = (npc and mine and npc ~= mine) and true or false
    if neutral ~= S.neutral then
        S.neutral = neutral
        L.Bump()
        L.StartAnalysis()
    end
    L.Tell("ah", true)
    if ns.db and ns.db.goldScanOnOpen then M.StartScan() end
    L.Changed()
end

L.on.AUCTION_HOUSE_CLOSED = function()
    if not S.ahOpen and S.state == "idle" then return end
    S.ahOpen, S.ahTok = false, S.ahTok + 1
    if S.state ~= "idle" then M.Abort("closed") end
    if S.neutral then
        S.neutral = false
        L.Bump()
        L.StartAnalysis()
    end
    L.Tell("ah", false)
    L.Changed()
end

--------------------------------------------------------------------------
-- our own auctions never count
--------------------------------------------------------------------------

-- this character's name and those of the account's other characters here
function L.OwnNames()
    local names, realm = {}, L.Realm()
    local me = L.CallStr(UnitName, "player")
    if me then names[me] = true end
    for _, ch in pairs(L.Recipes()) do
        if type(ch) == "table" and type(ch.name) == "string" and ch.realm == realm then names[ch.name] = true end
    end
    return names
end
function L.IsOurs(names, owner)
    if type(owner) ~= "string" then return false end
    owner = PlainStr(owner)
    if not owner then return false end
    return (names[owner] or names[(owner:gsub("%-.*$", ""))]) and true or false
end

-- A full scan that named no owner, read before the Auctions tab had listed
-- what we have up, counted our own auctions as anybody's. The book keeps
-- when that scan was (book.noOwners); a record it wrote, of an item we have
-- up, is "own-counted" until the item is looked up again (a look-up always
-- tells ours apart) or the next scan. -> {keys = {[key] = true}, ids =
-- {itemID, ...} in order, n = how many keys}
function L.OwnCounted()
    local memo = L.Memo("ownCounted")
    if memo.keys then return memo end
    memo.keys, memo.ids, memo.n = {}, {}, 0
    local book = L.Book()
    local at = book and tonumber(book.noOwners)
    if not at or not next(S.own) then return memo end
    local seen = {}
    for key, rec in pairs(book.items) do
        local id = L.KeyItem(key)
        if id and S.own[id] and L.ValidRec(rec) and rec.s == "f" and rec.t == at and rec.q > 0 then
            memo.keys[key], memo.n = true, memo.n + 1
            if not seen[id] then
                seen[id] = true
                memo.ids[#memo.ids + 1] = id
            end
        end
    end
    table.sort(memo.ids)
    return memo
end

-- nothing of ours is left in what the ownerless scan wrote: it needn't be
-- said again (at the next login, or to a character with nothing up)
function L.OwnSettle()
    local book = L.Book()
    if book and book.noOwners and S.ownSeen and L.OwnCounted().n == 0 then
        book.noOwners = nil
        L.Changed()
    end
end

-- the Auctions tab listed what we have up (we never ask for it ourselves)
L.on.OWNED_AUCTIONS_UPDATED = function()
    local rows = L.Call(C_AuctionHouse and C_AuctionHouse.GetOwnedAuctions)
    if type(rows) ~= "table" then return end
    S.own, S.ownSeen = {}, true
    for _, row in ipairs(rows) do
        pcall(function()
            local id = Plain(row.itemKey.itemID)
            local qty, buyout = Plain(row.quantity), Plain(row.buyoutAmount)
            if id and qty and qty > 0 and buyout and buyout > 0 then
                local list = S.own[id] or {}
                S.own[id] = list
                -- (a stack's buyout, or a commodity's price for one: either may be it)
                list[#list + 1] = {a = buyout, b = math.ceil(buyout / qty), n = qty}
            end
        end)
    end
    L.Bump()
    L.OwnSettle()
end

function L.OwnUnits(id)
    local n = 0
    for _, o in ipairs(S.own[id] or {}) do n = n + o.n end
    return n
end

-- take our own units out of a scan's listings
function L.TakeOwn(agg)
    if not next(S.own) then return end
    for key, map in pairs(agg) do
        for _, o in ipairs(S.own[L.KeyItem(key)] or {}) do
            local left = o.n
            for _, price in ipairs({o.b, o.a}) do
                local have = map[price]
                if have and left > 0 then
                    local take = math.min(have, left)
                    map[price], left = have - take, left - take
                end
            end
        end
    end
end

--------------------------------------------------------------------------
-- the full scan
--------------------------------------------------------------------------

function L.Add(agg, key, unit, n)
    local map = agg[key]
    if not map then
        map = {}
        agg[key] = map
    end
    map[unit] = (map[unit] or 0) + n
end

-- seconds until a full scan may be asked for again
function L.ScanWait()
    local book = L.Book()
    local asked = book and tonumber(book.fullAsked) or 0
    return math.max(0, SCAN_WAIT - (time() - asked))
end

function M.StartScan()
    if not S.on then return false, "the gold finder is switched off" end
    if not S.ahOpen then return false, "open the auction house first" end
    if S.state == "checking" then return false, "wait for the price check to finish" end
    if S.state ~= "idle" then return false, "a scan is already running" end
    local book = L.Book(true)
    if not book then return false, "can't tell which realm this is yet" end
    local wait = L.ScanWait()
    if wait > 0 then return false, ("a scan can be asked again in %d min"):format(math.ceil(wait / 60)) end
    local ask = C_AuctionHouse and C_AuctionHouse.ReplicateItems
    if type(ask) ~= "function" or not pcall(ask) then
        S.message = "A full scan isn't available here - use Price my items."
        L.Changed()
        return false, "a full scan isn't available here - use Price my items"
    end
    -- (fullPending: asked for and not yet read to the end - what a /reload
    -- or a disconnect in the middle leaves behind)
    book.fullAsked, book.fullPending = time(), true
    S.gen = S.gen + 1
    S.state, S.message = "asked", nil
    local g = S.gen
    L.Later(90, function() if g == S.gen and S.state == "asked" then M.Abort("timeout") end end)
    L.Changed()
    return true
end

-- one row of the list into the scan's tally
function L.ReadScanRow(scan, i)
    local AH = C_AuctionHouse
    local _, _, count, _, _, _, _, _, _, buyout, _, _, _, owner, ownerFull, _, itemID = AH.GetReplicateItemInfo(i)
    if type(owner) == "string" and PlainStr(owner) then scan.sawOwner = true end
    itemID, count, buyout = Plain(itemID), Plain(count), Plain(buyout)
    if not (itemID and count and buyout) then
        scan.bad = scan.bad + 1
        return
    end
    if count <= 0 or buyout <= 0 then return end -- (bid only)
    if L.IsOurs(scan.names, owner) or L.IsOurs(scan.names, ownerFull) then return end
    if C_Item and C_Item.DoesItemExistByID and L.Call(C_Item.DoesItemExistByID, itemID) == false then return end
    local unit, key = math.ceil(buyout / count), itemID
    if L.IsGear(itemID) then
        local link = PlainStr(L.Call(AH.GetReplicateItemLink, i))
        if link then
            key = L.KeyFor(itemID, link)
        else
            -- no link yet: counted as the plain item for now, looked at again at the end
            if #scan.later < QUEUE_CAP then scan.later[#scan.later + 1] = {i, itemID, unit, count} end
            L.Queue(itemID)
        end
    end
    L.Add(scan.agg, key, unit, count)
end

function L.ReadScanRows(scan)
    -- (the list can shrink while it is read)
    local n = Plain(C_AuctionHouse.GetNumReplicateItems())
    if n and n < scan.n then scan.n = n end
    -- (scan.i only ever grows: it is how many rows were read)
    local last = math.max(scan.i, math.min(scan.n, scan.i + SCAN_BATCH))
    for i = scan.i, last - 1 do
        if not pcall(L.ReadScanRow, scan, i) then scan.bad = scan.bad + 1 end
    end
    scan.i = last
end

function L.ScanBatch(g)
    if g ~= S.gen or S.state ~= "reading" then return end
    local scan = S.scan
    local ok, err = pcall(L.ReadScanRows, scan)
    if not ok then return L.Fail(err) end
    L.Changed()
    if scan.i < scan.n then return L.Later(0.01, function() L.ScanBatch(g) end) end
    if #scan.later == 0 then return L.Commit(g) end
    -- gear rows that had no link: once more, a moment later
    L.Later(2, function()
        if g ~= S.gen or S.state ~= "reading" or not S.ahOpen then return end
        pcall(L.RereadGear, scan)
        L.Commit(g)
    end)
end

function L.RereadGear(scan)
    local AH = C_AuctionHouse
    for _, row in ipairs(scan.later) do
        pcall(function()
            local i, itemID, unit, count = row[1], row[2], row[3], row[4]
            if Plain((select(17, AH.GetReplicateItemInfo(i)))) ~= itemID then return end
            local key = L.KeyFor(itemID, L.Call(AH.GetReplicateItemLink, i))
            local map = scan.agg[itemID]
            if key ~= itemID and map and (map[unit] or 0) >= count then
                map[unit] = map[unit] - count
                L.Add(scan.agg, key, unit, count)
            end
        end)
    end
end

-- the book is written in one step, after the last row
function L.Commit(g)
    local scan = S.scan
    local ok, err = pcall(function()
        scan.now, scan.book = time(), L.Book(true)
        -- (ours come out by name where the rows name their owner, else by
        -- what the Auctions tab listed - when it has been seen)
        scan.ownKnown = scan.sawOwner or S.ownSeen or false
        L.TakeOwn(scan.agg)
        scan.keys, scan.out, scan.k = {}, {}, 0
        for key in pairs(scan.agg) do scan.keys[#scan.keys + 1] = key end
    end)
    if not ok then return L.Fail(err) end
    L.CommitBatch(g)
end

function L.CommitSome(scan, count)
    local items = scan.book.items
    for _ = 1, count do
        scan.k = scan.k + 1
        local key = scan.keys[scan.k]
        if key == nil then return end
        scan.out[key] = L.MakeRecord(L.ValidRec(items[key]) and items[key] or nil, scan.agg[key], "f", scan.now)
    end
end

function L.CommitBatch(g)
    if g ~= S.gen or S.state ~= "reading" then return end
    local scan = S.scan
    local ok, err = pcall(L.CommitSome, scan, #scan.keys > 2000 and 500 or #scan.keys)
    if not ok then return L.Fail(err) end
    if scan.k < #scan.keys then return L.Later(0, function() L.CommitBatch(g) end) end
    ok, err = pcall(L.CommitEnd, scan)
    if not ok then L.Fail(err) end
end

function L.CommitEnd(scan)
    local book, now, n = scan.book, scan.now, 0
    for key, rec in pairs(scan.out) do
        book.items[key] = rec
        n = n + 1
    end
    -- what the book knew and the scan didn't see is sold out - unless too
    -- much of the list couldn't be read to say so. Rows the list lost while
    -- it was read (it shrank, or another add-on's scan replaced it) weren't
    -- read either
    local unread = math.max(0, scan.rows - scan.i)
    if (scan.bad + unread) * 20 <= scan.rows then
        for key, rec in pairs(book.items) do
            if not scan.out[key] and L.ValidRec(rec) then L.MarkNone(book, key, now, "f") end
        end
        -- ... and so is what the recipes, the bags and the vendors use and
        -- the book had never seen: a whole scan that didn't list it has
        -- answered "none listed" - no need to look it up as well
        if unread == 0 then
            L.EachCared(book, function(id, key)
                for _, k in ipairs({id, key}) do
                    if not L.ValidRec(book.items[k]) then L.MarkNone(book, k, now, "f") end
                end
            end)
        end
    end
    L.PruneBook(book, now)
    -- (a list cut short is no full scan: what was read is kept, no more is claimed)
    if unread == 0 then book.full, book.fullPending = now, nil end
    -- (when this scan couldn't tell our own auctions from anybody's)
    book.noOwners = not scan.ownKnown and now or nil
    S.scan, S.state, S.lastRead = nil, "idle", GetTime()
    if unread == 0 then
        S.message = ("Scan finished: %s."):format(L.Items(n))
    else
        S.message = ("Scan cut short: %s item%s read - the auction house's list changed while it was read."):format(
                        M.Count(n), n == 1 and "" or "s")
    end
    L.Bump()
    L.StartAnalysis()
end

-- the list arrived (ours, or another add-on's scan: read as well)
L.on.REPLICATE_ITEM_LIST_UPDATE = function()
    if not S.ahOpen or S.state == "reading" or S.state == "checking" then return end
    if S.lastRead and GetTime() - S.lastRead < 60 then return end
    local AH = C_AuctionHouse
    if type(AH) ~= "table" or type(AH.GetReplicateItemInfo) ~= "function" then return end
    local n = L.CallNum(AH.GetNumReplicateItems)
    if not n or n <= 0 then return end -- (no list: when we asked, the timer goes on waiting)
    local book = L.Book(true)
    if not book then return end
    if S.state == "idle" then
        book.fullAsked, book.fullPending = time(), true
        S.gen = S.gen + 1
    end
    S.scan = {n = n, rows = n, i = 0, agg = {}, bad = 0, later = {}, names = L.OwnNames(), sawOwner = false}
    S.state, S.message = "reading", nil
    L.ScanBatch(S.gen)
end

--------------------------------------------------------------------------
-- reading a search answer (ours, or the player's own search)
--------------------------------------------------------------------------

-- -> {[key] = {[unit] = units}}, whether there is more than was read
function L.ReadCommodity(id)
    local AH, maps = C_AuctionHouse, {}
    local n = L.CallNum(AH.GetNumCommoditySearchResults, id) or 0
    for i = 1, math.min(n, ROWS_PER_ANSWER) do
        pcall(function()
            local r = AH.GetCommoditySearchResultInfo(id, i)
            if type(r) ~= "table" or L.True(r.containsAccountItem) then return end
            local qty, unit = Plain(r.quantity), Plain(r.unitPrice)
            if not (qty and unit) or unit <= 0 then return end
            qty = qty - (Plain(r.numOwnerItems) or 0)
            if qty > 0 then L.Add(maps, id, unit, qty) end
        end)
    end
    return maps, n > ROWS_PER_ANSWER or L.Call(AH.HasFullCommoditySearchResults, id) == false
end

function L.ReadItems(id, itemKey)
    local AH, maps = C_AuctionHouse, {}
    local n = L.CallNum(AH.GetNumItemSearchResults, itemKey) or 0
    for i = 1, math.min(n, ROWS_PER_ANSWER) do
        pcall(function()
            local r = AH.GetItemSearchResultInfo(itemKey, i)
            if type(r) ~= "table" or L.True(r.containsOwnerItem) or L.True(r.containsAccountItem) then return end
            local qty, buyout = Plain(r.quantity) or 1, Plain(r.buyoutAmount)
            if not buyout or buyout <= 0 then return end -- (bid only)
            qty = math.max(1, qty)
            local key = L.KeyFor(id, r.itemLink, type(r.itemKey) == "table" and r.itemKey.itemSuffix or nil)
            L.Add(maps, key, math.ceil(buyout / qty), qty)
        end)
    end
    return maps, n > ROWS_PER_ANSWER or L.Call(AH.HasFullItemSearchResults, itemKey) == false
end

-- an answer into the book; none = also note "none listed" when it had no
-- rows; ours = the answer to our own query, which lists the item under every
-- random suffix: the pieces in the bags it didn't list ("of the Bear", when
-- only "of the Whale" is for sale - or nothing at all) are none listed too,
-- or Your bags would ask for a price check that can never bring one. So is
-- the plain item (else every "Price my items" would ask for it again), and
-- a record of our own auction that an ownerless scan took for somebody's
function L.WriteAnswer(id, maps, partial, none, ours)
    local book = L.Book(true)
    if not book then return end
    local now, any = time(), false
    for key, map in pairs(maps) do
        local rec = L.MakeRecord(L.ValidRec(book.items[key]) and book.items[key] or nil, map, "c", now, partial)
        if rec then
            book.items[key] = rec
            any = true
        end
    end
    if not any and none then L.MarkNone(book, id, now, "c") end
    if ours and not partial and L.IsGear(id) then
        if not maps[id] then L.MarkNone(book, id, now, "c") end
        for _, s in ipairs(L.ReadBags()) do
            if s.id == id and not maps[s.key] then L.MarkNone(book, s.key, now, "c") end
        end
        for key in pairs(S.own[id] and L.OwnCounted().keys or {}) do
            if L.KeyItem(key) == id and not maps[key] then L.MarkNone(book, key, now, "c") end
        end
    end
    if any or none then L.Bump() end
end

--------------------------------------------------------------------------
-- "Price my items": the items your recipes and bags use, one a second
--------------------------------------------------------------------------

-- the bags: {{id, key, count, bound, noValue, quality, link}, ...}, one per
-- item, bound and unbound apart
function L.ReadBag(C, bag, stacks, order)
    local n = Plain(C.GetContainerNumSlots(bag)) or 0
    for slot = 1, n do
        local info = C.GetContainerItemInfo(bag, slot)
        local id = type(info) == "table" and Plain(info.itemID)
        local count = id and Plain(info.stackCount)
        if count and count > 0 then
            local bound = L.True(info.isBound)
            local key = L.KeyFor(id, info.hyperlink)
            local k = tostring(key) .. (bound and "b" or "")
            local s = stacks[k]
            if not s then
                s = {id = id, key = key, count = 0, bound = bound, noValue = L.True(info.hasNoValue),
                     quality = Plain(info.quality), link = PlainStr(info.hyperlink)}
                stacks[k] = s
                order[#order + 1] = s
            end
            s.count = s.count + count
        end
    end
end
function L.ReadBags()
    local C, stacks, order = C_Container, {}, {}
    if type(C) ~= "table" or type(C.GetContainerNumSlots) ~= "function" or type(C.GetContainerItemInfo) ~= "function" then
        return order
    end
    for bag = 0, Plain(NUM_TOTAL_EQUIPPED_BAG_SLOTS) or 4 do pcall(L.ReadBag, C, bag, stacks, order) end
    return order
end

-- everything the window's tabs go by, most useful first: Want(itemID) for
-- each - and Want(itemID, key) for a stack in the bags, whose book key may
-- carry a random suffix. The same item may come more than once
function L.EachCared(book, Want)
    local x = L.Index()
    local function Recipes(mine, outputs)
        for _, r in ipairs(x.list) do
            if r.mine == mine then
                if outputs then
                    Want(r.o)
                else
                    for _, reagent in ipairs(r.reagents) do Want(reagent[1]) end
                end
            end
        end
    end
    Recipes(true, false)
    Recipes(true, true)
    if x.enchanter then for _, id in ipairs(D.materials or {}) do Want(id) end end
    for _, s in ipairs(L.ReadBags()) do
        local info = L.Info(s.id)
        local quality = s.quality or (info and info.quality)
        if not s.bound and quality and quality >= 1 then Want(s.id, s.key) end
    end
    Recipes(false, false)
    Recipes(false, true)
    local ids = {}
    for id in pairs(D.seed or {}) do ids[#ids + 1] = id end
    for id in pairs(L.Vendors()) do
        if type(id) == "number" and not (D.seed and D.seed[id]) then
            local info = L.Info(id)
            if (info and info.reagent) or book.items[id] then ids[#ids + 1] = id end
        end
    end
    table.sort(ids)
    for _, id in ipairs(ids) do Want(id) end
end

-- what to price: -> the first 300, how many there were. An item priced in
-- the last 10 minutes is skipped - unless its price still counts our own
-- auctions; those come first
function L.CheckList(book)
    local now, counted = time(), L.OwnCounted()
    local list, seen, total = {}, {}, 0
    local stale = {}
    for _, id in ipairs(counted.ids) do stale[id] = true end
    local function Want(id)
        if type(id) ~= "number" or seen[id] then return end
        seen[id] = true
        local rec = book.items[id]
        if L.ValidRec(rec) and now - rec.t < SKIP_CHECK and now >= rec.t and not stale[id] then return end
        total = total + 1
        if #list < CHECK_CAP then list[#list + 1] = id end
    end
    for _, id in ipairs(counted.ids) do Want(id) end
    L.EachCared(book, Want)
    return list, total
end

-- nil when a query may go out now; else why not, and when to look again
function L.Hold(now)
    if not S.ahOpen then return "closed", 0.5 end
    if now < S.nextSend then return "gap", S.nextSend - now end
    if now - S.foreign < 2 then return "foreign", 0.5 end
    for _, name in ipairs({"CommoditiesBuyFrame", "ItemBuyFrame", "CommoditiesSellFrame", "ItemSellFrame", "AuctionsFrame",
                           "BuyDialog"}) do
        if L.Panel(name) then return "panel", 1 end
    end
    local ready = C_AuctionHouse.IsThrottledMessageSystemReady
    if type(ready) == "function" and not L.True(L.Call(ready)) then return "throttle", 0.5 end
end

-- look again in a while (one look pending at a time)
function L.Poll(delay)
    local c, g = S.chk, S.gen
    if not c then return end
    c.tok = c.tok + 1
    local tok = c.tok
    L.Later(delay, function()
        if g == S.gen and S.chk == c and c.tok == tok then L.CheckStep() end
    end)
end

-- every item still on the list is waiting for its data: true when this
-- deferral completes a round of them (the next look can wait a moment)
function L.Deferred(c)
    c.idle = (c.idle or 0) + 1
    if c.idle < #c.list - c.i then return false end
    c.idle = 0
    return true
end

-- no answer: once more at the end of the list, then it counts as unanswered
function L.NoAnswer(c, id)
    if c.retried[id] then
        c.failed[id] = true
    else
        c.retried[id] = true
        c.list[#c.list + 1] = id
    end
end

function L.IsCommodity(itemKey)
    local info = L.Call(C_AuctionHouse.GetItemKeyInfo, itemKey)
    if type(info) ~= "table" or type(info.isCommodity) ~= "boolean" then return nil end
    return L.True(info.isCommodity)
end

function L.Send(c, id)
    local AH = C_AuctionHouse
    local key = L.Call(AH.MakeItemKey, id)
    if type(key) ~= "table" then return L.NoAnswer(c, id) end
    local commodity = L.IsCommodity(key)
    if commodity == nil then
        local info = L.Info(id, true)
        if info and info.stack then commodity = info.stack > 1 end
    end
    if commodity == nil then
        -- can't tell which kind of search it takes until its data has loaded:
        -- to the end of the list, for as long as a load may take
        local now = GetTime()
        c.moved[id] = c.moved[id] or now
        if now - c.moved[id] < LOAD_WAIT then
            c.list[#c.list + 1] = id
            return L.Deferred(c) and "wait" or nil
        end
        c.failed[id] = true
        return
    end
    c.idle = 0
    local order = Enum and Enum.AuctionHouseSortOrder or {}
    local sent
    if commodity then
        sent = pcall(AH.SendSearchQuery, key, {{sortOrder = order.Price or 0, reverseSort = false}}, true)
    else
        sent = pcall(AH.SendSellSearchQuery, key, {{sortOrder = order.Buyout or 4, reverseSort = false},
                                                  {sortOrder = order.Bid or 3, reverseSort = false}}, true)
    end
    S.nextSend = GetTime() + SEND_GAP
    if not sent then return L.NoAnswer(c, id) end
    local pending, g = {id = id}, S.gen
    c.pending = pending
    L.Later(ANSWER_WAIT, function()
        if g ~= S.gen or S.chk ~= c or c.pending ~= pending then return end
        c.pending = nil
        L.NoAnswer(c, id)
        L.Poll(0)
    end)
end

function L.CheckNext(c)
    if c.i >= #c.list then return L.FinishCheck(c) end
    local now = GetTime()
    local why, delay = L.Hold(now)
    local paused = why == "panel"
    if paused ~= S.paused then
        S.paused = paused
        L.Changed()
    end
    if why == "throttle" then
        -- an item that has waited 20 s for the game's throttle is passed over
        c.held = c.held or now
        if now - c.held >= 20 then
            c.held = nil
            c.i = c.i + 1
            L.NoAnswer(c, c.list[c.i])
            return L.Poll(0)
        end
    else
        c.held = nil
    end
    if why then return L.Poll(delay) end
    c.i = c.i + 1
    local wait = L.Send(c, c.list[c.i])
    -- (nothing sent: the next item at once - or, when all that is left is
    -- waiting for its data, a moment later: never a look per frame)
    if not c.pending then L.Poll(wait and 0.3 or 0) end
    L.Changed()
end

function L.CheckStep()
    local c = S.chk
    if S.state ~= "checking" or not c or c.pending then return end
    local ok, err = pcall(L.CheckNext, c)
    if not ok then L.Fail(err) end
end

function L.FinishCheck(c)
    local priced, failed = L.CountKeys(c.answered), L.CountKeys(c.failed)
    local book = L.Book(true)
    if book then book.check, book.checkN = time(), priced end
    S.chk, S.state, S.paused = nil, "idle", false
    S.gen = S.gen + 1
    local text = ("Priced %s item%s."):format(M.Count(priced), priced == 1 and "" or "s")
    if failed > 0 then text = text .. (" %s didn't answer."):format(M.Count(failed)) end
    if c.total > CHECK_CAP then
        text = text .. (" %d of %s - press again for the rest."):format(CHECK_CAP, M.Count(c.total))
    end
    S.message = text
    L.Bump()
    L.OwnSettle()
    L.StartAnalysis()
end

function M.StopCheck()
    if S.state == "checking" then M.Abort("stopped") end
end

function M.StartCheck()
    if not S.on then return false, "the gold finder is switched off" end
    if S.state == "checking" then
        M.StopCheck()
        return true, "stopped"
    end
    if not S.ahOpen then return false, "open the auction house first" end
    if S.state ~= "idle" then return false, "wait for the scan to finish" end
    local AH = C_AuctionHouse
    if type(AH) ~= "table" or type(AH.MakeItemKey) ~= "function" or type(AH.SendSearchQuery) ~= "function" or
        type(AH.SendSellSearchQuery) ~= "function" then
        return false, "the auction house can't be searched here"
    end
    local book = L.Book(true)
    if not book then return false, "can't tell which realm this is yet" end
    local list, total = L.CheckList(book)
    if #list == 0 then
        S.message = "Nothing to price: everything your recipes and bags use was priced in the last 10 minutes."
        L.Changed()
        return false, "everything was priced in the last 10 minutes"
    end
    S.gen = S.gen + 1
    S.state, S.message, S.paused = "checking", nil, false
    S.chk = {list = list, i = 0, count = #list, total = total, answered = {}, failed = {}, retried = {}, moved = {}, tok = 0}
    L.CheckStep()
    L.Changed()
    return true
end

-- our pending query's answer
function L.TakeAnswer(c, id, maps, partial)
    c.pending = nil
    L.WriteAnswer(id, maps, partial, true, true)
    c.answered[id], c.failed[id] = true, nil
    L.Poll(math.max(0, S.nextSend - GetTime()))
end

-- a search answer: ours when it is for the item we are waiting on; any
-- other is the player's own search - read too, and our next query waits
function L.SearchAnswer(id, Read, arg, none)
    if not id or not S.ahOpen then return end
    local c = S.chk
    if S.state == "checking" and c and c.pending and c.pending.id == id then
        local ok, err = pcall(function() L.TakeAnswer(c, id, Read(id, arg)) end)
        if not ok then L.Fail(err) end
        return
    end
    S.foreign = GetTime()
    if S.state ~= "idle" then return end
    local maps, partial = Read(id, arg)
    -- (the player's item list may be sorted by bid, or highest first: a part
    -- of it needn't hold the lowest buyout. A commodity's is always by price)
    if partial and Read == L.ReadItems then return end
    L.WriteAnswer(id, maps, partial, none)
end

L.on.COMMODITY_SEARCH_RESULTS_UPDATED = function(itemID)
    L.SearchAnswer(Plain(itemID), L.ReadCommodity, nil, true)
end
L.on.ITEM_SEARCH_RESULTS_UPDATED = function(itemKey)
    if type(itemKey) ~= "table" then return end
    -- (the player's search for one "of the Bear" says nothing of the plain item)
    L.SearchAnswer(Plain(itemKey.itemID), L.ReadItems, itemKey, (Plain(itemKey.itemSuffix) or 0) == 0)
end
L.on.AUCTION_HOUSE_THROTTLED_SYSTEM_READY = function()
    if S.state == "checking" then L.Poll(0) end
end
L.on.AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED = function()
    local c = S.chk
    if S.state ~= "checking" or not c or not c.pending then return end
    local id = c.pending.id
    c.pending = nil
    L.NoAnswer(c, id)
    L.Poll(0)
end

--------------------------------------------------------------------------
-- what the player browses: read as it goes by, never asked for
--------------------------------------------------------------------------

function L.BrowseRow(book, row, now)
    local itemKey = row.itemKey
    local id = type(itemKey) == "table" and Plain(itemKey.itemID)
    -- (commodities only: for anything else the lowest price may be a bid)
    if not id or L.IsCommodity(itemKey) ~= true or L.True(row.containsOwnerItem) then return end
    local price, qty = Plain(row.minPrice), Plain(row.totalQuantity)
    if not (price and qty) or price <= 0 or qty <= 0 then return end
    local old = L.ValidRec(book.items[id]) and book.items[id] or nil
    if old and (old.s == "f" or old.s == "c") and now - old.t < HOUR then return end
    book.items[id] = {m = price, q = qty, t = now, s = "b", v = old and old.v or price,
                      h = L.AddHistory(old and old.h, price, false, true)}
    return true
end

function L.Browse(rows, from, tok)
    if tok ~= S.ahTok or not S.ahOpen then return end
    local book = L.Book(true)
    if not book then return end
    local now, last, changed = time(), math.min(#rows, from + BROWSE_BATCH - 1), false
    for i = from, last do
        local ok, wrote = pcall(L.BrowseRow, book, rows[i], now)
        if ok and wrote then changed = true end
    end
    if changed then L.Bump() end
    if last < #rows then L.Later(0, function() L.Browse(rows, last + 1, tok) end) end
end

L.on.AUCTION_HOUSE_BROWSE_RESULTS_UPDATED = function()
    local rows = L.Call(C_AuctionHouse and C_AuctionHouse.GetBrowseResults)
    if type(rows) == "table" then L.Browse(rows, 1, S.ahTok) end
end
L.on.AUCTION_HOUSE_BROWSE_RESULTS_ADDED = function(added)
    if type(added) == "table" then L.Browse(added, 1, S.ahTok) end
end

--------------------------------------------------------------------------
-- Bargains: worked out in the background after each scan or check
--------------------------------------------------------------------------

L.LAST_LINE = "Press Search to see it in the auction house. Pace's QoL never buys for you."

-- a listing fresh and deep enough to act on (browsed prices never are)
function L.Fresh(rec, now)
    return L.ValidRec(rec) and (rec.s == "f" or rec.s == "c") and rec.q > 0 and now - rec.t <= FRESH and now >= rec.t
end

-- the units at prices that qualify, cheapest first: units, what they cost,
-- the highest price among them
function L.Walk(points, Qualifies, cap)
    local units, paid, top = 0, 0, nil
    for _, p in ipairs(points) do
        if not Qualifies(p[1]) then break end
        local n = cap and math.min(p[2], cap - units) or p[2]
        if n <= 0 then break end
        units, paid, top = units + n, paid + n * p[1], p[1]
    end
    return units, paid, top
end

function L.Deal(job, kind, key, rec, info, top, worth, units, profit)
    local row = {kind = kind, key = key, id = L.KeyItem(key), name = info.name, icon = info.icon, quality = info.quality,
                 link = info.link, cheapest = rec.m, upTo = top, worth = worth, units = units, profit = profit, t = rec.t,
                 tip = {}, act = {}}
    job.rows[#job.rows + 1] = row
    return row
end

-- listed for less than a vendor pays
function L.VendorDeal(job, key, rec, info, points)
    local sell = info.sell
    if not sell or sell <= 0 then return end
    local units, paid, top = L.Walk(points, function(unit) return sell - unit >= 1 end)
    local profit = sell * units - paid
    if units == 0 or profit < SILVER then return end
    local row = L.Deal(job, "Vendor", key, rec, info, top, sell, units, profit)
    row.tip[1] = ("A vendor pays %s each; %s listed for less."):format(M.Money(sell), M.Count(units))
    if units == 1 then
        row.act[1] = ("Buy it (up to %s), then sell it to any vendor."):format(M.Money(top))
    else
        row.act[1] = ("Buy the %s cheapest (up to %s each), then sell them to any vendor."):format(M.Count(units), M.Money(top))
    end
    row.act[2] = L.LAST_LINE
end

-- listed for less than its disenchanted materials sell for
function L.DisenchantDeal(job, key, rec, info, points, x)
    if not info.quality or info.quality < 2 or info.quality > 4 then return end
    local value, skill = M.DisenchantValue(key)
    if not value then return end
    local units, paid, top = L.Walk(points, function(unit) return value - unit >= math.max(unit * 0.2, 10 * SILVER) end)
    if units == 0 then return end
    local row = L.Deal(job, "Disenchant", key, rec, info, top, value, units, value * units - paid)
    row.estimate = true
    row.tip[1] = ("Disenchants into about %s of materials on average, after the %s%% auction cut."):format(M.Money(value), M.Cut())
    if skill and x.skill and x.skill < skill then
        row.note = "may need skill " .. skill
        row.tip[2] = ("Your best Enchanting skill on record is %d: this %s."):format(x.skill, row.note)
    end
    row.act[1] = ("Buy up to %s, disenchant, sell the materials. Average over many items - a single one can give less. Estimate: not checked on Forever. Your Enchanting skill may need to be higher for high-level items."):format(M.Money(top))
    row.act[2] = L.LAST_LINE
end

-- listed well under what it usually goes for
function L.ResellDeal(job, key, rec, info, points)
    local deep = M.UsualDeep(key)
    if not deep then return end
    -- (never what a vendor sells for less: nobody needs ours then)
    local vendor = M.VendorBuy(L.KeyItem(key))
    local units, paid, top = L.Walk(points, function(unit) return unit * 10 <= deep * 7 and (not vendor or unit < vendor) end,
                                    math.max(1, math.floor(rec.q / 4)))
    local profit = M.AfterCut(deep) * units - paid
    if units == 0 or profit < 20 * SILVER then return end
    local row = L.Deal(job, "Resell", key, rec, info, top, deep, units, profit)
    row.tip[1] = ("Usually %s each (days with 5 or more listed); these are at 70%% of that or less."):format(M.Money(deep))
    row.tip[2] = ("Counted: %s of the %s listed, after the %s%% auction cut."):format(M.Count(units), M.Count(rec.q), M.Cut())
    row.act[1] = ("Buy up to %s, list again near %s. Resale is a guess: it may take days and each failed listing costs the deposit."):format(
                     M.Money(top), M.Money(deep))
    row.act[2] = L.LAST_LINE
end

-- a material of your recipes, cheaper than usual
function L.MaterialDeal(job, key, rec, info, points, uses)
    local usual = M.Usual(key)
    if not usual then return end
    -- a vendor's price is the most it need ever cost: only below that is it
    -- a bargain, and the saving is measured against it
    local vendor, kind = M.VendorBuy(L.KeyItem(key))
    local worth = math.min(usual, vendor or usual)
    local units, paid, top = L.Walk(points, function(unit) return unit * 10 <= usual * 8 and (not vendor or unit < vendor) end)
    local saving = worth * units - paid
    if units == 0 or saving < 10 * SILVER then return end
    local row = L.Deal(job, "Material", key, rec, info, top, worth, units, saving)
    row.note = "used by " .. uses[1] .. (#uses > 1 and (" (+%d more)"):format(#uses - 1) or "")
    row.tip[1] = ("Usually %s each; these are at 80%% of that or less. The profit shown is what you save."):format(M.Money(usual))
    if vendor and vendor < usual and kind == "seed" then
        -- (a built-in price no merchant has shown yet: an estimate, and said to be one)
        row.estimate = true
        row.tip[1] = ("Usually %s each, and a vendor should sell them for about %s (price not confirmed - visit one); these are below both. The profit shown is what you would save on that price."):format(
                         M.Money(usual), M.Money(vendor))
    elseif vendor and vendor < usual then
        row.tip[1] = ("Usually %s each, and a vendor sells them for %s; these are below both. The profit shown is what you save on the vendor's price."):format(
                         M.Money(usual), M.Money(vendor))
    end
    row.tip[2] = row.note
    row.act[1] = "Cheaper than usual - buy what you'll craft with."
    row.act[2] = L.LAST_LINE
end

function L.AnalyseKey(job, key, x)
    local rec = job.book.items[key]
    if not L.Fresh(rec, job.now) then return end
    local id = L.KeyItem(key)
    local info = id and L.Info(id)
    if not info then
        -- (left out until its data has loaded; the pass runs again then)
        job.loading = job.loading + 1
        return
    end
    local points = L.Points(rec)
    L.VendorDeal(job, key, rec, info, points)
    if info.class == 2 or info.class == 4 then
        if x.enchanter then L.DisenchantDeal(job, key, rec, info, points, x) end
    elseif (info.stack or 1) > 1 then
        L.ResellDeal(job, key, rec, info, points)
    end
    if x.uses[key] then L.MaterialDeal(job, key, rec, info, points, x.uses[key]) end
end

-- buy `take` of one essence, right-click, sell `give` of the other
function L.EssenceDeal(job, from, to, take, give)
    local rec, target = job.book.items[from], job.book.items[to]
    if not L.Fresh(rec, job.now) or not L.ValidRec(target) or job.now - target.t > FRESH then return end
    local info = L.Info(from)
    local sell = M.SellPrice(to)
    if not (info and sell) then return end
    local gain = M.AfterCut(sell * give)
    local points, p, used = L.Points(rec), 1, 0
    local units, profit, top = 0, 0, nil
    while units < 1000 do
        -- the next `take` units, cheapest first
        local cost, need, q, u, high = 0, take, p, used, nil
        while need > 0 and points[q] do
            local n = math.min(need, points[q][2] - u)
            cost, need, u, high = cost + n * points[q][1], need - n, u + n, points[q][1]
            if u >= points[q][2] then q, u = q + 1, 0 end
        end
        if need > 0 or gain - cost < 10 * SILVER then break end
        units, profit, top, p, used = units + 1, profit + gain - cost, high, q, u
    end
    if units == 0 then return end
    -- (Worth is of one of the row's own item: a third of a Greater, or three Lesser)
    local row = L.Deal(job, "Essence", from, rec, info, top, take == 3 and math.floor(sell / 3) or sell * 3, units, profit)
    row.estimate, row.target = true, to
    local other = L.Name(to)
    if take == 3 then
        row.tip[1] = ("3 of these make one %s, which sells for %s (less the %s%% cut)."):format(other, M.Money(sell), M.Cut())
        row.act[1] = "Buy 3 Lesser, right-click to combine, sell the Greater."
    else
        row.tip[1] = ("One splits into 3 %s, which sell for %s each (less the %s%% cut)."):format(other, M.Money(sell), M.Cut())
        row.act[1] = "Buy a Greater, right-click to split, sell the 3 Lesser."
    end
    row.tip[2] = ("Units counts conversions (%s): %s keep%s 10s or more each."):format(
                     take == 3 and "3 Lesser each" or "one Greater each", M.Count(units), units == 1 and "s" or "")
    row.act[2] = "Estimate: Forever may have changed this."
    row.act[3] = L.LAST_LINE
end

function L.FinishAnalysis(job, x)
    if x.enchanter then
        for _, pair in ipairs(D.essences or {}) do
            pcall(L.EssenceDeal, job, pair[1], pair[2], 3, 1)
            pcall(L.EssenceDeal, job, pair[2], pair[1], 1, 3)
        end
    end
    table.sort(job.rows, function(a, b)
        if a.profit ~= b.profit then return a.profit > b.profit end
        return tostring(a.key) < tostring(b.key)
    end)
    S.bargains = {rows = job.rows, loading = job.loading, book = job.key}
    S.leftOut, S.aJob = job.loading, nil
    L.Changed()
end

function L.AnalysisBatch(job, g)
    if g ~= S.aGen or not S.on then return end
    local ok, err = pcall(function()
        local x = L.Index()
        for _ = 1, ANALYSIS_BATCH do
            job.i = job.i + 1
            local key = job.keys[job.i]
            if key == nil then return L.FinishAnalysis(job, x) end
            pcall(L.AnalyseKey, job, key, x)
        end
        L.Later(0, function() L.AnalysisBatch(job, g) end)
    end)
    if not ok then
        S.aJob = nil
        ns.SafeCall("gold", error, tostring(err), 0)
    end
end

-- a pass of its own (not one of the jobs above: it only reads the book)
function L.StartAnalysis()
    S.aGen = S.aGen + 1
    S.aJob = nil
    if not S.on then return end
    S.aRan = true
    local book, key, now = L.Book(), L.BookKey(), time()
    local job = {keys = {}, i = 0, rows = {}, loading = 0, now = now, book = book, key = key}
    if book then
        for k, rec in pairs(book.items) do
            if L.Fresh(rec, now) then job.keys[#job.keys + 1] = k end
        end
    end
    S.aJob = job
    local g = S.aGen
    L.Later(0, function() L.AnalysisBatch(job, g) end)
end

-- how many prices the book has, and how new they are
function L.Stats()
    local st = L.Memo("stats")
    if st.n then return st end
    -- (n: items listed when last looked at; all: every record, the sold-out too)
    st.n, st.all = 0, 0
    local book = L.Book()
    for _, rec in pairs(book and book.items or {}) do
        if L.ValidRec(rec) then
            st.all = st.all + 1
            if rec.q > 0 then st.n = st.n + 1 end
            if not st.newest or rec.t > st.newest then st.newest = rec.t end
            if rec.q > 0 and (rec.s == "f" or rec.s == "c") and (not st.deep or rec.t > st.deep) then st.deep = rec.t end
        end
    end
    return st
end

function L.NoPrices()
    if S.ahOpen then return "Press Scan (everything, once per 15 minutes) or Price my items (quick)." end
    return "Go to an auctioneer, open the auction house, then press Scan (everything, once per 15 minutes) or Price my items (quick)."
end

function M.BargainRows()
    if not S.aRan then L.StartAnalysis() end
    local rows, b, now = {}, S.bargains, time()
    if b and b.book == L.BookKey() then
        for _, row in ipairs(b.rows) do
            if now - row.t <= FRESH then rows[#rows + 1] = row end
        end
    end
    return rows, {loading = b and b.loading or 0, working = S.aJob ~= nil, empty = #rows == 0 and M.Empty("bargains") or nil}
end

--------------------------------------------------------------------------
-- Crafts
--------------------------------------------------------------------------

function L.MadeBy(x, r)
    if x.chars > 1 and r.char then return r.prof .. " - " .. r.char end
    return r.prof
end

-- one craft's materials: the cost (nil when one has no price), why not, and
-- a tooltip line for each
function L.Materials(r, tip)
    local cost, why = 0, nil
    for _, reagent in ipairs(r.reagents) do
        local c, from, flag = M.Cost(reagent[1], reagent[2])
        if c then
            if cost then cost = cost + c end
            tip[#tip + 1] = ("%d x %s: %s (%s%s)"):format(reagent[2], L.Name(reagent[1]), M.Money(c), from,
                                                         flag and (", " .. flag) or "")
        else
            cost, why = nil, why or from
            tip[#tip + 1] = ("%d x %s"):format(reagent[2], from)
        end
    end
    return cost, why
end

-- how many crafts the bags (and bank) hold the materials for
function L.CanMake(r)
    local best
    for _, reagent in ipairs(r.reagents) do
        local have = L.CallNum(C_Item and C_Item.GetItemCount, reagent[1], true) or 0
        local n = math.floor(have / reagent[2])
        if not best or n < best then best = n end
    end
    return best
end
function L.SetCanMake(row)
    if row.mine then
        row.canMake = L.CanMake(row.r)
        row.canMakeText = row.canMake and tostring(row.canMake) or "?"
    else
        row.canMake, row.canMakeText = nil, "-"
    end
end

-- the three ways to sell one craft's output: the best, and a line for each
function L.SellOptions(row, r, info, x, bop)
    local best, how
    local function Offer(name, value)
        if value and (not best or value > best) then best, how = value, name end
    end
    local sp, flag, cheaper
    if not bop then sp, flag, cheaper = M.SellPrice(r.o) end
    if sp then
        local value = math.floor(M.AfterCut(sp) * r.avg)
        Offer("Auction", value)
        row.tip[#row.tip + 1] = ("Auction: %s (%s each, less the %s%% cut)"):format(M.Money(value), M.Money(sp), M.Cut())
        if (cheaper or 0) > 0 then row.tip[#row.tip + 1] = L.CheapLine(sp, cheaper) end
    end
    local sell = info and info.sell
    if sell and sell > 0 then
        Offer("Vendor", math.floor(sell * r.avg))
        row.tip[#row.tip + 1] = "Vendor: " .. M.Money(math.floor(sell * r.avg))
    end
    local dis = x.enchanter and M.DisenchantValue(r.o)
    if dis then
        Offer("Disenchant", math.floor(dis * r.avg))
        row.tip[#row.tip + 1] = ("Disenchant: about %s (estimate)"):format(M.Money(math.floor(dis * r.avg)))
    end
    row.sells, row.how = best, how
    row.estimate = how == "Disenchant" or nil
    if how == "Auction" and flag then
        row.mark = flag
        if flag == "unproven" then
            row.tip[#row.tip + 1] = L.UnprovenLine(r.o)
        else
            row.tip[#row.tip + 1] = "None listed now - this is its usual price."
        end
    end
    if not best then row.tip[#row.tip + 1] = "Sells for: ? (" .. (select(2, M.SellPrice(r.o)) or "no price yet") .. ")" end
end

function L.CraftRow(x, r)
    local info = L.Info(r.o, true)
    if info and info.class == 12 then return nil end -- (quest items)
    -- a bind-on-pickup output can only be disenchanted or vendored, by its maker
    local bop = info and info.bind == 1 or false
    if bop and not x.enchanters[r.guid] then return nil end
    local row = {id = r.o, key = r.o, name = info and info.name, icon = info and info.icon, quality = info and info.quality,
                 link = info and info.link, recipe = r.n, cooldown = r.c and true or nil, mine = r.mine, by = L.MadeBy(x, r),
                 r = r, tip = {}, act = {}}
    row.cost, row.costWhy = L.Materials(r, row.tip)
    row.listed, row.listedText = L.Listed(r.o)
    local rec = L.Rec(r.o)
    row.t = rec and rec.t or nil
    L.SellOptions(row, r, info, x, bop)
    local usual = M.Usual(r.o)
    if usual then row.tip[#row.tip + 1] = "Usual price: " .. M.Money(usual) end
    local ours = L.OwnUnits(r.o)
    if row.listed and ours > 0 then
        if L.OwnCounted().keys[r.o] then
            -- (read by a scan that couldn't tell whose they were)
            row.tip[#row.tip + 1] = ("Listed: %s - your own %d may be among them, and the price may be yours. Press Price my items to put that right."):format(
                                        row.listedText, ours)
        else
            -- (our own are taken out of every other count as it is read)
            row.tip[#row.tip + 1] = ("Listed: %s, not counting %d of yours"):format(row.listedText, ours)
        end
    end
    if row.cost and row.sells then row.profit = row.sells - row.cost end
    row.rank = (not row.profit and 3) or (row.mark == "unproven" and 2) or 1
    if row.listed == 0 then
        row.act[#row.act + 1] = "0 listed: nobody is selling - you set the price, but check that anyone buys."
    end
    row.act[#row.act + 1] = ("Profit is after the %s%% auction cut. The listing deposit comes back when it sells and is lost when it doesn't."):format(
                                M.Cut())
    L.SetCanMake(row)
    return row
end

function L.Text(v) return tostring(v or "") end

function M.CraftRows()
    local memo = L.Memo("crafts")
    if not memo.rows then
        local x, rows = L.Index(), {}
        for _, r in ipairs(x.list) do
            if r.o and not r.e then
                local ok, row = pcall(L.CraftRow, x, r)
                if ok and row then rows[#rows + 1] = row end
            end
        end
        table.sort(rows, function(a, b)
            if a.rank ~= b.rank then return a.rank < b.rank end
            if a.profit ~= b.profit then return (a.profit or 0) > (b.profit or 0) end
            if L.Text(a.name) ~= L.Text(b.name) then return L.Text(a.name) < L.Text(b.name) end
            return a.by < b.by
        end)
        memo.rows, memo.bags = rows, S.bagVer
    elseif memo.bags ~= S.bagVer then
        -- (only the bags changed: Can make again, nothing else)
        for _, row in ipairs(memo.rows) do L.SetCanMake(row) end
        memo.bags = S.bagVer
    end
    return memo.rows
end

function M.EnchantRows()
    local memo = L.Memo("enchants")
    if not memo.rows then
        local x, rows = L.Index(), {}
        for _, r in ipairs(x.list) do
            if r.e then
                local row = {name = r.n, recipe = r.n, by = L.MadeBy(x, r), mine = r.mine, cooldown = r.c and true or nil,
                             tip = {}, act = {M.ENCHANT_FOOTER}}
                row.cost, row.costWhy = L.Materials(r, row.tip)
                rows[#rows + 1] = row
            end
        end
        table.sort(rows, function(a, b)
            if a.name ~= b.name then return a.name < b.name end
            return a.by < b.by
        end)
        memo.rows = rows
    end
    return memo.rows
end

--------------------------------------------------------------------------
-- Vendors: bought from a vendor, sold on the auction house
--------------------------------------------------------------------------

function L.VendorRow(id, price, v)
    local sp, flag = M.SellPrice(id)
    if not sp then return nil end
    local profit = M.AfterCut(sp) - price
    if profit < math.max(price * 0.2, SILVER) then return nil end
    local listed, text = L.Listed(id)
    if (listed or 0) < 2 and not M.Usual(id) then return nil end
    local info = L.Info(id, true)
    local rec = L.Rec(id)
    local row = {id = id, key = id, name = info and info.name, icon = info and info.icon, quality = info and info.quality,
                 link = info and info.link, vendor = price, auction = sp, mark = flag, profit = profit, listed = listed,
                 listedText = text, t = rec and rec.t or nil, tip = {}, act = {}}
    if v then
        row.where = v.w .. (v.z ~= "" and (", " .. v.z) or "") .. (v.lim and " (limited supply)" or "")
        row.limited = v.lim and true or nil
        row.tip[1] = v.lim and "limited supply - often the real money" or "anyone can buy this from the vendor - sells slowly"
    else
        row.seed = true
        row.where = "trade supplies vendors (price not confirmed - visit one)"
        row.tip[1] = "anyone can buy this from the vendor - sells slowly"
    end
    row.tip[2] = ("Sells for %s on the auction house; %s after the %s%% cut."):format(M.Money(sp), M.Money(M.AfterCut(sp)), M.Cut())
    if flag == "unproven" then
        row.tip[3] = L.UnprovenLine(id)
    elseif flag == "none listed" then
        row.tip[3] = "None listed now - this is its usual price."
    end
    row.act[1] = "your price may differ with reputation"
    return row
end

function M.VendorRows()
    local memo = L.Memo("vendors")
    if memo.rows then return memo.rows end
    local rows, vendors = {}, L.Vendors()
    for id, v in pairs(vendors) do
        if type(id) == "number" and type(v) == "table" and type(v.p) == "number" then
            local ok, row = pcall(L.VendorRow, id, v.p, {w = L.Text(v.w), z = L.Text(v.z), lim = v.lim})
            if ok and row then rows[#rows + 1] = row end
        end
    end
    for id, price in pairs(D.seed or {}) do
        if type(vendors[id]) ~= "table" then
            local ok, row = pcall(L.VendorRow, id, price, nil)
            if ok and row then rows[#rows + 1] = row end
        end
    end
    table.sort(rows, function(a, b)
        if (a.seed or false) ~= (b.seed or false) then return not a.seed end
        if a.profit ~= b.profit then return a.profit > b.profit end
        return a.id < b.id
    end)
    memo.rows = rows
    return rows
end

--------------------------------------------------------------------------
-- Your bags: the best way to turn each stack into gold
--------------------------------------------------------------------------

-- reagent -> the best craft with a profit that uses it
function L.KeepFor()
    local memo = L.Memo("keep")
    if memo.map then return memo.map end
    memo.map = {}
    for _, row in ipairs(M.CraftRows()) do
        if row.profit and row.profit > 0 then
            for _, reagent in ipairs(row.r.reagents) do
                if not memo.map[reagent[1]] then memo.map[reagent[1]] = row.name or row.recipe end
            end
        end
    end
    return memo.map
end

function L.BagRow(s, x)
    local info = L.Info(s.id, true)
    local quality = s.quality or (info and info.quality)
    local row = {id = s.id, key = s.key, name = info and info.name, icon = info and info.icon, quality = quality,
                 link = s.link or (info and info.link), count = s.count, bound = s.bound or nil, tip = {}, act = {}}
    local best, how
    local function Offer(name, value)
        if value and (not best or value > best) then best, how = value, name end
    end
    local sell = info and info.sell
    if not s.noValue and sell and sell > 0 then row.vendor = sell * s.count end
    -- (greys, bound things and quest items can't be auctioned)
    local canAuction = not s.bound and quality ~= 0 and not (info and info.class == 12)
    local noneListed = false
    if canAuction then
        local unit, flag, cheaper = M.SellPrice(s.key)
        local priced = s.key
        if x.enchanter and L.essence[s.id] then
            -- worth more as its other size (an enchanter converts with a
            -- right-click): that size's price, and that price's own mark
            local value, mark, pair, each = L.MatValue(s.id)
            if pair then
                unit, flag, cheaper, priced = value, mark, nil, pair.other
                if pair.lesser then
                    row.tip[#row.tip + 1] = ("Worth more combined: 3 make one %s (%s each) - right-click to combine, then sell (estimate)."):format(
                                                L.Name(pair.other), M.Money(each))
                else
                    row.tip[#row.tip + 1] = ("Worth more split into 3 %s (%s each) - right-click to split, then sell (estimate)."):format(
                                                L.Name(pair.other), M.Money(each))
                end
            end
        end
        if unit then
            row.auction, row.mark = math.floor(M.AfterCut(unit) * s.count), flag
            if (cheaper or 0) > 0 then row.tip[#row.tip + 1] = L.CheapLine(unit, cheaper) end
            if flag == "unproven" then
                row.tip[#row.tip + 1] = L.UnprovenLine(priced)
            elseif flag == "none listed" then
                row.tip[#row.tip + 1] = "None listed now - this is its usual price."
            end
        elseif flag == "none listed" then
            -- (looked for and not there: an answer, and pricing again won't change it)
            noneListed = true
            row.tip[#row.tip + 1] = "None listed - no auction price to go by."
        end
        local rec = L.Rec(priced)
        row.t = rec and rec.t or nil
    end
    -- (a bound piece can't be mailed to the account's enchanter: this
    -- character's own Enchanting or nothing)
    local canDisenchant = x.enchanter
    if s.bound then canDisenchant = x.me and x.enchanters[x.me] or false end
    if canDisenchant and quality and quality >= 2 and quality <= 4 then
        local dis = M.DisenchantValue(s.key)
        if dis then row.disenchant = dis * s.count end
    end
    Offer("Auction", row.auction)
    Offer("Vendor", row.vendor)
    Offer("Disenchant", row.disenchant)
    row.confident = (row.auction ~= nil) or not canAuction or noneListed
    if row.confident then
        row.best, row.bestHow = best, how
        row.bestText = best and (how .. " " .. M.Money(best)) or "-"
    else
        -- without an auction price, "best" would only be a guess
        row.auctionText = "?"
        row.bestText = (row.vendor and ("Vendor " .. M.Money(row.vendor) .. " - ") or "") .. "auction price unknown"
    end
    row.keep = L.KeepFor()[s.id]
    if row.keep then table.insert(row.tip, 1, ("or keep it: %s uses it"):format(row.keep)) end
    return row
end

function M.BagRows()
    local memo = L.Memo("bags")
    if memo.rows and memo.ver == S.bagVer then return memo.rows end
    local rows, x = {}, L.Index()
    for _, s in ipairs(L.ReadBags()) do
        local ok, row = pcall(L.BagRow, s, x)
        if ok and row then rows[#rows + 1] = row end
    end
    table.sort(rows, function(a, b)
        if (a.best or -1) ~= (b.best or -1) then return (a.best or -1) > (b.best or -1) end
        if L.Text(a.name) ~= L.Text(b.name) then return L.Text(a.name) < L.Text(b.name) end
        return tostring(a.key) < tostring(b.key)
    end)
    memo.rows, memo.ver = rows, S.bagVer
    return rows
end

function M.BagTotals(rows, money)
    money = type(money) == "function" and money or M.Money
    local t = {vendor = 0, auction = 0, best = 0, unpriced = 0, unproven = 0}
    for _, row in ipairs(rows or {}) do
        t.vendor = t.vendor + (row.vendor or 0)
        if not row.confident then
            t.unpriced = t.unpriced + 1
        elseif row.mark == "unproven" then
            -- one seller's asking price is no sum to count on: it stays out
            -- of Auction - and of Best, unless the vendor or disenchanting
            -- is the stack's best anyway, which owes that price nothing
            if row.bestHow == "Auction" or not row.best then
                t.unproven = t.unproven + 1
            else
                t.best = t.best + row.best
            end
        else
            t.auction = t.auction + (row.auction or 0)
            t.best = t.best + (row.best or 0)
        end
    end
    -- (kept short: the window shows it on one line, and what to press must fit)
    t.text = ("Vendors %s / Auction %s / Best of each %s"):format(money(t.vendor), money(t.auction), money(t.best))
    if t.unpriced > 0 then t.text = t.text .. (" - %d unpriced (Price my items)"):format(t.unpriced) end
    if t.unproven > 0 then t.text = t.text .. (" - %d unproven, not counted"):format(t.unproven) end
    return t
end

L.on.BAG_UPDATE_DELAYED = function()
    S.bagVer = (S.bagVer or 0) + 1
    L.Tell("bags")
end

--------------------------------------------------------------------------
-- what the window asks: rows' tooltips, sorting, the header, the buttons
--------------------------------------------------------------------------

-- a row's tooltip lines: how it was worked out, the data's age, what to do
function M.Tip(row)
    local out = {}
    if type(row) ~= "table" then return out end
    for _, line in ipairs(row.tip or {}) do out[#out + 1] = line end
    if row.t then
        local age = time() - row.t
        out[#out + 1] = (age > RECENT and "Price last seen " or "Price from ") .. M.Ago(age)
    end
    for _, line in ipairs(row.act or {}) do out[#out + 1] = line end
    return out
end

-- "3 d old" for a row whose price is a last-seen one (over 48 hours), else nil
function M.Old(row)
    local age = type(row) == "table" and row.t and time() - row.t
    if age and age > RECENT then return L.Span(age) .. " old" end
end

-- sort rows by one field; rows without it last, whichever way
function M.Sort(rows, field, descending)
    local order = {}
    for i, row in ipairs(rows) do order[row] = i end
    table.sort(rows, function(a, b)
        local x, y = a[field], b[field]
        if type(x) == "boolean" then x = x and 1 or 0 end
        if type(y) == "boolean" then y = y and 1 or 0 end
        if x ~= y then
            if x == nil then return false end
            if y == nil then return true end
            if type(x) ~= type(y) then x, y = tostring(x), tostring(y) end
            if descending then return x > y end
            return x < y
        end
        return order[a] < order[b]
    end)
    return rows
end

function M.PriceState(tab)
    if not L.BookKey() then return "Can't tell which realm this is yet", false end
    local st, book, now = L.Stats(), L.Book(), time()
    local text, at
    if st.all == 0 then
        if not S.usedAuctionator then return L.NoPrices(), false end
        text, at = "Prices: none of our own yet", now
    else
        -- the book, not the last job: how many items it has a price of,
        -- then where from - the full scan, and "Price my items" when that
        -- was later
        local full, check = tonumber(book.full) or 0, tonumber(book.check) or 0
        local items = st.n > 0 and L.Items(st.n) or "nothing listed"
        local parts = {}
        if full > 0 then parts[#parts + 1] = "full scan " .. M.Ago(now - full) end
        if check > full then parts[#parts + 1] = "your items looked up " .. M.Ago(now - check) end
        if #parts > 0 then
            text, at = ("Prices: %s - %s"):format(items, table.concat(parts, ", ")), math.max(full, check)
        else
            text, at = ("Prices: %s from your own searches, %s"):format(items, M.Ago(now - st.newest)), st.newest
        end
    end
    if S.neutral then text = text .. " - Neutral auction house" end
    if S.usedAuctionator then text = text .. " (some prices from Auctionator)" end
    return text, now - at > (tab == "bargains" and HOUR or RECENT)
end

function M.Empty(tab)
    local st = L.Stats()
    if tab == "crafts" then
        if #L.Index().list == 0 then
            return "Open each profession window once on each character - that's how I learn your recipes."
        end
    elseif tab == "vendors" then
        if st.all == 0 and not S.usedAuctionator then return L.NoPrices() end
        return "Visit vendors - I remember what they sell - then price the items."
    elseif tab == "bargains" then
        if st.all == 0 then return L.NoPrices() end
        local age = time() - (st.deep or st.newest)
        if age > FRESH then
            local hours = math.max(1, math.floor(age / HOUR))
            return ("These prices are %d hour%s old - bargains will be gone. Press Scan or Price my items."):format(
                       hours, hours == 1 and "" or "s")
        end
        return "Nothing worth buying in the last scan."
    end
end

-- what a running job is doing
function L.Progress()
    if S.state == "asked" then return "Asking the auction house for its list..." end
    if S.state == "reading" and S.scan then
        return ("Scanning: %s of %s"):format(M.Count(S.scan.i), M.Count(S.scan.n))
    end
    local c = S.chk
    if S.state == "checking" and c then
        if S.paused then return "Paused while you buy or sell - continues when you're back on the list" end
        local done = math.min(c.count, L.CountKeys(c.answered) + L.CountKeys(c.failed))
        local left = (c.count - done) * 1.2
        return ("Pricing %s of %s (about %s)"):format(M.Count(math.min(c.count, done + 1)), M.Count(c.count),
                                                      left < 60 and (math.ceil(left) .. " s") or (math.ceil(left / 60) .. " min"))
    end
end

-- the last scan couldn't tell our own auctions apart: what to do about it,
-- said where it can be done - at the auction house
function L.OwnHint()
    local book = L.Book()
    if not (S.ahOpen and book and book.noOwners) then return nil end
    if not S.ownSeen then return "Your own auctions may be counted - open your Auctions tab once." end
    local n = L.OwnCounted().n
    if n > 0 then
        return ("Your own auctions are still counted in %d price%s - press Price my items."):format(n, n == 1 and "" or "s")
    end
end

-- a scan was asked for and never read to the end (a /reload, a disconnect,
-- the auction house closed) - and the game's 15 minutes still run
function L.Unfinished()
    local book = S.on and S.state == "idle" and L.Book()
    local wait = book and book.fullPending and L.ScanWait() or 0
    if wait > 0 then
        return ("The last scan didn't finish - the game allows another in %d min. Price my items works meanwhile."):format(
                   math.ceil(wait / 60))
    end
end

-- how long "Price my items" would take now
function L.CheckSeconds()
    local memo = L.Memo("checkN")
    if not memo.n then
        -- (no book yet: everything is still to price - and none is made here)
        memo.n = #L.CheckList(L.Book() or {items = {}})
    end
    return math.ceil(memo.n * 1.2)
end

function M.State()
    local idle, wait = S.state == "idle", L.ScanWait()
    local scan = {label = "Scan", enabled = S.on and S.ahOpen and idle and wait <= 0}
    if not S.ahOpen then
        scan.tip = "Open the auction house first"
    elseif S.state == "checking" then
        scan.tip = "Wait for the price check to finish"
    elseif not idle then
        scan.tip = "A scan is running"
    elseif wait > 0 then
        scan.tip = "The auction house allows a full scan about once every 15 minutes."
    else
        scan.tip = "Reads every auction once (the game allows it about every 15 minutes)."
    end
    if wait > 0 then scan.label = ("Scan (in %d min)"):format(math.ceil(wait / 60)) end
    local checking = S.state == "checking"
    local check = {label = checking and "Stop" or "Price my items", enabled = S.on and S.ahOpen and (idle or checking)}
    if not S.ahOpen then
        check.tip = "Open the auction house first"
    elseif not (idle or checking) then
        check.tip = "Wait for the scan to finish"
    else
        check.tip = ("Looks up only the items your recipes and bags use. About %d seconds. Works even when Scan is on its 15-minute wait."):format(
                        L.CheckSeconds())
    end
    return {state = S.state, ahOpen = S.ahOpen, neutral = S.neutral, paused = S.paused,
            message = L.Progress() or S.message or L.Unfinished(),
            hint = L.OwnHint(), auctionator = S.usedAuctionator and true or false, scan = scan, check = check}
end

-- a name cut to what the auction house's search box takes (63 bytes), never
-- through the middle of a character
function L.Cut63(s)
    if #s <= 63 then return s end
    local cut = 63
    while cut > 0 do
        local b = s:byte(cut + 1)
        if b < 128 or b >= 192 then break end
        cut = cut - 1
    end
    return s:sub(1, cut)
end

-- the Search button (the player's own click): Auctionator's exact search
-- when it is there, else the name into Blizzard's search box - the player
-- clicks Search there (the box hasn't the keyboard: Enter alone opens chat)
function M.Search(name)
    name = PlainStr(name)
    if not name then return "Still loading this item's name" end
    if not S.ahOpen then return "Open the auction house first" end
    local api = L.AuctionatorAPI()
    if api and type(api.MultiSearchExact) == "function" and pcall(api.MultiSearchExact, CALLER, {name}) then
        return "Searching in Auctionator"
    end
    local ah = AuctionHouseFrame
    local bar = type(ah) == "table" and ah.SearchBar
    local box = type(bar) == "table" and bar.SearchBox
    local shown = false
    if type(bar) == "table" then
        local ok, yes = pcall(bar.IsShown, bar)
        shown = ok and yes and true or false
    end
    if shown and type(box) == "table" and pcall(box.SetText, box, L.Cut63(name)) then
        return ("%s is in the auction house's search box - click Search there."):format(name)
    end
    return "Open the Buy tab first"
end

-- forget the current realm's prices (recipes and vendor prices stay)
function M.Forget()
    local key, book = L.BookKey(), L.Book()
    if not book then return 0 end
    if S.state ~= "idle" then M.Abort("stopped") end
    -- (the count the header gave: items with a price, not every record)
    local n = L.Stats().n
    local asked = tonumber(book.fullAsked)
    -- (the wait between scans is the game's: it isn't forgotten)
    ns.db.goldBook[key] = (asked and time() - asked < SCAN_WAIT) and {items = {}, fullAsked = asked} or nil
    S.bargains, S.message = nil, nil
    -- (a Bargains pass under way still holds the old book: it mustn't finish)
    S.aGen, S.aJob, S.leftOut = S.aGen + 1, nil, 0
    L.Bump()
    return n
end

function L.Window(open)
    if not S.on then
        ns.Print("gold: switched off - |cFFFFCC00/pqol gold on|r switches it on")
        return
    end
    local ui = M.ui
    local fn = type(ui) == "table" and ((open and ui.Open) or ui.Toggle)
    if type(fn) == "function" then
        ns.SafeCall("gold", fn)
    else
        ns.Print("gold: the window isn't available")
    end
end
function M.Toggle() L.Window(false) end
-- (the options page's button: the window may come up behind that page, and
-- a second click must not close what the player never saw)
function M.Open() L.Window(true) end

--------------------------------------------------------------------------
-- the feature: events, slash command, status
--------------------------------------------------------------------------

L.EVENTS = {
    "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "REPLICATE_ITEM_LIST_UPDATE", "COMMODITY_SEARCH_RESULTS_UPDATED",
    "ITEM_SEARCH_RESULTS_UPDATED", "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", "AUCTION_HOUSE_BROWSE_RESULTS_ADDED",
    "AUCTION_HOUSE_THROTTLED_SYSTEM_READY", "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED", "OWNED_AUCTIONS_UPDATED",
    "TRADE_SKILL_SHOW", "TRADE_SKILL_CLOSE", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_DATA_SOURCE_CHANGED",
    "NEW_RECIPE_LEARNED", "MERCHANT_SHOW", "MERCHANT_UPDATE", "ITEM_DATA_LOAD_RESULT", "GET_ITEM_INFO_RECEIVED",
    "BAG_UPDATE_DELAYED"
}

local frame = CreateFrame("Frame")
M.eventFrame = frame
frame:SetScript("OnEvent", ns.Guard("gold", function(_, event, ...)
    local handler = L.on[event]
    if not (handler and S.on) then return end
    local ok, err = pcall(handler, ...)
    if ok then return end
    -- on record once - and a job under way ends here (L.Fail) rather than
    -- wait for ever on a step this handler didn't finish
    if S.state ~= "idle" then return L.Fail(err) end
    ns.SafeCall("gold", error, tostring(err), 0)
end))

function M:Init()
    local db = ns.db
    db.goldCut = L.Clamp(tonumber(db.goldCut) or 5, 0, 30)
    L.PruneAll()
end

function M:Apply(on)
    on = on and true or false
    S.on = on
    for _, event in ipairs(L.EVENTS) do
        -- (an event this client doesn't know throws: it just isn't heard)
        if on then pcall(frame.RegisterEvent, frame, event) else pcall(frame.UnregisterEvent, frame, event) end
    end
    if not on then
        M.Abort("off")
        S.ahOpen, S.ahTok, S.neutral = false, S.ahTok + 1, false
        S.rGen, S.aGen, S.aJob = S.rGen + 1, S.aGen + 1, nil
        L.StopQueue()
    end
    L.Tell("apply", on)
    -- switched on with the auction house already open: its event was missed
    local ah = on and AuctionHouseFrame
    if type(ah) == "table" and not S.ahOpen then
        local ok, shown = pcall(ah.IsShown, ah)
        if ok and shown then L.on.AUCTION_HOUSE_SHOW() end
    end
end

function M:Status()
    local st, book, now = L.Stats(), L.Book(), time()
    local prices = "no prices yet"
    if st.all > 0 then
        prices = "prices of " .. L.Items(st.n)
        local full, check = tonumber(book.full) or 0, tonumber(book.check) or 0
        if full > 0 and full >= check then
            prices = prices .. ", full scan " .. M.Ago(now - full)
        elseif check > 0 then
            prices = prices .. ", priced " .. M.Ago(now - check)
        end
    end
    return ("(%s; recipes of %d character%s; %s vendor prices; cut %s%%)"):format(prices, L.CountKeys(L.Recipes()),
               L.CountKeys(L.Recipes()) == 1 and "" or "s", M.Count(L.CountKeys(L.Vendors())), tostring(M.Cut()))
end

-- the options page's note
function M.Note()
    if not S.on then return "Switched off." end
    local text = M.PriceState()
    return text .. " |cFFFFCC00/pqol gold|r opens the window."
end

L.HELP = "gold: |cFFFFCC00/pqol gold|r opens the window; |cFFFFCC00scan|r reads the whole auction house; |cFFFFCC00price|r looks up the items your recipes and bags use (again: stops); |cFFFFCC00cut <0-30>|r the auction house's cut in percent; |cFFFFCC00forget|r forgets this realm's prices"

function L.CutCommand(value)
    if value == "" then
        ns.Print("gold: the auction house's cut is counted as %s%% - |cFFFFCC00/pqol gold cut <0-30>|r changes it", tostring(M.Cut()))
        return
    end
    local n = tonumber(value)
    if not n or n ~= n then
        ns.Print("gold: |cFFFFCC00/pqol gold cut <0-30>|r - the auction house's cut in percent, as a number")
        return
    end
    ns.db.goldCut = L.Clamp(n, 0, 30)
    L.Bump()
    L.StartAnalysis()
    ns.Print("gold: the auction house's cut is now counted as %s%%", tostring(M.Cut()))
end

-- /pqol gold <arg> (on and off are Core's)
function M:Command(arg)
    arg = arg or ""
    local word, rest = arg:match("^(%S*)%s*(.-)$")
    if word == "" then
        M.Toggle()
    elseif word == "scan" then
        local ok, why = M.StartScan()
        ns.Print("gold: %s", ok and "asked the auction house for its list" or why)
    elseif word == "price" or word == "check" then
        local ok, why = M.StartCheck()
        if ok and why == "stopped" then
            ns.Print("gold: price check stopped")
        elseif ok then
            local n = S.chk and S.chk.count or 0
            ns.Print("gold: pricing %s, about %d seconds", L.Items(n), math.ceil(n * 1.2))
        else
            ns.Print("gold: %s", why)
        end
    elseif word == "cut" then
        L.CutCommand(rest)
    elseif word == "forget" then
        ns.Print("gold: forgot the prices of %s on this realm", L.Items(M.Forget()))
    else
        ns.Print("%s", L.HELP)
    end
    return true
end

ns.RegisterFeature("gold",
    -- (two lines of the options page at most: the page doesn't scroll)
    "Gold finder: what makes gold right now - your recipes, auctions worth buying, vendor items and your bags (|cFFFFCC00/pqol gold|r; it never buys or posts for you)",
    M)
