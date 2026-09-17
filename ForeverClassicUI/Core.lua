-- Forever Classic UI - core
-- Small module loader + saved settings + /cui slash command. Every module
-- runs inside pcall so one thing breaking on a new client build never takes
-- the rest of the addon down; errors are collected for /cui probe.

local addonName, ns = ...

ns.VERSION = "0.3.1"
ns.modules = {}
ns.moduleOrder = {}
ns.errors = {}

local DEFAULTS = {
    nameplates = true,
    castbar = true,
    combo = true,
    unitframes = true,
    actionbars = true,
    minimap = true
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

function ns.InitDB()
    ForeverClassicUIDB = ForeverClassicUIDB or {}
    for k, v in pairs(DEFAULTS) do
        if ForeverClassicUIDB[k] == nil then ForeverClassicUIDB[k] = v end
    end
    ns.db = ForeverClassicUIDB
end

function ns.OnLogin()
    if not ns.db then ns.InitDB() end
    for _, name in ipairs(ns.moduleOrder) do
        if ns.db[name] ~= false then EnableModule(name) end
    end
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
    ns.Print("  /cui unitframes|actionbars|minimap on|off|force - the other classic parts")
    ns.Print("  /cui options - open the settings panel (Options > AddOns > Classic UI for Forever)")
    ns.Print("  /cui probe - client report to copy and send for support")
    ns.Print("  /cui dump <FrameName> - list a frame's visible parts (e.g. /cui dump TargetFrame)")
end

function ns.HandleSlash(input)
    local rawCmd, rawArg = (input or ""):match("^(%S*)%s*(.-)$")
    local cmd, arg = rawCmd:lower(), rawArg:lower()
    if cmd == "" or cmd == "status" then
        PrintStatus()
    elseif cmd == "probe" then
        if ns.ShowProbe then ns.SafeCall("probe", ns.ShowProbe) end
    elseif cmd == "dump" then
        -- frame names are case-sensitive globals, keep the arg as typed
        if ns.DumpFrame then
            ns.SafeCall("dump", ns.DumpFrame, rawArg ~= "" and rawArg or "TargetFrame")
        end
    elseif cmd == "options" or cmd == "config" then
        if ns.OpenOptions then ns.SafeCall("options", ns.OpenOptions) end
    elseif cmd == "help" then
        PrintHelp()
    elseif ns.modules[cmd] then
        local mod = ns.modules[cmd]
        if arg == "on" then
            ns.db[cmd] = true
            EnableModule(cmd)
            ns.Print("%s on.", cmd)
            if ns.optionsPanel and ns.optionsPanel.Refresh then ns.optionsPanel.Refresh() end
        elseif arg == "off" then
            ns.db[cmd] = false
            DisableModule(cmd)
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
