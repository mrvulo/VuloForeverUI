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

-- What the icon needs; the range is the player's. The sparkle (NodeSparkle.lua)
-- adds the object nameplate, kept closed here and opened per herb or ore.
local function wanted()
    local w = {
        SoftTargetInteract       = "3",
        SoftTargetIconGameObject = "1",
        SoftTargetIconInteract   = "1",
        SoftTargetInteractArc    = ARC_FRONT,
        SoftTargetInteractRange  = tostring(db().range or 40),
    }
    if Prof.Sparkle and Prof.Sparkle.Wanted() then
        w.SoftTargetNameplateInteract    = "0"
        w.nameplateGameObjectMaxDistance = tostring(math.max(db().range or 40, 20))
    end
    return w
end

-- "40" and "40.000000" are the same distance: no write, no CVAR_UPDATE.
local function same(cur, v)
    return cur == v or (tonumber(cur) ~= nil and tonumber(cur) == tonumber(v))
end

-- Is this gathering skill line (MINING, HERBALISM) among the two main
-- professions? Without an argument: either of them.
local function knows(line)
    if type(GetProfessions) ~= "function" then return false end
    local p1, p2 = GetProfessions()
    for _, idx in ipairs({ p1 or 0, p2 or 0 }) do
        if idx > 0 then
            local skillLine = select(7, GetProfessionInfo(idx))
            if skillLine == line or (line == nil and (skillLine == MINING or skillLine == HERBALISM)) then
                return true
            end
        end
    end
    return false
end

function Prof.KnowsGathering() return knows(nil) end
function Prof.KnowsHerbalism() return knows(HERBALISM) end
function Prof.KnowsMining() return knows(MINING) end

local function giveBack(k, v, fk)
    if fk and fk[k] ~= nil then
        fk[k] = v                                       -- fishing puts it back when it ends
    else
        C_CVar.SetCVar(k, v)
    end
end

local function setOn()
    local keep = db().savedCVars
    if type(keep) ~= "table" then keep = {}; db().savedCVars = keep end
    local fk = fishKeep()
    local w = wanted()
    -- a value no longer wanted (the sparkle switched off) goes back on its own
    for k, v in pairs(keep) do
        if w[k] == nil then giveBack(k, v, fk); keep[k] = nil end
    end
    for k, v in pairs(w) do
        local cur = C_CVar.GetCVar(k)
        if cur ~= nil then
            if keep[k] == nil then keep[k] = (fk and fk[k]) or cur end
            if not same(cur, v) then C_CVar.SetCVar(k, v) end
            if fk and fk[k] ~= nil then fk[k] = v end   -- fishing's end leaves ours
        end
    end
end

local function restore()
    local keep = db().savedCVars
    if type(keep) ~= "table" or not next(keep) then return end
    local fk = fishKeep()
    for k, v in pairs(keep) do giveBack(k, v, fk) end
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
    if Prof.Sparkle then Prof.Sparkle.Apply() end
end

-- The sparkle asks for this after a loading screen: the client puts some of
-- these values back on its own there.
Prof.Refresh = update

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
    if Prof.Sparkle then Prof.Sparkle.Apply(true) end
    if InCombatLockdown() then
        ns:RunOutOfCombatOnce("qol_professions_off", restore)
    else
        restore()
    end
end
