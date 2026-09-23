-- VuloForeverUI / Modules / Bags / Bank
--
-- The bank, which is the same window with other containers in it.
--
-- WHY THE CLIENT'S BANK FRAME IS PARKED AND NOT HIDDEN
--
-- The obvious move is BankFrame:Hide(). It is also the one move that ends the
-- visit: the frame's own OnHide closes the bank at the banker, the client
-- fires BANKFRAME_CLOSED, our window closes itself in the same frame it
-- opened, and the containers it was showing are no longer ours to touch.
--
-- So the frame stays SHOWN and is parked instead: no alpha, no mouse, and
-- moved off the screen. Nothing of its own code runs differently, the visit
-- stays open, and the player sees ours. Everything we changed is given back
-- when the module is switched off.
local _, ns = ...
local Bags = ns.Bags

local Bank = Bags.WindowFactory.New("bank", function() return Bags.BankBags() end)
Bags.Bank = Bank

local baseOpen, baseClose = Bank.Open, Bank.Close
local parked = false

local function park()
    local frame = _G.BankFrame
    -- Every time, not once: the frame is a UI panel, and the panel manager
    -- puts it back into the left slot on each visit.
    if not frame then return end
    parked = true
    -- Position first, then the rest: a protected frame refuses a move while a
    -- fight is on, and standing at a banker means there is none.
    pcall(function()
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -4000, 4000)
    end)
    pcall(frame.SetAlpha, frame, 0)
    pcall(frame.EnableMouse, frame, false)
end

function Bank.RestoreBlizzard()
    local frame = _G.BankFrame
    if not (frame and parked) then return end
    parked = false
    pcall(frame.SetAlpha, frame, 1)
    pcall(frame.EnableMouse, frame, true)
    pcall(function()
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 35, -104)
    end)
end

function Bank.Open()
    if not Bags.db().bank then return end
    park()
    baseOpen()
    -- Our bags belong beside the bank, the way every bank window in the game
    -- has always worked -- and they are remembered as ours to close again.
    if Bags.Window and not Bags.Window.IsShown() then
        Bank.openedBags = true
        Bags.Window.Open()
    end
end

function Bank.Close()
    baseClose()
    -- The bags go with it, but only if the bank is what brought them up.
    if Bank.openedBags then
        Bank.openedBags = nil
        if Bags.Window then Bags.Window.Close() end
    end
end

-- The bank's own frame likes to come back on its own -- a tab change, a
-- purchase. Parking it again is enough; it is never hidden.
function Bank.Hook()
    if Bank.hooked then return end
    local frame = _G.BankFrame
    if not frame then return end        -- try again on the next pass
    Bank.hooked = true
    frame:HookScript("OnShow", function()
        if not (Bags.mod.active and Bags.db().bank) then return end
        ns.NextFrame(function()
            park()
            if not Bank.IsShown() then Bank.Open() end
        end)
    end)
end
