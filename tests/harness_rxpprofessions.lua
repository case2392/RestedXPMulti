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
                        "GetCraftDisplaySkillLine", "GetNumCrafts", "GetCraftInfo", "LibStub", "RXPProfessionsDB"}) do
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
    local function expand(i) local l = visible()[i]; assert(l and l.header, "expand on a non-header"); l.folded = false; w.expands = w.expands + 1 end
    local function collapse(i) local l = visible()[i]; assert(l and l.header, "collapse on a non-header"); l.folded = true; w.collapses = w.collapses + 1 end
    -- the classic profession window (w.trade = {prof, {{name, difficulty}, ...}})
    -- and trainer window (w.trainer = {{name, category, skill, level}, ...})
    w.trade, w.trainer = nil, {}
    _G.GetNumTrainerServices = function() return #w.trainer end
    _G.GetTrainerServiceInfo = function(i) local t = w.trainer[i]; return t[1], "", t[2], false end
    _G.GetTrainerServiceSkillReq = function(i) local t = w.trainer[i]; return t[3], t[4] end
    if opts.client == "classic" then
        _G.GetTradeSkillLine = function() return w.trade and w.trade[1] or "UNKNOWN" end
        _G.GetNumTradeSkills = function() return w.trade and #w.trade[2] or 0 end
        _G.GetTradeSkillInfo = function(i) local r = w.trade[2][i]; return r[1], r[2] end
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
                if id == 7 then return "Mining", 1, 45, 75 end
                if id == 12 then return "Cooking", 1, 20, 75 end
            end
        end
        w.recipes = {}
        _G.C_TradeSkillUI = {
            GetChildProfessionInfo = function() return {professionName = w.openProf or "Cooking", skillLevel = 20, maxSkillLevel = 75} end,
            GetAllRecipeIDs = function() local ids = {}; for id in pairs(w.recipes) do ids[#ids + 1] = id end; table.sort(ids); return ids end,
            GetRecipeInfo = function(id) return w.recipes[id] end
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
                        "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_CLOSE", "TRAINER_SHOW", "TRAINER_UPDATE"}

--------------------------------------------------------------------------
-- Classic Era: as before
--------------------------------------------------------------------------
do
    local ok, w = pcall(NewWorld, {client = "classic", events = CLASSIC_EVENTS, db = {setupDone = true, chosen = {Mining = true, Cooking = true}, show = true}})
    check(ok, "classic: loads")
    check(#w.ns.missingEvents == 1 and w.ns.missingEvents[1] == "TRADE_SKILL_LIST_UPDATE", "classic: only retail's list event is missing here, and it is skipped")
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
    check(wp.ns.profs.Mining.rank == 45 and wp.ns.profs.Cooking.rank == 20 and wp.ns.skillAPI == "GetProfessions + C_SkillInfo", "forever: GetProfessions and C_SkillInfo both read, results merged")
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
    check(text:find("Craft: Embossed Leather Gloves", 1, true) and text:find("Learn it at 55 from your trainer", 1, true) == nil and text:find("You don't know this recipe yet!", 1, true) and text:find("Meanwhile: Handstitched Leather Boots (still skills up)", 1, true), "leatherworking: at 56 the gloves are due, unknown, and the orange boots offered meanwhile")
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
