-- VuloForeverUI / Modules / CooldownManager / Glow
--
-- The three ways an icon can light up, and the one rule they all obey.
--
-- A glow is never SHOWN or HIDDEN on a condition -- "is the spell ready" and
-- "does the aura have three stacks" are secret in combat and a boolean test on
-- a secret throws. So every glow is BUILT ONCE and ANIMATES FOREVER, and the
-- only thing that ever changes is its alpha, set through ns.AlphaFromBool,
-- which lets the engine pick the number from a boolean we never look at.
-- A glow at alpha zero costs an animation nobody sees; that is the price of
-- not asking.
--
-- Each icon carries two slots, because a proc and a ready state can be true at
-- the same time and one must not overwrite the other:
--   "main"   ready, stacks, the active phase
--   "proc"   the client's own spell-lit-up event
local _, ns = ...
local CM = ns.CM

local Glow = {}
CM.Glow = Glow

local ANTS  = "Interface\\SpellActivationOverlay\\IconAlert"
local STAR  = "Interface\\Cooldown\\star4"
local WHITE = CM.WHITE

-- ---------------------------------------------------------------- builders --

-- A thin frame around the icon whose four edges breathe. The cheapest of the
-- three and the only one that keeps the icon's own shape readable.
local function buildPixel(button)
    local f = CreateFrame("Frame", nil, button)
    f:SetPoint("TOPLEFT", button, "TOPLEFT", -2, 2)
    f:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 2, -2)
    f:SetFrameLevel((button:GetFrameLevel() or 1) + 4)
    f.textures = {}
    for _, side in ipairs({ "top", "bot", "lft", "rgt" }) do
        local t = f:CreateTexture(nil, "OVERLAY")
        t:SetTexture(WHITE)
        f.textures[side] = t
    end
    local th = 2
    local t, b, l, r = f.textures.top, f.textures.bot, f.textures.lft, f.textures.rgt
    t:SetPoint("TOPLEFT"); t:SetPoint("TOPRIGHT"); t:SetHeight(th)
    b:SetPoint("BOTTOMLEFT"); b:SetPoint("BOTTOMRIGHT"); b:SetHeight(th)
    l:SetPoint("TOPLEFT"); l:SetPoint("BOTTOMLEFT"); l:SetWidth(th)
    r:SetPoint("TOPRIGHT"); r:SetPoint("BOTTOMRIGHT"); r:SetWidth(th)

    -- The pulse is on the FRAME, so the four edges stay in step. The alpha
    -- fold below rides on top of it: an animation scales what it is given.
    local ag = f:CreateAnimationGroup()
    ag:SetLooping("BOUNCE")
    local a = ag:CreateAnimation("Alpha")
    a:SetFromAlpha(1)
    a:SetToAlpha(0.35)
    a:SetDuration(0.6)
    f.anim = ag
    return f
end

-- A star that turns, the shape the client uses for its own pet-cast marker.
local function buildShine(button)
    local f = CreateFrame("Frame", nil, button)
    f:SetPoint("TOPLEFT", button, "TOPLEFT", -6, 6)
    f:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 6, -6)
    f:SetFrameLevel((button:GetFrameLevel() or 1) + 4)
    local t = f:CreateTexture(nil, "OVERLAY")
    t:SetAllPoints(f)
    t:SetTexture(STAR)
    t:SetBlendMode("ADD")
    f.textures = { star = t }

    local ag = f:CreateAnimationGroup()
    ag:SetLooping("REPEAT")
    local rot = ag:CreateAnimation("Rotation")
    rot:SetDegrees(360)
    rot:SetDuration(3)
    f.anim = ag
    return f
end

-- The client's own "this spell just lit up" art: the ring plus the ants that
-- crawl around it. Two textures, one pulse, no atlas -- the atlas names differ
-- between builds and a missing atlas draws nothing at all.
local function buildProc(button)
    local f = CreateFrame("Frame", nil, button)
    f:SetPoint("TOPLEFT", button, "TOPLEFT", -5, 5)
    f:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 5, -5)
    f:SetFrameLevel((button:GetFrameLevel() or 1) + 5)
    local ring = f:CreateTexture(nil, "OVERLAY")
    ring:SetAllPoints(f)
    ring:SetTexture(ANTS)
    ring:SetTexCoord(0.00781250, 0.50781250, 0.27734375, 0.52734375)
    ring:SetBlendMode("ADD")
    local ants = f:CreateTexture(nil, "OVERLAY", nil, 1)
    ants:SetAllPoints(f)
    ants:SetTexture(ANTS)
    ants:SetTexCoord(0.00781250, 0.50781250, 0.53515625, 0.78515625)
    ants:SetBlendMode("ADD")
    f.textures = { ring = ring, ants = ants }

    local ag = f:CreateAnimationGroup()
    ag:SetLooping("BOUNCE")
    local a = ag:CreateAnimation("Alpha")
    a:SetFromAlpha(1)
    a:SetToAlpha(0.45)
    a:SetDuration(0.5)
    f.anim = ag
    return f
end

local BUILD = { pixel = buildPixel, shine = buildShine, proc = buildProc }

Glow.TYPES = { "none", "pixel", "shine", "proc" }

-- ---------------------------------------------------------------- use --

local function widget(icon, slot, kind)
    icon.glows = icon.glows or {}
    local key = slot .. ":" .. kind
    local w = icon.glows[key]
    if w then return w end
    local build = BUILD[kind]
    if not build then return nil end
    w = build(icon.button)
    icon.glows[key] = w
    return w
end

-- Set one slot. `state` may be a plain boolean or a secret one; either way the
-- alpha is the only thing that moves. Every other widget in the slot is taken
-- to zero, so switching the glow type leaves nothing of the old one behind.
function Glow.Set(icon, slot, kind, color, state, strength)
    icon.glows = icon.glows or {}
    for key, w in pairs(icon.glows) do
        if key:sub(1, #slot + 1) == slot .. ":" and key ~= slot .. ":" .. tostring(kind) then
            for _, t in pairs(w.textures) do t:SetAlpha(0) end
            if w.anim and w.anim:IsPlaying() then w.anim:Stop() end
        end
    end
    if kind == nil or kind == "none" then return end
    local w = widget(icon, slot, kind)
    if not w then return end
    if w.anim and not w.anim:IsPlaying() then w.anim:Play() end
    local r, g, b = 1, 1, 1
    if color then r, g, b = color.r or 1, color.g or 1, color.b or 1 end
    for _, t in pairs(w.textures) do
        t:SetVertexColor(r, g, b)
        ns.AlphaFromBool(t, state, strength or 0.9, 0)
    end
end

-- Take a slot down for good, for an icon that has left the bar.
function Glow.Clear(icon, slot)
    if not icon.glows then return end
    for key, w in pairs(icon.glows) do
        if slot == nil or key:sub(1, #slot + 1) == slot .. ":" then
            for _, t in pairs(w.textures) do t:SetAlpha(0) end
            if w.anim and w.anim:IsPlaying() then w.anim:Stop() end
        end
    end
end
