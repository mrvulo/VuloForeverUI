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
        borderColor = { r = 0, g = 0, b = 0, a = 1 },

        -- Paging. Whether this client lets us do it at all is probed once.
        keepPage    = false,
    },
})
AB.mod = mod

function AB.db() return mod.db end

-- ---------------------------------------------------------------- buttons --

-- Every bar the client has, and the prefix its buttons are named with. The
-- main bar is the one exception: its buttons are plain ActionButtonN.
local BARS = {
    { frame = "MainActionBar",       prefix = "ActionButton" },
    { frame = "MultiBarBottomLeft",  prefix = "MultiBarBottomLeftButton" },
    { frame = "MultiBarBottomRight", prefix = "MultiBarBottomRightButton" },
    { frame = "MultiBarRight",       prefix = "MultiBarRightButton" },
    { frame = "MultiBarLeft",        prefix = "MultiBarLeftButton" },
    { frame = "MultiBar5",           prefix = "MultiBar5Button" },
    { frame = "MultiBar6",           prefix = "MultiBar6Button" },
    { frame = "MultiBar7",           prefix = "MultiBar7Button" },
}

-- The pet and stance buttons, which are a different shape and a separate
-- setting because plenty of people want the bars dressed and these left alone.
local EXTRA = {
    { prefix = "PetActionButton",    count = 10 },
    { prefix = "StanceButton",       count = 10 },
    { prefix = "PossessButton",      count = 2 },
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
        "UPDATE_SHAPESHIFT_USABLE", "ACTIONBAR_UPDATE_STATE",
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
        standard = L["Standard -- the look the client came with"],
        classic  = L["Classic -- the old 1.x buttons"],
        modern   = L["Modern -- flat, in the suite's own style"],
    }
    return labels[key] or key
end
