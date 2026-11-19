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

-- this character, whose switch it is (the saved settings are the account's)
local function Me()
    if not UnitGUID then return nil end
    local ok, g = pcall(UnitGUID, "player")
    if ok and type(g) == "string" and g ~= "" and not ns.IsSecret(g) then return g end
end

-- a switch waiting for the next reload: {want =, from = the setting then,
-- who = the character it was asked on (another character's is dropped at
-- login)}
local function Pending()
    local p = ns.db and ns.db.partyPetsPending
    if type(p) == "table" and type(p.want) == "boolean" and type(p.from) == "boolean" then return p end
end

-- the game refused the last switch: {want =, from = the setting then}; it
-- stands until the setting changes or a new switch is asked for
local function Refused()
    local r = ns.db and ns.db.partyPetsRefused
    if type(r) == "table" and type(r.want) == "boolean" and type(r.from) == "boolean" then return r end
end

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
        return ("The game didn't take the switch from the add-on at your last reload. Type /console showPartyPets %d, then /reload."):format(
                   r.want and 1 or 0), false
    end
    return "The game's own pet frames, under each party member. A switch takes effect at your next /reload.", false
end

function M:Set(on)
    local now = Current()
    if now == nil or Kept() then return (M.Note()) end
    ns.db.partyPetsRefused = nil -- (a new switch: the old refusal no longer says anything)
    if on == now then
        ns.db.partyPetsPending = nil
        return ("party pets are %s (the game's setting)"):format(now and "shown" or "hidden")
    end
    ns.db.partyPetsPending = {want = on, from = now, who = Me()}
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

-- the reload (or logout): the switch goes through now. (The saved settings
-- are written after PLAYER_LOGOUT, so what is cleared here stays cleared.)
function M.Logout()
    local p = Pending()
    if not p then return end
    local now = Current()
    if now == nil or now ~= p.from then
        -- (changed some other way meanwhile: that stands)
        ns.db.partyPetsPending = nil
        return
    end
    if InCombat() then return end -- (kept for the next reload)
    pcall(C_CVar.SetCVar, CVAR, p.want and "1" or "0")
    if Current() == p.want then
        -- done: nothing is left to do, or to do again later
        ns.db.partyPetsPending = nil
        ns.db.partyPetsRefused = nil
    else
        p.refused = true
    end
end

function M:Init()
    -- a switch that went through is done; one that couldn't (a reload in
    -- combat) waits for the next; one the game refused is dropped, and the
    -- options page says what to type instead. Another character's switch,
    -- left by a reload in combat, isn't this one's to make.
    local raw, me = ns.db.partyPetsPending, Me()
    if raw ~= nil and (not Pending() or (raw.who ~= nil and me ~= nil and raw.who ~= me)) then
        ns.db.partyPetsPending = nil -- (another character's, or not one this add-on made)
    end
    local p, now = Pending(), Current()
    if p and (now == nil or now == p.want or now ~= p.from) then
        ns.db.partyPetsPending = nil
        if now == p.want then ns.db.partyPetsRefused = nil end
    elseif p and p.refused then
        ns.db.partyPetsPending = nil
        ns.db.partyPetsRefused = {want = p.want, from = now}
        ns.Print("party pets: the game didn't take the switch from the add-on - type |cFFFFCC00/console showPartyPets %d|r, then /reload", p.want and 1 or 0)
    end
    local r = ns.db.partyPetsRefused
    if r ~= nil and (not Refused() or now == nil or r.from ~= now) then
        ns.db.partyPetsRefused = nil -- (the setting changed since: the report is out of date)
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
