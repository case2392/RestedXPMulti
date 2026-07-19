-- RestedXP Multi - group communication
-- Broadcasts our guide/step state over the party addon channel and keeps a
-- table of every partner's last reported state.

local addonName, ns = ...

local Multi
local lastSend = 0
local sendDirty = false
local tickCount = 0

local function NormalizeCode(code)
    code = (code or ""):lower()
    code = code:gsub("%s+", "")
    return code
end
ns.NormalizeCode = NormalizeCode

-- compared at use time so changing your own code takes effect immediately
function ns.CodeMatches(partner)
    return NormalizeCode(ns.db.code) == NormalizeCode(partner.code)
end

local function ChatChannel()
    if LE_PARTY_CATEGORY_INSTANCE and
        IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
    if IsInRaid() then return "RAID" end
    if IsInGroup() then return "PARTY" end
end

local function BuildPayload(msgType)
    local my = ns.my
    return {
        t = msgType,
        v = ns.VERSION,
        c = NormalizeCode(ns.db.code),
        k = my.key or "",
        g = my.guideName or "",
        s = my.step or 0,
        n = my.total or 0,
        d = my.done and true or false,
        l = my.level or 0
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

local function OnLocalProgress()
    -- send right away: a partner may be holding on this very step
    if ns.RefreshMyState() then ns.BroadcastState(true) end
    ns.UpdateUI()
end

local function PruneParted()
    for name in pairs(ns.partners) do
        if not (UnitInParty(name) or UnitInRaid(name)) then
            ns.partners[name] = nil
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

local function OnCommReceived(prefix, message, distribution, sender)
    if prefix ~= ns.PREFIX then return end

    local name = Ambiguate(sender, "short")
    if name == UnitName("player") then return end

    local ok, msg = Multi:Deserialize(message)
    if not ok or type(msg) ~= "table" or type(msg.s) ~= "number" then
        return
    end

    ns.partners[name] = {
        step = msg.s or 0,
        total = tonumber(msg.n) or 0,
        key = tostring(msg.k or ""),
        guideName = tostring(msg.g or ""),
        done = msg.d and true or false,
        level = tonumber(msg.l) or 0,
        version = tonumber(msg.v) or 1,
        code = NormalizeCode(msg.c),
        lastSeen = GetTime()
    }

    if msg.t == "HI" then
        -- introduce ourselves back (small random delay to avoid a burst
        -- when several people zone in at once)
        C_Timer.After(math.random() * 2, function()
            if IsInGroup() then ns.BroadcastState(true) end
        end)
    end

    ns.TryRelease()
    ns.UpdateUI()
end

function ns.SetupSync()
    Multi = ns.Multi

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
