-- VuloForeverUI / Modules / UnitFrames / Classic
--
-- The Classic style, shared part. The style is a port of the second
-- reference's unit-frame skin: Blizzard's PlayerFrame, TargetFrame, FocusFrame
-- and PetFrame stay (and keep Edit Mode, their menus, auras and cast bars);
-- for player, target and focus an overlay of our own carries the two bars,
-- fed with the raw unit values, while Blizzard's bars go to alpha 0 and their
-- status text strings are reparented so they stay visible. The frame art is
-- Blizzard's own FrameTexture, retextured to the original UI-TargetingFrame
-- files.
--
-- One file per reference file:
--   UnitFramesClassic.lua         this one: power colours, the overlay and
--                                 its feed, the combat gate, Enable/Disable
--   UnitFramesClassicPlayer.lua   player frame incl. vehicle art
--   UnitFramesClassicTarget.lua   target, focus, target-of-target
--   UnitFramesClassicCastBar.lua  target and focus cast bar
--   UnitFramesClassicPet.lua      pet frame
--
-- Where this port differs from the reference, on purpose:
--   * nothing runs at file load; every hook body starts with the `active`
--     test, and Enable applies what the reference applied while loading;
--   * no Lua field is ever written into a Blizzard frame table -- state the
--     reference kept there (haveElite, the regions it created) lives in the
--     weak side table behind Classic.State();
--   * every hook body is split in two: PAINT (textures, tex coords, colours,
--     alpha, fonts -- allowed at any time) and LAYOUT (SetPoint, SetSize,
--     SetParent, Show/Hide, frame level and strata of anything that belongs
--     to a protected Blizzard frame). Layout runs through Classic.Layout():
--     at once out of combat, otherwise once on PLAYER_REGEN_ENABLED;
--   * whatever is COMPARED goes through ns.CanRead first; raw unit values
--     only ever travel into widget setters;
--   * each block sits in a pcall (Classic.Guard): a region missing on some
--     build skips that block and is said once per session, never thrown.
local _, ns = ...
ns.UF = ns.UF or {}
local UF = ns.UF

UF.Classic = {}
local Classic = UF.Classic

local BAR = "Interface\\TargetingFrame\\UI-StatusBar"
Classic.BAR = BAR

------------------------------------------------------------------------------
-- Power colours, as the second reference has them (the Classic values, not
-- the client's PowerBarColor, whose entries name retail atlases).
------------------------------------------------------------------------------

local PowerBarColor = {
    MANA           = { r = 0.00, g = 0.00, b = 1.00 },
    RAGE           = { r = 1.00, g = 0.00, b = 0.00 },
    FOCUS          = { r = 1.00, g = 0.50, b = 0.25 },
    ENERGY         = { r = 1.00, g = 1.00, b = 0.00 },
    COMBO_POINTS   = { r = 1.00, g = 0.96, b = 0.41 },
    RUNES          = { r = 0.50, g = 0.50, b = 0.50 },
    RUNIC_POWER    = { r = 0.00, g = 0.82, b = 1.00 },
    SOUL_SHARDS    = { r = 0.50, g = 0.32, b = 0.55 },
    LUNAR_POWER    = { r = 0.30, g = 0.52, b = 0.90, atlas = "_Druid-LunarBar" },
    HOLY_POWER     = { r = 0.95, g = 0.90, b = 0.60 },
    MAELSTROM      = { r = 0.00, g = 0.50, b = 1.00, atlas = "_Shaman-MaelstromBar" },
    INSANITY       = { r = 0.40, g = 0.00, b = 0.80, atlas = "_Priest-InsanityBar" },
    CHI            = { r = 0.71, g = 1.00, b = 0.92 },
    ARCANE_CHARGES = { r = 0.10, g = 0.10, b = 0.98 },
    FURY           = { r = 0.788, g = 0.259, b = 0.992, atlas = "_DemonHunter-DemonicFuryBar" },
    PAIN           = { r = 1.00, g = 156 / 255, b = 0.00, atlas = "_DemonHunter-DemonicPainBar" },
    -- vehicle colours
    AMMOSLOT       = { r = 0.80, g = 0.60, b = 0.00 },
    FUEL           = { r = 0.00, g = 0.55, b = 0.50 },
}
-- by power type, the fallback for a token the table does not know
PowerBarColor[0]  = PowerBarColor.MANA
PowerBarColor[1]  = PowerBarColor.RAGE
PowerBarColor[2]  = PowerBarColor.FOCUS
PowerBarColor[3]  = PowerBarColor.ENERGY
PowerBarColor[4]  = PowerBarColor.CHI
PowerBarColor[5]  = PowerBarColor.RUNES
PowerBarColor[6]  = PowerBarColor.RUNIC_POWER
PowerBarColor[7]  = PowerBarColor.SOUL_SHARDS
PowerBarColor[8]  = PowerBarColor.LUNAR_POWER
PowerBarColor[9]  = PowerBarColor.HOLY_POWER
PowerBarColor[11] = PowerBarColor.MAELSTROM
PowerBarColor[13] = PowerBarColor.INSANITY
PowerBarColor[17] = PowerBarColor.FURY
PowerBarColor[18] = PowerBarColor.PAIN
Classic.PowerBarColor = PowerBarColor

------------------------------------------------------------------------------
-- State
------------------------------------------------------------------------------

local active, mod = false, nil
local parts = {}                                   -- the four frame files
local installed = false
local reported = {}
local state = setmetatable({}, { __mode = "k" })   -- Blizzard object -> our notes
local pending, pendingArmed = {}, false

function Classic.IsActive() return active end
function Classic.Mod() return mod end

-- Our notes about a Blizzard frame or region: what the reference wrote INTO
-- the frame table (haveElite, the textures it created) is kept here instead.
function Classic.State(obj)
    local s = state[obj]
    if not s then s = {}; state[obj] = s end
    return s
end

-- One pcall per block. A refused or impossible call skips that block only,
-- and is said once per key per session.
local function guard(key, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok and not reported[key] then
        reported[key] = true
        ns:Print("Classic style: %s could not be applied (%s)", key, tostring(err))
    end
    return ok
end
Classic.Guard = guard

-- A value we may compare, or nil. For everything a hook DECIDES on. The
-- readability test comes first: `v ~= nil` is already a comparison.
function Classic.Readable(v)
    if ns.CanRead(v) then return v end
    return nil
end

------------------------------------------------------------------------------
-- The combat gate. Keyed: a hook that fires ten times in a fight leaves one
-- replay behind, the last one. The registry refuses a second registration of
-- the same handler, the flag only saves the call.
------------------------------------------------------------------------------

local function onRegen()
    pendingArmed = false
    local todo = pending
    pending = {}
    if not active then return end
    for key, fn in pairs(todo) do guard(key, fn) end
end

function Classic.Layout(key, fn)
    if ns:InCombat() then
        pending[key] = fn
        if not pendingArmed then
            pendingArmed = true
            ns:RegisterEventOnce("PLAYER_REGEN_ENABLED", onRegen)
        end
        return false
    end
    return guard(key, fn)
end

------------------------------------------------------------------------------
-- The overlay: a 232 x 100 button without mouse, a half-black backdrop and
-- two 119 x 12 status bars on the plain UI-StatusBar fill. It is OUR frame,
-- so fields on it are ours to write.
--
-- The values go from the API straight into the setters and are never looked
-- at -- UnitHealth and UnitPower are secret on this client, out of combat
-- too. The reference guards them with `or 1` / `or 0`; a truth test is one
-- more thing done to a secret, and an existing unit has no nil health, so the
-- fallbacks are left out.
------------------------------------------------------------------------------

-- Blizzard's frame art is NOT snapped to the pixel grid (PlayerFrame.xml:48,
-- TargetFrame.xml:78: snapToPixelGrid="false" texelSnappingBias="0.0"), and
-- Blizzard un-snaps its own bar fills to match (Mainline/PlayerFrame.lua:28-30,
-- TargetFrame.lua:77-79). A texture of ours that keeps the default snapping
-- lands up to a pixel beside the art, depending on where the frame happens to
-- sit on screen -- one frame fits, the other does not (seen 2026-09-18 on
-- the player). Everything of ours that has to line up with the art goes
-- through here.
function Classic.Unsnap(tex)
    if not tex or not tex.SetSnapToPixelGrid then return end
    tex:SetSnapToPixelGrid(false)
    tex:SetTexelSnappingBias(0)
end

local function paintHealthColor(f)
    local r, g, b = 0, 1, 0
    if mod and mod.db and mod.db.classicClassColor then
        local unit = f.unit
        if Classic.Readable(UnitIsPlayer(unit)) then
            local cr, cg, cb
            if UF.Extras and UF.Extras.ClassTint then
                cr, cg, cb = UF.Extras.ClassTint(unit)
            elseif UF.ClassColor then
                cr, cg, cb = UF.ClassColor(unit)
            end
            if cr then r, g, b = cr, cg, cb end
        end
    end
    f.HealthBar:SetStatusBarColor(r, g, b)
end

function Classic.UpdateHealth(f)
    local unit = f and f.unit
    if not unit or not UnitExists(unit) then return end
    f.HealthBar:SetMinMaxValues(0, UnitHealthMax(unit))
    f.HealthBar:SetValue(UnitHealth(unit))
end

function Classic.UpdatePower(f)
    local unit = f and f.unit
    if not unit or not UnitExists(unit) then return end
    local bar = f.ManaBar
    bar:SetMinMaxValues(0, UnitPowerMax(unit))
    bar:SetValue(UnitPower(unit))

    local powerType, powerToken, altR, altG, altB = UnitPowerType(unit)
    powerType, powerToken = Classic.Readable(powerType), Classic.Readable(powerToken)
    local info = powerToken and PowerBarColor[powerToken]

    bar:SetStatusBarTexture(BAR)
    if info then
        local deadOrGhost = unit == "player"
            and (Classic.Readable(UnitIsDead("player")) or Classic.Readable(UnitIsGhost("player")))
            and true or false
        if info.atlas then
            bar:SetStatusBarTexture(info.atlas)
            bar:SetStatusBarColor(1, 1, 1)
            local t = bar:GetStatusBarTexture()
            if t then
                t:SetDesaturated(deadOrGhost)
                t:SetAlpha(deadOrGhost and 0.5 or 1)
            end
        elseif deadOrGhost then
            bar:SetStatusBarColor(0.6, 0.6, 0.6, 0.5)
        else
            bar:SetStatusBarColor(info.r, info.g, info.b, 1)
        end
    elseif Classic.Readable(altR) then
        bar:SetStatusBarColor(altR, altG, altB)
    else
        info = (powerType and PowerBarColor[powerType]) or PowerBarColor.MANA
        bar:SetStatusBarColor(info.r, info.g, info.b, 1)
    end
    Classic.Unsnap(bar:GetStatusBarTexture())   -- the fill was just set again
end

function Classic.UpdateFrame(f)
    if not f then return end
    paintHealthColor(f)
    Classic.UpdateHealth(f)
    Classic.UpdatePower(f)
end

local function onOverlayEvent(f, event)
    if not active then return end
    if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
        Classic.UpdateHealth(f)
    elseif event == "UNIT_DISPLAYPOWER" or event == "UNIT_POWER_UPDATE" or event == "UNIT_MAXPOWER"
        or event == "PLAYER_DEAD" or event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST" then
        Classic.UpdatePower(f)
    else
        -- entering world, target / focus changed, vehicle entered / left
        Classic.UpdateFrame(f)
    end
end

-- `events`: plain event names; `unitEvents`: registered for `units` only.
-- (The reference listens to UNIT_HEALTH of every unit in the world for the
-- player overlay; the unit filter is the same picture for less work.)
function Classic.NewOverlay(parent, unit, events, unitEvents, units)
    local f = CreateFrame("Button", nil, parent)
    f:SetSize(232, 100)
    f:EnableMouse(false)
    f.unit = unit

    f.Background = f:CreateTexture(nil, "BACKGROUND")
    f.Background:SetColorTexture(0, 0, 0, 0.5)

    f.HealthBar = CreateFrame("StatusBar", nil, f)
    f.HealthBar:SetSize(119, 12)
    f.HealthBar:SetStatusBarTexture(BAR)
    f.HealthBar:SetStatusBarColor(0, 1, 0)

    f.ManaBar = CreateFrame("StatusBar", nil, f)
    f.ManaBar:SetSize(119, 12)
    f.ManaBar:SetStatusBarTexture(BAR)
    f.ManaBar:SetStatusBarColor(0, 0, 1)

    Classic.Unsnap(f.Background)
    Classic.Unsnap(f.HealthBar:GetStatusBarTexture())
    Classic.Unsnap(f.ManaBar:GetStatusBarTexture())

    for _, e in ipairs(events or {}) do f:RegisterEvent(e) end
    for _, e in ipairs(unitEvents or {}) do f:RegisterUnitEvent(e, unpack(units)) end
    f:SetScript("OnEvent", onOverlayEvent)
    return f
end

------------------------------------------------------------------------------
-- Blizzard's own mana bars that stay visible (pet, target-of-target): the
-- reference's UnitFrameManaBar_UpdateType hook. Blizzard puts a retail atlas
-- on the bar on every power-type update (Mainline/UnitFrame.lua:497); this
-- answers after it. The reference does it for every mana bar in the client;
-- here only the bars the frame files register, so frames this round leaves
-- alone (party, boss) keep a consistent retail look.
------------------------------------------------------------------------------

local manaBars = setmetatable({}, { __mode = "k" })

local function tintBlizzardManaBar(bar)
    local _, powerToken, altR, altG, altB = UnitPowerType(bar.unit)
    powerToken = Classic.Readable(powerToken)
    local info = powerToken and PowerBarColor[powerToken]

    bar:SetStatusBarTexture(BAR)
    if info then
        if info.atlas then
            bar:SetStatusBarTexture(info.atlas)
            bar:SetStatusBarColor(1, 1, 1)
        else
            bar:SetStatusBarColor(info.r, info.g, info.b)
        end
        if bar.Spark then bar.Spark:SetAlpha(0) end
    elseif Classic.Readable(altR) then
        bar:SetStatusBarColor(altR, altG, altB)
    end
end

function Classic.RegisterManaBar(bar)
    if bar then manaBars[bar] = true end
end

------------------------------------------------------------------------------
-- Blizzard's status text, always on, percent + value: the two CVars
-- TextStatusBar reads. Display mode first, so the CVAR_UPDATE for the second
-- one repaints every bar with it. Never restored: it is the user's setting
-- from here on, changeable in Blizzard's options.
------------------------------------------------------------------------------

local function applyStatusTextCVars()
    if not (mod and mod.db and mod.db.classicStatusText) then return end
    if ns:InCombat() then return end
    guard("statustext.cvars", function()
        SetCVar("statusTextDisplay", "BOTH")
        SetCVar("statusText", "1")
    end)
end

------------------------------------------------------------------------------
-- Public. A frame file registers { name, install, enable, disable }:
-- install() sets its hooks (once, ever), enable() applies the look (out of
-- combat -- the caller gates), disable() hides what is ours.
------------------------------------------------------------------------------

function Classic.RegisterPart(part)
    parts[#parts + 1] = part
end

function Classic.Enable(m)
    mod, active = m, true
    if not installed then
        installed = true
        if type(_G.UnitFrameManaBar_UpdateType) == "function" then
            hooksecurefunc("UnitFrameManaBar_UpdateType", function(bar)
                if not active or not bar or not manaBars[bar] then return end
                guard("manabar.type", tintBlizzardManaBar, bar)
            end)
        end
        for _, part in ipairs(parts) do
            if part.install then guard(part.name .. ".hooks", part.install) end
        end
    end
    applyStatusTextCVars()
    for _, part in ipairs(parts) do
        if part.enable then guard(part.name .. ".enable", part.enable) end
    end
    for bar in pairs(manaBars) do guard("manabar.type", tintBlizzardManaBar, bar) end
end

-- Hides what is ours. Blizzard's regions stay where we put them and the hooks
-- stay installed (gated off); the module asks for a reload.
function Classic.Disable()
    active = false
    pending = {}
    for _, part in ipairs(parts) do
        if part.disable then guard(part.name .. ".disable", part.disable) end
    end
end
