-- VuloForeverUI / Modules / Reminder / Supplies
--
-- What the "Possible buffs" window recommends, per role. Item and spell IDs
-- and required levels are checked against the client's item and spell tables
-- (2026-10-10); a wrong one would show the wrong name, so nothing here is
-- typed from memory.
--
-- A CHAIN is one buff in several ranks, best first, each { itemID, level }.
-- The window shows the best rank the character may use; a chain with no
-- usable rank is left out, so a level 20 character sees level 20 things.
--
--   cat      weapon, flask, elixir, food, scroll, other, potion
--   roles    set of roles it is for; nil = every role
--   mana     only for a class that has mana
--   class    only for these classes;  noClass: never for these
--   weapon   "edge" / "blunt": only for that kind of main-hand weapon
--   from     not before this character level (end-game items with no level)
local _, ns = ...
local R = ns.Reminder

R.ROLES = {
    { value = "melee",  text = "Melee damage" },
    { value = "ranged", text = "Ranged damage" },
    { value = "caster", text = "Spell damage" },
    { value = "healer", text = "Healer" },
    { value = "tank",   text = "Tank" },
}

-- The guess before the player picks; Forever does not reliably name a spec.
R.ROLE_DEFAULT = {
    WARRIOR = "melee", ROGUE = "melee", HUNTER = "ranged", MAGE = "caster",
    WARLOCK = "caster", PRIEST = "healer", DRUID = "healer", SHAMAN = "healer",
    PALADIN = "healer",
}

local function set(...)
    local t = {}
    for _, k in ipairs({ ... }) do t[k] = true end
    return t
end

local M, RA, C, H, T = "melee", "ranged", "caster", "healer", "tank"

-- the generic Well Fed foods (stamina and spirit) a character finds while levelling
local FOOD_BASE = { { 18045, 40 }, { 12210, 25 }, { 3727, 15 }, { 6888, 1 } }
local FOOD_MANA = { { 13931, 35 }, { 21217, 30 }, { 21072, 10 } }

local function chain(best, rest)
    local t = { unpack(best) }
    for _, v in ipairs(rest) do t[#t + 1] = v end
    return t
end

R.SUPPLIES = {
    -- weapons: poisons for rogues, stones for blades and blunt weapons, oils
    { cat = "weapon", class = set("ROGUE"), items = {
        { 8928, 60 }, { 8927, 52 }, { 8926, 44 }, { 6950, 36 }, { 6949, 28 }, { 6947, 20 } } },  -- Instant Poison
    { cat = "weapon", class = set("ROGUE"), items = {
        { 20844, 60 }, { 8985, 54 }, { 8984, 46 }, { 2893, 38 }, { 2892, 30 } } },               -- Deadly Poison
    { cat = "weapon", roles = set(M, T), items = { { 18262, 50 } } },
    { cat = "weapon", roles = set(M, T), weapon = "edge", items = {
        { 12404, 35 }, { 7964, 25 }, { 2871, 15 }, { 2863, 5 }, { 2862, 1 } } },                 -- sharpening stones
    { cat = "weapon", roles = set(M, T), weapon = "blunt", items = {
        { 12643, 35 }, { 7965, 25 }, { 3241, 15 }, { 3240, 5 }, { 3239, 1 } } },                  -- weightstones
    { cat = "weapon", roles = set(C), items = { { 20749, 45 }, { 20750, 40 }, { 20746, 30 }, { 20744, 5 } } },  -- wizard oil
    { cat = "weapon", roles = set(H), items = { { 20748, 45 }, { 20747, 40 }, { 20745, 20 } } },               -- mana oil

    -- flasks
    { cat = "flask", roles = set(M, RA, T), items = { { 13510, 50 } } },   -- Titans
    { cat = "flask", roles = set(C), items = { { 13512, 50 } } },          -- Supreme Power
    { cat = "flask", roles = set(H), items = { { 13511, 50 } } },          -- Distilled Wisdom

    -- elixirs
    { cat = "elixir", roles = set(M, RA, T), items = {
        { 13452, 46 }, { 9187, 38 }, { 8949, 27 }, { 3390, 18 }, { 2457, 2 } } },               -- agility
    { cat = "elixir", roles = set(M, T), items = { { 9206, 38 }, { 3391, 20 }, { 2454, 1 } } }, -- strength
    { cat = "elixir", roles = set(T), items = { { 13445, 43 }, { 8951, 29 }, { 3389, 16 }, { 5997, 1 } } },  -- armor
    { cat = "elixir", roles = set(T), items = { { 3825, 25 }, { 2458, 2 } } },                  -- fortitude
    { cat = "elixir", roles = set(T), items = { { 20004, 53 }, { 3826, 26 }, { 3388, 15 } } },  -- troll's blood
    { cat = "elixir", roles = set(T), items = { { 9088, 38 } } },                               -- Gift of Arthas
    { cat = "elixir", roles = set(C), items = { { 13454, 47 }, { 9155, 37 } } },                -- spell power
    { cat = "elixir", roles = set(C), class = set("MAGE", "WARLOCK"), items = { { 21546, 40 }, { 6373, 18 } } },  -- fire
    { cat = "elixir", roles = set(C), class = set("WARLOCK", "PRIEST"), items = { { 9264, 40 } } },             -- shadow
    { cat = "elixir", roles = set(C), class = set("MAGE"), items = { { 17708, 28 } } },                         -- frost
    { cat = "elixir", roles = set(C, H), items = { { 20007, 40 } } },                           -- Mageblood
    { cat = "elixir", roles = set(C, H), items = { { 13447, 44 }, { 9179, 37 }, { 3383, 10 } } },  -- intellect

    -- food: one Well Fed at a time, so one chain per role
    { cat = "food", roles = set(M), class = set("ROGUE", "DRUID"), items = chain({ { 13928, 35 } }, FOOD_BASE) },
    { cat = "food", roles = set(M), noClass = set("ROGUE", "DRUID"), items = chain({ { 20452, 45 } }, FOOD_BASE) },
    { cat = "food", roles = set(RA), items = chain({ { 13928, 35 } }, FOOD_BASE) },
    { cat = "food", roles = set(C), items = chain({ { 18254, 45 } }, FOOD_MANA) },
    { cat = "food", roles = set(H), items = FOOD_MANA },
    { cat = "food", roles = set(T), items = chain({ { 21023, 55 } }, FOOD_BASE) },

    -- scrolls
    { cat = "scroll", roles = set(M, RA), items = { { 10309, 55 }, { 4425, 40 }, { 1477, 25 }, { 3012, 10 } } },  -- agility
    { cat = "scroll", roles = set(M, T), items = { { 10310, 55 }, { 4426, 40 }, { 2289, 25 }, { 954, 10 } } },    -- strength
    { cat = "scroll", roles = set(M, T), items = { { 10305, 45 }, { 4421, 30 }, { 1478, 15 }, { 3013, 1 } } },    -- protection
    { cat = "scroll", items = { { 10307, 50 }, { 4422, 35 }, { 1711, 20 }, { 1180, 5 } } },                       -- stamina
    { cat = "scroll", roles = set(C, H), items = { { 10308, 50 }, { 4419, 35 }, { 2290, 20 }, { 955, 5 } } },     -- intellect
    { cat = "scroll", roles = set(C, H), items = { { 10306, 45 }, { 4424, 30 }, { 1712, 15 }, { 1181, 1 } } },    -- spirit

    -- other end-game consumables
    { cat = "other", from = 55, items = { { 20079, 55 } } },                                    -- Spirit of Zanza
    { cat = "other", from = 50, roles = set(M, T), items = { { 21151, 0 } } },                  -- Rumsey Rum Black Label
    { cat = "other", from = 50, roles = set(M, T), items = { { 12451, 0 } } },                  -- Juju Power
    { cat = "other", from = 50, roles = set(M, T), items = { { 12460, 0 } } },                  -- Juju Might
    { cat = "other", from = 50, roles = set(M, T), items = { { 12820, 45 } } },                 -- Winterfall Firewater
    { cat = "other", from = 50, roles = set(M, T), items = { { 8410, 0 } } },                   -- R.O.I.D.S.
    { cat = "other", from = 50, roles = set(M, RA), items = { { 8412, 0 } } },                  -- Ground Scorpok Assay
    { cat = "other", from = 50, roles = set(C, H), items = { { 8423, 0 } } },                   -- Cerebral Cortex Compound
    { cat = "other", from = 50, roles = set(T), items = { { 8411, 0 } } },                      -- Lung Juice Cocktail

    -- potions
    { cat = "potion", items = { { 13446, 45 }, { 3928, 35 }, { 1710, 21 }, { 929, 12 }, { 858, 3 }, { 118, 1 } } },  -- healing
    { cat = "potion", mana = true, items = {
        { 13444, 49 }, { 13443, 41 }, { 6149, 31 }, { 3827, 22 }, { 3385, 14 }, { 2455, 5 } } },                    -- mana
    { cat = "potion", class = set("WARRIOR"), items = { { 13442, 46 }, { 5633, 25 }, { 5631, 4 } } },                -- rage
    { cat = "potion", roles = set(T), items = { { 13455, 46 }, { 4623, 33 } } },                                    -- stoneshield
    { cat = "potion", mana = true, from = 50, items = { { 12662, 0 } } },                                           -- Demonic Rune
}

-- Buffs other classes give. Recognised by name like the class buffs, so the
-- group and greater versions count too. faction: the class exists only there.
R.GROUP_BUFFS = {
    { class = "DRUID",   ids = { 1126, 21849 } },                         -- Mark / Gift of the Wild
    { class = "DRUID",   ids = { 467 }, roles = set(T) },                 -- Thorns
    { class = "DRUID",   ids = { 17007, 24932 }, roles = set(M, RA) },    -- Leader of the Pack
    { class = "DRUID",   ids = { 24907 }, roles = set(C, H) },            -- Moonkin Aura
    { class = "PRIEST",  ids = { 1243, 21562 } },                         -- Fortitude
    { class = "PRIEST",  ids = { 14752, 27681 }, mana = true },           -- Divine Spirit
    { class = "PRIEST",  ids = { 976, 27683 } },                          -- Shadow Protection
    { class = "MAGE",    ids = { 1459, 23028 }, mana = true },            -- Arcane Intellect
    { class = "PALADIN", faction = "Alliance", ids = { 20217, 25898 } },  -- Kings
    { class = "PALADIN", faction = "Alliance", ids = { 19740, 25782 }, roles = set(M, RA, T) },     -- Might
    { class = "PALADIN", faction = "Alliance", ids = { 19742, 25894 }, mana = true },               -- Wisdom
    { class = "PALADIN", faction = "Alliance", ids = { 1038, 25895 }, roles = set(M, RA, C, H) },   -- Salvation
    { class = "PALADIN", faction = "Alliance", ids = { 19977, 25890 }, roles = set(T) },            -- Light
    { class = "PALADIN", faction = "Alliance", ids = { 20911, 25899 }, roles = set(T) },            -- Sanctuary
    { class = "PALADIN", faction = "Alliance", ids = { 465 }, roles = set(M, T) },                  -- Devotion Aura
    { class = "SHAMAN",  faction = "Horde", ids = { 8076 }, roles = set(M, T) },                    -- Strength of Earth
    { class = "SHAMAN",  faction = "Horde", ids = { 8836 }, roles = set(M, RA, T) },                -- Grace of Air
    { class = "SHAMAN",  faction = "Horde", ids = { 5677 }, mana = true },                          -- Mana Spring
    { class = "WARRIOR", ids = { 6673 }, roles = set(M, T) },             -- Battle Shout
    { class = "HUNTER",  ids = { 19506 }, roles = set(M, RA) },           -- Trueshot Aura
    { class = "WARLOCK", ids = { 6307 } },                                -- Blood Pact (imp)
}

-- Buffs from the world, shown from level 55 on.
R.WORLD_BUFFS = {
    { ids = { 22888 } },    -- Rallying Cry of the Dragonslayer
    { ids = { 24425 } },    -- Spirit of Zandalar
    { ids = { 16609 }, faction = "Horde" },   -- Warchief's Blessing
    { ids = { 15366 } },    -- Songflower Serenade
    { ids = { 22817 }, roles = set(M, RA, T) },   -- Fengus' Ferocity
    { ids = { 22818 } },    -- Mol'dar's Moxie
    { ids = { 22820 }, roles = set(C, H) },       -- Slip'kik's Savvy
}
