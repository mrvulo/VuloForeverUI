-- VuloForeverUI / Modules / QoL / Stats
--
-- A small block of secondary stats on the screen: crit, haste, mastery,
-- versatility, and the three tertiaries if you want them.
--
-- THE WHOLE POINT OF THIS FILE
--
-- In restricted content the stat getters hand back SECRET numbers. A secret
-- refuses inspection -- comparing one, doing arithmetic on one or formatting
-- one in Lua all fail -- but it renders perfectly through an engine sink.
-- SetFormattedText is such a sink, so every figure below travels as an
-- ARGUMENT into a template built purely from clean data. That is what keeps
-- this block live during a fight instead of showing a row of question marks.
--
-- Two consequences follow, and both are visible in the code:
--
--   * versatility is the one row built by ADDING two getters, and addition is
--     exactly what a secret refuses. Under restriction the true total simply
--     cannot be computed here, so the last clean total is shown instead --
--     falling back to the rating alone would silently drop the rest.
--   * measuring costs us: GetStringWidth returns a secret once a secret string
--     has been laid out, so the block keeps its last known size until the
--     figures are readable again. Only the mover box cares, and it can wait
--     for the end of the fight.
local _, ns = ...
local L = ns.L

local QoL = ns.QoL
local Stats = QoL.RegisterPart("stats", {})
QoL.Stats = Stats

local frame, text

-- One hue per secondary, so the rows can be told apart at a glance; the
-- tertiaries share the class colour as a group.
local STAT_HEX = {
    crit    = "ffd100",
    haste   = "2ecc71",
    mastery = "55aaff",
    vers    = "c77dff",
}

local ROWS = {
    { key = "crit",      label = "Crit",      short = "C" },
    { key = "haste",     label = "Haste",     short = "H" },
    { key = "mastery",   label = "Mastery",   short = "M" },
    { key = "vers",      label = "Vers",      short = "V" },
    { key = "leech",     label = "Leech",     short = "L",  tertiary = true },
    { key = "avoidance", label = "Avoidance", short = "A",  tertiary = true },
    { key = "speed",     label = "Speed",     short = "S",  tertiary = true },
}
Stats.ROWS = ROWS

-- Labels are interpolated INTO the template, so a percent sign inside a
-- translation would turn into a stray format specifier.
local function esc(s)
    return (tostring(s):gsub("%%", "%%%%"))
end

local classHex, versLastClean

-- The class colour, resolved once. A white fallback is used per paint and never
-- cached: caching it would leave the labels white for the rest of the session
-- whenever the first paint beat the colour tables.
local function resolveClassHex()
    if classHex then return classHex end
    -- IsSecret first: UnitClass returns a secret in restricted content, and
    -- testing one for truth is itself a crash.
    local _, token = UnitClass("player")
    if ns.IsSecret(token) then token = nil end
    local c = token and RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]
    if c then classHex = string.format("%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255) end
    return classHex or "ffffff"
end

local function labelHex()
    local db = QoL.db().stats
    if db.colorMode == "custom" then
        local c = db.color
        return string.format("%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255)
    end
    if db.colorMode == "class" then return resolveClassHex() end
    return nil   -- palette: every row brings its own
end

-- The raw rating behind a row, for the "rating" and "both" display modes.
local function rating(key)
    if key == "crit"      then return GetCombatRating(CR_CRIT_MELEE) end
    if key == "haste"     then return GetCombatRating(CR_HASTE_MELEE) end
    if key == "mastery"   then return GetCombatRating(CR_MASTERY) end
    if key == "vers"      then return GetCombatRating(CR_VERSATILITY_DAMAGE_DONE) end
    if key == "leech"     then return GetCombatRating(CR_LIFESTEAL) end
    if key == "avoidance" then return GetCombatRating(CR_AVOIDANCE) end
    if key == "speed"     then return GetCombatRating(CR_SPEED) end
end

local function percent(key)
    if key == "crit"      then return GetCritChance("player") end
    if key == "haste"     then return UnitSpellHaste("player") end
    if key == "mastery"   then return GetMasteryEffect() end
    if key == "leech"     then return GetLifesteal() end
    if key == "avoidance" then return GetAvoidance() end
    if key == "speed"     then return GetSpeed() end
    if key ~= "vers" then return nil end

    -- Versatility: the total is rating bonus plus base bonus, and that sum is
    -- impossible on secrets. The client's own sheet still shows it (its code
    -- reads true values; an addon gets secrets), which is why the two disagree
    -- during a fight.
    -- No `or 0` here: a truth test on a secret throws, a nil test does not.
    local fromRating = GetCombatRatingBonus(CR_VERSATILITY_DAMAGE_DONE)
    local base = GetVersatilityBonus(CR_VERSATILITY_DAMAGE_DONE)
    if fromRating == nil or base == nil then return versLastClean end
    if ns.IsSecret(fromRating) or ns.IsSecret(base) then
        return versLastClean   -- nil until there has been one clean read
    end
    versLastClean = fromRating + base
    return versLastClean
end

local function applySettings()
    if not frame then return end
    local db = QoL.db().stats
    text:SetFont(QoL.Font(), db.fontSize, QoL.Outline())
    text:SetSpacing(db.rowGap)
end
Stats.ApplySettings = applySettings

local function update()
    if not (frame and frame:IsShown()) then return end
    local db = QoL.db().stats
    local custom = labelHex()
    local rows, vals = {}, {}
    local anySecret, unreadable = false, false

    for _, row in ipairs(ROWS) do
        if not db.hidden[row.key] then
            local hex = custom or (row.tertiary and resolveClassHex()) or STAT_HEX[row.key]
            local body, first, second
            if db.showBoth then
                body, first, second = "%.0f (%.2f%%)", rating(row.key), percent(row.key)
            elseif db.showRating then
                body, first = "%.0f", rating(row.key)
            else
                body, first = "%.2f%%", percent(row.key)
            end
            -- A nil test is allowed on a secret; anything else is not.
            if first == nil or (db.showBoth and second == nil) then
                unreadable = true
                body = "?"
            else
                if ns.IsSecret(first) then anySecret = true end
                vals[#vals + 1] = first
                if db.showBoth then
                    if ns.IsSecret(second) then anySecret = true end
                    vals[#vals + 1] = second
                end
            end
            local label = db.abbreviate and row.short or L[row.label]
            rows[#rows + 1] = string.format("|cff%s%s:|r |cff%s%s|r",
                hex, esc(label), db.coloredValues and hex or "ffffff", body)
        end
    end

    -- The engine fills the template in. This is the whole point: a secret
    -- figure is never read here, and it still draws its true number.
    text:SetFormattedText(table.concat(rows, "\n"), unpack(vals))

    if not anySecret then
        -- Clean figures do not buy a clean measurement: the metrics belong to
        -- the string that was last laid OUT, so the first paint after a secret
        -- one still answers with a secret width. Test what the arithmetic is
        -- about to touch, not what was fed in.
        local w, h = text:GetStringWidth(), text:GetStringHeight()
        if not (ns.IsSecret(w) or ns.IsSecret(h)) and w > 0 then
            frame:SetSize(w + 2, h + 2)
            if frame.mover then
                frame.mover.opts.width, frame.mover.opts.height = w + 2, h + 2
                ns:RefreshMoverGeometry(frame.mover)
            end
        end
    end

    -- A figure that is missing (not merely secret) heals on its own clock and
    -- there is no event for it, so a bounded chain of retries is armed once.
    -- A secret deliberately does NOT arm it: that clears when the fight does.
    if unreadable then
        local tries = (frame.heals or 0)
        if tries < 5 then
            frame.heals = tries + 1
            C_Timer.After(2, update)
        end
    else
        frame.heals = nil
    end
end
Stats.Update = update

local function create()
    if frame then return frame end
    local db = QoL.db().stats

    frame = CreateFrame("Frame", "VuloForeverUISecondaryStats", UIParent)
    frame:SetSize(160, 60)
    frame:SetFrameStrata("LOW")
    frame:EnableMouse(false)

    text = frame:CreateFontString(nil, "OVERLAY")
    text:SetPoint("TOPLEFT")
    text:SetJustifyH("LEFT")
    frame.text = text

    frame.mover = ns:CreateMover(frame, {
        key      = "qol_stats",
        label    = L["Secondary stats"],
        db       = db,
        module   = "qol",
        width    = 160,
        height   = 60,
        scalable = true,
    })
    applySettings()
    ns:ApplyMover(frame.mover)
    return frame
end
Stats.Frame = function() return create() end

-- The stat events come in bursts during a fight, so the block redraws at once
-- and again when the burst has settled -- two paints per window, and the first
-- one is not the one that waits.
local repaintPending = false
local function onStatEvent()
    if repaintPending then return end
    repaintPending = true
    update()
    C_Timer.After(0.5, function()
        repaintPending = false
        update()
    end)
end

local UNIT_EVENTS = { "UNIT_STATS", "UNIT_ATTACK_POWER", "UNIT_RANGED_ATTACK_POWER", "UNIT_SPELL_HASTE" }
local EVENTS = {
    "COMBAT_RATING_UPDATE", "PLAYER_EQUIPMENT_CHANGED", "MASTERY_UPDATE",
    "SPELL_POWER_CHANGED", "PLAYER_DAMAGE_DONE_MODS", "PLAYER_ENTERING_WORLD",
    "TRAIT_CONFIG_UPDATED",
    -- The figures stay live through a fight, but the block cannot be MEASURED
    -- while one of them is secret; this is the edge that catches its footprint
    -- back up afterwards.
    "PLAYER_REGEN_ENABLED",
}

function Stats.Apply()
    local on = QoL.db().stats.enabled and true or false
    for _, ev in ipairs(UNIT_EVENTS) do QoL.SyncEvent(on, ev, onStatEvent) end
    for _, ev in ipairs(EVENTS) do QoL.SyncEvent(on, ev, onStatEvent) end

    if not on then
        if frame then frame:Hide() end
        return
    end
    create()
    applySettings()
    classHex = nil          -- the colour mode may just have changed
    ns:ApplyMover(frame.mover)
    frame:Show()
    update()
end

function Stats.Disable()
    for _, ev in ipairs(UNIT_EVENTS) do ns:UnregisterEvent(ev, onStatEvent) end
    for _, ev in ipairs(EVENTS) do ns:UnregisterEvent(ev, onStatEvent) end
    if frame then frame:Hide() end
end
