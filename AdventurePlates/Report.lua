-- Adventure Plates - the report, for bugs and ideas
--
-- /plate report opens a window with everything that helps: the addon and
-- client versions, the settings, what the plate holds, what has been
-- sent and received, the window's state, and any error the addon
-- caught. It is a text box, so Ctrl+A, Ctrl+C, and paste it as a
-- comment on the CurseForge page or in an email. Suggestions go the same
-- way.

local addonName, ns = ...

ns.FEEDBACK_URL = "https://www.curseforge.com/wow/addons/adventure-plates"
ns.FEEDBACK_EMAIL = "classicuiforforever@gmail.com"

local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d = pcall(fn, ...)
    if ok then return a, b, c, d end
end

local function yn(v) return v and "yes" or "no" end

function ns.BuildReport()
    local lines = {}
    local function line(fmt, ...) lines[#lines + 1] = select("#", ...) > 0 and fmt:format(...) or fmt end
    line("-- Adventure Plates %s report", ns.VERSION)
    line("-- Paste this as a comment on %s", ns.FEEDBACK_URL)
    line("-- or email it to %s. Ideas and suggestions are welcome the same way.", ns.FEEDBACK_EMAIL)
    line("")
    local version, build, date, toc = Call(GetBuildInfo)
    line("client: version %s build %s (%s) toc %s", tostring(version), tostring(build), tostring(date), tostring(toc))
    line("realm: %s  character: %s", ns.RealmName(), ns.CharKey())
    local s = ns.db and ns.db.settings or {}
    line("settings: share=%s menu=%s greet=%s minimap=%s learn=%s welcomed=%s", tostring(s.share), yn(s.menu), yn(s.greet), yn(s.minimap), yn(s.learn), yn(s.welcomed))
    local p = ns.db and ns.db.plates[ns.CharKey()]
    if p then
        line("my plate: title=%q tags=%s roles=%s motto=%d chars looking=%q main=%q weekdays=%s weekends=%s",
             p.title or "", table.concat(p.tags or {}, ","),
             (p.roles and p.roles.tank and "tank " or "") .. (p.roles and p.roles.healer and "healer " or "") .. (p.roles and p.roles.dps and "dps" or ""),
             #(p.motto or ""), p.looking or "", p.main or "", p.weekdays or "?", p.weekends or "?")
        line("professions: %s", ns.ProfsText(ns.Professions()) ~= "" and ns.ProfsText(ns.Professions()) or "none")
        line("encoded plate: %d bytes, %d message(s)", #ns.Encode(ns.MyPlate()), #ns.Chunks(ns.Encode(ns.MyPlate())))
    else
        line("my plate: none yet")
    end
    local learned, samples = ns.LearnedHours()
    line("learned hours: %d samples%s", samples or 0, learned and (" weekdays=" .. learned.weekdays .. " weekends=" .. learned.weekends) or " (not enough yet)")
    line("chat links: installed=%s  filter=%s  SetItemRef=%s", yn(ns.chatLinksInstalled), yn(ChatFrame_AddMessageEventFilter ~= nil), yn(SetItemRef ~= nil))
    line("plates kept: %d", ns.db and #ns.db.cache or 0)
    for i, entry in ipairs(ns.db and ns.db.cache or {}) do
        if i > 10 then line("  ..."); break end
        line("  %s  level %s %s %s  seen %s", entry.key, tostring(entry.plate.level), entry.plate.race or "", entry.plate.class or "", tostring(entry.seen))
    end
    local c = ns._comm or {}
    local waiting = {}
    for _, p in pairs(c.pending or {}) do waiting[#waiting + 1] = p.name or "?" end
    line("waiting on: %s", #waiting > 0 and table.concat(waiting, ", ") or "nobody")
    line("comm: prefix %s registered=%s  sent=%d  queued=%d  C_ChatInfo=%s  Menu=%s  BackdropTemplate=%s",
         ns.PREFIX, yn(ns.commRegistered), ns.sentCount or 0, #(c.outbox or {}), yn(C_ChatInfo ~= nil), yn(Menu and Menu.ModifyMenu), yn(BackdropTemplateMixin ~= nil))
    local w = ns.window
    line("window: built=%s shown=%s own=%s key=%s model=%s", yn(w), yn(w and w:IsShown()), yn(w and w.own), tostring(w and w.key),
         w and (w.model:IsShown() and "shown" or "hidden (class icon)") or "-")
    local missing = ns.EraArtMissing and ns.EraArtMissing() or {}
    line("era art: %s", #missing == 0 and "all four page files present" or ("missing " .. table.concat(missing, ", ")))
    line("minimap button: %s", ns.minimapButton and (ns.minimapButton:IsShown() and "shown" or "hidden") or "not built")
    line("errors caught: %d", #ns.errors)
    for i, e in ipairs(ns.errors) do
        if i > 20 then line("  ..."); break end
        line("  %s", e)
    end
    return table.concat(lines, "\n")
end

local function BuildReportWindow()
    local f = ns.BuildEraPage("AdventurePlatesReport", UIParent)
    f:SetSize(560, 460)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    if f.SetFrameStrata then f:SetFrameStrata("DIALOG") end
    if f.SetMovable then f:SetMovable(true) end
    if f.EnableMouse then f:EnableMouse(true) end
    if f.RegisterForDrag then f:RegisterForDrag("LeftButton") end
    f:SetScript("OnDragStart", function(self) if self.StartMoving then self:StartMoving() end end)
    f:SetScript("OnDragStop", function(self) if self.StopMovingOrSizing then self:StopMovingOrSizing() end end)
    if UISpecialFrames then table.insert(UISpecialFrames, "AdventurePlatesReport") end
    f.heading = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    f.heading:SetPoint("TOP", f, "TOP", 0, -18)
    f.heading:SetText("Adventure Plates report")
    f.note = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    f.note:SetPoint("TOPLEFT", f, "TOPLEFT", 28, -100)
    f.note:SetWidth(500)
    f.note:SetJustifyH("LEFT")
    f.note:SetTextColor(ns.ERA.brown[1], ns.ERA.brown[2], ns.ERA.brown[3])
    f.note:SetText("Click in the box, Ctrl+A, Ctrl+C, then paste it as a comment on the CurseForge page or email it to " .. ns.FEEDBACK_EMAIL .. ". Ideas are welcome the same way.")
    local ok, scroll = pcall(CreateFrame, "ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    if not ok or not scroll then scroll = CreateFrame("ScrollFrame", nil, f) end
    scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 28, -140)
    scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -52, 100)
    local box = CreateFrame("EditBox", nil, scroll)
    box:SetMultiLine(true)
    box:SetAutoFocus(false)
    if box.SetFontObject then box:SetFontObject("ChatFontSmall") end
    box:SetWidth(470)
    if box.SetTextColor then box:SetTextColor(ns.ERA.ink[1], ns.ERA.ink[2], ns.ERA.ink[3]) end
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEditFocusGained", function(self) if self.HighlightText then self:HighlightText() end end)
    if scroll.SetScrollChild then scroll:SetScrollChild(box) end
    f.box = box
    f.close = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.close:SetSize(100, 24)
    f.close:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -44, 60)
    f.close:SetText("Close")
    f.close:SetScript("OnClick", function() f:Hide() end)
    f.x = ns.EraCloseButton(f, function() f:Hide() end)
    return f
end

function ns.ShowReport()
    if not (CreateFrame and UIParent) then return end
    ns.reportFrame = ns.reportFrame or BuildReportWindow()
    local text = ns.BuildReport()
    ns.lastReport = text
    ns.reportFrame.box:SetText(text)
    ns.reportFrame:Show()
    return ns.reportFrame
end
