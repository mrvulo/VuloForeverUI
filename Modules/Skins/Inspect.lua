-- VuloForeverUI / Modules / Skins / Inspect
--
-- The inspect window (Blizzard_InspectUI, loaded on demand): a button frame
-- with an inset, the model with its own ground and border, the slots in
-- InspectPaperDollItemsFrame. InspectPaperDollItemSlotButton_Update draws a
-- slot from InspectFrame.unit; our hook runs after it. Item level and
-- enchant come from the item's link, so they hold for anyone inspected;
-- durability is not something the client tells about others.
local _, ns = ...
local L = ns.L
local Skins = ns.Skins

local Inspect = {}
Skins.Inspect = Inspect
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
    if e == nil and not Skins.ItemReady(GetInventoryItemID(u, slot)) then
        e = false                     -- asked for; not kept until it arrives
    elseif e == nil then
        local ok, data = pcall(C_TooltipInfo.GetHyperlink, link)
        e = ok and Skins.EnchantFrom(data) or false
        enchantByLink[link] = e
    end
    info.enchant = e or nil
    info.textWidth = Skins.SideTextWidth(_G.InspectHeadSlot, _G.InspectHandsSlot)
    return info
end

local function paint(button)
    local side = sideOf[button]
    if not side then return end
    if not Skins.db().inspect then
        Skins.PaintSlot(button, side, nil, true)
        return
    end
    Skins.PaintSlot(button, side, slotInfo(button:GetID()))
end

-- The average item level beside the level line, the way the character
-- window shows yours: the client's own figure for the inspected unit, in the
-- character window's colour choice. InspectLevelText is 220 wide and centred,
-- so the text is placed from the end of the words, not the end of the box.
local avg

local function meanQualityColor(u)
    local sum, n = 0, 0
    for b in pairs(sideOf) do
        local slot = b:GetID()
        local q = not Skins.NO_LEVEL[slot] and GetInventoryItemID(u, slot) and GetInventoryItemQuality(u, slot)
        if type(q) == "number" and q >= 0 then sum, n = sum + q, n + 1 end
    end
    if n == 0 then return 1, 1, 1 end
    local r, g, b = C_Item.GetItemQualityColor(math.floor(sum / n + 0.5))
    if r then return r, g, b end
    return 1, 1, 1
end

local function paintAverage()
    local db = Skins.db()
    local lvl, pdf = _G.InspectLevelText, _G.InspectPaperDollFrame
    local u = unit()
    local on = Skins.mod.active and db.inspect and db.inspectAvgItemLevel ~= false and u and lvl and pdf
    if not avg then
        if not on then return end
        local f = CreateFrame("Frame", nil, pdf)
        f:SetAllPoints(pdf)
        f:SetFrameLevel((pdf.LevelTextWrapper or pdf):GetFrameLevel() + 2)
        avg = f:CreateFontString(nil, "OVERLAY")
        avg:SetWordWrap(false)
    end
    local ok, level = pcall(C_PaperDollInfo.GetInspectItemLevel, u)
    if not (on and ok and type(level) == "number" and ns.CanRead(level) and level > 0) then
        avg:Hide()
        return
    end
    ns.UI.FontFor("skins", avg, 13, "OUTLINE")
    avg:SetFormattedText(L["iLvL %d"], math.floor(level))
    local c = db.avgItemLevelCustom
    if db.avgItemLevelColor == "custom" and type(c) == "table" then
        avg:SetTextColor(c.r, c.g, c.b)
    else
        avg:SetTextColor(meanQualityColor(u))
    end
    avg:ClearAllPoints()
    avg:SetPoint("LEFT", lvl, "CENTER", (lvl:GetStringWidth() or 0) / 2 + 8, 0)
    avg:Show()
end

local function paintAll()
    for b in pairs(sideOf) do paint(b) end
    paintAverage()
end

function Inspect.Repaint()
    if ready and _G.InspectFrame and _G.InspectFrame:IsShown() then paintAll() end
end

local function modernParts()
    local f = _G.InspectFrame
    local list = {}
    -- appended one by one: a missing piece must not end the list early
    local function add(t) if t then list[#list + 1] = t end end
    add(f.NineSlice); add(f.Bg or _G.InspectFrameBg); add(f.TopTileStreaks)
    add(f.PortraitContainer); add(_G.InspectFramePortrait)
    local inset = f.Inset or _G.InspectFrameInset
    if inset then add(inset.NineSlice); add(inset.Bg) end
    local model = _G.InspectModelFrame
    if model then
        for _, r in ipairs({ model:GetRegions() }) do add(r) end
    end
    for i = 1, 3 do
        local tab = _G["InspectFrameModeTab" .. i]
        if tab then add(tab.Background) end
    end
    return list
end

function Inspect.Apply()
    local f = _G.InspectFrame
    if not (ready and f) then return end
    local db = Skins.db()
    local modern = Skins.mod.active and db.inspect and db.inspectStyle == "modern"
    if modern then
        panel = panel or Skins.Ground(f, Skins.BG)
        for _, r in ipairs(modernParts()) do Skins.Fade(r) end
    end
    if panel then panel:SetShown(modern) end
    Skins.FlatClose(f.CloseButton or _G.InspectFrameCloseButton, modern)
    paintAll()
end

local function setup()
    if ready or not _G.InspectFrame or not _G.InspectPaperDollItemSlotButton_Update then return end
    ready = true
    -- The inspect window is narrower: its weapon row has no room for text
    -- beside or above the slots, so the weapons show level and ring only.
    local WEAPON = { MainHand = true, SecondaryHand = true, Ranged = true }
    for n, side in pairs(Skins.SLOTS) do
        local b = _G["Inspect" .. n .. "Slot"]
        if b then sideOf[b] = WEAPON[n] and "none" or side end
    end
    hooksecurefunc("InspectPaperDollItemSlotButton_Update", function(button)
        if sideOf[button] then paint(button) end
    end)
    -- the level line is written on open and when the inspect data arrives;
    -- the average goes with it
    local pdf = _G.InspectPaperDollFrame
    if pdf and type(pdf.SetLevel) == "function" then
        hooksecurefunc(pdf, "SetLevel", paintAverage)
    end
    Inspect.Apply()
end

function Inspect.Enable(mod)
    if C_AddOns.IsAddOnLoaded("Blizzard_InspectUI") then setup() end
    mod:RegisterEvent("ADDON_LOADED", function(_, name)
        if name == "Blizzard_InspectUI" then setup() end
    end)
end
