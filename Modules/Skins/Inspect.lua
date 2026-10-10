-- VuloForeverUI / Modules / Skins / Inspect
--
-- The inspect window (Blizzard_InspectUI, loaded on demand): a button frame
-- with an inset, the model with its own ground and border, the slots in
-- InspectPaperDollItemsFrame. InspectPaperDollItemSlotButton_Update draws a
-- slot from InspectFrame.unit; our hook runs after it. Item level and
-- enchant come from the item's link, so they hold for anyone inspected;
-- durability is not something the client tells about others.
local _, ns = ...
local Skins = ns.Skins

local Inspect = {}
table.insert(Skins.parts, Inspect)

local sideOf = {}
local enchantByLink = {}
local panel, ready

local function unit()
    local f = _G.InspectFrame
    return f and f.unit
end

local function slotInfo(slot)
    local u = unit()
    if not u then return nil end
    local link = GetInventoryItemLink(u, slot)
    if not (type(link) == "string" and ns.CanRead(link)) then return nil end
    local info = { quality = GetInventoryItemQuality(u, slot) }
    if not Skins.NO_LEVEL[slot] then
        local lvl = C_Item.GetDetailedItemLevelInfo(link)
        if type(lvl) == "number" then info.level = lvl end
    end
    local e = enchantByLink[link]
    if e == nil then
        local ok, data = pcall(C_TooltipInfo.GetHyperlink, link)
        e = ok and Skins.EnchantFrom(data) or false
        enchantByLink[link] = e
    end
    info.enchant = e or nil
    return info
end

local function paint(button)
    local side = sideOf[button]
    if not side then return end
    if not Skins.db().inspect then
        Skins.PaintSlot(button, side, nil)
        return
    end
    Skins.PaintSlot(button, side, slotInfo(button:GetID()))
end

local function paintAll()
    for b in pairs(sideOf) do paint(b) end
end

local function modernParts()
    local f = _G.InspectFrame
    local list = { f.NineSlice, f.Bg or _G.InspectFrameBg, f.TopTileStreaks, f.PortraitContainer,
                   _G.InspectFramePortrait }
    local inset = f.Inset or _G.InspectFrameInset
    if inset then list[#list + 1] = inset.NineSlice; list[#list + 1] = inset.Bg end
    local model = _G.InspectModelFrame
    if model then
        for _, r in ipairs({ model:GetRegions() }) do list[#list + 1] = r end
    end
    for i = 1, 3 do
        local tab = _G["InspectFrameModeTab" .. i]
        if tab then list[#list + 1] = tab.Background end
    end
    return list
end

function Inspect.Apply()
    local f = _G.InspectFrame
    if not (ready and f) then return end
    local modern = Skins.Modern() and Skins.db().inspect
    if modern then
        panel = panel or Skins.Ground(f, Skins.BG)
        for _, r in ipairs(modernParts()) do Skins.Fade(r) end
    end
    if panel then panel:SetShown(modern) end
    paintAll()
end

local function setup()
    if ready or not _G.InspectFrame or not _G.InspectPaperDollItemSlotButton_Update then return end
    ready = true
    for side, names in pairs(Skins.SLOTS) do
        for _, n in ipairs(names) do
            local b = _G["Inspect" .. n .. "Slot"]
            if b then sideOf[b] = side end
        end
    end
    hooksecurefunc("InspectPaperDollItemSlotButton_Update", function(button)
        if sideOf[button] then paint(button) end
    end)
    Inspect.Apply()
end

function Inspect.Enable(mod)
    if C_AddOns.IsAddOnLoaded("Blizzard_InspectUI") then setup() end
    mod:RegisterEvent("ADDON_LOADED", function(_, name)
        if name == "Blizzard_InspectUI" then setup() end
    end)
end
