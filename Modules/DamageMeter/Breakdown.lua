-- VuloForeverUI / Modules / DamageMeter / Breakdown
--
-- What one row is made of. Three flavours, because the client tracks three
-- different things:
--   ordinary types   the source's spells, one bar each
--   Deaths           the death recap: the last events before the player died,
--                    the fill showing the health that was left
--   Enemy Damage     which players hit this enemy, summed per player
--
-- Two presentations of the same content: the panel that takes over the window
-- when a row is clicked, and the floating preview on hover. Both are built by
-- BuildEntries, so they can never disagree.
--
-- The recap event fields are undocumented (deliberately -- they can come back
-- secret mid-fight), so every read here is either guarded before Lua touches
-- the value or passed whole into a widget setter.
local _, ns = ...
local L  = ns.L
local DM = ns.DM
local UI = ns.UI

local FALLBACK_ICON = 134400   -- INV_Misc_QuestionMark

-- ---------------------------------------------------------------- entries --

-- One list of rows for either presentation:
--   { icon, label, amount, fillValue, fillMax, r, g, b, spellID }
-- Nothing in here is compared or computed on unless it read plain.

local function spellEntries(W, source)
    local spells = source and source.combatSpells
    if type(spells) ~= "table" then return nil end
    local out = {}
    -- No `or` anywhere near these: every one of them is secret in combat, and
    -- a boolean test on a secret throws.
    local maxAmt = source.maxAmount
    if type(maxAmt) == "nil" then
        if spells[1] and type(spells[1].totalAmount) ~= "nil" then maxAmt = spells[1].totalAmount else maxAmt = 1 end
    end
    local total = source.totalAmount
    local canPercent = DM.Plain(total) and type(total) == "number" and total > 0
    local fmt = DM.db().numberFormat or 2
    for i = 1, #spells do
        local sp = spells[i]
        local id = sp.spellID
        local icon = FALLBACK_ICON
        local name
        if type(id) ~= "nil" then
            -- Both take a secret id and hand back a secret answer, so the
            -- result is tested with type(), never with `or`.
            local tex = C_Spell.GetSpellTexture(id)
            if type(tex) ~= "nil" then icon = tex end
            name = C_Spell.GetSpellName(id)
        end
        if type(name) == "nil" or (DM.Plain(name) and name == "") then name = L["Unknown"] end
        -- A pet's casts carry the creature that did them.
        local creature = sp.creatureName
        if DM.Plain(creature) and creature ~= "" then
            name = ("%s (%s)"):format(name, creature)
        end
        local amountText
        if canPercent and DM.Plain(sp.totalAmount) and type(sp.totalAmount) == "number" then
            amountText = ("%s  %.0f%%"):format(DM.Abbrev(sp.totalAmount), sp.totalAmount / total * 100)
        else
            amountText = DM.FormatValue(sp.totalAmount, sp.amountPerSecond, fmt)
        end
        local value = sp.totalAmount
        if type(value) == "nil" then value = 0 end
        out[#out + 1] = {
            icon = icon, label = name, amount = amountText,
            fillValue = value, fillMax = maxAmt,
            spellID = DM.Plain(id) and id or nil,
        }
    end
    return out
end

-- Enemy Damage Taken: who hit this enemy. The per-target detail carries the
-- player that dealt each spell's damage, so the sum is per unit name. Only
-- plain names can be used as a table key, which is why this needs readable
-- data and simply reports nothing while restricted.
local function enemyEntries(W, source)
    local spells = source and source.combatSpells
    if type(spells) ~= "table" then return nil end
    local byName, order = {}, {}
    for i = 1, #spells do
        local sp = spells[i]
        local det = sp.combatSpellDetails
        local unit = det and det.unitName
        local amount = det and det.amount
        if DM.Plain(unit) and type(unit) == "string" and unit ~= ""
           and DM.Plain(amount) and type(amount) == "number" then
            local rec = byName[unit]
            if not rec then
                rec = { total = 0, classFile = DM.Plain(det.unitClassFilename) and det.unitClassFilename or nil }
                byName[unit] = rec
                order[#order + 1] = unit
            end
            rec.total = rec.total + amount
        end
    end
    if #order == 0 then return nil end
    table.sort(order, function(a, b) return byName[a].total > byName[b].total end)
    local maxAmt = byName[order[1]].total
    local total = 0
    for _, n in ipairs(order) do total = total + byName[n].total end
    local out = {}
    for i, n in ipairs(order) do
        local rec = byName[n]
        local r, g, b = DM.ClassColor(rec.classFile)
        out[i] = {
            noIcon = true,
            label = DM.StripRealm(n),
            amount = total > 0 and ("%s  %.0f%%"):format(DM.Abbrev(rec.total), rec.total / total * 100) or DM.Abbrev(rec.total),
            fillValue = rec.total, fillMax = maxAmt,
            r = r, g = g, b = b,
        }
    end
    return out
end

-- Death recap. deathRecapID is NeverSecret; everything the recap returns may
-- not be.
local function recapEntries(W, src)
    local rid = src and src.deathRecapID
    if type(rid) ~= "number" or DM.IsSecret(rid) or rid <= 0 then return nil end
    if not (C_DeathRecap and C_DeathRecap.GetRecapEvents) then return nil end
    local ok, raw = pcall(C_DeathRecap.GetRecapEvents, rid)
    if not ok or type(raw) ~= "table" then return nil end

    local maxHP, maxHPSecret = 1, nil
    if C_DeathRecap.GetRecapMaxHealth then
        local ok2, hp = pcall(C_DeathRecap.GetRecapMaxHealth, rid)
        if ok2 and type(hp) ~= "nil" then
            if DM.IsSecret(hp) then maxHPSecret = hp
            elseif type(hp) == "number" and hp > 0 then maxHP = hp end
        end
    end

    -- Oldest first, the way it happened. The length probe is guarded too: if
    -- the client ever hands back a secret table, `#` on it throws, and that
    -- must degrade to "no recap" rather than to an error per frame.
    local okLen, count = pcall(function() return #raw end)
    if not okLen or type(count) ~= "number" or count == 0 then return nil end
    local evs = {}
    for i = count, 1, -1 do evs[#evs + 1] = raw[i] end
    local deathTime = evs[#evs] and evs[#evs].timestamp
    if not DM.Plain(deathTime) or type(deathTime) ~= "number" then deathTime = nil end

    local out = {}
    for i = 1, #evs do
        local ev = evs[i]
        local id = ev.spellId
        local icon = FALLBACK_ICON
        if type(id) ~= "nil" then
            local tex = C_Spell.GetSpellTexture(id)
            if type(tex) ~= "nil" then icon = tex end
        end
        local evType = ev.event
        if not DM.Plain(evType) or type(evType) ~= "string" then evType = "" end
        local isHeal = (evType == "SPELL_HEAL" or evType == "SPELL_PERIODIC_HEAL")

        local spellName = ev.spellName
        if DM.Plain(spellName) and (type(spellName) ~= "string" or spellName == "") then
            spellName = isHeal and L["Heal"] or (evType == "SWING_DAMAGE" and L["Melee"] or L["Unknown"])
        end

        -- Health left: a plain pair becomes a fraction, a secret one goes in
        -- whole and the status bar divides.
        local cur = ev.currentHP
        if type(cur) == "nil" then cur = 0 end
        local pct, fillValue, fillMax
        if DM.Plain(cur) and not maxHPSecret and type(cur) == "number" then
            pct = math.min(1, math.max(0, maxHP > 0 and cur / maxHP or 0))
            fillValue, fillMax = pct, 1
        elseif type(maxHPSecret) ~= "nil" then
            fillValue, fillMax = cur, maxHPSecret
        else
            fillValue, fillMax = cur, maxHP
        end

        local ts = ev.timestamp
        local before
        if deathTime and DM.Plain(ts) and type(ts) == "number" then before = deathTime - ts end

        local amt = ev.amount
        if type(amt) == "nil" then amt = 0 end
        local pctStr = pct and (" (%.0f%%)"):format(pct * 100) or ""
        local amountText, amountSuffix
        if DM.IsSecret(amt) then
            -- A secret must not be concatenated. The two halves travel apart
            -- and the font string's own formatter joins them.
            amountText, amountSuffix = DM.Abbrev(amt), pctStr
        else
            local str = isHeal and ("+" .. DM.Abbrev(math.abs(amt))) or ("-" .. DM.Abbrev(amt))
            -- The meter's own structures spell this overkillAmount; the recap
            -- event table is undocumented, so both spellings are accepted.
            local over = ev.overkillAmount
            if type(over) == "nil" then over = ev.overkill end
            local fatal = (i == #evs and not isHeal)
            if fatal and DM.Plain(over) and type(over) == "number" and over > 0 then
                str = ("%s |cffff3333(%s %s)|r"):format(str, DM.Abbrev(over), L["overkill"])
            end
            amountText = str .. pctStr
        end

        out[#out + 1] = {
            icon = icon,
            label = spellName, labelPrefix = before,
            amount = amountText, amountSuffix = amountSuffix,
            fillValue = fillValue, fillMax = fillMax,
            r = isHeal and 0.10 or 0.60, g = isHeal and 0.50 or 0.08, b = isHeal and 0.10 or 0.08,
            spellID = DM.Plain(id) and type(id) == "number" and id > 0 and id or nil,
        }
    end
    return out
end

-- Who this row is about, for the panel heading and the API lookup. In combat
-- the GUID is secret and may not be passed as an argument, so the own row
-- (UnitGUID) and a death recap are the two that still work.
local function rowIdentity(src)
    if not src then return nil end
    local guid, cid = src.sourceGUID, src.sourceCreatureID
    if DM.Plain(guid) and type(guid) == "string" then
        return { guid = guid, cid = DM.Plain(cid) and cid or nil, src = src }
    end
    if DM.Plain(cid) then
        return { guid = nil, cid = cid, src = src }
    end
    if DM.IsOwnRow(src) then
        return { guid = UnitGUID("player"), cid = nil, src = src }
    end
    return nil
end

-- The entry list for one source, or nil plus the reason it could not be built.
-- The caller may hand in the identity it captured earlier: the open panel does
-- that, because the row it was opened from is recycled by rank and would start
-- answering for a different player as the ranks change.
function DM.BuildEntries(W, src, pinned)
    if not src then return nil end
    if DM.IsDeaths(W.dmType) then
        local e = recapEntries(W, src)
        if not e then return nil, L["No death recap available."] end
        return e, nil, L["Death Recap"]
    end
    local id = pinned or rowIdentity(src)
    if not id then return nil, L["Details are secret while you are in combat."] end
    local source = DM.FetchSource(W, id.guid, id.cid)
    if not source then return nil, L["No details for this row."] end
    if W.dmType == DM.T.EnemyDamageTaken then
        local e = enemyEntries(W, source)
        if not e then return nil, L["Details are secret while you are in combat."] end
        return e, nil, DM.TypeName(DM.T.DamageTaken)
    end
    local e = spellEntries(W, source)
    if not e or #e == 0 then return nil, L["No details for this row."] end
    return e, nil, DM.TypeName(W.dmType)
end

-- ---------------------------------------------------------------- shared row --

local function makeEntryRow(parent, onSpellTooltip)
    local bar = {}
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(18)
    bar.row = row

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("LEFT", row, "LEFT", 0, 0)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    bar.icon = icon

    local fill = CreateFrame("StatusBar", nil, row)
    fill:SetPoint("TOPLEFT", icon, "TOPRIGHT", 0, 0)
    fill:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
    fill:SetStatusBarTexture(DM.WHITE)
    bar.fill = fill

    local tf = CreateFrame("Frame", nil, row)
    tf:SetAllPoints(fill)
    tf:SetFrameLevel(row:GetFrameLevel() + 4)

    local label = tf:CreateFontString(nil, "OVERLAY")
    label:SetJustifyH("LEFT"); label:SetWordWrap(false)
    label:SetPoint("LEFT", tf, "LEFT", 3, 0)
    bar.label = label
    local amount = tf:CreateFontString(nil, "OVERLAY")
    amount:SetJustifyH("RIGHT")
    amount:SetPoint("RIGHT", tf, "RIGHT", -3, 0)
    label:SetPoint("RIGHT", amount, "LEFT", -6, 0)
    bar.amount = amount

    -- The client's own spell tooltip, the one place GameTooltip is used here.
    icon:SetParent(row)
    row:SetScript("OnEnter", function(self)
        if not DM.db().showSpellTooltips or not self._spellID then return end
        GameTooltip:SetOwner(self, "ANCHOR_NONE")
        GameTooltip:SetPoint("TOPRIGHT", self, "TOPLEFT", -6, 0)
        GameTooltip:SetSpellByID(self._spellID)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    if onSpellTooltip then row:SetScript("OnClick", onSpellTooltip) end
    return bar
end

local function paintEntryRow(bar, e, texture, height, fontSize, defR, defG, defB)
    bar.row:SetHeight(height)
    bar.icon:SetSize(height, height)
    -- `noIcon` is its own flag rather than a sentinel in the icon slot: the
    -- icon may be a secret file id, and comparing one throws.
    if e.noIcon then
        bar.icon:Hide()
        bar.fill:SetPoint("TOPLEFT", bar.row, "TOPLEFT", 0, 0)
    else
        local tex = e.icon
        if type(tex) == "nil" then tex = FALLBACK_ICON end
        bar.icon:SetTexture(tex)
        bar.icon:Show()
        bar.fill:SetPoint("TOPLEFT", bar.icon, "TOPRIGHT", 0, 0)
    end
    bar.fill:SetStatusBarTexture(texture)
    bar.fill:SetMinMaxValues(0, e.fillMax)
    bar.fill:SetValue(e.fillValue)
    bar.fill:SetStatusBarColor(e.r or defR, e.g or defG, e.b or defB)
    DM.Font(bar.label, fontSize)
    DM.Font(bar.amount, fontSize)
    bar.label:SetTextColor(1, 1, 1)
    bar.amount:SetTextColor(1, 1, 1)
    if e.labelPrefix then
        -- The engine formats: a secret name never meets Lua concatenation.
        bar.label:SetFormattedText("-%.1fs %s", e.labelPrefix, e.label)
    else
        bar.label:SetFormattedText("%s", e.label)
    end
    if e.amountSuffix then
        bar.amount:SetFormattedText("%s%s", e.amount, e.amountSuffix)
    else
        bar.amount:SetText(e.amount)
    end
    bar.row._spellID = e.spellID
    bar.row:Show()
end

-- ---------------------------------------------------------------- panel --

-- The in-window breakdown: takes over the bar area, any click goes back.
function DM.AttachBreakdown(W)
    local frame, header = W.frame, W.header
    local panel, scroll, child, heading
    local rows = {}
    local scrollMax = 0

    local function ensure()
        if panel then return end
        panel = CreateFrame("Button", nil, frame)
        panel:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
        panel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        panel:SetFrameLevel(frame:GetFrameLevel() + 20)
        panel:RegisterForClicks("AnyUp")
        panel:Hide()
        local pb = panel:CreateTexture(nil, "BACKGROUND")
        pb:SetAllPoints(panel)
        pb:SetColorTexture(0.03, 0.03, 0.03, 0.95)
        panel:SetScript("OnClick", function() W.CloseSource() end)

        heading = panel:CreateFontString(nil, "OVERLAY")
        heading:SetPoint("TOPLEFT", panel, "TOPLEFT", 4, -3)
        heading:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -4, -3)
        heading:SetJustifyH("LEFT"); heading:SetWordWrap(false)

        scroll = CreateFrame("ScrollFrame", nil, panel)
        scroll:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -3)
        scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 2)
        scroll:SetClipsChildren(true)
        child = CreateFrame("Frame", nil, scroll)
        child:SetSize(1, 1)
        scroll:SetScrollChild(child)
        scroll:SetScript("OnSizeChanged", function(_, w) child:SetWidth(w) end)
        local function wheel(_, delta)
            local cur = scroll:GetVerticalScroll() or 0
            scroll:SetVerticalScroll(math.max(0, math.min(scrollMax, cur - delta * 30)))
        end
        panel:EnableMouseWheel(true); panel:SetScript("OnMouseWheel", wheel)
        scroll:EnableMouseWheel(true); scroll:SetScript("OnMouseWheel", wheel)
    end

    function W.OpenSourceFromRow(bar)
        ensure()
        local src = bar.src
        -- Pinned at open time, not read back from the row: rows are recycled
        -- by rank, so a rank change mid-fight would swap the player under the
        -- panel while the heading kept the old name.
        W.sourceSrc  = src
        W.sourceID   = rowIdentity(src)
        local entries, why, kind = DM.BuildEntries(W, src, W.sourceID)
        W.sourceOpen = true
        W.sourceName = DM.StripRealm(src and src.name)
        W.sourceKind = kind
        W.HideHome()
        panel:Show()
        W.RenderSource(entries, why)
    end

    function W.RefreshSource()
        if not W.sourceOpen or not W.sourceSrc then return end
        local entries, why = DM.BuildEntries(W, W.sourceSrc, W.sourceID)
        W.RenderSource(entries, why)
    end

    function W.RenderSource(entries, why)
        local d = DM.db()
        local h = ns:PixelSnap(d.barHeight or 18, frame)
        local tex = DM.BreakdownTexture()
        DM.Font(heading, (d.hdrFontSize or 11))
        local hr, hg, hb
        if d.hdrTextUseAccent then hr, hg, hb = DM.Accent() else hr, hg, hb = d.hdrTextColor.r, d.hdrTextColor.g, d.hdrTextColor.b end
        heading:SetTextColor(hr, hg, hb)
        heading:SetFormattedText(L["%s — %s"], W.sourceName or "", W.sourceKind or "")

        local dr, dg, db2
        if d.barColorUseAccent then dr, dg, db2 = DM.Accent() else dr, dg, db2 = d.barColor.r, d.barColor.g, d.barColor.b end

        local n = entries and #entries or 0
        for i = 1, math.max(n, #rows) do
            local bar = rows[i]
            if i <= n then
                if not bar then bar = makeEntryRow(child); rows[i] = bar end
                bar.row:ClearAllPoints()
                bar.row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -((i - 1) * (h + 1)))
                bar.row:SetPoint("TOPRIGHT", child, "TOPRIGHT", 0, -((i - 1) * (h + 1)))
                paintEntryRow(bar, entries[i], tex, h, d.rightFontSize or 11, dr, dg, db2)
            elseif bar then
                bar.row:Hide()
            end
        end
        if not W.sourceEmpty then
            W.sourceEmpty = panel:CreateFontString(nil, "OVERLAY")
            DM.Font(W.sourceEmpty, 11)
            W.sourceEmpty:SetPoint("CENTER", panel, "CENTER", 0, 0)
            W.sourceEmpty:SetTextColor(0.6, 0.6, 0.65)
        end
        W.sourceEmpty:SetText(n == 0 and (why or L["No details for this row."]) or "")
        W.sourceEmpty:SetShown(n == 0)

        local contentH = n * (h + 1)
        child:SetHeight(math.max(1, contentH))
        scrollMax = math.max(0, contentH - (scroll:GetHeight() or 0))
    end

    function W.CloseSource()
        if panel then panel:Hide() end
        W.sourceOpen, W.sourceSrc, W.sourceID = false, nil, nil
    end

    function W.RestyleSource()
        if W.sourceOpen then W.RefreshSource() end
    end
end

-- ---------------------------------------------------------------- preview --

-- The floating breakdown on hover. One frame for every window.
local PREV_W, PREV_HDR = 275, 20
local prev, prevRows, prevOwner = nil, {}, nil
local prevTicker

local function ensurePreview()
    if prev then return prev end
    prev = CreateFrame("Frame", nil, UIParent)
    prev:SetFrameStrata("TOOLTIP")
    prev:SetSize(PREV_W, PREV_HDR)
    prev:Hide()
    UI:StyleBackdrop(prev, { bg = { r = 0.03, g = 0.03, b = 0.04, a = 0.96 } })
    prev.heading = prev:CreateFontString(nil, "OVERLAY")
    prev.heading:SetPoint("TOPLEFT", prev, "TOPLEFT", 5, -4)
    prev.heading:SetPoint("TOPRIGHT", prev, "TOPRIGHT", -5, -4)
    prev.heading:SetJustifyH("LEFT"); prev.heading:SetWordWrap(false)
    prev.empty = prev:CreateFontString(nil, "OVERLAY")
    prev.empty:SetPoint("TOP", prev, "TOP", 0, -PREV_HDR - 4)
    prev.empty:SetTextColor(0.6, 0.6, 0.65)
    return prev
end

local function anchorPreview(W, bar)
    local d = DM.db()
    prev:ClearAllPoints()
    local mode = d.breakdownAnchorPoint or "row"
    if mode == "center" then
        prev:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    elseif mode == "left" then
        prev:SetPoint("TOPRIGHT", W.frame, "TOPLEFT", -4, 0)
    elseif mode == "right" then
        prev:SetPoint("TOPLEFT", W.frame, "TOPRIGHT", 4, 0)
    else
        prev:SetPoint("BOTTOMRIGHT", bar.row, "TOPRIGHT", 0, 2)
    end
end

function DM.ShowPreview(W, bar)
    local d = DM.db()
    if not d.showHoverTooltip or DM.toggleHidden then return end
    ensurePreview()
    prevOwner = bar
    local entries, why, kind = DM.BuildEntries(W, bar.src)
    local maxRows = d.showAllBreakdownSpells and 15 or 8
    local n = math.min(entries and #entries or 0, maxRows)

    prev:SetScale((tonumber(d.hoverTooltipScale) or 100) / 100)
    DM.Font(prev.heading, d.hdrFontSize or 11)
    DM.Font(prev.empty, 11)
    local hr, hg, hb
    if d.hdrTextUseAccent then hr, hg, hb = DM.Accent() else hr, hg, hb = d.hdrTextColor.r, d.hdrTextColor.g, d.hdrTextColor.b end
    prev.heading:SetTextColor(hr, hg, hb)
    prev.heading:SetFormattedText(L["%s — %s"], DM.StripRealm(bar.src and bar.src.name), kind or DM.TypeName(W.dmType))

    local h = ns:PixelSnap(d.barHeight or 18, prev)
    local tex = DM.BreakdownTexture()
    local dr, dg, db2
    if d.barColorUseAccent then dr, dg, db2 = DM.Accent() else dr, dg, db2 = d.barColor.r, d.barColor.g, d.barColor.b end

    for i = 1, math.max(n, #prevRows) do
        local pb = prevRows[i]
        if i <= n then
            if not pb then pb = makeEntryRow(prev); prevRows[i] = pb end
            pb.row:ClearAllPoints()
            pb.row:SetPoint("TOPLEFT", prev, "TOPLEFT", 3, -(PREV_HDR + (i - 1) * (h + 1)))
            pb.row:SetPoint("TOPRIGHT", prev, "TOPRIGHT", -3, -(PREV_HDR + (i - 1) * (h + 1)))
            paintEntryRow(pb, entries[i], tex, h, d.rightFontSize or 11, dr, dg, db2)
        elseif pb then
            pb.row:Hide()
        end
    end
    prev.empty:SetText(n == 0 and (why or L["No details for this row."]) or "")
    prev.empty:SetShown(n == 0)
    prev:SetSize(PREV_W, PREV_HDR + (n > 0 and n * (h + 1) + 4 or 24))
    anchorPreview(W, bar)
    prev:Show()

    -- Refreshes while the cursor stays, and closes itself if the row went away.
    if not prevTicker then
        prevTicker = ns:AddTicker(0.25, function()
            if not prevOwner or not prevOwner.row:IsMouseOver() then
                DM.HidePreview()
                return
            end
            DM.ShowPreview(W, prevOwner)
        end, nil, "meter preview")
    end
end

function DM.HidePreview()
    if prev then prev:Hide() end
    prevOwner = nil
    if prevTicker then ns:CancelTicker(prevTicker); prevTicker = nil end
end
