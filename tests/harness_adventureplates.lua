-- Offline harness for Adventure Plates (Lua 5.1).   lua5.1 tests/harness_adventureplates.lua .
local root = arg and arg[1] or "."
local realPrint = print
local passed, failed = 0, 0
local function check(cond, label)
    if cond then passed = passed + 1 else failed = failed + 1; realPrint("FAIL: " .. label) end
end

local printed, sent, timers
local function Printed(pat)
    for _, l in ipairs(printed) do if l:find(pat, 1, true) then return true end end
    return false
end

-- a widget that records what matters and shrugs at the rest
local function Widget(kind)
    local f = {kind = kind, children = {}, shown = true, alpha = 1}
    local self = f
    function f:SetScript(k, fn) self.scripts = self.scripts or {}; self.scripts[k] = fn end
    function f:GetScript(k) return self.scripts and self.scripts[k] end
    function f:SetText(v) self.text = v end
    function f:GetText() return self.text end
    function f:SetTextColor(...) self.color = {...} end
    function f:SetColorTexture(...) self.color = {...} end
    function f:SetTexture(t) self.texture = t end
    function f:SetTexCoord(...) self.coords = {...} end
    function f:SetPoint(...) self.anchors = self.anchors or {}; table.insert(self.anchors, {...}) end
    function f:ClearAllPoints() self.anchors = {} end
    function f:SetSize(w, h) self.width, self.height = w, h end
    function f:SetWidth(w) self.width = w end
    function f:SetHeight(h) self.height = h end
    function f:Show() self.shown = true; if self.scripts and self.scripts.OnShow then self.scripts.OnShow(self) end end
    function f:Hide() self.shown = false end
    function f:IsShown() return self.shown end
    function f:SetChecked(v) self.checked = v and true or false end
    function f:GetChecked() return self.checked end
    function f:Click() self.checked = not self.checked; if self.scripts and self.scripts.OnClick then self.scripts.OnClick(self) end end
    function f:Press() if self.scripts and self.scripts.OnClick then self.scripts.OnClick(self) end end
    function f:Type(t) self.text = t; if self.scripts and self.scripts.OnTextChanged then self.scripts.OnTextChanged(self) end end
    function f:CreateFontString() local r = Widget("FontString"); table.insert(self.children, r); return r end
    function f:CreateTexture() local r = Widget("Texture"); table.insert(self.children, r); return r end
    function f:GetFrameLevel() return 1 end
    function f:GetEffectiveScale() return 1 end
    function f:GetCenter() return 100, 100 end
    function f:SetFacing(v) self.facing = v end
    function f:SetCamDistanceScale(v) self.zoom = v end
    function f:SetUnit(u) if u == "badunit" then error("bad unit") end self.unit = u end
    -- the metatable answers any capitalised key with a no-op, so these must not read through it
    function f:SetNormalTexture(t) local r = rawget(self, "NormalTexture") or Widget("Texture"); r.texture = t; rawset(self, "NormalTexture", r) end
    function f:SetPushedTexture(t) local r = rawget(self, "PushedTexture") or Widget("Texture"); r.texture = t; rawset(self, "PushedTexture", r) end
    function f:SetHighlightTexture(t) local r = rawget(self, "HighlightTexture") or Widget("Texture"); r.texture = t; rawset(self, "HighlightTexture", r) end
    function f:SetMaxLetters(n) self.maxLetters = n end
    function f:Enable() self.enabled = true end
    function f:Disable() self.enabled = false end
    function f:IsEnabled() return self.enabled ~= false end
    function f:RegisterEvent(e) self.events = self.events or {}; self.events[e] = true end
    setmetatable(f, {__index = function(_, k)
        if type(k) == "string" and k:match("^[A-Z]") then return function() end end
    end})
    return f
end

local function NewWorld(opts)
    opts = opts or {}
    printed, sent, timers = {}, {}, {}
    _G.print = function(...) local t = {} for i = 1, select("#", ...) do t[i] = tostring(select(i, ...)) end table.insert(printed, table.concat(t, " ")) end
    _G.AdventurePlatesDB = opts.db or (not opts.firstRun and {settings = {welcomed = true}} or nil)
    _G.CreateFrame = function(kind, name, parent, template)
        local f = Widget(kind)
        f.name, f.template, f.parent = name, template, parent
        if parent and parent.children then table.insert(parent.children, f) end
        if template == "Missing" then error("template missing") end
        return f
    end
    _G.UIParent = Widget("Frame")
    _G.Minimap = Widget("Minimap")
    _G.UISpecialFrames = {}
    _G.GetCursorPosition = function() return opts.cursorX or 0, opts.cursorY or 0 end
    _G.GetBuildInfo = function() return "1.60.1", "69913", "Sep 17 2026", 16001 end
    _G.SetPortraitTexture = function(tex, unit) tex.portraitUnit = unit end
    _G.GetFileIDFromPath = function(p) if p:find("Spellbook") or p:find("Rotation") or p:find("Minimap") then return 136000 end end
    _G.BackdropTemplateMixin = {}
    _G.GameTooltip = Widget("GameTooltip")
    _G.Settings = {
        RegisterCanvasLayoutCategory = function(frame, name) return {ID = "cat_" .. name, frame = frame} end,
        RegisterAddOnCategory = function(cat) _G.__registeredCategory = cat end,
        OpenToCategory = function(id) _G.__openedCategory = id end
    }
    _G.SlashCmdList = {}
    _G.C_Timer = {After = function(s, fn) table.insert(timers, {s, fn}) end}
    _G.GetTime = function() return opts.now or 1000 end
    _G.time = function() return 1700000000 end
    _G.date = function(fmt, t) return "01 Jan 12:00" end
    _G.UnitName = function(u)
        if u == "player" then return "Siggy" end
        if u == "target" then return opts.target, opts.targetRealm end
        local i = u:match("^party(%d)$")
        if i and opts.party and opts.party[tonumber(i)] then
            local full = opts.party[tonumber(i)]
            local name, realm = full:match("^([^%-]+)%-?(.*)$")
            return name, realm ~= "" and realm or nil
        end
        return nil
    end
    _G.UnitExists = function(u) return u == "target" and opts.target ~= nil end
    _G.UnitIsPlayer = function(u) return u == "target" and opts.target ~= nil end
    _G.UnitLevel = function() return 14 end
    _G.UnitRace = function() return "Night Elf", "NightElf" end
    _G.UnitClass = function() return "Druid", "DRUID", 11 end
    _G.UnitFactionGroup = function() return "Alliance", "Alliance" end
    _G.GetGuildInfo = function() if opts.guildName then return opts.guildName, opts.guildRank or "Member", 2 end end
    _G.GetCurrentTitle = function() return opts.titleID or 0 end
    _G.GetTitleName = function(id) if id == 5 then return "the Explorer " end end
    _G.GetNormalizedRealmName = function() return "Firemaw" end
    _G.GetRealmName = function() return "Firemaw" end
    _G.GetGameTime = function() return opts.hour or 20, 15 end
    _G.C_DateAndTime = {GetCurrentCalendarTime = function() return {weekday = opts.weekday or 3} end}
    _G.RAID_CLASS_COLORS = {DRUID = {r = 1, g = 0.49, b = 0.04}, HUNTER = {r = 0.67, g = 0.83, b = 0.45}}
    _G.CLASS_ICON_TCOORDS = {DRUID = {0.75, 1, 0, 0.25}, HUNTER = {0, 0.25, 0.25, 0.5}}
    _G.C_ChatInfo = {
        RegisterAddonMessagePrefix = function(p) _G.__prefix = p; return true end,
        SendAddonMessage = function(prefix, text, kind, target)
            if opts.commDown then error("comm down") end
            table.insert(sent, {prefix = prefix, text = text, kind = kind, target = target})
        end
    }
    _G.GetNumGroupMembers = function() return opts.party and #opts.party or 0 end
    _G.IsInRaid = function() return false end
    _G.IsInGuild = function() return opts.guild ~= nil end
    _G.GetNumGuildMembers = function() return opts.guild and #opts.guild or 0 end
    _G.GetGuildRosterInfo = function(i) return opts.guild[i] end
    _G.C_FriendList = {
        GetNumFriends = function() return opts.friends and #opts.friends or 0 end,
        GetFriendInfoByIndex = function(i) return {name = opts.friends[i]} end
    }
    -- professions: retail's API when opts.profs is given, Era's skill lines when opts.skills is
    _G.GetProfessions = opts.profs and function() return opts.profs[1] and 1 or nil, opts.profs[2] and 2 or nil end or nil
    _G.GetProfessionInfo = opts.profs and function(i) local p = opts.profs[i]; if p then return p[1], "icon", p[2], p[3] end end or nil
    _G.GetNumSkillLines = opts.skills and function() return #opts.skills end or nil
    _G.GetSkillLineInfo = opts.skills and function(i) local k = opts.skills[i]; return k[1], k[2] or false, false, k[3] or 0, 0, 0, k[4] or 0 end or nil
    -- chat: filters, the link handler and the edit box
    _G.__filters = {}
    _G.ChatFrame_AddMessageEventFilter = function(e, fn) _G.__filters[e] = fn end
    _G.SetItemRef = function() end
    _G.hooksecurefunc = function(name, fn) local orig = _G[name]; _G[name] = function(...) orig(...); fn(...) end end
    -- current clients send "addon:" links through LinkUtil, which fires this event and never calls SetItemRef
    _G.EventRegistry = {callbacks = {}}
    function _G.EventRegistry:RegisterCallback(event, fn, owner) self.callbacks[event] = fn end
    function _G.EventRegistry:TriggerEvent(event, ...) local fn = self.callbacks[event]; if fn then fn(nil, ...) end end
    _G.__clock = 0
    _G.GetTime = function() return _G.__clock end
    _G.__chat = {}
    _G.ChatEdit_GetActiveWindow = function() return opts.chatOpen and {} or nil end
    _G.ChatEdit_InsertLink = function(t) _G.__chat.inserted = t; return true end
    _G.ChatFrame_OpenChat = function(t) _G.__chat.opened = t end
    _G.__menus = {}
    local menus = _G.__menus
    _G.Menu = opts.noMenu and nil or {
        ModifyMenu = function(tag, fn) menus[tag] = fn end
    }
    local ns = {}
    for _, f in ipairs({"Core.lua", "Era.lua", "Comm.lua", "Report.lua", "UI.lua", "Options.lua"}) do
        local chunk = assert(loadfile(root .. "/AdventurePlates/" .. f))
        chunk("AdventurePlates", ns)
    end
    ns.OnEvent("ADDON_LOADED", "AdventurePlates")
    ns.OnEvent("PLAYER_LOGIN")
    local slash = SlashCmdList["ADVENTUREPLATES"]
    ns.slash = function(s) slash(s) end
    return ns
end

local function RunTimers() local t = timers; timers = {}; for _, x in ipairs(t) do x[2]() end end

-- 1. defaults, the plate and what the client says about the character
do
    local ns = NewWorld({guildName = "Lotion Appreciation Club", guildRank = "Gold Member", titleID = 5})
    check(_G.AdventurePlatesDB ~= nil and ns.db.settings.share == "everyone" and ns.db.settings.menu == true and ns.db.settings.minimap == true, "defaults: saved variables made, sharing on, menu on, minimap button on")
    check(_G.__prefix == "ADVPLATE" and SlashCmdList.ADVENTUREPLATES ~= nil and _G.__registeredCategory ~= nil, "defaults: prefix registered, slash and options in place")
    local p = ns.MyPlate()
    check(ns.CharKey() == "Siggy-Firemaw" and ns.db.plates["Siggy-Firemaw"] == p, "plate: one plate per character on the account")
    check(p.name == "Siggy" and p.realm == "Firemaw" and p.level == 14 and p.race == "Night Elf" and p.class == "Druid" and p.classFile == "DRUID" and p.guild == "Lotion Appreciation Club" and p.rank == "Gold Member" and p.gameTitle == "the Explorer" and p.faction == "Alliance", "plate: the character's facts read from the client")
    check(p.title == "" and #p.tags == 0 and p.weekdays == string.rep("0", 24) and p.motto == "", "plate: nothing filled in yet")
    check(ns.Sanitize("|cffff0000hi|r |Hitem:1|h[x]|h\n bye  ", 6) == "cffff0", "sanitize: link and colour codes stripped, control characters spaced, length capped")
    check(ns.CleanHours("11x1") == "1101" .. string.rep("0", 20) and #ns.CleanHours(nil) == 24 and #ns.CleanHours(string.rep("1", 30)) == 24, "hours: always 24 of 0 or 1")
    local c = ns.CleanPlate({title = "The |cffExplorer", tags = {"dungeons", "bogus", "pvp", "worldpvp", "raiding", "roleplay", "gold"}, roles = {tank = true, dps = "yes"}, level = "14", motto = string.rep("x", 400)})
    check(c.title == "The cffExplorer" and #c.tags == 4 and c.tags[2] == "worldpvp" and c.tags[4] == "roleplay" and c.roles.tank == true and c.roles.dps == nil and c.level == 14 and #c.motto == ns.MAX_MOTTO, "clean: unknown tags dropped, capped at four, roles must be true, motto capped")
    check(ns.FullName("bob") == "Bob-Firemaw" and ns.FullName("Bob-Gehennas") == "Bob-Gehennas" and ns.FullName("  ") == nil, "names: realm added when missing, capitalised")
    -- numbers off the wire stay within reason
    local odd = ns.CleanPlate({level = "1e999", updated = "-1e999"})
    local nan = ns.CleanPlate({level = "nan", updated = "0/0"})
    check(odd.level == 0 and odd.updated == 0 and nan.level == 0 and nan.updated == 0 and ns.CleanPlate({level = "500"}).level == 0 and ns.CleanPlate({level = "60.7", updated = "1700000000.5"}).level == 60 and ns.CleanPlate({updated = "1700000000.5"}).updated == 1700000000, "clean: infinite, nan and out-of-range numbers become 0, fractions are floored")
    -- lengths count letters, not bytes
    local accented = string.rep("é", 200)
    check(ns.Utf8Len(accented) == 200 and ns.Utf8Len("abc") == 3 and ns.Utf8Len("") == 0, "utf8: letters counted, not bytes")
    local cut = ns.Sanitize(accented, ns.MAX_MOTTO)
    check(ns.Utf8Len(cut) == ns.MAX_MOTTO and #cut == 2 * ns.MAX_MOTTO and cut:sub(-2) == "é", "utf8: the motto is cut at 160 letters, never in the middle of one")
    check(ns.Sanitize("héllo wörld", 6) == "héllo " and ns.Sanitize("日本語テキスト", 3) == "日本語", "utf8: two- and three-byte letters cut whole")
end

-- 2. the wire: encode, decode, chunks
do
    local ns = NewWorld({guildName = "Guild~Name=Odd"})
    local p = ns.MyPlate()
    p.title = "The Explorer"
    p.motto = "50% off ~ all = day"
    p.tags = {"dungeons", "worldpvp"}
    p.roles = {healer = true}
    p.weekdays = "000000000011111100000111"
    local text = ns.Encode(p)
    check(text:find("motto=50%%25 off %%7E all %%3D day", 1) ~= nil and text:find("guild=Guild%%7EName%%3DOdd", 1) ~= nil and text:find("tags=dungeons%%2Cworldpvp", 1) == nil and text:find("tags=dungeons,worldpvp", 1, true) ~= nil and text:find("roles=healer", 1, true) ~= nil, "encode: separators escaped inside values, tags and roles as lists")
    local d = ns.Decode(text)
    check(d.title == "The Explorer" and d.motto == "50% off ~ all = day" and d.guild == "Guild~Name=Odd" and d.tags[1] == "dungeons" and d.tags[2] == "worldpvp" and d.roles.healer == true and d.roles.tank == nil and d.weekdays == p.weekdays and d.level == 14 and d.classFile == "DRUID" and d.name == "Siggy", "decode: everything comes back, cleaned")
    check(ns.Decode("garbage~~=x~v=1").name == "" and ns.Decode(nil) == nil, "decode: rubbish gives an empty plate, nil gives nothing")
    local long = string.rep("a", 500)
    local chunks = ns.Chunks(long)
    check(#chunks == 3 and #chunks[1] == 248 and chunks[1]:sub(1, 1) == "P" and chunks[1]:sub(5, 8) == "0103" and chunks[3]:sub(5, 8) == "0303" and #chunks[3] == 28, "chunks: 240 bytes of text each, numbered, under the 255 byte limit")
    local one = ns.Chunks("short")
    check(#one == 1 and one[1]:sub(5, 8) == "0101" and one[1]:sub(9) == "short", "chunks: a short plate is one message")
end

-- 3. asking, answering, showing
do
    local ns = NewWorld()
    ns.slash("bob")
    check(#sent == 1 and sent[1].prefix == "ADVPLATE" and sent[1].text == "Q1" and sent[1].kind == "WHISPER" and sent[1].target == "Bob-Firemaw" and Printed("asking Bob-Firemaw"), "ask: /plate bob whispers a request to Bob-Firemaw")
    check(#timers == 2, "ask: a timer waits for the answer (next to the playtime sampler's)")
    -- Bob's answer, in two chunks, out of order
    local bob = ns.CleanPlate({name = "Bob", realm = "Firemaw", level = 60, race = "Orc", class = "Hunter", classFile = "HUNTER", title = "Beast Whisperer", motto = string.rep("m", 200), tags = {"hardcore"}, roles = {dps = true}, weekends = string.rep("1", 24)})
    local text = ns.Encode(bob)
    local chunks = ns.Chunks(text)
    check(#chunks == 2, "answer: Bob's plate needs two messages")
    ns.OnEvent("CHAT_MSG_ADDON", "ADVPLATE", chunks[2], "WHISPER", "Bob-Firemaw")
    check(ns.window == nil, "answer: half a plate shows nothing")
    ns.OnEvent("CHAT_MSG_ADDON", "OTHER", chunks[1], "WHISPER", "Bob-Firemaw")
    check(ns.window == nil, "answer: another addon's prefix is ignored")
    ns.OnEvent("CHAT_MSG_ADDON", "ADVPLATE", chunks[1], "WHISPER", "Bob-Firemaw")
    local win = ns.window
    check(win ~= nil and win.shown == true and win.card.shown == true and win.editor.shown == false, "answer: the whole plate opens the window on the card")
    local card = win.card
    check(card.name.text == "Bob" and card.title.text == "« Beast Whisperer »" and card.guild.text == "No guild" and card.line.text == "Level 60 Orc Hunter" and card.line.color[1] == 0.67, "card: name, title, guild line, level/race/class in the class colour")
    check(card.roles.dps.shown == true and card.roles.tank.shown == false and card.tags[1].label.text == "Hardcore / Survival" and card.tags[1].icon.shown == true and card.tags[2].icon.shown == false and card.tags[2].label.text == "", "card: roles and tags")
    check(card.rows.weekends.cells[0].color[1] == 0.95 and card.rows.weekdays.cells[0].color[1] == 0.55 and card.rows.weekdays.now.shown == true and card.rows.weekends.now.shown == false, "card: weekend hours lit, weekdays dark, the current hour marked on a weekday")
    check(card.motto.text == '"' .. string.rep("m", 160) .. '"' and card.edit.shown == false and card.ask.shown == true, "card: motto quoted and capped, Ask Again instead of Edit on someone else's plate")
    check(win.model.shown == false and win.classIcon.shown == true and win.classIcon.coords[1] == 0 and win.classNote.shown == true, "card: Bob is out of range, so his class icon stands in for the model")
    check(win.sub.text == "Bob - Firemaw", "card: the window says whose plate it is")
    local cached, seen = ns.Cached("Bob-Firemaw")
    check(cached ~= nil and cached.name == "Bob" and seen == 1700000000 and #ns.db.cache == 1, "answer: the plate is kept")
    _G.GetTime = function() return 1007 end
    RunTimers()
    check(not Printed("no plate from"), "ask: no complaint once the answer came")
    _G.GetTime = function() return 1000 end
    -- asking again shows the cached plate at once and asks for a fresh one
    local said = #printed
    ns.slash("bob")
    check(#sent == 2 and card.stamp.text:find("as of", 1, true) ~= nil and #printed == said, "ask again: the kept plate shows straight away with its date, a fresh one is asked for quietly")
    -- someone we never asked: their plate is dropped, it cannot open a window on us
    ns.OnEvent("CHAT_MSG_ADDON", "ADVPLATE", ns.Chunks(ns.Encode(ns.CleanPlate({name = "Eve", classFile = "HUNTER"})))[1], "WHISPER", "Eve-Firemaw")
    check(win.card.name.text == "Bob" and ns.Cached("Eve-Firemaw") == nil and ns._comm.inbox["Eve-Firemaw"] == nil, "answer: a plate sent unasked is ignored, not shown, not kept")
    -- an answer claims to be someone else: the server's word on the sender wins
    ns.slash("Mallory")
    ns.OnEvent("CHAT_MSG_ADDON", "ADVPLATE", ns.Chunks(ns.Encode(ns.CleanPlate({name = "Bob", realm = "Gehennas", classFile = "HUNTER", title = "Not Bob"})))[1], "WHISPER", "Mallory-Firemaw")
    local mal = ns.Cached("Mallory-Firemaw")
    check(win.card.name.text == "Mallory" and win.sub.text == "Mallory - Firemaw" and mal ~= nil and mal.name == "Mallory" and mal.realm == "Firemaw" and ns.Cached("Bob-Firemaw").title == "Beast Whisperer", "answer: the plate is filed and shown under the sender's real name and realm")
    -- a name typed with a realm keeps its case, so the reply matches
    sent = {}
    ns.slash("Tia-Gehennas")
    check(sent[1].target == "Tia-Gehennas" and ns._comm.pending["tia-gehennas"] ~= nil, "ask: /plate Tia-Gehennas asks that realm's Tia, as typed")
    ns.slash("tia-gehennas")
    check(sent[2].target == "Tia-gehennas", "ask: typed lowercase, only the first letter is fixed up")
    ns.OnEvent("CHAT_MSG_ADDON", "ADVPLATE", ns.Chunks(ns.Encode(ns.CleanPlate({classFile = "DRUID"})))[1], "WHISPER", "Tia-Gehennas")
    check(win.card.name.text == "Tia" and win.sub.text == "Tia - Gehennas" and ns._comm.pending["tia-gehennas"] == nil, "answer: the reply from Tia-Gehennas is matched to the request whatever the case typed")
    -- a plate that was half received long ago is not stitched to a new one
    local long = ns.Chunks(ns.Encode(ns.CleanPlate({motto = string.rep("x", 200), classFile = "DRUID"})))
    ns.slash("Zed")
    ns.OnEvent("CHAT_MSG_ADDON", "ADVPLATE", long[2], "WHISPER", "Zed-Firemaw")
    _G.GetTime = function() return 1003 end
    ns.slash("Zed")
    ns.OnEvent("CHAT_MSG_ADDON", "ADVPLATE", long[1], "WHISPER", "Zed-Firemaw")
    check(win.card.name.text == "Zed", "answer: two pieces a few seconds apart make a plate")
    ns.slash("Zed")
    ns.OnEvent("CHAT_MSG_ADDON", "ADVPLATE", long[2], "WHISPER", "Zed-Firemaw")
    _G.GetTime = function() return 1003 + 20 end
    ns.slash("Zed")
    ns.OnEvent("CHAT_MSG_ADDON", "ADVPLATE", long[1], "WHISPER", "Zed-Firemaw")
    check(ns._comm.inbox["Zed-Firemaw"] ~= nil and ns._comm.inbox["Zed-Firemaw"].count == 1, "answer: a piece from twenty seconds ago is forgotten, the plate waits for its other half")
    _G.GetTime = function() return 1030 end
    -- a request from Bob: our plate goes out
    sent = {}
    ns.OnEvent("CHAT_MSG_ADDON", "ADVPLATE", "Q1", "GUILD", "Bob-Firemaw")
    check(#sent == 0, "answer: a request that was not whispered is ignored")
    ns.OnEvent("CHAT_MSG_ADDON", "ADVPLATE", "Q1", "WHISPER", "Bob-Firemaw")
    check(#sent == 1 and sent[1].target == "Bob-Firemaw" and sent[1].text:sub(1, 1) == "P" and sent[1].text:find("name=Siggy", 1, true) ~= nil, "answer: a request gets our plate back")
    ns.OnEvent("CHAT_MSG_ADDON", "ADVPLATE", "Q1", "WHISPER", "Bob-Firemaw")
    check(#sent == 1, "answer: not twice within a few seconds")
    _G.GetTime = function() return 1040 end
    ns.OnEvent("CHAT_MSG_ADDON", "ADVPLATE", "Q1", "WHISPER", "Bob-Firemaw")
    check(#sent == 2, "answer: again later")
    ns.OnEvent("CHAT_MSG_ADDON", "ADVPLATE", "Q1", "WHISPER", "Siggy-Firemaw")
    check(#sent == 2, "answer: our own echo is ignored")
    ns.db.settings.greet = true
    _G.GetTime = function() return 1050 end
    ns.OnEvent("CHAT_MSG_ADDON", "ADVPLATE", "Q1", "WHISPER", "Carl-Firemaw")
    check(Printed("Carl-Firemaw looked at your plate"), "answer: greet says who looked")
    -- no answer
    sent = {}
    ns.slash("nobody")
    _G.GetTime = function() return 1060 end
    RunTimers()
    check(Printed("no plate from Nobody-Firemaw"), "ask: says so when nothing comes back")
    -- a flood of requests: the answers leave a few a second, the client is never swamped
    sent = {}
    timers = {}
    _G.GetTime = function() return 2000 end
    for i = 1, 10 do ns.OnEvent("CHAT_MSG_ADDON", "ADVPLATE", "Q1", "WHISPER", "Flood" .. i .. "-Firemaw") end
    check(#sent == 6 and #ns._comm.outbox == 4 and #timers == 1, "flood: six go at once, the rest wait in the queue on a timer")
    _G.GetTime = function() return 2000.34 end
    RunTimers()
    check(#sent == 7 and #ns._comm.outbox == 3 and #timers == 1, "flood: a third of a second later, one more")
    _G.GetTime = function() return 2010 end
    RunTimers()
    check(#sent == 10 and #ns._comm.outbox == 0 and #timers == 0, "flood: the queue drains and the timer stops")
    -- a crowd of askers cannot hold up this player's own request
    _G.GetTime = function() return 2015 end
    for i = 1, 40 do ns.OnEvent("CHAT_MSG_ADDON", "ADVPLATE", "Q1", "WHISPER", "Crowd" .. i .. "-Firemaw") end
    check(#ns._comm.outbox == 30 and #sent == 16, "flood: replies queue only until the queue is half full, the rest are dropped")
    ns.slash("Friend")
    check(ns._comm.outbox[1].text == "Q1" and ns._comm.outbox[1].target == "Friend-Firemaw" and #ns._comm.outbox == 31, "flood: my own request jumps the queue")
    for i = 1, 8 do _G.GetTime = function() return 2015 + i * 2 end; RunTimers() end
    check(#ns._comm.outbox == 0 and #sent == 47 and sent[17].target == "Friend-Firemaw", "flood: the queue drains, my request first")
    -- the client says it is throttling: the message waits at the head of the queue
    local realSend = C_ChatInfo.SendAddonMessage
    local throttle = 2
    C_ChatInfo.SendAddonMessage = function(...) if throttle > 0 then throttle = throttle - 1; return 3 end return realSend(...) end
    _G.GetTime = function() return 2020 end
    ns.OnEvent("CHAT_MSG_ADDON", "ADVPLATE", "Q1", "WHISPER", "Late-Firemaw")
    check(#sent == 47 and #ns._comm.outbox == 1 and #timers == 1, "throttled: the plate stays queued")
    _G.GetTime = function() return 2021 end
    RunTimers()
    check(#sent == 47 and #ns._comm.outbox == 1 and #timers == 1, "throttled: still refused, still queued")
    _G.GetTime = function() return 2022 end
    RunTimers()
    check(#sent == 48 and #ns._comm.outbox == 0 and sent[48].target == "Late-Firemaw", "throttled: through once the client lets it")
    C_ChatInfo.SendAddonMessage = realSend
    check(#ns.errors == 0, "no errors")
end

-- 4. who may see it
do
    local ns = NewWorld({guild = {"Gil-Firemaw", "Gilda"}, friends = {"Fay", "Far-Gehennas"}, party = {"Pat", "Pam-Gehennas"}})
    ns.db.settings.share = "friends"
    check(ns.MayShareWith("Gil-Firemaw") and ns.MayShareWith("Gilda-Firemaw") and ns.MayShareWith("Fay-Firemaw") and ns.MayShareWith("Pat-Firemaw") and not ns.MayShareWith("Rando-Firemaw"), "friends mode: guild, friends and group yes, strangers no")
    check(ns.MayShareWith("Far-Gehennas") and ns.MayShareWith("Pam-Gehennas") and ns.MayShareWith("gilda-firemaw"), "friends mode: friends and group members on other realms, whatever the case")
    check(not ns.MayShareWith("Gilda-Gehennas") and not ns.MayShareWith("Fay-Gehennas") and not ns.MayShareWith("Pat-Gehennas") and not ns.MayShareWith("Far-Firemaw"), "friends mode: a stranger on another realm with a friend's first name is not the friend")
    sent = {}
    ns.OnEvent("CHAT_MSG_ADDON", "ADVPLATE", "Q1", "WHISPER", "Rando-Firemaw")
    check(#sent == 0, "friends mode: a stranger's request is ignored")
    ns.OnEvent("CHAT_MSG_ADDON", "ADVPLATE", "Q1", "WHISPER", "Fay-Firemaw")
    check(#sent == 1, "friends mode: a friend gets it")
    ns.slash("share off")
    check(ns.db.settings.share == "off" and Printed("shared with: off"), "share off: set from the slash command")
    sent = {}
    ns.OnEvent("CHAT_MSG_ADDON", "ADVPLATE", "Q1", "WHISPER", "Fay-Firemaw")
    check(#sent == 0, "share off: nobody gets it")
    ns.slash("share")
    check(Printed("share is off"), "share: reports the setting")
    ns.slash("share everyone")
    check(ns.MayShareWith("Rando-Firemaw"), "share everyone: anyone")
    -- the options panel follows
    local panel = ns.optionsPanel
    check(panel.share.everyone.checked == true and panel.share.off.checked == false, "options: the share choice shows")
    panel.share.friends:Click()
    check(ns.db.settings.share == "friends" and panel.share.everyone.checked == false and panel.share.friends.checked == true, "options: picking one unticks the others")
    panel.greet:Click()
    check(ns.db.settings.greet == true, "options: greet switch")
    ns.slash("options")
    check(_G.__openedCategory == "cat_Adventure Plates", "options: /plate options opens the panel")
end

-- 5. my plate and the editor
do
    local ns = NewWorld({hour = 9, weekday = 7})
    ns.slash("")
    local win = ns.window
    check(win.shown and win.card.shown and win.card.edit.shown == true and win.card.ask.shown == false and win.model.unit == "player" and win.model.shown == true and win.classIcon.shown == false, "mine: the card with Edit My Plate, my model in the pane")
    check(win.card.name.text == "Siggy" and win.card.line.text == "Level 14 Night Elf Druid" and win.card.tags[1].label.text == "(nothing picked yet)" and win.card.title.text == " ", "mine: empty plate reads as empty")
    check(win.card.rows.weekends.now.shown == true and win.card.rows.weekends.now.anchors[1][2] == win.card.rows.weekends.cells[9], "mine: Saturday morning marks the 9 o'clock weekend cell")
    win.card.edit:Press()
    local ed = win.editor
    check(ed.shown == true and win.card.shown == false and ed.title.text == "" and ed.tagCount.text == "0/4", "editor: opens over the card")
    ed.title:Type("The Explorer")
    ed.motto:Type("Exploring the lands of Azeroth!")
    ed.tags.dungeons:Click(); ed.tags.leveling:Click(); ed.tags.worldpvp:Click(); ed.tags.hardcore:Click()
    ed.tags.raiding:Click()
    check(ed.tags.raiding.checked == false and ed.tagCount.text == "4/4" and Printed("up to 4 tags"), "editor: a fifth tag is refused")
    ed.tags.leveling:Click()
    check(ed.tagCount.text == "3/4", "editor: unticking frees a slot")
    ed.roles.tank:Click()
    ed.rows.weekdays[18]:Press(); ed.rows.weekdays[19]:Press(); ed.rows.weekdays[19]:Press(); ed.rows.weekends[0]:Press()
    check(ed.rows.weekdays[18].fill.color[1] == 0.95 and ed.rows.weekdays[19].fill.color[1] == 0.55, "editor: hour cells toggle")
    check(ed.mottoCount.text == "31/160", "editor: the motto counter")
    ed.save:Press()
    local p = ns.db.plates["Siggy-Firemaw"]
    check(p.title == "The Explorer" and p.motto == "Exploring the lands of Azeroth!" and #p.tags == 3 and p.tags[1] == "dungeons" and p.tags[2] == "worldpvp" and p.roles.tank == true and p.weekdays:sub(19, 19) == "1" and p.weekdays:sub(20, 20) == "0" and p.weekends:sub(1, 1) == "1", "save: the plate is kept")
    check(win.card.shown == true and ed.shown == false and win.card.title.text == "« The Explorer »" and win.card.tags[1].label.text == "Dungeon Delver" and win.card.rows.weekdays.cells[18].color[1] == 0.95 and win.card.roles.tank.shown == true and Printed("plate saved"), "save: the card shows it")
    -- cancel keeps the old
    win.card.edit:Press()
    ed.title:Type("Something else")
    ed.cancel:Press()
    check(p.title == "The Explorer" and win.card.title.text == "« The Explorer »" and ed.shown == false, "cancel: nothing changes")
    -- what goes out is what was saved
    local d = ns.Decode(ns.Encode(ns.MyPlate()))
    check(d.title == "The Explorer" and d.tags[2] == "worldpvp" and d.roles.tank == true and d.weekdays:sub(19, 19) == "1", "save: the saved plate is what other players get")
    -- the plate survives a reload
    local saved = _G.AdventurePlatesDB
    local ns2 = NewWorld({db = saved})
    check(ns2.MyPlate().title == "The Explorer" and ns2.db.settings.share == "everyone", "reload: plate and settings come back")
    check(#ns.errors == 0 and #ns2.errors == 0, "no errors")
end

-- 6. the right-click menu, /plate target, and a client without the pieces
do
    local ns = NewWorld({target = "Tia"})
    check(_G.__menus ~= nil and _G.__menus.MENU_UNIT_PLAYER ~= nil and _G.__menus.MENU_UNIT_PARTY ~= nil, "menu: entries installed on the player menus")
    local root = {buttons = {}, CreateDivider = function(self) self.divided = true end, CreateButton = function(self, label, fn) self.buttons[#self.buttons + 1] = {label = label, fn = fn} end}
    _G.__menus.MENU_UNIT_PLAYER(nil, root, {name = "Tia", server = "Gehennas", unit = "target"})
    check(root.divided and root.buttons[1].label == "View Adventure Plate", "menu: one entry after a divider")
    root.buttons[1].fn()
    check(#sent == 1 and sent[1].target == "Tia-Gehennas" and ns._comm.pending["tia-gehennas"].unit == "target", "menu: clicking it asks Tia on her realm, remembering the unit for the model")
    sent = {}
    ns.slash("target")
    check(#sent == 1 and sent[1].target == "Tia-Firemaw", "/plate target: asks the targeted player")
    local tia = ns.Chunks(ns.Encode(ns.CleanPlate({name = "Tia", classFile = "DRUID"})))[1]
    ns.OnEvent("CHAT_MSG_ADDON", "ADVPLATE", tia, "WHISPER", "Tia-Firemaw")
    check(ns.window.model.unit == "target" and ns.window.model.shown == true and ns.window.classIcon.shown == false, "answer: Tia is targeted, so her model shows")
    ns.db.settings.menu = false
    root.buttons = {}
    _G.__menus.MENU_UNIT_PLAYER(nil, root, {name = "Tia"})
    check(#root.buttons == 0, "menu: switched off, no entry")
    ns.slash("help")
    check(Printed("/plate edit"), "help prints")
    ns.slash("mouseover")
    check(Printed("no player under the mouseover"), "/plate mouseover with nothing there says so")
    local ns3 = NewWorld({noMenu = true, commDown = true})
    ns3.slash("bob")
    check(Printed("could not ask Bob-Firemaw"), "comm down: says so")
    check(#ns.errors == 0 and #ns3.errors == 0, "no errors")
end

-- 7. Era's page, the model controls, the minimap button, the welcome, the report
do
    local ns = NewWorld({firstRun = true, cursorX = 150, cursorY = 100})
    -- a second world below replaces the globals, so keep this world's
    local menus, minimap = _G.__menus, _G.Minimap
    -- first run: the welcome, on Era's page
    local welcome = ns.welcomeFrame
    check(welcome ~= nil and welcome.shown == true and ns.db.settings.welcomed == false, "welcome: opens the first time")
    check(welcome.pieces ~= nil and welcome.pieces.topLeft.texture == "Interface\\Spellbook\\UI-SpellbookPanel-TopLeft" and welcome.pieces.center.texture == "Interface\\Spellbook\\UI-SpellbookPanel-BotLeft" and welcome.disc.texture == "Interface\\Minimap\\UI-Minimap-Background" and welcome.portrait.portraitUnit == "player", "welcome: Era's spellbook page with the player's face in the ring")
    check(welcome.body.text:find("Shobek", 1, true) ~= nil and welcome.body.text:find("/plate report", 1, true) ~= nil and welcome.body.text:find("classicuiforforever@gmail.com", 1, true) ~= nil, "welcome: credits Shobek and says how to report a bug or an idea")
    welcome.close:Press()
    check(welcome.shown == false and ns.db.settings.welcomed == true, "welcome: Got it is remembered")
    local ns2 = NewWorld({db = _G.AdventurePlatesDB})
    check(ns2.welcomeFrame == nil, "welcome: not again after a reload")
    ns2.slash("welcome")
    check(ns2.welcomeFrame ~= nil and ns2.welcomeFrame.shown == true, "welcome: /plate welcome brings it back")
    ns2.welcomeFrame.report:Press()
    check(ns2.reportFrame ~= nil and ns2.reportFrame.shown == true and ns2.reportFrame.box.text:find("Adventure Plates 1.2.1 report", 1, true) ~= nil, "welcome: Report a bug opens the report")
    -- the plate window on Era's page
    ns.slash("")
    local win = ns.window
    check(win.pieces ~= nil and win.pieces.bottomRight.texture == "Interface\\Spellbook\\UI-SpellbookPanel-BotRight" and win.heading.text == "Adventure Plates" and win.heading.anchors[1][5] == -18 and win.close.anchors[1][4] == -12 and win.close.anchors[1][5] == -25 and win.portrait.portraitUnit == "player", "window: Era's page, the title over the header band, Era's X on the drawn corner (12 in, not 44 - this page has no canvas margin), my face in the ring")
    -- the brown floor under the parchment stops short of the edges: the art's outer pixels are
    -- see-through and it showed as a brown rim outside the page
    check(win.fill ~= nil and #win.fill.anchors == 2 and win.fill.anchors[1][1] == "TOPLEFT" and win.fill.anchors[1][4] == 10 and win.fill.anchors[1][5] == -10 and win.fill.anchors[2][1] == "BOTTOMRIGHT" and win.fill.anchors[2][4] == -10, "window: the floor is kept 10px in from the page's edges")
    check(win.card.guild.color[1] == 0.35 and win.card.tags[1].label.color[1] == 0.35, "window: body text in Era's parchment brown")
    -- turning the model
    check(win.rotateLeft.shown == true and win.rotateLeft.NormalTexture.texture == "Interface\\Buttons\\UI-RotationLeft-Button-Up" and win.rotateRight.NormalTexture.texture == "Interface\\Buttons\\UI-RotationRight-Button-Up" and win.model.facing == 0, "model: Era's rotate buttons under it, facing front")
    win.rotateLeft.scripts.OnMouseDown(win.rotateLeft)
    win.rotateLeft.scripts.OnUpdate(win.rotateLeft, 0.5)
    check(math.abs(win.model.facing - 1.25) < 0.001, "model: holding the left button turns it")
    win.rotateLeft.scripts.OnMouseUp(win.rotateLeft)
    check(win.rotateLeft.scripts.OnUpdate == nil, "model: letting go stops it")
    win.rotateRight.scripts.OnMouseDown(win.rotateRight)
    win.rotateRight.scripts.OnUpdate(win.rotateRight, 1)
    win.rotateRight.scripts.OnMouseUp(win.rotateRight)
    check(math.abs(win.model.facing + 1.25) < 0.001, "model: the right button turns it the other way")
    _G.GetCursorPosition = function() return 150, 100 end
    win.model.scripts.OnMouseDown(win.model, "LeftButton")
    _G.GetCursorPosition = function() return 250, 100 end
    win.model.scripts.OnUpdate(win.model)
    win.model.scripts.OnMouseUp(win.model)
    check(math.abs(win.model.facing - (-1.25 + 100 * 0.012)) < 0.001 and win.model.scripts.OnUpdate == nil, "model: dragging it turns it by the distance dragged")
    win.model.scripts.OnMouseWheel(win.model, -1)
    check(math.abs(win.model.zoom - 1.1) < 0.001, "model: the wheel zooms")
    for _ = 1, 20 do win.model.scripts.OnMouseWheel(win.model, -1) end
    check(math.abs(win.model.zoom - 1.8) < 0.001, "model: zoom is capped")
    ns.slash("")
    check(win.model.facing == 0 and win.model.zoom == 1, "model: opening a plate faces it front again")
    -- my own portrait's menu
    local root = {buttons = {}, CreateDivider = function(self) self.divided = true end, CreateButton = function(self, label, fn) self.buttons[#self.buttons + 1] = {label = label, fn = fn} end}
    check(menus.MENU_UNIT_SELF ~= nil, "menu: an entry on my own portrait")
    menus.MENU_UNIT_SELF(nil, root)
    check(root.buttons[1].label == "View My Adventure Plate" and root.buttons[2].label == "Edit My Adventure Plate", "menu: view and edit")
    win:Hide()
    root.buttons[1].fn()
    check(win.shown == true and win.card.shown == true and win.own == true, "menu: View opens my plate")
    root.buttons[2].fn()
    check(win.editor.shown == true, "menu: Edit opens the editor")
    -- the minimap button
    local mb = ns.minimapButton
    check(mb ~= nil and mb.shown ~= false and mb.parent == minimap and mb.icon.texture == "Interface\\Icons\\INV_Misc_Map02" and mb.anchors[1][2] == minimap, "minimap: a button on the ring")
    win:Hide()
    mb.scripts.OnClick(mb, "LeftButton")
    check(win.shown == true and win.own == true and win.card.shown == true, "minimap: left click opens my plate")
    mb.scripts.OnClick(mb, "LeftButton")
    check(win.shown == false, "minimap: left click again closes it")
    mb.scripts.OnClick(mb, "RightButton")
    check(_G.__openedCategory == "cat_Adventure Plates", "minimap: right click opens the settings")
    mb.scripts.OnDragStart(mb)
    _G.GetCursorPosition = function() return 100, 180 end
    mb.scripts.OnUpdate(mb)
    mb.scripts.OnDragStop(mb)
    check(math.abs(ns.db.settings.minimapAngle - 90) < 0.01 and math.abs(mb.anchors[1][5] - 80) < 0.01, "minimap: dragging moves it round the ring and the angle is kept")
    ns.slash("button off")
    check(mb.shown == false and ns.db.settings.minimap == false and ns.optionsPanel.minimap.checked == false, "minimap: /plate button off hides it, and the options box follows")
    ns.optionsPanel.minimap:Click()
    check(mb.shown == true and ns.db.settings.minimap == true, "minimap: the options box brings it back")
    local ns3 = NewWorld({db = {settings = {welcomed = true, minimap = false}}})
    check(ns3.minimapButton == nil, "minimap: off in the settings, not built at login")
    -- the report
    ns.slash("report")
    local rep = ns.reportFrame
    check(rep ~= nil and rep.shown == true and rep.pieces ~= nil, "report: /plate report opens it on Era's page")
    local text = rep.box.text
    check(text:find("Adventure Plates 1.2.1 report", 1, true) and text:find(ns.FEEDBACK_URL, 1, true) and text:find(ns.FEEDBACK_EMAIL, 1, true) and text:find("suggestions are welcome", 1, true), "report: says where it goes, for bugs and ideas")
    check(text:find("client: version 1.60.1 build 69913", 1, true) and text:find("character: Siggy-Firemaw", 1, true) and text:find("settings: share=everyone", 1, true) and text:find("my plate: title=\"\"", 1, true) and text:find("era art: all four page files present", 1, true) and text:find("errors caught: 0", 1, true), "report: client, character, settings, plate and art")
    ns.slash("probe")
    check(ns.lastReport == text or ns.lastReport:find("report", 1, true), "report: /plate probe is the same window")
    ns.slash("link")
    check(Printed(ns.FEEDBACK_URL) and Printed(ns.FEEDBACK_EMAIL), "link: both places printed")
    check(ns.optionsPanel.report ~= nil and ns.optionsPanel.feedback.text:find(ns.FEEDBACK_EMAIL, 1, true) ~= nil, "options: the report button and the addresses")
    local links = ns.optionsPanel.links
    check(links ~= nil and #links == 2 and links[1].name == "Classic UI for Forever" and links[1].box.text == "https://www.curseforge.com/wow/addons/classic-ui-for-forever" and links[2].box.text == ns.FEEDBACK_URL and links[2].label.text:find("this one", 1, true) ~= nil, "options: the other add-ons by RealJustinCase, with copyable addresses")
    check(#ns.errors == 0 and #ns2.errors == 0 and #ns3.errors == 0, "no errors")
end

-- 8. professions, looking for, a main, learned hours, shared hours, the chat link
do
    -- the side worlds first: a later NewWorld replaces the globals the main world reads
    -- Era's skill lines when there is no GetProfessions
    local era = NewWorld({skills = {{"Weapon Skills", true}, {"Herbalism", false, 60, 75}, {"Cooking", false, 20, 75}, {"Mining", false, 5, 75}}})
    local ep = era.MyPlate()
    check(#ep.profs == 2 and ep.profs[1].name == "Herbalism" and ep.profs[1].skill == 60 and ep.profs[1].max == 75 and ep.profs[2].name == "Mining", "profs: Era's skill lines, headers and secondaries skipped, the max kept")
    -- a German client names its skills in German: the profession spells say which are professions
    _G.GetSpellInfo = function(id) return ({[2366] = "Kr\195\164uterkunde", [2575] = "Bergbau"})[id] end
    local de = NewWorld({skills = {{"Waffenfertigkeiten", true}, {"Kr\195\164uterkunde", false, 60, 75}, {"Kochkunst", false, 20, 75}, {"Bergbau", false, 5, 75}}})
    local dp = de.MyPlate()
    check(#dp.profs == 2 and dp.profs[1].name == "Kr\195\164uterkunde" and dp.profs[2].name == "Bergbau", "profs: Era's skill lines in another language")
    _G.GetSpellInfo = nil
    -- a message being typed: the link goes into it
    local open = NewWorld({chatOpen = true})
    open.slash("chat")
    check(_G.__chat.inserted == "[Adventure Plate: Siggy-Firemaw]" and _G.__chat.opened == nil, "chat: with a message being typed, the link goes into it")
    -- a client without the old chat globals: ChatFrameUtil is used instead
    local util = {}
    _G.ChatFrameUtil = {
        AddMessageEventFilter = function(e, fn) util[e] = fn end,
        GetActiveWindow = function() return nil end,
        InsertLink = function() return true end,
        OpenChat = function(t) util.opened = t end
    }
    local modern = NewWorld()
    _G.ChatFrame_AddMessageEventFilter, _G.ChatEdit_GetActiveWindow, _G.ChatEdit_InsertLink, _G.ChatFrame_OpenChat = nil, nil, nil, nil
    modern.InstallChatLinks()
    modern.slash("chat")
    check(util.CHAT_MSG_SAY == modern.LinkifyChat and util.opened == "[Adventure Plate: Siggy-Firemaw]" and modern.BuildReport():find("filter=yes (ChatFrameUtil)", 1, true) ~= nil, "chat: ChatFrameUtil is preferred, and works when the old globals are gone")
    _G.ChatFrameUtil = nil
    -- six samples in six different hours: nothing stands out, nothing offered
    local scattered = NewWorld({hour = 1, weekday = 3})
    local clock = 1700000000
    _G.time = function() return clock end
    for h = 2, 6 do _G.GetGameTime = function() return h, 0 end; clock = clock + 600; scattered.RecordPlaytime() end
    local sl, ss = scattered.LearnedHours()
    check(sl == nil and ss == 6, "learn: six samples in six hours offer nothing yet")
    -- a weekend habit is judged against weekend samples, not weekday ones
    for i = 1, 30 do _G.GetGameTime = function() return 20, 0 end; clock = clock + 600; scattered.RecordPlaytime() end
    _G.C_DateAndTime = {GetCurrentCalendarTime = function() return {weekday = 7} end}
    for i = 1, 4 do _G.GetGameTime = function() return 10, 0 end; clock = clock + 600; scattered.RecordPlaytime() end
    sl = scattered.LearnedHours()
    check(sl.weekdays:sub(21, 21) == "1" and sl.weekends:sub(11, 11) == "1" and sl.weekends:sub(21, 21) == "0", "learn: four Saturday mornings light the weekend row despite thirty weekday evenings")
    local ns = NewWorld({profs = {{"Herbalism", 75, 150}, {"Alchemy", 40, 150}}, hour = 20, weekday = 3})
    local filters, chat = _G.__filters, _G.__chat
    -- professions from the client, on the wire, on the card
    local p = ns.MyPlate()
    check(#p.profs == 2 and p.profs[1].name == "Herbalism" and p.profs[1].skill == 75 and p.profs[2].max == 150, "profs: read from the client")
    local text = ns.Encode(p)
    check(text:find("profs=Herbalism:75:150,Alchemy:40:150", 1, true) ~= nil, "profs: on the wire as name:skill:max pairs")
    local d = ns.Decode(text)
    check(#d.profs == 2 and d.profs[2].name == "Alchemy" and d.profs[2].skill == 40, "profs: decoded")
    local bad = ns.CleanPlate({profs = "Herb|cffalism:9999:x,Mining:10:75,Skinning:1:1,"})
    check(#bad.profs == 2 and bad.profs[1].name == "Herbcffalism" and bad.profs[1].skill == 0 and bad.profs[1].max == 0 and bad.profs[2].name == "Mining" and bad.profs[2].max == 75, "profs: cleaned, capped at two, numbers bounded")
    ns.slash("")
    local win, card = ns.window, ns.window.card
    check(card.profs.text == "Herbalism 75/150  -  Alchemy 40/150", "profs: a line under the class on the card")
    check(card.share.shown == true and card.edit.shown == true and card.alt.shown == false and card.looking.text == "-", "mine: Share in Chat next to Edit, no main, nothing looked for yet")
    -- the editor: looking for, a main
    card.edit:Press()
    local ed = win.editor
    check(ed.looking.text == "" and ed.main.text == "" and ed.learned.text == "Use my hours?", "editor: looking-for and main boxes, Use my hours marked until enough is learned")
    ed.learned:Press()
    check(Printed("not enough seen yet: 1 of 6 samples") and win.draft.weekdays == string.rep("0", 24), "editor: pressing it too early says why and changes nothing")
    ed.looking:Type("  a levelling guild <b>  ")
    ed.main:Type("bob the great")
    ed.rows.weekdays[18]:Press(); ed.rows.weekdays[19]:Press()
    ed.save:Press()
    local mine = ns.db.plates["Siggy-Firemaw"]
    check(mine.looking == "a levelling guild <b>" and mine.main == "bobthegreat", "save: looking-for kept, the main squeezed to a name")
    check(ns.CleanPlate({main = "Bj\195\182rn-Ge hennas-x'\"[y]"}).main == "Bj\195\182rn-Gehennas", "clean: a main keeps its letters and one dash, nothing after a second dash")
    check(card.looking.text == "a levelling guild <b>" and card.alt.shown == true and card.alt.text.text == "Alt of bobthegreat" and ns.window.mainKey == "Bobthegreat-Firemaw", "card: Looking for and Alt of on the card")
    sent = {}
    card.alt:Press()
    check(#sent == 1 and sent[1].target == "Bobthegreat-Firemaw" and sent[1].text == "Q1", "card: clicking Alt of asks for the main's plate")
    -- someone else's plate: their main on their realm, and the hours you share in green
    local bob = ns.CleanPlate({classFile = "HUNTER", main = "Ann", looking = "raid buddies", weekdays = "000000000000000000111100", weekends = string.rep("1", 24)})
    ns.slash("Bob-Gehennas")
    ns.OnEvent("CHAT_MSG_ADDON", "ADVPLATE", ns.Chunks(ns.Encode(bob))[1], "WHISPER", "Bob-Gehennas")
    check(card.name.text == "Bob" and card.alt.text.text == "Alt of Ann" and ns.window.mainKey == "Ann-Gehennas" and card.looking.text == "raid buddies" and card.share.shown == false, "theirs: the main is on their realm, Share in Chat hidden")
    check(card.rows.weekdays.cells[18].color[1] == 0.45 and card.rows.weekdays.cells[19].color[1] == 0.45 and card.rows.weekdays.cells[20].color[1] == 0.95 and card.rows.weekends.cells[3].color[1] == 0.95 and card.overlap.shown == true, "theirs: the hours we both play are green, theirs alone gold, the note shown")
    ns.slash("")
    check(card.rows.weekdays.cells[18].color[1] == 0.95 and card.overlap.shown == false, "mine: my own hours are plain gold")
    -- learned hours: a sample at login, one every ten minutes, enough after an hour
    check(ns.db.learned ~= nil and ns.db.learned.samples == 1 and ns.db.learned.weekdays[21] == 1, "learn: a sample at login, Wednesday 20:00")
    local learned, samples = ns.LearnedHours()
    check(learned == nil and samples == 1, "learn: nothing offered after one sample")
    check(ns.RecordPlaytime() == false and ns.db.learned.samples == 1, "learn: a /reload a moment later is not another sample")
    local clock = 1700000000
    local function Tick() clock = clock + 600; _G.time = function() return clock end end
    Tick()
    RunTimers()
    check(ns.db.learned.samples == 2 and #timers >= 1, "learn: the ten-minute timer samples and re-arms")
    for i = 1, 4 do Tick(); ns.RecordPlaytime() end
    _G.GetGameTime = function() return 21, 0 end
    Tick(); ns.RecordPlaytime()
    _G.GetGameTime = function() return 3, 0 end
    Tick(); ns.RecordPlaytime()
    learned, samples = ns.LearnedHours()
    check(learned ~= nil and samples == 8 and learned.weekdays:sub(21, 21) == "1" and learned.weekdays:sub(22, 22) == "0" and learned.weekdays:sub(4, 4) == "0" and learned.weekends == string.rep("0", 24), "learn: eight samples: the hour with six lit, the odd ones not")
    card.edit:Press()
    check(ed.learned.text == "Use my hours", "editor: Use my hours offered")
    ed.learned:Press()
    check(win.draft.weekdays == learned.weekdays and ed.rows.weekdays[20].fill.color[1] == 0.95 and ed.rows.weekdays[18].fill.color[1] == 0.55, "editor: Use my hours fills the rows from what was learned")
    ed.cancel:Press()
    ns.slash("hours")
    check(Printed("learning my hours is on, 8 samples"), "/plate hours reports")
    ns.slash("hours off")
    check(ns.db.settings.learn == false and ns.RecordPlaytime() == false and ns.db.learned.samples == 8, "/plate hours off: no more samples")
    ns.slash("hours forget")
    check(ns.db.learned == nil and ns.LearnedHours() == nil, "/plate hours forget: wiped")
    ns.slash("hours on")
    check(ns.db.settings.learn == true and ns.optionsPanel.learn ~= nil, "/plate hours on again, and the option is on the panel")
    -- the chat link: plain text out, a link when it comes back in
    check(filters.CHAT_MSG_SAY ~= nil and filters.CHAT_MSG_GUILD ~= nil and filters.CHAT_MSG_WHISPER ~= nil and ns.chatLinksInstalled == true, "chat: filters on the chat channels")
    ns.slash("chat")
    check(chat.opened == "[Adventure Plate: Siggy-Firemaw]" and chat.inserted == nil, "chat: /plate chat opens the chat box with the plain link text")
    ns.slash("")
    card.share:Press()
    check(chat.opened == "[Adventure Plate: Siggy-Firemaw]", "chat: Share in Chat does the same")
    local _, out = ns.LinkifyChat(nil, "CHAT_MSG_SAY", "look at my plate [Adventure Plate: Bob-Firemaw] please", "Bob", "x")
    check(out == "look at my plate |cff66ccff|Haddon:AdventurePlates:Bob-Firemaw|h[Adventure Plate: Bob-Firemaw]|h|r please", "chat: the text becomes a clickable addon link")
    local _, same = ns.LinkifyChat(nil, "CHAT_MSG_SAY", "no plate here [Adventure Plate: bad|name]", "Bob")
    check(same == "no plate here [Adventure Plate: bad|name]", "chat: a name with a bar in it is left as text")
    local _, utf = ns.LinkifyChat(nil, "CHAT_MSG_SAY", "[Adventure Plate: Bj\195\182rn-Firemaw]", "Bob")
    check(utf == "|cff66ccff|Haddon:AdventurePlates:Bj\195\182rn-Firemaw|h[Adventure Plate: Bj\195\182rn-Firemaw]|h|r", "chat: a name with an accent links too")
    sent = {}
    SetItemRef("addon:AdventurePlates:Bob-Firemaw", "[Adventure Plate: Bob-Firemaw]", "LeftButton")
    check(#sent == 1 and sent[1].target == "Bob-Firemaw" and sent[1].text == "Q1", "chat: clicking the link asks for the plate")
    SetItemRef("item:6948", "[Hearthstone]", "LeftButton")
    check(#sent == 1, "chat: other links are not ours")
    _G.IsModifiedClick = function(k) return k == "CHATLINK" end
    SetItemRef("addon:AdventurePlates:Bob-Firemaw", "[Adventure Plate: Bob-Firemaw]", "LeftButton")
    check(#sent == 1, "chat: a shift-click (the game linking it) does not ask")
    _G.IsModifiedClick = nil
    _G.__clock = 10
    SetItemRef("addon:AdventurePlates:Bj\195\182rn-Firemaw", "x", "LeftButton")
    check(#sent == 2 and sent[2].target == "Bj\195\182rn-Firemaw", "chat: an accented name is asked for")
    -- Forever (and every current client) never calls SetItemRef for an addon link: LinkUtil's
    -- handler fires the "SetItemRef" EventRegistry event instead. A report: clicking did nothing.
    _G.__clock = 20
    EventRegistry:TriggerEvent("SetItemRef", "addon:AdventurePlates:Bob-Firemaw", "[Adventure Plate: Bob-Firemaw]", "LeftButton", {})
    check(#sent == 3 and sent[3].target == "Bob-Firemaw", "chat: a click that comes through the EventRegistry event asks too")
    SetItemRef("addon:AdventurePlates:Bob-Firemaw", "[Adventure Plate: Bob-Firemaw]", "LeftButton")
    check(#sent == 3, "chat: the same click arriving through both doors is one click")
    _G.__clock = 21
    SetItemRef("addon:AdventurePlates:Bob-Firemaw", "[Adventure Plate: Bob-Firemaw]", "LeftButton")
    check(#sent == 4, "chat: a second click a second later asks again")
    EventRegistry:TriggerEvent("SetItemRef", "item:6948", "[Hearthstone]", "LeftButton", {})
    check(#sent == 4, "chat: other link kinds through the event are not ours")
    check(ns.BuildReport():find("click=SetItemRef+EventRegistry", 1, true) ~= nil, "report: names both link doors")
    -- the report carries the new bits
    local report = ns.BuildReport()
    check(report:find("professions: Herbalism:75:150,Alchemy:40:150", 1, true) ~= nil and report:find("learn=yes", 1, true) ~= nil and report:find("chat links: installed=yes", 1, true) ~= nil, "report: professions, learning and chat links")
    check(#ns.errors == 0 and #era.errors == 0 and #open.errors == 0, "no errors")
end

realPrint(("Adventure Plates harness: %d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
