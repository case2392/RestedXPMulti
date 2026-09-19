-- Forever Classic UI - character sheet
--
-- Forever's character window is the retail one: a 631x484 metal shell with
-- the paper doll on the left, a scrolling stats list on the right and six
-- picture tabs down the side. Classic Era's is 384x512, drawn from four
-- pieces of "UI-Character-CharacterTab" art, with the model in a window
-- between two columns of slots, a small attribute box and a resistance
-- column under it, and text tabs along the bottom edge.
--
-- What this part does while the Character tab is showing:
--   * CharacterFrame is resized to 384x512 (Blizzard's UpdateSize is
--     re-applied after every RefreshDisplay, so it is hooked and undone);
--   * the retail shell (NineSlice, pane hosts, stats list, sidebar tabs,
--     level banner, collapse button, side tabs) is faded to alpha 0 and
--     its mouse disabled; the classic art goes on a frame of ours;
--   * Blizzard's slot buttons, model scene, portrait and title are
--     re-anchored to the Era positions (all widget calls);
--   * attribute and resistance panels of ours are filled from the unit
--     stat API the way Era's PaperDollFrame.lua did;
--   * text tabs of ours along the bottom call ToggleCharacter().
-- On the other tabs (reputation, skills, honor...) Blizzard's layout is
-- put back until those get their classic versions.
--
-- Every number here comes from Era's PaperDollFrame.xml / CharacterFrame.xml
-- and a `/cui report all` taken on Classic Era 1.15.9. Rule as elsewhere:
-- no Lua field writes into Blizzard's frames, widget calls and
-- hooksecurefunc only; anything of ours hung on a Blizzard frame lives in
-- M.own.

local addonName, ns = ...

local M = {mode = "off"}

local PD = "Interface\\PaperDollInfoFrame\\"
local ART = {
    topLeft = PD .. "UI-Character-CharacterTab-L1",
    topRight = PD .. "UI-Character-CharacterTab-R1",
    bottomLeft = PD .. "UI-Character-CharacterTab-BottomLeft",
    bottomRight = PD .. "UI-Character-CharacterTab-BottomRight",
    generalTopLeft = PD .. "UI-Character-General-TopLeft",
    generalTopRight = PD .. "UI-Character-General-TopRight",
    generalBottomLeft = PD .. "UI-Character-General-BottomLeft",
    generalBottomRight = PD .. "UI-Character-General-BottomRight",
    statBackground = PD .. "UI-Character-StatBackground",
    resistanceIcons = PD .. "UI-Character-ResistanceIcons",
    activeTab = PD .. "UI-Character-ActiveTab",
    inactiveTab = PD .. "UI-Character-InActiveTab",
    tabHighlight = PD .. "UI-Character-Tab-Highlight",
    ammoSlot = PD .. "UI-Character-AmmoSlot",
    closeUp = "Interface\\Buttons\\UI-Panel-MinimizeButton-Up",
    closeDown = "Interface\\Buttons\\UI-Panel-MinimizeButton-Down",
    closeHighlight = "Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight"
}
M.ART = ART

-- the four-piece 384x512 art sets: the paper doll's own, and the "General"
-- one every other Era tab used (drawn 2px right, 1px down of the frame)
M.DOLL_ART = {ART.topLeft, ART.topRight, ART.bottomLeft, ART.bottomRight, x = 0, y = 0}
M.GENERAL_ART = {ART.generalTopLeft, ART.generalTopRight, ART.generalBottomLeft, ART.generalBottomRight, x = 2, y = -1}

-- other tabs (reputation, skills...) register themselves here, see CharacterLists.lua
M.panels = {}
function M.RegisterPanel(panel)
    M.panels[#M.panels + 1] = panel
end

local FRAME_WIDTH, FRAME_HEIGHT = 384, 512
local PANEL_WIDTH = 400 -- what UIParent reserves for the panel (Era: frame + tab strip margin)

-- Era slot positions, relative to PaperDollFrame's TOPLEFT (BOTTOMLEFT for the weapons)
local SLOT_LEFT = {"CharacterHeadSlot", "CharacterNeckSlot", "CharacterShoulderSlot", "CharacterBackSlot",
                   "CharacterChestSlot", "CharacterShirtSlot", "CharacterTabardSlot", "CharacterWristSlot"}
local SLOT_RIGHT = {"CharacterHandsSlot", "CharacterWaistSlot", "CharacterLegsSlot", "CharacterFeetSlot",
                    "CharacterFinger0Slot", "CharacterFinger1Slot", "CharacterTrinket0Slot", "CharacterTrinket1Slot"}
local SLOT_STEP = 41 -- 37px slot + 4px gap

-- bottom tabs, Era order; a tab only exists when Forever has the frame
local TABS = {
    {frame = "PaperDollFrame", text = "CHARACTER", fallback = "Character"},
    {frame = "ReputationFrame", text = "REPUTATION", fallback = "Reputation"},
    {frame = "SkillsFrame", text = "SKILLS", fallback = "Skills"},
    {frame = "PVPRankFrame", text = "HONOR", fallback = "Honor"},
    {frame = "TokenFrame", text = "CURRENCY", fallback = "Currency", currency = true},
    {frame = "StatisticsFrame", text = "STATISTICS", fallback = "Statistics"}
}
local TAB_PADDING = 40      -- Era: text width + 40
local TAB_MIN_PADDING = 20
local TAB_ROW_WIDTH = 340   -- room from the first tab's left edge to the frame's right edge

-- resistance column, top to bottom: damage school id (UnitResistance index)
-- and the row of the icon strip
local RESISTANCES = {
    {id = 6, top = 0.2265625, bottom = 0.33984375, stat = "ARCANE"},
    {id = 2, top = 0, bottom = 0.11328125, stat = "FIRE"},
    {id = 3, top = 0.11328125, bottom = 0.2265625, stat = "NATURE"},
    {id = 4, top = 0.33984375, bottom = 0.453125, stat = "FROST"},
    {id = 5, top = 0.453125, bottom = 0.56640625, stat = "SHADOW"}
}
local STATS = {"STRENGTH", "AGILITY", "STAMINA", "INTELLECT", "SPIRIT"}

-- our own textures / frames hung on Blizzard frames, keyed by that frame
M.own = setmetatable({}, {__mode = "k"})
local function Own(frame)
    local t = M.own[frame]
    if not t then
        t = {}
        M.own[frame] = t
    end
    return t
end

local function G(name)
    return _G[name]
end

local function Str(key, fallback)
    local v = _G[key]
    if type(v) == "string" and v ~= "" then return v end
    return fallback
end

local function Fade(frame, on)
    if frame and frame.SetAlpha then frame:SetAlpha(on and 0 or 1) end
end

local function Mouse(frame, on)
    if frame and frame.EnableMouse then frame:EnableMouse(on) end
end

local function HasFile(path)
    if not GetFileIDFromPath then return true end
    local ok, id = pcall(GetFileIDFromPath, path)
    return ok and id ~= nil
end

-- errors inside Blizzard hooks are recorded instead of thrown
local function Guard(label, fn)
    return function(...)
        local ok, err = pcall(fn, ...)
        if not ok then ns.errors[#ns.errors + 1] = "charsheet " .. label .. ": " .. tostring(err) end
    end
end

-- remember a region's anchors and size so Disable can put them back
local function Remember(region)
    local own = Own(region)
    if own.saved then return end
    local saved = {points = {}}
    if region.GetNumPoints and region.GetPoint then
        for i = 1, region:GetNumPoints() do
            saved.points[i] = {region:GetPoint(i)}
        end
    end
    if region.GetSize then saved.width, saved.height = region:GetSize() end
    own.saved = saved
end

local function Restore(region)
    local own = M.own[region]
    local saved = own and own.saved
    if not saved then return end
    if region.ClearAllPoints and region.SetPoint then
        region:ClearAllPoints()
        for _, p in ipairs(saved.points) do
            if p[1] then region:SetPoint(p[1], p[2], p[3], p[4], p[5]) end
        end
    end
    if saved.width and region.SetSize then region:SetSize(saved.width, saved.height) end
end

local function Anchor(region, point, rel, relPoint, x, y, w, h)
    if not region then return end
    Remember(region)
    if region.ClearAllPoints and region.SetPoint then
        region:ClearAllPoints()
        region:SetPoint(point, rel, relPoint, x, y)
    end
    if w and region.SetSize then region:SetSize(w, h) end
end

local function InCombat()
    return InCombatLockdown and InCombatLockdown()
end

--------------------------------------------------------------------------
-- stat text helpers (Era's PaperDollFormatStat and friends)
--------------------------------------------------------------------------

local GREEN = "|cff20ff20"
local RED = "|cffff2020"
local WHITE = "|cffffffff"
local CLOSE = "|r"

local function Colored(color, value)
    return color .. value .. CLOSE
end

-- value coloured green when buffed, red when debuffed; tooltip line with the formula
local function FormatStat(name, base, posBuff, negBuff)
    local effective = math.max(0, base + posBuff + negBuff)
    local tooltip = WHITE .. name .. " " .. effective
    local text
    if posBuff == 0 and negBuff == 0 then
        tooltip = tooltip .. CLOSE
        text = tostring(effective)
    else
        tooltip = tooltip .. " (" .. base .. CLOSE
        if posBuff > 0 then tooltip = tooltip .. Colored(GREEN, "+" .. posBuff) end
        if negBuff < 0 then tooltip = tooltip .. Colored(RED, " " .. negBuff) end
        tooltip = tooltip .. WHITE .. ")" .. CLOSE
        text = Colored(negBuff < 0 and RED or GREEN, effective)
    end
    return text, tooltip
end

local function DamageRange(minDamage, maxDamage, color)
    local lo, hi = math.max(math.floor(minDamage), 1), math.max(math.ceil(maxDamage), 1)
    local sep = (lo < 100 and hi < 100) and " - " or "-"
    local text = lo .. sep .. hi
    if color then text = Colored(color, text) end
    return text, lo .. " - " .. hi
end

-- min/max/speed and bonuses -> display text, tooltip damage string, dps
local function FormatDamage(minDamage, maxDamage, bonusPos, bonusNeg, percent, speed)
    local baseMin, baseMax
    if percent == 0 then
        baseMin, baseMax = 0, 0
    else
        baseMin = (minDamage / percent) - bonusPos - bonusNeg
        baseMax = (maxDamage / percent) - bonusPos - bonusNeg
    end
    local baseDamage = (baseMin + baseMax) * 0.5
    local fullDamage = (baseDamage + bonusPos + bonusNeg) * percent
    local totalBonus = fullDamage - baseDamage
    if totalBonus < 0.1 and totalBonus > -0.1 then totalBonus = 0 end
    local dps = 0
    if speed and speed > 0 then dps = math.max(fullDamage, 1) / speed end
    local color
    if totalBonus > 0 then color = GREEN elseif totalBonus < 0 then color = RED end
    local text = DamageRange(minDamage, maxDamage, color)
    local _, tooltip = DamageRange(baseMin, baseMax)
    if totalBonus ~= 0 then
        if bonusPos > 0 then tooltip = tooltip .. Colored(GREEN, " +" .. bonusPos) end
        if bonusNeg < 0 then tooltip = tooltip .. Colored(RED, " " .. bonusNeg) end
        if percent > 1 then
            tooltip = tooltip .. Colored(GREEN, " x" .. math.floor(percent * 100 + 0.5) .. "%")
        elseif percent < 1 then
            tooltip = tooltip .. Colored(RED, " x" .. math.floor(percent * 100 + 0.5) .. "%")
        end
    end
    return text, tooltip, dps
end

--------------------------------------------------------------------------
-- our frames: art, level/guild text, attribute box, resistance column, tabs
--------------------------------------------------------------------------

local function StatTooltip(row)
    if not row.tooltip or not GameTooltip then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetText(row.tooltip, 1, 1, 1)
    if row.tooltip2 then
        GameTooltip:AddLine(row.tooltip2, 1, 0.82, 0, true)
    end
    GameTooltip:Show()
end

local function DamageTooltip(row)
    if not row.damage or not GameTooltip then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetText(row.title, 1, 1, 1)
    GameTooltip:AddDoubleLine(Str("ATTACK_SPEED_COLON", "Attack Speed:"), ("%.2f"):format(row.attackSpeed or 0), 1, 0.82, 0, 1, 1, 1)
    GameTooltip:AddDoubleLine(Str("DAMAGE_COLON", "Damage:"), row.damage, 1, 0.82, 0, 1, 1, 1)
    GameTooltip:AddDoubleLine(Str("DAMAGE_PER_SECOND", "Damage Per Second"), ("%.1f"):format(row.dps or 0), 1, 0.82, 0, 1, 1, 1)
    if row.offhandDamage then
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine(Str("ATTACK_SPEED_COLON", "Attack Speed:"), ("%.2f"):format(row.offhandSpeed or 0), 1, 0.82, 0, 1, 1, 1)
        GameTooltip:AddDoubleLine(Str("DAMAGE_COLON", "Damage:"), row.offhandDamage, 1, 0.82, 0, 1, 1, 1)
        GameTooltip:AddDoubleLine(Str("DAMAGE_PER_SECOND", "Damage Per Second"), ("%.1f"):format(row.offhandDps or 0), 1, 0.82, 0, 1, 1, 1)
    end
    GameTooltip:Show()
end

local function HideTooltip()
    if GameTooltip then GameTooltip:Hide() end
end

-- one "Label:   value" row of the attribute box (Era AttributeFrameTemplate, 104x13)
local function StatRow(parent, width, label, onEnter)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(width or 104, 13)
    row:EnableMouse(true)
    row.Label = row:CreateFontString(nil, "BACKGROUND", "GameFontNormalSmall")
    row.Label:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.Label:SetText(label)
    row.Value = row:CreateFontString(nil, "BACKGROUND", "GameFontHighlightSmall")
    row.Value:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.Value:SetJustifyH("RIGHT")
    row:SetScript("OnEnter", onEnter or StatTooltip)
    row:SetScript("OnLeave", HideTooltip)
    return row
end

local function StatBackground(parent, x, y, middleHeight, relTo)
    local tex = ART.statBackground
    local top = parent:CreateTexture(nil, "BACKGROUND")
    top:SetTexture(tex)
    top:SetSize(115, 16)
    top:SetTexCoord(0, 0.8984375, 0, 0.125)
    if relTo then
        top:SetPoint("TOPLEFT", relTo, "BOTTOMLEFT", x, y)
    else
        top:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    end
    local middle = parent:CreateTexture(nil, "BACKGROUND")
    middle:SetTexture(tex)
    middle:SetSize(115, middleHeight)
    middle:SetTexCoord(0, 0.8984375, 0.125, 0.1953125)
    middle:SetPoint("TOPLEFT", top, "BOTTOMLEFT", 0, 0)
    local bottom = parent:CreateTexture(nil, "BACKGROUND")
    bottom:SetTexture(tex)
    bottom:SetSize(115, 16)
    bottom:SetTexCoord(0, 0.8984375, 0.484375, 0.609375)
    bottom:SetPoint("TOPLEFT", middle, "BOTTOMLEFT", 0, 0)
    return bottom
end

local function BuildAttributes(sheet)
    -- Era CharacterAttributesFrame: 230x78 at 67,-291
    local box = CreateFrame("Frame", nil, sheet.doll)
    box:SetSize(230, 78)
    box:SetPoint("TOPLEFT", sheet, "TOPLEFT", 67, -291)
    box:SetFrameLevel(sheet:GetFrameLevel() + 1)
    StatBackground(box, 0, 0, 53)
    local meleeBottom = StatBackground(box, 115, 0, 12)
    StatBackground(box, 0, 2, 11, meleeBottom)

    local rows = {}
    local prev
    for i, stat in ipairs(STATS) do
        local row = StatRow(box, 104, Str("SPELL_STAT" .. i .. "_NAME", stat) .. ":")
        if prev then
            row:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, 0)
        else
            row:SetPoint("TOPLEFT", box, "TOPLEFT", 6, -3)
        end
        row.stat = stat
        row.statIndex = i
        rows[stat] = row
        prev = row
    end
    rows.ARMOR = StatRow(box, 104, Str("ARMOR_COLON", Str("ARMOR", "Armor") .. ":"))
    rows.ARMOR:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, 0)

    rows.ATTACK = StatRow(box, 104, Str("MELEE_ATTACK", "Melee Attack"))
    rows.ATTACK:SetPoint("TOPLEFT", box, "TOPLEFT", 122, -2)
    rows.ATTACK_POWER = StatRow(box, 99, Str("ATTACK_POWER_COLON", "Attack Power:"))
    rows.ATTACK_POWER:SetPoint("TOPLEFT", rows.ATTACK, "BOTTOMLEFT", 5, 1)
    rows.DAMAGE = StatRow(box, 99, Str("DAMAGE_COLON", "Damage:"), DamageTooltip)
    rows.DAMAGE:SetPoint("TOPLEFT", rows.ATTACK_POWER, "BOTTOMLEFT", 0, 1)
    rows.DAMAGE.title = Str("INVTYPE_WEAPONMAINHAND", "Main Hand")
    rows.RANGED_ATTACK = StatRow(box, 104, Str("RANGED_ATTACK", "Ranged Attack"))
    rows.RANGED_ATTACK:SetPoint("TOPLEFT", rows.DAMAGE, "BOTTOMLEFT", -5, -6)
    rows.RANGED_ATTACK_POWER = StatRow(box, 99, Str("ATTACK_POWER_COLON", "Attack Power:"))
    rows.RANGED_ATTACK_POWER:SetPoint("TOPLEFT", rows.RANGED_ATTACK, "BOTTOMLEFT", 5, 1)
    rows.RANGED_DAMAGE = StatRow(box, 99, Str("DAMAGE_COLON", "Damage:"), DamageTooltip)
    rows.RANGED_DAMAGE:SetPoint("TOPLEFT", rows.RANGED_ATTACK_POWER, "BOTTOMLEFT", 0, 1)
    rows.RANGED_DAMAGE.title = Str("INVTYPE_RANGED", "Ranged")
    sheet.attributes = box
    sheet.rows = rows
end

local function BuildResistances(sheet)
    -- Era CharacterResistanceFrame: 32x160, its TOPRIGHT at 297,-77 of the frame's TOPLEFT
    local column = CreateFrame("Frame", nil, sheet.doll)
    column:SetSize(32, 160)
    column:SetPoint("TOPRIGHT", sheet, "TOPLEFT", 297, -77)
    column:SetFrameLevel(sheet:GetFrameLevel() + 1)
    local prev
    sheet.resistances = {}
    for i, res in ipairs(RESISTANCES) do
        local f = CreateFrame("Frame", nil, column)
        f:SetSize(32, 29)
        f:EnableMouse(true)
        if prev then
            f:SetPoint("TOP", prev, "BOTTOM", 0, 0)
        else
            f:SetPoint("TOP", column, "TOP", 0, 0)
        end
        local icon = f:CreateTexture(nil, "BACKGROUND")
        icon:SetTexture(ART.resistanceIcons)
        icon:SetTexCoord(0, 1, res.top, res.bottom)
        icon:SetAllPoints(f)
        f.Value = f:CreateFontString(nil, "BACKGROUND", "GameFontHighlightSmall")
        f.Value:SetPoint("BOTTOM", f, "BOTTOM", 0, 3)
        f.id = res.id
        f.stat = res.stat
        f:SetScript("OnEnter", StatTooltip)
        f:SetScript("OnLeave", HideTooltip)
        sheet.resistances[i] = f
        prev = f
    end
end

-- classic ammo slot art around Blizzard's ammo button (a plate under it, the
-- bracket over it); only when the client still has the file
local function BuildAmmoArt(sheet)
    local ammo = G("CharacterAmmoSlot")
    if not ammo or not HasFile(ART.ammoSlot) then return end
    local under = CreateFrame("Frame", nil, sheet.doll)
    under:SetSize(41, 41)
    under:SetPoint("CENTER", ammo, "CENTER", 0, 0)
    under:SetFrameLevel(100) -- just under the slot buttons (101)
    local plate = under:CreateTexture(nil, "BACKGROUND")
    plate:SetTexture(ART.ammoSlot)
    plate:SetTexCoord(0, 0.640625, 0, 0.640625)
    plate:SetAllPoints(under)
    local over = CreateFrame("Frame", nil, sheet.doll)
    over:SetSize(23, 41)
    over:SetPoint("CENTER", ammo, "CENTER", -22, 0)
    over:SetFrameLevel(102)
    local bracket = over:CreateTexture(nil, "OVERLAY")
    bracket:SetTexture(ART.ammoSlot)
    bracket:SetTexCoord(0.640625, 1, 0, 0.640625)
    bracket:SetAllPoints(over)
    sheet.ammoUnder, sheet.ammoOver = under, over
end

-- point the four art pieces at a set (paper doll or General) and place them
function M.SetArt(set, sheet)
    sheet = sheet or M.sheet
    if not sheet or sheet.artSet == set then return end
    local x, y = set.x or 0, set.y or 0
    local places = {{x, y}, {x + 256, y}, {x, y - 256}, {x + 256, y - 256}}
    for i, tex in ipairs(sheet.art) do
        tex:SetTexture(set[i])
        tex:ClearAllPoints()
        tex:SetPoint("TOPLEFT", sheet, "TOPLEFT", places[i][1], places[i][2])
    end
    sheet.artSet = set
end

local function BuildSheet()
    local cf = G("CharacterFrame")
    local sheet = CreateFrame("Frame", "ForeverClassicUICharacterSheet", cf)
    sheet:SetAllPoints(cf)
    sheet:SetFrameLevel(cf:GetFrameLevel() + 1)
    local function Piece(w, h)
        local t = sheet:CreateTexture(nil, "BORDER")
        t:SetSize(w, h)
        return t
    end
    sheet.art = {Piece(256, 256), Piece(128, 256), Piece(256, 256), Piece(128, 256)}
    M.SetArt(M.DOLL_ART, sheet)
    -- the paper doll's own pieces live on a sub-frame shown on the Character tab only
    sheet.doll = CreateFrame("Frame", nil, sheet)
    sheet.doll:SetAllPoints(sheet)
    sheet.doll:SetFrameLevel(sheet:GetFrameLevel())
    -- "Level 39 Human Priest" under the name, guild line under that (Era: GameFontNormalSmall)
    sheet.levelText = sheet.doll:CreateFontString(nil, "BORDER", "GameFontNormalSmall")
    sheet.levelText:SetPoint("TOP", sheet, "TOP", 7, -37)
    sheet.levelText:SetJustifyH("CENTER")
    sheet.guildText = sheet.doll:CreateFontString(nil, "BORDER", "GameFontNormalSmall")
    sheet.guildText:SetPoint("TOP", sheet.levelText, "BOTTOM", 0, -1)
    sheet.guildText:SetJustifyH("CENTER")
    BuildAttributes(sheet)
    BuildResistances(sheet)
    BuildAmmoArt(sheet)
    -- classic close button (Blizzard's red one is faded while we are on)
    local close = CreateFrame("Button", nil, sheet)
    close:SetSize(32, 32)
    close:SetPoint("CENTER", cf, "TOPRIGHT", -44, -25)
    close:SetFrameLevel(cf:GetFrameLevel() + 5)
    close:SetNormalTexture(ART.closeUp)
    close:SetPushedTexture(ART.closeDown)
    close:SetHighlightTexture(ART.closeHighlight, "ADD")
    close:SetScript("OnClick", function()
        if HideUIPanel then HideUIPanel(cf) else cf:Hide() end
    end)
    sheet.close = close
    sheet:Hide()
    return sheet
end

-- events that change what the attribute box shows
local SHEET_EVENTS = {
    "UNIT_STATS", "UNIT_RESISTANCES", "UNIT_ATTACK", "UNIT_DAMAGE", "UNIT_ATTACK_POWER",
    "UNIT_RANGED_ATTACK_POWER", "UNIT_RANGEDDAMAGE", "UNIT_ATTACK_SPEED", "UNIT_LEVEL",
    "UNIT_AURA", "UNIT_MAXHEALTH"
}
local SHEET_EVENTS_GLOBAL = {
    "PLAYER_EQUIPMENT_CHANGED", "PLAYER_GUILD_UPDATE", "SKILL_LINES_CHANGED", "PLAYER_ENTERING_WORLD",
    "COMBAT_RATING_UPDATE", "PLAYER_DAMAGE_DONE_MODS"
}

--------------------------------------------------------------------------
-- filling the panels
--------------------------------------------------------------------------

-- Forever can hand a unit number back as a "secret value" once addon code
-- has tainted the call path (the error reads "arithmetic on a secret
-- number value"). The C layer throws that straight past pcall, so a
-- secret has to be spotted before it is used. Every number a unit API
-- returns comes through here: plain numbers come back as a list, and a
-- single secret one returns nil, which leaves the row showing whatever it
-- last had instead of erroring out of the whole update.
local function Numbers(...)
    local count = select("#", ...)
    local out = {}
    for i = 1, count do
        local v = select(i, ...)
        if v == nil then
            out[i] = 0
        else
            if issecretvalue then
                local ok, secret = pcall(issecretvalue, v)
                if (not ok) or secret == true then
                    M.secretReads = (M.secretReads or 0) + 1
                    return nil
                end
            end
            if type(v) ~= "number" then return nil end
            out[i] = v
        end
    end
    return out
end

local function ClassStatTooltip(stat)
    if not UnitClass then return end
    local _, classFile = UnitClass("player")
    local text
    if classFile then text = _G[string.upper(classFile) .. "_" .. stat .. "_TOOLTIP"] end
    if type(text) ~= "string" then text = _G["DEFAULT_" .. stat .. "_TOOLTIP"] end
    if type(text) == "string" then return text end
end

local function UpdatePrimaryStats(sheet)
    if not UnitStat then return end
    for i, stat in ipairs(STATS) do
        local row = sheet.rows[stat]
        local n = Numbers(UnitStat("player", i))
        if n then
            local effective, posBuff, negBuff = n[2], n[3], n[4]
            local name = Str("SPELL_STAT" .. i .. "_NAME", stat)
            local text, tooltip = FormatStat(name, effective - posBuff - negBuff, posBuff, negBuff)
            row.Value:SetText(text)
            row.tooltip = tooltip
            row.tooltip2 = ClassStatTooltip(stat)
        end
    end
end

local function UpdateArmor(sheet)
    local row = sheet.rows.ARMOR
    if not UnitArmor then
        row.Value:SetText("-")
        return
    end
    local n = Numbers(UnitArmor("player"))
    if not n then return end
    local base, effective, posBuff, negBuff = n[1], n[2], n[4], n[5]
    local text, tooltip = FormatStat(Str("ARMOR", "Armor"), base, posBuff, negBuff)
    row.Value:SetText(text)
    row.tooltip = tooltip
    local reduction
    if PaperDollFrame_GetArmorReduction then
        local ok, value = pcall(PaperDollFrame_GetArmorReduction, effective, UnitLevel("player"))
        if ok and type(value) == "number" then reduction = value end
    end
    row.tooltip2 = nil
    if reduction then
        local level = UnitLevel and UnitLevel("player") or 0
        local ok, text = pcall(string.format, Str("DEFAULT_STATARMOR_TOOLTIP", "Reduces physical damage taken from level %d attackers by %.2f%%"), level, reduction)
        if ok then row.tooltip2 = text end
    end
end

-- Forever has no UnitAttackBothHands; the weapon skill is read off the
-- skills list instead: item weapon subclass -> Era skill line id.
local WEAPON_SKILL_BY_SUBCLASS = {
    [0] = 44, [1] = 172, [2] = 45, [3] = 46, [4] = 54, [5] = 160, [6] = 229, [7] = 43,
    [8] = 55, [10] = 136, [11] = 473, [12] = 473, [13] = 162, [15] = 173, [16] = 176,
    [18] = 226, [19] = 228
}
local UNARMED_SKILL = 162

local function WeaponSkillFromSkills()
    local api = C_SkillInfo
    if not (api and api.GetNumSkillLines and api.GetSkillLineInfo) then return end
    local skillID = UNARMED_SKILL
    local itemID = GetInventoryItemID and GetInventoryItemID("player", 16)
    if itemID then
        local classID, subclassID
        if C_Item and C_Item.GetItemInfoInstant then
            local _, _, _, _, _, c, s = C_Item.GetItemInfoInstant(itemID)
            classID, subclassID = c, s
        elseif GetItemInfoInstant then
            local _, _, _, _, _, c, s = GetItemInfoInstant(itemID)
            classID, subclassID = c, s
        end
        if classID == 2 and WEAPON_SKILL_BY_SUBCLASS[subclassID] then
            skillID = WEAPON_SKILL_BY_SUBCLASS[subclassID]
        end
    end
    for i = 1, api.GetNumSkillLines() do
        local info = api.GetSkillLineInfo(i)
        if info and not info.isHeader and info.skillID == skillID then
            return info.rank or 0, (info.modifier or 0) + (info.tempPoints or 0), info.name
        end
    end
end

local function UpdateMelee(sheet)
    local rows = sheet.rows
    -- weapon skill line (Era "Melee Attack 195")
    local skill
    if UnitAttackBothHands then skill = Numbers(UnitAttackBothHands("player")) end
    if not skill then
        -- the skills list also hands back a name: only the two numbers go in
        local rank, mod = WeaponSkillFromSkills()
        if rank ~= nil then skill = Numbers(rank, mod) end
    end
    if skill and skill[1] then
        local base, mod = skill[1], skill[2] or 0
        if mod == 0 then
            rows.ATTACK.Value:SetText(base)
        else
            rows.ATTACK.Value:SetText(Colored(mod > 0 and GREEN or RED, base + mod))
        end
        rows.ATTACK.tooltip = Str("ATTACK_TOOLTIP", "Weapon Skill")
        rows.ATTACK.tooltip2 = Str("ATTACK_TOOLTIP_SUBTEXT", "Your skill with the equipped weapon.")
    else
        rows.ATTACK.Value:SetText("-")
        rows.ATTACK.tooltip = nil
    end
    local ap = UnitAttackPower and Numbers(UnitAttackPower("player"))
    if ap then
        local base, posBuff, negBuff = ap[1], ap[2], ap[3]
        local text, tooltip = FormatStat(Str("MELEE_ATTACK_POWER", "Melee Attack Power"), base, posBuff, negBuff)
        rows.ATTACK_POWER.Value:SetText(text)
        rows.ATTACK_POWER.tooltip = tooltip
        local perSecond = math.max(base + posBuff + negBuff, 0) / (ATTACK_POWER_MAGIC_NUMBER or 14)
        rows.ATTACK_POWER.tooltip2 = ("Increases damage with melee weapons by %.1f damage per second."):format(perSecond)
    elseif not UnitAttackPower then
        rows.ATTACK_POWER.Value:SetText("-")
    end
    local dmg = UnitDamage and Numbers(UnitDamage("player"))
    local spd = UnitAttackSpeed and Numbers(UnitAttackSpeed("player"))
    if dmg then
        local minDamage, maxDamage, minOff, maxOff = dmg[1], dmg[2], dmg[3], dmg[4]
        local bonusPos, bonusNeg, percent = dmg[5], dmg[6], dmg[7] ~= 0 and dmg[7] or 1
        local speed, offSpeed = spd and spd[1] or 0, spd and spd[2] or 0
        local text, tooltip, dps = FormatDamage(minDamage, maxDamage, bonusPos, bonusNeg, percent, speed)
        local row = rows.DAMAGE
        row.Value:SetText(text)
        row.damage, row.dps, row.attackSpeed = tooltip, dps, speed or 0
        if offSpeed > 0 and minOff and maxOff then
            local _, offTooltip, offDps = FormatDamage(minOff, maxOff, bonusPos, bonusNeg, percent, offSpeed)
            row.offhandDamage, row.offhandDps, row.offhandSpeed = offTooltip, offDps, offSpeed
        else
            row.offhandDamage, row.offhandDps, row.offhandSpeed = nil, nil, nil
        end
    elseif not UnitDamage then
        rows.DAMAGE.Value:SetText("-")
    end
end

local function UpdateRanged(sheet)
    local rows = sheet.rows
    local hasRanged = GetInventoryItemTexture and GetInventoryItemTexture("player", 18) ~= nil
    if UnitHasRelicSlot and UnitHasRelicSlot("player") then hasRanged = false end
    local na = Str("NOT_APPLICABLE", "N/A")
    if not hasRanged or not UnitRangedAttack then
        rows.RANGED_ATTACK.Value:SetText(na)
        rows.RANGED_ATTACK.tooltip = nil
        rows.RANGED_ATTACK_POWER.Value:SetText(na)
        rows.RANGED_ATTACK_POWER.tooltip = nil
        rows.RANGED_DAMAGE.Value:SetText(na)
        rows.RANGED_DAMAGE.damage = nil
        return
    end
    local ranged = Numbers(UnitRangedAttack("player"))
    if ranged then
        local base, mod = ranged[1], ranged[2]
        if mod == 0 then
            rows.RANGED_ATTACK.Value:SetText(base)
        else
            rows.RANGED_ATTACK.Value:SetText(Colored(mod > 0 and GREEN or RED, base + mod))
        end
        rows.RANGED_ATTACK.tooltip = Str("RANGED_ATTACK_TOOLTIP", "Ranged Weapon Skill")
        rows.RANGED_ATTACK.tooltip2 = Str("RANGED_ATTACK_TOOLTIP_SUBTEXT", "Your skill with the equipped ranged weapon.")
    end
    local wand = HasWandEquipped and HasWandEquipped()
    if wand or not UnitRangedAttackPower then
        rows.RANGED_ATTACK_POWER.Value:SetText("--")
        rows.RANGED_ATTACK_POWER.tooltip = nil
    else
        local rap = Numbers(UnitRangedAttackPower("player"))
        if rap then
            local apBase, posBuff, negBuff = rap[1], rap[2], rap[3]
            local text, tooltip = FormatStat(Str("RANGED_ATTACK_POWER", "Ranged Attack Power"), apBase, posBuff, negBuff)
            rows.RANGED_ATTACK_POWER.Value:SetText(text)
            rows.RANGED_ATTACK_POWER.tooltip = tooltip
            rows.RANGED_ATTACK_POWER.tooltip2 = ("Increases damage with ranged weapons by %.1f damage per second."):format(apBase / (ATTACK_POWER_MAGIC_NUMBER or 14))
        end
    end
    local rdmg = UnitRangedDamage and Numbers(UnitRangedDamage("player"))
    if rdmg then
        local speed, minDamage, maxDamage = rdmg[1], rdmg[2], rdmg[3]
        local bonusPos, bonusNeg, percent = rdmg[4], rdmg[5], rdmg[6] ~= 0 and rdmg[6] or 1
        local text, tooltip, dps = FormatDamage(minDamage, maxDamage, bonusPos, bonusNeg, percent, speed)
        local row = rows.RANGED_DAMAGE
        row.Value:SetText(text)
        row.damage, row.dps, row.attackSpeed = tooltip, dps, speed
    elseif not UnitRangedDamage then
        rows.RANGED_DAMAGE.Value:SetText("-")
    end
end

local function UpdateResistances(sheet)
    if not UnitResistance then return end
    for _, f in ipairs(sheet.resistances) do
        local n = Numbers(UnitResistance("player", f.id))
        if n then
        local base, resistance, positive, negative = n[1], n[2], n[3], n[4]
        if math.abs(negative) > positive then
            f.Value:SetText(Colored(RED, resistance))
        elseif math.abs(negative) == positive then
            f.Value:SetText(resistance)
        else
            f.Value:SetText(Colored(GREEN, resistance))
        end
        local name = Str("RESISTANCE" .. f.id .. "_NAME", Str("DAMAGE_SCHOOL" .. (f.id + 1), f.stat) .. " " .. Str("RESISTANCE", "Resistance"))
        local tooltip = name .. " " .. resistance
        if positive ~= 0 or negative ~= 0 then
            tooltip = tooltip .. " ( " .. WHITE .. base
            if positive > 0 then tooltip = tooltip .. GREEN .. " +" .. positive end
            if negative < 0 then tooltip = tooltip .. " " .. RED .. negative end
            tooltip = tooltip .. CLOSE .. " )"
        end
        f.tooltip = tooltip
        end
    end
end

local function UpdateHeader(sheet)
    local level = UnitLevel and UnitLevel("player") or 0
    local race = UnitRace and UnitRace("player") or ""
    local class = UnitClass and UnitClass("player") or ""
    sheet.levelText:SetText(("%s %d %s %s"):format(Str("LEVEL", "Level"), level, race, class))
    local guild, title
    if GetGuildInfo then guild, title = GetGuildInfo("player") end
    if guild then
        local template = Str("GUILD_TITLE_TEMPLATE", "%s of %s")
        if title and template:find("%%s.*%%s") then
            sheet.guildText:SetText(template:format(title, guild))
        else
            sheet.guildText:SetText(guild)
        end
        sheet.guildText:Show()
    else
        sheet.guildText:SetText("")
        sheet.guildText:Hide()
    end
end

function M.UpdateSheet()
    local sheet = M.sheet
    if not sheet or not sheet:IsShown() or not sheet.doll:IsShown() then return end
    UpdateHeader(sheet)
    UpdatePrimaryStats(sheet)
    UpdateArmor(sheet)
    UpdateMelee(sheet)
    UpdateRanged(sheet)
    UpdateResistances(sheet)
end

--------------------------------------------------------------------------
-- bottom tabs
--------------------------------------------------------------------------

local function TabPiece(tab, w, x, l, r)
    local t = tab:CreateTexture(nil, "BACKGROUND")
    t:SetSize(w, 32)
    t:SetTexCoord(l, r, 0, 1)
    return t
end

local function BuildTab(parent, info)
    local tab = CreateFrame("Button", nil, parent)
    tab:SetSize(60, 32)
    tab:SetFrameLevel(parent:GetFrameLevel() + 5)
    tab.Left = TabPiece(tab, 20, 0, 0, 0.15625)
    tab.Middle = TabPiece(tab, 20, 20, 0.15625, 0.84375)
    tab.Right = TabPiece(tab, 20, 40, 0.84375, 1)
    tab.Left:SetPoint("TOPLEFT", tab, "TOPLEFT", 0, 0)
    tab.Middle:SetPoint("LEFT", tab.Left, "RIGHT", 0, 0)
    tab.Right:SetPoint("LEFT", tab.Middle, "RIGHT", 0, 0)
    tab.Text = tab:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    tab.Text:SetPoint("CENTER", tab, "CENTER", 0, 2)
    tab.Text:SetText(Str(info.text, info.fallback))
    if HasFile(ART.tabHighlight) then
        tab:SetHighlightTexture(ART.tabHighlight, "ADD")
        local hl = tab:GetHighlightTexture()
        if hl then
            hl:ClearAllPoints()
            hl:SetPoint("TOPLEFT", tab, "TOPLEFT", 3, 5)
            hl:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -3, 0)
        end
    end
    tab.frameName = info.frame
    tab:SetScript("OnClick", function()
        if M.mode ~= "restyled" then return end
        if ToggleCharacter then
            ToggleCharacter(info.frame, true)
        end
    end)
    return tab
end

-- Era drew the selected tab with UI-Character-ActiveTab lifted 4px into the
-- frame's bottom edge. Forever's copy of that file is not Era's (it renders
-- as a glow band with no tab body), so every tab keeps the InActiveTab art
-- in place and the selected one is told apart the other Era way: white
-- text and the button disabled, like PanelTemplates_SelectTab.
local function SetTabSelected(tab, selected)
    local file = ART.inactiveTab
    tab.Left:SetTexture(file)
    tab.Middle:SetTexture(file)
    tab.Right:SetTexture(file)
    tab.Left:ClearAllPoints()
    tab.Left:SetPoint("TOPLEFT", tab, "TOPLEFT", 0, 0)
    tab.Text:ClearAllPoints()
    tab.Text:SetPoint("CENTER", tab, "CENTER", 0, 2)
    if selected then
        tab.Text:SetTextColor(1, 1, 1)
        if tab.Disable then tab:Disable() end
    else
        tab.Text:SetTextColor(1, 0.82, 0)
        if tab.Enable then tab:Enable() end
    end
    tab.selected = selected
end

local function TabWanted(info)
    local frame = G(info.frame)
    if not frame then return false end
    if info.currency then
        local cf = G("CharacterFrame")
        if cf and cf.ShouldShowCurrencyTab then
            local ok, show = pcall(cf.ShouldShowCurrencyTab, cf)
            if ok and show == false then return false end
        end
    end
    return true
end

-- lay the tabs out along the bottom edge: Era spacing when it fits, tighter
-- side padding when Forever's extra tabs (currency, statistics) would not
function M.LayoutTabs(classic)
    local tabs = M.tabs
    if not tabs then return end
    if classic == nil then classic = tabs.classic ~= false end
    tabs.classic = classic
    local shown, textTotal = {}, 0
    for _, tab in ipairs(tabs.list) do
        if TabWanted(tab.info) then
            shown[#shown + 1] = tab
            textTotal = textTotal + (tab.Text.GetStringWidth and tab.Text:GetStringWidth() or 40)
            tab:Show()
        else
            tab:Hide()
        end
    end
    local n = #shown
    if n == 0 then return end
    local padding = TAB_PADDING
    local total = textTotal + n * padding - (n - 1) * 16
    if classic and total > TAB_ROW_WIDTH then
        padding = math.max(TAB_MIN_PADDING, math.floor((TAB_ROW_WIDTH - textTotal + (n - 1) * 16) / n))
    end
    -- Era: the row sits on the sheet art's bottom margin. On a tab that keeps
    -- Blizzard's wide window (Currency, Statistics) the row hangs under the
    -- window's bottom edge instead, the way retail's own bottom tabs do.
    local tabY = classic and 62 or -14
    local prev
    for _, tab in ipairs(shown) do
        local textWidth = tab.Text.GetStringWidth and tab.Text:GetStringWidth() or 40
        local width = textWidth + padding
        tab:SetWidth(width)
        tab.Middle:SetWidth(math.max(width - 40, 1))
        tab:ClearAllPoints()
        if prev then
            tab:SetPoint("LEFT", prev, "RIGHT", -16, 0)
        else
            tab:SetPoint("CENTER", G("CharacterFrame"), "BOTTOMLEFT", 60, tabY)
        end
        prev = tab
    end
    tabs.padding = padding
end

function M.UpdateTabs()
    local tabs = M.tabs
    if not tabs then return end
    for _, tab in ipairs(tabs.list) do
        local frame = G(tab.frameName)
        local selected = frame ~= nil and frame.IsShown ~= nil and frame:IsShown() == true
        SetTabSelected(tab, selected)
    end
end

local function BuildTabs()
    local cf = G("CharacterFrame")
    local holder = CreateFrame("Frame", "ForeverClassicUICharacterTabs", cf)
    holder:SetSize(1, 1)
    holder:SetPoint("BOTTOMLEFT", cf, "BOTTOMLEFT", 0, 0)
    holder:SetFrameLevel(cf:GetFrameLevel() + 1)
    holder.list = {}
    for _, info in ipairs(TABS) do
        local tab = BuildTab(holder, info)
        tab.info = info
        holder.list[#holder.list + 1] = tab
    end
    holder:Hide()
    return holder
end

--------------------------------------------------------------------------
-- Blizzard's frame: shell on/off, paper doll re-anchoring
--------------------------------------------------------------------------

local function PaperDollShown()
    local pd = G("PaperDollFrame")
    return pd ~= nil and pd.IsShown ~= nil and pd:IsShown() == true
end

local function BlizzardShell(cf, hidden)
    Fade(cf.NineSlice, hidden)
    Fade(cf.LeftPaneHost, hidden)
    Fade(cf.RightPaneHost, hidden)
    Fade(cf.RightPaneToggleButton, hidden)
    Mouse(cf.RightPaneToggleButton, not hidden)
    Fade(cf.CloseButton, hidden)
    Mouse(cf.CloseButton, not hidden)
end

-- the retail paper doll extras that Blizzard shows again on every Expand()
local function PaperDollExtras(hidden)
    local stats = G("CharacterStatsPaneScrollBox")
    if stats then
        Fade(stats, hidden)
        Mouse(stats, not hidden)
        if stats.ScrollBox then Mouse(stats.ScrollBox, not hidden) end
        if hidden and stats.Hide then stats:Hide() end
    end
    local tabs = G("PaperDollSidebarTabs")
    if tabs then
        Fade(tabs, hidden)
        for i = 1, 3 do Mouse(G("PaperDollSidebarTab" .. i), not hidden) end
    end
    Fade(G("PaperDollLevelInfo"), hidden)
end

local function SideTabs(cf, hidden)
    local mt = cf.ModeTabs
    if not mt then return end
    Fade(mt, hidden)
    if mt.Tabs then
        for _, tab in ipairs(mt.Tabs) do Mouse(tab, not hidden) end
    end
end

-- portrait and title into the Era corners (Era: portrait 60x60 at 7,-6, name centred at TOP 7,-19)
local function Header(cf, classic)
    local portrait = cf.PortraitContainer and cf.PortraitContainer.portrait
    local mask = cf.PortraitContainer and cf.PortraitContainer.CircleMask
    local title = cf.TitleContainer
    if classic then
        Anchor(portrait, "TOPLEFT", cf, "TOPLEFT", 7, -6, 60, 60)
        if mask then
            Remember(mask)
            mask:ClearAllPoints()
            mask:SetPoint("TOPLEFT", portrait, "TOPLEFT", 0, 0)
            mask:SetPoint("BOTTOMRIGHT", portrait, "BOTTOMRIGHT", 0, 0)
        end
        Anchor(title, "TOP", cf, "TOP", 7, -14, 300, 20)
    else
        Restore(portrait)
        Restore(mask)
        Restore(title)
    end
end

local function SlotExtras(slot, hidden)
    if not slot then return end
    Fade(slot.BorderFrame, hidden)
end

local function AmmoExtras(ammo, hidden)
    if not ammo then return end
    if ammo.GetRegions then
        for _, region in ipairs({ammo:GetRegions()}) do
            if region.GetAtlas and region:GetAtlas() == "UI-Character-Info-GearSlotSmall" then Fade(region, hidden) end
        end
    end
    if ammo.GetChildren then
        for _, child in ipairs({ammo:GetChildren()}) do
            if child.GetRegions then
                for _, region in ipairs({child:GetRegions()}) do
                    if region.GetAtlas and region:GetAtlas() == "UI-Character-Info-GearSlot-Arrow" then Fade(child, hidden) end
                end
            end
        end
    end
end

-- Era slot layout on Blizzard's buttons; model window 233x224 at 65,-78
local function PaperDoll(classic)
    local pd = G("PaperDollFrame")
    if not pd then return end
    for i, name in ipairs(SLOT_LEFT) do
        local slot = G(name)
        if slot then
            if classic then Anchor(slot, "TOPLEFT", pd, "TOPLEFT", 21, -74 - (i - 1) * SLOT_STEP) else Restore(slot) end
            SlotExtras(slot, classic)
        end
    end
    for i, name in ipairs(SLOT_RIGHT) do
        local slot = G(name)
        if slot then
            if classic then Anchor(slot, "TOPLEFT", pd, "TOPLEFT", 306, -74 - (i - 1) * SLOT_STEP) else Restore(slot) end
            SlotExtras(slot, classic)
        end
    end
    local main, off, ranged, ammo = G("CharacterMainHandSlot"), G("CharacterSecondaryHandSlot"), G("CharacterRangedSlot"), G("CharacterAmmoSlot")
    if classic then
        Anchor(main, "TOPLEFT", pd, "BOTTOMLEFT", 122, 127)
        if main then Anchor(off, "TOPLEFT", main, "TOPRIGHT", 5, 0) end
        if off then Anchor(ranged, "TOPLEFT", off, "TOPRIGHT", 5, 0) end
        if ranged then Anchor(ammo, "LEFT", ranged, "RIGHT", 15, 0) end
    else
        Restore(main); Restore(off); Restore(ranged); Restore(ammo)
    end
    SlotExtras(main, classic); SlotExtras(off, classic); SlotExtras(ranged, classic)
    AmmoExtras(ammo, classic)
    local model = G("CharacterModelScene")
    if model then
        if classic then
            Anchor(model, "TOPLEFT", pd, "TOPLEFT", 65, -78, 233, 224)
        else
            Restore(model)
        end
        for _, key in ipairs({"BackgroundTopLeft", "BackgroundTopRight", "BackgroundBotLeft", "BackgroundBotRight", "BackgroundOverlay"}) do
            Fade(model[key], classic)
        end
    end
end

local function FrameShown(name)
    local f = G(name)
    return f ~= nil and f.IsShown ~= nil and f:IsShown() == true
end

-- which classic tab is up: "doll", a registered panel, or nil (a tab we leave to Blizzard)
local function ActivePanel()
    if PaperDollShown() then return "doll" end
    for _, panel in ipairs(M.panels) do
        if panel.built and FrameShown(panel.frameName) then return panel end
    end
end

-- the whole thing: classic look on the tabs we cover, Blizzard's on the others
function M.Apply()
    if M.mode ~= "restyled" then return end
    local cf = G("CharacterFrame")
    if not cf then return end
    local active = ActivePanel()
    local classic = active ~= nil
    if classic ~= M.applied then
        BlizzardShell(cf, classic)
        Header(cf, classic)
        PaperDoll(classic)
        M.applied = classic
    end
    if classic then
        cf:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
        if SetUIPanelAttribute then pcall(SetUIPanelAttribute, cf, "width", PANEL_WIDTH) end
        M.sheet:Show()
        if active == "doll" then
            PaperDollExtras(true)
            M.SetArt(M.DOLL_ART)
            M.sheet.doll:Show()
            M.UpdateSheet()
        else
            M.SetArt(active.art or M.GENERAL_ART)
            M.sheet.doll:Hide()
        end
    else
        PaperDollExtras(false)
        M.sheet:Hide()
        if SetUIPanelAttribute and cf.GetWidth then pcall(SetUIPanelAttribute, cf, "width", cf:GetWidth() + 82) end
    end
    for _, panel in ipairs(M.panels) do
        if panel.built then panel:SetClassic(panel == active) end
    end
    SideTabs(cf, true)
    M.tabs:Show()
    M.LayoutTabs(classic)
    M.UpdateTabs()
end

local function Undo()
    local cf = G("CharacterFrame")
    if not cf then return end
    BlizzardShell(cf, false)
    Header(cf, false)
    PaperDoll(false)
    PaperDollExtras(false)
    SideTabs(cf, false)
    for _, panel in ipairs(M.panels) do
        if panel.built then panel:SetClassic(false) end
    end
    M.applied = false
    if M.sheet then M.sheet:Hide() end
    if M.tabs then M.tabs:Hide() end
    if cf.UpdateSize then pcall(cf.UpdateSize, cf) end
    if cf.SetUIPanelAttribute then pcall(cf.SetUIPanelAttribute, cf) end
    if PaperDollShown() then
        local stats = G("CharacterStatsPaneScrollBox")
        if stats and stats.Show then stats:Show() end
    end
end

--------------------------------------------------------------------------
-- hooks
--------------------------------------------------------------------------

local function Hook()
    if M.hooked then return end
    local cf = G("CharacterFrame")
    if not cf or not hooksecurefunc then return end
    -- size and shell after every refresh (tab switch, show, pane toggle)
    if cf.RefreshDisplay then hooksecurefunc(cf, "RefreshDisplay", Guard("RefreshDisplay", M.Apply)) end
    if cf.UpdateSize then hooksecurefunc(cf, "UpdateSize", Guard("UpdateSize", function()
        if M.mode == "restyled" and PaperDollShown() then cf:SetSize(FRAME_WIDTH, FRAME_HEIGHT) end
    end)) end
    if cf.SetUIPanelAttribute and SetUIPanelAttribute then hooksecurefunc(cf, "SetUIPanelAttribute", Guard("SetUIPanelAttribute", function()
        if M.mode == "restyled" and PaperDollShown() then pcall(SetUIPanelAttribute, cf, "width", PANEL_WIDTH) end
    end)) end
    -- Blizzard shows its stats list / sidebar tabs / level banner again here
    if cf.Expand then hooksecurefunc(cf, "Expand", Guard("Expand", function()
        if M.mode == "restyled" and PaperDollShown() then PaperDollExtras(true) end
    end)) end
    if G("PaperDollFrame_ShowSidebar") then hooksecurefunc("PaperDollFrame_ShowSidebar", Guard("ShowSidebar", function(frame)
        if M.mode == "restyled" and PaperDollShown() and frame and frame.Hide then frame:Hide() end
    end)) end
    local pd = G("PaperDollFrame")
    if pd and pd.HookScript then
        pd:HookScript("OnShow", Guard("OnShow", M.Apply))
        pd:HookScript("OnHide", Guard("OnHide", M.Apply))
    end
    for _, panel in ipairs(M.panels) do
        local f = G(panel.frameName)
        if f and f.HookScript then
            f:HookScript("OnShow", Guard(panel.frameName .. " OnShow", function() M.Apply(); if panel.built then panel:Update() end end))
            f:HookScript("OnHide", Guard(panel.frameName .. " OnHide", M.Apply))
        end
    end
    M.hooked = true
end

--------------------------------------------------------------------------
-- module interface
--------------------------------------------------------------------------

local function IsForeverSheet()
    local cf = G("CharacterFrame")
    return cf ~= nil and cf.LeftPaneHost ~= nil and cf.ModeTabs ~= nil and G("PaperDollFrame") ~= nil
end

function M:Enable()
    if not G("CharacterFrame") then
        self.mode = "off"
        return
    end
    if not IsForeverSheet() then
        -- classic client: its own sheet already
        self.mode = "native"
        return
    end
    self.missingArt = {}
    for _, key in ipairs({"topLeft", "topRight", "bottomLeft", "bottomRight", "statBackground", "resistanceIcons", "inactiveTab"}) do
        if not HasFile(ART[key]) then self.missingArt[#self.missingArt + 1] = ART[key]:match("[^\\]+$") end
    end
    if not self.sheet then
        self.sheet = BuildSheet()
        self.tabs = BuildTabs()
        local ev = self.sheet
        for _, e in ipairs(SHEET_EVENTS) do
            if ev.RegisterUnitEvent then ev:RegisterUnitEvent(e, "player") else ev:RegisterEvent(e) end
        end
        for _, e in ipairs(SHEET_EVENTS_GLOBAL) do ev:RegisterEvent(e) end
        ev:SetScript("OnEvent", Guard("event", function() M.UpdateSheet() end))
    end
    for _, panel in ipairs(self.panels) do
        if not panel.built and G(panel.frameName) then
            if ns.SafeCall("charsheet " .. panel.frameName, panel.Build, panel) then panel.built = true end
        end
    end
    self.mode = "restyled"
    self.applied = nil
    Hook()
    M.Apply()
end

function M:Force()
    if self.mode == "restyled" then
        self.applied = nil
        M.Apply()
    end
end

function M:Disable()
    local was = self.mode
    self.mode = "off" -- first, so the hooks stop re-applying while things are put back
    if was == "restyled" then Undo() end
end

function M:Status()
    if self.mode == "restyled" then
        local tabs = {"character"}
        for _, panel in ipairs(self.panels) do
            if panel.built then tabs[#tabs + 1] = panel.label end
        end
        local s = "classic 384x512 sheet (" .. table.concat(tabs, ", ") .. " tabs), Era slot layout, bottom tabs"
        if (self.secretReads or 0) > 0 then
            s = s .. (" (%d stat reads came back secret and were left as they were)"):format(self.secretReads)
        end
        if self.missingArt and #self.missingArt > 0 then
            s = s .. " (art missing: " .. table.concat(self.missingArt, ", ") .. ")"
        end
        return s
    elseif self.mode == "native" then
        return "classic client, Blizzard's sheet left alone"
    end
    return "off"
end

ns.RegisterModule("charsheet", M)
ns.charsheet = M
