-- VuloForeverUI / Modules / Auras / Bars
--
-- The player's own buff and debuff rows: two engine aura containers, one
-- holder each, placed with the house mover.
--
-- Not a single aura is read here. The client is told WHAT to show, as a filter
-- string it parses and evaluates in C, and it creates, filters, sorts and lays
-- out the buttons itself. We own the geometry and the styling (Style.lua),
-- nothing else.
--
-- Order matters and is not negotiable: create the container, add its group,
-- and only THEN SetUnit. A group added after the first parse renders nothing.
local _, ns = ...
ns.Auras = ns.Auras or {}
local A = ns.Auras

local KINDS = { "buffs", "debuffs" }
A.KINDS = KINDS

local bars = {}          -- kind -> { holder, container }
A.Bars = bars

local available          -- nil = not asked yet, false = this client cannot

local function canBuild()
    if available == nil then
        local ok, c = pcall(CreateFrame, "AuraContainer", nil, UIParent,
            "CustomAuraContainerTemplate")
        available = (ok and c) and true or false
        if c then c:Hide(); A._probe = c end   -- kept, not leaked onto UIParent
    end
    return available
end

A.CanBuild = canBuild

-- The client's own filter tokens, read from its own table rather than spelled
-- out here: AddAuraGroup asserts the string is valid, so one typo would cost
-- the whole container.
local function filterFor(kind)
    local F = AuraUtil and AuraUtil.AuraFilters or {}
    return kind == "buffs" and (F.Helpful or "HELPFUL") or (F.Harmful or "HARMFUL")
end

-- How many buttons the container may ever show. Rows are a display limit, so
-- the smaller of the two wins -- a max of 32 over two rows of eight is eight
-- icons and sixteen invisible ones otherwise.
local function countFor(kind, db)
    if kind == "buffs" then
        return math.min(db.maxBuffs, db.perRowBuffs * db.rowsBuffs)
    end
    return math.min(db.maxDebuffs, db.perRowDebuffs * db.rowsDebuffs)
end

local function perRow(kind, db)
    return kind == "buffs" and db.perRowBuffs or db.perRowDebuffs
end

local function rowsOf(kind, db)
    return kind == "buffs" and db.rowsBuffs or db.rowsDebuffs
end

local function padOf(kind, db)
    return kind == "buffs" and db.paddingBuffs or db.paddingDebuffs
end

-- ---------------------------------------------------------------------------
-- Geometry
-- ---------------------------------------------------------------------------

-- FlowDirection is Left/Right/Up/Down, and the padding setter wants all four
-- sides as numbers -- a single argument would throw. The anchor point is a
-- CORNER: anchoring elements to a mid-edge starts the row at the container's
-- centre instead of filling it.
local CORNER = {
    rightdown = "TOPLEFT",  leftdown = "TOPRIGHT",
    rightup   = "BOTTOMLEFT", leftup  = "BOTTOMRIGHT",
}

-- Icon size and spacing on whole physical pixels of the holder, so every icon
-- and every border edge starts on a pixel and all four sides come out equal.
local function snapped(kind, db, frame)
    local size = math.max(ns:Pixel(frame, 1), ns:PixelSnap(db.iconSize, frame))
    return size, ns:PixelSnap(padOf(kind, db), frame)
end

local function applyLayout(container, kind, db, holder)
    local dir = AnchorUtil and AnchorUtil.FlowDirection
    local size, pad = snapped(kind, db, holder)
    if container.SetFlowLayoutPadding then
        pcall(container.SetFlowLayoutPadding, container, 0, 0, 0, 0)
    end
    if dir and container.SetFlowLayoutGrowthDirection then
        pcall(container.SetFlowLayoutGrowthDirection, container,
            db.growthX == "left" and dir.Left or dir.Right,
            db.growthY == "up"   and dir.Up   or dir.Down)
    end
    if container.SetFlowLayoutAnchorPoint then
        pcall(container.SetFlowLayoutAnchorPoint, container,
            CORNER[db.growthX .. db.growthY] or "TOPLEFT")
    end
    if container.SetFlowLayoutMaximumLineSize then
        pcall(container.SetFlowLayoutMaximumLineSize, container,
            perRow(kind, db) * (size + pad))
    end
end

-- The holder is what the mover grabs, so it has to be the size of the block of
-- icons -- not 1x1, which would leave a drag box the size of a pixel.
local function sizeHolder(kind, db)
    local b = bars[kind]
    if not b then return end
    local size, pad = snapped(kind, db, b.holder)
    local w = perRow(kind, db) * (size + pad) - pad
    local h = rowsOf(kind, db) * (size + pad) - pad
    b.holder:SetSize(math.max(w, size), math.max(h, size))
end

-- The holder sits wherever the mover put it, usually between two pixels. The
-- container is anchored at the corner the icons grow from, moved by the
-- fraction of a pixel that puts that corner on the grid.
local function placeContainer(kind)
    local b = bars[kind]
    if not (b and b.container and b.db) then return end
    local holder, db = b.holder, b.db
    local corner = CORNER[(db.growthX or "right") .. (db.growthY or "down")] or "TOPLEFT"
    local px = ns:Pixel(holder, 1)
    local l, r, t, bt = holder:GetLeft(), holder:GetRight(), holder:GetTop(), holder:GetBottom()
    local dx, dy = 0, 0
    if l and r and t and bt and px > 0 then
        local x = corner:find("LEFT") and l or r
        local y = corner:find("TOP") and t or bt
        dx = (math.floor(x / px + 0.5) - x / px) * px
        dy = (math.floor(y / px + 0.5) - y / px) * px
    end
    -- Kept for the weapon enchants (Enchants.lua), which start the buff row
    -- from the same corner on the same pixel grid.
    b.corner, b.dx, b.dy = corner, dx, dy
    -- The enchants take the first places of the buff row, so the buffs start
    -- that many places further in -- and their rows are as much shorter, so
    -- the block keeps to its box.
    local used = (kind == "buffs" and A.EnchantSlots) and A.EnchantSlots() or 0
    local size, pad = snapped(kind, db, holder)
    local shift = used * (size + pad)
    if corner:find("RIGHT") then shift = -shift end
    if b.container.SetFlowLayoutMaximumLineSize then
        pcall(b.container.SetFlowLayoutMaximumLineSize, b.container,
            math.max(1, perRow(kind, db) - used) * (size + pad))
    end
    b.container:ClearAllPoints()
    b.container:SetPoint(corner, holder, corner, dx + shift, dy)
    b.container:SetSize(holder:GetWidth(), holder:GetHeight())
    if kind == "buffs" and A.PlaceEnchants then A.PlaceEnchants() end
end
A.PlaceContainer = placeContainer

-- Re-placed after every move, resize or rescale of the holder; one frame
-- later, when the new position can be read back.
local function watchHolder(kind)
    local b = bars[kind]
    if b.watched then return end
    b.watched = true
    local queued
    local function queue()
        if queued then return end
        queued = true
        C_Timer.After(0, function() queued = false; placeContainer(kind) end)
    end
    hooksecurefunc(b.holder, "SetPoint", queue)
    hooksecurefunc(b.holder, "SetSize", queue)
    hooksecurefunc(b.holder, "SetScale", function()
        queue()
        -- the borders were measured in pixels of the old scale
        if b.builtScale and b.holder:GetEffectiveScale() ~= b.builtScale and A.QueueRebuild then
            A.QueueRebuild()
        end
    end)
end

-- ---------------------------------------------------------------------------
-- Building
-- ---------------------------------------------------------------------------
local LABELS = {
    buffs   = "|cffffffffBUFFS|r",
    debuffs = "|cffffffffDEBUFFS|r",
}

local function newContainer(holder, kind, db)
    local ok, c = pcall(CreateFrame, "AuraContainer", nil, holder,
        "CustomAuraContainerTemplate")
    if not ok or not c then return nil end
    local size, pad = snapped(kind, db, holder)
    local opts = {
        maxFrameCount   = countFor(kind, db),
        sortDirection   = _G.AuraContainerSortDirection and _G.AuraContainerSortDirection.Normal,
        initializeFrame = A.Style.Initializer(kind, db, holder),
        layout = { elementWidth = size, elementHeight = size,
                   elementSpacing = pad, lineSpacing = pad },
    }
    if not pcall(c.AddAuraGroup, c, "all", filterFor(kind), opts) then return nil end
    return c
end

-- A settings change means NEW containers: the initialiser is handed to the
-- engine once per group and the buttons it already made belong to the engine
-- from then on. Nothing here reaches into a live button.
local function teardown()
    for _, kind in ipairs(KINDS) do
        local b = bars[kind]
        if b then
            if b.container then
                pcall(b.container.SetUnit, b.container, "none")
                b.container:Hide()
                b.container:SetParent(nil)
            end
            b.container = nil
        end
    end
end

-- True once both containers stand, so a loading screen can put the rows back
-- without tearing down the ones that are already there.
function A.IsBuilt()
    for _, kind in ipairs(KINDS) do
        if not (bars[kind] and bars[kind].container) then return false end
    end
    return true
end

-- ---------------------------------------------------------------------------
-- Home: beside the minimap
--
-- A block nobody has moved stands at its home: the buffs with their top-right
-- corner at the minimap's top-left, the debuffs under them, right edges flush. Home is worked out from where the minimap stands NOW and
-- written back as the mover's centre offset, so the editor, a nudge and the
-- layouts all see the real place. Once the player drags a block it counts as
-- moved and stays where it was put; a reset in the editor sends it home again.
-- ---------------------------------------------------------------------------
local HOME_GAP = 10
local CHAIN = { "buffs", "debuffs" }

local holders = {}       -- key -> { holder, mover, pos }, one per block
A.Holders = holders
local homeOf = {}        -- key -> { x, y } of its home on the last pass
local placing            -- set while the homes are laid, so their own moves are not "moved"
local queueHomes         -- forward

local function moverChanged(key)
    local h = holders[key]
    if not h then return end
    local pos = h.pos
    if ns._inMoverReset then
        pos.moved = nil
    elseif not placing then
        -- no home measured yet: the first build is still putting it together
        local home = homeOf[key]
        if home and pos.x then
            pos.moved = (math.abs(pos.x - home[1]) > 1 or math.abs((pos.y or 0) - home[2]) > 1) or nil
        end
    end
    -- a block under this one may have to follow it
    if not placing then queueHomes() end
end

-- The frame a block hangs under, and at which of its points.
local function homeParent(key)
    for i = #CHAIN, 1, -1 do
        if CHAIN[i] == key then
            for j = i - 1, 1, -1 do
                local h = holders[CHAIN[j]]
                if h and h.holder:IsShown() then return h.holder, "BOTTOMRIGHT", 0, -HOME_GAP end
            end
            break
        end
    end
    local mm = _G.MinimapCluster
    if mm and mm:GetLeft() then return mm, "TOPLEFT", -HOME_GAP, -HOME_GAP end
    return UIParent, "TOPRIGHT", -200, -HOME_GAP
end

local function placeHomes()
    placing = true
    for _, key in ipairs(CHAIN) do
        local h = holders[key]
        if h and h.holder:IsShown() and not h.pos.moved and not ns:GetMoverLink(h.mover.key) then
            local rel, relPoint, x, y = homeParent(key)
            h.holder:ClearAllPoints()
            h.holder:SetPoint("TOPRIGHT", rel, relPoint, x, y)
            local cx, cy = ns:GetCenterOffsets(h.holder)
            if cx then
                h.pos.x, h.pos.y = cx, cy
                homeOf[key] = { cx, cy }
            end
            ns:ApplyMover(h.mover)
        end
    end
    placing = false
end
A.PlaceHomes = placeHomes

local homesQueued
queueHomes = function()
    if homesQueued then return end
    homesQueued = true
    C_Timer.After(0, function()
        homesQueued = false
        placeHomes()
    end)
end

-- The minimap is laid out again at login, after a loading screen and whenever
-- the editor moves it; the blocks still at home go with it.
local minimapHooked
local function hookMinimap()
    if minimapHooked or not _G.MinimapCluster then return end
    minimapHooked = true
    hooksecurefunc(_G.MinimapCluster, "SetPoint", queueHomes)
    hooksecurefunc(_G.MinimapCluster, "SetScale", queueHomes)
end

-- One holder and its mover per block, made once; `pos` follows the profile.
function A.EnsureHolder(key, label, pos)
    local h = holders[key]
    if not h then
        local holder = CreateFrame("Frame", "VuloForeverUI_Aura_" .. key, UIParent)
        holder:SetSize(200, 40)
        h = { holder = holder }
        h.mover = ns:CreateMover(holder, {
            key      = "auras_" .. key,
            label    = label,
            db       = pos,
            width    = 200,
            height   = 40,
            scalable = true,
            onMove   = function() moverChanged(key) end,
        })
        holders[key] = h
    end
    h.pos = pos
    h.mover.opts.db = pos
    hookMinimap()
    return h
end

function A.Build(mod)
    if not canBuild() then return false end
    local db = mod.db
    for _, kind in ipairs(KINDS) do
        local b = bars[kind]
        if not b then
            local h = A.EnsureHolder(kind, LABELS[kind], db[kind])
            b = { holder = h.holder, mover = h.mover }
            bars[kind] = b
            ns:ApplyMover(b.mover)
        end
        A.EnsureHolder(kind, LABELS[kind], db[kind])
        b.db = db
        b.builtScale = b.holder:GetEffectiveScale()
        watchHolder(kind)
        b.container = newContainer(b.holder, kind, db)
        if not b.container then
            -- NOT `available = false`: the widget itself answered for this
            -- client in canBuild(). A group that would not take is a bad
            -- setting or a bad profile, and switching auras off for the rest
            -- of the session over one of those leaves no way back but a
            -- reload.
            return false
        end
        sizeHolder(kind, db)
        placeContainer(kind)
        applyLayout(b.container, kind, db, b.holder)
        -- the scale is the mover's business (opts.scalable); setting it here
        -- as well would fight ApplyMover below
        b.holder:Show()
        b.container:Show()
        pcall(b.container.SetUnit, b.container, "player")
        ns:RefreshMoverGeometry(b.mover)
        ns:ApplyMover(b.mover)
        placeContainer(kind)
    end
    if A.BuildEnchants then A.BuildEnchants(mod) end
    placeHomes()
    return true
end

function A.Hide()
    teardown()
    for _, kind in ipairs(KINDS) do
        local b = bars[kind]
        if b then b.holder:Hide() end
    end
    if A.HideEnchants then A.HideEnchants() end
end

-- A setting changed: the containers are thrown away and made again. The
-- POLICY -- whether we build at all, and what happens to Blizzard's rows --
-- belongs to the module (Auras.lua), which is why this only does the work.
A.Teardown = teardown

-- Runs `fn` now, or at the end of the fight. Building a container and hiding
-- the client's frames are both things combat refuses.
function A.WhenSafe(fn)
    if not ns:InCombat() then fn(); return end
    if A._pending then return end
    A._pending = true
    ns:RegisterEventOnce("PLAYER_REGEN_ENABLED", function()
        A._pending = nil
        fn()
    end)
end

-- ---------------------------------------------------------------------------
-- Blizzard's own rows
--
-- Not hidden with Hide() alone: the client's own update paths and Edit Mode
-- show them again. They are SILENCED -- events off -- and kept hidden, the same
-- recipe the unit frames use. Both frames are the client's, so the work waits
-- for the end of combat.
-- ---------------------------------------------------------------------------
local silenced = {}

local function keepHidden(frame)
    if frame._vfuiKeepHidden then return end
    frame._vfuiKeepHidden = true
    hooksecurefunc(frame, "Show", function(self)
        if silenced[self] then C_Timer.After(0, function() self:Hide() end) end
    end)
end

function A.SilenceBlizzard(on)
    if ns:InCombat() then
        ns:RegisterEventOnce("PLAYER_REGEN_ENABLED", function() A.SilenceBlizzard(on) end)
        return
    end
    for _, name in ipairs({ "BuffFrame", "DebuffFrame" }) do
        local f = _G[name]
        if f then
            if on then
                silenced[f] = true
                pcall(f.UnregisterAllEvents, f)
                pcall(f.Hide, f)
                keepHidden(f)
            else
                silenced[f] = nil
                -- Shown again, so "Later" on the reload prompt is not a
                -- session without any aura display at all. The events are
                -- gone until the next load either way.
                pcall(f.Show, f)
            end
        end
    end
end

-- True while our rows have taken Blizzard's place, so the short-duration hook
-- knows there is nothing of Blizzard's left to shorten.
function A.BlizzardSilenced()
    local f = _G.BuffFrame
    return f ~= nil and silenced[f] == true
end
