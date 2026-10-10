-- VuloForeverUI / Modules / Bags / Slots
--
-- The item buttons: a pool of them, and what one looks like once it has an
-- item in it.
--
-- THE POOL IS THE WHOLE POINT
--
-- These are secure buttons from the client's own container template, which is
-- what makes a left click use the item and a drag pick it up. A button made
-- while a fight is on is tainted for the rest of the session, and the failure
-- shows up as "action blocked" the first time somebody drinks a potion in a
-- dungeon. So: the pool is grown out of combat, generously, and a window that
-- runs out of slots mid-fight draws what it has and waits.
--
-- Each button also gets a PARENT of its own, because that is where the bag
-- number lives: the client's secure click reads the bag from the parent's id
-- and the slot from the button's. That is also why our own state lives in
-- Bags.State(button) instead of on the button -- a custom field there taints
-- the same click.
local _, ns = ...
local Bags = ns.Bags

local Slots = {}
Bags.Slots = Slots

-- ONE POOL PER WINDOW, not one for the module.
--
-- The bags and the bank are open at the same time whenever anyone visits a
-- banker, and a single shared pool means the second window to lay itself out
-- takes the buttons the first one is already using -- the bank would draw
-- itself out of the bags' slots and the bags would go blank. Each window keeps
-- its own list and its own cursor into it.
local pools, host = {}, nil

-- The rounded look: the house's rounded-square mask, a one-pixel ring cut to
-- the same outline, and the thicker ring for the just-picked-up mark. All
-- three files leave 10 of their 128 pixels transparent on every side, so they
-- are stretched past the slot by that much to make the shape fill it.
local MASK_ROUND = "Interface\\AddOns\\VuloForeverUI\\Media\\Masks\\csquare_mask.tga"
local RING_THIN  = "Interface\\AddOns\\VuloForeverUI\\Media\\Masks\\csquare_ring.tga"
local RING_THICK = "Interface\\AddOns\\VuloForeverUI\\Media\\Buttons\\csquare_border.tga"
local ROUND_MARGIN = 10 / 108
local WARM_TARGET = 160     -- a full set of bags plus room to grow

local function poolFor(owner)
    local p = pools[owner]
    if not p then p = { slots = {}, used = 0 }; pools[owner] = p end
    return p
end

local function ensureHost()
    if host then return host end
    host = CreateFrame("Frame", nil, UIParent)
    host:Hide()
    return host
end

-- ---------------------------------------------------------------- pool --

-- The flat look, laid over the client's template once per button.
--
-- The template brings its own art: a bevelled frame (NormalTexture) that sits
-- on every slot, full or empty, a quality ring (IconBorder), a rounded mask on
-- the icon, and the new-item and shop glows. All of it goes by the regions'
-- own methods -- alpha, texture, anchors -- and never by a field written on
-- the button, which would taint the secure click it carries. In its place: a
-- dark ground on OUR parent frame, and a one-pixel border inside the slot in
-- the item's quality colour, drawn on a frame of ours above the button.
local function skinButton(slot)
    local button, parent = slot.button, slot.frame

    for _, key in ipairs({ "NormalTexture", "IconBorder", "NewItemTexture",
        "BattlepayItemTexture", "flash" }) do
        local r = button[key]
        if r and r.SetAlpha then r:SetAlpha(0) end
    end
    local normal = button.GetNormalTexture and button:GetNormalTexture()
    if normal then normal:SetAlpha(0) end
    if button.newitemglowAnim and button.newitemglowAnim.Stop then button.newitemglowAnim:Stop() end

    -- The icon fills the slot edge to edge, square: the client's mask rounds
    -- its corners, and the border below would show the gap.
    local icon = button.icon or button.Icon
    if icon then
        icon:ClearAllPoints()
        icon:SetAllPoints(button)
        local mask = button.IconMask
        if mask and icon.RemoveMaskTexture then
            pcall(icon.RemoveMaskTexture, icon, mask)
            mask:Hide()
        end
    end

    -- Hover and press as a flat wash over the whole slot, instead of the
    -- template's glossy squares sized for its old frame.
    local hl = button.GetHighlightTexture and button:GetHighlightTexture()
    if hl then
        hl:ClearAllPoints(); hl:SetAllPoints(button)
        hl:SetColorTexture(1, 1, 1, 0.10)
    end
    local pushed = button.GetPushedTexture and button:GetPushedTexture()
    if pushed then
        pushed:ClearAllPoints(); pushed:SetAllPoints(button)
        pushed:SetColorTexture(1, 1, 1, 0.18)
    end

    -- The ground an empty slot shows, on our own frame behind the button.
    local ground = parent:CreateTexture(nil, "BACKGROUND")
    ground:SetAllPoints(parent)
    ground:SetColorTexture(1, 1, 1, 1)
    slot.ground = ground

    -- The border has to draw over the icon, and a region of our parent frame
    -- draws under the button whatever its layer. So: a mouse-dead frame of our
    -- own, one step above the button, carrying four edge textures.
    local ring = CreateFrame("Frame", nil, parent)
    ring:SetAllPoints(parent)
    ring:SetFrameLevel(button:GetFrameLevel() + 1)
    ring:EnableMouse(false)
    slot.ring = ring
    slot.edges = {}
    for _, side in ipairs({ "top", "bot", "lft", "rgt" }) do
        local t = ring:CreateTexture(nil, "OVERLAY")
        t:SetTexture("Interface\\Buttons\\WHITE8X8")
        slot.edges[side] = t
    end

    -- The rounded parts, made once and switched on by the setting. The masks
    -- are regions: one on the button for its icon and washes, one on our
    -- parent for the ground. Neither writes a field on the button.
    slot.iconMask = button:CreateMaskTexture()
    slot.iconMask:SetTexture(MASK_ROUND, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    slot.groundMask = parent:CreateMaskTexture()
    slot.groundMask:SetTexture(MASK_ROUND, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    slot.roundRing = ring:CreateTexture(nil, "OVERLAY")
    slot.roundRing:SetTexture(RING_THIN)
    slot.roundRing:Hide()
    slot.roundFresh = ring:CreateTexture(nil, "OVERLAY", nil, 1)
    slot.roundFresh:SetTexture(RING_THICK)
    slot.roundFresh:Hide()
end

-- Rounded or square, as the setting says. The masks are added and taken off
-- only when that changes; the stretch past the slot follows its size.
local function applyRound(slot, round)
    local button = slot.button
    local regions = {
        button.icon or button.Icon,
        button.GetHighlightTexture and button:GetHighlightTexture(),
        button.GetPushedTexture and button:GetPushedTexture(),
    }
    if slot.isRound ~= round then
        local fn = round and "AddMaskTexture" or "RemoveMaskTexture"
        for _, r in ipairs(regions) do
            if r and r[fn] then pcall(r[fn], r, slot.iconMask) end
        end
        pcall(slot.ground[fn], slot.ground, slot.groundMask)
        slot.isRound = round
    end
    if not round then
        slot.roundRing:Hide()
        slot.roundFresh:Hide()
        return
    end
    local e = (slot.frame:GetWidth() or 37) * ROUND_MARGIN
    for _, t in ipairs({ slot.iconMask, slot.groundMask, slot.roundRing, slot.roundFresh }) do
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", slot.frame, "TOPLEFT", -e, e)
        t:SetPoint("BOTTOMRIGHT", slot.frame, "BOTTOMRIGHT", e, -e)
    end
end

-- The inside border, one physical pixel wide. Laid out at paint time, when the
-- slot is on screen and its scale is the real one.
local function layoutRing(slot, r, g, b, a)
    local e, ring = slot.edges, slot.ring
    if slot.isRound then
        for _, t in pairs(e) do t:Hide() end
        slot.roundRing:SetVertexColor(r, g, b, a)
        slot.roundRing:Show()
        return
    end
    for _, t in pairs(e) do t:Show() end
    local px = ns:Pixel(ring, 1)
    if not (px and px > 0) then px = 1 end
    e.top:ClearAllPoints(); e.top:SetPoint("TOPLEFT", ring, "TOPLEFT"); e.top:SetPoint("TOPRIGHT", ring, "TOPRIGHT"); e.top:SetHeight(px)
    e.bot:ClearAllPoints(); e.bot:SetPoint("BOTTOMLEFT", ring, "BOTTOMLEFT"); e.bot:SetPoint("BOTTOMRIGHT", ring, "BOTTOMRIGHT"); e.bot:SetHeight(px)
    e.lft:ClearAllPoints(); e.lft:SetPoint("TOPLEFT", ring, "TOPLEFT"); e.lft:SetPoint("BOTTOMLEFT", ring, "BOTTOMLEFT"); e.lft:SetWidth(px)
    e.rgt:ClearAllPoints(); e.rgt:SetPoint("TOPRIGHT", ring, "TOPRIGHT"); e.rgt:SetPoint("BOTTOMRIGHT", ring, "BOTTOMRIGHT"); e.rgt:SetWidth(px)
    for _, t in pairs(e) do t:SetVertexColor(r, g, b, a) end
end

local function makeSlot(owner)
    if InCombatLockdown() then return nil end
    local parent = CreateFrame("Frame", nil, ensureHost())
    parent:SetSize(Bags.SLOT_SIZE, Bags.SLOT_SIZE)

    local ok, button = pcall(CreateFrame, "ItemButton", nil, parent, "ContainerFrameItemButtonTemplate")
    if not ok or not button then return nil end
    button:SetAllPoints(parent)
    -- Shown explicitly. A button from this template does not necessarily come
    -- up shown -- the client's own container shows its buttons itself as it
    -- fills them -- and showing only the frame around it gave a window with
    -- the right shape, the right counts and no icons at all.
    button:Show()

    local slot = { frame = parent, button = button }
    skinButton(slot)

    -- One font string, and nothing else: the quality border comes from the
    -- client's own setter further down, and the four edge textures an earlier
    -- draft made here were laid out at zero width -- a thousand hidden
    -- textures for a border that could never be seen.
    local level = button:CreateFontString(nil, "OVERLAY")
    level:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -2)
    slot.level = level

    -- The three small marks an item can carry, each in a corner of its own so
    -- two of them are never drawn on top of each other: the bind tag bottom
    -- left, the set name bottom right, the pin top right.
    local tag = button:CreateFontString(nil, "OVERLAY")
    tag:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 2, 2)
    slot.tag = tag

    local setName = button:CreateFontString(nil, "OVERLAY")
    setName:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)
    setName:SetJustifyH("RIGHT")
    slot.setName = setName

    -- The vendor-junk mark, bottom right. Our own font string on the button,
    -- like the item level; it steps left of the stack count when both show.
    local junk = button:CreateFontString(nil, "OVERLAY")
    slot.junk = junk

    -- The upgrade arrow: the client's own green bag arrow where it has one,
    -- the old green stream arrow otherwise.
    local upgrade = button:CreateTexture(nil, "OVERLAY")
    if C_Texture.GetAtlasInfo("bags-greenarrow") then
        upgrade:SetAtlas("bags-greenarrow")
    else
        upgrade:SetTexture("Interface\\Buttons\\UI-MicroStream-Green")
    end
    upgrade:SetSize(12, 12)
    upgrade:Hide()
    slot.upgrade = upgrade

    local pin = button:CreateTexture(nil, "OVERLAY")
    pin:SetAtlas("PetJournal-FavoritesIcon")
    pin:SetSize(10, 10)
    pin:SetPoint("TOPRIGHT", button, "TOPRIGHT", -1, -1)
    pin:Hide()
    slot.pin = pin

    -- "Just picked up": a tinted frame around the icon rather than a fourth
    -- corner mark, because it has to read at a glance across a full bag.
    slot.freshEdges = ns.MakeEdges(button, "OVERLAY")

    -- The tool overlay. It is a plain button, it only exists while a tool mode
    -- is on, and it is what makes pinning and splitting possible at all: the
    -- item button underneath is SECURE, so a click on it uses the item and no
    -- hook of ours may take that click away.
    local overlay = CreateFrame("Button", nil, parent)
    overlay:SetAllPoints(parent)
    overlay:SetFrameLevel(button:GetFrameLevel() + 5)
    overlay:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    overlay:Hide()
    local wash = overlay:CreateTexture(nil, "BACKGROUND")
    wash:SetAllPoints(overlay)
    wash:SetColorTexture(0, 0, 0, 0.35)
    overlay.wash = wash
    slot.overlay = overlay

    -- The tip under the item's own tooltip. HookScript, not SetScript: the
    -- template's own handler is what shows the tooltip in the first place, and
    -- taking it away would leave a bag with no tooltips at all. A hook adds no
    -- field to the button and takes no click.
    button:HookScript("OnLeave", function(self)
        if self:IsMouseOver() then Bags.NoteSpuriousLeave(self) end
    end)
    button:HookScript("OnEnter", function(self)
        local db = Bags.db()
        local parent = self:GetParent()
        if parent then
            Bags.Marks.Acknowledge(parent:GetID(), self:GetID())
        end
        if not db.pinnedTips then return end
        if not (GameTooltip and GameTooltip:IsShown() and GameTooltip:GetOwner() == self) then return end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(ns.L["Pin and recent marks are set from the bag's tool row."], 0.6, 0.6, 0.65)
        GameTooltip:Show()
    end)

    local p = poolFor(owner)
    p.slots[#p.slots + 1] = slot
    return slot
end

-- Grow the pool up to what a full set of bags needs. Called at login and every
-- time a fight ends.
-- Grown for both windows, because the bank window has to be ready before the
-- player reaches a banker: at the banker the fight is over, but the bags may
-- already be full and the pool is cheaper to have than to need.
function Slots.Warm()
    if InCombatLockdown() then return end
    for _, owner in ipairs({ "bags", "bank" }) do
        local p = poolFor(owner)
        local want = (owner == "bags") and math.min(WARM_TARGET, math.max(#p.slots + 24, 64)) or 40
        while #p.slots < want do
            if not makeSlot(owner) then break end
        end
    end
end

-- Hand out the next free slot, or nothing at all. "Nothing at all" is a real
-- answer here: in combat the pool cannot grow, and a missing slot is better
-- than a tainted one.
function Slots.Begin(owner)
    poolFor(owner).used = 0
end

-- Second return value: WHY there is no slot. "in combat" is a wait that
-- passes; anything else means the client would not give us a button at all,
-- and the two must not reach the player as the same sentence.
function Slots.Next(owner)
    local p = poolFor(owner)
    p.used = p.used + 1
    local slot = p.slots[p.used]
    if slot then return slot end
    if InCombatLockdown() then return nil, "combat" end
    local made = makeSlot(owner)
    if made then return made end
    return nil, "refused"
end

function Slots.HideRest(owner)
    local p = poolFor(owner)
    for i = p.used + 1, #p.slots do
        p.slots[i].frame:Hide()
    end
end

function Slots.PoolSize(owner) return #poolFor(owner).slots end

-- ---------------------------------------------------------------- paint --

local POOR = (Enum.ItemQuality and Enum.ItemQuality.Poor) or 0

-- THE SETTERS EXIST IN TWO SHAPES, and which one a client has is not ours to
-- assume: newer builds carry them as methods on the button, older ones only as
-- global functions. Both are tried, and a failure is SAID ONCE rather than
-- swallowed -- the first draft wrapped each call in a bare pcall, and when the
-- method was not there the window came up with headings and no items and no
-- word about why.
-- The first n LETTERS of a name, not the first n bytes. A German set name is
-- full of two-byte characters, and cutting one in half draws a question mark.
local function firstLetters(text, n)
    local out, count = "", 0
    for char in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        out = out .. char
        count = count + 1
        if count >= n then break end
    end
    return out
end

local reported = {}

local function callSetter(button, name, ...)
    local method = button[name]
    if type(method) == "function" then
        local ok = pcall(method, button, ...)
        if ok then return true end
    end
    local global = _G[name]
    if type(global) == "function" then
        local ok = pcall(global, button, ...)
        if ok then return true end
    end
    if not reported[name] then
        reported[name] = true
        ns:Print(ns.L["The client has no %s; bag icons may stay empty."], name)
    end
    return false
end

-- One slot, bound to one place in one bag. The two ids are what the client's
-- secure click reads, and they are set with the frame's own setter -- which is
-- not a custom field and is therefore allowed.
-- Profession bags by the bag family the client reports for them: one colour
-- each, from the lowest bit that is set. 0 is a normal bag, which keeps the
-- plain look.
local FAMILY_COLORS = {
    [0x0001] = { 0.80, 0.65, 0.40 },  -- quiver
    [0x0002] = { 0.80, 0.65, 0.40 },  -- ammo pouch
    [0x0004] = { 0.65, 0.35, 0.90 },  -- soul bag
    [0x0008] = { 0.75, 0.50, 0.30 },  -- leatherworking
    [0x0010] = { 0.45, 0.70, 0.95 },  -- inscription
    [0x0020] = { 0.35, 0.85, 0.35 },  -- herbs
    [0x0040] = { 0.75, 0.45, 0.95 },  -- enchanting
    [0x0080] = { 0.95, 0.65, 0.25 },  -- engineering
    [0x0200] = { 0.95, 0.40, 0.65 },  -- gems
    [0x0400] = { 0.70, 0.70, 0.75 },  -- mining
    [0x1000] = { 0.35, 0.70, 0.90 },  -- fishing
    [0x2000] = { 0.95, 0.55, 0.40 },  -- cooking
}
local FAMILY_DEFAULT = { 0.40, 0.80, 0.80 }

-- The reagent bag's own slot (Enum.BagIndex.ReagentBag): only reagents go
-- in, but the client reports no family for it, so it was never tinted.
local REAGENT_BAG = Enum.BagIndex and Enum.BagIndex.ReagentBag
local REAGENT_COLOR = { 0.35, 0.80, 0.55 }

local function colorOf(family)
    local mask = 1
    while mask <= family do
        if family % (mask * 2) >= mask then return FAMILY_COLORS[mask] or FAMILY_DEFAULT end
        mask = mask * 2
    end
    return FAMILY_DEFAULT
end

-- The family of the BAG ITEM in a bag slot, for a slot the container itself
-- reports none for: a leather reagent bag is leatherworking, whatever its
-- container says.
local getItemFamily = (C_Item and C_Item.GetItemFamily) or _G.GetItemFamily
local toInvSlot = (C_Container and C_Container.ContainerIDToInventoryID) or _G.ContainerIDToInventoryID

-- Asked once per bag that sits in the slot: bagID -> { itemID, family }.
local bagFamilyCache = {}

local function bagItemFamily(bagID)
    if not (getItemFamily and toInvSlot) or bagID <= 0 then return nil end
    local ok, inv = pcall(toInvSlot, bagID)
    local itemID = ok and inv and GetInventoryItemID("player", inv)
    if not itemID then return nil end
    local hit = bagFamilyCache[bagID]
    if hit and hit.itemID == itemID then return hit.family end
    local ok2, family = pcall(getItemFamily, itemID)
    family = (ok2 and type(family) == "number" and family > 0) and family or nil
    bagFamilyCache[bagID] = { itemID = itemID, family = family }
    return family
end

-- A reagent bag only takes its own reagents, so what lies in it says what it
-- is -- the one answer left when the client reports a family for neither the
-- slot nor the bag (measured on Forever: a leather reagent bag reports none).
-- Trade goods subclass -> the bag family it belongs to; language-independent.
local TRADEGOODS = 7
local SUBCLASS_FAMILY = {
    [6]  = 0x0008,   -- leather          -> leatherworking
    [9]  = 0x0020,   -- herb             -> herbs
    [7]  = 0x0400,   -- metal and stone  -> mining
    [12] = 0x0040,   -- enchanting
    [8]  = 0x2000,   -- cooking
    [4]  = 0x0200,   -- jewelcrafting    -> gems
    [1]  = 0x0080, [2] = 0x0080, [3] = 0x0080,   -- parts, explosives, devices -> engineering
    [16] = 0x0010,   -- inscription
}
local contentCache = { at = -1, family = {} }

local function contentFamily(bagID)
    local now = GetTime()
    if contentCache.at ~= now then contentCache.at = now; wipe(contentCache.family) end
    local hit = contentCache.family[bagID]
    if hit ~= nil then return hit or nil end
    local found = false
    for slot = 1, C_Container.GetContainerNumSlots(bagID) or 0 do
        local itemID = C_Container.GetContainerItemID(bagID, slot)
        if itemID then
            local _, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(itemID)
            if classID == TRADEGOODS and SUBCLASS_FAMILY[subclassID] then
                found = SUBCLASS_FAMILY[subclassID]
                break
            end
        end
    end
    contentCache.family[bagID] = found
    return found or nil
end

-- What the slot holds decides first (the container's family), then what the
-- bag item is, then -- for the reagent bag -- what lies in it, and only a
-- reagent bag that tells nothing at all gets the general reagent colour.
local function familyColor(bagID)
    local _, family = C_Container.GetContainerNumFreeSlots(bagID)
    if type(family) ~= "number" or family <= 0 then family = bagItemFamily(bagID) end
    if not family and REAGENT_BAG and bagID == REAGENT_BAG then family = contentFamily(bagID) end
    if family then return colorOf(family) end
    if REAGENT_BAG and bagID == REAGENT_BAG then return REAGENT_COLOR end
    return nil
end
Slots.FamilyColor = familyColor

-- ---------------------------------------------------------------- corners --
--
-- Every mark goes to the corner the options give it. Two in one corner sit
-- side by side, in this order outward from the corner; in the bottom right
-- the client's stack count is already there, so the row starts left of it.
local CORNER_ORDER = {
    { "pin", "cornerPin", "TOPRIGHT" },
    { "upgrade", "cornerUpgrade", "TOPRIGHT" },
    { "junk", "cornerJunk", "BOTTOMRIGHT" },
    { "level", "cornerLevel", "TOPLEFT" },
    { "tag", "cornerBind", "BOTTOMLEFT" },
    { "setName", "cornerSet", "BOTTOMRIGHT" },
}
local INSET = {
    TOPLEFT = { 2, -2 }, TOPRIGHT = { -2, -2 },
    BOTTOMLEFT = { 2, 2 }, BOTTOMRIGHT = { -2, 2 },
}

local function placeCorners(slot, button, db)
    local last = {}
    for _, e in ipairs(CORNER_ORDER) do
        local region = slot[e[1]]
        if region and region:IsShown() then
            local corner = db[e[2]]
            if not INSET[corner] then corner = e[3] end
            local prev = last[corner]
            if not prev and corner == "BOTTOMRIGHT" then
                local count = button.Count or button.count
                if count and count:IsShown() and (count:GetText() or "") ~= "" then prev = count end
            end
            region:ClearAllPoints()
            if prev then
                local edge = corner:find("^TOP") and "TOP" or "BOTTOM"
                if corner:find("RIGHT$") then
                    region:SetPoint(edge .. "RIGHT", prev, edge .. "LEFT", -1, 0)
                else
                    region:SetPoint(edge .. "LEFT", prev, edge .. "RIGHT", 1, 0)
                end
            else
                local o = INSET[corner]
                region:SetPoint(corner, button, corner, o[1], o[2])
            end
            last[corner] = region
        end
    end
end

-- The Standard look (Window.lua, THE TWO LOOKS): the client's own empty bag
-- slot as the ground, its quality ring instead of our edge, its square hover
-- light. Switched per slot only when the look changes, since the hover and
-- the ground keep what was set on them.
local EMPTY_SLOT = "Interface\\Paperdoll\\UI-Backpack-EmptySlot"
local HOVER = "Interface\\Buttons\\ButtonHilight-Square"

local function applyLook(slot, standard)
    if slot.look == standard then return end
    slot.look = standard
    local button = slot.button
    local hl = button.GetHighlightTexture and button:GetHighlightTexture()
    if standard then
        slot.ground:SetTexture(EMPTY_SLOT)
        slot.ground:SetTexCoord(0, 1, 0, 1)
        if hl then hl:SetTexture(HOVER); hl:SetBlendMode("ADD"); hl:SetVertexColor(1, 1, 1, 1) end
        for _, t in pairs(slot.edges) do t:Hide() end
    else
        slot.ground:SetColorTexture(1, 1, 1, 1)
        if hl then hl:SetColorTexture(1, 1, 1, 0.10); hl:SetBlendMode("BLEND") end
        if button.IconBorder then button.IconBorder:SetAlpha(0) end
    end
end

function Slots.Paint(slot, bagID, slotID, info)
    local db = Bags.db()
    local button, frame = slot.button, slot.frame
    local standard = db.style == "standard"

    frame:SetID(bagID)
    button:SetID(slotID)
    frame:SetSize(db.slotSize or 37, db.slotSize or 37)
    applyLook(slot, standard)
    -- "Rounded slots" holds in both looks
    applyRound(slot, db.roundSlots ~= false)

    button:Show()

    -- The icon, from whichever field this client's container info carries it
    -- in. If none of them has it, the item's own link is asked instead -- and
    -- the first time that happens the fields we DID get are printed, because
    -- guessing twice about the same table is how an empty bag stays empty.
    local icon = info and (info.iconFileID or info.icon or info.texture)
    if info and not icon then
        if info.hyperlink and C_Item.GetItemIconByID then
            icon = C_Item.GetItemIconByID(info.hyperlink)
        end
        if not reported.info then
            reported.info = true
            local keys = {}
            for k in pairs(info) do keys[#keys + 1] = tostring(k) end
            table.sort(keys)
            ns:Print(ns.L["The bag data has no icon field. What it does have: %s"], table.concat(keys, ", "))
        end
    end
    if not callSetter(button, "SetItemButtonTexture", icon) then
        -- Last resort: the icon region itself. Not as good as the setter --
        -- it knows about the slot's empty art and the overlays -- but an icon
        -- drawn by hand beats a bag full of nothing.
        local tex = button.icon or button.Icon
        if tex then tex:SetTexture(icon) end
    end

    -- The zoom: a crop of the icon's own texture coordinates, set AFTER the
    -- texture. No setter takes it, and SetItemButtonTexture resets the coords
    -- along with the texture -- cropping first left every icon uncropped.
    local zoom = math.max(0, math.min(0.2, db.iconZoom or 0))
    local iconTex = button.icon or button.Icon
    if iconTex then iconTex:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom) end

    callSetter(button, "SetItemButtonCount",
        (db.showCount ~= false and info) and (slot.mergedCount or info.stackCount) or 0)

    -- The stack count is the template's own font string, so it is restyled
    -- rather than replaced: replacing it would mean a second number drawn on
    -- top of the client's.
    local count = button.Count or button.count
    if count then
        ns.UI.FontFor("bags", count, db.countSize or 11, "OUTLINE")
    end

    -- The client's quality setter still runs: besides its ring it drives the
    -- profession-quality and other overlays, which know item types a guess
    -- would miss. Its ring itself stays at alpha zero (set once, in the skin);
    -- the colour goes on our own inside border instead.
    if info then
        callSetter(button, "SetItemButtonQuality", info.quality, info.hyperlink, false, false)
    else
        callSetter(button, "SetItemButtonQuality", nil)
    end
    if button.IconBorder then
        -- Standard keeps the client's ring, which its setter just placed.
        button.IconBorder:SetAlpha((standard and db.qualityBorder ~= false) and 1 or 0)
    end

    if standard then
        -- The client's slot art; a profession bag's slots tinted in its colour.
        local fam = db.markBagFamily ~= false and familyColor(bagID) or nil
        if fam then
            slot.ground:SetVertexColor(0.55 + fam[1] * 0.45, 0.55 + fam[2] * 0.45, 0.55 + fam[3] * 0.45, 1)
        else
            slot.ground:SetVertexColor(1, 1, 1, 1)
        end
        local q = info and info.quality
        local ringShown = info and db.qualityBorder ~= false and type(q) == "number" and q >= 2
        if slot.isRound then
            -- The client's ring is square and would sit around a round icon:
            -- our round ring instead, the quality first, else the bag's colour.
            if button.IconBorder then button.IconBorder:SetAlpha(0) end
            local r, g, b
            if ringShown and C_Item.GetItemQualityColor then
                local ok, qr, qg, qb = pcall(C_Item.GetItemQualityColor, q)
                if ok and type(qr) == "number" then r, g, b = qr, qg, qb end
            end
            if not r and fam then r, g, b = fam[1], fam[2], fam[3] end
            if r then
                layoutRing(slot, r, g, b, 0.95)
            else
                slot.roundRing:Hide()
            end
        else
            slot.roundRing:Hide()
            -- A profession bag's colour as an edge, as in Modern: the ground
            -- alone vanished under every icon. Not over the client's quality
            -- ring -- an uncommon or better item keeps that.
            if fam and not ringShown then
                layoutRing(slot, fam[1], fam[2], fam[3], 0.9)
            else
                for _, t in pairs(slot.edges) do t:Hide() end
            end
        end
    end

    -- Empty slots are a dark square with a faint edge; full ones sit on the
    -- same ground and carry their quality colour, or a neutral grey when the
    -- setting is off or the item is plain.
    -- A slot of a profession bag takes that bag's colour: tinted ground and
    -- edge while empty, the edge alone under an item the quality leaves plain.
    local fam = db.markBagFamily ~= false and familyColor(bagID) or nil
    if standard then
        -- painted above
    elseif info then
        slot.ground:SetVertexColor(0.02, 0.02, 0.03, 0.9)
        local r, g, b = 0.25, 0.25, 0.27
        if fam then r, g, b = fam[1], fam[2], fam[3] end
        local q = info.quality
        if db.qualityBorder ~= false and type(q) == "number" and q >= 2 and C_Item.GetItemQualityColor then
            local ok, qr, qg, qb = pcall(C_Item.GetItemQualityColor, q)
            if ok and type(qr) == "number" then r, g, b = qr, qg, qb end
        end
        layoutRing(slot, r, g, b, 1)
    elseif fam then
        slot.ground:SetVertexColor(fam[1] * 0.35, fam[2] * 0.35, fam[3] * 0.35, 0.7)
        layoutRing(slot, fam[1], fam[2], fam[3], 0.8)
    else
        slot.ground:SetVertexColor(0.08, 0.08, 0.09, 0.55)
        layoutRing(slot, 0, 0, 0, 0.45)
    end

    -- The C on vendor junk: the same test the sort uses to put it last.
    if db.markJunk ~= false and Bags.Sort.IsVendorJunk(info) then
        ns.UI.FontFor("bags", slot.junk, math.max(9, (db.countSize or 11)), "OUTLINE")
        slot.junk:SetTextColor(0.93, 0.64, 0.35)
        slot.junk:SetText("C")
        slot.junk:Show()
    else
        slot.junk:Hide()
    end

    -- The client's yellow "!" on an item that starts a quest, as its own
    -- bags show it. The template carries the texture; it is sized to the
    -- slot here because the template pins it at 37 by 38.
    local bang = button.IconQuestTexture
    if bang then
        local q = info and db.markQuestStarter ~= false
            and C_Container.GetContainerItemQuestInfo
            and C_Container.GetContainerItemQuestInfo(bagID, slotID)
        if q and q.questID and not q.isActive then
            bang:SetTexture(_G.TEXTURE_ITEM_QUEST_BANG or "Interface\\ContainerFrame\\UI-Icon-QuestBang")
            bang:ClearAllPoints()
            bang:SetAllPoints(button)
            bang:Show()
        else
            bang:Hide()
        end
    end

    -- Grey items go quiet so the rest of the bag can be read.
    local isJunk = info and ((type(info.quality) == "number" and info.quality == POOR)
        or (ns.Junk and ns.Junk.IsMarked(info.itemID)))
    callSetter(button, "SetItemButtonDesaturated", (db.dimJunk and isJunk) and true or false)

    -- The cooldown swirl, driven by the client's own numbers.
    local cd = button.Cooldown or button.cooldown
    if cd then
        local start, duration, enable = C_Container.GetContainerItemCooldown(bagID, slotID)
        if type(start) == "number" and type(duration) == "number" then
            pcall(cd.SetCooldown, cd, start, duration)
            cd:SetShown((enable or 0) ~= 0 and duration > 0)
        else
            pcall(cd.Clear, cd)
        end
    end

    -- The item level, on gear only.
    if db.showItemLevel and info and Bags.Categories.IsGear(info) then
        local level
        local loc = ns.BagSlotLocation(bagID, slotID)
        if C_Item.GetCurrentItemLevel then
            local ok, value = pcall(C_Item.GetCurrentItemLevel, loc)
            if ok and type(value) == "number" then level = value end
        end
        if level then
            ns.UI.FontFor("bags", slot.level, db.itemLevelSize or 11, "OUTLINE")
            slot.level:SetTextColor(db.itemLevelColor.r, db.itemLevelColor.g, db.itemLevelColor.b)
            slot.level:SetText(tostring(level))
            slot.level:Show()
        else
            slot.level:Hide()
        end
    else
        slot.level:Hide()
    end

    -- The bind tag. Two letters in a corner rather than the client's own
    -- sentence, which is a tooltip line and would not fit on an icon.
    local tag = db.showBindTags and info and Bags.Items.BindTag(info) or nil
    if tag then
        ns.UI.FontFor("bags", slot.tag, db.bindTagSize or 10, "OUTLINE")
        local c = (tag == "BoE") and db.bindTagColor or db.warboundColor
        slot.tag:SetTextColor(c.r, c.g, c.b)
        slot.tag:SetText(tag)
        slot.tag:Show()
    else
        slot.tag:Hide()
    end

    -- The name of the equipment set a piece of gear belongs to, shortened to
    -- its first few letters: a corner of a 37 px icon has room for about
    -- three, and the full name is in the tooltip anyway.
    local setName = db.showSetNames and info and Bags.Items.SetName(bagID, slotID) or nil
    if setName then
        ns.UI.FontFor("bags", slot.setName, db.setNameSize or 10, "OUTLINE")
        slot.setName:SetTextColor(db.setNameColor.r, db.setNameColor.g, db.setNameColor.b)
        slot.setName:SetText(firstLetters(setName, db.setNameLetters or 3))
        slot.setName:Show()
    else
        slot.setName:Hide()
    end

    -- Pinned and just-picked-up. Both are ours, both come from Marks, and
    -- neither asks the item anything.
    local id = info and info.itemID
    slot.pin:SetShown(db.showPinned and Bags.Marks.IsPinned(id) or false)
    slot.upgrade:SetShown(db.showUpgrades and info and Bags.Categories.IsGear(info)
        and Bags.Items.IsUpgrade(bagID, slotID, info) or false)
    placeCorners(slot, button, db)
    if db.showRecent and Bags.Marks.IsRecent(bagID, slotID) then
        local c = db.recentColor
        if slot.isRound then
            ns.LayoutEdges(slot.freshEdges, button, 0, 1, 1, 1, 1)
            slot.roundFresh:SetVertexColor(c.r, c.g, c.b, 1)
            slot.roundFresh:Show()
        else
            ns.LayoutEdges(slot.freshEdges, button, 2, c.r, c.g, c.b, 1, 0)
            slot.roundFresh:Hide()
        end
    else
        ns.LayoutEdges(slot.freshEdges, button, 0, 1, 1, 1, 1)
        slot.roundFresh:Hide()
    end

    -- A locked item -- one that is on the cursor or being moved -- is drawn
    -- faded, the way the client draws it in its own bags.
    -- An empty profession-bag slot tints the client's empty-slot art as well.
    local locked = info and info.isLocked
    local shade = locked and 0.5 or 1
    local sr, sg, sb = shade, shade, shade
    if fam and not info then
        sr, sg, sb = 0.35 + 0.65 * fam[1], 0.35 + 0.65 * fam[2], 0.35 + 0.65 * fam[3]
    end
    if type(button.SetItemButtonTextureVertexColor) == "function" then
        pcall(button.SetItemButtonTextureVertexColor, button, sr, sg, sb)
    else
        local tex = button.icon or button.Icon
        if tex then tex:SetVertexColor(sr, sg, sb) end
    end

    frame:Show()
end

-- A slot the search has filtered out: still there, still clickable, just faded
-- so the eye goes to what was searched for.
function Slots.SetFiltered(slot, filtered)
    slot.frame:SetAlpha(filtered and 0.25 or 1)
end

-- ---------------------------------------------------------------- tools --
--
-- Pinning an item and splitting a stack both need a CLICK on a slot, and the
-- slot's own click belongs to the client: it uses, equips or picks up the
-- item, and nothing of ours may take that away. So a tool is a MODE. While one
-- is on, every slot wears a plain button of its own over the top, the mode's
-- click lands on that, and switching the mode off takes it away again.
--
-- The alternative -- a modifier on the secure click -- was rejected on
-- purpose: a hook cannot cancel the secure action underneath, so alt-right
-- clicking a flask to pin it would have drunk the flask.

local mode = nil

function Slots.Mode() return mode end

function Slots.SetMode(new)
    -- An if, not "(mode == new) and nil or new": an and/or with nil in the
    -- middle always falls through to the right-hand side, so the second click
    -- on a tool switched its mode on again instead of off.
    if mode == new then mode = nil else mode = new end
    Bags.Refresh()
    return mode
end

local function pinClick(overlay)
    Bags.Marks.TogglePin(overlay.itemID)
end

-- The client's own splitter, driven the way the client drives it: it asks the
-- OWNER frame for SplitStack when the player confirms, so the overlay carries
-- that method. No secure call is involved -- moving part of a stack inside the
-- bags is an ordinary container call.
local function splitClick(overlay)
    local frame = _G.StackSplitFrame
    local open = frame and frame.OpenStackSplitFrame
    if type(open) ~= "function" or (overlay.stack or 1) < 2 then return end
    pcall(open, frame, overlay.stack, overlay, "BOTTOMLEFT", "TOPLEFT")
end

-- Everything the mode needs about this slot, refreshed on every paint: the
-- overlay is pooled with the slot and may have been over a different item a
-- moment ago.
function Slots.ApplyMode(slot, bagID, slotID, info)
    local overlay = slot.overlay
    if not mode or not info then overlay:Hide(); return end

    overlay.bagID, overlay.slotID = bagID, slotID
    overlay.itemID = info.itemID
    overlay.stack = tonumber(info.stackCount) or 1
    overlay.SplitStack = function(self, amount)
        if type(amount) == "number" and amount > 0 then
            pcall(C_Container.SplitContainerItem, self.bagID, self.slotID, amount)
        end
    end

    if mode == "pin" then
        overlay.wash:SetColorTexture(0.9, 0.7, 0.2, 0.25)
        overlay:SetScript("OnClick", pinClick)
    else
        overlay.wash:SetColorTexture(0.2, 0.6, 0.9, 0.25)
        overlay:SetScript("OnClick", splitClick)
    end
    overlay:Show()
end
