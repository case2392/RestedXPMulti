-- Forever Classic UI - the Guild & Communities window
--
-- Era's guild was a tab on the friends window: a parchment panel with the
-- roster inset into it. Forever ships retail's CommunitiesFrame instead -
-- a separate window with a dark metal shell, a filigreed sidebar and a
-- dark page behind the roster. Communities, clubs and the guild finder
-- have no Era original at all, so this is not a rebuild: the window is
-- dressed in Era's furniture, the way the Appearances window is.
--   * retail's shell is faded - the window's own Bg and TopTileStreaks,
--     its nine-slice, portrait and portrait overlay - and so is the dark
--     art inside it, which hangs off frames of its own: the sidebar's Bg,
--     its top and bottom filigree and the bars and corners of its
--     FilligreeOverlay, every inset's nine-slice, and the guild finder's
--     own backdrop and wide background.
--   * an Era panel is drawn behind the lot: the tiling parchment inside
--     Era's gold UI-DialogBox border, which is right at any size. Era's
--     book art is deliberately not used - it is four fixed quarters with
--     the decoration baked in and only works at 384x512.
--   * Forever's own title and close button are left alone: the title is
--     already Era's gold font and the X is the way out of the window.
-- The roster, the tabs, the chat and the finder inside are Blizzard's and
-- stay as they are: only the frame around them changes.
-- Rule as elsewhere: widget calls and hooksecurefunc only, nothing of
-- ours written into Blizzard's tables (M.own holds what hangs on them),
-- and everything we change is remembered so /cui guild off puts it back.

local addonName, ns = ...

local M = {mode = "off"}

local FRAME_NAME = "CommunitiesFrame"
-- the frames inside the window that carry dark modern art of their own.
-- Each is looked for under CommunitiesFrame first and then as a global,
-- because Forever reaches them both ways depending on the tab.
local INNER_FRAMES = {
    "CommunitiesList", "MemberList", "CommunitiesListDropdown",
    "Chat", "ChatTab", "ChatEditBox",
    "GuildFinderFrame", "CommunityFinderFrame",
    "ClubFinderGuildFinderFrame", "ClubFinderCommunityAndGuildFinderFrame",
    "GuildBenefitsFrame", "GuildDetailsFrame", "GuildMemberDetailFrame",
    "ApplicantList", "RecruitmentDialog", "InviteFrame", "NotificationSettingsDialog"
}
-- on any of those frames, these children are pure art
local ART_CHILDREN = {"NineSlice", "FilligreeOverlay", "InsetFrame", "Inset", "DisabledFrame", "PortraitContainer", "PortraitOverlay"}

M.own = setmetatable({}, {__mode = "k"})
local function Own(frame)
    local t = M.own[frame]
    if not t then t = {}; M.own[frame] = t end
    return t
end

local function G(name) return _G[name] end

local function Guard(label, fn)
    return function(...)
        local ok, err = pcall(fn, ...)
        if not ok then ns.errors[#ns.errors + 1] = "guild " .. label .. ": " .. tostring(err) end
    end
end

--------------------------------------------------------------------------
-- remember / restore
--------------------------------------------------------------------------

local function Remember(region)
    if not region then return nil end
    local own = Own(region)
    if own.saved then return own.saved end
    local saved = {}
    if region.GetAlpha then saved.alpha = region:GetAlpha() end
    own.saved = saved
    return saved
end

local function Restore(region)
    local own = M.own[region]
    local saved = own and own.saved
    if not saved then return end
    if saved.alpha and region.SetAlpha then region:SetAlpha(saved.alpha) end
end

local function Fade(region, on)
    if not region or not region.SetAlpha then return end
    if on then
        Remember(region)
        region:SetAlpha(0)
    else
        Restore(region)
    end
end

--------------------------------------------------------------------------
-- finding retail's shell
--------------------------------------------------------------------------

local function TextureRegions(frame)
    local out = {}
    if not frame or type(frame) ~= "table" or not frame.GetRegions then return out end
    local ok, regions = pcall(function() return {frame:GetRegions()} end)
    if not ok then return out end
    for _, region in ipairs(regions) do
        local okType, kind = pcall(function() return region:GetObjectType() end)
        if okType and kind == "Texture" then out[#out + 1] = region end
    end
    return out
end

-- the art layers of a frame that also holds real content: a roster's rows
-- and a finder's cards live on ARTWORK, so only the backdrop layers go
local function BackdropRegions(frame)
    local out = {}
    for _, region in ipairs(TextureRegions(frame)) do
        if region.GetDrawLayer then
            local okLayer, layer = pcall(region.GetDrawLayer, region)
            if okLayer and (layer == "BACKGROUND" or layer == "BORDER") then out[#out + 1] = region end
        end
    end
    return out
end

-- everything a frame keeps its own backdrop in: its background layers, the
-- named art children, and one level under those (an inset's nine-slice)
local function Backdrop(frame, out)
    if type(frame) ~= "table" then return out end
    for _, region in ipairs(BackdropRegions(frame)) do out[#out + 1] = region end
    for _, key in ipairs(ART_CHILDREN) do
        local child = frame[key]
        if type(child) == "table" then
            -- these hold nothing but art, so every layer of them goes
            for _, region in ipairs(TextureRegions(child)) do out[#out + 1] = region end
            for _, inner in ipairs(ART_CHILDREN) do
                local grand = child[inner]
                if type(grand) == "table" then
                    for _, region in ipairs(TextureRegions(grand)) do out[#out + 1] = region end
                end
            end
        end
    end
    return out
end

local function ShellPieces(frame)
    local out = {}
    -- the window itself: Bg, TopTileStreaks, the nine-slice and the portrait
    for _, region in ipairs(TextureRegions(frame)) do
        if region.GetDrawLayer then
            local okLayer, layer = pcall(region.GetDrawLayer, region)
            if okLayer and (layer == "BACKGROUND" or layer == "BORDER" or layer == "OVERLAY") then
                out[#out + 1] = region
            end
        end
    end
    for _, key in ipairs(ART_CHILDREN) do
        local child = frame[key]
        if type(child) == "table" then
            for _, region in ipairs(TextureRegions(child)) do out[#out + 1] = region end
        end
    end
    if frame.portrait then out[#out + 1] = frame.portrait end
    if frame.PortraitFrame then out[#out + 1] = frame.PortraitFrame end
    -- the sidebar, the roster, the chat and the finder each carry their own
    -- dark page, none of it a region of the window
    for _, name in ipairs(INNER_FRAMES) do
        local inner = frame[name]
        if type(inner) ~= "table" then inner = G(name) end
        if type(inner) == "table" and inner.GetRegions then
            Backdrop(inner, out)
            -- the sidebar's own filigree hangs straight off it
            for _, key in ipairs({"Bg", "TopFiligree", "BottomFiligree", "Background", "BackgroundTile"}) do
                local art = inner[key]
                if type(art) == "table" and art.SetAlpha then out[#out + 1] = art end
            end
        end
    end
    return out
end

--------------------------------------------------------------------------
-- our parchment
--------------------------------------------------------------------------

local function BuildPanel(frame)
    local panel = ns.BuildEraPanel("ForeverClassicUIGuildPanel", frame)
    if not panel then return nil end
    panel:SetAllPoints(frame)
    local level = frame.GetFrameLevel and frame:GetFrameLevel() or 1
    panel:SetFrameLevel(math.max(level - 1, 0))
    return panel
end

--------------------------------------------------------------------------
-- applying and undoing
--------------------------------------------------------------------------

local function Shell(frame, on)
    M.faded = 0
    for _, region in ipairs(ShellPieces(frame)) do
        Fade(region, on)
        M.faded = M.faded + 1
    end
end

function M.Apply()
    if M.mode ~= "restyled" then return end
    local frame = G(FRAME_NAME)
    if not frame then return end
    if not M.panel then M.panel = BuildPanel(frame) end
    if not M.panel then return end
    if frame.IsShown and not frame:IsShown() then
        M.panel:Hide()
        return
    end
    Shell(frame, true)
    M.panel:Show()
end

local function ApplyLater()
    M.Apply()
    if C_Timer and C_Timer.After then C_Timer.After(0, Guard("later", M.Apply)) end
end

local function Undo()
    local frame = G(FRAME_NAME)
    if not frame then return end
    Shell(frame, false)
    if M.panel then M.panel:Hide() end
end

local function Hook()
    if M.hooked then return end
    local frame = G(FRAME_NAME)
    if not frame or not hooksecurefunc then return end
    if frame.HookScript then
        frame:HookScript("OnShow", Guard("OnShow", ApplyLater))
        frame:HookScript("OnHide", Guard("OnHide", function() if M.panel then M.panel:Hide() end end))
    end
    -- the tabs swap whole pages in and out, and each page brings its own
    -- dark art with it, so ours runs again after every switch
    for _, name in ipairs({"SetDisplayMode", "SelectClub", "OnClubSelected", "UpdateClubSelection"}) do
        if type(frame[name]) == "function" then
            hooksecurefunc(frame, name, Guard(name, ApplyLater))
        end
    end
    if type(PanelTemplates_SetTab) == "function" then
        hooksecurefunc("PanelTemplates_SetTab", Guard("PanelTemplates_SetTab", function(f)
            if f == G(FRAME_NAME) then ApplyLater() end
        end))
    end
    if not M.events and CreateFrame then
        local ev = CreateFrame("Frame")
        for _, e in ipairs({"GUILD_ROSTER_UPDATE", "PLAYER_GUILD_UPDATE", "CLUB_SELECTED", "PLAYER_ENTERING_WORLD"}) do
            pcall(ev.RegisterEvent, ev, e)
        end
        ev:SetScript("OnEvent", Guard("event", function()
            local f = G(FRAME_NAME)
            if f and f.IsShown and f:IsShown() then ApplyLater() end
        end))
        M.events = ev
    end
    M.hooked = true
end

--------------------------------------------------------------------------
-- module interface
--------------------------------------------------------------------------

local function WatchForFrame()
    if M.watcher or not CreateFrame then return end
    local watcher = CreateFrame("Frame")
    watcher:RegisterEvent("ADDON_LOADED")
    pcall(watcher.RegisterEvent, watcher, "PLAYER_ENTERING_WORLD")
    watcher:SetScript("OnEvent", function()
        if M.mode ~= "waiting" then return end
        if G(FRAME_NAME) then
            if ns.SafeCall("guild", M.Enable, M) and M.mode == "restyled" then
                watcher:UnregisterAllEvents()
            end
        end
    end)
    M.watcher = watcher
end

function M:Enable()
    if not G(FRAME_NAME) then
        self.mode = "waiting"
        WatchForFrame()
        return
    end
    self.missingArt = ns.EraPanelArtMissing and ns.EraPanelArtMissing() or {}
    self.mode = "restyled"
    Hook()
    M.Apply()
end

function M:Force()
    if self.mode == "restyled" then M.Apply() end
end

function M:Disable()
    local was = self.mode
    self.mode = "off"
    if was == "restyled" then Undo() end
end

function M:Status()
    if self.mode == "restyled" then
        local s = ("Era panel on Forever's Guild & Communities window, %d retail pieces faded"):format(self.faded or 0)
        if self.missingArt and #self.missingArt > 0 then
            s = s .. " (art missing: " .. table.concat(self.missingArt, ", ") .. ")"
        end
        return s .. " (Era's guild was a tab on the friends window, so this is Era furniture, not a copy)"
    elseif self.mode == "waiting" then
        return "waiting for Forever's guild window (CommunitiesFrame) to exist"
    end
    return "off"
end

ns.RegisterModule("guild", M)
