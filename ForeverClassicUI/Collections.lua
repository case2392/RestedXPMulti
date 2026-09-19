-- Forever Classic UI - the Appearances (collections) window
--
-- There is no Era original to copy here: transmog did not exist in 1.15,
-- so the Appearances window is one of Forever's own. It is treated the
-- way the Currency and Statistics tabs were - not rebuilt, but dressed in
-- Era's furniture so it sits with the rest of the UI:
--   * retail's nine-slice shell, portrait and flat backdrop are faded,
--     along with the dark page inside it (the wardrobe's own Bg, tiled
--     background, corner shadows and inner nine-slice, which hang off a
--     frame of their own), and the spellbook's parchment - the same four
--     pieces the professions book uses, stretched to the window's size -
--     is drawn in their place;
--   * Forever's own title and close button are left alone: the title is
--     already Era's gold font over the top edge, and the X is the only
--     way out of the window.
-- The lists, the model, the tabs and the filters inside are Blizzard's
-- and are left alone: only the frame around them changes.
-- Rule as elsewhere: widget calls and hooksecurefunc only, nothing of
-- ours written into Blizzard's tables (M.own holds what hangs on them),
-- and everything we change is remembered so /cui collections off puts it
-- back.

local addonName, ns = ...

local M = {mode = "off"}

local SB = "Interface\\Spellbook\\"
local ART = {
    topLeft = SB .. "UI-SpellbookPanel-TopLeft",
    topRight = SB .. "UI-SpellbookPanel-TopRight",
    bottomLeft = SB .. "UI-SpellbookPanel-BotLeft",
    bottomRight = SB .. "UI-SpellbookPanel-BotRight",
}
M.ART = ART

local FRAME_NAME = "CollectionsJournal"
-- the parchment is a 384x512 book: a 256 left page and a 128 right one,
-- 256 top and 256 bottom. Those fractions hold at any window size.
local ART_LEFT, ART_TOP = 256 / 384, 256 / 512
-- the frames inside the window whose own art is a dark modern page; each
-- one is tried under CollectionsJournal and as a global
local PAGE_FRAMES = {"WardrobeCollectionFrame", "PetJournal", "MountJournal", "ToyBox", "HeirloomsJournal", "WardrobeFrame"}

M.own = setmetatable({}, {__mode = "k"})
local function Own(frame)
    local t = M.own[frame]
    if not t then t = {}; M.own[frame] = t end
    return t
end

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
        if not ok then ns.errors[#ns.errors + 1] = "collections " .. label .. ": " .. tostring(err) end
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
-- retail's shell: the nine-slice, the portrait, the flat backdrop
--------------------------------------------------------------------------

local function TextureRegions(frame)
    local out = {}
    if not frame or not frame.GetRegions then return out end
    local ok, regions = pcall(function() return {frame:GetRegions()} end)
    if not ok then return out end
    for _, region in ipairs(regions) do
        local okType, kind = pcall(function() return region:GetObjectType() end)
        if okType and kind == "Texture" then out[#out + 1] = region end
    end
    return out
end

local function ShellPieces(frame)
    local out = {}
    for _, region in ipairs(TextureRegions(frame)) do
        if region.GetDrawLayer then
            local okLayer, layer = pcall(region.GetDrawLayer, region)
            if okLayer and (layer == "BACKGROUND" or layer == "BORDER" or layer == "OVERLAY") then
                out[#out + 1] = region
            end
        end
    end
    -- the nine-slice and the portrait are frames of their own
    for _, key in ipairs({"NineSlice", "PortraitContainer"}) do
        local child = frame[key]
        if child then
            for _, region in ipairs(TextureRegions(child)) do out[#out + 1] = region end
        end
    end
    if frame.portrait then out[#out + 1] = frame.portrait end
    if frame.PortraitFrame then out[#out + 1] = frame.PortraitFrame end
    -- the dark page inside: the open journal's activeFrame carries its own
    -- background, tiled fill, corner shadows and inner nine-slice, none of
    -- which are regions of the window itself
    for _, name in ipairs(PAGE_FRAMES) do
        local journal = frame[name] or G(name)
        local page = type(journal) == "table" and journal.activeFrame
        if type(page) == "table" then
            for _, region in ipairs(TextureRegions(page)) do out[#out + 1] = region end
            if page.NineSlice then
                for _, region in ipairs(TextureRegions(page.NineSlice)) do out[#out + 1] = region end
            end
        end
    end
    return out
end

--------------------------------------------------------------------------
-- our parchment
--------------------------------------------------------------------------

local function BuildBook(frame)
    local book = CreateFrame("Frame", "ForeverClassicUICollectionsBook", frame)
    book:SetAllPoints(frame)
    local level = frame.GetFrameLevel and frame:GetFrameLevel() or 1
    book:SetFrameLevel(math.max(level - 1, 0))
    local function Piece(path, point)
        local t = book:CreateTexture(nil, "BACKGROUND")
        t:SetTexture(path)
        t:SetPoint(point, book, point, 0, 0)
        return t
    end
    book.topLeft = Piece(ART.topLeft, "TOPLEFT")
    book.topRight = Piece(ART.topRight, "TOPRIGHT")
    book.bottomLeft = Piece(ART.bottomLeft, "BOTTOMLEFT")
    book.bottomRight = Piece(ART.bottomRight, "BOTTOMRIGHT")

    book:Hide()
    return book
end

local function SizeBook(book, frame)
    if not book or not frame or not frame.GetSize then return end
    local ok, w, h = pcall(frame.GetSize, frame)
    if not ok or not w or w <= 0 or h <= 0 then return end
    local lw, rw = math.floor(w * ART_LEFT + 0.5), math.ceil(w * (1 - ART_LEFT))
    local th, bh = math.floor(h * ART_TOP + 0.5), math.ceil(h * (1 - ART_TOP))
    book.topLeft:SetSize(lw, th)
    book.topRight:SetSize(rw, th)
    book.bottomLeft:SetSize(lw, bh)
    book.bottomRight:SetSize(rw, bh)
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
    if not M.book then M.book = BuildBook(frame) end
    if frame.IsShown and not frame:IsShown() then
        M.book:Hide()
        return
    end
    Shell(frame, true)
    SizeBook(M.book, frame)
    M.book:Show()
end

local function ApplyLater()
    M.Apply()
    if C_Timer and C_Timer.After then C_Timer.After(0, Guard("later", M.Apply)) end
end

local function Undo()
    local frame = G(FRAME_NAME)
    if not frame then return end
    Shell(frame, false)
    if M.book then M.book:Hide() end
end

local function Hook()
    if M.hooked then return end
    local frame = G(FRAME_NAME)
    if not frame or not hooksecurefunc then return end
    if frame.HookScript then
        frame:HookScript("OnShow", Guard("OnShow", ApplyLater))
        frame:HookScript("OnHide", Guard("OnHide", function() if M.book then M.book:Hide() end end))
        frame:HookScript("OnSizeChanged", Guard("OnSizeChanged", function()
            if M.mode == "restyled" and M.book then SizeBook(M.book, G(FRAME_NAME)) end
        end))
    end
    if type(CollectionsJournal_SetTab) == "function" then
        hooksecurefunc("CollectionsJournal_SetTab", Guard("SetTab", ApplyLater))
    end
    if type(PanelTemplates_SetTab) == "function" then
        hooksecurefunc("PanelTemplates_SetTab", Guard("PanelTemplates_SetTab", function(f)
            if f == G(FRAME_NAME) then ApplyLater() end
        end))
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
            if ns.SafeCall("collections", M.Enable, M) and M.mode == "restyled" then
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
    self.missingArt = {}
    for _, key in ipairs({"topLeft", "topRight", "bottomLeft", "bottomRight"}) do
        if not HasFile(ART[key]) then self.missingArt[#self.missingArt + 1] = ART[key]:match("[^\\]+$") end
    end
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
        local s = ("Era parchment on Forever's Appearances window, %d retail pieces faded"):format(self.faded or 0)
        if self.missingArt and #self.missingArt > 0 then
            s = s .. " (art missing: " .. table.concat(self.missingArt, ", ") .. ")"
        end
        s = s .. " (Era had no transmog window, so this is Era furniture, not a copy)"
        return s
    elseif self.mode == "waiting" then
        return "waiting for Forever's Appearances window (CollectionsJournal) to exist"
    end
    return "off"
end

ns.RegisterModule("collections", M)
