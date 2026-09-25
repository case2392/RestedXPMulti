-- Forever Classic UI - making a bug report easy to hand over
--
-- An addon cannot send anything anywhere: the client gives Lua no network
-- of any kind, and a screenshot it takes is saved into the game's own
-- Screenshots folder and stays there. So the most that can be done is to
-- put the report one click away and say plainly where to paste it:
--   * a welcome window the first time the addon runs on an account;
--   * a minimap button that opens the report;
--   * a notice the first time something errors in a session, with the
--     same button on it;
--   * the page to paste it on written at the top of the report itself.

local addonName, ns = ...

-- the page people are already commenting on; /cui link prints it
ns.FEEDBACK_URL = "https://www.curseforge.com/wow/addons/classic-ui-for-forever"
-- the report carries the whole client and every open frame, so it can run
-- past what a CurseForge comment will take. Someone hit that, so there is
-- somewhere else to put it.
ns.FEEDBACK_EMAIL = "classicuiforforever@gmail.com"

local ICON = "Interface\\Spellbook\\Spellbook-Icon"
local RING = "Interface\\Minimap\\MiniMap-TrackingBorder"
local RING_FALLBACK = "Interface\\Minimap\\UI-Minimap-Border"
local HIGHLIGHT = "Interface\\Buttons\\ButtonHilight-Square"
local DEFAULT_ANGLE = 198        -- lower left of the ring, clear of the clock
local RADIUS = 80

local function HasFile(path)
    if not GetFileIDFromPath then return true end
    local ok, id = pcall(GetFileIDFromPath, path)
    return ok and id ~= nil
end

local function Guard(label, fn)
    return function(...)
        local ok, err = pcall(fn, ...)
        if not ok then ns.errors[#ns.errors + 1] = "feedback " .. label .. ": " .. tostring(err) end
    end
end

local WELCOME_LINES = {
    "Thank you for installing Classic UI (Forever).",
    "",
    "Forever is in beta and so is this addon. Two things are worth a report, and both take the same minute:",
    "",
    "|cffffd100Something looks wrong.|r A frame in the wrong place, art that did not load, an error on screen.",
    "|cffffd100A window is still the modern one.|r Whole parts are not built yet, because they cannot be seen without a character who has reached them: anything past level 25. A screenshot of that window is what gets it built.",
    "",
    "To send either one:",
    "",
    "1. Click the book button on your minimap, or type |cffffd100/cui report|r.",
    "2. Press Ctrl+A then Ctrl+C in that window to copy the text. It already carries your client build, which parts are on, and every error this session.",
    "3. Take a screenshot of the window or the thing that looks wrong. The button below saves one into your WoW Screenshots folder.",
    "4. Paste the text, and the screenshot, as a comment on the page below.",
    "",
    "|cffffd100If the report is too long for a comment|r - it can be, it carries every open window - email it instead, to the address below. Either one reaches me.",
    "",
    "If the window you are reporting is open when you take the report, its whole layout comes with it, which is usually enough to build the classic version.",
    "",
    "Reports are usually turned around within a day. Nothing is sent anywhere on its own: an addon cannot, so this is all by your hand."
}

--------------------------------------------------------------------------
-- the report window, one call from anywhere
--------------------------------------------------------------------------

local function OpenReport()
    if ns.ShowReport then ns.SafeCall("report", ns.ShowReport) end
end

local function TakeScreenshot()
    if Screenshot then
        pcall(Screenshot)
        ns.Print("screenshot saved in your WoW Screenshots folder.")
    else
        ns.Print("this client has no screenshot command: use PrintScreen.")
    end
end

ns.OpenReport = OpenReport
ns.TakeScreenshot = TakeScreenshot

--------------------------------------------------------------------------
-- the welcome window
--------------------------------------------------------------------------

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

ns.LinkBox = LinkBox

-- the author's other add-ons, with their pages in a box the player can
-- copy from (the game opens no browser, so a copyable address is the link)
ns.OTHER_ADDONS = {
    {name = "Classic UI (Forever)", url = ns.FEEDBACK_URL, mine = true},
    {name = "Adventure Plates", url = "https://www.curseforge.com/wow/addons/adventure-plates", blurb = "an adventurer card for your character, like FFXIV's"}
}

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

local function Button(parent, text, width, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    if b.SetText then b:SetText(text) end
    b:SetScript("OnClick", onClick)
    return b
end

local function BuildWelcome()
    local f = CreateFrame("Frame", "ForeverClassicUIWelcome", UIParent, "BackdropTemplate")
    f:SetSize(480, 560)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    if f.SetBackdrop then
        f:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = {left = 11, right = 12, top = 12, bottom = 11}
        })
    end
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.title:SetPoint("TOP", f, "TOP", 0, -18)
    f.title:SetText("Classic UI (Forever)")

    f.body = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    f.body:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -48)
    f.body:SetWidth(436)
    f.body:SetJustifyH("LEFT")
    f.body:SetJustifyV("TOP")
    if f.body.SetWordWrap then f.body:SetWordWrap(true) end
    f.body:SetText(table.concat(WELCOME_LINES, "\n"))

    f.linkLabel = f:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    f.linkLabel:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 22, 132)
    f.linkLabel:SetText("Paste it here (click to select, Ctrl+C to copy):")
    f.link = LinkBox(f, 420, ns.FEEDBACK_URL)
    f.link:SetPoint("TOPLEFT", f.linkLabel, "BOTTOMLEFT", 6, -6)

    f.mailLabel = f:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    f.mailLabel:SetPoint("TOPLEFT", f.link, "BOTTOMLEFT", -6, -10)
    f.mailLabel:SetText("Or email it, if it is too long for a comment:")
    f.mail = LinkBox(f, 420, ns.FEEDBACK_EMAIL)
    f.mail:SetPoint("TOPLEFT", f.mailLabel, "BOTTOMLEFT", 6, -6)

    f.report = Button(f, "Open the report", 130, Guard("welcome report", OpenReport))
    f.report:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 22, 18)
    f.shot = Button(f, "Take a screenshot", 140, Guard("welcome shot", TakeScreenshot))
    f.shot:SetPoint("LEFT", f.report, "RIGHT", 8, 0)
    f.close = Button(f, "Got it", 100, Guard("welcome close", function()
        ns.SetWelcomed(true)
        f:Hide()
    end))
    f.close:SetPoint("LEFT", f.shot, "RIGHT", 8, 0)

    local x = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    x:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -6)
    x:SetScript("OnClick", Guard("welcome x", function()
        ns.SetWelcomed(true)
        f:Hide()
    end))
    f:Hide()
    return f
end

function ns.SetWelcomed(on)
    if ns.db then
        ns.db.welcomed = on and true or false
        if ns.SaveFallback then ns.SaveFallback() end
    end
end

function ns.ShowWelcome()
    if not (CreateFrame and UIParent) then return end
    ns.welcomeFrame = ns.welcomeFrame or BuildWelcome()
    ns.welcomeFrame:Show()
    return ns.welcomeFrame
end

--------------------------------------------------------------------------
-- the minimap button
--------------------------------------------------------------------------

local function Angle()
    local a = tonumber(ns.db and ns.db.minimapAngle) or DEFAULT_ANGLE
    return a
end

local function PlaceButton(button)
    local a = math.rad(Angle())
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", RADIUS * math.cos(a), RADIUS * math.sin(a))
end

local function DragUpdate(button)
    if not (GetCursorPosition and Minimap.GetCenter) then return end
    local scale = UIParent:GetEffectiveScale()
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    if not (mx and cx) then return end
    cx, cy = cx / scale, cy / scale
    local angle = math.deg(math.atan2(cy - my, cx - mx))
    if ns.db then ns.db.minimapAngle = angle end
    PlaceButton(button)
end

local function BuildMinimapButton()
    if not (CreateFrame and Minimap) then return end
    local b = CreateFrame("Button", "ForeverClassicUIMinimapButton", Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    if b.SetFrameLevel and Minimap.GetFrameLevel then b:SetFrameLevel(Minimap:GetFrameLevel() + 8) end
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")

    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetTexture(ICON)
    b.icon:SetSize(20, 20)
    b.icon:SetPoint("CENTER", b, "CENTER", 0, 1)

    b.ring = b:CreateTexture(nil, "OVERLAY")
    b.ring:SetTexture(HasFile(RING) and RING or RING_FALLBACK)
    b.ring:SetSize(53, 53)
    b.ring:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)

    b:SetHighlightTexture(HIGHLIGHT, "ADD")

    b:SetScript("OnClick", Guard("minimap click", function(_, mouse)
        if mouse == "RightButton" and ns.OpenOptions then
            ns.SafeCall("options", ns.OpenOptions)
        else
            OpenReport()
        end
    end))
    b:SetScript("OnDragStart", function(self)
        self.dragging = true
        self:SetScript("OnUpdate", Guard("minimap drag", DragUpdate))
    end)
    b:SetScript("OnDragStop", function(self)
        self.dragging = nil
        self:SetScript("OnUpdate", nil)
        if ns.SaveFallback then ns.SaveFallback() end
    end)
    b:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Classic UI (Forever)")
        GameTooltip:AddLine("Left click: the bug report window")
        GameTooltip:AddLine("Right click: settings")
        GameTooltip:AddLine("Drag: move me round the minimap")
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    PlaceButton(b)
    return b
end

function ns.SetMinimapButton(on)
    if ns.db then
        ns.db.bugbutton = on and true or false
        if ns.SaveFallback then ns.SaveFallback() end
    end
    if on then
        ns.minimapButton = ns.minimapButton or BuildMinimapButton()
        if ns.minimapButton then
            PlaceButton(ns.minimapButton)
            ns.minimapButton:Show()
        end
    elseif ns.minimapButton then
        ns.minimapButton:Hide()
    end
    return ns.minimapButton
end

--------------------------------------------------------------------------
-- the first error of a session says so
--------------------------------------------------------------------------

local function BuildNotice()
    local f = CreateFrame("Frame", "ForeverClassicUIErrorNotice", UIParent, "BackdropTemplate")
    f:SetSize(380, 120)
    f:SetPoint("TOP", UIParent, "TOP", 0, -120)
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    if f.SetBackdrop then
        f:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = {left = 11, right = 12, top = 12, bottom = 11}
        })
    end
    f.text = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    f.text:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -18)
    f.text:SetWidth(344)
    f.text:SetJustifyH("LEFT")
    if f.text.SetWordWrap then f.text:SetWordWrap(true) end
    f.text:SetText("Classic UI (Forever) hit an error. Open the report and paste it on the addon page, or email it to " .. tostring(ns.FEEDBACK_EMAIL) .. " if it is too long for a comment: that is how it gets fixed.")
    f.report = Button(f, "Open the report", 130, Guard("notice report", function()
        OpenReport()
        f:Hide()
    end))
    f.report:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 18, 14)
    f.later = Button(f, "Not now", 90, function() f:Hide() end)
    f.later:SetPoint("LEFT", f.report, "RIGHT", 8, 0)
    f:Hide()
    return f
end

function ns.ShowErrorNotice()
    if ns.noticeShown or not (CreateFrame and UIParent) then return end
    -- once a session: a second one would be noise, the report holds them all
    ns.noticeShown = true
    ns.errorNotice = ns.errorNotice or BuildNotice()
    ns.errorNotice:Show()
    return ns.errorNotice
end

-- ns.errors is a plain list every part appends to, and ns.luaErrors is
-- what the error handler in Core collects. Watching both here keeps the
-- modules unaware of any of this. __newindex fires on each new slot and
-- rawset keeps the list a plain array, so everything that reads it (the
-- report, the options panel) is untouched.
local function Watch(list, wanted)
    if not list or getmetatable(list) then return end
    setmetatable(list, {__newindex = function(t, key, value)
        rawset(t, key, value)
        local ok = true
        if wanted then
            local text = type(value) == "table" and value.msg or value
            ok = type(text) == "string" and text:find(wanted, 1, true) ~= nil
        end
        if ok and (ns.db == nil or ns.db.bugbutton ~= false) then
            pcall(ns.ShowErrorNotice)
        end
    end})
end

local function WatchErrors()
    if ns.errorsWatched then return end
    ns.errorsWatched = true
    Watch(ns.errors)
    Watch(ns.luaErrors, addonName)
end

--------------------------------------------------------------------------
-- login
--------------------------------------------------------------------------

function ns.FeedbackLogin()
    WatchErrors()
    if not ns.db or ns.db.bugbutton ~= false then ns.SetMinimapButton(true) end
    if ns.db and ns.db.welcomed ~= true then
        -- let the loading screen finish first
        if C_Timer and C_Timer.After then
            C_Timer.After(4, Guard("welcome", ns.ShowWelcome))
        else
            ns.ShowWelcome()
        end
    end
end
