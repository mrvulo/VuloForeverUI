-- VuloForeverUI / Modules / CooldownManager / Picker
--
-- The menu behind the plus button next to the live preview: everything that
-- can go on a bar, in one list.
--
-- Three groups, in the order somebody reaches for them: the things that need
-- typing (a spell id, an item id), the things that are a PLACE rather than a
-- thing (an equipment slot, the two trinkets), and then the spells this
-- character actually has, with their artwork beside the name.
--
-- The lists are built when the menu opens, never cached: a trinket is swapped,
-- a potion is drunk, a spell is learned, and a menu that remembered yesterday's
-- answer would offer rows that no longer exist.
local _, ns = ...
local L  = ns.L
local CM = ns.CM

local Picker = {}
CM.Picker = Picker

-- The bar the menu is adding to, and the kind the id popup is asking about.
-- Both are set on the way into a popup and read on the way out, because a
-- StaticPopup carries no context of its own.
local target, pendingKind

local function addAndRedraw(id, kind)
    if type(id) ~= "number" or not target then return end
    CM.AddSpell(target, id, kind)
    if CM.RebuildOptions then CM.RebuildOptions("spells") end
    CM.RefreshPreview()
end

ns.OnLocaleReady(function()
    StaticPopupDialogs["VFUI_CM_ADD_ID"] = {
        text = L["Enter an id:"],
        button1 = _G.OKAY or _G.ACCEPT or L["Save"], button2 = _G.CANCEL,
        hasEditBox = true, maxLetters = 12,
        OnShow = function(self)
            local box = ns.PopupEditBox(self)
            if box then box:SetText(""); box:SetFocus() end
        end,
        OnAccept = function(self)
            local box = ns.PopupEditBox(self)
            if box then addAndRedraw(tonumber(box:GetText()), pendingKind) end
        end,
        EditBoxOnEnterPressed = function(self)
            addAndRedraw(tonumber(self:GetText()), pendingKind)
            self:GetParent():Hide()
        end,
        EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
end)

local function askForID(kind)
    pendingKind = kind
    StaticPopup_Show("VFUI_CM_ADD_ID")
end

-- ---------------------------------------------------------------- groups --

-- Every equipment slot, named by the client. The two trinkets are ALSO offered
-- one level up, because they are what this is used for nine times out of ten.
local function slotEntries()
    local out = {}
    for _, slot in ipairs(CM.SLOTS) do
        local id = slot.id
        local worn = GetInventoryItemID("player", id)
        out[#out + 1] = {
            text = CM.SlotName(id),
            icon = type(worn) == "number" and C_Item.GetItemIconByID
                and C_Item.GetItemIconByID(worn) or nil,
            func = function() addAndRedraw(id, "slot") end,
        }
    end
    return out
end

-- The racials, from the spellbook's FIRST skill line -- which is where the
-- client itself files them. Asked of the spellbook rather than kept as a table
-- of ids per race: a table would be a list to maintain, and it would be wrong
-- on the first race this client has and we forgot.
local function racialEntries()
    local out = {}
    local bank = (Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or 0
    local numLines = C_SpellBook.GetNumSpellBookSkillLines
        and C_SpellBook.GetNumSpellBookSkillLines() or 0
    if numLines < 1 then return out end

    local ok, line = pcall(C_SpellBook.GetSpellBookSkillLineInfo, 1)
    if not (ok and type(line) == "table") then return out end
    local first = (line.itemIndexOffset or 0) + 1
    local last  = (line.itemIndexOffset or 0) + (line.numSpellBookItems or 0)

    for index = first, last do
        local okItem, item = pcall(C_SpellBook.GetSpellBookItemInfo, index, bank)
        if okItem and type(item) == "table" and item.spellID and not item.isPassive then
            out[#out + 1] = {
                text = item.name or ("#" .. tostring(item.spellID)),
                icon = item.iconID or C_Spell.GetSpellTexture(item.spellID),
                func = function() addAndRedraw(item.spellID, "spell") end,
            }
        end
    end
    return out
end

-- Potions and healthstones, from the BAGS: what is offered is what the player
-- is carrying, which is the only list that is ever right.
local POTION_SUBCLASS = { [1] = true, [8] = true }   -- Potion, Other (healthstones)

local function potionEntries()
    local out, seen = {}, {}
    local bags = { 0 }
    for i = 1, (NUM_BAG_SLOTS or 4) do bags[#bags + 1] = i end

    for _, bag in ipairs(bags) do
        local slots = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, slots do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            local id = info and info.itemID
            if type(id) == "number" and not seen[id] then
                local _, _, _, _, _, classID, subClassID = C_Item.GetItemInfoInstant(id)
                if classID == (Enum.ItemClass and Enum.ItemClass.Consumable or 0)
                   and POTION_SUBCLASS[subClassID] then
                    seen[id] = true
                    out[#out + 1] = {
                        text = (C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)) or ("#" .. id),
                        icon = C_Item.GetItemIconByID and C_Item.GetItemIconByID(id) or nil,
                        func = function() addAndRedraw(id, "item") end,
                    }
                end
            end
        end
    end
    table.sort(out, function(a, b) return a.text < b.text end)
    return out
end

local function emptyNote(list, text)
    if #list > 0 then return list end
    return { { text = text, disabled = true } }
end

-- ---------------------------------------------------------------- menu --

function Picker.Menu(barKey)
    target = barKey

    local entries = {
        { text = L["Custom spell id"], func = function() askForID("spell") end },
        { text = L["Custom item id"],  func = function() askForID("item") end },
        { text = L["Equipment slot"],  submenu = function()
            return emptyNote(slotEntries(), L["Nothing to add"]) end },
        { separator = true },
        { text = CM.SlotName(13), func = function() addAndRedraw(13, "slot") end },
        { text = CM.SlotName(14), func = function() addAndRedraw(14, "slot") end },
        { text = L["Racial ability"], submenu = function()
            return emptyNote(racialEntries(), L["Nothing to add"]) end },
        { text = L["Potions & healthstone"], submenu = function()
            return emptyNote(potionEntries(), L["Nothing to add"]) end },
        { separator = true },
    }

    -- The spellbook's own candidates, the same list the "add a spell" box
    -- offers. A spell already on a bar says which one, so picking it here
    -- reads as moving it rather than as a duplicate.
    local base = #entries
    for _, cand in ipairs(CM.Candidates()) do
        local on = CM.SpellBarName(cand.spellID)
        entries[#entries + 1] = {
            text = on and ("%s  |cff777777(%s)|r"):format(cand.name, on) or cand.name,
            icon = C_Spell.GetSpellTexture(cand.spellID),
            func = function() addAndRedraw(cand.spellID, "spell") end,
        }
    end
    if #entries == base then
        entries[#entries + 1] = { text = L["The spellbook has nothing to add"], disabled = true }
    end
    return entries
end
