-- Adventure Plates - options panel (Options > AddOns > Adventure Plates)

local addonName, ns = ...

local panel

local SHARE = {
    {key = "everyone", label = "Anyone who asks may see my plate"},
    {key = "friends", label = "Only friends, guildmates and my group may see it"},
    {key = "off", label = "Nobody (my plate stays on this computer)"}
}

-- the other add-ons, with their pages in a box the player can copy from
-- (the game opens no browser, so a copyable address is the link)
ns.OTHER_ADDONS = {
    {name = "Classic UI for Forever", url = "https://www.curseforge.com/wow/addons/classic-ui-for-forever", blurb = "the Classic Era look on WoW Forever"},
    {name = "Adventure Plates", url = "https://www.curseforge.com/wow/addons/adventure-plates", blurb = "this one", mine = true}
}

local function LinkBox(parent, width, text)
    local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    box:SetSize(width, 20)
    box:SetAutoFocus(false)
    if box.SetFontObject then box:SetFontObject("ChatFontNormal") end
    box:SetText(text)
    box:SetCursorPosition(0)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    -- a link nobody can edit away: any change puts it back
    box:SetScript("OnTextChanged", function(self, user)
        if user then
            self:SetText(text)
            self:HighlightText()
        end
    end)
    box:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    return box
end

-- "More add-ons by RealJustinCase": a heading, then a name and a copyable
-- address per add-on. Returns the y below it.
function ns.BuildAddonLinks(parent, y)
    local head = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    head:SetPoint("TOPLEFT", 16, y)
    head:SetText("More add-ons by RealJustinCase")
    local hint = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    hint:SetPoint("LEFT", head, "RIGHT", 8, 0)
    hint:SetText("(click an address and press Ctrl+C to copy it)")
    y = y - 26
    local links = {}
    for _, a in ipairs(ns.OTHER_ADDONS) do
        local label = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        label:SetPoint("TOPLEFT", 20, y - 2)
        label:SetWidth(180)
        label:SetJustifyH("LEFT")
        label:SetText(a.mine and (a.name .. " (this one)") or a.name)
        local box = LinkBox(parent, 360, a.url)
        box:SetPoint("TOPLEFT", 210, y)
        links[#links + 1] = {name = a.name, url = a.url, box = box, label = label}
        y = y - 26
    end
    return y, links
end

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
    y = y - 28
    panel.minimap = Check(panel, y, "Show the minimap button (left click: my plate, right click: these settings)",
        function() return ns.db.settings.minimap end,
        function(v) ns.SetMinimapButton(v) end)
    y = y - 28
    panel.learn = Check(panel, y, "Note the hours I am logged in, so \"Use my hours\" can fill the playtime rows (kept on this computer only)",
        function() return ns.db.settings.learn end,
        function(v) ns.db.settings.learn = v end)
    y = y - 40
    local open = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    open:SetSize(160, 24)
    open:SetPoint("TOPLEFT", 16, y)
    open:SetText("Open my plate")
    open:SetScript("OnClick", function() ns.ShowOwnPlate() end)
    local welcome = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    welcome:SetSize(160, 24)
    welcome:SetPoint("LEFT", open, "RIGHT", 8, 0)
    welcome:SetText("Show the welcome")
    welcome:SetScript("OnClick", function() ns.ShowWelcome() end)
    local report = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    report:SetSize(160, 24)
    report:SetPoint("LEFT", welcome, "RIGHT", 8, 0)
    report:SetText("Report a bug or an idea")
    report:SetScript("OnClick", function() ns.ShowReport() end)
    panel.open, panel.welcome, panel.report = open, welcome, report
    y = y - 34
    local feedback = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    feedback:SetPoint("TOPLEFT", 16, y)
    feedback:SetWidth(560)
    feedback:SetJustifyH("LEFT")
    feedback:SetText("Bugs and suggestions: post a comment at " .. ns.FEEDBACK_URL .. " or email " .. ns.FEEDBACK_EMAIL .. ". /plate report gives you the details to paste.")
    panel.feedback = feedback
    y = y - 40
    y, panel.links = ns.BuildAddonLinks(panel, y)

    function panel.Refresh()
        for _, cb in pairs(panel.share) do cb:Refresh() end
        panel.menu:Refresh()
        panel.greet:Refresh()
        panel.minimap:Refresh()
        panel.learn:Refresh()
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
