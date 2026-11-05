-- VuloForeverUI / Modules / QoL / Professions
--
-- Gathering made easier to see: with Mining or Herbalism known, the client's
-- own interact icon (pickaxe, herb) stands over the ore or herb you face,
-- from further away than the client's default.
--
-- HOW, AND WHY THIS WAY
--
-- The sparkle on quest objects is drawn by the engine for quest objects only;
-- no API lets an addon put an effect on a world object, and node positions are
-- not readable either. What the client does offer is soft interact: its
-- CVars pick the interactable object in front of you and mark it with an icon.
-- This part only sets those CVars, and only while the character knows a
-- gathering profession. The player's own values are kept in the saved
-- settings (professions.savedCVars) and come back when the switch goes off,
-- the profession is unlearned or the module is disabled.
--
-- Fishing (Fishing.lua) sets some of the same CVars while the line is out and
-- puts back what it found. The two share the work: whichever keeps a value,
-- the other writes through that keep, so neither restores the other's value
-- as the player's own. SoftTargetInteract is a secure CVar -- never written in
-- combat.
local _, ns = ...

local QoL = ns.QoL
local Prof = QoL.RegisterPart("professions", {})
QoL.Professions = Prof

local MINING, HERBALISM = 186, 182        -- skill line IDs
local ARC_FRONT = "1"                     -- anywhere in the front arc, not only straight ahead

local function db() return QoL.db().professions end
local function fishKeep()
    local f = QoL.db().fishing
    return type(f) == "table" and type(f.savedCVars) == "table" and f.savedCVars or nil
end

-- What the icon needs; the range is the player's.
local function wanted()
    return {
        SoftTargetInteract       = "3",
        SoftTargetIconGameObject = "1",
        SoftTargetIconInteract   = "1",
        SoftTargetInteractArc    = ARC_FRONT,
        SoftTargetInteractRange  = tostring(db().range or 40),
    }
end

-- Mining or Herbalism among the two main professions.
function Prof.KnowsGathering()
    if type(GetProfessions) ~= "function" then return false end
    local p1, p2 = GetProfessions()
    for _, idx in ipairs({ p1 or 0, p2 or 0 }) do
        if idx > 0 then
            local skillLine = select(7, GetProfessionInfo(idx))
            if skillLine == MINING or skillLine == HERBALISM then return true end
        end
    end
    return false
end

local function setOn()
    local keep = db().savedCVars
    if type(keep) ~= "table" then keep = {}; db().savedCVars = keep end
    local fk = fishKeep()
    for k, v in pairs(wanted()) do
        local cur = C_CVar.GetCVar(k)
        if cur ~= nil then
            if keep[k] == nil then keep[k] = (fk and fk[k]) or cur end
            if cur ~= v then C_CVar.SetCVar(k, v) end
            if fk and fk[k] ~= nil then fk[k] = v end   -- fishing's end leaves ours
        end
    end
end

local function restore()
    local keep = db().savedCVars
    if type(keep) ~= "table" or not next(keep) then return end
    local fk = fishKeep()
    for k, v in pairs(keep) do
        if fk and fk[k] ~= nil then
            fk[k] = v                                   -- fishing puts it back when it ends
        else
            C_CVar.SetCVar(k, v)
        end
    end
    db().savedCVars = nil
end

local registered

local function update()
    if InCombatLockdown() then
        ns:RunOutOfCombatOnce("qol_professions", update)
        return
    end
    local on = QoL.mod.active and db().gatherIcon and Prof.KnowsGathering()
    if on then setOn() else restore() end
end

function Prof.Apply()
    local listen = QoL.mod.active and db().gatherIcon and true or false
    if listen ~= (registered or false) then
        registered = listen
        QoL.SyncEvent(listen, "SKILL_LINES_CHANGED", update)
    end
    update()
end

function Prof.Disable()
    ns:UnregisterEvent("SKILL_LINES_CHANGED", update)
    registered = nil
    if InCombatLockdown() then
        ns:RunOutOfCombatOnce("qol_professions_off", restore)
    else
        restore()
    end
end
