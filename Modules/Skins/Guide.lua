-- VuloForeverUI / Modules / Skins / Guide
--
-- A skin for the levelling-guide addon the player runs: its guide window
-- (header, step list, footer, scrollbar), the floating "current step"
-- boxes above it, the waypoint arrow and the "Active Targets" window, in two
-- looks:
--
--   Standard  the game's own tooltip frame: dark ground, the classic border
--   Modern    flat dark panels with a one-pixel edge, like our own windows
--
-- The guide's frames are plain frames of that addon, created at its load
-- (window, header, footer) or pooled later (list steps, current steps). It
-- re-applies its own backdrops on every redraw, so each of its redraw
-- functions is hooked and our backdrop goes back on after it. Its pooled
-- frames are checked against the look they carry, so a pass over the pools
-- costs nothing once they are done. Its secure item and target buttons are
-- left alone entirely.
--
-- The addon's globals are named below only where they must be: to find its
-- frames and to know when it has loaded.
local _, ns = ...
local L = ns.L
local Skins = ns.Skins

local Guide = {}
Skins.Guide = Guide
table.insert(Skins.parts, Guide)

local ADDON = "RXPGuides"

local looks = {
    standard = {
        backdrop = {
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 },
        },
        bg = { 0.04, 0.04, 0.05, 0.92 }, hover = { 0.12, 0.12, 0.14, 0.95 },
        edge = { 0.75, 0.75, 0.78, 1 },
    },
    modern = {
        backdrop = {
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 },
        },
        pixel = true,       -- edge and insets one physical pixel (backdropFor)
        bg = { 0.055, 0.055, 0.065, 0.95 }, hover = { 0.10, 0.10, 0.12, 0.97 },
        edge = { 0.22, 0.22, 0.26, 1 },
    },
}

local skinned = setmetatable({}, { __mode = "k" })    -- frame -> look name
local colorHooked = setmetatable({}, { __mode = "k" })
local painting = false

local function db() return Skins.mod.db.guide end

local function active()
    local d = db()
    return Skins.mod.active and d and d.enabled and _G.RXPFrame and not _G.RXPV2GuideWindow
end

local function look() return looks[db().style] or looks.standard end

-- Our colours, whatever the guide asks for: it sets its theme's colours on
-- hover and on every redraw. The mouse decides between ground and hover.
local function recolor(f)
    if painting or not skinned[f] then return end
    local lk = looks[skinned[f]]
    painting = true
    local c = (f.IsMouseOver and f:IsMouseOver()) and lk.hover or lk.bg
    f:SetBackdropColor(c[1], c[2], c[3], c[4])
    f:SetBackdropBorderColor(lk.edge[1], lk.edge[2], lk.edge[3], lk.edge[4])
    painting = false
end

local deferred = false

-- The look's backdrop for one frame: the modern edge is one physical pixel
-- at that frame's scale, not one UI unit.
local function backdropFor(f)
    local lk = look()
    if not lk.pixel then return lk.backdrop end
    local px = ns:Pixel(f, 1)
    local b = lk.backdrop
    return { bgFile = b.bgFile, edgeFile = b.edgeFile, edgeSize = px,
             insets = { left = px, right = px, top = px, bottom = px } }
end

local function skin(f)
    if not (f and f.SetBackdrop) then return end
    -- a frame holding secure buttons (the target window) waits for the
    -- fight to end; PLAYER_REGEN_ENABLED runs the pass again
    if InCombatLockdown() and f.IsProtected and f:IsProtected() then
        deferred = true
        return
    end
    local name = db().style
    if skinned[f] == name then return end
    skinned[f] = name
    painting = true
    f:SetBackdrop(backdropFor(f))
    painting = false
    if not colorHooked[f] then
        colorHooked[f] = true
        hooksecurefunc(f, "SetBackdropColor", recolor)
        hooksecurefunc(f, "SetBackdrop", function(self)
            -- the guide put its own backdrop back: ours again, next frame
            if painting or not skinned[self] then return end
            skinned[self] = nil
            if active() then ns.NextFrame(function() if active() then skin(self) end end) end
        end)
    end
    recolor(f)
end

-- ---------------------------------------------------------------- pieces --

local function pools()
    local main = _G.RXPFrame
    local list = main.ScrollChild and main.ScrollChild.framePool
    local cur = main.CurrentStepFrame and main.CurrentStepFrame.framePool
    return list, cur
end

-- The waypoint arrow: one picture that only turns. Grey first, then tinted
-- in the look's colour: gold for Standard, the accent for Modern.
local function arrow()
    local a = _G.RXPG_ARROW
    local t = a and a.texture
    if not (t and t.SetDesaturated) then return end
    t:SetDesaturated(true)
    if db().style == "modern" then
        local ac = ns.COLORS.accent
        t:SetVertexColor(ac.r, ac.g, ac.b, 1)
    else
        t:SetVertexColor(1, 0.82, 0, 1)
    end
end

-- The "Active Targets" window and its title tab, made on demand by the guide.
local function targets()
    local f = _G.RXPTargetFrame
    if not f then return end
    skin(f)
    if f.title then skin(f.title) end
end

local function skinPools()
    if not active() then return end
    local list, cur = pools()
    for _, f in ipairs(list or {}) do skin(f) end
    for _, f in ipairs(cur or {}) do
        skin(f)
        if f.number then skin(f.number) end
    end
    targets()
end

-- Banner art the guide draws behind its header and footer.
local function banners(on)
    local main = _G.RXPFrame
    for _, part in ipairs({ main.GuideName, main.Footer }) do
        if part and part.bg and part.bg.SetAlpha then part.bg:SetAlpha(on and 0 or 1) end
    end
end

-- The scrollbar: Modern gets the house's thin bar, Standard the game's own
-- arrows and knob in place of the guide's round blue ones.
local STD = {
    up   = { "Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Up", "Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Down",
             "Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Disabled", "Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Highlight" },
    down = { "Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up", "Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Down",
             "Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Disabled", "Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Highlight" },
}
local function scrollbar()
    local sf = _G.RXPFrame.ScrollFrame
    local bar = sf and sf.ScrollBar
    if not bar then return end
    if db().style == "modern" then
        ns.UI.StyleScrollbar(sf)
        return
    end
    for key, tex in pairs({ ScrollUpButton = STD.up, ScrollDownButton = STD.down }) do
        local b = bar[key]
        if b and b.SetNormalTexture then
            b:SetNormalTexture(tex[1]); b:SetPushedTexture(tex[2])
            b:SetDisabledTexture(tex[3]); b:SetHighlightTexture(tex[4], "ADD")
        end
    end
    if bar.SetThumbTexture then bar:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob") end
end

local function skinStatic()
    if not active() then return end
    local main = _G.RXPFrame
    skin(main.BottomFrame)
    skin(main.GuideName)
    skin(main.Footer)
    banners(true)
    scrollbar()
    arrow()
    skinPools()
end

-- ---------------------------------------------------------------- wiring --

local hooked
local function setup()
    local main = _G.RXPFrame
    if hooked or not main then return end
    hooked = true
    local function after() if active() then skinStatic() end end
    if main.UpdateVisuals then hooksecurefunc(main, "UpdateVisuals", after) end
    if main.UpdateScrollBar then hooksecurefunc(main, "UpdateScrollBar", function() if active() then scrollbar() end end) end
    local body = main.BottomFrame
    if body and body.UpdateFrame then hooksecurefunc(body, "UpdateFrame", skinPools) end
    if body and body.StepScroll then hooksecurefunc(body, "StepScroll", skinPools) end
    local a = _G.RXPG_ARROW
    if a and a.UpdateVisuals then hooksecurefunc(a, "UpdateVisuals", function() if active() then arrow() end end) end
    Guide.Apply()
end

function Guide.Installed()
    return C_AddOns.IsAddOnLoaded(ADDON) and _G.RXPFrame ~= nil
end

function Guide.Enable(mod)
    if Guide.Installed() then setup() end
    mod:RegisterEvent("ADDON_LOADED", function(_, name)
        if name == ADDON then ns.NextFrame(setup) end
    end)
    mod:RegisterEvent("PLAYER_REGEN_ENABLED", function()
        if deferred and active() then deferred = false; skinStatic() end
    end)
end

-- A switch between the looks re-skins everything at once. Off cannot hand
-- the guide its own backdrops back -- it only sets most of them on its own
-- theme changes -- so that waits for a reload.
function Guide.Apply()
    if not hooked then return end
    if active() then
        wipe(skinned)
        skinStatic()
    end
end
