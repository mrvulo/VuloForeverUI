-- Shared addon table, used by all files.
local addonName, ns = ...

_G.VuloForeverUI = ns

ns.NAME    = addonName
ns.VERSION = C_AddOns.GetAddOnMetadata(addonName, "Version") or "?"
ns.PREFIX  = "|cff9b6cffVuloForeverUI|r"

-- Client detection.
--
-- VuloClassicUI carried four flavour flags plus an interface-range fallback,
-- because it shipped for Era, Anniversary, Wrath and Cata at once. This addon
-- ships for ONE client, so the only question worth asking is "is this actually
-- Forever" -- a wrong answer here means running retail-only code on a Classic
-- client, or the reverse, and every module below assumes the answer is yes.
--
-- Forever is interface 16001 (build 1.60.1, "%d%02d%02d" of the version), and
-- it is NOT a Classic client: game type `camelot` belongs to Blizzard's Mainline
-- family, so the retail API and Edit Mode are what we get. C_SwingTimer is the
-- capability probe: it exists in Forever and in no retail build.
--
-- WOW_PROJECT_ID is deliberately NOT used. Blizzard defines no constant for
-- camelot, so the value the client reports is unverified -- and a check against
-- WOW_PROJECT_CLASSIC would be wrong for exactly the reason above.
local _iface = tonumber((select(4, GetBuildInfo()))) or 0

ns.IFACE     = _iface
ns.isForever = (_iface >= 16000 and _iface < 20000) and (C_SwingTimer ~= nil)

-- Everything here is written against the retail API surface. Say so once, out
-- loud, instead of letting a Classic client fail module by module.
if not ns.isForever then
    local msg = "|cff9b6cffVuloForeverUI|r: |cffff5555this addon is for World of Warcraft: Forever"
        .. " (interface 16001) and does nothing on this client (interface %d).|r"
    C_Timer.After(5, function()
        print(msg:format(_iface))
    end)
    ns.disabled = true
end

ns.C = {
    accent = "|cff9b6cff",
    gold   = "|cffffd100",
    silver = "|cffc7c7cf",
    copper = "|cffeda55f",
    pos    = "|cff44ff44",
    neg    = "|cffff4444",
    gray   = "|cffaaaaaa",
    white  = "|cffffffff",
    yellow = "|cffffff00",
    red    = "|cffff5555",
    r      = "|r",
}

ns.COLORS = {
    accent     = { r = 0.608, g = 0.424, b = 1.000 },
    accentDim  = { r = 0.300, g = 0.200, b = 0.500 },
    bg         = { r = 0.06,  g = 0.06,  b = 0.08, a = 0.96 },
    bgLight    = { r = 0.055, g = 0.055, b = 0.07, a = 0.96 },
    bgContent  = { r = 0.08,  g = 0.08,  b = 0.10, a = 0.96 },
    border     = { r = 0.25,  g = 0.25,  b = 0.30, a = 1.00 },
    borderDark = { r = 0.02,  g = 0.02,  b = 0.03, a = 1.00 },
    text       = { r = 1.00,  g = 1.00,  b = 1.00 },
    textDim    = { r = 0.65,  g = 0.65,  b = 0.70 },
    textMuted  = { r = 0.45,  g = 0.45,  b = 0.50 },
    toggleOff  = { r = 0.20,  g = 0.20,  b = 0.23, a = 1.00 },
    sectionHdr = { r = 0.55,  g = 0.50,  b = 0.60 },
}

-- Canonical resource colors, keyed by the UnitPowerType token. Lives here so
-- both the power bar and the color settings mutate ONE table: consumers keep
-- reading at paint time, the settings page rewrites the fields in place.
-- Forever has the nine original classes, so no death-knight or monk resources.
ns.POWER_COLORS = {
    MANA        = { r = 0.25, g = 0.45, b = 0.95 },
    RAGE        = { r = 0.85, g = 0.22, b = 0.22 },
    ENERGY      = { r = 0.95, g = 0.85, b = 0.25 },
    FOCUS       = { r = 0.95, g = 0.55, b = 0.25 },
}

ns.modules     = {}
ns.moduleOrder = {}

-- Set to true in Init.lua after PLAYER_LOGIN
ns.isInitialised = false
