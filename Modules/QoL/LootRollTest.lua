-- VuloForeverUI / Modules / QoL / LootRollTest
--
-- The loot roll list's example rows (F-81), for the options button and our
-- edit mode. The data and the rows are LootRoll.lua and LootRollList.lua.
local _, ns = ...
local L = ns.L

local QoL = ns.QoL
local LR = QoL.LootRoll
local rolls = LR.rolls

local TEST_TIME = 20    -- seconds the test rolls stay
local testToken = 0

-- Test rows give way to a real roll, and go when the part is switched off.
function LR.DropTests()
    local removed = false
    for i = #rolls, 1, -1 do
        if rolls[i].test then table.remove(rolls, i); removed = true end
    end
    LR.testing = false
    testToken = testToken + 1
    return removed
end
local dropTests = LR.DropTests

-- Example rows for judging the layout: no roll behind them, the buttons do
-- nothing, the history is made up -- one of them finished with a winner.
local TEST_ICONS = {
    "Interface\\Icons\\INV_Sword_04",
    "Interface\\Icons\\INV_Helmet_03",
    "Interface\\Icons\\INV_Misc_Bag_08",
    "Interface\\Icons\\INV_Jewelry_Ring_03",
}

local function fakePlayers(states, winner)
    local me = UnitName and UnitName("player") or "?"
    local names = { me, "Brannor", "Elyse", "Tovik", "Mirra" }
    local classes = { select(2, UnitClass("player")) or "WARRIOR", "WARRIOR", "PRIEST", "ROGUE", "MAGE" }
    local list = {}
    for i, s in ipairs(states) do
        list[i] = {
            playerName = names[i], playerClass = classes[i], isSelf = i == 1,
            state = s, isWinner = winner == i,
            roll = winner and (s ~= 5) and (100 - i * 13) or nil,
        }
    end
    return list
end

local function testRows()
    local now = GetTime()
    local function row(i, t)
        t.test, t.texture = true, TEST_ICONS[i]
        t.name = L["Example item %d"]:format(i)
        t.duration = 60000
        t.endsAt = now + (t.left or 60)
        return t
    end
    local list = {
        row(1, { quality = 4, count = 1, canNeed = true, canGreed = true, canDE = true, boe = true, left = 52,
                 info = { rollInfos = fakePlayers({ 4, 0, 3, 5, 4 }) } }),
        row(2, { quality = 3, count = 1, canNeed = true, canTransmog = true, boe = false, left = 37, choice = 1,
                 info = { rollInfos = fakePlayers({ 0, 2, 5, 0 }) } }),
        row(3, { quality = 2, count = 5, canNeed = false, reasonNeed = 1, canGreed = true, boe = false, left = 18,
                 info = { rollInfos = fakePlayers({ 4, 3, 3 }) } }),
        row(4, { quality = 3, count = 1, canNeed = true, canGreed = true, boe = true, left = 0, choice = 2,
                 doneAt = now, info = { rollInfos = fakePlayers({ 3, 0, 5, 3 }, 2) } }),
    }
    local d4 = list[4]
    d4.info.winner = d4.info.rollInfos[2]
    return list
end

local function showTest(on)
    dropTests()
    if on then
        for _, t in ipairs(testRows()) do rolls[#rolls + 1] = t end
        LR.testing = true
        LR.hidden, LR.collapsed = nil, nil
    end
    LR.Layout()
end

-- The options button: on for 20 seconds, or until clicked again.
function LR.ToggleTest()
    if not LR.IsActive() then return end
    local on = not LR.testing
    showTest(on)
    if on then
        local token = testToken
        C_Timer.After(TEST_TIME, function()
            if token == testToken and not LR.editing then showTest(false) end
        end)
    end
end

-- Our edit mode: the examples give the mover something to show.
function LR.EditPreview(on)
    LR.editing = on and true or false
    if not LR.IsActive() then return end
    if on then
        local real = false
        for _, r in ipairs(rolls) do
            if not r.test then real = true; break end
        end
        if not real and not LR.testing then showTest(true) end
    elseif LR.testing then
        showTest(false)
    end
end
