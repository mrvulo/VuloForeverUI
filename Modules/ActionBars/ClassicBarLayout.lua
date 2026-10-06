-- VuloForeverUI / Modules / ActionBars / ClassicBarLayout: the client's bars, page arrows, bags, micro menu and experience bar laid on the band
local _, ns = ...
local AB = ns.AB
local Classic = AB.ClassicBar
local P = AB._classic

local ART_W, BAND_H, STRIP_H, BUTTON_PITCH, BAND_SCALE = P.ART_W, P.BAND_H, P.STRIP_H, P.BUTTON_PITCH, P.BAND_SCALE
local BUTTON_SIZE, ROW_X, ROW_Y, PAGE_X, PAGE_UP_Y = P.BUTTON_SIZE, P.ROW_X, P.ROW_Y, P.PAGE_X, P.PAGE_UP_Y
local PAGE_DOWN_Y, UPPER_Y, UPPER_BARS, SMALL_Y, SMALL_X = P.PAGE_DOWN_Y, P.UPPER_Y, P.UPPER_BARS, P.SMALL_Y, P.SMALL_X
local SMALL_BUTTON, SMALL_PITCH, SIDE_TOP_MIN, SIDE_TOP_SHARE, SIDE_RIGHT = P.SMALL_BUTTON, P.SMALL_PITCH, P.SIDE_TOP_MIN, P.SIDE_TOP_SHARE, P.SIDE_RIGHT
local SIDE_COLUMN, EXTRA_Y, EXTRA_BARS, HOLDER, SIDE_BARS = P.SIDE_COLUMN, P.EXTRA_Y, P.EXTRA_BARS, P.HOLDER, P.SIDE_BARS
local MICRO_X, MICRO_Y, MICRO_W, MICRO_STEP, MICRO_ROOM = P.MICRO_X, P.MICRO_Y, P.MICRO_W, P.MICRO_STEP, P.MICRO_ROOM
local MICRO_SKIP, BAG_SIZE, BAG_PITCH, BAG_BOTTOM, BAG_RIGHT = P.MICRO_SKIP, P.BAG_SIZE, P.BAG_PITCH, P.BAG_BOTTOM, P.BAG_RIGHT
local KEYRING_W, KEYRING_GAP, REAGENT_SIZE, original, remember = P.KEYRING_W, P.KEYRING_GAP, P.REAGENT_SIZE, P.original, P.remember
local restoreFrame, ratio, placed, anchor, Row = P.restoreFrame, P.ratio, P.placed, P.anchor, P.Row
local matchScale, ROW_KEY, placeRow = P.matchScale, P.ROW_KEY, P.placeRow

-- THE BUTTONS ARE NOT WHAT MOVES.
--
-- Each of the client's action buttons sits in a CONTAINER frame, and the
-- client's own layout positions those containers -- which is why anchoring the
-- buttons themselves achieved nothing that survived the next layout pass, and
-- why the row came out at the client's spacing rather than ours.
--
-- So the container is what is moved and what carries the size: scaled so its
-- 45 pixel button comes out at the 36 the art was drawn for. The step between
-- them is then read IN THE CONTAINER'S OWN SPACE, which is why the pitch is
-- divided by that same scale before it is used.
-- Every bar laid on a row of ours, with that row's number, for the watch.
local laid = setmetatable({}, { __mode = "k" })

local function layoutBarButtons(bar, rowIndex, x, y, pitch, target)
    if not (bar and bar.actionButtons) then return 0 end
    laid[bar] = rowIndex

    local first = bar.actionButtons[1]
    local size = (first and first:GetWidth()) or 45
    if not size or size == 0 then size = 45 end
    -- Both measured against the band: the container's parent does not wear
    -- the band's scale, so band pixels are converted through the two.
    local first_container = first and first.container
    local parent = first_container and first_container:GetParent()
    local k = P.art:GetEffectiveScale() / ((parent and parent:GetEffectiveScale()) or 1)
    local scale = (target or BUTTON_SIZE) * k / size
    if scale <= 0 then scale = 1 end
    local step = (pitch or BUTTON_PITCH) * k / scale

    -- The bar frame keeps the plain scale: the client puts the icon size on
    -- the buttons and leaves the frame alone, and the frame is what Edit Mode
    -- draws its box around -- scaling it too would count the size twice.
    matchScale(bar, 1)

    local row = Row(rowIndex)
    row:SetScale(1)
    local shown = 0
    for _, button in ipairs(bar.actionButtons) do
        if button.container then shown = shown + 1 end
    end
    row:SetSize(math.max(1, (shown - 1) * (pitch or BUTTON_PITCH) + (target or BUTTON_SIZE)),
        target or BUTTON_SIZE)
    placeRow(row, ROW_KEY[bar:GetName() or ""], "BOTTOMLEFT", P.art, "BOTTOMLEFT", x, y)

    local count = 0
    for i, button in ipairs(bar.actionButtons) do
        local container = button.container
        if container then
            count = i
            remember(container)
            pcall(function()
                container:SetScale(scale)
                container:ClearAllPoints()
                container:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", (i - 1) * step, 0)
            end)
        end
    end

    -- The bar's own rectangle becomes exactly the buttons it shows, so Edit
    -- Mode's box sits on them instead of around where they used to be.
    if count > 0 then
        local slot = target or BUTTON_SIZE
        local along = (count - 1) * (pitch or BUTTON_PITCH) + slot
        if math.abs((bar:GetWidth() or 0) - along) > 0.5 or math.abs((bar:GetHeight() or 0) - slot) > 0.5 then
            remember(bar)
            local fs = ratio(bar)
            pcall(bar.SetSize, bar, along / fs, slot / fs)
        end
        -- And it stands where they stand. The bars above are chained to THIS
        -- frame, not to its buttons, so a frame left at the client's place
        -- pulls bars 2 and 3 and the stance bar off to one side of the row.
        remember(bar)
        pcall(function()
            bar:ClearAllPoints()
            bar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
        end)
    end
    return count
end

-- One of the right-hand columns: the same containers, stepped DOWN from a row
-- frame hung off the screen's bottom right corner instead of the band.
local function layoutColumn(bar, rowIndex, right, top, pitch, target)
    if not (bar and bar.actionButtons) then return 0 end
    laid[bar] = rowIndex

    local first = bar.actionButtons[1]
    local size = (first and first:GetWidth()) or 45
    if not size or size == 0 then size = 45 end
    local container1 = first and first.container
    local parent = container1 and container1:GetParent()
    local k = P.art:GetEffectiveScale() / ((parent and parent:GetEffectiveScale()) or 1)
    local scale = target * k / size
    if scale <= 0 then scale = 1 end
    local step = pitch * k / scale

    matchScale(bar, 1)
    local row = Row(rowIndex)
    row:SetScale(1)
    row:SetSize(target, 11 * pitch + target)
    placeRow(row, ROW_KEY[bar:GetName() or ""], "TOPRIGHT", UIParent, "BOTTOMRIGHT", right, top)

    local count = 0
    for i, button in ipairs(bar.actionButtons) do
        local container = button.container
        if container then
            count = i
            remember(container)
            pcall(function()
                container:SetScale(scale)
                container:ClearAllPoints()
                container:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, -(i - 1) * step)
            end)
        end
    end
    if count > 0 then
        remember(bar)
        local fs = ratio(bar)
        pcall(function()
            bar:SetSize(target / fs, ((count - 1) * pitch + target) / fs)
            bar:ClearAllPoints()
            bar:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)
        end)
    end
    return count
end

-- The shaman's totem bar, when it is asked for: on the small row after
-- whichever of the stance, possess and pet bars show, and moved whole -- its
-- slot, page and summon buttons are anchored to each other inside it, so the
-- frame is what goes onto the row. Off, it is handed back to the client's
-- place, and the watch is told to stop looking after it.
local totemHooked = false

-- How far the rows over the band are lifted, all of them together so they
-- never close up on each other: bars 2 and 3, the small row above them, and
-- the extra bars on top. Room for the experience strip's texts under them.
local function lift()
    local v = AB.db().upperLift
    return type(v) == "number" and v or 0
end

local function layoutTotem(x)
    local totem = _G.MultiCastActionBarFrame
    if not totem then return end
    local _, class = UnitClass("player")
    local want = AB.db().classicTotemBar and class == "SHAMAN"
    -- The bar shows only once the client counts the totem slots, which is
    -- after the band's first pass: when it comes up unplaced, the band is
    -- laid again (after the fight, if one is on).
    if want and not totemHooked and totem.UpdateShownState then
        totemHooked = true
        hooksecurefunc(totem, "UpdateShownState", function(self)
            if not (P.applied and AB.mod.active and AB.db().classicTotemBar) then return end
            if self:IsShown() and not placed[self] then
                -- a frame later: not from inside the client's own update
                ns.NextFrame(function()
                    ns:RunOutOfCombatOnce("actionbars.totem", function()
                        if P.applied then Classic.Apply() end
                    end)
                end)
            end
        end)
    end
    if want and totem:IsShown() then
        local row = Row(HOLDER.totem)
        row:SetScale(1)
        local fs = ratio(totem)
        local w, h = totem:GetSize()
        row:SetSize(math.max(1, (w or 1) * fs), math.max(1, (h or 1) * fs))
        placeRow(row, "totem", "BOTTOMLEFT", P.art, "BOTTOMLEFT", x, SMALL_Y + lift())
        anchor(totem, "BOTTOMLEFT", "BOTTOMLEFT", 0, 0, nil, nil, row)
    elseif not want and placed[totem] then
        restoreFrame(totem)
        placed[totem], original[totem] = nil, nil
    end
end

local function layoutButtons()
    -- The main bar first; its twelve buttons are the row the band was drawn
    -- around. A client that keeps its buttons somewhere other than
    -- bar.actionButtons falls back to the flat list, which at least places
    -- them even if their containers are not where we expect.
    local bar = _G.MainActionBar
    if bar and bar.actionButtons then
        layoutBarButtons(bar, 1, ROW_X, ROW_Y, BUTTON_PITCH, BUTTON_SIZE)
        for _, upper in ipairs(UPPER_BARS) do
            local ub = _G[upper.name]
            if ub and ub:IsShown() then
                layoutBarButtons(ub, upper.row, upper.x, UPPER_Y + lift(), BUTTON_PITCH, BUTTON_SIZE)
            end
        end
        -- Stance or possess first, the pet bar after whichever of them shows.
        local x = SMALL_X
        for i, name in ipairs({ "StanceBar", "PossessActionBar", "PetActionBar" }) do
            local sb = _G[name]
            if sb and sb:IsShown() then
                if name == "PetActionBar" then x = math.max(36, x) end
                local n = layoutBarButtons(sb, 3 + i, x, SMALL_Y + lift(), SMALL_PITCH, SMALL_BUTTON)
                if n > 0 then x = x + n * SMALL_PITCH + 6 end
            end
        end
        layoutTotem(x)
        -- Bar 4 outermost; bar 5 takes the outer column when bar 4 is off.
        local right = SIDE_RIGHT
        local screenH = (UIParent:GetHeight() or 768) / (P.art:GetScale() or BAND_SCALE)
        local top = math.max(SIDE_TOP_MIN, math.min(screenH - 40, screenH * SIDE_TOP_SHARE))
        for _, side in ipairs(SIDE_BARS) do
            local sb = _G[side.name]
            if sb and sb:IsShown() then
                layoutColumn(sb, side.row, right, top, BUTTON_PITCH, BUTTON_SIZE)
                right = right - SIDE_COLUMN
            end
        end
        local y = EXTRA_Y + lift()
        for _, extra in ipairs(EXTRA_BARS) do
            local eb = _G[extra.name]
            if eb and eb:IsShown() then
                layoutBarButtons(eb, extra.row, ROW_X, y, BUTTON_PITCH, BUTTON_SIZE)
                y = y + BUTTON_PITCH
            end
        end
        return
    end
    for i = 1, 12 do
        local b = _G["ActionButton" .. i]
        if b then
            anchor(b, "BOTTOMLEFT", "BOTTOMLEFT",
                ROW_X + (i - 1) * BUTTON_PITCH, ROW_Y, BUTTON_SIZE, BUTTON_SIZE)
        end
    end
end

-- The page number and its two arrows, on the band's corner past the twelfth
-- button, at the 32 pixels 1.x drew them; the art is set in dress().
P.pageWasShown = nil

local function layoutPageArrows()
    local bar = _G.MainActionBar
    local pn = bar and bar.ActionBarPageNumber
    if not pn then return end
    local midY = (PAGE_UP_Y + PAGE_DOWN_Y) / 2
    local holder = Row(HOLDER.page)
    holder:SetScale(1)
    holder:SetSize(48, 76)
    placeRow(holder, "page", "CENTER", P.art, "TOPLEFT", PAGE_X + 8, midY)

    anchor(pn, "CENTER", "CENTER", -8, 0, 32, 76, holder)
    -- Shown by us, so hidden again by us if the client had it hidden.
    if P.pageWasShown == nil then P.pageWasShown = pn:IsShown() end
    pcall(pn.Show, pn)
    for _, entry in ipairs({ { pn.UpButton, PAGE_UP_Y }, { pn.DownButton, PAGE_DOWN_Y } }) do
        local button, y = entry[1], entry[2]
        if button then
            anchor(button, "CENTER", "CENTER", -8, y - midY, 32, 32, holder)
            pcall(button.SetHitRectInsets, button, 6, 6, 7, 7)
        end
    end
    if pn.Text then
        local fs = ratio(pn)
        remember(pn.Text)
        pcall(function()
            pn.Text:ClearAllPoints()
            pn.Text:SetPoint("CENTER", holder, "CENTER", 12 / fs, 0.5 / fs)
        end)
    end
end

-- THE MICRO MENU AND THE BAGS ARE SCALED, NOT SIZED.
--
-- This client's micro and bag buttons carry their art on child textures sized
-- to the 45 pixel button. SetSize shrinks the button and leaves that art at
-- full size, which is the pile of overlapping gold frames the first version
-- of this band showed. SetScale takes the art along. The anchor offsets stay
-- in band pixels because anchor() divides by the ratio, scale included.
local function fitTo(frame, width)
    local w = frame:GetWidth()
    if not w or w <= 0 then return 1 end
    -- Measured in band pixels, so a second pass over a frame already at the
    -- right size asks for the scale it already has.
    local scale = (frame:GetScale() or 1) * width / (w * ratio(frame))
    matchScale(frame, scale)
    return (frame:GetHeight() or 0) * width / w
end

-- The bags, chained right to left from the backpack, on their own holder.
-- Measured first -- the holder is as wide as the chain -- then placed from the
-- holder's right edge. Answers the band x where the chain begins.
-- bagsLaying: our own SetPoints on the bag buttons, which hookBags must not
-- answer.
local bagsLaying = false

local function layoutBags()
    local seats = {}
    local right, lastLeft = BAG_RIGHT, BAG_RIGHT
    local function seat(b, width, bottom)
        if not (b and b:IsShown()) then return false end
        local h = fitTo(b, width)
        seats[#seats + 1] = { b, right, bottom or ((BAND_H - h) / 2) }
        lastLeft = right - width
        return true
    end
    if seat(_G.MainMenuBarBackpackButton, BAG_SIZE, BAG_BOTTOM) then
        right = lastLeft + (BAG_SIZE - BAG_PITCH)
    end
    for n = 0, 3 do
        if seat(_G["CharacterBag" .. n .. "Slot"], BAG_SIZE, BAG_BOTTOM) then
            right = lastLeft + (BAG_SIZE - BAG_PITCH)
        end
    end
    right = lastLeft - 2
    seat(_G.CharacterReagentBag0Slot, REAGENT_SIZE, BAG_BOTTOM + (BAG_SIZE - REAGENT_SIZE) / 2)
    right = lastLeft - KEYRING_GAP
    seat(_G.KeyRingButton, KEYRING_W)

    local holder = Row(HOLDER.bags)
    holder:SetScale(1)
    holder:SetSize(math.max(1, BAG_RIGHT - lastLeft), BAND_H)
    placeRow(holder, "bags", "BOTTOMRIGHT", P.art, "BOTTOMLEFT", BAG_RIGHT, 0)
    bagsLaying = true
    for _, s in ipairs(seats) do
        anchor(s[1], "BOTTOMRIGHT", "BOTTOMRIGHT", s[2] - BAG_RIGHT, s[3], nil, nil, holder)
    end
    bagsLaying = false
    return lastLeft
end

-- The micro menu: every button the client shows but the shop, in the
-- client's own order, 28 wide at a step of 25 -- the row shrunk as a whole
-- when there are more than its room holds.
local skipped = setmetatable({}, { __mode = "k" })

local function layoutMicro(stopAt)
    local menu = _G.MicroMenu
    if not menu then return end
    local buttons = {}
    for _, child in ipairs({ menu:GetChildren() }) do
        if child:GetObjectType() == "Button" then
            local name = child:GetName()
            if name and MICRO_SKIP[name] then
                skipped[child] = true
                pcall(child.SetAlpha, child, 0)
                pcall(child.EnableMouse, child, false)
            elseif child:IsShown() then
                buttons[#buttons + 1] = child
            end
        end
    end
    if #buttons == 0 then return end
    table.sort(buttons, function(a, b)
        local la, lb = a.layoutIndex, b.layoutIndex
        if type(la) == "number" and type(lb) == "number" then return la < lb end
        return (a:GetLeft() or 0) < (b:GetLeft() or 0)
    end)

    -- The row runs up to the bags: fewer buttons than the room was drawn for
    -- grow a little (never past a fifth) instead of leaving a gap.
    local room = math.min(MICRO_ROOM, (stopAt or ART_W) - 3 - MICRO_X)
    local rs = math.min(1.2, room / (#buttons * MICRO_STEP + 3))
    local holder = Row(HOLDER.micro)
    holder:SetScale(1)
    holder:SetSize(math.max(1, (#buttons * MICRO_STEP + 3) * rs), BAND_H)
    placeRow(holder, "micro", "BOTTOMLEFT", P.art, "BOTTOMLEFT", MICRO_X, 0)
    for i, b in ipairs(buttons) do
        fitTo(b, MICRO_W * rs)
        anchor(b, "BOTTOMLEFT", "BOTTOMLEFT", (i - 1) * MICRO_STEP * rs, MICRO_Y, nil, nil, holder)
    end
end

local function unskipMicro()
    for b in pairs(skipped) do
        pcall(b.SetAlpha, b, 1)
        pcall(b.EnableMouse, b, true)
        skipped[b] = nil
    end
end

-- The experience bar along the band's top edge, where 1.x kept it.
local XP_CONTAINERS = { "MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer" }
local xpBusy = false

local function placeExperience()
    local holder = Row(HOLDER.xp)
    holder:SetScale(1)
    holder:SetSize(ART_W - 4, STRIP_H)
    placeRow(holder, "xp", "BOTTOM", P.art, "TOP", 0, -STRIP_H - 1)
end

local function layoutExperience()
    if xpBusy then return end
    xpBusy = true
    for _, name in ipairs(XP_CONTAINERS) do
        local container = _G[name]
        if container then
            -- The client sizes its bars to their CONTAINER in its own
            -- ResizeContainerBars; so the container gets the band's width,
            -- at the band's scale, and the client's own call fills it.
            matchScale(container, (container:GetScale() or 1) / ratio(container))
            anchor(container, "BOTTOM", "BOTTOM", 0, 0, nil, nil, Row(HOLDER.xp))
            pcall(container.SetWidth, container, (ART_W - 4) / ratio(container))
            if type(container.ResizeContainerBars) == "function" then
                pcall(container.ResizeContainerBars, container)
            end
            if not InCombatLockdown() and type(container.UpdateDividers) == "function"
                and type(container.GetExpectedSegments) == "function" then
                pcall(container.UpdateDividers, container, container:GetExpectedSegments())
            end
        end
    end
    xpBusy = false
end

local function restoreExperience()
    for _, name in ipairs(XP_CONTAINERS) do
        local container = _G[name]
        if container and type(container.GetExpectedWidth) == "function" then
            pcall(container.SetWidth, container, container:GetExpectedWidth())
            if type(container.ResizeContainerBars) == "function" then
                pcall(container.ResizeContainerBars, container)
            end
        end
    end
end

-- The client lays these bars out again on its own events -- a new target, a
-- panel opened from the micro menu, a reputation change -- and every one of
-- those puts them back at its own width and place. Its layout calls are
-- followed, not replaced: right after each, the band lays them again. These
-- bars are not protected, so this also works in a fight.
local xpHooked = false

local function hookExperience()
    if xpHooked then return end
    xpHooked = true
    local function again()
        if P.applied then layoutExperience() end
    end
    local manager = _G.StatusTrackingBarManager
    if manager then
        for _, method in ipairs({ "UpdateBarsShown", "CheckForLayoutChange" }) do
            if type(manager[method]) == "function" then hooksecurefunc(manager, method, again) end
        end
    end
    for _, name in ipairs(XP_CONTAINERS) do
        local container = _G[name]
        if container then
            for _, method in ipairs({ "ApplySystemAnchor", "UpdateShownState", "SetShownBar" }) do
                if type(container[method]) == "function" then hooksecurefunc(container, method, again) end
            end
        end
    end
    -- The bars are managed frames: whenever ANY frame in the bottom managed
    -- container shows or hides -- a target, a panel -- the client lays every
    -- one of them out again. Following that Layout is what stops the flicker.
    local managed = _G.BottomManagedFrameContainer
    for _, frame in ipairs({ managed, managed and managed.BottomManagedLayoutContainer }) do
        if frame and type(frame.Layout) == "function" then hooksecurefunc(frame, "Layout", again) end
    end
end

-- The bags on the band hold still.
--
-- The client folds its bag bar away and out again on its own: an item on the
-- cursor unfolds it, putting the item down folds it (MainMenuBarBagManager's
-- OnCursorChanged -> SetExpandBarAuto). Folding HIDES the four bag slots
-- (SetBarExpanded), and every fold ends in BagsBar:Layout, which anchors the
-- buttons back into the client's own row. A bag sort moves every item through
-- the cursor, so the bags jumped between the band and the client's row on
-- every single move. On the band the slots stay shown, and after each of the
-- client's layout passes the band lays bags and micro menu again. The bag
-- buttons are plain buttons, so this also works in a fight.
--
-- Hooking BagsBar.Layout alone is not enough: the bar registers that Layout
-- as a callback on MainMenuBarManager.OnExpandChanged when it loads, so the
-- fold on every pickup and drop calls the ORIGINAL function and never reaches
-- a hook on the field. What every path has in common is the SetPoint on the
-- buttons, so that is where the band answers -- inside the client's own call,
-- before anything is drawn.
local bagsHooked = false
local BAG_BUTTONS = {
    "MainMenuBarBackpackButton", "CharacterBag0Slot", "CharacterBag1Slot",
    "CharacterBag2Slot", "CharacterBag3Slot", "CharacterReagentBag0Slot",
    "KeyRingButton",
}

local function hookBags()
    if bagsHooked then return end
    bagsHooked = true
    local function again()
        if P.applied and not bagsLaying then layoutMicro(layoutBags()) end
    end
    local bar = _G.BagsBar
    if bar and type(bar.Layout) == "function" then hooksecurefunc(bar, "Layout", again) end
    for _, name in ipairs(BAG_BUTTONS) do
        local b = _G[name]
        if b then hooksecurefunc(b, "SetPoint", again) end
    end
    for n = 0, 3 do
        local b = _G["CharacterBag" .. n .. "Slot"]
        if b and type(b.SetBarExpanded) == "function" then
            hooksecurefunc(b, "SetBarExpanded", function(self)
                if P.applied and not self:IsShown() then pcall(self.Show, self) end
            end)
        end
    end
end

-- The client's own modern bar art, out of the way.
--
-- Its REGIONS are walked rather than named: the parentKeys of that art differ
-- between builds, and a list of names is a list that is wrong on the build it
-- was not written for. A frame's own textures are safe to fade -- the buttons
-- are children, not regions, so nothing that answers a click is touched.
local function hideModernArt(hide)
    for _, name in ipairs({ "MainActionBar", "StatusTrackingBarManager", "BagsBar", "MicroMenu" }) do
        local frame = _G[name]
        if frame and frame.GetRegions then
            for _, region in ipairs({ frame:GetRegions() }) do
                if region.GetObjectType and region:GetObjectType() == "Texture" then
                    pcall(region.SetAlpha, region, hide and 0 or 1)
                end
            end
        end
    end
    -- The client's gryphons are not regions of the bar but a child FRAME of
    -- it, so the walk above never reaches them. Alpha rather than Hide: the
    -- client shows them again itself on every Edit Mode exit, and an alpha
    -- survives that where a Hide does not.
    local bar = _G.MainActionBar
    local caps = bar and bar.EndCaps
    if caps then pcall(caps.SetAlpha, caps, hide and 0 or 1) end
end

-- What the band's other files take from here.
P.laid = laid
P.layoutButtons, P.layoutPageArrows, P.layoutBags, P.layoutMicro = layoutButtons, layoutPageArrows, layoutBags, layoutMicro
P.unskipMicro, P.XP_CONTAINERS, P.placeExperience, P.layoutExperience = unskipMicro, XP_CONTAINERS, placeExperience, layoutExperience
P.restoreExperience, P.hookExperience, P.hookBags, P.hideModernArt = restoreExperience, hookExperience, hookBags, hideModernArt
