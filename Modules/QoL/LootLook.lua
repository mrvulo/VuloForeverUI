-- VuloForeverUI / Modules / QoL / LootLook
--
-- The loot window in the look of the game's other windows. The client brings
-- the flat, modern list from its retail side for it; every other window of
-- this client wears the metal frame with the round portrait. This gives the
-- loot window the same: frame, portrait circle, title, stone ground, and a
-- name plate behind every row, the way loot looked before the flat list.
--
-- WHAT IS OURS AND WHAT STAYS THE CLIENT'S
--
-- The client's window keeps doing everything: its place (Edit Mode), its
-- rows, clicks, tooltips, rolls, its fade in and out. Only paint changes.
--   * the frame is a frame of OUR OWN behind the client's window, built from
--     the client's own portrait-frame template, so it is drawn by the same
--     art as the character window. It reaches TOP pixels above the window:
--     the portrait and the title sit there, over nothing of the list.
--   * the client's flat ground, border, title and per-row cards are faded to
--     alpha 0 -- never hidden (a Hide on a client frame runs its OnHide in our
--     taint, concepts.md), never written into.
--   * nothing of ours is stored on a client frame: the per-row textures live
--     in a weak table keyed by the row.
-- The rows come from a pool the client refills on every open; the client's
-- own "row initialised" callback restyles each one after the client has
-- painted it (the registry calls us secure-wrapped, so no taint flows back).
local _, ns = ...

local QoL = ns.QoL
local Look = QoL.RegisterPart("lootLook", {})
QoL.LootLook = Look

local TOP = 38               -- frame height above the client's window
local PLATE = "Interface\\QuestFrame\\UI-QuestItemNameFrame"
local BAG_ICON = "Interface\\Icons\\INV_Misc_Bag_10"
local FISH_ICON = "Interface\\Icons\\Trade_Fishing"

-- the client's pieces that make up the flat look, per window and per row
local FRAME_PARTS = { "Bg", "NineSlice", "TitleContainer" }
local ROW_PARTS = { "NameFrame", "BorderFrame", "HighlightNameFrame", "PushedNameFrame",
    "QualityStripe", "QualityText" }

local deco                   -- our frame
local on = false             -- live switch read by every hook
local hooked = false
local closeAnchor            -- the client close button's own anchor
local alphaWas = setmetatable({}, { __mode = "k" })   -- region -> its own alpha
local rowArt = setmetatable({}, { __mode = "k" })     -- row -> { plate, glow }

local function lootFrame() return _G.LootFrame end

-- Faded, or given its own alpha back. The client's highlight is 0.7 by its
-- template, so the first alpha seen is the one restored.
local function fade(region, hide)
    if not (region and region.SetAlpha) then return end
    if hide then
        if alphaWas[region] == nil then alphaWas[region] = region:GetAlpha() end
        region:SetAlpha(0)
    elseif alphaWas[region] ~= nil then
        region:SetAlpha(alphaWas[region])
    end
end

-- ------------------------------------------------------------------ rows --

local function styleRow(row)
    if not (row and row.Item) then return end   -- the empty base row
    for _, key in ipairs(ROW_PARTS) do fade(row[key], on) end
    local art = rowArt[row]
    if not art then
        if not on then return end
        local plate = row:CreateTexture(nil, "BACKGROUND")
        plate:SetTexture(PLATE)
        plate:SetPoint("LEFT", row.Item, "RIGHT", -10, 0)
        plate:SetPoint("RIGHT", row, "RIGHT", 6, 0)
        plate:SetHeight(64)
        local glow = row:CreateTexture(nil, "ARTWORK")
        glow:SetTexture(PLATE)
        glow:SetBlendMode("ADD")
        glow:SetAllPoints(plate)
        glow:SetAlpha(0)
        art = { plate = plate, glow = glow }
        rowArt[row] = art
        -- HookScript keeps the client's own enter/leave; the glow only answers
        row.Item:HookScript("OnEnter", function() if on then glow:SetAlpha(0.35) end end)
        row.Item:HookScript("OnLeave", function() glow:SetAlpha(0) end)
    end
    art.plate:SetShown(on)
    art.glow:SetAlpha(0)
end

local function styleRows()
    local f = lootFrame()
    if not (f and f.ScrollBox and f.ScrollBox.ForEachFrame) then return end
    f.ScrollBox:ForEachFrame(function(row) styleRow(row) end)
end

-- ---------------------------------------------------------------- portrait --

local function deadTarget()
    if not UnitExists("target") then return false end
    local dead = UnitIsDead("target")
    return ns.CanRead(dead) and dead == true
end

local function paintPortrait()
    if not deco then return end
    if IsFishingLoot and IsFishingLoot() then
        deco:SetPortraitToAsset(FISH_ICON)
    elseif deadTarget() then
        deco:SetPortraitToUnit("target")
    else
        deco:SetPortraitToAsset(BAG_ICON)
    end
end

-- ------------------------------------------------------------------ frame --

local function build(f)
    local ok, frame = pcall(CreateFrame, "Frame", nil, f, "PortraitFrameTemplateNoCloseButton")
    if not ok or not frame then return end
    deco = frame
    deco:SetPoint("TOPLEFT", f, "TOPLEFT", 0, TOP)
    deco:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    -- under the client's list and close button; catches the clicks above it
    deco:SetFrameLevel(f:GetFrameLevel())
    deco:EnableMouse(true)
    if deco.SetTitle then deco:SetTitle(_G.ITEMS or "") end
    deco:SetPortraitToAsset(BAG_ICON)
end

local function hook(f)
    if hooked then return end
    hooked = true
    if f.ScrollBox and ScrollUtil and ScrollUtil.AddInitializedFrameCallback then
        -- a table as owner: the registry hands it in as the first argument
        ScrollUtil.AddInitializedFrameCallback(f.ScrollBox, function(_, row)
            if on or rowArt[row] then styleRow(row) end
        end, Look)
    end
end

local function paintFrame(f)
    for _, key in ipairs(FRAME_PARTS) do fade(f[key], on) end
    local sb = f.ScrollBox
    if sb then
        if sb.GetUpperShadowTexture then fade(sb:GetUpperShadowTexture(), on) end
        if sb.GetLowerShadowTexture then fade(sb:GetLowerShadowTexture(), on) end
    end

    -- the close button moves up with the frame's top edge
    local close = f.ClosePanelButton
    if close then
        if not closeAnchor then closeAnchor = { close:GetPoint(1) } end
        close:ClearAllPoints()
        if on then
            close:SetPoint("TOPRIGHT", deco, "TOPRIGHT", 0, 3)
            close:SetFrameLevel(f:GetFrameLevel() + 10)
        else
            local p, rel, rp, x, y = unpack(closeAnchor)
            close:SetPoint(p or "TOPRIGHT", rel or f, rp or "TOPRIGHT", x or 0, y or 3)
        end
    end
    -- the screen edge holds the frame, not only the window under it
    f:SetClampRectInsets(0, 0, on and TOP or 0, 0)
    deco:SetShown(on)
end

function Look.Apply()
    local want = QoL.db().lootClassic and true or false
    local f = lootFrame()
    if not f then return end
    if not want and not deco then return end   -- never switched on: touch nothing
    if want and not deco then build(f) end
    if not deco then return end
    on = want
    hook(f)
    paintFrame(f)
    styleRows()
    QoL.SyncEvent(on, "LOOT_OPENED", paintPortrait)
    if on and f:IsShown() then paintPortrait() end
end

function Look.Disable()
    if not deco then return end
    on = false
    local f = lootFrame()
    if f then paintFrame(f); styleRows() end
    ns:UnregisterEvent("LOOT_OPENED", paintPortrait)
end
