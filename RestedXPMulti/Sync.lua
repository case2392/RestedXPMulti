-- RestedXP Party Sync - group communication & sync pairing
-- Broadcasts our guide/step state over the party addon channel, keeps a
-- table of every partner's last reported state, and manages the "want to
-- sync with X?" handshake shown when two addon users end up in a party.

local addonName, ns = ...

local Multi
local lastSend = 0
local sendDirty = false
local tickCount = 0

local function ChatChannel()
    if LE_PARTY_CATEGORY_INSTANCE and
        IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
    if IsInRaid() then return "RAID" end
    if IsInGroup() then return "PARTY" end
end

local function BuildPayload(msgType)
    local my = ns.my
    -- carry our accepted-partner list in every broadcast: pairing state can
    -- never get stuck on a single lost handshake message this way
    local pd = {}
    for pname in pairs(ns.db.paired) do table.insert(pd, pname) end
    -- and who we said no to this session, so a lost DECLINE whisper can't
    -- leave the other side on "waiting for their accept"
    local dn = {}
    for pname in pairs(ns.sessionDeclined) do table.insert(dn, pname) end
    return {
        t = msgType,
        v = ns.VERSION,
        id = ns.sid,
        dn = dn,
        k = my.key or "",
        g = my.guideName or "",
        gv = my.version or 0,
        s = my.step or 0,
        n = my.total or 0,
        si = my.stepId or 0,
        sn = my.nextStepId or 0,
        d = my.done and true or false,
        l = my.level or 0,
        pd = pd,
        st = my.stepLines or {},
        dg = my.dungeonTag and tostring(my.dungeonTag) or nil,
        sg = my.contentSig or 0,
        xh = my.xph or 0
    }
end

local function Send(msgType)
    local channel = ChatChannel()
    if not channel then return end
    lastSend = GetTime()
    sendDirty = false
    Multi:SendCommMessage(ns.PREFIX, Multi:Serialize(BuildPayload(msgType)),
                          channel)
end

-- force=true sends immediately; otherwise throttled and flushed by the ticker
function ns.BroadcastState(force)
    if not Multi then return end
    if force or GetTime() - lastSend > 3 then
        Send("S")
    else
        sendDirty = true
    end
end

function ns.BroadcastHello()
    if Multi then Send("HI") end
end

--------------------------------------------------------------------------
-- Pairing: when we detect another RXP Multi user in the party, ask the
-- player whether to sync. Both sides must accept; the choice is remembered
-- so the same friend never has to be confirmed twice.
--------------------------------------------------------------------------

local function SendTo(name, msgType)
    local p = ns.partners[name]
    Multi:SendCommMessage(ns.PREFIX, Multi:Serialize({t = msgType,
                                                      v = ns.VERSION}),
                          "WHISPER", (p and p.fullSender) or name)
end

function ns.SendPair(name)
    local p = ns.partners[name]
    if p then p.linkSent = true end
    SendTo(name, "PAIR")
end

function ns.SendDecline(name) SendTo(name, "DECLINE") end

-- close a sync popup still on screen once the question is answered another
-- way (the window's button, /rxpm sync). Called after the state change, so
-- the popup's OnHide sees it settled.
local function HidePrompt(name)
    if StaticPopup_Hide then StaticPopup_Hide("RXPMULTI_PAIR", name) end
end

-- Is this name from a partner's pd/dn list us? Partners file us under
-- Ambiguate(sender, "short"); ns.myWire is that exact string, learnt from
-- our own broadcast coming back. On WoW Forever it can differ from
-- UnitName("player"), which there returns the first name only.
local function IsMe(pname)
    return pname == ns.myWire or pname == UnitName("player")
end

-- nil when the list is missing (an older Party Sync), else true/false
local function ListHasMe(list)
    if type(list) ~= "table" then return nil end
    for _, pname in ipairs(list) do
        if IsMe(pname) then return true end
    end
    return false
end

-- the name partners know us by, for "/rxpm sync <name>" hints
function ns.MyName()
    return ns.myWire or UnitName("player")
end

function ns.AcceptPair(name)
    ns.db.paired[name] = true
    ns.sessionDeclined[name] = nil
    HidePrompt(name)
    ns.SendPair(name)
    local p = ns.partners[name]
    if p and p.pairedBack then
        ns.Print("now syncing with |cFFFFCC00%s|r!", name)
    else
        ns.Print("sync request sent to |cFFFFCC00%s|r - waiting for them to accept.",
                 name)
    end
    ns.BroadcastState(true)
    ns.TryRelease()
    ns.UpdateUI()
end

function ns.DeclinePair(name)
    ns.sessionDeclined[name] = true
    ns.db.paired[name] = nil
    HidePrompt(name)
    ns.SendDecline(name)
    ns.BroadcastState() -- carries the refusal (dn) too
    ns.Print("not syncing with %s. Use /rxpm sync %s if you change your mind.",
             name, name)
    ns.TryRelease()
    ns.UpdateUI()
end

function ns.Unpair(name)
    ns.db.paired[name] = nil
    ns.sessionDeclined[name] = true
    HidePrompt(name)
    ns.SendDecline(name)
    ns.BroadcastState()
    ns.Print("stopped syncing with |cFFFFCC00%s|r.", name)
    ns.TryRelease()
    ns.UpdateUI()
end

function ns.ShowPairPrompt(name)
    ns.prompted[name] = true
    if not StaticPopup_Show then return end
    -- already on screen: showing it again would replace it and flicker it
    -- on every message the partner sends
    if StaticPopup_FindVisible and
        StaticPopup_FindVisible("RXPMULTI_PAIR", name) then
        return
    end
    local dialog = StaticPopup_Show("RXPMULTI_PAIR", name, nil, name)
    if not dialog then
        -- all popup slots busy; retry shortly
        ns.prompted[name] = nil
        C_Timer.After(5, function()
            if not ns.db.paired[name] and not ns.sessionDeclined[name] and
                not ns.prompted[name] and ns.partners[name] then
                ns.ShowPairPrompt(name)
            end
        end)
    end
end

--------------------------------------------------------------------------
-- Receiving
--------------------------------------------------------------------------

local function OnCommReceived(prefix, message, distribution, sender)
    if prefix ~= ns.PREFIX then return end

    local name = Ambiguate(sender, "short")

    local ok, msg = Multi:Deserialize(message)
    if not ok or type(msg) ~= "table" then return end

    -- our own party broadcast coming back. Known by session id, not by
    -- name: WoW Forever's two-part names (and two same-named players from
    -- different realms) break a name test. It also tells us the exact
    -- name partners file us under.
    if msg.id ~= nil then
        if msg.id == ns.sid then
            ns.myWire = name
            return
        end
    elseif name == UnitName("player") then
        return -- older Party Sync without a session id
    end

    local p = ns.partners[name]
    if not p then
        p = {step = 0, total = 0, key = "", guideName = ""}
        ns.partners[name] = p
    end
    p.fullSender = sender
    p.lastSeen = GetTime()

    if msg.t == "S" or msg.t == "HI" then
        if type(msg.s) ~= "number" then return end
        p.step = msg.s
        p.total = tonumber(msg.n) or 0
        p.key = tostring(msg.k or "")
        p.guideName = tostring(msg.g or "")
        p.gv = tonumber(msg.gv) or 0
        p.stepId = tonumber(msg.si) or 0
        p.nextStepId = tonumber(msg.sn) or 0
        p.done = msg.d and true or false
        p.level = tonumber(msg.l) or 0
        p.version = tonumber(msg.v) or 1
        p.dungeonTag = type(msg.dg) == "string" and msg.dg or nil
        p.contentSig = tonumber(msg.sg) or 0
        p.xph = tonumber(msg.xh) or 0

        -- live text of the step they're on, as their RestedXP renders it
        p.stepLines = nil
        if type(msg.st) == "table" then
            local stepLines = {}
            for i, line in ipairs(msg.st) do
                if i > 8 then break end
                if type(line) == "string" then
                    table.insert(stepLines, line:sub(1, 120))
                end
            end
            if #stepLines > 0 then p.stepLines = stepLines end
        end

        -- a hello means they just logged in or reloaded and lost session
        -- state: re-send our accept so they don't wait on us
        if msg.t == "HI" then p.linkSent = nil end

        -- their broadcast is the authoritative word on whether they've
        -- accepted us: if our name is in their paired list, we're in
        if type(msg.pd) == "table" then
            local wasPairedBack = p.pairedBack
            local mePaired = ListHasMe(msg.pd)
            p.pairedBack = mePaired
            if mePaired then
                p.theyDeclined = nil
                if ns.db.paired[name] and not wasPairedBack then
                    ns.Print("now syncing with |cFFFFCC00%s|r!", name)
                end
            end
        end
        -- their refusals ride along the same way (not sent by older versions)
        local meDeclined = ListHasMe(msg.dn)
        if meDeclined then
            p.theyDeclined = true
            p.pairedBack = false
        elseif meDeclined == false and not p.pairedBack then
            p.theyDeclined = nil -- they reloaded or changed their mind
        end

        if ns.db.paired[name] then
            -- previously accepted partner: re-establish the link silently
            if not p.linkSent then ns.SendPair(name) end
        elseif not ns.sessionDeclined[name] and not ns.prompted[name] then
            ns.ShowPairPrompt(name)
        end

        if msg.t == "HI" then
            -- introduce ourselves back (small random delay to avoid a burst
            -- when several people zone in at once)
            C_Timer.After(math.random() * 2, function()
                if IsInGroup() then ns.BroadcastState(true) end
            end)
        end
    elseif msg.t == "PAIR" then
        local wasPaired = p.pairedBack
        p.pairedBack = true
        p.theyDeclined = nil
        if ns.db.paired[name] then
            if not p.linkSent then ns.SendPair(name) end
            if not wasPaired then
                ns.Print("now syncing with |cFFFFCC00%s|r!", name)
            end
            ns.BroadcastState(true)
        elseif ns.sessionDeclined[name] then
            ns.SendDecline(name)
        elseif not ns.prompted[name] then
            ns.ShowPairPrompt(name)
        end
    elseif msg.t == "DECLINE" then
        p.pairedBack = false
        p.theyDeclined = true
        if ns.db.paired[name] then
            ns.Print("|cFFFFCC00%s|r declined guide sync.", name)
        end
    end

    ns.TryRelease()
    ns.UpdateUI()
end

--------------------------------------------------------------------------
-- Local progress + housekeeping
--------------------------------------------------------------------------

local lastQuestScan = 0
local function RescanGroupQuests(force)
    if force or GetTime() - lastQuestScan > 5 then
        lastQuestScan = GetTime()
        if ns.ScanGroupQuests then ns.ScanGroupQuests() end
    end
end

local function OnLocalProgress()
    ns.RefreshMyProgress()
    -- send right away: a partner may be holding on this very step
    if ns.RefreshMyState() then ns.BroadcastState(true) end
    RescanGroupQuests(true)
    ns.UpdateUI()
end

-- objective counts changed (mob killed, item looted, quest turned in...):
-- share the new numbers, coalesced by the broadcast throttle
local function OnObjectiveProgress()
    if ns.RefreshMyProgress() then ns.BroadcastState() end
    RescanGroupQuests()
    ns.UpdateUI()
end

local function InGroup(name)
    return UnitInParty(name) or UnitInRaid(name)
end

local function PruneParted()
    for name, p in pairs(ns.partners) do
        -- the short name can miss a cross-realm or two-part name; the full
        -- sender name is the second try
        if not (InGroup(name) or (p.fullSender and InGroup(p.fullSender))) then
            ns.partners[name] = nil
            ns.prompted[name] = nil -- re-prompt if they rejoin later
        end
    end
end

local function OnTick()
    tickCount = tickCount + 1
    if ns.RefreshMyState() then sendDirty = true end
    if ns.RefreshMyProgress() then sendDirty = true end
    if ns.TickStats then ns.TickStats(8) end

    local now = GetTime()
    for name, p in pairs(ns.partners) do
        if now - (p.lastSeen or 0) > ns.PRUNE_SECONDS then
            ns.partners[name] = nil
            ns.prompted[name] = nil
        end
    end

    if IsInGroup() then
        -- flush pending changes, and send a keepalive every ~24s so partners
        -- recover from any lost message
        if sendDirty or tickCount % 3 == 0 then Send("S") end
    end

    ns.TryRelease()
    ns.UpdateUI()
end

function ns.SetupSync()
    Multi = ns.Multi
    -- this session's id: recognises our own broadcasts when they come back
    ns.sid = string.format("%d.%d", math.random(1, 2147483646),
                           math.floor(GetTime() * 1000) % 1000000)

    StaticPopupDialogs["RXPMULTI_PAIR"] = {
        text = "%s is also using RestedXP Party Sync.\n\nSync your RestedXP guide progress with them?",
        button1 = "Sync",
        button2 = "Not now",
        OnAccept = function(self, data)
            if data then ns.AcceptPair(data) end
        end,
        OnCancel = function(self, data, reason)
            -- older clients call OnCancel() bare when they refuse a show
            if not data then return end
            -- only a real "Not now" click declines; a popup replaced by
            -- another or refused by the game asks again later
            if reason == "clicked" then
                ns.DeclinePair(data)
            else
                ns.prompted[data] = nil
            end
        end,
        -- hidden without an answer (RestedXP closes the first popup slot on
        -- its set-hearthstone steps; other addons can too): let it come
        -- back on the partner's next message instead of never asking again.
        -- A click runs OnAccept/OnCancel before the hide, so a real answer
        -- is already recorded here.
        OnHide = function(self, data)
            if data and not ns.db.paired[data] and
                not ns.sessionDeclined[data] then
                ns.prompted[data] = nil
            end
        end,
        timeout = 0,
        whileDead = true,
        -- Escape counts as a "Not now" click in Blizzard's code, so a player
        -- closing their bags would decline: Escape leaves this popup alone
        hideOnEscape = false,
        -- one popup per partner, so three players each get their own
        multiple = true
    }

    Multi:RegisterComm(ns.PREFIX, OnCommReceived)

    -- RestedXP fires these AceEvent messages as the guide progresses
    Multi:RegisterMessage("RXP_STEP_ACTIVATED", OnLocalProgress)
    Multi:RegisterMessage("RXP_GUIDE_LOADED", OnLocalProgress)
    Multi:RegisterMessage("RXP_OBJECTIVE_COMPLETE", OnObjectiveProgress)
    Multi:RegisterEvent("QUEST_LOG_UPDATE", OnObjectiveProgress)
    Multi:RegisterMessage("RXP_STEP_COMPLETE", function(_, step)
        -- compare by table identity, not index number, so a sticky or
        -- generated step completing can never be mistaken for our own
        local guide = ns.RXP.currentGuide
        local current = guide and guide.steps and RXPCData and
                            guide.steps[RXPCData.currentStep]
        if step and current and step == current and not ns.my.done then
            ns.my.done = true
            ns.BroadcastState(true)
            ns.UpdateUI()
        end
    end)

    Multi:RegisterEvent("GROUP_ROSTER_UPDATE", function()
        PruneParted()
        ns.BroadcastState()
        ns.TryRelease()
        ns.UpdateUI()
    end)
    Multi:RegisterEvent("PLAYER_ENTERING_WORLD", function()
        C_Timer.After(5, function()
            ns.RefreshMyState()
            ns.BroadcastHello()
        end)
    end)

    C_Timer.NewTicker(8, OnTick)
end
