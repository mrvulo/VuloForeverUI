-- VuloForeverUI / Modules / CooldownManager / BuffGlow
--
-- Bar glows: a row lights up while one of the buffs chosen for it is on you,
-- on its own icon and on every action button that holds the spell.
--
-- HOW, WITH AURAS CLOSED IN COMBAT
--
-- Which buff is up is secret in a fight and player auras throw at addon code,
-- so nothing here asks. Every glowing place carries a client aura container on
-- "player" (filter HELPFUL, candidates = the chosen buffs plus the ids the
-- client links to them), the same route as the active phase (BuffPhase.lua).
-- The one button the client makes for a present buff carries nothing but the
-- glow; while none of the buffs is up there is no button, so no glow.
--
-- A container is a frame for good and fixes its look when it is made, so a
-- change of size, kind or colour makes a fresh one and lets the old one go
-- (unit "none", hidden). Changes wait until a slider or a colour stops moving.
--
-- The action buttons are found by the spell NAME in their slot, out of combat:
-- a stance or form page turned in a fight is followed after it.
local _, ns = ...
local CM = ns.CM

local BuffGlow = {}
CM.BuffGlow = BuffGlow

local F = AuraUtil and AuraUtil.AuraFilters or {}
local FILTER = F.Helpful or "HELPFUL"
local DELAY = 0.4

-- The buffs chosen for a row, or nil.
local function chosen(entry)
    local g = type(entry) == "table" and entry.glowBuffs
    if type(g) ~= "table" or next(g) == nil then return nil end
    return g
end

function BuffGlow.Count(entry)
    local n = 0
    for _ in pairs(chosen(entry) or {}) do n = n + 1 end
    return n
end

-- The bar's glow, or nil when it is switched off.
local function look(bar)
    local kind = bar.buffGlowType or "proc"
    if kind == "none" then return nil end
    return kind, bar.buffGlowColor or bar.glowColor or { r = 1, g = 1, b = 1 }
end

local function initializer(size, kind, color)
    return function(button)
        button:SetSize(size, size)
        CM.Glow.Set({ button = button }, "main", kind, color, true)
        pcall(button.SetMouseClickEnabled, button, false)
        pcall(button.SetMouseMotionEnabled, button, false)
    end
end

local function letGo(c)
    if not c then return end
    pcall(c.SetUnit, c, "none")
    c:Hide()
end

local function make(host, size, set, kind, color, level)
    local ok, c = pcall(CreateFrame, "AuraContainer", nil, host, "CustomAuraContainerTemplate")
    if not ok or not c then return nil end
    c:SetAllPoints(host)
    c:SetFrameLevel(level)
    pcall(c.EnableMouse, c, false)
    -- The group goes in BEFORE the unit: a group added after the first parse
    -- renders nothing (Auras/Bars.lua).
    local grouped = pcall(c.AddAuraGroup, c, "glow", FILTER, {
        maxFrameCount = 1,
        candidateFilters = { includeSpellIDs = set },
        initializeFrame = initializer(size, kind, color),
        layout = { elementWidth = size, elementHeight = size, elementSpacing = 0, lineSpacing = 0 },
    })
    if not grouped then c:Hide(); return nil end
    if c.SetFlowLayoutAnchorPoint then pcall(c.SetFlowLayoutAnchorPoint, c, "TOPLEFT") end
    pcall(c.SetUnit, c, "player")
    return c
end

local function keyOf(size, kind, color, set)
    return table.concat({ size, kind, color.r, color.g, color.b, CM.BuffPhase.SetKey(set) }, ":")
end

-- ---------------------------------------------------------------- icons --

local function releaseIcon(icon)
    if icon.bglowTimer then icon.bglowTimer:Cancel(); icon.bglowTimer = nil end
    letGo(icon.bglow)
    icon.bglow, icon.bglowKey = nil, nil
end

-- From CM.StyleFrame, after the icon's look is set. entry nil = the icon left
-- the bar.
function BuffGlow.Style(icon, bar, entry, size)
    local g = chosen(entry)
    local kind, color
    if g and bar then kind, color = look(bar) end
    if not kind then releaseIcon(icon); return end
    local set = CM.BuffPhase.IdsFor(g)
    local key = keyOf(size, kind, color, set)
    if icon.bglowTimer then icon.bglowTimer:Cancel(); icon.bglowTimer = nil end
    if icon.bglow and icon.bglowKey == key then return end
    local function build()
        icon.bglowTimer = nil
        letGo(icon.bglow)
        -- over the swipe and the buff phase, under the corner texts
        icon.bglow = make(icon.button, size, set, kind, color, (icon.cooldown:GetFrameLevel() or 1) + 4)
        icon.bglowKey = icon.bglow and key or nil
    end
    if icon.bglow then icon.bglowTimer = C_Timer.NewTimer(DELAY, build) else build() end
end

function BuffGlow.Release(icon) releaseIcon(icon) end

-- ---------------------------------------------------------------- buttons --

local PREFIXES = {
    "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton",
    "MultiBarRightButton", "MultiBarLeftButton", "MultiBar5Button",
    "MultiBar6Button", "MultiBar7Button",
}

local onButton = {}   -- [action button] = { c = container, key = key }

local function slotSpellName(button)
    local slot = button.action
    if type(slot) ~= "number" or not ns.CanRead(slot) then return nil end
    local ok, kind, id = pcall(GetActionInfo, slot)
    if not ok then return nil end
    if kind == "macro" and GetMacroSpell then
        local okm, sid = pcall(GetMacroSpell, id)
        kind, id = "spell", (okm and sid) or nil
    end
    if kind ~= "spell" or type(id) ~= "number" or not ns.CanRead(id) then return nil end
    local name = C_Spell.GetSpellName(id)
    return type(name) == "string" and name or nil
end

-- What glows for which spell name, from every bar that lends its glows to
-- the action buttons. The first bar that names a spell wins.
local function wanted()
    local out = {}
    if not CM.mod.active then return out end
    for _, key in ipairs(CM.db().barOrder or {}) do
        local bar = CM.Bar(key)
        if bar and bar.enabled and bar.buffGlowButtons and bar.visibility ~= "hidden" then
            local kind, color = look(bar)
            if kind then
                for _, e in ipairs(CM.Shown(bar)) do
                    local g = chosen(e)
                    if g and e.kind == "spell" then
                        local name = C_Spell.GetSpellName(CM.Resolve(e) or e.id)
                        if type(name) == "string" and not out[name] then
                            out[name] = { ids = g, kind = kind, color = color }
                        end
                    end
                end
            end
        end
    end
    return out
end

local function rebuildNow()
    if ns:InCombat() then return end
    local want = wanted()
    for _, prefix in ipairs(PREFIXES) do
        for i = 1, 12 do
            local b = _G[prefix .. i]
            if b then
                local name = slotSpellName(b)
                local w = name and want[name]
                local have = onButton[b]
                if w then
                    local size = math.floor((b:GetWidth() or 36) + 0.5)
                    local set = CM.BuffPhase.IdsFor(w.ids)
                    local key = keyOf(size, w.kind, w.color, set)
                    if not (have and have.key == key) then
                        if have then letGo(have.c) end
                        local c = make(b, size, set, w.kind, w.color, (b:GetFrameLevel() or 1) + 4)
                        onButton[b] = c and { c = c, key = key } or nil
                    end
                elseif have then
                    letGo(have.c)
                    onButton[b] = nil
                end
            end
        end
    end
end

-- Coalesced: a restyle per slider step, a slot event per slot on a page turn.
local pending
function BuffGlow.RebuildButtons()
    if pending then pending:Cancel() end
    pending = C_Timer.NewTimer(DELAY, function()
        pending = nil
        rebuildNow()
    end)
end

function BuffGlow.ReleaseButtons()
    if pending then pending:Cancel(); pending = nil end
    for b, have in pairs(onButton) do
        letGo(have.c)
        onButton[b] = nil
    end
end
