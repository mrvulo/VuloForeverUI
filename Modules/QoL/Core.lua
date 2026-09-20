-- VuloForeverUI / Modules / QoL / Core
--
-- The small conveniences, in one module with four tabs:
--
--   vendor   selling the greys, repairing, and a warning before the gear is gone
--   loot     looting a corpse in one click, opening what can be opened,
--            typing DELETE for you
--   stats    the secondary stats, drawn from values the client keeps secret
--   display  frame rate, latency, map coordinates, a combat line, a crosshair
--
-- WHY THIS MODULE IS SPLIT THE WAY IT IS
--
-- Every part here talks to a different piece of the client, and two of them
-- touch values this client will not let an addon read:
--
--   * the secondary stats are SECRET in restricted content -- they are never
--     compared, added or formatted in Lua, only handed to SetFormattedText as
--     arguments (Stats.lua carries the full reasoning)
--   * everything the vendor and the container code does is plain item data,
--     which stays readable, but it is RATE LIMITED by the server: the sweeps
--     re-count and retry rather than assuming one call did the job
--
-- Nothing in this module needs the combat log, and nothing decides on a secret.
local _, ns = ...
local L = ns.L

local QoL = {}
ns.QoL = QoL

-- Parts register themselves here at load; Core turns them on and off in one
-- place, so adding a fifth feature never means editing OnEnable.
QoL.parts = {}
QoL.partOrder = {}

function QoL.RegisterPart(key, part)
    QoL.parts[key] = part
    QoL.partOrder[#QoL.partOrder + 1] = key
    return part
end

local mod = ns:RegisterModule("qol", {
    name        = "Quality of Life",
    group       = "General",
    description = "The small conveniences: the vendor visit, looting and opening, and a few readouts of your own.",
    defaults = {
        enabled = false,

        -- Shared by every readout below, so they look like one addon.
        font        = "Expressway",
        fontOutline = "OUTLINE",

        -- ------------------------------------------------------------ vendor
        sellJunk        = true,
        repairAll       = true,
        repairGuild     = true,
        repairCoinIcons = true,
        repairReport    = true,

        durability = {
            enabled   = true,
            threshold = 30,
            fontSize  = 26,
            color     = { r = 1, g = 0.27, b = 0.27 },
            x = 0, y = 220, scale = 1,
        },

        -- -------------------------------------------------------------- loot
        quickLoot      = true,
        quickLootDelay = 0.05,
        autoOpen       = false,
        autoFillDelete = true,

        -- ------------------------------------------------------------- stats
        stats = {
            enabled    = false,
            fontSize   = 12,
            rowGap     = 3,
            colorMode  = "palette",          -- palette | class | custom
            color      = { r = 1, g = 1, b = 1 },
            coloredValues = false,
            showRating = false,              -- rating instead of percent
            showBoth   = false,              -- rating AND percent
            abbreviate = false,
            hidden     = { leech = true, avoidance = true, speed = true },
            x = -360, y = 200, scale = 1,
        },

        -- ----------------------------------------------------------- display
        fps = {
            enabled   = false,
            interval  = 1,
            fontSize  = 12,
            showWorld = true,
            showLocal = true,
            showLabel = true,
            color     = { r = 1, g = 1, b = 1 },
            x = -360, y = 260, scale = 1,
        },

        combatAlert = {
            enabled    = false,
            mode       = "both",             -- enter | leave | both
            enterText  = "+Combat",
            leaveText  = "-Combat",
            enterColor = { r = 1, g = 0.35, b = 0.35 },
            leaveColor = { r = 0.45, g = 1, b = 0.55 },
            fontSize   = 22,
            x = 0, y = 170, scale = 1,
        },

        crosshair = {
            enabled     = false,
            visibility  = "always",          -- always | combat | instances
            length      = 40,
            thickness   = 2,
            gap         = 0,
            color       = { r = 1, g = 1, b = 1, a = 0.75 },
            borderSize  = 1,
            borderColor = { r = 0, g = 0, b = 0, a = 1 },
            xOffset = 0, yOffset = 0,
        },

        mapCoords     = false,
        mapCoordsSize = 12,
    },
})
QoL.mod = mod

function QoL.db() return mod.db end

-- The font every readout in this module uses. One place, so a font that is not
-- installed falls back once rather than five times.
function QoL.Font()
    return ns.MediaFont(QoL.db().font)
end

function QoL.Outline()
    local o = QoL.db().fontOutline
    return (o == "NONE") and "" or o
end

-- Register or unregister one handler to match a feature's switch. Every part
-- here is toggled on its own, so registration follows the setting rather than
-- the module: a feature that is off costs no event at all.
function QoL.SyncEvent(on, event, handler)
    if on then
        ns:RegisterEvent(event, handler)
    else
        ns:UnregisterEvent(event, handler)
    end
end

mod.tabs = {
    { id = "vendor",  label = "Vendor" },
    { id = "loot",    label = "Loot" },
    { id = "stats",   label = "Stats" },
    { id = "display", label = "Display" },
}

-- Re-runs every part. Options call this after a write: a part decides for
-- itself whether it has anything to do, which keeps the options free of
-- knowledge about what a setting switches on.
function QoL.Apply()
    if not mod.active then return end
    for _, key in ipairs(QoL.partOrder) do
        local part = QoL.parts[key]
        if part and part.Apply then
            local ok, err = pcall(part.Apply)
            if not ok then ns:Debug("qol %s apply: %s", key, tostring(err)) end
        end
    end
end

function mod:OnEnable()
    QoL.Apply()
end

function mod:OnDisable()
    for _, key in ipairs(QoL.partOrder) do
        local part = QoL.parts[key]
        if part and part.Disable then pcall(part.Disable) end
    end
end
