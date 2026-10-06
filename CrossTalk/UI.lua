-- CrossTalk (Forever) - windows
--   the phrase board: one button per phrase, left click says it, right
--   click yells it, the tooltip shows what the other faction will read
--   the calibrate window (sender), the listen window (listener) and the
--   share code box (import / export)

local addonName, ns = ...

local BOARD_W = 268
local PAD = 12
local BTN_W, BTN_H, BTN_GAP = 118, 22, 4

local function SavePosition(f)
    local point, _, relPoint, x, y = f:GetPoint()
    ns.db.pos = ns.db.pos or {}
    ns.db.pos[f:GetName()] = {point, relPoint, x, y}
end

local function Window(name, title, width, strata, x, y)
    local f = CreateFrame("Frame", name, UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(width, 120)
    f:SetFrameStrata(strata or "MEDIUM")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition(self)
    end)
    local pos = ns.db.pos and ns.db.pos[name]
    if pos then
        f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else
        f:SetPoint("CENTER", UIParent, "CENTER", x or 0, y or 80)
    end
    if f.SetBackdrop then
        f:SetBackdrop({
            bgFile = "Interface/BUTTONS/WHITE8X8",
            edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
            edgeSize = 14,
            insets = {left = 3, right = 3, top = 3, bottom = 3}
        })
        f:SetBackdropColor(0.05, 0.05, 0.08, 0.94)
        f:SetBackdropBorderColor(0.6, 0.6, 0.65, 1)
    end
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOP", 0, -10)
    f.title:SetText(title)
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    f.close = close
    return f
end

local function Text(parent, template, width)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
    fs:SetWidth(width)
    fs:SetJustifyH("LEFT")
    if fs.SetWordWrap then fs:SetWordWrap(true) end
    return fs
end

local function Button(parent, label, width, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, BTN_H)
    b:SetText(label)
    b:SetScript("OnClick", onClick)
    return b
end

local function Height(fs)
    return (fs.GetStringHeight and fs:GetStringHeight()) or 12
end

--------------------------------------------------------------------------
-- the phrase board
--------------------------------------------------------------------------

local board

local function TableStatus()
    local lang = ns.MyLanguage()
    local t = ns.Table(lang)
    if not t then
        return ("|cFFFFAA00No %s letter table yet.|r It has to be found once with a player of the other faction: click Calibrate."):format(ns.LanguageName(lang))
    end
    local s = ("%s: %d letters (%s)"):format(ns.LanguageName(lang), t.count or 0, ns.LetterList(t))
    if not ns.TableCurrent(t) then
        s = s .. ("\n|cFFFFAA00found on build %s, you are on %s - calibrate again if they read gibberish|r"):format(tostring(t.build), ns.Build())
    end
    return s
end

local function PhraseTooltip(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(self.phrase, 1, 1, 1)
    local t = ns.Table((ns.MyLanguage()))
    local _, preview = ns.Encode(self.phrase, t)
    if preview then
        GameTooltip:AddLine("They see: " .. preview, 1, 0.4, 0.4, true)
    else
        GameTooltip:AddLine("No letter table yet: calibrate first", 1, 0.6, 0.2, true)
    end
    GameTooltip:AddLine("Left click: /say   Right click: /yell", 0.7, 0.7, 0.7)
    GameTooltip:AddLine("Ctrl-click: remove from the board", 0.5, 0.5, 0.5)
    GameTooltip:Show()
end

local function PhraseClick(self, mouse)
    if IsControlKeyDown and IsControlKeyDown() then
        ns.RemovePhrase(self.phrase)
        return
    end
    ns.Say(self.phrase, mouse == "RightButton" and "YELL" or "SAY")
end

local function BuildBoard()
    board = Window("CrossTalkFrame", "CrossTalk", BOARD_W, "MEDIUM", 360, 60)
    board.close:SetScript("OnClick", function()
        ns.db.show = false
        board:Hide()
        ns.Print("board hidden. |cFFFFCC00/ct|r brings it back.")
    end)
    board.status = Text(board, "GameFontHighlightSmall", BOARD_W - PAD * 2)
    board.status:SetPoint("TOPLEFT", PAD, -30)
    board.buttons = {}

    board.input = CreateFrame("EditBox", nil, board, "InputBoxTemplate")
    board.input:SetSize(BOARD_W - PAD * 2 - 58, 20)
    board.input:SetAutoFocus(false)
    board.input:SetMaxLetters(60)
    board.input:SetScript("OnEnterPressed", function(self)
        ns.AddPhrase(self:GetText())
        self:SetText("")
        self:ClearFocus()
    end)
    board.input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    board.add = Button(board, "Add", 50, function()
        ns.AddPhrase(board.input:GetText())
        board.input:SetText("")
        board.input:ClearFocus()
    end)
    board.calibrate = Button(board, "Calibrate", 90, function() ns.ShowCalibrate() end)
    board.import = Button(board, "Import code", 90, function() ns.ShowCodeBox("import") end)
    board.listen = Button(board, "Listen", 60, function() ns.ListenToTarget() end)
    board.listen:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Listen to your target", 1, 1, 1)
        GameTooltip:AddLine("For helping a player of the other faction find their letter table: target them, click this, and have them send probes.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    board.listen:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
end

function ns.RefreshBoard()
    if not board then return end
    board.status:SetText(TableStatus())
    local y = 30 + Height(board.status) + 8
    for i, phrase in ipairs(ns.db.phrases) do
        local b = board.buttons[i]
        if not b then
            b = CreateFrame("Button", nil, board, "UIPanelButtonTemplate")
            b:SetSize(BTN_W, BTN_H)
            b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            b:SetScript("OnClick", PhraseClick)
            b:SetScript("OnEnter", PhraseTooltip)
            b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
            board.buttons[i] = b
        end
        b.phrase = phrase
        b:SetText(phrase)
        b:ClearAllPoints()
        local col = (i - 1) % 2
        local row = math.floor((i - 1) / 2)
        b:SetPoint("TOPLEFT", PAD + col * (BTN_W + BTN_GAP), -(y + row * (BTN_H + BTN_GAP)))
        b:Show()
    end
    for i = #ns.db.phrases + 1, #board.buttons do board.buttons[i]:Hide() end
    y = y + math.ceil(#ns.db.phrases / 2) * (BTN_H + BTN_GAP) + 6
    board.input:ClearAllPoints()
    board.input:SetPoint("TOPLEFT", PAD + 6, -y)
    board.add:ClearAllPoints()
    board.add:SetPoint("LEFT", board.input, "RIGHT", 4, 0)
    y = y + BTN_H + 6
    board.calibrate:ClearAllPoints()
    board.calibrate:SetPoint("TOPLEFT", PAD, -y)
    board.import:ClearAllPoints()
    board.import:SetPoint("LEFT", board.calibrate, "RIGHT", 4, 0)
    board.listen:ClearAllPoints()
    board.listen:SetPoint("LEFT", board.import, "RIGHT", 4, 0)
    y = y + BTN_H + PAD
    board:SetHeight(y)
end

function ns.ToggleBoard(force)
    if not board then BuildBoard() end
    local show
    if force ~= nil then show = force else show = not board:IsShown() end
    ns.db.show = show
    if show then
        ns.RefreshBoard()
        board:Show()
    else
        board:Hide()
    end
end

function ns.AddPhrase(text)
    text = tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return end
    text = text:upper()
    for _, p in ipairs(ns.db.phrases) do
        if p == text then return end
    end
    table.insert(ns.db.phrases, text)
    ns.RefreshUI()
end

function ns.RemovePhrase(which)
    local n = tonumber(which)
    for i, p in ipairs(ns.db.phrases) do
        if i == n or p == tostring(which):upper() then
            table.remove(ns.db.phrases, i)
            ns.RefreshUI()
            return true
        end
    end
end

--------------------------------------------------------------------------
-- calibrate (sender)
--------------------------------------------------------------------------

local cal

function ns.ShowCalibrate()
    if not cal then
        cal = Window("CrossTalkCalibrate", "CrossTalk: find your letters", 320, "DIALOG")
        if UISpecialFrames then table.insert(UISpecialFrames, "CrossTalkCalibrate") end
        cal.text = Text(cal, "GameFontHighlightSmall", 296)
        cal.text:SetPoint("TOPLEFT", PAD, -30)
        cal.send = Button(cal, "Send probe", 160, function() ns.SendProbe() end)
        cal.import = Button(cal, "Paste their code", 130, function() ns.ShowCodeBox("import") end)
    end
    ns.RefreshCalibrate()
    cal:Show()
end

function ns.RefreshCalibrate()
    if not cal then return end
    local lang = ns.MyLanguage()
    local probes = ns.Probes()
    local nextN = ns.db.probeNext or 1
    if nextN > #probes then nextN = 1 end
    cal.text:SetText(table.concat({
        ("The game turns your %s into gibberish for the other faction, and which letter each character becomes changes from patch to patch. This finds the letters for the build you are on."):format(ns.LanguageName(lang)),
        "",
        "1. Find a player of the other faction who has CrossTalk too (a friend, or your own second account).",
        "2. Stand next to each other. They target you and click Listen (or type /ct listen YourName).",
        "3. Click Send probe until their window says all letters are found - usually three or four probes.",
        "4. They copy the code their window shows and send it to you (a Battle.net whisper crosses factions). Click Paste their code.",
        "",
        TableStatus()
    }, "\n"))
    local y = 30 + Height(cal.text) + 10
    cal.send:SetText(("Send probe %d of %d"):format(nextN, #probes))
    cal.send:ClearAllPoints()
    cal.send:SetPoint("TOPLEFT", PAD, -y)
    cal.import:ClearAllPoints()
    cal.import:SetPoint("LEFT", cal.send, "RIGHT", 6, 0)
    cal:SetHeight(y + BTN_H + PAD)
end

--------------------------------------------------------------------------
-- listen (listener)
--------------------------------------------------------------------------

local lis

function ns.ShowListen()
    if not lis then
        lis = Window("CrossTalkListen", "CrossTalk: listening", 320, "DIALOG")
        if UISpecialFrames then table.insert(UISpecialFrames, "CrossTalkListen") end
        lis.text = Text(lis, "GameFontHighlightSmall", 296)
        lis.text:SetPoint("TOPLEFT", PAD, -30)
        lis.code = CreateFrame("EditBox", nil, lis, "InputBoxTemplate")
        lis.code:SetSize(290, 20)
        lis.code:SetAutoFocus(false)
        lis.code:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
        lis.code:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        -- read only: whatever is typed, the code comes back
        lis.code:SetScript("OnTextChanged", function(self, user)
            if user and self.value then self:SetText(self.value); self:HighlightText() end
        end)
        lis.stop = Button(lis, "Stop listening", 120, function()
            ns.StopListening()
            lis:Hide()
        end)
        lis.close:SetScript("OnClick", function()
            ns.StopListening()
            lis:Hide()
        end)
    end
    ns.RefreshListen()
    lis:Show()
end

function ns.RefreshListen()
    if not lis then return end
    local L = ns.listen
    local lines = {}
    if L then
        lines[#lines + 1] = ("Listening to |cFFFFCC00%s|r. They click Send probe while standing next to you."):format(tostring(L.display))
        lines[#lines + 1] = ""
        lines[#lines + 1] = ns.ListenSummary()
    else
        lines[#lines + 1] = "Not listening."
    end
    local lang, _, code = ns.ListenResult()
    if code then
        lines[#lines + 1] = ""
        lines[#lines + 1] = ("Their %s code - click it, Ctrl+C, and send it to them (a Battle.net whisper crosses factions):"):format(ns.LanguageName(lang))
    end
    lis.text:SetText(table.concat(lines, "\n"))
    local y = 30 + Height(lis.text) + 8
    lis.code.value = code
    lis.code:SetText(code or "")
    lis.code:ClearAllPoints()
    lis.code:SetPoint("TOPLEFT", PAD + 6, -y)
    if code then lis.code:Show() else lis.code:Hide() end
    y = y + (code and 28 or 0)
    lis.stop:ClearAllPoints()
    lis.stop:SetPoint("TOPLEFT", PAD, -y)
    lis:SetHeight(y + BTN_H + PAD)
end

function ns.ListenToTarget()
    local name
    if UnitExists and UnitExists("target") and UnitIsPlayer and UnitIsPlayer("target") then
        local ok, n = pcall(UnitName, "target")
        name = ok and ns.Plain(n)
    end
    if not name then
        ns.Print("target the player who will send probes first (or type |cFFFFCC00/ct listen Name|r).")
        return
    end
    ns.StartListening(name)
end

--------------------------------------------------------------------------
-- share code box: import a code, or show your own to pass on
--------------------------------------------------------------------------

local box

function ns.ShowCodeBox(mode)
    if not box then
        box = Window("CrossTalkCode", "CrossTalk: code", 320, "DIALOG")
        if UISpecialFrames then table.insert(UISpecialFrames, "CrossTalkCode") end
        box.text = Text(box, "GameFontHighlightSmall", 296)
        box.text:SetPoint("TOPLEFT", PAD, -30)
        box.edit = CreateFrame("EditBox", nil, box, "InputBoxTemplate")
        box.edit:SetSize(290, 20)
        box.edit:SetAutoFocus(false)
        box.edit:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
        box.edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        box.edit:SetScript("OnEnterPressed", function()
            if box.mode == "import" then ns.ImportCode(box.edit:GetText()) end
        end)
        box.go = Button(box, "Import", 100, function() ns.ImportCode(box.edit:GetText()) end)
    end
    box.mode = mode
    local lang = ns.MyLanguage()
    if mode == "import" then
        box.text:SetText("Paste the code the other player's CrossTalk gave you (Ctrl+V), then click Import.")
        box.edit:SetText("")
        box.go:Show()
    else
        local code = ns.ShareCode(lang, ns.Table(lang))
        box.text:SetText(code and ("Your %s table. Give this to friends of your faction on Forever so they don't have to calibrate (click it, Ctrl+C):"):format(ns.LanguageName(lang))
                             or "You have no letter table to share yet.")
        box.edit:SetText(code or "")
        box.go:Hide()
    end
    local y = 30 + Height(box.text) + 8
    box.edit:ClearAllPoints()
    box.edit:SetPoint("TOPLEFT", PAD + 6, -y)
    box.go:ClearAllPoints()
    box.go:SetPoint("TOPLEFT", PAD, -(y + 28))
    box:SetHeight(y + 28 + (mode == "import" and BTN_H + PAD or PAD))
    box:Show()
    if mode == "import" then box.edit:SetFocus() end
end

function ns.ImportCode(code)
    local lang, t = ns.ParseShareCode(code)
    if not lang then
        ns.Print("%s.", tostring(t))
        return false
    end
    local mine = ns.MyLanguage()
    ns.StoreTable(lang, t, "imported")
    local sep = ns.Separator(t)
    ns.Print("imported the %s table: %d letters (%s), word break '%s', found on build %s.",
             ns.LanguageName(lang), t.count, ns.LetterList(t), tostring(sep or "none"), tostring(t.build))
    if lang ~= mine then
        ns.Print("|cFFFFAA00that is a %s table and you speak %s - it is for players of the other faction.|r", ns.LanguageName(lang), ns.LanguageName(mine))
    end
    if box and box.mode == "import" then box:Hide() end
    return true
end

--------------------------------------------------------------------------

function ns.RefreshUI()
    ns.RefreshBoard()
    ns.RefreshCalibrate()
    ns.RefreshListen()
end

function ns.SetupUI()
    BuildBoard()
    ns.RefreshBoard()
    if ns.db.show then board:Show() else board:Hide() end
end
