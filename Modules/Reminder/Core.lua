-- VuloForeverUI / Modules / Reminder / Core
--
-- A row of icons for what is missing: a buff of your own class, a temporary
-- enchant on a weapon, the campfire buff, or any spell ID you track yourself.
-- A left click fixes it where that can be done with one click; a middle click
-- hides that reminder until the next loading screen.
--
--   Data.lua     what is looked for, per class
--   Core.lua     the checks, the weapon-item learning, events and lifecycle
--   Display.lua  the secure icon row
--   Preview.lua  the live preview on the options page
--   Options.lua  the options page
--
-- WHEN IT LOOKS
--
-- Only out of combat. Auras turn secret in a fight and reading them then does
-- not return a secret, it throws (docs/forever-client-research.md), and the
-- secure buttons could not be rearranged anyway. A state driver hides the row
-- the moment a fight starts; the next look is at PLAYER_REGEN_ENABLED.
-- Also hidden: dead, on a taxi, in a vehicle, mounted in the air, in a rest
-- area (switchable), and where "Show in" says no.
--
-- HOW A BUFF IS RECOGNISED
--
-- By spell NAME, not ID: every rank of a spell shares its name, and the group
-- version (Arcane Brilliance for Arcane Intellect) is one more name that
-- satisfies the entry.
--
-- WEAPON ITEMS
--
-- Poisons, oils and stones have no fixed list on this client. Instead the
-- module watches which consumable in the bags went down in the same moment a
-- weapon got its enchant, remembers it per slot (per character), and a click
-- on the reminder then runs "/use item:<id>" + "/use <slot>".
local _, ns = ...
local L = ns.L
local R = ns.Reminder

local mod = ns:RegisterModule("reminders", {
    name        = "Reminders",
    group       = "General",
    description = "Shows an icon when one of your own buffs or a weapon enchant is missing. Click it to cast. Hidden in combat.",
    defaults    = {
        enabled     = true,
        buffs       = true,
        weapons     = true,
        camp        = false,    -- the campfire buff; opt-in, it is missing most of the time
        customIDs   = {},       -- spell IDs the user tracks, in the order added
        warnMinutes = 0,        -- 0 = only when missing
        hideResting = true,
        showLabels  = true,
        size        = 40,
        spacing     = 6,
        where       = { world = true, party = true, raid = true, pvp = false },
        pos         = { x = 0, y = 180, scale = 1 },
        entries     = {},       -- [entry key] = { on = bool, pick = spellID }
        slots       = {},       -- [slot key]  = { on = bool, pick = spellID }
    },
})
R.mod = mod

local class = select(2, UnitClass("player"))
R.class = class
R.classBuffs = R.BUFFS[class] or {}

-- ---------------------------------------------------------------- spells --

local function spellName(id)
    local n = C_Spell.GetSpellName(id)
    if type(n) == "string" and ns.CanRead(n) then return n end
end
R.SpellName = spellName

-- IsSpellKnown by rank-1 ID, and the name lookup as the fallback for a
-- spellbook that keeps only the top rank: a name only resolves for a spell
-- the player has.
local function isKnown(id)
    if C_SpellBook.IsSpellKnown(id) then return true end
    local n = spellName(id)
    return n ~= nil and C_Spell.GetSpellInfo(n) ~= nil
end

function R.KnownList(list)
    local out = {}
    for _, id in ipairs(list or {}) do
        if isKnown(id) then out[#out + 1] = id end
    end
    return out
end

-- The spell a click casts: the pick if the player still knows it, else the
-- first known one.
function R.CastFor(cfg, list)
    local known = R.KnownList(list)
    if cfg.pick then
        for _, id in ipairs(known) do if id == cfg.pick then return id end end
    end
    return known[1]
end

-- ---------------------------------------------------------------- config --

function R.EntryCfg(e)
    local t = mod.db.entries[e.key]
    if type(t) ~= "table" then t = {}; mod.db.entries[e.key] = t end
    if type(t.on) == "nil" then t.on = e.on ~= false end
    return t
end

function R.SlotCfg(s)
    local t = mod.db.slots[s.key]
    if type(t) ~= "table" then t = {}; mod.db.slots[s.key] = t end
    if type(t.on) == "nil" then
        local d = R.SLOT_DEFAULT[class]
        t.on = (d and d[s.key]) and true or false
    end
    return t
end

-- The item last put on each weapon slot. Per character: it names something
-- one character carries.
local function weaponItems()
    local c = _G.VuloForeverUICharDB
    if type(c) ~= "table" then return {} end
    if type(c.reminderWeaponItem) ~= "table" then c.reminderWeaponItem = {} end
    return c.reminderWeaponItem
end

-- ---------------------------------------------------------------- checks --

-- Seconds left on the best matching aura, math.huge for one that does not
-- run out, nil when none is on. Callers have already checked AurasRestricted;
-- a single spell can still be secret on its own, and one we cannot read
-- counts as present -- a false "missing" is the worse mistake.
local function auraLeft(ids)
    local best
    for _, id in ipairs(ids) do
        if ns.SpellAuraRestricted(id) then return math.huge end
        local n = spellName(id)
        local aura = n and C_UnitAuras.GetAuraDataBySpellName("player", n, "HELPFUL")
        if type(aura) == "table" and ns.CanRead(aura) then
            local exp = aura.expirationTime
            local left = math.huge
            if ns.CanRead(exp) and type(exp) == "number" and exp > 0 then
                left = exp - GetTime()
            end
            if not best or left > best then best = left end
        end
    end
    return best
end

local function isWeapon(inv)
    local id = GetInventoryItemID("player", inv)
    if not id then return false end
    local _, _, _, equipLoc, _, classID = C_Item.GetItemInfoInstant(id)
    return classID == Enum.ItemClass.Weapon
        and equipLoc ~= "INVTYPE_SHIELD" and equipLoc ~= "INVTYPE_HOLDABLE"
end

-- Seconds left on the slot's temporary enchant, nil when it has none.
local function enchantLeft(slot)
    local list = C_Item.GetWeaponEnchantInfo(slot)
    if type(list) ~= "table" then return nil end
    for _, e in pairs(list) do
        if ns.CanRead(e.hasEnchant) and e.hasEnchant
            and ns.CanRead(e.enchantType) and e.enchantType ~= Enum.ItemEnchantType.Permanent then
            local ms = e.timeLeft
            if ns.CanRead(ms) and type(ms) == "number" and ms > 0 then return ms / 1000 end
            return math.huge
        end
    end
end

local function weaponSlot(s)
    return s.key == "main" and Enum.WeaponSlot.MainHand or Enum.WeaponSlot.OffHand
end

-- "Show in": the instance type decides the bucket.
local function whereAllowed()
    local where = mod.db.where
    local _, kind = IsInInstance()
    if kind == "party" or kind == "scenario" then return where.party ~= false end
    if kind == "raid" then return where.raid ~= false end
    if kind == "pvp" or kind == "arena" then return where.pvp == true end
    return where.world ~= false
end

local function suppressed()
    if UnitIsDeadOrGhost("player") or UnitOnTaxi("player") or UnitInVehicle("player") then return true end
    if IsMounted() and IsFlying() then return true end
    if mod.db.hideResting and IsResting() then return true end
    return not whereAllowed()
end

-- ---------------------------------------------------------------- weapon items --

-- Which consumable went down, and when; which slot gained an enchant, and when.
-- Two events that land within MATCH seconds of each other are one action.
local MATCH = 5
local bagCounts = {}
local lastUsed, lastUsedAt
local gainedAt, prevLeft = {}, {}

-- Only what can go ON a weapon: a consumable or an item enhancement that is
-- not itself equippable. Equipping a weapon from the bags drops its count too,
-- and it arrives with its enchant -- that must never be learned as the poison.
local function canBeWeaponItem(id)
    local _, _, _, equipLoc, _, classID = C_Item.GetItemInfoInstant(id)
    if equipLoc and equipLoc ~= "" then return false end
    return classID == Enum.ItemClass.Consumable or classID == Enum.ItemClass.ItemEnhancement
end

local function countBags()
    local counts = {}
    for bag = 0, 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID then
                counts[info.itemID] = (counts[info.itemID] or 0) + (info.stackCount or 1)
            end
        end
    end
    return counts
end

local function matchWeaponItem()
    if not (lastUsed and lastUsedAt) then return end
    for _, s in ipairs(R.SLOTS) do
        local t = gainedAt[s.key]
        if t and math.abs(t - lastUsedAt) <= MATCH then
            weaponItems()[s.key] = lastUsed
            gainedAt[s.key] = nil
        end
    end
end

local function onBags()
    local now = countBags()
    for id, n in pairs(bagCounts) do
        if (now[id] or 0) < n and canBeWeaponItem(id) then lastUsed, lastUsedAt = id, GetTime() end
    end
    bagCounts = now
    matchWeaponItem()
end

-- A slot "gains" when it had nothing, or when its time jumped up (a refresh).
local function watchEnchants()
    for _, s in ipairs(R.SLOTS) do
        local left = enchantLeft(weaponSlot(s))
        local before = prevLeft[s.key]
        if left and (not before or (left ~= math.huge and before ~= math.huge and left > before + 60)) then
            gainedAt[s.key] = GetTime()
        end
        prevLeft[s.key] = left
    end
    matchWeaponItem()
end

-- What is on the weapons right now is the starting point, not a gain:
-- otherwise the first look after a login would learn whatever was sold,
-- banked or turned in during those seconds.
local function primeEnchants()
    wipe(gainedAt)
    for _, s in ipairs(R.SLOTS) do prevLeft[s.key] = enchantLeft(weaponSlot(s)) end
    bagCounts = countBags()
    lastUsed, lastUsedAt = nil, nil
end

-- ---------------------------------------------------------------- collect --

R.dismissed = {}        -- [key] = true until the next loading screen

-- all = the preview's question: every reminder that is switched on, whether
-- it is due or not, each marked `due`. The row asks only for the due ones.
local function add(items, it, all)
    if all or (it.due and not R.dismissed[it.key]) then items[#items + 1] = it end
end

-- item: { key, icon, title, short, line, hint, spell, tip, itemID, macro, soon, due }
function R.Collect(all)
    local items = {}
    local db = mod.db
    if not all and suppressed() then return items end
    local warn = (db.warnMinutes or 0) * 60
    local aurasOk = not ns.AurasRestricted()

    if db.buffs and (aurasOk or all) then
        for _, e in ipairs(R.classBuffs) do
            local cfg = R.EntryCfg(e)
            local cast = cfg.on and R.CastFor(cfg, e.cast)
            if cast then
                local left = aurasOk and auraLeft(e.ids) or nil
                add(items, {
                    key   = "buff:" .. e.key,
                    icon  = C_Spell.GetSpellTexture(cast),
                    short = L[e.short],
                    line  = left and L["Runs out soon"] or L["Missing"],
                    hint  = L["Left click: cast"],
                    spell = cast,
                    soon  = left ~= nil,
                    due   = aurasOk and (not left or left < warn),
                }, all)
            end
        end
    end

    if db.weapons and (class ~= "ROGUE" or isKnown(R.POISONS)) then
        local remembered = weaponItems()
        for _, s in ipairs(R.SLOTS) do
            local cfg = R.SlotCfg(s)
            local armed = isWeapon(s.inv)
            if cfg.on and (armed or all) then
                local left = armed and enchantLeft(weaponSlot(s)) or nil
                local it = {
                    key   = "slot:" .. s.key,
                    short = L[s.label],
                    title = L[s.label],
                    line  = left and L["Weapon enchant runs out soon"] or L["No weapon enchant"],
                    soon  = left ~= nil,
                    due   = armed and (not left or left < warn),
                }
                local cast = class == "SHAMAN" and R.CastFor(cfg, R.IMBUES) or nil
                local itemID = remembered[s.key]
                if cast then
                    it.spell, it.icon, it.hint = cast, C_Spell.GetSpellTexture(cast), L["Left click: cast"]
                elseif itemID and (C_Item.GetItemCount(itemID) or 0) > 0 then
                    it.itemID = itemID
                    it.icon   = C_Item.GetItemIconByID(itemID)
                    it.macro  = "/use item:" .. itemID .. "\n/use " .. s.inv
                    it.hint   = L["Left click: apply the item you used last"]
                else
                    it.icon = GetInventoryItemTexture("player", s.inv)
                end
                add(items, it, all)
            end
        end
    end

    if aurasOk or all then
        local tracked = {}
        if db.camp then tracked[1] = R.CAMP end
        for _, id in ipairs(db.customIDs) do tracked[#tracked + 1] = id end
        for _, id in ipairs(tracked) do
            local name = spellName(id)
            if name then
                add(items, {
                    key   = "id:" .. id,
                    icon  = C_Spell.GetSpellTexture(id),
                    short = name,
                    line  = L["Missing"],
                    tip   = id,       -- the spell's tooltip, but nothing to cast
                    due   = aurasOk and not auraLeft({ id }),
                }, all)
            end
        end
    end
    return items
end

-- ---------------------------------------------------------------- update --

local pending
local function update()
    pending = nil
    -- the preview is plain frames: it follows every change, module on or off
    if R.RefreshPreview then R.RefreshPreview() end
    if not (R.IsBuilt() and mod.active) or InCombatLockdown() then return end
    watchEnchants()
    R.Layout()
    R.Show(R.Collect())
end

-- Many of the events come in bursts (a buff falls off, three UNIT_AURA);
-- one look per frame is enough.
function R.Queue()
    if pending then return end
    pending = true
    C_Timer.After(0, update)
end
mod.Refresh = R.Queue

-- ---------------------------------------------------------------- lifecycle --

local ticker

-- The row has secure children, so building, driving and hiding it is refused
-- in a fight. A switch in combat waits here for the fight to end.
local deferred
local regen = CreateFrame("Frame")
regen:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    local fn = deferred
    deferred = nil
    if fn then fn() end
end)

local function afterCombat(fn)
    if not InCombatLockdown() then return fn() end
    deferred = fn
    regen:RegisterEvent("PLAYER_REGEN_ENABLED")
end

function mod:OnEnable()
    afterCombat(R.Build)
    primeEnchants()
    local queue = R.Queue
    local function mine(_, unit) if unit == "player" then queue() end end
    self:RegisterEvent("UNIT_AURA", mine)
    self:RegisterEvent("UNIT_INVENTORY_CHANGED", mine)
    self:RegisterEvent("UNIT_ENTERED_VEHICLE", mine)
    self:RegisterEvent("UNIT_EXITED_VEHICLE", mine)
    self:RegisterEvent("BAG_UPDATE_DELAYED", function() onBags(); queue() end)
    self:RegisterEvent("PLAYER_ENTERING_WORLD", function() wipe(R.dismissed); queue() end)
    for _, ev in ipairs({ "PLAYER_REGEN_ENABLED", "PLAYER_EQUIPMENT_CHANGED", "WEAPON_ENCHANT_CHANGED",
                          "SPELLS_CHANGED", "PLAYER_UPDATE_RESTING", "ZONE_CHANGED_NEW_AREA",
                          "PLAYER_MOUNT_DISPLAY_CHANGED", "PLAYER_CONTROL_GAINED",
                          "PLAYER_ALIVE", "PLAYER_UNGHOST", "PLAYER_DEAD" }) do
        self:RegisterEvent(ev, queue)
    end
    -- time passing fires no event; this is what moves a buff into "runs out soon"
    if ticker then ticker:Cancel() end
    ticker = C_Timer.NewTicker(5, queue)
end

-- In a fight the driver keeps the row hidden until teardown runs.
function mod:OnDisable()
    if ticker then ticker:Cancel(); ticker = nil end
    afterCombat(R.Teardown)
end
