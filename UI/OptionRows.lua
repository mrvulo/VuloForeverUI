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
--     scale = n }      slider only: shown value = stored value * scale
--
-- Rows are built per call, never at file load: labels are locale lookups and
-- the saved language only exists from ADDON_LOADED on.
local _, ns = ...

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
        if extra.get then row.get = extra.get end
        if extra.set then row.set = extra.set end
        return row
    end

    local rows = {}

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

    function rows.dropdown(key, label, values, extra)
        extra = asExtra(extra)
        return finish({ type = "dropdown", label = label, values = values, width = dropdownWidth,
            get = function() return db()[key] end,
            set = function(_, v) db()[key] = v; changed(extra) end }, extra)
    end

    local function setColor(key, extra)
        return function(r, g, b)
            local c = db()[key]
            c.r, c.g, c.b = r, g, b
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
