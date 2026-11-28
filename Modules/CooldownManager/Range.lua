-- VuloForeverUI / Modules / CooldownManager / Range
--
-- Two colours on a spell's icon, the way an action bar button wears them:
--   red    your target is out of this spell's range
--   blue   you lack the mana, rage or energy for it
--
-- Both answers may be secret in a fight, so neither is ever tested here. The
-- red is a tinted layer over the icon whose alpha the engine folds from "in
-- range"; the blue is the icon's own vertex colour, folded from "not enough
-- power". No answer (no target, a spell without a range) leaves the icon as
-- it is.
--
-- The client only reports range for spells it was asked to watch
-- (C_Spell.EnableSpellRangeCheck); its event then says that SOMETHING
-- changed, and every red layer is asked again. The spell id it carries may be
-- secret, so it is never used as a key.
local _, ns = ...
local CM = ns.CM

local Range = {}
CM.Range = Range

local RED = { 1, 0.1, 0.1, 0.55 }
local POWER = { 0.35, 0.45, 1 }
local watched = {}          -- spell id -> true once the client watches it

local function layer(icon)
    local t = icon.range
    if t then return t end
    t = icon.button:CreateTexture(nil, "ARTWORK", nil, 2)
    t:SetAllPoints(icon.texture)
    t:SetColorTexture(RED[1], RED[2], RED[3], RED[4])
    t:SetAlpha(0)
    icon.range = t
    return t
end

local function paintRange(icon)
    local t = icon.range
    if not t then return end
    local id = icon.rangeSpell
    if not id or not icon.button:IsShown() then t:SetAlpha(0); return end
    local inRange = C_Spell.IsSpellInRange(id, "target")
    -- nil: no target, or a spell with no range -- nothing to warn about
    if type(inRange) == "nil" then t:SetAlpha(0); return end
    ns.AlphaFromBool(t, inRange, 0, 1)
end

-- From the paint pass, for every icon. A spell row gets both colours as the
-- bar or the row asks; anything else is left untinted.
function Range.Paint(bar, icon, entry, rid, rkind)
    local spell = rkind == "spell" and type(rid) == "number" and rid or nil

    -- No red over art that is hidden or faded (numbers only, a buff row
    -- without its buff): the red square would be all that is left.
    local wantRange = spell and (icon.artAlpha or 1) >= 1 and CM.Val(bar, entry, "rangeColor") ~= false
    if wantRange then
        local t = layer(icon)
        -- the layer follows the icon's shape, like the icon art does
        local shape = CM.SHAPES[icon.shapeName or "square"] or CM.SHAPES.square
        local want = (icon.mask and shape.mask) and true or false
        if want ~= (icon.rangeMasked or false) then
            if want then pcall(t.AddMaskTexture, t, icon.mask)
            else pcall(t.RemoveMaskTexture, t, icon.mask) end
            icon.rangeMasked = want
        end
        icon.rangeSpell = spell
        if not watched[spell] and C_Spell.EnableSpellRangeCheck then
            watched[spell] = true
            pcall(C_Spell.EnableSpellRangeCheck, spell, true)
        end
        paintRange(icon)
    else
        icon.rangeSpell = nil
        if icon.range then icon.range:SetAlpha(0) end
    end

    if spell and CM.Val(bar, entry, "powerColor") ~= false then
        local _, noPower = C_Spell.IsSpellUsable(spell)
        if type(noPower) == "nil" then noPower = false end
        icon.texture:SetVertexColor(ns.FoldColor(noPower, POWER[1], POWER[2], POWER[3], 1, 1, 1))
    else
        icon.texture:SetVertexColor(1, 1, 1)
    end
end

-- Every red layer on every bar, asked again. Cheap: one client call per icon.
function Range.UpdateAll()
    local db = CM.db()
    for _, key in ipairs(db and db.barOrder or {}) do
        local frame = CM.frames[key]
        for _, icon in ipairs(frame and frame.icons or {}) do paintRange(icon) end
    end
end
