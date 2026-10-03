-- VuloForeverUI / Modules / Bags / Search
--
-- What the search box understands. Plain words look in the item's name; a
-- word with a # in front is a keyword (#boe, #blau, #trank, #kopf); a number
-- with a comparison is the item level (>200, <=50, 100-120). Words side by
-- side must ALL fit, a | between them means EITHER, and a ! in front of a
-- word turns it around:
--
--     #rüstung #blau >30     blue armour above item level 30
--     #trank | #essen        potions or food
--     #boe !#ausrüstungsset  bind-on-equip that is in no equipment set
--
-- Keywords come in English and German. A # word that is no keyword is matched
-- against the client's own type, subtype and slot names, which are already in
-- the player's language: #stoff, #kräuter, #trank, #kopf need no table here.
--
-- A search is turned into a list of tests once, when it is typed, and the
-- layout then runs the list per slot. Item data is plain on this client, so
-- none of this touches a secret.
local _, ns = ...
local L = ns.L
local Bags = ns.Bags

local Search = {}
Bags.Search = Search

local C = Enum.ItemClass or {}
local Q = Enum.ItemQuality or {}

-- ------------------------------------------------------------- the facts --

local function instant(info)
    local _, itemType, itemSubType, equipLoc, _, classID, subclassID = C_Item.GetItemInfoInstant(info.itemID)
    return itemType, itemSubType, equipLoc, classID, subclassID
end

local function classIs(id) return function(_, info)
    local _, _, _, classID = instant(info)
    return classID == id
end end

local function qualityIs(q) return function(_, info)
    return type(info.quality) == "number" and info.quality == q
end end

local function bindTagIs(tag) return function(_, info)
    return not info.isBound and Bags.Items.BindTag(info) == tag
end end

-- The item level as the tooltip shows it, and only for gear: on a potion the
-- client's "item level" is the level it was designed for, which no player
-- means when they type >30.
local function itemLevel(entry, info)
    if not Bags.Categories.IsGear(info) then return nil end
    local loc = ItemLocation:CreateFromBagAndSlot(entry.bag, entry.slot)
    local ok, value = pcall(C_Item.GetCurrentItemLevel, loc)
    if ok and type(value) == "number" then return value end
    return nil
end

local function isJunk(_, info)
    if ns.Junk and ns.Junk.IsJunk then return ns.Junk.IsJunk(info) and true or false end
    return type(info.quality) == "number" and info.quality == (Q.Poor or 0)
end

-- --------------------------------------------------------------- keywords --

-- Every spelling a player is likely to type, lower case, without the #.
local KEYWORDS = {}
local function keyword(names, test)
    for _, name in ipairs(names) do KEYWORDS[name] = test end
end

keyword({ "poor", "grau", "grey", "gray" },             qualityIs(Q.Poor or 0))
keyword({ "common", "weiß", "weiss", "white" },          qualityIs(Q.Common or 1))
keyword({ "uncommon", "grün", "gruen", "green" },        qualityIs(Q.Uncommon or 2))
keyword({ "rare", "selten", "blau", "blue" },            qualityIs(Q.Rare or 3))
keyword({ "epic", "episch", "lila", "purple" },          qualityIs(Q.Epic or 4))
keyword({ "legendary", "legendär", "legendaer", "orange" }, qualityIs(Q.Legendary or 5))
keyword({ "heirloom", "erbstück", "erbstueck" },         qualityIs(Q.Heirloom or 7))

keyword({ "boe", "bindetbeianlegen" },                   bindTagIs("BoE"))
keyword({ "warbound", "wue", "kriegsgebunden", "account" }, bindTagIs("WuE"))
keyword({ "bound", "soulbound", "bop", "gebunden", "seelengebunden" },
    function(_, info) return info.isBound and true or false end)

keyword({ "junk", "schrott", "trash", "müll", "muell" }, isJunk)
keyword({ "new", "neu", "recent" },
    function(entry) return Bags.Marks.IsRecent(entry.bag, entry.slot) end)
keyword({ "pinned", "pin", "angeheftet" },
    function(_, info) return Bags.Marks.IsPinned(info.itemID) end)
keyword({ "set", "equipmentset", "ausrüstungsset", "ausruestungsset" },
    function(entry) return Bags.Items.SetName(entry.bag, entry.slot) ~= nil end)
keyword({ "gear", "ausrüstung", "ausruestung", "equipment" },
    function(_, info) return Bags.Categories.IsGear(info) end)

keyword({ "weapon", "waffe", "waffen" },                 classIs(C.Weapon or 2))
keyword({ "armor", "armour", "rüstung", "ruestung" },    classIs(C.Armor or 4))
keyword({ "consumable", "verbrauchbar", "verbrauch" },   classIs(C.Consumable or 0))
keyword({ "container", "bag", "behälter", "behaelter", "tasche" }, classIs(C.Container or 1))
keyword({ "gem", "edelstein" },                          classIs(C.Gem or 3))
keyword({ "reagent", "reagenz" },                        classIs(C.Reagent or 5))
keyword({ "projectile", "ammo", "munition" },            classIs(C.Projectile or 6))
keyword({ "tradegoods", "trade", "handwerk", "handwerkswaren" }, classIs(C.Tradegoods or 7))
keyword({ "recipe", "rezept", "rezepte" },               classIs(C.Recipe or 9))
keyword({ "quiver", "köcher", "koecher" },               classIs(C.Quiver or 11))
keyword({ "quest" },                                     classIs(C.Questitem or 12))
keyword({ "key", "schlüssel", "schluessel" },            classIs(C.Key or 13))
keyword({ "misc", "verschiedenes" },                     classIs(C.Miscellaneous or 15))

keyword({ "cooldown", "abklingzeit" }, function(entry)
    local start, duration = C_Container.GetContainerItemCooldown(entry.bag, entry.slot)
    return type(start) == "number" and type(duration) == "number" and duration > 1.5
        and start + duration > GetTime()
end)

-- A # word that is no keyword: the client's own names for the item's type,
-- subtype and slot, from the start. "#trank" finds "Trank", "#stoff" "Stoff".
local function byClientName(word)
    return function(_, info)
        local itemType, itemSubType, equipLoc = instant(info)
        for _, name in ipairs({ itemType, itemSubType,
            (type(equipLoc) == "string" and equipLoc ~= "") and Bags.Items.EquipLocLabel(equipLoc) or nil }) do
            if type(name) == "string" and name:lower():sub(1, #word) == word then return true end
        end
        return false
    end
end

-- ------------------------------------------------------------ item level --

local function levelTest(word)
    local lo, hi = word:match("^(%d+)%-(%d+)$")
    if lo then
        lo, hi = tonumber(lo), tonumber(hi)
        return function(entry, info)
            local v = itemLevel(entry, info)
            return v ~= nil and v >= lo and v <= hi
        end
    end
    local op, n = word:match("^([<>]=?)(%d+)$")
    if not op then op, n = word:match("^(=)(%d+)$") end
    if not op then return nil end
    n = tonumber(n)
    return function(entry, info)
        local v = itemLevel(entry, info)
        if not v then return false end
        if op == ">" then return v > n end
        if op == ">=" then return v >= n end
        if op == "<" then return v < n end
        if op == "<=" then return v <= n end
        return v == n
    end
end

-- ------------------------------------------------------------------ name --

local function nameOf(info)
    local link = info.hyperlink
    if type(link) ~= "string" then return nil end
    local name = C_Item.GetItemNameByID and C_Item.GetItemNameByID(link)
    if type(name) ~= "string" then name = link end
    return name:lower()
end

local function nameTest(word)
    return function(_, info)
        local name = nameOf(info)
        return name ~= nil and name:find(word, 1, true) ~= nil
    end
end

-- -------------------------------------------------------------- compile --

local function termTest(word)
    local negate = false
    if word:sub(1, 1) == "!" and #word > 1 then
        negate, word = true, word:sub(2)
    end
    local test
    if word:sub(1, 1) == "#" and #word > 1 then
        local key = word:sub(2)
        test = KEYWORDS[key] or byClientName(key)
    else
        test = levelTest(word) or nameTest(word)
    end
    if negate then
        local inner = test
        test = function(entry, info) return not inner(entry, info) end
    end
    return test
end

-- text -> { { test, test }, { test } }: the outer list is EITHER, the inner
-- one ALL. Kept for the last few searches, because the layout asks once per
-- slot and the box asks again at every key press.
local compiled, compiledOrder = {}, {}

local function compile(text)
    local hit = compiled[text]
    if hit then return hit end
    local groups = {}
    for part in (text:lower() .. "|"):gmatch("([^|]*)|") do
        local group = {}
        for word in part:gmatch("%S+") do group[#group + 1] = termTest(word) end
        if #group > 0 then groups[#groups + 1] = group end
    end
    compiled[text] = groups
    compiledOrder[#compiledOrder + 1] = text
    if #compiledOrder > 20 then
        compiled[table.remove(compiledOrder, 1)] = nil
    end
    return groups
end

-- Does this entry survive the search? An empty box keeps everything; an
-- empty slot survives nothing that was typed.
function Search.Matches(entry, text)
    if not text or text == "" then return true end
    local info = entry and entry.info
    if not (info and type(info.itemID) == "number") then return false end
    local groups = compile(text)
    if #groups == 0 then return true end
    for _, group in ipairs(groups) do
        local all = true
        for _, test in ipairs(group) do
            if not test(entry, info) then all = false; break end
        end
        if all then return true end
    end
    return false
end

-- ------------------------------------------------------------------ help --

-- The tooltip on the search box. Built when it is shown, so it is in the
-- language the player picked.
function Search.ShowHelp(owner)
    GameTooltip:SetOwner(owner, "ANCHOR_BOTTOM")
    GameTooltip:AddLine(L["Search"], 1, 1, 1)
    GameTooltip:AddLine(L["Words look in the name. #word is a keyword, a number with < > or a range is the item level."], 0.8, 0.8, 0.8, true)
    GameTooltip:AddLine(" ")
    local rows = {
        { "#boe  #bop  #warbound", L["Binding"] },
        { "#grau #weiß #grün #blau #lila", L["Quality"] },
        { "#waffe #rüstung #trank #stoff …", L["Type, subtype or slot"] },
        { "#neu  #angeheftet  #set  #schrott", L["Marks"] },
        { ">30   <=50   20-40", L["Item level (gear)"] },
        { "a b   a | b   !a", L["All of / either / not"] },
    }
    for _, r in ipairs(rows) do
        GameTooltip:AddDoubleLine(r[1], r[2], 1, 0.82, 0, 0.8, 0.8, 0.8)
    end
    GameTooltip:Show()
end
