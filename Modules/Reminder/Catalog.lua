-- VuloForeverUI / Modules / Reminder / Catalog
--
-- "What could I have on me right now?" -- a window opened from the options
-- page, listing everything this character can put on itself or get from
-- others, for the role picked at its top:
--
--   Your spells         the class buffs from Data.lua the character knows
--   From other classes  group buffs (Supplies.lua), for this role
--   World buffs         from level 55
--   Weapons             each weapon slot's temporary enchant, shaman imbues,
--                       the recommended poison / stone / oil, the bag's own
--   Flasks, Elixirs, Food, Scrolls, Other, Potions
--                       the recommended ones first (best rank the level
--                       allows, Supplies.lua), then whatever else of that kind
--                       is in the bags
--
-- Every row says whether that buff is on you and for how long; a recommended
-- item also whether you carry it. Only to look at: casting and using stay
-- with the reminder row and the bags, so nothing here is secure and nothing
-- can taint.
--
-- An item counts as "on you" when an aura of its use-spell's name is up (an
-- elixir and its buff share the name). Food is the exception: what it leaves
-- is "Well Fed", so the food group starts with that buff's own row.
local _, ns = ...
local L = ns.L
local R = ns.Reminder

local W, H, PAD = 360, 540, 12
local ROW_H, ICON = 30, 22
local TOP = 90                  -- title, line, role picker
local WELL_FED = 19705
local GREEN, GREY, GOLD = { 0.35, 0.85, 0.35 }, { 0.6, 0.6, 0.6 }, { 1, 0.82, 0 }

local win, scroll, child, note, rolePick
local rows, heads = {}, {}
local notedMissing

-- ---------------------------------------------------------------- data --

local CS = Enum.ItemConsumableSubclass or {}
local CAT_OF = {
    [CS.Flasksphials or -1] = "flask", [CS.Elixir or -1] = "elixir", [CS.Potion or -1] = "potion",
    [CS.Scroll or -1] = "scroll", [CS.Fooddrink or -1] = "food",
    [CS.Itemenhancement or -1] = "weapon", [CS.ItemenhancementTemporary or -1] = "weapon",
}
local GROUPS = {
    { cat = "flask",  label = "Flasks" },
    { cat = "elixir", label = "Elixirs" },
    { cat = "food",   label = "Food" },
    { cat = "scroll", label = "Scrolls" },
    { cat = "other",  label = "Other" },
    { cat = "potion", label = "Potions" },
}

local function fmtLeft(left)
    if left == math.huge then return L["Active"] end
    local t
    if left >= 3600 then t = L["%d h"]:format(math.floor(left / 3600))
    elseif left >= 60 then t = L["%d min"]:format(math.floor(left / 60))
    else t = L["%d s"]:format(math.max(0, math.floor(left))) end
    return L["Active · %s"]:format(t)
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

-- the aura an item leaves: its use-spell's name (nil while the item is not cached)
local function itemAura(id)
    local name, spellID = C_Item.GetItemSpell(id)
    return auraByName(name, spellID)
end

-- state: number/huge = on you, nil = not on you, false = unreadable
local function status(state)
    if state == false then return L["Not readable in combat"], GREY end
    if state then return fmtLeft(state), GREEN end
    return L["Not active"], GREY
end

local function itemName(id)
    local n = C_Item.GetItemNameByID(id)
    if n then return n end
    C_Item.RequestLoadItemDataByID(id)     -- GET_ITEM_INFO_RECEIVED redraws
    return "…"
end

local function bagItems()
    local seen, list = {}, {}
    local remembered = {}
    for _, id in pairs(R.WeaponItems()) do remembered[id] = true end
    for bag = 0, (NUM_BAG_SLOTS or 4) + 1 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            local id = info and info.itemID
            if id and not seen[id] then
                seen[id] = true
                local _, _, _, equipLoc, icon, classID, subID = C_Item.GetItemInfoInstant(id)
                if classID == Enum.ItemClass.Consumable and (not equipLoc or equipLoc == "")
                    and subID ~= CS.Bandage and C_Item.GetItemSpell(id) then
                    list[#list + 1] = { id = id, icon = icon,
                        cat = remembered[id] and "weapon" or CAT_OF[subID] or "other",
                        name = C_Item.GetItemNameByID(id) or info.itemName or "",
                        count = C_Item.GetItemCount(id) or 1 }
                end
            end
        end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

local fits, bestRank, mainHandKind = R.SupplyFits, R.BestRank, R.MainHandKind

-- The classes of everyone else in the group; second value: in a group at all.
local function groupClasses()
    local out = {}
    if not IsInGroup() then return out, false end
    local raid = IsInRaid()
    for i = 1, raid and GetNumGroupMembers() or 4 do
        local unit = raid and ("raid" .. i) or ("party" .. i)
        if UnitExists(unit) and not UnitIsUnit(unit, "player") then
            local _, class = UnitClass(unit)
            if ns.CanRead(class) and type(class) == "string" then out[class] = true end
        end
    end
    return out, true
end

local function recommendedRow(id, isWeapon, chainItems)
    local count = C_Item.GetItemCount(id) or 0
    local row = { icon = C_Item.GetItemIconByID(id), item = id, name = itemName(id),
                  count = count > 0 and count or nil, use = count > 0, weapon = isWeapon }
    -- any rank of the chain on you counts: a lower elixir is still an elixir
    local state
    if not isWeapon then
        for _, it in ipairs(chainItems) do
            local s = itemAura(it[1])
            if s == false then state = false; break end
            if s and (not state or s > state) then state = s end
        end
    end
    if state ~= nil then
        row.line, row.color = status(state)
    elseif count > 0 then
        row.line, row.color = L["Recommended · in your bags"], GOLD
    else
        row.line, row.color, row.dim = L["Recommended · not in your bags"], GREY, true
    end
    return row
end

-- { head = text } or { icon, name, line, color, count, dim, spell | item | inv }
local function collect()
    local out = {}
    local role = R.Role()
    local ctx = { level = UnitLevel("player") or 1, weapon = mainHandKind() }
    local function head(text) out[#out + 1] = { head = text } end
    local function addAll(list) for _, it in ipairs(list) do out[#out + 1] = it end end

    -- your spells
    local spells = {}
    for _, e in ipairs(R.classBuffs) do
        local cast = R.CastFor(R.EntryCfg(e), e.cast)
        if cast then
            local line, color = status(auraAny(e.ids))
            spells[#spells + 1] = { icon = C_Spell.GetSpellTexture(cast), spell = cast, cast = true,
                name = e.label and L[e.label] or R.SpellName(cast), line = line, color = color }
        end
    end
    if #spells > 0 then head(L["Your spells"]); addAll(spells) end

    -- from other classes; in a group, the classes someone there can give
    -- come first, the rest is dimmed and says nobody here has it
    local faction = UnitFactionGroup("player")
    local names = _G.LOCALIZED_CLASS_NAMES_MALE or {}
    local present, grouped = groupClasses()
    local others, absent, missing = {}, {}, {}
    for _, b in ipairs(R.GROUP_BUFFS) do
        if b.giver ~= R.class and (not b.faction or b.faction == faction) and R.SupplyFits(b, role, ctx) then
            local name = R.SpellName(b.ids[1])
            if not name then
                -- not loaded yet (SPELL_DATA_LOAD_RESULT redraws); noted once
                -- in the diag log in case this client does not know the ID
                C_Spell.RequestLoadSpellData(b.ids[1])
                missing[#missing + 1] = b.ids[1]
            end
            local state = auraAny(b.ids)
            local line, color = status(state)
            local who = names[b.giver] or b.giver
            local cc = C_ClassColor.GetClassColor(b.giver)
            if cc then who = cc:WrapTextInColorCode(who) end
            local row = { icon = C_Spell.GetSpellTexture(b.ids[1]), spell = b.ids[1],
                name = name or "…", line = line, color = color, count = who }
            if grouped and not present[b.giver] and not state then
                row.dim, row.line = true, line .. " · " .. L["Nobody in your group"]
                absent[#absent + 1] = row
            else
                others[#others + 1] = row
            end
        end
    end
    for _, row in ipairs(absent) do others[#others + 1] = row end
    if #missing > 0 and not notedMissing then
        notedMissing = true
        ns.Diag.Note("reminders", "group buff spells without a name: " .. table.concat(missing, ", "))
    end
    if #others > 0 then head(L["From other classes"]); addAll(others) end

    -- world buffs
    if ctx.level >= 55 then
        local world = {}
        for _, b in ipairs(R.WORLD_BUFFS) do
            local name = (not b.faction or b.faction == faction) and fits(b, role, ctx)
                and R.SpellName(b.ids[1])
            if name then
                local line, color = status(auraAny(b.ids))
                world[#world + 1] = { icon = C_Spell.GetSpellTexture(b.ids[1]), spell = b.ids[1],
                    name = name, line = line, color = color }
            end
        end
        if #world > 0 then head(L["World buffs"]); addAll(world) end
    end

    -- recommendations per category, then the bags
    local items = bagItems()
    local shown = {}
    local byCat = {}
    for _, chainDef in ipairs(R.SUPPLIES) do
        if fits(chainDef, role, ctx) then
            local id = bestRank(chainDef.items, ctx.level)
            if id and not shown[id] then
                shown[id] = true
                local list = byCat[chainDef.cat] or {}
                byCat[chainDef.cat] = list
                list[#list + 1] = recommendedRow(id, chainDef.cat == "weapon", chainDef.items)
            end
        end
    end
    local function bagRows(cat, list, isWeapon)
        for _, it in ipairs(items) do
            if it.cat == cat and not shown[it.id] then
                local line, color
                if isWeapon then line, color = L["For a weapon"], GREY
                else line, color = status(itemAura(it.id)) end
                list[#list + 1] = { icon = it.icon, item = it.id, name = it.name, count = it.count,
                    line = line, color = color, use = true, weapon = isWeapon }
            end
        end
    end

    local weapons = {}
    for _, s in ipairs(R.SLOTS) do
        if R.IsWeapon(s.inv) then
            local left = R.EnchantLeft(R.WeaponSlot(s))
            weapons[#weapons + 1] = { icon = GetInventoryItemTexture("player", s.inv), inv = s.inv,
                name = L[s.label],
                line = left and fmtLeft(left) or L["No weapon enchant"], color = left and GREEN or GREY }
        end
    end
    if R.class == "SHAMAN" then
        for _, id in ipairs(R.KnownList(R.IMBUES)) do
            weapons[#weapons + 1] = { icon = C_Spell.GetSpellTexture(id), spell = id,
                name = R.SpellName(id), line = L["Spell"], color = GREY, cast = true }
        end
    end
    for _, it in ipairs(byCat.weapon or {}) do weapons[#weapons + 1] = it end
    bagRows("weapon", weapons, true)
    if #weapons > 0 then head(L["Weapons"]); addAll(weapons) end

    for _, g in ipairs(GROUPS) do
        local list = {}
        if g.cat == "food" then
            local fed = R.SpellName(WELL_FED)
            if fed then
                -- any food buff counts, not only the ones named Well Fed
                local line, color = status(auraAny(R.FOOD_BUFFS))
                list[1] = { icon = C_Spell.GetSpellTexture(WELL_FED), spell = WELL_FED,
                    name = fed, line = line, color = color }
            end
        end
        for _, it in ipairs(byCat[g.cat] or {}) do list[#list + 1] = it end
        bagRows(g.cat, list, false)
        if #list > (g.cat == "food" and 1 or 0) then head(L[g.label]); addAll(list) end
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
    if it.cast then
        GameTooltip:AddLine(L["Left click: cast"], 0.6, 1, 0.6)
    elseif it.use and it.weapon and R.IsWeapon(17) then
        GameTooltip:AddLine(L["Left click: main hand, right click: off hand"], 0.6, 1, 0.6)
    elseif it.use then
        GameTooltip:AddLine(L["Left click: use"], 0.6, 1, 0.6)
    end
    GameTooltip:Show()
end

-- ---------------------------------------------------------------- clicks --
--
-- Casting and using are protected, so the rows stay plain frames and ONE
-- secure button lays itself over the row under the mouse -- out of combat
-- only, and it is taken away the moment a fight starts. Nothing in the list
-- itself is ever protected, so scrolling, redrawing and closing the window
-- stay free in a fight.
local catcher

local function dropCatcher()
    if not catcher or InCombatLockdown() then return end
    if catcher.row then catcher.row.hl:Hide() end
    catcher.row = nil
    catcher:Hide()
    catcher:ClearAllPoints()
end

local function ensureCatcher()
    if catcher then return catcher end
    catcher = CreateFrame("Button", "VFUI_ReminderCatalogClick", UIParent, "SecureActionButtonTemplate")
    catcher:SetFrameStrata("DIALOG")
    catcher:SetFrameLevel(win:GetFrameLevel() + 50)
    catcher:RegisterForClicks("LeftButtonDown", "LeftButtonUp", "RightButtonDown", "RightButtonUp")
    catcher:Hide()
    catcher:SetScript("OnEnter", function(self)
        if self.row then self.row.hl:Show(); showTip(self.row) end
    end)
    catcher:SetScript("OnLeave", function(self)
        if self.row then self.row.hl:Hide() end
        GameTooltip:Hide()
        dropCatcher()
    end)
    return catcher
end

local function bindCatcher(row)
    local it = row.data
    if InCombatLockdown() or not (it and (it.cast or it.use)) then return false end
    -- Only a row the scroll frame shows whole: the button is not clipped, and
    -- over a half-hidden row it would reach past the list onto the role box
    -- or beyond the window, where a click would still use the item.
    local top, bottom = row:GetTop(), row:GetBottom()
    local sTop, sBottom = scroll:GetTop(), scroll:GetBottom()
    if not (top and bottom and sTop and sBottom) or top > sTop + 0.5 or bottom < sBottom - 0.5 then
        return false
    end
    local c = ensureCatcher()
    local spell = it.cast and R.SpellName(it.spell)
    for _, k in ipairs({ "*type1", "*spell1", "*unit1", "*macrotext1", "*type2", "*macrotext2" }) do
        c:SetAttribute(k, nil)
    end
    if spell then
        c:SetAttribute("*type1", "spell")
        c:SetAttribute("*spell1", spell)
        c:SetAttribute("*unit1", "player")
    elseif it.use and it.item then
        local use = "/use item:" .. it.item
        c:SetAttribute("*type1", "macro")
        if it.weapon then
            c:SetAttribute("*macrotext1", use .. "\n/use 16")
            -- right click only when the off hand holds a weapon, not a shield
            if R.IsWeapon(17) then
                c:SetAttribute("*type2", "macro")
                c:SetAttribute("*macrotext2", use .. "\n/use 17")
            end
        else
            c:SetAttribute("*macrotext1", use)
        end
    else
        return false
    end
    c.row = row
    c:ClearAllPoints()
    c:SetAllPoints(row)
    c:Show()
    return true
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
    f:SetScript("OnEnter", function(self)
        -- with an action, the secure button takes over the hover (and the tooltip)
        if bindCatcher(self) then return end
        self.hl:Show(); showTip(self)
    end)
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
    child:SetWidth(scroll:GetWidth())
    local ac = ns.COLORS.accent
    local y, nr, nh = 0, 0, 0
    for _, it in ipairs(list) do
        if it.head then
            nh = nh + 1
            local gap = nh > 1 and 10 or 0
            local fs = heads[nh] or makeHead(nh)
            fs:ClearAllPoints()
            fs:SetPoint("TOPLEFT", child, "TOPLEFT", 2, -(y + gap))
            fs:SetPoint("RIGHT", child, "RIGHT", -2, 0)
            fs:SetTextColor(ac.r, ac.g, ac.b)
            fs:SetText(it.head)
            fs:Show()
            y = y + gap + 18
        else
            nr = nr + 1
            local f = rows[nr] or makeRow(nr)
            f.data = it
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
            f:SetPoint("RIGHT", child, "RIGHT", 0, 0)
            f.icon:SetTexture(it.icon or 134400)
            f.icon:SetDesaturated(it.dim == true)
            f.icon:SetAlpha(it.dim and 0.6 or 1)
            f.name:SetText(it.name or "")
            f.name:SetAlpha(it.dim and 0.7 or 1)
            f.line:SetText(it.line or "")
            local c = it.color or GREY
            f.line:SetTextColor(c[1], c[2], c[3])
            local count = it.count
            f.count:SetText(type(count) == "number" and ("×" .. count) or count or "")
            f:Show()
            y = y + ROW_H
        end
    end
    for i = nr + 1, #rows do rows[i]:Hide(); rows[i].data = nil end
    for i = nh + 1, #heads do heads[i]:Hide() end
    child:SetHeight(math.max(1, y))
    note:SetShown(nr == 0)
    -- the rows were just refilled: the click button follows what is under
    -- the mouse now, or goes
    if catcher and catcher.row and not InCombatLockdown() then
        local r = catcher.row
        if not (r:IsShown() and r:IsMouseOver() and bindCatcher(r)) then
            dropCatcher()
        elseif GameTooltip:IsOwned(r) then
            showTip(r)      -- the row may hold something else now
        end
    end
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
    UI:CreateCloseX(win, function() win:Hide() end)

    local sub = win:CreateFontString(nil, "OVERLAY")
    UI.Font(sub, 10)
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    sub:SetPoint("RIGHT", win, "RIGHT", -PAD, 0)
    sub:SetJustifyH("LEFT")
    sub:SetTextColor(ns.TC("textDim"))
    sub:SetText(L["Green = on you now. Recommended for your role and level."])

    rolePick = UI:CreateDropdown(win, {
        label = L["Role"], width = W - 2 * PAD, values = R.ROLES,
        get = function() return R.Role() end,
        set = function(_, v) R.SetRole(v); render() end,
    })
    rolePick:SetPoint("TOPLEFT", win, "TOPLEFT", PAD, -50)

    scroll = CreateFrame("ScrollFrame", nil, win, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", win, "TOPLEFT", PAD, -TOP)
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
        -- the last moment protected changes are allowed: no click button in a fight
        if ev == "PLAYER_REGEN_DISABLED" then dropCatcher() end
        queue()
    end)
    win:SetScript("OnShow", function(self)
        for _, ev in ipairs({ "UNIT_AURA", "BAG_UPDATE_DELAYED", "WEAPON_ENCHANT_CHANGED",
                              "PLAYER_EQUIPMENT_CHANGED", "GET_ITEM_INFO_RECEIVED", "SPELL_DATA_LOAD_RESULT",
                              "PLAYER_LEVEL_UP", "GROUP_ROSTER_UPDATE", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED" }) do
            self:RegisterEvent(ev)
        end
        self.ticker = C_Timer.NewTicker(5, queue)   -- the minutes count down
        if rolePick._button and rolePick._button._refresh then rolePick._button._refresh() end
        render()
    end)
    win:SetScript("OnHide", function(self)
        dropCatcher()
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
