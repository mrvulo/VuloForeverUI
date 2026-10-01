-- VuloForeverUI / Modules / QoL / Trainer
--
-- A "Train all" button on the trainer window, left of the client's own Train
-- button.
--
-- ONE AT A TIME
--
-- Every purchase changes the list: the bought line turns "used", may drop out
-- under the type filter, and the next line's index moves. So the run buys one
-- service, waits for the server to answer with TRAINER_UPDATE, and scans the
-- list again. A purchase the server refuses without an update ends the run on
-- a timeout rather than asking for the same line forever.
--
-- WHAT IS LEFT OUT
--
-- A profession itself, because learning one takes a profession slot and that
-- is a decision; and the pet trainer, whose costs are training points, not gold.
local _, ns = ...
local L = ns.L

local QoL = ns.QoL
local Trainer = QoL.RegisterPart("trainer", {})
QoL.Trainer = Trainer

local function db() return QoL.db().world end

local button
local buying, awaiting = false, false
local timeout

local function isPetTrainer()
    return Enum.TrainerType and C_Trainer.GetTrainerType() == Enum.TrainerType.Pet
end

-- The first line the run would buy, how many it would buy, and what that costs.
-- Counted in list order against the gold you have, the way the run spends it.
local function learnable()
    if isPetTrainer() then return nil, 0, 0 end
    local money = GetMoney()
    local first, count, total = nil, 0, 0
    for i = 1, GetNumTrainerServices() do
        local _, serviceType = GetTrainerServiceInfo(i)
        if serviceType == "available" then
            local cost, isProfession = GetTrainerServiceCost(i)
            cost = cost or 0
            if not isProfession and total + cost <= money then
                first = first or i
                count = count + 1
                total = total + cost
            end
        end
    end
    return first, count, total
end

local function refresh()
    if not button then return end
    if not db().trainAll or isPetTrainer() then button:Hide(); return end
    local _, count = learnable()
    button:SetText(count > 0 and L["Train all (%d)"]:format(count) or L["Train all"])
    button:SetEnabled(count > 0 and not buying)
    button:Show()
end

local function stop()
    buying, awaiting = false, false
    if timeout then timeout:Cancel(); timeout = nil end
    refresh()
end

local function buyNext()
    if not buying then return end
    if not (ClassTrainerFrame and ClassTrainerFrame:IsShown()) then stop(); return end
    local index = learnable()
    if not index then stop(); return end
    if timeout then timeout:Cancel() end
    timeout = C_Timer.NewTimer(2, stop)
    awaiting = true
    BuyTrainerService(index)
end

local function onTrainerUpdate()
    -- One purchase can raise more than one update; only the first one moves
    -- the run on, or the next line would be bought twice.
    if buying and awaiting then
        awaiting = false
        C_Timer.After(0.1, buyNext)
    end
    refresh()
end

local function showTooltip(self)
    local _, count, total = learnable()
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(L["Train all"])
    GameTooltip:AddLine(L["Learns everything this trainer offers that you can afford, one after the other. A profession itself is left to you."], 1, 1, 1, true)
    if count > 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine(L["Cost"], C_CurrencyInfo.GetCoinTextureString(total), 1, 0.82, 0, 1, 1, 1)
    end
    GameTooltip:Show()
end

local function create()
    if button or not ClassTrainerFrame then return end
    local anchor = ClassTrainerFrame.TrainButton
    if not anchor then return end
    button = CreateFrame("Button", nil, ClassTrainerFrame, "MagicButtonTemplate")
    button:SetSize(120, anchor:GetHeight())
    button:SetPoint("RIGHT", anchor, "LEFT", 0, 0)
    button:SetMotionScriptsWhileDisabled(true)
    button:SetScript("OnClick", function()
        if buying then return end
        buying = true
        refresh()
        buyNext()
    end)
    button:SetScript("OnEnter", showTooltip)
    button:SetScript("OnLeave", GameTooltip_Hide)
    ClassTrainerFrame:HookScript("OnShow", refresh)
    ClassTrainerFrame:HookScript("OnHide", stop)
end

-- The trainer window is loaded on demand by the same event, so the button is
-- built a frame later, once the window is sure to exist.
local function onTrainerShow()
    C_Timer.After(0, function()
        create()
        refresh()
    end)
end

function Trainer.Apply()
    local on = db().trainAll and true or false
    QoL.SyncEvent(on, "TRAINER_SHOW",   onTrainerShow)
    QoL.SyncEvent(on, "TRAINER_UPDATE", onTrainerUpdate)
    if not on then stop() end
    refresh()
end

function Trainer.Disable()
    QoL.SyncEvent(false, "TRAINER_SHOW",   onTrainerShow)
    QoL.SyncEvent(false, "TRAINER_UPDATE", onTrainerUpdate)
    stop()
    if button then button:Hide() end
end
