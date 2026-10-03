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

-- The value itself when it may be read, nil when it may not. For lookups that
-- treat "not readable" the same as "not there".
function ns.Readable(v)
    if ns.CanRead(v) then return v end
    return nil
end

-- A frame's rectangle in UIParent units, or nil while it is not resolved or
-- not readable. Each value is tested on its own: GetRect answers with plain
-- nils for a frame whose rectangle is not resolved yet (the first moments
-- after login), and a table walk would stop at the first hole.
function ns.UIParentRect(f)
    local ok, left, bottom, width, height = pcall(f.GetRect, f)
    if not ok then return nil end
    if not (ns.Num(left) and ns.Num(bottom) and ns.Num(width) and ns.Num(height)) then
        return nil
    end
    local s = (f:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
    return left * s, bottom * s, width * s, height * s
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

-- One spell's aura can be secret while the aura system as a whole is not;
-- reading it then throws just the same.
function ns.SpellAuraRestricted(spellID)
    return pred("ShouldSpellAuraBeSecret", spellID)
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
    -- The duration object is asked for directly instead of being dug out of
    -- the info table. Two reasons: it is the sanctioned path, and the old
    -- line `if info.duration and ...` was a BOOLEAN TEST on a field that is
    -- secret in combat, which throws -- the one shape that reads as harmless
    -- and is not.
    local duration = C_Spell.GetSpellCooldownDuration and C_Spell.GetSpellCooldownDuration(spell)
    if type(duration) ~= "nil" and cd.SetCooldownFromDurationObject then
        cd:SetCooldownFromDurationObject(duration)
        return
    end
    local info = C_Spell.GetSpellCooldown(spell)
    if type(info) ~= "table" then return end
    cd:SetCooldown(info.startTime, info.duration, info.modRate)
end

-- The remaining time of a duration object, written into a font string.
--
-- The obvious route is C_DurationUtil.CreateDurationTextBinding, and that is
-- what the first draft of the cast bar used -- it produced no text at all in
-- the client. What DOES work, and is what Modules/Nameplates/CastBar has been
-- running on all along, is to format the object's own getter: the number is
-- secret, and string.format on a secret is allowed, so the engine writes a
-- time nobody read.
--
-- `host` owns the ticking. A hidden frame gets no OnUpdate, so a bar that is
-- not on screen costs nothing, and passing a nil duration stops it for good.
local function durationTick(host, elapsed)
    host._durWait = (host._durWait or 0) + elapsed
    if host._durWait < 0.05 then return end
    host._durWait = 0
    local fs, dur = host._durText, host._duration
    if not (fs and type(dur) ~= "nil") then
        host:SetScript("OnUpdate", nil)
        return
    end
    -- pcall, not a check: an object whose cast has ended can refuse the getter,
    -- and one refused frame must not take the handler down with it.
    if not pcall(fs.SetFormattedText, fs, "%.1f", dur:GetRemainingDuration()) then
        fs:SetText("")
        host:SetScript("OnUpdate", nil)
    end
end

function ns:DurationText(host, fontString, duration)
    if not (host and fontString) then return end
    host._durText = fontString
    host._duration = duration
    if type(duration) == "nil" then
        host:SetScript("OnUpdate", nil)
        fontString:SetText("")
        return
    end
    host:SetScript("OnUpdate", durationTick)
end

-- "Is there a value at all" for something that may be secret. Every other test
-- -- `if v then`, `v ~= nil` -- is a boolean test or a comparison and throws on
-- a secret; type() is the one question a secret answers.
function ns.Exists(v)
    return type(v) ~= "nil"
end

-- A two-way colour choice on a boolean that may be secret (a cast's
-- notInterruptible, a duration object's IsZero): the client picks per channel,
-- our code never sees which way it went. First colour when the boolean is true.
-- A plain boolean takes the ordinary branch, so callers need not care which
-- kind they hold.
local evalColor = C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean

function ns.FoldColor(bool, r1, g1, b1, r2, g2, b2)
    if not ns.IsSecret(bool) then
        if bool then return r1, g1, b1 end
        return r2, g2, b2
    end
    if not evalColor then return r2, g2, b2 end   -- cannot ask: never test a secret
    return evalColor(bool, r1, r2), evalColor(bool, g1, g2), evalColor(bool, b1, b2)
end

-- One channel of the same, for an alpha that hangs on two booleans in a row.
function ns.FoldValue(bool, ifTrue, ifFalse)
    if not ns.IsSecret(bool) then
        if bool then return ifTrue end
        return ifFalse
    end
    if not evalColor then return ifFalse end
    return evalColor(bool, ifTrue, ifFalse)
end

-- Show a region while the boolean is true. The setter's own defaults are
-- documented as 255/0, so both ends are passed.
function ns.AlphaFromBool(region, bool, alphaIfTrue, alphaIfFalse)
    if not region then return end
    alphaIfTrue, alphaIfFalse = alphaIfTrue or 1, alphaIfFalse or 0
    if ns.IsSecret(bool) then
        if region.SetAlphaFromBoolean then
            region:SetAlphaFromBoolean(bool, alphaIfTrue, alphaIfFalse)
        else
            region:SetAlpha(alphaIfFalse)
        end
    else
        region:SetAlpha(bool and alphaIfTrue or alphaIfFalse)
    end
end
