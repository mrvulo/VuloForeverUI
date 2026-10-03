-- VuloForeverUI / UI / OptionRows: the row builders every options page uses.
--
--   local rows = ns.OptionRows(db, apply, opts)
--   local toggle, slider = rows.toggle, rows.slider
--
-- db()        returns the table the keys live in. Called on every get and set,
--             never cached: a profile switch swaps the table underneath.
-- apply()     runs after every set. A row's `extra.after` runs instead.
-- opts        { dropdownWidth = n }  default width of a dropdown row.
--
-- Every builder takes (key, label, ...) and ends in `extra`, which is either
-- the tooltip string or a table:
--   { tooltip, inline, disabled, width, subKey, after, get, set,
--     scale = n,       slider only: shown value = stored value * scale
--     hasAlpha = true, colour only: the picker shows an opacity bar, .a is saved
--     suffix = "%" }    slider only: a unit after the number
--
-- Rows are built per call, never at file load: labels are locale lookups and
-- the saved language only exists from ADDON_LOADED on.
local _, ns = ...
local L = ns.L

local function asExtra(extra)
    if type(extra) == "string" then return { tooltip = extra } end
    return extra
end

function ns.OptionRows(db, apply, opts)
    local dropdownWidth = opts and opts.dropdownWidth

    local function changed(extra)
        local after = extra and extra.after
        if after then after() elseif apply then apply() end
    end

    -- The fields every row type shares, copied from `extra` onto the row.
    local function finish(row, extra)
        if not extra then return row end
        row.tooltip = extra.tooltip
        row.inline, row.disabled = extra.inline, extra.disabled
        if extra.width then row.width = extra.width end
        if extra.subKey then row.subKey = extra.subKey end
        if extra.hasAlpha then row.hasAlpha = true end
        if extra.suffix then row.suffix = extra.suffix end
        if extra.get then row.get = extra.get end
        if extra.set then row.set = extra.set end
        return row
    end

    -- Exposed for builders that compose rows of their own (ns.BorderRows):
    -- the bound table, and "a setting changed" with the same after/apply rule.
    local rows = { db = db, changed = changed }

    function rows.toggle(key, label, extra)
        extra = asExtra(extra)
        return finish({ type = "toggle", label = label,
            get = function() return db()[key] end,
            set = function(_, v) db()[key] = v and true or false; changed(extra) end }, extra)
    end

    function rows.slider(key, label, min, max, step, extra)
        extra = asExtra(extra)
        local scale = extra and extra.scale or 1
        local get, set
        if scale == 1 then
            get = function() return db()[key] end
            set = function(_, v) db()[key] = v; changed(extra) end
        else
            get = function() return (db()[key] or 0) * scale end
            set = function(_, v) db()[key] = v / scale; changed(extra) end
        end
        return finish({ type = "slider", label = label, min = min, max = max,
            step = step or 1, get = get, set = set }, extra)
    end

    -- Opacity, the same everywhere: shown as 0-100 %, saved as 0..1 (or as
    -- 0..100 with extra.percent, for the keys that were always saved that way).
    -- extra.min / extra.max are in per cent.
    function rows.opacity(key, label, extra)
        extra = asExtra(extra) or {}
        local scale = extra.percent and 1 or 100
        return finish({ type = "slider", label = label, suffix = "%",
            min = extra.min or 0, max = extra.max or 100, step = extra.step or 1,
            get = function() return (db()[key] or 0) * scale end,
            set = function(_, v) db()[key] = v / scale; changed(extra) end }, extra)
    end

    function rows.dropdown(key, label, values, extra)
        extra = asExtra(extra)
        return finish({ type = "dropdown", label = label, values = values, width = dropdownWidth,
            get = function() return db()[key] end,
            set = function(_, v) db()[key] = v; changed(extra) end }, extra)
    end

    local function setColor(key, extra)
        return function(r, g, b, a)
            local t = db()
            local c = t[key]
            if type(c) ~= "table" then c = {}; t[key] = c end
            c.r, c.g, c.b = r, g, b
            if a and extra and extra.hasAlpha then c.a = a end
            changed(extra)
        end
    end

    function rows.color(key, label, extra)
        extra = asExtra(extra)
        return finish({ type = "color", label = label,
            get = function() return db()[key] end, set = setColor(key, extra) }, extra)
    end

    -- A colour swatch inline next to another row, without a label of its own.
    function rows.swatch(key, extra)
        extra = asExtra(extra)
        return finish({ kind = "color",
            get = function() return db()[key] end, set = setColor(key, extra) }, extra)
    end

    return rows
end

-- A list of rows that stands in a page as if its rows were written there one
-- by one (ns.BorderRows returns one). Flattened by ns.ModuleOptions.
function ns.RowList(list)
    list._splice = true
    return list
end

local function splice(list)
    if type(list) ~= "table" then return list end
    local i = 1
    while i <= #list do
        local it = list[i]
        if type(it) == "table" and it._splice then
            table.remove(list, i)
            for k = #it, 1, -1 do table.insert(list, i, it[k]) end
        else
            if type(it) == "table" then
                splice(it.items)
                splice(it.inline)
                if type(it.popup) == "table" then splice(it.popup.items) end
            end
            i = i + 1
        end
    end
    return list
end

-- A module's rows for one tab: GetOptions, protected, with row lists
-- flattened. Every place that reads a module's options goes through here.
-- Returns ok, items (or ok == false and the error).
function ns.ModuleOptions(mod, tabId)
    if not (mod and mod.GetOptions) then return false, "no options" end
    local ok, items = pcall(mod.GetOptions, mod, tabId)
    if ok and type(items) == "table" then splice(items) end
    return ok, items
end

-- The font outline choices, the same words on every page. `first` is an
-- optional row on top ("from the font settings").
function ns.OutlineValues(first)
    local v = {
        { value = "NONE",         text = L["None"] },
        { value = "OUTLINE",      text = L["Outline"] },
        { value = "THICKOUTLINE", text = L["Thick outline"] },
    }
    if first then table.insert(v, 1, first) end
    return v
end

-- The two layout rows that bind to nothing.
function ns.OptionSection(title, items)
    return { type = "section", title = title, items = items }
end

function ns.OptionGear(title, items, extra)
    extra = asExtra(extra)
    return { kind = "gear", tooltip = extra and extra.tooltip or title,
        disabled = extra and extra.disabled,
        popup = { title = title, width = 300, items = items } }
end
