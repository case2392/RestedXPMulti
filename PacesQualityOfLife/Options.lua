-- Pace's Quality of Life - options page (Options > AddOns > Pace's Quality
-- of Life, or /pqol): one checkbox per feature.

local addonName, ns = ...

local TITLE = "Pace's Quality of Life"
local LABEL_WIDTH = 560

local panel
local checks = {}

local function MakeCheck(parent, x, y, text, get, set)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", x, y)
    cb:SetSize(26, 26)
    local label = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    label:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    label:SetWidth(LABEL_WIDTH - x)
    label:SetJustifyH("LEFT")
    if label.SetWordWrap then label:SetWordWrap(true) end
    label:SetText(text)
    cb.label = label
    cb.get = get
    cb:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
    table.insert(checks, cb)
    local h = label.GetStringHeight and label:GetStringHeight() or 0
    return cb, math.max(30, h + 12)
end

local function Dim(cb, on)
    if on then cb:Enable() else cb:Disable() end
    cb.label:SetFontObject(on and "GameFontHighlight" or "GameFontDisable")
end

function ns.RefreshOptions()
    for _, cb in ipairs(checks) do cb:SetChecked(cb.get() and true or false) end
    if panel and panel.voiceShare then Dim(panel.voiceShare, ns.IsOn("voice")) end
    local pets = ns.PartyPets
    if panel and panel.petsNote and pets then
        local text, waiting = pets.Note()
        panel.petsNote:SetText(text)
        panel.petsReload:SetShown(waiting and true or false)
        if panel.petsCheck then Dim(panel.petsCheck, pets.Available()) end
    end
    if panel and panel.layoutNote and ns.Layout then panel.layoutNote:SetText(ns.Layout.Note()) end
    if panel and panel.goldNote and ns.Gold then
        local ok, text = pcall(ns.Gold.Note)
        panel.goldNote:SetText(ok and text or "")
        if panel.goldScan then Dim(panel.goldScan, ns.IsOn("gold")) end
    end
end

-- a note under a feature's checkbox, and a button at its right
local function NoteAndButton(y, buttonText, onClick)
    local note = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    note:SetPoint("TOPLEFT", 48, y + 4)
    note:SetWidth(LABEL_WIDTH - 160)
    note:SetJustifyH("LEFT")
    if note.SetWordWrap then note:SetWordWrap(true) end
    local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    button:SetSize(110, 22)
    button:SetPoint("TOPLEFT", LABEL_WIDTH - 96, y + 6)
    button:SetText(buttonText)
    button:SetScript("OnClick", onClick)
    return note, button
end

function ns.BuildOptions()
    if panel then return end
    panel = CreateFrame("Frame")
    panel.name = TITLE

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText(TITLE)
    local sub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    sub:SetText("v" .. ns.VERSION .. " - small conveniences for WoW Forever's own windows. |cFFFFCC00/pqol|r opens this page.")

    local y = -64
    for _, key in ipairs(ns.featureOrder) do
        local feature = ns.features[key]
        local check, h = MakeCheck(panel, 16, y, feature.label,
                                   function() return ns.IsOn(key) end,
                                   function(on) ns.SetFeature(key, on) end)
        y = y - h
        if key == "partypets" then
            -- what the switch waits for, and a button for the reload
            local note, reload = NoteAndButton(y, "Reload now", function()
                if ns.PartyPets then ns.SafeCall("partypets", ns.PartyPets.ReloadNow) end
            end)
            panel.petsCheck, panel.petsNote, panel.petsReload = check, note, reload
            y = y - 30
        end
        if key == "layout" then
            -- this computer's layout, and a button making the one on now it
            local note, use = NoteAndButton(y, "Use current", function()
                if ns.Layout then
                    ns.SafeCall("layout", function() ns.Print("%s", ns.Layout.UseCurrent()) end)
                end
            end)
            panel.layoutNote, panel.layoutUse = note, use
            y = y - 30
        end
        if key == "gold" then
            -- how fresh the prices are, and a button opening the window
            local note, open = NoteAndButton(y, "Open", function()
                if ns.Gold then ns.SafeCall("gold", ns.Gold.Open or ns.Gold.Toggle) end
            end)
            panel.goldNote, panel.goldOpen = note, open
            y = y - 30
            local cb, h2 = MakeCheck(panel, 44, y,
                "Scan the whole auction house each time I open it (at most every 15 minutes)",
                function() return ns.db.goldScanOnOpen end,
                function(on) ns.db.goldScanOnOpen = on end)
            panel.goldScan = cb
            y = y - h2
        end
        if key == "voice" then
            local cb, h2 = MakeCheck(panel, 44, y,
                "Answer Pace's QoL users who ask whether I'm in a community's voice channel (needed for them to see you; only people who also run Pace's QoL can see anyone)",
                function() return ns.db.voiceShare end,
                function(on)
                    ns.db.voiceShare = on
                    if ns.VoiceShareChanged then ns.SafeCall("voice", ns.VoiceShareChanged) end
                end)
            panel.voiceShare = cb
            y = y - h2
        end
    end

    local status = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    status:SetPoint("TOPLEFT", 20, y - 12)
    status:SetWidth(LABEL_WIDTH)
    status:SetJustifyH("LEFT")
    status:SetText("|cFFFFCC00/pqol status|r lists what's on and any errors this session.")

    panel:SetScript("OnShow", function() ns.RefreshOptions() end)

    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, TITLE)
        Settings.RegisterAddOnCategory(category)
        panel.categoryID = category and (category.GetID and category:GetID() or category.ID)
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end
    ns.RefreshOptions()
end

function ns.OpenOptions()
    if not panel then ns.BuildOptions() end
    if Settings and Settings.OpenToCategory and panel.categoryID then
        Settings.OpenToCategory(panel.categoryID)
    elseif InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(panel)
    end
end

-- the minimap's add-ons button (## AddonCompartmentFunc in the toc)
function PacesQualityOfLife_OnAddonCompartmentClick()
    ns.OpenOptions()
end
