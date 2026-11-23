-- Pace's Quality of Life - Gold finder: the window and the auction house button
-- (the sums and the saved data are Gold.lua's; what this file may call is
-- listed at the top of that file)
--
--   * The window is a frame of our own, built the first time it is opened:
--     four tabs, a line saying how old the prices are, column headers that
--     sort, 14 rows scrolled by the mouse wheel or a slider of our own, and
--     the Scan / Price my items / Search buttons.
--   * A refresh reads the tab's row list from Gold.lua (kept there until the
--     data changes), sorts a copy when a column was clicked, and fills the
--     14 rows. Nothing here walks the price book, and nothing runs per frame:
--     a refresh follows a click, the wheel, or Gold.lua saying something
--     changed (at most one every 0.2 s), a one-second tick runs only while
--     a countdown or a job's progress is on screen, and while the window is
--     open it is refreshed once a minute (the header says how old the
--     prices are).
--   * Search only puts the item's name into the auction house's search box
--     (or hands it to Auctionator): the player clicks Search there. Nothing
--     is bought, bid on or posted from here.
--   * The auction house button is ours, parented to AuctionHouseFrame and
--     sitting just above its top right corner; nothing is written into
--     Blizzard's frames.
--   * Fields we keep on our own widgets are lower-case, and every value a
--     widget hands back is checked before use.

local addonName, ns = ...

local Gold = ns.Gold
if not Gold then return end

-- U is Gold.ui: the window's state and widgets (tests read them)
local U = {tab = "crafts", offset = 0, sort = {}, on = false, enchants = false}
Gold.ui = U

local WIDTH, HEIGHT = 720, 460
local ROWS, ROW_H = 14, 20
local LEFT, LIST_W = 12, 676
local LIST_TOP = -98          -- the first row's top, from the window's top
local MAX_COLS = 8
local WHEEL = 3               -- rows per notch of the mouse wheel

local GREY, ORANGE, RED, YELLOW = "|cff808080", "|cffff9933", "|cffff6666", "|cffffd100"
-- item quality colours (poor .. legendary)
local QUALITY = {[0] = "9d9d9d", [1] = "ffffff", [2] = "1eff00", [3] = "0070dd", [4] = "a335ee", [5] = "ff8000"}
local COIN_G = "|TInterface\\MoneyFrame\\UI-GoldIcon:0|t"
local COIN_S = "|TInterface\\MoneyFrame\\UI-SilverIcon:0|t"
local COIN_C = "|TInterface\\MoneyFrame\\UI-CopperIcon:0|t"
local ARROW_UP = "Interface\\Buttons\\Arrow-Up-Up"
local ARROW_DOWN = "Interface\\Buttons\\Arrow-Down-Up"
local UNKNOWN_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

local TABS = {{"crafts", "Crafts"}, {"bargains", "Bargains"}, {"vendors", "Vendors"}, {"bags", "Your bags"}}

local function Later(delay, fn) C_Timer.After(delay, ns.Guard("gold", fn)) end

--------------------------------------------------------------------------
-- what a cell says
--------------------------------------------------------------------------

-- copper with coin icons: "1,204[g] 56[s] 7[c]". short: no copper from 10
-- gold up, so a column never has to cut a price off
local function Coins(copper, short)
    copper = tonumber(copper)
    if not copper or copper ~= copper then return "?" end
    local sign = copper < 0 and "-" or ""
    copper = math.floor(math.abs(copper))
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = Gold.Count(g) .. COIN_G end
    if s > 0 then parts[#parts + 1] = s .. COIN_S end
    if (c > 0 and not (short and g >= 10)) or #parts == 0 then parts[#parts + 1] = c .. COIN_C end
    return sign .. table.concat(parts, " ")
end
U.Coins = Coins

-- a price in a row: nothing for none, a grey "?" for unknown
local function Cell(copper, unknown)
    if copper then return Coins(copper, true) end
    return unknown and (GREY .. "?|r") or ""
end

local function NameCell(row)
    local text
    if row.name then
        text = "|cff" .. (QUALITY[row.quality] or QUALITY[1]) .. row.name .. "|r"
    elseif row.id then
        text = GREY .. "item #" .. tostring(row.id) .. "|r"
    else
        text = "?"
    end
    local extra = {}
    if row.cooldown then extra[#extra + 1] = "cooldown" end
    if row.bound then extra[#extra + 1] = "bound" end
    if row.note then extra[#extra + 1] = row.note end
    -- (a price over 48 hours old is a "last seen" one: its age beside it)
    local old = Gold.Old(row)
    if old then extra[#extra + 1] = old end
    if #extra > 0 then text = text .. " " .. GREY .. table.concat(extra, ", ") .. "|r" end
    return text
end

-- what it sells for, with the small mark of a price that isn't proven
local function SellsCell(value, mark)
    if not value then return GREY .. "?|r" end
    local text = Coins(value, true)
    if mark == "unproven" then
        text = text .. " " .. YELLOW .. "*|r"
    elseif mark == "none listed" then
        text = text .. " " .. GREY .. "*|r"
    end
    return text
end

local function ProfitCell(row)
    local p = row.profit
    if not p then return GREY .. "?|r" end
    local text = (row.estimate and "~" or "") .. Coins(p, true)
    if p < 0 then text = RED .. text .. "|r" end
    return text
end

local function BestCell(row)
    if not row.confident then return GREY .. tostring(row.bestText or "?") .. "|r" end
    if not row.best then return GREY .. "-|r" end
    -- (an auction price that isn't proven keeps its mark here too)
    if row.bestHow == "Auction" and row.mark then return "Auction " .. SellsCell(row.best, row.mark) end
    return tostring(row.bestHow) .. " " .. Coins(row.best, true)
end

-- the columns of each list: {title, width, the field it sorts by, the
-- cell's text; right = a number (right-aligned, sorted highest first),
-- icon = the item's icon goes here}
local COLUMNS = {
    crafts = {
        {"Item", 170, "name", NameCell, icon = true},
        {"Made by", 100, "by", function(r) return r.by end},
        {"Cost", 72, "cost", function(r) return Cell(r.cost, true) end, right = true},
        {"Sells for", 82, "sells", function(r) return SellsCell(r.sells, r.mark) end, right = true},
        {"How", 62, "how", function(r) return r.how end},
        {"Profit", 76, "profit", ProfitCell, right = true},
        {"Listed", 42, "listed", function(r) return r.listedText end, right = true},
        {"Can make", 60, "canMake", function(r) return r.canMakeText end, right = true},
    },
    enchants = {
        {"Enchant", 300, "name", NameCell},
        {"Made by", 220, "by", function(r) return r.by end},
        {"Cost", 110, "cost", function(r) return Cell(r.cost, true) end, right = true},
    },
    bargains = {
        {"Kind", 66, "kind", function(r) return r.kind end},
        {"Item", 244, "name", NameCell, icon = true},
        {"Cheapest", 74, "cheapest", function(r) return Cell(r.cheapest) end, right = true},
        {"Buy up to", 74, "upTo", function(r) return Cell(r.upTo) end, right = true},
        {"Worth", 74, "worth", function(r) return Cell(r.worth) end, right = true},
        {"Units", 46, "units", function(r) return r.units and Gold.Count(r.units) end, right = true},
        {"Profit", 86, "profit", ProfitCell, right = true},
    },
    vendors = {
        {"Item", 170, "name", NameCell, icon = true},
        {"Vendor price", 78, "vendor", function(r) return Cell(r.vendor) end, right = true},
        {"Auction price", 86, "auction", function(r) return SellsCell(r.auction, r.mark) end, right = true},
        {"Profit each", 78, "profit", ProfitCell, right = true},
        {"Listed", 42, "listed", function(r) return r.listedText end, right = true},
        {"Where", 210, "where", function(r) return r.where end},
    },
    bags = {
        {"Item", 180, "name", NameCell, icon = true},
        {"Count", 44, "count", function(r) return r.count and Gold.Count(r.count) end, right = true},
        {"Vendor", 76, "vendor", function(r) return Cell(r.vendor) end, right = true},
        {"Auction", 76, "auction", function(r)
            if r.auctionText then return GREY .. r.auctionText .. "|r" end
            return r.auction and SellsCell(r.auction, r.mark) or ""
        end, right = true},
        {"Disenchant", 76, "disenchant", function(r) return Cell(r.disenchant) end, right = true},
        {"Best", 212, "best", BestCell},
    },
}
U.COLUMNS = COLUMNS

--------------------------------------------------------------------------
-- the list on screen
--------------------------------------------------------------------------

-- the tab's rows from Gold.lua: rows, which columns, the Bargains pass's state
local function Source()
    if U.tab == "crafts" then
        if U.enchants then return Gold.EnchantRows(), "enchants" end
        return Gold.CraftRows(), "crafts"
    elseif U.tab == "bargains" then
        local rows, meta = Gold.BargainRows()
        return rows, "bargains", meta
    elseif U.tab == "vendors" then
        return Gold.VendorRows(), "vendors"
    end
    return Gold.BagRows(), "bags"
end

-- what tells one row from another once the lists have been worked out again
local function Sig(row)
    return tostring(row.key or row.name) .. "/" .. tostring(row.kind or row.by or "") .. (row.bound and "/bound" or "")
end

-- keep the selection on the same item when the list was rebuilt
local function Reselect(list)
    local sel = U.selected
    if not (sel or U.selSig) then return end
    for _, row in ipairs(list) do if sel and row == sel then return end end
    U.selected = nil
    for _, row in ipairs(list) do
        if Sig(row) == U.selSig then
            U.selected = row
            return
        end
    end
end

local function MaxOffset() return math.max(0, #(U.list or {}) - ROWS) end

-- put the headers and every row's cells where this list's columns are
local function LayOut(view)
    if U.laidOut == view then return end
    U.laidOut = view
    local cols = COLUMNS[view]
    local x = 2
    for i = 1, MAX_COLS do
        local col, head = cols[i], U.heads[i]
        head.col = col
        if col then
            head:ClearAllPoints()
            head:SetPoint("TOPLEFT", U.frame, "TOPLEFT", LEFT + x, LIST_TOP + 20)
            head:SetSize(col[2], 18)
            head.label:SetJustifyH(col.right and "RIGHT" or "LEFT")
            -- (the sort arrow sits over the head's top edge, on the side the
            -- title is on: the narrow columns have no room beside the title)
            head.arrow:ClearAllPoints()
            if col.right then
                head.arrow:SetPoint("BOTTOMRIGHT", head, "TOPRIGHT", -3, -4)
            else
                head.arrow:SetPoint("BOTTOMLEFT", head, "TOPLEFT", 3, -4)
            end
            head:Show()
            local left = x + (col.icon and 22 or 3)
            for _, b in ipairs(U.rows) do
                local cell = b.cells[i]
                cell:ClearAllPoints()
                cell:SetPoint("LEFT", b, "LEFT", left, 0)
                cell:SetWidth(col[2] - (col.icon and 25 or 6))
                cell:SetJustifyH(col.right and "RIGHT" or "LEFT")
                cell:Show()
                if col.icon then
                    b.icon:ClearAllPoints()
                    b.icon:SetPoint("LEFT", b, "LEFT", x + 3, 0)
                end
            end
            x = x + col[2]
        else
            head:Hide()
            for _, b in ipairs(U.rows) do
                b.cells[i]:SetText("")
                b.cells[i]:Hide()
            end
        end
    end
end

local function FillHeads(view)
    local sort = U.sort[view]
    for i, col in ipairs(COLUMNS[view]) do
        local head = U.heads[i]
        head.label:SetText(col[1])
        if sort and sort.field == col[3] then
            head.arrow:SetTexture(sort.desc and ARROW_DOWN or ARROW_UP)
            head.arrow:Show()
        else
            head.arrow:Hide()
        end
    end
end

-- (defined with the tooltips, below)
local RowTip

local function FillRows()
    local list, cols = U.list or {}, COLUMNS[U.view or "crafts"]
    local iconCol = false
    for _, col in ipairs(cols) do if col.icon then iconCol = true end end
    for i, b in ipairs(U.rows) do
        local row = list[U.offset + i]
        b.row = row
        if row then
            -- (a name not loaded yet: asked for ahead of the queue; Gold.lua
            -- says "change" when it arrives)
            if row.id and not row.name then Gold.Info(row.id, true) end
            for c, col in ipairs(cols) do
                local text = col[4](row)
                b.cells[c]:SetText(text ~= nil and tostring(text) or "")
            end
            if iconCol and row.id then
                b.icon:SetTexture(row.icon or UNKNOWN_ICON)
                b.icon:Show()
            else
                b.icon:Hide()
            end
            b.sel:SetShown(row == U.selected)
            b:Show()
        else
            b:Hide()
        end
    end
    local n = #list
    if n > 0 then
        U.count:SetText(("%d-%d of %s"):format(U.offset + 1, math.min(n, U.offset + ROWS), Gold.Count(n)))
    else
        U.count:SetText("")
    end
    -- the tooltip of the row under the mouse follows what the row now shows
    local tt = GameTooltip
    if type(tt) == "table" and type(tt.IsOwned) == "function" then
        for _, b in ipairs(U.rows) do
            if tt:IsOwned(b) and b.row ~= U.tipRow then
                if b.row then RowTip(b) else tt:Hide() end
            end
        end
    end
end

-- what an empty list says instead
local function EmptyText(view, meta)
    if view == "bargains" then
        if meta and meta.working then return "Looking through the prices for bargains..." end
        return meta and meta.empty or Gold.Empty("bargains") or "Nothing worth buying in the last scan."
    elseif view == "enchants" then
        return Gold.Empty("crafts") or "None of your recorded recipes is an enchant."
    elseif view == "crafts" then
        return Gold.Empty("crafts") or "None of your recorded recipes makes an item."
    elseif view == "vendors" then
        return Gold.Empty("vendors") or "Visit vendors - I remember what they sell - then price the items."
    end
    return Gold.Empty("bags") or "Your bags are empty."
end

-- the line under the list
local function FootText(view, list, meta)
    if view == "bags" then
        -- (short coins: three sums and what to press have to fit one line)
        return #list > 0 and Gold.BagTotals(list, U.ShortCoins).text or ""
    elseif view == "enchants" then
        return #list > 0 and Gold.ENCHANT_FOOTER or ""
    elseif view == "bargains" and meta then
        local parts = {}
        if (tonumber(meta.loading) or 0) > 0 then
            parts[#parts + 1] = ("%s item%s still loading"):format(Gold.Count(meta.loading), meta.loading == 1 and "" or "s")
        end
        if meta.working and #list > 0 then parts[#parts + 1] = "still looking" end
        return table.concat(parts, " - ")
    end
    return ""
end

function U.ShortCoins(copper) return Coins(copper, true) end

local function SetButton(b, label, enabled, tip)
    b:SetText(label)
    if enabled then b:Enable() else b:Disable() end
    b.tip = tip
end

-- the three buttons and the line above them; true when a countdown or a
-- job's progress is showing (the one-second tick keeps them current)
local function Footer()
    local st = Gold.State()
    SetButton(U.scan, st.scan.label, st.scan.enabled, st.scan.tip)
    SetButton(U.check, st.check.label, st.check.enabled, st.check.tip)
    local sel = U.selected
    if not sel then
        SetButton(U.search, "Search", false, "Click a row first.")
    elseif not sel.id then
        SetButton(U.search, "Search", false, "An enchant isn't an item: there is nothing to search for.")
    elseif not sel.name then
        SetButton(U.search, "Search", false, "Still loading this item's name")
    else
        SetButton(U.search, "Search", true,
                  ("Puts %s into the auction house's search box - then click Search there. Pace's QoL never buys for you."):format(
                      sel.name))
    end
    -- (a note is about the moment it was said in: gone once a job starts or
    -- ends, or the auction house opens or closes)
    if U.note and (st.state ~= U.noteState or st.ahOpen ~= U.noteAh) then U.note = nil end
    -- (the warning that our own auctions may be counted stays beside
    -- whatever the last job said)
    local said = st.message
    if said and st.hint then said = said .. " " .. st.hint end
    U.status:SetText(U.note or said or st.hint or "")
    return st.state ~= "idle" or st.scan.label ~= "Scan"
end

-- what a click has to say, on the line above the buttons: until the state
-- it was said in changes, and for 8 seconds at most (a job's progress and
-- how it ended belong on that line too)
local function SetNote(text)
    U.note = text
    U.noteTok = (U.noteTok or 0) + 1
    if not text then return end
    local st, tok = Gold.State(), U.noteTok
    U.noteState, U.noteAh = st.state, st.ahOpen
    Later(8, function()
        if tok ~= U.noteTok or not U.note then return end
        U.note = nil
        if U.frame and U.frame:IsShown() then Footer() end
    end)
end

local function Tick()
    U.ticking = false
    if not (U.frame and U.frame:IsShown()) then return end
    if Footer() then
        U.ticking = true
        Later(1, Tick)
    end
end

function U.Refresh()
    local f = U.frame
    if not (f and f:IsShown()) then return end
    -- (the rows first: the header then knows whether a shown price was Auctionator's)
    local src, view, meta = Source()
    local sort, list = U.sort[view], src
    if sort then
        -- (a copy: Gold.lua's own list keeps its order)
        list = {}
        for i, row in ipairs(src) do list[i] = row end
        Gold.Sort(list, sort.field, sort.desc)
    end
    U.list, U.view = list, view
    Reselect(list)
    U.offset = math.max(0, math.min(U.offset, MaxOffset()))
    -- (a new range can move the slider's old value, and the slider then says
    -- so: that isn't the player scrolling)
    U.syncing = true
    U.slider:SetMinMaxValues(0, MaxOffset())
    U.slider:SetValue(U.offset)
    U.syncing = false
    U.slider:SetShown(MaxOffset() > 0)

    for _, tab in ipairs(TABS) do
        local b = U.tabs[tab[1]]
        if tab[1] == U.tab then b:Disable() else b:Enable() end
    end
    U.enchantCheck:SetShown(U.tab == "crafts")
    U.enchantCheck:SetChecked(U.enchants)

    LayOut(view)
    FillHeads(view)
    FillRows()

    local text, old = Gold.PriceState(U.tab)
    U.header:SetText((old and ORANGE or "") .. tostring(text or "") .. (old and "|r" or ""))
    if #list == 0 then
        U.empty:SetText(EmptyText(view, meta))
        U.empty:Show()
    else
        U.empty:Hide()
    end
    U.foot:SetText(FootText(view, list, meta))
    if Footer() and not U.ticking then
        U.ticking = true
        Later(1, Tick)
    end
    -- the header's "25 min ago" (and what is too old to show) moves with
    -- the clock: once a minute while the window is open
    if not U.minute then
        U.minute = true
        Later(60, function()
            U.minute = false
            U.Refresh()
        end)
    end
end

-- a refresh soon: once per 0.2 s however often it is asked for
function U.Soon()
    if U.pending or not (U.frame and U.frame:IsShown()) then return end
    U.pending = true
    Later(0.2, function()
        U.pending = false
        U.Refresh()
    end)
end

local function ScrollTo(offset)
    offset = math.max(0, math.min(math.floor((tonumber(offset) or 0) + 0.5), MaxOffset()))
    if offset == U.offset then return end
    U.offset = offset
    U.slider:SetValue(offset)
    FillRows()
end

local function SetTab(key)
    if U.tab == key then return end
    U.tab, U.offset, U.selected, U.selSig = key, 0, nil, nil
    SetNote(nil)
    U.Refresh()
end
U.SetTab = SetTab

--------------------------------------------------------------------------
-- tooltips
--------------------------------------------------------------------------

local function HideTip() GameTooltip:Hide() end

-- a row: the item's own tooltip, then how the row was worked out
-- (SetHyperlink and SetItemByID say false, and hide the tooltip, when the
-- game has nothing to show for the item: not having thrown isn't enough)
local function TipItem(tt, method, arg)
    if type(tt[method]) ~= "function" then return false end
    local ok, shown = pcall(tt[method], tt, arg)
    return ok and shown ~= false
end

function RowTip(b)
    local row = b.row
    if not row then return end
    U.tipRow = row
    local tt = GameTooltip
    tt:SetOwner(b, "ANCHOR_RIGHT")
    local item = false
    if row.link then item = TipItem(tt, "SetHyperlink", row.link) end
    if not item and row.id then item = TipItem(tt, "SetItemByID", row.id) end
    if not item then
        -- (ours again: a tooltip that hid itself has let go of its owner)
        tt:SetOwner(b, "ANCHOR_RIGHT")
        tt:AddLine(row.name or (row.id and ("item #" .. tostring(row.id))) or "?")
    end
    local lines = Gold.Tip(row)
    if row.confident == false and row.bestText then table.insert(lines, 1, row.bestText) end
    if #lines > 0 then tt:AddLine(" ") end
    for _, line in ipairs(lines) do tt:AddLine(line, 0.9, 0.9, 0.9, true) end
    tt:Show()
end

-- a button or header: its name, then b.tip
local function PlainTip(b)
    if not b.tip then return end
    local tt = GameTooltip
    tt:SetOwner(b, "ANCHOR_TOP")
    if b.tipTitle then tt:AddLine(b.tipTitle) end
    tt:AddLine(b.tip, 1, 1, 1, true)
    tt:Show()
end

local function WithTip(b, title, tip)
    b.tipTitle, b.tip = title, tip
    b:SetScript("OnEnter", ns.Guard("gold", PlainTip))
    b:SetScript("OnLeave", ns.Guard("gold", HideTip))
    -- (a disabled button says why it is: it still needs the mouse)
    if b.SetMotionScriptsWhileDisabled then b:SetMotionScriptsWhileDisabled(true) end
end

--------------------------------------------------------------------------
-- clicks
--------------------------------------------------------------------------

local function ClickRow(b)
    local row = b.row
    if not row then return end
    U.selected, U.selSig = row, Sig(row)
    SetNote(nil)
    for _, other in ipairs(U.rows) do other.sel:SetShown(other.row == row) end
    Footer()
end

-- a header: sort by its column (numbers highest first, words a-z), again
-- to reverse; the right button brings the list's own order back
local function ClickHead(head, button)
    local col, view = head.col, U.view
    if not (col and view) then return end
    local sort = U.sort[view]
    if button == "RightButton" then
        U.sort[view] = nil
    elseif sort and sort.field == col[3] then
        sort.desc = not sort.desc
    else
        U.sort[view] = {field = col[3], desc = col.right and true or false}
    end
    U.offset = 0
    U.Refresh()
end

local function ClickScan()
    local ok, why = Gold.StartScan()
    SetNote((not ok and type(why) == "string") and (why:sub(1, 1):upper() .. why:sub(2)) or nil)
    U.Refresh()
end

local function ClickCheck()
    local ok, why = Gold.StartCheck()
    SetNote((not ok and type(why) == "string") and (why:sub(1, 1):upper() .. why:sub(2)) or nil)
    U.Refresh()
end

-- the player's own click: the name goes to the auction house's search box
-- (or to Auctionator); what to do next is said on the line above the buttons
local function ClickSearch()
    local row = U.selected
    if not row then return end
    SetNote(Gold.Search(row.name))
    Footer()
end

--------------------------------------------------------------------------
-- the window
--------------------------------------------------------------------------

local function Text(parent, font, justify)
    local fs = parent:CreateFontString(nil, "ARTWORK", font)
    fs:SetJustifyH(justify or "LEFT")
    -- (one line, cut off with "..." when it doesn't fit)
    if fs.SetWordWrap then fs:SetWordWrap(false) end
    return fs
end

-- where the window was left (goldPos = {point, relative point, x, y})
local function Place(f)
    f:ClearAllPoints()
    local p = ns.db and ns.db.goldPos
    if type(p) == "table" and type(p[1]) == "string" and type(p[2]) == "string" and Gold.Plain(p[3]) and Gold.Plain(p[4]) and
        pcall(f.SetPoint, f, p[1], UIParent, p[2], p[3], p[4]) then
        return
    end
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
end

local function KeepPlace(f)
    local point, _, relative, x, y = f:GetPoint(1)
    x, y = Gold.Plain(x), Gold.Plain(y)
    if type(point) ~= "string" or not (x and y) or not ns.db then return end
    ns.db.goldPos = {point, type(relative) == "string" and relative or point, math.floor(x + 0.5), math.floor(y + 0.5)}
end

local function Button(parent, text, width, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    b:SetText(text)
    b:SetScript("OnClick", ns.Guard("gold", onClick))
    return b
end

local function BuildRow(f, i)
    local b = CreateFrame("Button", nil, f)
    b:SetSize(LIST_W, ROW_H)
    b:SetPoint("TOPLEFT", f, "TOPLEFT", LEFT, LIST_TOP - (i - 1) * ROW_H)
    if i % 2 == 0 then
        local stripe = b:CreateTexture(nil, "BACKGROUND")
        stripe:SetAllPoints(b)
        stripe:SetColorTexture(1, 1, 1, 0.04)
    end
    b.sel = b:CreateTexture(nil, "BORDER")
    b.sel:SetAllPoints(b)
    b.sel:SetColorTexture(1, 0.82, 0, 0.2)
    b.sel:Hide()
    b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(16, 16)
    b.cells = {}
    for c = 1, MAX_COLS do b.cells[c] = Text(b, "GameFontHighlightSmall") end
    b:SetScript("OnClick", ns.Guard("gold", ClickRow))
    b:SetScript("OnEnter", ns.Guard("gold", RowTip))
    b:SetScript("OnLeave", ns.Guard("gold", HideTip))
    b:Hide()
    return b
end

local function Build()
    local f = CreateFrame("Frame", nil, UIParent, "BasicFrameTemplateWithInset")
    f:Hide()
    f:SetSize(WIDTH, HEIGHT)
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    Place(f)

    -- (the template has no title of its own)
    U.title = Text(f, "GameFontNormal", "CENTER")
    U.title:SetPoint("TOP", f, "TOP", 0, -5)
    U.title:SetText("Gold finder - Pace's Quality of Life")

    -- the title bar moves the window
    local drag = CreateFrame("Frame", nil, f)
    drag:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    drag:SetPoint("TOPRIGHT", f, "TOPRIGHT", -28, 0)
    drag:SetHeight(22)
    drag:EnableMouse(true)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", ns.Guard("gold", function() f:StartMoving() end))
    drag:SetScript("OnDragStop", ns.Guard("gold", function()
        f:StopMovingOrSizing()
        KeepPlace(f)
    end))
    U.drag = drag

    -- the template's close button, made to just hide our frame (or one of
    -- our own where the template brought none)
    local close = f.CloseButton
    if type(close) ~= "table" then
        close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", f, "TOPRIGHT", 2, 2)
    end
    close:SetScript("OnClick", ns.Guard("gold", function() f:Hide() end))
    U.close = close

    U.tabs = {}
    for i, tab in ipairs(TABS) do
        local b = Button(f, tab[2], 96, function() SetTab(tab[1]) end)
        b:SetPoint("TOPLEFT", f, "TOPLEFT", LEFT + (i - 1) * 100, -30)
        U.tabs[tab[1]] = b
    end

    -- Crafts: the recipes that make no item - what an enchant costs to cast
    local check = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    check:SetSize(24, 24)
    check:SetPoint("TOPLEFT", f, "TOPLEFT", LEFT + 412, -29)
    -- (the label is the box's own: it shows and hides with it)
    check.label = Text(check, "GameFontHighlightSmall")
    check.label:SetPoint("LEFT", check, "RIGHT", 2, 0)
    check.label:SetText("Enchants: what they cost")
    check:SetScript("OnClick", ns.Guard("gold", function(self)
        U.enchants = self:GetChecked() and true or false
        U.offset, U.selected, U.selSig = 0, nil, nil
        SetNote(nil)
        U.Refresh()
    end))
    U.enchantCheck = check

    U.header = Text(f, "GameFontHighlightSmall")
    U.header:SetPoint("TOPLEFT", f, "TOPLEFT", LEFT + 4, -60)
    U.header:SetWidth(LIST_W)

    U.heads = {}
    for i = 1, MAX_COLS do
        local head = CreateFrame("Button", nil, f)
        head.label = Text(head, "GameFontNormalSmall")
        head.label:SetPoint("LEFT", head, "LEFT", 3, 0)
        head.label:SetPoint("RIGHT", head, "RIGHT", -3, 0)
        head.arrow = head:CreateTexture(nil, "OVERLAY")
        head.arrow:SetSize(9, 9)
        head.arrow:Hide()
        head:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        head:SetScript("OnClick", ns.Guard("gold", ClickHead))
        WithTip(head, nil, "Click to sort by this column, again to reverse. Right-click: the list's own order.")
        U.heads[i] = head
    end

    U.rows = {}
    for i = 1, ROWS do U.rows[i] = BuildRow(f, i) end

    U.empty = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    U.empty:SetPoint("TOP", f, "TOP", 0, LIST_TOP - 90)
    U.empty:SetWidth(LIST_W - 120)
    U.empty:SetJustifyH("CENTER")
    if U.empty.SetWordWrap then U.empty:SetWordWrap(true) end
    U.empty:Hide()

    -- a slider of our own beside the rows; the wheel anywhere on the window
    local slider = CreateFrame("Slider", nil, f)
    slider:SetOrientation("VERTICAL")
    slider:SetSize(14, ROWS * ROW_H)
    slider:SetPoint("TOPLEFT", f, "TOPLEFT", LEFT + LIST_W + 4, LIST_TOP)
    local track = slider:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints(slider)
    track:SetColorTexture(0, 0, 0, 0.35)
    slider:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
    local thumb = slider:GetThumbTexture()
    if type(thumb) == "table" then thumb:SetSize(18, 24) end
    slider:SetMinMaxValues(0, 0)
    slider:SetValueStep(1)
    if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
    slider:SetValue(0)
    slider:SetScript("OnValueChanged", ns.Guard("gold", function(self, value)
        -- (our own setting of its range and value isn't a scroll)
        if U.syncing then return end
        -- (the value as handed over, else as the slider has it)
        local v = tonumber(value)
        if not v then
            local now = self:GetValue()
            v = tonumber(now)
        end
        if v then ScrollTo(v) end
    end))
    U.slider = slider
    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", ns.Guard("gold", function(_, delta)
        ScrollTo(U.offset - (tonumber(delta) or 0) * WHEEL)
    end))

    -- under the list: the totals (or a note) and which rows are showing
    local footY = LIST_TOP - ROWS * ROW_H - 5
    U.foot = Text(f, "GameFontHighlightSmall")
    U.foot:SetPoint("TOPLEFT", f, "TOPLEFT", LEFT + 4, footY)
    U.foot:SetWidth(LIST_W - 96)
    U.count = Text(f, "GameFontDisableSmall", "RIGHT")
    U.count:SetPoint("TOPRIGHT", f, "TOPLEFT", LEFT + LIST_W, footY)
    U.count:SetWidth(90)
    -- what a job is doing, how it ended, or what Search asks of the player:
    -- two lines' worth (the longest of them end with what to do next)
    U.status = Text(f, "GameFontNormalSmall")
    U.status:SetPoint("TOPLEFT", f, "TOPLEFT", LEFT + 4, footY - 17)
    U.status:SetWidth(LIST_W)
    if U.status.SetWordWrap then U.status:SetWordWrap(true) end
    if U.status.SetMaxLines then U.status:SetMaxLines(2) end
    if U.status.SetJustifyV then U.status:SetJustifyV("TOP") end

    -- (8 up: clear of the inset's bottom border)
    U.scan = Button(f, "Scan", 130, ClickScan)
    U.scan:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", LEFT, 8)
    WithTip(U.scan, "Scan")
    U.check = Button(f, "Price my items", 130, ClickCheck)
    U.check:SetPoint("LEFT", U.scan, "RIGHT", 6, 0)
    WithTip(U.check, "Price my items")
    U.search = Button(f, "Search", 110, ClickSearch)
    U.search:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -LEFT, 8)
    WithTip(U.search, "Search")

    U.frame = f
    return f
end

function U.Open()
    local f = U.frame or Build()
    SetNote(nil)
    f:Show()
    -- (on top of whatever else is at this strata: the Settings panel, which
    -- holds the options page's Open button, would cover it whole)
    if f.Raise then f:Raise() end
    U.Refresh()
end

function U.Close()
    if U.frame then U.frame:Hide() end
end

-- /pqol gold, the options page's Open button, the auction house button
function U.Toggle()
    if U.frame and U.frame:IsShown() then U.Close() else U.Open() end
end

--------------------------------------------------------------------------
-- the auction house button
--------------------------------------------------------------------------

-- made once, when Blizzard's auction house has loaded and the feature is
-- on; after that only shown and hidden
local function AHButton()
    if U.ahButton then
        U.ahButton:SetShown(U.on)
        return
    end
    local ah = AuctionHouseFrame
    if not U.on or type(ah) ~= "table" then return end
    local b = CreateFrame("Button", nil, ah, "UIPanelButtonTemplate")
    U.ahButton = b
    b:SetSize(96, 22)
    -- (above the frame's top edge and left of its close button, which
    -- reaches 3 px over that edge: none of Blizzard's controls are there)
    b:SetPoint("BOTTOMRIGHT", ah, "TOPRIGHT", -30, 1)
    b:SetText("Gold finder")
    b:SetScript("OnClick", ns.Guard("gold", function() Gold.Toggle() end))
    WithTip(b, nil, "Gold finder (Pace's QoL)")
end

ns.OnAddOnLoaded("Blizzard_AuctionHouseUI", ns.Guard("gold", AHButton))

--------------------------------------------------------------------------
-- what Gold.lua tells us
--------------------------------------------------------------------------

Gold.Listen(function(what, arg)
    if what == "apply" then
        U.on = arg and true or false
        if not U.on then U.Close() end
        AHButton()
    elseif not (U.frame and U.frame:IsShown()) then
        return
    elseif what == "ah" then
        -- (the buttons at once; the texts that depend on it a moment later)
        Footer()
        U.Soon()
    elseif what == "bags" then
        -- (Your bags, and Crafts' "Can make")
        if U.tab == "bags" or U.tab == "crafts" then U.Soon() end
    elseif what == "change" then
        U.Soon()
    end
end)
