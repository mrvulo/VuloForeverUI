-- VuloForeverUI / Modules / QoL / Gold
--
-- The day's gold: what came in, what went out, what is left, and the balance.
-- Shown under the money line of the bags (Modules/Bags/Gold.lua asks for it).
--
-- WHY IT SURVIVES A RELOAD
--
-- The session lives in the character's saved variables, not in a local: a
-- reload or a relog picks up the same numbers. It starts over on the first
-- login of a new calendar day, or when you press the reset button.
--
-- HOW IT COUNTS
--
-- Every PLAYER_MONEY compares the purse with the last one seen: up is earned,
-- down is spent. Money does not move while you are offline, so the purse on
-- login only becomes the new reference, it is never counted.
local _, ns = ...
local L = ns.L

local QoL = ns.QoL
local Gold = QoL.RegisterPart("gold", {})
QoL.Gold = Gold

local registered

local function db() return QoL.db().gold end

local function today() return date("%Y-%m-%d") end

local function money()
    local m = GetMoney()
    if ns.CanRead(m) and type(m) == "number" then return m end
    return nil
end

local function store()
    if not VuloForeverUICharDB then return nil end
    local s = VuloForeverUICharDB.qolGold
    if type(s) ~= "table" then s = {}; VuloForeverUICharDB.qolGold = s end
    return s
end

local function start(s, m)
    s.day, s.start, s.last = today(), m, m
    s.earned, s.spent = 0, 0
end

-- A new day starts a new session. Checked on every read as well, so a session
-- left running past midnight shows the new day without waiting for a coin.
local function current()
    local s, m = store(), money()
    if not (s and m) then return nil end
    if s.day ~= today() or type(s.last) ~= "number" then start(s, m) end
    return s, m
end

local function onMoney()
    local s, m = current()
    if not s then return end
    local diff = m - s.last
    if diff > 0 then
        s.earned = s.earned + diff
    elseif diff < 0 then
        s.spent = s.spent - diff
    end
    s.last = m
end

local function onLogin()
    local s, m = current()
    if s then s.last = m end
end

function Gold.Reset()
    local s, m = store(), money()
    if s and m then start(s, m) end
end

function Gold.Active()
    return QoL.mod.active and db().session
end

-- Lines for the bags' money tooltip, or nil when the session is off.
function Gold.SessionLines(text)
    if not Gold.Active() then return nil end
    local s, m = current()
    if not s then return nil end
    local net = m - s.start
    local lines = {
        { L["Today"], 1, 0.82, 0 },
        { L["Earned"], right = "|cff55ff55+" .. text(s.earned) .. "|r" },
        { L["Spent"],  right = "|cffff5555-" .. text(s.spent) .. "|r" },
        { L["Now"],    right = text(m) },
    }
    if net >= 0 then
        lines[#lines + 1] = { L["Balance"], right = "|cff55ff55+" .. text(net) .. "|r" }
    else
        lines[#lines + 1] = { L["Balance"], right = "|cffff5555-" .. text(-net) .. "|r" }
    end
    return lines
end

function Gold.Apply()
    local on = Gold.Active()
    if on == registered then return end
    registered = on
    QoL.SyncEvent(on, "PLAYER_MONEY", onMoney)
    QoL.SyncEvent(on, "PLAYER_ENTERING_WORLD", onLogin)
    if on then onLogin() end
end

function Gold.Disable()
    if not registered then return end
    registered = nil
    ns:UnregisterEvent("PLAYER_MONEY", onMoney)
    ns:UnregisterEvent("PLAYER_ENTERING_WORLD", onLogin)
end
