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

-- One message on the combat line, whatever put it there. Both the +Combat line
-- and the combat messages below go through this, so they share the frame, the
-- font, the mover and the fade -- three different looks for three kinds of
-- notice would be three things to place and three to style.
local function showMessage(text, color)
    if ns:IsMoverEditMode() then return end
    createAlert()
    alertSettings()
    alertFrame.text:SetText(text)
    local c = color or { r = 1, g = 1, b = 1 }
    alertFrame.text:SetTextColor(c.r, c.g, c.b, 1)
    alertFrame.anim:Stop()
    alertFrame:SetAlpha(1)
    alertFrame:Show()
    alertFrame.anim:Play()
end

Display.ShowMessage = showMessage

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

-- ------------------------------------------------- combat messages --
--
-- WHERE THESE COME FROM, GIVEN THERE IS NO COMBAT LOG
--
-- `COMBAT_TEXT_UPDATE` is not the combat log. It is the feed behind the game's
-- own floating combat text, it carries ONE argument -- the kind of thing that
-- just happened -- and that argument is a plain readable string. The numbers
-- behind it are not: `C_CombatText.GetCurrentEventInfo` is declared
-- `SecretReturns` in this build, so an amount could only ever be handed to a
-- widget, never compared. None of the messages below need one.
--
-- The kinds come from the client's own table (Blizzard_CombatText/Shared/
-- CombatTextConstants.lua), which is why INTERRUPT and SPELL_REFLECT are here
-- and a banish or a buff handed to someone else is not: those exist only in the
-- combat log, and the combat log is not readable at all.
--
-- The feed reports the ACTIVE UNIT, which is the player unless something else
-- claims it. So these are your interrupts, your reflects, your dodges.

local MESSAGE_TYPE = {
    INTERRUPT      = "interrupted",
    SPELL_REFLECT  = "reflected",
    MISS           = "avoided", SPELL_MISS    = "avoided",
    DODGE          = "avoided", SPELL_DODGE   = "avoided",
    PARRY          = "avoided", SPELL_PARRY   = "avoided",
    BLOCK          = "avoided", SPELL_BLOCK   = "avoided",
    DEFLECT        = "avoided", SPELL_DEFLECT = "avoided",
    EVADE          = "avoided", SPELL_EVADE   = "avoided",
    IMMUNE         = "avoided", SPELL_IMMUNE  = "avoided",
    RESIST         = "avoided", SPELL_RESIST  = "avoided",
}

-- The word each kind says -- the CLIENT'S OWN word, not one of ours.
--
-- The game already names every one of these on its floating combat text
-- (COMBAT_TEXT_DODGE, COMBAT_TEXT_PARRY, ...), in whatever language it is
-- running. Taking those strings means the message reads exactly like the rest
-- of the game and stays right in a language nobody here speaks. The SPELL_
-- kinds share the word of their plain sibling, which is how the client's own
-- table is built; INTERRUPT has no combat-text string, so it borrows the
-- global the client uses for the same thing.
--
-- Our own words stay as the fallback, for a build where one of the globals is
-- missing: an empty message would be worse than an English one.
local FALLBACK_WORD
ns.OnLocaleReady(function()
    FALLBACK_WORD = {
        INTERRUPT = L["Interrupted!"], REFLECT = L["Reflected!"],
        MISS      = L["Missed!"],      DODGE   = L["Dodged!"],
        PARRY     = L["Parried!"],     BLOCK   = L["Blocked!"],
        DEFLECT   = L["Deflected!"],   EVADE   = L["Evaded!"],
        IMMUNE    = L["Immune!"],      RESIST  = L["Resisted!"],
    }
end)

local function wordFor(kind)
    local base = kind:gsub("^SPELL_", "")
    if base == "INTERRUPT" then
        local s = _G.INTERRUPTED
        return (type(s) == "string" and s ~= "" and s) or (FALLBACK_WORD and FALLBACK_WORD.INTERRUPT)
    end
    local s = _G["COMBAT_TEXT_" .. base]
    if type(s) == "string" and s ~= "" then return s end
    return FALLBACK_WORD and FALLBACK_WORD[base]
end

local function onCombatText(_, kind)
    local d = QoL.db().combatEvents
    local group = kind and MESSAGE_TYPE[kind]
    if not group or not d[group] then return end
    local word = wordFor(kind)
    if not word then return end
    showMessage(word, d[group .. "Color"])
end

-- Deaths in the group have no such feed, so they are looked at rather than
-- listened for: once a second, and only while you are in a group at all. The
-- dead flag can come back as a secret in restricted content, and a truth test
-- on a secret throws -- ns.CanRead is the gate in front of it, and a unit whose
-- state cannot be read this second is simply left for the next one.
local deathTicker
local wasDead = {}

local function checkDeaths()
    local d = QoL.db().combatEvents
    local n = GetNumGroupMembers and GetNumGroupMembers() or 0
    if n == 0 then wipe(wasDead); return end
    local prefix = (IsInRaid and IsInRaid()) and "raid" or "party"
    local count = (prefix == "raid") and n or (n - 1)

    for i = 1, count do
        local unit = prefix .. i
        if UnitExists(unit) then
            local dead = UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit)
            if ns.CanRead(dead) then
                local isDead = dead and true or false
                local name = UnitName(unit)
                if isDead and not wasDead[unit] and ns.CanRead(name) then
                    showMessage(string.format(L["%s died."], tostring(name)), d.partyDeathColor)
                end
                wasDead[unit] = isDead
            end
        else
            wasDead[unit] = nil
        end
    end
end

local function applyCombatEvents()
    local d = QoL.db().combatEvents
    local feed = d.interrupted or d.reflected or d.avoided
    QoL.SyncEvent(feed, "COMBAT_TEXT_UPDATE", onCombatText)

    if deathTicker then ns:CancelTicker(deathTicker); deathTicker = nil end
    wipe(wasDead)
    if d.partyDeath then
        deathTicker = ns:AddTicker(1, checkDeaths, nil, "qol.deaths")
    end
    if feed or d.partyDeath then createAlert(); alertSettings() end
end
Display.ApplyCombatEvents = applyCombatEvents

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

    applyCombatEvents()

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
