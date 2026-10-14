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
    for _, f in ipairs({"Locales.lua", "Data.lua", "Core.lua", "UI.lua"}) do
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
end

-- a client with no skill API at all: nothing tracked, nothing thrown
do
    local w = NewWorld({client = "none", events = FOREVER_EVENTS, db = {setupDone = true, chosen = {Mining = true}, show = true}})
    local ok = pcall(w.Fire, "PLAYER_ENTERING_WORLD")
    check(ok and next(w.ns.profs) == nil and w.ns.skillAPI == "none", "no skill API: tracks nothing, no error")
end

realPrint(("RestedXP Professions harness: %d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
