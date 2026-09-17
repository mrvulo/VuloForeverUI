-- VuloForeverUI / UI / Tooltip: the one place that opens, fills and closes GameTooltip.
--
-- WHY THIS EXISTS
-- There were 57 hand-written GameTooltip:SetOwner sites across 26 files, each
-- repeating the same four steps and each choosing its own anchor: 24 RIGHT,
-- 17 TOP, 9 LEFT, 5 NONE, 2 BOTTOM. Three things followed from that:
--
--   * OnLeave was the caller's job to remember. Forget it once and a tooltip
--     stays on screen with nothing under the mouse.
--   * Half the sites guarded with `if GameTooltip then`, half did not. Neither
--     half was wrong -- there was simply no rule.
--   * Nothing stopped a tooltip from running off the screen edge. A button on
--     the right with ANCHOR_RIGHT pushes its tooltip out of view, and the only
--     fix available to a single site was to hard-code the opposite anchor and
--     hope the window never moves.
--
-- WHAT THIS ADDS, beyond removing the repetition: the tooltip is MEASURED after
-- it is filled, and if it left the screen it is re-anchored to the other side
-- and filled again. That is why ShowTooltip takes the content instead of
-- returning the tooltip -- it has to be able to build it twice.
--
-- THE FOUR ENTRY POINTS
--
--   UI:ShowTooltip(owner, spec)   open, fill, show, keep on screen
--   UI:HideTooltip()              close, guarded
--   UI:AttachTooltip(frame, spec) the two scripts at once, for hover-only frames
--   UI:OpenTooltip(owner, anchor) SetOwner alone, for content a table cannot describe
--
-- SPEC -- a string is a title and nothing else. Everything else is a table:
--
--   { title   = "Sort bags",          -- first line
--     anchor  = "ANCHOR_TOP",         -- default ANCHOR_RIGHT
--     accent  = true,                 -- title in the theme color instead of white
--     gold    = true,                 -- title in the item-name gold 1, 0.82, 0
--     color   = { 1, 0.82, 0.25 },    -- ... or any other title color
--     wrap    = true,                 -- let the title wrap instead of widening
--     lines   = { "Right-click to toggle sort order.",   -- plain string: grey
--                 { "Watch out", 1, 0.35, 0.35 },        -- text with a color
--                 { "Long note", nil, nil, nil, true },  -- ... and wrapping
--                 { "Frostbolt", right = "12.3k (34%)" } } -- two columns, right side white
--   }
--
-- A spec may also be a FUNCTION, called with the owner frame and returning any
-- of the above, or nil for "no tooltip here right now". AttachTooltip runs it on
-- every hover, which is what a label like "Collapse"/"Expand" needs.
local _, ns = ...
ns.UI = ns.UI or {}
local UI = ns.UI

local GREY_R, GREY_G, GREY_B = 0.7, 0.7, 0.7
local DEFAULT_ANCHOR = "ANCHOR_RIGHT"

-- The two anchors that place the tooltip beside the owner, and so the two that
-- can leave the screen sideways. TOP and BOTTOM are left alone: the client
-- already keeps those inside the vertical edges.
local FLIP = { ANCHOR_RIGHT = "ANCHOR_LEFT", ANCHOR_LEFT = "ANCHOR_RIGHT" }

local function accentColor()
    local c = ns.COLORS and ns.COLORS.accent
    return (c and c.r) or 0.608, (c and c.g) or 0.424, (c and c.b) or 1.000
end

local function normalize(spec, owner)
    if type(spec) == "function" then spec = spec(owner) end
    if type(spec) == "string" then return { title = spec } end
    if type(spec) == "table" then return spec end
    return nil
end

local function titleColor(spec)
    if spec.accent then return accentColor() end
    if spec.gold then return 1, 0.82, 0 end
    local c = spec.color
    if c then return c[1] or 1, c[2] or 1, c[3] or 1 end
    return 1, 1, 1
end

local function fill(tip, spec)
    local title = spec.title
    if title and title ~= "" then
        local r, g, b = titleColor(spec)
        tip:SetText(title, r, g, b, 1, spec.wrap and true or false)
    end
    local lines = spec.lines
    if not lines then return end
    for i = 1, #lines do
        local line = lines[i]
        if type(line) == "string" then
            tip:AddLine(line, GREY_R, GREY_G, GREY_B)
        elseif type(line) == "table" then
            -- {1} text, {2..4} color (nil means grey), {5} wrap; a `right`
            -- field makes it a two-column line with a white right side
            if line.right then
                tip:AddDoubleLine(line[1], line.right,
                                  line[2] or GREY_R, line[3] or GREY_G, line[4] or GREY_B,
                                  1, 1, 1)
            else
                tip:AddLine(line[1], line[2] or GREY_R, line[3] or GREY_G, line[4] or GREY_B,
                            line[5] and true or false)
            end
        end
    end
end

-- Both sides converted to screen pixels first: SetOwner reparents the tooltip to
-- the owner, so the two frames need not share a scale and raw coordinates from
-- one cannot be compared against the other.
--
-- The second condition is what keeps this from making things worse. A tooltip
-- wider than the free space on BOTH sides overflows either way, and flipping it
-- would only move the cut-off part to the other edge. So the owner must actually
-- sit on the crowded half before the flip is worth doing.
local function shouldFlip(tip, owner, anchor)
    if not (UIParent and owner.GetCenter) then return false end
    local ts = tip.GetEffectiveScale and tip:GetEffectiveScale() or 1
    local ws = owner.GetEffectiveScale and owner:GetEffectiveScale() or 1
    local us = UIParent:GetEffectiveScale() or 1

    local ownerX = owner:GetCenter()
    local left, right = UIParent:GetLeft(), UIParent:GetRight()
    if not (ownerX and left and right) then return false end
    local middle = ((left + right) / 2) * us
    ownerX = ownerX * ws

    if anchor == "ANCHOR_RIGHT" then
        local edge = tip:GetRight()
        return (edge ~= nil) and (edge * ts) > (right * us) and ownerX > middle
    elseif anchor == "ANCHOR_LEFT" then
        local edge = tip:GetLeft()
        return (edge ~= nil) and (edge * ts) < (left * us) and ownerX < middle
    end
    return false
end

-- SetOwner, guarded, with no content. For tooltips whose body is built by a
-- loop or by an item link -- anything the spec table cannot express. Note that
-- these do NOT get the off-screen correction: it works by rebuilding the
-- tooltip on the other side, and only the caller knows how to do that here.
function UI:OpenTooltip(owner, anchor)
    if not (GameTooltip and owner) then return nil end
    GameTooltip:SetOwner(owner, anchor or DEFAULT_ANCHOR)
    return GameTooltip
end

function UI:ShowTooltip(owner, spec)
    if not (GameTooltip and owner) then return nil end
    spec = normalize(spec, owner)
    if not spec then return nil end

    local anchor = spec.anchor or DEFAULT_ANCHOR
    GameTooltip:SetOwner(owner, anchor)
    fill(GameTooltip, spec)
    GameTooltip:Show()

    local other = FLIP[anchor]
    if other and shouldFlip(GameTooltip, owner, anchor) then
        GameTooltip:SetOwner(owner, other)
        fill(GameTooltip, spec)
        GameTooltip:Show()
    end
    return GameTooltip
end

function UI:HideTooltip()
    if GameTooltip then GameTooltip:Hide() end
end

-- For a frame whose hover does nothing but show a tooltip. Anything that also
-- changes a color on hover keeps its own scripts and calls ShowTooltip from
-- inside them -- that is the majority, and wrapping those would hide the color
-- change behind an option table for no gain.
function UI:AttachTooltip(frame, spec)
    if not frame then return frame end
    frame._vcTooltipSpec = spec
    frame:SetScript("OnEnter", function(self)
        UI:ShowTooltip(self, self._vcTooltipSpec)
    end)
    frame:SetScript("OnLeave", function()
        UI:HideTooltip()
    end)
    return frame
end
