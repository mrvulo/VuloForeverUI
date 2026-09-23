-- VuloForeverUI / Modules / CooldownManager / Bar
--
-- One bar: a frame the mover owns, a pool of icons, and the paint pass that
-- hands each icon its spell's duration object.
--
-- Nothing in the paint pass reads a cooldown. The places where a decision
-- would normally be made are all pushed into the engine:
--   ready or not   Cooldown:SetCooldownFromDurationObject clears itself at
--                  zero, so nothing has to ask
--   dimming        ns.FoldValue turns the secret "is zero" into a number
--   glow           CM.Glow folds the same boolean into an alpha
--   ready sound    the widget's own OnCooldownDone script, which the engine
--                  fires when the swipe runs out -- we never watch the clock
--
-- The threshold colour is the one place where the client may refuse us: it
-- needs "is less than five seconds left", and that is a COMPARISON. Out of
-- combat the number is readable and the comparison is ours to make; in combat
-- it is made only if the duration object offers a predicate that returns a
-- secret boolean (probed once below). If it does not, the countdown keeps its
-- ordinary colour rather than a wrong one.
local _, ns = ...
local L  = ns.L
local CM = ns.CM
local UI = ns.UI

CM.frames = CM.frames or {}

local WHITE = CM.WHITE
local DU = _G.C_DurationUtil

-- THE COUNTDOWN, AND WHY THERE ARE TWO WAYS TO WRITE IT
--
-- The engine-side binding below is the nice one: the client writes the text
-- itself, tenths and all, and nothing ticks in Lua. It is tried first -- but
-- on this build it produced no text at all where the cast bar used it, so a
-- second route stands behind it, the one Modules/Nameplates/CastBar has been
-- running on: format the object's own getter. The number stays secret and
-- string.format on a secret is allowed.
--
-- The fallback is ONE ticker for every icon on every bar, not an OnUpdate per
-- icon: a full set of bars is two dozen icons, and two dozen handlers for one
-- line of text each is how a countdown becomes a frame-rate problem.
local timed, timedCount, ticker = {}, 0, nil

local function tickTimed()
    for icon, dur in pairs(timed) do
        if icon.button:IsShown() and icon.countdown:IsShown() then
            if not pcall(icon.countdown.SetFormattedText, icon.countdown, "%.1f", dur:GetRemainingDuration()) then
                icon.countdown:SetText("")
                timed[icon] = nil
                timedCount = timedCount - 1
            end
        end
    end
    if timedCount <= 0 and ticker then
        ns:CancelTicker(ticker)
        ticker = nil
    end
end

local function driveText(icon, duration)
    if type(duration) == "nil" then
        if timed[icon] then timed[icon] = nil; timedCount = timedCount - 1 end
        icon.countdown:SetText("")
        return
    end
    if not timed[icon] then timedCount = timedCount + 1 end
    timed[icon] = duration
    if not ticker then ticker = ns:AddTicker(0.05, tickTimed, nil, "cooldownmanager.countdown") end
end

local function ensureBinding(icon)
    if icon.binding ~= nil then return icon.binding end
    icon.binding = false
    if DU and DU.CreateDurationTextBinding then
        local ok, binding = pcall(DU.CreateDurationTextBinding)
        if ok and binding then
            binding:SetFontString(icon.countdown)
            -- Nothing to say while the spell is ready; the swipe is gone then
            -- as well, so an empty icon stays empty.
            if binding.SetZeroDurationText then binding:SetZeroDurationText("") end
            icon.binding = binding
        end
    end
    return icon.binding
end

-- ---------------------------------------------------------------- threshold --

-- "Is there less than n seconds left?" on a duration object. The readable
-- answer first, then the client's own predicate, then nothing at all -- and
-- "nothing at all" is a nil return, never a guess.
local PREDICATES = { "IsRemainingLessThan", "IsLessThan", "IsBelow", "IsRemainingBelow" }
local predicate   -- nil unknown, false none, otherwise the method name

local function belowThreshold(duration, seconds)
    if type(duration) == "nil" or type(seconds) ~= "number" or seconds <= 0 then return nil end

    local rem = duration.GetRemainingDuration and duration:GetRemainingDuration()
    if ns.CanRead(rem) and type(rem) == "number" then
        return rem > 0 and rem <= seconds
    end

    if predicate == nil then
        predicate = false
        for _, name in ipairs(PREDICATES) do
            if type(duration[name]) == "function" then predicate = name; break end
        end
    end
    if not predicate then return nil end
    local ok, res = pcall(duration[predicate], duration, seconds)
    if not ok then return nil end
    return res
end

-- The file behind a sound name: ours first, then whatever other addons have
-- registered as shared media. An unknown name plays nothing rather than the
-- wrong thing.
function CM.SoundPath(name)
    if type(name) ~= "string" or name == "" then return nil end
    local own = ns.MediaSound(name)
    if own then return own end
    local LSM = ns.LSM
    local hash = LSM and LSM:HashTable("sound")
    local path = hash and hash[name]
    if type(path) == "string" and path ~= "" then return path end
    return nil
end

-- ---------------------------------------------------------------- icons --

local function makeIcon(parent, index)
    local icon = {}
    local b = CreateFrame("Button", nil, parent)
    b:RegisterForClicks("AnyUp")
    icon.button = b

    local tex = b:CreateTexture(nil, "ARTWORK")
    tex:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
    tex:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
    icon.texture = tex

    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(b)
    bg:SetTexture(WHITE)
    icon.bg = bg

    -- Three border kinds share one icon: the flat edges, a shaped border that
    -- belongs to the mask, and a shared-media frame. Only one is ever shown,
    -- and each is created once so switching between them costs nothing.
    icon.edges = ns.MakeEdges(b, "OVERLAY")

    local shaped = b:CreateTexture(nil, "OVERLAY")
    shaped:Hide()
    icon.shaped = shaped

    local media = CreateFrame("Frame", nil, b, BackdropTemplateMixin and "BackdropTemplate")
    media:SetFrameLevel((b:GetFrameLevel() or 1) + 1)
    media:Hide()
    icon.media = media

    -- Our own cooldown frame, never one of Blizzard's: the setters are
    -- protected functions on this client, and a frame we created ourselves is
    -- the one place they are ours to call.
    local cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    cd:SetAllPoints(b)
    cd:SetHideCountdownNumbers(true)   -- our own font string does the text
    cd:SetDrawEdge(false)
    icon.cooldown = cd

    -- The ready sound. The engine fires this when the swipe runs out, which is
    -- the one moment "the spell is ready again" is knowable without a clock
    -- and without reading anything.
    -- pcall, because a script element a client does not know is a throw and
    -- not a nil: on a build without this one the icon simply stays silent.
    pcall(cd.SetScript, cd, "OnCooldownDone", function()
        local file = icon.readySound
        if type(file) == "string" and file ~= "" then
            pcall(PlaySoundFile, file, "SFX")
        end
    end)

    local text = b:CreateFontString(nil, "OVERLAY")
    text:SetPoint("CENTER", b, "CENTER", 0, 0)
    icon.countdown = text

    local charges = b:CreateFontString(nil, "OVERLAY")
    charges:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 2)
    icon.charges = charges

    -- Top left is the key that casts it, bottom left the number of them you
    -- carry or the stacks you have. Neither is ever about the fight.
    local keybind = b:CreateFontString(nil, "OVERLAY")
    keybind:SetPoint("TOPRIGHT", b, "TOPRIGHT", -2, -2)
    icon.keybind = keybind

    local count = b:CreateFontString(nil, "OVERLAY")
    count:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 2, 2)
    icon.count = count

    -- A one pixel highlight along the top edge. Cheap, and it stops a row of
    -- dark squares from reading as one flat block.
    local sheen = b:CreateTexture(nil, "OVERLAY", nil, 1)
    sheen:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
    sheen:SetPoint("TOPRIGHT", b, "TOPRIGHT", 0, 0)
    sheen:SetTexture(WHITE)
    sheen:SetColorTexture(1, 1, 1, 0.14)
    icon.sheen = sheen

    b:SetScript("OnEnter", function(self)
        if not self._spellID then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self._kind == "item" then
            GameTooltip:SetItemByID(self._spellID)
        else
            GameTooltip:SetSpellByID(self._spellID)
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)

    icon.index = index
    return icon
end

-- The shape. A mask on the icon art, and the border art that goes with it --
-- a square border around a round icon is the one combination that always
-- looks like a bug.
local function applyShape(icon, shapeName)
    local shape = CM.SHAPES[shapeName] or CM.SHAPES.square
    if icon.shapeName == shapeName then return shape end
    icon.shapeName = shapeName

    if shape.mask then
        if not icon.mask then
            icon.mask = icon.button:CreateMaskTexture()
            icon.mask:SetAllPoints(icon.texture)
        end
        icon.mask:SetTexture(shape.mask, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        pcall(icon.texture.AddMaskTexture, icon.texture, icon.mask)
        pcall(icon.bg.AddMaskTexture, icon.bg, icon.mask)
        if icon.texture.SetSnapToPixelGrid then icon.texture:SetSnapToPixelGrid(false) end
        if icon.texture.SetTexelSnappingBias then icon.texture:SetTexelSnappingBias(0) end
    elseif icon.mask then
        pcall(icon.texture.RemoveMaskTexture, icon.texture, icon.mask)
        pcall(icon.bg.RemoveMaskTexture, icon.bg, icon.mask)
    end
    return shape
end

-- ---------------------------------------------------------------- build --

function CM.BuildBar(key)
    if CM.frames[key] then return CM.frames[key] end
    local bar = CM.Bar(key)
    if not bar then return nil end

    local frame = CreateFrame("Frame", "VuloForeverUICooldownBar" .. key, UIParent)
    frame:SetSize(200, 42)
    frame:SetFrameStrata("MEDIUM")
    frame.icons = {}
    frame.barKey = key
    CM.frames[key] = frame

    frame.mover = ns:CreateMover(frame, {
        key      = "cooldownbar_" .. key,
        label    = bar.name,
        db       = bar,
        module   = "cooldownmanager",
        width    = 200,
        height   = 42,
        scalable = true,
        -- The anchor point keeps one edge still while icons come and go;
        -- growAnchor writes it into the bar before every apply.
        anchorable = true,
    })
    ns:ApplyMover(frame.mover)

    CM.Restyle(key)
    return frame
end

-- ---------------------------------------------------------------- layout --

-- The size an icon on this bar actually gets. iconSize is what was asked for;
-- a bar with a width limit shrinks its icons to fit, and stops at minIconSize
-- rather than turning the row into a line of dots.
local function iconSizeFor(bar, count)
    local size = bar.iconSize or 32
    local maxW = tonumber(bar.maxWidth) or 0
    if maxW > 0 and count > 0 then
        local rows   = math.max(1, bar.rows or 1)
        local perRow = math.max(1, math.ceil(count / rows))
        local gap    = bar.spacing or 0
        local fit    = (maxW - math.max(0, perRow - 1) * gap) / perRow
        if fit < size then size = math.max(fit, bar.minIconSize or 20) end
    end
    return math.max(8, math.floor(size + 0.5))
end

-- Where icon number i sits, always measured from the frame's top left corner.
--
-- The grow direction is deliberately NOT in this maths. The frame is sized to
-- its content and the mover pins it by one point, so "grows to the right"
-- means "keep the left edge still" -- that is what an anchor point is for,
-- and the house mover already does it (see growAnchor below). Doing it here
-- as well once put half the icons outside the frame the mover was showing.
local function place(frame, bar, icon, i, count, size)
    local gap  = ns:PixelSnap(bar.spacing, frame)
    local rows = math.max(1, bar.rows)
    local perRow = math.max(1, math.ceil(count / rows))

    local col = (i - 1) % perRow
    local row = math.floor((i - 1) / perRow)

    -- The split: every row after the first is pushed out by an extra gap, so
    -- a double row reads as two rows instead of a block.
    local extra = 0
    if bar.splitRows and row > 0 then extra = (bar.splitGap or 0) * row end

    local x, y
    if bar.vertical then
        x, y = row * (size + gap) + extra, -(col * (size + gap))
    else
        x, y = col * (size + gap), -(row * (size + gap) + extra)
    end

    icon.button:ClearAllPoints()
    icon.button:SetPoint("TOPLEFT", frame, "TOPLEFT", x, y)
    icon.button:SetSize(size, size)
end

-- Which edge stays still while the bar grows and shrinks.
local function growAnchor(bar)
    if bar.grow == "RIGHT" then return bar.vertical and "TOP" or "LEFT" end
    if bar.grow == "LEFT"  then return bar.vertical and "BOTTOM" or "RIGHT" end
    return "CENTER"
end

local function barSize(bar, count, size)
    local gap  = bar.spacing
    local rows = math.max(1, bar.rows)
    local perRow = math.max(1, math.ceil(math.max(count, 1) / rows))
    local usedRows = math.max(1, math.ceil(math.max(count, 1) / perRow))
    local split = (bar.splitRows and math.max(0, usedRows - 1) * (bar.splitGap or 0)) or 0
    local w = perRow * size + math.max(0, perRow - 1) * gap
    local h = usedRows * size + math.max(0, usedRows - 1) * gap + split
    -- Upright: the rows run sideways, so what was the height is the width
    -- and the split is already inside it.
    if bar.vertical then return h, w end
    return w, h
end

-- ---------------------------------------------------------------- overflow --

-- Everything a bar shows, in order: its own rows up to its limit, then the
-- rows its feeders could not fit. A feeder that is itself fed passes its
-- overflow on, and `seen` keeps a pair of bars pointing at each other from
-- turning that into a loop.
local function collectOverflow(targetKey, out, seen)
    local db = CM.db()
    for _, key in ipairs(db.barOrder or {}) do
        local other = db.bars[key]
        if other and key ~= targetKey and other.overflowInto == targetKey and not seen[key] then
            seen[key] = true
            local cap = tonumber(other.maxIcons) or 0
            if cap > 0 then
                local list = CM.Spells(other)
                for i = cap + 1, #list do out[#out + 1] = list[i] end
            end
            collectOverflow(key, out, seen)
        end
    end
end

function CM.Own(bar)
    local list = CM.Spells(bar)
    local cap = tonumber(bar.maxIcons) or 0
    if cap <= 0 or #list <= cap then return list end
    local out = {}
    for i = 1, cap do out[i] = list[i] end
    return out
end

-- ---------------------------------------------------------------- style --

-- What this bar draws right now: its own rows, the rows handed to it by the
-- bars that overflow into it, and -- while the settings page is open -- enough
-- borrowed ones to make the layout visible.
local PREVIEW_MIN = 5

function CM.Display(bar, key)
    local out = CM.Own(bar)
    if key then
        local extra = {}
        collectOverflow(key, extra, { [key] = true })
        if #extra > 0 then
            local merged = {}
            for i = 1, #out do merged[i] = out[i] end
            for i = 1, #extra do merged[#merged + 1] = extra[i] end
            out = merged
        end
    end
    local owned = #out
    if CM.optionsOpen then return CM.PreviewFill(out, PREVIEW_MIN), owned end
    return out, owned
end

-- Lay a list of rows out on a frame and paint them. Everything the settings
-- decide lives here and nothing about WHERE the frame is, which is what lets
-- the settings preview run the very same pass on a frame of its own: what the
-- page shows is the display code itself, not a drawing of it.
function CM.StyleFrame(frame, bar, list, owned)
    frame.icons = frame.icons or {}
    local count = math.min(#list, CM.MAX_ICONS)
    frame.ownedCount = owned or count
    local size = iconSizeFor(bar, count)
    frame.iconSize = size
    local w, h = barSize(bar, count, size)
    frame:SetSize(math.max(w, size), math.max(h, size))

    local br, bg, bb = bar.borderColor.r, bar.borderColor.g, bar.borderColor.b
    if bar.borderClassColor then
        local _, class = UnitClass("player")
        local c = RAID_CLASS_COLORS[class]
        if c then br, bg, bb = c.r, c.g, c.b end
    end
    local ba = bar.borderColor.a or 1
    local inset = tonumber(bar.borderInset) or 0
    local mediaBorder = ns.MediaBorder(bar.borderTexture)

    local zoom = bar.iconZoom or 0
    for i = 1, count do
        local icon = frame.icons[i]
        if not icon then
            icon = makeIcon(frame, i)
            frame.icons[i] = icon
        end
        local entry = list[i]
        -- the proc ring belongs to a spell, not to a slot: an icon that now
        -- shows another spell drops it (only the event would ever clear it)
        local id = entry and entry.id
        if icon.procFor ~= id then CM.Glow.Clear(icon, "proc"); icon.procFor = id end
        place(frame, bar, icon, i, count, size)
        local shape = applyShape(icon, bar.iconShape or "square")
        icon.texture:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)
        icon.bg:SetColorTexture(bar.bgColor.r, bar.bgColor.g, bar.bgColor.b, bar.bgColor.a)
        icon.sheen:SetHeight(ns:Pixel(frame, 1))
        icon.sheen:SetShown(not shape.mask)

        -- One border kind at a time: shaped art when the icon has a shape, a
        -- shared-media frame when one is chosen, the flat edges otherwise.
        icon.borderColor = { r = br, g = bg, b = bb, a = ba }
        if shape.border then
            ns.LayoutEdges(icon.edges, icon.button, 0, br, bg, bb, ba, 0)
            icon.media:Hide()
            icon.shaped:Show()
            icon.shaped:SetTexture(shape.border)
            icon.shaped:ClearAllPoints()
            icon.shaped:SetPoint("TOPLEFT", icon.button, "TOPLEFT", -inset, inset)
            icon.shaped:SetPoint("BOTTOMRIGHT", icon.button, "BOTTOMRIGHT", inset, -inset)
            icon.shaped:SetVertexColor(br, bg, bb, ba)
        elseif mediaBorder then
            ns.LayoutEdges(icon.edges, icon.button, 0, br, bg, bb, ba, 0)
            icon.shaped:Hide()
            icon.media:Show()
            icon.media:ClearAllPoints()
            local edge = math.max(2, (bar.borderSize or 1) * 4)
            icon.media:SetPoint("TOPLEFT", icon.button, "TOPLEFT", -inset - edge / 4, inset + edge / 4)
            icon.media:SetPoint("BOTTOMRIGHT", icon.button, "BOTTOMRIGHT", inset + edge / 4, -inset - edge / 4)
            if icon.media.SetBackdrop then
                icon.media:SetBackdrop({ edgeFile = mediaBorder, edgeSize = edge })
                icon.media:SetBackdropBorderColor(br, bg, bb, ba)
            end
        else
            icon.shaped:Hide()
            icon.media:Hide()
            ns.LayoutEdges(icon.edges, icon.button, bar.borderSize or 0, br, bg, bb, ba, inset)
        end

        icon.cooldown:SetDrawSwipe(CM.Val(bar, entry, "showSwipe") ~= false)
        icon.cooldown:SetSwipeColor(0, 0, 0, CM.Val(bar, entry, "swipeAlpha") or 0.7)

        UI.FontFor("cooldownmanager", icon.countdown, bar.countdownSize or 12, "OUTLINE")
        icon.countdown:SetShown(CM.Val(bar, entry, "showCountdown") ~= false)
        UI.FontFor("cooldownmanager", icon.charges, bar.chargeSize or 11, "OUTLINE")
        UI.FontFor("cooldownmanager", icon.keybind, bar.keybindSize or 10, "OUTLINE")
        icon.keybind:SetTextColor(bar.keybindColor.r, bar.keybindColor.g, bar.keybindColor.b)
        icon.keybind:SetShown(CM.Val(bar, entry, "showKeybind") == true)
        UI.FontFor("cooldownmanager", icon.count, bar.countSize or 11, "OUTLINE")
        icon.count:SetTextColor(bar.countColor.r, bar.countColor.g, bar.countColor.b)
        icon.count:SetShown(CM.Val(bar, entry, "showCount") ~= false)
    end
    for i = count + 1, #frame.icons do
        frame.icons[i].button:Hide()
        CM.Glow.Clear(frame.icons[i])
    end

    CM.PaintFrame(frame, bar, list, frame.ownedCount)
end

-- Everything the settings decide, for one of OUR bars: the layout above, plus
-- the mover and the anchor, which a preview frame has neither of.
function CM.Restyle(key)
    local frame = CM.frames[key]
    local bar = CM.Bar(key)
    if not frame or not bar then return end

    local list, owned = CM.Display(bar, key)
    CM.StyleFrame(frame, bar, list, owned)
    frame:SetAlpha(bar.opacity or 1)

    if frame.mover then
        -- Only ours to write while it still holds what we last wrote: a
        -- player who re-anchored the bar in Edit Mode keeps that.
        local want = growAnchor(bar)
        if bar.anchor == nil or bar.anchor == bar._growAnchor then
            bar.anchor, bar._growAnchor = want, want
        end
        frame.mover.opts.label = bar.name
        frame.mover.opts.db = bar
        frame.mover.opts.width, frame.mover.opts.height = frame:GetWidth(), frame:GetHeight()
        ns:RefreshMoverGeometry(frame.mover)
        ns:ApplyMover(frame.mover)
    end
    -- No paint here: CM.StyleFrame already did one, and painting twice for
    -- one settings change is a second walk over every icon for nothing.
    CM.ApplyAnchor(key)
end

-- ---------------------------------------------------------------- anchors --

-- What a bar can hang off besides the screen. Ours first, the client's frame
-- second: someone running our unit frames should get ours, and someone who
-- turned them off still gets a bar under the portrait.
local ANCHORS = {
    player = function() return (ns.UF and ns.UF.Frames and ns.UF.Frames.player) or _G.PlayerFrame end,
    target = function() return (ns.UF and ns.UF.Frames and ns.UF.Frames.target) or _G.TargetFrame end,
    focus  = function() return (ns.UF and ns.UF.Frames and ns.UF.Frames.focus) or _G.FocusFrame end,
}

local function followCursor(frame, elapsed)
    frame._cursorWait = (frame._cursorWait or 0) + elapsed
    if frame._cursorWait < 0.02 then return end
    frame._cursorWait = 0
    local bar = CM.Bar(frame.barKey)
    if not bar then return end
    local x, y = GetCursorPosition()
    local s = frame:GetEffectiveScale()
    if not (x and s and s > 0) then return end
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / s + (bar.x or 0), y / s + (bar.y or 0))
end

function CM.ApplyAnchor(key)
    local frame = CM.frames[key]
    local bar = CM.Bar(key)
    if not (frame and bar) then return end
    local to = bar.anchorTo or "screen"

    if to ~= "cursor" then frame:SetScript("OnUpdate", nil) end

    if to == "screen" then
        ns:ApplyMover(frame.mover)
        return
    end
    if to == "cursor" then
        frame:SetScript("OnUpdate", followCursor)
        return
    end

    local get = ANCHORS[to]
    local target = get and get()
    if not target then
        -- The frame this bar wanted is not on screen -- the target frame with
        -- no target, our unit frames switched off. Falling back to the screen
        -- keeps the bar somewhere findable instead of nowhere.
        ns:ApplyMover(frame.mover)
        return
    end
    if bar.scale then frame:SetScale(bar.scale) end
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", target, "CENTER", bar.ax or 0, bar.ay or 0)
end

-- A drop, a nudge, an Edit Mode move. The mover writes a SCREEN position; an
-- attached bar wants the same place written as an offset from the thing it
-- hangs off, so the two are one point in two coordinate systems and the
-- conversion happens here.
--
-- Called only when the player moved the bar -- never from a plain re-apply,
-- which would read a screen position the attached bar is not at and walk it
-- across the screen one settings change at a time.
function CM.OnMoved(key)
    local frame = CM.frames[key]
    local bar = CM.Bar(key)
    if not (frame and bar) then return end
    local to = bar.anchorTo or "screen"
    if to == "screen" then return end
    local x, y = bar.x or 0, bar.y or 0
    if to == "cursor" then
        -- Offsets from the cursor are exactly what x and y already are once
        -- the cursor is the origin; the follow script adds them every frame.
        return
    end
    local get = ANCHORS[to]
    local target = get and get()
    if not target then return end
    local tx, ty = target:GetCenter()
    local ux, uy = UIParent:GetCenter()
    if not (tx and ux) then return end
    local ts = (target:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
    local fs = frame:GetScale() or 1
    if fs <= 0 then fs = 1 end
    bar.ax = ((ux + x) - tx * ts) / fs
    bar.ay = ((uy + y) - ty * ts) / fs
    CM.ApplyAnchor(key)
end

-- ---------------------------------------------------------------- paint --

-- The active phase: while the buff this row watches is on the player, the icon
-- shows the BUFF running out, not the cooldown coming back. Auras are closed
-- to addon code in combat on this client (they throw rather than come back
-- secret), so this is asked only when they are open -- in a fight the icon
-- falls back to its cooldown, which is the honest thing to show.
local function activeAura(spellID)
    if ns.AurasRestricted() then return nil end
    if not (C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID) then return nil end
    local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellID)
    if not ok or type(aura) ~= "table" then return nil end
    local duration
    if C_UnitAuras.GetAuraDuration and type(aura.auraInstanceID) ~= "nil" then
        local okd, d = pcall(C_UnitAuras.GetAuraDuration, "player", aura.auraInstanceID)
        if okd then duration = d end
    end
    return aura, duration
end

-- The cooldown of one row, spell or item, as a duration object when the client
-- offers one and as a plain start/duration pair when it does not.
-- Second return value: "the swipe is already set, leave it alone". An item on
-- a client without the duration object still has a start and a length, and a
-- caller that cleared the widget after we set it would wipe the swipe we had
-- just drawn.
local function applyCooldown(icon, entry)
    local cd = icon.cooldown
    -- A slot row answers with the item worn in it; from here on it IS an item.
    local rid, rkind = CM.Resolve(entry)
    if rid and rkind ~= entry.kind then entry = { id = rid, kind = rkind } end
    if entry.kind == "item" then
        local getter = C_Item and C_Item.GetItemCooldown
        if getter then
            local ok, start, dur = pcall(getter, entry.id)
            if ok and ns.CanRead(start) and type(start) == "number" then
                pcall(cd.SetCooldown, cd, start, dur)
                return nil, true
            end
        end
        return nil, false
    end
    return C_Spell.GetSpellCooldownDuration and C_Spell.GetSpellCooldownDuration(entry.id), false
end

-- The texts in the corners. All three are plain data about our own character
-- and our own bags, and the one that is not -- an aura's stack count -- is
-- formatted by the engine rather than read.
local function paintTexts(bar, icon, entry, aura)
    if CM.Val(bar, entry, "showKeybind") == true then
        icon.keybind:SetText(CM.Bindings.For(entry) or "")
    else
        icon.keybind:SetText("")
    end

    if CM.Val(bar, entry, "showCount") ~= false then
        if entry.kind == "item" then
            local ok, n = pcall(C_Item.GetItemCount, entry.id)
            local readable = ok and ns.CanRead(n) and type(n) == "number"
            icon.count:SetText((readable and n > 1) and tostring(n) or "")
        elseif type(aura) == "table" then
            local ok = pcall(function()
                icon.count:SetFormattedText("%d", aura.applications)
            end)
            if not ok then icon.count:SetText("") end
        else
            icon.count:SetText("")
        end
    else
        icon.count:SetText("")
    end
end

-- One icon's live state. Every value here may be secret and none is read.
local function paintIcon(bar, icon, entry)
    local b = icon.button
    -- The tooltip, the texture and the cooldown all want what the row POINTS
    -- AT, which for an equipment slot is whatever is worn in it right now.
    local rid, rkind = CM.Resolve(entry)
    b._spellID = rid
    b._kind = rkind
    b:Show()

    local tex
    if rid == nil then
        tex = nil
    elseif rkind == "item" then
        tex = C_Item.GetItemIconByID and C_Item.GetItemIconByID(rid)
    else
        tex = C_Spell.GetSpellTexture(rid)
    end
    -- An empty equipment slot draws the slot's own empty art rather than the
    -- last item that was in it.
    if rid == nil and entry.kind == "slot" then
        icon.texture:SetTexture("Interface\\PaperDoll\\UI-PaperDoll-Slot-Trinket")
    elseif type(tex) ~= "nil" then
        icon.texture:SetTexture(tex)
    end

    icon.readySound = CM.SoundPath(CM.Val(bar, entry, "readySound"))

    -- The active phase wins over the cooldown: a buff that is running is what
    -- the row is about while it lasts.
    local aura, auraDuration
    if entry.activePhase then aura, auraDuration = activeAura(entry.id) end
    local active = type(auraDuration) ~= "nil"

    local duration, kept = auraDuration, false
    if not active then duration, kept = applyCooldown(icon, entry) end
    local isZero

    if type(duration) ~= "nil" and icon.cooldown.SetCooldownFromDurationObject then
        -- Protected function on this client. On our own frame it should be
        -- ours to call, but "should" is not "does": a refusal must not take
        -- the rest of the icon down with it.
        pcall(icon.cooldown.SetReverse, icon.cooldown, active and true or false)
        pcall(icon.cooldown.SetCooldownFromDurationObject, icon.cooldown, duration)
        local binding = ensureBinding(icon)
        if binding then
            binding:SetDuration(duration)
        else
            driveText(icon, duration)
        end
        isZero = duration.IsZero and duration:IsZero()
    elseif not kept then
        pcall(icon.cooldown.Clear, icon.cooldown)
        if icon.binding then icon.binding:SetDuration(nil) else driveText(icon, nil) end
    end

    -- Dim while it runs. IsZero is a secret boolean; FoldValue picks a
    -- number from it without ever looking, and SetDesaturation takes the
    -- result. Ready is 0, running is 1.
    if type(isZero) ~= "nil" and CM.Val(bar, entry, "desaturateOnCooldown") and not active then
        icon.texture:SetDesaturation(ns.FoldValue(isZero, 0, 1))
    else
        icon.texture:SetDesaturation(0)
    end

    -- The countdown colour, and the threshold that may repaint it. The plain
    -- colour goes on first, so a client that will not answer the threshold
    -- question leaves a correctly coloured number behind rather than none.
    local cc = bar.countdownColor
    icon.countdown:SetTextColor(cc.r, cc.g, cc.b)
    local seconds = entry.thresholdTime
    if type(seconds) == "number" and seconds > 0 and type(duration) ~= "nil" then
        local low = belowThreshold(duration, seconds)
        if type(low) ~= "nil" then
            local tc = entry.thresholdColor or { r = 1, g = 0.3, b = 0.3 }
            icon.countdown:SetTextColor(ns.FoldColor(low, tc.r, tc.g, tc.b, cc.r, cc.g, cc.b))
        end
    end

    -- The border takes the active colour while the buff runs, so the phase is
    -- readable at a glance and not only from the swipe direction.
    if active and entry.activeColor and icon.borderColor then
        local ac = entry.activeColor
        if icon.shaped:IsShown() then
            icon.shaped:SetVertexColor(ac.r, ac.g, ac.b, icon.borderColor.a)
        else
            ns.LayoutEdges(icon.edges, icon.button, bar.borderSize or 0,
                ac.r, ac.g, ac.b, icon.borderColor.a, tonumber(bar.borderInset) or 0)
        end
    end

    -- Glows. The main slot answers, in this order, to the active phase, to a
    -- stack count and to being ready; the proc slot is the client's own event
    -- and is set from there, never here.
    local glowType = CM.Val(bar, entry, "glowType") or "pixel"
    local glowColor = entry.glowColor or bar.glowColor
    local stackGlow = tonumber(CM.Val(bar, entry, "stackGlow")) or 0
    if active and entry.activeGlow then
        CM.Glow.Set(icon, "main", glowType, entry.activeColor or glowColor, true)
    elseif stackGlow > 0 and type(aura) == "table" then
        -- A stack count is readable exactly when the aura was, which is the
        -- same gate activeAura already passed -- so this comparison is safe.
        local ok, n = pcall(function() return aura.applications end)
        local readable = ok and ns.CanRead(n) and type(n) == "number"
        CM.Glow.Set(icon, "main", glowType, glowColor, (readable and n >= stackGlow) or false)
    elseif CM.Val(bar, entry, "readyGlow") and type(isZero) ~= "nil" then
        CM.Glow.Set(icon, "main", glowType, glowColor, isZero)
    else
        CM.Glow.Set(icon, "main", "none")
    end

    -- Charges. The count is secret in combat, and a font string takes one as
    -- long as the engine does the formatting.
    local chargeMode = entry.chargeMode or (CM.Val(bar, entry, "showCharges") ~= false and "count" or "none")
    icon.charges:SetShown(chargeMode ~= "none")
    -- Charges are a SPELL thing. An item row has none, and a slot row is an
    -- item once it is resolved -- asking the client for the charges of the
    -- number 13 is a question about nothing.
    if chargeMode ~= "none" and entry.kind == "spell" then
        -- In combat this comes back as a SECRET TABLE, and reading a field of
        -- one throws -- type() says "table" either way, so the guard has to be
        -- the pcall, not the type check.
        local ok = pcall(function()
            local charges = C_Spell.GetSpellCharges(entry.id)
            if type(charges) ~= "table" then return end
            icon.charges:SetFormattedText("%d", charges.currentCharges)
        end)
        if not ok then icon.charges:SetText("") end
    else
        icon.charges:SetText("")
    end

    paintTexts(bar, icon, entry, aura)
end

-- The live half: what each row shows right now. Takes any frame that went
-- through CM.StyleFrame, so the preview ticks along with the real bars.
function CM.PaintFrame(frame, bar, list, owned)
    local count = math.min(#list, CM.MAX_ICONS)
    owned = owned or count
    frame.ownedCount = owned

    for i = 1, count do
        local icon = frame.icons[i]
        if icon then
            paintIcon(bar, icon, list[i])
            -- A borrowed icon is a stand-in, not a setting: half strength, and
            -- it answers no mouse.
            local borrowed = i > owned
            icon.button:SetAlpha(borrowed and 0.45 or 1)
            icon.button:EnableMouse(not borrowed)
        end
    end
    for i = count + 1, #frame.icons do
        frame.icons[i].button:Hide()
        frame.icons[i].button._spellID = nil
    end
end

function CM.Refresh(key)
    local frame = CM.frames[key]
    local bar = CM.Bar(key)
    if not frame or not bar then return end
    local list, owned = CM.Display(bar, key)
    CM.PaintFrame(frame, bar, list, owned)
end

-- ---------------------------------------------------------------- procs --

-- The client tells us which spell lit up. The id it hands over may itself be
-- secret in a fight, and a secret cannot be compared with anything -- so a
-- proc we cannot place is a proc we ignore, rather than one we guess at.
function CM.SetProc(spellID, on)
    if not ns.CanRead(spellID) or type(spellID) ~= "number" then return end
    local db = CM.db()
    for _, key in ipairs(db.barOrder or {}) do
        local frame, bar = CM.frames[key], CM.Bar(key)
        if frame and bar then
            local list = CM.Display(bar, key)
            for i = 1, math.min(#list, #frame.icons) do
                local entry = list[i]
                if entry.id == spellID and CM.Val(bar, entry, "procGlow") then
                    CM.Glow.Set(frame.icons[i], "proc", "proc",
                        entry.glowColor or bar.glowColor, on and true or false)
                end
            end
        end
    end
end

-- ---------------------------------------------------------------- visible --

-- The extra conditions. Every one that is switched on must hold, so "in an
-- instance" plus "no target" means both at once, which is what a list of
-- checkboxes reads as.
CM.CONDS = {
    { key = "instance", label = "In an instance",    test = function() return (IsInInstance()) end },
    { key = "raid",     label = "In a raid",         test = function() return IsInRaid() end },
    { key = "group",    label = "In a group",        test = function() return IsInGroup() end },
    { key = "solo",     label = "On your own",       test = function() return not IsInGroup() end },
    { key = "mounted",  label = "Mounted",           test = function() return IsMounted() end },
    { key = "target",   label = "With a target",     test = function() return UnitExists("target") end },
    { key = "notarget", label = "Without a target",  test = function() return not UnitExists("target") end },
    { key = "resting",  label = "Resting",           test = function() return IsResting() end },
}

-- A condition the client will not answer must not hide the bar: an unanswered
-- question is not a "no".
local function condHolds(cond)
    local ok, res = pcall(cond.test)
    if not ok or ns.IsSecret(res) then return true end
    return res and true or false
end

function CM.CondsPass(bar)
    local conds = bar.conds
    if type(conds) ~= "table" then return true end
    for _, cond in ipairs(CM.CONDS) do
        if conds[cond.key] and not condHolds(cond) then return false end
    end
    return true
end

function CM.UpdateVisibility(key)
    local frame = CM.frames[key]
    local bar = CM.Bar(key)
    if not frame or not bar then return end
    -- a switched-off module keeps its frames, and nothing drives them
    if not CM.mod.active and not CM.optionsOpen then frame:Hide(); return end
    if ns:IsEditModeActive() or CM.optionsOpen then
        frame:Show()
        frame:SetAlpha(bar.opacity or 1)
        return
    end
    if not bar.enabled then frame:Hide(); return end

    local vis = bar.visibility or "always"
    local shown = true
    if vis == "hidden" then shown = false
    elseif vis == "combat" then shown = ns:InCombat()
    elseif vis == "noncombat" then shown = not ns:InCombat() end
    if shown then shown = CM.CondsPass(bar) end
    frame:SetShown(shown)

    if shown then
        local alpha = bar.opacity or 1
        if bar.oocFade and not ns:InCombat() then alpha = bar.oocAlpha or 0.4 end
        frame:SetAlpha(alpha)
    end
end

-- The label used by the options and by Edit Mode for a bar that is attached to
-- something. Kept here because the anchor table is here.
function CM.AnchorValues()
    return {
        { value = "screen", text = L["The screen"] },
        { value = "player", text = L["The player frame"] },
        { value = "target", text = L["The target frame"] },
        { value = "focus",  text = L["The focus frame"] },
        { value = "cursor", text = L["The mouse cursor"] },
    }
end
