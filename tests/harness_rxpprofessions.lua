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
                        "GetCraftDisplaySkillLine", "GetNumCrafts", "GetCraftInfo", "LibStub", "RXPProfessionsDB", "GetBuildInfo"}) do
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
    _G.UnitFactionGroup = function() return "Alliance" end
    _G.UnitRace = function() return "Human", "Human" end
    _G.GetRealZoneText = function() return opts.zone or "Elwynn Forest" end
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
    -- the game build: a new one starts recipe colours afresh
    w.build = opts.build or "61582"
    -- Forever reports toc 16001; the routes pick its recipe names and mats from that
    local toc = opts.client == "forever" and 16001 or opts.client == "tbc" and 20505 or 11508
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
    if opts.client == "classic" or opts.client == "tbc" then
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
                return {name = l.name, isHeader = l.header or false, isCollapsed = l.header and l.folded or false, rank = l.rank, maxRank = l.maxRank, parentSkillLineID = 0}
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
        -- professionName. GetFilteredRecipeIDs is learned-only on Forever.
        local function ids(all)
            local out = {}
            for id, r in pairs(w.recipes) do if all or r.learned then out[#out + 1] = id end end
            table.sort(out)
            return out
        end
        _G.C_TradeSkillUI = {
            GetChildProfessionInfo = function()
                if w.noChild then return {professionID = 0, professionName = "", skillLevel = 0, maxSkillLevel = 0} end
                return {professionID = 2540, professionName = w.childName or w.openProf or "Cooking", parentProfessionName = w.openProf or "Cooking",
                        skillLevel = w.openRank or 20, maxSkillLevel = 75}
            end,
            GetBaseProfessionInfo = function()
                return {professionID = 185, professionName = w.openProf or "Cooking", skillLevel = w.openRank or 20, maxSkillLevel = 75}
            end,
            GetFilteredRecipeIDs = function() return ids(false) end,
            GetRecipeInfo = function(id) return w.recipes[id] end,
            IsTradeSkillReady = function() return not w.notReady end,
            IsDataSourceChanging = function() return w.changing or false end,
            IsTradeSkillLinked = function() return w.linked or false end,
            IsTradeSkillGuild = function() return false end,
            IsNPCCrafting = function() return false end
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
    for _, f in ipairs({"Data.lua", "Core.lua", "UI.lua"}) do
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
                        "TRADE_SKILL_SHOW", "TRADE_SKILL_UPDATE", "CRAFT_SHOW", "CRAFT_UPDATE", "TRAINER_SHOW", "TRAINER_UPDATE"}
-- Forever: retail's trade skill events, no TRADE_SKILL_UPDATE, no CRAFT_*
local FOREVER_EVENTS = {"PLAYER_ENTERING_WORLD", "SKILL_LINES_CHANGED", "CHAT_MSG_SKILL", "ZONE_CHANGED_NEW_AREA",
                        "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_DATA_SOURCE_CHANGED", "TRADE_SKILL_CLOSE",
                        "TRAINER_SHOW", "TRAINER_UPDATE"}

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
    check(text:find("Craft: Linen Bag (orange)", 1, true) and text:find("Mats: 3 Bolt of Linen + Coarse Thread", 1, true) and not text:find("game moved it", 1, true),
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
    check(text:find("Craft: Enchant Cloak - Minor Resistance (orange)", 1, true) and text:find("(Enchant Bracers - Minor Stamina is grey for you now", 1, true),
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
    check(known and known["Simple Kilt"] == "optimal" and known["Linen Bag"] == "trivial" and not known["Reinforced Linen Cape"] and w.ns.recipeAPI == "GetFilteredRecipeIDs",
          "forever: recipes read through GetFilteredRecipeIDs; one that can't skill up counts as grey")
    -- the player ticks "skill-ups only": the list shrinks, nothing known is forgotten
    w.recipes[1].learned, w.recipes[2].learned = false, false
    w.Fire("TRADE_SKILL_LIST_UPDATE")
    known = w.ns.GetKnownRecipes("Tailoring")
    check(known["Linen Bag"] and known["Bolt of Linen Cloth"] and known["Simple Kilt"], "forever: a filtered list adds to the known recipes, never replaces them")
    -- a window still loading says skill 0: not a profession learned afresh
    w.openRank = 0
    w.Fire("TRADE_SKILL_LIST_UPDATE")
    check(w.ns.GetKnownRecipes("Tailoring")["Linen Bag"] and w.ns.db.recipeRank.Tailoring == 63, "forever: a window reading skill 0 while it loads does not start the list over")
    w.openRank = 63
    w.recipes[1].learned, w.recipes[2].learned = true, true
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
    check(Printed("(last through GetFilteredRecipeIDs)"), "forever: /rxpp status names the recipe API")
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

-- Forever's own recipe names and mats, read from Wowhead's Forever data:
-- Enchant Bracer - Minor Health is "Inferior Stamina" there and takes a
-- Mote of Magic; Elixir of Greater Defense is "Elixir of Defense"
do
    local function lines(w, prof)
        local out = {}
        for _, l in ipairs(w.ns.BuildProfLines(prof, w.ns.GetTracked()[prof])) do out[#out + 1] = l.text end
        return table.concat(out, "\n")
    end
    local f = NewWorld({client = "forever", events = FOREVER_EVENTS, extra = {{name = "Enchanting", rank = 10, maxRank = 75}, {name = "Alchemy", rank = 212, maxRank = 225}},
                        db = {setupDone = true, chosen = {Enchanting = true, Alchemy = true}, show = true}})
    f.Fire("PLAYER_ENTERING_WORLD")
    local text = lines(f, "Enchanting")
    check(f.ns.IS_FOREVER and text:find("Craft: Enchant Bracer - Inferior Stamina", 1, true) and text:find("Mats: 1 Mote of Magic", 1, true) and text:find("At 50: Enchant Bracer - Minor Deflect", 1, true),
          "forever names: the route uses Forever's recipe name and mats")
    check(lines(f, "Alchemy"):find("Craft: Elixir of Defense", 1, true) and lines(f, "Alchemy"):find("(makes 2)", 1, true), "forever names: Alchemy too")
    local c = NewWorld({client = "classic", events = CLASSIC_EVENTS, extra = {{name = "Enchanting", rank = 52, maxRank = 75}},
                        db = {setupDone = true, chosen = {Enchanting = true}, show = true}})
    c.Fire("PLAYER_ENTERING_WORLD")
    c.craft = {"Enchanting", 52, {{"Enchant Bracer - Minor Deflect", "optimal"}, {"Enchant Bracer - Minor Health", "easy"}}}
    c.Fire("CRAFT_SHOW")
    text = lines(c, "Enchanting")
    check(not c.ns.IS_FOREVER and text:find("Craft: Enchant Bracer - Minor Deflect (orange)", 1, true) and text:find("Mats: 1 Lesser Magic Essence + 1 Strange Dust", 1, true) and not text:find("know this recipe", 1, true),
          "classic names: 'Minor Deflect' (the game's name) now matches the known recipe, with Classic's mats")
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
