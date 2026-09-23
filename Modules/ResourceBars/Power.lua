-- VuloForeverUI / Modules / ResourceBars / Power
--
-- The power bar, and the second one a form brings with it.
--
-- THE WHOLE DISPLAY WITHOUT READING A NUMBER
--
-- The player's own power is secret on this client even out of combat, and the
-- max is not. That split decides everything here:
--
--   fill       SetMinMaxValues(0, max) + SetValue(secret) -- the widget takes
--              a secret and does the maths itself (ns:SetPowerFill)
--   colour     UnitPowerPercent("player", type, true, curve): the fourth
--              argument is a COLOUR CURVE, the client evaluates the secret
--              percent against it C-side and hands back a Color. This is the
--              only route to a threshold colour; a comparison in Lua throws
--   text       SetFormattedText("%d", secret) -- formatting is allowed, and
--              the number never becomes ours
--   ticks      typed by the player, so plain data, drawn from the max
--
-- What IS read: the power TYPE and its max, both readable, and both about what
-- kind of resource we have rather than how much of it is left.
local _, ns = ...
local L = ns.L
local RB = ns.RB

local Power = {}
RB.Power = Power

local MANA = (Enum.PowerType and Enum.PowerType.Mana) or 0

-- The client's own colour per power, with a fallback for a type it does not
-- name. PowerBarColor is keyed by token ("RAGE") and by type on retail.
local function typeColor(powerType, token)
    local c = _G.PowerBarColor
    local entry = c and ((token and c[token]) or c[powerType])
    if entry and entry.r then return entry.r, entry.g, entry.b end
    return 0.2, 0.45, 0.95
end

-- What the player runs on right now. Both answers stay readable on this
-- client; the amount does not, and is never asked for.
local primaryType, primaryToken

function Power.Rescan()
    local t, token = UnitPowerType("player")
    if ns.CanRead(t) and type(t) == "number" then
        primaryType, primaryToken = t, (ns.CanRead(token) and token) or nil
    end
    Power.Restyle()
    Power.Update()
end

-- The colours and the suppression: which of the two bars has anything to say.
function Power.Restyle()
    local powerBar, manaBar = RB.Bar("power"), RB.Bar("mana")
    local powerFrame, manaFrame = RB.frames.power, RB.frames.mana
    if powerFrame and powerBar and powerBar.useTypeColor then
        local r, g, b = typeColor(primaryType, primaryToken)
        powerFrame.fill:SetStatusBarColor(r, g, b)
    end

    if manaFrame and manaBar then
        -- The second bar is for the mana a form hides, so it has nothing to
        -- show while mana IS the primary power. "Which power is primary" is
        -- readable; "how much of it" is not, and is not what this asks.
        local max = UnitPowerMax("player", MANA)
        local hasMana = ns.CanRead(max) and type(max) == "number" and max > 0
        local isPrimary = (primaryType == MANA)
        manaFrame.suppressed = (not hasMana) or (manaBar.onlyInForms and isPrimary)
        RB.UpdateVisibility("mana")
    end
end

-- ---------------------------------------------------------------- threshold --

-- A two point step curve: the threshold colour up to the mark, the fill colour
-- above it. Rebuilt only when one of its seven inputs changed -- this runs on
-- every power event, twice per bar, and a rebuild per tick would allocate a
-- curve and seven colours for an unchanged answer.
local curveCache = {}

local function thresholdCurve(key, r1, g1, b1, r2, g2, b2, pct)
    if not (C_CurveUtil and C_CurveUtil.CreateColorCurve and CreateColor) then return nil end
    local c = curveCache[key]
    if c and c.r1 == r1 and c.g1 == g1 and c.b1 == b1
       and c.r2 == r2 and c.g2 == g2 and c.b2 == b2 and c.pct == pct then
        return c.curve
    end

    local ok, curve = pcall(C_CurveUtil.CreateColorCurve)
    if not ok or not curve then return nil end
    local t = math.max(0, math.min(1, pct / 100))
    local EPS = 0.0001
    curve:AddPoint(0.0, CreateColor(r1, g1, b1, 1))
    if t > EPS then curve:AddPoint(t, CreateColor(r1, g1, b1, 1)) end
    if t < 1.0 then curve:AddPoint(math.min(1, t + EPS), CreateColor(r2, g2, b2, 1)) end
    curve:AddPoint(1.0, CreateColor(r2, g2, b2, 1))

    curveCache[key] = { curve = curve, r1 = r1, g1 = g1, b1 = b1,
                        r2 = r2, g2 = g2, b2 = b2, pct = pct }
    return curve
end

local function applyThreshold(key, bar, frame, powerType)
    local pct = tonumber(bar.thresholdPct) or 0
    if pct <= 0 or not UnitPowerPercent then return false end

    local baseR, baseG, baseB
    if bar.useTypeColor then
        baseR, baseG, baseB = typeColor(primaryType, primaryToken)
    else
        baseR, baseG, baseB = bar.fillColor.r, bar.fillColor.g, bar.fillColor.b
    end
    local tc = bar.thresholdColor
    local curve = thresholdCurve(key, tc.r, tc.g, tc.b, baseR, baseG, baseB, pct)
    if not curve then return false end

    -- The colour that comes back may itself be secret. It goes straight into
    -- the setter; nothing looks at it.
    -- Its channels are read inside the pcall, as the unit frames do.
    local ok, r, g, b = pcall(function()
        return UnitPowerPercent("player", powerType, true, curve):GetRGB()
    end)
    if ok then
        frame.fill:SetStatusBarColor(r, g, b)
        return true
    end
    return false
end

-- ---------------------------------------------------------------- text --

-- Looked up when it is needed, not when the file loads: the constants table
-- is another addon-visible global that may not exist yet at load time.
local function scaleTo100()
    return _G.CurveConstants and _G.CurveConstants.ScaleTo100
end

-- Does this client hand out a power percentage at all? Core/Secret.lua says
-- flatly that it does not ("Power has no percent API"), and this module is the
-- first place that needs one, so the answer is probed once rather than assumed
-- -- and a "no" means the percent text stays EMPTY. Falling through to the raw
-- value, which is what an earlier draft did, put "40" where a player had asked
-- for "40%" and looked like a working setting.
local function hasPercent()
    return UnitPowerPercent ~= nil and scaleTo100() ~= nil
end

local function setValueText(frame, bar, powerType)
    local mode = bar.rightText or "value"
    if mode == "none" then frame.right:SetText(""); return end

    -- A power bar has no remaining time; the cast and swing bars do. Rather
    -- than print something else, it prints nothing.
    if mode == "time" then frame.right:SetText(""); return end

    if mode == "percent" then
        if hasPercent() then
            local ok, pct = pcall(UnitPowerPercent, "player", powerType, true, scaleTo100())
            if ok and type(pct) ~= "nil" then
                -- The percent may be secret; the format string is ours and the
                -- engine does the writing.
                local okf = pcall(frame.right.SetFormattedText, frame.right, "%d%%", pct)
                if okf then return end
            end
        end
        frame.right:SetText("")
        return
    end

    local cur = UnitPower("player", powerType)
    local max = UnitPowerMax("player", powerType)
    if mode == "valuemax" then
        local ok = pcall(frame.right.SetFormattedText, frame.right, "%d / %d", cur, max)
        if not ok then frame.right:SetText("") end
        return
    end
    local ok = pcall(frame.right.SetFormattedText, frame.right, "%d", cur)
    if not ok then frame.right:SetText("") end
end

-- ---------------------------------------------------------------- update --

local function updateOne(key, powerType, label)
    local frame, bar = RB.frames[key], RB.Bar(key)
    if not (frame and bar) then return end
    if type(powerType) ~= "number" then return end

    ns:SetPowerFill(frame.fill, "player", powerType)

    local max = UnitPowerMax("player", powerType)
    if ns.CanRead(max) and type(max) == "number" and max ~= frame.maxValue then
        frame.maxValue = max
        RB.ApplyTicks(key, max)
    end

    if not applyThreshold(key, bar, frame, powerType) then
        if bar.useTypeColor then
            local r, g, b = typeColor(primaryType, primaryToken)
            frame.fill:SetStatusBarColor(r, g, b)
        else
            frame.fill:SetStatusBarColor(bar.fillColor.r, bar.fillColor.g, bar.fillColor.b)
        end
    end

    RB.SetLeftText(key, nil, label)
    setValueText(frame, bar, powerType)
end

function Power.Update()
    if type(primaryType) ~= "number" then
        local t, token = UnitPowerType("player")
        if ns.CanRead(t) and type(t) == "number" then
            primaryType, primaryToken = t, (ns.CanRead(token) and token) or nil
        else
            return
        end
    end
    updateOne("power", primaryType, L["Power"])
    updateOne("mana", MANA, L["Mana"])
end
