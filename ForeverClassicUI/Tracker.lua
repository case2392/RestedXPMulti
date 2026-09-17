-- Forever Classic UI - objective tracker
--
-- Forever uses the retail objective tracker: an "All Objectives" header in
-- a gold box, a boxed header per section ("Quests"), and text in the
-- retail tracker fonts. Classic's quest watch was plain gold text. The
-- tracker's layout is Blizzard's business; this part only fades the header
-- boxes out (alpha only, re-applied after every tracker update) so what is
-- left is the text.

local addonName, ns = ...

local M = {mode = "off"}

local function SetHeaderArt(frame, alpha)
    local header = frame and frame.Header
    local bg = header and header.Background
    if bg and bg.SetAlpha then bg:SetAlpha(alpha) end
end

function M.Apply(alpha)
    local tracker = ObjectiveTrackerFrame
    if not tracker then return false end
    alpha = alpha or 0
    SetHeaderArt(tracker, alpha)
    if type(tracker.modules) == "table" then
        for _, module in ipairs(tracker.modules) do SetHeaderArt(module, alpha) end
    end
    return true
end

local function IsNative()
    return QuestWatchFrame ~= nil and not (ObjectiveTrackerFrame and ObjectiveTrackerFrame.Header)
end

function M:Enable()
    if IsNative() then
        M.mode = "native"
        return
    end
    if not ObjectiveTrackerFrame then
        M.mode = "unavailable"
        return
    end
    if M.Apply() then
        M.mode = "restyled"
        if hooksecurefunc and not M.hooked and ObjectiveTrackerFrame.Update then
            M.hooked = true
            hooksecurefunc(ObjectiveTrackerFrame, "Update", function()
                if M.mode == "restyled" then M.Apply() end
            end)
        end
    else
        M.mode = "unavailable"
    end
end

function M:Force()
    M:Enable()
    ns.Print("tracker: objective tracker header boxes %s.", M.mode)
end

function M:Disable()
    M.Apply(1)
    M.mode = "off"
end

function M:Status()
    if M.mode == "native" then return "(client already has the classic quest watch)" end
    if M.mode == "restyled" then return "(retail header boxes hidden, plain text)" end
    if M.mode == "unavailable" then return "(unavailable on this client)" end
    return ""
end

ns.RegisterModule("tracker", M)
