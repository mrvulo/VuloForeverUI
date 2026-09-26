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

-- Diagnostics. Prints what is readable right now, which is the one question the
-- API documentation cannot answer -- run it standing still, then again mid-fight
-- and in a raid, because the answers differ per restriction state.
ns:RegisterSlash({ key = "SECRETS", commands = { "/vfsecrets" },
    desc = "Report which combat values this client lets the addon read right now.",
    note = "Run it out of combat, in combat, and in a raid: the answers differ. "
        .. "'/vfsecrets force' toggles the client's simulated combat restrictions. "
        .. "'/vfsecrets np' reports what a nameplate may read about your target.",
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

-- "/vfsecrets np": what a nameplate module may read about the TARGET. Its own
-- report because it needs a target with a plate (ideally one that is casting)
-- and answers different questions: which display paths the client accepts.
-- Interrupt candidates by their classic spell ids; the report says which one
-- this client knows, the nameplate cast bar takes its list from that answer.
-- Kept in step with Modules/Nameplates/Kick.lua: every rank, because a
-- Classic-shaped spellbook gives each rank its own id.
local KICK_CANDIDATES = {
    1769, 1768, 1767, 1766, 1672, 1671, 72, 6554, 6552, 2139,
    10414, 10413, 10412, 8046, 8045, 8044, 8042, 15487, 16979,
}
local KICK_PET_CANDIDATES = { 19647, 19244 }

local NP_CVARS = {
    "nameplateMinScale", "nameplateMaxScale", "nameplateSelectedScale",
    "nameplateMinAlpha", "nameplateMaxAlpha", "nameplateMaxAlphaDistance",
    "nameplateMinAlphaDistance", "nameplateOverlapH", "nameplateOverlapV",
    "nameplateOccludedAlphaMult", "nameplateStackingTypes", "nameplateShowAll",
    "nameplateShowEnemies", "nameplateShowEnemyPets", "nameplateShowClassColor",
    "ShowClassColorInNameplate", "nameplateMaxDistance",
}

local scratchText
local scratchCooldown

local function nameplateReport()
    local A, R = ns.C.accent, ns.C.r
    local function state(v)
        if type(v) == "nil" then return "nil" end
        if not ns.IsSecret(v) then return ns.C.pos .. "readable" .. R end
        if ns.CanRead(v) then return ns.C.yellow .. "secret, accessible" .. R end
        return ns.C.neg .. "secret" .. R
    end
    local function probe(label, fn)
        local ok, res = pcall(fn)
        if ok then
            ns:Print("  %-26s%s", label, res)
        else
            ns:Print("  %-26s%sthrows:%s %s", label, ns.C.neg, R, tostring(res))
        end
    end
    local function accepted() return ns.C.pos .. "accepted" .. R end

    if not UnitExists("target") then
        ns:Print("Target something with a nameplate first -- best a mob that is casting.")
        return
    end
    ns:Print("%sNameplate report%s — combat: %s%s", A, R, InCombatLockdown() and "yes" or "no",
        restrictionsForced() and (ns.C.yellow .. "  (restrictions FORCED)" .. R) or "")

    -- 1. Text from a secret number: the health text and the cast timer hang on it.
    scratchText = scratchText or UIParent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    scratchText:Hide()
    probe("globals", function()
        return ("CurveConstants %s, AbbreviateNumbers %s, GetCreatureDifficultyColor %s"):format(
            tostring(_G.CurveConstants ~= nil), tostring(_G.AbbreviateNumbers ~= nil),
            tostring(_G.GetCreatureDifficultyColor ~= nil))
    end)
    probe("SetFormattedText(%d%%)", function()
        local scale = _G.CurveConstants and _G.CurveConstants.ScaleTo100
        scratchText:SetFormattedText("%d%%", UnitHealthPercent("target", true, scale))
        return accepted()
    end)
    probe("string.format(secret)", function()
        local s = string.format("%d", UnitHealth("target"))
        return accepted() .. ", result " .. state(s)
    end)
    probe("AbbreviateNumbers(secret)", function()
        scratchText:SetText(AbbreviateNumbers(UnitHealth("target")))
        return accepted()
    end)

    -- 2. Cast info, field by field. Only meaningful while the target casts.
    probe("UnitCastingInfo(target)", function()
        local name, text, texture, startMS, endMS, isTrade, castID, notInt, spellID = UnitCastingInfo("target")
        if type(name) == "nil" then
            name, text, texture, startMS, endMS, isTrade, notInt, spellID = UnitChannelInfo("target")
            if type(name) == "nil" then return "not casting" end
        end
        return ("name %s, texture %s, start %s, notInterruptible %s, spellID %s"):format(
            state(name), state(texture), state(startMS), state(notInt), state(spellID))
    end)
    probe("UnitCastingDuration", function()
        local d = UnitCastingDuration("target")
        if type(d) == "nil" then d = UnitChannelDuration("target") end
        return type(d) == "nil" and "nil (not casting?)" or ("object, " .. state(d))
    end)
    -- The cast bar calls these on the object; a refusal here is a refusal there.
    probe("duration getters", function()
        local d = UnitCastingDuration("target")
        if type(d) == "nil" then d = UnitChannelDuration("target") end
        if type(d) == "nil" then return "not casting" end
        scratchText:SetFormattedText("%.1f", d:GetRemainingDuration())
        return ("remaining %s, elapsed %s, total %s -- timer text %s"):format(
            state(d:GetRemainingDuration()), state(d:GetElapsedDuration()),
            state(d:GetTotalDuration()), accepted())
    end)

    -- 3. Geometry setters, fed their own current values so nothing changes.
    --
    -- NOT called in combat, and this is the whole lesson of 2026-09-20: these
    -- are PROTECTED functions. A protected call from tainted code in combat
    -- raises no Lua error at all -- the client fires ADDON_ACTION_BLOCKED and
    -- does nothing -- so the pcall around it returns TRUE and an earlier
    -- version of this report cheerfully printed "accepted" for a call that had
    -- just been refused. Never let a pcall stand in for "this worked" on a
    -- protected function.
    if InCombatLockdown() then
        ns:Print("  %-26s%sprotected, not called in combat%s", "plate geometry", ns.C.yellow, R)
    else
        probe("SetNamePlateSize", function()
            local w, h = C_NamePlate.GetNamePlateSize()
            C_NamePlate.SetNamePlateSize(w, h)
            return accepted() .. (" (%dx%d)"):format(w, h)
        end)
        probe("SetNamePlateHitTestInsets", function()
            local t = Enum.NamePlateType.Enemy
            local l, r, top, b = C_NamePlateManager.GetNamePlateHitTestInsets(t)
            C_NamePlateManager.SetNamePlateHitTestInsets(t, l, r, top, b)
            return accepted()
        end)
    end

    -- 4. What the colour chain and the text slots read.
    -- The VALUE too, in brackets: a nameplate showed "Wilde_der_Staubschwingen"
    -- where the chat log says "Wilde der Staubschwingen", so the question is
    -- whether the client hands out underscores or our FontString draws them.
    -- Forever also returns TWO values here (main, secondary), so both are shown.
    probe("UnitName", function()
        local main, second = UnitName("target")
        if not ns.CanRead(main) then return state(main) end
        return ("%s  [%s]%s"):format(state(main), tostring(main),
            ns.Exists(second) and ("  second [" .. tostring(second) .. "]") or "")
    end)
    probe("UnitClass", function() return state((select(2, UnitClass("target")))) end)
    probe("UnitClassification", function() return state(UnitClassification("target")) end)
    probe("UnitEffectiveLevel", function() return state(UnitEffectiveLevel("target")) end)
    probe("UnitReaction", function() return state(UnitReaction("target", "player")) end)
    probe("UnitIsTapDenied", function() return state(UnitIsTapDenied("target")) end)
    probe("UnitAffectingCombat", function() return state(UnitAffectingCombat("target")) end)
    probe("UnitThreatSituation", function() return state(UnitThreatSituation("player", "target")) end)
    probe("GetRaidTargetIndex", function() return state(GetRaidTargetIndex("target")) end)
    probe("UnitGetTotalAbsorbs", function() return state(UnitGetTotalAbsorbs("target")) end)
    probe("UnitGroupRolesAssigned", function() return tostring(UnitGroupRolesAssigned("player")) end)
    probe("plate token vs target", function()
        local plate = C_NamePlate.GetNamePlateForUnit("target")
        if not plate then return "target has no plate" end
        -- The base plate keeps its unit in .unitToken / :GetUnit(); the retail
        -- name .namePlateUnitToken does NOT exist here (client, 2026-09-20).
        local token = (plate.GetUnit and plate:GetUnit()) or plate.unitToken or plate.namePlateUnitToken
        if type(token) ~= "string" then
            return ("no token (GetUnit %s, .unitToken %s, .namePlateUnitToken %s)"):format(
                tostring(plate.GetUnit and plate:GetUnit()), tostring(plate.unitToken),
                tostring(plate.namePlateUnitToken))
        end
        return ("%s, UnitIsUnit %s"):format(token, state(UnitIsUnit(token, "target")))
    end)
    probe("hidden bar colour", function()
        local plate = C_NamePlate.GetNamePlateForUnit("target")
        local hb = plate and plate.UnitFrame and plate.UnitFrame.healthBar
            or plate and plate.UnitFrame and plate.UnitFrame.HealthBarsContainer
               and plate.UnitFrame.HealthBarsContainer.healthBar
        if not hb then return "no Blizzard health bar" end
        return state((hb:GetStatusBarColor()))
    end)

    -- 5. Which CVars this client has at all.
    local have, missing = {}, {}
    for _, name in ipairs(NP_CVARS) do
        local ok, v = pcall(C_CVar.GetCVar, name)
        table.insert((ok and v ~= nil) and have or missing, name)
    end
    ns:Print("  cvars present: %s", table.concat(have, ", "))
    ns:Print("  cvars %smissing%s: %s", ns.C.neg, R, #missing > 0 and table.concat(missing, ", ") or "none")

    -- 6. The player's interrupt. Each candidate id is printed with the name
    -- the client gives it: an id that resolves to nothing (or to the wrong
    -- spell) is a wrong id, an id that resolves but is not known is simply a
    -- spell this character does not have. Forever renumbers some spells.
    local _, playerClass = UnitClass("player")
    ns:Print("  interrupt candidates (%s, level %d):", tostring(playerClass), UnitLevel("player") or 0)
    local found, foundBank
    for i = 1, #KICK_CANDIDATES + #KICK_PET_CANDIDATES do
        local pet = i > #KICK_CANDIDATES
        local id = pet and KICK_PET_CANDIDATES[i - #KICK_CANDIDATES] or KICK_CANDIDATES[i]
        local bank = pet and Enum.SpellBookSpellBank.Pet or Enum.SpellBookSpellBank.Player
        local okName, name = pcall(C_Spell.GetSpellName, id)
        local okKnown, known = pcall(C_SpellBook.IsSpellKnownOrInSpellBook, id, bank)
        if okKnown and known and not found then found, foundBank = id, bank end
        ns:Print("    %-6d %-22s %s%s", id, (okName and name) or (ns.C.neg .. "no such spell" .. R),
            (okKnown and known) and (ns.C.pos .. "known" .. R) or "not known", pet and "  (pet book)" or "")
    end
    probe("interrupt cooldown", function()
        if not found then return "no interrupt known -- kick colour and tick stay off" end
        local d = C_Spell.GetSpellCooldownDuration(found)
        local zero
        if type(d) ~= "nil" then zero = d:IsZero() end
        return ("%d, duration %s, IsZero %s"):format(found,
            type(d) == "nil" and "nil" or "object", state(zero))
    end)
end

-- "/vfsecrets cd": what a cooldown module may build on. Two questions decide
-- the whole design. Does the client's own cooldown viewer carry any data for
-- a Forever spec (static analysis says its category sets come back empty, so
-- the spell list would have to come from the spellbook instead), and does a
-- duration object reach a Cooldown widget and keep ticking once a fight has
-- started. Run it standing still, then again mid-fight.
local function cooldownReport()
    local A, R = ns.C.accent, ns.C.r
    local function state(v)
        if type(v) == "nil" then return "nil" end
        if not ns.IsSecret(v) then return ns.C.pos .. "readable" .. R end
        if ns.CanRead(v) then return ns.C.yellow .. "secret, accessible" .. R end
        return ns.C.neg .. "secret" .. R
    end
    local function probe(label, fn)
        local ok, res = pcall(fn)
        if ok then
            ns:Print("  %-26s%s", label, res)
        else
            ns:Print("  %-26s%sthrows:%s %s", label, ns.C.neg, R, tostring(res))
        end
    end

    ns:Print("%sCooldown report%s — combat: %s%s", A, R, InCombatLockdown() and "yes" or "no",
        restrictionsForced() and (ns.C.yellow .. "  (restrictions FORCED)" .. R) or "")

    -- 1. The client's own viewer: is there anything in it for this spec?
    local CV = _G.C_CooldownViewer
    probe("C_CooldownViewer", function()
        return CV and (ns.C.pos .. "present" .. R) or (ns.C.neg .. "MISSING" .. R)
    end)
    if CV then
        probe("IsCooldownViewerAvailable", function()
            local ok, why = CV.IsCooldownViewerAvailable()
            return ("%s%s"):format(tostring(ok), (not ok and why and why ~= "") and ("  (" .. why .. ")") or "")
        end)
        local cats = Enum.CooldownViewerCategory or {}
        local names = {}
        for name, value in pairs(cats) do names[#names + 1] = { name = name, value = value } end
        table.sort(names, function(a, b) return a.value < b.value end)
        for _, c in ipairs(names) do
            probe("category " .. c.name, function()
                local known = CV.GetCooldownViewerCategorySet(c.value, false)
                local all   = CV.GetCooldownViewerCategorySet(c.value, true)
                local n1 = type(known) == "table" and #known or -1
                local n2 = type(all) == "table" and #all or -1
                local first = ""
                if n1 > 0 then
                    local info = CV.GetCooldownViewerCooldownInfo(known[1])
                    local sid = info and info.spellID
                    first = ("  first: %s %s"):format(tostring(sid),
                        (sid and C_Spell.GetSpellName(sid)) or "?")
                end
                return ("known %d, with unlearned %d%s"):format(n1, n2, first)
            end)
        end
        probe("GetGroupBuffItems", function()
            local t = CV.GetGroupBuffItems()
            return ("%d entries"):format(type(t) == "table" and #t or -1)
        end)
    end

    -- 2. The spellbook, the fallback source for the spell list.
    local firstSpell
    probe("spellbook", function()
        local lines = C_SpellBook.GetNumSpellBookSkillLines()
        local total, known = 0, 0
        for i = 1, lines do
            local info = C_SpellBook.GetSpellBookSkillLineInfo(i)
            if info then
                for s = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
                    total = total + 1
                    local item = C_SpellBook.GetSpellBookItemInfo(s, Enum.SpellBookSpellBank.Player)
                    if item and item.spellID and not item.isPassive then
                        known = known + 1
                        if not firstSpell and item.actionID then firstSpell = item.spellID end
                    end
                end
            end
        end
        return ("%d skill lines, %d items, %d active spells"):format(lines, total, known)
    end)

    -- 3. The display path: duration object into a Cooldown widget of our own.
    scratchCooldown = scratchCooldown or CreateFrame("Cooldown", nil, UIParent, "CooldownFrameTemplate")
    scratchCooldown:Hide()
    probe("GetSpellCooldownDuration", function()
        if not firstSpell then return "no active spell found" end
        local d = C_Spell.GetSpellCooldownDuration(firstSpell)
        if type(d) == "nil" then return "nil" end
        return ("%s (%s), IsZero %s"):format(C_Spell.GetSpellName(firstSpell) or "?",
            type(d), state(d:IsZero()))
    end)
    probe("SetCooldownFromDurationObject", function()
        if not firstSpell then return "no active spell found" end
        local d = C_Spell.GetSpellCooldownDuration(firstSpell)
        if type(d) == "nil" then return "no duration object" end
        if not scratchCooldown.SetCooldownFromDurationObject then return ns.C.neg .. "method missing" .. R end
        scratchCooldown:SetCooldownFromDurationObject(d)
        return ns.C.pos .. "accepted" .. R
    end)
    probe("spellbook duration object", function()
        if not C_SpellBook.GetSpellBookItemCooldownDuration then return "method missing" end
        local d = C_SpellBook.GetSpellBookItemCooldownDuration(1, Enum.SpellBookSpellBank.Player)
        return type(d) == "nil" and "nil" or "object"
    end)
    probe("charges", function()
        if not firstSpell then return "no active spell found" end
        local c = C_Spell.GetSpellCharges(firstSpell)
        if type(c) == "nil" then return "nil (spell has no charges)" end
        return ("current %s, max %s"):format(state(c.currentCharges), state(c.maxCharges))
    end)

    -- 4. The widgets a bar display would need.
    probe("C_DurationUtil", function()
        local D = _G.C_DurationUtil
        return ("CreateDuration %s, StatusBar:SetTimerDuration %s"):format(
            tostring(D and D.CreateDuration ~= nil),
            tostring(UIParent.SetTimerDuration ~= nil or CreateFrame("StatusBar").SetTimerDuration ~= nil))
    end)
    probe("AuraContainer widget", function()
        local ok = pcall(CreateFrame, "AuraContainer", nil, UIParent)
        return ok and (ns.C.pos .. "creatable" .. R) or (ns.C.neg .. "not available" .. R)
    end)
    probe("restricted: cooldowns", function() return tostring(ns.CooldownsRestricted()) end)
end

ns.Slash.SECRETS = function(msg)
    local A, R = ns.C.accent, ns.C.r
    if (msg or ""):lower():match("^%s*cd") then
        cooldownReport()
        return
    end
    if (msg or ""):lower():match("^%s*np") then
        nameplateReport()
        return
    end
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
