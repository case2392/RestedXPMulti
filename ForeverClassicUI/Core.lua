-- Forever Classic UI - core
-- Small module loader + saved settings + /cui slash command. Every module
-- runs inside pcall so one thing breaking on a new client build never takes
-- the rest of the addon down; errors are collected for /cui probe.

local addonName, ns = ...

-- the toc's version, so the probe header follows each release
do
    local meta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local ok, v = pcall(function() return meta and meta(addonName, "Version") end)
    ns.VERSION = (ok and type(v) == "string" and v ~= "" and v) or "0.6.5"
end
ns.modules = {}
ns.moduleOrder = {}
ns.errors = {}

-- Parts that are built but not finished go here by name, and while a name
-- is here the part never enables whatever the saved settings say, will not
-- turn on from the slash command, and has its options box greyed out. The
-- saved setting itself is left alone, so anyone who had deliberately
-- turned one off still has it off when it comes back. 0.7.9 held the
-- quest log, Appearances and Guild parts here while their shared Era
-- panel was wrong; 0.7.16 let them back out with the panel rebuilt.
ns.COMING_SOON = {}

function ns.IsComingSoon(name)
    return ns.COMING_SOON[name] == true
end

local DEFAULTS = {
    nameplates = true,
    castbar = true,
    combo = true,
    unitframes = true,
    party = true,
    charsheet = true,
    spellbook = true,
    professions = true,
    questlog = true,
    collections = true,
    guild = true,
    actionbars = true,
    minimap = true,
    tracker = true,
    -- not a look: the minimap bug-report button, and whether the welcome
    -- window has been seen. Booleans so they ride the CVar fallback too.
    bugbutton = true,
    welcomed = false
}

function ns.Print(fmt, ...)
    local msg = fmt
    if select("#", ...) > 0 then msg = fmt:format(...) end
    print("|cFF66CCFFClassic UI (Forever)|r: " .. msg)
end

function ns.RegisterModule(name, mod)
    ns.modules[name] = mod
    table.insert(ns.moduleOrder, name)
end

-- run fn(...) and report (instead of throwing) if it blows up
function ns.SafeCall(label, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then
        local text = tostring(err)
        ns.errors[#ns.errors + 1] = label .. ": " .. text
        ns.Print("%s hit an error (it's recorded for /cui probe): %s", label,
                 text)
    end
    return ok
end

local function EnableModule(name)
    local mod = ns.modules[name]
    if mod and mod.Enable then
        return ns.SafeCall(name, mod.Enable, mod)
    end
end

local function DisableModule(name)
    local mod = ns.modules[name]
    if mod and mod.Disable then
        return ns.SafeCall(name, mod.Disable, mod)
    end
end

--------------------------------------------------------------------------
-- settings storage
-- Primary: the SavedVariables table (ForeverClassicUIDB). Fallback: a CVar
-- of our own, because the Forever beta was seen never writing the
-- SavedVariables file while CVars (nameplateStyle...) did persist. The
-- on/off flags go to both on every change; at login the CVar is used only
-- when the client handed back no saved table.
--------------------------------------------------------------------------

local SETTINGS_CVAR = "ForeverClassicUI_settings"

local function SerializeSettings()
    local parts = {}
    for _, name in ipairs(ns.moduleOrder) do
        parts[#parts + 1] = name .. "=" .. (ns.db[name] == false and "0" or "1")
    end
    -- Forever does not always write the settings file, so the two
    -- feedback flags ride the CVar with the rest
    parts[#parts + 1] = "bugbutton=" .. (ns.db.bugbutton == false and "0" or "1")
    parts[#parts + 1] = "welcomed=" .. (ns.db.welcomed == true and "1" or "0")
    return table.concat(parts, ",")
end

local function CVarAPI()
    if C_CVar and C_CVar.RegisterCVar and C_CVar.GetCVar and C_CVar.SetCVar then return C_CVar end
end

function ns.SaveFallback()
    local api = CVarAPI()
    if not api or not ns.db then return end
    pcall(api.RegisterCVar, SETTINGS_CVAR, "")
    pcall(api.SetCVar, SETTINGS_CVAR, SerializeSettings())
end

local function LoadFallback()
    local api = CVarAPI()
    if not api then return nil end
    pcall(api.RegisterCVar, SETTINGS_CVAR, "")
    local ok, value = pcall(api.GetCVar, SETTINGS_CVAR)
    if not ok or type(value) ~= "string" or value == "" then return nil end
    local t = {}
    for key, v in value:gmatch("(%w+)=([01])") do t[key] = (v == "1") end
    return t, value
end

function ns.InitDB()
    -- remember whether the client handed us a saved table at all: if this
    -- stays "no" after a /reload, the settings file is not being written
    ns.dbLoaded = ForeverClassicUIDB ~= nil
    ForeverClassicUIDB = ForeverClassicUIDB or {}
    for k, v in pairs(DEFAULTS) do
        if ForeverClassicUIDB[k] == nil then ForeverClassicUIDB[k] = v end
    end
    ForeverClassicUIDB.logins = (tonumber(ForeverClassicUIDB.logins) or 0) + 1
    ns.db = ForeverClassicUIDB
    ns.dbSource = ns.dbLoaded and "saved file" or "defaults"
    if not ns.dbLoaded then
        local fb, raw = LoadFallback()
        if fb then
            for k, v in pairs(fb) do
                if DEFAULTS[k] ~= nil then ns.db[k] = v end
            end
            ns.dbSource = "cvar fallback (" .. raw .. ")"
        end
    end
end

-- switch one part on or off: saved setting + module enable/disable
function ns.SetPart(key, on)
    if on and ns.IsComingSoon(key) then return false end
    if ns.db[key] == on then return end
    ns.db[key] = on
    ns.SaveFallback()
    if on then EnableModule(key) else DisableModule(key) end
    return true
end

--------------------------------------------------------------------------
-- a second copy of the addon (an old folder left beside a new one, or a
-- renamed folder next to the original) loads too, and both draw their
-- frames: a 0.7.25 report had every skin frame twice, one at the old
-- offsets. The newest copy runs; any other copy is switched off in the
-- AddOns list and named, so the folder can be deleted.
--------------------------------------------------------------------------

ns.NAME = "Classic UI (Forever)"
-- the titles this addon has shipped under, so an older copy is recognised
local OUR_TITLES = {["classic ui (forever)"] = true, ["classic ui for forever"] = true}

local function VersionParts(v)
    local t = {}
    for n in tostring(v or ""):gmatch("%d+") do t[#t + 1] = tonumber(n) end
    return t
end

-- 1 when a is newer than b, -1 when older, 0 when the same
function ns.CompareVersions(a, b)
    local pa, pb = VersionParts(a), VersionParts(b)
    for i = 1, math.max(#pa, #pb) do
        local x, y = pa[i] or 0, pb[i] or 0
        if x ~= y then return x > y and 1 or -1 end
    end
    return 0
end

local function AddOnAPI()
    local num = (C_AddOns and C_AddOns.GetNumAddOns) or GetNumAddOns
    local info = (C_AddOns and C_AddOns.GetAddOnInfo) or GetAddOnInfo
    local meta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local loaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    local disable = (C_AddOns and C_AddOns.DisableAddOn) or DisableAddOn
    if not num or not info or not meta then return nil end
    return {num = num, info = info, meta = meta, loaded = loaded, disable = disable}
end

-- every other loaded addon that is this addon under another folder name:
-- {folder, version, newer} for each, newest first
function ns.FindOtherCopies()
    local api = AddOnAPI()
    local found = {}
    if not api then return found end
    local ok, count = pcall(api.num)
    if not ok or type(count) ~= "number" then return found end
    for i = 1, count do
        local okI, folder = pcall(api.info, i)
        if okI and type(folder) == "string" and folder ~= addonName then
            local okT, title = pcall(api.meta, folder, "Title")
            local lowerFolder = folder:lower()
            local isCopy = (okT and type(title) == "string" and OUR_TITLES[title:lower():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")])
                or lowerFolder:find("foreverclassicui", 1, true) ~= nil
            if isCopy then
                local okL, isLoaded = pcall(function() return api.loaded and api.loaded(folder) end)
                if not api.loaded or (okL and isLoaded) then
                    local okV, version = pcall(api.meta, folder, "Version")
                    version = (okV and type(version) == "string" and version ~= "" and version) or "?"
                    local cmp = ns.CompareVersions(version, ns.VERSION)
                    -- the same version twice: the folder that sorts first runs
                    local newer = cmp > 0 or (cmp == 0 and folder < addonName)
                    found[#found + 1] = {folder = folder, version = version, newer = newer}
                end
            end
        end
    end
    table.sort(found, function(a, b) return ns.CompareVersions(a.version, b.version) > 0 end)
    return found
end

-- returns true when this copy should run
local function ClaimSingleCopy()
    local ok, others = pcall(ns.FindOtherCopies)
    if not ok then return true end
    ns.otherCopies = others
    if #others == 0 then return true end
    for _, o in ipairs(others) do
        if o.newer then
            ns.yieldedTo = o.folder
            ns.Print("another copy of this addon is installed in Interface\\AddOns\\%s (version %s), newer than this one (%s, version %s). This copy stays off; delete one of the two folders.",
                     o.folder, o.version, addonName, ns.VERSION)
            return false
        end
    end
    local api = AddOnAPI()
    local names = {}
    for _, o in ipairs(others) do
        names[#names + 1] = ("%s (version %s)"):format(o.folder, o.version)
        if api and api.disable then pcall(api.disable, o.folder) end
    end
    ns.Print("a second copy of this addon was found: %s. Two copies draw everything twice, so the other one has been switched off in the AddOns list; delete its folder from Interface\\AddOns and type /reload.",
             table.concat(names, ", "))
    -- this copy owns the slash command and the global, whichever loaded last
    if SlashCmdList then SlashCmdList["CLASSICUI"] = ns.HandleSlash end
    _G.ForeverClassicUI = ns
    return true
end

function ns.OnLogin()
    if not ns.db then ns.InitDB() end
    if not ClaimSingleCopy() then return end
    local off, soon = {}, {}
    for _, name in ipairs(ns.moduleOrder) do
        if ns.IsComingSoon(name) then
            soon[#soon + 1] = name
        elseif ns.db[name] ~= false then
            EnableModule(name)
        else
            off[#off + 1] = name
        end
    end
    if #soon > 0 then
        ns.Print("coming soon, so off for now: %s", table.concat(soon, ", "))
    end
    if #off > 0 then ns.Print("off (saved): %s", table.concat(off, ", ")) end
    if ns.BuildOptionsPanel then ns.SafeCall("options", ns.BuildOptionsPanel) end
    if ns.FeedbackLogin then ns.SafeCall("feedback", ns.FeedbackLogin) end
end

--------------------------------------------------------------------------
-- slash command
--------------------------------------------------------------------------

local function PrintStatus()
    ns.Print("v%s", ns.VERSION)
    for _, name in ipairs(ns.moduleOrder) do
        local mod = ns.modules[name]
        local state = ns.db[name] == false and "|cFFFF6666off|r" or
                          "|cFF66FF66on|r"
        local detail = mod.Status and mod:Status() or ""
        if ns.IsComingSoon(name) then
            state, detail = "|cFFFFD100coming soon|r", "not finished yet, so off for now"
        end
        ns.Print("  %s: %s %s", name, state, detail)
    end
    if #ns.errors > 0 then
        ns.Print("  %d error(s) recorded - run /cui probe and send me the report.",
                 #ns.errors)
    end
end

local function PrintHelp()
    ns.Print("commands:")
    ns.Print("  /cui - status of each part")
    ns.Print("  /cui nameplates on|off - classic-look nameplates")
    ns.Print("  /cui nameplates classic - switch to the classic plates on Forever (sets the style and reloads the UI)")
    ns.Print("  /cui nameplates size small|medium|large|xl|huge - nameplate size")
    ns.Print("  /cui nameplates force - force the Lua fallback (testing)")
    ns.Print("  /cui castbar on|off - classic-look cast bars")
    ns.Print("  /cui castbar force - re-skin the cast bars now (testing)")
    ns.Print("  /cui combo on|off - classic combo points on the target frame")
    ns.Print("  /cui combo offset <x> <y> - nudge the combo points (no numbers = reset)")
    ns.Print("  /cui combo force - draw the classic combo points now (testing)")
    ns.Print("  /cui unitframes|party|charsheet|spellbook|professions|actionbars|minimap|tracker on|off|force - the other classic parts")
    ns.Print("  /cui talents on|off|force - Era's talent frame on the talents page, one tree at a time")
    ns.Print("  /cui questlog on|off|force - Era's page on the map window and its quest list")
    ns.Print("  /cui collections on|off|force - Era's page on the Appearances window")
    ns.Print("  /cui guild on|off|force - Era's page on the Guild & Communities window")
    ns.Print("  /cui options - open the settings panel (Options > AddOns > Classic UI (Forever))")
    ns.Print("  /cui report - everything for support in one window: probe, every frame, Lua errors")
    ns.Print("  /cui report all - the same including hidden parts (use this on Classic Era for comparison)")
    ns.Print("  /cui probe - client report only")
    ns.Print("  /cui dump <FrameName> - list a frame's visible parts (e.g. /cui dump TargetFrame)")
    ns.Print("  /cui dump target - the same for your target's nameplate")
    ns.Print("  /cui welcome - the first-run window again (how to report a bug)")
    ns.Print("  /cui link - where to send a report")
    ns.Print("  /cui button on|off - the minimap bug-report button")
    ns.Print("  /cui screenshot - save a screenshot to your WoW Screenshots folder")
end

function ns.HandleSlash(input)
    local rawCmd, rawArg = (input or ""):match("^(%S*)%s*(.-)$")
    local cmd, arg = rawCmd:lower(), rawArg:lower()
    if cmd == "" or cmd == "status" then
        PrintStatus()
    elseif cmd == "probe" then
        if ns.ShowProbe then ns.SafeCall("probe", ns.ShowProbe) end
    elseif cmd == "report" then
        if ns.ShowReport then ns.SafeCall("report", ns.ShowReport, arg == "all") end
    elseif cmd == "dump" then
        -- frame names are case-sensitive globals, keep the arg as typed
        if ns.DumpFrame then
            local target, mode = rawArg:match("^(%S*)%s*(%S*)$")
            ns.SafeCall("dump", ns.DumpFrame, target ~= "" and target or "TargetFrame", mode:lower() == "all")
        end
    elseif cmd == "welcome" then
        if ns.ShowWelcome then ns.SafeCall("welcome", ns.ShowWelcome) end
    elseif cmd == "link" or cmd == "bug" then
        ns.Print("report bugs here: %s", tostring(ns.FEEDBACK_URL))
        ns.Print("copy the text from /cui report into a comment, with a screenshot.")
        ns.Print("the report is long and a comment has a limit: if it will not fit, email it to %s instead.",
                 tostring(ns.FEEDBACK_EMAIL))
    elseif cmd == "button" then
        if ns.SetMinimapButton then
            local on = arg ~= "off"
            ns.SafeCall("button", ns.SetMinimapButton, on)
            ns.Print("minimap bug-report button %s.", on and "on" or "off")
            if ns.optionsPanel and ns.optionsPanel.Refresh then ns.optionsPanel.Refresh() end
        end
    elseif cmd == "screenshot" then
        if ns.TakeScreenshot then ns.SafeCall("screenshot", ns.TakeScreenshot) end
    elseif cmd == "options" or cmd == "config" then
        if ns.OpenOptions then ns.SafeCall("options", ns.OpenOptions) end
    elseif cmd == "help" then
        PrintHelp()
    elseif ns.modules[cmd] then
        local mod = ns.modules[cmd]
        if ns.IsComingSoon(cmd) then
            ns.Print("%s: coming soon. It is built but it does not look right yet, so it is off until it does.", cmd)
        elseif arg == "on" then
            ns.SetPart(cmd, true)
            ns.Print("%s on.", cmd)
            if ns.optionsPanel and ns.optionsPanel.Refresh then ns.optionsPanel.Refresh() end
        elseif arg == "off" then
            ns.SetPart(cmd, false)
            ns.Print("%s off.", cmd)
            if ns.optionsPanel and ns.optionsPanel.Refresh then ns.optionsPanel.Refresh() end
        elseif arg == "force" and mod.Force then
            ns.SafeCall(cmd .. " force", mod.Force, mod)
        elseif arg ~= "" and mod.Command and mod:Command(arg) then
            -- handled by the module
        else
            ns.Print("%s: %s", cmd, mod.Status and mod:Status() or "")
        end
    else
        PrintHelp()
    end
end

--------------------------------------------------------------------------
-- Lua error log for /cui report (keeps the last 30, addon or Blizzard,
-- shown or not; Blizzard's own handler still runs)
--------------------------------------------------------------------------

ns.luaErrors = {}
if seterrorhandler and geterrorhandler then
    local previous = geterrorhandler()
    seterrorhandler(function(msg, ...)
        local text = tostring(msg)
        local log = ns.luaErrors
        local last = log[#log]
        if last and last.msg == text then
            last.count = last.count + 1
        else
            if #log >= 30 then table.remove(log, 1) end
            local stack = debugstack and debugstack(2, 6, 0) or ""
            log[#log + 1] = {msg = text, count = 1, stack = stack,
                             time = date and date("%H:%M:%S") or ""}
        end
        if previous then return previous(msg, ...) end
    end)
end

--------------------------------------------------------------------------
-- bootstrap
--------------------------------------------------------------------------

if CreateFrame then
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("ADDON_LOADED")
    frame:RegisterEvent("PLAYER_LOGIN")
    frame:SetScript("OnEvent", function(_, event, arg1)
        if event == "ADDON_LOADED" and arg1 == addonName then
            ns.InitDB()
        elseif event == "PLAYER_LOGIN" then
            ns.OnLogin()
        end
    end)
    ns.eventFrame = frame
end

if SlashCmdList then
    SLASH_CLASSICUI1 = "/cui"
    SLASH_CLASSICUI2 = "/fcui"
    SlashCmdList["CLASSICUI"] = ns.HandleSlash
end

_G.ForeverClassicUI = ns
