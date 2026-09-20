-- VuloForeverUI / Modules / Nameplates / Health
--
-- Fill, absorb and health text of one plate.
--
-- UnitHealth of a nameplate unit is ALWAYS secret, and the absorb amount with
-- it. So there is one path, and it never computes: the client's heal-prediction
-- calculator hands us current health, the maximum WITH absorbs and the absorb
-- amount; all three go straight into StatusBar setters. The absorb bar hangs on
-- the right edge of the health fill and shares its range, so it ends exactly
-- where health plus shield ends -- geometry does the addition.
local _, ns = ...
local NP = ns.NP

local Health = {}
NP.Health = Health

local WHITE = "Interface\\Buttons\\WHITE8X8"
local ABSORB_ATLAS_FILL = "Interface\\RaidFrame\\Shield-Fill"

local function newCalculator()
    if not CreateUnitHealPredictionCalculator then return nil end
    local calc = CreateUnitHealPredictionCalculator()
    local maxMode, clamp = Enum.UnitMaximumHealthMode, Enum.UnitDamageAbsorbClampMode
    if maxMode and calc.SetMaximumHealthMode then calc:SetMaximumHealthMode(maxMode.WithAbsorbs) end
    if clamp and calc.SetDamageAbsorbClampMode then calc:SetDamageAbsorbClampMode(clamp.MaximumHealth) end
    return calc
end

function Health.Build(plate)
    local health = plate.health

    -- Clipped to the bar: the absorb bar is as wide as the whole plate and
    -- starts at the health fill's edge, so most of it lies outside.
    local clip = CreateFrame("Frame", nil, health)
    clip:SetAllPoints(health)
    clip:SetClipsChildren(true)
    clip:SetFrameLevel(health:GetFrameLevel() + 1)

    local absorb = CreateFrame("StatusBar", nil, clip)
    absorb:SetStatusBarTexture(WHITE)
    absorb:SetPoint("TOPLEFT", health:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
    absorb:SetPoint("BOTTOMLEFT", health:GetStatusBarTexture(), "BOTTOMRIGHT", 0, 0)
    plate.absorb = absorb

    -- The hash line: a mark at N % of the bar, shown on the target only.
    local hash = clip:CreateTexture(nil, "OVERLAY")
    hash:SetColorTexture(1, 1, 1, 1)
    hash:Hide()
    plate.hashLine = hash

    plate.calc = newCalculator()
end

function Health.ApplyAppearance(plate)
    local db = NP.db()
    local absorb = plate.absorb
    absorb:SetWidth(db.healthBarWidth)
    local style, col = db.absorbStyle, db.absorbColor
    if style == "blizzard" then
        absorb:SetStatusBarTexture(ABSORB_ATLAS_FILL)
        absorb:SetStatusBarColor(1, 1, 1, db.absorbAlpha / 100)
    elseif style == "clean" then
        absorb:SetStatusBarTexture(WHITE)
        absorb:SetStatusBarColor(col.r, col.g, col.b, db.absorbAlpha / 100)
    else
        absorb:SetStatusBarTexture(ns.MediaStatusbar(style, WHITE))
        absorb:SetStatusBarColor(col.r, col.g, col.b, db.absorbAlpha / 100)
    end
    -- SetStatusBarTexture can hand the bar a new fill texture object
    absorb:ClearAllPoints()
    absorb:SetPoint("TOPLEFT", plate.health:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
    absorb:SetPoint("BOTTOMLEFT", plate.health:GetStatusBarTexture(), "BOTTOMRIGHT", 0, 0)

    local hash, hc = plate.hashLine, db.hashLineColor
    hash:SetColorTexture(hc.r, hc.g, hc.b, 1)
    hash:ClearAllPoints()
    hash:SetPoint("TOP", plate.health, "TOPLEFT", db.healthBarWidth * db.hashLinePercent / 100, 0)
    hash:SetPoint("BOTTOM", plate.health, "BOTTOMLEFT", db.healthBarWidth * db.hashLinePercent / 100, 0)
    hash:SetWidth(NP.Pixel(plate, 1))
end

-- ---------------------------------------------------------------------------
-- Fill
-- ---------------------------------------------------------------------------
function Health.Update(plate)
    local unit = plate.unit
    if not unit then return end
    local health, calc = plate.health, plate.calc
    if calc then
        UnitGetDetailedHealPrediction(unit, nil, calc)
        local max = calc:GetMaximumHealth()
        health:SetMinMaxValues(0, max)
        health:SetValue(calc:GetCurrentHealth())
        plate.absorb:SetMinMaxValues(0, max)
        plate.absorb:SetValue((calc:GetDamageAbsorbs()))
    else
        -- The maximum only moves on UNIT_MAXHEALTH; maxValid is OUR flag, so
        -- this branch never depends on anything the unit reports.
        if not plate.maxValid then
            health:SetMinMaxValues(0, UnitHealthMax(unit))
            plate.maxValid = true
        end
        health:SetValue(UnitHealth(unit))
    end
    Health.UpdateText(plate)
    NP.Extras.UpdateExecute(plate)
end

-- ---------------------------------------------------------------------------
-- Text. The number never passes through our hands as a number: the percent
-- comes out of the client scaled to 0..100 and goes into SetFormattedText as a
-- format ARGUMENT, which the widget accepts from a secret. The unit frames of
-- this addon show health the same way (Modules/UnitFrames/Engine.lua).
-- ---------------------------------------------------------------------------
local DASH = { healthPctNumDash = true, healthNumPctDash = true }
local NUMBER_FIRST = { healthNumPct = true, healthNumPctDash = true }

local scaleTo100
local function percentScale()
    if scaleTo100 == nil then
        scaleTo100 = (CurveConstants and CurveConstants.ScaleTo100) or false
    end
    return scaleTo100 or nil
end

local function writeHealth(fs, element, unit, decimal)
    local pct = UnitHealthPercent(unit, true, percentScale())
    local pctFmt = decimal and "%.1f" or "%d"
    if element == "healthPercent" then
        fs:SetFormattedText(pctFmt .. "%%", pct)
    elseif element == "healthPercentNoSign" then
        fs:SetFormattedText(pctFmt, pct)
    elseif element == "healthNumber" then
        fs:SetFormattedText("%s", AbbreviateNumbers(UnitHealth(unit)))
    else
        local num = AbbreviateNumbers(UnitHealth(unit))
        local sep = DASH[element] and " - " or " | "
        if NUMBER_FIRST[element] then
            fs:SetFormattedText("%s" .. sep .. pctFmt .. "%%", num, pct)
        else
            fs:SetFormattedText(pctFmt .. "%%" .. sep .. "%s", pct, num)
        end
    end
end

function Health.UpdateText(plate)
    local unit = plate.unit
    if not unit then return end
    local db = NP.db()
    for slot, fs in pairs(plate.texts) do
        local element = fs.element
        if NP.HEALTH_ELEMENTS[element] then
            local dead = UnitIsDeadOrGhost(unit)
            if ns.CanRead(dead) and dead then
                fs:SetText("0%")
            else
                -- One refusal must not take the bar down with it; the text
                -- simply stays empty on a client that will not format a secret.
                local ok = pcall(writeHealth, fs, element, unit, db.textSlots[slot].decimal)
                if not ok then fs:SetText("") end
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Coalescer. UNIT_HEALTH can fire many times per frame in a pull; the events
-- only mark the plate, one frame-driven pass draws each marked plate once. The
-- driver is hidden -- no OnUpdate at all -- while nothing is marked.
-- ---------------------------------------------------------------------------
local dirty, anyDirty = {}, false
local driver = CreateFrame("Frame")
driver:Hide()

local function onError(err) geterrorhandler()(err) end

driver:SetScript("OnUpdate", function(self)
    self:Hide()
    anyDirty = false
    for plate in pairs(dirty) do
        dirty[plate] = nil
        if plate.unit then xpcall(Health.Update, onError, plate) end
    end
end)

function Health.MarkDirty(plate)
    dirty[plate] = true
    if not anyDirty then
        anyDirty = true
        driver:Show()
    end
end

function Health.Forget(plate)
    dirty[plate] = nil
end
