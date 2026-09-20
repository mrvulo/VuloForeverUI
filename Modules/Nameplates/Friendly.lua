-- VuloForeverUI / Modules / Nameplates / Friendly
--
-- Plates of friendly players and NPCs. Two modes, and they work in opposite
-- ways on purpose:
--
--   NAME ONLY (the default) -- Blizzard's own plate stays exactly as it is and
--   we never touch it per unit. The client is told to show nothing but the name
--   (a CVar it already has), and the look is changed through the two FONT
--   OBJECTS every plate name inherits. One write, every plate follows, and it
--   keeps working inside instances where friendly plates are forbidden frames
--   that addon code may not reach at all.
--
--   HEALTH BAR -- the unit gets one of our own plates, the same one the enemy
--   side uses (Plate.lua): the bar, the name, the target glow and the cast bar
--   all come for free, and only the colour differs.
--
-- Inside a dungeon or raid the client hands friendly units FORBIDDEN plates:
-- C_NamePlate.GetNamePlateForUnit returns nothing for them, so the attach path
-- in Nameplates.lua bails on its own. Nothing here needs an instance check --
-- except friendly NPCs, which are switched off there because the name-only
-- lever is all that would be left and it looks half-applied.
local _, ns = ...
local NP = ns.NP

local Friendly = {}
NP.Friendly = Friendly

-- ---------------------------------------------------------------------------
-- The font objects. Every nameplate name inherits one of these two, so setting
-- them is how a name-only plate is styled at all -- a per-plate SetFont is
-- refused on a restricted frame. The originals are kept so switching the module
-- off gives the client its own look back.
-- ---------------------------------------------------------------------------
local FONT_OBJECTS = { "SystemFont_NamePlate", "SystemFont_NamePlate_Outlined" }
local original = {}

-- Recorded even when GetFont answers nothing: an object we changed but could
-- not read would otherwise never be given back.
local function saveOriginal(name, fo)
    if original[name] then return end
    local file, size, flags = fo:GetFont()
    original[name] = { file or ns.UI.FONT_PATH, size or 12, flags or "" }
end

local function applyFonts()
    local db = NP.db()
    for _, name in ipairs(FONT_OBJECTS) do
        local fo = _G[name]
        if fo and fo.GetFont then
            saveOriginal(name, fo)
            local o = original[name]
            local flags = (name:find("Outlined") and "OUTLINE") or (o and o[3]) or ""
            pcall(fo.SetFont, fo, ns.ModuleFontPath("nameplates"), db.friendlyNameSize, flags)
        end
    end
end

local function restoreFonts()
    for name, o in pairs(original) do
        local fo = _G[name]
        if fo and fo.SetFont then pcall(fo.SetFont, fo, o[1], o[2], o[3]) end
    end
    wipe(original)
end

-- ---------------------------------------------------------------------------
-- CVars. These are the client's own friendly-plate switches; the module owns
-- them while it runs and hands them back when it stops (NP.SetCVar records the
-- value it found).
-- ---------------------------------------------------------------------------
function Friendly.ApplyCVars()
    local db = NP.db()
    local nameOnly = db.showFriendlyPlayers and db.friendlyNameOnly
    NP.SetCVar("nameplateShowOnlyNameForFriendlyPlayerUnits", nameOnly and "1" or "0")
    NP.SetCVar("nameplateUseClassColorForFriendlyPlayerUnitNames",
        db.classColorFriendly and "1" or "0")
    -- the bar-side one; nameplateUseClassColorForFriendlyPlayerUnitNames above
    -- only colours the name text
    NP.SetCVar("nameplateShowFriendlyClassColor", db.classColorFriendly and "1" or "0")
    NP.SetCVar("UnitNameFriendlyPlayerName", db.showFriendlyPlayers and "1" or "0")
    NP.SetCVar("nameplateShowFriendlyPlayers", db.showFriendlyPlayers and "1" or "0")
    NP.SetCVar("nameplateShowFriendlyNpcs",
        (db.showFriendlyNPCs and not NP.ctx.inInstance) and "1" or "0")
end

-- Not clickable: the insets are pushed INWARD until nothing of the plate is
-- left to hit. Protected, so out of combat only.
local function applyClickThrough()
    local mgr = C_NamePlateManager
    if not (mgr and mgr.SetNamePlateHitTestInsets and Enum.NamePlateType) then return end
    if InCombatLockdown() then return end
    local db = NP.db()
    local t = Enum.NamePlateType.Friendly
    if db.friendlyClickThrough then
        pcall(mgr.SetNamePlateHitTestInsets, t, 10000, 10000, 10000, 10000)
    else
        pcall(mgr.SetNamePlateHitTestInsets, t, 0, 0, 0, 0)
    end
end

-- ---------------------------------------------------------------------------
-- Which friendly units get one of OUR plates
-- ---------------------------------------------------------------------------
-- A plain true only. A secret or nil answer leaves the unit to the client,
-- which is the safe direction: its own plate is already there.
local function plainTrue(v)
    return ns.CanRead(v) and v == true
end

function Friendly.WantsOwnPlate(unit)
    local db = NP.db()
    if db.friendlyNameOnly then return false end
    if plainTrue(UnitIsPlayer(unit)) then return db.showFriendlyPlayers end
    return db.showFriendlyNPCs and not NP.ctx.inInstance
end

-- The bar colour for a friendly plate. A player in our group has a readable
-- class; one outside it does not, so the colour is read off Blizzard's own
-- hidden bar -- the same route the enemy side uses for enemy players.
function Friendly.BarColor(plate)
    local db = NP.db()
    if db.classColorFriendly and plainTrue(UnitIsPlayer(plate.unit)) then
        local _, class = UnitClass(plate.unit)
        if ns.CanRead(class) and class then
            local c = (ns.CLASS_COLORS and ns.CLASS_COLORS[class]) or RAID_CLASS_COLORS[class]
            if c then return c.r, c.g, c.b, false end
        end
        local uf = plate.blizz
        local bar = uf and not uf:IsForbidden()
            and (uf.healthBar or (uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar))
        if bar and not bar:IsForbidden() then
            local r, g, b = bar:GetStatusBarColor()
            if ns.Exists(r) then return r, g, b, true end   -- secret: never cached
        end
    end
    local c = plainTrue(UnitIsPlayer(plate.unit)) and db.friendlyBarColor or db.friendlyNPCColor
    return c.r, c.g, c.b, false
end

-- ---------------------------------------------------------------------------
-- Enable / disable
-- ---------------------------------------------------------------------------
function Friendly.Apply()
    if not NP.mod.active then return end
    if NP.db().showFriendlyPlayers then applyFonts() else restoreFonts() end
    ns:RunOutOfCombatOnce("np-friendly", function()
        Friendly.ApplyCVars()
        applyClickThrough()
    end)
end

-- A mode or visibility change moves units across the line between "ours" and
-- "the client's", so every plate is re-decided: the ones that are no longer
-- ours go back, and every base plate on screen is offered again.
function Friendly.Refresh()
    Friendly.Apply()
    if not NP.mod.active then return end
    local drop = {}
    for unit, plate in pairs(NP.plates) do
        if plate.friendly and not Friendly.WantsOwnPlate(unit) then drop[#drop + 1] = unit end
    end
    for _, unit in ipairs(drop) do NP.Detach(unit) end
    for _, nameplate in ipairs(C_NamePlate.GetNamePlates()) do
        local unit = NP.UnitOf(nameplate)
        if unit then NP.Attach(unit) end
    end
end

function Friendly.Restore()
    restoreFonts()
    ns:RunOutOfCombatOnce("np-friendly-off", function()
        local mgr = C_NamePlateManager
        if mgr and mgr.SetNamePlateHitTestInsets and Enum.NamePlateType then
            pcall(mgr.SetNamePlateHitTestInsets, Enum.NamePlateType.Friendly, 0, 0, 0, 0)
        end
    end)
end
