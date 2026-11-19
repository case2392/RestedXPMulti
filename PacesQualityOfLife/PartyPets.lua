-- Pace's Quality of Life - party members' pets under the party frames
--
-- The game's party frames (not the raid-style ones) have a pet frame under
-- each member (PartyMemberFrame.PetFrame), shown while the showPartyPets
-- setting is on - and WoW Forever's options have no switch for it. This is
-- that switch.
--
-- It switches at the next /reload or logout, not on the spot. The party
-- frames act on the setting the moment it changes (CVarCallbackRegistry,
-- from CVAR_UPDATE, which the game fires inside the call that changes it).
-- Changed from an add-on - and the game's own /console command counts as
-- one (SlashCommands.lua: forceinsecure) - that would run as add-on code
-- and could leave the frames unable to show a pet or move in combat until
-- the next reload. At logout the old UI is on its way out; after the reload
-- the frames read the setting afresh. Nothing is changed in combat.
--
-- Whether it took is read back from the setting itself: the game refuses a
-- setting it keeps from add-ons by returning nothing at all
-- (CVarDocumentation.lua: FailureMode "ReturnNothing"), not false.

local addonName, ns = ...

local M = {}
ns.PartyPets = M

local CVAR = "showPartyPets"

-- the game's setting now: true/false, nil when this client has none
local function Current()
    if not (C_CVar and C_CVar.GetCVar) then return nil end
    local ok, v = pcall(C_CVar.GetCVar, CVAR)
    if not ok or v == nil or ns.IsSecret(v) then return nil end
    return v ~= "0"
end

-- the game keeps the setting from add-ons - read-only, or one only its own
-- code may change (SetCVar's RequiresNonReadOnlyCVar and
-- RequiresNonSecureCVar): nothing here can switch it
local function Kept()
    if not (C_CVar and C_CVar.GetCVarInfo) then return false end
    local ok, _, _, _, _, _, secure, readOnly = pcall(C_CVar.GetCVarInfo, CVAR)
    if not ok then return false end
    return (secure == true and not ns.IsSecret(secure)) or (readOnly == true and not ns.IsSecret(readOnly))
end

-- this character, whose switch it is (the saved settings are the account's;
-- read once and kept, so the logout has it too)
local me
local function Me()
    if me then return me end
    if UnitGUID then
        local ok, g = pcall(UnitGUID, "player")
        if ok and type(g) == "string" and g ~= "" and not ns.IsSecret(g) then
            me = g
            return g
        end
    end
    return "?" -- (nothing to tell characters apart by: one record for them all)
end

-- Each character's own records, by its GUID - another character's are left
-- for it:
--   partyPetsPending[guid]: a switch waiting for that character's next
--     reload or logout: {want =, from = the setting then, refused = true
--     once the game didn't take it}
--   partyPetsRefused[guid]: the game didn't take that character's last
--     switch: {want =, from = the setting then, told = true once said in
--     chat}. It stands until the setting changes or a new switch is asked
--     for.
local function Valid(r) return type(r) == "table" and type(r.want) == "boolean" and type(r.from) == "boolean" end

local function Mine(name)
    local t = ns.db and ns.db[name]
    local r = type(t) == "table" and t[Me()] or nil
    if Valid(r) then return r end
end

local function Keep(name, r)
    if not ns.db then return end
    local t = ns.db[name]
    if type(t) ~= "table" then
        if r == nil then return end
        t = {}
        ns.db[name] = t
    end
    t[Me()] = r
    if next(t) == nil then ns.db[name] = nil end
end

-- (at login: anything not a record of this add-on's goes)
local function Tidy(name)
    local t = ns.db[name]
    if t == nil then return end
    if type(t) ~= "table" then
        ns.db[name] = nil
        return
    end
    for k, r in pairs(t) do
        if type(k) ~= "string" or not Valid(r) then t[k] = nil end
    end
    if next(t) == nil then ns.db[name] = nil end
end

local function Pending() return Mine("partyPetsPending") end
local function Refused() return Mine("partyPetsRefused") end

local function InCombat() return InCombatLockdown and InCombatLockdown() and true or false end

function M:IsOn()
    local p = Pending()
    if p then return p.want end
    return Current() == true
end

function M.Available() return Current() ~= nil and not Kept() end

-- what the options page and /pqol say under the switch, and whether a
-- reload is waiting
function M.Note()
    local p, now = Pending(), Current()
    if now == nil then
        return "This client has no party pet frames (no showPartyPets setting): nothing to switch.", false
    end
    if Kept() then
        return "The game keeps this setting from add-ons, so it can't be switched here.", false
    end
    if p then
        return ("Party pets will be %s after your next /reload (the game's party frames take this from an add-on only then)."):format(
                   p.want and "shown" or "hidden"), true
    end
    local r = Refused()
    if r and r.from == now then
        return ("The game didn't take the add-on's switch. Type /console showPartyPets %d, then /reload."):format(
                   r.want and 1 or 0), false
    end
    return "The game's own pet frames, under each party member. A switch takes effect at your next /reload.", false
end

function M:Set(on)
    local now = Current()
    if now == nil or Kept() then return (M.Note()) end
    Keep("partyPetsRefused", nil) -- (a new switch: the old refusal no longer says anything)
    if on == now then
        Keep("partyPetsPending", nil)
        return ("party pets are %s (the game's setting)"):format(now and "shown" or "hidden")
    end
    Keep("partyPetsPending", {want = on, from = now})
    return ("party pets %s after your next |cFFFFCC00/reload|r"):format(on and "shown" or "hidden")
end

-- the options page's button
function M.ReloadNow()
    if InCombat() then
        ns.Print("party pets: not in combat - reload once it's over")
        return
    end
    if ReloadUI then ReloadUI() elseif C_UI and C_UI.Reload then C_UI.Reload() end
end

-- the reload (or logout): this character's switch goes through now. (The
-- saved settings are written after PLAYER_LOGOUT, so what is cleared here
-- stays cleared.)
function M.Logout()
    local p = Pending()
    if not p then return end
    local now = Current()
    if now == nil or now ~= p.from then
        -- (changed some other way meanwhile: that stands)
        Keep("partyPetsPending", nil)
        return
    end
    if InCombat() then return end -- (kept for the next reload)
    pcall(C_CVar.SetCVar, CVAR, p.want and "1" or "0")
    if Current() == p.want then
        -- done: nothing is left to do, or to do again later
        Keep("partyPetsPending", nil)
        Keep("partyPetsRefused", nil)
    else
        p.refused = true
    end
end

function M:Init()
    -- this character's switch: one that went through is done; one that
    -- couldn't (a reload in combat) waits for the next; one the game refused
    -- is said once, and the options page says what to type instead.
    -- Another character's are left for it, to make or be told at its own
    -- logout and login.
    Me()
    Tidy("partyPetsPending")
    Tidy("partyPetsRefused")
    local p, now = Pending(), Current()
    if p and (now == nil or now == p.want or now ~= p.from) then
        Keep("partyPetsPending", nil)
        if now == p.want then Keep("partyPetsRefused", nil) end
    elseif p and p.refused then
        Keep("partyPetsPending", nil)
        Keep("partyPetsRefused", {want = p.want, from = now})
    end
    local r = Refused()
    if r and (now == nil or r.from ~= now) then
        Keep("partyPetsRefused", nil) -- (the setting changed since: the report is out of date)
    elseif r and not r.told then
        r.told = true
        ns.Print("party pets: the game didn't take the add-on's switch - type |cFFFFCC00/console showPartyPets %d|r, then /reload",
                 r.want and 1 or 0)
    end
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGOUT")
    f:SetScript("OnEvent", ns.Guard("partypets", M.Logout))
    M.eventFrame = f
end

function M:Status()
    local now = Current()
    if now == nil then return "(this client has no party pet setting)" end
    if Kept() then return ("(the game's setting: %s; the game keeps it from add-ons)"):format(now and "shown" or "hidden") end
    local p = Pending()
    return ("(the game's setting: %s%s)"):format(now and "shown" or "hidden",
                                                 p and ("; %s at your next /reload"):format(p.want and "shown" or "hidden") or "")
end

ns.RegisterFeature("partypets",
    "Party frames: show your party members' pets under their frames (the game's own pet frames, which WoW Forever's options can't switch on; the standard party frames, not the raid-style ones)",
    M)
