-- RestedXP Multi - group communication & sync pairing
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
    return {
        t = msgType,
        v = ns.VERSION,
        k = my.key or "",
        g = my.guideName or "",
        gv = my.version or 0,
        s = my.step or 0,
        n = my.total or 0,
        si = my.stepId or 0,
        sn = my.nextStepId or 0,
        d = my.done and true or false,
        l = my.level or 0,
        pd = pd
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

function ns.AcceptPair(name)
    ns.db.paired[name] = true
    ns.sessionDeclined[name] = nil
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
    ns.SendDecline(name)
    ns.Print("not syncing with %s. Use /rxpm sync %s if you change your mind.",
             name, name)
    ns.TryRelease()
    ns.UpdateUI()
end

function ns.Unpair(name)
    ns.db.paired[name] = nil
    ns.sessionDeclined[name] = true
    ns.SendDecline(name)
    ns.Print("stopped syncing with |cFFFFCC00%s|r.", name)
    ns.TryRelease()
    ns.UpdateUI()
end

function ns.ShowPairPrompt(name)
    ns.prompted[name] = true
    if not StaticPopup_Show then return end
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
    if name == UnitName("player") then return end

    local ok, msg = Multi:Deserialize(message)
    if not ok or type(msg) ~= "table" then return end

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

        -- a hello means they just logged in or reloaded and lost session
        -- state: re-send our accept so they don't wait on us
        if msg.t == "HI" then p.linkSent = nil end

        -- their broadcast is the authoritative word on whether they've
        -- accepted us: if our name is in their paired list, we're in
        if type(msg.pd) == "table" then
            local wasPairedBack = p.pairedBack
            local myName = UnitName("player")
            local mePaired = false
            for _, pname in ipairs(msg.pd) do
                if pname == myName then
                    mePaired = true
                    break
                end
            end
            p.pairedBack = mePaired
            if mePaired then
                p.theyDeclined = nil
                if ns.db.paired[name] and not wasPairedBack then
                    ns.Print("now syncing with |cFFFFCC00%s|r!", name)
                end
            end
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

local function OnLocalProgress()
    -- send right away: a partner may be holding on this very step
    if ns.RefreshMyState() then ns.BroadcastState(true) end
    ns.UpdateUI()
end

local function PruneParted()
    for name in pairs(ns.partners) do
        if not (UnitInParty(name) or UnitInRaid(name)) then
            ns.partners[name] = nil
            ns.prompted[name] = nil -- re-prompt if they rejoin later
        end
    end
end

local function OnTick()
    tickCount = tickCount + 1
    if ns.RefreshMyState() then sendDirty = true end

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

    StaticPopupDialogs["RXPMULTI_PAIR"] = {
        text = "%s is also using RestedXP Multi.\n\nSync your RestedXP guide progress with them?",
        button1 = "Sync",
        button2 = "Not now",
        OnAccept = function(self, data) ns.AcceptPair(data) end,
        OnCancel = function(self, data, reason)
            -- only a real "Not now" click declines; the popup can also be
            -- dismissed by other dialogs overriding it or by Escape
            if reason == "clicked" then
                ns.DeclinePair(data)
            else
                ns.prompted[data] = nil -- allow the prompt to come back
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3
    }

    Multi:RegisterComm(ns.PREFIX, OnCommReceived)

    -- RestedXP fires these AceEvent messages as the guide progresses
    Multi:RegisterMessage("RXP_STEP_ACTIVATED", OnLocalProgress)
    Multi:RegisterMessage("RXP_GUIDE_LOADED", OnLocalProgress)
    Multi:RegisterMessage("RXP_STEP_COMPLETE", function(_, step)
        if step and RXPCData and step.index == RXPCData.currentStep and
            not ns.my.done then
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
