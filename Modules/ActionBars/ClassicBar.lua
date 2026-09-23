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
local BUTTON_SIZE, BUTTON_PITCH = 36, 42
local ROW_X, ROW_Y = 8, 4                   -- first button from the band's corner
local PAGE_X, PAGE_UP_Y, PAGE_DOWN_Y = 522, -22, -42
local MICRO_X, MICRO_Y = 555, 2.5
local MICRO_W, MICRO_H, MICRO_STEP = 28, 38, -3
local BAG_PITCH, BAG_SIZE, BAG_Y = 34, 28, 22

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
    original[frame] = { points = points, scale = frame:GetScale() }
end

local function restoreFrame(frame)
    local o = original[frame]
    if not (frame and o) then return end
    if o.scale then pcall(frame.SetScale, frame, o.scale) end
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

-- Anchor one of the client's frames onto the band. SetPoint only: the frame
-- keeps its parent, and with it everything the client does to it.
local function anchor(frame, point, bandPoint, x, y, w, h)
    if not frame then return end
    remember(frame)
    local fs = ratio(frame)
    pcall(function()
        frame:ClearAllPoints()
        frame:SetPoint(point, art, bandPoint, x / fs, y / fs)
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

    art.pieces = {}
    for i, piece in ipairs(PIECES) do
        local tex = art:CreateTexture(nil, "BACKGROUND")
        tex:SetSize(256, BAND_H)
        tex:SetPoint("BOTTOMLEFT", art, "BOTTOMLEFT", piece.x, 0)
        art.pieces[i] = tex
    end

    -- The gryphons are one sheet, drawn twice: the left one is the right one
    -- with its horizontal coordinates swapped.
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
    art.leftCap:SetTexCoord(1, 0, 0, 1)
    art.rightCap:SetTexture(TEX.cap)
    art.rightCap:SetTexCoord(0, 1, 0, 1)

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
local function layoutBarButtons(bar, rowIndex, x, y, pitch, target)
    if not (bar and bar.actionButtons) then return 0 end

    local first = bar.actionButtons[1]
    local size = (first and first:GetWidth()) or 45
    if not size or size == 0 then size = 45 end
    local scale = (target or BUTTON_SIZE) / size
    if scale <= 0 then scale = 1 end
    local step = (pitch or BUTTON_PITCH) / scale

    -- The bar frame keeps the plain scale: the client puts the icon size on
    -- the buttons and leaves the frame alone, and the frame is what Edit Mode
    -- draws its box around -- scaling it too would count the size twice.
    matchScale(bar, 1)

    local row = Row(rowIndex)
    row:SetScale(1)
    row:ClearAllPoints()
    row:SetPoint("BOTTOMLEFT", art, "BOTTOMLEFT", x, y)

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
        local slot = BUTTON_SIZE
        local along = (count - 1) * (pitch or BUTTON_PITCH) + slot
        if math.abs((bar:GetWidth() or 0) - along) > 0.5 or math.abs((bar:GetHeight() or 0) - slot) > 0.5 then
            remember(bar)
            pcall(bar.SetSize, bar, along, slot)
        end
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
-- button, at the 32 pixels 1.x drew them.
local function layoutPageArrows()
    local bar = _G.MainActionBar
    local pn = bar and bar.ActionBarPageNumber
    if not pn then return end
    anchor(pn, "CENTER", "TOPLEFT", PAGE_X, (PAGE_UP_Y + PAGE_DOWN_Y) / 2, 32, 76)
    pcall(pn.Show, pn)
    for _, entry in ipairs({ { pn.UpButton, PAGE_UP_Y }, { pn.DownButton, PAGE_DOWN_Y } }) do
        local button, y = entry[1], entry[2]
        if button then
            anchor(button, "CENTER", "TOPLEFT", PAGE_X, y, 32, 32)
            pcall(button.SetHitRectInsets, button, 6, 6, 7, 7)
        end
    end
    if pn.Text then
        local fs = ratio(pn)
        pcall(function()
            pn.Text:ClearAllPoints()
            pn.Text:SetPoint("CENTER", art, "TOPLEFT",
                (PAGE_X + 20) / fs, ((PAGE_UP_Y + PAGE_DOWN_Y) / 2 + 0.5) / fs)
        end)
    end
end

-- The micro menu, in the row of sockets the band art has for it. The shop
-- button is left out: it never had a socket, because it did not exist.
local MICRO_ORDER = {
    "CharacterMicroButton", "SpellbookMicroButton", "PlayerSpellsMicroButton",
    "TalentMicroButton", "AchievementMicroButton", "QuestLogMicroButton",
    "GuildMicroButton", "LFDMicroButton", "CollectionsMicroButton",
    "EJMicroButton", "MainMenuMicroButton", "HelpMicroButton",
}

local function layoutMicro()
    local index = 0
    for _, name in ipairs(MICRO_ORDER) do
        local b = _G[name]
        if b and b:IsShown() then
            anchor(b, "BOTTOMLEFT", "BOTTOMLEFT",
                MICRO_X + index * (MICRO_W + MICRO_STEP), MICRO_Y, MICRO_W, MICRO_H)
            index = index + 1
        end
    end
end

-- The bags, chained right to left from the band's own corner: the backpack in
-- its wider socket, then the four bags at the pitch the art was drawn with.
local function layoutBags()
    local backpack = _G.MainMenuBarBackpackButton
    if not backpack then return end
    anchor(backpack, "BOTTOMRIGHT", "BOTTOMRIGHT", -42, BAG_Y - BAG_SIZE / 2,
        BAG_SIZE + 2, BAG_SIZE + 2)

    for i = 0, 3 do
        local b = _G["CharacterBag" .. i .. "Slot"]
        if b then
            anchor(b, "BOTTOMRIGHT", "BOTTOMRIGHT",
                -42 - (BAG_SIZE + 2) - i * BAG_PITCH, BAG_Y - BAG_SIZE / 2,
                BAG_SIZE, BAG_SIZE)
        end
    end
    local keyring = _G.KeyRingButton
    if keyring then
        anchor(keyring, "BOTTOMRIGHT", "BOTTOMRIGHT", -10, BAG_Y - 8)
    end
end

-- The experience bar along the band's top edge, where 1.x kept it.
local function layoutExperience()
    for _, name in ipairs({ "MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer" }) do
        local container = _G[name]
        if container and container:IsShown() then
            anchor(container, "BOTTOMLEFT", "TOPLEFT", 0, -STRIP_H - 1, ART_W, STRIP_H)
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
    for _, name in ipairs({ "MainActionBar", "StatusTrackingBarManager" }) do
        local frame = _G[name]
        if frame and frame.GetRegions then
            for _, region in ipairs({ frame:GetRegions() }) do
                if region.GetObjectType and region:GetObjectType() == "Texture" then
                    pcall(region.SetAlpha, region, hide and 0 or 1)
                end
            end
        end
    end
end

-- ---------------------------------------------------------------- pass --

-- Is the client's own Edit Mode open? While it is, it owns these frames.
local function editModeOpen()
    local f = _G.EditModeManagerFrame
    return f and f.IsShown and f:IsShown() and true or false
end

function Classic.Apply()
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
    hideModernArt(true)
    layoutButtons()
    layoutPageArrows()
    layoutMicro()
    layoutBags()
    layoutExperience()
    applied = true
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
    for frame in pairs(original) do
        restoreFrame(frame)
    end
    -- And the client is asked to lay its own bar out again, which is the only
    -- thing that puts its containers back the way it wants them.
    local bar = _G.MainActionBar
    if bar and type(bar.UpdateGridLayout) == "function" then
        pcall(bar.UpdateGridLayout, bar)
    end
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
    self.wait = (self.wait or 0) + elapsed
    if self.wait < WATCH_EVERY then return end
    self.wait = 0
    if not applied or InCombatLockdown() or not AB.mod.active then return end
    local bar = _G.MainActionBar
    local first = bar and bar.actionButtons and bar.actionButtons[1]
    local container = first and first.container
    local row = art and art.rows and art.rows[1]
    if not (container and row) then return end
    -- One comparison is enough: if the first container is no longer sitting on
    -- our row, the client has been through here.
    local ok, point, rel = pcall(container.GetPoint, container, 1)
    if ok and rel ~= row then
        Classic.Apply()
    end
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
