-- CrossTalk (Forever) - events and /ct

local addonName, ns = ...

--------------------------------------------------------------------------
-- incoming /say and /yell
--------------------------------------------------------------------------

-- CHAT_MSG_SAY / CHAT_MSG_YELL payload: text, playerName, languageName,
-- channelName, playerName2, specialFlags, zoneChannelID, channelIndex,
-- channelBaseName, languageID, ... Forever may hand text and playerName
-- back secret; languageName and languageID never are.
function ns.OnChat(event, text, playerName, languageName, _, _, _, _, _, _, languageID)
    if ns.Speaks(languageID, languageName) then return end
    text = ns.Plain(text)
    if not text then return end
    local short = ns.ShortName(playerName)
    -- a probe from the player being listened to is read for letters; a
    -- normal message from them (a test phrase) is read back like any other
    if ns.listen and short and short == ns.listen.target then
        if ns.Observe(text, languageID) then return end
    end
    if not ns.db.decode then return end
    local spelled = ns.Despell(text)
    if spelled then
        local who = ns.Plain(playerName) or "?"
        if Ambiguate then
            local ok, s = pcall(Ambiguate, who, "short")
            if ok and type(s) == "string" then who = s end
        end
        ns.Print("%s spelled: |cFFFFFF00%s|r", who, spelled)
    end
end

--------------------------------------------------------------------------
-- slash
--------------------------------------------------------------------------

local function Help()
    ns.Print("v%s - spell out short messages the other faction can read", ns.VERSION)
    ns.Print("  /ct - show or hide the phrase board")
    ns.Print("  /ct <text>  or  /ct say <text> - say it so they can read it;  /ct yell <text>")
    ns.Print("  /ct add <text>, /ct remove <text> - phrases on the board")
    ns.Print("  /ct calibrate - find your letters with a player of the other faction")
    ns.Print("  /ct probe [n] - send the next probe (the Send probe button does the same)")
    ns.Print("  /ct listen [name] - read someone's probes (no name = your target);  /ct stop")
    ns.Print("  /ct import [code] - use a code from the other side;  /ct code - your table as a code")
    ns.Print("  /ct decode on|off - read spelled messages from the other faction in chat")
    ns.Print("  /ct status")
end

local function Status()
    local lang, name = ns.MyLanguage()
    local t = ns.Table(lang)
    ns.Print("you speak %s (language %d), game build %s.", tostring(name or ns.LanguageName(lang)), lang, ns.Build())
    if t then
        ns.Print("letter table: %d letters (%s), word break '%s', found on build %s (%s)%s",
                 t.count or 0, ns.LetterList(t), tostring(ns.Separator(t) or "none"),
                 tostring(t.build), tostring(t.source or "?"),
                 ns.TableCurrent(t) and "" or " |cFFFFAA00- not this build|r")
    else
        ns.Print("no letter table yet: /ct calibrate")
    end
    if ns.listen then ns.Print("listening: %s", ns.ListenSummary():gsub("\n", " / ")) end
end

function ns.HandleSlash(input)
    input = tostring(input or "")
    local cmd, rest = input:match("^%s*(%S*)%s*(.-)%s*$")
    local lower = cmd:lower()
    if lower == "" then
        ns.ToggleBoard()
    elseif lower == "help" then
        Help()
    elseif lower == "say" or lower == "yell" then
        ns.Say(rest, lower:upper())
    elseif lower == "add" then
        ns.AddPhrase(rest)
    elseif lower == "remove" then
        if not ns.RemovePhrase(rest) then ns.Print("no phrase '%s' on the board.", rest) end
    elseif lower == "calibrate" then
        ns.ShowCalibrate()
    elseif lower == "probe" then
        ns.SendProbe(tonumber(rest))
    elseif lower == "listen" then
        if rest ~= "" then ns.StartListening(rest) else ns.ListenToTarget() end
    elseif lower == "stop" then
        ns.StopListening()
        ns.Print("stopped listening.")
    elseif lower == "import" then
        if rest ~= "" then ns.ImportCode(rest) else ns.ShowCodeBox("import") end
    elseif lower == "code" or lower == "export" then
        ns.ShowCodeBox("export")
    elseif lower == "decode" then
        ns.db.decode = rest:lower() ~= "off"
        ns.Print("reading spelled messages: %s.", ns.db.decode and "on" or "off")
    elseif lower == "status" then
        Status()
    else
        -- anything else is a message: /ct rip bozo
        ns.Say(input, "SAY")
    end
end

--------------------------------------------------------------------------
-- bootstrap
--------------------------------------------------------------------------

if CreateFrame then
    local f = CreateFrame("Frame")
    f:RegisterEvent("ADDON_LOADED")
    f:RegisterEvent("PLAYER_LOGIN")
    f:RegisterEvent("CHAT_MSG_SAY")
    f:RegisterEvent("CHAT_MSG_YELL")
    f:SetScript("OnEvent", function(_, event, ...)
        if event == "ADDON_LOADED" then
            if ... == addonName then ns.InitDB() end
        elseif event == "PLAYER_LOGIN" then
            if not ns.db then ns.InitDB() end
            ns.SetupUI()
        elseif ns.db then
            local ok, err = pcall(ns.OnChat, event, ...)
            if not ok then ns.lastError = tostring(err) end
        end
    end)
    ns.eventFrame = f
end

if SlashCmdList then
    SLASH_CROSSTALK1 = "/ct"
    SLASH_CROSSTALK2 = "/crosstalk"
    SlashCmdList["CROSSTALK"] = ns.HandleSlash
end
