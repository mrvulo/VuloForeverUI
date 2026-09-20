-- VuloForeverUI / Modules / QoL / Display
--
-- Four small readouts that have nothing to do with each other except that they
-- all draw text on the screen and none of them reads anything the client
-- keeps secret:
--
--   fps          frame rate and the two latencies, on the shared ticker
--   combat line  a word when a fight starts and when it ends
--   crosshair    two bars in the middle of the screen
--   map coords   your position and the cursor, on the world map
--
-- The frame rate and the latencies come from GetFramerate and GetNetStats,
-- both plain numbers at all times; the crosshair reads nothing at all. The one
-- thing that needs care here is the tick rate, which is why the frame rate
-- rides the house ticker rather than an OnUpdate of its own: an idle readout
-- then costs nothing per frame.
local _, ns = ...
local L = ns.L

local QoL = ns.QoL
local Display = QoL.RegisterPart("display", {})
QoL.Display = Display

local DIM = "|cff9d9d9d"

-- ----------------------------------------------------------------- fps --

local fpsFrame, fpsTicker

local function fpsColor()
    local c = QoL.db().fps.color
    return string.format("%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255)
end

local function fpsUpdate()
    if not (fpsFrame and fpsFrame:IsShown()) then return end
    local db = QoL.db().fps
    local hex = fpsColor()
    local parts = { "|cff" .. hex .. math.floor(GetFramerate() + 0.5) .. " fps|r" }
    local _, _, home, world = GetNetStats()
    if db.showWorld then
        parts[#parts + 1] = "|cff" .. hex .. world .. " ms|r"
            .. (db.showLabel and (DIM .. " " .. L["(world)"] .. "|r") or "")
    end
    if db.showLocal then
        parts[#parts + 1] = "|cff" .. hex .. home .. " ms|r"
            .. (db.showLabel and (DIM .. " " .. L["(local)"] .. "|r") or "")
    end
    -- Two pipes render one literal pipe; the divider is dim on purpose, it is
    -- punctuation rather than a value.
    fpsFrame.text:SetText(table.concat(parts, DIM .. " || " .. "|r"))

    local w, h = fpsFrame.text:GetStringWidth(), fpsFrame.text:GetStringHeight()
    if w > 0 then
        fpsFrame:SetSize(w + 4, h + 4)
        if fpsFrame.mover then
            fpsFrame.mover.opts.width, fpsFrame.mover.opts.height = w + 4, h + 4
            ns:RefreshMoverGeometry(fpsFrame.mover)
        end
    end
end

local function createFPS()
    if fpsFrame then return fpsFrame end
    fpsFrame = CreateFrame("Frame", "VuloForeverUIFPSCounter", UIParent)
    fpsFrame:SetSize(120, 20)
    fpsFrame:SetFrameStrata("LOW")
    fpsFrame:EnableMouse(false)

    local fs = fpsFrame:CreateFontString(nil, "OVERLAY")
    fs:SetPoint("LEFT")
    fs:SetJustifyH("LEFT")
    fpsFrame.text = fs

    fpsFrame.mover = ns:CreateMover(fpsFrame, {
        key      = "qol_fps",
        label    = L["Frame rate"],
        db       = QoL.db().fps,
        module   = "qol",
        width    = 120,
        height   = 20,
        scalable = true,
    })
    ns:ApplyMover(fpsFrame.mover)
    return fpsFrame
end

local function applyFPS()
    local db = QoL.db().fps
    if fpsTicker then ns:CancelTicker(fpsTicker); fpsTicker = nil end
    if not db.enabled then
        if fpsFrame then fpsFrame:Hide() end
        return
    end
    createFPS()
    fpsFrame.text:SetFont(QoL.Font(), db.fontSize, QoL.Outline())
    ns:ApplyMover(fpsFrame.mover)
    fpsFrame:Show()
    fpsUpdate()
    fpsTicker = ns:AddTicker(db.interval, fpsUpdate, nil, "qol.fps")
end

-- --------------------------------------------------------- combat line --

local alertFrame

local function alertSettings()
    if not alertFrame then return end
    local db = QoL.db().combatAlert
    -- An outline always, whatever the shared setting says: this line appears
    -- over the middle of the screen, on top of whatever happens to be there.
    local outline = QoL.Outline()
    if not outline:find("OUTLINE") then
        outline = (outline == "") and "OUTLINE" or (outline .. ", OUTLINE")
    end
    alertFrame.text:SetFont(QoL.Font(), db.fontSize, outline)
    alertFrame:SetSize(db.fontSize * 8, db.fontSize + 14)
    if alertFrame.mover then
        alertFrame.mover.opts.width  = alertFrame:GetWidth()
        alertFrame.mover.opts.height = alertFrame:GetHeight()
        ns:RefreshMoverGeometry(alertFrame.mover)
        ns:ApplyMover(alertFrame.mover)
    end
end
Display.RefreshAlert = alertSettings

local function createAlert()
    if alertFrame then return alertFrame end
    alertFrame = CreateFrame("Frame", "VuloForeverUICombatAlert", UIParent)
    alertFrame:SetSize(200, 40)
    alertFrame:SetFrameStrata("HIGH")
    alertFrame:EnableMouse(false)

    local fs = alertFrame:CreateFontString(nil, "OVERLAY")
    fs:SetPoint("CENTER")
    alertFrame.text = fs

    local ag = alertFrame:CreateAnimationGroup()
    local fadeIn = ag:CreateAnimation("Alpha")
    fadeIn:SetFromAlpha(0); fadeIn:SetToAlpha(1); fadeIn:SetDuration(0.15); fadeIn:SetOrder(1)
    local hold = ag:CreateAnimation("Alpha")
    hold:SetFromAlpha(1); hold:SetToAlpha(1); hold:SetDuration(1.2); hold:SetOrder(2)
    local fadeOut = ag:CreateAnimation("Alpha")
    fadeOut:SetFromAlpha(1); fadeOut:SetToAlpha(0); fadeOut:SetDuration(0.5); fadeOut:SetOrder(3)
    ag:SetScript("OnFinished", function() alertFrame:Hide() end)
    alertFrame.anim = ag
    alertFrame:SetScript("OnHide", function() ag:Stop() end)

    alertFrame.mover = ns:CreateMover(alertFrame, {
        key      = "qol_combatalert",
        label    = L["Combat line"],
        db       = QoL.db().combatAlert,
        module   = "qol",
        width    = 200,
        height   = 40,
        scalable = true,
        fill     = true,   -- shown for two seconds at a time
    })
    alertSettings()
    ns:ApplyMover(alertFrame.mover)
    alertFrame:Hide()
    return alertFrame
end

local function showAlert(which)
    -- Never fire a live alert while the mover owns the frame.
    if ns:IsMoverEditMode() then return end
    createAlert()
    alertSettings()
    local db = QoL.db().combatAlert
    local c = (which == "leave") and db.leaveColor or db.enterColor
    alertFrame.text:SetText((which == "leave") and db.leaveText or db.enterText)
    alertFrame.text:SetTextColor(c.r, c.g, c.b, 1)
    alertFrame.anim:Stop()
    alertFrame:SetAlpha(1)
    alertFrame:Show()
    alertFrame.anim:Play()
end
Display.ShowAlert = showAlert

local function onCombatStart()
    if QoL.db().combatAlert.mode ~= "leave" then showAlert("enter") end
end

local function onCombatEnd()
    if QoL.db().combatAlert.mode ~= "enter" then showAlert("leave") end
end

-- ----------------------------------------------------------- crosshair --

local crossFrame

local function applyCrosshair()
    local db = QoL.db().crosshair
    if not db.enabled then
        if crossFrame then crossFrame:Hide() end
        return
    end

    if not crossFrame then
        crossFrame = CreateFrame("Frame", "VuloForeverUICrosshair", UIParent)
        crossFrame:SetFrameStrata("BACKGROUND")
        crossFrame:EnableMouse(false)
        crossFrame:SetSize(1, 1)
        local function bar(layer)
            local t = crossFrame:CreateTexture(nil, layer)
            if t.SetSnapToPixelGrid then
                t:SetSnapToPixelGrid(false)
                t:SetTexelSnappingBias(0)
            end
            t:SetPoint("CENTER")
            return t
        end
        -- The borders sit below, so the arms are drawn on top of them.
        crossFrame.hEdge, crossFrame.vEdge = bar("ARTWORK"), bar("ARTWORK")
        crossFrame.h, crossFrame.v = bar("OVERLAY"), bar("OVERLAY")
    end

    crossFrame:ClearAllPoints()
    crossFrame:SetPoint("CENTER", UIParent, "CENTER", db.xOffset, db.yOffset)

    local len = ns:Pixel(crossFrame, db.length)
    local thick = ns:Pixel(crossFrame, db.thickness)
    local c, bc = db.color, db.borderColor
    crossFrame.h:SetSize(len, thick)
    crossFrame.h:SetColorTexture(c.r, c.g, c.b, c.a)
    crossFrame.v:SetSize(thick, len)
    crossFrame.v:SetColorTexture(c.r, c.g, c.b, c.a)

    if db.borderSize > 0 then
        local b = ns:Pixel(crossFrame, db.borderSize)
        crossFrame.hEdge:SetSize(len + b * 2, thick + b * 2)
        crossFrame.hEdge:SetColorTexture(bc.r, bc.g, bc.b, bc.a)
        crossFrame.vEdge:SetSize(thick + b * 2, len + b * 2)
        crossFrame.vEdge:SetColorTexture(bc.r, bc.g, bc.b, bc.a)
        crossFrame.hEdge:Show(); crossFrame.vEdge:Show()
    else
        crossFrame.hEdge:Hide(); crossFrame.vEdge:Hide()
    end

    local show = true
    if db.visibility == "combat" then
        show = ns:InCombat() or UnitAffectingCombat("player")
    elseif db.visibility == "instances" then
        show = IsInInstance()
    end
    if show then crossFrame:Show() else crossFrame:Hide() end
end
Display.ApplyCrosshair = applyCrosshair

-- ---------------------------------------------------------- map coords --

local coordFrame

local function createCoords()
    if coordFrame then return coordFrame end
    if not (WorldMapFrame and WorldMapFrame.ScrollContainer) then return nil end

    coordFrame = CreateFrame("Frame", nil, WorldMapFrame.ScrollContainer)
    coordFrame:SetFrameStrata("HIGH")
    coordFrame:SetSize(1, 1)
    coordFrame:SetPoint("BOTTOM", WorldMapFrame.ScrollContainer, "BOTTOM", 0, 10)

    local player = coordFrame:CreateFontString(nil, "OVERLAY")
    player:SetPoint("RIGHT", coordFrame, "CENTER", -10, 0)
    player:SetJustifyH("RIGHT")
    local cursor = coordFrame:CreateFontString(nil, "OVERLAY")
    cursor:SetPoint("LEFT", coordFrame, "CENTER", 10, 0)
    cursor:SetJustifyH("LEFT")
    coordFrame.player, coordFrame.cursor = player, cursor

    -- The map is only open while you look at it, so an OnUpdate here is bound
    -- to the window rather than to the session.
    local acc = 0
    coordFrame:SetScript("OnUpdate", function(_, elapsed)
        acc = acc + elapsed
        if acc < 0.05 then return end
        acc = 0
        local mapID = WorldMapFrame:GetMapID()
        if not mapID then
            player:SetText(""); cursor:SetText("")
            return
        end
        local pos = C_Map.GetPlayerMapPosition(mapID, "player")
        if pos then
            local px, py = pos:GetXY()
            if px and py and px > 0 and py > 0 then
                player:SetFormattedText("%s %.1f, %.1f", L["You"], px * 100, py * 100)
            else
                player:SetText("")
            end
        else
            player:SetText("")
        end

        local child = WorldMapFrame.ScrollContainer.Child
        if child and child:IsMouseOver() then
            local cw, ch = child:GetSize()
            local scale, left, top = child:GetEffectiveScale(), child:GetLeft(), child:GetTop()
            if cw > 0 and ch > 0 and scale and left and top then
                local mx, my = GetCursorPosition()
                local nx, nyv = (mx / scale - left) / cw, (top - my / scale) / ch
                if nx >= 0 and nx <= 1 and nyv >= 0 and nyv <= 1 then
                    cursor:SetFormattedText("%s %.1f, %.1f", L["Cursor"], nx * 100, nyv * 100)
                else
                    cursor:SetText("")
                end
            end
        else
            cursor:SetText("")
        end
    end)
    return coordFrame
end

local function applyCoords()
    local db = QoL.db()
    if not db.mapCoords then
        if coordFrame then coordFrame:Hide() end
        return
    end
    if not C_AddOns.IsAddOnLoaded("Blizzard_WorldMap") then return end
    if not createCoords() then return end
    coordFrame.player:SetFont(QoL.Font(), db.mapCoordsSize, QoL.Outline())
    coordFrame.cursor:SetFont(QoL.Font(), db.mapCoordsSize, QoL.Outline())
    coordFrame:Show()
end
Display.ApplyCoords = applyCoords

local function onAddOnLoaded(_, name)
    -- The world map is loaded on demand, so the coordinates wait for it.
    if name == "Blizzard_WorldMap" then applyCoords() end
end

-- ----------------------------------------------------------- lifecycle --

local function onCombatEdge(event)
    if event == "PLAYER_REGEN_DISABLED" then onCombatStart() else onCombatEnd() end
    applyCrosshair()
end

local function onEnteringWorld()
    applyCrosshair()
end

function Display.Apply()
    local db = QoL.db()

    applyFPS()

    local alertOn = db.combatAlert.enabled and true or false
    local crossOn = db.crosshair.enabled and true or false
    -- One handler for both: the crosshair can be bound to combat as well, and
    -- two registrations on the same edge would only make the order matter.
    local edgeOn = alertOn or crossOn
    QoL.SyncEvent(edgeOn, "PLAYER_REGEN_DISABLED", onCombatEdge)
    QoL.SyncEvent(edgeOn, "PLAYER_REGEN_ENABLED", onCombatEdge)
    QoL.SyncEvent(crossOn, "PLAYER_ENTERING_WORLD", onEnteringWorld)
    if alertOn then createAlert(); alertSettings() end
    applyCrosshair()

    QoL.SyncEvent(db.mapCoords and true or false, "ADDON_LOADED", onAddOnLoaded)
    applyCoords()
end

function Display.Disable()
    if fpsTicker then ns:CancelTicker(fpsTicker); fpsTicker = nil end
    if fpsFrame then fpsFrame:Hide() end
    if alertFrame then alertFrame:Hide() end
    if crossFrame then crossFrame:Hide() end
    if coordFrame then coordFrame:Hide() end
    ns:UnregisterEvent("PLAYER_REGEN_DISABLED", onCombatEdge)
    ns:UnregisterEvent("PLAYER_REGEN_ENABLED", onCombatEdge)
    ns:UnregisterEvent("PLAYER_ENTERING_WORLD", onEnteringWorld)
    ns:UnregisterEvent("ADDON_LOADED", onAddOnLoaded)
end
