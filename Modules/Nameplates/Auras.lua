-- VuloForeverUI / Modules / Nameplates / Auras
--
-- Auras on a plate: three engine containers per unit -- debuffs, buffs, crowd
-- control.
--
-- Not a single aura is read here. In combat C_UnitAuras throws at tainted code,
-- so instead the client is told WHAT to show, as a filter string it parses and
-- evaluates in C, and it creates, filters, sorts and lays out the buttons
-- itself. We own the geometry and the styling (AuraStyle.lua), nothing else.
--
-- Order matters and is not negotiable: create the container, add every group it
-- will ever have, and only THEN SetUnit. A group added after the first parse
-- renders nothing. Groups are never removed either; one that is switched off is
-- parked at a frame count of zero.
local _, ns = ...
local NP = ns.NP

local Auras = {}
NP.Auras = Auras

local KINDS = { "debuffs", "buffs", "cc" }
Auras.KINDS = KINDS

-- The client's own filter tokens, read from its own table rather than spelled
-- out here: AddAuraGroup asserts the string is valid, so one typo would cost
-- the whole container. "!" negates a component; INCLUDE_NAME_PLATE_ONLY is what
-- lets plate-flagged auras through at all and is the one token that cannot be
-- negated.
local F = AuraUtil and AuraUtil.AuraFilters or {}

local function filter(...)
    if AuraUtil and AuraUtil.CreateFilterString then
        return AuraUtil.CreateFilterString(...)
    end
    return table.concat({ ... }, "|")
end

local function filterFor(kind, db)
    local plate = F.IncludeNameplateOnly or "INCLUDE_NAME_PLATE_ONLY"
    local cc = F.CrowdControl or "CROWD_CONTROL"
    local harmful, helpful = F.Harmful or "HARMFUL", F.Helpful or "HELPFUL"
    if kind == "cc" then return filter(harmful, plate, cc) end
    if kind == "buffs" then
        -- "only dispellable" is pointless for a character who cannot dispel;
        -- the capability comes from the spellbook, never from an aura.
        if db.enemyBuffFilter == "dispellable" and NP.AuraStyle.CanDispelMagic() then
            return filter(helpful, plate, F.Dispellable or "DISPELLABLE")
        end
        return filter(helpful, plate, F.Important or "IMPORTANT")
    end
    if db.debuffIncludeCC then return filter(harmful, plate) end
    return filter(harmful, plate, "!" .. cc)
end

-- "Important only" is the client's own ranking, and that is the whole point: it
-- ranks auras we are not allowed to compare.
local function sortFor(kind, db)
    local m = _G.AuraContainerSortMethod
    if not m then return nil end
    if kind == "debuffs" and db.showAllDebuffs then return m.Default end
    return m.ImportantOnly
end

local function candidatesFor(kind, db)
    if kind ~= "debuffs" or db.showAllDebuffs then return {} end
    -- the client's own "would this show on a plate" rule, decided in C
    return { nameplateShowPersonal = true }
end

-- ---------------------------------------------------------------------------
-- Bundles: one holder plus the three containers, pooled together because
-- building a container is the expensive part.
-- ---------------------------------------------------------------------------
local free = {}
local available   -- nil = not asked yet, false = this client cannot

local probe

local function canBuild()
    if available == nil then
        local ok, c = pcall(CreateFrame, "AuraContainer", nil, UIParent,
            "CustomAuraContainerTemplate")
        available = (ok and c) and true or false
        if c then c:Hide(); probe = c end   -- kept, not leaked onto UIParent
    end
    return available
end

-- One size per kind, and it is the SLOT's size: the buttons, the layout
-- arithmetic and the wrap width must all agree or the row breaks in the wrong
-- place and the icons come out the wrong size.
local function sizeFor(kind)
    local slot = NP.SlotOfAura(kind)
    local cfg = slot ~= "none" and NP.db().iconSlots[slot]
    return cfg and cfg.size or 24
end

local function newContainer(holder, kind)
    local ok, c = pcall(CreateFrame, "AuraContainer", nil, holder, "CustomAuraContainerTemplate")
    if not ok or not c then return nil end
    local db = NP.db()
    local a = db.auras[kind]
    local size = sizeFor(kind)
    local opts = {
        maxFrameCount    = a.max,
        sortMethod       = sortFor(kind, db),
        sortDirection    = _G.AuraContainerSortDirection and _G.AuraContainerSortDirection.Normal,
        candidateFilters = candidatesFor(kind, db),
        initializeFrame  = NP.AuraStyle.Initializer(kind, size),
        layout = { elementWidth = size, elementHeight = size,
                   elementSpacing = a.spacing, lineSpacing = a.spacing },
    }
    if not pcall(c.AddAuraGroup, c, "main", filterFor(kind, db), opts) then return nil end
    return c
end

-- Adding a group makes the engine build TEN buttons on the spot, so a
-- container is only built for a kind that has somewhere to go. A slot switched
-- on later goes through Auras.Rebuild.
local function newBundle()
    if not canBuild() then return nil end
    local holder = CreateFrame("Frame", nil, UIParent)
    holder:SetSize(1, 1)
    local b, any = { holder = holder }, false
    for _, kind in ipairs(KINDS) do
        if NP.SlotOfAura(kind) ~= "none" then
            b[kind] = newContainer(holder, kind)
            if not b[kind] then return nil, "refused" end
            any = true
        end
    end
    -- "empty" is a setting, "refused" is a client that cannot do this at all.
    -- Confusing the two switched auras off for the rest of the session.
    if not any then return nil, "empty" end
    return b
end

-- ---------------------------------------------------------------------------
-- Geometry. Every slot pins its container to the plate and says which way the
-- icons grow from there; the sizes come from the settings, never from a getter.
-- ---------------------------------------------------------------------------
local SLOT_ANCHOR = {
    top      = { "BOTTOM", "TOP", 0, 1 },
    bottom   = { "TOP", "BOTTOM", 0, -1 },
    left     = { "RIGHT", "LEFT", -1, 0 },
    right    = { "LEFT", "RIGHT", 1, 0 },
    topleft  = { "BOTTOMLEFT", "TOPLEFT", 0, 1 },
    topright = { "BOTTOMRIGHT", "TOPRIGHT", 0, 1 },
}

-- Which way a slot's icons run when the setting says "auto": a single column
-- beside the bar, a row above or below it, the top-left row leftwards.
function Auras.AutoGrow(slot)
    if slot == "left" or slot == "right" then return "up" end
    if slot == "topleft" then return "left" end
    return "right"
end

-- The container's own anchor point for a grow direction: the slot's point,
-- with the edge ALONG the growth replaced by the one it grows away from. A
-- column set beside the bar by its middle would grow up and down at once;
-- pinned by its bottom edge it only grows up.
function Auras.ContainerPoint(slotPoint, grow)
    local v = slotPoint:match("^TOP") or slotPoint:match("^BOTTOM") or ""
    local h = slotPoint:match("LEFT$") or slotPoint:match("RIGHT$") or ""
    if grow == "up" then v = "BOTTOM" elseif grow == "down" then v = "TOP"
    elseif grow == "right" then h = "LEFT" elseif grow == "left" then h = "RIGHT" end
    local p = v .. h
    return p ~= "" and p or "CENTER"
end

-- The direction a kind's icons run and the point its container is pinned by.
-- "auto" keeps the slot's own point, so a row above the bar stays centred on
-- it as it always was. The settings preview asks the same function.
function Auras.GrowOf(setting, slot, slotPoint)
    if setting == "up" or setting == "down" or setting == "left" or setting == "right" then
        return setting, Auras.ContainerPoint(slotPoint, setting)
    end
    return Auras.AutoGrow(slot), slotPoint
end

-- FlowDirection is Left/Right/Up/Down, and the padding setter wants all four
-- sides as numbers -- a single argument would throw.
local function applyLayout(container, slot, grow, size, spacing, count)
    local dir = AnchorUtil and AnchorUtil.FlowDirection
    local column = grow == "up" or grow == "down"
    -- A row wraps downwards under the bar and upwards everywhere else.
    local down = grow == "down" or (not column and slot == "bottom")
    if container.SetFlowLayoutPadding then
        pcall(container.SetFlowLayoutPadding, container, 0, 0, 0, 0)
    end
    if dir and container.SetFlowLayoutGrowthDirection then
        local horizontal = (grow == "left") and dir.Left or dir.Right
        local vertical = down and dir.Down or dir.Up
        pcall(container.SetFlowLayoutGrowthDirection, container, horizontal, vertical)
    end
    if container.SetFlowLayoutAnchorPoint then
        -- a CORNER: anchoring elements to a mid-edge starts the row at the
        -- container's centre instead of filling it
        local corner = (down and "TOP" or "BOTTOM") .. ((grow == "left") and "RIGHT" or "LEFT")
        pcall(container.SetFlowLayoutAnchorPoint, container, corner)
    end
    if container.SetFlowLayoutMaximumLineSize then
        local perLine = column and 1 or count
        pcall(container.SetFlowLayoutMaximumLineSize, container, perLine * (size + spacing))
    end
end

function Auras.Layout(plate)
    local bundle = plate.auras
    if not bundle then return end
    local db = NP.db()
    bundle.holder:SetParent(plate)
    bundle.holder:ClearAllPoints()
    bundle.holder:SetPoint("CENTER", plate.health, "CENTER", 0, 0)

    for _, kind in ipairs(KINDS) do
        local container = bundle[kind]
        local slot = container and NP.SlotOfAura(kind) or "none"
        if container then container:ClearAllPoints() end
        if not container then                      -- nothing built for this kind
        elseif slot == "none" then
            container:Hide()
        else
            local cfg = db.iconSlots[slot]
            local anc = SLOT_ANCHOR[slot]
            local top = db.textSlots.Top
            local gap = 2
            if anc[4] > 0 and top.element ~= "none" then gap = top.size + 4 end
            local anchorTo = (slot == "bottom") and plate.cast or plate.health
            local a = db.auras[kind]
            local grow, point = Auras.GrowOf(a.grow, slot, anc[1])
            container:SetPoint(point, anchorTo, anc[2],
                anc[3] * 2 + cfg.x, anc[4] * gap + cfg.y)
            applyLayout(container, slot, grow, sizeFor(kind), a.spacing, a.max)
            container:Show()
        end
    end
end

-- ---------------------------------------------------------------------------
-- On and off a unit
-- ---------------------------------------------------------------------------
function Auras.Attach(plate)
    if plate.auras or not plate.unit or plate.friendly or not canBuild() then return end
    local bundle, why = table.remove(free)
    if not bundle then bundle, why = newBundle() end
    if not bundle then
        if why == "refused" then available = false end   -- stop asking
        return
    end
    plate.auras = bundle
    bundle.holder:Show()
    -- a pooled bundle carries the counts and filters of its last settings
    -- change; the plate's own ApplyAppearance ran before it had one
    Auras.ApplyAppearance(plate)
    for _, kind in ipairs(KINDS) do
        local c = bundle[kind]
        if c then pcall(c.SetUnit, c, plate.unit) end
    end
end

function Auras.Detach(plate)
    local bundle = plate.auras
    if not bundle then return end
    plate.auras = nil
    for _, kind in ipairs(KINDS) do
        -- the engine owns its buttons; letting go of the unit is how it is told
        local c = bundle[kind]
        if c then pcall(c.SetUnit, c, "none") end
    end
    -- hidden as a whole: the containers keep the points Layout gave them, and
    -- a SetUnit that was refused would leave icons hanging at the old spot
    bundle.holder:Hide()
    bundle.holder:SetParent(UIParent)
    bundle.holder:ClearAllPoints()
    free[#free + 1] = bundle
end

-- A settings change. Counts, filters and sorting are live setters; the button
-- STYLE is not, because a button may only be touched while it is being created
-- -- so a style change throws the bundles away (Auras.Rebuild) instead.
function Auras.ApplyAppearance(plate)
    local bundle = plate.auras
    if not bundle then return end
    local db = NP.db()
    for _, kind in ipairs(KINDS) do
        local c, a = bundle[kind], db.auras[kind]
        if c then
            local slot = NP.SlotOfAura(kind)
            pcall(c.SetAuraGroupMaxFrameCount, c, "main", slot == "none" and 0 or a.max)
            pcall(c.SetAuraGroupFilterString, c, "main", filterFor(kind, db))
            pcall(c.SetAuraGroupCandidateFilters, c, "main", candidatesFor(kind, db))
            local method = sortFor(kind, db)
            if method then
                pcall(c.SetAuraGroupSortMethod, c, "main", method,
                    _G.AuraContainerSortDirection and _G.AuraContainerSortDirection.Normal)
            end
            -- merged over the DEFAULTS, not over what is set, so every field we
            -- want kept has to be in this table
            local size = sizeFor(kind)
            pcall(c.SetAuraGroupLayout, c, "main", {
                elementWidth = size, elementHeight = size,
                elementSpacing = a.spacing, lineSpacing = a.spacing,
            })
        end
    end
    Auras.Layout(plate)
end

-- Style-level change. A button can only be styled while the engine is creating
-- it, so new styling means new buttons -- and the engine gives none of the old
-- ones back (it deliberately exposes no way to remove a group). Every rebuild
-- therefore costs real frames, which is why a slider drag is collapsed into a
-- single rebuild at the end instead of one per step.
local rebuildQueued

local function doRebuild()
    rebuildQueued = false
    if not NP.mod.active then return end
    for _, plate in pairs(NP.plates) do
        if plate.auras then Auras.Detach(plate) end
    end
    wipe(free)
    for _, plate in pairs(NP.plates) do Auras.Attach(plate) end
end

function Auras.Rebuild()
    if rebuildQueued then return end
    rebuildQueued = true
    C_Timer.After(0.35, doRebuild)
end

-- No CVars here on purpose. nameplateEnemyNpcAuraDisplay and its siblings only
-- drive SetShown on BLIZZARD's own aura list frames (Blizzard_NamePlateAuras.lua
-- UpdateEnemyNpcAuraFrames); nothing in the aura container or in C_UnitAuras
-- consults them. What we get is decided by the filter string alone, so writing
-- them would change a player's settings for no effect at all.
