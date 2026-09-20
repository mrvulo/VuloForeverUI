-- VuloForeverUI / Modules / Nameplates / Colors
--
-- Which colour a plate's health bar gets. One chain, highest priority first:
--
--   tapped > threat (groups only) > target > focus > neutral
--          > enemy player (class colour) > mob type > plain enemy
--
-- Everything the chain reads is documented readable for a nameplate unit:
-- tap state, threat SITUATION (not the numbers), reaction, classification,
-- level, combat state. Each read still goes through ns.CanRead / ns.Num, so a
-- value that does turn secret drops that step instead of throwing.
--
-- The one thing that cannot be decided here is an enemy player's class:
-- UnitClass is identity-restricted. Blizzard's own hidden bar has that colour,
-- set by untainted code -- it is read off that bar and handed straight on.
local _, ns = ...
local NP = ns.NP

local Colors = {}
NP.Colors = Colors

-- ---------------------------------------------------------------------------
-- Context: plain facts about the player, refreshed on roster and zone events.
-- ---------------------------------------------------------------------------
function Colors.RefreshContext()
    local ctx, db = NP.ctx, NP.db()
    ctx.inGroup = IsInGroup() and true or false
    local inInstance = IsInInstance()
    ctx.inInstance = inInstance and true or false
    -- Forever has no specialisations; whether the client ever reports a TANK
    -- role is open, hence the manual switch.
    ctx.isTank = db.assumeTank or UnitGroupRolesAssigned("player") == "TANK"
end

function Colors.RefreshAll()
    Colors.RefreshContext()
    for _, plate in pairs(NP.plates) do
        Colors.Apply(plate)
        plate:UpdateClassification()
    end
end

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
local function plainTrue(v)
    return ns.CanRead(v) and v == true
end

-- boss / miniboss / caster / nil. Classic-shaped: a skull or a world boss is a
-- boss, any elite is a mini-boss, a mana user is a caster. Level differences
-- alone say nothing out in the world, where +2 mobs are everyday.
local function mobType(unit)
    local class = UnitClassification(unit)
    if ns.CanRead(class) then
        if class == "worldboss" then return "boss" end
        local lvl = ns.Num(UnitEffectiveLevel(unit), nil)
        if lvl and lvl < 0 then return "boss" end
        if class == "elite" or class == "rareelite" then return "miniboss" end
    end
    local powerType = UnitPowerType(unit)
    if ns.CanRead(powerType) and powerType == Enum.PowerType.Mana then return "caster" end
    return nil
end

-- A unit that is not fighting is shown darker (or in its own colour), so a
-- pull stands out from the pack next to it.
local function dim(db, unit, r, g, b)
    if not db.darkenEnemiesOOC then return r, g, b end
    if plainTrue(UnitAffectingCombat(unit)) then return r, g, b end
    if db.darkenOOCRecolor then
        local c = db.darkenOOCColor
        return c.r, c.g, c.b
    end
    return r * 0.6, g * 0.6, b * 0.6
end

-- Threat step. Returns a colour table, or nil when threat has nothing to say.
local function threatColor(db, unit, kind)
    local status = ns.Num(UnitThreatSituation("player", unit), nil)
    if not status then return nil end
    if NP.ctx.isTank then
        if status >= 3 then
            if db.classicTankAggro then return db.tankHasAggro end
            if not db.tankHasAggroEnabled then return nil end
            if kind == "boss" and not db.tankHasAggroOverrideBoss then return nil end
            if (kind == "miniboss" or kind == "caster") and not db.tankHasAggroOverrideMobType then return nil end
            return db.tankHasAggro
        elseif status == 2 then
            return db.tankLosingAggro
        end
        -- Someone else has it. Another tank is fine, anyone else is not. The
        -- mob's target is a compound token and may be unreadable; then it
        -- counts as "not a tank".
        if db.offTankAggroEnabled then
            local role = UnitGroupRolesAssigned(unit .. "target")
            if ns.CanRead(role) and role == "TANK" then return db.offTankAggro end
        end
        return db.tankNoAggro
    end
    if status >= 3 then return db.dpsHasAggro end
    if status == 2 then return db.dpsNearAggro end
    if db.dpsNoAggroEnabled then
        if kind == "boss" and not db.dpsNoAggroOverrideBoss then return nil end
        if kind == "miniboss" and not db.dpsNoAggroOverrideMiniBoss then return nil end
        if kind == "caster" and not db.dpsNoAggroOverrideCaster then return nil end
        return db.dpsNoAggro
    end
    return nil
end

-- Blizzard's hidden health bar of this plate, if it is still the right one.
local function blizzardBar(plate)
    local uf = plate.blizz
    if not uf or uf:IsForbidden() then return nil end
    local bar = uf.healthBar or (uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar)
    if not bar or bar:IsForbidden() then return nil end
    return bar
end

-- ---------------------------------------------------------------------------
-- Apply
-- ---------------------------------------------------------------------------
local function setPlain(plate, r, g, b)
    if plate.lastR == r and plate.lastG == g and plate.lastB == b then return end
    plate.lastR, plate.lastG, plate.lastB = r, g, b
    plate.health:SetStatusBarColor(r, g, b)
end

function Colors.Apply(plate)
    local unit = plate.unit
    if not unit then return end
    local db = NP.db()

    if plainTrue(UnitIsTapDenied(unit)) then
        local c = db.tapped
        return setPlain(plate, c.r, c.g, c.b)
    end

    local kind = mobType(unit)

    if NP.ctx.inGroup then
        local c = threatColor(db, unit, kind)
        if c then return setPlain(plate, c.r, c.g, c.b) end
    end

    if plate.isTarget and db.targetColorEnabled then
        local c = db.target
        return setPlain(plate, c.r, c.g, c.b)
    end
    if plate.isFocus and db.focusColorEnabled then
        local c = db.focus
        return setPlain(plate, c.r, c.g, c.b)
    end

    local reaction = ns.Num(UnitReaction(unit, "player"), nil)
    if reaction == 4 and not NP.ctx.inInstance then
        local c = db.neutral
        return setPlain(plate, dim(db, unit, c.r, c.g, c.b))
    end

    if plainTrue(UnitIsPlayer(unit)) then
        local bar = blizzardBar(plate)
        if bar then
            -- Possibly secret numbers: handed on, never looked at, and kept
            -- out of the last-colour cache for the same reason.
            local r, g, b = bar:GetStatusBarColor()
            if ns.Exists(r) then
                plate.lastR = nil
                plate.health:SetStatusBarColor(r, g, b)
                return
            end
        end
    end

    local c = (kind and db[kind]) or (reaction == 4 and db.neutral) or db.enemyInCombat
    return setPlain(plate, dim(db, unit, c.r, c.g, c.b))
end

-- Name colour: the slot's own colour, or hostile/neutral by reaction.
local NAME_FAMILY = { enemyName = true, levelName = true, nameLevel = true }

function Colors.Name(plate)
    local db = NP.db()
    if not db.enemyNameTextReactionColor or not plate.unit then return end
    local reaction = ns.Num(UnitReaction(plate.unit, "player"), nil)
    local c = (reaction == 4) and db.enemyNameNeutralColor or db.enemyNameHostileColor
    for _, fs in pairs(plate.texts) do
        if NAME_FAMILY[fs.element] then fs:SetTextColor(c.r, c.g, c.b) end
    end
end
