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
    function f:SetUnit(u) if u == "badunit" then error("bad unit") end self.unit = u end
    function f:SetMaxLetters(n) self.maxLetters = n end
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
    _G.AdventurePlatesDB = opts.db
    _G.CreateFrame = function(kind, name, parent, template)
        local f = Widget(kind)
        f.name, f.template, f.parent = name, template, parent
        if parent and parent.children then table.insert(parent.children, f) end
        if template == "Missing" then error("template missing") end
        return f
    end
    _G.UIParent = Widget("Frame")
    _G.UISpecialFrames = {}
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
        if u == "target" then return opts.target end
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
    _G.UnitInParty = function(n) return opts.party and opts.party[n] or false end
    _G.UnitInRaid = function() return false end
    _G.IsInGuild = function() return opts.guild ~= nil end
    _G.GetNumGuildMembers = function() return opts.guild and #opts.guild or 0 end
    _G.GetGuildRosterInfo = function(i) return opts.guild[i] end
    _G.C_FriendList = {
        GetNumFriends = function() return opts.friends and #opts.friends or 0 end,
        GetFriendInfoByIndex = function(i) return {name = opts.friends[i]} end
    }
    _G.Menu = opts.noMenu and nil or {
        ModifyMenu = function(tag, fn) _G.__menus = _G.__menus or {}; _G.__menus[tag] = fn end
    }
    local ns = {}
    for _, f in ipairs({"Core.lua", "Comm.lua", "UI.lua", "Options.lua"}) do
        local chunk = assert(loadfile(root .. "/AdventurePlates/" .. f))
        chunk("AdventurePlates", ns)
    end
    ns.OnEvent("ADDON_LOADED", "AdventurePlates")
    ns.OnEvent("PLAYER_LOGIN")
    ns.slash = function(s) SlashCmdList["ADVENTUREPLATES"](s) end
    return ns
end

local function RunTimers() local t = timers; timers = {}; for _, x in ipairs(t) do x[2]() end end

-- 1. defaults, the plate and what the client says about the character
do
    local ns = NewWorld({guildName = "Lotion Appreciation Club", guildRank = "Gold Member", titleID = 5})
    check(_G.AdventurePlatesDB ~= nil and ns.db.settings.share == "everyone" and ns.db.settings.menu == true, "defaults: saved variables made, sharing on, menu on")
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
    check(#timers == 1, "ask: a timer waits for the answer")
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
    check(card.rows.weekends.cells[0].color[1] == 0.95 and card.rows.weekdays.cells[0].color[1] == 0.16 and card.rows.weekdays.now.shown == true and card.rows.weekends.now.shown == false, "card: weekend hours lit, weekdays dark, the current hour marked on a weekday")
    check(card.motto.text == '"' .. string.rep("m", 160) .. '"' and card.edit.shown == false and card.ask.shown == true, "card: motto quoted and capped, Ask Again instead of Edit on someone else's plate")
    check(win.model.shown == false and win.classIcon.shown == true and win.classIcon.coords[1] == 0 and win.classNote.shown == true, "card: Bob is out of range, so his class icon stands in for the model")
    check(win.sub.text == "Bob - Firemaw", "card: the window says whose plate it is")
    local cached, seen = ns.Cached("Bob-Firemaw")
    check(cached ~= nil and cached.name == "Bob" and seen == 1700000000 and #ns.db.cache == 1, "answer: the plate is kept")
    RunTimers()
    check(not Printed("no plate from"), "ask: no complaint once the answer came")
    -- asking again shows the cached plate at once and asks for a fresh one
    local said = #printed
    ns.slash("bob")
    check(#sent == 2 and card.stamp.text:find("as of", 1, true) ~= nil and #printed == said, "ask again: the kept plate shows straight away with its date, a fresh one is asked for quietly")
    -- someone we never asked
    ns.OnEvent("CHAT_MSG_ADDON", "ADVPLATE", ns.Chunks(ns.Encode(ns.CleanPlate({name = "Eve", classFile = "HUNTER"})))[1], "WHISPER", "Eve-Firemaw")
    check(win.card.name.text == "Eve" and ns.Cached("Eve-Firemaw") ~= nil, "answer: a plate sent unasked still shows (they wanted you to see it)")
    -- a request from Bob: our plate goes out
    sent = {}
    ns.OnEvent("CHAT_MSG_ADDON", "ADVPLATE", "Q1", "WHISPER", "Bob-Firemaw")
    check(#sent == 1 and sent[1].target == "Bob-Firemaw" and sent[1].text:sub(1, 1) == "P" and sent[1].text:find("name=Siggy", 1, true) ~= nil, "answer: a request gets our plate back")
    ns.OnEvent("CHAT_MSG_ADDON", "ADVPLATE", "Q1", "WHISPER", "Bob-Firemaw")
    check(#sent == 1, "answer: not twice within a few seconds")
    _G.GetTime = function() return 1010 end
    ns.OnEvent("CHAT_MSG_ADDON", "ADVPLATE", "Q1", "WHISPER", "Bob-Firemaw")
    check(#sent == 2, "answer: again later")
    ns.OnEvent("CHAT_MSG_ADDON", "ADVPLATE", "Q1", "WHISPER", "Siggy-Firemaw")
    check(#sent == 2, "answer: our own echo is ignored")
    ns.db.settings.greet = true
    _G.GetTime = function() return 1020 end
    ns.OnEvent("CHAT_MSG_ADDON", "ADVPLATE", "Q1", "WHISPER", "Carl-Firemaw")
    check(Printed("Carl-Firemaw looked at your plate"), "answer: greet says who looked")
    -- no answer
    sent = {}
    ns.slash("nobody")
    _G.GetTime = function() return 1030 end
    RunTimers()
    check(Printed("no plate from Nobody-Firemaw"), "ask: says so when nothing comes back")
    -- comm failure
    check(#ns.errors == 0, "no errors")
end

-- 4. who may see it
do
    local ns = NewWorld({guild = {"Gil-Firemaw", "Gilda"}, friends = {"Fay"}, party = {Pat = true}})
    ns.db.settings.share = "friends"
    check(ns.MayShareWith("Gil-Firemaw") and ns.MayShareWith("Gilda-Firemaw") and ns.MayShareWith("Fay-Firemaw") and ns.MayShareWith("Pat-Firemaw") and not ns.MayShareWith("Rando-Firemaw"), "friends mode: guild, friends and group yes, strangers no")
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
    check(ed.rows.weekdays[18].fill.color[1] == 0.95 and ed.rows.weekdays[19].fill.color[1] == 0.16, "editor: hour cells toggle")
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
    check(#sent == 1 and sent[1].target == "Tia-Gehennas" and ns._comm.pending["Tia-Gehennas"].unit == "target", "menu: clicking it asks Tia on her realm, remembering the unit for the model")
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

realPrint(("Adventure Plates harness: %d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
