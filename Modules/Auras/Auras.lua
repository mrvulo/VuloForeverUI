-- VuloForeverUI / Modules / Auras
--
-- Your own buffs and debuffs. Two things live here:
--
--   * our own rows (Bars.lua + Style.lua), built on the client's aura widget,
--     which is the only way to show auras from addon code while they are
--     secret -- the engine filters, sorts and lays them out, we own the look;
--   * the short wording under Blizzard's own rows ("58m" instead of "58 Min."),
--     for anyone who keeps them.
--
-- The two are mutually exclusive in practice: with our rows on, Blizzard's are
-- silenced and there is nothing left to shorten.
local _, ns = ...
local L = ns.L
local A = ns.Auras

local mod = ns:RegisterModule("auras", {
    name        = "Auras",
    group       = "HUD",
    description = "Your own buffs and debuffs: own rows placed with the editor, or shorter times under the client's.",
    optionsGrid = true,
    defaults = {
        -- OFF by default. This module takes the client's own buff and debuff
        -- rows away and puts ours in their place, which is too big a change to
        -- make for someone who never asked for it. The switch in the sidebar
        -- turns it on.
        enabled = false,
        ownBars = true,
        -- Applies to the client's own rows; with ours on there are none left.
        shortDurations = true,

        iconSize = 32,
        growthX  = "left",     -- from the top-right corner inward, like the client's own row
        growthY  = "down",

        perRowBuffs    = 11, rowsBuffs   = 3, maxBuffs   = 32, paddingBuffs   = 5,
        perRowDebuffs  = 8,  rowsDebuffs = 2, maxDebuffs = 16, paddingDebuffs = 5,

        -- Per cent of the icon cut off on every side; the client's icons carry
        -- a border in the art that a small crop takes away.
        buffZoom   = 6,
        debuffZoom = 6,
        buffBorderSize    = 1,
        debuffBorderSize  = 1,
        buffBorderColor   = { r = 0, g = 0, b = 0 },
        debuffBorderColor = { r = 0, g = 0, b = 0 },

        showDuration     = true,
        durationPosition = "CENTER",
        durationSize     = 11,
        durationX        = 0,
        durationY        = 0,
        showStacks       = true,
        stackPosition    = "BOTTOMRIGHT",
        stackSize        = 11,
        stackX           = 0,
        stackY           = 0,

        -- The client decides which debuff is of which type and whether it has
        -- one at all; these are only the colours it paints with.
        dispelColors     = true,
        dispelBorderSize = 2,
        dispelMagic      = { r = 0.349, g = 0.475, b = 1.000 },
        dispelCurse      = { r = 0.636, g = 0.000, b = 0.640 },
        dispelDisease    = { r = 0.671, g = 0.384, b = 0.098 },
        dispelPoison     = { r = 0.000, g = 0.706, b = 0.286 },
        dispelBleed      = { r = 0.750, g = 0.150, b = 0.150 },

        buffs   = { x = 0, y = -20,  scale = 1 },
        debuffs = { x = 0, y = -120, scale = 1 },
    },
})

-- ---------------------------------------------------------------------- --
-- Short durations under the client's own rows
-- ---------------------------------------------------------------------- --

-- The client's own rule, kept as it is so only the spelling changes
-- (Blizzard_SharedXML/TimeUtil.lua:463 SecondsToTimeAbbrev, threshold 1.5):
-- a unit takes over once the time reaches one and a half of it, rounded up.
local MIN, HOUR, DAY = 60, 3600, 86400
local THRESHOLD = 1.5

local function short(seconds)
    if seconds >= DAY * THRESHOLD then return "%dd", math.ceil(seconds / DAY) end
    if seconds >= HOUR * THRESHOLD then return "%dh", math.ceil(seconds / HOUR) end
    if seconds >= MIN * THRESHOLD then return "%dm", math.ceil(seconds / MIN) end
    return "%ds", seconds
end

-- Runs after Blizzard_BuffFrame/BuffFrame.lua:1355 AuraButtonMixin:UpdateDuration,
-- which has just written its own text. In combat the time left is a secret
-- value: no comparison and no arithmetic, so Blizzard's text stays as it is
-- there. (A curve cannot help either -- Curve:Evaluate takes secrets only from
-- untainted code.)
local function afterUpdateDuration(self, timeLeft)
    if not mod.active or not mod.db.shortDurations or self.isExample then return end
    -- Secret check first: even "== nil" is a comparison, and that throws.
    if not ns.CanRead(timeLeft) or type(timeLeft) ~= "number" then return end
    local duration = self.Duration
    if not duration then return end
    duration:SetFormattedText(short(timeLeft))
end

-- The buttons are created once, in AuraFrame_OnLoad (BuffFrame.lua:191), and
-- carry their own copy of the mixin method, so each one is hooked by itself.
-- A secure hook cannot be taken back; the flags above are what switch it off,
-- and Blizzard rewrites the text on the very next frame.
local hooked = setmetatable({}, { __mode = "k" })

local function hookFrame(auraFrame)
    if not (auraFrame and auraFrame.auraFrames) then return end
    for _, button in ipairs(auraFrame.auraFrames) do
        -- private aura anchors sit in the same list and have no duration text
        if not hooked[button] and type(button.UpdateDuration) == "function" then
            hooked[button] = true
            hooksecurefunc(button, "UpdateDuration", afterUpdateDuration)
        end
    end
end

-- ---------------------------------------------------------------------- --
-- Lifecycle
-- ---------------------------------------------------------------------- --

ns.OnLocaleReady(function()
StaticPopupDialogs["VFUI_AURAS_RELOAD"] = {
    text = L["The client's own buff rows come back after a reload. Reload the UI now?"],
    button1 = L["Reload now"],
    button2 = L["Later"],
    OnAccept = function() ReloadUI() end,
    timeout = 0, whileDead = 1, hideOnEscape = 1, preferredIndex = 3,
}
end)

-- The one place that decides what the player sees. `fresh` throws the
-- containers away first; without it the rows are only put back if they are not
-- standing already, because a rebuild costs real frames (see rebuild below).
local function apply(fresh)
    if not mod.active then return end
    A.WhenSafe(function()
        if not mod.active then return end
        if mod.db.ownBars then
            if fresh then A.Teardown() elseif A.IsBuilt() then
                A.SilenceBlizzard(true)
                return
            end
            if A.Build(mod) then
                A.SilenceBlizzard(true)
            else
                -- The widget is not there, or the client refused it. Better
                -- the client's own rows than none at all.
                mod.db.ownBars = false
                A.Hide()
                ns:Print(L["This client will not build aura rows for an addon; the game's own rows stay."])
                if ns.UI and ns.UI.BuildOptionsPage then ns.UI:BuildOptionsPage("auras") end
            end
        else
            A.Hide()
            -- Un-silencing only takes the keep-hidden hook off; the frames
            -- lost their events and get them back at the next load.
            if A.BlizzardSilenced() then
                A.SilenceBlizzard(false)
                StaticPopup_Show("VFUI_AURAS_RELOAD")
            end
        end
    end)
end

function mod:OnEnable()
    hookFrame(_G.BuffFrame)
    hookFrame(_G.DebuffFrame)
    -- Wrapped, not passed straight in: the dispatcher hands the handler
    -- (event, ...), and the event name would arrive as `fresh` and tear the
    -- rows down at every loading screen.
    self:RegisterEvent("PLAYER_ENTERING_WORLD", function() apply() end)
    if IsLoggedIn and IsLoggedIn() then apply() end
end

function mod:OnDisable()
    A.Hide()
    if A.BlizzardSilenced() then
        A.SilenceBlizzard(false)
        StaticPopup_Show("VFUI_AURAS_RELOAD")
    end
end

-- ---------------------------------------------------------------------- --
-- Options
-- ---------------------------------------------------------------------- --

-- A button can only be styled while the engine is creating it, so new styling
-- means new buttons -- and the engine gives none of the old ones back (it
-- deliberately exposes no way to remove a group). Every rebuild therefore
-- costs real frames, which is why a slider drag, which fires its setter on
-- every step, is collapsed into a single rebuild at the end.
local rebuildQueued

local function refresh()
    if rebuildQueued then return end
    rebuildQueued = true
    C_Timer.After(0.35, function()
        rebuildQueued = false
        apply(true)
    end)
end

local function num(key, label, min, max, step, tooltip)
    return { type = "slider", label = label, tooltip = tooltip,
        min = min, max = max, step = step,
        get = function() return mod.db[key] end,
        set = function(_, v) mod.db[key] = v; refresh() end }
end

local function flag(key, label, tooltip, rebuild)
    return { type = "toggle", label = label, tooltip = tooltip,
        get = function() return mod.db[key] end,
        set = function(_, v)
            mod.db[key] = v
            refresh()
            if rebuild and ns.UI and ns.UI.BuildOptionsPage then
                ns.UI:BuildOptionsPage("auras")
            end
        end }
end

local function color(key, label)
    return { type = "color", label = label,
        get = function() return mod.db[key] end,
        set = function(r, g, b)
            local c = mod.db[key]
            c.r, c.g, c.b = r, g, b
            refresh()
        end }
end

local function choice(key, label, values)
    return { type = "dropdown", label = label, values = values, width = 200,
        get = function() return mod.db[key] end,
        set = function(_, v) mod.db[key] = v; refresh() end }
end

function mod:GetOptions()
    local points = {
        { value = "TOPLEFT",     text = L["Top left"] },
        { value = "TOP",         text = L["Top"] },
        { value = "TOPRIGHT",    text = L["Top right"] },
        { value = "LEFT",        text = L["Left"] },
        { value = "CENTER",      text = L["Centre"] },
        { value = "RIGHT",       text = L["Right"] },
        { value = "BOTTOMLEFT",  text = L["Bottom left"] },
        { value = "BOTTOM",      text = L["Bottom"] },
        { value = "BOTTOMRIGHT", text = L["Bottom right"] },
    }
    local acrossValues = {
        { value = "right", text = L["To the right"] },
        { value = "left",  text = L["To the left"] },
    }
    local downValues = {
        { value = "down", text = L["Downwards"] },
        { value = "up",   text = L["Upwards"] },
    }

    local items = {
        { type = "group", layout = "row", gap = 10, align = "center", items = {
            { type = "button", label = L["Open Edit Mode"], width = 200, primary = true,
              onClick = function() ns:SetEditMode(true) end },
        } },
        flag("ownBars", L["Use our own aura rows"],
             L["Replaces the client's buff and debuff rows with ours. Leaving this off again needs a reload before the client's come back."], true),
    }

    if not mod.db.ownBars then
        items[#items + 1] = { type = "desc", text = L["|cffaaaaaaThe client's own rows are showing. Only the wording of the times below applies to them.|r"] }
        items[#items + 1] = { type = "section", title = L["The client's rows"], items = {
            flag("shortDurations", L["Short times"],
                 L["Writes the time under your buffs and debuffs with one letter: 58m, 2h, 4s. In combat the game hides these times from addons, so its own wording is shown there."]),
        } }
        return items
    end

    items[#items + 1] = { type = "desc", text = L["|cffaaaaaaTwo rows of your own, placed with /vedit. The client still decides which aura is shown and in what order -- in combat that is the only way an addon may show auras at all.|r"] }

    items[#items + 1] = { type = "section", title = L["Icons"], items = {
        num("iconSize", L["Icon size"], 12, 64, 1),
        choice("growthX", L["Icons run"], acrossValues),
        choice("growthY", L["Further rows go"], downValues),
        num("buffZoom", L["Buff icon crop"], 0, 20, 1,
            L["Per cent cut off each side of the icon art. A small crop takes away the border the client's icons carry."]),
        num("debuffZoom", L["Debuff icon crop"], 0, 20, 1),
    } }

    items[#items + 1] = { type = "section", title = L["Buffs"], items = {
        num("perRowBuffs", L["Icons per row"], 1, 20, 1),
        num("rowsBuffs", L["Rows"], 1, 6, 1),
        num("maxBuffs", L["Most icons"], 1, 40, 1),
        num("paddingBuffs", L["Spacing"], 0, 20, 1),
        num("buffBorderSize", L["Border thickness"], 0, 4, 1),
        color("buffBorderColor", L["Border color"]),
    } }

    local debuffRows = {
        num("perRowDebuffs", L["Icons per row"], 1, 20, 1),
        num("rowsDebuffs", L["Rows"], 1, 6, 1),
        num("maxDebuffs", L["Most icons"], 1, 40, 1),
        num("paddingDebuffs", L["Spacing"], 0, 20, 1),
        num("debuffBorderSize", L["Border thickness"], 0, 4, 1),
        color("debuffBorderColor", L["Border color"]),
        flag("dispelColors", L["Color by dispel type"],
             L["The client tints the border of a debuff it knows a dispel type for. Which debuff that is stays its decision -- the type is never read here."], true),
    }
    if mod.db.dispelColors then
        debuffRows[#debuffRows + 1] = num("dispelBorderSize", L["Dispel border thickness"], 1, 6, 1)
        debuffRows[#debuffRows + 1] = color("dispelMagic", L["Magic"])
        debuffRows[#debuffRows + 1] = color("dispelCurse", L["Curse"])
        debuffRows[#debuffRows + 1] = color("dispelDisease", L["Disease"])
        debuffRows[#debuffRows + 1] = color("dispelPoison", L["Poison"])
        debuffRows[#debuffRows + 1] = color("dispelBleed", L["Bleed"])
    end
    items[#items + 1] = { type = "section", title = L["Debuffs"], items = debuffRows }

    local textRows = {
        flag("showDuration", L["Show the time left"], nil, true),
    }
    if mod.db.showDuration then
        textRows[#textRows + 1] = choice("durationPosition", L["Time position"], points)
        textRows[#textRows + 1] = num("durationSize", L["Time size"], 6, 24, 1)
        textRows[#textRows + 1] = num("durationX", L["Time horizontal offset"], -30, 30, 1)
        textRows[#textRows + 1] = num("durationY", L["Time vertical offset"], -30, 30, 1)
    end
    textRows[#textRows + 1] = flag("showStacks", L["Show the stack count"], nil, true)
    if mod.db.showStacks then
        textRows[#textRows + 1] = choice("stackPosition", L["Stack position"], points)
        textRows[#textRows + 1] = num("stackSize", L["Stack size"], 6, 24, 1)
        textRows[#textRows + 1] = num("stackX", L["Stack horizontal offset"], -30, 30, 1)
        textRows[#textRows + 1] = num("stackY", L["Stack vertical offset"], -30, 30, 1)
    end
    items[#items + 1] = { type = "section", title = L["Text"], items = textRows }

    return items
end
