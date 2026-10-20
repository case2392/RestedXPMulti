-- Offline harness for RestedXP Professions (Lua 5.1).
--   lua5.1 tests/harness_rxpprofessions.lua .
-- Three clients: Classic Era (GetSkillLineInfo), Forever (C_SkillInfo +
-- C_TradeSkillUI, no TRADE_SKILL_UPDATE / CRAFT_* events) and a
-- retail-style one (GetProfessions). A report had the addon never start
-- on Forever: "Attempt to register unknown event TRADE_SKILL_UPDATE".
local root = arg and arg[1] or "."
local realPrint = print
local passed, failed = 0, 0
local function check(cond, label)
    if cond then passed = passed + 1 else failed = failed + 1; realPrint("FAIL: " .. label) end
end

local printed
local function Printed(pat)
    for _, l in ipairs(printed) do if l:find(pat, 1, true) then return true end end
    return false
end

-- a widget that accepts any method; the ones with state are real
local function Widget()
    local w = {shown = false, children = {}, events = {}, texts = {}, scripts = {}}
    -- methods are CamelCase and all accepted; data fields read nil as usual
    setmetatable(w, {__index = function(_, k)
        if type(k) == "string" and k:match("^%u") then return function() end end
    end})
    function w:Show() self.shown = true end
    function w:Hide() self.shown = false end
    function w:IsShown() return self.shown end
    function w:SetScript(k, fn) self.scripts = self.scripts or {}; self.scripts[k] = fn end
    function w:GetScript(k) return self.scripts and self.scripts[k] end
    function w:SetText(t) self.text = t end
    function w:GetText() return self.text end
    function w:GetStringHeight() return 12 end
    function w:SetChecked(v) self.checked = v and true or false end
    function w:GetChecked() return self.checked end
    function w:GetPoint() return "CENTER", nil, "CENTER", 0, 0 end
    function w:CreateFontString() local fs = Widget(); table.insert(self.texts, fs); return fs end
    function w:CreateTexture() return Widget() end
    return w
end

local function NewWorld(opts)
    printed = {}
    for _, k in ipairs({"GetNumSkillLines", "GetSkillLineInfo", "C_SkillInfo", "GetProfessions", "GetProfessionInfo",
                        "GetTradeSkillLine", "GetNumTradeSkills", "GetTradeSkillInfo", "C_TradeSkillUI",
                        "GetCraftDisplaySkillLine", "GetNumCrafts", "GetCraftInfo", "LibStub", "RXPProfessionsDB", "GetBuildInfo",
                        "GetLocale", "GetSpellInfo", "GetItemInfo", "C_Map", "C_Item", "C_Spell"}) do
        _G[k] = nil
    end
    _G.print = function(...) local t = {} for i = 1, select("#", ...) do t[i] = tostring(select(i, ...)) end table.insert(printed, table.concat(t, " ")) end
    local w = {frames = {}, timers = {}}
    local known = {}
    for _, e in ipairs(opts.events) do known[e] = true end
    _G.CreateFrame = function(kind, name, parent, template)
        local f = Widget()
        f.kind, f.template, f.name = kind, template, name
        function f:RegisterEvent(e)
            -- the client throws on an event it does not have
            if not known[e] then error('Frame:RegisterEvent(): Attempt to register unknown event "' .. e .. '"') end
            self.events[e] = true
        end
        if parent and parent.children then table.insert(parent.children, f) end
        table.insert(w.frames, f)
        return f
    end
    _G.UIParent = Widget()
    _G.SlashCmdList = {}
    _G.C_Timer = {NewTicker = function(s, fn) table.insert(w.timers, {s, fn}) end, After = function(s, fn) table.insert(w.timers, {s, fn}) end}
    _G.UnitLevel = function() return opts.level or 20 end
    _G.UnitFactionGroup = function() return opts.faction or "Alliance" end
    _G.UnitRace = function() return opts.race or "Human", opts.race or "Human" end
    _G.GetRealZoneText = function() return opts.zone or "Elwynn Forest" end
    -- another language: the client names skills, spells, items and zones
    -- in it (opts.names: English skill name -> the client's; opts.spells /
    -- opts.items: id -> name; opts.map: the player's uiMapID, opts.mapNames)
    _G.GetLocale = function() return opts.locale or "enUS" end
    w.itemRequests = {}
    if opts.spells then _G.GetSpellInfo = function(id) return opts.spells[id] end end
    if opts.items then
        _G.GetItemInfo = function(id) return opts.items[id] end
        _G.C_Item = {RequestLoadItemDataByID = function(id) w.itemRequests[id] = true end}
    end
    if opts.map then
        _G.C_Map = {GetBestMapForUnit = function() return opts.map end,
                    GetMapInfo = function(id) return {name = (opts.mapNames or {})[id] or "?", parentMapID = (opts.mapParents or {})[id]} end}
    end
    _G.RXPProfessionsDB = opts.db

    -- the skills tab's list: headers with children that vanish from the
    -- list while the header is folded (opts.folded folds "Professions")
    local secret = setmetatable({}, {__eq = function() error("attempt to compare a secret number value") end})
    local tree = {
        {name = "Class Skills", header = true, folded = false, children = {{name = "Defense", rank = 100, maxRank = 100}}},
        {name = "Professions", header = true, folded = opts.folded or false, children = {{name = "Mining", rank = 45, maxRank = 75}}},
        {name = "Secondary Skills", header = true, folded = false, children = {{name = "Cooking", rank = opts.secretRank and secret or 20, maxRank = 75}}}
    }
    if opts.leatherworking then table.insert(tree[2].children, {name = "Leatherworking", rank = opts.leatherworking, maxRank = 75}) end
    for _, extra in ipairs(opts.extra or {}) do table.insert(tree[2].children, extra) end
    -- opts.skillIDs: English name -> the skill line's ID, which C_SkillInfo hands back
    for _, h in ipairs(tree) do
        for _, c in ipairs(h.children) do c.id = (opts.skillIDs or {})[c.name] end
    end
    if opts.names then
        for _, h in ipairs(tree) do
            for _, c in ipairs(h.children) do c.name = opts.names[c.name] or c.name end
        end
    end
    -- the game build: a new one starts recipe colours afresh
    w.build = opts.build or "61582"
    -- Forever reports toc 16001; the routes pick its recipe names and mats from that
    local toc = opts.client == "forever" and 16001 or opts.client == "tbc" and 20505 or opts.client == "mists" and 50504 or 11508
    _G.GetBuildInfo = function() return "1.15.8", w.build, "Oct 1 2026", toc end
    local function visible()
        local out = {}
        for _, h in ipairs(tree) do
            out[#out + 1] = h
            if not h.folded then for _, c in ipairs(h.children) do out[#out + 1] = c end end
        end
        return out
    end
    w.visible = visible
    w.tree = tree
    w.expands, w.collapses = 0, 0
    -- Forever raises SKILL_LINES_CHANGED on the spot when a header opens
    -- or closes (opts.syncEvents), inside the call
    local function changed()
        if opts.syncEvents and w.eventFrame then
            w.depth = (w.depth or 0) + 1
            w.maxDepth = math.max(w.maxDepth or 0, w.depth)
            assert(w.depth < 20, "SKILL_LINES_CHANGED recursion")
            w.Fire("SKILL_LINES_CHANGED")
            w.depth = w.depth - 1
        end
    end
    local function expand(i) local l = visible()[i]; assert(l and l.header, "expand on a non-header"); l.folded = false; w.expands = w.expands + 1; changed() end
    local function collapse(i) local l = visible()[i]; assert(l and l.header, "collapse on a non-header"); l.folded = true; w.collapses = w.collapses + 1; changed() end
    -- the classic profession window (w.trade = {prof, {{name, difficulty}, ...}},
    -- its skill in w.tradeRank), the craft window Enchanting uses on older
    -- clients (w.craft = {prof, rank, {{name, difficulty}, ...}}) and the
    -- trainer window (w.trainer = {{name, category, skill, level}, ...})
    w.trade, w.trainer = nil, {}
    _G.GetNumTrainerServices = function() return #w.trainer end
    -- Classic: name, subText, serviceType, isExpanded
    -- Forever: name, serviceType, texture, reqLevel, subText, category
    _G.GetTrainerServiceInfo = function(i)
        local t = w.trainer[i]
        if opts.client == "forever" then return t[1], t[2], 136243, 0, "", "Recipes" end
        return t[1], "", t[2], false
    end
    _G.GetTrainerServiceSkillReq = function(i) local t = w.trainer[i]; return t[3], t[4] end
    if opts.client == "classic" or opts.client == "tbc" or opts.client == "mists" then
        _G.GetTradeSkillLine = function() return w.trade and w.trade[1] or "UNKNOWN", w.tradeRank, 75 end
        _G.GetCraftDisplaySkillLine = function() if w.craft then return w.craft[1], w.craft[2], 75 end end
        _G.GetNumCrafts = function() return w.craft and #w.craft[3] or 0 end
        _G.GetCraftInfo = function(i) local r = w.craft[3][i]; return r[1], "", r[2], 0, true, 0, 0 end
        _G.GetNumTradeSkills = function() return w.trade and #w.trade[2] or 0 end
        _G.GetTradeSkillInfo = function(i) local r = w.trade[2][i]; return r[1], r[2] end
        _G.IsTradeSkillLinked = function() return w.linked or false end
        _G.GetNumSkillLines = function() return #visible() end
        _G.GetSkillLineInfo = function(i) local l = visible()[i]; return l.name, l.header or false, l.header and not l.folded or nil, l.rank, nil, nil, l.maxRank end
        _G.ExpandSkillHeader, _G.CollapseSkillHeader = expand, collapse
    elseif opts.client == "forever" then
        -- C_SkillInfo hands tables back; rank may be a secret value
        _G.C_SkillInfo = {
            GetNumSkillLines = function() return #visible() end,
            GetSkillLineInfo = function(i)
                local l = visible()[i]
                return {name = l.name, isHeader = l.header or false, isCollapsed = l.header and l.folded or false, rank = l.rank, maxRank = l.maxRank, parentSkillLineID = 0, skillID = l.id}
            end,
            ExpandSkillHeader = expand, CollapseSkillHeader = collapse
        }
        if opts.professions then
            _G.GetProfessions = function() return 7, nil, nil, nil, 12, nil end
            _G.GetProfessionInfo = function(id)
                if id == 7 then return "Mining", 1, opts.staleMining or 45, 75 end
                if id == 12 then return "Cooking", 1, 20, 75 end
            end
        end
        w.recipes = {}
        -- GetChildProfessionInfo always returns a table: professionID 0
        -- when there is no child (w.noChild), and Blizzard then reads the
        -- base; the name players see is parentProfessionName, else
        -- professionName. GetAllRecipeIDs lists every recipe, learned or
        -- not, whatever the filters (w.noAllIDs: a client without it);
        -- GetFilteredRecipeIDs is learned-only on Forever, less what the
        -- window's filters hide (w.hidden[id]) - the recipe stays learned.
        w.hidden = {}
        local function ids(all)
            local out = {}
            for id, r in pairs(w.recipes) do
                if all or (r.learned and not w.hidden[id]) then out[#out + 1] = id end
            end
            table.sort(out)
            return out
        end
        _G.C_TradeSkillUI = {
            GetChildProfessionInfo = function()
                if w.noChild then return {professionID = 0, professionName = "", skillLevel = 0, maxSkillLevel = 0} end
                return {professionID = 2540, professionName = w.childName or w.openProf or "Cooking", parentProfessionName = w.openProf or "Cooking",
                        parentProfessionID = w.openID, skillLevel = w.openRank or 20, maxSkillLevel = 75}
            end,
            GetBaseProfessionInfo = function()
                -- the base line's ID is the profession's skill line (Tailoring 197)
                local ids = {Cooking = 185, Tailoring = 197, Enchanting = 333, Alchemy = 171, Jewelcrafting = 755}
                return {professionID = w.openID or ids[w.openProf or "Cooking"] or 0, professionName = w.openProf or "Cooking",
                        skillLevel = w.openRank or 20, maxSkillLevel = 75}
            end,
            GetFilteredRecipeIDs = function() return ids(false) end,
            GetAllRecipeIDs = function() if not w.noAllIDs then return ids(true) end end,
            GetRecipeInfo = function(id) return w.recipes[id] end,
            IsTradeSkillReady = function() return not w.notReady end,
            IsDataSourceChanging = function() return w.changing or false end,
            IsTradeSkillLinked = function() return w.linked or false end,
            IsTradeSkillGuild = function() return false end,
            IsNPCCrafting = function() return false end,
            -- the skill line's name in the client's language (opts.displayNames: id -> name)
            GetTradeSkillDisplayName = function(id) return (opts.displayNames or {})[id] end
        }
    elseif opts.client == "retail" then
        _G.GetProfessions = function() return 7, 9, nil, nil, 12, nil end
        _G.GetProfessionInfo = function(id)
            if id == 7 then return "Mining", 1, 45, 75 end
            if id == 9 then return "Enchanting", 1, 10, 75 end
            if id == 12 then return "Cooking", 1, 20, 75 end
        end
    end

    local ns = {}
    for _, f in ipairs({"Locales.lua", "Data.lua", "Core.lua", "UI.lua", "Inventory.lua"}) do
        local chunk = assert(loadfile(root .. "/RXPProfessions/" .. f))
        chunk("RXPProfessions", ns)
    end
    w.ns = ns
    -- the event frame is the first frame Core.lua makes
    w.eventFrame = w.frames[1]
    function w.Fire(event, ...) w.eventFrame.scripts.OnEvent(w.eventFrame, event, ...) end
    w.slash = function(s) SlashCmdList["RXPPROFESSIONS"](s) end
    return w
end

local CLASSIC_EVENTS = {"PLAYER_ENTERING_WORLD", "SKILL_LINES_CHANGED", "CHAT_MSG_SKILL", "ZONE_CHANGED_NEW_AREA",
                        "TRADE_SKILL_SHOW", "TRADE_SKILL_UPDATE", "CRAFT_SHOW", "CRAFT_UPDATE", "TRAINER_SHOW", "TRAINER_UPDATE",
                        "GET_ITEM_INFO_RECEIVED", "SPELL_DATA_LOAD_RESULT"}
-- Forever: retail's trade skill events, no TRADE_SKILL_UPDATE, no CRAFT_*
local FOREVER_EVENTS = {"PLAYER_ENTERING_WORLD", "SKILL_LINES_CHANGED", "CHAT_MSG_SKILL", "ZONE_CHANGED_NEW_AREA",
                        "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_DATA_SOURCE_CHANGED", "TRADE_SKILL_CLOSE",
                        "TRAINER_SHOW", "TRAINER_UPDATE", "GET_ITEM_INFO_RECEIVED", "SPELL_DATA_LOAD_RESULT"}

--------------------------------------------------------------------------
-- Classic Era: as before
--------------------------------------------------------------------------
do
    local ok, w = pcall(NewWorld, {client = "classic", events = CLASSIC_EVENTS, db = {setupDone = true, chosen = {Mining = true, Cooking = true}, show = true}})
    check(ok, "classic: loads")
    check(#w.ns.missingEvents == 2 and w.ns.missingEvents[1] == "TRADE_SKILL_LIST_UPDATE" and w.ns.missingEvents[2] == "TRADE_SKILL_DATA_SOURCE_CHANGED",
          "classic: only retail's list events are missing here, and they are skipped")
    w.Fire("PLAYER_ENTERING_WORLD")
    check(w.ns.profs.Mining and w.ns.profs.Mining.rank == 45 and w.ns.profs.Mining.maxRank == 75 and w.ns.skillAPI == "skill lines", "classic: skills read from GetSkillLineInfo")
    local lines = w.ns.BuildProfLines("Mining", w.ns.profs.Mining)
    local mine, nextUp = false, false
    for _, l in ipairs(lines) do
        if l.text == "Mine: Copper Vein" then mine = true end
        if l.text == "At 65: Tin Vein" then nextUp = true end
    end
    check(lines[1].text == "Mining  45/75" and mine and nextUp, "classic: advice built")
    w.slash("status")
    check(Printed("skills read through skill lines: Cooking 20/75, Mining 45/75"), "classic: /rxpp status lists the skills")
    -- the report: "Professions" folded shut in the skills tab hid Mining from the list, and a
    -- trained miner read as never trained. The header is opened for the scan and folded back.
    local w2 = NewWorld({client = "classic", events = CLASSIC_EVENTS, folded = true, db = {setupDone = true, chosen = {Mining = true}, show = true}})
    check(#w2.visible() == 5 and w2.visible()[4].name == "Secondary Skills", "classic: with Professions folded, Mining is not in the list at all")
    w2.Fire("PLAYER_ENTERING_WORLD")
    check(w2.ns.profs.Mining and w2.ns.profs.Mining.rank == 45, "classic: a folded header is opened for the scan, so the trained profession is found")
    check(w2.tree[2].folded == true and w2.expands == 1 and w2.collapses == 1 and w2.tree[1].folded == false, "classic: and folded back after, the open ones left open")
    local lines2 = w2.ns.BuildProfLines("Mining", w2.ns.GetTracked().Mining)
    check(lines2[1].text == "Mining  45/75" and not lines2[2].text:find("Not learned", 1, true), "classic: no 'Not learned yet' for a trained profession")
end

--------------------------------------------------------------------------
-- Forever: the report
--------------------------------------------------------------------------
do
    local ok, w = pcall(NewWorld, {client = "forever", events = FOREVER_EVENTS, db = {setupDone = true, chosen = {Mining = true, Cooking = true}, show = true}})
    check(ok, "forever: loads without 'Attempt to register unknown event'")
    check(#w.ns.missingEvents == 3 and w.ns.missingEvents[1] == "TRADE_SKILL_UPDATE" and w.ns.missingEvents[2] == "CRAFT_SHOW", "forever: the events this client lacks are skipped and remembered")
    check(w.eventFrame.events.TRADE_SKILL_LIST_UPDATE and w.eventFrame.events.SKILL_LINES_CHANGED, "forever: its own trade skill event is registered")
    w.Fire("PLAYER_ENTERING_WORLD")
    check(w.ns.profs.Mining and w.ns.profs.Mining.rank == 45 and w.ns.profs.Cooking.rank == 20 and w.ns.skillAPI == "C_SkillInfo", "forever: skills read from C_SkillInfo tables")
    check(SlashCmdList["RXPPROFESSIONS"] ~= nil, "forever: /rxpp exists")
    w.slash("status")
    check(Printed("skills read through C_SkillInfo") and Printed("events this client lacks (skipped): TRADE_SKILL_UPDATE, CRAFT_SHOW, CRAFT_UPDATE"), "forever: /rxpp status says what the client gives and lacks")
    -- known recipes through C_TradeSkillUI, on the window's list event
    w.recipes = {[2538] = {name = "Charred Wolf Meat", learned = true}, [2540] = {name = "Roasted Boar Meat", learned = true}, [2795] = {name = "Beer Basted Boar Ribs", learned = false}}
    w.Fire("TRADE_SKILL_LIST_UPDATE")
    local known = w.ns.GetKnownRecipes("Cooking")
    check(known and known["Charred Wolf Meat"] and known["Roasted Boar Meat"] and not known["Beer Basted Boar Ribs"], "forever: learned recipes remembered from C_TradeSkillUI, unlearned ones not")
    -- an empty list (the window still loading) does not wipe them
    w.recipes = {}
    w.Fire("TRADE_SKILL_LIST_UPDATE")
    check(w.ns.GetKnownRecipes("Cooking")["Charred Wolf Meat"], "forever: an empty recipe list leaves the remembered ones alone")
    -- a profession we do not track is ignored
    w.openProf = "Jewelcrafting"
    w.recipes = {[1] = {name = "Thing", learned = true}}
    w.Fire("TRADE_SKILL_LIST_UPDATE")
    check(w.ns.GetKnownRecipes("Jewelcrafting") == nil, "forever: an untracked profession's window is ignored")
    -- the window draws
    check(w.ns.UpdateUI ~= nil, "forever: UI present")
    local anyLine = false
    for _, f in ipairs(w.frames) do for _, t in ipairs(f.texts) do if t.text and t.text:find("Mining  45/75", 1, true) then anyLine = true end end end
    check(anyLine, "forever: the window shows the skill line")
    -- the same fold on Forever's skills tab, through C_SkillInfo's expand/collapse
    local wf = NewWorld({client = "forever", events = FOREVER_EVENTS, folded = true, db = {setupDone = true, chosen = {Mining = true}, show = true}})
    wf.Fire("PLAYER_ENTERING_WORLD")
    check(wf.ns.profs.Mining and wf.ns.profs.Mining.rank == 45 and wf.tree[2].folded == true and wf.expands == 1 and wf.collapses == 1, "forever: a folded Professions header is opened for the scan and folded back")
    -- with GetProfessions there too, both are read and merged
    local wp = NewWorld({client = "forever", events = FOREVER_EVENTS, folded = true, professions = true, db = {setupDone = true, chosen = {Mining = true, Cooking = true}, show = true}})
    wp.Fire("PLAYER_ENTERING_WORLD")
    check(wp.ns.profs.Mining.rank == 45 and wp.ns.profs.Cooking.rank == 20 and wp.ns.skillAPI == "C_SkillInfo + GetProfessions", "forever: GetProfessions and C_SkillInfo both read, results merged")
    -- the report: Skinning stuck at 61 after levelling to 105. One source lagging behind
    -- (here the profession list says Mining 30 while the skills tab says 45) must not hold it down
    local ws = NewWorld({client = "forever", events = FOREVER_EVENTS, professions = true, staleMining = 30, db = {setupDone = true, chosen = {Mining = true}, show = true}})
    ws.Fire("PLAYER_ENTERING_WORLD")
    check(ws.ns.profs.Mining.rank == 45, "forever: a source that lags behind does not hold the skill down (45, not 30)")
    ws.slash("status")
    check(Printed("Mining 45/75 (C_SkillInfo 45/75; GetProfessions 30/75)"), "forever: /rxpp status shows what each source said when they disagree")
    -- and the skill moves on: a skill-up is picked up from the skills tab
    ws.tree[2].children[1].rank = 46
    ws.Fire("CHAT_MSG_SKILL")
    check(ws.ns.profs.Mining.rank == 46, "forever: a skill-up updates the window")
    local later = 0
    for _, t in ipairs(ws.timers) do if t[1] == 1 then later = later + 1 end end
    check(later >= 1, "forever: and it looks again a moment after the skill-up message")
    -- Forever runs SKILL_LINES_CHANGED inside the header calls: the scan's own
    -- open/fold must not set off scan after scan
    local wr = NewWorld({client = "forever", events = FOREVER_EVENTS, folded = true, syncEvents = true, db = {setupDone = true, chosen = {Mining = true}, show = true}})
    local okR, errR = pcall(wr.Fire, "PLAYER_ENTERING_WORLD")
    check(okR and wr.ns.profs.Mining and wr.ns.profs.Mining.rank == 45 and wr.expands == 1 and wr.collapses == 1 and wr.tree[2].folded == true,
          "forever: the scan's own header events do not start another scan (" .. tostring(errR) .. ")")
end

--------------------------------------------------------------------------
-- The TBC leatherworking report: "wanted me to craft skill 55 gloves
-- while at 30, once I got to 55 it shifted to the next tier - as if it
-- was 1 ahead at all times"
--------------------------------------------------------------------------
do
    local function craftLines(w)
        local out = {}
        for _, l in ipairs(w.ns.BuildProfLines("Leatherworking", w.ns.GetTracked().Leatherworking)) do out[#out + 1] = l.text end
        return table.concat(out, "\n")
    end
    -- the data itself: at 30 the boots, the gloves from 55, the belt from 85
    local w = NewWorld({client = "classic", events = CLASSIC_EVENTS, leatherworking = 30, level = 12, db = {setupDone = true, chosen = {Leatherworking = true}, show = true}})
    w.Fire("PLAYER_ENTERING_WORLD")
    local text = craftLines(w)
    check(text:find("Craft: Handstitched Leather Boots", 1, true) and text:find("At 55: Embossed Leather Gloves", 1, true), "leatherworking: at 30 the boots, gloves promised at 55")
    w.tree[2].children[2].rank = 55; w.Fire("SKILL_LINES_CHANGED")
    text = craftLines(w)
    check(text:find("Craft: Embossed Leather Gloves", 1, true) and text:find("At 85: Fine Leather Belt", 1, true), "leatherworking: at 55 the gloves, the belt promised at 85")
    -- a wrong row corrected live: put the old mistake back (gloves at 30) and let the trainer speak
    w.ns.CRAFT.Leatherworking.route[3][1] = 30
    w.tree[2].children[2].rank = 30; w.Fire("SKILL_LINES_CHANGED")
    check(craftLines(w):find("Craft: Embossed Leather Gloves", 1, true), "leatherworking: the old row shows the gloves at 30 again")
    w.trainer = {{"Leatherworking", "header", nil, nil}, {"Embossed Leather Gloves", "unavailable", "Leatherworking", 55}, {"Fine Leather Belt", "unavailable", "Leatherworking", 85}, {"Handstitched Leather Boots", "used", "Leatherworking", 20}, {"Cooking Fire", "available", "Cooking", 1}}
    w.Fire("TRAINER_SHOW")
    check(w.ns.RecipeRequirement("Leatherworking", "Embossed Leather Gloves") == 55 and w.ns.RecipeRequirement("Leatherworking", "Fine Leather Belt") == 85, "leatherworking: the trainer's requirements remembered")
    text = craftLines(w)
    check(text:find("Craft: Handstitched Leather Boots", 1, true) and text:find("(Embossed Leather Gloves needs 55 - your trainer said so)", 1, true), "leatherworking: the row the trainer contradicts is stepped back, and says why")
    w.ns.CRAFT.Leatherworking.route[3][1] = 55
    -- the profession window: the route's recipe unknown, but a known one still orange
    w.trade = {"Leatherworking", {{"Light Armor Kit", "easy"}, {"Handstitched Leather Boots", "optimal"}, {"Handstitched Leather Bracers", "medium"}}}
    w.tree[2].children[2].rank = 56; w.Fire("SKILL_LINES_CHANGED")
    w.Fire("TRADE_SKILL_SHOW")
    text = craftLines(w)
    check(w.ns.GetKnownRecipes("Leatherworking")["Handstitched Leather Boots"] == "optimal", "leatherworking: known recipes carry their skill-up colour")
    check(text:find("Craft: Embossed Leather Gloves", 1, true) and text:find("Learn it at 55 from your trainer", 1, true) == nil and text:find("You don't know this recipe yet!", 1, true) and text:find("Meanwhile: Handstitched Leather Boots (orange)", 1, true), "leatherworking: at 56 the gloves are due, unknown, and the orange boots offered meanwhile")
    w.tree[2].children[2].rank = 40; w.Fire("SKILL_LINES_CHANGED")
    w.ns.CRAFT.Leatherworking.route[3][1] = 30   -- the old row again, trainer known: 55 > 40
    text = craftLines(w)
    check(text:find("Craft: Handstitched Leather Boots", 1, true) and not text:find("You don't know", 1, true), "leatherworking: with the trainer's word the known boots are the craft line at 40, no shopping trip")
    w.ns.CRAFT.Leatherworking.route[3][1] = 55
    w.ns.db.recipeReq = nil
    w.tree[2].children[2].rank = 56; w.Fire("SKILL_LINES_CHANGED")
    w.trainer = {{"Embossed Leather Gloves", "available", "Leatherworking", 55}}
    w.Fire("TRAINER_SHOW")
    w.tree[2].children[2].rank = 50; w.Fire("SKILL_LINES_CHANGED")
    w.ns.CRAFT.Leatherworking.route[3][1] = 45
    text = craftLines(w)
    check(text:find("Craft: Handstitched Leather Boots", 1, true), "leatherworking: trainer says 55, rank 50, row says 45: stepped back")
    w.ns.CRAFT.Leatherworking.route[3][1] = 55
end

--------------------------------------------------------------------------
-- The report: "recommending items for skill-up that no longer provide
-- skill-up. I'm 63 in tailoring; it instructs me to make Linen Bags until
-- I reach 70 [then] Reinforced Linen Cape. Similarly enchanting at 63 ...
-- Enchant Bracer - Minor (Inferior) Stamina, also some of the enchant
-- titles no longer match ... last week's patch". The game's own colours
-- now outrank the route.
--------------------------------------------------------------------------
do
    local function lines(w, prof)
        local out = {}
        for _, l in ipairs(w.ns.BuildProfLines(prof, w.ns.GetTracked()[prof])) do out[#out + 1] = l.text end
        return table.concat(out, "\n")
    end
    local tailor = {name = "Tailoring", rank = 63, maxRank = 75}
    local enchant = {name = "Enchanting", rank = 63, maxRank = 75}
    local w = NewWorld({client = "classic", events = CLASSIC_EVENTS, level = 14, extra = {tailor, enchant},
                        db = {setupDone = true, chosen = {Tailoring = true, Enchanting = true}, show = true}})
    w.Fire("PLAYER_ENTERING_WORLD")
    local text = lines(w, "Tailoring")
    check(text:find("Craft: Linen Bag\n", 1, true) and text:find("open your Tailoring window once so I can check these recipes against your game", 1, true),
          "report: before the window has been opened, the route's Linen Bag, and a nudge to open the window")

    -- the window after the patch: Linen Bag grey at 63, something else orange
    w.trade = {"Tailoring", {{"Tailoring", "header"}, {"Bolt of Linen Cloth", "trivial"}, {"Linen Bag", "trivial"},
                             {"Simple Linen Boots", "optimal"}, {"Brown Linen Pants", "medium"}, {"Cloth", "subheader"}}}
    w.tradeRank = 63
    w.Fire("TRADE_SKILL_SHOW")
    text = lines(w, "Tailoring")
    check(text:find("Craft: Simple Linen Boots (orange)", 1, true) and text:find("(Linen Bag is grey for you now - the game moved it, so this beats the route)", 1, true),
          "report: Linen Bag grey at 63 - the orange recipe the game shows is recommended instead, and the reason given")
    check(w.ns.GetKnownRecipes("Tailoring")["Tailoring"] == nil and w.ns.GetKnownRecipes("Tailoring")["Cloth"] == nil, "report: header and subheader rows are not recipes")
    check(not text:find("Mats: 3 Bolt of Linen", 1, true), "report: the route's mats for the bag are not shown for the boots")

    -- skill rises without the window: the boots' orange is from 63, the bag's grey holds
    tailor.rank = 66; w.Fire("SKILL_LINES_CHANGED")
    text = lines(w, "Tailoring")
    check(text:find("Craft: Simple Linen Boots (orange at 63)", 1, true) and text:find("(Linen Bag is grey for you now", 1, true),
          "report: at 66 the boots read 'orange at 63' (not re-seen), the bag stays grey (grey only gets more grey)")
    check(w.ns.RecipeColor("Tailoring", "Linen Bag", 66) == "trivial" and select(2, w.ns.RecipeColor("Tailoring", "Linen Bag", 66)) == true, "colours: grey at 63 is grey for sure at 66")
    check(w.ns.RecipeColor("Tailoring", "Simple Linen Boots", 50) == "optimal" and select(2, w.ns.RecipeColor("Tailoring", "Simple Linen Boots", 50)) == true, "colours: orange at 63 is orange for sure at 50")
    check(select(2, w.ns.RecipeColor("Tailoring", "Brown Linen Pants", 70)) == false, "colours: yellow at 63 is only a guess at 70")

    -- green route recipe, a yellow one known: the yellow one
    tailor.rank = 63; w.Fire("SKILL_LINES_CHANGED")
    w.trade = {"Tailoring", {{"Linen Bag", "easy"}, {"Brown Linen Pants", "medium"}, {"Simple Linen Boots", "trivial"}}}
    w.tradeRank = 64; tailor.rank = 64
    w.Fire("TRADE_SKILL_UPDATE")
    text = lines(w, "Tailoring")
    check(text:find("Craft: Brown Linen Pants (yellow)", 1, true) and text:find("(Linen Bag is green for you now", 1, true),
          "report: green route recipe and a yellow one known - the yellow one")
    -- green and nothing better: keep it, say it is hit and miss
    w.trade = {"Tailoring", {{"Linen Bag", "easy"}, {"Brown Linen Pants", "trivial"}}}
    w.tradeRank = 65; tailor.rank = 65
    w.Fire("TRADE_SKILL_UPDATE")
    text = lines(w, "Tailoring")
    check(text:find("Craft: Linen Bag (green)", 1, true) and text:find("Green: it only skills up some of the time", 1, true), "report: green and nothing better - kept, flagged")
    -- grey and nothing better: say there are no skill-ups left in it
    w.trade = {"Tailoring", {{"Linen Bag", "trivial"}, {"Brown Linen Pants", "trivial"}}}
    w.tradeRank = 66; tailor.rank = 66
    w.Fire("TRADE_SKILL_UPDATE")
    text = lines(w, "Tailoring")
    check(text:find("Craft: Linen Bag (grey)", 1, true) and text:find("It gives no skill-ups any more, and you know nothing better - check your trainer for new recipes", 1, true),
          "report: grey and nothing better - says so and points at the trainer")
    -- still orange where the route says: unchanged advice, with the colour
    w.trade = {"Tailoring", {{"Linen Bag", "optimal"}}}
    w.tradeRank = 66
    w.Fire("TRADE_SKILL_UPDATE")
    text = lines(w, "Tailoring")
    check(text:find("Craft: Linen Bag (orange)", 1, true) and text:find("Mats: 3 Bolt of Linen Cloth + 3 Coarse Thread", 1, true) and not text:find("game moved it", 1, true),
          "report: where the game agrees with the route, the route stands, with its colour and mats")
    check(w.ns.RecipeColor("Tailoring", "Linen Bag", 66) == "optimal" and w.ns.db.recipeColors.Tailoring["Linen Bag"].seen.trivial == nil,
          "colours: a sighting that contradicts older ones (a patch) replaces them")

    -- Enchanting through the craft window, with the names a later client uses
    w.craft = {"Enchanting", 63, {{"Enchanting", "header"}, {"Runed Copper Rod", "trivial"}, {"Enchant Bracers - Minor Health", "trivial"},
                                   {"Enchant Bracers - Minor Stamina", "trivial"}, {"Enchant Cloak - Minor Resistance", "optimal"}}}
    w.Fire("CRAFT_SHOW")
    text = lines(w, "Enchanting")
    check(w.ns.ResolveRecipe(w.ns.GetKnownRecipes("Enchanting"), "Enchant Bracer - Minor Stamina") == "Enchant Bracers - Minor Stamina",
          "names: the route's 'Enchant Bracer - Minor Stamina' finds the game's 'Enchant Bracers - Minor Stamina'")
    check(text:find("Craft: Enchant Cloak - Minor Resistance (orange)", 1, true) and text:find("(Enchant Bracers - Minor Health is grey for you now", 1, true),
          "report: enchanting at 63 - the grey bracer enchant replaced by the orange one the game shows")
    check(w.ns.GetKnownRecipes("Enchanting")["Enchant Cloak - Minor Resistance"] == "optimal", "craft window: colours recorded (they were not before)")
    -- trainer requirements match loosely too
    w.trainer = {{"Enchant Bracers - Lesser Stamina", "unavailable", "Enchanting", 130}}
    w.Fire("TRAINER_SHOW")
    check(w.ns.RecipeRequirement("Enchanting", "Enchant Bracer - Lesser Stamina") == 130, "names: the trainer's renamed recipe is found for the route's name")

    -- a new game build starts the colours afresh
    w.build = "62000"
    w.trade = {"Tailoring", {{"Linen Bag", "medium"}}}
    w.tradeRank = 66
    w.Fire("TRADE_SKILL_UPDATE")
    check(w.ns.db.recipeColors.Enchanting == nil and w.ns.db.recipeColors.Tailoring["Linen Bag"].last == "medium" and w.ns.db.recipeColorsBuild == "62000",
          "colours: a new game build clears the old sightings")

    w.slash("status")
    check(Printed("recipe colours read: Enchanting 4 recipes at skill 63, Tailoring 4 recipes at skill 66 (last through GetTradeSkillInfo)"),
          "status: when each profession's recipes were last read, and through what")
    -- saved data from before 0.6.2 (known recipes as true) still works
    w.ns.db.knownRecipes.Tailoring = {["Linen Bag"] = true}
    w.ns.db.recipeColors = nil
    local okOld = pcall(lines, w, "Tailoring")
    check(okOld, "old saved data: a recipe stored as true does not break the advice")
end

-- Forever: recipes come from GetFilteredRecipeIDs, as in Blizzard's own
-- window - learned ones only, less whatever the player's filters hide -
-- with the game's colour and whether each can still skill up
do
    local w = NewWorld({client = "forever", events = FOREVER_EVENTS, extra = {{name = "Tailoring", rank = 63, maxRank = 75}},
                        db = {setupDone = true, chosen = {Tailoring = true}, show = true}})
    w.Fire("PLAYER_ENTERING_WORLD")
    w.openProf, w.openRank = "Tailoring", 63
    w.recipes = {
        [1] = {name = "Bolt of Linen Cloth", learned = true, relativeDifficulty = 3},
        [2] = {name = "Linen Bag", learned = true, relativeDifficulty = 1, canSkillUp = false},
        [3] = {name = "Simple Kilt", learned = true, relativeDifficulty = 0, canSkillUp = true},
        [4] = {name = "Reinforced Linen Cape", learned = false}
    }
    w.Fire("TRADE_SKILL_LIST_UPDATE")
    local known = w.ns.GetKnownRecipes("Tailoring")
    check(known and known["Simple Kilt"] == "optimal" and known["Linen Bag"] == "trivial" and not known["Reinforced Linen Cape"] and w.ns.recipeAPI == "GetAllRecipeIDs",
          "forever: recipes read through GetAllRecipeIDs (all of them, unfiltered); one that can't skill up counts as grey")
    -- a client with only the filtered list, and the player ticks "skill-ups only":
    -- the list shrinks, nothing known is forgotten
    w.noAllIDs = true
    w.hidden = {[1] = true, [2] = true}
    w.Fire("TRADE_SKILL_LIST_UPDATE")
    known = w.ns.GetKnownRecipes("Tailoring")
    check(w.ns.recipeAPI == "GetFilteredRecipeIDs" and known["Linen Bag"] and known["Bolt of Linen Cloth"] and known["Simple Kilt"],
          "forever: a filtered list adds to the known recipes, never replaces them")
    -- a window still loading says skill 0: not a profession learned afresh
    w.openRank = 0
    w.Fire("TRADE_SKILL_LIST_UPDATE")
    check(w.ns.GetKnownRecipes("Tailoring")["Linen Bag"] and w.ns.db.recipeRank.Tailoring == 63, "forever: a window reading skill 0 while it loads does not start the list over")
    w.openRank = 63
    w.hidden, w.noAllIDs = {}, nil
    -- a list still being built, a linked window, someone else's: not read
    w.recipes[5] = {name = "Brown Linen Robe", learned = true, relativeDifficulty = 0}
    w.notReady = true; w.Fire("TRADE_SKILL_LIST_UPDATE"); w.notReady = false
    w.changing = true; w.Fire("TRADE_SKILL_LIST_UPDATE"); w.changing = false
    w.linked = true; w.Fire("TRADE_SKILL_LIST_UPDATE"); w.linked = false
    check(w.ns.GetKnownRecipes("Tailoring")["Brown Linen Robe"] == nil, "forever: not read while not ready, while the data source changes, or from a linked window")
    w.Fire("TRADE_SKILL_DATA_SOURCE_CHANGED")
    check(w.ns.GetKnownRecipes("Tailoring")["Brown Linen Robe"] == "optimal", "forever: read once the data source has changed")
    -- the profession's name: the parent's when the child's differs, the base's when there is no child
    w.childName = "Classic Tailoring"
    w.recipes[6] = {name = "Linen Cloak", learned = true, relativeDifficulty = 2}
    w.Fire("TRADE_SKILL_LIST_UPDATE")
    check(w.ns.GetKnownRecipes("Tailoring")["Linen Cloak"] == "easy", "forever: the child profession's parent name is used")
    w.childName, w.noChild = nil, true
    w.recipes[7] = {name = "Linen Belt", learned = true, relativeDifficulty = 1}
    w.Fire("TRADE_SKILL_LIST_UPDATE")
    check(w.ns.GetKnownRecipes("Tailoring")["Linen Belt"] == "medium", "forever: with no child profession (id 0), the base profession is read")
    w.noChild = nil
    -- the profession dropped and learned again: the old list goes
    w.openRank = 5
    w.recipes = {[1] = {name = "Bolt of Linen Cloth", learned = true, relativeDifficulty = 0}}
    w.Fire("TRADE_SKILL_LIST_UPDATE")
    known = w.ns.GetKnownRecipes("Tailoring")
    check(known["Bolt of Linen Cloth"] == "optimal" and known["Linen Bag"] == nil, "forever: a lower skill than last time starts the list over")
    -- Forever's trainer hands its values back in another order
    w.trainer = {{"Linen Belt", "used", "Tailoring", 15}, {"Woolen Cape", "unavailable", "Tailoring", 55}}
    w.Fire("TRAINER_SHOW")
    check(w.ns.RecipeRequirement("Tailoring", "Woolen Cape") == 55 and w.ns.RecipeRequirement("Tailoring", "Linen Belt") == 15, "forever: trainer requirements read in Forever's order")
    w.slash("status")
    check(Printed("(last through GetAllRecipeIDs)"), "forever: /rxpp status names the recipe API")
end

-- Classic: a linked profession (someone's [Tailoring] link) is not the player's own
do
    local w = NewWorld({client = "classic", events = CLASSIC_EVENTS, extra = {{name = "Tailoring", rank = 63, maxRank = 75}},
                        db = {setupDone = true, chosen = {Tailoring = true}, show = true}})
    w.Fire("PLAYER_ENTERING_WORLD")
    w.linked = true
    w.trade = {"Tailoring", {{"Mooncloth Robe", "optimal"}}}
    w.tradeRank = 300
    w.Fire("TRADE_SKILL_SHOW")
    check(w.ns.GetKnownRecipes("Tailoring") == nil, "classic: a linked profession window is not read")
end

-- WoW Forever has routes of its own: the report's player was shown
-- Classic Era's, where Linen Bag runs 45-69 - on Forever it greys at 65,
-- and Enchant Bracer - Minor Health is "Inferior Stamina", grey at 25
local function Lines(w, prof)
    local out = {}
    for _, l in ipairs(w.ns.BuildProfLines(prof, w.ns.GetTracked()[prof])) do out[#out + 1] = l.text end
    return table.concat(out, "\n")
end
do
    local tailor = {name = "Tailoring", rank = 63, maxRank = 75}
    local enchant = {name = "Enchanting", rank = 63, maxRank = 75}
    local alchemy = {name = "Alchemy", rank = 5, maxRank = 75}
    local f = NewWorld({client = "forever", events = FOREVER_EVENTS, level = 14, extra = {tailor, enchant, alchemy},
                        db = {setupDone = true, chosen = {Tailoring = true, Enchanting = true, Alchemy = true}, show = true}})
    f.Fire("PLAYER_ENTERING_WORLD")
    local text = Lines(f, "Tailoring")
    check(f.ns.IS_FOREVER and text:find("Craft: Bolt of Woolen Cloth\n", 1, true) and text:find("At 70: Woolen Cape", 1, true) and not text:find("Linen Bag", 1, true),
          "forever: at 63 Tailoring the Forever route (Bolt of Woolen Cloth, then Woolen Cape at 70), not Linen Bag")
    text = Lines(f, "Enchanting")
    check(text:find("Craft: Enchant Chest - Inferior Stamina\n", 1, true) and text:find("Mats: 1 Strange Dust", 1, true) and text:find("At 70: Enchant Bracer - Minor Stamina", 1, true),
          "forever: at 63 Enchanting, Chest - Inferior Stamina, then Minor Stamina at 70")
    enchant.rank = 10; f.Fire("SKILL_LINES_CHANGED")
    text = Lines(f, "Enchanting")
    check(text:find("Craft: Enchant Bracer - Inferior Stamina", 1, true) and text:find("Mats: 1 Mote of Magic", 1, true) and text:find("Mote of Magic: make them from Strange Dust", 1, true),
          "forever: Forever's names and mats, and its own notes")
    text = Lines(f, "Alchemy")
    check(text:find("Craft: Elixir of Minor Defense", 1, true) and not text:find("Healing Potion", 1, true) and text:find("healing potions are First Aid recipes", 1, true),
          "forever: Alchemy starts on an elixir - the healing potions are First Aid's there")
    -- a faction-split source shows the player's side only
    alchemy.rank = 270; alchemy.maxRank = 300; f.Fire("SKILL_LINES_CHANGED")
    text = Lines(f, "Alchemy")
    check(text:find("Get it: Recipe (about 1g 20s, limited stock): Ulthir", 1, true) and not text:find("Algernon", 1, true), "sources: a per-faction source shows the player's faction")
    -- Classic keeps Classic Era's route
    local c = NewWorld({client = "classic", events = CLASSIC_EVENTS, level = 14, extra = {{name = "Tailoring", rank = 63, maxRank = 75}},
                        db = {setupDone = true, chosen = {Tailoring = true}, show = true}})
    c.Fire("PLAYER_ENTERING_WORLD")
    check(Lines(c, "Tailoring"):find("Craft: Linen Bag", 1, true), "classic: Classic Era's route stands there (Linen Bag is orange to 69)")
end

-- TBC: its own mats where they differ (its rods use up the one before)
do
    local t = NewWorld({client = "tbc", events = CLASSIC_EVENTS, level = 30, extra = {{name = "Enchanting", rank = 110, maxRank = 150}},
                        db = {setupDone = true, chosen = {Enchanting = true}, show = true}})
    t.Fire("PLAYER_ENTERING_WORLD")
    check(t.ns.IS_TBC and Lines(t, "Enchanting"):find("Mats: 1 Silver Rod + 6 Strange Dust + 3 Greater Magic Essence + 1 Runed Copper Rod", 1, true), "tbc: TBC's mats for the Runed Silver Rod")
    local e = NewWorld({client = "classic", events = CLASSIC_EVENTS, level = 30, extra = {{name = "Enchanting", rank = 110, maxRank = 150}},
                        db = {setupDone = true, chosen = {Enchanting = true}, show = true}})
    e.Fire("PLAYER_ENTERING_WORLD")
    check(Lines(e, "Enchanting"):find("+ 1 Shadowgem", 1, true), "era: Era's mats for it")
end

-- ranks: no Master before TBC; a book or a quest for First Aid, Cooking
-- and Fishing; a character level for crafting trainers
do
    local tail = {name = "Tailoring", rank = 290, maxRank = 300}
    local fa = {name = "First Aid", rank = 150, maxRank = 150}
    local cook = {name = "Cooking", rank = 218, maxRank = 225}
    local w = NewWorld({client = "classic", events = CLASSIC_EVENTS, level = 60, extra = {tail, fa, cook},
                        db = {setupDone = true, chosen = {Tailoring = true, ["First Aid"] = true, Cooking = true}, show = true}})
    w.Fire("PLAYER_ENTERING_WORLD")
    local text = Lines(w, "Tailoring")
    check(not text:find("Master", 1, true), "ranks: Classic Era has no Master rank to train at 290/300")
    tail.rank = 300; w.Fire("SKILL_LINES_CHANGED")
    check(Lines(w, "Tailoring"):find("Skill capped for this expansion", 1, true), "ranks: 300/300 is the end on Classic Era")
    check(Lines(w, "First Aid"):find("Capped! Expert First Aid comes from a book - see below", 1, true), "ranks: Expert First Aid is a book, not a trainer")
    check(Lines(w, "Cooking"):find("Cap soon - Artisan comes from a quest at 225", 1, true), "ranks: Artisan Cooking is a quest at 225, not a trainer at 200")
    local t = NewWorld({client = "tbc", events = CLASSIC_EVENTS, level = 60, extra = {{name = "Tailoring", rank = 280, maxRank = 300}},
                        db = {setupDone = true, chosen = {Tailoring = true}, show = true}})
    t.Fire("PLAYER_ENTERING_WORLD")
    check(Lines(t, "Tailoring"):find("Can train Master now (275 needed)", 1, true), "ranks: TBC trains Master at 275")
    local low = NewWorld({client = "forever", events = FOREVER_EVENTS, level = 15, extra = {{name = "Tailoring", rank = 126, maxRank = 150}},
                          db = {setupDone = true, chosen = {Tailoring = true}, show = true}})
    low.Fire("PLAYER_ENTERING_WORLD")
    check(Lines(low, "Tailoring"):find("Expert at 125 - needs character level 20 (you're 15)", 1, true), "ranks: Expert needs character level 20")
end

-- a row of alternatives needs the least the trainer asks of them: Crab
-- Cake (75) or Dry Pork Ribs (110 in one table), so 80 still stands
do
    local cook = {name = "Cooking", rank = 85, maxRank = 150}
    local w = NewWorld({client = "classic", events = CLASSIC_EVENTS, level = 20, extra = {cook},
                        db = {setupDone = true, chosen = {Cooking = true}, show = true}})
    w.Fire("PLAYER_ENTERING_WORLD")
    w.trainer = {{"Crab Cake", "used", "Cooking", 75}, {"Dry Pork Ribs", "available", "Cooking", 110}}
    w.Fire("TRAINER_SHOW")
    check(Lines(w, "Cooking"):find("Craft: Crab Cake / Dry Pork Ribs", 1, true), "alternatives: one learnable alternative keeps the row")
    w.trainer = {{"Crab Cake", "available", "Cooking", 90}, {"Dry Pork Ribs", "available", "Cooking", 110}}
    w.Fire("TRAINER_SHOW")
    check(Lines(w, "Cooking"):find("Craft: Smoked Bear Meat", 1, true), "alternatives: when the trainer says all need more, the row steps back")
end

-- skinning: level 10 + skill/10 below 100, skill/5 from there
do
    local w = NewWorld({client = "classic", events = CLASSIC_EVENTS, extra = {{name = "Skinning", rank = 50, maxRank = 75}},
                        db = {setupDone = true, chosen = {Skinning = true}, show = true}})
    w.Fire("PLAYER_ENTERING_WORLD")
    check(Lines(w, "Skinning"):find("up to ~level 15 mobs", 1, true), "skinning: 50 skill skins level 15 beasts (not 10)")
end

-- Forever's trainers: its new race, and the starting areas' Junior trainers
do
    local function trainerLines(client, race)
        local w = NewWorld({client = client, race = race, level = 3, events = client == "forever" and FOREVER_EVENTS or CLASSIC_EVENTS,
                            db = {setupDone = true, chosen = {Herbalism = true, Tailoring = true, Mining = true}, show = true}})
        w.Fire("PLAYER_ENTERING_WORLD")
        return Lines(w, "Herbalism"), Lines(w, "Tailoring"), w
    end
    local herb = trainerLines("forever", "Dwarf")
    check(herb:find("Emrys Flintbeard - Anvilmar, Coldridge Valley", 1, true), "forever: a dwarf is sent to the Junior Herbalism trainer in Coldridge Valley")
    herb = trainerLines("classic", "Dwarf")
    check(not herb:find("Emrys Flintbeard", 1, true), "classic: no Forever-only trainers there")
    local _, tail = trainerLines("forever", "Skyborne")
    check(tail:find("Taleen Shimmerthread - Shen'dar Village", 1, true), "forever: the Skyborne train in Shen'dar Village")
    local _, _, w = trainerLines("forever", "Human")
    local mine = Lines(w, "Mining")
    check(mine:find("Mine: Copper Vein / Poor Copper Vein", 1, true), "forever: its starter copper nodes are named")
end

-- The 1.0.0 review's findings, each as the case that showed it
do
    local function world(client, profs, opts)
        opts = opts or {}
        local chosen = {}
        for _, p in ipairs(profs) do chosen[p.name] = true end
        local w = NewWorld({client = client, events = client == "forever" and FOREVER_EVENTS or CLASSIC_EVENTS,
                            level = opts.level or 60, faction = opts.faction, zone = opts.zone, extra = profs,
                            db = {setupDone = true, chosen = chosen, show = true}})
        w.Fire("PLAYER_ENTERING_WORLD")
        return w
    end
    -- an old orange guess (seen at 20) must not beat the route at 98: the
    -- linen bolts grey at 50 on every client
    local tail = {name = "Tailoring", rank = 20, maxRank = 75}
    local w = world("classic", {tail})
    w.trade, w.tradeRank = {"Tailoring", {{"Bolt of Linen Cloth", "optimal"}}}, 20
    w.Fire("TRADE_SKILL_SHOW")
    tail.rank, tail.maxRank = 98, 150; w.Fire("SKILL_LINES_CHANGED")
    w.trade, w.tradeRank = {"Tailoring", {{"Bolt of Woolen Cloth", "easy"}}}, 98
    w.Fire("TRADE_SKILL_UPDATE")
    local text = Lines(w, "Tailoring")
    check(text:find("Craft: Bolt of Woolen Cloth (green)", 1, true) and not text:find("Craft: Bolt of Linen Cloth", 1, true),
          "review: a colour seen 78 points ago does not replace the route")

    -- Mists: trainers teach every First Aid / Cooking / Fishing rank, and ranks go on past 375
    local mf = {name = "First Aid", rank = 150, maxRank = 150}
    local mt = {name = "Tailoring", rank = 375, maxRank = 375}
    w = world("mists", {mf, mt})
    text = Lines(w, "First Aid")
    check(text:find("Capped! Train Expert at a First Aid trainer", 1, true) and not text:find("book", 1, true),
          "review: Mists trains Expert First Aid at a trainer, no book")
    check(Lines(w, "Tailoring"):find("Capped! Train Grand Master at a Tailoring trainer", 1, true), "review: Mists has Grand Master after 375")

    -- TBC: Artisan at any trainer (no Classic-only trainer notes), Master First Aid from a book
    local te = {name = "Enchanting", rank = 200, maxRank = 225}
    local tf = {name = "First Aid", rank = 300, maxRank = 300}
    w = world("tbc", {te, tf}, {level = 40})
    check(not Lines(w, "Enchanting"):find("Uldaman", 1, true), "review: TBC is not sent into Uldaman for Artisan Enchanting")
    text = Lines(w, "First Aid")
    check(text:find("Capped! Master First Aid comes from a book - see below", 1, true) and text:find("Burko, Temple of Telhamat", 1, true),
          "review: TBC's Master First Aid is a book in Outland")

    -- Era: where Expert is taught, per faction
    w = world("classic", {{name = "Enchanting", rank = 125, maxRank = 150}}, {level = 25, faction = "Horde"})
    check(Lines(w, "Enchanting"):find("Expert rank: Hgarth - Sun Rock Retreat", 1, true), "review: Era names the Expert Enchanting trainer")

    -- the fish is only named where it is caught
    w = world("classic", {{name = "Cooking", rank = 285, maxRank = 300}, {name = "Fishing", rank = 280, maxRank = 300}},
              {zone = "Western Plaguelands"})
    check(not Lines(w, "Cooking"):find("In Western Plaguelands", 1, true), "review: no Whitescale Salmon spot in Western Plaguelands")

    -- level gates per game
    w = world("forever", {{name = "Fishing", rank = 50, maxRank = 75}, {name = "Cooking", rank = 50, maxRank = 75}}, {level = 8})
    check(Lines(w, "Fishing"):find("needs character level 10", 1, true), "review: Forever's Journeyman Fishing needs level 10")
    check(Lines(w, "Cooking"):find("Can train Journeyman now (50 needed)", 1, true), "review: Forever's Journeyman Cooking has no level gate")
    w = world("classic", {{name = "Cooking", rank = 50, maxRank = 75}}, {level = 8})
    check(Lines(w, "Cooking"):find("needs character level 10", 1, true), "review: Era's Journeyman Cooking needs level 10")
    w = world("tbc", {{name = "Fishing", rank = 125, maxRank = 150}}, {level = 15})
    check(not Lines(w, "Fishing"):find("character level", 1, true), "review: TBC's Expert Fishing book has no level gate")

    -- Era sells the top Alchemy recipes; TBC's trainers teach them
    local ea = {name = "Alchemy", rank = 266, maxRank = 300}
    w = world("classic", {ea})
    w.trade, w.tradeRank = {"Alchemy", {{"Elixir of Greater Agility", "easy"}}}, 266
    w.Fire("TRADE_SKILL_SHOW")
    check(Lines(w, "Alchemy"):find("Get it: Recipe (limited stock): Ulthir", 1, true), "review: Era names the Superior Mana Potion vendor")
    w = world("tbc", {ea})
    w.trade, w.tradeRank = {"Alchemy", {{"Elixir of Greater Agility", "easy"}}}, 266
    w.Fire("TRADE_SKILL_SHOW")
    check(Lines(w, "Alchemy"):find("Get it: check your trainer", 1, true), "review: TBC sends you to the trainer for it")

    -- the end of the road: no skill-up advice at the last cap
    w = world("classic", {{name = "Blacksmithing", rank = 300, maxRank = 300}})
    text = Lines(w, "Blacksmithing")
    check(text:find("Nothing left to skill up here", 1, true) and not text:find("Craft:", 1, true) and not text:find("Get it", 1, true),
          "review: 300/300 on Era gives no skill-up advice")

    -- after a trainer step-back, "At N" is the trainer's number
    local lw = {name = "Leatherworking", rank = 57, maxRank = 75}
    w = world("classic", {lw}, {level = 15})
    w.trainer = {{"Embossed Leather Gloves", "unavailable", "Leatherworking", 60}}
    w.Fire("TRAINER_SHOW")
    text = Lines(w, "Leatherworking")
    check(text:find("needs 60 - your trainer said so", 1, true) and text:find("At 60: Embossed Leather Gloves", 1, true),
          "review: the 'At' line uses the trainer's number after a step-back")

    -- alternatives: only the known one's mats; green is not "moved"
    local ck = {name = "Cooking", rank = 100, maxRank = 150}
    w = world("classic", {ck})
    w.trade, w.tradeRank = {"Cooking", {{"Crab Cake", "optimal"}}}, 100
    w.Fire("TRADE_SKILL_SHOW")
    text = Lines(w, "Cooking")
    check(text:find("Mats: 1 Crawler Meat + 1 Mild Spices\n", 1, true) or text:sub(-36) == "Mats: 1 Crawler Meat + 1 Mild Spices",
          "review: a row of alternatives shows only the known recipe's mats")
    local fa = {name = "First Aid", rank = 77, maxRank = 150}
    w = world("classic", {fa})
    w.trade, w.tradeRank = {"First Aid", {{"Heavy Linen Bandage", "easy"}, {"Anti-Venom", "medium"}}}, 77
    w.Fire("TRADE_SKILL_SHOW")
    text = Lines(w, "First Aid")
    check(text:find("(Heavy Linen Bandage is green for you now and only skills up some of the time", 1, true) and not text:find("moved", 1, true),
          "review: a green route recipe is not said to have been moved")

    -- "an Alchemy trainer"
    w = world("classic", {{name = "Alchemy", rank = 75, maxRank = 75}}, {level = 20})
    check(Lines(w, "Alchemy"):find("Capped! Train Journeyman at an Alchemy trainer", 1, true), "review: an Alchemy trainer")

    -- Forever: a known recipe the window's filter hides is still known
    local fe = {name = "Enchanting", rank = 63, maxRank = 75}
    w = world("forever", {fe}, {level = 20})
    w.openProf, w.openRank = "Enchanting", 63
    w.recipes = {[7420] = {name = "Enchant Chest - Inferior Stamina", learned = true, relativeDifficulty = 3, canSkillUp = false},
                 [7457] = {name = "Enchant Bracer - Minor Stamina", learned = true, relativeDifficulty = 0, canSkillUp = true}}
    w.hidden = {[7420] = true}
    w.Fire("TRADE_SKILL_LIST_UPDATE")
    text = Lines(w, "Enchanting")
    check(text:find("Craft: Enchant Bracer - Minor Stamina (orange)", 1, true) and not text:find("don't know", 1, true),
          "review: Forever - a grey recipe hidden by 'has skill up' is still known, and replaced")
    -- a client with only the filtered list says the filter may hide it
    w = world("forever", {fe}, {level = 20})
    w.openProf, w.openRank, w.noAllIDs = "Enchanting", 63, true
    w.recipes = {[7457] = {name = "Enchant Bracer - Minor Stamina", learned = true, relativeDifficulty = 0, canSkillUp = true},
                 [7420] = {name = "Enchant Chest - Inferior Stamina", learned = true, relativeDifficulty = 3}}
    w.hidden = {[7420] = true}
    w.Fire("TRADE_SKILL_LIST_UPDATE")
    check(Lines(w, "Enchanting"):find("Not in your window's list - if you know it, clear the window's filters once", 1, true),
          "review: with only the filtered list, a missing recipe may be the filter's doing")
end

--------------------------------------------------------------------------
-- Other languages (1.1.0). A report: "My professions are not detected
-- because I play in French." The game names skills, recipes, items and
-- zones in its own language; the addon's sentences come from Locales.lua.
--------------------------------------------------------------------------
do
    local FR = {Mining = "Minage", Tailoring = "Couture", Cooking = "Cuisine", Defense = "Défense",
                ["Class Skills"] = "Compétences de classe", Professions = "Métiers", ["Secondary Skills"] = "Compétences secondaires"}
    local function french(opts)
        opts = opts or {}
        local tail = {name = "Tailoring", rank = opts.rank or 50, maxRank = 75}
        local w = NewWorld({client = opts.client or "classic", locale = "frFR", level = 15, names = FR, extra = {tail},
                            events = opts.client == "forever" and FOREVER_EVENTS or CLASSIC_EVENTS,
                            spells = {[3755] = "Sac en lin", [2397] = "Cape en lin renforcée", [8776] = "Ceinture en lin"},
                            items = opts.items or {[2996] = "Rouleau d'étoffe de lin", [2320] = "Fil grossier"},
                            map = opts.map, mapNames = opts.mapNames, mapParents = opts.mapParents, zone = opts.zone,
                            db = {setupDone = true, chosen = {Mining = true, Tailoring = true, Cooking = true}, show = true}})
        w.Fire("PLAYER_ENTERING_WORLD")
        return w, tail
    end
    local w = french()
    check(w.ns.profs.Mining and w.ns.profs.Mining.rank == 45 and w.ns.profs.Tailoring and w.ns.profs.Tailoring.rank == 50 and
          w.ns.profs.Cooking and w.ns.profs.Cooking.rank == 20, "fr: Minage, Couture and Cuisine are found")
    local text = Lines(w, "Mining")
    check(text:find("Minage  45/75", 1, true) and text:find("Miner : Filon de cuivre", 1, true) and text:find("À 65 : Filon d'étain", 1, true),
          "fr: the mining advice reads in French, nodes named as the game names them")
    text = Lines(w, "Tailoring")
    check(text:find("Couture  50/75", 1, true) and text:find("Créer : Sac en lin\n", 1, true) and
          text:find("Composants : 3 Rouleau d'étoffe de lin + 3 Fil grossier", 1, true) and text:find("À 70 : Cape en lin renforcée", 1, true),
          "fr: recipes and mats named by the game, by spell and item ID")
    check(not text:find("Linen", 1, true) and not text:find("Craft:", 1, true), "fr: no English left in the craft lines")
    w.slash("status")
    check(Printed("client language: frFR"), "fr: /rxpp status names the client's language")
    -- the profession window, in French
    w.trade, w.tradeRank = {"Couture", {{"Sac en lin", "optimal"}, {"Ceinture en lin", "medium"}}}, 50
    w.Fire("TRADE_SKILL_SHOW")
    local known = w.ns.GetKnownRecipes("Tailoring")
    check(known and known["Sac en lin"] and known["Ceinture en lin"], "fr: the Couture window's recipes are remembered under Tailoring")
    text = Lines(w, "Tailoring")
    check(text:find("Créer : Sac en lin (orange)", 1, true) and not text:find("Vous ne connaissez pas", 1, true),
          "fr: the window's colour is matched to the route recipe by its French name")
    -- the trainer, in French
    w = french()
    w.trainer = {{"Sac en lin", "available", "Couture", 55}}
    w.Fire("TRAINER_SHOW")
    check(w.ns.RecipeRequirement("Tailoring", "Sac en lin") == 55, "fr: a trainer's 'Couture' requirement is filed under Tailoring")
    check(Lines(w, "Tailoring"):find("(Sac en lin requiert 55 - d'après votre maître)", 1, true), "fr: and the route steps back for it")
    -- an item not cached yet: English until it arrives, and it is asked for
    w = french({items = {[2996] = "Rouleau d'étoffe de lin"}})
    text = Lines(w, "Tailoring")
    check(text:find("Composants : 3 Bolt of Linen Cloth + 3 Coarse Thread", 1, true) and w.itemRequests[2320],
          "fr: an uncached reagent leaves the English mats and asks the game for the item")
    w.timers = {}
    w.Fire("GET_ITEM_INFO_RECEIVED", 2320, true)
    check(#w.timers == 1, "fr: the item's arrival schedules a redraw")
    -- the zone, by map ID: the French zone name is not in the data
    w = french({map = 1433, mapNames = {[1433] = "Les Carmines"}, zone = "Les Carmines"})
    local key, waters, label = w.ns.CurrentZone()
    check(key == "Redridge Mountains" and waters and label == "Les Carmines", "fr: the zone is found by its map ID")
    check(w.ns.ZoneWaterSpot({water = "inland"}) == "Ici (Les Carmines) : les eaux intérieures", "fr: the fishing spot names the zone as the game does")
    w = french({map = 9999, mapParents = {[9999] = 1433}, mapNames = {[1433] = "Les Carmines"}})
    check(w.ns.CurrentZone() == "Redridge Mountains", "fr: a sub-zone map is walked up to its zone")
    w = french({zone = "Les Carmines"})
    check(w.ns.CurrentZone() == nil, "fr: without a map ID, a French zone name matches nothing (no wrong water)")
end

-- Russian: names with no ASCII letters must not all match each other
do
    local RU = {Mining = "Горное дело", Tailoring = "Портняжное дело"}
    local tail = {name = "Tailoring", rank = 50, maxRank = 75}
    local w = NewWorld({client = "classic", locale = "ruRU", events = CLASSIC_EVENTS, level = 15, names = RU, extra = {tail},
                        spells = {[3755] = "Льняная сумка"},
                        db = {setupDone = true, chosen = {Mining = true, Tailoring = true}, show = true}})
    w.Fire("PLAYER_ENTERING_WORLD")
    local L = w.ns.L
    check(w.ns.profs.Mining and w.ns.profs.Tailoring and w.ns.profs.Tailoring.rank == 50, "ru: Cyrillic skill names are found")
    check(Lines(w, "Mining"):find(string.format(L["Mine: %s"], "Медная жила"), 1, true) and L["Mine: %s"] ~= "Mine: %s",
          "ru: the mining line in Russian")
    local k1, k2 = w.ns.RecipeKey("Льняная сумка"), w.ns.RecipeKey("Льняной плащ")
    check(k1 ~= "" and k2 ~= "" and k1 ~= k2, "ru: Cyrillic recipe keys keep their letters")
    check(w.ns.ResolveRecipe({["Льняной плащ"] = true}, "Льняная сумка") == nil and
          w.ns.ResolveRecipe({["Льняная сумка"] = true}, "Льняная сумка") == "Льняная сумка", "ru: one Cyrillic recipe does not match another")
    -- a window without the route's recipe: it is not mistaken for another one
    w.trade, w.tradeRank = {"Портняжное дело", {{"Льняной плащ", "optimal"}}}, 50
    w.Fire("TRADE_SKILL_SHOW")
    local text = Lines(w, "Tailoring")
    check(w.ns.GetKnownRecipes("Tailoring")["Льняной плащ"] and text:find(L["You don't know this recipe yet!"], 1, true) and
          not text:find("Льняная сумка (", 1, true) and text:find(string.format(L["Meanwhile: %s (%s)"], "Льняной плащ", L["orange"]), 1, true),
          "ru: an unknown route recipe is not matched to another Cyrillic one (that one is offered meanwhile)")
    -- TBC's Russian client writes Skinning with a Latin C
    local t = NewWorld({client = "tbc", locale = "ruRU", events = CLASSIC_EVENTS, names = {Skinning = "Cнятие шкур"},
                        extra = {{name = "Skinning", rank = 80, maxRank = 150}}, db = {setupDone = true, chosen = {Skinning = true}, show = true}})
    t.Fire("PLAYER_ENTERING_WORLD")
    check(t.ns.profs.Skinning and t.ns.profs.Skinning.rank == 80, "ru: TBC's 'Cнятие шкур' (Latin C) is Skinning")
    check(t.ns.RankLabel("Artisan") == "Искусник" and w.ns.RankLabel("Artisan") ~= "Искусник", "ru: TBC's own word for Artisan")
end

-- Forever: the skill line's ID decides, whatever the name
do
    local tail = {name = "Tailoring", rank = 50, maxRank = 75}
    local w = NewWorld({client = "forever", locale = "frFR", events = FOREVER_EVENTS, names = {Tailoring = "Couture d'antan"},
                        skillIDs = {Tailoring = 197}, extra = {tail}, db = {setupDone = true, chosen = {Tailoring = true}, show = true}})
    w.Fire("PLAYER_ENTERING_WORLD")
    check(w.ns.profs.Tailoring and w.ns.profs.Tailoring.rank == 50, "forever fr: a name in no table is found by its skill-line ID")
    check(Lines(w, "Tailoring"):find("Couture d'antan  50/75", 1, true), "forever fr: and labelled as the game names it")
    w.openProf, w.openRank, w.openID = "Couture d'antan", 50, 197
    w.recipes = {[3755] = {name = "Sac en lin", learned = true, relativeDifficulty = 0}}
    w.Fire("TRADE_SKILL_LIST_UPDATE")
    check(w.ns.GetKnownRecipes("Tailoring") and w.ns.GetKnownRecipes("Tailoring")["Sac en lin"], "forever fr: its window is read by the profession's ID")
    -- a client that only names it: GetTradeSkillDisplayName
    local d = NewWorld({client = "forever", locale = "deDE", events = FOREVER_EVENTS, names = {Tailoring = "Schneidern"},
                        displayNames = {[197] = "Schneidern"}, extra = {{name = "Tailoring", rank = 30, maxRank = 75}},
                        db = {setupDone = true, chosen = {Tailoring = true}, show = true}})
    d.Fire("PLAYER_ENTERING_WORLD")
    check(d.ns.profs.Tailoring and d.ns.profs.Tailoring.rank == 30, "forever: the game's own display name for the skill line is matched")
    -- Italian: Forever names professions and ranks in Italian, the Classic clients in English
    local it = NewWorld({client = "forever", locale = "itIT", events = FOREVER_EVENTS, names = {Tailoring = "Sartoria"},
                         extra = {{name = "Tailoring", rank = 30, maxRank = 75}}, db = {setupDone = true, chosen = {Tailoring = true}, show = true}})
    it.Fire("PLAYER_ENTERING_WORLD")
    check(it.ns.profs.Tailoring and it.ns.RankLabel("Artisan") == "Specialista", "forever it: Sartoria found, Italian ranks")
    local ic = NewWorld({client = "classic", locale = "itIT", events = CLASSIC_EVENTS, extra = {{name = "Tailoring", rank = 30, maxRank = 75}},
                         db = {setupDone = true, chosen = {Tailoring = true}, show = true}})
    ic.Fire("PLAYER_ENTERING_WORLD")
    check(ic.ns.profs.Tailoring and ic.ns.RankLabel("Artisan") == "Artisan", "classic it: English names there")
    -- a language with no translation reads in English
    local x = NewWorld({client = "classic", locale = "xxXX", events = CLASSIC_EVENTS, db = {setupDone = true, chosen = {Mining = true}, show = true}})
    x.Fire("PLAYER_ENTERING_WORLD")
    check(Lines(x, "Mining"):find("Mine: Copper Vein", 1, true), "unknown language: English")
end

-- The 1.1.0 review's findings
do
    local function world(client, locale, profs, opts)
        opts = opts or {}
        local chosen = {}
        for _, name in ipairs(opts.chosen or {}) do chosen[name] = true end
        for _, p in ipairs(profs) do chosen[p.name] = true end
        local w = NewWorld({client = client, locale = locale, events = client == "forever" and FOREVER_EVENTS or CLASSIC_EVENTS,
                            level = opts.level or 60, zone = opts.zone, extra = profs, names = opts.names, items = opts.items,
                            map = opts.map, mapNames = opts.mapNames, displayNames = opts.displayNames,
                            db = {setupDone = true, chosen = chosen, show = true}})
        w.Fire("PLAYER_ENTERING_WORLD")
        return w
    end
    -- closing the window says so in the player's language
    local w = world("classic", "frFR", {})
    for _, f in ipairs(w.frames) do
        if f.template == "UIPanelCloseButton" then f.scripts.OnClick(f) end
    end
    local closed = w.ns.L["window hidden. Type /rxpp to bring it back."]
    check(closed ~= "window hidden. Type /rxpp to bring it back." and Printed(closed), "l10n review: the close message is translated")
    -- a profession not learned yet: the client's own spelling
    w = world("tbc", "esES", {}, {chosen = {"Tailoring"}})
    check(Lines(w, "Tailoring"):find("^Sastrería\n"), "l10n review: TBC's Spanish names Tailoring 'Sastrería' before it is learned")
    w = world("classic", "esES", {}, {chosen = {"Tailoring"}})
    check(Lines(w, "Tailoring"):find("^Costura\n"), "l10n review: Era's Spanish 'Costura'")
    w = world("forever", "itIT", {}, {chosen = {"Tailoring"}})
    check(Lines(w, "Tailoring"):find("^Sartoria\n"), "l10n review: Forever's Italian 'Sartoria', not English")
    w = world("forever", "frFR", {}, {chosen = {"Tailoring"}, displayNames = {[197] = "Couture (jeu)"}})
    check(Lines(w, "Tailoring"):find("^Couture %(jeu%)\n"), "l10n review: the game's own name for the skill line comes first")
    -- Mists renamed Plaguebloom in English too
    w = world("mists", "enUS", {{name = "Herbalism", rank = 286, maxRank = 300}})
    check(Lines(w, "Herbalism"):find("Pick: Sorrowmoss", 1, true), "l10n review: Mists in English picks Sorrowmoss")
    w = world("classic", "enUS", {{name = "Herbalism", rank = 286, maxRank = 300}})
    check(Lines(w, "Herbalism"):find("Pick: Plaguebloom", 1, true), "l10n review: Era keeps Plaguebloom")
    -- the fishing spots, zone names from the game
    local fish = {name = "Fishing", rank = 200, maxRank = 225}
    w = world("classic", "enUS", {fish}, {zone = "Orgrimmar", chosen = {"Cooking"}})
    w.tree[3].children[1].rank, w.tree[3].children[1].maxRank = 180, 225
    w.Fire("SKILL_LINES_CHANGED")
    check(Lines(w, "Fishing"):find("Where: coasts of 30-45 zones (Swamp of Sorrows, Dustwallow Marsh, Stranglethorn Vale, Desolace)", 1, true),
          "l10n review: English fishing spot with its zones")
    local names = {[1435] = "Marais des Chagrins", [1445] = "Marécage d'Âprefange", [1434] = "Vallée de Strangleronce", [1443] = "Désolace",
                   [1454] = "Orgrimmar"}
    w = world("classic", "frFR", {fish}, {zone = "Orgrimmar", map = 1454, mapNames = names, names = {Fishing = "Pêche", Cooking = "Cuisine"}, chosen = {"Cooking"}})
    w.tree[3].children[1].rank, w.tree[3].children[1].maxRank = 180, 225
    w.Fire("SKILL_LINES_CHANGED")
    local L = w.ns.L
    local where = string.format(L["coasts of 30-45 zones (%s)"], "Marais des Chagrins, Marécage d'Âprefange, Vallée de Strangleronce, Désolace")
    check(L["coasts of 30-45 zones (%s)"] ~= "coasts of 30-45 zones (%s)" and Lines(w, "Fishing"):find(string.format(L["Where: %s"], where), 1, true),
          "l10n review: the French fishing spot, zones named by the game")
    check(Lines(w, "Cooking"):find(string.format(L["(fish: %s)"], where), 1, true), "l10n review: and on the Cooking side")
    -- no escaping fish on Mists (gone since patch 3.1)
    fish = {name = "Fishing", rank = 20, maxRank = 75}
    w = world("mists", "enUS", {fish}, {zone = "Redridge Mountains"})
    check(not Lines(w, "Fishing"):find("Fish escape here", 1, true), "l10n review: Mists does not warn of escaping fish")
    w = world("classic", "enUS", {fish}, {zone = "Redridge Mountains"})
    check(Lines(w, "Fishing"):find("Fish escape here! Redridge Mountains needs ~55 skill (you: 20)", 1, true), "l10n review: Era still does")
end

-- a secret rank (Forever hides some numbers from addon code) counts as unknown, not an error
do
    local w = NewWorld({client = "forever", events = FOREVER_EVENTS, secretRank = true, db = {setupDone = true, chosen = {Cooking = true}, show = true}})
    local ok = pcall(w.Fire, "PLAYER_ENTERING_WORLD")
    check(ok and w.ns.profs.Cooking and w.ns.profs.Cooking.rank == 0 and w.ns.profs.Cooking.maxRank == 75, "forever: a secret rank reads as 0 instead of throwing")
end

--------------------------------------------------------------------------
-- retail-style: GetProfessions
--------------------------------------------------------------------------
do
    local ok, w = pcall(NewWorld, {client = "retail", events = FOREVER_EVENTS, db = {setupDone = true, chosen = {Mining = true}, show = true}})
    check(ok, "retail: loads")
    w.Fire("PLAYER_ENTERING_WORLD")
    check(w.ns.profs.Mining and w.ns.profs.Mining.rank == 45 and w.ns.profs.Enchanting.rank == 10 and w.ns.skillAPI == "GetProfessions", "retail: skills read from GetProfessions ids")
    check(w.ns.profs.Cooking and w.ns.profs.Cooking.rank == 20, "retail: a profession after an empty slot is read too")
end

-- a client with no skill API at all: nothing tracked, nothing thrown
do
    local w = NewWorld({client = "none", events = FOREVER_EVENTS, db = {setupDone = true, chosen = {Mining = true}, show = true}})
    local ok = pcall(w.Fire, "PLAYER_ENTERING_WORLD")
    check(ok and next(w.ns.profs) == nil and w.ns.skillAPI == "none", "no skill API: tracks nothing, no error")
end

--------------------------------------------------------------------------
-- Item tooltips (Inventory.lua): what the plan needs, span by span, against
-- what you have in bags and bank. A span is a route row, from its skill to
-- the next row's; the one you are in counts from your skill.
--------------------------------------------------------------------------

-- a world with the modern tooltip pipeline (TooltipDataProcessor, as WoW
-- Forever has it) and an item count that knows bags and bank apart:
-- counts[id] = {bags = n, bank = n}, or anything else for a secret value
local postCalls = {}
local function TooltipWorld(opts, counts)
    _G.Enum = {TooltipDataType = {Item = 0}, PlayerInteractionType = {Banker = 8}}
    _G.TooltipDataProcessor = {AddTooltipPostCall = function(kind, fn) postCalls[#postCalls + 1] = {kind, fn} end}
    local w = NewWorld(opts)
    w.post = postCalls[#postCalls]
    w.counts = counts or {}
    w.bankVisible = true
    _G.C_Item = _G.C_Item or {}
    _G.C_Item.GetItemCount = function(id, includeBank)
        local c = w.counts[id]
        if c == nil then return 0 end
        if type(c) ~= "table" or c.bags == nil then return c end
        if includeBank and w.bankVisible then return c.bags + c.bank end
        return c.bags
    end
    w.Fire("PLAYER_ENTERING_WORLD")
    return w
end
-- the lines a tooltip gets for an item, joined: the game's own tooltip
-- unless `which` names another (ItemRefTooltip, a comparison tooltip, an
-- addon's hidden scanning one); forbidden = one the game locks away
local function Tip(w, id, which, forbidden)
    which = which or "GameTooltip"
    local tip = {lines = {}}
    function tip:AddLine(text) table.insert(self.lines, text) end
    function tip:GetName() return which end
    function tip:IsForbidden() return forbidden or false end
    local saved = {GameTooltip = _G.GameTooltip, ItemRefTooltip = _G.ItemRefTooltip}
    if which == "GameTooltip" or which == "ItemRefTooltip" then _G[which] = tip end
    w.post[2](tip, {id = id})
    _G.GameTooltip, _G.ItemRefTooltip = saved.GameTooltip, saved.ItemRefTooltip
    return table.concat(tip.lines, "\n")
end
-- the inventory frame: the one listening for the bank
local function FireInventory(w, event, ...)
    for _, f in ipairs(w.frames) do
        if f.events.BANKFRAME_OPENED and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
    end
end
-- the timers set for a moment later (C_Timer.After), run now; the
-- window's 15-second ticker stays
local function RunSoon(w)
    local due, keep = {}, {}
    for _, t in ipairs(w.timers) do
        if t[1] < 15 then due[#due + 1] = t else keep[#keep + 1] = t end
    end
    w.timers = keep
    for _, t in ipairs(due) do t[2]() end
    return #due
end
local BANK_EVENTS = {"BANKFRAME_OPENED", "BANKFRAME_CLOSED", "BAG_UPDATE_DELAYED", "PLAYERBANKSLOTS_CHANGED",
                     "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE"}
local function With(list, extra)
    local out = {}
    for _, e in ipairs(list) do out[#out + 1] = e end
    for _, e in ipairs(extra) do out[#out + 1] = e end
    return out
end

-- Forever, Tailoring 63: the bolt row 55-70 is "now"; the bolts go into
-- Woolen Cape (70-100) and Double-Stitched Woolen Shoulders (110-120)
do
    local tailor = {name = "Tailoring", rank = 63, maxRank = 75}
    local w = TooltipWorld({client = "forever", events = FOREVER_EVENTS, level = 14, extra = {tailor},
                            db = {setupDone = true, chosen = {Tailoring = true}, show = true}},
                           {[2592] = {bags = 25, bank = 15}})
    check(w.post and w.post[1] == 0 and w.ns.tooltipAPI == "TooltipDataProcessor", "tooltips: item tooltips through TooltipDataProcessor where the client has it")
    local wool = Tip(w, 2592)
    check(wool:find(" \nRXP Professions\nTailoring\n", 1, true), "tooltips: a gap, a header, then the profession")
    check(wool:find("  Now 63-70 · 21 (bags 21) of ~21 · Bolt of Woolen Cloth\n", 1, true),
          "tooltips: the span you are in counts from your skill (7 crafts x 3 Wool Cloth), and gets what you have first, from the bags")
    check(wool:find("  70-100 · 19 (bags 4 · bank 15) of ~69 · Woolen Cape (via Bolt of Woolen Cloth)\n", 1, true),
          "tooltips: a later span through the bolts, less the 7 the span before makes ((30 - 7) x 3), with the rest of the bags and the bank")
    check(wool:find("  110-120 · 0 of ~90 · Double-Stitched Woolen Shoulders (via Bolt of Woolen Cloth)\n", 1, true), "tooltips: and the next span that uses the bolts (30 x 3), nothing left for it")
    check(wool:find("\nYou have 40 (bags 25 · bank 15) · ~140 short", 1, true), "tooltips: the total, bags and bank apart, and what is short")
    check(Tip(w, 2997):find("  70-100 · 0 of ~30 · Woolen Cape\n", 1, true), "tooltips: the bolt itself shows the spans that use it")
    check(Tip(w, 4306):find("  100-110 · 0 of ~40 · Bolt of Silk Cloth\n", 1, true), "tooltips: Silk Cloth from its own span on (10 crafts x 4)")
    check(Tip(w, 4306):find("You have 0 (bags 0 · bank 0) · ~620 short", 1, true), "tooltips: none in the bags, nothing needed now: what the later spans need")
    check(Tip(w, 2589) == "", "tooltips: Linen Cloth is behind you at Tailoring 63 - no block at all")
    check(Tip(w, 12345) == "", "tooltips: an item the plan does not name gets nothing")
    check(Lines(w, "Tailoring"):find("Craft: Bolt of Woolen Cloth\n", 1, true), "tooltips: the window names the same row")

    -- what you have in the bags of a made reagent comes off what it is made of
    w.counts[2997] = {bags = 10, bank = 0}
    w.ns.planDirty = true
    check(Tip(w, 2592):find("  70-100 · 19 (bags 4 · bank 15) of ~39 · Woolen Cape (via Bolt of Woolen Cloth)\n", 1, true),
          "tooltips: 10 bolts in the bags take 30 Wool Cloth off ((30 - 7 - 10) x 3)")
    w.counts[2997] = nil
    w.ns.planDirty = true

    -- a long list is cut short with a sum
    w.ns.TOOLTIP_MAX_SPANS = 1
    check(Tip(w, 2592):find("  70-100 · 19 (bags 4 · bank 15) of ~69 · Woolen Cape (via Bolt of Woolen Cloth)\n  +1 more span · 0 of ~90\n", 1, true),
          "tooltips: spans past the limit are summed on one line")
    w.ns.TOOLTIP_MAX_SPANS = 5

    -- the professions you did not pick: off, then on under their own heading
    check(not wool:find("First Aid", 1, true), "tooltips: a profession you did not pick stays out by default")
    w.slash("tooltip others")
    local text = Tip(w, 2592)
    local head = text:find("Other professions (not in your setup)", 1, true)
    check(head and text:find("First Aid (not learned yet)\n  80-115 · ~35 · Wool Bandage\n  115-150 · ~70 · Heavy Wool Bandage", head, true),
          "tooltips: with others on, First Aid shows under its own heading, after yours, with what it needs alone")
    check(head and text:find("You have 40 (bags 25 · bank 15) · ~140 short", 1, true) < head, "tooltips: the others leave what your bags cover alone")
    w.slash("tooltip others")
    check(not Tip(w, 2592):find("First Aid", 1, true), "tooltips: /rxpp tooltip others turns them off again")

    -- later spans off, then the whole block
    w.slash("tooltip later")
    text = Tip(w, 2592)
    check(text:find("  Now 63-70", 1, true) and not text:find("  70-100 ", 1, true), "tooltips: /rxpp tooltip later hides the spans after the one you are in")
    w.slash("tooltip later")
    w.slash("tooltip")
    check(Tip(w, 2592) == "", "tooltips: /rxpp tooltip turns them off")
    w.slash("tooltip")
    check(Tip(w, 2592) ~= "", "tooltips: and on")
end

-- Classic Era, Tailoring 63: Linen Bag (45-70) uses the bolts, the bolts
-- the cloth
do
    local c = TooltipWorld({client = "classic", events = CLASSIC_EVENTS, level = 14, extra = {{name = "Tailoring", rank = 63, maxRank = 75}},
                            db = {setupDone = true, chosen = {Tailoring = true}, show = true}})
    check(Tip(c, 2996):find("  Now 63-70 · 0 of ~21 · Linen Bag\n", 1, true), "tooltips, Classic Era: Bolt of Linen Cloth now for Linen Bag (7 crafts x 3)")
    check(Tip(c, 2589):find("  Now 63-70 · 0 of ~42 · Linen Bag (via Bolt of Linen Cloth)\n", 1, true), "tooltips, Classic Era: Linen Cloth through the bolts (21 x 2)")
    check(Tip(c, 2996):find("You have 0 (bags 0 · bank 0) · ~31 short", 1, true), "tooltips, Classic Era: none in the bags - short")
end

-- the trainer said Woolen Cape needs 75: the window steps back to the
-- bolts at 72, and the tooltip with it
do
    local w = TooltipWorld({client = "forever", events = FOREVER_EVENTS, level = 14, extra = {{name = "Tailoring", rank = 72, maxRank = 75}},
                            db = {setupDone = true, chosen = {Tailoring = true}, show = true, recipeReq = {Tailoring = {["Woolen Cape"] = 75}}}})
    local window = Lines(w, "Tailoring")
    check(window:find("Craft: Bolt of Woolen Cloth", 1, true) and window:find("At 75: Woolen Cape", 1, true), "tooltips: the window steps back to the bolts")
    check(Tip(w, 2592):find("  Now 72-75 · 0 of ~9 · Bolt of Woolen Cloth\n  75-100 · 0 of ~66 · Woolen Cape (via Bolt of Woolen Cloth)", 1, true),
          "tooltips: and the tooltip with it - now 72-75, Woolen Cape from 75")
end

-- a client that sees the bank only while it is open: the count taken at
-- the last visit stands in, and says so
do
    local w = TooltipWorld({client = "forever", events = With(FOREVER_EVENTS, BANK_EVENTS), level = 14, extra = {{name = "Tailoring", rank = 63, maxRank = 75}},
                            db = {setupDone = true, chosen = {Tailoring = true}, show = true}},
                           {[2592] = {bags = 5, bank = 20}})
    w.bankVisible = false
    check(Tip(w, 2592):find("  Now 63-70 · 5 (bags 5) of ~21 · Bolt of Woolen Cloth\n", 1, true) and
              Tip(w, 2592):find("You have 5 (bags 5 · bank 0) · ~175 short", 1, true), "tooltips: away from a bank the client cannot see, the bags alone")
    w.bankVisible = true
    FireInventory(w, "BANKFRAME_OPENED")
    check(w.ns.db.bankSeen and w.ns.db.bankSeen[2592] == 20, "tooltips: the bank is counted while it is open")
    FireInventory(w, "BANKFRAME_CLOSED")
    w.bankVisible = false
    check(Tip(w, 2592):find("  Now 63-70 · 21 (bags 5 · bank 16) of ~21 · Bolt of Woolen Cloth\n  70-100 · 4 (bank 4) of ~69", 1, true) and
              Tip(w, 2592):find("You have 25 (bags 5 · bank 20) · ~155 short\n(bank as counted at your last visit)", 1, true),
          "tooltips: the bank as counted at the last visit, and saying so")
end

-- Fishing + Cooking: the raw fish feeds the Cooking span you are in
do
    local w = TooltipWorld({client = "classic", events = CLASSIC_EVENTS, level = 14,
                            db = {setupDone = true, chosen = {Cooking = true, Fishing = true}, show = true}})
    check(Tip(w, 6291):find("Cooking\n  Now 20-50 · 0 of ~30 · Brilliant Smallfish\n", 1, true), "tooltips: Fishing + Cooking - the fish for the dish you are cooking now")
end

-- nothing left to skill up: no needs
do
    local w = TooltipWorld({client = "classic", events = CLASSIC_EVENTS, level = 60, extra = {{name = "Tailoring", rank = 300, maxRank = 300}},
                            db = {setupDone = true, chosen = {Tailoring = true}, show = true}})
    check(Tip(w, 14047) == "", "tooltips: at the last cap the plan needs nothing more")
end

-- a secret item count (Forever hides some numbers from addon code) reads
-- as none instead of taking the tooltip down
do
    local secret = setmetatable({}, {__eq = function() error("attempt to compare a secret number value") end})
    local w = TooltipWorld({client = "forever", events = FOREVER_EVENTS, level = 14, extra = {{name = "Tailoring", rank = 63, maxRank = 75}},
                            db = {setupDone = true, chosen = {Tailoring = true}, show = true}}, {[2592] = secret})
    local ok, text = pcall(Tip, w, 2592)
    check(ok and text:find("You have 0 (bags 0 · bank 0)", 1, true), "tooltips: a secret count reads as none, no error")
end

-- older clients: OnTooltipSetItem, which can fire twice for one showing
do
    _G.TooltipDataProcessor = nil
    local hooks = {}
    local tip = {lines = {}, shown = 0}
    function tip:HookScript(event, fn) hooks[event] = fn end
    function tip:AddLine(text) table.insert(self.lines, text) end
    function tip:GetItem() return "Bolt of Linen Cloth", "|cffffffff|Hitem:2996::::::::14:::::|h[Bolt of Linen Cloth]|h|r" end
    function tip:GetName() return "GameTooltip" end
    function tip:Show() self.shown = self.shown + 1 end
    _G.GameTooltip = tip
    local w = NewWorld({client = "classic", events = CLASSIC_EVENTS, level = 14, extra = {{name = "Tailoring", rank = 63, maxRank = 75}},
                        db = {setupDone = true, chosen = {Tailoring = true}, show = true}})
    w.Fire("PLAYER_ENTERING_WORLD")
    check(w.ns.tooltipAPI == "OnTooltipSetItem" and hooks.OnTooltipSetItem and hooks.OnTooltipCleared, "tooltips: older clients hook OnTooltipSetItem")
    hooks.OnTooltipSetItem(tip)
    local n = #tip.lines
    hooks.OnTooltipSetItem(tip)
    check(n > 0 and #tip.lines == n and tip.shown == 1, "tooltips: the lines go in once per showing, read from the item link")
    hooks.OnTooltipCleared(tip)
    tip.lines = {}
    hooks.OnTooltipSetItem(tip)
    check(#tip.lines == n, "tooltips: and again once the tooltip is cleared")
    local cmp = {lines = {}}
    function cmp:AddLine(text) table.insert(self.lines, text) end
    function cmp:GetItem() return tip:GetItem() end
    function cmp:GetName() return "ShoppingTooltip1" end
    hooks.OnTooltipSetItem(cmp)
    check(#cmp.lines == 0, "tooltips: comparison tooltips get nothing")
    _G.GameTooltip = nil
    -- a client that refuses the hook: the addon still loads, without tooltips
    _G.GameTooltip = {HookScript = function() error("no such script") end}
    local ok2, w2 = pcall(NewWorld, {client = "classic", events = CLASSIC_EVENTS, level = 14, db = {setupDone = true, chosen = {Tailoring = true}, show = true}})
    check(ok2 and w2.ns.tooltipAPI == "none", "tooltips: a refused hook leaves the addon running, tooltips off")
    _G.GameTooltip = nil
end

-- the game outranks the route: Bolt of Woolen Cloth is grey for you and
-- Woolen Cape orange, so the window says Woolen Cape - and "Now" is the
-- cape's mats, the bolts and through them the cloth
do
    local w = TooltipWorld({client = "forever", events = FOREVER_EVENTS, level = 14, extra = {{name = "Tailoring", rank = 63, maxRank = 75}},
                            db = {setupDone = true, chosen = {Tailoring = true}, show = true}})
    w.openProf, w.openRank = "Tailoring", 63
    w.recipes = {[2964] = {name = "Bolt of Woolen Cloth", learned = true, relativeDifficulty = 3, canSkillUp = false},
                 [2402] = {name = "Woolen Cape", learned = true, relativeDifficulty = 0, canSkillUp = true}}
    w.Fire("TRADE_SKILL_LIST_UPDATE")
    check(Lines(w, "Tailoring"):find("Craft: Woolen Cape (orange)", 1, true), "tooltips: the window takes the orange recipe over the grey route row")
    check(Tip(w, 2592):find("  Now 63-70 · 0 of ~21 · Woolen Cape (via Bolt of Woolen Cloth)\n  70-100 · 0 of ~90 · Woolen Cape (via Bolt of Woolen Cloth)\n", 1, true),
          "tooltips: and so does the tooltip - now is the cape, through the bolts")
end

-- the trainer moved rows past the rows after them (Woolen Cape to 105,
-- Bolt of Silk Cloth to 115): the window goes bolts until 105, the cape
-- until 110 (where Double-Stitched Woolen Shoulders start) and never
-- shows the silk bolts. The spans follow the window, one after another.
do
    local w = TooltipWorld({client = "forever", events = FOREVER_EVENTS, level = 20, extra = {{name = "Tailoring", rank = 63, maxRank = 150}},
                            db = {setupDone = true, chosen = {Tailoring = true}, show = true,
                                  recipeReq = {Tailoring = {["Woolen Cape"] = 105, ["Bolt of Silk Cloth"] = 115}}}})
    check(Lines(w, "Tailoring"):find("At 105: Woolen Cape", 1, true), "tooltips: the window moves on to the cape at 105")
    local bolt = Tip(w, 2997)
    check(bolt:find("  105-110 · 0 of ~5 · Woolen Cape\n  110-120 · 0 of ~30 · Double-Stitched Woolen Shoulders\n", 1, true),
          "tooltips: the cape for as long as the window shows it (105-110), then the shoulders")
    check(not bolt:find("115", 1, true), "tooltips: no span runs into the next one")
    check(Tip(w, 2592):find("  Now 63-105 · 0 of ~126 · Bolt of Woolen Cloth\n", 1, true) and not Tip(w, 2592):find("Woolen Cape", 1, true),
          "tooltips: now runs to 105 (42 bolts), which cover the cape and the shoulders")
    local spans = w.ns.PlanSpans("Tailoring", w.ns.GetTracked().Tailoring)
    local rows = {}
    for _, sp in ipairs(spans) do rows[#rows + 1] = sp.row[2] .. " " .. sp.from .. "-" .. sp.to end
    check(table.concat(rows, ", "):find("^Bolt of Woolen Cloth 63%-105, Woolen Cape 105%-110, Double%-Stitched Woolen Shoulders 110%-120, Azure Silk Hood 120%-135"),
          "tooltips: the spans in the window's order: " .. table.concat(rows, ", "):sub(1, 120))
end

-- what the hooks saw, in /rxpp status, and /rxpp need <link or ID>: the
-- tooltip's lines in chat, or which professions the plan reads
do
    local w = TooltipWorld({client = "forever", events = FOREVER_EVENTS, level = 14, extra = {{name = "Tailoring", rank = 63, maxRank = 75}},
                            db = {setupDone = true, chosen = {Tailoring = true}, show = true}}, {[2592] = {bags = 25, bank = 15}})
    local shown = 0
    local tip = {lines = {}}
    function tip:AddLine(text) table.insert(self.lines, text) end
    function tip:GetName() return "GameTooltip" end
    function tip:Show() shown = shown + 1 end
    _G.GameTooltip = tip
    w.post[2](tip, {id = 2592})
    w.post[2](tip, {hyperlink = "|cffffffff|Hitem:2997::::::::14:::::|h[Bolt of Woolen Cloth]|h|r"})
    w.post[2](tip, {})
    w.post[2]({GetName = function() return "ShoppingTooltip1" end, AddLine = function() end}, {id = 2592})
    _G.GameTooltip = nil
    check(shown == 2, "tooltips: the tooltip is shown again to fit the new lines (" .. shown .. ")")
    printed = {}
    w.slash("status")
    check(Printed("item tooltips: on through TooltipDataProcessor; 4 item tooltips seen, 3 ours, 1 without an item ID, 2 with lines; last item nil on ShoppingTooltip1"),
          "tooltips: /rxpp status says what the hooks saw: " .. tostring(printed[#printed]))
    printed = {}
    w.slash("need |cffffffff|Hitem:2592::::::::14:::::|h[Wool Cloth]|h|r")
    check(Printed("item 2592:") and Printed("  Now 63-70 · 21 (bags 21) of ~21 · Bolt of Woolen Cloth"), "tooltips: /rxpp need with a link prints the lines")
    printed = {}
    w.slash("need 2771")
    check(Printed("item 2771: the plan names nothing (craft professions picked: Tailoring)"), "tooltips: /rxpp need for an item the plan does not name says what it reads")
end

-- what the professions make from what you gather (Data.lua's REFINE):
-- ore through the bars it smelts into (with Mining picked), cloth through
-- the bolts Forever's route uses without a row for them, hides through
-- the cured hides
do
    local function world(client, profs, chosen, counts)
        local c = {}
        for _, n in ipairs(chosen) do c[n] = true end
        return TooltipWorld({client = client, events = With(client == "forever" and FOREVER_EVENTS or CLASSIC_EVENTS, BANK_EVENTS), level = 40,
                             extra = profs, db = {setupDone = true, chosen = c, show = true}}, counts)
    end
    local w = world("classic", {{name = "Engineering", rank = 30, maxRank = 75}}, {"Engineering", "Mining"})
    check(Tip(w, 2770):find("  Now 30-50 · 0 of ~20 · Handful of Copper Bolts (via Copper Bar)\n", 1, true),
          "refine: Copper Ore through the bars it smelts into")
    check(Tip(w, 2771):find("  105-125 · 0 of ~20 · Bronze Tube (via Bronze Bar)\n", 1, true), "refine: Tin Ore through Bronze Bar, two bars a smelt")
    w.bankVisible = true
    w.counts[2770] = {bags = 0, bank = 12}
    FireInventory(w, "BANKFRAME_OPENED")
    check(w.ns.db.bankSeen[2770] == 12, "refine: the bank count covers ore too")
    check(Tip(world("classic", {{name = "Engineering", rank = 30, maxRank = 75}}, {"Engineering"}), 2770) == "",
          "refine: no Mining picked - ore is not kept for bars")
    local bs = world("classic", {{name = "Blacksmithing", rank = 100, maxRank = 150}}, {"Blacksmithing", "Mining"}, {[2841] = {bags = 10, bank = 0}})
    check(Tip(bs, 2771):find("  105-125 · 0 of ~55 · Rough Bronze Leggings (via Bronze Bar)\n", 1, true),
          "refine: 10 Bronze Bar in the bags come off, two bars a smelt ((120 - 10) / 2)")
    check(Tip(bs, 2838):find("  190-215 · 0 of ~144 · Golden Scale Bracers (via Heavy Grinding Stone)\n", 1, true), "refine: Heavy Stone through the grinding stones")
    local tail = world("forever", {{name = "Tailoring", rank = 165, maxRank = 225}}, {"Tailoring"})
    check(Tip(tail, 4338):find("  170-185 · 0 of ~150 · Black Mageweave Leggings / Black Mageweave Vest (via Bolt of Mageweave)\n", 1, true),
          "refine: Forever's Mageweave Cloth through the bolts its route has no row for (15 x 2 x 5)")
    local lw = world("forever", {{name = "Leatherworking", rank = 110, maxRank = 150}}, {"Leatherworking"})
    check(Tip(lw, 4232):find("  115-137 · 0 of ~22 · Dark Leather Belt (via Cured Medium Hide)\n", 1, true), "refine: Medium Hide through Cured Medium Hide")
    check(Tip(lw, 4289):find("  155-180 · 0 of ~75 · Barbaric Shoulders (via Cured Heavy Hide)\n", 1, true), "refine: three Salt a Cured Heavy Hide")
end

-- a later row of alternatives counts the ones you know: Forever's
-- Tailoring 265 is Runecloth Shoulders (Rugged Leather in it) or
-- Runecloth Headband (none); knowing only the headband, the leather is
-- not kept for 265-300
do
    local function world(known)
        return TooltipWorld({client = "forever", events = FOREVER_EVENTS, level = 55, extra = {{name = "Tailoring", rank = 240, maxRank = 300}},
                             db = {setupDone = true, chosen = {Tailoring = true}, show = true, knownRecipes = known}})
    end
    check(Tip(world(nil), 8170):find("  265-300 · 0 of ~140 · Runecloth Shoulders\n", 1, true), "tooltips: neither known - both alternatives count (35 x 4 leather)")
    local text = Tip(world({Tailoring = {["Runecloth Headband"] = "optimal"}}), 8170)
    check(text:find("  250-265 ", 1, true) and not text:find("265-300", 1, true), "tooltips: the headband known - no leather for 265-300")
    check(Tip(world({Tailoring = {["Runecloth Headband"] = "optimal"}}), 14048):find("  265-300 · 0 of ~140 · Runecloth Headband\n", 1, true),
          "tooltips: and the bolts for the headband alone (35 x 4)")
end

-- the hovered tooltip only: the game's own and the chat link's get the
-- lines; comparison, forbidden and addons' hidden scanning tooltips do not
do
    local w = TooltipWorld({client = "forever", events = FOREVER_EVENTS, level = 14, extra = {{name = "Tailoring", rank = 63, maxRank = 75}},
                            db = {setupDone = true, chosen = {Tailoring = true}, show = true}},
                           {[2592] = {bags = 25, bank = 15}})
    check(Tip(w, 2592, "ItemRefTooltip"):find("Now 63-70", 1, true), "tooltips: a chat link's tooltip gets the lines")
    check(Tip(w, 2592, "ShoppingTooltip1") == "" and Tip(w, 2592, "ItemRefShoppingTooltip1") == "", "tooltips: the comparison tooltips do not")
    check(Tip(w, 2592, "SomeAddonScanningTooltip") == "", "tooltips: nor an addon's hidden scanning tooltip")
    check(Tip(w, 2592, "GameTooltip", true) == "", "tooltips: nor a forbidden one")

    -- the later spans off: what you have against now alone, and an item
    -- needed only later shows nothing (no profession with nothing under it)
    w.slash("tooltip later")
    check(Tip(w, 2592):find("Tailoring\n  Now 63-70 · 21 (bags 21) of ~21 · Bolt of Woolen Cloth\nYou have 40 (bags 25 · bank 15) · ~19 to spare", 1, true),
          "tooltips: later off - now against what you have")
    check(Tip(w, 4306) == "", "tooltips: later off - Silk Cloth, needed only later, shows nothing")
    w.slash("tooltip later")
end

-- the plan is built once and kept while nothing it is built from changes:
-- a hover, a zone change or the window's 15-second refresh does not
-- rebuild it; a skill-up, a trainer visit or a bolt more in the bags does
do
    local tailor = {name = "Tailoring", rank = 63, maxRank = 75}
    local w = TooltipWorld({client = "forever", events = With(FOREVER_EVENTS, BANK_EVENTS), level = 14, extra = {tailor},
                            db = {setupDone = true, chosen = {Tailoring = true}, show = true}},
                           {[2592] = {bags = 25, bank = 15}})
    local builds, real = 0, w.ns.BuildNeedIndex
    w.ns.BuildNeedIndex = function() builds = builds + 1; return real() end
    Tip(w, 2592)
    Tip(w, 2592)
    Tip(w, 4306)
    check(builds == 1, "tooltips: built once for three hovers (" .. builds .. ")")
    w.Fire("ZONE_CHANGED_NEW_AREA")
    for _, t in ipairs(w.timers) do if t[1] == 15 then t[2]() end end
    Tip(w, 2592)
    check(builds == 1, "tooltips: a zone change and the window's refresh leave it (" .. builds .. ")")
    w.counts[2592] = {bags = 30, bank = 15}
    FireInventory(w, "BAG_UPDATE_DELAYED")
    local text = Tip(w, 2592)
    check(builds == 1 and text:find("You have 45 (bags 30 · bank 15)", 1, true), "tooltips: more Wool Cloth is counted without a rebuild")
    w.counts[2997] = {bags = 10, bank = 0}
    text = Tip(w, 2592)
    check(builds == 2 and text:find("  70-100 · 24 (bags 9 · bank 15) of ~39 · Woolen Cape (via Bolt of Woolen Cloth)\n", 1, true), "tooltips: 10 bolts in the bags rebuild it")
    tailor.rank = 64
    w.Fire("SKILL_LINES_CHANGED")
    text = Tip(w, 2592)
    check(builds == 3 and text:find("  Now 64-70 · 18 (bags 18) of ~18 · Bolt of Woolen Cloth\n", 1, true), "tooltips: a skill-up rebuilds it")
    w.trainer = {{"Woolen Cape", "available", "Tailoring", 75}}
    w.Fire("TRAINER_SHOW")
    text = Tip(w, 2592)
    check(builds == 4 and text:find("  Now 64-75 · 33 (bags 30 · bank 3) of ~33 · Bolt of Woolen Cloth\n", 1, true), "tooltips: what a trainer said rebuilds it")
    FireInventory(w, "SPELL_DATA_LOAD_RESULT")
    Tip(w, 2592)
    check(builds == 5, "tooltips: a recipe name the game hands over late rebuilds it (" .. builds .. ")")
end

-- two professions you picked share Wool Cloth: what you have against both
do
    local w = TooltipWorld({client = "forever", events = FOREVER_EVENTS, level = 20,
                            extra = {{name = "Tailoring", rank = 63, maxRank = 75}, {name = "First Aid", rank = 85, maxRank = 150}},
                            db = {setupDone = true, chosen = {Tailoring = true, ["First Aid"] = true}, show = true}},
                           {[2592] = {bags = 40, bank = 20}})
    local text = Tip(w, 2592)
    check(text:find("RXP Professions\nFirst Aid\n  Now 85-115 · 30 (bags 30) of ~30 · Wool Bandage\n  115-150 · 9 (bank 9) of ~70 · Heavy Wool Bandage\n" ..
                        "Tailoring\n  Now 63-70 · 21 (bags 10 · bank 11) of ~21", 1, true),
          "tooltips: two professions, each with its spans; both spans you are in get theirs first, then the rest top down")
    check(text:find("You have 60 (bags 40 · bank 20) · ~220 short", 1, true), "tooltips: two professions - the total over both")
    w.counts[2592] = {bags = 45, bank = 0}
    check(Tip(w, 2592):find("  Now 63-70 · 15 (bags 15) of ~21", 1, true), "tooltips: two professions - short for now")
end

-- Forever's Leatherworking uses Elixir of Defense, which Alchemy makes on
-- its own route: with both picked, the elixirs Alchemy makes go first, and
-- only the rest counts its herbs again
do
    local w = TooltipWorld({client = "forever", events = FOREVER_EVENTS, level = 40,
                            extra = {{name = "Alchemy", rank = 200, maxRank = 225}, {name = "Leatherworking", rank = 200, maxRank = 225}},
                            db = {setupDone = true, chosen = {Alchemy = true, Leatherworking = true}, show = true}})
    check(Tip(w, 3355):find("Alchemy\n  210-230 · 0 of ~20 · Elixir of Defense\nLeatherworking\n  210-235 · 0 of ~5 · Thick Leather Ammo Pouch (via Elixir of Defense)\n", 1, true),
          "tooltips: 25 elixirs for the ammo pouches, 20 of them from Alchemy's span")
    check(Tip(w, 8951):find("Leatherworking\n  210-235 · 0 of ~25 · Thick Leather Ammo Pouch\n", 1, true), "tooltips: the elixir itself, all 25")
    local lw = TooltipWorld({client = "forever", events = FOREVER_EVENTS, level = 40,
                             extra = {{name = "Alchemy", rank = 200, maxRank = 225}, {name = "Leatherworking", rank = 200, maxRank = 225}},
                             db = {setupDone = true, chosen = {Leatherworking = true}, show = true}})
    check(Tip(lw, 3355) == "" and Tip(lw, 8951):find("of ~25 · Thick Leather Ammo Pouch", 1, true),
          "tooltips: Alchemy not picked - the elixir is bought, its herbs are not counted")
end

-- the bank: the interaction manager's banker opens it (a merchant does
-- not), what moves there is counted, and a close after the client dropped
-- the contents wipes nothing
do
    local w = TooltipWorld({client = "forever", events = With(FOREVER_EVENTS, BANK_EVENTS), level = 14, extra = {{name = "Tailoring", rank = 63, maxRank = 75}},
                            db = {setupDone = true, chosen = {Tailoring = true}, show = true}},
                           {[2592] = {bags = 5, bank = 20}})
    FireInventory(w, "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 5)
    check(not w.ns.bankOpen, "tooltips: a merchant is not the bank")
    FireInventory(w, "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 8)
    check(w.ns.bankOpen and w.ns.db.bankSeen[2592] == 20, "tooltips: the banker opens it, and it is counted")
    w.counts[2592] = {bags = 25, bank = 0}
    for _ = 1, 5 do FireInventory(w, "BAG_UPDATE_DELAYED") end
    check(w.ns.db.bankSeen[2592] == 20 and RunSoon(w) == 2 and w.ns.db.bankSeen[2592] == nil,
          "tooltips: what you take out at the bank is counted out, once a moment later however many events come")
    FireInventory(w, "PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 8)
    w.bankVisible = false
    check(not w.ns.bankOpen and Tip(w, 2592):find("You have 25 (bags 25 · bank 0)", 1, true), "tooltips: and stays out after")
    w.bankVisible = true
    FireInventory(w, "BANKFRAME_OPENED")
    w.counts[2592] = {bags = 15, bank = 10}
    FireInventory(w, "PLAYERBANKSLOTS_CHANGED")
    RunSoon(w)
    w.bankVisible = false
    FireInventory(w, "BANKFRAME_CLOSED")
    check(w.ns.db.bankSeen[2592] == 10 and Tip(w, 2592):find("You have 25 (bags 15 · bank 10) · ~155 short\n(bank as counted at your last visit)", 1, true),
          "tooltips: a close the client sees nothing at keeps the count")
    w.bankVisible = true
    check(Tip(w, 2592):find("You have 25 (bags 15 · bank 10) · ~155 short", 1, true) and not Tip(w, 2592):find("last visit", 1, true),
          "tooltips: a client that sees the closed bank is read as it is")
    -- and from then on its own count stands, none included: a client that
    -- crafts from the bank takes things out of it while it is closed
    w.counts[2592] = {bags = 15, bank = 0}
    check(Tip(w, 2592):find("You have 15 (bags 15 · bank 0) · ~165 short", 1, true) and not Tip(w, 2592):find("last visit", 1, true),
          "tooltips: once the closed bank has been seen, the client's count stands")
    FireInventory(w, "BANKFRAME_OPENED")
    FireInventory(w, "PLAYER_ENTERING_WORLD")
    check(not w.ns.bankOpen, "tooltips: a loading screen ends a visit whose close was missed")
end

-- the tooltips in every translated language: each of their sentences
-- translated, and every translation (theirs and the window's) keeps its
-- key's %d / %s in the same order, which string.format needs
do
    local keys = {"Now %d-%d · %d (%s) of ~%d · %s", "%d-%d · %d (%s) of ~%d · %s", "Now %d-%d · %d of ~%d · %s",
                  "%d-%d · %d of ~%d · %s", "Now %d-%d · ~%d · %s", "%d-%d · ~%d · %s", "%s (via %s)", "bags %d · bank %d",
                  "bags %d", "bank %d", "+1 more span · %d of ~%d", "+%d more spans · %d of ~%d", "+1 more span · ~%d",
                  "+%d more spans · ~%d", "You have %d (bags %d · bank %d) · ~%d to spare", "You have %d (bags %d · bank %d) · ~%d short",
                  "You have %d (bags %d · bank %d) · just enough", "(bank as counted at your last visit)", "%s (not learned yet)",
                  "Other professions (not in your setup)", "item tooltips on", "item tooltips off",
                  "item tooltips show the spans after the one you are in", "item tooltips show only the span you are in",
                  "item tooltips also show the professions you did not pick, apart", "item tooltips show only the professions you picked",
                  "item tooltips: |cFFFFCC00/rxpp tooltip|r on or off, |cFFFFCC00/rxpp tooltip later|r the spans after the one you are in, |cFFFFCC00/rxpp tooltip others|r the professions you did not pick"}
    local function specs(text)
        local out = {}
        for sp in text:gsub("%%%%", ""):gmatch("%%[%-%d%.]*[dsfx]") do out[#out + 1] = sp end
        return table.concat(out, " ")
    end
    local missing, mismatched, entries = {}, {}, 0
    for _, locale in ipairs({"frFR", "deDE", "esES", "esMX", "ptBR", "itIT", "ruRU", "koKR", "zhCN", "zhTW"}) do
        local w = NewWorld({client = "classic", locale = locale, events = CLASSIC_EVENTS, db = {setupDone = true, chosen = {Mining = true}, show = true}})
        for _, k in ipairs(keys) do
            if rawget(w.ns.L, k) == nil then missing[#missing + 1] = locale .. ": " .. k end
        end
        for k, v in pairs(w.ns.L) do
            entries = entries + 1
            if specs(k) ~= specs(v) then mismatched[#mismatched + 1] = locale .. ": " .. k end
        end
    end
    check(#missing == 0, "tooltips: every tooltip sentence is translated (" .. (missing[1] or "all") .. ")")
    check(#mismatched == 0 and entries > 1000, ("tooltips: %d translations keep their %%d / %%s (%s)"):format(entries, mismatched[1] or "all"))
    local fr = TooltipWorld({client = "forever", locale = "frFR", events = FOREVER_EVENTS, level = 14, extra = {{name = "Tailoring", rank = 63, maxRank = 75}},
                             db = {setupDone = true, chosen = {Tailoring = true}, show = true}},
                            {[2592] = {bags = 25, bank = 15}})
    check(Tip(fr, 2592):find("  Maintenant 63-70 · 21 (sacs 21) sur ~21 · Bolt of Woolen Cloth\n", 1, true) and
              Tip(fr, 2592):find("Vous en avez 40 (sacs 25 · banque 15) · il en manque ~140", 1, true),
          "tooltips: in French")
end

-- every craft profession, every 25 skill, on Classic Era, TBC and Forever:
-- the index builds without an error, every span runs forward with
-- something in it, and every item's lines come out
do
    local profs = {"Alchemy", "Blacksmithing", "Enchanting", "Engineering", "Leatherworking", "Tailoring", "First Aid", "Cooking"}
    local clients = {{"classic", CLASSIC_EVENTS}, {"tbc", CLASSIC_EVENTS}, {"forever", FOREVER_EVENTS}}
    local built, bad, items = 0, 0, 0
    for _, client in ipairs(clients) do
        for _, prof in ipairs(profs) do
            for rank = 1, 300, 25 do
                local maxRank = rank < 75 and 75 or rank < 150 and 150 or rank < 225 and 225 or 300
                local w = TooltipWorld({client = client[1], events = client[2], level = 60, extra = {{name = prof, rank = rank, maxRank = maxRank}},
                                        db = {setupDone = true, chosen = {[prof] = true}, show = true, tooltipOthers = true}})
                local index = w.ns.BuildNeedIndex()
                built = built + 1
                if w.ns.lastError then
                    bad = bad + 1
                    realPrint("index: " .. client[1] .. " " .. prof .. " " .. rank .. ": " .. tostring(w.ns.lastError))
                end
                for id, entries in pairs(index) do
                    items = items + 1
                    for _, e in ipairs(entries) do
                        if not (e.to > e.from and e.need > 0 and e.need == math.floor(e.need)) then bad = bad + 1 end
                    end
                    local ok, lines = pcall(w.ns.TooltipLines, id)
                    if not ok or #lines == 0 then
                        bad = bad + 1
                        realPrint("lines: " .. client[1] .. " " .. prof .. " " .. rank .. " item " .. id .. ": " .. tostring(lines))
                    end
                end
            end
        end
    end
    check(built == 3 * 8 * 12 and items > 1000 and bad == 0,
          ("tooltips: every craft profession every 25 skill on three clients - %d plans, %d item tooltips, %d problems"):format(built, items, bad))
end

-- the same sweep with a trainer that moved rows (about a third of them,
-- by 1-60 points; random, the same every run): the spans never overlap,
-- run to the route's end, and each is the row the window shows from its
-- first skill to its last - "now" the row the window says to craft
do
    local profs = {"Alchemy", "Blacksmithing", "Enchanting", "Engineering", "Leatherworking", "Tailoring", "First Aid", "Cooking"}
    local clients = {{"classic", CLASSIC_EVENTS}, {"tbc", CLASSIC_EVENTS}, {"forever", FOREVER_EVENTS}}
    math.randomseed(2392)
    local plans, spansSeen, bad = 0, 0, 0
    local function Bad(what)
        bad = bad + 1
        if bad <= 10 then realPrint("trainer sweep: " .. what) end
    end
    for _, client in ipairs(clients) do
        for _, prof in ipairs(profs) do
            for rank = 1, 300, 25 do
                local maxRank = rank < 75 and 75 or rank < 150 and 150 or rank < 225 and 225 or 300
                local w = TooltipWorld({client = client[1], events = client[2], level = 60, extra = {{name = prof, rank = rank, maxRank = maxRank}},
                                        db = {setupDone = true, chosen = {[prof] = true}, show = true}})
                local ns = w.ns
                local req = {}
                for _, row in ipairs(ns.RoutePosition(prof, {rank = 1}).route) do
                    if math.random() < 0.35 then
                        local need = row[1] + math.random(1, 60)
                        for _, alt in ipairs(ns.RowAlts(row)) do req[alt] = need end
                    end
                end
                ns.db.recipeReq = {[prof] = req}
                ns.dataVersion = (ns.dataVersion or 0) + 1
                local p = ns.GetTracked()[prof]
                local where = client[1] .. " " .. prof .. " " .. rank
                local spans = ns.IsFinalCap(p) and {} or ns.PlanSpans(prof, p)
                plans = plans + 1
                local prevTo
                for _, sp in ipairs(spans) do
                    spansSeen = spansSeen + 1
                    if prevTo and sp.from < prevTo then Bad(where .. ": " .. sp.from .. " starts before " .. prevTo) end
                    local last = ns.RoutePosition(prof, {rank = sp.to - 1}).current
                    if sp.now then
                        local pos = ns.RoutePosition(prof, p)
                        local craft = ns.CraftNow(prof, p, pos.current)
                        if sp.row ~= (craft.takeBest and craft.bestRow or pos.current) then Bad(where .. ": now is not the window's row") end
                        if last ~= pos.current then Bad(where .. ": the window moves on before now ends at " .. sp.to) end
                    else
                        local first = ns.RoutePosition(prof, {rank = sp.from}).current
                        if first ~= sp.row or last ~= sp.row then
                            Bad(("%s: %d-%d %s, the window shows %s / %s"):format(where, sp.from, sp.to, sp.row[2], first and first[2] or "-", last and last[2] or "-"))
                        end
                    end
                    prevTo = sp.to
                end
                if #spans > 0 and spans[#spans].to ~= 300 then Bad(where .. ": the last span ends at " .. spans[#spans].to) end
                local index = ns.BuildNeedIndex()
                if ns.lastError then Bad(where .. ": " .. tostring(ns.lastError)) end
                for id in pairs(index) do
                    local ok, lines = pcall(ns.TooltipLines, id)
                    if not ok or #lines == 0 then Bad(where .. " item " .. id .. ": " .. tostring(lines)) end
                end
            end
        end
    end
    check(plans == 3 * 8 * 12 and spansSeen > 1500 and bad == 0,
          ("tooltips: with a trainer that moved rows - %d plans, %d spans, %d problems"):format(plans, spansSeen, bad))
end

realPrint(("RestedXP Professions harness: %d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
