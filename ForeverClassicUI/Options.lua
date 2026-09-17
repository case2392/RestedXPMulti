-- Forever Classic UI - options panel (Options > AddOns > Forever Classic UI)
-- One checkbox per part, plus probe and reload buttons.

local addonName, ns = ...

local LABELS = {
    nameplates = "Classic nameplates (rounded border, level in the border, small cast bar)",
    castbar = "Classic cast bars (player and target)",
    combo = "Classic combo points on the target frame",
    unitframes = "Classic player and target frames",
    actionbars = "Classic main action bar art (stone bar under the buttons, gryphons)",
    minimap = "Classic round minimap with the ring border"
}

local panel

local function MakeCheck(parent, y, key)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", 16, y)
    cb:SetSize(26, 26)
    local label = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    label:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    label:SetText(LABELS[key] or key)
    cb.key = key
    cb:SetScript("OnClick", function(self)
        local on = self:GetChecked() and true or false
        ns.db[self.key] = on
        local mod = ns.modules[self.key]
        if on then
            if mod and mod.Enable then ns.SafeCall(self.key, mod.Enable, mod) end
        else
            if mod and mod.Disable then ns.SafeCall(self.key, mod.Disable, mod) end
        end
        if panel and panel.RefreshStatus then panel.RefreshStatus() end
    end)
    return cb
end

function ns.BuildOptionsPanel()
    if panel or not CreateFrame then return panel end
    panel = CreateFrame("Frame", "ForeverClassicUIOptionsPanel")
    panel.name = "Forever Classic UI"

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Forever Classic UI")
    local sub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    sub:SetText("Tick what should look classic. Turning something off takes effect after /reload. Slash: /cui")

    panel.checks = {}
    local y = -64
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
    probe:SetSize(160, 24)
    probe:SetText("Probe report")
    probe:SetScript("OnClick", function()
        if ns.ShowProbe then ns.SafeCall("probe", ns.ShowProbe) end
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
