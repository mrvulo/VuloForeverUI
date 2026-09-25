-- VuloForeverUI / Modules / Nameplates / Import
--
-- Nameplate settings out of another suite's profile string. Reading the
-- string, finding the nameplate table in it and the type-checked copy are
-- Core/ForeignProfile.lua. The nameplate settings there carry the same names
-- and meanings as ours with two exceptions, translated below: the bar width is
-- an EXTRA on a fixed 150 there (6 by default), and the overlay textures are
-- names of their own media that do not exist here.
--
-- Our nested tables (text slots, aura groups, icon slots) are built
-- differently from anything that section carries and are left alone.
local _, ns = ...
local L = ns.L
local NP = ns.NP

-- Whether the module is on is the player's choice here, and the saved-CVar
-- bookkeeping belongs to this client.
local SKIP = { enabled = true, savedCVars = true, savedStacking = true }

--- Returns the number of settings taken over, or nil and an error line.
function NP.ImportForeignString(text)
    local FP = ns.ForeignProfile
    local mod = ns.modules.nameplates
    local db = mod and mod.db
    if not (db and mod.defaults) then return nil, L["The nameplate settings are not loaded."] end

    local payload = FP.Decode(text)
    if not payload then return nil, L["This is not a profile string that can be read."] end
    local section = FP.FindSection(payload, mod.defaults, 15)
    if not section then return nil, L["The string carries no nameplate settings."] end

    local src = FP.Copy(section)
    if type(src.healthBarWidth) == "number" then
        src.healthBarWidth = math.max(100, math.min(250, 150 + src.healthBarWidth))
    end
    -- An overlay name unknown here would fall back to a solid white fill over
    -- the whole bar; such an overlay is switched off instead.
    for _, k in ipairs({ "targetOverlayTexture", "focusOverlayTexture", "hoverOverlayTexture" }) do
        local v = src[k]
        if type(v) == "string" and v ~= "none" and not (ns.MediaStatusbarValid and ns.MediaStatusbarValid(v)) then
            src[k] = "none"
        end
    end

    local taken = FP.Apply(db, mod.defaults, src, SKIP)

    -- Everything that reads a setting once rather than on every paint.
    NP.ApplyCVars()
    NP.ApplyHitbox()
    NP.ApplyShowEnemies()
    NP.Bump()
    -- a kind that gained or lost its slot, or a slot of another size, needs
    -- its aura container built anew
    if NP.Auras and NP.Auras.Rebuild then NP.Auras.Rebuild() end
    return taken
end
