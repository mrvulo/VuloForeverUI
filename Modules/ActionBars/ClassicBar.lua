-- VuloForeverUI / Modules / ActionBars / ClassicBar
--
-- The 1.x main bar: a 1024 x 53 stone band across the bottom of the screen
-- with a gryphon on each end, and the client's own buttons put back in their
-- 2004 places on it -- the twelve action buttons, the page arrows, the micro
-- menu, the bags, and the experience bar along the band's top edge.
--
-- WHAT IS OURS AND WHAT IS NOT
--
-- The band and the gryphons are ours: plain textures on a frame of our own.
-- Everything standing ON them stays the client's -- its buttons, its clicks,
-- its keybinds. We only ever RE-ANCHOR them, never reparent them and never
-- touch a field on them, because an action button is a secure button and the
-- click that casts the spell is the thing at risk.
--
-- Two consequences run through the whole file:
--   * anchoring a protected frame is refused while a fight is on, so every
--     pass bails out in combat and is repeated when the fight ends
--   * the client's own Edit Mode moves the same frames. While it is open the
--     band hands everything back, or the two would fight over every anchor.
--
-- THE MEASUREMENTS
--
-- These are the 1.x numbers, and they are only correct together: the art was
-- drawn around 36 pixel buttons at a 42 pixel pitch, so a band scaled one way
-- and buttons scaled another lands the sockets between the buttons.
local _, ns = ...
local L = ns.L
local AB = ns.AB

local Classic = {}
AB.ClassicBar = Classic

local ART_W, ART_H = 1024, 53
local BAND_H, STRIP_H = 43, 10
local CAP_SIZE = 128
local BUTTON_PITCH = 42
-- The band at its 1.x size, the buttons at the 36 its sockets were drawn for.
local BAND_SCALE = 1
local BUTTON_SIZE = 36
local ROW_X, ROW_Y = 8, 4                   -- first button from the band's corner
local PAGE_X, PAGE_UP_Y, PAGE_DOWN_Y = 522, -22, -42
-- Bars 2 and 3 on one row over the band, bar 3 starting where bar 1's twelve
-- sockets end; the stance, pet and possess bars one row higher, indented.
local UPPER_Y = 59
local UPPER_BARS = {
    { name = "MultiBarBottomLeft",  row = 2, x = ROW_X },
    { name = "MultiBarBottomRight", row = 3, x = ROW_X + 12 * BUTTON_PITCH },
}
local SMALL_Y, SMALL_X, SMALL_BUTTON, SMALL_PITCH = 108, 30, 30, 33
-- Bars 4 and 5 as the right-hand columns: hung from the screen's right edge,
-- twelve 36 pixel buttons down at the same pitch; bar 4 on the outside, bar 5
-- one column in. Their top sits at a share of the screen's height, never
-- below the 1.x 602, so a small screen keeps the whole column on it.
local SIDE_TOP_MIN, SIDE_TOP_SHARE, SIDE_RIGHT, SIDE_COLUMN = 602, 0.68, -2, 42
-- Bars 6 to 8 never had a place in 1.x: when the client shows them, they
-- stack above the stance row, one row each, until they are moved.
local EXTRA_Y = 146
local EXTRA_BARS = {
    { name = "MultiBar5", row = 9 },
    { name = "MultiBar6", row = 10 },
    { name = "MultiBar7", row = 11 },
}
-- The band's own groups each stand on a holder of their own, so each can be
-- moved on its own: the micro menu, the bags, the experience bar, the page
-- arrows. A holder nobody moved stands exactly where the group always stood.
local HOLDER = { micro = 12, bags = 13, xp = 14, page = 15 }
local SIDE_BARS = {
    { name = "MultiBarRight", row = 7 },
    { name = "MultiBarLeft",  row = 8 },
}
-- The micro row: 28 wide buttons at a step of 25, shrunk as a row when the
-- client has more of them than the room holds. The shop never had a place.
local MICRO_X, MICRO_Y, MICRO_W, MICRO_STEP = 555, 2.5, 28, 25
local MICRO_ROOM = 300
local MICRO_SKIP = { StoreMicroButton = true }
-- The bags: 30 pixel slots overlapping by 2, the backpack's right edge four
-- pixels in from the band's end; past the last bag the small round reagent
-- slot, then the key ring as a tall post.
local BAG_SIZE, BAG_PITCH, BAG_BOTTOM, BAG_RIGHT = 30, 28, 6, 1020
local KEYRING_W, KEYRING_GAP, REAGENT_SIZE = 18, 5, 17

-- The band is four 256 wide slices of two classic sheets. The pairs are the
-- vertical crop of the band inside each sheet.
local TEX = {
    body    = "Interface\\MainMenuBar\\UI-MainMenuBar-Dwarf",
    keyring = "Interface\\MainMenuBar\\UI-MainMenuBar-KeyRing",
    cap     = "Interface\\MainMenuBar\\UI-MainMenuBar-EndCap-Dwarf",
}
local PIECES = {
    { x = 0,   file = "body",    v = { 0.83203125, 1.0 } },
    { x = 256, file = "body",    v = { 0.58203125, 0.75 } },
    { x = 512, file = "keyring", v = { 0.6640625, 1.0 } },
    { x = 768, file = "keyring", v = { 0.1640625, 0.5 } },
}

local art, applied = nil, false
local missingArt = false

-- Forward: the watch is written after the layout it calls, and Apply installs
-- it before that.
local watch

-- What a frame's anchors were before we moved it, kept OFF the frame.
local original = setmetatable({}, { __mode = "k" })

local function remember(frame)
    if original[frame] then return end
    local points = {}
    for i = 1, frame:GetNumPoints() do
        local point, rel, relPoint, x, y = frame:GetPoint(i)
        -- A point we cannot read is a point we cannot put back; the frame is
        -- then simply left out of the restore rather than guessed at.
        if not (ns.CanRead(point) and ns.CanRead(x) and ns.CanRead(y)) then
            points = nil
            break
        end
        points[i] = { point, rel, relPoint, x, y }
    end
    local w, h = frame:GetSize()
    original[frame] = {
        points = points,
        scale  = frame.GetScale and frame:GetScale() or nil,
        w = w, h = h,
    }
end

local function restoreFrame(frame)
    local o = original[frame]
    if not (frame and o) then return end
    if o.scale then pcall(frame.SetScale, frame, o.scale) end
    -- The size too: the bar frames are shrunk to the band's buttons, and the
    -- client's gryphons and border art hang off the main bar's edges.
    if o.w and o.h and o.w > 0 and o.h > 0 then pcall(frame.SetSize, frame, o.w, o.h) end
    if o.points and #o.points > 0 then
        pcall(function()
            frame:ClearAllPoints()
            for _, p in ipairs(o.points) do
                frame:SetPoint(p[1], p[2], p[3], p[4], p[5])
            end
        end)
    end
end

-- EVERY OFFSET IN THIS FILE IS IN BAND PIXELS, and this is where that is made
-- true. A SetPoint offset is read in the coordinate space of the frame being
-- moved, not of the frame it is anchored to -- so handing the client's button
-- a 42 pixel pitch while it sits at a different scale than the band stretches
-- or squeezes the whole row. The ratio between the two scales divides it back
-- out, and the same for any size we set.
local function ratio(frame)
    local fs = (frame:GetEffectiveScale() or 1) / ((art and art:GetEffectiveScale()) or 1)
    if not fs or fs <= 0 then return 1 end
    return fs
end

-- Every frame placed on the band, so the watch can see the client take one
-- back -- it re-lays the micro menu, the bags and the experience bar on its
-- own events (a new target is one), not only when the action bar changes.
local placed = setmetatable({}, { __mode = "k" })

-- Anchor one of the client's frames onto the band. SetPoint only: the frame
-- keeps its parent, and with it everything the client does to it.
local function anchor(frame, point, bandPoint, x, y, w, h, on)
    if not frame then return end
    on = on or art
    remember(frame)
    placed[frame] = on
    local fs = ratio(frame)
    pcall(function()
        frame:ClearAllPoints()
        frame:SetPoint(point, on, bandPoint, x / fs, y / fs)
        if w then frame:SetSize(w / fs, h / fs) end
    end)
end

-- ---------------------------------------------------------------- band --

local function build()
    if art then return art end
    art = CreateFrame("Frame", "VuloForeverUIClassicBar", UIParent)
    art:SetSize(ART_W, ART_H)
    art:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 0)
    art:SetFrameStrata("MEDIUM")
    art:SetFrameLevel(1)
    art:SetScale(BAND_SCALE)

    art.pieces = {}
    for i, piece in ipairs(PIECES) do
        local tex = art:CreateTexture(nil, "BACKGROUND")
        tex:SetSize(256, BAND_H)
        tex:SetPoint("BOTTOMLEFT", art, "BOTTOMLEFT", piece.x, 0)
        art.pieces[i] = tex
    end

    -- The gryphons are one sheet, drawn twice: the sheet is the LEFT one, and
    -- the right one is it with its horizontal coordinates swapped.
    art.leftCap = art:CreateTexture(nil, "OVERLAY", nil, 5)
    art.leftCap:SetSize(CAP_SIZE, CAP_SIZE)
    art.leftCap:SetPoint("BOTTOM", art, "BOTTOM", -544, 0)
    art.rightCap = art:CreateTexture(nil, "OVERLAY", nil, 5)
    art.rightCap:SetSize(CAP_SIZE, CAP_SIZE)
    art.rightCap:SetPoint("BOTTOM", art, "BOTTOM", 544, 0)
    return art
end

-- Paint the band, and say once if the client no longer ships the art.
local function paint()
    local ok = true
    for i, piece in ipairs(PIECES) do
        local tex = art.pieces[i]
        -- SetTexture answers false for a file that is not there, which is the
        -- only way to ask this question.
        if tex:SetTexture(TEX[piece.file]) == false then ok = false end
        tex:SetTexCoord(0, 1, piece.v[1], piece.v[2])
        tex:Show()
    end
    if art.leftCap:SetTexture(TEX.cap) == false then ok = false end
    art.leftCap:SetTexCoord(0, 1, 0, 1)
    art.rightCap:SetTexture(TEX.cap)
    art.rightCap:SetTexCoord(1, 0, 0, 1)

    if not ok and not missingArt then
        missingArt = true
        ns:Print(L["This client no longer ships the old main bar art, so the Classic bar has nothing to draw."])
    end
    return ok
end

-- ---------------------------------------------------------------- pieces --

-- A scaled child of the band, one per row of buttons. The row exists so the
-- offsets inside it can be written in 1.x pixels no matter what size the
-- buttons are wearing.
local function Row(index)
    art.rows = art.rows or {}
    local row = art.rows[index]
    if not row then
        row = CreateFrame("Frame", nil, art)
        row:SetSize(1, 1)
        art.rows[index] = row
    end
    return row
end

local function matchScale(frame, scale)
    if not (frame and frame.SetScale and frame.GetScale) then return end
    if math.abs((frame:GetScale() or 1) - scale) < 0.005 then return end
    remember(frame)
    pcall(frame.SetScale, frame, scale)
end

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

-- ---------------------------------------------------------------- movers --
--
-- Every bar stands on a row frame of ours, and the row is what our own edit
-- mode moves: the client's containers hang from it, so they follow. A row
-- nobody has moved stands where 1.x put it; a moved one stands at its saved
-- centre offset from the screen's centre, which is the mover's own model.
-- The band itself is moved the same way and carries bar 1, the page arrows,
-- the micro menu, the bags and the experience bar with it.
local ROW_KEY = {
    MultiBarBottomLeft = "bar2", MultiBarBottomRight = "bar3",
    MultiBarRight = "bar4", MultiBarLeft = "bar5",
    StanceBar = "stance", PossessActionBar = "possess", PetActionBar = "pet",
    MultiBar5 = "bar6", MultiBar6 = "bar7", MultiBar7 = "bar8",
}
local movers = {}

local function posDB(key)
    local d = AB.db()
    d.pos = d.pos or {}
    d.pos[key] = d.pos[key] or {}
    return d.pos[key]
end

local function moverLabel(key)
    local labels = {
        band   = L["Action bar 1 and the classic band"],
        bar2   = L["Action bar 2"],
        bar3   = L["Action bar 3"],
        bar4   = L["Action bar 4"],
        bar5   = L["Action bar 5"],
        bar6   = L["Action bar 6"],
        bar7   = L["Action bar 7"],
        bar8   = L["Action bar 8"],
        micro  = L["Micro menu"],
        bags   = L["Bags"],
        xp     = L["Experience bar"],
        page   = L["Page arrows"],
        stance = L["Stance bar"],
        possess = L["Possess bar"],
        pet    = L["Pet bar"],
    }
    return labels[key] or key
end

-- Where each row stood at its 1.x place on the last pass, as a centre
-- offset: the yardstick for "has this been moved".
local homeOf = {}

-- After any change the mover made -- a drop, a nudge, a reset, a discard --
-- the row counts as moved when it no longer stands at its 1.x place. A reset
-- always means "back home". Then the band lays everything again.
local function moverChanged(key)
    local db = posDB(key)
    local home = homeOf[key]
    if ns._inMoverReset then
        db.moved = nil
    elseif db.x and home then
        db.moved = (math.abs(db.x - home[1]) > 1 or math.abs((db.y or 0) - home[2]) > 1) or nil
    elseif db.x then
        db.moved = true
    end
    if applied then Classic.Apply() end
end

-- One mover per key, made once; its db follows the profile on every pass.
local function ensureMover(frame, key)
    local m = movers[key]
    if not m then
        m = ns:CreateMover(frame, {
            key      = "actionbars_" .. key,
            label    = moverLabel(key),
            db       = posDB(key),
            module   = "actionbars",
            applyPos = function() moverChanged(key) end,
            onMove   = function() moverChanged(key) end,
        })
        movers[key] = m
    end
    m.opts.db = posDB(key)
    return m
end

-- Put a row at its chosen place, or at its 1.x one. A row at home writes its
-- real centre offset back, so the mover's own model -- a centre offset -- is
-- true for it too, and a nudge moves it one pixel instead of to the middle.
local function placeRow(row, key, point, rel, relPoint, x, y)
    local db = key and posDB(key)
    row:ClearAllPoints()
    if db and db.moved and db.x then
        row:SetPoint("CENTER", UIParent, "CENTER", db.x, db.y or 0)
    else
        row:SetPoint(point, rel, relPoint, x, y)
        if db then
            local cx, cy = ns:GetCenterOffsets(row)
            if cx then
                db.x, db.y = cx, cy
                homeOf[key] = { cx, cy }
            end
        end
    end
    if key then ensureMover(row, key) end
end

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
    local k = art:GetEffectiveScale() / ((parent and parent:GetEffectiveScale()) or 1)
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
    placeRow(row, ROW_KEY[bar:GetName() or ""], "BOTTOMLEFT", art, "BOTTOMLEFT", x, y)

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
    local k = art:GetEffectiveScale() / ((parent and parent:GetEffectiveScale()) or 1)
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
                layoutBarButtons(ub, upper.row, upper.x, UPPER_Y, BUTTON_PITCH, BUTTON_SIZE)
            end
        end
        -- Stance or possess first, the pet bar after whichever of them shows.
        local x = SMALL_X
        for i, name in ipairs({ "StanceBar", "PossessActionBar", "PetActionBar" }) do
            local sb = _G[name]
            if sb and sb:IsShown() then
                if name == "PetActionBar" then x = math.max(36, x) end
                local n = layoutBarButtons(sb, 3 + i, x, SMALL_Y, SMALL_PITCH, SMALL_BUTTON)
                if n > 0 then x = x + n * SMALL_PITCH + 6 end
            end
        end
        -- Bar 4 outermost; bar 5 takes the outer column when bar 4 is off.
        local right = SIDE_RIGHT
        local screenH = (UIParent:GetHeight() or 768) / BAND_SCALE
        local top = math.max(SIDE_TOP_MIN, math.min(screenH - 40, screenH * SIDE_TOP_SHARE))
        for _, side in ipairs(SIDE_BARS) do
            local sb = _G[side.name]
            if sb and sb:IsShown() then
                layoutColumn(sb, side.row, right, top, BUTTON_PITCH, BUTTON_SIZE)
                right = right - SIDE_COLUMN
            end
        end
        local y = EXTRA_Y
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
local pageWasShown

local function layoutPageArrows()
    local bar = _G.MainActionBar
    local pn = bar and bar.ActionBarPageNumber
    if not pn then return end
    local midY = (PAGE_UP_Y + PAGE_DOWN_Y) / 2
    local holder = Row(HOLDER.page)
    holder:SetScale(1)
    holder:SetSize(48, 76)
    placeRow(holder, "page", "CENTER", art, "TOPLEFT", PAGE_X + 8, midY)

    anchor(pn, "CENTER", "CENTER", -8, 0, 32, 76, holder)
    -- Shown by us, so hidden again by us if the client had it hidden.
    if pageWasShown == nil then pageWasShown = pn:IsShown() end
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
    placeRow(holder, "bags", "BOTTOMRIGHT", art, "BOTTOMLEFT", BAG_RIGHT, 0)
    for _, s in ipairs(seats) do
        anchor(s[1], "BOTTOMRIGHT", "BOTTOMRIGHT", s[2] - BAG_RIGHT, s[3], nil, nil, holder)
    end
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
    placeRow(holder, "micro", "BOTTOMLEFT", art, "BOTTOMLEFT", MICRO_X, 0)
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
    placeRow(holder, "xp", "BOTTOM", art, "TOP", 0, -STRIP_H - 1)
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
        if applied then layoutExperience() end
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
local bagsHooked = false

local function hookBags()
    if bagsHooked then return end
    bagsHooked = true
    local function again()
        if applied then layoutMicro(layoutBags()) end
    end
    local bar = _G.BagsBar
    if bar and type(bar.Layout) == "function" then hooksecurefunc(bar, "Layout", again) end
    for n = 0, 3 do
        local b = _G["CharacterBag" .. n .. "Slot"]
        if b and type(b.SetBarExpanded) == "function" then
            hooksecurefunc(b, "SetBarExpanded", function(self)
                if applied and not self:IsShown() then pcall(self.Show, self) end
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

-- ---------------------------------------------------------------- dress --
--
-- The bags keep the client's frames but wear the 1.x art. They are plain
-- buttons, not secure action buttons, so their textures are ours to set, and
-- the client's own texture pass puts its art back on restore.

-- The bags: the 1.x ring around a square icon. The client re-dresses a bag
-- button in its own UpdateTextures whenever that bag changes, so the dress is
-- hooked onto that call, once per button, and does nothing while the band is
-- off.
local BAG_RING = "Interface\\Buttons\\UI-Quickslot2"
local bagHooked = setmetatable({}, { __mode = "k" })

local function bagButtons()
    local out = {}
    for _, name in ipairs({ "MainMenuBarBackpackButton", "CharacterBag0Slot", "CharacterBag1Slot",
        "CharacterBag2Slot", "CharacterBag3Slot", "CharacterReagentBag0Slot", "KeyRingButton" }) do
        if _G[name] then out[#out + 1] = _G[name] end
    end
    return out
end

-- The key ring was never a bag slot in 1.x but a tall narrow post.
local KEYRING_ART = "Interface\\Buttons\\UI-Button-KeyRing"
local KEYRING_COORDS = { 0, 0.5625, 0, 0.609375 }
local KEYRING_H = 39

local function dressKeyRing(b)
    local fs = ratio(b)
    local function post(tex, file)
        if not tex then return end
        pcall(function()
            tex:SetTexture(file)
            tex:SetTexCoord(unpack(KEYRING_COORDS))
            tex:ClearAllPoints()
            tex:SetPoint("CENTER", b, "CENTER")
            tex:SetSize(KEYRING_W / fs, KEYRING_H / fs)
        end)
    end
    post(b:GetNormalTexture(), KEYRING_ART)
    post(b:GetPushedTexture(), KEYRING_ART .. "-Down")
    post(b:GetHighlightTexture(), KEYRING_ART .. "-Highlight")
    if b.icon then pcall(b.icon.SetAlpha, b.icon, 0) end
end

local function dressBag(b)
    if not applied then return end
    if b == _G.KeyRingButton then return dressKeyRing(b) end
    local w = b:GetWidth() or 45
    if w <= 0 then w = 45 end
    local ring = w * 64 / 37
    for _, tex in ipairs({ b:GetNormalTexture(), b:GetPushedTexture() }) do
        pcall(function()
            tex:SetTexture(BAG_RING)
            tex:SetTexCoord(0, 1, 0, 1)
            tex:ClearAllPoints()
            tex:SetPoint("CENTER", b, "CENTER", 0, -w / 37)
            tex:SetSize(ring, ring)
        end)
    end
    -- The rounded mask is what made the icon a porthole; 1.x bags are square.
    if b.icon and b.SquareMask then pcall(b.icon.RemoveMaskTexture, b.icon, b.SquareMask) end
end

-- The free bag slots on the backpack, in the 1.x place (bottom right). The
-- client writes the same number into the backpack's own Count, but on the
-- band that string ended up out of sight under the ring; a font string of
-- ours on a frame ABOVE the button is on top whatever the client's layers do.
-- The backpack is a plain button, so a child frame of ours on it is allowed.
local freeHost, freeText
local freeEvents = CreateFrame("Frame")

local function paintFree()
    if not freeText then return end
    local on = applied and AB.db().backpackFreeSlots ~= false
    freeHost:SetShown(on)
    local own = _G.MainMenuBarBackpackButton and _G.MainMenuBarBackpackButton.Count
    if own then pcall(own.SetAlpha, own, on and 0 or 1) end
    if not on then return end
    local free = C_Container.CalculateTotalNumberOfFreeBagSlots()
    freeText:SetText(type(free) == "number" and tostring(free) or "")
end

freeEvents:SetScript("OnEvent", paintFree)

local function dressFreeSlots(on)
    local b = _G.MainMenuBarBackpackButton
    if not b then return end
    if on and not freeHost then
        freeHost = CreateFrame("Frame", nil, b)
        freeHost:SetAllPoints(b)
        freeHost:SetFrameLevel(b:GetFrameLevel() + 5)
        freeText = freeHost:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
        freeText:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -3, 3)
        freeText:SetJustifyH("RIGHT")
    end
    if on then
        freeEvents:RegisterEvent("BAG_UPDATE_DELAYED")
        freeEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
    else
        freeEvents:UnregisterAllEvents()
    end
    paintFree()
end

local function dressBags(on)
    for _, b in ipairs(bagButtons()) do
        if on then
            if not bagHooked[b] and type(b.UpdateTextures) == "function" then
                bagHooked[b] = true
                hooksecurefunc(b, "UpdateTextures", dressBag)
            end
            dressBag(b)
            -- No drag off the band: a slot dragged by accident lifts the
            -- whole bag onto the cursor. Clicking still opens the bag and
            -- still drops a bag held on the cursor into the slot.
            pcall(b.RegisterForDrag, b)
        else
            pcall(b.RegisterForDrag, b, "LeftButton")
            if b.icon and b.SquareMask then pcall(b.icon.AddMaskTexture, b.icon, b.SquareMask) end
            if b.icon then pcall(b.icon.SetAlpha, b.icon, 1) end
            -- The client's pass adds a TOPLEFT point without clearing ours
            -- first; two points would override its size, so ours go.
            for _, tex in ipairs({ b:GetNormalTexture(), b:GetPushedTexture(), b:GetHighlightTexture() }) do
                if tex then pcall(tex.ClearAllPoints, tex) end
            end
            -- The client's own pass puts its art, size and anchor back.
            if type(b.UpdateTextures) == "function" then pcall(b.UpdateTextures, b) end
        end
    end
end

-- The page arrows: the 1.x sheets, 32 pixel squares with the arrow in the
-- middle. A client without them keeps its own atlases.
local ARROW_ART = {
    up   = { file = "Interface\\MainMenuBar\\UI-MainMenu-ScrollUpButton",
             atlas = "ui-hud-actionbar-pageuparrow" },
    down = { file = "Interface\\MainMenuBar\\UI-MainMenu-ScrollDownButton",
             atlas = "ui-hud-actionbar-pagedownarrow" },
}

local function dressArrow(button, arrow, on)
    if not button then return end
    local normal = button:GetNormalTexture()
    local classic = on and normal and normal:SetTexture(arrow.file .. "-Up") ~= false
    pcall(function()
        if classic then
            button:SetPushedTexture(arrow.file .. "-Down")
            button:SetDisabledTexture(arrow.file .. "-Disabled")
            button:SetHighlightTexture(arrow.file .. "-Highlight", "ADD")
        else
            button:SetNormalAtlas(arrow.atlas .. "-up")
            button:SetPushedAtlas(arrow.atlas .. "-down")
            button:SetDisabledAtlas(arrow.atlas .. "-disabled")
            button:SetHighlightAtlas(arrow.atlas .. "-mouseover")
        end
        if not on then
            button:SetSize(17, 14)
            button:SetHitRectInsets(0, 0, 0, 0)
        end
    end)
end

local function dress(on)
    local bar = _G.MainActionBar
    local pn = bar and bar.ActionBarPageNumber
    if pn then
        dressArrow(pn.UpButton, ARROW_ART.up, on)
        dressArrow(pn.DownButton, ARROW_ART.down, on)
    end
    dressBags(on)
    dressFreeSlots(on)
    if not on then unskipMicro() end
end

-- ---------------------------------------------------------------- pass --

-- Is the client's own Edit Mode open? While it is, it owns these frames.
local function editModeOpen()
    local f = _G.EditModeManagerFrame
    return f and f.IsShown and f:IsShown() and true or false
end

-- The client's own edit mode: the band hands everything back while it is open
-- (it moves these same frames) and lays them again the moment it closes.
local editHooked = false

local function hookEditMode()
    if editHooked or not (EventRegistry and EventRegistry.RegisterCallback) then return end
    editHooked = true
    EventRegistry:RegisterCallback("EditMode.Enter", function()
        if applied then Classic.Restore() end
    end, "VuloForeverUI_ClassicBarEnter")
    EventRegistry:RegisterCallback("EditMode.Exit", function()
        if AB.mod.active then AB.Apply() end
    end, "VuloForeverUI_ClassicBarExit")
end

function Classic.Apply()
    hookEditMode()
    if InCombatLockdown() then return false end
    if editModeOpen() then
        Classic.Restore()
        return false
    end
    build()
    if not paint() then
        art:Hide()
        return false
    end

    art:Show()
    if not art.watching then
        art.watching = true
        art:SetScript("OnUpdate", watch)
    end
    -- The band at its chosen place, or on the bottom edge's centre.
    placeRow(art, "band", "BOTTOM", UIParent, "BOTTOM", 0, 0)
    hideModernArt(true)
    layoutButtons()
    layoutPageArrows()
    layoutMicro(layoutBags())
    hookExperience()
    hookBags()
    placeExperience()
    layoutExperience()
    applied = true
    -- After the flag: the bag hook dresses only while the band is applied.
    dress(true)
    return true
end

function Classic.Restore()
    if not applied then
        if art then art:Hide() end
        return
    end
    if InCombatLockdown() then return end
    applied = false

    if art then art:Hide() end
    hideModernArt(false)
    dress(false)
    restoreExperience()
    local pn = _G.MainActionBar and _G.MainActionBar.ActionBarPageNumber
    if pn and pageWasShown == false then pcall(pn.Hide, pn) end
    pageWasShown = nil
    for frame in pairs(original) do
        restoreFrame(frame)
    end
    -- Not asking the client to lay its bars out again: UpdateGridLayout only
    -- runs when its cached settings changed, which they did not, and when it
    -- does run it writes fields on a secure bar from our code. The snapshot
    -- above already put every container, bar and size back where it was.
end

-- ---------------------------------------------------------------- watch --
--
-- The client lays its own bar out again whenever almost anything happens --
-- a setting, a page, a form, Edit Mode closing -- and every one of those puts
-- the containers back where IT wants them. There is no single function to
-- hook for it, so the band simply checks, twice a second, that its row is
-- still its row, and lays it again when it is not.
local WATCH_EVERY = 0.5

function watch(self, elapsed)
    -- The experience bar every frame, and in a fight too: it is not protected,
    -- and a half second of the client's own bar is exactly the flicker seen.
    if applied then
        for _, name in ipairs(XP_CONTAINERS) do
            local c = _G[name]
            if c and c:IsShown() then
                -- Its place, its width, and the width of the bars inside: the
                -- client resets the last two on its own after a loading
                -- screen, with the anchor left where the band put it.
                local ok, _, rel = pcall(c.GetPoint, c, 1)
                local w = c:GetWidth() or 0
                local stale = (ok and rel ~= placed[c]) or math.abs(w * ratio(c) - (ART_W - 4)) > 1
                local bars = not stale and c.bars
                if type(bars) == "table" then
                    for _, child in pairs(bars) do
                        if child:IsShown() and (child:GetWidth() or 0) > w + 1 then stale = true break end
                    end
                end
                if stale then layoutExperience() break end
            end
        end
    end
    self.wait = (self.wait or 0) + elapsed
    if self.wait < WATCH_EVERY then return end
    self.wait = 0
    if not applied or InCombatLockdown() or not AB.mod.active then return end
    -- One comparison per bar is enough: if its first container is no longer
    -- sitting on our row, the client has been through here.
    local function moved(bar, rowIndex)
        local first = bar and bar:IsShown() and bar.actionButtons and bar.actionButtons[1]
        local container = first and first.container
        local row = art and art.rows and art.rows[rowIndex]
        if not (container and row) then return false end
        local ok, _, rel = pcall(container.GetPoint, container, 1)
        return ok and rel ~= row
    end
    local bar = _G.MainActionBar
    if not bar then return end
    local okBar, _, barRel = pcall(bar.GetPoint, bar, 1)
    local stale = moved(bar, 1) or (okBar and barRel ~= (art.rows and art.rows[1]))
    for laidBar, rowIndex in pairs(laid) do
        stale = stale or moved(laidBar, rowIndex)
    end
    if not stale then
        for frame in pairs(placed) do
            if frame:IsShown() then
                local ok, _, rel = pcall(frame.GetPoint, frame, 1)
                if ok and rel ~= placed[frame] then stale = true break end
            end
        end
    end
    if stale then Classic.Apply() end
end

function Classic.IsApplied() return applied end

-- ---------------------------------------------------------------- report --
--
-- What the client actually answers, printed on demand.
--
-- This exists because the alternative is guessing from screenshots. The three
-- things that decide whether the Classic bar can work at all -- does the old
-- art still ship, what scale is each piece wearing, and does the client re-lay
-- out its own bar after we have -- are all questions only the client can
-- answer, and none of them shows up in a picture.
function Classic.Report()
    local A, R = ns.C.accent, ns.C.r
    ns:Print(A .. "Classic bar" .. R)

    local probe = UIParent:CreateTexture()
    for key, path in pairs(TEX) do
        local ok = probe:SetTexture(path)
        ns:Print("  art %s: %s", key, (ok == false) and (ns.C.neg .. "missing" .. R) or "ok")
    end
    probe:SetTexture(nil)

    local function scaleOf(frame)
        if not frame then return "-" end
        return ("%.3f"):format(frame:GetEffectiveScale() or 0)
    end
    ns:Print("  scale  UIParent %s, MainActionBar %s, ActionButton1 %s, band %s",
        scaleOf(UIParent), scaleOf(_G.MainActionBar), scaleOf(_G.ActionButton1), scaleOf(art))

    local b = _G.ActionButton1
    if b then
        local w, h = b:GetWidth(), b:GetHeight()
        ns:Print("  ActionButton1 size %.1f x %.1f, points %d",
            w or 0, h or 0, b:GetNumPoints() or 0)
        local point, rel, relPoint, x, y = b:GetPoint(1)
        if ns.CanRead(point) then
            ns:Print("    1: %s of %s %s at %.1f, %.1f", tostring(point),
                (rel and rel.GetName and rel:GetName()) or "?", tostring(relPoint), x or 0, y or 0)
        end
    end
    local b2 = _G.ActionButton2
    if b and b2 then
        local x1, x2 = b:GetLeft(), b2:GetLeft()
        if x1 and x2 then ns:Print("  pitch on screen: %.1f", x2 - x1) end
    end

    -- The slot art of a filled and an empty button, and the bar's own art:
    -- which of them is on, at what alpha, wearing which atlas.
    local function texLine(label, tex)
        if not tex then ns:Print("    %s: none", label) return end
        local layer, sub = tex:GetDrawLayer()
        ns:Print("    %s: %s, alpha %.2f, %s %s, %s", label,
            tex:IsShown() and "shown" or (ns.C.neg .. "hidden" .. R), tex:GetAlpha() or 0,
            tostring(layer), tostring(sub),
            tostring(tex.GetAtlas and tex:GetAtlas() or tex:GetTexture()))
    end
    for _, name in ipairs({ "ActionButton1", "ActionButton4" }) do
        local btn = _G[name]
        if btn then
            ns:Print("  %s (bar art %s)", name,
                (btn.bar and btn.bar.hideBarArt) and "hidden" or "on")
            texLine("SlotArt", btn.SlotArt)
            texLine("SlotBackground", btn.SlotBackground)
            texLine("Normal", btn:GetNormalTexture())
        end
    end
    for _, name in ipairs({ "MainActionBar" }) do
        local frame = _G[name]
        if frame then
            ns:Print("  %s regions", name)
            for i, region in ipairs({ frame:GetRegions() }) do
                if region:GetObjectType() == "Texture" then texLine("#" .. i, region) end
            end
            for key, child in pairs(frame) do
                if type(key) == "string" and key:find("Art") and type(child) == "table"
                    and child.GetObjectType then
                    ns:Print("    child %s: %s, alpha %.2f", key,
                        child:IsShown() and "shown" or "hidden", child:GetAlpha() or 0)
                end
            end
        end
    end

    -- Which of the client's own layout calls exist. One of these putting the
    -- buttons back is the likeliest reason a row we placed does not stay
    -- placed, and the fix is a hook on whichever one is really there.
    local bar = _G.MainActionBar
    if bar then
        local found = {}
        for _, name in ipairs({ "UpdateGridLayout", "UpdateShownButtons", "Layout",
            "ApplySystemAnchor", "UpdateSystemSettingIconSize", "MarkDirty" }) do
            if type(bar[name]) == "function" then found[#found + 1] = name end
        end
        ns:Print("  MainActionBar methods: %s", (#found > 0) and table.concat(found, ", ") or "none of the usual")
    end
end
