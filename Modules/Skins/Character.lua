-- VuloForeverUI / Modules / Skins / Character
--
-- The character window (Blizzard_UIPanels_Game, Camelot build): a portrait
-- frame with a left pane (model, slots) and a right pane (stats), the level
-- line in a strip above the model, side tabs on the right edge.
--
-- Slots: PaperDollItemSlotButton_Update redraws a slot on every equipment
-- and bag event and colours its IconBorder; our hook runs after it and lays
-- the ring and texts over the result.
local _, ns = ...
local Skins = ns.Skins

local Character = {}
table.insert(Skins.parts, Character)

-- Which way each slot's enchant text runs (Core.lua, decorate).
local SLOTS = {
    Head = "left", Neck = "left", Shoulder = "left", Back = "left", Chest = "left",
    Shirt = "left", Tabard = "left", Wrist = "left",
    Hands = "right", Waist = "right", Legs = "right", Feet = "right",
    Finger0 = "right", Finger1 = "right", Trinket0 = "right", Trinket1 = "right",
    MainHand = "right", SecondaryHand = "above", Ranged = "left",
}
local NO_LEVEL = { [0] = true, [4] = true, [19] = true }     -- ammo, shirt, tabard
Skins.SLOTS, Skins.NO_LEVEL = SLOTS, NO_LEVEL

local sideOf = {}          -- client slot button -> "left" | "right" | "above" | "none"
local enchantCache = {}    -- inventory slot -> enchant text (or false)

-- ---------------------------------------------------------------- slot data --

-- The name of the poison, oil or stone on a weapon: the item the reminders
-- learned for that hand, when the hand carries a temporary enchant now.
local function weaponTemp(slot)
    local R = ns.Reminder
    if not (R and R.WeaponItems and R.EnchantLeft and R.WeaponSlot and R.SLOTS) then return nil end
    for _, s in ipairs(R.SLOTS) do
        if s.inv == slot and R.EnchantLeft(R.WeaponSlot(s)) then
            local id = R.WeaponItems()[s.key]
            return id and C_Item.GetItemNameByID(id) or nil
        end
    end
end

local function enchantOf(slot)
    if slot == 0 then return nil end          -- ammo: nothing to enchant
    local v = enchantCache[slot]
    if v == nil and not Skins.ItemReady(GetInventoryItemID("player", slot)) then
        v = false                     -- asked for; not kept until it arrives
    elseif v == nil then
        local ok, data = pcall(C_TooltipInfo.GetInventoryItem, "player", slot)
        v = ok and Skins.EnchantFrom(data) or false
        enchantCache[slot] = v
    end
    local temp = (slot == 16 or slot == 17) and weaponTemp(slot) or nil
    if v and temp then return v .. " · " .. temp end
    return v or temp
end

local function slotInfo(slot)
    if not GetInventoryItemID("player", slot) then return nil end
    local info = { quality = GetInventoryItemQuality("player", slot) }
    if not NO_LEVEL[slot] then
        local ok, lvl = pcall(C_Item.GetCurrentItemLevel, ItemLocation:CreateFromEquipmentSlot(slot))
        if ok and type(lvl) == "number" then info.level = lvl end
    end
    local cur, max = GetInventoryItemDurability(slot)
    if type(cur) == "number" and type(max) == "number" and max > 0 then info.dura = cur / max end
    info.enchant = enchantOf(slot)
    return info
end

local function paint(button)
    local side = sideOf[button]
    if not side then return end
    local db = Skins.db()
    if not db.character then
        Skins.PaintSlot(button, side, nil, true)
        return
    end
    -- the ranged text starts behind the ammo slot while that one is shown
    local ammo = _G.CharacterAmmoSlot
    local after = (button == _G.CharacterRangedSlot and ammo and ammo:IsShown()) and ammo or nil
    Skins.PaintSlot(button, side, slotInfo(button:GetID()), false, after)
end

function Character.PaintAll()
    for button in pairs(sideOf) do paint(button) end
end

-- ---------------------------------------------------------------- frame --

local panels = {}

local function modernParts()
    local cf = _G.CharacterFrame
    local pdf = _G.PaperDollFrame
    local list = { cf.NineSlice, cf.PortraitContainer, cf.FrameGlow }
    local function add(t) if t then list[#list + 1] = t end end
    local statBoxes = { [_G.CharacterStatsPaneScrollBox or 0] = true, [_G.CharacterStatsPanePetScrollBox or 0] = true }
    for _, host in ipairs({ cf.LeftPaneHost, cf.RightPaneHost }) do
        if host then
            -- textures only: the panes may hold live frames (the stat list)
            for _, r in ipairs({ host:GetRegions() }) do add(r) end
            add(host.StoneBg)
            -- and the art of its plain child frames (the gold divider), never
            -- the stat lists themselves
            for _, c in ipairs({ host:GetChildren() }) do
                if not statBoxes[c] then
                    for _, r in ipairs({ c:GetRegions() }) do add(r) end
                end
            end
        end
    end
    -- every texture of the stat lists: border, class ground, the scroll line
    for box in pairs(statBoxes) do
        if box ~= 0 then for _, r in ipairs({ box:GetRegions() }) do add(r) end end
    end
    if pdf then
        add(pdf.TopBackgroundStripHost)
        local scene = pdf.CharacterModelScene
        if scene then add(scene.BackgroundOverlay) end
    end
    for _, n in ipairs({ "CharacterModelFrameBackgroundTopLeft", "CharacterModelFrameBackgroundTopRight",
                         "CharacterModelFrameBackgroundBotLeft", "CharacterModelFrameBackgroundBotRight" }) do
        add(_G[n])
    end
    for i = 1, 6 do
        local tab = _G["CharacterFrameModeTab" .. i]
        if tab then add(tab.Background) end
    end
    return list
end

local function buildPanels()
    if panels.window then return end
    local cf, pdf = _G.CharacterFrame, _G.PaperDollFrame
    panels.window = Skins.Ground(cf, Skins.BG)
    if pdf and pdf.TopBackgroundStripHost then
        -- the level line ("Level 5, Hunter"): a strip in the window's own
        -- dark, a shade lighter, under the title
        local strip = pdf.TopBackgroundStripHost
        -- on PaperDollFrame, which is never faded: it goes with the page,
        -- not over the other tabs' controls
        panels.strip = Skins.Panel(strip, Skins.STRIP, 0, pdf)
        panels.strip:SetFrameLevel(strip:GetFrameLevel())
    end
    local right = cf.RightPaneHost
    if right then
        -- the stat side reads as its own area: a darker ground on the pane
        local t = right:CreateTexture(nil, "BACKGROUND", nil, -8)
        t:SetPoint("TOPLEFT", right, "TOPLEFT", 0, -26)
        t:SetPoint("BOTTOMRIGHT", right, "BOTTOMRIGHT", -6, 8)
        t:SetColorTexture(0, 0, 0, 0.2)
        panels.statGround = t
    end
    panels.tabs = {}
    for i = 1, 6 do
        local tab = _G["CharacterFrameModeTab" .. i]
        if tab then
            local p = Skins.Panel(tab, Skins.STRIP, -4)
            p:SetFrameLevel(math.max(0, tab:GetFrameLevel() - 1))
            panels.tabs[#panels.tabs + 1] = p
        end
    end
end

local function showPanels(on)
    if not panels.window then return end
    panels.window:SetShown(on)
    if panels.strip then panels.strip:SetShown(on) end
    if panels.statGround then panels.statGround:SetShown(on) end
    local cf = _G.CharacterFrame
    Skins.FlatClose(cf.CloseButton or _G.CharacterFrameCloseButton, on)
    for _, box in ipairs({ _G.CharacterStatsPaneScrollBox, _G.CharacterStatsPanePetScrollBox }) do
        if box then Skins.FlatScrollBar(box.ScrollBar, on) end
    end
    for _, p in ipairs(panels.tabs) do p:SetShown(on) end
end

function Character.Apply()
    local cf = _G.CharacterFrame
    if not cf then return end
    local modern = Skins.Modern() and Skins.db().character
    if modern then
        buildPanels()
        for _, r in ipairs(modernParts()) do Skins.Fade(r) end
    end
    showPanels(modern)
    wipe(enchantCache)
    Character.PaintAll()
    if Skins.Stats then Skins.Stats.Apply() end
end

-- ---------------------------------------------------------------- events --

local hooked
function Character.Enable(mod)
    if not hooked and _G.PaperDollItemSlotButton_Update then
        hooked = true
        for n, side in pairs(SLOTS) do
            local b = _G["Character" .. n .. "Slot"]
            if b then sideOf[b] = side end
        end
        if _G.CharacterAmmoSlot then sideOf[_G.CharacterAmmoSlot] = "none" end
        hooksecurefunc("PaperDollItemSlotButton_Update", function(button)
            if sideOf[button] then paint(button) end
        end)
    end
    local function changed()
        wipe(enchantCache)
        if _G.CharacterFrame and _G.CharacterFrame:IsShown() then Character.PaintAll() end
    end
    mod:RegisterEvent("PLAYER_EQUIPMENT_CHANGED", changed)
    mod:RegisterEvent("WEAPON_ENCHANT_CHANGED", changed)
    -- an item the slots asked for has arrived: draw again, once per frame
    local queued
    mod:RegisterEvent("GET_ITEM_INFO_RECEIVED", function()
        if not Skins.waiting or queued then return end
        queued = true
        ns.NextFrame(function()
            queued = false
            Skins.waiting = false
            wipe(enchantCache)
            Character.PaintAll()
            if Skins.Inspect then Skins.Inspect.Repaint() end
        end)
    end)
    mod:RegisterEvent("UPDATE_INVENTORY_DURABILITY", function()
        if _G.CharacterFrame and _G.CharacterFrame:IsShown() then Character.PaintAll() end
    end)
end
