-- VuloForeverUI / Modules / QoL / FishingGear
--
-- The rest of the fishing outfit: a hat, boots, gloves with the fishing
-- enchant -- whatever in the bags adds more to Fishing than what is worn
-- goes on with the fishing key, and what came off goes back on mounting,
-- together with the weapons (Fishing.lua).
--
-- The bonus is read from the item's tooltip: a line that names the Fishing
-- skill and carries a number ("Equip: Increased Fishing +5.", an enchant
-- line "Fishing +2"), never the "Requires Fishing (100)" line. The client
-- writes these in the player's language, so the skill name and the
-- requirement format come from the client too. Read once per item link.
--
-- Only bound items: equipping an unbound one would open the client's bind
-- confirmation on every press. Equipping armour is not protected out of
-- combat, and the key's PreClick only runs out of combat.
local _, ns = ...

local QoL = ns.QoL
local Fish = QoL.Fishing

local FISHING_SPELL = 7620
local THROTTLE = 1                         -- PreClick runs on both edges of a press

-- Armour slots only: rings and trinkets have two slots each, and a fishing
-- bonus there is a rarity not worth guessing which of the two to replace.
local SLOTS = {
    INVTYPE_HEAD = 1, INVTYPE_NECK = 2, INVTYPE_SHOULDER = 3,
    INVTYPE_CHEST = 5, INVTYPE_ROBE = 5, INVTYPE_WAIST = 6, INVTYPE_LEGS = 7,
    INVTYPE_FEET = 8, INVTYPE_WRIST = 9, INVTYPE_HAND = 10, INVTYPE_CLOAK = 15,
}

local cache = {}                           -- item link -> { bonus, needs }
local skillName, requiresPattern, usePrefix
local lastWear = 0

-- "Requires %s (%d)" -> a Lua pattern for that line in the client's language.
local function toPattern(fmt)
    if type(fmt) ~= "string" or fmt == "" then return nil end
    local p = fmt:gsub("%%%d?%$?[sd]", "\001")
    p = p:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
    return (p:gsub("\001", ".+"))
end

local function strings()
    if skillName then return true end
    local name = C_Spell.GetSpellName(FISHING_SPELL)
    if type(name) ~= "string" or name == "" then return false end
    skillName = name
    requiresPattern = toPattern(_G.ITEM_MIN_SKILL)
    usePrefix = type(_G.ITEM_SPELL_TRIGGER_ONUSE) == "string" and _G.ITEM_SPELL_TRIGGER_ONUSE or nil
    return true
end

-- bonus, skill needed: the "Requires Fishing (100)" line is a need, not a bonus
local function lineBonus(text)
    if type(text) ~= "string" or not ns.CanRead(text) then return 0, 0 end
    if not text:find(skillName, 1, true) then return 0, 0 end
    if requiresPattern and text:find(requiresPattern) then
        return 0, tonumber(text:match("(%d+)%D*$")) or 0
    end
    if usePrefix and text:sub(1, #usePrefix) == usePrefix then return 0, 0 end
    return tonumber(text:match("(%d+)")) or 0, 0
end

-- nil when the tooltip is not there yet (item data still loading): not cached
local function tooltipBonus(data)
    if type(data) ~= "table" or type(data.lines) ~= "table" or #data.lines < 2 then return nil end
    local sum, needs = 0, 0
    -- line 1 is the item's name, which may well contain the word
    for i = 2, #data.lines do
        local line = data.lines[i]
        if type(line) == "table" then
            local b, n = lineBonus(line.leftText)
            sum = sum + b
            if n > needs then needs = n end
        end
    end
    return { bonus = sum, needs = needs }
end

-- An item the character's skill is still too low for counts as no bonus:
-- the equip would fail with a red error on every press. The need is cached,
-- the comparison is not -- the skill rises while fishing.
local function bonusOf(link, read)
    if type(link) ~= "string" then return 0 end
    local e = cache[link]
    if not e then
        if not strings() then return 0 end
        local ok, data = pcall(read)
        e = ok and tooltipBonus(data) or nil
        if not e then return 0 end
        cache[link] = e
    end
    if e.needs > 0 and (Fish.Skill() or 0) < e.needs then return 0 end
    return e.bonus
end

function Fish.BagBonus(bag, slot)
    local link = C_Container.GetContainerItemLink(bag, slot)
    return bonusOf(link, function() return C_TooltipInfo.GetBagItem(bag, slot) end)
end

local function wornBonus(slot)
    local link = GetInventoryItemLink("player", slot)
    return bonusOf(link, function() return C_TooltipInfo.GetInventoryItem("player", slot) end)
end

local function isBound(bag, slot)
    if not (C_Item.IsBound and ItemLocation and ItemLocation.CreateFromBagAndSlot) then return false end
    local ok, bound = pcall(C_Item.IsBound, ItemLocation:CreateFromBagAndSlot(bag, slot))
    return ok and bound == true
end

-- The best fishing piece per armour slot in the bags, where it beats what is
-- worn. What comes off is noted once per slot, so later presses keep the
-- player's own piece as the one to go back.
function Fish.WearGear()
    if InCombatLockdown() or GetTime() - lastWear < THROTTLE then return end
    lastWear = GetTime()
    local best = {}
    for _, bag in ipairs(ns.CarriedBags()) do
        for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
            local id = C_Container.GetContainerItemID(bag, slot)
            if id then
                local _, _, _, equipLoc = C_Item.GetItemInfoInstant(id)
                local inv = SLOTS[equipLoc]
                if inv then
                    local b = Fish.BagBonus(bag, slot)
                    if b > 0 and (not best[inv] or b > best[inv].bonus) and isBound(bag, slot) then
                        best[inv] = { bonus = b, id = id, link = C_Container.GetContainerItemLink(bag, slot) }
                    end
                end
            end
        end
    end
    if not next(best) then return end
    local c = Fish.CharDB()
    for inv, cand in pairs(best) do
        if cand.bonus > wornBonus(inv) then
            if type(c.gearBack) ~= "table" then c.gearBack = {} end
            local note = c.gearBack[inv]
            if type(note) ~= "table" then
                note = { back = GetInventoryItemLink("player", inv) or false }
                c.gearBack[inv] = note
            end
            note.put = cand.id
            C_Item.EquipItemByName(cand.link, inv)
        end
    end
end

-- On mounting: every noted slot that still wears the fishing piece gets the
-- player's own piece back. A slot that was empty keeps the fishing piece --
-- there is nothing to put on, and taking it off needs bag room.
function Fish.GearBack()
    local c = Fish.CharDB()
    local notes = c.gearBack
    if type(notes) ~= "table" then return end
    if InCombatLockdown() or UnitIsDeadOrGhost("player") then return end
    c.gearBack = nil
    if not Fish.db().swapBack then return end
    for inv, note in pairs(notes) do
        if type(note) == "table" and note.back and GetInventoryItemID("player", inv) == note.put
            and C_Item.GetItemCount(note.back) > 0 then
            C_Item.EquipItemByName(note.back, inv)
        end
    end
end
