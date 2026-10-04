-- VuloForeverUI / Modules / Auras / Enchants
--
-- Temporary weapon enchants -- a shaman's imbue, a poison, a sharpening stone.
--
-- They are not auras, so the engine's aura rows never show them: the client's
-- own buff row adds them by hand from C_Item.GetWeaponEnchantInfo
-- (Blizzard_BuffFrame/BuffFrame.lua:763), and the container's own
-- AddItemEnchantment slots draw nothing on this client. With our rows in
-- place of the client's they would simply be gone, so they are put back where
-- the client has them: the first places of the buff row, styled like the
-- buffs, which start that many places further in.
--
-- GetWeaponEnchantInfo stays readable in combat (measured, see
-- docs/forever-client-research.md); every value is still checked before it is
-- used, so a client that hides one costs that button its text, nothing more.
local _, ns = ...
local A = ns.Auras

-- The client's own order: main hand, off hand, ranged, each with the inventory
-- slot whose item gives the icon and the tooltip.
local SLOTS = {
    { key = "MainHand", inv = 16 },
    { key = "OffHand",  inv = 17 },
    { key = "Ranged",   inv = 18 },
}

local bar                -- { holder = the buff block, buttons = {} }
local mod                -- the auras module, handed in by Build

-- The same wording as the engine's formatter on the buff rows (Core/Utils.lua
-- AuraDurationFormatter): plain seconds, then whole minutes, hours, days,
-- each rounded up.
local function shortTime(s)
    if s >= 86400 then return "%dd", math.ceil(s / 86400) end
    if s >= 3600 then return "%dh", math.ceil(s / 3600) end
    if s >= 60 then return "%dm", math.ceil(s / 60) end
    return "%d", math.ceil(s)
end

-- The slot's temporary enchant: seconds left (nil when unknown) and charges.
-- `false` when the slot has none.
local function enchantOf(slot)
    local id = Enum.WeaponSlot and Enum.WeaponSlot[slot.key]
    if id == nil then return false end
    local ok, list = pcall(C_Item.GetWeaponEnchantInfo, id)
    if not ok or type(list) ~= "table" then return false end
    for _, e in pairs(list) do
        if ns.CanRead(e.hasEnchant) and e.hasEnchant
            and ns.CanRead(e.enchantType) and e.enchantType ~= Enum.ItemEnchantType.Permanent then
            local left, charges = e.timeLeft, e.charges
            if not (ns.CanRead(left) and type(left) == "number" and left > 0) then left = nil end
            if not (ns.CanRead(charges) and type(charges) == "number") then charges = 0 end
            return left and left / 1000, charges
        end
    end
    return false
end

-- ---------------------------------------------------------------------------
-- Buttons
-- ---------------------------------------------------------------------------

local function onEnter(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
    GameTooltip:SetInventoryItem("player", self.inv)
    GameTooltip:Show()
end

local function onLeave() GameTooltip:Hide() end

-- Built anew whenever the settings change, like the engine's buttons are; the
-- old ones are only hidden and handed back to the pool below.
local function styleButton(button, db, holder)
    local px   = ns:Pixel(holder, 1)
    local size = math.max(px, ns:PixelSnap(db.iconSize, holder))
    local zoom = db.buffZoom / 100
    button:SetSize(size, size)

    button.icon:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)

    local bSize, c = db.buffBorderSize, db.buffBorderColor
    if bSize > 0 then
        ns.LayoutEdgesAt(button.edges, button, bSize * px, c.r, c.g, c.b, c.a or 1)
        for _, t in pairs(button.edges) do t:Show() end
    else
        for _, t in pairs(button.edges) do t:Hide() end
    end

    local font = ns.ModuleFontPath("auras")
    local anchors = A.Style.ANCHORS
    local function place(fs, point, x, y, fontSize)
        local a = anchors[point] or anchors.CENTER
        fs:SetFont(font, fontSize, "OUTLINE")
        fs:ClearAllPoints()
        fs:SetPoint(a[1], button, a[1], a[2] + x, a[3] + y)
    end
    place(button.duration, db.durationPosition, db.durationX, db.durationY, db.durationSize)
    place(button.count, db.stackPosition, db.stackX, db.stackY, db.stackSize)
    button.duration:SetShown(db.showDuration)
    button.count:SetShown(db.showStacks)
end

local function newButton(holder, slot)
    local b = CreateFrame("Frame", nil, holder)
    b.inv = slot.inv
    b.slot = slot
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints(b)
    b.edges = ns.MakeEdges(b, "OVERLAY")
    for _, t in pairs(b.edges) do
        if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false) end
        if t.SetTexelSnappingBias then t:SetTexelSnappingBias(0) end
    end
    b.duration = b:CreateFontString(nil, "OVERLAY")
    b.count = b:CreateFontString(nil, "OVERLAY")
    b:EnableMouse(true)
    b:SetScript("OnEnter", onEnter)
    b:SetScript("OnLeave", onLeave)
    b:Hide()
    return b
end

-- ---------------------------------------------------------------------------
-- Update
-- ---------------------------------------------------------------------------

local shown = 0          -- enchant buttons standing at the start of the buff row

-- How many places of the buff row the enchants take: Bars.lua asks this every
-- time it places the buff container.
function A.EnchantSlots()
    if not (bar and mod and mod.active and mod.db.weaponEnchants) then return 0 end
    return math.max(0, shown)
end

-- The shown buttons from the buff row's starting corner, on the pixel the
-- container's own corner was snapped to.
function A.PlaceEnchants()
    local b = bar and A.Bars.buffs
    if not (b and b.corner) then return end
    local db = mod.db
    local size = math.max(ns:Pixel(bar.holder, 1), ns:PixelSnap(db.iconSize, bar.holder))
    local step = size + ns:PixelSnap(db.paddingBuffs, bar.holder)
    if b.corner:find("RIGHT") then step = -step end
    local n = 0
    for _, button in ipairs(bar.buttons) do
        if button:IsShown() then
            button:ClearAllPoints()
            button:SetPoint(b.corner, bar.holder, b.corner, b.dx + n * step, b.dy)
            n = n + 1
        end
    end
end

local function update()
    if not (bar and mod and mod.active and mod.db.weaponEnchants) then return end
    local n, ticking = 0, false
    for _, b in ipairs(bar.buttons) do
        local secs, charges = enchantOf(b.slot)
        if secs == false then
            b:Hide()
        else
            b.icon:SetTexture(GetInventoryItemTexture("player", b.inv))
            if secs then
                b.duration:SetFormattedText(shortTime(secs))
                ticking = true
            else
                b.duration:SetText("")
            end
            b.count:SetText(charges > 1 and charges or "")
            b:Show()
            n = n + 1
        end
    end
    -- the time left is not an event; it is read again while something runs down
    bar.ticking = ticking
    if n ~= shown then
        -- one more or one fewer: the buffs move up or make room
        shown = n
        A.PlaceContainer("buffs")
    else
        A.PlaceEnchants()
    end
end

-- Only UNIT_INVENTORY_CHANGED names a unit; the others carry a slot number.
local function onEvent(event, unit)
    if event == "UNIT_INVENTORY_CHANGED" and unit ~= "player" then return end
    update()
end

local EVENTS = { "WEAPON_ENCHANT_CHANGED", "WEAPON_SLOT_CHANGED",
                 "PLAYER_EQUIPMENT_CHANGED", "UNIT_INVENTORY_CHANGED" }

local function listen(on)
    for _, event in ipairs(EVENTS) do
        if on then ns:RegisterEvent(event, onEvent) else ns:UnregisterEvent(event, onEvent) end
    end
end

-- ---------------------------------------------------------------------------
-- Build / hide, called by Bars.lua right after the buff row is built
-- ---------------------------------------------------------------------------

function A.HideEnchants()
    if not bar then return end
    for _, b in ipairs(bar.buttons) do b:Hide() end
    bar.ticking = false
    shown = 0
    listen(false)
end

function A.BuildEnchants(m)
    mod = m
    local db = m.db
    local buffs = A.Bars.buffs
    if not (db.weaponEnchants and buffs) then
        A.HideEnchants()
        if buffs and buffs.container then A.PlaceContainer("buffs") end
        return
    end
    if not bar then
        -- the buttons live in the buff block itself: no box of their own
        bar = { holder = buffs.holder, buttons = {} }
        for i, slot in ipairs(SLOTS) do bar.buttons[i] = newButton(buffs.holder, slot) end
        local ticker = CreateFrame("Frame", nil, buffs.holder)
        local acc = 0
        ticker:SetScript("OnUpdate", function(_, elapsed)
            if not bar.ticking then return end
            acc = acc + elapsed
            if acc < 0.5 then return end
            acc = 0
            update()
        end)
    end
    for _, b in ipairs(bar.buttons) do styleButton(b, db, bar.holder) end
    listen(true)
    -- forces the buffs to be placed again with the room the enchants need
    shown = -1
    update()
end
