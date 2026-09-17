-- RIP Bozo - options panel (Options > AddOns > RIP Bozo)

local addonName, ns = ...

local CHECKS = {
    {key = "guild", label = "Whisper guildmates when they die"},
    {key = "friends", label = "Whisper friends (friends list + Battle.net) when they die"},
    {key = "party", label = "Whisper party / raid members when they die"},
    {key = "everyone", label = "Whisper everyone on the realm when they die"},
    {key = "self", label = "Roast me in chat when I die"}
}

local panel

local function MakeCheck(parent, y, entry)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", 16, y)
    cb:SetSize(26, 26)
    local label = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    label:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    label:SetText(entry.label)
    cb.key = entry.key
    cb:SetScript("OnClick", function(self)
        ns.db[self.key] = self:GetChecked() and true or false
        if ns.OnOptionChanged then ns.OnOptionChanged(self.key) end
    end)
    return cb
end

function ns.BuildOptionsPanel()
    if panel or not CreateFrame then return panel end
    panel = CreateFrame("Frame", "RIPBozoOptionsPanel")
    panel.name = "RIP Bozo"

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("RIP Bozo")
    local sub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    sub:SetText("Hardcore death roasts. Slash commands: /rip and /ripbozo")

    panel.checks = {}
    local y = -64
    for _, entry in ipairs(CHECKS) do
        panel.checks[entry.key] = MakeCheck(panel, y, entry)
        y = y - 30
    end

    -- what to send: plain RIPBOZO or the roast lines (radio-style pair)
    local modeLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    modeLabel:SetPoint("TOPLEFT", 16, y - 6)
    modeLabel:SetText("What to whisper")
    y = y - 30
    panel.modes = {}
    local MODES = {
        {key = "ripbozo", label = "Just say RIPBOZO"},
        {key = "lines", label = "Use the built-in roasts and my custom lines"}
    }
    for _, entry in ipairs(MODES) do
        local cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
        cb:SetPoint("TOPLEFT", 16, y)
        cb:SetSize(26, 26)
        local label = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        label:SetPoint("LEFT", cb, "RIGHT", 4, 0)
        label:SetText(entry.label)
        cb.mode = entry.key
        cb:SetScript("OnClick", function(self)
            ns.db.mode = self.mode
            for _, other in pairs(panel.modes) do
                other:SetChecked(other.mode == self.mode)
            end
        end)
        panel.modes[entry.key] = cb
        y = y - 30
    end

    -- minimum level for everyone mode
    local ok, slider = pcall(CreateFrame, "Slider", "RIPBozoMinLevelSlider", panel,
                             "UISliderTemplate")
    if not ok or not slider then slider = CreateFrame("Slider", nil, panel) end
    slider:SetPoint("TOPLEFT", 20, y - 24)
    slider:SetSize(200, 16)
    slider:SetOrientation("HORIZONTAL")
    slider:SetMinMaxValues(1, 60)
    slider:SetValueStep(1)
    if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
    local sliderLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    sliderLabel:SetPoint("BOTTOMLEFT", slider, "TOPLEFT", 0, 6)
    slider.label = sliderLabel
    slider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value + 0.5)
        ns.db.minLevel = value
        self.label:SetText(("Everyone mode ignores deaths below level %d"):format(value))
    end)
    panel.slider = slider

    local note = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    note:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", 0, -12)
    note:SetWidth(520)
    note:SetJustifyH("LEFT")
    note:SetText("Everyone mode whispers strangers. One whisper per death, never the same person twice. Unsolicited whispers can get reported, so keep it to banter.")

    local test = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    test:SetPoint("TOPLEFT", note, "BOTTOMLEFT", 0, -16)
    test:SetSize(140, 24)
    test:SetText("Print a test line")
    test:SetScript("OnClick", function() ns.Print(ns.LineFor(nil)) end)

    function panel.Refresh()
        if not ns.db then return end
        for key, cb in pairs(panel.checks) do
            cb:SetChecked(ns.db[key] and true or false)
        end
        panel.slider:SetValue(ns.db.minLevel or 10)
        for key, cb in pairs(panel.modes) do
            cb:SetChecked((ns.db.mode or "lines") == key)
        end
    end
    panel:SetScript("OnShow", panel.Refresh)
    panel.OnRefresh = panel.Refresh

    if Settings and Settings.RegisterCanvasLayoutCategory and
        Settings.RegisterAddOnCategory then
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
