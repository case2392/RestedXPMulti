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
    actionbars = "Classic bottom bar (stone bar, 36px buttons, micro buttons and bags on the bar, XP bar in the bar)",
    minimap = "Classic round minimap with the ring border",
    tracker = "Plain quest tracker (retail header boxes hidden)"
}

local panel

-- switch one part on or off: saved setting (file + CVar fallback) and module enable/disable
local function SetPart(key, on)
    ns.SetPart(key, on)
end

local function MakeCheck(parent, y, key)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", 16, y)
    cb:SetSize(26, 26)
    local label = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    label:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    label:SetText(LABELS[key] or key)
    cb.key = key
    cb:SetScript("OnClick", function(self)
        SetPart(self.key, self:GetChecked() and true or false)
        if panel and panel.RefreshStatus then panel.RefreshStatus() end
    end)
    return cb
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
        panel.checks[key] = MakeCheck(panel, y, key)
        y = y - 30
    end

    local status = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    status:SetPoint("TOPLEFT", 20, y - 8)
    status:SetWidth(560)
    status:SetJustifyH("LEFT")
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
