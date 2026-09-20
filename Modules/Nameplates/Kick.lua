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

-- Every RANK of every interrupt, because a Classic-shaped spellbook gives each
-- rank its own id: a shaman at rank 3 does not "know" 8042. Highest rank first,
-- so the id we settle on is the one the player actually casts.
--   Kick, Shield Bash, Pummel, Counterspell, Earth Shock, Silence,
--   Feral Charge; then the felhunter's Spell Lock, which is in the pet's book.
-- `/vfsecrets np` prints each id with the name this client gives it -- Forever
-- renumbers some spells (the GCD spell is 29515 here, not 61304), so an id that
-- resolves to nothing is a wrong id, not a missing spell.
local PLAYER_SPELLS = {
    1769, 1768, 1767, 1766,                          -- Kick
    1672, 1671, 72,                                  -- Shield Bash
    6554, 6552,                                      -- Pummel
    2139,                                            -- Counterspell
    10414, 10413, 10412, 8046, 8045, 8044, 8042,     -- Earth Shock
    15487,                                           -- Silence
    16979,                                           -- Feral Charge
}
local PET_SPELLS = { 19647, 19244 }                  -- Spell Lock

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
