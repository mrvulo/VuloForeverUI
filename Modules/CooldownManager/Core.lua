-- VuloForeverUI / Modules / CooldownManager / Core
--
-- Icon bars for your own cooldowns: a row per purpose, the spells you picked,
-- the swipe and the countdown on each icon.
--
-- WHY THIS IS OUR OWN DISPLAY AND NOT A RESKIN OF THE CLIENT'S
--
-- The client's cooldown viewer does carry data here -- measured 2026-09-20,
-- warrior: Essential 3, Utility 2, TrackedBuff 6, the other six categories
-- empty. What it does NOT carry is enough of it to hang a whole module on,
-- and taking over its frames would tie every icon to a layout we do not own.
-- So the viewer is used for what it is good at, seeding a new bar with the
-- spells the client itself considers essential, and the bars below own their
-- look and their state. The spellbook fills the picker with the rest.
--
-- HOW A COOLDOWN IS SHOWN WITHOUT EVER READING IT
--
-- In combat every cooldown number is a secret value. Not one of them is read
-- here. The client hands out a DURATION OBJECT per spell, and every part of
-- the icon is driven from that object by the engine:
--
--   swipe        Cooldown:SetCooldownFromDurationObject(d) -- clears itself
--                when the duration is zero, so "is it ready" is never asked
--   countdown    a DurationTextBinding bound to our own font string; the
--                engine writes the text, including the tenths near the end
--   desaturate   SetDesaturation with ns.FoldValue over d:IsZero(), which
--                picks a number from a secret boolean without reading it
--   ready glow   ns.AlphaFromBool on the same boolean
--   charges      SetFormattedText("%d", secret) -- formatting is allowed
--
-- The one thing we decide ourselves is WHICH spell sits WHERE, and that is
-- plain data from the spellbook.
local _, ns = ...
local L = ns.L

local CM = {}
ns.CM = CM

CM.MAX_BARS   = 8
CM.MAX_ICONS  = 24      -- pooled icons per bar
CM.WHITE      = "Interface\\Buttons\\WHITE8X8"

-- The icon shapes. Each is a mask file plus the matching border art, so a
-- round icon does not sit in a square frame.
CM.SHAPES = {
    square  = { mask = nil,
                border = nil },
    rounded = { mask = "Interface\\AddOns\\VuloForeverUI\\Media\\Masks\\csquare_mask.tga",
                border = "Interface\\AddOns\\VuloForeverUI\\Media\\Buttons\\csquare_border.tga" },
    circle  = { mask = "Interface\\AddOns\\VuloForeverUI\\Media\\Masks\\circle_mask.tga",
                border = "Interface\\AddOns\\VuloForeverUI\\Media\\Buttons\\circle_border.tga" },
    hexagon = { mask = "Interface\\AddOns\\VuloForeverUI\\Media\\Buttons\\hexagon_mask.tga",
                border = "Interface\\AddOns\\VuloForeverUI\\Media\\Buttons\\hexagon_border.tga" },
}

-- One bar's settings. A new bar is this table copied, so every key a bar can
-- have is listed here once.
CM.BAR_DEFAULTS = {
    name        = "Cooldowns",
    enabled     = true,
    iconSize    = 42,
    spacing     = 2,
    rows        = 1,
    grow        = "CENTER",      -- CENTER | RIGHT | LEFT
    vertical    = false,
    iconZoom    = 0.08,
    iconShape   = "square",
    borderSize  = 1,
    borderTexture = "",          -- a shared-media border; "" is the flat edges
    borderInset = 0,             -- how far the border sits outside the icon
    borderColor = { r = 0, g = 0, b = 0, a = 1 },
    borderClassColor = false,
    bgColor     = { r = 0.08, g = 0.08, b = 0.08, a = 0.6 },
    desaturateOnCooldown = true,
    showSwipe   = true,
    swipeAlpha  = 0.7,
    showCountdown = true,
    countdownSize = 12,
    countdownColor = { r = 1, g = 1, b = 1 },
    showCharges = true,
    chargeSize  = 11,
    -- Keybind, item count and aura stacks: three texts that live in three
    -- corners of the icon and are all plain data about us, never about a fight.
    showKeybind = false,
    keybindSize = 10,
    keybindColor = { r = 1, g = 1, b = 1 },
    showCount   = true,
    countSize   = 11,
    countColor  = { r = 1, g = 1, b = 1 },
    readyGlow   = false,
    glowType    = "pixel",       -- none | pixel | shine | proc
    glowColor   = { r = 1, g = 0.86, b = 0.32 },
    procGlow    = false,         -- the client says the spell lit up
    stackGlow   = 0,             -- glow from this many stacks on; 0 is off
    -- Overflow. Everything past maxIcons is handed to another bar, which is
    -- how a long list stays one readable row instead of a wall.
    maxIcons    = 0,             -- 0 is "no limit"
    overflowInto = "",           -- the bar key that takes the rest
    -- Size rules. maxWidth shrinks the icons until the row fits, but never
    -- below minIconSize; past that the row simply grows again.
    maxWidth    = 0,             -- 0 is "no limit"
    minIconSize = 20,
    splitRows   = false,         -- a gap between the two halves of a double row
    splitGap    = 10,
    anchorTo    = "screen",      -- screen | player | target | focus | cursor
    visibility  = "always",      -- always | combat | noncombat | mouseover | hidden
    conds       = false,         -- extra conditions, ALL of them must hold
    opacity     = 1,
    oocFade     = false,
    oocAlpha    = 0.4,
    spells      = false,         -- per spec, see CM.Spells()
    -- Position and scale in the shape the house mover expects, so /vedit
    -- moves a bar like every other frame in the suite.
    x           = 0,
    y           = -180,
    scale       = 1,
}

local mod = ns:RegisterModule("cooldownmanager", {
    name        = "Cooldown Manager",
    group       = "HUD",
    description = "Icon bars for your own spell cooldowns, with the swipe and the countdown drawn by the client so they keep running in combat.",
    defaults = {
        -- Off out of the box. The suite already draws a lot at first login,
        -- and a set of cooldown rows is a choice, not a default -- the
        -- settings page shows a live preview of what turning it on gives you
        -- without turning it on.
        enabled = false,
        bars = {},              -- filled at first use, see CM.EnsureBars()
        barOrder = {},          -- bar keys in display order
        nextBarId = 1,
    },
})
CM.mod = mod

function CM.db() return mod.db end

-- ---------------------------------------------------------------- spec --

-- The spell list is per specialisation: a Forever character switching talents
-- wants a different row. The key is the spec index, or "0" while the client
-- cannot answer, which keeps it a valid table key either way.
function CM.SpecKey()
    local idx = C_SpecializationInfo.GetSpecialization()
    if type(idx) ~= "number" then return "0" end
    return tostring(idx)
end

-- ---------------------------------------------------------------- entries --
--
-- A row on a bar is a TABLE, not a bare id: { id = 1234, kind = "spell" } plus
-- whatever that one row overrides. Every setting a bar has can be answered
-- per row, and a key that is nil means "whatever the bar says" -- which is why
-- an entry carries no defaults of its own. CM.Val is the only reader.
--
-- Old profiles hold plain numbers; CM.Normalize turns them into entries the
-- first time a list is touched, so nothing else in the module has to know.
function CM.Normalize(list)
    for i = 1, #list do
        if type(list[i]) == "number" then
            list[i] = { id = list[i], kind = "spell" }
        elseif type(list[i]) == "table" and list[i].kind == nil then
            list[i].kind = "spell"
        end
    end
    return list
end

-- The one setting reader. An entry wins over the bar; nil falls through.
function CM.Val(bar, entry, key)
    if entry then
        local v = entry[key]
        if v ~= nil then return v end
    end
    return bar[key]
end

-- The spell list of one bar for the current spec. Created on demand so a
-- fresh profile carries no empty tables for specs nobody plays.
function CM.Spells(bar, specKey)
    specKey = specKey or CM.SpecKey()
    if type(bar.spells) ~= "table" then bar.spells = {} end
    local list = bar.spells[specKey]
    if type(list) ~= "table" then
        list = CM.SeedFor(bar.seed)
        bar.spells[specKey] = list
    end
    return CM.Normalize(list)
end

-- Every spec this character has a list for, plus the one it is in right now.
-- The names come from the client when it answers and are numbered when it
-- does not, which on this build it often does not.
function CM.SpecValues(bar)
    local out, seen = {}, {}
    local current = CM.SpecKey()
    local function add(key)
        if seen[key] then return end
        seen[key] = true
        local name
        local idx = tonumber(key)
        if idx and idx > 0 then
            local ok, _, n = pcall(C_SpecializationInfo.GetSpecializationInfo, idx)
            if ok and type(n) == "string" and n ~= "" then name = n end
        end
        out[#out + 1] = { value = key, text = name or (L["Specialisation"] .. " " .. key) }
    end
    add(current)
    if type(bar.spells) == "table" then
        for key in pairs(bar.spells) do add(key) end
    end
    return out, current
end

-- Take another spec's list over into this one. A copy, not a share: editing
-- the row afterwards must not reach back into the spec it came from.
function CM.CopySpec(bar, fromKey)
    local from = bar.spells and bar.spells[fromKey]
    if type(from) ~= "table" or fromKey == CM.SpecKey() then return false end
    CM.Normalize(from)
    local out = {}
    for i, entry in ipairs(from) do
        local copy = {}
        for k, v in pairs(entry) do
            if type(v) == "table" then
                local c = {}
                for k2, v2 in pairs(v) do c[k2] = v2 end
                copy[k] = c
            else
                copy[k] = v
            end
        end
        out[i] = copy
    end
    bar.spells[CM.SpecKey()] = out
    return true
end

-- What the client puts in one of its own categories, as plain spell ids.
-- Two members of the enum, HiddenActive and HiddenPassive, are rejected by
-- the getter with "bad argument #1" (seen in the client), so every call is
-- pcalled rather than trusted.
function CM.SeedFor(categoryName)
    local out = {}
    local CV = _G.C_CooldownViewer
    local cat = categoryName and Enum.CooldownViewerCategory and Enum.CooldownViewerCategory[categoryName]
    if not (CV and CV.GetCooldownViewerCategorySet and cat) then return out end
    local ok, ids = pcall(CV.GetCooldownViewerCategorySet, cat, false)
    if not ok or type(ids) ~= "table" then return out end
    for _, id in ipairs(ids) do
        local info = CV.GetCooldownViewerCooldownInfo(id)
        local sid = info and (info.overrideSpellID or info.spellID)
        if type(sid) == "number" and C_Spell.GetSpellName(sid) then
            out[#out + 1] = { id = sid, kind = "spell" }
        end
    end
    return out
end

-- ---------------------------------------------------------------- bars --

local function copyDefaults()
    local t = {}
    for k, v in pairs(CM.BAR_DEFAULTS) do
        if type(v) == "table" then
            local c = {}
            for k2, v2 in pairs(v) do c[k2] = v2 end
            t[k] = c
        else
            t[k] = v
        end
    end
    return t
end

-- The three bars a new profile starts with. They differ only in name and
-- icon size; everything else a user changes per bar afterwards.
-- The client's own cooldown viewer does carry data on this build (checked
-- 2026-09-20: Essential 3, Utility 2, TrackedBuff 6 on a warrior), so a new
-- bar starts with what the client itself considers that category -- nobody
-- should have to fill three empty rows by hand before seeing anything.
local STARTERS = {
    { key = "cooldowns", name = "Cooldowns", iconSize = 42, seed = "Essential" },
    { key = "utility",   name = "Utility",   iconSize = 36, seed = "Utility" },
    { key = "buffs",     name = "Buffs",     iconSize = 32, seed = "TrackedBuff" },
}

function CM.EnsureBars()
    local db = CM.db()
    if type(db.bars) ~= "table" then db.bars = {} end
    if type(db.barOrder) ~= "table" then db.barOrder = {} end
    if #db.barOrder > 0 then return end
    for _, s in ipairs(STARTERS) do
        local bar = copyDefaults()
        bar.name, bar.iconSize, bar.seed = s.name, s.iconSize, s.seed
        db.bars[s.key] = bar
        db.barOrder[#db.barOrder + 1] = s.key
    end
end

-- Every bar goes through here, so this is where a table that predates a
-- setting gets the missing key. The defaults are applied ONCE per bar at
-- creation; an imported profile never saw that pass.
-- Raised whenever BAR_DEFAULTS grows a key. A bar filled by an OLDER version
-- of this file is filled again: without that, a saved bar from before a new
-- setting existed reaches the paint pass with the key missing, and the first
-- thing that reads bar.countColor.r takes the whole bar down.
CM.DEFAULTS_VERSION = 2

function CM.Bar(key)
    local db = CM.db()
    local bar = db.bars and db.bars[key]
    if bar and bar._filled ~= CM.DEFAULTS_VERSION then
        ns:ApplyDefaults(bar, CM.BAR_DEFAULTS)
        bar._filled = CM.DEFAULTS_VERSION
    end
    return bar
end

-- A new bar, optionally of a KIND.
--
-- The kind is the client's own cooldown-viewer category, and it is stored
-- rather than resolved here: CM.Spells fills a bar from its seed the first
-- time a spec asks for it, so a bar added for a spec you are not in fills
-- correctly when you get there instead of being filled once, now, wrongly.
function CM.AddBar(name, seed)
    local db = CM.db()
    if #db.barOrder >= CM.MAX_BARS then return nil end
    db.nextBarId = (tonumber(db.nextBarId) or 1) + 1
    local key = "bar" .. db.nextBarId
    local bar = copyDefaults()
    bar.seed = seed
    bar.name = name or (L["Bar"] .. " " .. tostring(db.nextBarId))
    db.bars[key] = bar
    db.barOrder[#db.barOrder + 1] = key
    CM.BuildBar(key)
    return key
end

function CM.RemoveBar(key)
    local db = CM.db()
    for i, k in ipairs(db.barOrder) do
        if k == key then table.remove(db.barOrder, i); break end
    end
    db.bars[key] = nil
    -- The frame is parked, not destroyed: its mover is registered for good
    -- (ns._movers has no remove), so throwing the frame away would leave a
    -- mover pointing at nothing that Edit Mode still writes into.
    local frame = CM.frames and CM.frames[key]
    if frame then frame:Hide() end
end

-- ---------------------------------------------------------------- spells --

-- Everything the player can put on a bar, read from the spellbook: active
-- spells only, no passives, both the player's book and the pet's.
--
-- The client's cooldown viewer would be the nicer source, but its categories
-- are empty here, so it is asked first and the book fills in the rest.
function CM.CollectCandidates()
    local out, seen = {}, {}

    local function add(spellID, source)
        if type(spellID) ~= "number" or seen[spellID] then return end
        local name = C_Spell.GetSpellName(spellID)
        if type(name) ~= "string" or name == "" then return end
        seen[spellID] = true
        out[#out + 1] = {
            spellID = spellID,
            name = name,
            icon = C_Spell.GetSpellTexture(spellID),
            source = source,
        }
    end

    -- 1. The client's own catalogue, when it carries anything.
    local CV = _G.C_CooldownViewer
    if CV and CV.GetCooldownViewerCategorySet and Enum.CooldownViewerCategory then
        for _, category in pairs(Enum.CooldownViewerCategory) do
            local ok, ids = pcall(CV.GetCooldownViewerCategorySet, category, false)
            if ok and type(ids) == "table" then
                for _, id in ipairs(ids) do
                    local info = CV.GetCooldownViewerCooldownInfo(id)
                    -- An override replaces the base spell while it is active,
                    -- and a linked id is the form the player actually casts.
                    local sid = info and (info.overrideSpellID or info.spellID)
                    if sid then add(sid, "viewer") end
                end
            end
        end
    end

    -- 2. The spellbook. Passives have no cooldown worth a row.
    local lines = C_SpellBook.GetNumSpellBookSkillLines and C_SpellBook.GetNumSpellBookSkillLines() or 0
    for i = 1, lines do
        local line = C_SpellBook.GetSpellBookSkillLineInfo(i)
        if line then
            for slot = line.itemIndexOffset + 1, line.itemIndexOffset + line.numSpellBookItems do
                local item = C_SpellBook.GetSpellBookItemInfo(slot, Enum.SpellBookSpellBank.Player)
                if item and item.spellID and not item.isPassive then
                    add(item.spellID, "book")
                end
            end
        end
    end
    if C_SpellBook.HasPetSpells and C_SpellBook.HasPetSpells() then
        local n = C_SpellBook.HasPetSpells()
        for slot = 1, (type(n) == "number" and n or 0) do
            local item = C_SpellBook.GetSpellBookItemInfo(slot, Enum.SpellBookSpellBank.Pet)
            if item and item.spellID and not item.isPassive then
                add(item.spellID, "pet")
            end
        end
    end

    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

-- Cached. The settings search calls GetOptions for every module and tab on
-- every keystroke, and a full walk of the spellbook per keystroke is not
-- something a picker list is worth. Dropped when the spellbook changes.
function CM.Candidates()
    if not CM.candidates then CM.candidates = CM.CollectCandidates() end
    return CM.candidates
end

-- Filler for the settings preview. A bar someone is still styling is often
-- empty or nearly so, and an empty row shows nothing of the size, spacing or
-- border being set. These ids are never saved; they exist for as long as the
-- page is open.
function CM.PreviewFill(list, want)
    local out = {}
    for i = 1, #list do out[i] = list[i] end
    if #out >= want then return out end
    for _, cand in ipairs(CM.Candidates()) do
        if #out >= want then break end
        local dup = false
        for _, e in ipairs(out) do if e.id == cand.spellID then dup = true end end
        if not dup then out[#out + 1] = { id = cand.spellID, kind = "spell" } end
    end
    return out
end

-- Is this spell already on a bar? Used to grey it out in the picker.
function CM.SpellBarName(spellID)
    local db = CM.db()
    for _, key in ipairs(db.barOrder or {}) do
        local bar = db.bars[key]
        if bar then
            for _, e in ipairs(CM.Spells(bar)) do
                if e.id == spellID then return bar.name end
            end
        end
    end
    return nil
end

-- ---------------------------------------------------------------- slots --
--
-- A third kind of row: an EQUIPMENT SLOT. The row is the slot, not the item in
-- it, so a trinket swapped between dungeons keeps its place on the bar instead
-- of leaving a hole and needing to be added again.
--
-- Everything downstream still only knows spells and items, so the slot is
-- resolved to whatever is worn in it at paint time -- one function, called
-- wherever an id is needed.
CM.SLOTS = {
    { id = 13, g = "TRINKET0SLOT_UNIQUE" },
    { id = 14, g = "TRINKET1SLOT_UNIQUE" },
    { id = 1,  g = "HEADSLOT" },
    { id = 2,  g = "NECKSLOT" },
    { id = 3,  g = "SHOULDERSLOT" },
    { id = 15, g = "BACKSLOT" },
    { id = 5,  g = "CHESTSLOT" },
    { id = 9,  g = "WRISTSLOT" },
    { id = 10, g = "HANDSSLOT" },
    { id = 6,  g = "WAISTSLOT" },
    { id = 7,  g = "LEGSSLOT" },
    { id = 8,  g = "FEETSLOT" },
    { id = 11, g = "FINGER0SLOT_UNIQUE" },
    { id = 16, g = "MAINHANDSLOT" },
    { id = 17, g = "SECONDARYHANDSLOT" },
}

-- The client's own name for a slot, so the menu reads in the player's
-- language without a locale entry of ours for every piece of armour.
function CM.SlotName(slotID)
    for _, slot in ipairs(CM.SLOTS) do
        if slot.id == slotID then
            local name = _G[slot.g]
            if type(name) == "string" and name ~= "" then return name end
            return slot.g
        end
    end
    return tostring(slotID)
end

-- What an entry POINTS AT right now: its own id for a spell or an item, and
-- for a slot whatever is worn there. An empty slot answers nil, and the icon
-- that draws it stays blank rather than drawing the last thing it saw.
function CM.Resolve(entry)
    if type(entry) ~= "table" then return nil, "spell" end
    if entry.kind ~= "slot" then return entry.id, entry.kind end
    local itemID = GetInventoryItemID("player", entry.id)
    if type(itemID) == "number" then return itemID, "item" end
    return nil, "item"
end

function CM.AddSpell(barKey, spellID, kind)
    local bar = CM.Bar(barKey)
    if not bar or type(spellID) ~= "number" then return end
    -- A row lives on one bar only: adding it elsewhere moves it, which is
    -- what someone dragging it to another bar means.
    CM.RemoveSpellEverywhere(spellID, kind or "spell")
    local list = CM.Spells(bar)
    list[#list + 1] = { id = spellID, kind = kind or "spell" }
    -- Restyle, not Refresh: the number of icons changed, and only Restyle
    -- creates them.
    CM.RestyleAll()
end

-- The KIND is part of the match. Without it, adding trinket slot 13 swept
-- away any other row that happened to carry the number 13.
function CM.RemoveSpellEverywhere(spellID, kind)
    local db = CM.db()
    for _, key in ipairs(db.barOrder or {}) do
        local bar = db.bars[key]
        if bar then
            local list = CM.Spells(bar)
            for i = #list, 1, -1 do
                if list[i].id == spellID and (kind == nil or list[i].kind == kind) then
                    table.remove(list, i)
                end
            end
        end
    end
end

function CM.RemoveSpell(barKey, index)
    local bar = CM.Bar(barKey)
    if not bar then return end
    local list = CM.Spells(bar)
    table.remove(list, index)
    CM.RestyleAll()
end

function CM.MoveSpell(barKey, from, to)
    local bar = CM.Bar(barKey)
    if not bar then return end
    local list = CM.Spells(bar)
    if not list[from] or to < 1 or to > #list then return end
    local id = table.remove(list, from)
    table.insert(list, to, id)
    CM.RestyleAll()
end

-- ---------------------------------------------------------------- refresh --

function CM.RefreshAll()
    local db = CM.db()
    for _, key in ipairs(db.barOrder or {}) do CM.Refresh(key) end
end

-- SPELL_UPDATE_COOLDOWN fires several times for one cast, and a refresh walks
-- every icon on every bar. One pass per frame is enough: the swipe and the
-- countdown are driven by the engine afterwards, not by this.
local pending

function CM.RequestRefresh()
    if pending then return end
    pending = true
    ns.NextFrame(function()
        pending = false
        CM.RefreshAll()
    end)
end

function CM.RestyleAll()
    local db = CM.db()
    for _, key in ipairs(db.barOrder or {}) do CM.Restyle(key) end
end

function CM.UpdateVisibilityAll()
    local db = CM.db()
    for _, key in ipairs(db.barOrder or {}) do CM.UpdateVisibility(key) end
end

-- ---------------------------------------------------------------- lifecycle --

local function buildAll()
    CM.EnsureBars()
    local db = CM.db()
    for _, key in ipairs(db.barOrder) do CM.BuildBar(key) end
    CM.Bindings.Rebuild()
    CM.RefreshAll()
    CM.UpdateVisibilityAll()
end

function mod:OnEnable()
    self:RegisterEvent("PLAYER_ENTERING_WORLD", function()
        buildAll()
    end)
    -- A new spell, a talent change or a spec change all change what the bars
    -- should show; the icons are rebuilt from the saved list either way.
    self:RegisterEvent("SPELLS_CHANGED", function()
        CM.candidates = nil
        CM.RequestRefresh()
    end)
    self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", function()
        -- A different spec means a different list and a different icon count.
        CM.candidates = nil
        CM.RestyleAll()
    end)
    self:RegisterEvent("PLAYER_REGEN_DISABLED", function() CM.UpdateVisibilityAll() end)
    self:RegisterEvent("PLAYER_REGEN_ENABLED", function() CM.UpdateVisibilityAll() end)
    -- The cooldown of a spell we show has started or ended. The duration
    -- object is re-fetched here; the engine does the rest on its own.
    self:RegisterEvent("SPELL_UPDATE_COOLDOWN", function() CM.RequestRefresh() end)
    self:RegisterEvent("SPELL_UPDATE_CHARGES", function() CM.RequestRefresh() end)
    -- An aura on us drives the active phase and the stack glow; a bag change
    -- drives the item count. Both are cheap refreshes, both coalesced.
    self:RegisterEvent("UNIT_AURA", function(_, unit)
        if unit == "player" then CM.RequestRefresh() end
    end)
    self:RegisterEvent("BAG_UPDATE_DELAYED", function() CM.RequestRefresh() end)

    -- The key an icon shows comes from the action bars, so it is rebuilt when
    -- a binding or a slot changes -- and once at login, when both are known.
    local function rebind()
        CM.Bindings.Rebuild()
        CM.RequestRefresh()
    end
    self:RegisterEvent("UPDATE_BINDINGS", rebind)
    self:RegisterEvent("ACTIONBAR_SLOT_CHANGED", rebind)
    self:RegisterEvent("ACTIONBAR_PAGE_CHANGED", rebind)

    -- The client's own "this spell lit up" pair. The spell id may be secret in
    -- a fight; CM.SetProc drops the ones it may not place.
    self:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", function(_, spellID)
        CM.SetProc(spellID, true)
    end)
    self:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", function(_, spellID)
        CM.SetProc(spellID, false)
    end)

    -- Everything the extra visibility conditions ask about, plus the frames an
    -- attached bar hangs off -- a target frame only exists while you have one.
    local function reconsider()
        CM.UpdateVisibilityAll()
        for key in pairs(CM.frames or {}) do CM.ApplyAnchor(key) end
    end
    self:RegisterEvent("PLAYER_TARGET_CHANGED", reconsider)
    self:RegisterEvent("PLAYER_FOCUS_CHANGED", reconsider)
    self:RegisterEvent("GROUP_ROSTER_UPDATE", reconsider)
    self:RegisterEvent("ZONE_CHANGED_NEW_AREA", reconsider)
    self:RegisterEvent("PLAYER_UPDATE_RESTING", reconsider)
    self:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED", reconsider)

    -- The cooldown setters are protected functions on this client. A blocked
    -- call raises nothing at all, so the only way to learn about it is to
    -- listen for the client's own complaint -- once, not once per icon.
    self:RegisterEvent("ADDON_ACTION_BLOCKED", function(_, addon, func)
        if addon ~= ns.NAME or CM.blockedReported then return end
        CM.blockedReported = true
        ns:Print(L["The client blocked %s. The cooldown swipes cannot run in combat on this build; please report the output of /vfsecrets cd."],
            tostring(func))
    end)

    if not CM.profileHooked then
        CM.profileHooked = true
        hooksecurefunc(ns, "LoadProfile", function() CM.OnProfileChanged() end)
        -- The one signal that says "the player moved this frame", as opposed
        -- to the many that say "it was re-applied". A bar hanging off the
        -- player frame turns that drop into an offset from its anchor.
        hooksecurefunc(ns, "OnMoverRepositioned", function(_, mover)
            local key = mover and mover.key and mover.key:match("^cooldownbar_(.+)$")
            if key then CM.OnMoved(key) end
        end)
    end

    if CM.HookPreview then CM.HookPreview() end
    if IsLoggedIn() then buildAll() end

    ns:RegisterSlash({ key = "COOLDOWNS", commands = { "/vfcd" },
        desc = "Open the cooldown bar settings.",
    })
end

ns.Slash.COOLDOWNS = function()
    local f = ns.UI:CreateMainFrame()
    f:Show()
    ns.UI:PopulateSidebar()
    ns.UI:ShowModulePage("cooldownmanager")
end

-- A profile switch repoints mod.db. Every mover was handed the OLD bar
-- table and would keep writing a drag into the profile the player just left,
-- and a bar that only the new profile has would never be built.
function CM.OnProfileChanged()
    if not mod.active then return end
    CM.EnsureBars()
    local db = CM.db()
    for key, frame in pairs(CM.frames) do
        local bar = CM.Bar(key)
        if bar then
            if frame.mover then frame.mover.opts.db = bar end
        else
            frame:Hide()
        end
    end
    for _, key in ipairs(db.barOrder) do CM.BuildBar(key) end
    CM.RestyleAll()
    CM.UpdateVisibilityAll()
end

function mod:OnDisable()
    for _, frame in pairs(CM.frames or {}) do frame:Hide() end
end
