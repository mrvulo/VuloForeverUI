-- VuloForeverUI / Modules / Minimap / StyleApply: applying the look, enable/disable hooks and the /vfmmtex art probe
local _, ns = ...
local L = ns.L
local MM = ns.MM
local mod = MM.mod
local P = mod._style
local setShown, applyClutter, applyZoneSize = P.setShown, P.applyClutter, P.applyZoneSize
local applyStandard, applyClassic, applyModern = P.applyStandard, P.applyClassic, P.applyModern
local skinCalendar, scaleQueue = P.skinCalendar, P.scaleQueue

-- ---------------------------------------------------------------------------
-- Applying, and doing it again when the client redoes its own skin
-- ---------------------------------------------------------------------------
local applying

function mod:Apply()
    if not self.active or applying then return end
    if InCombatLockdown() then
        ns:RunOutOfCombatOnce("minimapstyle", function() mod:Apply() end)
        return
    end
    applying = true
    local ok, err = pcall(function()
        local style = self.db.style
        if style ~= "standard" then applyStandard() end   -- from a clean slate
        if style == "classic" then applyClassic()
        elseif style == "modern" then applyModern()
        else applyStandard() end
        applyClutter()
        if style ~= "standard" then applyZoneSize() end
        scaleQueue(self.db.queueScale)
        -- a place of the user's own wins over every look's
        if self.queueMover then self.queueMover.Apply() end
        MM.Elements.Apply()
        MM.Elements.ApplyVisibility()
    end)
    applying = false
    -- The rim buttons measure the map when they place themselves, and they
    -- load before this file: after a look changes its size they sit wrong.
    for _, key in ipairs({ "minimap", "minimapcollector" }) do
        local m = ns.modules[key]
        if m and m.active and m.UpdatePosition then pcall(m.UpdatePosition) end
    end
    if not ok then ns:Print(L["|cffff5555Minimap style failed:|r %s"], tostring(err)) end
end

-- Script hooks cannot be taken off again: each one asks the module first.
local function onEnter()
    if not mod.active then return end
    MM.Elements.SetHovered(true)
    -- the client shows its zoom buttons on every hover
    if mod.db.hideZoom then
        setShown(Minimap.ZoomIn, false)
        setShown(Minimap.ZoomOut, false)
    end
end
local function onLeave() if mod.active then MM.Elements.SetHovered(false) end end
local mouseHooked = false
local blizzWheel      -- the map's own zoom handler, put back on disable

-- Zoom back out after a while, so a map left zoomed in does not stay that way.
local zoomTimer

local function scheduleZoomReset()
    local seconds = mod.db.zoomReset
    if seconds <= 0 then return end
    if zoomTimer then ns:CancelTicker(zoomTimer); zoomTimer = nil end
    local waited = 0
    zoomTimer = ns:AddTicker(1, function()
        waited = waited + 1
        if waited < seconds then return end
        ns:CancelTicker(zoomTimer); zoomTimer = nil
        for _ = 1, Minimap:GetZoom() do Minimap:SetZoom(Minimap:GetZoom() - 1) end
    end, nil, "minimapstyle")
end

function mod:OnEnable()
    -- MinimapCluster lays itself out again on its own -- an Edit Mode change, a
    -- size setting, a zone with a different header. Without this hook our
    -- placement survives exactly until the next time it does.
    if not self._layoutHooked then
        self._layoutHooked = true
        local function relayout()
            if mod.active and mod.db.style ~= "standard" then
                ns.NextFrame(function() mod:Apply() end)
            end
        end
        -- Everything that lays the cluster out again behind our back.
        local cluster = MinimapCluster
        if cluster then
            if cluster.Layout then hooksecurefunc(cluster, "Layout", relayout) end
            if cluster.SetRotateMinimap then hooksecurefunc(cluster, "SetRotateMinimap", relayout) end
            if cluster.IndicatorFrame and cluster.IndicatorFrame.Layout then
                hooksecurefunc(cluster.IndicatorFrame, "Layout", relayout)
            end
        end
        if _G.QueueStatusButton and _G.QueueStatusButton.UpdatePosition then
            hooksecurefunc(_G.QueueStatusButton, "UpdatePosition", relayout)
        end
        -- This client puts the eye back with UpdateDefaultAnchor (a layout
        -- applied, the minimap's scale changed), not with UpdatePosition --
        -- the button has none. Our look and our own place go back on top.
        if _G.QueueStatusButton and _G.QueueStatusButton.UpdateDefaultAnchor then
            hooksecurefunc(_G.QueueStatusButton, "UpdateDefaultAnchor", function()
                if mod.active then ns.NextFrame(function() mod:Apply() end) end
            end)
        end
        -- The client's editor sets the eye's own size when a layout loads;
        -- our factor goes back on top of it.
        if _G.QueueStatusButton and _G.QueueStatusButton.UpdateSystemSettingSize then
            hooksecurefunc(_G.QueueStatusButton, "UpdateSystemSettingSize", function()
                if mod.active then scaleQueue(mod.db.queueScale) end
            end)
        end
        -- The calendar redraws its own face whenever the date is set.
        if _G.GameTimeFrame_SetDate then
            hooksecurefunc("GameTimeFrame_SetDate", function()
                if mod.active and mod.db.style == "classic" then skinCalendar() end
            end)
        end
        -- Two frames that put themselves back: 1.x has neither.
        if _G.AddonCompartmentFrame and _G.AddonCompartmentFrame.UpdateDisplay then
            hooksecurefunc(_G.AddonCompartmentFrame, "UpdateDisplay", function(self)
                if mod.active and mod.db.style == "classic" then self:Hide() end
            end)
        end
        if _G.ExpansionLandingPageMinimapButton and _G.ExpansionLandingPageMinimapButton.UpdateIcon then
            hooksecurefunc(_G.ExpansionLandingPageMinimapButton, "UpdateIcon", function(self)
                if mod.active and mod.db.style == "classic" then
                    self:SetAlpha(0); self:EnableMouse(false)
                end
            end)
        end
        -- The client hides the zoom buttons when the mouse leaves the map; in
        -- the classic look they are part of the frame and stay put.
        Minimap:HookScript("OnLeave", function()
            if mod.active and mod.db.style == "classic" and not mod.db.hideZoom then
                setShown(Minimap.ZoomIn, true)
                setShown(Minimap.ZoomOut, true)
            end
        end)
    end
    self:RegisterEvent("PLAYER_ENTERING_WORLD", function() self:Apply() end)
    -- the Camelot skin rebuilds itself when this CVar flips, undoing our work
    self:RegisterEvent("CVAR_UPDATE", function(_, name)
        if name == "rotateMinimap" then ns.NextFrame(function() self:Apply() end) end
    end)
    if not mouseHooked then
        mouseHooked = true
        blizzWheel = Minimap:GetScript("OnMouseWheel")
        Minimap:HookScript("OnEnter", onEnter)
        Minimap:HookScript("OnLeave", onLeave)
        Minimap:HookScript("OnMouseUp", function(_, button)
            if mod.active and button == "MiddleButton" and mod.db.middleClickMenu then
                if _G.MainMenuMicroButton and _G.ToggleFrame then
                    pcall(_G.ToggleFrame, _G.MicroMenuContainer)
                end
            end
        end)
    end
    Minimap:EnableMouseWheel(true)
    Minimap:SetScript("OnMouseWheel", function(_, delta)
        if not mod.db.scrollZoom then return end
        if delta > 0 then Minimap.ZoomIn:Click() else Minimap.ZoomOut:Click() end
        scheduleZoomReset()
    end)
    -- what the map is allowed to be seen for
    for _, event in ipairs({ "PLAYER_TARGET_CHANGED", "PLAYER_MOUNT_DISPLAY_CHANGED",
                             "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED" }) do
        self:RegisterEvent(event, function() MM.Elements.ApplyVisibility() end)
    end
    self:Apply()
    -- A box in our edit mode for the whole minimap cluster. The cluster is
    -- one of the client's Edit Mode systems, so it is moved the careful way
    -- (Core/EditModeMover.lua); its place is saved here, in the profile.
    if MinimapCluster then
        self.editMover = ns:AttachEditModeMover(MinimapCluster, {
            key      = "minimap",
            label    = L["Minimap"],
            module   = "minimapstyle",
            isActive = function() return mod.active end,
            getPos   = function() return mod.db.clusterPos end,
            setPos   = function(p) mod.db.clusterPos = p end,
            onPlaced = function() if mod.active then mod:Apply() end end,
        })
        self.editMover.Apply()
    end
    -- And one for the queue eye, the same careful way. Without a place of
    -- its own it sits where the look puts it; a reset hands it back there.
    if _G.QueueStatusButton then
        self.queueMover = ns:AttachEditModeMover(_G.QueueStatusButton, {
            key      = "minimap_queue",
            label    = L["Queue eye"],
            module   = "minimapstyle",
            isActive = function() return mod.active end,
            getPos   = function() return mod.db.queuePos end,
            setPos   = function(p) mod.db.queuePos = p end,
            onPlaced = function() if mod.active then mod:Apply() end end,
        })
        self.queueMover.Apply()
    end
end

function mod:OnDisable()
    if self.editMover then self.editMover.Release() end
    if self.queueMover then self.queueMover.Release() end
    MM.Elements.HideAll()
    if MinimapCluster then MinimapCluster:Show() end
    Minimap:SetScript("OnMouseWheel", blizzWheel)
    applyStandard()
    applyClutter()
    scaleQueue(1)
    -- the collector's opener wore the classic map's size; give it back
    local m = ns.modules and ns.modules.minimapcollector
    if m and m.active and m.UpdatePosition then pcall(m.UpdatePosition) end
end

-- ---------------------------------------------------------------------------
-- Which classic textures this client actually ships
--
-- The classic look is built from Blizzard's own 1.x art. Whether Forever still
-- carries those files is not something the UI source can answer -- only the
-- running client can, and SetTexture returning false is how it says no.
-- ---------------------------------------------------------------------------
local CLASSIC_ART = {
    "Interface\\Minimap\\UI-Minimap-Border",
    "Interface\\Minimap\\UI-Minimap-Background",
    "Interface\\Minimap\\CompassRing",
    "Interface\\Minimap\\CompassNorthTag",
    "Interface\\Minimap\\MiniMap-TrackingBorder",
    "Interface\\Minimap\\UI-Minimap-ZoomInButton-Up",
    "Interface\\Minimap\\UI-Minimap-ZoomInButton-Down",
    "Interface\\Minimap\\UI-Minimap-ZoomInButton-Disabled",
    "Interface\\Minimap\\UI-Minimap-ZoomOutButton-Up",
    "Interface\\Minimap\\UI-Minimap-ZoomOutButton-Down",
    "Interface\\Minimap\\UI-Minimap-ZoomOutButton-Disabled",
    "Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight",
    "Interface\\CharacterFrame\\TempPortraitAlphaMask",
    "Interface\\TimeManager\\ClockBackground",
    "Interface\\Calendar\\UI-Calendar-Button",
}

ns:RegisterSlash({ key = "MMTEX", commands = { "/vfmmtex" },
    desc = "Report which classic minimap textures this client ships.",
})

local probeTex

ns.Slash.MMTEX = function()
    if not probeTex then probeTex = UIParent:CreateTexture(nil, "BACKGROUND"); probeTex:Hide() end
    local A, R = ns.C.accent, ns.C.r
    ns:Print("%sClassic minimap art%s", A, R)
    local missing = 0
    for _, path in ipairs(CLASSIC_ART) do
        local ok = probeTex:SetTexture(path) ~= false and probeTex:GetTexture() ~= nil
        if not ok then missing = missing + 1 end
        ns:Print("  %s%-52s%s", ok and (ns.C.pos .. "yes  " .. R) or (ns.C.neg .. "NO   " .. R),
            path:gsub("Interface\\", ""), "")
    end
    ns:Print("  %d of %d missing", missing, #CLASSIC_ART)
end
