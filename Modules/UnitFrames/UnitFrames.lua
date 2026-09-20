-- VuloForeverUI / Modules / UnitFrames / UnitFrames
--
-- Unit frames in three styles. Standard keeps Blizzard's frames and lays
-- extras on them (UnitFramesExtras). Classic keeps Blizzard's frames too and
-- reskins them -- player, target, focus, target-of-target, the target cast bar
-- and the pet frame -- with overlay bars of our own on the original frame art
-- (UnitFramesClassic*). Only Modern is our own frame (UnitFramesEngine +
-- UnitFramesSkins) and silences Blizzard's player and target frames.
local _, ns = ...
local L = ns.L
local UF = ns.UF

-- Every Modern number, per unit. The values here are the frame as it shipped,
-- so an untouched profile looks exactly as before; Skins.lua reads the same
-- fallbacks, which keeps the two honest against each other.
local function modernDefaults(unit)
    return {
        width            = 220,
        healthHeight     = 30,
        showPower        = true,
        powerHeight      = 12,
        texture          = "",                  -- empty: follow the global texture
        healthClassColor = true,
        healthColor      = { r = 0.15, g = 0.65, b = 0.25 },
        healthBgColor    = { r = 0, g = 0, b = 0 },
        healthBgOpacity  = 60,
        healthOpacity    = 100,
        powerTypeColor   = true,
        powerColor       = { r = 0.20, g = 0.40, b = 0.90 },
        powerBgColor     = { r = 0, g = 0, b = 0 },
        powerBgOpacity   = 60,
        powerOpacity     = 100,
        showPortrait     = true,
        -- The portrait faces outwards, the way the Classic pair does.
        portraitSide     = (unit == "target") and "right" or "left",
        portraitSize     = 0,
        leftText         = "name",  leftSize   = 12, leftX   = 0, leftY   = 0, leftClassColor   = true,
        centerText       = "none",  centerSize = 12, centerX = 0, centerY = 0, centerClassColor = false,
        rightText        = "perhp", rightSize  = 11, rightX  = 0, rightY  = 0, rightClassColor  = false,
        powerText        = "curpp", powerTextSize = 11, powerTextX = 0, powerTextY = 0,
        showLevel        = true,
        levelSize        = 11,
        showTag          = false,
        showClassIcon    = false,
        showThreat       = true,
    }
end

local mod = ns:RegisterModule("unitframes", {
    name        = "Unit Frames",
    group       = "Unit Frames",
    description = "Player and target frames: Blizzard's own with extras, the Classic look, or a flat Modern look.",
    defaults = {
        enabled     = true,
        style       = "standard",
        classColor  = true,
        -- Both off by default on Blizzard's frames: the retail frame shows
        -- threat itself, and the class icon is a matter of taste.
        threat      = false,
        classIcon   = false,
        playerElite = true,
        classicClassColor = false,     -- Classic: Blizzard's green unless asked
        classicStatusText = true,      -- Classic: Blizzard's bar text, always on, percent + value
        classicClassIcon  = false,     -- Classic: ringed class badge on the target portrait
        player      = { x = -260, y = -180, scale = 1, modern = modernDefaults("player") },
        target      = { x =  260, y = -180, scale = 1, modern = modernDefaults("target") },
    },
})

-- Which unit the Modern options page is showing. A view state, not a setting:
-- it does not belong in a profile and is not worth saving.
local optUnit = "player"

local function needsReloadFrom(oldStyle)
    return oldStyle == "classic" or oldStyle == "modern"
end

-- Going back to Standard needs a reload: Blizzard's frames were silenced and
-- their events cannot be re-registered from here. Said before the switch,
-- not after it.
ns.OnLocaleReady(function()
StaticPopupDialogs["VFUI_UNITFRAMES_RELOAD"] = {
    text = L["Blizzard's frames come back after a reload. Reload the UI now?"],
    button1 = L["Reload now"],
    button2 = L["Later"],
    OnAccept = function() ReloadUI() end,
    timeout = 0, whileDead = 1, hideOnEscape = 1, preferredIndex = 3,
}
end)

local pendingApply = false

local function applyStyle(oldStyle)
    if ns:InCombat() then
        if not pendingApply then
            pendingApply = true
            ns:RegisterEventOnce("PLAYER_REGEN_ENABLED", function()
                pendingApply = false
                applyStyle(oldStyle)
            end)
        end
        return
    end
    local style = mod.db.style
    if style == "modern" then
        if UF.Extras  then UF.Extras.Disable() end
        if UF.Classic then UF.Classic.Disable() end
        UF.ActivateOwnFrames(mod)
    elseif style == "classic" then
        UF.DeactivateOwnFrames()
        if UF.Extras  then UF.Extras.Enable(mod) end
        if UF.Classic then UF.Classic.Enable(mod) end
    else
        UF.DeactivateOwnFrames()
        if UF.Classic then UF.Classic.Disable() end
        if UF.Extras  then UF.Extras.Enable(mod) end
    end
    if oldStyle and oldStyle ~= style and needsReloadFrom(oldStyle) then
        StaticPopup_Show("VFUI_UNITFRAMES_RELOAD")
    end
end

mod.ApplyStyle = applyStyle

function mod:OnEnable()
    -- PLAYER_ENTERING_WORLD: Blizzard's frames exist and have laid out by then,
    -- and it also covers a /reload.
    self:RegisterEvent("PLAYER_ENTERING_WORLD", function()
        applyStyle()
    end)
    if IsLoggedIn and IsLoggedIn() then applyStyle() end
end

function mod:OnDisable()
    local oldStyle = mod.db.style
    UF.DeactivateOwnFrames()
    if UF.Extras then UF.Extras.Disable() end
    if UF.Classic then UF.Classic.Disable() end
    if needsReloadFrom(oldStyle) then
        StaticPopup_Show("VFUI_UNITFRAMES_RELOAD")
    end
end

-- ------------------------------------------------------- Modern options --
--
-- Every row below writes one key of mod.db[unit].modern and asks the engine to
-- rebuild that unit's skin. Nothing here knows what a frame looks like.

local function cfgOf(unit) return mod.db[unit].modern end

local function rebuildPage()
    if ns.UI and ns.UI.BuildOptionsPage then ns.UI:BuildOptionsPage("unitframes") end
end

local function numRow(unit, key, label, min, max, step, tooltip)
    return { type = "slider", label = label, tooltip = tooltip,
        min = min, max = max, step = step,
        get = function() return cfgOf(unit)[key] end,
        set = function(_, v) cfgOf(unit)[key] = v; ns.UF.RefreshModern(mod, unit) end }
end

-- `rebuild` is for a switch that other rows depend on: the page has to come
-- back with the rows it now owns.
local function flagRow(unit, key, label, tooltip, rebuild)
    return { type = "toggle", label = label, tooltip = tooltip,
        get = function() return cfgOf(unit)[key] end,
        set = function(_, v)
            cfgOf(unit)[key] = v
            ns.UF.RefreshModern(mod, unit)
            if rebuild then rebuildPage() end
        end }
end

local function colorRow(unit, key, label)
    return { type = "color", label = label,
        get = function() return cfgOf(unit)[key] end,
        set = function(r, g, b)
            local c = cfgOf(unit)[key]
            c.r, c.g, c.b = r, g, b
            ns.UF.RefreshModern(mod, unit)
        end }
end

local function choiceRow(unit, key, label, values, rebuild)
    return { type = "dropdown", label = label, values = values, width = 220,
        get = function() return cfgOf(unit)[key] end,
        set = function(_, v)
            cfgOf(unit)[key] = v
            ns.UF.RefreshModern(mod, unit)
            if rebuild then rebuildPage() end
        end }
end

-- One text slot: what it says, behind the gear how big it is, where it sits
-- and whether it wears the class colour.
local function textSlotRow(unit, label, values, keys)
    local row = choiceRow(unit, keys.content, label, values)
    row.subKey = "uf/" .. keys.content
    row.subOptions = {
        numRow(unit, keys.size, L["Text size"], 6, 24, 1),
        numRow(unit, keys.x, L["Horizontal offset"], -100, 100, 1),
        numRow(unit, keys.y, L["Vertical offset"], -50, 50, 1),
    }
    if keys.classColor then
        row.subOptions[#row.subOptions + 1] =
            flagRow(unit, keys.classColor, L["Class color on this text"])
    end
    return row
end

local function modernOptions(unit)
    local healthTexts = {
        { value = "none",   text = L["Nothing"] },
        { value = "name",   text = L["Name"] },
        { value = "curhp",  text = L["Health value"] },
        { value = "perhp",  text = L["Health percent"] },
        { value = "hpboth", text = L["Health value and percent"] },
    }
    local powerTexts = {
        { value = "none",   text = L["Nothing"] },
        { value = "curpp",  text = L["Power value"] },
        { value = "ppboth", text = L["Power value and maximum"] },
    }
    local sides = {
        { value = "left",  text = L["Left"] },
        { value = "right", text = L["Right"] },
    }
    local textures = { { value = "", text = L["Global texture"] } }
    for _, v in ipairs(ns.MediaStatusbarValues()) do textures[#textures + 1] = v end

    local cfg = cfgOf(unit)

    local frameRows = {
        numRow(unit, "width", L["Frame width"], 120, 400, 1),
        numRow(unit, "healthHeight", L["Health bar height"], 8, 80, 1),
        flagRow(unit, "showPower", L["Show the power bar"], nil, true),
    }
    if cfg.showPower then
        frameRows[#frameRows + 1] = numRow(unit, "powerHeight", L["Power bar height"], 2, 40, 1)
    end
    frameRows[#frameRows + 1] = flagRow(unit, "showPortrait", L["Show portrait"], nil, true)
    if cfg.showPortrait then
        frameRows[#frameRows + 1] = choiceRow(unit, "portraitSide", L["Portrait side"], sides)
        frameRows[#frameRows + 1] = numRow(unit, "portraitSize", L["Portrait size"], -30, 60, 1,
            L["Added to the frame's own height; 0 makes the portrait square with the frame."])
    end

    local colorRows = {
        choiceRow(unit, "texture", L["Bar texture"], textures),
        flagRow(unit, "healthClassColor", L["Class color on the health bar"], nil, true),
    }
    if not cfg.healthClassColor then
        colorRows[#colorRows + 1] = colorRow(unit, "healthColor", L["Health bar color"])
    end
    colorRows[#colorRows + 1] = colorRow(unit, "healthBgColor", L["Health bar background"])
    colorRows[#colorRows + 1] = numRow(unit, "healthBgOpacity", L["Health background opacity"], 0, 100, 1)
    colorRows[#colorRows + 1] = numRow(unit, "healthOpacity", L["Health bar opacity"], 10, 100, 1)
    if cfg.showPower then
        colorRows[#colorRows + 1] = flagRow(unit, "powerTypeColor", L["Color the power bar by power type"], nil, true)
        if not cfg.powerTypeColor then
            colorRows[#colorRows + 1] = colorRow(unit, "powerColor", L["Power bar color"])
        end
        colorRows[#colorRows + 1] = colorRow(unit, "powerBgColor", L["Power bar background"])
        colorRows[#colorRows + 1] = numRow(unit, "powerBgOpacity", L["Power background opacity"], 0, 100, 1)
        colorRows[#colorRows + 1] = numRow(unit, "powerOpacity", L["Power bar opacity"], 10, 100, 1)
    end

    local textRows = {
        textSlotRow(unit, L["Left text"], healthTexts,
            { content = "leftText", size = "leftSize", x = "leftX", y = "leftY", classColor = "leftClassColor" }),
        textSlotRow(unit, L["Center text"], healthTexts,
            { content = "centerText", size = "centerSize", x = "centerX", y = "centerY", classColor = "centerClassColor" }),
        textSlotRow(unit, L["Right text"], healthTexts,
            { content = "rightText", size = "rightSize", x = "rightX", y = "rightY", classColor = "rightClassColor" }),
    }
    if cfg.showPower then
        textRows[#textRows + 1] = textSlotRow(unit, L["Power bar text"], powerTexts,
            { content = "powerText", size = "powerTextSize", x = "powerTextX", y = "powerTextY" })
    end

    local extraRows = {
        flagRow(unit, "showLevel", L["Show level"], nil, true),
    }
    if cfg.showLevel then
        extraRows[#extraRows + 1] = numRow(unit, "levelSize", L["Level text size"], 6, 24, 1)
    end
    extraRows[#extraRows + 1] = flagRow(unit, "showTag", L["Show classification"],
        L["Elite, Rare or Boss, next to the level."])
    extraRows[#extraRows + 1] = flagRow(unit, "showClassIcon", L["Class icon beside the frame"])
    extraRows[#extraRows + 1] = flagRow(unit, "showThreat", L["Threat text above the frame"])

    return {
        -- A view switch, not a setting: it must not count as "differs from
        -- the default" when the page is showing the target.
        { type = "segmented", label = L["Settings for"], noDefaultMark = true,
          values = {
              { value = "player", text = L["Player"] },
              { value = "target", text = L["Target"] },
          },
          get = function() return optUnit end,
          set = function(_, v) optUnit = v; rebuildPage() end },
        { type = "section", title = L["Frame"],  items = frameRows },
        { type = "section", title = L["Colors"], items = colorRows },
        { type = "section", title = L["Text"],   items = textRows },
        { type = "section", title = L["Extras"], items = extraRows },
    }
end

function mod:GetOptions()
    local items = {
        { type = "header", text = L["Style"] },
        { type = "dropdown", label = L["Frame style"], width = 240,
          values = {
              { value = "standard", text = L["Standard (Blizzard's frames plus extras)"] },
              { value = "classic",  text = L["Classic (original frame art)"] },
              { value = "modern",   text = L["Modern (flat house style)"] },
          },
          get = function() return mod.db.style end,
          set = function(_, v)
              if v == mod.db.style then return end
              local old = mod.db.style
              mod.db.style = v
              applyStyle(old)
              if ns.UI and ns.UI.BuildOptionsPage then ns.UI:BuildOptionsPage("unitframes") end
          end },
        { type = "desc", text = L["|cffaaaaaaClassic reskins Blizzard's frames; Modern is our own frame, moved with /vedit. Leaving Classic or Modern asks for a reload.|r"] },
        { type = "spacer", height = 8 },
    }

    if mod.db.style == "standard" then
        items[#items + 1] = { type = "header", text = L["Extras on Blizzard's frames"] }
        items[#items + 1] = { type = "toggle", label = L["Class color on the health bar"],
            get = function() return mod.db.classColor end,
            set = function(_, v) mod.db.classColor = v; applyStyle() end }
        items[#items + 1] = { type = "toggle", label = L["Threat display on the target frame"],
            get = function() return mod.db.threat end,
            set = function(_, v) mod.db.threat = v; applyStyle() end }
        items[#items + 1] = { type = "toggle", label = L["Class icon on the portrait"],
            get = function() return mod.db.classIcon end,
            set = function(_, v) mod.db.classIcon = v; applyStyle() end }
    elseif mod.db.style == "classic" then
        items[#items + 1] = { type = "header", text = L["Classic"] }
        items[#items + 1] = { type = "toggle", label = L["Elite dragon on the player frame"],
            get = function() return mod.db.playerElite end,
            set = function(_, v) mod.db.playerElite = v; applyStyle() end }
        items[#items + 1] = { type = "toggle", label = L["Class color on the health bar"],
            get = function() return mod.db.classicClassColor end,
            set = function(_, v) mod.db.classicClassColor = v; applyStyle() end }
        items[#items + 1] = { type = "toggle", label = L["Class icon on the target portrait"],
            get = function() return mod.db.classicClassIcon end,
            set = function(_, v) mod.db.classicClassIcon = v; applyStyle() end }
        items[#items + 1] = { type = "toggle", label = L["Status text on the bars"],
            tooltip = L["Sets Blizzard's status text to percent and value, always shown. Change it back under Blizzard's options."],
            get = function() return mod.db.classicStatusText end,
            set = function(_, v) mod.db.classicStatusText = v; applyStyle() end }
        items[#items + 1] = { type = "desc", text = L["|cffaaaaaaClassic keeps Blizzard's frames underneath: target auras, the target cast bar and the pet frame stay, and Edit Mode moves them.|r"] }
    end

    if mod.db.style == "modern" then
        items[#items + 1] = { type = "header", text = L["Modern"] }
        for _, row in ipairs(modernOptions(optUnit)) do
            items[#items + 1] = row
        end
        items[#items + 1] = { type = "spacer", height = 8 }
        items[#items + 1] = { type = "header", text = L["Position"] }
        local key = optUnit
        items[#items + 1] = { type = "slider", label = L["Frame scale"],
            min = 0.5, max = 2, step = 0.05,
            get = function() return mod.db[key].scale or 1 end,
            -- Through RefreshModern, not MoverSetScale: scaling a secure unit
            -- button is refused in combat, silently, and RefreshModern is the
            -- one place that waits for the fight to end. ApplyMover re-reads
            -- db.scale on the way, so the slider still lands.
            set = function(_, v)
                mod.db[key].scale = v
                ns.UF.RefreshModern(mod, key)
            end }
        items[#items + 1] = { type = "button", label = L["Open Edit Mode"],
            onClick = function() ns:SetEditMode(true) end }
    end

    return items
end
