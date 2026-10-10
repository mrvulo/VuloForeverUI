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

local rows = ns.OptionRows(db, function() NP.Bump() end)
local toggle, slider, dropdown, opacity = rows.toggle, rows.slider, rows.dropdown, rows.opacity
local color, swatch = rows.color, rows.swatch
local gear, section = ns.OptionGear, ns.OptionSection

local function resize(title, items, disabled)
    return { kind = "expand", tooltip = title, disabled = disabled,
        popup = { title = title, width = 300, items = items } }
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
                  set = function(_, v)
                      db().iconSlots[slot].size = v
                      NP.Bump()
                      if NP.IconInSlot(slot) ~= "none" then NP.Auras.Rebuild() end
                  end },
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
        set = function(_, v)
            -- "none" clears THIS kind's slot; AssignIconSlot("none", "none")
            -- would have cleared nothing at all.
            if v == "none" then
                NP.AssignIconSlot(NP.SlotOfAura(kind), "none")
            else
                NP.AssignIconSlot(v, kind)
            end
            -- a kind that gains or loses its slot needs its container built
            -- or dropped, which only a rebuild does
            NP.Auras.Rebuild()
        end,
        inline = {
            resize(label, {
                { type = "dropdown", label = L["Grow direction"], values = {
                        { value = "auto",  text = L["Automatic"] },
                        { value = "up",    text = L["Up"] },
                        { value = "down",  text = L["Down"] },
                        { value = "left",  text = L["Left"] },
                        { value = "right", text = L["Right"] },
                    },
                    get = function() return cfg().grow or "auto" end,
                    set = function(_, v) cfg().grow = v; NP.Bump() end },
                -- The size belongs to the SLOT the group sits in (Positions);
                -- offered here too, where one looks for it.
                { type = "slider", label = L["Icon size"], min = 10, max = 50, step = 1,
                  disabled = function() return NP.SlotOfAura(kind) == "none" end,
                  get = function()
                      local slot = NP.SlotOfAura(kind)
                      return slot ~= "none" and db().iconSlots[slot].size or 24
                  end,
                  set = function(_, v)
                      local slot = NP.SlotOfAura(kind)
                      if slot == "none" then return end
                      db().iconSlots[slot].size = v
                      NP.Bump()
                      NP.Auras.Rebuild()
                  end },
                num("max", L["Max Icons"], 1, 10),
                num("spacing", L["Spacing"], -5, 20),
                flag("crop", L["Cropped Icons"], restyleAuras),
                num("cropPct", L["Adjust Crop"], 5, 25, restyleAuras),
                ns.BorderRows(ns.OptionRows(cfg, restyleAuras),
                    { hide = "hideBorder", size = "borderSize", color = "borderColor" }),
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
        toggle("showAllDebuffs", L["Show All Debuffs"], L["Off, only the debuffs you (or your pet) cast are shown. On, also those cast by other players."]),
        toggle("allOwnDebuffs", L["All of your own debuffs"], L["On, every debuff you or your pet cast shows, also those the game does not mark for nameplates (many classic damage-over-time spells). Off, only the marked ones, as on the game's own nameplates."]),
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
        ns.BorderRows(rows, { show = "showBorder", size = "borderSize", color = "borderColor" }, { minSize = 1 }),
        toggle("wrapBorderCastbar", L["Wrap Around Castbar"], { disabled = function() return not d.showBorder end }),
        toggle("borderBarColor", L["Border in the bar's color"],
            { tooltip = L["The border takes the health bar's colour: red for hostile, yellow for neutral, the threat colours in a group. A player whose colour cannot be read keeps the border colour."], disabled = function() return not d.showBorder end }),
        opacity("bgAlpha", L["Background"], { inline = { swatch("bgColor", L["Background color"]) } }),
        dropdown("absorbStyle", L["Absorb Style"], absorbStyles, { inline = {
            swatch("absorbColor", { tooltip = L["Absorb color"], disabled = function() return d.absorbStyle == "blizzard" end }),
            gear(L["Absorb Style"], { opacity("absorbAlpha", L["Opacity"], { percent = true, min = 5 }) }),
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
        toggle("showCastIcon", L["Spell Icon"], { inline = { gear(L["Spell Icon Settings"], {
            slider("castIconScale", L["Scale"], 0.5, 2, 0.1),
            slider("castIconOffsetX", L["X Offset"], -50, 50),
            slider("castIconOffsetY", L["Y Offset"], -50, 50),
            toggle("castbarIconInWidth", L["Make Icon Part of the Bar"]),
            toggle("castIconOnRight", L["Icon on Right"]),
            toggle("castIconFullSize", L["Full Sized (Health + Cast Bar)"]),
            toggle("hideCastIconBorder", L["Hide Border"]),
            toggle("castIconTargetBorder", L["Use Target Border Color"]),
        }) } }),
        opacity("castBgAlpha", L["Cast Background"], { inline = { swatch("castBgColor", L["Background color"]) } }),
        { type = "header", text = L["Cast Bar Border"] },
        ns.BorderRows(rows, { size = "castBorderSize", color = "castBorderColor" }),
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
        toggle("importantCastColorEnabled", L["Important Cast Color"], { inline = { swatch("castBarImportant", L["Important Cast"]) } }),
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
                swatch("interruptMidCastColor", { tooltip = L["Bar color"], disabled = function() return not d.interruptMidCastEnabled end }),
                swatch("kickTickColor", L["Tick color"]),
            } }),
        toggle("importantCastGlow", L["Important Cast Glow"], { inline = { swatch("importantCastGlowColor", L["Glow color"]) } }),
        toggle("interruptedFlashEnabled", L["Show Interrupted Flash Effect"], { inline = {
            swatch("interruptedFlashColor", { tooltip = L["Flash color"], disabled = function() return not d.interruptedFlashEnabled end }) } }),
    })

    local function overlayRow(prefix, label, colorKey, alphaKey)
        local none = function() return d[prefix .. "OverlayTexture"] == "none" end
        local items = { toggle(prefix .. "OverlayFullBgAlpha", L["Full alpha on empty part of bar"]) }
        if alphaKey then
            table.insert(items, 1, opacity(alphaKey, L["Opacity"], { min = 5 }))
            items[#items + 1] = toggle(prefix .. "OverlayNoTint", L["Don't tint (keep bar's own color)"])
        end
        local inline = { gear(label, items, { disabled = none }) }
        if colorKey then table.insert(inline, 1, swatch(colorKey, { tooltip = L["Texture color"], disabled = none })) end
        return dropdown(prefix .. "OverlayTexture", label, textures(true), { inline = inline })
    end

    local effects = section(L["Target, Focus & Hover Effects"], {
        toggle("targetGlow", L["Target: Glow"], { inline = {
            swatch("targetGlowColor", L["Glow color"]),
            gear(L["Target: Glow"], { opacity("targetGlowAlpha", L["Glow Opacity"]) }),
        } }),
        toggle("targetGlowBorderColor", L["Target: Border Color"], { inline = { swatch("targetBorderColor", { tooltip = L["Border color"], hasAlpha = true }) } }),
        toggle("targetGlowBorderSize", L["Target: Border Size"], { inline = {
            gear(L["Target: Border Size"], { slider("targetBorderSizeValue", L["Border size"], 0, 4) }) } }),
        toggle("targetGlowHighlight", L["Target: Highlight"], { inline = {
            swatch("targetHighlightColor", L["Highlight Color"]),
            gear(L["Target: Highlight"], { opacity("targetHighlightAlpha", L["Highlight Opacity"]) }),
        } }),
        toggle("showTargetArrows", L["Target Arrows"], { inline = {
            swatch("targetArrowColor", { tooltip = L["Arrow color"], disabled = function() return d.targetArrowClassColor end }),
            gear(L["Target Arrows"], {
                slider("targetArrowScale", L["Scale"], 0.5, 3, 0.1),
                toggle("targetArrowClassColor", L["Use my class color"]),
            }),
        } }),
        toggle("targetColorEnabled", L["Enable Target Color"], { inline = { swatch("target", L["Target color"]) } }),
        toggle("focusColorEnabled", L["Enable Focus Color"], { inline = { swatch("focus", L["Focus color"]) } }),
        overlayRow("target", L["Target Texture"], "targetOverlayColor", "targetOverlayAlpha"),
        overlayRow("focus", L["Focus Texture"], "focusOverlayColor", "focusOverlayAlpha"),
        overlayRow("hover", L["Hover Texture"]),
        toggle("hoverGlowHighlight", L["Hover: Highlight"], { inline = {
            swatch("hoverColor", L["Highlight Color"]),
            gear(L["Hover: Highlight"], { opacity("hoverAlpha", L["Highlight Opacity"]) }),
        } }),
        toggle("hoverGlow", L["Hover: Glow"], { inline = {
            swatch("hoverGlowColor", L["Glow color"]),
            gear(L["Hover: Glow"], { opacity("hoverGlowAlpha", L["Glow Opacity"]) }),
        } }),
        toggle("hoverGlowBorderColor", L["Hover: Border Color"], { inline = { swatch("hoverBorderColor", { tooltip = L["Border color"], hasAlpha = true }) } }),
        toggle("hoverGlowBorderSize", L["Hover: Border Size"], { inline = {
            gear(L["Hover: Border Size"], { slider("hoverBorderSizeValue", L["Border size"], 0, 4) }) } }),
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
                swatch("castTargetColor", { tooltip = L["Text color"], disabled = function() return d.castTargetClassColor end }),
                resize(L["Spell Target"], {
                    slider("castTargetSize", L["Size"], 6, 20),
                    slider("castTargetOffsetX", L["X Offset"], -300, 300),
                    slider("castTargetOffsetY", L["Y Offset"], -300, 300),
                    slider("castTargetWidthPct", L["Width %"], 10, 150),
                    toggle("castTargetWrap", L["Wrap"]),
                    toggle("castTargetClassColor", L["Class color"]),
                }),
            } }),
        -- A row of its own, not in the popup: it counts in the combined mode
        -- too, where the row above is locked.
        toggle("castTargetFirstName", L["Spell Target: first name only"],
            L["\"Vulo Hunt\" is shown as \"Vulo\". In combat the client hides the name; then the first name of the caster's own target is shown, which is nearly always the one the spell is aimed at."]),
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
        toggle("mobTypesInInstancesOnly", L["Enemy types in instances only"],
            { tooltip = L["Outside dungeons and raids every enemy wears the enemy colour; casters, elites and bosses are told apart in instances only. Grey then means one thing: tagged by someone else."], after = function() NP.Colors.RefreshAll() end }),
        toggle("darkenEnemiesOOC", L["Darken Enemies Out of Combat"], { inline = {
            gear(L["Out of Combat"], {
                toggle("darkenOOCRecolor", L["Change Color Instead"]),
                color("darkenOOCColor", L["Out of Combat Color"], { disabled = function() return not d.darkenOOCRecolor end }),
            }) } }),
        toggle("questMobEnabled", L["Quest Mob Marker"],
            { tooltip = L["Puts a quest marker on a mob one of your quests needs."], after = function() NP.Extras.ForgetQuest(); NP.Bump() end }),
        toggle("questMobColorEnabled", L["Color Quest Mobs"], { inline = {
            swatch("questMobColor", { tooltip = L["Quest Mob Color"], disabled = function() return not d.questMobColorEnabled end }) } }),
        toggle("enemyNameTextReactionColor", L["Color Name by Reaction"], { inline = {
            swatch("enemyNameNeutralColor", { tooltip = L["Neutral Color"], disabled = function() return not d.enemyNameTextReactionColor end }),
            swatch("enemyNameHostileColor", { tooltip = L["Hostile Color"], disabled = function() return not d.enemyNameTextReactionColor end }),
        } }),
    })

    local recolor = { after = function() NP.Colors.RefreshAll() end }
    local threat = section(L["Threat Colors (Groups Only)"], {
        { type = "desc", text = L["|cffaaaaaaThreat colours apply while you are in a party or raid.|r"] },
        toggle("assumeTank", L["I am the tank"], { tooltip = L["Use the tank colours. The game has no tank role to read on this client."], after = recolor.after }),
        color("tankLosingAggro", L["Tank: Losing Aggro"]),
        color("tankNoAggro", L["Tank: No Aggro"]),
        color("dpsHasAggro", L["Non-Tank: Has Aggro"]),
        color("dpsNearAggro", L["Non-Tank: Near Aggro"]),
        toggle("dpsNoAggroEnabled", L["DPS: Show Special \"No Aggro\" Color"], { inline = {
            swatch("dpsNoAggro", L["No Aggro"]),
            gear(L["No Aggro"], {
                toggle("dpsNoAggroOverrideMiniBoss", L["Override Elite colors"]),
                toggle("dpsNoAggroOverrideCaster", L["Override Caster colors"]),
                toggle("dpsNoAggroOverrideBoss", L["Override Boss colors"]),
            }),
        } }),
        toggle("classicTankAggro", L["Classic Tank Aggro"], { tooltip = L["Every enemy you hold takes the \"Has Aggro\" colour, whatever its type."], inline = { swatch("tankHasAggro", L["Has Aggro"]) } }),
        toggle("tankHasAggroEnabled", L["Tank: Show Special \"Has Aggro\" Color"], { inline = {
            swatch("tankHasAggro", L["Has Aggro"]),
            gear(L["Has Aggro"], {
                toggle("tankHasAggroOverrideMobType", L["Override Elite and Caster colors"]),
                toggle("tankHasAggroOverrideBoss", L["Override Boss colors"]),
            }),
        } }),
        toggle("offTankAggroEnabled", L["Tank: Show Special \"Off-Tank\" Color"], { inline = { swatch("offTankAggro", L["Off-Tank"]) } }),
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
        toggle("showFriendlyPlayers", L["Show Friendly Players"], refresh),
        toggle("friendlyNameOnly", L["Name Only"],
            { tooltip = L["Just the name, drawn by the game. Switch it off for a full plate with a health bar."], after = refresh.after, disabled = off }),
        slider("friendlyNameSize", L["Friendly Name Size"], 8, 30, 1,
            { after = function() NP.Friendly.Apply() end, disabled = notNameOnly }),
        toggle("classColorFriendly", L["Class Color"], { after = refresh.after, disabled = off,
            inline = { swatch("friendlyBarColor", { tooltip = L["Bar color"], disabled = function() return d.classColorFriendly end }) } }),
        toggle("showFriendlyNPCs", L["Show Friendly NPCs"], { after = refresh.after,
            inline = { swatch("friendlyNPCColor", { tooltip = L["NPC Color"], disabled = function() return not d.showFriendlyNPCs end }) } }),
        toggle("friendlyClickThrough", L["Friendly Names Not Clickable"], refresh),
    })
end

local function generalPage()
    local d = db()
    local hitbox = { after = function() NP.ApplyHitbox() end }
    local spacing = section(L["Nameplate Spacing"], {
        toggle("stackingEnabled", L["Stacking Nameplates"], { tooltip = L["Enemy nameplates move apart instead of overlapping."], after = function() NP.ApplyCVars(); NP.Bump() end }),
        slider("stackSpacingScale", L["Stacked Nameplate Spacing"], 50, 200, 5),
        slider("hitboxScaleX", L["Hitbox Size X"], 50, 250, 5, hitbox),
        slider("hitboxScaleY", L["Hitbox Size Y"], 50, 250, 5, hitbox),
        { type = "desc", text = L["|cffaaaaaaThe clickable area can only change out of combat; a change made in a fight applies when it ends.|r"] },
    })

    local targetFocus = section(L["Target and Focus Effects"], {
        toggle("hashLineEnabled", L["Show Hash Line on Target at Percent"], { inline = { swatch("hashLineColor", L["Line color"]) } }),
        slider("hashLinePercent", L["Hash Line Location"], 0, 100, 1, { disabled = function() return not d.hashLineEnabled end }),
        slider("targetScale", L["Scale Target Nameplate (Percent)"], 50, 200, 5),
        opacity("nonTargetAlpha", L["Non-Target Opacity"], { percent = true, inline = {
            gear(L["Non-Target Opacity"], { toggle("nonTargetKeepFocus", L["Keep Focus Full Opacity"]) }) } }),
        slider("focusCastHeight", L["Focus Cast Height"], 100, 200, 5),
        toggle("focusLetterEnabled", L["Focus Letter"], { inline = { gear(L["Focus Letter"], {
            dropdown("focusLetterAnchor", L["Anchor"], ns.AnchorPointValues()),
            slider("focusLetterSize", L["Size"], 6, 40),
            slider("focusLetterX", L["X Offset"], -100, 100),
            slider("focusLetterY", L["Y Offset"], -100, 100),
        }) } }),
    })

    local extras = {
        slider("castScale", L["Scale Nameplate On Cast"], 50, 200, 5),
        toggle("hideEnemyNameWhileCasting", L["Hide Enemy Name While Casting"]),
        toggle("nameRaidMarkerEnabled", L["Name Raid Marker"], { tooltip = L["A small raid marker next to the name."], inline = {
            gear(L["Name Raid Marker"], { slider("nameRaidMarkerSize", L["Size"], 6, 32) }) } }),
        toggle("executeEnabled", L["Execute Glow"],
            { tooltip = L["Lights the plate up once the enemy is low enough to finish."], inline = {
                gear(L["Execute Glow"], {
                    slider("executeThreshold", L["Execute Threshold"], 5, 50, 1, { suffix = "%" }),
                    slider("executeGlowSize", L["Size"], 2, 16),
                }),
            } }),
        toggle("questObjectiveText", L["Quest progress instead of the marker"],
            { tooltip = L["Shows how far the quest is (3/8, 40%) where the quest marker would be. A mob whose line carries no count keeps the marker."], disabled = function() return not d.questMobEnabled end,
              after = function() NP.Bump() end,
              inline = { gear(L["Quest progress instead of the marker"], {
                  slider("questObjectiveTextSize", L["Size"], 8, 24),
              }) } }),
        toggle("comboEnabled", L["Combo Points"],
            { tooltip = L["Shows your combo points under the plate of your target."], inline = {
                swatch("comboColor", L["Bar color"]),
                gear(L["Combo Points"], {
                    slider("comboHeight", L["Pip Height"], 2, 16),
                    slider("comboGap", L["Spacing"], 0, 10),
                    slider("comboOffset", L["Y Offset"], -20, 20),
                }),
            } }),
        toggle("showEnemyPets", L["Show Enemy Pet Nameplates"], { after = function() NP.ApplyCVars() end }),
        toggle("hideEnemyPlatesOOC", L["Hide Enemy Nameplates out of Combat"], { after = function() NP.ApplyShowEnemies() end }),
    }
    -- A pure client setting with no copy in the profile; only offered when
    -- this client has it.
    if C_CVar.GetCVar("nameplateOccludedAlphaMult") ~= nil then
        extras[#extras + 1] = { type = "slider", label = L["Line of Sight Opacity"], min = 0, max = 100, step = 1, suffix = "%",
            tooltip = L["How visible nameplates stay behind walls and terrain. Cannot change in combat."],
            get = function() return (tonumber(C_CVar.GetCVar("nameplateOccludedAlphaMult")) or 1) * 100 end,
            set = function(_, v)
                if not InCombatLockdown() then pcall(C_CVar.SetCVar, "nameplateOccludedAlphaMult", tostring(v / 100)) end
            end }
    end
    -- Settings out of another suite's profile string (Import.lua).
    local import = section(L["Import"], {
        { type = "desc", text = L["|cffaaaaaaPaste a profile string from another UI suite. Every nameplate setting it carries that exists here is taken over; the rest stays as it is.|r"] },
        { type = "button", label = L["Import nameplate settings"], width = 220, onClick = function()
            ns.UI:ShowStringImportDialog(L["Import nameplate settings"], function(text)
                local taken, err = NP.ImportForeignString(text)
                if not taken then return err end
                ns:Print(L["Nameplates: %d settings taken over."], taken)
                local UI = ns.UI
                if UI.currentModule == "nameplates" and UI.BuildOptionsPage then
                    UI:BuildOptionsPage(UI.currentModule, UI.currentTab)
                end
            end)
        end },
    })
    return { friendlySection(), spacing, targetFocus, section(L["Extras"], extras), import }
end

function M:GetOptions(tabId)
    if tabId == "colors" then return colorsPage() end
    if tabId == "general" then return generalPage() end
    return displayPage()
end

-- The live plate, pinned above every tab (Preview.lua).
function M.BuildPageHeader(host)
    return NP.Preview.BuildHeader(host)
end
