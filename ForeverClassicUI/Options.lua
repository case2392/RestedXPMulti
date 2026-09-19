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
    professions = "Classic professions window (Era book, the professions as rows down the page)",
    questlog = "Classic quest log (Era parchment panel on the quest list in Forever's map window)",
    collections = "Classic framing on the Appearances window (Era parchment panel; Era had no transmog)",
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
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", 16, y)
    cb:SetSize(26, 26)
    local label = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    label:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    label:SetWidth(LABEL_WIDTH)
    label:SetJustifyH("LEFT")
    if label.SetWordWrap then label:SetWordWrap(true) end
    label:SetText(LABELS[key] or key)
    cb.label = label
    cb.key = key
    cb:SetScript("OnClick", function(self)
        SetPart(self.key, self:GetChecked() and true or false)
        if panel and panel.RefreshStatus then panel.RefreshStatus() end
    end)
    local h = label.GetStringHeight and label:GetStringHeight() or 0
    return cb, math.max(30, h + 12)
end

local function MakeAllButton(parent, anchor, text, on)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(110, 22)
    b:SetText(text)
    b:SetScript("OnClick", function()
        for _, key in ipairs(ns.moduleOrder) do SetPart(key, on) end
        if panel and panel.Refresh then panel.Refresh() end
    end)
    if anchor then b:SetPoint("LEFT", anchor, "RIGHT", 6, 0) end
    return b
end

function ns.BuildOptionsPanel()
    if panel or not CreateFrame then return panel end
    panel = CreateFrame("Frame", "ForeverClassicUIOptionsPanel")
    panel.name = "Classic UI for Forever"

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Classic UI for Forever")
    local sub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    sub:SetText("Tick what should look classic. Turning something off takes effect after /reload. Slash: /cui")

    panel.selectAll = MakeAllButton(panel, nil, "Select all", true)
    panel.selectAll:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -8)
    panel.deselectAll = MakeAllButton(panel, panel.selectAll, "Deselect all", false)

    panel.checks = {}
    local y = -96
    for _, key in ipairs(ns.moduleOrder) do
        local cb, rowHeight = MakeCheck(panel, y, key)
        panel.checks[key] = cb
        y = y - rowHeight
    end

    -- not a look setting: the bug-report button and the window that
    -- explains how to send one
    local bug = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    bug:SetPoint("TOPLEFT", 16, y)
    bug:SetSize(26, 26)
    local bugLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    bugLabel:SetPoint("LEFT", bug, "RIGHT", 4, 0)
    bugLabel:SetWidth(LABEL_WIDTH)
    bugLabel:SetJustifyH("LEFT")
    bugLabel:SetText("Minimap button for bug reports (and a notice when something errors)")
    bug:SetScript("OnClick", function(self)
        if ns.SetMinimapButton then ns.SetMinimapButton(self:GetChecked() and true or false) end
    end)
    panel.bugButton = bug
    y = y - 30

    local howto = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    howto:SetPoint("TOPLEFT", 20, y - 4)
    howto:SetSize(200, 24)
    howto:SetText("How to report a bug")
    howto:SetScript("OnClick", function()
        if ns.ShowWelcome then ns.SafeCall("welcome", ns.ShowWelcome) end
    end)
    y = y - 34

    local status = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    status:SetPoint("TOPLEFT", 20, y - 8)
    status:SetWidth(LABEL_WIDTH + 30)
    status:SetJustifyH("LEFT")
    if status.SetWordWrap then status:SetWordWrap(true) end
    panel.status = status

    local probe = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    probe:SetPoint("TOPLEFT", status, "BOTTOMLEFT", 0, -16)
    probe:SetSize(200, 24)
    probe:SetText("Support report (copy & send)")
    probe:SetScript("OnClick", function()
        if ns.ShowReport then ns.SafeCall("report", ns.ShowReport) end
    end)

    local reload = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    reload:SetPoint("LEFT", probe, "RIGHT", 8, 0)
    reload:SetSize(120, 24)
    reload:SetText("Reload UI")
    reload:SetScript("OnClick", function() if ReloadUI then ReloadUI() end end)

    function panel.RefreshStatus()
        local lines = {}
        for _, key in ipairs(ns.moduleOrder) do
            local mod = ns.modules[key]
            local state = ns.db[key] == false and "off" or "on"
            lines[#lines + 1] = ("%s: %s %s"):format(key, state, mod.Status and mod:Status() or "")
        end
        if #ns.errors > 0 then
            lines[#lines + 1] = ("%d error(s) this session - send the probe report."):format(#ns.errors)
        end
        panel.status:SetText(table.concat(lines, "\n"))
    end

    function panel.Refresh()
        if not ns.db then return end
        for key, cb in pairs(panel.checks) do
            cb:SetChecked(ns.db[key] ~= false)
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
