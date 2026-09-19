-- Minimap button collector: one button on the rim opens a box that holds every other addon's minimap button.
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("minimapcollector", {
    name        = "Minimap Button Collector",
    group       = "Core",
    description = "Collects the other addons' minimap buttons in one box that opens from a single button on the minimap.",
    defaults = {
        enabled      = true,
        angle        = 250,     -- degrees on the minimap (0 = right, 90 = top, 180 = left, 270 = bottom)
        columns      = 4,       -- cells per row in the box
        includeOwn   = true,    -- our own minimap button goes into the box as well
        closeOnLeave = false,   -- close the box shortly after the mouse left it
        buttonSize   = 28,      -- cell size in the box; buttons are scaled to fit
    },
})

local OPENER_NAME = "VuloForeverUIMinimapCollector"
local TRAY_NAME   = "VuloForeverUIMinimapTray"
local OWN_BUTTON  = "VuloForeverUIMinimapButton"
local OWN_PREFIX  = "VuloForeverUI"
local ICON_PATH   = "Interface\\AddOns\\VuloForeverUI\\Media\\Icons\\infinity"

-- The icon library other addons bring along (we do not ship it). Both strings
-- are needed to FIND its buttons; nothing else here depends on it.
local ICONLIB_NAME   = "LibDBIcon-1.0"
local ICONLIB_PREFIX = "LibDBIcon10_"

local TRAY_GAP    = 4
local TRAY_PAD    = 6
local CLOSE_DELAY = 0.4     -- seconds the mouse may be away before closeOnLeave acts
local SWEEP_EVERY = 0.5     -- seconds between "is everything still in the box" checks

local opener, tray

-- ---------------------------------------------------------------------------
-- What is Blizzard's and must stay where it is
--
-- Taken from the 1.60.1 client source, Blizzard_Minimap (its TOC loads these
-- files for this client), not from memory:
--   Mainline/Minimap.xml:3    MinimapCluster
--   Mainline/Minimap.xml:195  Minimap
--   Mainline/Minimap.xml:240  MinimapBackdrop
--   Mainline/Minimap.xml:267  ExpansionLandingPageMinimapButton
--   Mainline/GameTime.xml:3           GameTimeFrame          (parent MinimapCluster)
--   Mainline/AddonCompartment.xml:3   AddonCompartmentFrame  (parent MinimapCluster)
-- The remaining names in Minimap.xml are textures and font strings
-- (MinimapZoneText :44, MiniMapMailIcon :113, MiniMapCraftingOrderIcon :167,
-- MinimapCompassTextureUnderlay :250, MinimapCompassTexture :258), which
-- GetChildren never returns. Minimap.lua creates no frame of its own and names
-- none beyond these.
local BLIZZ_NAMES = {
    MinimapCluster                    = true,
    Minimap                           = true,
    MinimapBackdrop                   = true,
    ExpansionLandingPageMinimapButton = true,
    GameTimeFrame                     = true,
    AddonCompartmentFrame             = true,
}

local BLIZZ_PREFIXES = {
    "Minimap", "MiniMap", "GameTime", "QueueStatus", "TimeManager", "Expansion", "AddonCompartment",
}

-- Everything else Blizzard puts there is unnamed and reached through a
-- parentKey (Minimap.xml:18-447). Unnamed frames are skipped anyway; this set
-- is the second lock, by identity, so a later rule change cannot open the door.
local blizzFrames

local function blizzFrameSet()
    if blizzFrames then return blizzFrames end
    blizzFrames = {}
    local function add(owner, ...)
        if not owner then return end
        for i = 1, select("#", ...) do
            local f = owner[(select(i, ...))]
            if type(f) == "table" then blizzFrames[f] = true end
        end
    end
    local cluster = MinimapCluster
    add(cluster, "GamepadHudBackground", "BorderTop", "ZoneTextButton", "Tracking", "IndicatorFrame",
        "MinimapContainer", "InstanceDifficulty", "GamepadButtons")
    add(cluster and cluster.IndicatorFrame, "MailFrame", "CraftingOrderFrame")
    add(cluster and cluster.MinimapContainer, "PlayerCoords")
    add(Minimap, "ZoomHitArea", "ZoomIn", "ZoomOut")
    return blizzFrames
end

local function isBlizzardName(name)
    if BLIZZ_NAMES[name] then return true end
    for i = 1, #BLIZZ_PREFIXES do
        local p = BLIZZ_PREFIXES[i]
        if name:sub(1, #p) == p then return true end
    end
    return false
end

-- ---------------------------------------------------------------------------
-- Side tables. Nothing is ever written into a foreign frame: what we know
-- about a button lives here, weak-keyed, and goes away with the button.
local weak = { __mode = "k" }
local records    = setmetatable({}, weak)   -- button -> where it came from (see snapshot)
local cells      = setmetatable({}, weak)   -- button -> { x, y, scale } inside the box
local placing    = setmetatable({}, weak)   -- button -> true while WE are the one calling SetPoint
local hooked     = setmetatable({}, weak)   -- button -> true once its methods carry our hooks
local dragHooked = setmetatable({}, weak)   -- button -> true once its drag start carries our hook
local order      = {}                       -- collected buttons in display order

local function iconLib()
    local stub = _G.LibStub
    if not (stub and stub.GetLibrary) then return nil end
    return stub(ICONLIB_NAME, true)
end

-- Anchors, parent, strata, level and scale at the moment of collection, so the
-- button can go back exactly where the addon that owns it had put it. Taken
-- once: a second collection must not overwrite it with the place in the box.
local function snapshot(b, libName)
    if records[b] then return records[b] end
    local pts = {}
    for i = 1, b:GetNumPoints() do pts[i] = { b:GetPoint(i) } end
    local rec = {
        parent  = b:GetParent(),
        points  = pts,
        strata  = b:GetFrameStrata(),
        level   = b:GetFrameLevel(),
        scale   = b:GetScale(),
        libName = libName,
    }
    records[b] = rec
    return rec
end

local function restore(b)
    local rec = records[b]
    if not rec then return end
    -- Out of the tables first: the SetPoint calls below then pass our hook
    -- untouched instead of being pulled back into a cell.
    records[b], cells[b] = nil, nil
    if rec.parent then pcall(b.SetParent, b, rec.parent) end
    pcall(b.SetScale, b, rec.scale or 1)
    b:ClearAllPoints()
    for _, p in ipairs(rec.points) do
        pcall(b.SetPoint, b, p[1], p[2], p[3], p[4], p[5])
    end
    if rec.strata then pcall(b.SetFrameStrata, b, rec.strata) end
    if rec.level then pcall(b.SetFrameLevel, b, rec.level) end

    -- The owner knows the current place better than a snapshot does: the icon
    -- library re-reads the saved angle, our own button its module setting.
    if rec.libName then
        local lib = iconLib()
        if lib and lib.Refresh then pcall(lib.Refresh, lib, rec.libName) end
    elseif b:GetName() == OWN_BUTTON then
        local own = ns.modules and ns.modules.minimap
        if own and own.UpdatePosition then pcall(own.UpdatePosition) end
    end
end

-- The one place that positions a collected button. Offsets are divided by the
-- button's scale because SetPoint reads them in the button's own units.
local function placeInCell(b)
    local c = cells[b]
    if not (c and tray) then return end
    placing[b] = true
    b:ClearAllPoints()
    b:SetPoint("CENTER", tray, "TOPLEFT", c.x / c.scale, c.y / c.scale)
    placing[b] = nil
end

local requestSync   -- forward declaration; defined with the scheduler below

-- Other libraries re-anchor their buttons whenever they refresh or while the
-- player drags one, and show or hide them on their own. A secure hook sees
-- each of those calls; the button is put back into its cell at once, which is
-- also what keeps a drag from carrying it out of the box.
local function hookButton(b)
    if hooked[b] then return end
    hooked[b] = true
    hooksecurefunc(b, "SetPoint", function(self)
        if placing[self] or not records[self] then return end
        if cells[self] then placeInCell(self) else requestSync() end
    end)
    local function visibilityChanged(self)
        if records[self] then requestSync() end
    end
    hooksecurefunc(b, "Show", visibilityChanged)
    hooksecurefunc(b, "Hide", visibilityChanged)
    hooksecurefunc(b, "SetShown", visibilityChanged)
end

-- A drag on an icon-library button runs an OnUpdate that writes a new angle
-- into its owner's settings every frame. The SetPoint hook already keeps the
-- button in its cell, but the saved angle would still drift, and the button
-- would come back somewhere else after a restore. Ending the drag the way the
-- library's own OnDragStop does prevents that. Only for buttons whose drag
-- code is known; others are held by the SetPoint hook and the sweep alone.
local function hookLibDrag(b)
    if dragHooked[b] or not (b.HasScript and b:HasScript("OnDragStart")) then return end
    dragHooked[b] = true
    b:HookScript("OnDragStart", function(self)
        if not records[self] then return end
        self:SetScript("OnUpdate", nil)
        if self.UnlockHighlight then self:UnlockHighlight() end
    end)
end

-- ---------------------------------------------------------------------------
-- Finding the buttons

local CLICK_SCRIPTS = { "OnClick", "OnMouseUp", "OnMouseDown" }

local function hasClickScript(f)
    for i = 1, #CLICK_SCRIPTS do
        local script = CLICK_SCRIPTS[i]
        if f:HasScript(script) and f:GetScript(script) then return true end
    end
    return false
end

-- found: button -> icon-library name, or false for a plain addon button
local function consider(f, found, libButtons)
    if found[f] ~= nil or f == opener or f == tray then return end
    if f.IsForbidden and f:IsForbidden() then return end
    if blizzFrameSet()[f] then return end

    local name = f:GetName()
    local libName = libButtons[f]
    if not libName and name and name:sub(1, #ICONLIB_PREFIX) == ICONLIB_PREFIX then
        libName = name:sub(#ICONLIB_PREFIX + 1)
    end

    if not libName then
        -- Unnamed and not from the icon library: map pins, tracking blips and
        -- the like. Never touched. Named pins are told by their numbering.
        if not name then return end
        if name == OWN_BUTTON then
            if not mod.db.includeOwn then return end
        elseif name:sub(1, #OWN_PREFIX) == OWN_PREFIX then
            return
        end
        if isBlizzardName(name) then return end
        if name:find("Pin%d+$") or name:find("Pins", 1, true) then return end
        if not (f:IsObjectType("Button") or f:IsObjectType("Frame")) then return end
        if not hasClickScript(f) then return end
        local w, h = f:GetWidth() or 0, f:GetHeight() or 0
        if w < 20 or w > 40 or h < 20 or h > 40 then return end
    end

    -- A protected child would make the box itself protected for the length of
    -- a fight, and then it could neither open nor close. Those stay outside.
    if f:IsProtected() then return end
    found[f] = libName or false
end

local function scanChildren(parent, found, libButtons)
    if not (parent and parent.GetChildren) then return end
    for _, child in ipairs({ parent:GetChildren() }) do
        consider(child, found, libButtons)
    end
end

local function findButtons()
    local found, libButtons = {}, {}

    -- The library's own list first: it carries the registration name that
    -- Refresh wants, and it still knows a button that was parented elsewhere.
    local lib = iconLib()
    if lib and lib.GetButtonList and lib.GetMinimapButton then
        local ok, names = pcall(lib.GetButtonList, lib)
        if ok and type(names) == "table" then
            for _, n in ipairs(names) do
                local b = lib:GetMinimapButton(n)
                if b then libButtons[b] = n end
            end
        end
    end
    for b in pairs(libButtons) do consider(b, found, libButtons) end

    scanChildren(Minimap, found, libButtons)
    scanChildren(MinimapBackdrop, found, libButtons)
    scanChildren(MinimapCluster, found, libButtons)
    -- Already collected ones are children of the box now, not of the minimap.
    scanChildren(tray, found, libButtons)
    return found
end

-- ---------------------------------------------------------------------------
-- The box

local function anchorTray()
    if not (tray and opener) then return end
    -- Beside the opener, on the side with more room; screen pixels on both
    -- sides of the comparison because minimap and UIParent may differ in scale.
    local ox, oy = opener:GetCenter()
    local os = opener:GetEffectiveScale() or 1
    local us = UIParent:GetEffectiveScale() or 1
    local midX = ((UIParent:GetLeft() or 0) + (UIParent:GetRight() or 0)) / 2 * us
    local midY = ((UIParent:GetBottom() or 0) + (UIParent:GetTop() or 0)) / 2 * us
    local toLeft = (ox or 0) * os > midX
    local upward = (oy or 0) * os < midY

    local v = upward and "BOTTOM" or "TOP"
    tray:ClearAllPoints()
    if toLeft then
        tray:SetPoint(v .. "RIGHT", opener, v .. "LEFT", -6, 0)
    else
        tray:SetPoint(v .. "LEFT", opener, v .. "RIGHT", 6, 0)
    end
end

local function createTray()
    if tray then return tray end

    tray = CreateFrame("Frame", TRAY_NAME, UIParent)
    tray:SetFrameStrata("DIALOG")
    tray:SetSize(2 * TRAY_PAD + 28, 2 * TRAY_PAD + 28)
    tray:SetClampedToScreen(true)
    tray:EnableMouse(true)      -- clicks between the cells must not reach the world
    ns.UI:StyleBackdrop(tray)
    ns.UI:CreateShadow(tray)
    tray:Hide()
    tinsert(UISpecialFrames, TRAY_NAME)  -- ESC closes

    tray.empty = tray:CreateFontString(nil, "OVERLAY")
    ns.UI.Font(tray.empty, 12)
    tray.empty:SetPoint("CENTER", 0, 0)
    tray.empty:SetTextColor(0.7, 0.7, 0.7)
    tray.empty:Hide()

    -- Runs only while the box is open; a hidden frame has no OnUpdate at all.
    local away, sweep = 0, 0
    tray:SetScript("OnShow", function() away, sweep = 0, 0 end)
    tray:SetScript("OnUpdate", function(self, elapsed)
        if mod.db.closeOnLeave then
            if self:IsMouseOver(4, -4, -4, 4) or (opener and opener:IsMouseOver()) then
                away = 0
            else
                away = away + elapsed
                if away >= CLOSE_DELAY then self:Hide(); return end
            end
        end
        -- A library that reparents instead of re-anchoring passes the SetPoint
        -- hook unseen. Twice a second is enough to bring such a button back.
        sweep = sweep + elapsed
        if sweep >= SWEEP_EVERY then
            sweep = 0
            for i = 1, #order do
                if order[i]:GetParent() ~= self then requestSync(); break end
            end
        end
    end)

    return tray
end

local function layoutTray()
    if not tray then return end
    local size = mod.db.buttonSize or 28
    local cols = math.max(1, mod.db.columns or 4)
    local step = size + TRAY_GAP
    local level = tray:GetFrameLevel() + 5

    local n = 0
    for i = 1, #order do
        local b = order[i]
        if b:GetParent() ~= tray then pcall(b.SetParent, b, tray) end
        -- Set outright, not inherited: several of these buttons pin their
        -- strata and level, and would otherwise sit underneath the box.
        b:SetFrameStrata(tray:GetFrameStrata())
        b:SetFrameLevel(level)
        -- A hidden button (switched off in its own addon) gets no cell, so the
        -- grid has no holes. Its Show hook asks for a new layout.
        if b:IsShown() then
            local extent = math.max(b:GetWidth() or 0, b:GetHeight() or 0)
            local scale = (extent > 0) and (size / extent) or 1
            b:SetScale(scale)
            local col, row = n % cols, math.floor(n / cols)
            cells[b] = {
                x = TRAY_PAD + col * step + size / 2,
                y = -(TRAY_PAD + row * step + size / 2),
                scale = scale,
            }
            placeInCell(b)
            n = n + 1
        else
            cells[b] = nil
        end
    end

    if n == 0 then
        tray.empty:SetText(L["No addon buttons found."])
        tray.empty:Show()
        tray:SetSize(tray.empty:GetStringWidth() + 4 * TRAY_PAD, 2 * TRAY_PAD + size)
        return
    end
    tray.empty:Hide()
    local usedCols = math.min(n, cols)
    local rows = math.ceil(n / cols)
    tray:SetSize(usedCols * size + (usedCols - 1) * TRAY_GAP + 2 * TRAY_PAD,
                 rows * size + (rows - 1) * TRAY_GAP + 2 * TRAY_PAD)
end

-- ---------------------------------------------------------------------------
-- Collect, or give everything back: one function for both directions, so the
-- deferred run after a fight does whatever is right by then.

local libHooked = false

local function hookIconLib()
    if libHooked then return end
    local lib = iconLib()
    if not (lib and lib.RegisterCallback) then return end
    libHooked = true
    -- There is no module-owned way to take this back out, so it stays and
    -- asks the module state instead.
    lib.RegisterCallback(mod, "LibDBIcon_IconCreated", function()
        if mod.active then requestSync() end
    end)
end

local function sync()
    -- Reparenting waits for the end of the fight; the registry hands the
    -- handler back by itself and refuses a second copy of it.
    if ns:InCombat() then
        ns:RegisterEventOnce("PLAYER_REGEN_ENABLED", sync)
        return
    end

    if not mod.active then
        for i = #order, 1, -1 do
            restore(order[i])
            order[i] = nil
        end
        return
    end

    hookIconLib()
    createTray()
    local found = findButtons()

    -- Whatever is no longer wanted (our own button after includeOwn went off)
    -- returns to its place before the grid is rebuilt.
    for i = #order, 1, -1 do
        local b = order[i]
        if found[b] == nil then restore(b) end
        order[i] = nil
    end

    local sortKey = {}
    for b, libName in pairs(found) do
        snapshot(b, libName or nil)
        hookButton(b)
        if libName then hookLibDrag(b) end
        sortKey[b] = (libName or b:GetName() or ""):lower()
        order[#order + 1] = b
    end
    -- By name, so the grid does not reshuffle from one login to the next.
    table.sort(order, function(a, b) return sortKey[a] < sortKey[b] end)

    layoutTray()
end

mod.Collect = sync

-- Several triggers tend to arrive in the same frame (a library creating ten
-- icons in a row); they collapse into one run on the next frame.
local syncQueued = false

function requestSync()
    if syncQueued then return end
    syncQueued = true
    C_Timer.After(0, function()
        syncQueued = false
        sync()
    end)
end

local function syncAfter(seconds)
    C_Timer.After(seconds, function()
        if mod.active then sync() end
    end)
end

-- ---------------------------------------------------------------------------
-- The opener

local function toggleTray()
    if not tray then createTray() end
    if tray:IsShown() then
        tray:Hide()
        return
    end
    sync()          -- catches whatever registered since the last sweep
    -- Opened in a fight before the first collection: sync has deferred itself,
    -- and with nothing to reparent the layout is safe and sizes the empty box.
    if #order == 0 then layoutTray() end
    anchorTray()
    tray:Show()
end

local function createOpener()
    if opener then return opener end

    -- Same recipe and sizes as our own minimap button (Mainline set: 31 button,
    -- 50 ring, 24 ground); only the icon is larger, because the logo is wide.
    opener = CreateFrame("Button", OPENER_NAME, Minimap)
    opener:SetSize(31, 31)
    opener:SetFrameStrata("MEDIUM")
    opener:SetFixedFrameStrata(true)
    opener:SetFrameLevel(8)
    opener:SetFixedFrameLevel(true)
    opener:RegisterForClicks("AnyUp")
    opener:RegisterForDrag("LeftButton")
    opener:SetMovable(true)
    opener:EnableMouse(true)

    opener.bg = opener:CreateTexture(nil, "BACKGROUND")
    opener.bg:SetSize(24, 24)
    opener.bg:SetPoint("CENTER", 0, 0)
    opener.bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")

    opener.icon = opener:CreateTexture(nil, "ARTWORK")
    opener.icon:SetSize(22, 22)
    opener.icon:SetPoint("CENTER", 0, 0)
    opener.icon:SetTexture(ICON_PATH)

    -- Press feedback: the icon rests 5% inset and fills out while the mouse
    -- is down, so a click is visible without a second texture.
    local function setPressed(pressed)
        local d = pressed and 0 or 0.05
        opener.icon:SetTexCoord(d, 1 - d, d, 1 - d)
    end
    setPressed(false)
    opener:SetScript("OnMouseDown", function() setPressed(true) end)
    opener:SetScript("OnMouseUp",   function() setPressed(false) end)

    opener.border = opener:CreateTexture(nil, "OVERLAY")
    opener.border:SetSize(50, 50)
    opener.border:SetPoint("TOPLEFT", 0, 0)
    opener.border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    opener:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    opener:SetScript("OnClick", function(_, mouseBtn)
        if mouseBtn == "LeftButton" then toggleTray() end
    end)

    opener:SetScript("OnDragStart", function(self)
        if IsShiftKeyDown() then
            self.isMoving = true
            self:SetScript("OnUpdate", mod.OnUpdatePosition)
        end
    end)
    opener:SetScript("OnDragStop", function(self)
        self.isMoving = false
        self:SetScript("OnUpdate", nil)
        -- the new rim position may have changed which side has more room
        if tray and tray:IsShown() then anchorTray() end
    end)

    -- A function, so the text follows a language switch without a reload.
    ns.UI:AttachTooltip(opener, function()
        return {
            anchor = "ANCHOR_LEFT",
            accent = true,
            title  = L["Minimap buttons"],
            lines  = {
                { L["Click: show or hide the collected buttons"], 1, 1, 1 },
                { L["Shift+drag: move this button"],              1, 1, 1 },
            },
        }
    end)

    return opener
end

-- The rim follows the minimap's actual size; 5 px past the half width puts the
-- ring half over the map edge, level with the other buttons of this recipe.
local RIM_OVERHANG = 5

local function edgeRadius(extent)
    return math.floor((extent or 140) / 2 + RIM_OVERHANG + 0.5)
end

-- GetMinimapShape is the convention minimap addons use to announce a square or
-- corner-cut map. Per quadrant (1 = top-right, going counter-clockwise):
-- true = round there (follow the circle), false = square there (push out to
-- the corner, clamped to the box).
local minimapShapes = {
    ["ROUND"]                 = { true,  true,  true,  true  },
    ["SQUARE"]                = { false, false, false, false },
    ["CORNER-TOPLEFT"]        = { false, false, false, true  },
    ["CORNER-TOPRIGHT"]       = { false, false, true,  false },
    ["CORNER-BOTTOMLEFT"]     = { false, true,  false, false },
    ["CORNER-BOTTOMRIGHT"]    = { true,  false, false, false },
    ["SIDE-LEFT"]             = { false, true,  false, true  },
    ["SIDE-RIGHT"]            = { true,  false, true,  false },
    ["SIDE-TOP"]              = { false, false, true,  true  },
    ["SIDE-BOTTOM"]           = { true,  true,  false, false },
    ["TRICORNER-TOPLEFT"]     = { false, true,  true,  true  },
    ["TRICORNER-TOPRIGHT"]    = { true,  false, true,  true  },
    ["TRICORNER-BOTTOMLEFT"]  = { true,  true,  false, true  },
    ["TRICORNER-BOTTOMRIGHT"] = { true,  true,  true,  false },
}

local function updatePosition()
    if not opener then return end
    local angle = math.rad(mod.db.angle or 250)
    local x, y, q = math.cos(angle), math.sin(angle), 1
    if x < 0 then q = q + 1 end
    if y > 0 then q = q + 2 end
    local shape = (_G.GetMinimapShape and _G.GetMinimapShape()) or "ROUND"
    local quads = minimapShapes[shape] or minimapShapes.ROUND
    local w = edgeRadius(Minimap:GetWidth())
    local h = edgeRadius(Minimap:GetHeight())
    if quads[q] then
        x, y = x * w, y * h
    else
        local diagW = math.sqrt(2 * w ^ 2) - 10
        local diagH = math.sqrt(2 * h ^ 2) - 10
        x = math.max(-w, math.min(x * diagW, w))
        y = math.max(-h, math.min(y * diagH, h))
    end
    opener:ClearAllPoints()
    opener:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

mod.UpdatePosition = updatePosition

function mod.OnUpdatePosition()
    if not opener or not opener.isMoving then return end
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    cx, cy = cx / scale, cy / scale
    -- Angle in degrees (0 = right, mathematical), kept in 0..360 for the slider
    mod.db.angle = math.deg(math.atan2(cy - my, cx - mx)) % 360
    updatePosition()
end

-- ---------------------------------------------------------------------------

function mod:OnEnable()
    createOpener()
    updatePosition()
    opener:Show()

    -- Other addons build their buttons during their own load and login steps,
    -- some a moment later still; hence the delays rather than the bare events.
    self:RegisterEvent("PLAYER_LOGIN", function() syncAfter(1) end)
    self:RegisterEvent("PLAYER_ENTERING_WORLD", function() syncAfter(2) end)

    -- Switched on from the options in a running session: the login events are
    -- long gone, so collect right away.
    if ns.isInitialised then requestSync() end
end

function mod:OnDisable()
    if tray then tray:Hide() end
    if opener then opener:Hide() end
    -- `active` is already false here, so this run gives every button back.
    sync()
end

function mod:GetOptions()
    return {
        { type = "header", text = L["Minimap Button Collector"] },
        { type = "desc", text = L["|cffaaaaaaOne button on the minimap opens a box with the minimap buttons of all your other addons, so the minimap itself stays clean. Turning the module off puts every button back where it was.|r"] },
        { type = "spacer", height = 6 },
        {
            type = "slider", label = L["Buttons per row"],
            min = 1, max = 8, step = 1,
            get = function() return mod.db.columns end,
            set = function(_, v) mod.db.columns = v; requestSync() end,
        },
        {
            type = "slider", label = L["Button size"],
            min = 20, max = 40, step = 1,
            get = function() return mod.db.buttonSize end,
            set = function(_, v) mod.db.buttonSize = v; requestSync() end,
        },
        {
            type = "slider", label = L["Angle (degrees)"],
            min = 0, max = 360, step = 1,
            get = function() return mod.db.angle end,
            set = function(_, v) mod.db.angle = v; updatePosition() end,
        },
        {
            type = "toggle", label = L["Also collect the VuloForeverUI button"],
            tooltip = L["If off, the VuloForeverUI button stays on the minimap rim."],
            get = function() return mod.db.includeOwn end,
            set = function(_, v) mod.db.includeOwn = v and true or false; requestSync() end,
        },
        {
            type = "toggle", label = L["Close the box when the mouse leaves"],
            tooltip = L["Closes the box shortly after the mouse has left both the box and its button."],
            get = function() return mod.db.closeOnLeave end,
            set = function(_, v) mod.db.closeOnLeave = v and true or false end,
        },
        { type = "spacer", height = 6 },
        {
            type = "button", label = L["Collect now"], width = 160,
            tooltip = L["Searches the minimap again for addon buttons."],
            onClick = function() requestSync() end,
        },
    }
end
