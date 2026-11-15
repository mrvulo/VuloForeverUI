-- VuloForeverUI / Modules / QoL / Macros
--
-- The macro factory: macros in the character's own macro list that this
-- addon writes and keeps up to date -- food, drink, healthstone, healing
-- potion, mana potion, for the warlock a soulstone, a spellstone and a
-- firestone, for the mage a mana gem. Each one uses the best thing of its
-- kind that is in the bags and that the level allows, so the button on the
-- bar never has to be swapped.
--
-- Every ID and name below is read from THIS client's tables (item, item
-- effect, spell name, spell effect; build 1.60.1.70938, 2026-11-15) -- it
-- differs from the 1.x game: a spellstone and a firestone are not held in
-- the off hand here, they are used on the weapon like a poison, and food
-- that gives a buff is "Nutritious Food", not "Food".
--
-- WHAT COUNTS AS "ITS KIND"
--
--   food, drink   any consumable in the bags whose use effect carries the
--                 client's name for eating or drinking: the name of spell
--                 433 / 430 and, as a second witness, of the use effect of
--                 item 117 / 159. No item list -- whatever a vendor or a
--                 mage hands you counts. The buffing kind ("Nutritious
--                 Food" / "Nutritious Drink", spells 1248377 / 1249906)
--                 counts too, but last.
--   potions       the healing and the mana chain of the Reminder data
--                 (Supplies.lua, `kind`), plus every consumable whose use
--                 effect is named like one of theirs.
--   stones, gems  fixed lists, best first -- a stone the list does not
--                 know is not used.
--
-- The best one is the highest required level the character meets. Food
-- and drink that give a buff of their own come last, so the macro does not
-- eat the raid food for health.
--
-- A spellstone or firestone goes on the weapon: "/use item" and then the
-- main hand slot, the way the Reminder puts on a poison.
--
-- A warlock without a stone, a mage without a gem: the same macro casts
-- the best creating spell the character knows, and turns back into "use"
-- once the item is in the bags.
--
-- RULES
--   * A macro is written out of combat only, and only when its text differs.
--   * Nothing found: the text stays as it was, so the button keeps showing
--     the last item with a count of 0.
--   * The icon is the question mark; #showtooltip puts the item's on it.
--   * Switching one off in the options deletes it. Nothing else ever
--     deletes a macro -- not a profile change, not turning the module off --
--     because a deleted macro is gone from the bars as well.
local _, ns = ...
local L = ns.L

local QoL = ns.QoL
local Macros = QoL.RegisterPart("macros", {})
QoL.Macros = Macros

local ICON = 134400             -- INV_Misc_QuestionMark
local HEAD = "#showtooltip\n"

local NO_MANA = { WARRIOR = true, ROGUE = true }

-- best first; the second and third of a size are the talented versions
local HEALTHSTONES = { 19013, 19012, 9421, 19011, 19010, 5510, 19009, 19008, 5509,
    19007, 19006, 5511, 19005, 19004, 5512 }
local SOULSTONES   = { 16896, 16895, 16893, 16892, 5232 }
local MANA_GEMS    = { 8008, 8007, 5513, 5514 }
local SPELLSTONES  = { 13603, 13602, 5522 }
local FIRESTONES   = { 13701, 13700, 13699, 1254 }

-- the spells that make them, best first
local CREATE_HEALTHSTONE = { 11730, 11729, 5699, 6202, 6201 }
local CREATE_SOULSTONE   = { 20757, 20756, 20755, 20752, 693 }
local CONJURE_GEM        = { 10054, 10053, 3552, 759 }
local CREATE_SPELLSTONE  = { 17728, 17727, 2362 }
local CREATE_FIRESTONE   = { 17953, 17952, 17951, 6366 }

-- name: the macro's name in the client's list (fixed, it is how we find it
-- again). label, tip: locale keys. mana: only for a class with mana.
-- lateSpells: use effects that count, but only when nothing else is there.
-- weapon: the item is used on the main hand.
Macros.DEFS = {
    { key = "food",  name = "VF Food",  label = "Food",
      tip = "Eats the best food in your bags that your level allows. Food that gives a buff of its own comes last.",
      useSpells = { 433 }, useItems = { 117 }, lateSpells = { 1248377 } },
    { key = "drink", name = "VF Drink", label = "Drink", mana = true,
      tip = "Drinks the best drink in your bags that your level allows. A drink that gives a buff of its own comes last.",
      useSpells = { 430 }, useItems = { 159 }, lateSpells = { 1249906 } },
    { key = "stone", name = "VF Stone", label = "Healthstone",
      tip = "Uses the best healthstone in your bags. A warlock without one creates one with the same button.",
      list = HEALTHSTONES, spells = CREATE_HEALTHSTONE },
    { key = "heal",  name = "VF Heal",  label = "Healing potion",
      tip = "Drinks the best healing potion in your bags that your level allows.",
      chain = "heal" },
    { key = "mana",  name = "VF Mana",  label = "Mana potion", mana = true,
      tip = "Drinks the best mana potion in your bags that your level allows.",
      chain = "mana" },
    { key = "soul",  name = "VF Soul",  label = "Soulstone", class = "WARLOCK",
      tip = "Uses your soulstone. Without one in your bags the same button creates one.",
      list = SOULSTONES, spells = CREATE_SOULSTONE },
    { key = "spell", name = "VF Spell", label = "Spellstone", class = "WARLOCK",
      tip = "Puts your best spellstone on your weapon. Without one in your bags the same button creates one.",
      list = SPELLSTONES, spells = CREATE_SPELLSTONE, weapon = true },
    { key = "fire",  name = "VF Fire",  label = "Firestone", class = "WARLOCK",
      tip = "Puts your best firestone on your weapon. Without one in your bags the same button creates one.",
      list = FIRESTONES, spells = CREATE_FIRESTONE, weapon = true },
    { key = "gem",   name = "VF Gem",   label = "Mana gem", class = "MAGE",
      tip = "Uses the best mana gem in your bags. Without one the same button conjures one.",
      list = MANA_GEMS, spells = CONJURE_GEM },
}

local byKey = {}
for _, def in ipairs(Macros.DEFS) do byKey[def.key] = def end

local function db() return QoL.db().macros end

-- Is this macro one for the character at all?
function Macros.Fits(def)
    local class = UnitClassBase("player")
    if def.class and def.class ~= class then return false end
    if def.mana and NO_MANA[class] then return false end
    return true
end

-- ---------------------------------------------------------------- items --

-- An item the client has not loaded is asked for ONCE: an ID this client
-- does not have would otherwise be asked for again on every answer.
local asked = {}
local function ask(id)
    if asked[id] then return end
    asked[id] = true
    C_Item.RequestLoadItemDataByID(id)
end

-- Required level; nil while the client has not loaded the item.
local function minLevel(id)
    local name, _, _, _, lvl = C_Item.GetItemInfo(id)
    if name then return lvl or 0 end
    ask(id)
end

-- The name of an item's use effect, nil when it has none or is not loaded.
local function useName(id)
    local name = C_Item.GetItemSpell(id)
    if type(name) == "string" then return name end
    ask(id)
end

local function carried()
    local t = {}
    for bag = 0, 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local id = C_Container.GetContainerItemID(bag, slot)
            if id then t[id] = true end
        end
    end
    return t
end

-- The Reminder's verified chains as sets of item IDs: the two potion chains
-- by `kind`, and every food that gives a buff.
local chains
local function supply()
    if chains then return chains end
    chains = { heal = {}, mana = {}, food = {} }
    local R = ns.Reminder
    for _, c in ipairs(R and R.SUPPLIES or {}) do
        local to = (c.cat == "food" and chains.food) or (c.kind and chains[c.kind])
        if to then
            for _, it in ipairs(c.items) do to[it[1]] = true end
        end
    end
    return chains
end

local function better(a, b)
    if a.late ~= b.late then return not a.late end
    if a.lvl ~= b.lvl then return a.lvl > b.lvl end
    if a.count ~= b.count then return a.count < b.count end     -- finish the small stack
    return a.id < b.id
end

-- The best carried item: one of `ids`, or a consumable whose use effect is
-- named in `names` or `lateNames`. Late ones -- by that name, or an item in
-- the set `late` -- are taken only when nothing else is there.
local function best(names, ids, level, bags, late, lateNames)
    local pick
    for id in pairs(bags) do
        local hit = ids and ids[id]
        local isLate = late and late[id]
        if not hit then
            local _, _, _, _, _, classID = C_Item.GetItemInfoInstant(id)
            if classID == Enum.ItemClass.Consumable then
                local n = C_Item.GetItemSpell(id)
                if type(n) == "string" then
                    if lateNames[n] then hit, isLate = true, true end
                    if names[n] then hit = true end
                end
            end
        end
        if hit then
            local lvl = minLevel(id)
            if lvl and lvl <= level then
                local c = { id = id, lvl = lvl, count = C_Item.GetItemCount(id) or 0,
                    late = isLate and true or false }
                if not pick or better(c, pick) then pick = c end
            end
        end
    end
    return pick and pick.id
end

local function firstCarried(list, bags, level)
    for _, id in ipairs(list) do
        if bags[id] then
            local lvl = minLevel(id)
            if not lvl or lvl <= level then return id end
        end
    end
end

local function firstKnown(spells)
    for _, id in ipairs(spells) do
        if C_SpellBook.IsSpellKnown(id) then
            local name = C_Spell.GetSpellName(id)
            if type(name) == "string" then return name end
        end
    end
end

-- item to use, or (nil, name of the spell that makes one)
local function pick(def, level, bags)
    if def.list then
        local id = firstCarried(def.list, bags, level)
        if id then return id end
        return nil, def.spells and firstKnown(def.spells) or nil
    end
    local s = supply()
    local ids = def.chain and s[def.chain] or nil
    local names = {}
    for _, spell in ipairs(def.useSpells or {}) do
        local n = C_Spell.GetSpellName(spell)
        if type(n) == "string" then names[n] = true end
    end
    for _, item in ipairs(def.useItems or {}) do
        local n = useName(item)
        if n then names[n] = true end
    end
    if ids then
        for id in pairs(ids) do
            local n = useName(id)
            if n then names[n] = true end
        end
    end
    local lateNames = {}
    for _, spell in ipairs(def.lateSpells or {}) do
        local n = C_Spell.GetSpellName(spell)
        if type(n) == "string" and not names[n] then lateNames[n] = true end
    end
    return best(names, ids, level, bags, def.key == "food" and s.food or nil, lateNames)
end

-- The macro's text, nil when there is nothing to put in it.
local function body(def, level, bags)
    local id, cast = pick(def, level, bags)
    if id then
        return HEAD .. "/use item:" .. id .. (def.weapon and "\n/use 16" or "")
    end
    if cast then
        -- The creating spells carry no brackets in this client ("Create
        -- Healthstone", the rank is a subtext, the plain name casts the
        -- best one). Should a name ever end in one: the macro reads
        -- trailing brackets as a rank, an empty pair behind it stops that.
        if cast:sub(-1) == ")" then cast = cast .. "()" end
        return HEAD .. "/cast " .. cast
    end
end

-- ---------------------------------------------------------------- macros --

local function wanted()
    if not QoL.mod.active then return false end
    local d = db()
    for _, def in ipairs(Macros.DEFS) do
        if d[def.key] and Macros.Fits(def) then return true end
    end
    return false
end

local fullWarned
local function create(def, text)
    local _, own = GetNumMacros()
    local consts = Constants and Constants.MacroConsts
    local max = consts and consts.MAX_CHARACTER_MACROS or 30
    if (own or 0) >= max then
        if not fullWarned then
            fullWarned = true
            ns:Print(L["Macros: no free slot among your character's macros for \"%s\"."]:format(L[def.label]))
        end
        return 0
    end
    fullWarned = nil
    return CreateMacro(def.name, ICON, text, true) or 0
end

local levelSeen = 0     -- PLAYER_LEVEL_UP names the level before UnitLevel does
local queued

local function sync()
    queued = nil
    if not wanted() then return end
    if InCombatLockdown() then
        ns:RunOutOfCombatOnce("qol_macros", sync)
        return
    end
    local d = db()
    local level = math.max(UnitLevel("player") or 1, levelSeen)
    local bags = carried()
    for _, def in ipairs(Macros.DEFS) do
        if d[def.key] and Macros.Fits(def) then
            local text = body(def, level, bags)
            local index = GetMacroIndexByName(def.name)
            if index == 0 then
                create(def, text or HEAD)
            elseif text and GetMacroBody(index) ~= text then
                EditMacro(index, nil, nil, text)
            end
        end
    end
end

local function queue()
    if queued then return end
    queued = true
    C_Timer.After(0.3, sync)
end

local function onLevel(_, level)
    if type(level) == "number" then levelSeen = level end
    queue()
end

-- only an item we asked for is news
local function onItem(_, id)
    if id and asked[id] then queue() end
end

local EVENTS = {
    BAG_UPDATE_DELAYED    = queue,
    SPELLS_CHANGED        = queue,
    PLAYER_ENTERING_WORLD = queue,
    PLAYER_LEVEL_UP       = onLevel,
    GET_ITEM_INFO_RECEIVED = onItem,
}

-- Switched off in the options: the macro goes.
function Macros.Remove(key)
    local def = byKey[key]
    if not def then return end
    if InCombatLockdown() then
        ns:RunOutOfCombatOnce("qol_macro_del_" .. key, function()
            if not db()[key] then Macros.Remove(key) end
        end)
        return
    end
    local index = GetMacroIndexByName(def.name)
    if index > 0 then DeleteMacro(index) end
end

function Macros.Set(key, on)
    db()[key] = on and true or false
    if not on then Macros.Remove(key) end
end

-- Onto the cursor, to be dropped on a bar.
function Macros.Pickup(key)
    local def = byKey[key]
    if not def then return end
    if InCombatLockdown() then
        ns:Print(L["Macros can only be picked up out of combat."])
        return
    end
    if not db()[key] then
        ns:Print(L["Tick \"%s\" first: the macro does not exist yet."]:format(L[def.label]))
        return
    end
    if GetMacroIndexByName(def.name) == 0 then sync() end
    local index = GetMacroIndexByName(def.name)
    if index > 0 then PickupMacro(index) end
end

local registered
function Macros.Apply()
    local on = wanted()
    if on ~= (registered or false) then
        registered = on
        for event, fn in pairs(EVENTS) do QoL.SyncEvent(on, event, fn) end
    end
    if on then queue() end
end

function Macros.Disable()
    for event, fn in pairs(EVENTS) do ns:UnregisterEvent(event, fn) end
    registered = nil
end
