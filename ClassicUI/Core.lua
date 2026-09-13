-- Classic UI - core
-- Small module loader + saved settings + /cui slash command. Every module
-- runs inside pcall so one thing breaking on a new client build never takes
-- the rest of the addon down; errors are collected for /cui probe.

local addonName, ns = ...

ns.VERSION = "0.1.0"
ns.modules = {}
ns.moduleOrder = {}
ns.errors = {}

local DEFAULTS = {
    nameplates = true,
    castbar = true
}

function ns.Print(fmt, ...)
    local msg = fmt
    if select("#", ...) > 0 then msg = fmt:format(...) end
    print("|cFF66CCFFClassic UI|r: " .. msg)
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
    ClassicUIDB = ClassicUIDB or {}
    for k, v in pairs(DEFAULTS) do
        if ClassicUIDB[k] == nil then ClassicUIDB[k] = v end
    end
    ns.db = ClassicUIDB
end

function ns.OnLogin()
    if not ns.db then ns.InitDB() end
    for _, name in ipairs(ns.moduleOrder) do
        if ns.db[name] ~= false then EnableModule(name) end
    end
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
    ns.Print("  /cui nameplates force - force the Lua fallback (testing)")
    ns.Print("  /cui castbar on|off - classic-look cast bars")
    ns.Print("  /cui castbar force - re-skin the cast bars now (testing)")
    ns.Print("  /cui probe - client report to copy and send for support")
end

function ns.HandleSlash(input)
    input = (input or ""):lower()
    local cmd, arg = input:match("^(%S*)%s*(.-)$")
    if cmd == "" or cmd == "status" then
        PrintStatus()
    elseif cmd == "probe" then
        if ns.ShowProbe then ns.SafeCall("probe", ns.ShowProbe) end
    elseif cmd == "help" then
        PrintHelp()
    elseif ns.modules[cmd] then
        local mod = ns.modules[cmd]
        if arg == "on" then
            ns.db[cmd] = true
            EnableModule(cmd)
            ns.Print("%s on.", cmd)
        elseif arg == "off" then
            ns.db[cmd] = false
            DisableModule(cmd)
            ns.Print("%s off.", cmd)
        elseif arg == "force" and mod.Force then
            ns.SafeCall(cmd .. " force", mod.Force, mod)
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
    SLASH_CLASSICUI2 = "/classicui"
    SlashCmdList["CLASSICUI"] = ns.HandleSlash
end

_G.ClassicUI = ns
