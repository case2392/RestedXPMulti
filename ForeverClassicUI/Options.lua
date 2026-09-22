-- Forever Classic UI - options panel (Options > AddOns > Forever Classic UI)
-- One checkbox per part, plus probe and reload buttons.

local addonName, ns = ...

local LABELS = {
    nameplates = "Classic nameplates (rounded border, level in the border, small cast bar)",
    castbar = "Classic cast bars (player and target)",
    combo = "Classic combo points on the target frame",
    unitframes = "Classic player, target and pet frames",
    party = "Classic party frames (UI-PartyFrame art, 70x8 bars, small pet frames)",
    charsheet = "Classic character sheet (Era paper doll, reputation, skills, honor, currency and statistics, tabs along the bottom)",
    spellbook = "Classic spellbook (Era book, 12 spells a page, skill line tabs on the right)",
    talents = "Classic talents (Era's talent frame: one tree at a time, its painting behind, branches and arrows, tabs along the bottom)",
    professions = "Classic professions window (Era book, the professions as rows down the page)",
    questlog = "Classic quest log (Era parchment panel on the quest list in Forever's map window)",
    collections = "Classic framing on the Appearances window (Era parchment panel; Era had no transmog)",
    guild = "Classic framing on the Guild & Communities window (Era parchment panel; Era's guild was a friends tab)",
    actionbars = "Classic bottom bar (stone bar, 36px buttons, micro buttons and bags on the bar, XP bar in the bar)",
    minimap = "Classic round minimap with the ring border",
    tracker = "Plain quest tracker (retail header boxes hidden)"
}

local panel

-- switch one part on or off: saved setting (file + CVar fallback) and module enable/disable
local function SetPart(key, on)
    ns.SetPart(key, on)
end

local LABEL_WIDTH = 560   -- the panel is ~640 wide on the AddOns page; long labels wrap

-- returns the check button and the height its row needs
local function MakeCheck(parent, y, key)
    local soon = ns.IsComingSoon and ns.IsComingSoon(key)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", 16, y)
    cb:SetSize(26, 26)
    -- a part that is not finished is shown, so it is clear it is coming,
    -- but greyed and dead to the mouse: there is nothing worth turning on
    local font = soon and "GameFontDisable" or "GameFontHighlight"
    local label = parent:CreateFontString(nil, "ARTWORK", font)
    label:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    label:SetWidth(LABEL_WIDTH)
    label:SetJustifyH("LEFT")
    if label.SetWordWrap then label:SetWordWrap(true) end
    local text = LABELS[key] or key
    if soon then text = "|cFFFFD100Coming soon:|r " .. text end
    label:SetText(text)
    cb.label = label
    cb.key = key
    cb.comingSoon = soon or nil
    if soon then
        cb:SetChecked(false)
        if cb.Disable then cb:Disable() end
        cb:SetScript("OnClick", function(self) self:SetChecked(false) end)
    else
        cb:SetScript("OnClick", function(self)
            SetPart(self.key, self:GetChecked() and true or false)
            if panel and panel.RefreshStatus then panel.RefreshStatus() end
        end)
    end
    local h = label.GetStringHeight and label:GetStringHeight() or 0
    return cb, math.max(30, h + 12)
end

local function MakeAllButton(parent, anchor, text, on)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(110, 22)
    b:SetText(text)
    b:SetScript("OnClick", function()
        for _, key in ipairs(ns.moduleOrder) do
            if not (ns.IsComingSoon and ns.IsComingSoon(key)) then SetPart(key, on) end
        end
        if panel and panel.Refresh then panel.Refresh() end
    end)
    if anchor then b:SetPoint("LEFT", anchor, "RIGHT", 6, 0) end
    return b
end

-- The page is taller than the AddOns window and there are more parts every
-- release, so the whole lot lives on a scroll child rather than running off
-- the bottom of the frame. If the scroll template is missing the content
-- goes straight on the panel, exactly as it used to.
local function BuildScroll(parent)
    local ok, scroll = pcall(CreateFrame, "ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    if not ok or not scroll or not scroll.SetScrollChild then return nil, parent end
    scroll:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -8)
    -- room on the right for the scroll bar the template brings
    scroll:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -28, 8)
    local ok2, content = pcall(CreateFrame, "Frame", nil, scroll)
    if not ok2 or not content then return nil, parent end
    content:SetSize(600, 10)
    scroll:SetScrollChild(content)
    -- the canvas is sized by the Settings frame, not by us: the child
    -- follows whatever width it ends up with so the labels wrap to fit
    local function Fit()
        local w = scroll.GetWidth and scroll:GetWidth()
        if type(w) == "number" and w > 1 then content:SetWidth(w) end
    end
    if scroll.HookScript then scroll:HookScript("OnSizeChanged", Fit) end
    Fit()
    return scroll, content
end

function ns.BuildOptionsPanel()
    if panel or not CreateFrame then return panel end
    panel = CreateFrame("Frame", "ForeverClassicUIOptionsPanel")
    panel.name = "Classic UI for Forever"

    local scroll, body = BuildScroll(panel)
    panel.scroll, panel.body = scroll, body

    local title = body:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Classic UI for Forever")
    local sub = body:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    sub:SetText("Tick what should look classic. Turning something off takes effect after /reload. Slash: /cui")

    panel.selectAll = MakeAllButton(body, nil, "Select all", true)
    panel.selectAll:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -8)
    panel.deselectAll = MakeAllButton(body, panel.selectAll, "Deselect all", false)

    panel.checks = {}
    local y = -96
    for _, key in ipairs(ns.moduleOrder) do
        local cb, rowHeight = MakeCheck(body, y, key)
        panel.checks[key] = cb
        y = y - rowHeight
    end

    -- not a look setting: the bug-report button and the window that
    -- explains how to send one
    local bug = CreateFrame("CheckButton", nil, body, "UICheckButtonTemplate")
    bug:SetPoint("TOPLEFT", 16, y)
    bug:SetSize(26, 26)
    local bugLabel = body:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    bugLabel:SetPoint("LEFT", bug, "RIGHT", 4, 0)
    bugLabel:SetWidth(LABEL_WIDTH)
    bugLabel:SetJustifyH("LEFT")
    bugLabel:SetText("Minimap button for bug reports (and a notice when something errors)")
    bug:SetScript("OnClick", function(self)
        if ns.SetMinimapButton then ns.SetMinimapButton(self:GetChecked() and true or false) end
    end)
    panel.bugButton = bug
    y = y - 30

    local howto = CreateFrame("Button", nil, body, "UIPanelButtonTemplate")
    howto:SetPoint("TOPLEFT", 20, y - 4)
    howto:SetSize(200, 24)
    howto:SetText("How to report a bug")
    howto:SetScript("OnClick", function()
        if ns.ShowWelcome then ns.SafeCall("welcome", ns.ShowWelcome) end
    end)
    y = y - 34

    local status = body:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    status:SetPoint("TOPLEFT", 20, y - 8)
    status:SetWidth(LABEL_WIDTH + 30)
    status:SetJustifyH("LEFT")
    if status.SetWordWrap then status:SetWordWrap(true) end
    panel.status = status

    local probe = CreateFrame("Button", nil, body, "UIPanelButtonTemplate")
    probe:SetPoint("TOPLEFT", status, "BOTTOMLEFT", 0, -16)
    probe:SetSize(200, 24)
    probe:SetText("Support report (copy & send)")
    probe:SetScript("OnClick", function()
        if ns.ShowReport then ns.SafeCall("report", ns.ShowReport) end
    end)

    local reload = CreateFrame("Button", nil, body, "UIPanelButtonTemplate")
    reload:SetPoint("LEFT", probe, "RIGHT", 8, 0)
    reload:SetSize(120, 24)
    reload:SetText("Reload UI")
    reload:SetScript("OnClick", function() if ReloadUI then ReloadUI() end end)

    -- the other add-ons, under the buttons; the status text above grows,
    -- so this block hangs off the probe button rather than a fixed y
    local linksHolder = CreateFrame("Frame", nil, body)
    linksHolder:SetPoint("TOPLEFT", probe, "BOTTOMLEFT", -4, -16)
    linksHolder:SetSize(600, 90)
    local linksBottom
    if ns.BuildAddonLinks then linksBottom, panel.links = ns.BuildAddonLinks(linksHolder, 0) end
    panel.linksHolder = linksHolder

    -- the child has to be as tall as what is on it or there is nothing to
    -- scroll; the status text grows as parts are added, so it is measured
    -- again whenever that text is rebuilt
    panel.contentBottom = y - 70 - (linksBottom and -linksBottom or 0) - 16
    function panel.FitContent()
        if body == panel or not body.SetHeight then return end
        local extra = panel.status and panel.status.GetStringHeight and panel.status:GetStringHeight() or 0
        body:SetHeight(math.max(10, -panel.contentBottom + (extra or 0)))
    end
    panel.FitContent()

    function panel.RefreshStatus()
        local lines = {}
        for _, key in ipairs(ns.moduleOrder) do
            local mod = ns.modules[key]
            local state = ns.db[key] == false and "off" or "on"
            local detail = mod.Status and mod:Status() or ""
            if ns.IsComingSoon and ns.IsComingSoon(key) then
                state, detail = "coming soon", "not finished yet, so off for now"
            end
            lines[#lines + 1] = ("%s: %s %s"):format(key, state, detail)
        end
        if #ns.errors > 0 then
            lines[#lines + 1] = ("%d error(s) this session - send the probe report."):format(#ns.errors)
        end
        panel.status:SetText(table.concat(lines, "\n"))
        if panel.FitContent then panel.FitContent() end
    end

    function panel.Refresh()
        if not ns.db then return end
        for key, cb in pairs(panel.checks) do
            cb:SetChecked(not cb.comingSoon and ns.db[key] ~= false)
        end
        if panel.bugButton then panel.bugButton:SetChecked(ns.db.bugbutton ~= false) end
        panel.RefreshStatus()
    end
    panel:SetScript("OnShow", panel.Refresh)
    panel.OnRefresh = panel.Refresh
    panel.Refresh()

    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
        Settings.RegisterAddOnCategory(category)
        panel.categoryID = category and category.ID or category
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end
    ns.optionsPanel = panel
    return panel
end

function ns.OpenOptions()
    local p = ns.BuildOptionsPanel()
    if not p then return end
    if Settings and Settings.OpenToCategory and p.categoryID then
        Settings.OpenToCategory(p.categoryID)
    elseif InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(p)
    end
end
