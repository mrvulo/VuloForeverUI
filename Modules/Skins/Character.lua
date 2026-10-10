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

local SLOTS = {
    left   = { "Head", "Neck", "Shoulder", "Back", "Chest", "Shirt", "Tabard", "Wrist" },
    right  = { "Hands", "Waist", "Legs", "Feet", "Finger0", "Finger1", "Trinket0", "Trinket1" },
    bottom = { "MainHand", "SecondaryHand", "Ranged" },
}
local NO_LEVEL = { [4] = true, [19] = true }     -- shirt, tabard
Skins.SLOTS, Skins.NO_LEVEL = SLOTS, NO_LEVEL

local sideOf = {}          -- client slot button -> "left" | "right" | "bottom"
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
    local v = enchantCache[slot]
    if v == nil then
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
        Skins.PaintSlot(button, side, nil)
        return
    end
    Skins.PaintSlot(button, side, slotInfo(button:GetID()))
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
    for _, host in ipairs({ cf.LeftPaneHost, cf.RightPaneHost }) do
        if host then
            -- textures only: the panes may hold live frames (the stat list)
            for _, r in ipairs({ host:GetRegions() }) do add(r) end
            add(host.StoneBg)
        end
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
    local stats = _G.CharacterStatsPaneScrollBox
    if stats then add(stats.Border); add(stats.ClassBackground) end
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
        panels.strip = Skins.Panel(strip, Skins.STRIP, 0, cf)
        panels.strip:SetFrameLevel(strip:GetFrameLevel())
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
        for side, names in pairs(SLOTS) do
            for _, n in ipairs(names) do
                local b = _G["Character" .. n .. "Slot"]
                if b then sideOf[b] = side end
            end
        end
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
    mod:RegisterEvent("UPDATE_INVENTORY_DURABILITY", function()
        if _G.CharacterFrame and _G.CharacterFrame:IsShown() then Character.PaintAll() end
    end)
end
