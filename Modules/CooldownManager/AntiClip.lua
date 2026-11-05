-- VuloForeverUI / Modules / CooldownManager / AntiClip
--
-- A damage-over-time row can show the dot's remaining time on the target, on
-- its own icon, and turn that number green once a recast no longer cuts the
-- running one short. Vanilla dots carry no time over on a refresh: cast again
-- too early and the ticks that were left are gone.
--
-- HOW, WITH AURAS CLOSED IN COMBAT
--
-- The target's auras are secret in combat and C_UnitAuras throws at addon
-- code, so nothing here reads one -- the same route as the dot bars
-- (ResourceBars/Dots.lua). Each such icon carries a client aura container:
-- filter HARMFUL|PLAYER on "target", candidate filter = every spell id of the
-- dot's name. The client finds the aura, makes one button over the icon and
-- drives the font string we registered on it as its duration text. The colour
-- is a curve over the remaining seconds, evaluated by the client: green up to
-- the threshold, the bar's countdown colour above it.
--
-- The threshold is the spell's own cast time (read when the icon is styled,
-- out of combat) plus the row's lead, which stands in for the global cooldown
-- and your reaction -- the moment you would really land the recast.
--
-- The client fixes a button's look when it makes it, so any change of size,
-- font, colours or threshold means a fresh container; the old one is let go
-- (unit "none", hidden).
local _, ns = ...
local CM = ns.CM
local UI = ns.UI

local AntiClip = {}
CM.AntiClip = AntiClip

local F = AuraUtil and AuraUtil.AuraFilters or {}
local FILTER = table.concat({ F.Harmful or "HARMFUL", F.Player or "PLAYER" }, "|")

AntiClip.DEFAULT_LEAD  = 1
AntiClip.DEFAULT_COLOR = { r = 0.3, g = 1, b = 0.3 }

local live = setmetatable({}, { __mode = "k" })   -- icon -> true while it has a container on "target"
local eventsOn
local build
local REBUILD_DELAY = 0.5

-- Every spell id of the row's dot, ranks and all: the aura filter matches by
-- id, and the aura on the target is the rank that was cast. The dot table of
-- the resource bars already lists them; a spell outside it is matched by its
-- own id only.
local function idSet(entry, rid)
    local set = {}
    local dots = ns.RB and ns.RB.DOTS
    if type(dots) == "table" then
        for _, class in pairs(dots) do
            for _, dot in ipairs(class) do
                for _, x in ipairs(dot.ids) do
                    if x == entry.id or x == rid then
                        for _, y in ipairs(dot.ids) do set[y] = true end
                        break
                    end
                end
            end
        end
    end
    set[entry.id] = true
    if type(rid) == "number" then set[rid] = true end
    return set
end

local function setKey(set)
    local ids = {}
    for id in pairs(set) do ids[#ids + 1] = id end
    table.sort(ids)
    return table.concat(ids, ",")
end

-- Seconds; 0 for an instant or when the client will not say.
local function castSeconds(rid)
    if type(rid) ~= "number" or not (C_Spell and C_Spell.GetSpellInfo) then return 0 end
    local ok, info = pcall(C_Spell.GetSpellInfo, rid)
    if not ok or type(info) ~= "table" then return 0 end
    local ms = info.castTime
    if not ns.CanRead(ms) or type(ms) ~= "number" or ms <= 0 then return 0 end
    return ms / 1000
end

local function makeCurve(threshold, green, normal)
    if not (C_CurveUtil and C_CurveUtil.CreateColorCurve and CreateColor) then return nil end
    local ok, curve = pcall(C_CurveUtil.CreateColorCurve)
    if not ok or not curve then return nil end
    local g = CreateColor(green.r, green.g, green.b, 1)
    local n = CreateColor(normal.r, normal.g, normal.b, 1)
    curve:AddPoint(0, g)
    curve:AddPoint(threshold, g)
    curve:AddPoint(threshold + 0.01, n)
    curve:AddPoint(86400, n)
    return curve
end

-- What the client registers on the one button it makes: our font string as
-- the duration text, coloured by the curve. The button takes no mouse, so the
-- icon's own tooltip stays reachable.
local function initializer(size, fontSize, curve)
    return function(button)
        button:SetSize(size, size)
        local text = button:CreateFontString(nil, "OVERLAY")
        UI.FontFor("cooldownmanager", text, fontSize, "OUTLINE")
        text:SetPoint("CENTER", button, "CENTER", 0, 0)
        local opts = { textFormatter = ns.AuraDurationFormatter and ns.AuraDurationFormatter() or nil }
        local prop = Enum.DurationTextBindingProperty and Enum.DurationTextBindingProperty.RemainingDuration
        if curve and prop then opts.textColor = { curve = curve, property = prop } end
        if not pcall(button.SetDurationText, button, text, opts) then
            opts.textFormatter = nil
            pcall(button.SetDurationText, button, text, opts)
        end
        pcall(button.SetMouseClickEnabled, button, false)
        pcall(button.SetMouseMotionEnabled, button, false)
    end
end

local function onTarget()
    for icon in pairs(live) do
        local c = icon.clip
        if c and icon.button:IsShown() then pcall(c.UpdateAllAuras, c) end
    end
end

local function release(icon)
    if icon.clipTimer then icon.clipTimer:Cancel(); icon.clipTimer = nil end
    local c = icon.clip
    if not c then return end
    pcall(c.SetUnit, c, "none")
    c:Hide()
    icon.clip, icon.clipKey = nil, nil
    live[icon] = nil
end

-- From CM.StyleFrame, after the icon's fonts are set. entry nil = the icon
-- left the bar.
function AntiClip.Style(icon, bar, entry, size)
    if not (entry and entry.antiClip and entry.kind == "spell" and bar) then
        release(icon)
        return
    end
    -- The dot's time takes the middle of the icon; the cooldown number would
    -- sit on top of it, so it gives way (the swipe still shows the cooldown).
    icon.countdown:SetShown(false)

    local rid = CM.Resolve(entry)
    local set = idSet(entry, rid)
    local lead = tonumber(entry.antiClipLead) or AntiClip.DEFAULT_LEAD
    local threshold = castSeconds(rid) + lead
    local green = entry.antiClipColor or AntiClip.DEFAULT_COLOR
    local normal = bar.countdownColor or { r = 1, g = 1, b = 1 }
    local fontSize = bar.countdownSize or 12
    local key = table.concat({ size, fontSize, string.format("%.2f", threshold),
        green.r, green.g, green.b, normal.r, normal.g, normal.b, setKey(set) }, ":")
    if icon.clipTimer then icon.clipTimer:Cancel(); icon.clipTimer = nil end
    if icon.clip and icon.clipKey == key then return end
    -- A container is a frame for good: dragging the lead slider or a colour
    -- would leave one per step. A change waits until the dragging stops.
    if icon.clip then
        icon.clipTimer = C_Timer.NewTimer(REBUILD_DELAY, function()
            icon.clipTimer = nil
            build(icon, size, fontSize, threshold, green, normal, set, key)
        end)
        return
    end
    build(icon, size, fontSize, threshold, green, normal, set, key)
end

build = function(icon, size, fontSize, threshold, green, normal, set, key)
    release(icon)
    local ok, c = pcall(CreateFrame, "AuraContainer", nil, icon.button, "CustomAuraContainerTemplate")
    if not ok or not c then return end
    c:SetAllPoints(icon.button)
    c:SetFrameLevel((icon.cooldown:GetFrameLevel() or 1) + 2)
    -- The icon's tooltip lives on the button underneath.
    pcall(c.EnableMouse, c, false)
    -- The group goes in BEFORE the unit: a group added after the first parse
    -- renders nothing (Auras/Bars.lua).
    local grouped = pcall(c.AddAuraGroup, c, "clip", FILTER, {
        maxFrameCount = 1,
        candidateFilters = { includeSpellIDs = set },
        initializeFrame = initializer(size, fontSize, makeCurve(threshold, green, normal)),
        layout = { elementWidth = size, elementHeight = size, elementSpacing = 0, lineSpacing = 0 },
    })
    if not grouped then c:Hide(); return end
    if c.SetFlowLayoutAnchorPoint then pcall(c.SetFlowLayoutAnchorPoint, c, "TOPLEFT") end
    pcall(c.SetUnit, c, "target")
    icon.clip, icon.clipKey = c, key
    live[icon] = true

    if not eventsOn then
        eventsOn = true
        -- SetUnit("target") again is a no-op for the same token; the client's
        -- own target frame asks its container to look again, and so do we.
        ns:RegisterEvent("PLAYER_TARGET_CHANGED", onTarget)
    end
end

function AntiClip.Release(icon) release(icon) end
