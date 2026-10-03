-- VuloForeverUI / Core / SecretReport
--
-- /vfsecrets: the runtime half of Core/Secret.lua. The source says which APIs
-- exist; only the running client says which of their values we may read, and
-- the answer differs out of combat, in combat and in a raid.
local _, ns = ...

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

-- What a value is to us right now, coloured for the report.
local function state(v)
    local R = ns.C.r
    if type(v) == "nil" then return "nil" end
    if not ns.IsSecret(v) then return ns.C.pos .. "readable" .. R end
    if ns.CanRead(v) then return ns.C.yellow .. "secret, accessible" .. R end
    return ns.C.neg .. "secret" .. R
end

-- One report line. Every probe runs in its own pcall: the aura API THROWS when
-- restricted (seen 2026-09-18), and one throw must not eat the rest of the report.
local function probe(label, fn)
    local ok, res = pcall(fn)
    if ok then
        ns:Print("  %-26s%s", label, res)
    else
        ns:Print("  %-26s%sthrows:%s %s", label, ns.C.neg, ns.C.r, tostring(res))
    end
end

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

    ns:Print("%sForever secret-value report%s — combat: %s%s", A, R,
        InCombatLockdown() and "yes" or "no",
        restrictionsForced() and (ns.C.yellow .. "  (restrictions FORCED by CVar)" .. R) or "")

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

    -- The quest marker on the plates reads the unit's tooltip lines; whether
    -- that works in a fight decides whether a mob met mid-fight gets its
    -- marker at once or only after it.
    probe("tooltip lines (target)", function()
        if not hasTarget then return "no target" end
        local info = C_TooltipInfo and C_TooltipInfo.GetUnit and C_TooltipInfo.GetUnit("target", true)
        local lines = type(info) == "table" and info.lines
        if type(lines) ~= "table" then return ns.C.neg .. "no data" .. R end
        local types = Enum.TooltipDataLineType
        local n, hidden, quest = 0, 0, 0
        for _, line in ipairs(lines) do
            n = n + 1
            local kind = line.type
            if not ns.CanRead(kind) then
                hidden = hidden + 1
            elseif kind == types.QuestTitle or kind == types.QuestObjective then
                quest = quest + 1
            end
        end
        return string.format("%d lines, %s%d unreadable%s, %d quest", n,
            hidden > 0 and ns.C.neg or ns.C.pos, hidden, R, quest)
    end)

    -- What the quest progress on the plates is read from: the target's first
    -- objective line, its text and its two counts, each readable or not.
    probe("quest objective (target)", function()
        if not hasTarget then return "no target" end
        local info = C_TooltipInfo and C_TooltipInfo.GetUnit and C_TooltipInfo.GetUnit("target", true)
        local lines = type(info) == "table" and info.lines
        if type(lines) ~= "table" then return ns.C.neg .. "no data" .. R end
        local kindObjective = Enum.TooltipDataLineType.QuestObjective
        for _, line in ipairs(lines) do
            local kind = line.type
            if ns.CanRead(kind) and kind == kindObjective then
                local function show(v)
                    if not ns.CanRead(v) then return ns.C.neg .. "secret" .. R end
                    if type(v) == "nil" then return "nil" end
                    return tostring(v)
                end
                return string.format("text=%s have=%s need=%s done=%s", show(line.leftText),
                    show(line.numFulfilled), show(line.numRequired), show(line.completed))
            end
        end
        return "no objective line"
    end)

    -- The combat log is the hard stop, and the reason five VuloClassicUI
    -- modules cannot come across as they are.
    local ccl = _G.C_CombatLog
    ns:Print("  combat log for addons   %s",
        (ccl and ccl.GetCurrentEventInfo) and (ns.C.pos .. "available" .. R)
                                          or (ns.C.neg .. "not available" .. R))
end
