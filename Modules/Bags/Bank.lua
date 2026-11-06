-- VuloForeverUI / Modules / Bags / Bank
--
-- The bank, which is the same window with other containers in it.
--
-- WHY THE CLIENT'S BANK FRAME IS RETIRED, NOT PARKED
--
-- The first take left the client's BankFrame shown and moved it off the
-- screen, so its own OnShow went on running at every visit. On Forever that
-- OnShow picks a tab, and picking a tab buys the free first bank tab
-- (BankFrameMixin:PurchaseFirstSlot) and writes BankPanel.bankType. Once that
-- ran in our taint the purchase was blocked (PurchaseBankTab forbidden), and
-- every item click for the rest of the session read the written bank type
-- (ContainerFrameItemButton_OnClick -> BankFrame:GetActiveBankType) and lost
-- its UseContainerItem to the block as well.
--
-- So the frame is retired instead: its OnShow, OnHide and OnEvent are taken
-- away and it hangs from a hidden frame of ours. The client still shows it as
-- a panel at every visit, but nothing of its code runs and it is never
-- visible; GetActiveBankType sees a panel that was never set up and answers
-- nil without reading anything we could have written.
--
-- Two things come with that. Its OnHide was what ended the visit, so closing
-- our bank window now ends it (C_Bank.CloseBankFrame). And the free first tab
-- is no longer bought behind the player's back: the buy button in our window
-- does it, through the client's own purchase dialog.
--
-- Handing the scripts back from addon code would make them ours, and the
-- next OnShow would run tainted -- the very fault this fixes. Switching the
-- bank off therefore asks for a /reload; until then our window keeps serving
-- the bank, so a banker never shows nothing.
local _, ns = ...
local Bags = ns.Bags
local L = ns.L

local Bank = Bags.WindowFactory.New("bank", function() return Bags.BankBags() end)
Bags.Bank = Bank

local baseOpen, baseClose = Bank.Open, Bank.Close
local retired, pending = false, false
local visiting = false
local holder

ns.OnLocaleReady(function()
    StaticPopupDialogs["VFUI_BANK_RELOAD"] = {
        text = L["Blizzard's frames come back after a reload. Reload the UI now?"],
        button1 = L["Reload now"],
        button2 = L["Later"],
        OnAccept = function() ReloadUI() end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
end)

local function retire()
    if retired then return end
    local frame = _G.BankFrame
    if not frame then return end
    -- At the banker the frame is on screen, and taking it away now would run
    -- its children's OnHide in our taint. It waits for the visit to end.
    if frame:IsShown() then pending = true; return end
    holder = holder or CreateFrame("Frame")
    holder:Hide()
    if not pcall(frame.SetParent, frame, holder) then return end
    frame:SetScript("OnShow", nil)
    frame:SetScript("OnHide", nil)
    frame:SetScript("OnEvent", nil)
    retired, pending = true, false
end

-- Whether our window is the bank right now: switched on, or switched off
-- since the last reload with the client's frame still retired.
function Bank.Serves()
    return Bags.db().bank or retired
end

-- Module off or bank takeover off. The client's frame can only come back
-- clean through a reload.
function Bank.RestoreBlizzard()
    pending = false
    -- once: every later option change runs through here too
    if retired and not Bank.askedReload then
        Bank.askedReload = true
        StaticPopup_Show("VFUI_BANK_RELOAD")
    end
end

function Bank.Open()
    if not Bank.Serves() then return end
    -- the moment the client's bank reads the bag list (Core.lua, StashBlizzard)
    Bags.CheckTaint("bank open")
    visiting = true
    baseOpen()
    Bank.Hook()
    -- Our bags belong beside the bank, the way every bank window in the game
    -- has always worked -- and they are remembered as ours to close again.
    if Bags.Window and not Bags.Window.IsShown() then
        Bank.openedBags = true
        Bags.Window.Open()
    end
end

function Bank.Close()
    -- before the hide: the hide below must not end a visit that has ended
    visiting = false
    baseClose()
    -- The bags go with it, but only if the bank is what brought them up.
    if Bank.openedBags then
        Bank.openedBags = nil
        if Bags.Window then Bags.Window.Close() end
    end
    if pending and Bags.mod.active and Bags.db().bank then retire() end
end

-- From the module's enable, the loading screen and the bank switch: retire
-- the client's frame, and let a hide of our window end the visit.
function Bank.Hook()
    if Bags.mod.active and Bags.db().bank then retire() end
    if Bank.hooked or not Bank.frame then return end
    Bank.hooked = true
    Bank.frame:HookScript("OnHide", function()
        -- still shown = only a parent went (the interface hidden), not a close
        if not (visiting and retired) or Bank.frame:IsShown() then return end
        visiting = false
        if C_Bank and C_Bank.CloseBankFrame then C_Bank.CloseBankFrame() end
    end)
end
