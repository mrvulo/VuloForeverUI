-- VuloForeverUI / Modules / Classes / Priest
--
-- Two arcs around the character, like brackets: ( you )
--
--   right  the shield. Its segments fill from the bottom; segment i is lit
--          while the absorb left is above (i-1)/n of the shield's size. The
--          lowest quarter turns red once the shield is down to it, the arc
--          flashes white when a hit is swallowed whole, and the number and
--          the time left stand under it.
--   left   Inner Fire, one segment per charge.
--
-- SECRETS. The absorb left (UnitGetTotalAbsorbs) is a secret value, in and
-- out of combat. It is never compared: every segment is a StatusBar of its
-- own whose range is the one step from "just below its threshold" to "at
-- it", and the bar is handed the secret. The client fills it or not. Absorbs
-- are whole numbers, so no bar ever stops half way. The number is the secret
-- turned into text by the client (empty at zero).
--
-- The shield's SIZE, which the thresholds need, is a plain number: out of
-- combat the shield's aura says what is left of it (the largest value seen
-- per shield is its size), and a shield cast in a fight takes the size this
-- rank had last time, or the size worked out from the rank's base values.
--
-- Aura data is not readable in a fight, and reading it there throws, so the
-- auras are read only outside of one. In a fight the charges of Inner Fire
-- are counted down by the hits that come through (UNIT_COMBAT: a physical
-- WOUND not absorbed, blocked or resisted -- its amount is secret), and the
-- time left of a shield ends when damage comes through it.
local _, ns = ...
local L = ns.L
local CL = ns.Classes

local TEXTURE = "Interface\\AddOns\\VuloForeverUI\\Media\\textures\\arc-segment.tga"
local FLASH_TIME = 0.25
local LOW_PART   = 0.25           -- the share of the arc that warns
local IF_CHARGES, IF_DURATION, PWS_DURATION = 20, 600, 30
local PREVIEW_VALUE = 1000000000  -- a plain number above every threshold

-- Power Word: Shield, every rank: base absorb, gain per level, from level,
-- up to level, spell level. Healing power adds a tenth.
local PWS = {
    [17]    = { 44,  0.8,  6, 11,  6 },
    [592]   = { 88,  1.2, 12, 17, 12 },
    [600]   = { 158, 1.6, 18, 23, 18 },
    [3747]  = { 234, 2.0, 24, 29, 24 },
    [6065]  = { 301, 2.3, 30, 35, 30 },
    [6066]  = { 381, 2.6, 36, 41, 36 },
    [10898] = { 484, 3.0, 42, 47, 42 },
    [10899] = { 605, 3.4, 48, 53, 48 },
    [10900] = { 763, 3.9, 54, 59, 54 },
    [10901] = { 942, 4.3, 60, 65, 60 },
    [27607] = { 942, 4.3, 60, 65, 60 },
}
local INNER_FIRE = {
    [588] = true, [7128] = true, [602] = true, [1006] = true, [10951] = true, [10952] = true,
}

local P = {
    maxBySpell = {},     -- spell id -> largest size seen of that rank
    maxByAura  = nil,    -- aura instance -> largest value seen of that shield
    size       = 0,      -- what the thresholds are cut from
}
CL.Priest = P

local function db() return CL.db("priest") end

local toText = C_StringUtil and C_StringUtil.TruncateWhenZero
local totalAbsorbs = UnitGetTotalAbsorbs

-- ---------------------------------------------------------------- frames --

local holder, mover, ticker, events
local shieldSegs, fireSegs = {}, {}
local numText, timeText
local painted, fireWhite, layoutCount

local function readNumber(v)
    if type(v) == "number" and ns.CanRead(v) then return v end
    return nil
end

local function previewing()
    return P.previewOpt or P.editPreview
end

-- Position (from the middle) and turn of segment i of n on the right arc;
-- segment 1 is the lowest. The left arc is its mirror image.
local function arcPoint(i, n, d)
    local t = (n > 1) and ((i - 1) / (n - 1) - 0.5) or 0
    local span = math.rad(d.curve or 0)
    if span < 0.005 then return d.distance, t * d.height, 0 end
    local radius = d.height / span
    local angle = t * span
    return d.distance + radius * (math.cos(angle) - 1), radius * math.sin(angle), angle
end

local function newGate()
    local bar = CreateFrame("StatusBar", nil, holder)
    bar:SetStatusBarTexture(TEXTURE)
    bar:GetStatusBarTexture():SetBlendMode("ADD")
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    return bar
end

local function build()
    if holder then return end
    holder = CreateFrame("Frame", nil, UIParent)
    holder:SetFrameStrata("LOW")
    holder:SetSize(240, 300)

    numText = holder:CreateFontString(nil, "OVERLAY")
    timeText = holder:CreateFontString(nil, "OVERLAY")
    timeText:SetPoint("TOP", numText, "BOTTOM", 0, -2)

    mover = ns:CreateMover(holder, {
        key      = "classes_priest",
        label    = L["Priest arcs"],
        db       = db().pos,
        module   = "classes",
        scalable = true,
        editPreview = function(on)
            P.editPreview = on and true or nil
            P.Refresh()
        end,
    })
end

-- Thresholds of the shield segments. Cut again whenever the size changes.
local function cutThresholds()
    local n = layoutCount or 0
    local size = P.size
    if not (size and size > 0) then size = 1 end
    local low = math.ceil(n * LOW_PART)
    local above = math.floor(low * size / n)
    for i = 1, n do
        local seg = shieldSegs[i]
        local t = math.floor((i - 1) * size / n)
        seg.gate:SetMinMaxValues(t + 0.99, t + 1)
        if seg.gate2 then seg.gate2:SetMinMaxValues(above + 0.99, above + 1) end
    end
end

-- Colours of the shield segments: normal, or white while flashing. A low
-- segment is drawn by two bars added together (both blend ADD): the warning
-- colour whenever the segment is lit, and the rest up to the normal colour
-- only while the shield is above the low part. Below it the second bar drops
-- out and the warning colour is left.
local function paintShield(flash)
    local d = db()
    local c, w = d.shieldColor, d.warnColor
    local n = layoutCount or 0
    local low = d.lowWarn and math.ceil(n * LOW_PART) or 0
    for i = 1, n do
        local seg = shieldSegs[i]
        if flash then
            seg.gate:SetStatusBarColor(1, 1, 1, 1)
            if seg.gate2 then seg.gate2:Hide() end
        elseif i <= low then
            local wr, wg, wb = math.min(w.r, c.r), math.min(w.g, c.g), math.min(w.b, c.b)
            seg.gate:SetStatusBarColor(wr, wg, wb, 1)
            if not seg.gate2 then
                seg.gate2 = newGate()
                seg.gate2:SetAllPoints(seg.gate)
                seg.gate2:GetStatusBarTexture():SetRotation(seg.angle or 0)
            end
            seg.gate2:SetStatusBarColor(c.r - wr, c.g - wg, c.b - wb, 1)
            seg.gate2:Show()
        else
            seg.gate:SetStatusBarColor(c.r, c.g, c.b, 1)
            if seg.gate2 then seg.gate2:Hide() end
        end
    end
    painted = flash and "flash" or "normal"
end

local function paintFire(white)
    local c = db().innerFireColor
    for i = 1, layoutCount or 0 do
        if white then fireSegs[i]:SetVertexColor(1, 1, 1, 1)
        else fireSegs[i]:SetVertexColor(c.r, c.g, c.b, 1) end
    end
    fireWhite = white
end

local function layout()
    local d = db()
    local n = math.max(3, math.floor(d.segments or 20))
    local s = d.segSize or 40
    for i = n + 1, #shieldSegs do
        shieldSegs[i].gate:Hide()
        if shieldSegs[i].gate2 then shieldSegs[i].gate2:Hide() end
        fireSegs[i]:Hide()
    end
    for i = 1, n do
        local seg = shieldSegs[i]
        if not seg then
            seg = { gate = newGate() }
            shieldSegs[i] = seg
            local tex = holder:CreateTexture(nil, "ARTWORK")
            tex:SetTexture(TEXTURE)
            fireSegs[i] = tex
        end
        local x, y, angle = arcPoint(i, n, d)
        seg.gate:SetSize(s, s)
        seg.gate:ClearAllPoints()
        seg.gate:SetPoint("CENTER", holder, "CENTER", x, y)
        seg.angle = angle
        seg.gate:GetStatusBarTexture():SetRotation(angle)
        if seg.gate2 then seg.gate2:GetStatusBarTexture():SetRotation(angle) end
        seg.gate:Show()
        local tex = fireSegs[i]
        tex:SetSize(s, s)
        tex:ClearAllPoints()
        tex:SetPoint("CENTER", holder, "CENTER", -x, y)
        tex:SetRotation(-angle)
    end
    layoutCount = n

    holder:SetSize(2 * (d.distance + s / 2), d.height + s)
    holder:SetAlpha(d.alpha or 1)

    local bx, by = arcPoint(1, n, d)
    numText:ClearAllPoints()
    numText:SetPoint("TOP", holder, "CENTER", bx, by - s * 0.3)
    ns.UI.TextShadow(numText, true)
    ns.UI.FontFor("classes", numText, d.numberSize or 20, "OUTLINE")
    ns.UI.TextShadow(timeText, true)
    ns.UI.FontFor("classes", timeText, math.max(8, (d.numberSize or 20) - 7), "OUTLINE")
    local c = d.shieldColor
    numText:SetTextColor(c.r, c.g, c.b, 1)
    timeText:SetTextColor(c.r, c.g, c.b, 0.85)

    paintShield(false)      -- first: it creates the second bars ...
    cutThresholds()         -- ... which need their range as well
    paintFire(false)

    if mover then
        mover.opts.db = d.pos
        ns:ApplyMover(mover)
    end
end

-- ---------------------------------------------------------------- reading --

local function size(spellID)
    local known = P.maxBySpell[spellID]
    if known then return known end
    local r = PWS[spellID]
    if not r then return nil end
    local level = readNumber(UnitLevel("player")) or 0
    local value = r[1] + math.max(0, math.min(level, r[4]) - r[3]) * r[2]
    local bonus = GetSpellBonusHealing and readNumber(GetSpellBonusHealing())
    if bonus then
        value = value + bonus * 0.1 * math.min(1, 1 - (20 - r[5]) * 0.03)
    end
    return math.floor(value + 0.5)
end

-- In a fight, and at its very first hit, the aura data is secret and a read
-- throws. The lockdown flag alone comes too late for that first hit.
local function aurasLocked()
    if InCombatLockdown() then return true end
    local fighting = UnitAffectingCombat("player")
    if ns.IsSecret(fighting) or fighting then return true end
    return ns.AurasRestricted()
end

local function scan()
    if aurasLocked() then return end
    local old = P.maxByAura
    local mayBeUsed = P.mayBeUsed or old == nil
    old = old or {}
    P.mayBeUsed = nil
    local fresh, total, ends = {}, 0, nil
    local fireFound, fireCharges, fireEnds = false, nil, nil

    for i = 1, 40 do
        -- One buff can be secret while the rest are not; the read throws then.
        local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
        if not (ok and a) then break end
        local id = readNumber(a.spellId)
        if id and PWS[id] then
            local amount = a.points and readNumber(a.points[1])
            local key = readNumber(a.auraInstanceID) or id
            if amount and amount > 0 then
                local m = old[key]
                if not m then
                    m = amount
                    local known = P.maxBySpell[id]
                    if mayBeUsed and known and known > m then m = known end
                elseif amount > m then
                    m = amount
                end
                fresh[key] = m
                local known = P.maxBySpell[id]
                if not (mayBeUsed and old[key] == nil and known and known > m) then
                    P.maxBySpell[id] = m
                end
                total = total + m
                local e = readNumber(a.expirationTime)
                if e and e > 0 and (not ends or e < ends) then ends = e end
            end
        elseif id and INNER_FIRE[id] then
            fireFound = true
            local ch = readNumber(a.applications)
            if ch and ch > 0 then fireCharges = ch end
            local e = readNumber(a.expirationTime)
            if e and e > 0 then fireEnds = e end
        end
    end
    P.maxByAura = fresh

    local now = GetTime()
    if total > 0 then
        if total ~= P.size then P.size = total; cutThresholds() end
        P.shieldEnds = ends
    else
        P.shieldEnds = nil
        if now - (P.castAt or 0) > 2 then P.castEnds = nil end
    end
    if fireFound then
        P.fireCharges = fireCharges or P.fireCharges or IF_CHARGES
        P.fireEnds = fireEnds or P.fireEnds
    elseif now - (P.fireCastAt or 0) > 2 then
        P.fireCharges, P.fireEnds = nil, nil
    end
end

local function onCast(spellID)
    local id = readNumber(spellID)
    if not id then return end
    local now = GetTime()
    if INNER_FIRE[id] then
        P.fireCharges, P.fireEnds, P.fireCastAt = IF_CHARGES, now + IF_DURATION, now
    elseif PWS[id] then
        local m = size(id)
        if m and m > 0 and m ~= P.size then P.size = m; cutThresholds() end
        P.castEnds, P.castAt, P.shieldEnds, P.fillSeen = now + PWS_DURATION, now, nil, false
        -- Out of a fight the aura says it better, once it is there.
        ns.NextFrame(scan)
    end
end

local function onHit(action, flag, amount, school)
    local d = db()
    local now = GetTime()
    if ns.CanRead(flag) and flag == "ABSORB" and d.flashHit then
        P.flashUntil = now + FLASH_TIME
    end
    if not (ns.CanRead(action) and action == "WOUND") then return end
    -- The amount is secret in every payload (client docs). A WOUND without
    -- one of these flags is a hit that came through, as in the client's own
    -- combat text; where the amount is readable it decides.
    local dmg = readNumber(amount)
    if dmg then
        if dmg <= 0 then return end
    elseif not ns.CanRead(flag) or flag == "ABSORB" or flag == "BLOCK" or flag == "RESIST" then
        return
    end
    -- A charge of Inner Fire goes with every physical hit that comes through.
    if P.fireCharges and ns.CanRead(school) and school == 1 then
        P.fireCharges = math.max(P.fireCharges - 1, 0)
        if d.innerFireFlash then P.fireFlashUntil = now + FLASH_TIME end
    end
    -- Damage through the shield means it is gone, and its time with it.
    if P.castEnds and now - (P.castAt or 0) > 0.5 then
        P.castEnds, P.shieldEnds = nil, nil
    end
end

-- ---------------------------------------------------------------- drawing --

local function clock(left)
    if left >= 60 then return string.format("%d:%02d", math.floor(left / 60), math.floor(left % 60)) end
    return string.format("%ds", math.ceil(left))
end

local function update()
    if not holder then return end
    local d = db()
    local now = GetTime()
    local preview = previewing()
    local n = layoutCount or 0

    -- the shield
    -- Never `x or 0` here: a boolean test on a secret throws.
    local value
    if preview then value = PREVIEW_VALUE
    elseif totalAbsorbs then value = totalAbsorbs("player") end
    if type(value) == "nil" then value = 0 end
    local flash = (not preview) and P.flashUntil and now < P.flashUntil and true or false
    if (flash and "flash" or "normal") ~= painted then paintShield(flash) end
    for i = 1, n do
        local seg = shieldSegs[i]
        if d.shield then
            seg.gate:Show()
            seg.gate:SetValue(value)
            if seg.gate2 and seg.gate2:IsShown() then seg.gate2:SetValue(value) end
        else
            seg.gate:Hide()
            if seg.gate2 then seg.gate2:Hide() end
        end
    end

    -- Is the lowest bar empty? Its fill has a size of its own; where the
    -- client lets us read it, an empty shield ends the time left at once.
    local empty = false
    local fill = shieldSegs[1] and shieldSegs[1].gate:GetStatusBarTexture()
    local w = fill and readNumber(fill:GetWidth())
    if w and not preview then
        if w > 0.5 then P.fillSeen = true
        elseif w < 0.01 and P.fillSeen then empty = true end
    end

    if d.shield and d.shieldNumber then
        if preview then numText:SetText("1234")
        elseif toText then numText:SetText(toText(value))
        else numText:SetText("") end
        numText:Show()
    else
        numText:Hide()
    end
    local text = ""
    if d.shield and d.shieldTime then
        if preview then
            text = clock(PWS_DURATION)
        elseif not empty then
            local ends = P.shieldEnds
            if not (ends and ends > now) then ends = P.castEnds end
            local left = ends and (ends - now)
            if left and left > 0 then text = clock(left) end
        end
    end
    timeText:SetText(text)

    -- Inner Fire
    local charges = P.fireCharges
    local on = d.innerFire and charges and charges > 0 and not (P.fireEnds and now >= P.fireEnds)
    if preview and d.innerFire then on, charges = true, IF_CHARGES end
    local white = (not preview) and P.fireFlashUntil and now < P.fireFlashUntil and true or false
    if white ~= fireWhite then paintFire(white) end
    local lit = on and math.ceil(math.min(charges, IF_CHARGES) * n / IF_CHARGES) or 0
    for i = 1, n do
        if i <= lit then fireSegs[i]:Show() else fireSegs[i]:Hide() end
    end
end

-- ---------------------------------------------------------------- module --

local EVENTS = {
    "UNIT_AURA", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_COMBAT",
}

local function onEvent(_, event, unit, a1, a2, a3, a4)
    if event == "UNIT_AURA" then scan()
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then onCast(a2)
    elseif event == "UNIT_COMBAT" then onHit(a1, a2, a3, a4)
    elseif event == "PLAYER_REGEN_DISABLED" then P.mayBeUsed = true
    else scan() end
end

function P.Refresh()
    if holder and holder:IsShown() then update() end
end

local function enable()
    build()
    if not events then
        events = CreateFrame("Frame")
        events:SetScript("OnEvent", onEvent)
    end
    for _, e in ipairs(EVENTS) do events:RegisterUnitEvent(e, "player") end
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
    events:RegisterEvent("PLAYER_REGEN_DISABLED")
    layout()
    holder:Show()
    scan()
    if not ticker then ticker = ns:AddTicker(0.1, update, nil, "priest arcs") end
    update()
end

local function disable()
    if events then events:UnregisterAllEvents() end
    if ticker then ns:CancelTicker(ticker); ticker = nil end
    if holder then holder:Hide() end
end

local function apply()
    if not holder then return end
    layout()
    update()
end

local function spellName(id, fallback)
    local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
    return name or fallback
end

local function options(rows)
    local t, c = rows.toggle, rows.color
    return {
        { type = "header", text = spellName(17, L["Shield"]) },
        t("shield", L["Show the shield arc"],
            L["Right of the character. Fills from the bottom with the absorb left; works in a fight too."]),
        t("shieldNumber", L["Show the number"]),
        t("shieldTime", L["Show the time left"]),
        t("lowWarn", L["Warn when the shield runs low"],
            L["The lowest quarter of the arc turns to the warning colour once the shield is down to it."]),
        t("flashHit", L["Flash when a hit is absorbed"]),
        c("shieldColor", L["Shield color"]),
        c("warnColor", L["Warning color"]),
        { type = "header", text = spellName(588, L["Inner Fire"]) },
        t("innerFire", L["Show the Inner Fire arc"],
            L["Left of the character, one segment per charge. In a fight every physical hit that comes through takes one off."]),
        t("innerFireFlash", L["Flash when a charge is lost"]),
        c("innerFireColor", L["Inner Fire color"]),
        { type = "header", text = L["Shape"] },
        rows.slider("segments", L["Segments"], 6, 40, 1),
        rows.slider("segSize", L["Segment size"], 16, 96, 1),
        rows.slider("distance", L["Distance from the middle"], 20, 500, 1),
        rows.slider("height", L["Height"], 60, 700, 5),
        rows.slider("curve", L["Curve"], 0, 90, 1),
        rows.slider("numberSize", L["Text size"], 8, 40, 1),
        rows.opacity("alpha", L["Opacity"], { min = 10 }),
        { type = "toggle", label = L["Show a preview"],
          tooltip = L["Both arcs full until you turn this off. Move them in the Edit Mode."],
          get = function() return P.previewOpt and true or false end,
          set = function(_, v) P.previewOpt = v and true or nil; P.Refresh() end },
    }
end

CL.Register("PRIEST", {
    tab     = "priest",
    label   = "Priest",
    Enable  = enable,
    Disable = disable,
    Apply   = apply,
    Options = options,
})
