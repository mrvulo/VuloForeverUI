-- VuloForeverUI / Modules / Skins / Core
--
-- Window skins: the client's character and inspect windows in one of two
-- looks, with marks on every equipment slot.
--
--   Standard  the client's own frame, the slots rounded and ringed in the
--             colour of their item's quality
--   Modern    flat dark panels with a thin edge -- title bar, the level line,
--             model ground, stat pane, tabs -- and the same rounded slots
--
--   Core.lua       module, settings, the shared pieces: art fading, panels,
--                  the slot ring and the slot texts
--   Character.lua  the character window
--   Stats.lua      the stat pane: section look, sections that fold
--   Inspect.lua    the inspect window (a load-on-demand addon of the client)
--   Options.lua    the options page
--
-- TAINT (docs/concepts.md, engine rules): nothing here hides, reparents or
-- moves a client frame. Client art is faded with SetAlpha(0) and remembered,
-- so switching back to Standard or turning the module off gives every piece
-- its own alpha back. Our panels and texts live on frames of our own. No
-- field is written on a client frame; per-frame state sits in weak tables.
-- None of these windows is protected, so all of it works in a fight too.
local _, ns = ...
local L = ns.L

local Skins = {}
ns.Skins = Skins

local mod = ns:RegisterModule("skins", {
    name        = "Skins",
    group       = "Unit Frames",
    description = "The character and inspect windows in the client's look or a flat Modern look, with rounded quality rings, item levels, enchants and durability on the slots.",
    defaults = {
        enabled = true,
        windows = {
            style        = "standard",   -- "standard" | "modern"
            character    = true,
            inspect      = true,
            itemLevel    = true,
            enchants     = true,
            durability   = true,
            statSections = true,
            collapsed    = {},           -- [section title] = true
        },
    },
})
Skins.mod = mod

function Skins.db() return mod.db.windows end

function Skins.Modern()
    return mod.active and Skins.db().style == "modern"
end

-- ---------------------------------------------------------------- art --

local faded = setmetatable({}, { __mode = "k" })   -- region -> its own alpha

-- Fade a piece of client art, once; Restore gives it back.
function Skins.Fade(region)
    if not region or not region.SetAlpha then return end
    if faded[region] == nil then faded[region] = region:GetAlpha() or 1 end
    region:SetAlpha(0)
end

function Skins.FadeRegions(frame)
    if not frame then return end
    for _, r in ipairs({ frame:GetRegions() }) do Skins.Fade(r) end
end

function Skins.RestoreAll()
    for region, a in pairs(faded) do region:SetAlpha(a) end
    wipe(faded)
end

-- ---------------------------------------------------------------- panels --

local BG     = { 0.055, 0.055, 0.065, 0.97 }
local STRIP  = { 0.09, 0.09, 0.105, 1 }
local EDGE   = { 0.22, 0.22, 0.26, 1 }
Skins.BG, Skins.STRIP, Skins.EDGE = BG, STRIP, EDGE

-- A flat panel with a one-pixel edge, ours, laid over `host` at its level.
-- `inset` grows (+) or shrinks (-) it on every side. `parent`: when the host
-- itself gets faded, the panel must hang elsewhere or it fades with it.
function Skins.Panel(host, color, inset, parent)
    local p = CreateFrame("Frame", nil, parent or host, "BackdropTemplate")
    inset = inset or 0
    p:SetPoint("TOPLEFT", host, "TOPLEFT", -inset, inset)
    p:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", inset, -inset)
    p:SetFrameLevel(math.max(0, host:GetFrameLevel()))
    p:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    local c = color or BG
    p:SetBackdropColor(c[1], c[2], c[3], c[4])
    p:SetBackdropBorderColor(EDGE[1], EDGE[2], EDGE[3], EDGE[4])
    p:EnableMouse(false)
    p:Hide()
    return p
end

-- A window's ground: textures on the window ITSELF, in its lowest layer, so
-- every child (model, slots, stats) stays above it whatever its level. A
-- panel frame of ours at the window's level could end up over a child that
-- shares that level.
function Skins.Ground(frame, color)
    local g = { parts = {} }
    local c = color or BG
    local bg = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetAllPoints(frame)
    bg:SetColorTexture(c[1], c[2], c[3], c[4])
    g.parts[1] = bg
    local px = 1
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local t = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
        t:SetColorTexture(EDGE[1], EDGE[2], EDGE[3], EDGE[4])
        if side == "TOP" or side == "BOTTOM" then
            t:SetPoint(side .. "LEFT", frame, side .. "LEFT", 0, 0)
            t:SetPoint(side .. "RIGHT", frame, side .. "RIGHT", 0, 0)
            t:SetHeight(px)
        else
            t:SetPoint("TOP" .. side, frame, "TOP" .. side, 0, 0)
            t:SetPoint("BOTTOM" .. side, frame, "BOTTOM" .. side, 0, 0)
            t:SetWidth(px)
        end
        g.parts[#g.parts + 1] = t
    end
    function g:SetShown(on)
        for _, t in ipairs(self.parts) do t:SetShown(on) end
    end
    g:SetShown(false)
    return g
end

-- ---------------------------------------------------------------- slots --
--
-- Every equipment slot gets: a round mask on the client's icon (the square
-- slot art faded), our ring in the colour of the item's quality, and three
-- texts -- item level, durability, enchant -- on a frame of ours above it.

local MASK = "Interface\\AddOns\\VuloForeverUI\\Media\\Masks\\csquare_mask.tga"
local RING = "Interface\\AddOns\\VuloForeverUI\\Media\\Masks\\csquare_ring.tga"
local MARGIN = 10 / 108            -- the files leave 10 of 128 px empty per side
local EMPTY = { 0.32, 0.32, 0.36 }

local deco = setmetatable({}, { __mode = "k" })    -- client slot button -> ours

local function grow(t, anchor)
    local e = (anchor:GetWidth() or 37) * MARGIN
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", anchor, "TOPLEFT", -e, e)
    t:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", e, -e)
end

-- side: "left" (text to the right), "right" (text to the left), "bottom"
-- (text above the slot)
local function decorate(button, side)
    local d = deco[button]
    if d then return d end
    d = { side = side }
    d.mask = button:CreateMaskTexture()
    d.mask:SetTexture(MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    d.over = CreateFrame("Frame", nil, button)
    d.over:SetAllPoints(button)
    d.over:SetFrameLevel(button:GetFrameLevel() + 3)
    d.over:EnableMouse(false)
    d.ring = d.over:CreateTexture(nil, "OVERLAY")
    d.ring:SetTexture(RING)
    d.level = d.over:CreateFontString(nil, "OVERLAY")
    d.level:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 2)
    d.dura = d.over:CreateFontString(nil, "OVERLAY")
    d.dura:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -2)
    d.enchant = d.over:CreateFontString(nil, "OVERLAY")
    d.enchant:SetWordWrap(false)
    d.enchant:SetTextColor(0.35, 0.95, 0.35)
    if side == "left" then
        d.enchant:SetPoint("LEFT", button, "RIGHT", 6, 0)
        d.enchant:SetJustifyH("LEFT")
    elseif side == "right" then
        d.enchant:SetPoint("RIGHT", button, "LEFT", -6, 0)
        d.enchant:SetJustifyH("RIGHT")
    else
        d.enchant:SetPoint("BOTTOM", button, "TOP", 0, 3)
        d.enchant:SetJustifyH("CENTER")
    end
    d.enchant:SetWidth(side == "bottom" and 90 or 110)
    deco[button] = d
    return d
end

local function setRound(button, d, on)
    local regions = { button.icon or button.Icon,
        button.GetHighlightTexture and button:GetHighlightTexture(),
        button.GetPushedTexture and button:GetPushedTexture() }
    if d.round ~= on then
        local fn = on and "AddMaskTexture" or "RemoveMaskTexture"
        for _, r in ipairs(regions) do
            if r and r[fn] then pcall(r[fn], r, d.mask) end
        end
        d.round = on
    end
    grow(d.mask, button)
    grow(d.ring, button)
end

-- The square art the client draws round a slot.
local function slotArt(button)
    local out = { button.IconBorder, button.GetNormalTexture and button:GetNormalTexture() }
    if button.BorderFrame then
        for _, r in ipairs({ button.BorderFrame:GetRegions() }) do out[#out + 1] = r end
    end
    return out
end

local function fontFor(fs, size)
    ns.UI.FontFor("skins", fs, size, "OUTLINE")
end

-- info: { quality, level, dura (0..1 or nil), enchant (string or nil) }
-- or nil for an empty slot. Called after the client has drawn the slot.
function Skins.PaintSlot(button, side, info)
    local d = decorate(button, side)
    if not mod.active then
        if d.round then setRound(button, d, false) end
        d.over:Hide()
        return
    end
    local db = Skins.db()
    setRound(button, d, true)
    for _, r in ipairs(slotArt(button)) do Skins.Fade(r) end
    d.over:Show()

    local q = info and info.quality
    local r, g, b = EMPTY[1], EMPTY[2], EMPTY[3]
    if type(q) == "number" and q >= 0 then
        local qr, qg, qb = C_Item.GetItemQualityColor(q)
        if qr then r, g, b = qr, qg, qb end
    end
    d.ring:SetVertexColor(r, g, b, 1)

    fontFor(d.level, 11)
    if db.itemLevel and info and info.level and info.level > 1 then
        d.level:SetText(info.level)
        d.level:SetTextColor(r, g, b)
        d.level:Show()
    else
        d.level:Hide()
    end

    fontFor(d.dura, 9)
    local du = info and info.dura
    if db.durability and du then
        d.dura:SetText(("%d%%"):format(math.floor(du * 100 + 0.5)))
        if du < 0.2 then d.dura:SetTextColor(1, 0.25, 0.25)
        elseif du < 0.5 then d.dura:SetTextColor(1, 0.82, 0)
        else d.dura:SetTextColor(0.85, 0.85, 0.85) end
        d.dura:Show()
    else
        d.dura:Hide()
    end

    fontFor(d.enchant, 10)
    if db.enchants and info and info.enchant then
        d.enchant:SetText(info.enchant)
        d.enchant:Show()
    else
        d.enchant:Hide()
    end
end

-- ---------------------------------------------------------------- data --

-- "Enchanted: %s" in the client's language, as a pattern for the tooltip line.
local enchantPattern
local function stripEnchanted(text)
    if not enchantPattern then
        local fmt = _G.ENCHANTED_TOOLTIP_LINE or "Enchanted: %s"
        enchantPattern = "^" .. fmt:gsub("([%%%(%)%.%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%%%s", "(.+)") .. "$"
    end
    return text:match(enchantPattern) or text
end

-- The permanent enchant line of a tooltip, or nil.
function Skins.EnchantFrom(data)
    if type(data) ~= "table" or not ns.CanRead(data) or type(data.lines) ~= "table" then return nil end
    local want = Enum.TooltipDataLineType and Enum.TooltipDataLineType.ItemEnchantmentPermanent
    for _, line in ipairs(data.lines) do
        if line.type == want and type(line.leftText) == "string" and ns.CanRead(line.leftText) then
            return stripEnchanted(line.leftText)
        end
    end
end

-- ---------------------------------------------------------------- lifecycle --

Skins.parts = {}       -- Character, Stats, Inspect register { Apply = fn }

-- Everything faded comes back first; each part then fades again what the
-- current settings want gone. A switch to Standard or off is just that.
function Skins.Apply()
    Skins.RestoreAll()
    for _, part in ipairs(Skins.parts) do
        if part.Apply then part.Apply() end
    end
end

function mod:OnEnable()
    for _, part in ipairs(Skins.parts) do
        if part.Enable then part.Enable(self) end
    end
    Skins.Apply()
end

function mod:OnDisable()
    Skins.Apply()
end

mod.Refresh = function() Skins.Apply() end
