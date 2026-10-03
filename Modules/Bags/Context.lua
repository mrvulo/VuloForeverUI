-- VuloForeverUI / Modules / Bags / Context
--
-- Where the player is standing, and what the bags can be used for there. At
-- a merchant an item the merchant pays nothing for is no use; at the mailbox,
-- a trade or the auction house a soulbound item cannot leave. Those go faded,
-- the same way the search fades what it did not find, so the eye lands on
-- what can actually be sold or sent.
--
-- The place is ASKED of the client, never remembered. An earlier version set
-- it from the open events and cleared it from the close events, and a close
-- event that never came left the bags faded long after the mailbox was gone.
-- The events below only say "look again".
local _, ns = ...
local Bags = ns.Bags

local Context = {}
Bags.Context = Context

local T = Enum.PlayerInteractionType or {}
local PLACES = {
    { T.Merchant, "merchant" },
    { T.MailInfo, "mail" },
    { T.TradePartner, "trade" },
    { T.Auctioneer, "auction" },
}

-- Asked once per frame: the layout asks per slot, the answer cannot change
-- between two slots of one draw.
local askedAt, place = -1, nil

function Context.Place()
    local now = GetTime()
    if now ~= askedAt then
        askedAt, place = now, nil
        local ask = C_PlayerInteractionManager.IsInteractingWithNpcOfType
        for _, p in ipairs(PLACES) do
            if p[1] and ask(p[1]) then place = p[2]; break end
        end
    end
    return place
end

-- Bound for good: soulbound, and not to the account. A warbound item still
-- goes by mail to the player's other characters.
local function stuck(info)
    return info.isBound and Bags.Items.BindTag(info) ~= "WuE"
end

-- Is this item of no use where the player is standing?
function Context.Fades(info)
    if not info or not Bags.db().contextFade then return false end
    local where = Context.Place()
    if not where then return false end
    if where == "merchant" then return info.hasNoValue and true or false end
    return stuck(info) and true or false
end

local EVENTS = {
    "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE",
    "MERCHANT_SHOW", "MERCHANT_CLOSED", "MAIL_SHOW", "MAIL_CLOSED",
    "TRADE_SHOW", "TRADE_CLOSED", "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED",
}

function Context.Register(mod)
    for _, event in ipairs(EVENTS) do
        mod:RegisterEvent(event, function()
            askedAt = -1
            Bags.Refresh()
        end)
    end
end
