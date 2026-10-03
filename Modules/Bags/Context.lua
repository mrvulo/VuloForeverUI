-- VuloForeverUI / Modules / Bags / Context
--
-- Where the player is standing, and what the bags can be used for there. At
-- a merchant an item the merchant pays nothing for is no use; at the mailbox,
-- a trade or the auction house a soulbound item cannot leave. Those go faded,
-- the same way the search fades what it did not find, so the eye lands on
-- what can actually be sold or sent.
--
-- The client says when each window opens and closes, and that is all this
-- needs: one word for the place, set by the events and cleared by them.
local _, ns = ...
local Bags = ns.Bags

local Context = {}
Bags.Context = Context

local place = nil   -- "merchant" | "mail" | "trade" | "auction" | nil

local OPEN = {
    MERCHANT_SHOW = "merchant", MAIL_SHOW = "mail",
    TRADE_SHOW = "trade", AUCTION_HOUSE_SHOW = "auction",
}
local CLOSE = {
    MERCHANT_CLOSED = "merchant", MAIL_CLOSED = "mail",
    TRADE_CLOSED = "trade", AUCTION_HOUSE_CLOSED = "auction",
}

function Context.Place() return place end

-- Bound for good: soulbound, and not to the account. A warbound item still
-- goes by mail to the player's other characters.
local function stuck(info)
    return info.isBound and Bags.Items.BindTag(info) ~= "WuE"
end

-- Is this item of no use where the player is standing?
function Context.Fades(info)
    if not place or not info or not Bags.db().contextFade then return false end
    if place == "merchant" then return info.hasNoValue and true or false end
    return stuck(info) and true or false
end

function Context.Register(mod)
    for event, where in pairs(OPEN) do
        mod:RegisterEvent(event, function()
            place = where
            Bags.Refresh()
        end)
    end
    for event, where in pairs(CLOSE) do
        mod:RegisterEvent(event, function()
            -- Only the window that set the place may clear it: closing a
            -- mailbox that was left behind for a merchant keeps the merchant.
            if place == where then
                place = nil
                Bags.Refresh()
            end
        end)
    end
end
