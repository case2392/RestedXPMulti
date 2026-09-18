-- Forever Classic UI - core
-- Small module loader + saved settings + /cui slash command. Every module
-- runs inside pcall so one thing breaking on a new client build never takes
-- the rest of the addon down; errors are collected for /cui probe.

local addonName, ns = ...

ns.VERSION = "0.4.0"
ns.modules = {}
ns.moduleOrder = {}
ns.errors = {}

local DEFAULTS = {
    nameplates = true,
    castbar = true,
    combo = true,
    unitframes = true,
    charsheet = true,
    actionbars = true,
    minimap = true,
    tracker = true
}

function ns.Print(fmt, ...)
    local msg = fmt
    if select("#", ...) > 0 then msg = fmt:format(...) end
    print("|cFF66CCFFClassic UI for Forever|r: " .. msg)
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
    if ns.db[key] == on then return end
    ns.db[key] = on
    ns.SaveFallback()
    if on then EnableModule(key) else DisableModule(key) end
end

function ns.OnLogin()
    if not ns.db then ns.InitDB() end
    local off = {}
    for _, name in ipairs(ns.moduleOrder) do
        if ns.db[name] ~= false then
            EnableModule(name)
        else
            off[#off + 1] = name
        end
    end
    if #off > 0 then ns.Print("off (saved): %s", table.concat(off, ", ")) end
    if ns.BuildOptionsPanel then ns.SafeCall("options", ns.BuildOptionsPanel) end
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
    ns.Print("  /cui nameplates size small|medium|large|xl|huge - nameplate size")
    ns.Print("  /cui nameplates force - force the Lua fallback (testing)")
    ns.Print("  /cui castbar on|off - classic-look cast bars")
    ns.Print("  /cui castbar force - re-skin the cast bars now (testing)")
    ns.Print("  /cui combo on|off - classic combo points on the target frame")
    ns.Print("  /cui combo offset <x> <y> - nudge the combo points (no numbers = reset)")
    ns.Print("  /cui combo force - draw the classic combo points now (testing)")
    ns.Print("  /cui unitframes|charsheet|actionbars|minimap|tracker on|off|force - the other classic parts")
    ns.Print("  /cui options - open the settings panel (Options > AddOns > Classic UI for Forever)")
    ns.Print("  /cui report - everything for support in one window: probe, every frame, Lua errors")
    ns.Print("  /cui report all - the same including hidden parts (use this on Classic Era for comparison)")
    ns.Print("  /cui probe - client report only")
    ns.Print("  /cui dump <FrameName> - list a frame's visible parts (e.g. /cui dump TargetFrame)")
    ns.Print("  /cui dump target - the same for your target's nameplate")
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
    elseif cmd == "options" or cmd == "config" then
        if ns.OpenOptions then ns.SafeCall("options", ns.OpenOptions) end
    elseif cmd == "help" then
        PrintHelp()
    elseif ns.modules[cmd] then
        local mod = ns.modules[cmd]
        if arg == "on" then
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
