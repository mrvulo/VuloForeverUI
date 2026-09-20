-- VuloForeverUI / Modules / Nameplates / Kick
--
-- The player's interrupt and its cooldown, for the cast bar's "can I stop this"
-- colour and the mark where the interrupt comes ready.
--
-- Which spell it is comes from the SPELLBOOK -- plain data about the player --
-- never from anything the enemy reports. The cooldown is only ever held as a
-- duration object: in combat its numbers are secret, the object is not, and
-- IsZero() on it is a boolean the client folds into a colour for us.
local _, ns = ...
local NP = ns.NP

local Kick = {}
NP.Kick = Kick

-- Kick, Pummel, Shield Bash, Counterspell, Earth Shock, Silence; then the
-- felhunter's Spell Lock, which lives in the pet's book. `/vfsecrets np` names
-- the one this client knows.
local PLAYER_SPELLS = { 1766, 6552, 72, 2139, 8042, 15487 }
local PET_SPELLS    = { 19647, 19244 }

local spell

local function known(id, bank)
    local ok, res
    if bank then
        ok, res = pcall(C_SpellBook.IsSpellKnownOrInSpellBook, id, bank)
    else
        ok, res = pcall(C_SpellBook.IsSpellKnownOrInSpellBook, id)
    end
    return ok and res == true
end

function Kick.Resolve()
    spell = nil
    local petBank = Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Pet
    if petBank then
        for _, id in ipairs(PET_SPELLS) do
            if known(id, petBank) then spell = id; return end
        end
    end
    for _, id in ipairs(PLAYER_SPELLS) do
        if known(id) then spell = id; return end
    end
end

function Kick.Spell() return spell end

-- The cooldown as a duration object, or nil without an interrupt.
function Kick.Duration()
    if not spell or not C_Spell.GetSpellCooldownDuration then return nil end
    local ok, d = pcall(C_Spell.GetSpellCooldownDuration, spell)
    if ok and ns.Exists(d) then return d end
    return nil
end
