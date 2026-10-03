-- VuloForeverUI / Core / Border: one border, everywhere a player can set one.
--
-- Two halves:
--
--   ns.PaintBorder(holder, anchor, spec)   draws it
--   ns.BorderRows(rows, keys, opts)        the options rows that set it
--
-- Every module keeps its own saved keys -- a border is mapped onto them, not
-- moved into a new table, so no profile needs a migration and an import from
-- an older version still lands. What is shared is the behaviour and the page:
-- the same rows in the same order with the same labels and ranges, colour with
-- opacity in the picker, flat edges or a shared-media frame.
local _, ns = ...
local L = ns.L

-- The value a texture dropdown stores for "flat edges, no media frame".
-- Modules that predate this file use "" or "solid"; both are understood.
local function isFlat(texture)
    return texture == nil or texture == "" or texture == "solid"
end

-- ---------------------------------------------------------------- paint --

local function ensure(holder)
    if holder._vfEdges then return end
    holder._vfEdges = ns.MakeEdges(holder, "OVERLAY")
    local bd = CreateFrame("Frame", nil, holder, BackdropTemplateMixin and "BackdropTemplate")
    bd:SetAllPoints(holder)
    bd:Hide()
    holder._vfBackdrop = bd
end

-- spec:
--   size      thickness in physical pixels; 0 or less hides the border
--   color     { r, g, b, a }; spec.alpha, when given, wins over color.a
--   texture   "" / "solid" for flat edges, else a shared-media border name
--   offset    pixels outward from the anchor's edge; negative draws inside
--   offX/offY shift the whole border (flat edges and media frame alike)
--   level     frame level for the media frame
-- Both kinds live on one holder, so switching between them is a repaint.
function ns.PaintBorder(holder, anchor, spec)
    ensure(holder)
    local edges, bd = holder._vfEdges, holder._vfBackdrop
    if spec.level then bd:SetFrameLevel(spec.level) end
    local size = spec.size or 0
    if size <= 0 then
        for _, t in pairs(edges) do t:Hide() end
        bd:Hide()
        return
    end
    local c = spec.color or {}
    local r, g, b = c.r or 0, c.g or 0, c.b or 0
    local a = spec.alpha or c.a or 1
    local offset, offX, offY = spec.offset or 0, spec.offX or 0, spec.offY or 0
    local path = not isFlat(spec.texture) and ns.MediaBorder(spec.texture) or nil

    if not path then
        bd:Hide()
        ns.LayoutEdges(edges, anchor, size, r, g, b, a, offset)
        if offX ~= 0 or offY ~= 0 then
            for _, t in pairs(edges) do
                for i = 1, t:GetNumPoints() do
                    local p1, rel, p2, x, y = t:GetPoint(i)
                    t:SetPoint(p1, rel, p2, (x or 0) + offX, (y or 0) + offY)
                end
            end
        end
        return
    end

    -- A media edge file draws its art across edgeSize, mostly inside it; a
    -- quarter of the edge outside the anchor centres the visible line on it.
    for _, t in pairs(edges) do t:Hide() end
    local edge = math.max(2, size * 4)
    local out = ns:Pixel(anchor, offset) + edge / 4
    bd:ClearAllPoints()
    bd:SetPoint("TOPLEFT", anchor, "TOPLEFT", -out + offX, out + offY)
    bd:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", out + offX, -out + offY)
    if bd.SetBackdrop then
        bd:SetBackdrop({ edgeFile = path, edgeSize = edge })
        bd:SetBackdropBorderColor(r, g, b, a)
    end
    bd:Show()
end

-- The texture dropdown's list: flat edges first, then every shared-media border.
function ns.BorderTextureValues(flatValue)
    local v = { { value = flatValue or "solid", text = L["Flat edges"] } }
    for _, e in ipairs(ns.MediaBorderValues()) do
        if e.value ~= "" then v[#v + 1] = e end
    end
    return v
end

-- ---------------------------------------------------------------- options --

-- keys maps each part of a border onto the module's saved key. Leave a part
-- out and its row is not offered:
--   show        toggle, on = border shown
--   hide        toggle, on = border hidden (shown inverted, as "Show a border")
--   texture     dropdown, flat edges or a shared-media border
--   size        slider, pixels
--   offset      slider, pixels outward (negative: inward)
--   color       colour with opacity
--   alpha       a separate saved opacity the colour row's picker writes to,
--               for modules that keep it apart from the colour table
--   classColor  toggle, the player's class colour instead of `color`
-- opts: { minSize = 0, maxSize = 4, minOffset = -4, maxOffset = 4,
--         flatValue = "solid", noAlpha = true, disabled = fn, after = fn,
--         subKeyPrefix = "..." (keeps rows of two tables apart in the
--                               change tracking when they share a page),
--         tooltips = { size = "...", ... } }
-- after runs instead of the row set's apply, as on any single row.
-- Returns a row list (ns.RowList): it stands in a page like the rows written
-- out one by one.
function ns.BorderRows(rows, keys, opts)
    opts = opts or {}
    local tips = opts.tooltips or {}
    local disabledFn = opts.disabled
    local out = {}

    local function extra(part, more)
        local e = more or {}
        e.tooltip = e.tooltip or tips[part]
        e.after = opts.after
        if opts.subKeyPrefix and keys[part] then e.subKey = opts.subKeyPrefix .. keys[part] end
        if disabledFn and part ~= "show" and part ~= "hide" then
            local own = e.disabled
            e.disabled = own and function() return own() or disabledFn() end or disabledFn
        end
        return e
    end

    -- Everything below the switch greys out while the border is off.
    if keys.show then
        local key = keys.show
        out[#out + 1] = rows.toggle(key, L["Show a border"], extra("show"))
        local prev = disabledFn
        disabledFn = function() return (prev and prev()) or not rows.db()[key] end
    elseif keys.hide then
        local key = keys.hide
        local e = extra("hide")
        e.get = function() return not rows.db()[key] end
        e.set = function(_, v) rows.db()[key] = not v; rows.changed(e) end
        out[#out + 1] = rows.toggle(key, L["Show a border"], e)
        local prev = disabledFn
        disabledFn = function() return (prev and prev()) or rows.db()[key] end
    end

    if keys.texture then
        local key, flat = keys.texture, opts.flatValue or "solid"
        out[#out + 1] = rows.dropdown(key, L["Border texture"], ns.BorderTextureValues(flat), extra("texture", {
            width = 220,
            get = function() local v = rows.db()[key]; return isFlat(v) and flat or v end }))
    end

    if keys.size then
        out[#out + 1] = rows.slider(keys.size, L["Border size"],
            opts.minSize or 0, opts.maxSize or 4, 1, extra("size"))
    end

    if keys.offset then
        out[#out + 1] = rows.slider(keys.offset, L["Border offset"],
            opts.minOffset or -4, opts.maxOffset or 4, 1, extra("offset"))
    end

    if keys.color then
        local more = extra("color", { hasAlpha = not opts.noAlpha })
        if keys.classColor then
            -- The class colour replaces this one while it is on.
            local ck, own = keys.classColor, more.disabled
            more.disabled = function() return (own and own()) or rows.db()[ck] end
        end
        if keys.alpha then
            -- The opacity lives in its own key: the row shows and saves it
            -- as part of the colour so the page has one place for both.
            local ck, ak = keys.color, keys.alpha
            more.hasAlpha = true
            more.get = function()
                local c = rows.db()[ck] or {}
                return { r = c.r, g = c.g, b = c.b, a = rows.db()[ak] or 1 }
            end
            more.set = function(r, g, b, a)
                local c = rows.db()[ck]
                c.r, c.g, c.b = r, g, b
                if a then rows.db()[ak] = a end
                rows.changed(more)
            end
        end
        out[#out + 1] = rows.color(keys.color, L["Border color"], more)
    end

    if keys.classColor then
        out[#out + 1] = rows.toggle(keys.classColor, L["Class-colored border"], extra("classColor"))
    end

    return ns.RowList(out)
end
