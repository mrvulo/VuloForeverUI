-- VuloForeverUI / Modules / Bags / Gold
--
-- What the money line in the bag header knows: what this character carries,
-- what every other character on the account carries, and what has come in and
-- gone out since the session started.
--
-- The store is ACCOUNT-WIDE (ns.db.global), not part of the profile: money is
-- a fact about a character, not a setting, and switching profile must not make
-- a character's gold disappear from the list.
local _, ns = ...
local L = ns.L
local Bags = ns.Bags

local Gold = {}
Bags.Gold = Gold

local startMoney       -- what the session started with
local lastMoney        -- what the last PLAYER_MONEY reported

local function global()
    local g = ns.db and ns.db.global
    if not g then return nil end
    local t = g.bagsGold
    if type(t) ~= "table" then t = {}; g.bagsGold = t end
    return t
end

local function me()
    local name = UnitName("player")
    if type(name) ~= "string" then return nil end
    local realm = GetRealmName()
    return name .. " - " .. (type(realm) == "string" and realm or "?")
end

-- Money as the client writes it, with the coin icons. GetMoneyString does not
-- exist on this client (checked against the 1.60.1 API list); the currency
-- namespace carries the same job.
function Gold.Text(amount)
    local fn = C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString
    if type(fn) == "function" then
        local ok, text = pcall(fn, amount or 0)
        if ok and type(text) == "string" then return text end
    end
    return tostring(math.floor((amount or 0) / 10000)) .. "g"
end

-- A signed amount, green up and red down. Used for the session line only,
-- where the direction is the whole point.
local function delta(amount)
    if amount == 0 then return nil end
    local colour = amount > 0 and "|cff55ff55+" or "|cffff5555-"
    return colour .. Gold.Text(math.abs(amount)) .. "|r"
end

-- ---------------------------------------------------------------- record --

function Gold.Record()
    local money = GetMoney() or 0
    if not startMoney then startMoney = money end
    lastMoney = money

    local t, key = global(), me()
    if not (t and key) then return end
    local entry = t[key]
    if type(entry) ~= "table" then entry = {}; t[key] = entry end
    entry.money = money
    entry.at = time()
end

function Gold.SessionChange()
    if not (startMoney and lastMoney) then return 0 end
    return lastMoney - startMoney
end

-- ---------------------------------------------------------------- tooltip --

-- Every character on the account, richest first, with the total underneath.
-- This is the whole reason the store is account-wide: "where is my gold" is a
-- question about the account, and it is asked from whichever character happens
-- to be logged in.
function Gold.Lines()
    local lines, total = {}, 0
    local t, key = global(), me()
    if t then
        local list = {}
        for name, entry in pairs(t) do
            if type(entry) == "table" and type(entry.money) == "number" then
                list[#list + 1] = { name = name, money = entry.money }
                total = total + entry.money
            end
        end
        table.sort(list, function(a, b) return a.money > b.money end)
        for _, row in ipairs(list) do
            local label = row.name
            if label == key then label = "|cffffd100" .. label .. "|r" end
            lines[#lines + 1] = { label, right = Gold.Text(row.money) }
        end
    end
    if #lines > 1 then
        lines[#lines + 1] = { L["Total"], right = Gold.Text(total) }
    end
    local change = delta(Gold.SessionChange())
    if change then
        lines[#lines + 1] = { L["This session"], right = change }
    end
    return lines
end

-- A character nobody plays any more should not sit in the list for ever.
function Gold.Forget(name)
    local t = global()
    if t then t[name] = nil end
end
