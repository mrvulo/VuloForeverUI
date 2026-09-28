-- VuloForeverUI / Modules / ActionBars / Core
--
-- The client's action bars, in one of three looks.
--
-- WHY THIS SKINS AND DOES NOT TAKE OVER
--
-- The predecessor suite replaces the action bars outright: its own frames, its
-- own buttons, paging and visibility driven by SECURE STATE DRIVERS. That
-- design cannot work here. This client is missing `loadstring_untainted`, so
-- the whole secure-snippet machinery -- state drivers, attribute drivers,
-- `RunAttribute`, wrapped scripts -- cannot compile at all, and every one of
-- them throws. A taken-over bar would be a bar that never changes page and
-- never hides.
--
-- So the client's bars stay, keep their secure clicks and their keybinds, and
-- what we do is dress them. Everything here is art and colour on buttons that
-- remain the client's own.
local _, ns = ...
local L = ns.L

local AB = {}
ns.AB = AB

local mod = ns:RegisterModule("actionbars", {
    name        = "Action Bars",
    group       = "HUD",
    description = "Dresses the client's own action bars: the look they came with, the old 1.x look, or a flat modern one.",
    defaults = {
        enabled = false,

        -- Which of the three looks. The client's own bars stay either way.
        style       = "standard",
        skin        = true,
        -- The Classic style's whole bar -- the stone band, the gryphons, and
        -- the client's buttons put back in their old places on it. Switched
        -- off, the Classic style is the old BUTTONS on the client's own bar.
        classicBar  = true,
        backpackFreeSlots = true,   -- the classic band: free bag slots on the backpack
        skinPetStance = true,
        -- Action bar 1's own art outside the Classic band: the frame with the
        -- dividers between its buttons, and the end caps, one switch each.
        showBarFrame  = true,
        showEndCaps   = true,
        borderColor = { r = 0, g = 0, b = 0, a = 1 },

        -- The Modern look. The interaction colour is a pale gold; it tints
        -- the press and hover glow and the cooldown's moving edge.
        borderSize       = "thin",
        borderClassColor = false,
        iconZoom         = 5.5,
        iconBgColor      = { r = 0.15, g = 0.15, b = 0.15 },
        iconBgOpacity    = 50,
        pressColor       = { r = 0.973, g = 0.839, b = 0.604 },
        pressClassColor  = false,
        pushedType       = 2,       -- 1 light, 2 medium, 3 strong, 4 solid, 6 none
        highlightType    = 2,
        castHighlight    = true,
        keybindHide      = false,
        keybindSize      = 12,
        keybindPos       = "default",
        macroHide        = false,
        macroSize        = 12,
        countSize        = 12,
        cooldownSize     = 12,
        -- Icons of actions the target is out of range for, tinted.
        outOfRange       = true,
        outOfRangeColor  = { r = 0.8, g = 0.1, b = 0.1 },

        -- Per bar: any of the Modern keys above, set for one bar only
        -- (perBar.bar3.iconZoom). A key a bar does not carry falls back to
        -- the value above, so the values above are "every other bar".
        perBar           = {},

        -- Paging. Whether this client lets us do it at all is probed once.
        keepPage    = false,
    },
})
AB.mod = mod

function AB.db() return mod.db end

-- ---------------------------------------------------------------- buttons --

-- Every bar the client has, and the prefix its buttons are named with. The
-- main bar is the one exception: its buttons are plain ActionButtonN.
-- `key` names the bar in the per-bar settings, numbered the way Edit Mode
-- numbers them; `binding` is the prefix of the key bindings its buttons fire.
local BARS = {
    { key = "bar1", frame = "MainActionBar",       prefix = "ActionButton",              binding = "ACTIONBUTTON" },
    { key = "bar2", frame = "MultiBarBottomLeft",  prefix = "MultiBarBottomLeftButton",  binding = "MULTIACTIONBAR1BUTTON" },
    { key = "bar3", frame = "MultiBarBottomRight", prefix = "MultiBarBottomRightButton", binding = "MULTIACTIONBAR2BUTTON" },
    { key = "bar4", frame = "MultiBarRight",       prefix = "MultiBarRightButton",       binding = "MULTIACTIONBAR3BUTTON" },
    { key = "bar5", frame = "MultiBarLeft",        prefix = "MultiBarLeftButton",        binding = "MULTIACTIONBAR4BUTTON" },
    { key = "bar6", frame = "MultiBar5",           prefix = "MultiBar5Button",           binding = "MULTIACTIONBAR5BUTTON" },
    { key = "bar7", frame = "MultiBar6",           prefix = "MultiBar6Button",           binding = "MULTIACTIONBAR6BUTTON" },
    { key = "bar8", frame = "MultiBar7",           prefix = "MultiBar7Button",           binding = "MULTIACTIONBAR7BUTTON" },
}

-- The pet and stance buttons, which are a different shape and a separate
-- setting because plenty of people want the bars dressed and these left alone.
local EXTRA = {
    { key = "pet",    prefix = "PetActionButton", count = 10, binding = "BONUSACTIONBUTTON" },
    { key = "stance", prefix = "StanceButton",    count = 10, binding = "SHAPESHIFTBUTTON" },
    { key = "pet",    prefix = "PossessButton",   count = 2 },
}

function AB.Buttons(includeExtra)
    local out = {}
    for _, bar in ipairs(BARS) do
        for i = 1, 12 do
            local b = _G[bar.prefix .. i]
            if b then out[#out + 1] = b end
        end
    end
    if includeExtra then
        for _, set in ipairs(EXTRA) do
            for i = 1, set.count do
                local b = _G[set.prefix .. i]
                if b then out[#out + 1] = b end
            end
        end
    end
    return out
end

-- Action bar 1: the twelve buttons on the client's main bar.
local MAIN_BAR = {}
for i = 1, 12 do MAIN_BAR["ActionButton" .. i] = true end

function AB.IsMainBarButton(button)
    return MAIN_BAR[button:GetName() or ""] == true
end

-- ---------------------------------------------------------------- per bar --

-- Which bar a button belongs to, from its name. Our preview buttons stand
-- for whichever bar the settings page has picked.
local barOfName = {}
for _, list in ipairs({ BARS, EXTRA }) do
    for _, bar in ipairs(list) do
        for i = 1, 12 do barOfName[bar.prefix .. i] = bar.key end
    end
end

AB.selectedBar = "bar1"

function AB.BarOf(button)
    local name = button:GetName() or ""
    return barOfName[name] or (name:find("PreviewActionButton") and AB.selectedBar) or "bar1"
end

function AB.IsSmallBar(key)
    return key == "pet" or key == "stance"
end

-- The binding command of button i on a bar, for the preview's key labels.
function AB.BindingOf(key, i)
    for _, list in ipairs({ BARS, EXTRA }) do
        for _, bar in ipairs(list) do
            if bar.key == key and bar.binding then return bar.binding .. i end
        end
    end
end

-- The live button i of a bar, so the preview can show what that bar holds.
function AB.ButtonOf(key, i)
    for _, list in ipairs({ BARS, EXTRA }) do
        for _, bar in ipairs(list) do
            if bar.key == key then return _G[bar.prefix .. i] end
        end
    end
end

-- The bars the settings can be picked for, in Edit Mode's order. Built per
-- call so the saved language answers.
function AB.BarList()
    local out = {}
    for i = 1, #BARS do
        out[#out + 1] = { value = BARS[i].key, text = L["Action Bar %d"]:format(i) }
    end
    out[#out + 1] = { value = "pet",    text = L["Pet bar"] }
    out[#out + 1] = { value = "stance", text = L["Stance bar"] }
    return out
end

-- The Modern settings a bar can carry for itself.
AB.PER_BAR_KEYS = {
    "borderSize", "borderColor", "borderClassColor", "iconZoom", "iconBgColor",
    "iconBgOpacity", "pressColor", "pressClassColor", "pushedType", "highlightType",
    "castHighlight", "keybindHide", "keybindSize", "keybindPos", "macroHide",
    "macroSize", "countSize", "cooldownSize", "outOfRange", "outOfRangeColor",
}

-- One read-only view per bar: its own value where it has one, the shared one
-- otherwise. Cached per bar; it reads the live profile on every lookup, so a
-- profile switch needs nothing.
local views = {}
function AB.Cfg(key)
    local view = views[key]
    if not view then
        view = setmetatable({}, { __index = function(_, k)
            local db = mod.db
            local own = db.perBar and db.perBar[key]
            if own and own[k] ~= nil then return own[k] end
            return db[k]
        end })
        views[key] = view
    end
    return view
end

-- The table a bar's own values are written into.
function AB.OwnCfg(key)
    local db = mod.db
    db.perBar = db.perBar or {}
    db.perBar[key] = db.perBar[key] or {}
    return db.perBar[key]
end

function AB.BarFrames()
    local out = {}
    for _, bar in ipairs(BARS) do
        local f = _G[bar.frame]
        if f then out[#out + 1] = f end
    end
    return out
end

-- ---------------------------------------------------------------- apply --

local pending

function AB.Apply()
    if pending then return end
    pending = true
    ns.NextFrame(function()
        pending = false
        if not mod.active then return end
        AB.Skin.ApplyAll()
        AB.Paging.Apply()
    end)
end

-- ---------------------------------------------------------------- lifecycle --

function mod:OnEnable()
    -- Deferred once at login: the bars are laid out by the client's own
    -- controller, and dressing a button before it has its art means dressing
    -- it again a moment later anyway.
    self:RegisterEvent("PLAYER_ENTERING_WORLD", function()
        C_Timer.After(0.5, function() if mod.active then AB.Apply() end end)
    end)

    -- Everything that makes the client redraw a button's art.
    for _, event in ipairs({
        "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED", "UPDATE_BONUS_ACTIONBAR",
        "UPDATE_VEHICLE_ACTIONBAR", "PET_BAR_UPDATE", "UPDATE_SHAPESHIFT_FORMS",
        "UPDATE_SHAPESHIFT_USABLE", "ACTIONBAR_UPDATE_STATE", "UPDATE_BINDINGS", "GAME_PAD_ACTIVE_CHANGED",
    }) do
        self:RegisterEvent(event, function() AB.Apply() end)
    end

    self:RegisterEvent("PLAYER_REGEN_ENABLED", function() AB.Apply() end)

    if not AB.profileHooked then
        AB.profileHooked = true
        hooksecurefunc(ns, "LoadProfile", function()
            if mod.active then AB.Apply() end
        end)
    end

    if IsLoggedIn() then C_Timer.After(0.5, function() if mod.active then AB.Apply() end end) end

    ns:RegisterSlash({ key = "ACTIONBARS", commands = { "/vfbars2" },
        desc = "Open the action bar settings.",
        note = "'/vfbars2 check' reports what the client says about the classic bar art and its own layout.",
    })
end

ns.Slash.ACTIONBARS = function(msg)
    -- "/vfbars2 check" measures instead of guessing: what the client answers
    -- about its own art, its scales and its own layout calls.
    if (msg or ""):lower():match("^%s*check") then
        AB.ClassicBar.Report()
        return
    end
    local f = ns.UI:CreateMainFrame()
    f:Show()
    ns.UI:PopulateSidebar()
    ns.UI:ShowModulePage("actionbars")
end

function mod:OnDisable()
    if ns:InCombat() then
        -- both touch secure buttons and would refuse now; the module's own
        -- regen handler is gone with it, so the restore books its own
        ns:RegisterEventOnce("PLAYER_REGEN_ENABLED", function()
            if not mod.active then AB.Skin.RestoreAll(); AB.Paging.Release() end
        end)
        return
    end
    AB.Skin.RestoreAll()
    AB.Paging.Release()
end

-- The style names, built lazily so the saved language is the one that answers.
function AB.StyleLabel(key)
    local labels = {
        standard = L["Standard"],
        classic  = L["Classic"],
        modern   = L["Modern"],
    }
    return labels[key] or key
end
