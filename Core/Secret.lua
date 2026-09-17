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
--   always          UnitHealth
--   not our units   UnitHealthMax, UnitPowerMax, UnitCastingInfo, UnitGUID,
--                   UnitName, UnitClass
--   in combat       aura data, cooldowns, threat, GetRaidTargetIndex
--   never readable  the combat log -- there is no addon-side event info at all
--
-- Everything is verified against the 1.60.1 API documentation; nothing here
-- guesses at a function name. The one thing that cannot be read from the source
-- is what is readable AT RUNTIME, which is what /vfui secrets is for.
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
-- The bar is scaled 0..100 and fed the PERCENT, because UnitHealthPercent
-- hands us the percentage directly: dividing a secret current by a secret max
-- ourselves is exactly the arithmetic that throws. The percent is still a
-- secret, and SetMinMaxValues/SetValue accept one.
function ns:SetHealthFill(bar, unit, usePredicted)
    if not bar or not unit then return end
    bar:SetMinMaxValues(0, 100)
    bar:SetValue(UnitHealthPercent(unit, usePredicted ~= false))
end

-- Power has no percent API, so the raw pair goes in: both values may be
-- secret, and the widget takes them anyway.
function ns:SetPowerFill(bar, unit, powerType)
    if not bar or not unit then return end
    bar:SetMinMaxValues(0, UnitPowerMax(unit, powerType))
    bar:SetValue(UnitPower(unit, powerType))
end

-- SecretUtil answers "would this be secret right now" WITHOUT handing us a
-- secret to test, which is the cheap way to decide whether a feature can run at
-- all. Wrapped because the namespace is new and every call site would otherwise
-- need the same nil check.
local SU = _G.SecretUtil

function ns.AurasRestricted()
    return (SU and SU.ShouldAurasBeSecret and SU.ShouldAurasBeSecret()) or false
end

function ns.CooldownsRestricted()
    return (SU and SU.ShouldCooldownsBeSecret and SU.ShouldCooldownsBeSecret()) or false
end

function ns.UnitPowerRestricted(unit, powerType)
    return (SU and SU.ShouldUnitPowerBeSecret and SU.ShouldUnitPowerBeSecret(unit, powerType)) or false
end

function ns.ThreatRestricted(unit)
    return (SU and SU.ShouldUnitThreatValuesBeSecret and SU.ShouldUnitThreatValuesBeSecret(unit)) or false
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
    note = "Run it out of combat, in combat, and in a raid: the answers differ.",
})
ns.Slash.SECRETS = function()
    local A, R = ns.C.accent, ns.C.r
    local function state(v)
        if not ns.IsSecret(v) then return ns.C.pos .. "readable" .. R end
        if ns.CanRead(v) then return ns.C.yellow .. "secret, accessible" .. R end
        return ns.C.neg .. "secret" .. R
    end

    ns:Print("%sForever secret-value report%s — combat: %s", A, R,
        InCombatLockdown() and "yes" or "no")

    ns:Print("  UnitHealth(player)      %s", state(UnitHealth("player")))
    ns:Print("  UnitHealthMax(player)   %s", state(UnitHealthMax("player")))
    ns:Print("  UnitHealth(target)      %s", UnitExists("target") and state(UnitHealth("target")) or "no target")
    ns:Print("  UnitPower(player)       %s", state(UnitPower("player")))
    ns:Print("  UnitPowerMax(player)    %s", state(UnitPowerMax("player")))

    local aura = C_UnitAuras.GetAuraDataByIndex("player", 1, "HELPFUL")
    ns:Print("  first player buff       %s",
        aura and state(aura.expirationTime) or "none active")

    ns:Print("  threat(player,target)   %s",
        UnitExists("target") and state(UnitThreatSituation("player", "target") or 0) or "no target")

    -- Restriction predicates: what the client says BEFORE we touch a value.
    ns:Print("%sRestrictions%s — auras: %s, cooldowns: %s", A, R,
        tostring(ns.AurasRestricted()), tostring(ns.CooldownsRestricted()))

    -- The combat log is the hard stop, and the reason five VuloClassicUI
    -- modules cannot come across as they are.
    local ccl = _G.C_CombatLog
    ns:Print("  combat log for addons   %s",
        (ccl and ccl.GetCurrentEventInfo) and (ns.C.pos .. "available" .. R)
                                          or (ns.C.neg .. "not available" .. R))
end
