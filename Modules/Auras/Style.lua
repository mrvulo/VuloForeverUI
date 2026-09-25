-- VuloForeverUI / Modules / Auras / Style
--
-- How one engine-made aura button looks.
--
-- The engine creates its own buttons and hands each one to us ONCE, in the
-- initialiser below. That callback is the only moment a button may be touched:
-- afterwards it belongs to the engine, and while auras are secret our writes
-- to it are refused. So everything -- regions, fonts, the formatter, the dispel
-- strips -- happens here, and a settings change REBUILDS the containers rather
-- than reaching into live buttons.
--
-- Not one aura is read. The duration text comes out of a formatter the client
-- runs against a time we never see, and the dispel colour is the engine's
-- decision against a dispel type we never see either.
local _, ns = ...
ns.Auras = ns.Auras or {}
local A = ns.Auras

local Style = {}
A.Style = Style

-- Every engine call is wrapped: a refusal must cost us that one feature, not
-- the whole batch of buttons the engine is building.
local function register(button, method, ...)
    local f = button[method]
    if not f then return false end
    return (pcall(f, button, ...))
end

local ANCHORS = {
    TOPLEFT     = { "TOPLEFT",      1, -1 },
    TOP         = { "TOP",          0, -1 },
    TOPRIGHT    = { "TOPRIGHT",    -1, -1 },
    LEFT        = { "LEFT",         1,  0 },
    CENTER      = { "CENTER",       0,  0 },
    RIGHT       = { "RIGHT",       -1,  0 },
    BOTTOMLEFT  = { "BOTTOMLEFT",   1,  1 },
    BOTTOM      = { "BOTTOM",       0,  1 },
    BOTTOMRIGHT = { "BOTTOMRIGHT", -1,  1 },
}
Style.ANCHORS = ANCHORS

local function placeText(fs, point, x, y, button)
    local a = ANCHORS[point] or ANCHORS.CENTER
    fs:ClearAllPoints()
    fs:SetPoint(a[1], button, a[1], a[2] + x, a[3] + y)
end

-- ---------------------------------------------------------------------------
-- The dispel palette.
--
-- A debuff's dispel type is aura data, so it is secret and we never ask for it.
-- Instead the engine is handed textures plus a colour PER TYPE NAME, and it
-- decides in C which button gets which colour, and whether it gets one at all
-- (an untyped debuff gets none).
-- ---------------------------------------------------------------------------
local DISPEL_KEYS = {
    { token = "Magic",   key = "dispelMagic" },
    { token = "Curse",   key = "dispelCurse" },
    { token = "Disease", key = "dispelDisease" },
    { token = "Poison",  key = "dispelPoison" },
    { token = "Bleed",   key = "dispelBleed" },
}
Style.DISPEL_KEYS = DISPEL_KEYS

local function dispelColorMap(db)
    if not CreateColor then return nil end
    local map = {}
    for _, d in ipairs(DISPEL_KEYS) do
        local c = db[d.key]
        if c then map[d.token] = CreateColor(c.r, c.g, c.b, 1) end
    end
    return map
end

-- PreserveAsset means "keep the texture I gave you and only tint it"; the
-- legacy build calls the same thing Color on another enum.
local function dispelStyle()
    return Enum.CustomAuraButtonDispelTypeTextureStyle.PreserveAsset
end

-- FOUR SOLID STRIPS, not one ring-shaped texture: the engine applies the
-- options, the visibility and the tint per REGISTERED TEXTURE, so a four-piece
-- ring is as legal as a one-piece one -- and a cropped band goes sub-texel at
-- large icon sizes, where it fades to alpha < 1 and lets the static border
-- bleed through the tint. Solid strips never sample.
local function addDispelStrips(button, db)
    local add = button.AddDispelTypeTexture
    local st  = dispelStyle()
    local map = dispelColorMap(db)
    if not (add and st ~= nil and map) then return end
    local strips = ns.MakeEdges(button, "OVERLAY")
    if not strips then return end
    ns.LayoutEdges(strips, button, db.dispelBorderSize, 1, 1, 1, 1)
    -- HIDDEN until the engine shows them. A texture is shown by default and
    -- LayoutEdges shows it white; if a registration below is refused, an
    -- unhidden set would sit on the icon as a plain white ring for the rest of
    -- the session.
    for _, t in pairs(strips) do t:Hide() end

    local opts = {
        style            = st,
        showWhenHarmful  = true,
        showWhenHelpful  = false,
        customDispelColorMap = map,
    }
    for _, t in pairs(strips) do
        if not pcall(add, button, t, opts) then
            -- All or nothing: a half-registered ring is worse than none, so
            -- the engine is told to forget the set and the strips stay hidden.
            if button.ClearDispelTypeTextures then
                pcall(button.ClearDispelTypeTextures, button)
            end
            return
        end
    end
end

-- ---------------------------------------------------------------------------
-- The initialiser. `kind` is "buffs" or "debuffs"; `db` is the module's whole
-- settings table, read HERE and only here, because the container carries the
-- callback and a changed setting means a new container.
-- ---------------------------------------------------------------------------
function Style.Initializer(kind, db)
    local buffs = (kind == "buffs")

    return function(button)
        -- EVERY setting is read here, at the moment the engine hands us the
        -- button -- never captured when the container was built. The engine
        -- creates its buttons in batches, so a later batch would otherwise
        -- come out half in the old style and half in the new one.
        local size   = db.iconSize
        local zoom   = (buffs and db.buffZoom or db.debuffZoom) / 100
        local bSize  = buffs and db.buffBorderSize or db.debuffBorderSize
        local bColor = buffs and db.buffBorderColor or db.debuffBorderColor
        local wantDispel = (not buffs) and db.dispelColors

        -- The AuraButton intrinsic carries no size of its own, and the flow
        -- layout only ANCHORS its elements -- layout.elementWidth feeds the
        -- spacing arithmetic and never reaches the frame. Without this the
        -- button stays 0x0 and nothing is ever visible, while every call
        -- involved reports success.
        button:SetSize(size, size)

        local icon = button:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints(button)
        icon:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)

        -- The swipe: "reverse" (the default -- the dark part is the time
        -- already gone), "normal" (the dark part is the time left) or "none".
        -- The engine still drives the cooldown either way; "none" only stops
        -- the swipe from being drawn, the duration text is untouched.
        local swipe = db.swipeStyle or "reverse"
        local cd = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
        cd:SetAllPoints(button)
        cd:SetReverse(swipe == "reverse")
        cd:SetDrawSwipe(swipe ~= "none")
        cd:SetDrawEdge(false)
        cd:SetHideCountdownNumbers(true)

        if bSize > 0 then
            local edges = ns.MakeEdges(button, "OVERLAY")
            ns.LayoutEdges(edges, button, bSize, bColor.r, bColor.g, bColor.b, 1)
        end
        -- after the static border, so the tinted ring draws over it
        if wantDispel then addDispelStrips(button, db) end

        local font = ns.ModuleFontPath("auras")

        -- Fonts BEFORE the engine is told about the strings: an unstyled
        -- FontString has no font assigned and the engine errors on it.
        local stacks = button:CreateFontString(nil, "OVERLAY")
        stacks:SetFont(font, db.stackSize, "OUTLINE")
        placeText(stacks, db.stackPosition, db.stackX, db.stackY, button)

        local duration = button:CreateFontString(nil, "OVERLAY")
        duration:SetFont(font, db.durationSize, "OUTLINE")
        placeText(duration, db.durationPosition, db.durationX, db.durationY, button)

        register(button, "SetIcon", icon)
        register(button, "SetDurationCooldown", cd)
        if db.showStacks then register(button, "SetApplicationCount", stacks, {}) end

        if db.showDuration then
            local f = ns.AuraDurationFormatter()
            if not (f and register(button, "SetDurationText", duration, { textFormatter = f })) then
                -- no formatter on this client: better the client's wording
                -- than none at all
                register(button, "SetDurationText", duration, {})
            end
        end

        -- Clicks off, hover on. The engine shows the aura's tooltip from its
        -- own OnEnter (Blizzard_AuraButton.lua:80), in and out of combat, so
        -- mouse motion is all it needs; a click still falls through to the
        -- world. Both calls are refused on a restricted button, and this
        -- callback is the one moment when it is not restricted yet.
        pcall(button.SetMouseClickEnabled, button, false)
        pcall(button.SetMouseMotionEnabled, button, true)
    end
end
