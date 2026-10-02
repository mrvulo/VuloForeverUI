-- VuloForeverUI / Modules / Nameplates / Import
--
-- Nameplate settings out of another suite's profile string. Reading the
-- string, finding the nameplate table in it and the type-checked copy are
-- Core/ForeignProfile.lua. The nameplate settings there carry the same names
-- and meanings as ours with two exceptions, translated below: the bar width is
-- an EXTRA on a fixed 150 there (6 by default), and the overlay textures are
-- names of their own media that do not exist here.
--
-- Our nested tables (text slots, icon slots, aura groups, aura text) are flat
-- keys there -- "textSlotLeft", "textSlotLeftSize", "leftSlotSize",
-- "maxDebuffs", "auraStackTextSize" -- and are put together into our shape
-- before the copy, which then type-checks them like everything else.
local _, ns = ...
local L = ns.L
local NP = ns.NP

-- Whether the module is on is the player's choice here, and the saved-CVar
-- bookkeeping belongs to this client.
local SKIP = { enabled = true, savedCVars = true, savedStacking = true }

local TEXT_ELEMENTS = { none = true, enemyName = true, level = true, levelName = true, nameLevel = true }
local TEXT_SLOTS = { "Top", "Right", "Left", "Center" }
local ICON_SLOTS = { "top", "bottom", "left", "right", "topleft", "topright" }
-- our aura kind -> their key stem
local AURA_KINDS = { debuffs = "debuff", buffs = "buff", cc = "cc" }
-- only the debuffs carry a count there; buffs and crowd control keep ours
local MAX_KEYS = { debuffs = "maxDebuffs" }

-- A table with only the keys that are there, or nil when none is.
local function pick(t)
    return next(t) ~= nil and t or nil
end

local function textSlots(src)
    local out = {}
    for _, slot in ipairs(TEXT_SLOTS) do
        local p = "textSlot" .. slot
        local el = src[p]
        if type(el) == "string" and not (TEXT_ELEMENTS[el] or NP.HEALTH_ELEMENTS[el]) then el = nil end
        out[slot] = pick({
            element = el, size = src[p .. "Size"], color = src[p .. "Color"],
            x = src[p .. "XOffset"], y = src[p .. "YOffset"], decimal = src[p .. "PctDecimal"],
        })
    end
    return pick(out)
end

local function iconSlots(src)
    local out = {}
    for _, slot in ipairs(ICON_SLOTS) do
        local p = slot .. "Slot"
        out[slot] = pick({ size = src[p .. "Size"], x = src[p .. "XOffset"], y = src[p .. "YOffset"] })
    end
    return pick(out)
end

local function auras(src)
    local out = {}
    for kind, p in pairs(AURA_KINDS) do
        out[kind] = pick({
            max = MAX_KEYS[kind] and src[MAX_KEYS[kind]], spacing = src[p .. "Spacing"],
            crop = src[p .. "CropIcons"], cropPct = src[p .. "CropPercent"],
            hideBorder = src["hide" .. (kind == "cc" and "CC" or p:gsub("^%l", string.upper)) .. "IconBorder"],
        })
    end
    return pick(out)
end

-- Their duration text is set per kind; ours is one for all, so the debuffs'
-- wins, and the older shared keys stand in where it is missing. Their centre
-- is spelled "center", ours "centre".
local function auraText(src)
    local pos = src.debuffTimerPosition or src.auraTextPosition
    if pos == "center" then pos = "centre" end
    return pick({
        duration = pick({ position = pos,
            size = src.debuffDurationTextSize or src.auraDurationTextSize,
            color = src.debuffTimerColor or src.auraDurationTextColor,
            x = src.debuffDurationTextX or src.auraDurationTextX,
            y = src.debuffDurationTextY or src.auraDurationTextY }),
        stacks = pick({ position = src.auraStackTextPosition, size = src.auraStackTextSize,
            color = src.auraStackTextColor, x = src.auraStackTextX, y = src.auraStackTextY }),
    })
end

--- Returns the number of settings taken over, or nil and an error line.
function NP.ImportForeignString(text)
    local FP = ns.ForeignProfile
    local mod = ns.modules.nameplates
    local db = mod and mod.db
    if not (db and mod.defaults) then return nil, L["The nameplate settings are not loaded."] end

    local payload = FP.Decode(text)
    if not payload then return nil, L["This is not a profile string that can be read."] end
    local section = FP.FindSection(payload, mod.defaults, 15)
    if not section then return nil, L["The string carries no nameplate settings."] end

    local src = FP.Copy(section)
    src.textSlots, src.iconSlots = textSlots(src), iconSlots(src)
    src.auras, src.auraText = auras(src), auraText(src)
    -- the red light on a plate low on health is our execute glow
    if type(src.lowHpGlow) == "boolean" then src.executeEnabled = src.lowHpGlow end
    if type(src.owBasicColoring) == "boolean" then src.mobTypesInInstancesOnly = src.owBasicColoring end
    if type(src.replaceQuestIconWithObjective) == "boolean" then
        src.questObjectiveText = src.replaceQuestIconWithObjective
    end
    -- media names in their spelling ("atrocity", "sm:Atrocity")
    for _, k in ipairs({ "healthBarTexture", "castBarTexture" }) do
        if type(src[k]) == "string" then
            src[k] = FP.MediaName("statusbar", (src[k]:gsub("^sm:", "")))
        end
    end
    if type(src.healthBarWidth) == "number" then
        src.healthBarWidth = math.max(100, math.min(250, 150 + src.healthBarWidth))
    end
    -- An overlay name unknown here would fall back to a solid white fill over
    -- the whole bar; such an overlay is switched off instead.
    for _, k in ipairs({ "targetOverlayTexture", "focusOverlayTexture", "hoverOverlayTexture" }) do
        local v = src[k]
        if type(v) == "string" and v ~= "none" and not (ns.MediaStatusbarValid and ns.MediaStatusbarValid(v)) then
            src[k] = "none"
        end
    end

    local taken = FP.Apply(db, mod.defaults, src, SKIP)

    -- Everything that reads a setting once rather than on every paint.
    NP.ApplyCVars()
    NP.ApplyHitbox()
    NP.ApplyShowEnemies()
    NP.Bump()
    -- a kind that gained or lost its slot, or a slot of another size, needs
    -- its aura container built anew
    if NP.Auras and NP.Auras.Rebuild then NP.Auras.Rebuild() end
    return taken
end
