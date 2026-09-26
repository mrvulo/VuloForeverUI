-- VuloForeverUI / Modules / Reminder / Options
local _, ns = ...
local L = ns.L
local R = ns.Reminder
local mod = R.mod

local function choices(list)
    local v = {}
    for _, id in ipairs(R.KnownList(list)) do
        v[#v + 1] = { value = id, text = R.SpellName(id) }
    end
    return v
end

-- Deferred: rebuilding inside a setter hands the widget's own write-back to
-- whatever pooled widget the rebuild gave out.
local function rebuild()
    ns.NextFrame(function() ns.UI:BuildOptionsPage("reminder") end)
end

local function toggle(label, get, set, tooltip)
    return { type = "toggle", label = label, tooltip = tooltip,
        get = get, set = function(_, v) set(v); R.Queue() end }
end

local function flag(key, label, tooltip)
    return toggle(label, function() return mod.db[key] end, function(v) mod.db[key] = v end, tooltip)
end

local function slider(key, label, min, max, tooltip)
    return { type = "slider", label = label, tooltip = tooltip, min = min, max = max, step = 1,
        get = function() return mod.db[key] end,
        set = function(_, v) mod.db[key] = v; R.Relayout(); R.Queue() end }
end

local function castPicker(cfg, list)
    return { type = "dropdown", label = L["Spell to cast"], width = 220,
        values = choices(list),
        get = function() return R.CastFor(cfg, list) end,
        set = function(_, v) cfg.pick = v; R.Queue() end }
end

-- A spell ID the client knows: a whole positive number in range.
local function validID(v)
    local id = tonumber(v)
    if not id or id ~= math.floor(id) or id <= 0 or id >= 2147483647 then return nil end
    return R.SpellName(id) and id
end

function mod:GetOptions()
    local db = mod.db
    local o = {
        { type = "group", layout = "row", gap = 10, align = "center", items = {
            { type = "button", label = L["Open Edit Mode"], width = 200, primary = true,
              onClick = function() ns:SetEditMode(true) end },
        } },
        slider("size", L["Icon size"], 24, 64),
        slider("spacing", L["Spacing"], 0, 20),
        flag("showLabels", L["Show names under the icons"]),
        slider("warnMinutes", L["Warn before it runs out (minutes)"], 0, 10, L["0 = only when it is missing."]),

        { type = "header", text = L["Show in"] },
        toggle(L["Open world"], function() return db.where.world end, function(v) db.where.world = v end),
        toggle(L["Dungeons"],   function() return db.where.party end, function(v) db.where.party = v end),
        toggle(L["Raids"],      function() return db.where.raid end,  function(v) db.where.raid = v end),
        toggle(L["Battlegrounds"], function() return db.where.pvp end, function(v) db.where.pvp = v end),
        flag("hideResting", L["Hide in rest areas"]),

        { type = "header", text = L["Buffs"] },
        flag("buffs", L["Remind about missing buffs"]),
    }

    for _, e in ipairs(R.classBuffs) do
        local cfg = R.EntryCfg(e)
        local label = e.label and L[e.label] or R.SpellName(e.cast[1])
        if label and #R.KnownList(e.cast) > 0 then
            o[#o + 1] = toggle(label, function() return cfg.on end, function(v) cfg.on = v end)
            if #e.cast > 1 then o[#o + 1] = castPicker(cfg, e.cast) end
        end
    end

    o[#o + 1] = { type = "header", text = L["Weapon enchants"] }
    o[#o + 1] = flag("weapons", L["Remind about missing weapon enchants"],
        L["A click puts the poison, oil or stone you used last on that weapon again."])
    for _, s in ipairs(R.SLOTS) do
        local cfg = R.SlotCfg(s)
        o[#o + 1] = toggle(L[s.label], function() return cfg.on end, function(v) cfg.on = v end)
        if R.class == "SHAMAN" and #R.KnownList(R.IMBUES) > 0 then
            o[#o + 1] = castPicker(cfg, R.IMBUES)
        end
    end

    o[#o + 1] = { type = "header", text = L["Tracked spells"] }
    o[#o + 1] = flag("camp", R.SpellName(R.CAMP) or L["Campfire buff"],
        L["Shows whenever the campfire buff is missing."])
    for i, id in ipairs(db.customIDs) do
        o[#o + 1] = { type = "button", label = L["Remove %s"]:format(R.SpellName(id) or tostring(id)), width = 240,
            onClick = function() table.remove(db.customIDs, i); R.Queue(); rebuild() end }
    end
    o[#o + 1] = { type = "editbox", label = L["Add a spell by its id"], width = 240,
        tooltip = L["Reminds you whenever this buff is not on you."],
        get = function() return "" end,
        set = function(_, v)
            local id = validID(v)
            if not id then return end
            for _, have in ipairs(db.customIDs) do if have == id then return end end
            db.customIDs[#db.customIDs + 1] = id
            R.Queue()
            rebuild()
        end }
    return o
end
