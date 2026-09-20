-- Adventure Plates - options panel (Options > AddOns > Adventure Plates)

local addonName, ns = ...

local panel

local SHARE = {
    {key = "everyone", label = "Anyone who asks may see my plate"},
    {key = "friends", label = "Only friends, guildmates and my group may see it"},
    {key = "off", label = "Nobody (my plate stays on this computer)"}
}

local function Check(parent, y, label, get, set)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", 16, y)
    cb:SetSize(26, 26)
    local text = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    text:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    text:SetText(label)
    cb:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
    cb.Refresh = function(self) self:SetChecked(get()) end
    return cb
end

function ns.BuildOptionsPanel()
    if panel or not CreateFrame then return panel end
    panel = CreateFrame("Frame", "AdventurePlatesOptionsPanel")
    panel.name = "Adventure Plates"
    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Adventure Plates")
    local sub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    sub:SetText("/plate opens yours, /plate <name> asks for someone else's. Both players need the addon.")

    local shareLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    shareLabel:SetPoint("TOPLEFT", 16, -60)
    shareLabel:SetText("Who may look at my plate")
    panel.share = {}
    local y = -84
    for _, entry in ipairs(SHARE) do
        local cb = Check(panel, y, entry.label,
            function() return ns.db.settings.share == entry.key end,
            function() ns.db.settings.share = entry.key; panel.Refresh() end)
        cb.key = entry.key
        panel.share[entry.key] = cb
        y = y - 28
    end
    y = y - 10
    panel.menu = Check(panel, y, "Add \"View Adventure Plate\" to a player's right-click menu (takes effect after /reload)",
        function() return ns.db.settings.menu end,
        function(v) ns.db.settings.menu = v end)
    y = y - 28
    panel.greet = Check(panel, y, "Tell me in chat when someone looks at my plate",
        function() return ns.db.settings.greet end,
        function(v) ns.db.settings.greet = v end)
    y = y - 40
    local open = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    open:SetSize(160, 24)
    open:SetPoint("TOPLEFT", 16, y)
    open:SetText("Open my plate")
    open:SetScript("OnClick", function() ns.ShowOwnPlate() end)

    function panel.Refresh()
        for _, cb in pairs(panel.share) do cb:Refresh() end
        panel.menu:Refresh()
        panel.greet:Refresh()
    end
    panel:SetScript("OnShow", panel.Refresh)
    panel.Refresh()

    if Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
        Settings.RegisterAddOnCategory(category)
        panel.category = category
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end
    ns.optionsPanel = panel
    return panel
end

function ns.OpenOptions()
    if not panel then ns.BuildOptionsPanel() end
    if panel and panel.category and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(panel.category.ID)
    elseif InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(panel)
    end
end
