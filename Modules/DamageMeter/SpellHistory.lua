-- VuloForeverUI / Modules / DamageMeter / SpellHistory
--
-- What you just cast, in two displays that stand on their own:
--   the icon strip   a row of the last few spell icons, growing in a chosen
--                    direction, failed casts tinted red
--   the bar window   the same casts as bars with the cast time and the target
--
-- Both are fed by the player's own cast events, which still carry the spell id
-- on this client. Nothing here touches the combat log -- there is none -- and
-- nothing costs anything while both displays are off: the events are only
-- registered when one of them is on.
local _, ns = ...
local L  = ns.L
local DM = ns.DM
local UI = ns.UI

local SH = {}
DM.SpellHistory = SH

local MAX_HISTORY = 40
local FADE_DUR    = 1.5
local ANIM_DUR    = 0.5

local history = {}           -- newest at index 1
local castTargets = {}       -- castGUID -> target name, from the SENT event
local activeChannel          -- suppresses a channel's per-tick SUCCEEDED
local pending = {}           -- entries with a running cast, for the fill

local function db() return DM.db().spellHistory end

local eventFrame, animFrame, fadeTicker
local registered = false
local strip, stripIcons = nil, {}
local barWin, barRows = nil, {}

-- ---------------------------------------------------------------- tracking --

local infoCache = {}

local function spellInfo(id)
    local c = infoCache[id]
    if c then return c end
    local info = C_Spell.GetSpellInfo(id)
    if not info then return nil end
    c = { name = info.name, icon = info.iconID }
    infoCache[id] = c
    return c
end

-- The id actually cast, after any override.
--
-- A spell id that is not plain is dropped here rather than carried further:
-- the id is used as a cache key and compared against the running channel, and
-- both of those throw on a secret. Your own casts read plain on this client,
-- so this is the guard for the case that changes, not the normal path.
local function resolveID(id)
    if type(id) ~= "number" or DM.IsSecret(id) then return nil end
    local ov = C_Spell.GetOverrideSpell and C_Spell.GetOverrideSpell(id)
    if type(ov) == "number" and not DM.IsSecret(ov) then return ov end
    return id
end

local function isPlayerSpell(id)
    if C_SpellBook and C_SpellBook.IsSpellKnownOrInSpellBook then
        if C_SpellBook.IsSpellKnownOrInSpellBook(id) then return true end
        if C_SpellBook.IsSpellKnownOrInSpellBook(id, Enum.SpellBookSpellBank.Pet) then return true end
    end
    -- An id the book does not list is still worth showing if it has a name;
    -- the alternative is silently dropping procs and item casts.
    return C_Spell.GetSpellName(id) ~= nil
end

local function push(entry)
    table.insert(history, 1, entry)
    for i = #history, MAX_HISTORY + 1, -1 do history[i] = nil end
end

-- A cast id that is not a plain string is treated as absent: it is compared
-- against the stored one and used as a table key, and both throw on a secret.
local function plainGUID(castGUID)
    if DM.Plain(castGUID) and type(castGUID) == "string" then return castGUID end
    return nil
end

local function findEntry(castGUID, spellID)
    castGUID = plainGUID(castGUID)
    for i = 1, math.min(#history, 5) do
        local e = history[i]
        if (castGUID and e.castGUID == castGUID) or (not castGUID and e.spellID == spellID) then return e, i end
    end
    return nil
end

local function startCast(spellID, castGUID, isChannel)
    castGUID = plainGUID(castGUID)
    local id = resolveID(spellID)
    if not id or not isPlayerSpell(id) then return end
    local info = spellInfo(id)
    if not info then return end
    -- Both return (name, text, texture, startTimeMS, endTimeMS, ...). The call
    -- needs its own statement: `a and f() or g()` would truncate to one value.
    local startMS, endMS
    if isChannel then
        startMS, endMS = select(4, UnitChannelInfo("player"))
    else
        startMS, endMS = select(4, UnitCastingInfo("player"))
    end
    local duration, startTime
    if DM.Plain(startMS) and DM.Plain(endMS) and type(startMS) == "number" and type(endMS) == "number" then
        duration = (endMS - startMS) / 1000
        startTime = GetTime()
    end
    local e = {
        spellID = id, castGUID = castGUID, name = info.name, icon = info.icon,
        target = castGUID and castTargets[castGUID] or nil,
        status = isChannel and "channeling" or "casting",
        isChannel = isChannel, duration = duration, startTime = startTime,
        stamp = GetTime(), progress = 0,
    }
    push(e)
    if duration then pending[e] = true end
    SH.Refresh()
end

local function instantCast(spellID, castGUID)
    castGUID = plainGUID(castGUID)
    local id = resolveID(spellID)
    if not id or not isPlayerSpell(id) then return end
    local info = spellInfo(id)
    if not info then return end
    push({
        spellID = id, castGUID = castGUID, name = info.name, icon = info.icon,
        target = castGUID and castTargets[castGUID] or nil,
        status = "success", isInstant = true, stamp = GetTime(), progress = 1,
    })
    if castGUID then castTargets[castGUID] = nil end
    SH.Refresh()
end

local function finishCast(castGUID, spellID, status)
    castGUID = plainGUID(castGUID)
    local e = findEntry(castGUID, resolveID(spellID))
    if not e then
        -- instantCast still needs the banked target, so the release happens
        -- after it, not before.
        if status == "success" then instantCast(spellID, castGUID) end
        if castGUID then castTargets[castGUID] = nil end
        return
    end
    -- Every outcome frees the banked target, not just a success: SENT also
    -- fires for casts that never start (out of range, moving, no line of
    -- sight), and the table would otherwise grow for the whole session.
    if castGUID then castTargets[castGUID] = nil end
    -- A success is never downgraded: a STOP arrives after the SUCCEEDED of a
    -- cast that landed.
    if e.status == "success" and status ~= "success" then return end
    e.status = status
    if status ~= "success" and e.startTime and e.duration then
        e.progress = math.min(1, (GetTime() - e.startTime) / e.duration)
    elseif status == "success" then
        e.progress = 1
        e.elapsed = e.startTime and (GetTime() - e.startTime) or nil
    end
    pending[e] = nil
    SH.Refresh()
end

local EVENTS = {
    "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_CHANNEL_START",
    "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_FAILED_QUIET",
    "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_CHANNEL_STOP",
}

local function onEvent(_, event, unit, castGUID, spellID)
    if unit ~= "player" then return end
    if event == "UNIT_SPELLCAST_SENT" then
        -- Arguments differ here: (unit, target, castGUID, spellID)
        local target, guid = castGUID, spellID
        -- The cast id is a table key here, so it has to be plain, and a nil
        -- key throws on its own.
        if DM.Plain(guid) and type(guid) == "string"
           and DM.Plain(target) and type(target) == "string" and target ~= "" then
            castTargets[guid] = target
        end
        return
    end
    if event == "UNIT_SPELLCAST_START" then
        startCast(spellID, castGUID, false)
    elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
        activeChannel = resolveID(spellID)
        startCast(spellID, castGUID, true)
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local id = resolveID(spellID)
        if activeChannel and id == activeChannel then return end   -- a channel tick
        local e = findEntry(castGUID, id)
        -- Both paths release the banked target themselves; doing it again here
        -- would be `castTargets[nil] = nil` for an event without a cast id,
        -- and a nil table index throws.
        if e then finishCast(castGUID, spellID, "success") else instantCast(spellID, castGUID) end
    elseif event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_FAILED_QUIET" then
        finishCast(castGUID, spellID, "failed")
    elseif event == "UNIT_SPELLCAST_INTERRUPTED" then
        finishCast(castGUID, spellID, "interrupted")
        if resolveID(spellID) == activeChannel then activeChannel = nil end
    elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        activeChannel = nil
        local e = findEntry(castGUID, resolveID(spellID))
        if e and e.status == "channeling" then finishCast(castGUID, spellID, "success") end
    elseif event == "UNIT_SPELLCAST_STOP" then
        -- One frame of grace: a SUCCEEDED for the same cast may still arrive.
        local guid, id = castGUID, spellID
        ns.NextFrame(function()
            local e = findEntry(guid, resolveID(id))
            if e and (e.status == "casting" or e.status == "channeling") then
                finishCast(guid, id, "failed")
            end
        end)
    end
end

-- ---------------------------------------------------------------- shared --

local function shouldHide(prefix)
    local d = db()
    if DM.toggleHidden and DM.db().toggleIncludeSpellHistory then return true end
    local _, itype = IsInInstance()
    if d[prefix .. "HideInDungeon"] and itype == "party" then return true end
    if d[prefix .. "HideInRaid"] and itype == "raid" then return true end
    if d[prefix .. "HideInPvP"] and (itype == "pvp" or itype == "arena") then return true end
    if d[prefix .. "HideOutOfInstance"] and (itype == "none" or not itype) then return true end
    return false
end

local function forced()
    return DM.optionsOpen or ns:IsEditModeActive()
end

local function entryColor(e)
    local d = db()
    if e.status == "failed" or e.status == "interrupted" then return 0.859, 0.255, 0.255 end
    if d.barColorUseClass then
        local _, class = UnitClass("player")
        local r, g, b = DM.ClassColor(class)
        if r then return r, g, b end
    end
    if d.barColorUseAccent then return DM.Accent() end
    return d.barColor.r, d.barColor.g, d.barColor.b
end

-- Stand-ins while the options page is open, so the strip is not empty.
local function previewEntries(count)
    local out = {}
    for slot = 1, 120 do
        if #out >= count then break end
        local kind, id = GetActionInfo(slot)
        if kind == "spell" and id then
            local info = spellInfo(id)
            if info then
                local dup = false
                for _, e in ipairs(out) do if e.spellID == id then dup = true end end
                if not dup then out[#out + 1] = { spellID = id, name = info.name, icon = info.icon, status = "success", progress = 1, stamp = GetTime() } end
            end
        end
    end
    return out
end

-- ---------------------------------------------------------------- icon strip --

local GROW = {
    LEFT  = { x = -1, y = 0 }, RIGHT = { x = 1, y = 0 },
    UP    = { x = 0, y = 1 },  DOWN  = { x = 0, y = -1 },
}

function SH.GrowValues()
    return {
        { value = "LEFT", text = L["Left"] }, { value = "RIGHT", text = L["Right"] },
        { value = "UP", text = L["Up"] },     { value = "DOWN", text = L["Down"] },
    }
end

function SH.AnimationValues()
    return {
        { value = "none",  text = L["None"] },
        { value = "slide", text = L["Slide in"] },
        { value = "fly",   text = L["Fly in"] },
    }
end

local function buildStrip()
    if strip then return strip end
    strip = CreateFrame("Frame", "VuloForeverUIMeterIconHistory", UIParent)
    strip:SetFrameStrata("MEDIUM")
    strip:SetSize(40, 40)
    strip:SetMovable(true)
    strip:SetClampedToScreen(true)
    strip:SetDontSavePosition(true)
    strip:EnableMouse(false)
    strip:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" or not IsShiftKeyDown() then return end
        self:StartMoving(); self.moving = true
    end)
    strip:SetScript("OnMouseUp", function(self)
        if not self.moving then return end
        self.moving = false
        self:StopMovingOrSizing()
        db().iconPos = { x = self:GetLeft(), y = self:GetTop() }
    end)
    -- Click-through unless shift is held, so it never eats a click in a fight.
    local mods = CreateFrame("Frame")
    mods:RegisterEvent("MODIFIER_STATE_CHANGED")
    mods:SetScript("OnEvent", function()
        if not strip or not strip:IsShown() then return end
        local on = IsShiftKeyDown() and true or false
        strip:EnableMouse(on)
    end)
    return strip
end

local function stripIcon(i)
    local t = stripIcons[i]
    if t then return t end
    t = CreateFrame("Frame", nil, strip)
    local tex = t:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints(t)
    t.tex = tex
    stripIcons[i] = t
    return t
end

local function zoom(tex, z)
    if z and z > 0 then tex:SetTexCoord(z, 1 - z, z, 1 - z) else tex:SetTexCoord(0, 1, 0, 1) end
end

-- The newest icon keeps its place on screen; the strip grows around it, so a
-- change of count or direction never moves what the eye is tracking.
local function layoutStrip(list)
    local d = db()
    local size, gap = d.iconSize or 36, d.iconSpacing or 1
    local dir = GROW[d.growDirection] or GROW.LEFT
    local count = math.min(#list, d.iconCount or 5)
    local shown = forced() and (d.iconCount or 5) or count

    local span = shown * size + math.max(0, shown - 1) * gap
    if dir.x ~= 0 then strip:SetSize(math.max(size, span), size)
    else strip:SetSize(size, math.max(size, span)) end

    for i = 1, math.max(#stripIcons, shown) do
        local ic = stripIcons[i] or (i <= shown and stripIcon(i)) or nil
        if ic then
            if i <= shown then
                ic:SetSize(size, size)
                ic:ClearAllPoints()
                local step = (i - 1) * (size + gap)
                -- The newest icon anchors at the corner the growth comes from.
                if dir.x < 0 then ic:SetPoint("TOPRIGHT", strip, "TOPRIGHT", -step, 0)
                elseif dir.x > 0 then ic:SetPoint("TOPLEFT", strip, "TOPLEFT", step, 0)
                elseif dir.y > 0 then ic:SetPoint("BOTTOMLEFT", strip, "BOTTOMLEFT", 0, step)
                else ic:SetPoint("TOPLEFT", strip, "TOPLEFT", 0, -step) end
                ic:Show()
            else
                ic:Hide()
            end
        end
    end
    return shown, dir, size
end

local function animateNewest(ic, dir, size)
    local d = db()
    local style = d.iconAnimation or "slide"
    if style == "none" then return end
    local start = GetTime()
    ic:SetScript("OnUpdate", function(self)
        local t = (GetTime() - start) / ANIM_DUR
        if t >= 1 then
            self:SetScript("OnUpdate", nil)
            self.tex:SetScale(1)
            self.tex:ClearAllPoints()
            self.tex:SetAllPoints(self)
            return
        end
        local e = 1 - (1 - t) ^ 3
        if style == "fly" then
            self.tex:SetScale(1.35 - 0.35 * e)
        else
            self.tex:ClearAllPoints()
            self.tex:SetPoint("TOPLEFT", self, "TOPLEFT", dir.x * 6 * (1 - e), dir.y * 6 * (1 - e))
            self.tex:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", dir.x * 6 * (1 - e), dir.y * 6 * (1 - e))
        end
    end)
end

-- Fading: entries age only out of combat, and each one is credited the time it
-- spent in a fight when the fight ends.
local function fadeAlpha(e, now)
    local d = db()
    local life = d.iconFadeTime or 0
    if life <= 0 then return 1 end
    if DM.inCombat then return 1 end
    local age = now - (e.stamp or now) - (e.combatCredit or 0)
    if age < life then return 1 end
    local over = age - life
    if over >= FADE_DUR then return 0 end
    return 1 - over / FADE_DUR
end

local function refreshStrip()
    if not strip or not strip:IsShown() then return end
    local d = db()
    local list = history
    if forced() and #history < (d.iconCount or 5) then
        list = {}
        for i, e in ipairs(history) do list[i] = e end
        for _, e in ipairs(previewEntries((d.iconCount or 5) - #history)) do list[#list + 1] = e end
    end
    local shown, dir, size = layoutStrip(list)
    local now = GetTime()
    for i = 1, shown do
        local ic, e = stripIcons[i], list[i]
        if ic then
            if e then
                ic.tex:SetTexture(e.icon)
                zoom(ic.tex, d.iconZoom)
                if e.status == "failed" or e.status == "interrupted" then
                    ic.tex:SetVertexColor(0.859, 0.255, 0.255)
                else
                    ic.tex:SetVertexColor(1, 1, 1)
                end
                ic:SetAlpha((d.iconOpacity or 1) * fadeAlpha(e, now))
                ic:Show()
                if i == 1 and e ~= SH._lastNewest then
                    SH._lastNewest = e
                    animateNewest(ic, dir, size)
                end
            else
                ic:Hide()
            end
        end
    end
end

-- Only runs while something is actually fading, and never in combat.
local function updateFadeTicker()
    local d = db()
    if not strip or not strip:IsShown() or (d.iconFadeTime or 0) <= 0 or DM.inCombat then
        if fadeTicker then ns:CancelTicker(fadeTicker); fadeTicker = nil end
        return
    end
    if fadeTicker then return end
    fadeTicker = ns:AddTicker(0.1, function()
        refreshStrip()
        local now = GetTime()
        local anyLive = false
        for _, e in ipairs(history) do
            if fadeAlpha(e, now) > 0 then anyLive = true; break end
        end
        if not anyLive then
            ns:CancelTicker(fadeTicker); fadeTicker = nil
        end
    end, nil, "meter cast fade")
end

-- ---------------------------------------------------------------- bar window --

local function buildBarWindow()
    if barWin then return barWin end
    barWin = CreateFrame("Frame", "VuloForeverUIMeterCastHistory", UIParent)
    barWin:SetFrameStrata("LOW")
    barWin:SetMovable(true)
    barWin:SetClampedToScreen(true)
    barWin:SetDontSavePosition(true)
    barWin:EnableMouse(true)

    local bgT = barWin:CreateTexture(nil, "BACKGROUND", nil, -6)
    bgT:SetAllPoints(barWin)
    bgT:SetTexture(DM.WHITE)
    barWin.bg = bgT

    local header = CreateFrame("Button", nil, barWin)
    header:SetPoint("TOPLEFT", barWin, "TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", barWin, "TOPRIGHT", 0, 0)
    header:SetHeight(18)
    header:RegisterForClicks("AnyUp")
    barWin.header = header
    local hbg = header:CreateTexture(nil, "BACKGROUND")
    hbg:SetAllPoints(header)
    hbg:SetColorTexture(0.106, 0.106, 0.106, 1)
    local htext = header:CreateFontString(nil, "OVERLAY")
    htext:SetPoint("LEFT", header, "LEFT", 5, 0)
    htext:SetText(L["Cast History"])
    barWin.headerText = htext

    local function headerButton(icon, tip, onClick, offset)
        local b = CreateFrame("Button", nil, header)
        b:SetSize(16, 16)
        b:SetPoint("RIGHT", header, "RIGHT", offset, 0)
        local t = b:CreateTexture(nil, "ARTWORK")
        t:SetAllPoints(b); t:SetTexture(icon)
        b.icon = t
        b:SetAlpha(DM.ICON_ALPHA)
        b:SetScript("OnEnter", function(self) self:SetAlpha(DM.ICON_HOVER); UI:ShowTooltip(self, tip()) end)
        b:SetScript("OnLeave", function(self) self:SetAlpha(DM.ICON_ALPHA); UI:HideTooltip() end)
        b:SetScript("OnClick", onClick)
        return b
    end
    barWin.settingsBtn = headerButton(DM.ICON .. "gear", function() return L["Settings"] end, function()
        local f = UI:CreateMainFrame(); f:Show(); UI:PopulateSidebar(); UI:ShowModulePage("damagemeter")
    end, -2)
    barWin.lockBtn = headerButton(DM.ICON .. "lock_open", function()
        return db().barLocked and L["Unlock window"] or L["Lock window"]
    end, function(self)
        local d = db()
        d.barLocked = not d.barLocked
        self.icon:SetTexture(DM.ICON .. (d.barLocked and "lock" or "lock_open"))
    end, -20)

    header:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" or db().barLocked then return end
        barWin:StartMoving(); barWin.moving = true
    end)
    header:SetScript("OnMouseUp", function()
        if not barWin.moving then return end
        barWin.moving = false
        barWin:StopMovingOrSizing()
        db().barPos = { x = barWin:GetLeft(), y = barWin:GetTop() }
    end)
    return barWin
end

local function barRow(i)
    local r = barRows[i]
    if r then return r end
    r = {}
    local row = CreateFrame("Frame", nil, barWin)
    r.row = row
    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("LEFT", row, "LEFT", 0, 0)
    r.icon = icon
    local fill = CreateFrame("StatusBar", nil, row)
    fill:SetPoint("TOPLEFT", icon, "TOPRIGHT", 0, 0)
    fill:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
    fill:SetStatusBarTexture(DM.WHITE)
    r.fill = fill
    local tf = CreateFrame("Frame", nil, row)
    tf:SetAllPoints(fill)
    tf:SetFrameLevel(row:GetFrameLevel() + 4)
    local label = tf:CreateFontString(nil, "OVERLAY")
    label:SetPoint("LEFT", tf, "LEFT", 3, 0)
    label:SetJustifyH("LEFT"); label:SetWordWrap(false)
    r.label = label
    local right = tf:CreateFontString(nil, "OVERLAY")
    right:SetPoint("RIGHT", tf, "RIGHT", -3, 0)
    right:SetJustifyH("RIGHT")
    label:SetPoint("RIGHT", right, "LEFT", -6, 0)
    r.right = right
    barRows[i] = r
    return r
end

-- "1.4" while casting, "1.4s" once it landed, then the outcome or the target.
local function rightText(e)
    local timePart = ""
    if e.isInstant then
        timePart = ""
    elseif e.status == "casting" or e.status == "channeling" then
        if e.startTime then timePart = ("%.1f"):format(GetTime() - e.startTime) end
    elseif e.elapsed then
        timePart = ("%.1fs"):format(e.elapsed)
    elseif e.duration then
        timePart = ("%.1fs"):format(e.duration * (e.progress or 1))
    end
    local tail
    if e.status == "interrupted" then tail = "|cffdb4141" .. L["Interrupted"] .. "|r"
    elseif e.status == "failed" then tail = "|cffdb4141" .. L["Failed"] .. "|r"
    elseif e.target then tail = DM.StripRealm(e.target) end
    if tail and timePart ~= "" then return timePart .. "  " .. tail end
    return tail or timePart
end

local function fillProgress(e)
    if e.status == "casting" and e.startTime and e.duration then
        return math.min(1, (GetTime() - e.startTime) / e.duration)
    end
    if e.status == "channeling" and e.startTime and e.duration then
        return math.max(0, 1 - (GetTime() - e.startTime) / e.duration)
    end
    return e.progress or 1
end

local function refreshBars()
    if not barWin or not barWin:IsShown() then return end
    local d = db()
    local list = history
    if forced() and #history < (d.maxBars or 5) then
        list = {}
        for i, e in ipairs(history) do list[i] = e end
        for _, e in ipairs(previewEntries((d.maxBars or 5) - #history)) do list[#list + 1] = e end
    end
    local h = ns:PixelSnap(d.barHeight or 18, barWin)
    local hdrH = d.hideTopBar and 0 or 18
    local n = math.min(#list, d.maxBars or 5)
    local tex = d.barTexture == "match" and DM.BarTexture(DM.db().barTexture) or DM.BarTexture(d.barTexture)
    local tr, tg, tb
    if d.textColorUseAccent then tr, tg, tb = DM.Accent() else tr, tg, tb = d.textColor.r, d.textColor.g, d.textColor.b end

    for i = 1, math.max(n, #barRows) do
        local r = barRows[i] or (i <= n and barRow(i)) or nil
        if r then
            if i <= n then
                local e = list[i]
                r.row:ClearAllPoints()
                r.row:SetPoint("TOPLEFT", barWin, "TOPLEFT", 0, -(hdrH + (i - 1) * (h + 1)))
                r.row:SetPoint("TOPRIGHT", barWin, "TOPRIGHT", 0, -(hdrH + (i - 1) * (h + 1)))
                r.row:SetHeight(h)
                r.icon:SetSize(h, h)
                r.icon:SetTexture(e.icon)
                zoom(r.icon, d.iconZoom)
                r.fill:SetStatusBarTexture(tex)
                r.fill:SetMinMaxValues(0, 1)
                r.fill:SetValue(fillProgress(e))
                r.fill:SetStatusBarColor(entryColor(e))
                r.fill:SetAlpha(d.barOpacity or 1)
                DM.Font(r.label, d.textSize or 11)
                DM.Font(r.right, d.textSize or 11)
                r.label:SetTextColor(tr, tg, tb)
                r.right:SetTextColor(tr, tg, tb)
                r.label:SetText(e.name)
                r.right:SetText(rightText(e))
                r.row:Show()
            else
                r.row:Hide()
            end
        end
    end
    barWin:SetSize(d.barWidth or 300, hdrH + n * (h + 1) + 2)
    barWin.header:SetShown(not d.hideTopBar)
end

-- A running cast animates; the frame stops itself once none is left.
local function ensureAnimFrame()
    if animFrame then return end
    animFrame = CreateFrame("Frame")
    animFrame:SetScript("OnUpdate", function(self)
        if not next(pending) then self:Hide(); return end
        refreshBars()
    end)
end

-- ---------------------------------------------------------------- public --

function SH.Refresh()
    refreshStrip()
    refreshBars()
    if next(pending) then
        ensureAnimFrame()
        animFrame:Show()
    end
    updateFadeTicker()
end

function SH.UpdateVisibility()
    local d = db()
    if strip then
        local show = d.iconEnabled and (forced() or not shouldHide("icon"))
        strip:SetShown(show and true or false)
    end
    if barWin then
        local show = d.barEnabled and (forced() or not shouldHide("bar"))
        barWin:SetShown(show and true or false)
    end
    SH.Refresh()
end

local function applyPositions()
    local d = db()
    if strip then
        strip:ClearAllPoints()
        local p = d.iconPos
        if type(p) == "table" and p.x and p.y then
            strip:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", p.x, p.y)
        else
            strip:SetPoint("CENTER", UIParent, "CENTER", 0, -180)
        end
    end
    if barWin then
        barWin:ClearAllPoints()
        local p = d.barPos
        if type(p) == "table" and p.x and p.y then
            barWin:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", p.x, p.y)
        else
            barWin:SetPoint("CENTER", UIParent, "CENTER", -300, -180)
        end
    end
end

function SH.Apply()
    local d = db()
    if not (d.iconEnabled or d.barEnabled or strip or barWin) then
        SH.Unregister()
        return
    end
    if d.iconEnabled then buildStrip() end
    if d.barEnabled then
        buildBarWindow()
        local bg = d.bgColor
        barWin.bg:SetColorTexture(bg.r, bg.g, bg.b, d.bgAlpha or 0.25)
        DM.Font(barWin.headerText, d.textSize or 11)
        barWin.lockBtn.icon:SetTexture(DM.ICON .. (d.barLocked and "lock" or "lock_open"))
    end
    applyPositions()
    if d.iconEnabled or d.barEnabled then SH.Register() else SH.Unregister() end
    SH.UpdateVisibility()
end

function SH.Register()
    if registered then return end
    if not eventFrame then
        eventFrame = CreateFrame("Frame")
        eventFrame:SetScript("OnEvent", onEvent)
    end
    for _, e in ipairs(EVENTS) do eventFrame:RegisterUnitEvent(e, "player") end
    registered = true
end

-- The frame is kept, only its events go: a frame cannot be collected, so
-- minting a new one on every enable from the options page would leak one per
-- click. SH.Register puts the events back on the same frame.
function SH.Unregister()
    if not eventFrame then return end
    eventFrame:UnregisterAllEvents()
    registered = false
end

function SH.Disable()
    SH.Unregister()
    if strip then strip:Hide() end
    if barWin then barWin:Hide() end
    if fadeTicker then ns:CancelTicker(fadeTicker); fadeTicker = nil end
    if animFrame then animFrame:Hide() end
end

function SH.Clear()
    wipe(history)
    wipe(pending)
    SH.Refresh()
end

-- Leaving combat credits every entry the time it spent in a fight, so nothing
-- fades out the instant the fight ends.
function SH.OnCombatEnd(seconds)
    for _, e in ipairs(history) do
        e.combatCredit = (e.combatCredit or 0) + seconds
    end
    updateFadeTicker()
end
