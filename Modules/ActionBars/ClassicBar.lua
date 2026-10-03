-- VuloForeverUI / Modules / ActionBars / ClassicBar: the 1.x band's measurements, art, anchoring helpers and movers
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

-- Private to the band's files (ClassicBar, ClassicBarLayout, ClassicBarDress,
-- ClassicBarApply): the state they share, the measurements and the helpers.
AB._classic = AB._classic or {}
local P = AB._classic

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
local HOLDER = { micro = 12, bags = 13, xp = 14, page = 15, totem = 16 }
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

P.art, P.applied = nil, false
local missingArt = false


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
    local fs = (frame:GetEffectiveScale() or 1) / ((P.art and P.art:GetEffectiveScale()) or 1)
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
    on = on or P.art
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
    if P.art then return P.art end
    P.art = CreateFrame("Frame", "VuloForeverUIClassicBar", UIParent)
    P.art:SetSize(ART_W, ART_H)
    P.art:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 0)
    P.art:SetFrameStrata("MEDIUM")
    P.art:SetFrameLevel(1)
    P.art:SetScale(BAND_SCALE)

    P.art.pieces = {}
    for i, piece in ipairs(PIECES) do
        local tex = P.art:CreateTexture(nil, "BACKGROUND")
        tex:SetSize(256, BAND_H)
        tex:SetPoint("BOTTOMLEFT", P.art, "BOTTOMLEFT", piece.x, 0)
        P.art.pieces[i] = tex
    end

    -- The gryphons are one sheet, drawn twice: the sheet is the LEFT one, and
    -- the right one is it with its horizontal coordinates swapped.
    P.art.leftCap = P.art:CreateTexture(nil, "OVERLAY", nil, 5)
    P.art.leftCap:SetSize(CAP_SIZE, CAP_SIZE)
    P.art.leftCap:SetPoint("BOTTOM", P.art, "BOTTOM", -544, 0)
    P.art.rightCap = P.art:CreateTexture(nil, "OVERLAY", nil, 5)
    P.art.rightCap:SetSize(CAP_SIZE, CAP_SIZE)
    P.art.rightCap:SetPoint("BOTTOM", P.art, "BOTTOM", 544, 0)
    return P.art
end

-- Paint the band, and say once if the client no longer ships the art.
local function paint()
    local ok = true
    for i, piece in ipairs(PIECES) do
        local tex = P.art.pieces[i]
        -- SetTexture answers false for a file that is not there, which is the
        -- only way to ask this question.
        if tex:SetTexture(TEX[piece.file]) == false then ok = false end
        tex:SetTexCoord(0, 1, piece.v[1], piece.v[2])
        tex:Show()
    end
    if P.art.leftCap:SetTexture(TEX.cap) == false then ok = false end
    P.art.leftCap:SetTexCoord(0, 1, 0, 1)
    P.art.rightCap:SetTexture(TEX.cap)
    P.art.rightCap:SetTexCoord(1, 0, 0, 1)

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
    P.art.rows = P.art.rows or {}
    local row = P.art.rows[index]
    if not row then
        row = CreateFrame("Frame", nil, P.art)
        row:SetSize(1, 1)
        P.art.rows[index] = row
    end
    return row
end

local function matchScale(frame, scale)
    if not (frame and frame.SetScale and frame.GetScale) then return end
    if math.abs((frame:GetScale() or 1) - scale) < 0.005 then return end
    remember(frame)
    pcall(frame.SetScale, frame, scale)
end


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
        totem  = L["Totem bar"],
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
    if P.applied then Classic.Apply() end
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

-- What the band's other files take from here.
P.ART_W, P.BAND_H, P.STRIP_H, P.BUTTON_PITCH, P.BAND_SCALE = ART_W, BAND_H, STRIP_H, BUTTON_PITCH, BAND_SCALE
P.BUTTON_SIZE, P.ROW_X, P.ROW_Y, P.PAGE_X, P.PAGE_UP_Y = BUTTON_SIZE, ROW_X, ROW_Y, PAGE_X, PAGE_UP_Y
P.PAGE_DOWN_Y, P.UPPER_Y, P.UPPER_BARS, P.SMALL_Y, P.SMALL_X = PAGE_DOWN_Y, UPPER_Y, UPPER_BARS, SMALL_Y, SMALL_X
P.SMALL_BUTTON, P.SMALL_PITCH, P.SIDE_TOP_MIN, P.SIDE_TOP_SHARE, P.SIDE_RIGHT = SMALL_BUTTON, SMALL_PITCH, SIDE_TOP_MIN, SIDE_TOP_SHARE, SIDE_RIGHT
P.SIDE_COLUMN, P.EXTRA_Y, P.EXTRA_BARS, P.HOLDER, P.SIDE_BARS = SIDE_COLUMN, EXTRA_Y, EXTRA_BARS, HOLDER, SIDE_BARS
P.MICRO_X, P.MICRO_Y, P.MICRO_W, P.MICRO_STEP, P.MICRO_ROOM = MICRO_X, MICRO_Y, MICRO_W, MICRO_STEP, MICRO_ROOM
P.MICRO_SKIP, P.BAG_SIZE, P.BAG_PITCH, P.BAG_BOTTOM, P.BAG_RIGHT = MICRO_SKIP, BAG_SIZE, BAG_PITCH, BAG_BOTTOM, BAG_RIGHT
P.KEYRING_W, P.KEYRING_GAP, P.REAGENT_SIZE, P.TEX, P.original = KEYRING_W, KEYRING_GAP, REAGENT_SIZE, TEX, original
P.remember, P.restoreFrame, P.ratio, P.placed, P.anchor = remember, restoreFrame, ratio, placed, anchor
P.build, P.paint, P.Row, P.matchScale, P.ROW_KEY = build, paint, Row, matchScale, ROW_KEY
P.placeRow = placeRow
