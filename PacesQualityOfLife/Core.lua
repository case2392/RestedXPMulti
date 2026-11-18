-- Pace's Quality of Life (WoW Forever)
-- A handful of small conveniences for Forever's own windows. Each is a
-- feature that can be switched off in Options > AddOns > Pace's Quality
-- of Life, or with /pqol:
--   questlog    - the Map & Quest Log list: track or untrack every quest,
--                 or every quest under one zone header
--   lfgroles    - Looking For Group: show only the players listing the
--                 roles you need (tank / healer / damage)
--   zonetracker - the objective tracker follows you: on entering a zone
--                 it tracks that zone's quests and untracks the rest
--   voice       - Chat Channels: a microphone on the people in a
--                 community's voice channel, before you join it
-- Rules: widget calls plus hooksecurefunc only, nothing of ours written
-- into Blizzard's tables, secret values read under pcall, Lua 5.1.

local addonName, ns = ...

ns.VERSION = (C_AddOns and C_AddOns.GetAddOnMetadata and
                 C_AddOns.GetAddOnMetadata(addonName, "Version")) or "?"
ns.errors = {}
ns.features = {}
ns.featureOrder = {}

-- saved settings: every feature on until switched off
local DEFAULTS = {
    questlog = true,
    lfgroles = true,
    zonetracker = true,
    voice = true,
    -- tell other Pace's QoL users in your communities when you're in voice
    voiceShare = true,
    -- the Looking For Group role filter's last choice
    lfgTank = true,
    lfgHealer = true,
    lfgDamage = true
}
ns.DEFAULTS = DEFAULTS

function ns.Print(fmt, ...)
    local msg = fmt
    if select("#", ...) > 0 then msg = fmt:format(...) end
    print("|cFF66CCFFPace's QoL|r: " .. msg)
end

-- run fn(...) and record (instead of throwing) if it blows up
function ns.SafeCall(label, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then
        local text = tostring(err)
        ns.errors[#ns.errors + 1] = label .. ": " .. text
        if #ns.errors <= 3 then
            ns.Print("%s hit an error (/pqol status lists it): %s", label, text)
        end
    end
    return ok, err
end

-- a hook or event handler that can never break Blizzard's own code
function ns.Guard(label, fn)
    return function(...) ns.SafeCall(label, fn, ...) end
end

-- secret values (12.x) can't be compared or stored: true when v is one
function ns.IsSecret(v)
    if issecretvalue then
        local ok, secret = pcall(issecretvalue, v)
        return ok and secret and true or false
    end
    return false
end

-- run fn once the Blizzard addon `name` is loaded (now, if it already is)
function ns.OnAddOnLoaded(name, fn)
    local loaded = C_AddOns and C_AddOns.IsAddOnLoaded and
                       C_AddOns.IsAddOnLoaded(name)
    if loaded then
        fn()
        return
    end
    ns.addonWaiters = ns.addonWaiters or {}
    ns.addonWaiters[name] = ns.addonWaiters[name] or {}
    table.insert(ns.addonWaiters[name], fn)
end

-- key, label for the options page, module with optional :Init() (once,
-- at login) and :Apply(on) (at login and on every switch)
function ns.RegisterFeature(key, label, mod)
    ns.features[key] = {label = label, mod = mod}
    table.insert(ns.featureOrder, key)
end

function ns.IsOn(key)
    return ns.db and ns.db[key] ~= false
end

function ns.SetFeature(key, on)
    local feature = ns.features[key]
    if not feature then return end
    ns.db[key] = on and true or false
    if feature.mod.Apply then
        ns.SafeCall(key, feature.mod.Apply, feature.mod, ns.db[key])
    end
    if ns.RefreshOptions then ns.RefreshOptions() end
end

local function InitDB()
    PacesQoLDB = type(PacesQoLDB) == "table" and PacesQoLDB or {}
    for k, v in pairs(DEFAULTS) do
        if PacesQoLDB[k] == nil then PacesQoLDB[k] = v end
    end
    ns.db = PacesQoLDB
end

local function OnLogin()
    InitDB()
    for _, key in ipairs(ns.featureOrder) do
        local mod = ns.features[key].mod
        if mod.Init then ns.SafeCall(key, mod.Init, mod) end
        if mod.Apply then ns.SafeCall(key, mod.Apply, mod, ns.IsOn(key)) end
    end
    if ns.BuildOptions then ns.SafeCall("options", ns.BuildOptions) end
end

--------------------------------------------------------------------------
-- slash command
--------------------------------------------------------------------------

local function PrintStatus()
    ns.Print("v%s", ns.VERSION)
    for _, key in ipairs(ns.featureOrder) do
        local mod = ns.features[key].mod
        local detail = mod.Status and mod:Status() or ""
        ns.Print("  %s: %s %s", key,
                 ns.IsOn(key) and "|cFF66FF66on|r" or "|cFFFF6666off|r", detail)
    end
    if #ns.errors == 0 then
        ns.Print("no errors this session.")
    else
        ns.Print("%d error(s) this session:", #ns.errors)
        for i, e in ipairs(ns.errors) do
            if i > 10 then break end
            print("  " .. e)
        end
    end
end

function ns.HandleSlash(input)
    if not ns.db then return end
    input = (input or ""):gsub("^%s+", ""):gsub("%s+$", ""):lower()
    local cmd, arg = input:match("^(%S*)%s*(.-)$")
    if cmd == "" or cmd == "options" or cmd == "config" then
        if ns.OpenOptions then ns.OpenOptions() end
    elseif cmd == "status" then
        PrintStatus()
    elseif ns.features[cmd] then
        local mod = ns.features[cmd].mod
        if arg == "on" or arg == "off" then
            local on = arg == "on"
            ns.SetFeature(cmd, on)
            ns.Print("%s %s", cmd, on and "|cFF66FF66on|r" or "|cFFFF6666off|r")
        else
            -- (a bare name no longer switches a feature: "/pqol voice" typed
            -- to see what voice sharing is doing must not turn it off)
            local handled = false
            if mod.Command then
                local ok, result = ns.SafeCall(cmd, mod.Command, mod, arg)
                handled = ok and result and true or false
            end
            if not handled then
                ns.Print("%s: %s %s - |cFFFFCC00/pqol %s on|off|r switches it", cmd,
                         ns.IsOn(cmd) and "|cFF66FF66on|r" or "|cFFFF6666off|r",
                         mod.Status and mod:Status() or "", cmd)
            end
        end
    else
        ns.Print("|cFFFFCC00/pqol|r options, |cFFFFCC00/pqol status|r what's on and any errors, |cFFFFCC00/pqol <feature> on|off|r: %s; |cFFFFCC00/pqol voice|r what voice sharing sent and heard",
                 table.concat(ns.featureOrder, ", "))
    end
end

SLASH_PACESQOL1 = "/pqol"
SLASH_PACESQOL2 = "/paces"
SlashCmdList["PACESQOL"] = ns.HandleSlash

--------------------------------------------------------------------------
-- events
--------------------------------------------------------------------------

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(_, event, name)
    if event == "PLAYER_LOGIN" then
        OnLogin()
    elseif event == "ADDON_LOADED" and ns.addonWaiters and
        ns.addonWaiters[name] then
        local waiters = ns.addonWaiters[name]
        ns.addonWaiters[name] = nil
        for _, fn in ipairs(waiters) do ns.SafeCall(name, fn) end
    end
end)
ns.eventFrame = frame
