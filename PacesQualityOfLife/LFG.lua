-- Pace's Quality of Life - Looking For Group: only the players listing
-- the roles you need
--
-- Forever's Looking For Group window is Blizzard_GroupFinder_VanillaStyle
-- (load-on-demand, Mainline files on camelot): LFGBrowseFrame lists
-- "Groups" and "Players" in a ScrollBox. A solo player's roles come from
-- C_LFGList.GetSearchResultPlayerInfo(id, 1).lfgRoles.
--
-- Three role buttons (tank / healer / damage) sit between Send Message
-- and Group Invite. All lit: Blizzard's list, untouched. Otherwise our own
-- list of the matching players covers the list area, with Send Message
-- and Group Invite buttons of its own. Blizzard's list is never changed:
-- filtering it in place would run its row code tainted, and inside
-- dungeons, where the LFG data turns secret, that ends in Lua errors from
-- Blizzard's window. Ours steps aside then (chat lockdown), and Blizzard's
-- list shows as usual.
--
-- Clicking a role while all three are lit shows only that role (one
-- click for "healers only"); after that each click adds or removes a
-- role, and clearing the last one shows everyone again.

local addonName, ns = ...

local M = {}
ns.LFG = M

local ROW_HEIGHT = 72
local ROLES = {
    {key = "lfgTank", field = "tank", atlas = "groupfinder-icon-role-large-tank", micro = "groupfinder-icon-role-micro-tank", name = "Tanks"},
    {key = "lfgHealer", field = "healer", atlas = "groupfinder-icon-role-large-heal", micro = "groupfinder-icon-role-micro-heal", name = "Healers"},
    {key = "lfgDamage", field = "dps", atlas = "groupfinder-icon-role-large-dps", micro = "groupfinder-icon-role-micro-dps", name = "Damage"},
}

local bar, overlay, list, rowsMade
local roleButtons = {}
local selected -- resultID chosen in our list
local hiddenAlpha = {}

local function Locked()
    if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown then
        local ok, locked = pcall(C_ChatInfo.InChatMessagingLockdown)
        return ok and locked and true or false
    end
    return false
end

local function AllOn()
    return ns.db.lfgTank and ns.db.lfgHealer and ns.db.lfgDamage
end

function M.FilterActive()
    return ns.IsOn("lfgroles") and not AllOn()
end

-- a player listing at least one of the roles we want
local function Wanted(roles)
    if not roles then return false end
    for _, r in ipairs(ROLES) do
        if ns.db[r.key] and roles[r.field] then return true end
    end
    return false
end

local function Read(fn, ...)
    if not fn then return end
    local ok, v = pcall(fn, ...)
    if ok then return v end
end

-- the solo players in Blizzard's current results that match the filter
function M.Matches()
    local out, solo, mine = {}, 0, false
    local results = LFGBrowseFrame and LFGBrowseFrame.results
    if type(results) ~= "table" then
        local _, fresh = pcall(C_LFGList.GetFilteredSearchResults)
        results = type(fresh) == "table" and fresh or {}
    end
    for _, id in ipairs(results) do
        local info = Read(C_LFGList.GetSearchResultInfo, id)
        if info and not ns.IsSecret(info.hasSelf) and info.hasSelf then mine = true end
        if info and not ns.IsSecret(info.numMembers) and not ns.IsSecret(info.hasSelf) and
            not info.hasSelf and (info.numMembers or 0) <= 1 then
            solo = solo + 1
            local p = Read(C_LFGList.GetSearchResultPlayerInfo, id, 1) or
                          Read(C_LFGList.GetSearchResultLeaderInfo, id)
            local roles = p and p.lfgRoles
            local clean = roles and not ns.IsSecret(roles.tank) and not ns.IsSecret(roles.healer) and
                              not ns.IsSecret(roles.dps)
            if clean and Wanted(roles) then
                local name = info.leaderName or (p and p.name)
                if name and not ns.IsSecret(name) then
                    table.insert(out, {
                        resultID = id, name = name, level = p and p.level, classFile = p and p.classFilename,
                        roles = {tank = roles.tank, healer = roles.healer, dps = roles.dps},
                        delisted = info.isDelisted, activityIDs = info.activityIDs,
                        playstyle = info.generalPlaystyle, comment = info.comment,
                    })
                end
            end
        end
    end
    return out, solo, mine
end

--------------------------------------------------------------------------
-- our list
--------------------------------------------------------------------------

local function ActivityText(entry)
    local ids = entry.activityIDs
    if type(ids) ~= "table" or #ids == 0 then return "" end
    if #ids > 1 then
        return LFGBROWSE_ACTIVITY_COUNT and LFGBROWSE_ACTIVITY_COUNT:format(#ids) or (#ids .. " activities")
    end
    local info = Read(C_LFGList.GetActivityInfoTable, ids[1])
    if not info then return "" end
    if LFGUtil_GetActivityInfoName then
        local name = Read(LFGUtil_GetActivityInfoName, info)
        if name then return name end
    end
    return info.fullName or info.shortName or ""
end

local function ClassColor(classFile)
    local c = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    if c then return c.r, c.g, c.b end
    return 1, 0.82, 0
end

local function CanInvite(entry)
    if not entry or entry.delisted then return false end
    if not IsInGroup or not IsInGroup() then return true end
    return (UnitIsGroupLeader and UnitIsGroupLeader("player")) or
               (UnitIsGroupAssistant and UnitIsGroupAssistant("player")) or false
end

local function SelectedEntry()
    if not selected or not overlay then return end
    for _, e in ipairs(overlay.entries or {}) do
        if e.resultID == selected then return e end
    end
end

local function UpdateButtons()
    if not overlay then return end
    local entry = SelectedEntry()
    if entry then overlay.send:Enable() else overlay.send:Disable() end
    if CanInvite(entry) then overlay.invite:Enable() else overlay.invite:Disable() end
end

local function InitRow(row, entry)
    if not row.paces then
        row.paces = true
        row:SetHeight(ROW_HEIGHT)
        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAtlas("common-button-list-mid2")
        bg:SetPoint("TOPLEFT", 3, -2)
        bg:SetPoint("BOTTOMRIGHT", -3, 0)
        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAtlas("common-button-list-mid2-hover")
        hl:SetBlendMode("ADD")
        hl:SetPoint("TOPLEFT", 3, -3)
        hl:SetPoint("BOTTOMRIGHT", -3, -1)
        row.sel = row:CreateTexture(nil, "OVERLAY")
        row.sel:SetAtlas("common-button-list-mid2-selected")
        row.sel:SetBlendMode("ADD")
        row.sel:SetPoint("TOPLEFT", 3, -3)
        row.sel:SetPoint("BOTTOMRIGHT", -3, -1)
        row.Name = row:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        row.Name:SetPoint("TOPLEFT", 14, -10)
        row.Name:SetJustifyH("LEFT")
        row.Level = row:CreateFontString(nil, "ARTWORK", "GameFontDisableLeft")
        row.Level:SetPoint("BOTTOMLEFT", row.Name, "BOTTOMRIGHT", 4, 0)
        row.Class = row:CreateTexture(nil, "ARTWORK")
        row.Class:SetSize(24, 24)
        row.Class:SetPoint("BOTTOMLEFT", row.Level, "BOTTOMRIGHT", 3, -5)
        row.Activity = row:CreateFontString(nil, "ARTWORK", "GameFontDisableLeft")
        row.Activity:SetPoint("TOPLEFT", row.Name, "BOTTOMLEFT", 0, -2)
        row.Playstyle = row:CreateFontString(nil, "ARTWORK", "GameFontDisableLeft")
        row.Playstyle:SetPoint("TOPLEFT", row.Activity, "BOTTOMLEFT", 0, -2)
        row.RolesLabel = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        row.RolesLabel:SetPoint("RIGHT", row, "RIGHT", -64, 0)
        row.RolesLabel:SetText(LFG_TOOLTIP_ROLES or "Roles:")
        row.RoleIcons = {}
        for i = 1, 3 do
            local t = row:CreateTexture(nil, "ARTWORK")
            t:SetSize(16, 16)
            t:SetPoint("LEFT", row.RolesLabel, "RIGHT", 2 + (i - 1) * 17, 0)
            row.RoleIcons[i] = t
        end
        row:SetScript("OnClick", ns.Guard("lfgroles", function(self)
            selected = (selected ~= self.entry.resultID) and self.entry.resultID or nil
            M.RefreshRows()
            UpdateButtons()
        end))
        row:SetScript("OnDoubleClick", ns.Guard("lfgroles", function(self)
            -- the first click of the two toggled it: select it for good
            selected = self.entry.resultID
            M.RefreshRows()
            UpdateButtons()
            M.SendMessage()
        end))
        row:SetScript("OnEnter", ns.Guard("lfgroles", function(self)
            local e = self.entry
            if not (e and GameTooltip) then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(e.name, ClassColor(e.classFile))
            if e.level then GameTooltip:AddLine((LEVEL or "Level") .. " " .. e.level, 1, 1, 1) end
            local activity = ActivityText(e)
            if activity ~= "" then GameTooltip:AddLine(activity, 0.4, 0.78, 1) end
            if type(e.comment) == "string" and e.comment ~= "" and not ns.IsSecret(e.comment) then
                GameTooltip:AddLine(e.comment, 0.8, 0.8, 0.8, true)
            end
            GameTooltip:Show()
        end))
        row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    end
    row.entry = entry
    row.Name:SetText(entry.name)
    row.Name:SetTextColor(ClassColor(entry.classFile))
    row.Level:SetText(entry.level and ((LEVEL_ABBR or "Lvl") .. " " .. entry.level) or "")
    if entry.classFile then
        row.Class:SetAtlas("groupfinder-icon-class-" .. entry.classFile:lower())
        row.Class:Show()
    else
        row.Class:Hide()
    end
    row.Activity:SetText(ActivityText(entry))
    row.Activity:SetTextColor(0.4, 0.78, 1)
    local playstyle = ""
    if entry.playstyle and GetGeneralPlaystyleString then
        playstyle = Read(GetGeneralPlaystyleString, entry.playstyle) or ""
    end
    row.Playstyle:SetText(playstyle)
    row.Playstyle:SetTextColor(0.1, 1, 0.1)
    local n = 0
    for _, r in ipairs(ROLES) do
        if entry.roles[r.field] then
            n = n + 1
            row.RoleIcons[n]:SetAtlas(r.micro)
            row.RoleIcons[n]:Show()
        end
    end
    for i = n + 1, 3 do row.RoleIcons[i]:Hide() end
    row.sel:SetShown(selected == entry.resultID)
    row:SetAlpha(entry.delisted and 0.5 or 1)
end

function M.RefreshRows()
    if not (list and list.box) then return end
    for _, row in list.box:EnumerateFrames() do
        if row.entry then InitRow(row, row.entry) end
    end
end

local function MakeOverlay()
    if overlay then return overlay end
    local blizzBox = LFGBrowseFrame.ScrollBox
    overlay = CreateFrame("Frame", nil, LFGBrowseFrame)
    -- Blizzard re-anchors its list at run time (a managed scroll bar:
    -- TOPLEFT 7,-112, BOTTOMRIGHT -22 or -6, 40): follow the list's top
    -- left, and cover to the frame's right edge, scroll bar included
    overlay:SetPoint("TOPLEFT", blizzBox, "TOPLEFT", 0, 0)
    overlay:SetPoint("BOTTOMRIGHT", LFGBrowseFrame, "BOTTOMRIGHT", -6, 40)
    overlay:SetFrameLevel(blizzBox:GetFrameLevel() + 20)
    overlay:EnableMouse(true)
    if overlay.EnableMouseWheel then overlay:EnableMouseWheel(true) end
    local bg = overlay:CreateTexture(nil, "BACKGROUND")
    bg:SetAtlas("groupfinder-background")
    bg:SetAllPoints()

    overlay.header = overlay:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    overlay.header:SetPoint("TOPLEFT", 12, -6)
    overlay.header:SetJustifyH("LEFT")
    overlay.empty = overlay:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    overlay.empty:SetPoint("TOP", 0, -60)
    overlay.empty:SetWidth(260)

    list = {}
    list.box = CreateFrame("Frame", nil, overlay, "WowScrollBoxList")
    list.box:SetPoint("TOPLEFT", 0, -40)
    list.box:SetPoint("BOTTOMRIGHT", -18, 0)
    list.bar = CreateFrame("EventFrame", nil, overlay, "MinimalScrollBar")
    list.bar:SetPoint("TOPLEFT", list.box, "TOPRIGHT", 4, 0)
    list.bar:SetPoint("BOTTOMLEFT", list.box, "BOTTOMRIGHT", 4, 0)
    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(ROW_HEIGHT)
    view:SetElementInitializer("Button", function(row, entry)
        ns.SafeCall("lfgroles", InitRow, row, entry)
    end)
    ScrollUtil.InitScrollBoxListWithScrollBar(list.box, list.bar, view)

    -- our own buttons over Blizzard's (theirs act on Blizzard's selection,
    -- which the user can't reach while ours covers the list)
    local send = CreateFrame("Button", nil, LFGBrowseFrame, "UIPanelButtonTemplate")
    send:SetSize(111, 28)
    send:SetPoint("BOTTOMLEFT", 21, 16)
    send:SetText(SEND_MESSAGE or "Send Message")
    -- above our own list (it reaches down over the buttons' top edge)
    send:SetFrameLevel(overlay:GetFrameLevel() + 5)
    send:SetScript("OnClick", ns.Guard("lfgroles", function() M.SendMessage() end))
    overlay.send = send
    local invite = CreateFrame("Button", nil, LFGBrowseFrame, "UIPanelButtonTemplate")
    invite:SetSize(109, 28)
    invite:SetPoint("BOTTOMRIGHT", -21, 16)
    invite:SetText(GROUP_INVITE or "Group Invite")
    invite:SetFrameLevel(overlay:GetFrameLevel() + 5)
    invite:SetScript("OnClick", ns.Guard("lfgroles", function() M.Invite() end))
    overlay.invite = invite
    overlay:SetScript("OnHide", function()
        send:Hide()
        invite:Hide()
    end)
    overlay:SetScript("OnShow", function()
        send:Show()
        invite:Show()
    end)
    overlay:Hide()
    send:Hide()
    invite:Hide()
    return overlay
end

function M.SendMessage()
    local entry = SelectedEntry()
    if not entry then return end
    if ChatFrameUtil and ChatFrameUtil.SendTell then
        ChatFrameUtil.SendTell(entry.name)
    elseif ChatFrame_SendTell then
        ChatFrame_SendTell(entry.name)
    end
end

function M.Invite()
    local entry = SelectedEntry()
    if not CanInvite(entry) then return end
    if C_PartyInfo and C_PartyInfo.InviteUnit then
        C_PartyInfo.InviteUnit(entry.name)
    elseif InviteUnit then
        InviteUnit(entry.name)
    end
end

-- Blizzard's own Send Message / Group Invite fade while ours are up
local function FadeBlizzardButtons(fade)
    for _, key in ipairs({"SendMessageButton", "GroupInviteButton"}) do
        local b = LFGBrowseFrame[key]
        if b then
            if fade then
                if hiddenAlpha[b] == nil then hiddenAlpha[b] = b:GetAlpha() end
                b:SetAlpha(0)
            elseif hiddenAlpha[b] ~= nil then
                b:SetAlpha(hiddenAlpha[b])
                hiddenAlpha[b] = nil
            end
        end
    end
end

-- after every refresh of Blizzard's list, and on every toggle
function M.Update()
    if not LFGBrowseFrame then return end
    M.UpdateBar()
    -- a search running or failed: Blizzard's spinner or message shows
    local show = M.FilterActive() and LFGBrowseFrame:IsShown() and not Locked() and
                     not LFGBrowseFrame.searching and not LFGBrowseFrame.searchFailed
    if not show then
        if overlay then overlay:Hide() end
        FadeBlizzardButtons(false)
        return
    end
    MakeOverlay()
    local entries, solo, mine = M.Matches()
    overlay.entries = entries
    local names = {}
    for _, r in ipairs(ROLES) do if ns.db[r.key] then table.insert(names, r.name) end end
    overlay.header:SetText(("%s: %s  |cFFAAAAAA(%d of %d)|r%s"):format(
        LFG_LIST_CATEGORY_SOLO_PLAYERS or "Players", table.concat(names, ", "), #entries, solo,
        mine and "\n|cFFAAAAAAYour listing is hidden while filtering: light all roles to manage it.|r" or ""))
    if #entries == 0 then
        overlay.empty:SetText(solo == 0 and "No players are listed for this search." or
                                  "No listed players match these roles. Click a lit role to change the filter.")
        overlay.empty:Show()
    else
        overlay.empty:Hide()
    end
    if selected and not SelectedEntry() then selected = nil end
    list.box:SetDataProvider(CreateDataProvider(entries),
                             ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition)
    overlay:Show()
    FadeBlizzardButtons(true)
    UpdateButtons()
end

--------------------------------------------------------------------------
-- the role buttons
--------------------------------------------------------------------------

local function RoleTooltip(button)
    if not GameTooltip then return end
    local r = button.role
    GameTooltip:SetOwner(button, "ANCHOR_TOP")
    GameTooltip:SetText(r.name)
    local hint
    if Locked() then
        hint = "The role filter is off in dungeons, raids and encounters (the game hides this data there)."
    elseif AllOn() then
        hint = "Click: show only " .. r.name:lower()
    elseif ns.db[r.key] then
        hint = "Click: stop showing " .. r.name:lower()
    else
        hint = "Click: also show " .. r.name:lower()
    end
    GameTooltip:AddLine(hint, 1, 1, 1, true)
    GameTooltip:Show()
end

function M.ClickRole(r)
    if AllOn() then
        for _, other in ipairs(ROLES) do ns.db[other.key] = (other == r) end
    else
        ns.db[r.key] = not ns.db[r.key]
        if not (ns.db.lfgTank or ns.db.lfgHealer or ns.db.lfgDamage) then
            for _, other in ipairs(ROLES) do ns.db[other.key] = true end
        end
    end
    selected = nil
    M.Update()
end

function M.UpdateBar()
    if not bar then return end
    local on = ns.IsOn("lfgroles")
    bar:SetShown(on and true or false)
    if not on then return end
    local locked = Locked()
    local all = AllOn()
    for _, b in ipairs(roleButtons) do
        local lit = ns.db[b.role.key] and not locked
        b.icon:SetDesaturated(not lit)
        b.icon:SetAlpha(lit and 1 or 0.35)
        -- all three lit is "no filter": a quieter look
        if all and not locked then b.icon:SetAlpha(0.85) end
    end
end

local function MakeBar()
    if bar then return end
    bar = CreateFrame("Frame", nil, LFGBrowseFrame)
    bar:SetSize(120, 28)
    bar:SetPoint("BOTTOM", LFGBrowseFrame, "BOTTOM", 0, 16)
    bar:SetFrameLevel(LFGBrowseFrame:GetFrameLevel() + 30)
    local label = bar:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    label:SetPoint("LEFT", 0, 0)
    label:SetText("Show:")
    for i, r in ipairs(ROLES) do
        local b = CreateFrame("Button", nil, bar)
        b:SetSize(24, 24)
        b:SetPoint("LEFT", label, "RIGHT", 4 + (i - 1) * 26, 0)
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetAtlas(r.atlas)
        b.icon:SetAllPoints()
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAtlas(r.atlas)
        hl:SetAllPoints()
        hl:SetBlendMode("ADD")
        hl:SetAlpha(0.3)
        b.role = r
        b:SetScript("OnClick", ns.Guard("lfgroles", function(self)
            if Locked() then return end
            M.ClickRole(self.role)
            RoleTooltip(self)
        end))
        b:SetScript("OnEnter", ns.Guard("lfgroles", RoleTooltip))
        b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        roleButtons[i] = b
    end
end

local function Setup()
    if M.ready or not (LFGBrowseFrame and LFGBrowseFrame.ScrollBox) then return end
    M.ready = true
    MakeBar()
    hooksecurefunc(LFGBrowseFrame, "UpdateResults", ns.Guard("lfgroles", M.Update))
    LFGBrowseFrame:HookScript("OnShow", ns.Guard("lfgroles", M.Update))
    LFGBrowseFrame:HookScript("OnHide", ns.Guard("lfgroles", function()
        if overlay then overlay:Hide() end
        FadeBlizzardButtons(false)
    end))
    local f = CreateFrame("Frame")
    for _, event in ipairs({"LFG_LIST_SEARCH_RESULT_UPDATED", "GROUP_ROSTER_UPDATE",
                            "ADDON_RESTRICTION_STATE_CHANGED", "PLAYER_ENTERING_WORLD"}) do
        pcall(f.RegisterEvent, f, event)
    end
    local armed = false
    f:SetScript("OnEvent", function()
        if armed then return end
        armed = true
        C_Timer.After(0, function()
            armed = false
            if LFGBrowseFrame:IsShown() then ns.SafeCall("lfgroles", M.Update) end
        end)
    end)
    M.Update()
end

function M:Init()
    ns.OnAddOnLoaded("Blizzard_GroupFinder_VanillaStyle", function() ns.SafeCall("lfgroles", Setup) end)
end

function M:Apply()
    if M.ready then M.Update() end
end

function M:Status()
    if not M.ready then return "(the Looking For Group window hasn't loaded yet)" end
    local names = {}
    for _, r in ipairs(ROLES) do if ns.db[r.key] then table.insert(names, r.name:lower()) end end
    return AllOn() and "(showing every player)" or ("(showing " .. table.concat(names, ", ") .. ")")
end

ns.RegisterFeature("lfgroles",
    "Looking For Group: tank / healer / damage buttons to show only the players listing the roles you need",
    M)
