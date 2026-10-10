-- VuloForeverUI / Modules / Reminder / Catalog
--
-- "What could I have on me right now?" -- a window opened from the options
-- page, listing everything this character can put on itself:
--
--   Your spells   the class buffs from Data.lua the character knows
--   Weapons       each weapon slot's temporary enchant, shaman imbues, and the
--                 poisons, oils and stones in the bags
--   then one group per kind of consumable in the bags -- flasks, elixirs,
--   potions, scrolls, food -- named by the client's own item subclass names.
--
-- Every row says whether that buff is on you and for how long. Only to look
-- at: casting and using stay with the reminder row and the bags, so nothing
-- here is secure and nothing can taint.
--
-- An item counts as "on you" when an aura of its use-spell's name is up (an
-- elixir and its buff share the name). Food is the exception: what it leaves
-- is "Well Fed", so the food group starts with that buff's own row.
local _, ns = ...
local L = ns.L
local R = ns.Reminder

local W, H, PAD = 340, 460, 12
local ROW_H, ICON = 30, 22
local WELL_FED = 19705

local win, scroll, child, note
local rows, heads = {}, {}

-- ---------------------------------------------------------------- data --

local CS = Enum.ItemConsumableSubclass or {}
-- consumable subclasses in display order; bandages heal, they buff nothing
local ORDER = { CS.Flasksphials, CS.Elixir, CS.Potion, CS.Scroll, CS.Fooddrink, CS.Other, CS.Generic }
local WEAPON_SUB = { [CS.Itemenhancement or -1] = true, [CS.ItemenhancementTemporary or -1] = true }

local function fmtLeft(left)
    if left == math.huge then return L["Active"] end
    if left >= 3600 then return L["Active · %s"]:format(L["%d h"]:format(math.floor(left / 3600))) end
    if left >= 60 then return L["Active · %s"]:format(L["%d min"]:format(math.floor(left / 60))) end
    return L["Active · %s"]:format(L["%d s"]:format(math.max(0, math.floor(left))))
end

-- Seconds left on an aura of this name; nil = not on you, false = cannot be
-- read right now (a fight). Unlike the reminder row, "unreadable" is shown as
-- such here, never as present.
local function auraByName(name, spellID)
    if not name then return nil end
    if ns.AurasRestricted() or (spellID and ns.SpellAuraRestricted(spellID)) then return false end
    local aura = C_UnitAuras.GetAuraDataBySpellName("player", name, "HELPFUL")
    if type(aura) ~= "table" or not ns.CanRead(aura) then return nil end
    local exp = aura.expirationTime
    if ns.CanRead(exp) and type(exp) == "number" and exp > 0 then return exp - GetTime() end
    return math.huge
end

local function auraAny(ids)
    local best
    for _, id in ipairs(ids) do
        local left = auraByName(R.SpellName(id), id)
        if left == false then return false end
        if left and (not best or left > best) then best = left end
    end
    return best
end

-- state: number/huge = on you, nil = not on you, false = unreadable
local function status(state)
    if state == false then return L["Not readable in combat"], 0.6, 0.6, 0.6 end
    if state then return fmtLeft(state), 0.35, 0.85, 0.35 end
    return L["Not active"], 0.6, 0.6, 0.6
end

local function bagItems()
    local seen, list = {}, {}
    for bag = 0, (NUM_BAG_SLOTS or 4) + 1 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            local id = info and info.itemID
            if id and not seen[id] then
                seen[id] = true
                local _, _, _, equipLoc, icon, classID, subID = C_Item.GetItemInfoInstant(id)
                local spellName, spellID = C_Item.GetItemSpell(id)
                if classID == Enum.ItemClass.Consumable and (not equipLoc or equipLoc == "")
                    and subID ~= CS.Bandage and spellName then
                    list[#list + 1] = { id = id, sub = subID, icon = icon,
                        name = C_Item.GetItemNameByID(id) or info.itemName or spellName,
                        count = C_Item.GetItemCount(id) or 1,
                        spellName = spellName, spellID = spellID }
                end
            end
        end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

-- { head = text } or { icon, name, line, r, g, b, count, spell, item }
local function collect()
    local out = {}
    local function head(text) out[#out + 1] = { head = text } end

    local spells = {}
    for _, e in ipairs(R.classBuffs) do
        local cast = R.CastFor(R.EntryCfg(e), e.cast)
        if cast then
            local line, r, g, b = status(auraAny(e.ids))
            spells[#spells + 1] = { icon = C_Spell.GetSpellTexture(cast), spell = cast,
                name = e.label and L[e.label] or R.SpellName(cast), line = line, r = r, g = g, b = b }
        end
    end
    if #spells > 0 then
        head(L["Your spells"])
        for _, it in ipairs(spells) do out[#out + 1] = it end
    end

    local items = bagItems()
    local remembered = R.WeaponItems()
    local mine = {}
    for _, id in pairs(remembered) do mine[id] = true end

    local weapons = {}
    for _, s in ipairs(R.SLOTS) do
        if R.IsWeapon(s.inv) then
            local left = R.EnchantLeft(R.WeaponSlot(s))
            local line, r, g, b
            if left then line, r, g, b = fmtLeft(left), 0.35, 0.85, 0.35
            else line, r, g, b = L["No weapon enchant"], 0.6, 0.6, 0.6 end
            weapons[#weapons + 1] = { icon = GetInventoryItemTexture("player", s.inv), inv = s.inv,
                name = L[s.label], line = line, r = r, g = g, b = b }
        end
    end
    if R.class == "SHAMAN" then
        for _, id in ipairs(R.KnownList(R.IMBUES)) do
            weapons[#weapons + 1] = { icon = C_Spell.GetSpellTexture(id), spell = id,
                name = R.SpellName(id), line = L["Spell"], r = 0.6, g = 0.6, b = 0.6 }
        end
    end
    for _, it in ipairs(items) do
        if WEAPON_SUB[it.sub] or mine[it.id] then
            it.weapon = true
            weapons[#weapons + 1] = { icon = it.icon, item = it.id, name = it.name, count = it.count,
                line = L["For a weapon"], r = 0.6, g = 0.6, b = 0.6 }
        end
    end
    if #weapons > 0 then
        head(L["Weapons"])
        for _, it in ipairs(weapons) do out[#out + 1] = it end
    end

    for _, sub in ipairs(ORDER) do
        local group = {}
        if sub == CS.Fooddrink then
            local fed = R.SpellName(WELL_FED)
            if fed then
                local line, r, g, b = status(auraByName(fed, WELL_FED))
                group[1] = { icon = C_Spell.GetSpellTexture(WELL_FED), spell = WELL_FED,
                    name = fed, line = line, r = r, g = g, b = b }
            end
        end
        local found
        for _, it in ipairs(items) do
            if it.sub == sub and not it.weapon then
                found = true
                local line, r, g, b = status(auraByName(it.spellName, it.spellID))
                group[#group + 1] = { icon = it.icon, item = it.id, name = it.name, count = it.count,
                    line = line, r = r, g = g, b = b }
            end
        end
        if found then
            head(C_Item.GetItemSubClassInfo(Enum.ItemClass.Consumable, sub) or "")
            for _, it in ipairs(group) do out[#out + 1] = it end
        end
    end
    return out
end

-- ---------------------------------------------------------------- window --

local function showTip(f)
    local it = f.data
    if not it then return end
    GameTooltip:SetOwner(f, "ANCHOR_RIGHT")
    if it.item then GameTooltip:SetItemByID(it.item)
    elseif it.spell then GameTooltip:SetSpellByID(it.spell)
    elseif it.inv then GameTooltip:SetInventoryItem("player", it.inv)
    else return end
    GameTooltip:Show()
end

local function makeRow(i)
    local f = CreateFrame("Frame", nil, child)
    f:SetHeight(ROW_H)
    f.hl = f:CreateTexture(nil, "BACKGROUND")
    f.hl:SetAllPoints(); f.hl:SetColorTexture(1, 1, 1, 0.05); f.hl:Hide()
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(ICON, ICON)
    f.icon:SetPoint("LEFT", f, "LEFT", 2, 0)
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.count = f:CreateFontString(nil, "OVERLAY")
    ns.UI.Font(f.count, 11)
    f.count:SetPoint("RIGHT", f, "RIGHT", -4, 0)
    f.count:SetTextColor(ns.TC("textDim"))
    f.name = f:CreateFontString(nil, "OVERLAY")
    ns.UI.Font(f.name, 12)
    f.name:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", 8, 1)
    f.name:SetPoint("RIGHT", f.count, "LEFT", -6, 0)
    f.name:SetJustifyH("LEFT"); f.name:SetWordWrap(false)
    f.line = f:CreateFontString(nil, "OVERLAY")
    ns.UI.Font(f.line, 10)
    f.line:SetPoint("BOTTOMLEFT", f.icon, "BOTTOMRIGHT", 8, -1)
    f.line:SetPoint("RIGHT", f.count, "LEFT", -6, 0)
    f.line:SetJustifyH("LEFT"); f.line:SetWordWrap(false)
    f:EnableMouse(true)
    f:SetScript("OnEnter", function(self) self.hl:Show(); showTip(self) end)
    f:SetScript("OnLeave", function(self) self.hl:Hide(); GameTooltip:Hide() end)
    rows[i] = f
    return f
end

local function makeHead(i)
    local fs = child:CreateFontString(nil, "OVERLAY")
    ns.UI.Font(fs, 12)
    fs:SetJustifyH("LEFT")
    heads[i] = fs
    return fs
end

local function render()
    if not (win and win:IsShown()) then return end
    local list = collect()
    local width = scroll:GetWidth()
    child:SetWidth(width)
    local y, nr, nh = 0, 0, 0
    for _, it in ipairs(list) do
        if it.head then
            nh = nh + 1
            local fs = heads[nh] or makeHead(nh)
            fs:ClearAllPoints()
            fs:SetPoint("TOPLEFT", child, "TOPLEFT", 2, -(y + (nh > 1 and 10 or 0)))
            fs:SetPoint("RIGHT", child, "RIGHT", -2, 0)
            local ac = ns.COLORS.accent
            fs:SetTextColor(ac.r, ac.g, ac.b)
            fs:SetText(it.head)
            fs:Show()
            y = y + (nh > 1 and 10 or 0) + 18
        else
            nr = nr + 1
            local f = rows[nr] or makeRow(nr)
            f.data = it
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
            f:SetPoint("RIGHT", child, "RIGHT", 0, 0)
            f.icon:SetTexture(it.icon or 134400)
            f.name:SetText(it.name or "")
            f.line:SetText(it.line or "")
            f.line:SetTextColor(it.r or 0.6, it.g or 0.6, it.b or 0.6)
            f.count:SetText(it.count and ("×" .. it.count) or "")
            f:Show()
            y = y + ROW_H
        end
    end
    for i = nr + 1, #rows do rows[i]:Hide(); rows[i].data = nil end
    for i = nh + 1, #heads do heads[i]:Hide() end
    child:SetHeight(math.max(1, y))
    note:SetShown(nr == 0)
end

local pending
local function queue()
    if pending then return end
    pending = true
    C_Timer.After(0.1, function() pending = nil; render() end)
end

local function build()
    local UI = ns.UI
    win = CreateFrame("Frame", "VFUI_ReminderCatalog", UIParent)
    win:SetSize(W, H)
    win:SetFrameStrata("DIALOG")
    win:SetClampedToScreen(true)
    win:SetMovable(true)
    win:EnableMouse(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", win.StopMovingOrSizing)
    win:Hide()
    UI:StyleBackdrop(win, { bg = ns.COLORS.bg, border = ns.COLORS.accentDim })
    UI:CreateShadow(win)
    table.insert(UISpecialFrames, "VFUI_ReminderCatalog")

    local title = win:CreateFontString(nil, "OVERLAY")
    UI.Font(title, 13)
    title:SetPoint("TOPLEFT", win, "TOPLEFT", PAD, -12)
    title:SetPoint("RIGHT", win, "RIGHT", -34, 0)
    title:SetJustifyH("LEFT")
    title:SetText(L["Possible buffs"])
    win.title = title
    UI:CreateCloseX(win, function() win:Hide() end)

    local sub = win:CreateFontString(nil, "OVERLAY")
    UI.Font(sub, 10)
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    sub:SetPoint("RIGHT", win, "RIGHT", -PAD, 0)
    sub:SetJustifyH("LEFT")
    sub:SetTextColor(ns.TC("textDim"))
    sub:SetText(L["Your own buffs and what is in your bags. Green = on you now."])

    scroll = CreateFrame("ScrollFrame", nil, win, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", win, "TOPLEFT", PAD, -52)
    scroll:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -PAD - 14, PAD)
    child = CreateFrame("Frame", nil, scroll)
    child:SetSize(1, 1)
    scroll:SetScrollChild(child)
    UI.StyleScrollbar(scroll)
    UI.EnableScrollWheel(scroll, child, ROW_H * 2)

    note = win:CreateFontString(nil, "OVERLAY")
    UI.Font(note, 12)
    note:SetPoint("CENTER", scroll, "CENTER")
    note:SetTextColor(ns.TC("textDim"))
    note:SetText(L["Nothing found."])

    win:SetScript("OnEvent", function(_, ev, unit)
        if ev == "UNIT_AURA" and unit ~= "player" then return end
        queue()
    end)
    win:SetScript("OnShow", function(self)
        for _, ev in ipairs({ "UNIT_AURA", "BAG_UPDATE_DELAYED", "WEAPON_ENCHANT_CHANGED",
                              "PLAYER_EQUIPMENT_CHANGED", "GET_ITEM_INFO_RECEIVED",
                              "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED" }) do
            self:RegisterEvent(ev)
        end
        self.ticker = C_Timer.NewTicker(5, queue)   -- the minutes count down
        render()
    end)
    win:SetScript("OnHide", function(self)
        self:UnregisterAllEvents()
        if self.ticker then self.ticker:Cancel(); self.ticker = nil end
    end)
end

function R.ToggleCatalog()
    if not win then build() end
    if win:IsShown() then win:Hide(); return end
    win:ClearAllPoints()
    local main = ns.UI.mainFrame
    if main and main:IsShown() then
        win:SetPoint("TOPLEFT", main, "TOPRIGHT", 8, 0)
    else
        win:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    end
    win:Show()
end
