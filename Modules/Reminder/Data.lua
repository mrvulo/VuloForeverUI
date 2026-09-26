-- VuloForeverUI / Modules / Reminder / Data
--
-- What the reminders look for. Spell IDs are rank 1: buffs are recognised by
-- NAME (Core.lua), so one ID stands for every rank of a spell. An ID the
-- client does not know gives no name and its entry drops out quietly.
local _, ns = ...

local R = {}
ns.Reminder = R

-- ids:   any of these on the player satisfies the entry.
-- cast:  what a click casts; the first one the player knows unless picked.
-- short: the text under the icon (a locale key).
-- label: the option's name when the spell name alone would mislead.
-- on:    default state; false for the situational ones.
R.BUFFS = {
    MAGE = {
        { key = "intellect", short = "Intellect", ids = { 1459, 23028 }, cast = { 1459 } },
        { key = "armor", label = "Armor spell", short = "Armor",
          ids = { 7302, 168, 6117 }, cast = { 7302, 168, 6117 } },
    },
    PRIEST = {
        { key = "fortitude",  short = "Fortitude", ids = { 1243, 21562 }, cast = { 1243 } },
        { key = "innerfire",  short = "Inner Fire", ids = { 588 }, cast = { 588 } },
        { key = "spirit",     short = "Spirit", ids = { 14752, 27681 }, cast = { 14752 } },
        { key = "shadowprot", short = "Shadow", ids = { 976, 27683 }, cast = { 976 }, on = false },
    },
    DRUID = {
        { key = "wild",   short = "Mark",   ids = { 1126, 21849 }, cast = { 1126 } },
        { key = "omen",   short = "Omen",   ids = { 16864 }, cast = { 16864 } },
        { key = "thorns", short = "Thorns", ids = { 467 },   cast = { 467 }, on = false },
    },
    WARLOCK = {
        { key = "armor", label = "Armor spell", short = "Armor", ids = { 706, 687 }, cast = { 706, 687 } },
    },
    SHAMAN = {
        { key = "shield", short = "Shield", ids = { 324 }, cast = { 324 } },
    },
    PALADIN = {
        { key = "blessing", label = "Blessing", short = "Blessing",
          ids  = { 19740, 19742, 20217, 1038, 19977, 20911, 25782, 25894, 25898, 25895, 25890, 25899 },
          cast = { 20217, 19740, 19742, 1038, 19977, 20911 } },
    },
    HUNTER = {
        { key = "trueshot", short = "Aura", ids = { 19506 }, cast = { 19506 } },
    },
    WARRIOR = {
        { key = "shout", short = "Shout", ids = { 6673 }, cast = { 6673 }, on = false },
    },
    ROGUE = {},
}

-- The campfire buff Forever adds; nothing casts it, you sit down by a fire.
R.CAMP = 1229741

-- Shaman imbues are spells, so their weapon reminder casts one.
R.IMBUES = { 8232, 8024, 8033, 8017 }  -- Windfury, Flametongue, Frostbrand, Rockbiter

R.SLOTS = {
    { key = "main", inv = 16, label = "Main hand" },
    { key = "off",  inv = 17, label = "Off hand" },
}

-- Which weapon slots remind by default, per class.
R.SLOT_DEFAULT = {
    ROGUE  = { main = true, off = true },
    SHAMAN = { main = true },
}

-- A rogue has nothing to put on a weapon before the Poisons skill (level 20);
-- until then the slots would remind about something that cannot be done.
R.POISONS = 2842
