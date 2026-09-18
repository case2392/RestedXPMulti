-- Forever Classic UI - reputation and skills tabs of the character sheet
--
-- Forever draws both as retail scroll boxes (398px list + a detail pane on
-- the right). Era drew them inside the same 384x512 sheet as the paper
-- doll: a column of 15 reputation bars (137x13, art around them) with
-- collapsible headers and a small detail popup to the right; 12 skill bars
-- (271x15 with a bevel border) with headers and a detail bar + description
-- under the list. Both lists were FauxScrollFrames, which Forever still
-- ships, so they are rebuilt the same way here, filled from Forever's
-- C_Reputation / C_SkillInfo.
--
-- Blizzard's ReputationFrame / SkillsFrame stay the frames that are shown
-- (the tabs key off them and Blizzard keeps firing their updates); their
-- retail children (ScrollBox, ScrollBar, detail pane, filter dropdown) are
-- hidden while the classic list of ours, parented to the same frame, is
-- up. Nothing is written into Blizzard's tables. Numbers come from Era's
-- ReputationFrame.xml / SkillFrame.xml and a `/cui report all` on Era.

local addonName, ns = ...

local M = ns.charsheet
if not M then return end

local PD = "Interface\\PaperDollInfoFrame\\"
local ART = {
    skillsBar = PD .. "UI-Character-Skills-Bar",
    skillsBorder = PD .. "UI-Character-Skills-BarBorder",
    skillsBorderHighlight = PD .. "UI-Character-Skills-BarBorderHighlight",
    skillBottomLeft = PD .. "SkillFrame-BotLeft",
    skillBottomRight = PD .. "SkillFrame-BotRight",
    repBar = PD .. "UI-Character-ReputationBar",
    repHighlight = PD .. "UI-Character-ReputationBar-Highlight",
    repDetailBackground = PD .. "UI-Character-Reputation-DetailBackground",
    scrollBar = PD .. "UI-Character-ScrollBar",
    trainerBar = "Interface\\ClassTrainerFrame\\UI-ClassTrainer-HorizontalBar",
    trainerScroll = "Interface\\ClassTrainerFrame\\UI-ClassTrainer-ScrollBar",
    sortTabLeft = "Interface\\QuestFrame\\UI-QuestLogSortTab-Left",
    sortTabMiddle = "Interface\\QuestFrame\\UI-QuestLogSortTab-Middle",
    sortTabRight = "Interface\\QuestFrame\\UI-QuestLogSortTab-Right",
    plus = "Interface\\Buttons\\UI-PlusButton-Up",
    minus = "Interface\\Buttons\\UI-MinusButton-Up",
    plusHighlight = "Interface\\Buttons\\UI-PlusButton-Hilight",
    check = "Interface\\Buttons\\UI-CheckBox-Check",
    swordCheck = "Interface\\Buttons\\UI-CheckBox-SwordCheck",
    cancelUp = "Interface\\Buttons\\CancelButton-Up",
    cancelDown = "Interface\\Buttons\\CancelButton-Down",
    cancelHighlight = "Interface\\Buttons\\CancelButton-Highlight",
    dialogCorner = "Interface\\DialogFrame\\UI-DialogBox-Corner",
    dialogDivider = "Interface\\DialogFrame\\UI-DialogBox-Divider"
}

local function G(name) return _G[name] end

local function Str(key, fallback)
    local v = _G[key]
    if type(v) == "string" and v ~= "" then return v end
    return fallback
end

local function HasFile(path)
    if not GetFileIDFromPath then return true end
    local ok, id = pcall(GetFileIDFromPath, path)
    return ok and id ~= nil
end

local function Guard(label, fn)
    return function(...)
        local ok, err = pcall(fn, ...)
        if not ok then ns.errors[#ns.errors + 1] = "charsheet " .. label .. ": " .. tostring(err) end
    end
end

local function Sound(kit)
    if PlaySound and SOUNDKIT and SOUNDKIT[kit] then pcall(PlaySound, SOUNDKIT[kit]) end
end

local function HideTooltip()
    if GameTooltip then GameTooltip:Hide() end
end

local function Tooltip(owner, text, wrap)
    if not GameTooltip or not text then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(text, 1, 1, 1, 1, wrap)
    GameTooltip:Show()
end

-- Era's list scroll frame: a FauxScrollFrame with the classic scroll art
-- beside it; falls back to a plain frame with a slider when the template
-- is gone (the list still scrolls with the wheel)
local function ListScroll(parent, width, height, rowHeight, numRows, art, onScroll)
    local scroll = CreateFrame("ScrollFrame", nil, parent, "FauxScrollFrameTemplate")
    scroll:SetSize(width, height)
    scroll.rowHeight, scroll.numRows = rowHeight, numRows
    if art then
        local top = scroll:CreateTexture(nil, "BACKGROUND")
        top:SetTexture(art.file)
        top:SetSize(31, art.topHeight)
        top:SetPoint("TOPLEFT", scroll, "TOPRIGHT", -2, 5)
        top:SetTexCoord(unpack(art.topCoord))
        local bottom = scroll:CreateTexture(nil, "BACKGROUND")
        bottom:SetTexture(art.file)
        bottom:SetSize(31, art.bottomHeight)
        bottom:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", -2, art.bottomOffset or -4)
        bottom:SetTexCoord(unpack(art.bottomCoord))
    end
    scroll:SetScript("OnVerticalScroll", function(self, offset)
        if FauxScrollFrame_OnVerticalScroll then
            FauxScrollFrame_OnVerticalScroll(self, offset, rowHeight, onScroll)
        else
            self.offset = math.floor((offset or 0) / rowHeight + 0.5)
            onScroll()
        end
    end)
    return scroll
end

local function ScrollOffset(scroll)
    if FauxScrollFrame_GetOffset then return FauxScrollFrame_GetOffset(scroll) or 0 end
    return scroll.offset or 0
end

local function ScrollUpdate(scroll, numItems)
    if FauxScrollFrame_Update then
        local ok, shown = pcall(FauxScrollFrame_Update, scroll, numItems, scroll.numRows, scroll.rowHeight)
        if ok and not shown and scroll.ScrollBar and scroll.ScrollBar.SetValue then scroll.ScrollBar:SetValue(0) end
    end
end

local function PlusMinus(button, collapsed)
    button:SetNormalTexture(collapsed and ART.plus or ART.minus)
    local tex = button:GetNormalTexture()
    if tex then
        tex:SetSize(16, 16)
        tex:ClearAllPoints()
        tex:SetPoint("LEFT", button, "LEFT", 3, 0)
    end
end

local function HeaderButton(parent, width, textFont, textX)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, 13)
    PlusMinus(b, false)
    if HasFile(ART.plusHighlight) then
        b:SetHighlightTexture(ART.plusHighlight, "ADD")
        local hl = b:GetHighlightTexture()
        if hl then
            hl:SetSize(16, 16)
            hl:ClearAllPoints()
            hl:SetPoint("LEFT", b, "LEFT", 3, 0)
        end
    end
    b.Text = b:CreateFontString(nil, "ARTWORK", textFont)
    b.Text:SetPoint("LEFT", b, "LEFT", textX, 0)
    return b
end

--------------------------------------------------------------------------
-- Reputation
--------------------------------------------------------------------------

local REP_ROWS, REP_ROW_HEIGHT, REP_PITCH = 15, 26, 23

local Rep = {frameName = "ReputationFrame", label = "reputation"}

local function RepAPI()
    return C_Reputation and C_Reputation.GetNumFactions and C_Reputation.GetFactionDataByIndex and C_Reputation
end

local function StandingText(reaction)
    local text
    if GetText and UnitSex then
        local ok, v = pcall(GetText, "FACTION_STANDING_LABEL" .. reaction, UnitSex("player"))
        if ok then text = v end
    end
    return text or Str("FACTION_STANDING_LABEL" .. reaction, "")
end

local function RepBar(panel, i)
    local bar = CreateFrame("StatusBar", nil, panel.list)
    bar:SetSize(137, 13)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(1)
    bar:SetStatusBarTexture(ART.skillsBar)
    if bar.SetHitRectInsets then bar:SetHitRectInsets(-126, 3, -2, -2) end
    bar:EnableMouse(true)
    bar.Left = bar:CreateTexture(nil, "ARTWORK")
    bar.Left:SetTexture(ART.repBar)
    bar.Left:SetSize(256, 22)
    bar.Left:SetPoint("TOPLEFT", bar, "TOPLEFT", -126, 4)
    bar.Left:SetTexCoord(0, 1, 0, 0.34375)
    bar.Right = bar:CreateTexture(nil, "ARTWORK")
    bar.Right:SetTexture(ART.repBar)
    bar.Right:SetSize(16, 24)
    bar.Right:SetPoint("TOPLEFT", bar.Left, "TOPRIGHT", 0, 0)
    bar.Right:SetTexCoord(0, 0.0625, 0.34375, 0.71875)
    bar.Name = bar:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    bar.Name:SetSize(110, 10)
    bar.Name:SetJustifyH("LEFT")
    bar.Name:SetPoint("LEFT", bar, "LEFT", -119, 0)
    bar.Standing = bar:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    bar.Standing:SetPoint("CENTER", bar, "CENTER", 0, 0)
    bar.Highlight1 = bar:CreateTexture(nil, "OVERLAY")
    bar.Highlight1:SetTexture(ART.repHighlight)
    bar.Highlight1:SetBlendMode("ADD")
    bar.Highlight1:SetSize(256, 28)
    bar.Highlight1:SetPoint("TOPLEFT", bar.Left, "TOPLEFT", -2, 3)
    bar.Highlight1:SetTexCoord(0, 1, 0, 0.4375)
    bar.Highlight1:Hide()
    bar.Highlight2 = bar:CreateTexture(nil, "OVERLAY")
    bar.Highlight2:SetTexture(ART.repHighlight)
    bar.Highlight2:SetBlendMode("ADD")
    bar.Highlight2:SetSize(17, 28)
    bar.Highlight2:SetPoint("LEFT", bar.Highlight1, "RIGHT", 0, 0)
    bar.Highlight2:SetTexCoord(0, 0.06640625, 0.4375, 0.875)
    bar.Highlight2:Hide()
    bar.Check = bar:CreateTexture(nil, "OVERLAY")
    bar.Check:SetTexture(ART.check)
    bar.Check:SetSize(16, 16)
    bar.Check:Hide()
    bar.AtWar = CreateFrame("Frame", nil, bar)
    bar.AtWar:SetSize(24, 22)
    bar.AtWar:SetPoint("LEFT", bar.Right, "RIGHT", -2, 0)
    bar.AtWar:EnableMouse(true)
    local sword = bar.AtWar:CreateTexture(nil, "BACKGROUND")
    sword:SetTexture(ART.repBar)
    sword:SetAllPoints(bar.AtWar)
    sword:SetTexCoord(0.0625, 0.15625, 0.34375, 0.71875)
    bar.AtWar:SetScript("OnEnter", function(self) Tooltip(self, Str("REPUTATION_STATUS_AT_WAR", "At War"), true) end)
    bar.AtWar:SetScript("OnLeave", HideTooltip)
    bar.AtWar:Hide()
    bar:SetScript("OnEnter", function(self)
        if self.tooltip then self.Standing:SetText(self.tooltip) end
        self.Highlight1:Show()
        self.Highlight2:Show()
    end)
    bar:SetScript("OnLeave", function(self)
        self.Standing:SetText(self.standingText or "")
        if not self.selected then
            self.Highlight1:Hide()
            self.Highlight2:Hide()
        end
    end)
    bar:SetScript("OnMouseUp", function(self) Rep:BarClicked(self) end)
    local header = HeaderButton(panel.list, 302, "GameFontNormal", 20)
    header:SetPoint("TOPLEFT", bar, "TOPLEFT", -125, 0)
    header:SetScript("OnClick", function(self)
        local api = RepAPI()
        if not api or not self.index then return end
        if self.collapsed then api.ExpandFactionHeader(self.index) else api.CollapseFactionHeader(self.index) end
        Rep:Update()
    end)
    bar.header = header
    return bar
end

local function BuildRepDetail(panel)
    local frame = G("ReputationFrame")
    local d = CreateFrame("Frame", nil, panel.list, "BackdropTemplate")
    d:SetSize(212, 203)
    d:SetPoint("TOPLEFT", frame, "TOPRIGHT", -33, -28)
    d:SetFrameLevel(panel.list:GetFrameLevel() + 3)
    d:EnableMouse(true)
    if d.SetBackdrop and BACKDROP_DIALOG_32_32 then pcall(d.SetBackdrop, d, BACKDROP_DIALOG_32_32) end
    if HasFile(ART.repDetailBackground) then
        local bg = d:CreateTexture(nil, "ARTWORK")
        bg:SetTexture(ART.repDetailBackground)
        bg:SetSize(256, 128)
        bg:SetPoint("TOPLEFT", d, "TOPLEFT", 11, -11)
    end
    if HasFile(ART.dialogCorner) then
        local corner = d:CreateTexture(nil, "OVERLAY")
        corner:SetTexture(ART.dialogCorner)
        corner:SetSize(32, 32)
        corner:SetPoint("TOPRIGHT", d, "TOPRIGHT", -6, -7)
        local divider = d:CreateTexture(nil, "OVERLAY")
        divider:SetTexture(ART.dialogDivider)
        divider:SetSize(256, 32)
        divider:SetPoint("TOPLEFT", d, "TOPLEFT", 9, -131)
    end
    d.Name = d:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    d.Name:SetSize(160, 0)
    d.Name:SetJustifyH("LEFT")
    d.Name:SetPoint("TOPLEFT", d, "TOPLEFT", 20, -21)
    d.Description = d:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    d.Description:SetSize(170, 0)
    d.Description:SetJustifyH("LEFT")
    d.Description:SetPoint("TOPLEFT", d.Name, "BOTTOMLEFT", 0, -2)
    local close = CreateFrame("Button", nil, d)
    close:SetSize(32, 32)
    close:SetPoint("TOPRIGHT", d, "TOPRIGHT", -3, -3)
    close:SetNormalTexture(M.ART.closeUp)
    close:SetPushedTexture(M.ART.closeDown)
    close:SetHighlightTexture(M.ART.closeHighlight, "ADD")
    close:SetScript("OnClick", function() Rep:CloseDetail() end)

    local function Check(label, x, y, relTo, relPoint)
        local cb = CreateFrame("CheckButton", nil, d, "UICheckButtonTemplate")
        cb:SetSize(26, 26)
        cb:SetPoint(relPoint and "LEFT" or "BOTTOMLEFT", relTo or d, relPoint or "BOTTOMLEFT", x, y)
        cb.Label = d:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        cb.Label:SetPoint("LEFT", cb, "RIGHT", -2, 0)
        cb.Label:SetText(label)
        cb:SetScript("OnLeave", HideTooltip)
        return cb
    end
    d.AtWar = Check(Str("AT_WAR", "At War"), 14, 34)
    d.AtWar.Label:SetTextColor(1, 0.1, 0.1)
    if HasFile(ART.swordCheck) and d.AtWar.SetCheckedTexture then
        d.AtWar:SetCheckedTexture(ART.swordCheck)
        local ct = d.AtWar.GetCheckedTexture and d.AtWar:GetCheckedTexture()
        if ct then
            ct:SetSize(32, 32)
            ct:ClearAllPoints()
            ct:SetPoint("TOPLEFT", d.AtWar, "TOPLEFT", 3, -5)
        end
    end
    d.AtWar:SetScript("OnEnter", function(self) Tooltip(self, Str("REPUTATION_AT_WAR_DESCRIPTION", "Toggle whether you are at war with this faction."), true) end)
    d.AtWar:SetScript("OnClick", function(self)
        local api = RepAPI()
        if api and api.ToggleFactionAtWar then api.ToggleFactionAtWar(api.GetSelectedFaction()) end
        Sound(self:GetChecked() and "IG_MAINMENU_OPTION_CHECKBOX_ON" or "IG_MAINMENU_OPTION_CHECKBOX_OFF")
        Rep:Update()
    end)
    d.Inactive = Check(Str("MOVE_TO_INACTIVE", "Inactive"), 3, 0, d.AtWar.Label, "RIGHT")
    d.Inactive:SetScript("OnClick", function(self)
        local api = RepAPI()
        if api and api.SetFactionActive then api.SetFactionActive(api.GetSelectedFaction(), not self:GetChecked()) end
        Sound(self:GetChecked() and "IG_MAINMENU_OPTION_CHECKBOX_ON" or "IG_MAINMENU_OPTION_CHECKBOX_OFF")
        Rep:Update()
    end)
    d.Watch = Check(Str("SHOW_FACTION_ON_MAINSCREEN", "Show as Experience Bar"), 0, 3, d.AtWar, "BOTTOMLEFT")
    d.Watch:ClearAllPoints()
    d.Watch:SetPoint("TOPLEFT", d.AtWar, "BOTTOMLEFT", 0, 3)
    d.Watch:SetScript("OnClick", function(self)
        local api = RepAPI()
        if api and api.SetWatchedFactionByIndex then api.SetWatchedFactionByIndex(self:GetChecked() and api.GetSelectedFaction() or 0) end
        Sound(self:GetChecked() and "IG_MAINMENU_OPTION_CHECKBOX_ON" or "IG_MAINMENU_OPTION_CHECKBOX_OFF")
        Rep:Update()
    end)
    d:Hide()
    panel.detail = d
end

function Rep:Build()
    local frame = G("ReputationFrame")
    local list = CreateFrame("Frame", "ForeverClassicUIReputationList", frame)
    list:SetAllPoints(frame)
    list:SetFrameLevel(frame:GetFrameLevel() + 2)
    self.list = list
    -- column labels (Era: GameFontHighlight at 70,-57 and 215,-59)
    list.FactionLabel = list:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    list.FactionLabel:SetPoint("TOPLEFT", list, "TOPLEFT", 70, -57)
    list.FactionLabel:SetText(Str("FACTION", "Faction"))
    list.StandingLabel = list:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    list.StandingLabel:SetPoint("TOPLEFT", list, "TOPLEFT", 215, -59)
    list.StandingLabel:SetText(Str("STANDING", "Standing"))
    self.bars = {}
    for i = 1, REP_ROWS do
        local bar = RepBar(self, i)
        bar:SetPoint("TOPLEFT", list, "TOPLEFT", 150, -86 - (i - 1) * REP_PITCH)
        self.bars[i] = bar
    end
    self.scroll = ListScroll(list, 296, 354, REP_ROW_HEIGHT, REP_ROWS,
        HasFile(ART.scrollBar) and {file = ART.scrollBar, topHeight = 256, topCoord = {0, 0.484375, 0, 1}, bottomHeight = 108, bottomCoord = {0.515625, 1, 0, 0.421875}, bottomOffset = -4} or nil,
        function() Rep:Update() end)
    self.scroll:SetPoint("TOPRIGHT", list, "TOPRIGHT", -66, -76)
    BuildRepDetail(self)
    list:RegisterEvent("UPDATE_FACTION")
    list:RegisterEvent("QUEST_LOG_UPDATE")
    list:SetScript("OnEvent", Guard("reputation event", function() if list:IsShown() and self.classic then Rep:Update() end end))
    list:Hide()
end

-- Blizzard's retail pieces of this tab go away while ours are up
function Rep:SetClassic(on)
    local frame = G("ReputationFrame")
    if not frame or on == self.classic then return end
    self.classic = on
    for _, key in ipairs({"ScrollBox", "ScrollBar", "ReputationDetailFrame", "filterDropdown"}) do
        local f = frame[key]
        if f and f.SetShown then f:SetShown(not on) end
    end
    if on then
        self.list:Show()
        self:Update()
    else
        self.list:Hide()
        self.detail:Hide()
    end
end

function Rep:BarClicked(bar)
    local api = RepAPI()
    if not api or not bar.index then return end
    if self.detail:IsShown() and api.GetSelectedFaction() == bar.index then
        self:CloseDetail()
    else
        api.SetSelectedFaction(bar.index)
        self.detail:Show()
        self:Update()
    end
end

function Rep:CloseDetail()
    self.detail:Hide()
    local api = RepAPI()
    if api and api.SetSelectedFaction then api.SetSelectedFaction(0) end
    self:Update()
end

function Rep:Update()
    local api = RepAPI()
    if not api or not self.list or not self.list:IsShown() then return end
    local numFactions = api.GetNumFactions() or 0
    ScrollUpdate(self.scroll, numFactions)
    local offset = ScrollOffset(self.scroll)
    local selected = api.GetSelectedFaction and api.GetSelectedFaction() or 0
    local colors = FACTION_BAR_COLORS or {}
    for i = 1, REP_ROWS do
        local bar, header = self.bars[i], self.bars[i].header
        local index = offset + i
        local data = index <= numFactions and api.GetFactionDataByIndex(index) or nil
        if not data then
            bar:Hide()
            header:Hide()
        elseif data.isHeader and not data.isHeaderWithRep then
            header.Text:SetText(data.name or "")
            header.index, header.collapsed = index, data.isCollapsed
            PlusMinus(header, data.isCollapsed)
            header:Show()
            bar:Hide()
        else
            local standing = StandingText(data.reaction or 4)
            bar.Name:SetText(data.name or "")
            bar.Standing:SetText(standing)
            bar.standingText = standing
            bar.index = index
            local barMin, barMax, value = data.currentReactionThreshold or 0, data.nextReactionThreshold or 1, data.currentStanding or 0
            barMax, value = barMax - barMin, value - barMin
            if (data.reaction or 0) >= (MAX_REPUTATION_REACTION or 8) then barMax, value = 1, 1 end
            if barMax <= 0 then barMax = 1 end
            bar.tooltip = "|cffffffff " .. value .. " / " .. barMax .. "|r"
            bar:SetMinMaxValues(0, barMax)
            bar:SetValue(value)
            local color = colors[data.reaction] or {r = 0, g = 0.6, b = 0.1}
            bar:SetStatusBarColor(color.r, color.g, color.b)
            bar.AtWar:SetShown(data.atWarWith == true)
            if data.isWatched then
                bar.Name:SetWidth(100)
                bar.Check:ClearAllPoints()
                bar.Check:SetPoint("LEFT", bar.Name, "LEFT", bar.Name:GetStringWidth(), 0)
                bar.Check:Show()
            else
                bar.Name:SetWidth(110)
                bar.Check:Hide()
            end
            bar.selected = (index == selected)
            bar.Highlight1:SetShown(bar.selected)
            bar.Highlight2:SetShown(bar.selected)
            if bar.selected and self.detail:IsShown() then
                local d = self.detail
                d.Name:SetText(data.name or "")
                d.Description:SetText(data.description or "")
                d.AtWar:SetChecked(data.atWarWith == true)
                if data.canToggleAtWar and not data.isHeader then
                    d.AtWar:Enable()
                    d.AtWar.Label:SetTextColor(1, 0.1, 0.1)
                else
                    d.AtWar:Disable()
                    d.AtWar.Label:SetTextColor(0.5, 0.5, 0.5)
                end
                local active = true
                if api.IsFactionActive then active = api.IsFactionActive(index) ~= false end
                d.Inactive:SetChecked(not active)
                d.Watch:SetChecked(data.isWatched == true)
            end
            bar:Show()
            header:Hide()
        end
    end
    if selected == 0 then self.detail:Hide() end
end

M.RegisterPanel(Rep)

--------------------------------------------------------------------------
-- Skills
--------------------------------------------------------------------------

local SKILL_ROWS, SKILL_PITCH = 12, 18
local HIDDEN_SKILL_CATEGORIES = {[7] = true} -- class skills, as Forever's own skills tab hides them
local DEFENSE_SKILL_ID = 95

local Skills = {frameName = "SkillsFrame", label = "skills"}
Skills.art = {M.ART.generalTopLeft, M.ART.generalTopRight, ART.skillBottomLeft, ART.skillBottomRight, x = 2, y = -1}

local function SkillAPI()
    return C_SkillInfo and C_SkillInfo.GetNumSkillLines and C_SkillInfo.GetSkillLineInfo and C_SkillInfo
end

-- the visible skill lines (top level only, class skills out), with API indexes
local function SkillList()
    local api = SkillAPI()
    local out = {}
    if not api then return out end
    for index = 1, api.GetNumSkillLines() or 0 do
        local info = api.GetSkillLineInfo(index)
        if info and (info.parentSkillLineID or 0) == 0 then
            local hidden = info.isHeader and HIDDEN_SKILL_CATEGORIES[info.skillID] or (not info.isHeader and HIDDEN_SKILL_CATEGORIES[info.skillLineCategoryID])
            if not hidden then
                info.index = index
                if info.skillID == DEFENSE_SKILL_ID and UnitDefenseSkill then
                    local _, mod = UnitDefenseSkill("player")
                    if mod then info.modifier = mod end
                end
                out[#out + 1] = info
            end
        end
    end
    return out
end

-- a skill bar: 271x15 with the bevel border around it (Era SkillStatusBarTemplate)
local function SkillBar(parent, width)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetSize(width or 271, 15)
    bar:SetMinMaxValues(0, 1)
    bar:SetStatusBarTexture(ART.skillsBar)
    bar:SetStatusBarColor(0.25, 0.25, 0.75)
    bar.Background = bar:CreateTexture(nil, "BACKGROUND")
    bar.Background:SetColorTexture(1, 1, 1, 0.2)
    bar.Background:SetAllPoints(bar)
    bar.Name = bar:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    bar.Name:SetPoint("LEFT", bar, "LEFT", 6, 1)
    bar.Rank = bar:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    bar.Rank:SetSize(128, 0)
    bar.Rank:SetJustifyH("LEFT")
    bar.Rank:SetPoint("LEFT", bar.Name, "RIGHT", 13, 0)
    bar.Fill = bar:CreateTexture(nil, "BORDER")
    bar.Fill:SetColorTexture(1, 1, 1, 0.5)
    bar.Fill:SetSize(1, 15)
    bar.Fill:Hide()
    return bar
end

-- colour by cost type (Era: 1 green, 2 yellow, 3 red, else grey; plain skills blue)
local function ColorSkillBar(bar, info)
    local costType = info.costType or 0
    if costType == 1 then
        bar:SetStatusBarColor(0, 0.75, 0, 0.5); bar.Background:SetVertexColor(0, 0.5, 0, 0.5)
    elseif costType == 2 then
        bar:SetStatusBarColor(0.75, 0.75, 0, 0.5); bar.Background:SetVertexColor(0.75, 0.75, 0, 0.5)
    elseif costType == 3 then
        bar:SetStatusBarColor(0.75, 0, 0, 0.5); bar.Background:SetVertexColor(0.75, 0, 0, 0.5)
    else
        bar:SetStatusBarColor(0, 0, 1, 0.5); bar.Background:SetVertexColor(0, 0, 0.75, 0.5)
    end
    local rank, maxRank, modifier = info.rank or 0, info.maxRank or 0, info.modifier or 0
    local temp = info.tempPoints or 0
    bar.Fill:Hide()
    if maxRank == 1 then
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(1)
        bar:SetStatusBarColor(0.5, 0.5, 0.5)
        bar.Background:SetVertexColor(1, 1, 1, 0.5)
        bar.Rank:SetText("")
    elseif maxRank > 0 then
        bar:SetMinMaxValues(0, maxRank)
        bar:SetValue(rank)
        if temp > 0 then
            bar.Fill:ClearAllPoints()
            bar.Fill:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
            bar.Fill:SetWidth(math.max(1, ((rank + temp) / maxRank) * bar:GetWidth()))
            bar.Fill:Show()
        end
        if modifier == 0 then
            bar.Rank:SetText((rank + temp) .. "/" .. maxRank)
        else
            local color = modifier > 0 and "|cff20ff20+" or "|cffff2020"
            bar.Rank:SetText((rank + temp) .. " (" .. color .. modifier .. "|r)/" .. maxRank)
        end
    else
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(0)
        bar.Rank:SetText("")
    end
    bar.Name:SetText(info.name or "")
end

function Skills:Build()
    local frame = G("SkillsFrame")
    local list = CreateFrame("Frame", "ForeverClassicUISkillList", frame)
    list:SetAllPoints(frame)
    list:SetFrameLevel(frame:GetFrameLevel() + 2)
    self.list = list
    -- the bar under the list (Era: UI-ClassTrainer-HorizontalBar at 15,-290)
    if HasFile(ART.trainerBar) then
        local left = list:CreateTexture(nil, "ARTWORK")
        left:SetTexture(ART.trainerBar)
        left:SetSize(256, 16)
        left:SetPoint("TOPLEFT", list, "TOPLEFT", 15, -290)
        left:SetTexCoord(0, 1, 0, 0.25)
        local right = list:CreateTexture(nil, "ARTWORK")
        right:SetTexture(ART.trainerBar)
        right:SetSize(75, 16)
        right:SetPoint("LEFT", left, "RIGHT", 0, 0)
        right:SetTexCoord(0, 0.29296875, 0.25, 0.5)
    end
    -- "All" expand/collapse tab (Era SkillFrameExpandButtonFrame at 70,-49)
    local expand = CreateFrame("Frame", nil, list)
    expand:SetSize(54, 32)
    expand:SetPoint("TOPLEFT", list, "TOPLEFT", 70, -49)
    if HasFile(ART.sortTabLeft) then
        local l = expand:CreateTexture(nil, "BACKGROUND"); l:SetTexture(ART.sortTabLeft); l:SetSize(8, 32); l:SetPoint("TOPLEFT", expand, "TOPLEFT", 0, 6)
        local r = expand:CreateTexture(nil, "BACKGROUND"); r:SetTexture(ART.sortTabRight); r:SetSize(8, 32); r:SetPoint("TOPRIGHT", expand, "TOPRIGHT", 0, 6)
        local m = expand:CreateTexture(nil, "BACKGROUND"); m:SetTexture(ART.sortTabMiddle); m:SetHeight(32); m:SetPoint("LEFT", l, "RIGHT", 0, 0); m:SetPoint("RIGHT", r, "LEFT", 0, 0)
    end
    local all = HeaderButton(expand, 40, "GameFontHighlight", 25)
    all:SetSize(40, 22)
    all:SetPoint("LEFT", expand, "LEFT", 5, -3)
    all.Text:SetText(Str("ALL", "All"))
    all:SetScript("OnClick", function(self) Skills:ToggleAll(self.collapsed) end)
    self.allButton = all
    if all.Text.GetStringWidth then expand:SetWidth(all.Text:GetStringWidth() + 45) end
    -- "Close" button (Era: 80x22 centred at 305,-422)
    local close = CreateFrame("Button", nil, list, "UIPanelButtonTemplate")
    close:SetSize(80, 22)
    close:SetPoint("CENTER", list, "TOPLEFT", 305, -422)
    if close.SetText then close:SetText(Str("CLOSE", "Close")) end
    close:SetScript("OnClick", function()
        local cf = G("CharacterFrame")
        if HideUIPanel then HideUIPanel(cf) else cf:Hide() end
    end)
    -- 12 rows: a header label or a skill bar in each slot
    self.rows = {}
    for i = 1, SKILL_ROWS do
        local y = -79 - (i - 1) * SKILL_PITCH
        local bar = SkillBar(list, 271)
        bar:SetPoint("TOPLEFT", list, "TOPLEFT", 38, y)
        bar.Border = CreateFrame("Button", nil, bar)
        bar.Border:SetSize(281, 32)
        bar.Border:SetPoint("LEFT", bar, "LEFT", -5, 0)
        if bar.Border.SetHitRectInsets then bar.Border:SetHitRectInsets(0, 0, 7, 7) end
        bar.Border:SetNormalTexture(ART.skillsBorder)
        bar.Border:SetHighlightTexture(ART.skillsBorderHighlight)
        bar.Border:SetScript("OnClick", function() Skills:BarClicked(bar) end)
        local header = HeaderButton(list, 285, "GameFontHighlight", 25)
        header:SetSize(285, 14)
        header:SetPoint("LEFT", list, "TOPLEFT", 22, y - 7)
        header:SetScript("OnClick", function(self)
            local api = SkillAPI()
            if not api or not self.index then return end
            if self.collapsed then api.ExpandSkillHeader(self.index) else api.CollapseSkillHeader(self.index) end
            Skills:Update()
        end)
        bar.header = header
        self.rows[i] = bar
    end
    self.scroll = ListScroll(list, 296, 220, SKILL_PITCH, SKILL_ROWS,
        HasFile(ART.trainerScroll) and {file = ART.trainerScroll, topHeight = 128, topCoord = {0, 0.46875, 0, 1}, bottomHeight = 128, bottomCoord = {0.53125, 1, 0, 1}, bottomOffset = -2} or nil,
        function() Skills:Update() end)
    self.scroll:SetPoint("TOPRIGHT", list, "TOPRIGHT", -67, -75)
    -- detail: bar with the bevel and an unlearn button, description under it
    local detail = CreateFrame("Frame", nil, list)
    detail:SetSize(296, 107)
    detail:SetPoint("TOPLEFT", self.scroll, "BOTTOMLEFT", 0, -8)
    local dbar = SkillBar(detail, 211)
    dbar:SetPoint("CENTER", detail, "TOP", -10, -20)
    dbar.BorderTex = dbar:CreateTexture(nil, "ARTWORK")
    dbar.BorderTex:SetTexture(ART.skillsBorder)
    dbar.BorderTex:SetSize(220, 32)
    dbar.BorderTex:SetPoint("LEFT", dbar, "LEFT", -5, 0)
    local unlearn = CreateFrame("Button", nil, dbar)
    unlearn:SetSize(32, 32)
    unlearn:SetPoint("LEFT", dbar.BorderTex, "RIGHT", -2, -1)
    unlearn:SetNormalTexture(ART.cancelUp)
    unlearn:SetPushedTexture(ART.cancelDown)
    unlearn:SetHighlightTexture(ART.cancelHighlight, "ADD")
    unlearn:SetScript("OnEnter", function(self) Tooltip(self, Str("UNLEARN_SKILL_TOOLTIP", "Unlearn")) end)
    unlearn:SetScript("OnLeave", HideTooltip)
    unlearn:SetScript("OnClick", function(self)
        if StaticPopup_Show and StaticPopupDialogs and StaticPopupDialogs.UNLEARN_SKILL and self.skillID then
            StaticPopup_Show("UNLEARN_SKILL", self.skillName, nil, self.skillID)
        end
    end)
    unlearn:Hide()
    dbar.Unlearn = unlearn
    detail.bar = dbar
    detail.Description = detail:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    detail.Description:SetSize(275, 0)
    detail.Description:SetJustifyH("LEFT")
    detail.Description:SetJustifyV("TOP")
    detail.Description:SetPoint("TOP", detail, "TOP", -5, -35)
    self.detail = detail
    list:RegisterEvent("SKILL_LINES_CHANGED")
    list:RegisterEvent("CHARACTER_POINTS_CHANGED")
    list:SetScript("OnEvent", Guard("skills event", function() if list:IsShown() and self.classic then Skills:Update() end end))
    list:Hide()
end

function Skills:SetClassic(on)
    local frame = G("SkillsFrame")
    if not frame or on == self.classic then return end
    self.classic = on
    for _, key in ipairs({"ScrollBox", "ScrollBar", "SkillDetailFrame"}) do
        local f = frame[key]
        if f and f.SetShown then f:SetShown(not on) end
    end
    if on then
        self.list:Show()
        self:Update()
    else
        self.list:Hide()
    end
end

function Skills:BarClicked(bar)
    local api = SkillAPI()
    if not api or not bar.index then return end
    api.SetSelectedSkill(bar.index)
    self:Update()
end

-- expand or collapse every header; from the last one up so earlier indexes stay valid
function Skills:ToggleAll(expandAll)
    local api = SkillAPI()
    if not api then return end
    local headers = {}
    for index = 1, api.GetNumSkillLines() or 0 do
        local info = api.GetSkillLineInfo(index)
        if info and info.isHeader then headers[#headers + 1] = index end
    end
    for i = #headers, 1, -1 do
        if expandAll then api.ExpandSkillHeader(headers[i]) else api.CollapseSkillHeader(headers[i]) end
    end
    self:Update()
end

function Skills:Update()
    local api = SkillAPI()
    if not api or not self.list or not self.list:IsShown() then return end
    local lines = SkillList()
    ScrollUpdate(self.scroll, #lines)
    local offset = ScrollOffset(self.scroll)
    local selected = api.GetSelectedSkill and api.GetSelectedSkill() or 0
    local anyCollapsed = false
    for _, info in ipairs(lines) do
        if info.isHeader and info.isCollapsed then anyCollapsed = true end
    end
    self.allButton.collapsed = anyCollapsed
    PlusMinus(self.allButton, anyCollapsed)
    for i = 1, SKILL_ROWS do
        local bar, header = self.rows[i], self.rows[i].header
        local info = lines[offset + i]
        if not info then
            bar:Hide()
            header:Hide()
        elseif info.isHeader then
            header.Text:SetText(info.name or "")
            header.index, header.collapsed = info.index, info.isCollapsed
            PlusMinus(header, info.isCollapsed)
            header:Show()
            bar:Hide()
        else
            bar.index = info.index
            ColorSkillBar(bar, info)
            if info.index == selected then
                if bar.Border.LockHighlight then bar.Border:LockHighlight() end
            elseif bar.Border.UnlockHighlight then
                bar.Border:UnlockHighlight()
            end
            bar:Show()
            header:Hide()
        end
    end
    -- detail for the selected skill
    local detail = self.detail
    local info = selected > 0 and api.GetSkillLineInfo(selected) or nil
    if info and not info.isHeader then
        ColorSkillBar(detail.bar, info)
        detail.bar:Show()
        detail.bar.Unlearn:SetShown(info.isAbandonable == true)
        detail.bar.Unlearn.skillName, detail.bar.Unlearn.skillID = info.name, info.skillID
        local template = Str("SKILL_DESCRIPTION", "%s%s")
        local ok, text = pcall(string.format, template, "", info.description or "")
        detail.Description:SetText(ok and text or (info.description or ""))
        detail.Description:Show()
    else
        detail.bar:Hide()
        detail.Description:Hide()
    end
end

M.RegisterPanel(Skills)

--------------------------------------------------------------------------
-- Honor (Forever's PvP rank tab)
--
-- Era's Honor tab listed honorable kills and contribution per session /
-- day / week; Forever keeps rank as a season-long "rank points" track
-- (a renown-style faction) with rewards per rank. The Era layout is kept
-- (Honor art panel, rank title with the rank badge, the 315x29 progress
-- bar under it) and the sections show what Forever has: season, rank
-- points, season cap, next reward, where to buy it.
--------------------------------------------------------------------------

local PVP_RANK_FACTION_ID = 2800
local HONOR_ART = {
    topLeft = PD .. "UI-Character-Honor-TopLeft",
    topRight = PD .. "UI-Character-Honor-TopRight",
    bottomLeft = PD .. "UI-Character-Honor-BottomLeft",
    bottomRight = PD .. "UI-Character-Honor-BottomRight",
    badge = "Interface\\PvPRankBadges\\PvPRank"
}

local Honor = {frameName = "PVPRankFrame", label = "honor"}

local function HonorAPI()
    return C_MajorFactions and C_MajorFactions.GetMajorFactionProgressionInfo and C_MajorFactions
end

local function RankTitle(rank)
    if not rank or rank <= 0 then return Str("PVP_RANK_0_NAME", "Civilian") end
    local faction01 = (UnitFactionGroup and UnitFactionGroup("player") == "Alliance") and 1 or 0
    local first = Enum and Enum.PvPRanks and Enum.PvPRanks.Rank_1 or 5
    local key = "PVP_RANK_" .. tostring(first + rank - 1) .. "_" .. tostring(faction01)
    local text
    if GetText and UnitSex then
        local ok, v = pcall(GetText, key, UnitSex("player"))
        if ok then text = v end
    end
    return text or Str(key, "Rank " .. rank)
end

local function Line(parent, font, width)
    local fs = parent:CreateFontString(nil, "ARTWORK", font)
    fs:SetJustifyH("LEFT")
    if width then fs:SetWidth(width) end
    return fs
end

function Honor:Build()
    local frame = G("PVPRankFrame")
    local panel = CreateFrame("Frame", "ForeverClassicUIHonorPanel", frame)
    panel:SetAllPoints(frame)
    panel:SetFrameLevel(frame:GetFrameLevel() + 2)
    self.panel = panel
    if HasFile(HONOR_ART.topLeft) then
        local function Piece(path, w, h, x, y)
            local t = panel:CreateTexture(nil, "BORDER")
            t:SetTexture(path); t:SetSize(w, h); t:SetPoint("TOPLEFT", panel, "TOPLEFT", x, y)
        end
        Piece(HONOR_ART.topLeft, 256, 256, 22, -69)
        Piece(HONOR_ART.topRight, 128, 256, 275, -69)
        Piece(HONOR_ART.bottomLeft, 256, 128, 22, -325)
        Piece(HONOR_ART.bottomRight, 128, 128, 275, -325)
    end
    panel.levelText = panel:CreateFontString(nil, "BORDER", "GameFontNormalSmall")
    panel.levelText:SetPoint("TOP", panel, "TOP", 7, -37)
    -- rank points bar behind the title (Era HonorFrameProgressBar 315x29 at 22,-77)
    local bar = CreateFrame("StatusBar", nil, panel)
    bar:SetSize(315, 29)
    bar:SetPoint("TOPLEFT", panel, "TOPLEFT", 22, -77)
    bar:SetFrameLevel(panel:GetFrameLevel())
    bar:SetStatusBarTexture(ART.skillsBar)
    bar:SetStatusBarColor(0.25, 0.25, 0.75)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    bar:EnableMouse(true)
    bar:SetScript("OnEnter", function(self) Tooltip(self, self.tooltip, true) end)
    bar:SetScript("OnLeave", HideTooltip)
    panel.bar = bar
    panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    panel.title:SetPoint("TOP", panel, "TOP", 0, -87)
    panel.rank = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    panel.rank:SetPoint("LEFT", panel.title, "RIGHT", 5, -1)
    panel.icon = panel:CreateTexture(nil, "OVERLAY")
    panel.icon:SetSize(24, 24)
    panel.icon:SetPoint("RIGHT", panel.title, "LEFT", -5, 0)
    -- the sections (Era: titles at 36,-112, rows indented 10)
    panel.seasonTitle = Line(panel, "GameFontNormal"); panel.seasonTitle:SetPoint("TOPLEFT", panel, "TOPLEFT", 36, -112)
    panel.points = Line(panel, "GameFontHighlightSmall", 300); panel.points:SetPoint("TOPLEFT", panel.seasonTitle, "BOTTOMLEFT", 10, -3)
    panel.total = Line(panel, "GameFontHighlightSmall", 300); panel.total:SetPoint("TOPLEFT", panel.points, "BOTTOMLEFT", 0, -2)
    panel.weekly = Line(panel, "GameFontNormalSmall", 300); panel.weekly:SetPoint("TOPLEFT", panel.total, "BOTTOMLEFT", 0, -2)
    panel.rewardTitle = Line(panel, "GameFontNormal"); panel.rewardTitle:SetPoint("TOPLEFT", panel.weekly, "BOTTOMLEFT", -10, -14)
    panel.rewardIcon = panel:CreateTexture(nil, "ARTWORK")
    panel.rewardIcon:SetSize(32, 32)
    panel.rewardIcon:SetPoint("TOPLEFT", panel.rewardTitle, "BOTTOMLEFT", 10, -4)
    panel.reward = Line(panel, "GameFontHighlightSmall", 250); panel.reward:SetPoint("LEFT", panel.rewardIcon, "RIGHT", 6, 0)
    panel.vendor = Line(panel, "GameFontNormalSmall", 300); panel.vendor:SetPoint("TOPLEFT", panel.rewardIcon, "BOTTOMLEFT", -10, -8)
    panel.seasonInfo = Line(panel, "GameFontHighlightSmall", 300); panel.seasonInfo:SetPoint("TOPLEFT", panel.vendor, "BOTTOMLEFT", 0, -10)
    panel.timer = Line(panel, "GameFontNormalSmall", 300); panel.timer:SetPoint("TOPLEFT", panel.seasonInfo, "BOTTOMLEFT", 0, -6)
    panel:RegisterEvent("UPDATE_FACTION")
    panel:RegisterEvent("MAJOR_FACTION_RENOWN_LEVEL_CHANGED")
    panel:SetScript("OnEvent", Guard("honor event", function() if panel:IsShown() and self.classic then Honor:Update() end end))
    panel:Hide()
end

function Honor:SetClassic(on)
    local frame = G("PVPRankFrame")
    if not frame or on == self.classic then return end
    self.classic = on
    for _, key in ipairs({"MainInfoFrame", "DetailFrame"}) do
        local f = frame[key]
        if f and f.SetShown then f:SetShown(not on) end
    end
    if frame.GetRegions then
        for _, region in ipairs({frame:GetRegions()}) do
            if region.SetAlpha then region:SetAlpha(on and 0 or 1) end
        end
    end
    if on then self.panel:Show(); self:Update() else self.panel:Hide() end
end

function Honor:Update()
    local panel = self.panel
    if not panel or not panel:IsShown() then return end
    local level = UnitLevel and UnitLevel("player") or 0
    local race = UnitRace and UnitRace("player") or ""
    local class = UnitClass and UnitClass("player") or ""
    panel.levelText:SetText(("%s %d %s %s"):format(Str("LEVEL", "Level"), level, race, class))
    local api = HonorAPI()
    local info = api and api.GetMajorFactionProgressionInfo(PVP_RANK_FACTION_ID)
    if not info then
        panel.title:SetText(Str("PVP_RANK_DETAIL_UNAVAILABLE", "No rank information."))
        panel.rank:SetText(""); panel.icon:Hide(); panel.bar:Hide()
        for _, key in ipairs({"seasonTitle", "points", "total", "weekly", "rewardTitle", "reward", "vendor", "seasonInfo", "timer"}) do panel[key]:SetText("") end
        panel.rewardIcon:Hide()
        return
    end
    local rank = info.renownLevel or 0
    local points, threshold = info.renownReputationEarned or 0, info.renownLevelThreshold or 0
    panel.title:SetText(RankTitle(rank))
    panel.rank:SetText(rank > 0 and ("(" .. Str("PVP_RANK_NUMBER", "Rank %d"):format(rank) .. ")") or "")
    if rank > 0 and HasFile(("%s%02d"):format(HONOR_ART.badge, rank)) then
        panel.icon:SetTexture(("%s%02d"):format(HONOR_ART.badge, rank))
        panel.icon:Show()
    else
        panel.icon:Hide()
    end
    panel.bar:Show()
    panel.bar:SetMinMaxValues(0, math.max(threshold, 1))
    panel.bar:SetValue(threshold > 0 and points or 1)
    panel.bar.tooltip = Str("PVP_RANK_CURRENT_PROGRESS", "Rank Points: %d / %d"):format(points, threshold)
    local season = GetCurrentArenaSeason and GetCurrentArenaSeason() or 0
    panel.seasonTitle:SetText(season > 0 and Str("EXPANSION_SEASON_NAME", "%sSeason %d"):format("", season) or Str("HONOR", "Honor"))
    panel.points:SetText(panel.bar.tooltip)
    local totalForRank = api.GetTotalReputationForRenownLevel and api.GetTotalReputationForRenownLevel(PVP_RANK_FACTION_ID, rank) or 0
    local myTotal = (totalForRank or 0) + points
    local weekCapRank = info.currentWeekProgressiveMaxLevel or 0
    local capTotal = api.GetTotalReputationForRenownLevel and api.GetTotalReputationForRenownLevel(PVP_RANK_FACTION_ID, weekCapRank) or 0
    if myTotal > 0 and (capTotal or 0) > 0 then
        panel.total:SetText(Str("PVP_RANK_SEASON_PROGRESS", "Season total: %d / %d"):format(myTotal, capTotal))
    elseif myTotal > 0 then
        panel.total:SetText(Str("PVP_RANK_SEASON_PROGRESS_NO_MAX", "Season total: %d"):format(myTotal))
    else
        panel.total:SetText("")
    end
    local prevCapTotal = api.GetTotalReputationForRenownLevel and api.GetTotalReputationForRenownLevel(PVP_RANK_FACTION_ID, info.previousWeekProgressiveMaxLevel or 0) or 0
    local increase = (capTotal or 0) - (prevCapTotal or 0)
    panel.weekly:SetText(increase > 0 and Str("PVP_RANK_WEEKLY_CAP_INCREASE", "The cap rose by %d this week."):format(increase) or "")
    -- next reward
    local maxRank = info.maxLevel or rank
    local nextRank, rewards
    if api.GetRenownRewardsForLevel then
        for test = rank + 1, maxRank do
            local list = api.GetRenownRewardsForLevel(PVP_RANK_FACTION_ID, test)
            if list and #list > 0 then nextRank, rewards = test, list; break end
        end
    end
    if nextRank then
        panel.rewardTitle:SetText(Str("PVP_RANK_NEXT_REWARD", "Next Rewards at Rank %d"):format(nextRank))
        local first = rewards[1]
        if first.icon then panel.rewardIcon:SetTexture(first.icon); panel.rewardIcon:Show() else panel.rewardIcon:Hide() end
        panel.reward:SetText(first.description or first.name or "")
        local horde = UnitFactionGroup and UnitFactionGroup("player") == "Horde"
        panel.vendor:SetText(horde and Str("PVP_RANK_REWARDS_VENDOR_HORDE", "Rewards may be purchased in Orgrimmar.") or Str("PVP_RANK_REWARDS_VENDOR_ALLIANCE", "Rewards may be purchased in Stormwind."))
    else
        panel.rewardTitle:SetText(""); panel.reward:SetText(""); panel.vendor:SetText(""); panel.rewardIcon:Hide()
    end
    local seasonMaxTotal = api.GetTotalReputationForRenownLevel and api.GetTotalReputationForRenownLevel(PVP_RANK_FACTION_ID, maxRank) or 0
    local ok, text = pcall(string.format, Str("PVP_RANK_SEASON_RANKUP_DESCRIPTION", "Each week the Rank Points cap is increased, up to a maximum of %d for Rank %d."), seasonMaxTotal, maxRank)
    panel.seasonInfo:SetText(ok and text or "")
    local left = C_SeasonInfo and C_SeasonInfo.GetTimeUntilCurrentPVPSeasonEnd and C_SeasonInfo.GetTimeUntilCurrentPVPSeasonEnd() or 0
    if left and left > 0 then
        local days = math.floor(left / 86400)
        panel.timer:SetText(Str("SEASON_ENDS_IN_TIME", "Season ends in %s"):format(days > 0 and (days .. "d") or (math.floor(left / 3600) .. "h")))
    else
        panel.timer:SetText("")
    end
end

M.RegisterPanel(Honor)
