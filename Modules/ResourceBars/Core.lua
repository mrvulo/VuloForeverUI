-- VuloForeverUI / Modules / ResourceBars / Core
--
-- Free-standing bars for the three things that tell you when to press what:
-- your power, your cast, and your swing. One module, three tabs, and every bar
-- its own frame with its own mover -- none of this hangs off a unit frame, so
-- it works whether or not our unit frames are switched on.
--
-- WHAT MAY BE READ HERE, AND WHAT MAY NOT
--
-- Measured on this client: the player's own power and health are SECRET even
-- out of combat, while the MAX values stay readable. So not one of the three
-- displays reads a number:
--
--   fill        SetMinMaxValues + SetValue take secret numbers as they are
--               (ns:SetPowerFill), and the widget does the arithmetic
--   colour      UnitPowerPercent(unit, type, true, colourCurve) hands the
--               secret percent to a curve the ENGINE evaluates and returns a
--               Color -- the percent itself never reaches us. That is the only
--               way a threshold colour is possible at all
--   text        SetFormattedText("%d", secret) is allowed; formatting is
--   cast/swing  a duration OBJECT into StatusBar:SetTimerDuration, after which
--               the client runs the fill frame by frame without us
--
-- The one thing we decide is the layout, and that is plain data.
local _, ns = ...
local L = ns.L

local RB = {}
ns.RB = RB

RB.WHITE = "Interface\\Buttons\\WHITE8X8"

-- Every bar in this module shares one shape, so a setting means the same thing
-- on all of them and the options can reuse one set of widgets.
RB.BAR_DEFAULTS = {
    enabled     = true,
    width       = 220,
    height      = 18,
    texture     = "Matte",
    fillColor   = { r = 0.20, g = 0.45, b = 0.95 },
    useTypeColor = true,           -- power bars: the client's colour per power
    bgColor     = { r = 0.05, g = 0.05, b = 0.06, a = 0.85 },
    borderSize  = 1,
    borderColor = { r = 0, g = 0, b = 0, a = 1 },
    showSpark   = true,
    -- Text. Two corners and a middle, each with its own job, because a bar
    -- that shows everything shows nothing.
    fontSize    = 11,
    textColor   = { r = 1, g = 1, b = 1 },
    leftText    = "none",          -- none | name | label
    rightText   = "value",         -- none | value | percent | valuemax | time
    -- Ticks. Plain numbers in a string ("20,40,60"), so nothing secret is
    -- involved in drawing them.
    ticks       = "",
    tickPercent = true,
    tickColor   = { r = 0, g = 0, b = 0, a = 0.6 },
    tickWidth   = 1,
    -- Visibility, the same four words the other modules use.
    visibility  = "always",        -- always | combat | noncombat | hidden
    opacity     = 1,
    oocFade     = false,
    oocAlpha    = 0.45,
    -- Position, in the shape the house mover expects.
    x           = 0,
    y           = -140,
    scale       = 1,
}

-- What each bar is, and where it differs from the shape above. The key is also
-- the mover key and the options row, so it never changes once shipped.
RB.BARS = {
    { key = "power",  tab = "resources", label = "Power",
      defaults = { y = -150, width = 240, height = 20, rightText = "value" } },
    { key = "mana",   tab = "resources", label = "Additional power",
      defaults = { y = -174, width = 240, height = 12, rightText = "percent",
                   useTypeColor = false, fillColor = { r = 0.20, g = 0.40, b = 0.90 } } },
    { key = "cast",   tab = "cast", label = "Cast bar",
      defaults = { y = -210, width = 260, height = 22, useTypeColor = false,
                   fillColor = { r = 0.95, g = 0.76, b = 0.25 },
                   leftText = "name", rightText = "time" } },
    { key = "swingMain", tab = "swing", label = "Main hand",
      defaults = { y = -250, width = 240, height = 12, useTypeColor = false,
                   fillColor = { r = 0.85, g = 0.65, b = 0.20 },
                   leftText = "label", rightText = "time" } },
    { key = "swingOff", tab = "swing", label = "Off hand",
      defaults = { y = -266, width = 240, height = 12, useTypeColor = false,
                   fillColor = { r = 0.70, g = 0.50, b = 0.20 },
                   leftText = "label", rightText = "time" } },
    { key = "swingRanged", tab = "swing", label = "Ranged",
      defaults = { y = -282, width = 240, height = 12, useTypeColor = false,
                   fillColor = { r = 0.55, g = 0.75, b = 0.40 },
                   leftText = "label", rightText = "time" } },
}

-- Settings that belong to one kind of bar only. They live in the same table as
-- everything else; this list exists so the options know what to offer.
RB.EXTRA_DEFAULTS = {
    power = {
        -- No "hide while full": full is a COMPARISON on a secret value, and a
        -- setting this client cannot honour has no business in the options.
        thresholdPct   = 0,        -- 0 is off
        thresholdColor = { r = 0.95, g = 0.35, b = 0.25 },
    },
    mana = {
        onlyInForms    = true,     -- only while the primary power is not mana
    },
    cast = {
        -- Which cast bar the player actually wants:
        --   standard  the client's own bar, untouched
        --   classic   the client's own bar, dressed back to the 1.x shape
        --   modern    our own bar, and the client's hidden
        -- The first two are the client's frame, so everything our own bar can
        -- do to itself does not apply to them -- what they get instead is the
        -- pair below, an icon and a cast time placed by hand.
        castStyle      = "standard",
        hideBorder     = false,     -- standard/classic: the client's frame around the bar
        attachIcon     = false,
        attachIconSize = 20,
        attachIconX    = -6,
        attachIconY    = 0,
        attachTime     = false,
        attachTimeSize = 12,
        attachTimeX    = 6,
        attachTimeY    = 0,
        showIcon       = true,
        iconSide       = "LEFT",
        hideBlizzard   = true,
        channelColor   = { r = 0.35, g = 0.75, b = 0.95 },
        uninterruptibleColor = { r = 0.6, g = 0.6, b = 0.6 },
        showShield     = true,
    },
    swingMain   = { showRange = true, outOfRangeColor = { r = 0.8, g = 0.25, b = 0.25 } },
    swingOff    = { showRange = true, outOfRangeColor = { r = 0.8, g = 0.25, b = 0.25 } },
    swingRanged = { showRange = true, outOfRangeColor = { r = 0.8, g = 0.25, b = 0.25 } },
}

local mod = ns:RegisterModule("resourcebars", {
    name        = "Resource Bars",
    group       = "HUD",
    description = "Free-standing bars for your power, your cast and your swing timer, each with its own place on the screen.",
    defaults = {
        -- Off out of the box, like the cooldown bars: a second set of bars is
        -- a choice, and the settings page previews them without switching the
        -- module on.
        enabled = false,
        bars = {},
    },
})
RB.mod = mod

function RB.db() return mod.db end

-- Raised when BAR_DEFAULTS or EXTRA_DEFAULTS grow a key, so a bar saved by an
-- older build is filled again rather than reaching the paint pass with a hole
-- in it.
RB.DEFAULTS_VERSION = 2

local function presetFor(key)
    for _, def in ipairs(RB.BARS) do
        if def.key == key then return def end
    end
    return nil
end
RB.Preset = presetFor

-- One bar's settings, created on demand and kept filled. Every read of a bar
-- table in this module goes through here.
function RB.Bar(key)
    local db = RB.db()
    if not db then return nil end
    local preset = presetFor(key)
    if not preset then return nil end
    if type(db.bars) ~= "table" then db.bars = {} end

    local bar = db.bars[key]
    if type(bar) ~= "table" then bar = {}; db.bars[key] = bar end
    if bar._filled ~= RB.DEFAULTS_VERSION then
        ns:ApplyDefaults(bar, preset.defaults or {})
        ns:ApplyDefaults(bar, RB.BAR_DEFAULTS)
        ns:ApplyDefaults(bar, RB.EXTRA_DEFAULTS[key] or {})
        bar._filled = RB.DEFAULTS_VERSION
    end
    return bar
end

function RB.Each(fn)
    for _, def in ipairs(RB.BARS) do
        local bar = RB.Bar(def.key)
        if bar then fn(def.key, bar, def) end
    end
end

-- ---------------------------------------------------------------- refresh --

function RB.StyleAll()
    RB.Each(function(key) RB.StyleBar(key) end)
end

function RB.UpdateAll()
    RB.Power.Update()
    -- Refresh, never Update: asking the client again whether a cast is running
    -- can bring a cast that has just ended back as a non-nil secret tuple, and
    -- the bar would sit there full with the last spell's name on it. Only a
    -- cast EVENT may start this bar.
    RB.Cast.Refresh()
    RB.Swing.UpdateAll()
    RB.Each(function(key) RB.UpdateVisibility(key) end)
end

-- ---------------------------------------------------------------- lifecycle --

local function buildAll()
    RB.Each(function(key) RB.BuildBar(key) end)
    RB.StyleAll()
    RB.Power.Rescan()
    RB.Cast.Apply()
    RB.UpdateAll()
end

function mod:OnEnable()
    self:RegisterEvent("PLAYER_ENTERING_WORLD", function()
        buildAll()
    end)

    -- Power. UNIT_DISPLAYPOWER is the one that matters on a druid: the primary
    -- power type itself changes, and with it the colour and the max.
    local function powerEvent(_, unit)
        if unit and unit ~= "player" then return end
        RB.Power.Update()
    end
    self:RegisterEvent("UNIT_POWER_UPDATE", powerEvent)
    self:RegisterEvent("UNIT_POWER_FREQUENT", powerEvent)
    self:RegisterEvent("UNIT_MAXPOWER", powerEvent)
    self:RegisterEvent("UNIT_DISPLAYPOWER", function(_, unit)
        if unit and unit ~= "player" then return end
        RB.Power.Rescan()
    end)

    RB.Cast.RegisterEvents(self)
    RB.Swing.RegisterEvents(self)

    self:RegisterEvent("PLAYER_REGEN_DISABLED", function() RB.Each(function(key) RB.UpdateVisibility(key) end) end)
    self:RegisterEvent("PLAYER_REGEN_ENABLED", function() RB.Each(function(key) RB.UpdateVisibility(key) end) end)

    if not RB.profileHooked then
        RB.profileHooked = true
        hooksecurefunc(ns, "LoadProfile", function()
            if not mod.active then return end
            RB.StyleAll()
            RB.UpdateAll()
        end)
    end

    if RB.HookPreview then RB.HookPreview() end

    -- Edit Mode. A mover box is a CHILD of the frame it moves, so a hidden bar
    -- hides its own box: the cast bar and the three swing bars, which are only
    -- on screen while something runs, would be unplaceable. Opening Edit Mode
    -- has to re-ask every bar whether it should be visible, and the answer
    -- there is always yes.
    if not RB.editHooked then
        RB.editHooked = true
        ns:RegisterEditModeHook(function()
            if not mod.active then return end
            RB.Each(function(key) RB.BuildBar(key) end)
            RB.Each(function(key) RB.UpdateVisibility(key) end)
        end)
    end
    if IsLoggedIn() then buildAll() end

    ns:RegisterSlash({ key = "RESOURCEBARS", commands = { "/vfbars" },
        desc = "Open the resource bar settings.",
    })
end

ns.Slash.RESOURCEBARS = function()
    local f = ns.UI:CreateMainFrame()
    f:Show()
    ns.UI:PopulateSidebar()
    ns.UI:ShowModulePage("resourcebars")
end

function mod:OnDisable()
    RB.Cast.Release()
    -- the client's cast bar frame gets its border back
    if RB.CastSkin and RB.CastSkin.ApplyBorder then RB.CastSkin.ApplyBorder() end
    for _, frame in pairs(RB.frames or {}) do frame:Hide() end
end

-- The label of a bar, for the mover box and the options. Built lazily: a
-- locale key read at file scope would bake the client language.
function RB.Label(key)
    local labels = {
        power       = L["Power"],
        mana        = L["Additional power"],
        cast        = L["Cast bar"],
        swingMain   = L["Main hand"],
        swingOff    = L["Off hand"],
        swingRanged = L["Ranged"],
    }
    return labels[key] or key
end
