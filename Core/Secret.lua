-- VuloForeverUI / Core / Secret
--
-- Forever runs the retail 12.x addon restrictions ("addon disarmament"): the
-- combat-relevant APIs hand tainted code SECRET VALUES. A secret can be passed
-- on and displayed, but our code may not do arithmetic on it, compare it,
-- concatenate it, or use it as a table key. Doing so throws.
--
-- The rule that follows from that, and the reason this file exists:
--
--     DISPLAY a secret, never DECIDE on one.
--
-- Blizzard's own unit frames pass UnitHealth() straight into
-- StatusBar:SetValue(), and that is the pattern every module here copies: the
-- value travels from the API into a widget setter without ever being touched.
-- Where a number really is needed for a decision, ask whether it is readable
-- first (ns.IsSecret / ns.CanRead) and have a path for "no".
--
-- WHAT IS SECRET, in short (see docs/forever-client-research.md for the list):
--   always          UnitHealth, UnitHealthPercent, UnitPower -- the player's
--                   own included, OUT of combat too, and canaccessvalue() says
--                   no as well (seen 2026-09-18). There is no
--                   ShouldUnitHealthBeSecret predicate for the same reason.
--   in combat       cooldowns; aura data; GetRaidTargetIndex
--   readable        UnitHealthMax and UnitPowerMax of the player, threat
--                   situation vs. the target -- in combat too (2026-09-18)
--   not our units   UnitHealthMax, UnitPowerMax, UnitCastingInfo, UnitGUID,
--                   UnitName, UnitClass
--   never readable  the combat log -- there is no addon-side event info at all
--
-- AURAS ARE DIFFERENT: when they are restricted, C_UnitAuras.GetAuraDataByIndex
-- does not hand back a secret, it THROWS ("Auras cannot be accessed when secret
-- while tainted by ..."). Every aura call must therefore be gated with
-- ns.AurasRestricted() first; a secret-safe display path alone is not enough.
--
-- Everything is verified against the 1.60.1 API documentation; nothing here
-- guesses at a function name. The one thing that cannot be read from the source
-- is what is readable AT RUNTIME, which is what /vfsecrets is for.
local _, ns = ...

-- The two primitives the client gives us. Both are plain globals in 12.x.
local issecretvalue = _G.issecretvalue
local canaccessvalue = _G.canaccessvalue

-- True when this value came out of a restricted API and must not be inspected.
function ns.IsSecret(v)
    return issecretvalue and issecretvalue(v) or false
end

-- True when the value may be read normally: not secret, or secret but currently
-- accessible to us. Use this as the gate in front of any comparison.
function ns.CanRead(v)
    if not issecretvalue then return true end
    if not issecretvalue(v) then return true end
    return canaccessvalue and canaccessvalue(v) or false
end

-- A number we are allowed to look at, or the fallback. For everything that
-- needs a real Lua number -- sorting, thresholds, string.format -- and has a
-- sensible answer for "not readable right now".
function ns.Num(v, fallback)
    if type(v) == "number" and ns.CanRead(v) then return v end
    return fallback
end

-- Health and power as a bar fill, secret-safe.
--
-- The bar is scaled 0..1 and fed the FRACTION, because UnitHealthPercent
-- hands us the fraction directly: dividing a secret current by a secret max
-- ourselves is exactly the arithmetic that throws. The fraction is still a
-- secret, and SetMinMaxValues/SetValue accept one.
--
-- 0..1, not 0..100: the raw return is a fraction (Blizzard's own
-- CurveConstants.ScaleTo100 exists to turn it into a percent). A bar scaled
-- to 100 showed a 62 % player as empty (seen 2026-09-18).
function ns:SetHealthFill(bar, unit, usePredicted)
    if not bar or not unit then return end
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(UnitHealthPercent(unit, usePredicted ~= false))
end

-- Power has no percent API, so the raw pair goes in: both values may be
-- secret, and the widget takes them anyway.
function ns:SetPowerFill(bar, unit, powerType)
    if not bar or not unit then return end
    bar:SetMinMaxValues(0, UnitPowerMax(unit, powerType))
    bar:SetValue(UnitPower(unit, powerType))
end

-- C_Secrets answers "would this be secret right now" WITHOUT handing us a
-- secret to test, which is the cheap way to decide whether a feature can run at
-- all. The documentation calls the system "SecretUtil"; the Lua namespace is
-- C_Secrets (SecretPredicateAPIDocumentation.lua, and that is what Blizzard's
-- own aura code calls). An earlier draft asked _G.SecretUtil, which is nil, so
-- every predicate said "not restricted" while the aura API was throwing.
-- Wrapped because every call site would otherwise need the same nil check.
local CS = _G.C_Secrets

local function pred(name, ...)
    local f = CS and CS[name]
    if not f then return false end
    return f(...) or false
end

-- False only on a build without secret restrictions at all -- there is no such
-- Forever build, but this is the honest answer to "can I skip the gates".
function ns.HasSecretRestrictions()
    return CS and CS.HasSecretRestrictions and CS.HasSecretRestrictions() or false
end

function ns.AurasRestricted()
    return pred("ShouldAurasBeSecret")
end

-- Per-index version, for loops that stop at the first secret aura instead of
-- refusing the whole list.
function ns.UnitAuraIndexRestricted(unit, index, filter)
    return pred("ShouldUnitAuraIndexBeSecret", unit, index, filter)
end

function ns.CooldownsRestricted()
    return pred("ShouldCooldownsBeSecret")
end

function ns.SpellCooldownRestricted(spell)
    return pred("ShouldSpellCooldownBeSecret", spell)
end

function ns.UnitPowerRestricted(unit, powerType)
    return pred("ShouldUnitPowerBeSecret", unit, powerType)
end

function ns.UnitHealthMaxRestricted(unit)
    return pred("ShouldUnitHealthMaxBeSecret", unit)
end

function ns.UnitIdentityRestricted(unit)
    return pred("ShouldUnitIdentityBeSecret", unit)
end

function ns.UnitCastingRestricted(unit)
    return pred("ShouldUnitSpellCastingBeSecret", unit)
end

-- Threat comes in two predicates with different signatures (checked in the
-- client 2026-09-18): the numeric values need BOTH units, the state (the
-- UnitThreatSituation tier) takes the mob as optional.
function ns.ThreatValuesRestricted(unit, mobUnit)
    return pred("ShouldUnitThreatValuesBeSecret", unit, mobUnit)
end

function ns.ThreatStateRestricted(unit, mobUnit)
    return pred("ShouldUnitThreatStateBeSecret", unit, mobUnit)
end

-- Cooldowns: hand the Cooldown widget the duration OBJECT instead of start and
-- duration numbers. The object survives being secret, and this is the only path
-- that keeps the swipe correct in combat.
--
-- NOTE Cooldown:SetCooldown and friends are PROTECTED FUNCTIONS in Forever --
-- stricter than live retail, where they are not. On a protected cooldown frame
-- (an action button's, for example) our call is refused in combat; on a frame
-- we created ourselves it is fine.
function ns:SetSpellCooldown(cd, spell)
    if not cd then return end
    local info = C_Spell.GetSpellCooldown(spell)
    if not info then return end
    if info.duration and cd.SetCooldownFromDurationObject and type(info.duration) == "table" then
        cd:SetCooldownFromDurationObject(info.duration)
    else
        cd:SetCooldown(info.startTime, info.duration, info.modRate)
    end
end

-- Diagnostics. Prints what is readable right now, which is the one question the
-- API documentation cannot answer -- run it standing still, then again mid-fight
-- and in a raid, because the answers differ per restriction state.
ns:RegisterSlash({ key = "SECRETS", commands = { "/vfsecrets" },
    desc = "Report which combat values this client lets the addon read right now.",
    note = "Run it out of combat, in combat, and in a raid: the answers differ. "
        .. "'/vfsecrets force' toggles the client's simulated combat restrictions.",
})

-- The client ships a CVar that forces the combat restriction state without a
-- fight (present on 1.60.1, not locked, not secure -- checked 2026-09-19). It
-- is a test switch: it is never set by anything but this command, and the
-- report says when it is on so a forgotten "1" cannot pass for real behaviour.
local FORCE_CVAR = "addonCombatRestrictionsForced"

local function restrictionsForced()
    return C_CVar.GetCVar(FORCE_CVAR) == "1"
end
ns.RestrictionsForced = restrictionsForced   -- Init.lua warns at login: the CVar outlives the session

ns.Slash.SECRETS = function(msg)
    local A, R = ns.C.accent, ns.C.r
    if (msg or ""):lower():match("^%s*force") then
        if InCombatLockdown() then
            ns:Print("Not while in combat.")
            return
        end
        local ok = pcall(C_CVar.SetCVar, FORCE_CVAR, restrictionsForced() and "0" or "1")
        ns:Print("simulated combat restrictions: %s%s", restrictionsForced()
            and (ns.C.yellow .. "ON" .. R .. " -- run /vfsecrets, then switch it off again")
            or  (ns.C.pos .. "off" .. R),
            ok and "" or (ns.C.neg .. "  (the client refused the change)" .. R))
        return
    end
    local function state(v)
        if not ns.IsSecret(v) then return ns.C.pos .. "readable" .. R end
        if ns.CanRead(v) then return ns.C.yellow .. "secret, accessible" .. R end
        return ns.C.neg .. "secret" .. R
    end

    ns:Print("%sForever secret-value report%s — combat: %s%s", A, R,
        InCombatLockdown() and "yes" or "no",
        restrictionsForced() and (ns.C.yellow .. "  (restrictions FORCED by CVar)" .. R) or "")

    -- Every probe runs in its own pcall: the aura API THROWS when restricted
    -- (seen 2026-09-18), and one throw must not eat the rest of the report.
    local function probe(label, fn)
        local ok, res = pcall(fn)
        if ok then
            ns:Print("  %-24s%s", label, res)
        else
            ns:Print("  %-24s%sthrows:%s %s", label, ns.C.neg, R, tostring(res))
        end
    end

    local hasTarget = UnitExists("target")
    probe("UnitHealth(player)",     function() return state(UnitHealth("player")) end)
    probe("UnitHealthPercent(pl.)", function() return state(UnitHealthPercent("player", true)) end)
    probe("UnitHealthMax(player)",  function() return state(UnitHealthMax("player")) end)
    probe("UnitHealth(target)",     function() return hasTarget and state(UnitHealth("target")) or "no target" end)
    probe("UnitPower(player)",      function() return state(UnitPower("player")) end)
    probe("UnitPowerMax(player)",   function() return state(UnitPowerMax("player")) end)

    -- Restriction predicates: what the client says BEFORE we touch a value.
    -- Printed ahead of the aura probe on purpose -- if the probe throws, this
    -- line tells whether the predicate would have warned us.
    probe("C_Secrets", function()
        return CS and (ns.C.pos .. "present" .. R) or (ns.C.neg .. "MISSING" .. R)
    end)
    probe("restricted: auras",   function() return tostring(ns.AurasRestricted()) end)
    probe("restricted: cooldowns", function() return tostring(ns.CooldownsRestricted()) end)
    probe("restricted: power",   function() return tostring(ns.UnitPowerRestricted("player")) end)
    probe("restricted: threat",  function()
        return hasTarget and tostring(ns.ThreatStateRestricted("player", "target")) or "no target"
    end)

    probe("first player buff", function()
        local aura = C_UnitAuras.GetAuraDataByIndex("player", 1, "HELPFUL")
        return aura and state(aura.expirationTime) or "none active"
    end)
    probe("player buff count", function()
        return state(C_UnitAuras.GetUnitAuraCount and C_UnitAuras.GetUnitAuraCount("player", "HELPFUL") or 0)
    end)
    probe("threat(player,target)", function()
        return hasTarget and state(UnitThreatSituation("player", "target") or 0) or "no target"
    end)
    probe("spell cooldown (1st)", function()
        local slot = 1
        local action = GetActionInfo and select(2, GetActionInfo(slot))
        local info = action and C_Spell.GetSpellCooldown(action)
        return info and state(info.startTime) or "no spell on action slot 1"
    end)

    -- The combat log is the hard stop, and the reason five VuloClassicUI
    -- modules cannot come across as they are.
    local ccl = _G.C_CombatLog
    ns:Print("  combat log for addons   %s",
        (ccl and ccl.GetCurrentEventInfo) and (ns.C.pos .. "available" .. R)
                                          or (ns.C.neg .. "not available" .. R))
end
