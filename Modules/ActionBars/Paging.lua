-- VuloForeverUI / Modules / ActionBars / Paging
--
-- "Keep the main bar on its page in every form."
--
-- Cat, bear, stealth, the warrior stances and Shadowform all swap action bar 1
-- to a page of their own. The way to stop that, on every other client, is an
-- ATTRIBUTE DRIVER per button: the client writes the parent bar's actionpage,
-- and a button's own actionpage attribute is consulted first, so pinning it
-- per button pins what you see and what the key fires together.
--
-- THE CATCH ON THIS CLIENT
--
-- Attribute drivers are part of the secure snippet machinery, and this build
-- is missing `loadstring_untainted`, which that machinery compiles with. So
-- the call may simply throw. It is therefore PROBED once, under pcall, and the
-- answer decides whether the setting is offered at all -- rather than a switch
-- that looks like it works and quietly does nothing.
local _, ns = ...
local L = ns.L
local AB = ns.AB

local Paging = {}
AB.Paging = Paging

-- Manual page switching stays alive; only the client's own form swaps stop
-- moving the bar.
local PIN = "[bar:2]2;[bar:3]3;[bar:4]4;[bar:5]5;[bar:6]6;1"

local applied = false

-- nil not asked yet, true it works, false this client will not have it.
Paging.supported = nil

local function buttons()
    local out = {}
    for i = 1, 12 do
        local b = _G["ActionButton" .. i]
        if b then out[#out + 1] = b end
    end
    return out
end

-- The probe. One button, one driver, put straight back -- and whatever it
-- answers is remembered for the session.
function Paging.Probe()
    if Paging.supported ~= nil then return Paging.supported end
    Paging.supported = false
    if InCombatLockdown() then
        Paging.supported = nil     -- ask again when it is safe to ask
        return false
    end
    local register = _G.RegisterAttributeDriver
    local unregister = _G.UnregisterAttributeDriver
    if type(register) ~= "function" or type(unregister) ~= "function" then
        return false
    end
    local b = _G.ActionButton1
    if not b then
        Paging.supported = nil
        return false
    end
    local ok = pcall(register, b, "actionpage", PIN)
    pcall(unregister, b, "actionpage")
    Paging.supported = ok and true or false
    return Paging.supported
end

function Paging.Apply()
    local db = AB.db()
    local want = db.keepPage and true or false

    if want and not Paging.Probe() then
        -- Said once, and the setting turns itself off: a switch that cannot do
        -- what it says is worse than no switch.
        if not Paging.warned then
            Paging.warned = true
            ns:Print(L["This client cannot pin the action bar page: the machinery behind it does not load here."])
        end
        db.keepPage = false
        return
    end

    if want == applied then return end
    if InCombatLockdown() then return end     -- the next pass out of combat
    applied = want

    for _, b in ipairs(buttons()) do
        if want then
            pcall(_G.RegisterAttributeDriver, b, "actionpage", PIN)
        else
            pcall(_G.UnregisterAttributeDriver, b, "actionpage")
        end
    end
end

function Paging.Release()
    if not applied then return end
    if InCombatLockdown() then return end
    applied = false
    for _, b in ipairs(buttons()) do
        pcall(_G.UnregisterAttributeDriver, b, "actionpage")
    end
end
