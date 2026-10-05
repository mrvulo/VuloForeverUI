-- VuloForeverUI / Modules / ActionBars / Uprank
--
-- "A new rank takes the old one's place on the bars."
--
-- WHICH SLOTS, AND WHICH NOT
--
-- Only the rank that was your HIGHEST until a moment ago is swapped. A lower
-- rank that sits on a bar was put there on purpose -- the cheap heal, the
-- small rank for downranking -- and stays where it is.
--
-- So the module keeps one table: for every spell name, the highest rank in
-- the spellbook. When the client says a spell was learned, the table still
-- holds the rank that was highest BEFORE it, every slot carrying exactly that
-- rank gets the new one, and the table is read again.
--
-- WHEN
--
-- PickupSpell and PlaceAction are refused in a fight. Learning happens at a
-- trainer, so this almost never matters; when it does, the swap waits for the
-- fight to end. Something already on the cursor is never thrown away either:
-- the swap waits until the cursor is empty.
local _, ns = ...
local AB = ns.AB

local Uprank = {}
AB.Uprank = Uprank

local MAX_SLOT = 180            -- every action slot the client has

local highest = {}              -- spell name -> highest known spell ID
local learned = {}              -- spell IDs learned since the last pass

local function enabled()
    local db = AB.db()
    return AB.mod.active and db and db.autoUprank
end

-- ---------------------------------------------------------------- spellbook --

local function rescan()
    wipe(highest)
    local SB = C_SpellBook
    local bank = Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
    if not (SB and bank and SB.GetNumSpellBookSkillLines) then return end
    local spellType = Enum.SpellBookItemType and Enum.SpellBookItemType.Spell
    for line = 1, SB.GetNumSpellBookSkillLines() or 0 do
        local info = SB.GetSpellBookSkillLineInfo(line)
        if info and not info.shouldHide then
            local first = (info.itemIndexOffset or 0) + 1
            for index = first, first + (info.numSpellBookItems or 0) - 1 do
                local item = SB.GetSpellBookItemInfo(index, bank)
                if item and item.spellID and item.name and item.itemType == spellType
                    and not item.isPassive and not item.isOffSpec
                    -- the spellbook may list every rank; only the top one counts
                    and not (SB.IsSpellBookItemLowRank and SB.IsSpellBookItemLowRank(index, bank)) then
                    highest[item.name] = highest[item.name] or item.spellID
                end
            end
        end
    end
end

-- ---------------------------------------------------------------- swap --

local function placeIn(slot, spellID)
    ClearCursor()
    C_Spell.PickupSpell(spellID)
    if not GetCursorInfo() then return false end
    PlaceAction(slot)           -- the old rank lands on the cursor ...
    ClearCursor()               -- ... and goes, it is still in the spellbook
    return true
end

local function swap()
    if not enabled() then wipe(learned); return end
    if InCombatLockdown() then
        ns:RunOutOfCombatOnce("actionbars.uprank", swap)
        return
    end
    -- Something the player is carrying: wait for the cursor to be free.
    if GetCursorInfo() then
        C_Timer.After(1, swap)
        return
    end

    -- old rank ID -> new rank ID, from the table as it was before the learn
    local replace = {}
    for id in pairs(learned) do
        local name = C_Spell.GetSpellName(id)
        local old = name and highest[name]
        if old and old ~= id then replace[old] = id end
    end
    wipe(learned)

    if next(replace) then
        for slot = 1, MAX_SLOT do
            local kind, id = GetActionInfo(slot)
            local new = kind == "spell" and replace[id]
            if new then placeIn(slot, new) end
        end
    end
    rescan()
end

-- ---------------------------------------------------------------- events --

function Uprank.RegisterEvents(mod)
    mod:RegisterEvent("PLAYER_ENTERING_WORLD", rescan)
    -- The spellbook changes for other reasons too (a talent, a form). Read it
    -- again then -- but never while a learn is waiting for its swap, or the
    -- rank it has to replace would already be gone from the table.
    mod:RegisterEvent("SPELLS_CHANGED", function()
        if next(learned) == nil then rescan() end
    end)
    -- The new spell first, the spellbook update after it: the swap runs a
    -- frame later, once the client has filed the new rank.
    mod:RegisterEvent("LEARNED_SPELL_IN_SKILL_LINE", function(_, spellID)
        if type(spellID) ~= "number" or not enabled() then return end
        learned[spellID] = true
        ns.NextFrame(swap)
    end)
    if IsLoggedIn() then rescan() end
end
