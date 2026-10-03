-- VuloForeverUI / Core / Database / Load: defaults, schema migrations, InitDB and LoadProfile
-- SavedVariables: VuloForeverUIDB holds global/profiles[name]/classAssignments/activeProfile; ns.db.profile points at the active profile.
local _, ns = ...
local L = ns.L

-- Shared between the files in Core/Database/ (Load, Profiles, Storage).
ns._DB = ns._DB or {}
local P = ns._DB

ns.defaults = {
    global = {
        debug = false,
        -- account-wide so layouts are shared across profiles and characters
        editLayouts = {},
        -- Vulslot's named snapshots. Account-wide for the same reason, and for
        -- a second one worth writing down: a new class profile is a DeepCopy of
        -- Default (see InitDB), so anything stored per profile is duplicated the
        -- first time each class logs in. Seven profiles held seven byte-identical
        -- copies of one 17 KB snapshot library -- 37 % of the saved file. The
        -- snapshots carry the class they were taken on and Vulslot warns on a
        -- mismatch, so they were never per-class data to begin with.
        vulslotProfiles = {},
        -- Fonts and custom colors are a LOOK, not a playstyle: account-wide on
        -- purpose, like the edit layouts above. Colors hold only overrides --
        -- an absent token means "client default".
        fonts = { font = "Expressway", outline = "NONE", gameText = false },
        classColors = {},
        powerColors = {},
        -- Per-profile hotkeys are account-wide bindings, not profile data.
        -- The key is the profile name; the value is WoW's binding token.
        profileKeybinds = {},
        -- Stable short button ids keep frame names valid even for old profiles
        -- with long or non-ASCII names.
        profileKeybindButtonIds = {},
        nextProfileKeybindButtonId = 0,
        -- The first-time setup (UI/Setup.lua). True by default so an existing
        -- install never sees it; InitDB sets it false for a database that did
        -- not exist before this login.
        setupDone = true,
        -- Settings window bookkeeping, account-wide like recentPages: which
        -- pages a player keeps returning to is a habit, not profile data.
        -- pinnedModules: module keys in the order they were pinned (UI/Sidebar.lua).
        -- recentChanges: the last settings written from the window, newest
        -- first (UI/OptionsBuilder/ records, UI/Dashboard.lua lists).
        pinnedModules = {},
        recentChanges = {},
    },
    profile = {
        ui = {
            mainFramePos = { point = "CENTER", relPoint = "CENTER", x = 0, y = 0 },
            -- Scale of the settings window alone, not the game's interface.
            mainFrameScale = 1,
        },
        editmode = {
            grid = { show = false, snap = true, size = 32 },
        },
        -- window-to-window pins: [childMoverKey] = { to, dx, dy } (Core/Mover/)
        moverLinks = {},
        moverSizeLinks = {},
        modules = {
            -- filled from mod.defaults at load
        },
    },
}

local DEFAULT_PROFILE = "Default"
P.DEFAULT_PROFILE = DEFAULT_PROFILE

-- Migrations report through this instead of printing: they run at ADDON_LOADED,
-- where a chat message can be scrolled away by the login sequence before anyone
-- reads it. Core/Init.lua empties the list at PLAYER_LOGIN.
ns.migrationNotes = ns.migrationNotes or {}
local function note(msg, ...)
    ns.migrationNotes[#ns.migrationNotes + 1] = { msg, ... }
end

-- Stored schema version. Bump it and add an entry to MIGRATIONS whenever a
-- stored shape or a default VALUE changes.
--
-- Why this has to exist: saving strips anything equal to the current default,
-- so "the player deliberately chose this value" and "the player never touched
-- it" are indistinguishable afterwards. Change a default and everyone who had
-- picked that exact value silently moves with it. A numbered migration is the
-- only chance to tell the two apart - at the moment of the change, while the
-- old default is still known.
--
-- Before this there were five hand-written one-shot booleans, each with its own
-- account and per-character guard. Those stay as they are; they work and are
-- idempotent. New ones belong here instead.
--
-- Entries run in ascending order for every version above the stored one, and
-- receive nothing: they operate on the saved tables directly. An install that
-- has never been stamped is stamped at the current version WITHOUT running
-- anything -- a fresh install has no old shape to convert.
-- Schema 1 is this addon's first release; the saved variables of
-- VuloClassicUI are a different product's, under a different name.
local SCHEMA = 2
local MIGRATIONS = {}

-- [2] The Modern unit frames now take their first place from Blizzard's
-- frames instead of fixed numbers (UnitFrames/Engine.lua, seedFromBlizzard).
-- Every profile that exists already keeps the place it has: marked as placed,
-- whether it was ever moved or not. Re-runnable: it only ever sets true.
MIGRATIONS[2] = function()
    local units = { "player", "target", "focus", "targettarget", "focustarget", "pet", "boss" }
    for _, prof in pairs(VuloForeverUIDB.profiles or {}) do
        if type(prof) == "table" then
            if type(prof.modules) ~= "table" then prof.modules = {} end
            if type(prof.modules.unitframes) ~= "table" then prof.modules.unitframes = {} end
            local uf = prof.modules.unitframes
            for _, unit in ipairs(units) do
                if type(uf[unit]) ~= "table" then uf[unit] = {} end
                uf[unit].seeded = true
            end
        end
    end
end

-- A database that has never been written carries no profile with module
-- settings in it. Anything that has been played with does -- that is the only
-- tell available, and it is enough for the question below.
local function looksUsed()
    for _, prof in pairs(VuloForeverUIDB.profiles or {}) do
        if type(prof) == "table" and type(prof.modules) == "table"
            and next(prof.modules) then
            return true
        end
    end
    return false
end

local function runMigrations()
    local g = VuloForeverUIDB.global
    local from = tonumber(g.schema)
    if not from then
        -- No stamp means one of TWO things that need opposite treatment: a fresh
        -- install, where there is nothing to migrate -- or an install from BEFORE
        -- the stamp existed, where everything is still to be migrated. Both used
        -- to be stamped at the current schema and skipped, so the older one lost
        -- every migration in silence, bar setups in their old place included.
        -- That is exactly the kind of loss the promise at the top of this file
        -- rules out.
        --
        -- Starting such an install at zero is safe: the migrations are written to
        -- survive a re-run (see the note on deterministic order in [2]), and an
        -- install without a stamp is by definition older than all of them.
        if not looksUsed() then
            g.schema = SCHEMA
            VuloForeverUICharDB.schema = VuloForeverUICharDB.schema or SCHEMA
            return
        end
        from = 0
        g.schema = 0
    end
    if from >= SCHEMA then return end
    for v = from + 1, SCHEMA do
        local fn = MIGRATIONS[v]
        if fn then
            local ok, err = pcall(fn)
            if not ok then
                ns:Print(L["|cffff5555Settings migration %s failed:|r %s"], tostring(v), tostring(err))
                return                 -- stop at the first failure; schema stays put
            end
        end
        g.schema = v
    end
    VuloForeverUICharDB.schema = SCHEMA
end

local function getClassKey()
    local _, class = UnitClass("player")
    return class or "UNKNOWN"
end
P.getClassKey = getClassKey

-- Must stay in sync with CLASS_LABELS in Modules/Profiles.lua so the auto per-class profile name matches the button.
local CLASS_ENGLISH = {
    WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue",
    PRIEST = "Priest", SHAMAN = "Shaman", MAGE = "Mage", WARLOCK = "Warlock",
    DRUID = "Druid",
}
function ns:GetClassProfileName(classKey)
    local eng = CLASS_ENGLISH[classKey]
    return (eng and L[eng]) or classKey
end

-- Runs on ADDON_LOADED, once SavedVariables exist.
function ns:InitDB()
    local freshInstall  = (VuloForeverUIDB == nil)
    local charWasNil    = (VuloForeverUICharDB == nil)
    VuloForeverUIDB     = VuloForeverUIDB     or {}
    VuloForeverUICharDB = VuloForeverUICharDB or {}

    if ns.RefreshLocale then ns:RefreshLocale() end

    -- Migration: single db.profile -> db.profiles.Default
    if VuloForeverUIDB.profile and not VuloForeverUIDB.profiles then
        VuloForeverUIDB.profiles = {
            [DEFAULT_PROFILE] = VuloForeverUIDB.profile,
        }
        VuloForeverUIDB.profile = nil
        ns:Print(L["Settings migrated to profile system (all settings are in profile '%s')."], DEFAULT_PROFILE)
    end

    VuloForeverUIDB.global            = VuloForeverUIDB.global            or {}
    VuloForeverUIDB.profiles          = VuloForeverUIDB.profiles          or {}
    VuloForeverUIDB.classAssignments  = VuloForeverUIDB.classAssignments  or {}

    VuloForeverUIDB.global = ns:ApplyDefaults(VuloForeverUIDB.global, ns.defaults.global)
    if freshInstall then
        ns._freshDatabase = true
        VuloForeverUIDB.global.setupDone = false
        -- Said out loud, and kept: a database that arrives empty although the
        -- player had settings is the one failure that looks like nothing at
        -- all. The log survives in the file, so the next report can show how
        -- often it happened and whether the character file was gone too.
        local log = VuloForeverUIDB.global.freshLog or {}
        log[#log + 1] = date("%Y-%m-%d %H:%M:%S") .. (charWasNil and " char=nil" or " char=kept")
        while #log > 8 do table.remove(log, 1) end
        VuloForeverUIDB.global.freshLog = log
        note(L["No saved settings were found at this login, so the addon started from defaults."])
    end

    -- The logout scrub parks its count here; saying it out loud is the whole
    -- point — a player whose settings kept resetting needs to see the cause.
    local scrubbed = tonumber(VuloForeverUIDB.global.scrubbedNonFinite)
    if scrubbed and scrubbed > 0 then
        note(L["%d broken numeric values were removed from the settings so they can be saved again."], scrubbed)
        VuloForeverUIDB.global.scrubbedNonFinite = nil
    end

    if not VuloForeverUIDB.profiles[DEFAULT_PROFILE] then
        VuloForeverUIDB.profiles[DEFAULT_PROFILE] = {}
    end
    VuloForeverUIDB.profiles[DEFAULT_PROFILE] = ns:ApplyDefaults(
        VuloForeverUIDB.profiles[DEFAULT_PROFILE], ns.defaults.profile
    )

    runMigrations()

    -- Precedence: char assignment > class assignment > this char's own auto-created class profile, so class settings never bleed onto another class.
    local charAssigned = VuloForeverUICharDB.profileOverride
    if charAssigned and not VuloForeverUIDB.profiles[charAssigned] then
        VuloForeverUICharDB.profileOverride = nil
        charAssigned = nil
    end
    local classKey   = getClassKey()
    local assigned   = VuloForeverUIDB.classAssignments[classKey]
    if assigned and not VuloForeverUIDB.profiles[assigned] then
        -- deleted/renamed elsewhere — self-heal, a fresh class profile is made below
        VuloForeverUIDB.classAssignments[classKey] = nil
        assigned = nil
    end
    local activeName = charAssigned or assigned

    if not activeName then
        -- Seed the per-class profile from Default on that class's first login, so existing users keep their look; it diverges freely afterwards.
        if classKey ~= "UNKNOWN" then
            activeName = ns:GetClassProfileName(classKey)
            if not VuloForeverUIDB.profiles[activeName] then
                VuloForeverUIDB.profiles[activeName] =
                    ns:DeepCopy(VuloForeverUIDB.profiles[DEFAULT_PROFILE])
            end
            VuloForeverUIDB.classAssignments[classKey] = activeName
        else
            activeName = VuloForeverUIDB.activeProfile or DEFAULT_PROFILE
        end
    end

    if not VuloForeverUIDB.profiles[activeName] then
        activeName = DEFAULT_PROFILE
    end

    ns:LoadProfile(activeName)

    -- needs the active profile loaded

    VuloForeverUICharDB = ns:ApplyDefaults(VuloForeverUICharDB, ns.defaults.char or {})

    ns.db.global = VuloForeverUIDB.global
    ns.db.char   = VuloForeverUICharDB


    -- Last, and it has to be: it needs ns.db.global and ns.db.char, and it has
    -- to happen before any module is enabled. See Trinkets/TrinketsStore.lua.
    if ns.BindTrinketStore then ns:BindTrinketStore() end
end

function ns:LoadProfile(profileName)
    local profileData = VuloForeverUIDB.profiles[profileName]
    if not profileData then
        ns:Print(L["|cffff5555Profile '%s' does not exist.|r"], profileName)
        return false
    end

    profileData = ns:ApplyDefaults(profileData, ns.defaults.profile)

    for key, mod in pairs(ns.modules or {}) do
        profileData.modules[key] = ns:ApplyDefaults(
            profileData.modules[key], mod.defaults or {}
        )
    end

    VuloForeverUIDB.profiles[profileName] = profileData
    VuloForeverUIDB.activeProfile = profileName

    ns.db = ns.db or {}
    ns.db.profile = profileData

    for key, mod in pairs(ns.modules or {}) do
        mod.db = profileData.modules[key]
    end

    -- theme color rides the profile — must run BEFORE modules paint anything
    if ns.ApplyThemeColor then ns:ApplyThemeColor() end

    return true
end

-- Mutates the ns.COLORS tables IN PLACE so modules holding a reference pick the
-- color up; already-painted textures keep the old color until /reload. The
-- window style (Core/Theme.lua) decides whether the Theme color is used at all.
function ns:ApplyThemeColor()
    local gs = ns.db and ns.db.profile and ns.db.profile.modules
        and ns.db.profile.modules.globalsettings
    local c = gs and gs.themeColor
    -- hard type check: an imported profile may carry arbitrary values here
    if not (c and type(c.r) == "number" and type(c.g) == "number" and type(c.b) == "number") then
        c = { r = 0.608, g = 0.424, b = 1.000 }
    end
    local style = gs and gs.uiStyle
    ns:ApplyUIStyle(type(style) == "string" and style or "blizzard", c)
end
