-- VuloForeverUI / Modules / Bags / Tutorials
--
-- The client's bag tutorials, while our window stands in for its bags.
--
-- A reagent bag in the bags starts one: "You received a reagent bag! Open
-- your bag." Its first step ends when one of the CLIENT's bag frames opens
-- (EventRegistry "ContainerFrame.OpenBag"). With the takeover on, those frames
-- never become visible, so that step never ends and its box stays on screen
-- for good, with nothing to click it away.
--
-- So that one box is made invisible while the takeover is on. Nothing of the
-- tutorial is called or written -- HelpTip's frame pool is shared with tips
-- the action bars show from secure code, and a call of ours into it would
-- carry our taint there. Its frames are only READ, and the one box gets alpha
-- zero. A pooled frame reused later for another tip gets its alpha back.
local _, ns = ...
local Bags = ns.Bags

local Tutorials = {}
Bags.Tutorials = Tutorials

local muted = {}   -- frame -> true while we hold it at alpha zero

-- The first step's text of every bag tutorial this client has.
local function stuckText(text)
    return type(text) == "string" and text ~= ""
        and (text == _G.TUTORIAL_REAGENT_BAG_STEP_1)
end

local function takeoverOn()
    return Bags.mod and Bags.mod.active and Bags.db().replaceBlizzard and true or false
end

function Tutorials.Update()
    local pool = HelpTip and HelpTip.framePool
    if not (pool and pool.EnumerateActive) then return end
    local on = takeoverOn()
    local seen = {}
    for frame in pool:EnumerateActive() do
        seen[frame] = true
        local info = frame.info
        if on and info and stuckText(info.text) then
            if not muted[frame] then
                muted[frame] = true
                frame:SetAlpha(0)
            end
        elseif muted[frame] then
            muted[frame] = nil
            frame:SetAlpha(1)
        end
    end
    -- released since: back to full alpha for whatever uses it next
    for frame in pairs(muted) do
        if not seen[frame] then
            muted[frame] = nil
            frame:SetAlpha(1)
        end
    end
end

local hooked = false

function Tutorials.Hook()
    if hooked or not (HelpTip and type(HelpTip.Show) == "function") then return end
    hooked = true
    -- After the client has shown a tip, never inside it.
    hooksecurefunc(HelpTip, "Show", function() ns.NextFrame(Tutorials.Update) end)
end
