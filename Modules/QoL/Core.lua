-- VuloForeverUI / Modules / QoL / Core
--
-- The small conveniences, in one module with four tabs:
--
--   general  the answers you would otherwise click: quests, rez, summon,
--            releasing in a battleground, the one-option NPC, and who is
--            allowed to invite you or open a trade
--   vendor   selling the greys, repairing, and a warning before the gear is gone
--   loot     looting a corpse in one click, opening what can be opened,
--            typing DELETE for you
--   display  frame rate, latency, map coordinates, a combat line, a crosshair
--
-- WHY THIS MODULE IS SPLIT THE WAY IT IS
--
-- Every part here talks to a different piece of the client:
--
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
    -- Strict two columns on every tab. Without it a switch that ends up alone
    -- on its row is stretched across the page, and next to its paired
    -- neighbours that reads as a different kind of setting rather than as the
    -- last one of a group (user report, 22.09.2026).
    optionsGrid = true,
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
            -- The same watcher's second output: a word on the combat line,
            -- with an earlier threshold than the warning itself.
            line          = false,
            lineText      = "Repair",
            lineThreshold = 15,
            lineColor     = { r = 1, g = 0.6, b = 0.25 },
            threshold = 30,
            fontSize  = 26,
            color     = { r = 1, g = 0.27, b = 0.27 },
            x = 0, y = 220, scale = 1,
        },

        -- ----------------------------------------------------------- character
        -- All off. Every one of them takes a decision out of your hands, and a
        -- module that ships making decisions for you is a module you have to
        -- discover before you can stop it.
        character = {
            acceptQuests    = false,
            turnInQuests    = false,
            acceptResurrect = false,
            acceptSummon    = false,
            releasePvP      = false,
        },

        -- --------------------------------------------------------------- world
        world = {
            gossipSingle = false,
            blockInvites = false,
            blockTrades  = false,
        },

        -- --------------------------------------------------------- stack split
        stackSplit = {
            maxButton = false,
            skin      = false,
        },

        -- --------------------------------------------------------- flight time
        -- The learned times themselves are NOT here: they are world facts and
        -- live account-wide (ns.db.global.qolFlightTimes), not per profile.
        flight = {
            showBar = false,
            chat    = false,
            width   = 240,
            height  = 18,
            texture = "Matte",
            -- the texts: "" / 0 follow the module font and the bar height
            font = "", fontSize = 0,
            labelPos = "left",  labelX = 0, labelY = 0,
            timePos  = "right", timeX  = 0, timeY  = 0,
            borderSize = 1, borderColor = { r = 0, g = 0, b = 0, a = 0.8 },
            x = 0, y = -180, scale = 1,
        },

        -- --------------------------------------------------------------- mail
        -- The remembered names are NOT here: like the flight times they are
        -- account-wide (ns.db.global.qolMailNames).
        mail = {
            recipients = false,
        },

        -- -------------------------------------------------------------- loot
        quickLoot      = true,
        quickLootDelay = 0.05,
        autoOpen       = false,
        autoFillDelete = true,

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

        -- Messages on the combat line. Only what COMBAT_TEXT_UPDATE can source:
        -- an interrupt, a reflect, an avoided hit. A banish or a buff handed to
        -- somebody else would need the combat log, which this client does not
        -- hand out at all.
        combatEvents = {
            interrupted      = false,
            reflected        = false,
            avoided          = false,
            partyDeath       = false,
            interruptedColor = { r = 1,    g = 0.82, b = 0.25 },
            reflectedColor   = { r = 0.60, g = 0.80, b = 1    },
            avoidedColor     = { r = 0.75, g = 0.75, b = 0.80 },
            partyDeathColor  = { r = 1,    g = 0.35, b = 0.35 },
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

        -- --------------------------------------------------------- trinkets
        -- The window's look. The queues name items one character carries and
        -- live per character (Trinkets.lua, VuloForeverUICharDB).
        trinkets = {
            enabled  = false,
            vertical = false,
            tooltips = true,
            freeMove = false,     -- moved without Edit Mode while on
            x = 0, y = -120, scale = 1,
        },
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
    { id = "general", label = "General" },
    { id = "vendor",  label = "Vendor" },
    { id = "loot",    label = "Loot" },
    { id = "display", label = "Display" },
    { id = "trinkets", label = "Trinkets" },
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
