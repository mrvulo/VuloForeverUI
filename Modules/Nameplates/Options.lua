-- VuloForeverUI / Modules / Nameplates / Options
--
-- Three pages: Display (what a plate looks like), Colors (which colour when),
-- General (spacing, target extras, behaviour). Rows are built per call --
-- labels are locale lookups and the saved language only exists from
-- ADDON_LOADED on.
--
-- Every setter ends in NP.Bump(): live plates restyle once, pooled ones pick
-- the change up from the generation stamp.
local _, ns = ...
local L = ns.L
local NP = ns.NP
local M = NP.mod

M.tabs = {
    { id = "display", label = "Display" },
    { id = "colors",  label = "Colors" },
    { id = "general", label = "General" },
}

-- ---------------------------------------------------------------------------
-- Row helpers. `after` runs instead of the plain NP.Bump when a setting needs
-- more than a restyle (a CVar, the clickable area).
-- ---------------------------------------------------------------------------
local function db() return M.db end

local function apply(after)
    if after then after() else NP.Bump() end
end

local function toggle(key, label, tooltip, extra)
    local row = { type = "toggle", label = label, tooltip = tooltip,
        get = function() return db()[key] end,
        set = function(_, v) db()[key] = v and true or false; apply(extra and extra.after) end }
    if extra then row.inline, row.disabled = extra.inline, extra.disabled end
    return row
end

-- scale: the stored value times `scale` is what the slider shows (alpha 0..1
-- stored, 0..100 shown).
local function slider(key, label, min, max, step, extra)
    local scale = extra and extra.scale or 1
    local row = { type = "slider", label = label, min = min, max = max, step = step or 1,
        tooltip = extra and extra.tooltip,
        get = function() return (db()[key] or 0) * scale end,
        set = function(_, v) db()[key] = v / scale; apply(extra and extra.after) end }
    if extra then row.inline, row.disabled = extra.inline, extra.disabled end
    return row
end

local function dropdown(key, label, values, extra)
    local row = { type = "dropdown", label = label, values = values,
        tooltip = extra and extra.tooltip,
        get = function() return db()[key] end,
        set = function(_, v) db()[key] = v; apply(extra and extra.after) end }
    if extra then
        row.inline, row.disabled = extra.inline, extra.disabled
        if extra.get then row.get = extra.get end
        if extra.set then row.set = extra.set end
    end
    return row
end

local function swatch(key, tooltip, disabled)
    return { kind = "color", tooltip = tooltip, disabled = disabled,
        get = function() return db()[key] end,
        set = function(r, g, b)
            local c = db()[key]
            c.r, c.g, c.b = r, g, b
            NP.Bump()
        end }
end

local function color(key, label, tooltip, disabled)
    return { type = "color", label = label, tooltip = tooltip, disabled = disabled,
        get = function() return db()[key] end,
        set = function(r, g, b)
            local c = db()[key]
            c.r, c.g, c.b = r, g, b
            NP.Bump()
        end }
end

local function gear(title, items, tooltip, disabled)
    return { kind = "gear", tooltip = tooltip or title, disabled = disabled,
        popup = { title = title, width = 300, items = items } }
end

local function resize(title, items, disabled)
    return { kind = "expand", tooltip = title, disabled = disabled,
        popup = { title = title, width = 300, items = items } }
end

local function section(title, items)
    return { type = "section", title = title, items = items }
end

local function textures(withNone)
    local v = {}
    if withNone then v[1] = { value = "none", text = L["None"] } end
    for _, e in ipairs(ns.MediaStatusbarValues()) do v[#v + 1] = e end
    return v
end

-- ---------------------------------------------------------------------------
-- Display
-- ---------------------------------------------------------------------------
local function textSlotLabel(slot)
    local t = { Top = L["Top Text"], Right = L["Right Text"], Left = L["Left Text"], Center = L["Center Text"] }
    return t[slot]
end

local function iconSlotLabel(slot)
    local t = { top = L["Top"], right = L["Right"], left = L["Left"],
                topright = L["Top right"], topleft = L["Top left"], bottom = L["Bottom"] }
    return t[slot]
end

local function textSlotRow(slot)
    local elements = {
        { value = "none",                text = L["None"] },
        { value = "enemyName",           text = L["Enemy Name"] },
        { value = "levelName",           text = L["Level | Name"] },
        { value = "nameLevel",           text = L["Name | Level"] },
        { value = "level",               text = L["Level"] },
        { value = "healthPercent",       text = L["Health %"] },
        { value = "healthPercentNoSign", text = L["Health % (No Sign)"] },
        { value = "healthNumber",        text = L["Health #"] },
        { value = "healthPctNum",        text = L["Health % | #"] },
        { value = "healthNumPct",        text = L["Health # | %"] },
        { value = "healthPctNumDash",    text = L["Health % - #"] },
        { value = "healthNumPctDash",    text = L["Health # - %"] },
    }
    local cfg = function() return db().textSlots[slot] end
    local empty = function() return cfg().element == "none" end
    local notHealth = function() return not NP.HEALTH_ELEMENTS[cfg().element] end
    local title = textSlotLabel(slot)
    -- rows that write into the slot's own table rather than the module db
    local function num(field, label, min, max)
        return { type = "slider", label = label, min = min, max = max, step = 1,
            get = function() return cfg()[field] end,
            set = function(_, v) cfg()[field] = v; NP.Bump() end }
    end
    return { type = "dropdown", label = title, values = elements,
        get = function() return cfg().element end,
        set = function(_, v) NP.AssignTextSlot(slot, v) end,
        inline = {
            { kind = "color", tooltip = L["Text color"], disabled = empty,
              get = function() return cfg().color end,
              set = function(r, g, b) local c = cfg().color; c.r, c.g, c.b = r, g, b; NP.Bump() end },
            resize(title, {
                num("size", L["Size"], 6, 30),
                num("x", L["X Offset"], -300, 300),
                num("y", L["Y Offset"], -300, 300),
                toggle("enemyNameWrap", L["Wrap name to two lines"]),
                slider("enemyNameWidthPct", L["Name width %"], 10, 150),
                { type = "toggle", label = L["Show % Decimal"], disabled = notHealth,
                  get = function() return cfg().decimal end,
                  set = function(_, v) cfg().decimal = v and true or false; NP.Bump() end },
            }, empty),
        } }
end

local function iconSlotRow(slot)
    local elements = {
        { value = "none",           text = L["None"] },
        { value = "debuffs",        text = L["Debuffs"] },
        { value = "buffs",          text = L["Buffs"] },
        { value = "cc",             text = L["Crowd Control"] },
        { value = "raidMarker",     text = L["Raid Marker"] },
        { value = "classification", text = L["Rare/Elite Indicator"] },
    }
    local empty = function() return NP.IconInSlot(slot) == "none" end
    local title = iconSlotLabel(slot)
    return { type = "dropdown", label = title, values = elements,
        get = function() return NP.IconInSlot(slot) end,
        set = function(_, v) NP.AssignIconSlot(slot, v) end,
        inline = {
            resize(title, {
                { type = "slider", label = L["Size"], min = 10, max = 50, step = 1,
                  get = function() return db().iconSlots[slot].size end,
                  set = function(_, v) db().iconSlots[slot].size = v; NP.Bump() end },
                { type = "slider", label = L["X Offset"], min = -300, max = 300, step = 1,
                  get = function() return db().iconSlots[slot].x end,
                  set = function(_, v) db().iconSlots[slot].x = v; NP.Bump() end },
                { type = "slider", label = L["Y Offset"], min = -300, max = 300, step = 1,
                  get = function() return db().iconSlots[slot].y end,
                  set = function(_, v) db().iconSlots[slot].y = v; NP.Bump() end },
                toggle("classificationShowInInstances", L["Show rare/elite icon in instances"]),
            }, empty),
        } }
end

local function sideValues(withCenter)
    local v = { { value = "none", text = L["None"] }, { value = "left", text = L["Left"] },
                { value = "right", text = L["Right"] } }
    if withCenter then v[#v + 1] = { value = "center", text = L["Centre"] } end
    return v
end

-- Auras. Everything here is a setting the ENGINE acts on: how many icons it may
-- show, how they are cut and where its own texts sit. A change to the button
-- style cannot reach buttons that already exist -- they belong to the engine --
-- so those rows throw the containers away and let fresh ones be built.
local function restyleAuras()
    NP.Bump()
    NP.Auras.Rebuild()
end

local function auraKindRows(kind, label)
    local cfg = function() return db().auras[kind] end
    local function num(field, text, min, max, after)
        return { type = "slider", label = text, min = min, max = max, step = 1,
            get = function() return cfg()[field] end,
            set = function(_, v) cfg()[field] = v; (after or NP.Bump)() end }
    end
    local function flag(field, text, after)
        return { type = "toggle", label = text,
            get = function() return cfg()[field] end,
            set = function(_, v) cfg()[field] = v and true or false; (after or NP.Bump)() end }
    end
    return { type = "dropdown", label = label, values = {
            { value = "none", text = L["None"] }, { value = "top", text = L["Top"] },
            { value = "bottom", text = L["Bottom"] }, { value = "left", text = L["Left"] },
            { value = "right", text = L["Right"] },
            { value = "topleft", text = L["Top left"] }, { value = "topright", text = L["Top right"] },
        },
        get = function() return NP.SlotOfAura(kind) end,
        set = function(_, v) NP.AssignIconSlot(v, v ~= "none" and kind or "none") end,
        inline = {
            resize(label, {
                num("max", L["Max Icons"], 1, 10),
                num("spacing", L["Spacing"], -5, 20),
                flag("crop", L["Cropped Icons"], restyleAuras),
                num("cropPct", L["Adjust Crop"], 5, 25, restyleAuras),
                flag("hideBorder", L["Hide Border"], restyleAuras),
            }),
        } }
end

local function auraTextRows(key, label)
    local cfg = function() return db().auraText[key] end
    local positions = {
        { value = "none",        text = L["None"] },
        { value = "topleft",     text = L["Top left"] },
        { value = "topright",    text = L["Top right"] },
        { value = "bottomleft",  text = L["Bottom left"] },
        { value = "bottomright", text = L["Bottom right"] },
        { value = "centre",      text = L["Centre"] },
    }
    local function num(field, text, min, max)
        return { type = "slider", label = text, min = min, max = max, step = 1,
            get = function() return cfg()[field] end,
            set = function(_, v) cfg()[field] = v; restyleAuras() end }
    end
    return { type = "dropdown", label = label, values = positions,
        get = function() return cfg().position end,
        set = function(_, v) cfg().position = v; restyleAuras() end,
        inline = {
            { kind = "color", tooltip = L["Text color"],
              get = function() return cfg().color end,
              set = function(r, g, b) local c = cfg().color; c.r, c.g, c.b = r, g, b; restyleAuras() end },
            resize(label, {
                num("size", L["Size"], 6, 20),
                num("x", L["X Offset"], -50, 50),
                num("y", L["Y Offset"], -50, 50),
            }),
        } }
end

local function aurasSection()
    return section(L["Auras"], {
        { type = "desc", text = L["|cffaaaaaaThe game decides which auras a nameplate may show and draws them itself; these settings say where they go and how many.|r"] },
        auraKindRows("debuffs", L["Debuffs"]),
        auraKindRows("buffs", L["Buffs"]),
        auraKindRows("cc", L["Crowd Control"]),
        toggle("debuffIncludeCC", L["Debuffs include Crowd Control"]),
        toggle("showAllDebuffs", L["Show All Debuffs"], L["Also show debuffs cast by other players."]),
        dropdown("enemyBuffFilter", L["Enemy Buff Filter"], {
            { value = "important",   text = L["Important"] },
            { value = "dispellable", text = L["Only Dispellable"] },
        }),
        auraTextRows("duration", L["Duration Text"]),
        auraTextRows("stacks", L["Stack Text"]),
    })
end

local function displayPage()
    local d = db()
    local absorbStyles = { { value = "blizzard", text = L["Blizzard"] }, { value = "clean", text = L["Clean (Flat)"] } }
    for _, e in ipairs(ns.MediaStatusbarValues()) do absorbStyles[#absorbStyles + 1] = e end

    local style = section(L["Style"], {
        toggle("showBorder", L["Border"], nil, { inline = {
            swatch("borderColor", L["Border color"]),
            gear(L["Castbar Border"], { toggle("wrapBorderCastbar", L["Wrap Around Castbar"]) }),
        } }),
        slider("borderSize", L["Border Size"], 1, 4, 1, { disabled = function() return not d.showBorder end }),
        slider("bgAlpha", L["Background"], 0, 100, 1, { scale = 100, inline = { swatch("bgColor", L["Background color"]) } }),
        dropdown("absorbStyle", L["Absorb Style"], absorbStyles, { inline = {
            swatch("absorbColor", L["Absorb color"], function() return d.absorbStyle == "blizzard" end),
            gear(L["Absorb Style"], { slider("absorbAlpha", L["Opacity"], 5, 100) }),
        } }),
        dropdown("healthBarTexture", L["Bar Texture"], ns.MediaStatusbarValues()),
        dropdown("castBarTexture", L["Cast Bar Texture"], ns.MediaStatusbarValues()),
    })

    local positions = section(L["Core Positions"], {
        iconSlotRow("top"), iconSlotRow("right"), iconSlotRow("left"),
        iconSlotRow("topright"), iconSlotRow("topleft"), iconSlotRow("bottom"),
    })

    local texts = section(L["Core Text Positions"], {
        textSlotRow("Top"), textSlotRow("Right"), textSlotRow("Left"), textSlotRow("Center"),
        toggle("levelDifficultyColor", L["Color level by difficulty"]),
    })

    local bars = section(L["Health and Cast Bar"], {
        slider("healthBarWidth", L["Health Bar Width"], 100, 250, 1, { after = function() NP.Bump(); NP.ApplyHitbox() end }),
        slider("healthBarHeight", L["Health Bar Height"], 6, 50, 1, { after = function() NP.Bump(); NP.ApplyHitbox() end }),
        slider("castBarHeight", L["Cast Bar Height"], 10, 40),
        toggle("showCastIcon", L["Spell Icon"], nil, { inline = { gear(L["Spell Icon Settings"], {
            slider("castIconScale", L["Scale"], 0.5, 2, 0.1),
            slider("castIconOffsetX", L["X Offset"], -50, 50),
            slider("castIconOffsetY", L["Y Offset"], -50, 50),
            toggle("castbarIconInWidth", L["Make Icon Part of the Bar"]),
            toggle("castIconOnRight", L["Icon on Right"]),
            toggle("castIconFullSize", L["Full Sized (Health + Cast Bar)"]),
            toggle("hideCastIconBorder", L["Hide Border"]),
            toggle("castIconTargetBorder", L["Use Target Border Color"]),
        }) } }),
        slider("castBgAlpha", L["Cast Background"], 0, 100, 1, { scale = 100, inline = { swatch("castBgColor", L["Background color"]) } }),
        slider("castBorderSize", L["Cast Bar Border"], 0, 4, 1, { inline = { swatch("castBorderColor", L["Border color"]) } }),
        dropdown("castTimerSide", L["Cast Timer"], sideValues(false), {
            get = function() return d.showCastTimer and d.castTimerSide or "none" end,
            set = function(_, v)
                d.showCastTimer = v ~= "none"
                if v ~= "none" then d.castTimerSide = v end
                NP.Bump()
            end,
            inline = {
                swatch("castTimerColor", L["Text color"]),
                resize(L["Cast Timer"], {
                    slider("castTimerSize", L["Size"], 6, 20),
                    slider("castTimerOffsetX", L["X Offset"], -300, 300),
                    slider("castTimerOffsetY", L["Y Offset"], -300, 300),
                }),
            } }),
        slider("castBarOffsetY", L["Cast Bar Y Offset"], -25, 75),
    })

    local kickHint = { { value = "none", text = L["None"] }, { value = "tick", text = L["Tick"] },
                       { value = "bar", text = L["Tick + Bar"] } }
    local castColors = section(L["Cast Colors and Effects"], {
        color("castBar", L["Interruptible Cast"]),
        color("interruptReady", L["Interrupt on CD"], L["The bar's colour while your interrupt is on cooldown."]),
        color("castBarUninterruptible", L["Uninterruptible Cast"]),
        toggle("importantCastColorEnabled", L["Important Cast Color"], nil, { inline = { swatch("castBarImportant", L["Important Cast"]) } }),
        toggle("castBarShieldEnabled", L["Show Shield Icon"]),
        toggle("castBarSparkEnabled", L["Show Spark"]),
        dropdown("kickTickEnabled", L["Kick Ready Mid-Cast Hint"], kickHint, {
            tooltip = L["Marks the moment on the cast bar at which your interrupt comes off cooldown."],
            get = function()
                if not d.kickTickEnabled then return "none" end
                return d.interruptMidCastEnabled and "bar" or "tick"
            end,
            set = function(_, v)
                d.kickTickEnabled = v ~= "none"
                d.interruptMidCastEnabled = v == "bar"
                NP.Bump()
            end,
            inline = {
                swatch("interruptMidCastColor", L["Bar color"], function() return not d.interruptMidCastEnabled end),
                swatch("kickTickColor", L["Tick color"]),
            } }),
        toggle("importantCastGlow", L["Important Cast Glow"], nil, { inline = { swatch("importantCastGlowColor", L["Glow color"]) } }),
        toggle("interruptedFlashEnabled", L["Show Interrupted Flash Effect"], nil, { inline = {
            swatch("interruptedFlashColor", L["Flash color"], function() return not d.interruptedFlashEnabled end) } }),
    })

    local function overlayRow(prefix, label, colorKey, alphaKey)
        local none = function() return d[prefix .. "OverlayTexture"] == "none" end
        local items = { toggle(prefix .. "OverlayFullBgAlpha", L["Full alpha on empty part of bar"]) }
        if alphaKey then
            table.insert(items, 1, slider(alphaKey, L["Opacity"], 5, 100, 1, { scale = 100 }))
            items[#items + 1] = toggle(prefix .. "OverlayNoTint", L["Don't tint (keep bar's own color)"])
        end
        local inline = { gear(label, items, nil, none) }
        if colorKey then table.insert(inline, 1, swatch(colorKey, L["Texture color"], none)) end
        return dropdown(prefix .. "OverlayTexture", label, textures(true), { inline = inline })
    end

    local effects = section(L["Target, Focus & Hover Effects"], {
        toggle("targetGlow", L["Target: Glow"], nil, { inline = {
            swatch("targetGlowColor", L["Glow color"]),
            gear(L["Target: Glow"], { slider("targetGlowAlpha", L["Glow Opacity"], 0, 100, 1, { scale = 100 }) }),
        } }),
        toggle("targetGlowBorderColor", L["Target: Border Color"], nil, { inline = { swatch("targetBorderColor", L["Border color"]) } }),
        toggle("targetGlowBorderSize", L["Target: Border Size"], nil, { inline = {
            gear(L["Target: Border Size"], { slider("targetBorderSizeValue", L["Border Size"], 0, 4) }) } }),
        toggle("targetGlowHighlight", L["Target: Highlight"], nil, { inline = {
            swatch("targetHighlightColor", L["Highlight Color"]),
            gear(L["Target: Highlight"], { slider("targetHighlightAlpha", L["Highlight Opacity"], 0, 100, 1, { scale = 100 }) }),
        } }),
        toggle("showTargetArrows", L["Target Arrows"], nil, { inline = {
            swatch("targetArrowColor", L["Arrow color"], function() return d.targetArrowClassColor end),
            gear(L["Target Arrows"], {
                slider("targetArrowScale", L["Scale"], 0.5, 3, 0.1),
                toggle("targetArrowClassColor", L["Use my class color"]),
            }),
        } }),
        toggle("targetColorEnabled", L["Enable Target Color"], nil, { inline = { swatch("target", L["Target color"]) } }),
        toggle("focusColorEnabled", L["Enable Focus Color"], nil, { inline = { swatch("focus", L["Focus color"]) } }),
        overlayRow("target", L["Target Texture"], "targetOverlayColor", "targetOverlayAlpha"),
        overlayRow("focus", L["Focus Texture"], "focusOverlayColor", "focusOverlayAlpha"),
        overlayRow("hover", L["Hover Texture"]),
        toggle("hoverGlowHighlight", L["Hover: Highlight"], nil, { inline = {
            swatch("hoverColor", L["Highlight Color"]),
            gear(L["Hover: Highlight"], { slider("hoverAlpha", L["Highlight Opacity"], 0, 100, 1, { scale = 100 }) }),
        } }),
        toggle("hoverGlow", L["Hover: Glow"], nil, { inline = {
            swatch("hoverGlowColor", L["Glow color"]),
            gear(L["Hover: Glow"], { slider("hoverGlowAlpha", L["Glow Opacity"], 0, 100, 1, { scale = 100 }) }),
        } }),
        toggle("hoverGlowBorderColor", L["Hover: Border Color"], nil, { inline = { swatch("hoverBorderColor", L["Border color"]) } }),
        toggle("hoverGlowBorderSize", L["Hover: Border Size"], nil, { inline = {
            gear(L["Hover: Border Size"], { slider("hoverBorderSizeValue", L["Border Size"], 0, 4) }) } }),
    })

    -- Spell name and spell target may not share a side: taking the other
    -- one's side sends that one to "none".
    local function castTextSide(key, otherKey)
        return function(_, v)
            if v ~= "none" and d[otherKey] == v then d[otherKey] = "none" end
            d[key] = v
            NP.Bump()
        end
    end
    local castText = section(L["Cast Bar Text"], {
        dropdown("castNameSide", L["Spell Name"], sideValues(true), {
            set = castTextSide("castNameSide", "castTargetSide"),
            inline = {
                swatch("castNameColor", L["Text color"]),
                resize(L["Spell Name Settings"], {
                    slider("castNameSize", L["Size"], 6, 20),
                    slider("castNameOffsetX", L["X Offset"], -300, 300),
                    slider("castNameOffsetY", L["Y Offset"], -300, 300),
                    toggle("castNameWrap", L["Wrap"]),
                    slider("castNameWidthPct", L["Width %"], 10, 150),
                    toggle("castCombineNameTarget", L["Combine Spell Name and Target"]),
                }),
            } }),
        dropdown("castTargetSide", L["Spell Target"], sideValues(true), {
            set = castTextSide("castTargetSide", "castNameSide"),
            disabled = function() return d.castCombineNameTarget end,
            inline = {
                swatch("castTargetColor", L["Text color"], function() return d.castTargetClassColor end),
                resize(L["Spell Target"], {
                    slider("castTargetSize", L["Size"], 6, 20),
                    slider("castTargetOffsetX", L["X Offset"], -300, 300),
                    slider("castTargetOffsetY", L["Y Offset"], -300, 300),
                    slider("castTargetWidthPct", L["Width %"], 10, 150),
                    toggle("castTargetWrap", L["Wrap"]),
                    toggle("castTargetClassColor", L["Class color"]),
                }),
            } }),
    })

    return { style, positions, texts, aurasSection(), bars, castColors, effects, castText }
end

-- ---------------------------------------------------------------------------
-- Colors
-- ---------------------------------------------------------------------------
local function colorsPage()
    local d = db()
    local enemy = section(L["Enemy Colors"], {
        color("enemyInCombat", L["Enemies"]),
        color("caster", L["Spell Casters"], L["Enemies that use mana."]),
        color("miniboss", L["Elites"]),
        color("boss", L["Bosses"], L["World bosses and skull-level enemies."]),
        color("neutral", L["Neutral"]),
        color("tapped", L["Tapped"], L["Enemies another player has tagged."]),
        toggle("darkenEnemiesOOC", L["Darken Enemies Out of Combat"], nil, { inline = {
            gear(L["Out of Combat"], {
                toggle("darkenOOCRecolor", L["Change Color Instead"]),
                color("darkenOOCColor", L["Out of Combat Color"], nil, function() return not d.darkenOOCRecolor end),
            }) } }),
        toggle("enemyNameTextReactionColor", L["Color Name by Reaction"], nil, { inline = {
            swatch("enemyNameNeutralColor", L["Neutral Color"], function() return not d.enemyNameTextReactionColor end),
            swatch("enemyNameHostileColor", L["Hostile Color"], function() return not d.enemyNameTextReactionColor end),
        } }),
    })

    local recolor = { after = function() NP.Colors.RefreshAll() end }
    local threat = section(L["Threat Colors (Groups Only)"], {
        { type = "desc", text = L["|cffaaaaaaThreat colours apply while you are in a party or raid.|r"] },
        toggle("assumeTank", L["I am the tank"], L["Use the tank colours. The game has no tank role to read on this client."], recolor),
        color("tankLosingAggro", L["Tank: Losing Aggro"]),
        color("tankNoAggro", L["Tank: No Aggro"]),
        color("dpsHasAggro", L["Non-Tank: Has Aggro"]),
        color("dpsNearAggro", L["Non-Tank: Near Aggro"]),
        toggle("dpsNoAggroEnabled", L["DPS: Show Special \"No Aggro\" Color"], nil, { inline = {
            swatch("dpsNoAggro", L["No Aggro"]),
            gear(L["No Aggro"], {
                toggle("dpsNoAggroOverrideMiniBoss", L["Override Elite colors"]),
                toggle("dpsNoAggroOverrideCaster", L["Override Caster colors"]),
                toggle("dpsNoAggroOverrideBoss", L["Override Boss colors"]),
            }),
        } }),
        toggle("classicTankAggro", L["Classic Tank Aggro"], L["Every enemy you hold takes the \"Has Aggro\" colour, whatever its type."],
            { inline = { swatch("tankHasAggro", L["Has Aggro"]) } }),
        toggle("tankHasAggroEnabled", L["Tank: Show Special \"Has Aggro\" Color"], nil, { inline = {
            swatch("tankHasAggro", L["Has Aggro"]),
            gear(L["Has Aggro"], {
                toggle("tankHasAggroOverrideMobType", L["Override Elite and Caster colors"]),
                toggle("tankHasAggroOverrideBoss", L["Override Boss colors"]),
            }),
        } }),
        toggle("offTankAggroEnabled", L["Tank: Show Special \"Off-Tank\" Color"], nil, { inline = { swatch("offTankAggro", L["Off-Tank"]) } }),
    })
    return { enemy, threat }
end

-- ---------------------------------------------------------------------------
-- General
-- ---------------------------------------------------------------------------
local function friendlySection()
    local d = db()
    local refresh = { after = function() NP.Friendly.Refresh() end }
    local off = function() return not d.showFriendlyPlayers end
    local notNameOnly = function() return not (d.showFriendlyPlayers and d.friendlyNameOnly) end
    return section(L["Friendly Nameplates"], {
        { type = "desc", text = L["|cffaaaaaaIn name-only mode the game draws these plates itself and only the font changes -- which is also the only thing that still works inside a dungeon, where friendly plates are closed to addons.|r"] },
        toggle("showFriendlyPlayers", L["Show Friendly Players"], nil, refresh),
        toggle("friendlyNameOnly", L["Name Only"],
            L["Just the name, drawn by the game. Switch it off for a full plate with a health bar."],
            { after = refresh.after, disabled = off }),
        slider("friendlyNameSize", L["Friendly Name Size"], 8, 30, 1,
            { after = function() NP.Friendly.Apply() end, disabled = notNameOnly }),
        toggle("classColorFriendly", L["Class Color"], nil, { after = refresh.after, disabled = off,
            inline = { swatch("friendlyBarColor", L["Bar color"], function() return d.classColorFriendly end) } }),
        toggle("showFriendlyNPCs", L["Show Friendly NPCs"], nil, { after = refresh.after,
            inline = { swatch("friendlyNPCColor", L["NPC Color"], function() return not d.showFriendlyNPCs end) } }),
        toggle("friendlyClickThrough", L["Friendly Names Not Clickable"], nil, refresh),
    })
end

local function generalPage()
    local d = db()
    local hitbox = { after = function() NP.ApplyHitbox() end }
    local spacing = section(L["Nameplate Spacing"], {
        toggle("stackingEnabled", L["Stacking Nameplates"], L["Enemy nameplates move apart instead of overlapping."],
            { after = function() NP.ApplyCVars(); NP.Bump() end }),
        slider("stackSpacingScale", L["Stacked Nameplate Spacing"], 50, 200, 5),
        slider("hitboxScaleX", L["Hitbox Size X"], 50, 250, 5, hitbox),
        slider("hitboxScaleY", L["Hitbox Size Y"], 50, 250, 5, hitbox),
        { type = "desc", text = L["|cffaaaaaaThe clickable area can only change out of combat; a change made in a fight applies when it ends.|r"] },
    })

    local targetFocus = section(L["Target and Focus Effects"], {
        toggle("hashLineEnabled", L["Show Hash Line on Target at Percent"], nil, { inline = { swatch("hashLineColor", L["Line color"]) } }),
        slider("hashLinePercent", L["Hash Line Location"], 0, 100, 1, { disabled = function() return not d.hashLineEnabled end }),
        slider("targetScale", L["Scale Target Nameplate (Percent)"], 50, 200, 5),
        slider("nonTargetAlpha", L["Non-Target Opacity"], 0, 100, 1, { inline = {
            gear(L["Non-Target Opacity"], { toggle("nonTargetKeepFocus", L["Keep Focus Full Opacity"]) }) } }),
        slider("focusCastHeight", L["Focus Cast Height"], 100, 200, 5),
        toggle("focusLetterEnabled", L["Focus Letter"], nil, { inline = { gear(L["Focus Letter"], {
            dropdown("focusLetterAnchor", L["Anchor"], ns.AnchorPointValues()),
            slider("focusLetterSize", L["Size"], 6, 40),
            slider("focusLetterX", L["X Offset"], -100, 100),
            slider("focusLetterY", L["Y Offset"], -100, 100),
        }) } }),
    })

    local extras = {
        slider("castScale", L["Scale Nameplate On Cast"], 50, 200, 5),
        toggle("hideEnemyNameWhileCasting", L["Hide Enemy Name While Casting"]),
        toggle("nameRaidMarkerEnabled", L["Name Raid Marker"], L["A small raid marker next to the name."], { inline = {
            gear(L["Name Raid Marker"], { slider("nameRaidMarkerSize", L["Size"], 6, 32) }) } }),
        toggle("showEnemyPets", L["Show Enemy Pet Nameplates"], nil, { after = function() NP.ApplyCVars() end }),
        toggle("hideEnemyPlatesOOC", L["Hide Enemy Nameplates out of Combat"], nil, { after = function() NP.ApplyShowEnemies() end }),
    }
    -- A pure client setting with no copy in the profile; only offered when
    -- this client has it.
    if C_CVar.GetCVar("nameplateOccludedAlphaMult") ~= nil then
        extras[#extras + 1] = { type = "slider", label = L["Line of Sight Opacity"], min = 0, max = 1, step = 0.01,
            tooltip = L["How visible nameplates stay behind walls and terrain. Cannot change in combat."],
            get = function() return tonumber(C_CVar.GetCVar("nameplateOccludedAlphaMult")) or 1 end,
            set = function(_, v)
                if not InCombatLockdown() then pcall(C_CVar.SetCVar, "nameplateOccludedAlphaMult", tostring(v)) end
            end }
    end
    return { friendlySection(), spacing, targetFocus, section(L["Extras"], extras) }
end

function M:GetOptions(tabId)
    if tabId == "colors" then return colorsPage() end
    if tabId == "general" then return generalPage() end
    return displayPage()
end
