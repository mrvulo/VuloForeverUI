-- VuloForeverUI / Modules / TooltipIDs
--
-- Adds ID lines to tooltips: spell, item, NPC, quest, currency, mount and
-- the rest. Switched on and off from its sidebar row like any module; the
-- ID types are chosen on its own page.
--
-- WHERE THE IDS COME FROM
--
-- Forever mixes TooltipDataHandlerMixin into GameTooltip, so every
-- GameTooltip:SetX goes through ProcessInfo and fires one post call with the
-- tooltip data. That single hook covers items, spells, auras, units, objects,
-- currencies, mounts, pets, macros, toys and quests. The few IDs the data does
-- not carry -- talent nodes, map POIs, quest log rows, transmog appearances --
-- come from hooks on the Blizzard functions that fill those tooltips.
--
-- SECRETS
--
-- A unit's GUID and an aura's spell ID can arrive secret in combat. Those
-- lines are skipped, never guessed: an ID is only written when it is readable.
local _, ns = ...
local L = ns.L

-- Line labels. These are the names the whole community uses in bug reports
-- and on the wiki, so they stay English in every language.
local KINDS = {
    item        = "ItemID",
    enchant     = "EnchantID",
    gem         = "GemID",
    bonus       = "BonusID",
    set         = "SetID",
    currency    = "CurrencyID",
    spell       = "SpellID",
    macro       = "MacroID",
    icon        = "IconID",
    traitnode   = "TraitNodeID",
    traitentry  = "TraitEntryID",
    traitdef    = "TraitDefinitionID",
    unit        = "NpcID",
    object      = "ObjectID",
    quest       = "QuestID",
    achievement = "AchievementID",
    areapoi     = "AreaPoiID",
    vignette    = "VignetteID",
    mount       = "MountID",
    species     = "SpeciesID",
    visual      = "VisualID",
    source      = "SourceID",
}

-- Noise for most players: bonus IDs are long lists, the trait IDs matter only
-- to talent tools.
local OFF_BY_DEFAULT = {
    bonus = true, traitnode = true, traitentry = true, traitdef = true,
}

-- Page order; every kind sits in exactly one section. The names are locale
-- keys, looked up when the page is built.
local SECTIONS = {
    { name = "Items",       "item", "enchant", "gem", "bonus", "set", "currency" },
    { name = "Spells",      "spell", "macro", "icon", "traitnode", "traitentry", "traitdef" },
    { name = "World",       "unit", "object", "quest", "achievement", "areapoi", "vignette" },
    { name = "Collections", "mount", "species", "visual", "source" },
}

-- Enum.TooltipDataType values that carry an ID worth a line.
local KIND_BY_TYPE = {
    [0]  = "item",        -- Item
    [1]  = "spell",       -- Spell
    [2]  = "unit",        -- Unit
    [3]  = "unit",        -- Corpse
    [4]  = "object",      -- Object
    [5]  = "currency",    -- Currency
    [7]  = "spell",       -- UnitAura
    [9]  = "species",     -- CompanionPet: the id is the species
    [10] = "mount",       -- Mount
    [11] = "spell",       -- PetAction
    [12] = "achievement", -- Achievement
    [14] = "set",         -- EquipmentSet
    [17] = "spell",       -- RecipeRankInfo
    [18] = "spell",       -- Totem
    [19] = "item",        -- Toy
    [23] = "quest",       -- Quest
    [24] = "quest",       -- QuestPartyProgress
    [25] = "macro",       -- Macro
}

local defaults = { enabled = false, modifier = "always", kinds = {} }
for kind in pairs(KINDS) do defaults.kinds[kind] = not OFF_BY_DEFAULT[kind] end

local mod = ns:RegisterModule("tooltipids", {
    name        = "Tooltip IDs",
    group       = "General",
    description = "Shows spell, item, NPC and many other IDs in tooltips.",
    optionsGrid = true,
    defaults    = defaults,
})

local LABEL_R, LABEL_G, LABEL_B = 0.55, 0.72, 0.95

-- True while Blizzard's own tooltip build runs our post call. It shows the
-- tooltip itself right after the post calls; a Show of ours there would run
-- the tooltip's OnShow chain inside our (insecure) code first.
local inPostCall = false

local function reshow(tooltip)
    if not inPostCall then tooltip:Show() end
end

local isSecret = ns.IsSecret

-- The per-kind switches; a profile saved before a kind existed gets its default.
local function kindsDB()
    local kinds = mod.db.kinds
    if type(kinds) ~= "table" then kinds = {}; mod.db.kinds = kinds end
    return kinds
end

local function kindOn(kind)
    if not mod._enabled then return false end
    local v = kindsDB()[kind]
    if v == nil then return not OFF_BY_DEFAULT[kind] end
    return v and true or false
end

local function isStringOrNumber(v)
    local t = type(v)
    return t == "string" or t == "number"
end

local function isValidId(id)
    if type(id) == "table" then return #id > 0 end
    return isStringOrNumber(id) and id ~= "" and id ~= 0 and id ~= "0"
end

local MOD_TEST = {
    shift = IsShiftKeyDown,
    ctrl  = IsControlKeyDown,
    alt   = IsAltKeyDown,
}

-- The modifier gate: "always", or the chosen key held right now.
local function modifierAllows()
    local test = MOD_TEST[mod.db.modifier]
    return not test or test()
end

local function allowed(kind)
    return kindOn(kind) and modifierAllows()
end

local function addUnique(list, value)
    if value == nil or isSecret(value) then return end
    for i = 1, #list do
        if list[i] == value then return end
    end
    list[#list + 1] = value
end

local function cellText(name, side, index)
    local fs = _G[name .. "Text" .. side .. index]
    local text = fs and fs:GetText()
    if isSecret(text) then return nil end
    return text, fs
end

-- Joins a further ID onto the line this kind already has (an item that is
-- also a transmog source, a spell reached by two hooks). Returns true when
-- such a line existed, so no second one is added.
local function extendLine(tooltip, name, label, id)
    local plural = label .. "s"
    for index = tooltip:NumLines(), 1, -1 do
        local text, left = cellText(name, "Left", index)
        if text == label or text == plural then
            local joined, right = cellText(name, "Right", index)
            if not right then return true end
            local values = {}
            for v in string.gmatch(joined or "", "[^,]+") do values[#values + 1] = v end
            local count = #values
            if type(id) == "table" then
                for _, v in ipairs(id) do addUnique(values, tostring(v)) end
            else
                addUnique(values, tostring(id))
            end
            if #values > count then
                left:SetText(#values > 1 and plural or label)
                right:SetText(table.concat(values, ","))
                reshow(tooltip)
            end
            return true
        end
    end
    return false
end

local function addLine(tooltip, id, kind)
    if isSecret(id) or not isValidId(id) or not kindOn(kind) then return end
    if not tooltip or not tooltip.NumLines then return end
    local ok, name = pcall(tooltip.GetName, tooltip)
    if not ok or not name then return end

    local label = KINDS[kind]
    if extendLine(tooltip, name, label, id) then return end

    local multiple = type(id) == "table"
    tooltip:AddDoubleLine(label .. (multiple and "s" or ""),
        multiple and table.concat(id, ",") or id,
        LABEL_R, LABEL_G, LABEL_B, 1, 1, 1)
    reshow(tooltip)
end

-- id may be a list (a transmog look has several sources). Spells and items
-- also bring their icon, and an item its use spell.
local function add(tooltip, id, kind)
    if isSecret(id) then return end
    if type(id) == "table" and #id == 1 then id = id[1] end
    addLine(tooltip, id, kind)
    if not isStringOrNumber(id) then return end

    if kind == "spell" then
        if kindOn("icon") then add(tooltip, C_Spell.GetSpellTexture(id), "icon") end
    elseif kind == "item" then
        if kindOn("icon") then add(tooltip, C_Item.GetItemIconByID(id), "icon") end
        if kindOn("spell") then
            local _, spellId = C_Item.GetItemSpell(id)
            add(tooltip, spellId, "spell")
        end
    end
end

-- Only a Creature or Vehicle GUID carries an NPC id; a Player or Pet GUID
-- holds something else in that field.
local function npcIdFromGUID(guid)
    if type(guid) ~= "string" then return nil end
    local unitType, npcId = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-%x+$")
    if unitType == "Creature" or unitType == "Vehicle" then return npcId end
    return nil
end

local function addItem(tooltip, link)
    if type(link) ~= "string" then return false end
    local itemString = link:match("item:([%-?%d:]+)")
    if not itemString then return false end
    local itemId = link:match("item:(%d+)")
    if not itemId or itemId == "0" then return false end

    add(tooltip, itemId, "item")

    local fields = {}
    for v in string.gmatch(itemString .. ":", "([^:]*):") do fields[#fields + 1] = v end

    local enchantId = tonumber(fields[2])
    if enchantId and enchantId ~= 0 then add(tooltip, enchantId, "enchant") end

    if kindOn("bonus") then
        local bonuses = {}
        -- a crafted link can claim more bonus IDs than it carries
        for i = 1, math.min(tonumber(fields[13]) or 0, #fields - 13) do
            bonuses[#bonuses + 1] = fields[13 + i]
        end
        add(tooltip, bonuses, "bonus")
    end

    if kindOn("gem") then
        local gems = {}
        for socket = 1, 4 do
            local _, gemLink = C_Item.GetItemGem(link, socket)
            addUnique(gems, gemLink and gemLink:match("item:(%d+)"))
        end
        add(tooltip, gems, "gem")
    end

    if kindOn("set") then
        local setId = select(16, C_Item.GetItemInfo(itemId))
        add(tooltip, setId, "set")
    end
    return true
end

local readable = ns.Readable

local function onTooltipData(tooltip, data)
    if not mod._enabled or not modifierAllows() then return end
    if type(data) ~= "table" then return end
    local dataType, guid = data.type, data.guid
    if isSecret(dataType) or isSecret(guid) then return end
    local kind = KIND_BY_TYPE[tonumber(dataType)]
    if not kind then return end

    if kind == "unit" then
        add(tooltip, npcIdFromGUID(guid), "unit")
    elseif kind == "item" then
        -- the GUID resolves the actual item instance, with its enchant and
        -- gems; the plain hyperlink is the fallback
        local link = guid and readable(C_Item.GetItemLinkByGUID(guid))
        link = link or readable(data.hyperlink)
        if not link and tooltip.GetItem then
            local _, l = tooltip:GetItem()
            link = readable(l)
        end
        if not addItem(tooltip, link) then add(tooltip, data.id, "item") end
    else
        add(tooltip, data.id, kind)
    end
end

-- Ownership is the only sign a pin actually opened a tooltip: with nothing
-- to show it returns early, and hooksecurefunc cannot see that.
local function pinTooltip(pin)
    if pin and GameTooltip:IsShown() and GameTooltip:IsOwned(pin) then return GameTooltip end
end

-- Hooks on code that may load later (talent UI, world map, collections).
-- Each is installed once, the first time its target exists; installHooks
-- runs again on every ADDON_LOADED until all are in.
local hooked = {}

local function hookOnce(key, target, method, fn)
    if hooked[key] or type(target) ~= "table" or type(target[method]) ~= "function" then return end
    hooksecurefunc(target, method, fn)
    hooked[key] = true
end

local function installHooks()
    if not hooked.post and TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall then
        TooltipDataProcessor.AddTooltipPostCall(TooltipDataProcessor.AllTypes, function(tooltip, data)
            inPostCall = true
            local ok, err = pcall(onTooltipData, tooltip, data)
            inPostCall = false
            if not ok then geterrorhandler()(err) end
        end)
        hooked.post = true
    end

    hookOnce("talent", TalentDisplayMixin, "SetTooltipInternal", function(button)
        if not button or not modifierAllows() then return end
        add(GameTooltip, button.entryID, "traitentry")
        add(GameTooltip, button.definitionID, "traitdef")
        local nodeInfo = button.GetNodeInfo and button:GetNodeInfo()
        add(GameTooltip, nodeInfo and nodeInfo.ID, "traitnode")
    end)

    hookOnce("taskpoi", _G, "TaskPOI_OnEnter", function(button)
        if button and button.questID and allowed("quest") then
            add(GameTooltip, button.questID, "quest")
        end
    end)

    hookOnce("questlog", _G, "QuestMapLogTitleButton_OnEnter", function(button)
        if button and button.questLogIndex and allowed("quest") then
            add(GameTooltip, C_QuestLog.GetQuestIDForLogIndex(button.questLogIndex), "quest")
        end
    end)

    hookOnce("areapoi", AreaPOIPinMixin, "TryShowTooltip", function(pin)
        if not allowed("areapoi") then return end
        local tooltip = pinTooltip(pin)
        if tooltip then
            add(tooltip, pin.areaPoiID or (pin.poiInfo and pin.poiInfo.areaPoiID), "areapoi")
        end
    end)

    hookOnce("vignette", VignettePinMixin, "OnMouseEnter", function(pin)
        if not allowed("vignette") then return end
        local tooltip = pinTooltip(pin)
        if tooltip and pin.vignetteInfo then add(tooltip, pin.vignetteInfo.vignetteID, "vignette") end
    end)

    hookOnce("appearance", CollectionWardrobeUtil, "SetAppearanceTooltip", function(tooltip, appearanceData)
        local sources = appearanceData and appearanceData.sources
        if type(sources) ~= "table" or not modifierAllows() then return end
        local visuals, sourceIds, items = {}, {}, {}
        for _, source in ipairs(sources) do
            addUnique(visuals, source.visualID)
            addUnique(sourceIds, source.sourceID)
            addUnique(items, source.itemID)
        end
        tooltip = tooltip or GameTooltip
        add(tooltip, visuals, "visual")
        add(tooltip, sourceIds, "source")
        add(tooltip, items, "item")
    end)
end

-- With a modifier chosen, pressing it over an open tooltip adds the lines
-- right away instead of only on the next hover. Letting go leaves them until
-- the tooltip changes: rebuilding Blizzard's tooltip from here would run its
-- code tainted, and that code reads secret unit values in combat.
local function onModifier()
    if mod.db.modifier == "always" or not modifierAllows() then return end
    if not GameTooltip:IsShown() or not GameTooltip.GetPrimaryTooltipData then return end
    onTooltipData(GameTooltip, GameTooltip:GetPrimaryTooltipData())
end

function mod:OnEnable()
    installHooks()
    self:RegisterEvent("ADDON_LOADED", installHooks)
    self:RegisterEvent("MODIFIER_STATE_CHANGED", onModifier)
end

function mod:OnDisable()
    -- The hooks cannot be removed; every one of them checks mod._enabled.
    self:UnregisterAllEvents()
end

-- ------------------------------------------------------------ options --

local function setAll(fn)
    local kinds = kindsDB()
    for kind in pairs(KINDS) do kinds[kind] = fn(kind) end
    if ns.UI and ns.UI.BuildOptionsPage then ns.UI:BuildOptionsPage("tooltipids") end
end

function mod:GetOptions()
    local items = {
        { type = "desc", text = L["Adds ID lines to tooltips - handy for macros, bug reports and the wiki. IDs the game keeps hidden in combat are left out rather than guessed."] },
        { type = "dropdown", label = L["Show IDs"], width = 240,
          values = {
              { value = "always", text = L["Always"] },
              { value = "shift",  text = L["While Shift is held"] },
              { value = "ctrl",   text = L["While Ctrl is held"] },
              { value = "alt",    text = L["While Alt is held"] },
          },
          get = function() return mod.db.modifier end,
          set = function(_, v) mod.db.modifier = v end },
        { type = "group", layout = "row", gap = 6, items = {
            { type = "button", label = L["All on"], width = 110,
              onClick = function() setAll(function() return true end) end },
            { type = "button", label = L["All off"], width = 110,
              onClick = function() setAll(function() return false end) end },
            { type = "button", label = L["Defaults"], width = 110,
              onClick = function() setAll(function(k) return not OFF_BY_DEFAULT[k] end) end },
        } },
    }
    for _, section in ipairs(SECTIONS) do
        local rows = {}
        for _, kind in ipairs(section) do
            local label = KINDS[kind]
            rows[#rows + 1] = { type = "toggle", label = label,
                tooltip = L["Adds a %s line to tooltips."]:format(label),
                get = function()
                    local v = kindsDB()[kind]
                    if v == nil then return not OFF_BY_DEFAULT[kind] end
                    return v
                end,
                set = function(_, v) kindsDB()[kind] = v end }
        end
        items[#items + 1] = { type = "section", title = L[section.name], items = rows }
    end
    return items
end
