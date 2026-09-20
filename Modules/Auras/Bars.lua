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

local function applyLayout(container, kind, db)
    local dir = AnchorUtil and AnchorUtil.FlowDirection
    local size, pad = db.iconSize, padOf(kind, db)
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
    local size, pad = db.iconSize, padOf(kind, db)
    local w = perRow(kind, db) * (size + pad) - pad
    local h = rowsOf(kind, db) * (size + pad) - pad
    b.holder:SetSize(math.max(w, size), math.max(h, size))
    b.container:ClearAllPoints()
    b.container:SetAllPoints(b.holder)
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
    local size, pad = db.iconSize, padOf(kind, db)
    local opts = {
        maxFrameCount   = countFor(kind, db),
        sortDirection   = _G.AuraContainerSortDirection and _G.AuraContainerSortDirection.Normal,
        initializeFrame = A.Style.Initializer(kind, db),
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

function A.Build(mod)
    if not canBuild() then return false end
    local db = mod.db
    for _, kind in ipairs(KINDS) do
        local b = bars[kind]
        if not b then
            local holder = CreateFrame("Frame", "VuloForeverUI_Aura_" .. kind, UIParent)
            holder:SetSize(200, 40)
            b = { holder = holder }
            bars[kind] = b
            b.mover = ns:CreateMover(holder, {
                key      = "auras_" .. kind,
                label    = LABELS[kind],
                db       = db[kind],
                width    = 200,
                height   = 40,
                scalable = true,
            })
            ns:ApplyMover(b.mover)
        end
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
        applyLayout(b.container, kind, db)
        -- the scale is the mover's business (opts.scalable); setting it here
        -- as well would fight ApplyMover below
        b.holder:Show()
        b.container:Show()
        pcall(b.container.SetUnit, b.container, "player")
        ns:RefreshMoverGeometry(b.mover)
        ns:ApplyMover(b.mover)
    end
    return true
end

function A.Hide()
    teardown()
    for _, kind in ipairs(KINDS) do
        local b = bars[kind]
        if b then b.holder:Hide() end
    end
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
