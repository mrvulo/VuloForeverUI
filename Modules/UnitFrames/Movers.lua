-- VuloForeverUI / Modules / UnitFrames / Movers
--
-- Boxes in our edit mode for Blizzard's own player, target, focus and
-- target-of-target frames. The Standard and Classic styles wear those frames
-- (Classic only re-dresses them, it never moves them); Modern brings frames of
-- its own, which have their own boxes (Engine.lua), and these stand down.
--
-- Player, target and focus are Edit Mode systems and are moved the careful way
-- (Core/EditModeMover.lua). Target-of-target is not: it is a child of the
-- target frame that Blizzard anchors once, in its template; the same helper
-- moves it with plain anchors and puts Blizzard's anchor back on a reset.
-- The places are saved in the profile, per frame.
local _, ns = ...
local L = ns.L
local UF = ns.UF

local FRAMES = {
    { key = "player", label = "Player", frame = function() return _G.PlayerFrame end },
    { key = "target", label = "Target", frame = function() return _G.TargetFrame end },
    { key = "focus",  label = "Focus",  frame = function() return _G.FocusFrame end },
    { key = "tot",    label = "Target of Target",
      frame = function() return _G.TargetFrame and _G.TargetFrame.totFrame end },
}

local attached = {}

local function wearsBlizzardFrames(mod)
    return mod.active and mod.db.style ~= "modern"
end

-- After every style change and on enable/disable: boxes on while Blizzard's
-- frames are the ones on screen, frames handed back to their places when not.
function UF.ApplyBlizzMovers(mod)
    local on = wearsBlizzardFrames(mod)
    for _, d in ipairs(FRAMES) do
        local I = attached[d.key]
        if not I and on then
            local frame = d.frame()
            if frame then
                I = ns:AttachEditModeMover(frame, {
                    key      = "blizz_" .. d.key,
                    label    = L[d.label],
                    module   = "unitframes",
                    isActive = function() return wearsBlizzardFrames(mod) end,
                    getPos   = function()
                        local all = mod.db.blizzPos
                        return type(all) == "table" and all[d.key] or nil
                    end,
                    setPos   = function(p)
                        if type(mod.db.blizzPos) ~= "table" then mod.db.blizzPos = {} end
                        mod.db.blizzPos[d.key] = p
                    end,
                })
                attached[d.key] = I
            end
        end
        if I then
            if on then I.Apply() else I.Release() end
        end
    end
end
