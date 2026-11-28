-- VuloForeverUI / Modules / CooldownManager / BuffPhase
--
-- The active phase in a fight. While the buff a row watches is on you, the
-- icon shows the BUFF: its own icon, a reverse swipe, the time it has left and
-- its stacks -- and once it is gone, the spell's cooldown underneath again.
--
-- HOW, WITH AURAS CLOSED IN COMBAT
--
-- Player auras throw at addon code in combat on this client, so nothing here
-- reads one. Each such icon carries a client aura container on "player"
-- (filter HELPFUL, candidate filter = the buff's spell ids), the same route
-- as the dot time on the target (AntiClip.lua). The client finds the aura and
-- makes one button over the icon; we only hand it the regions to drive.
-- Out of combat Bar.lua still reads the aura for what the button cannot say
-- (the border in the active colour, the stack glow); the button covers the
-- icon either way, so both show the same thing.
--
-- The client fixes a button's look when it makes it: any change of size,
-- shape, fonts or colours means a fresh container; the old one is let go
-- (unit "none", hidden).
local _, ns = ...
local CM = ns.CM
local UI = ns.UI

local BuffPhase = {}
CM.BuffPhase = BuffPhase

local F = AuraUtil and AuraUtil.AuraFilters or {}
local FILTER = F.Helpful or "HELPFUL"
local REBUILD_DELAY = 0.5

-- ---------------------------------------------------------------- ids --

-- The buff a spell puts on you is not always the spell's own id: a talent's
-- proc or a cooldown's effect has an id of its own. The client's cooldown
-- viewer links them (linkedSpellIDs), so every spell it knows brings its
-- buffs along. Built out of combat, by spell NAME (every rank shares it),
-- and dropped when the spellbook changes.
local linked, stale

local function addId(set, id)
    if type(id) == "number" and ns.CanRead(id) then set[id] = true end
end

local function buildLinked()
    linked = {}
    local CV = _G.C_CooldownViewer
    local cats = Enum.CooldownViewerCategory
    if not (CV and CV.GetCooldownViewerCategorySet and CV.GetCooldownViewerCooldownInfo and cats) then return end
    for _, cat in pairs(cats) do
        local ok, ids = pcall(CV.GetCooldownViewerCategorySet, cat, false)
        if ok and type(ids) == "table" then
            for _, cid in ipairs(ids) do
                local okInfo, info = pcall(CV.GetCooldownViewerCooldownInfo, cid)
                if okInfo and type(info) == "table" then
                    local set = {}
                    addId(set, info.spellID)
                    addId(set, info.overrideSpellID)
                    if type(info.linkedSpellIDs) == "table" then
                        for _, lid in ipairs(info.linkedSpellIDs) do addId(set, lid) end
                    end
                    for id in pairs(set) do
                        local name = C_Spell.GetSpellName(id)
                        if type(name) == "string" and name ~= "" then
                            linked[name] = linked[name] or {}
                            for other in pairs(set) do linked[name][other] = true end
                        end
                    end
                end
            end
        end
    end
end

-- Kept until it can be built again: in a fight the old links beat none.
function BuffPhase.Invalidate() stale = true end

local function idSet(entry, rid)
    local set = {}
    addId(set, entry.id)
    addId(set, rid)
    if (not linked or stale) and not ns:InCombat() then buildLinked(); stale = nil end
    local name = C_Spell.GetSpellName(rid or entry.id)
    local more = linked and type(name) == "string" and linked[name]
    if more then for id in pairs(more) do set[id] = true end end
    return set
end

-- The ids a list of chosen buffs answers to, linked ones included (BuffGlow).
function BuffPhase.IdsFor(ids)
    local set = {}
    if (not linked or stale) and not ns:InCombat() then buildLinked(); stale = nil end
    for id in pairs(ids) do
        addId(set, id)
        local name = C_Spell.GetSpellName(id)
        local more = linked and type(name) == "string" and linked[name]
        if more then for other in pairs(more) do set[other] = true end end
    end
    return set
end

local function setKey(set)
    local ids = {}
    for id in pairs(set) do ids[#ids + 1] = id end
    table.sort(ids)
    return table.concat(ids, ",")
end

-- ---------------------------------------------------------------- button --

-- What the client registers on the one button it makes. Fonts go on BEFORE
-- the engine is told about a string: an unstyled one makes it throw.
local function initializer(o)
    return function(button)
        button:SetSize(o.size, o.size)

        local tex = button:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints(button)
        tex:SetTexCoord(o.zoom, 1 - o.zoom, o.zoom, 1 - o.zoom)
        if o.mask then
            local m = button:CreateMaskTexture()
            m:SetAllPoints(tex)
            m:SetTexture(o.mask, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            pcall(tex.AddMaskTexture, tex, m)
        end
        pcall(button.SetIcon, button, tex)
        if o.textOnly then tex:SetAlpha(0) end

        local cd = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
        cd:SetAllPoints(button)
        cd:SetReverse(true)
        cd:SetHideCountdownNumbers(true)
        cd:SetDrawEdge(false)
        cd:SetDrawSwipe(o.swipe)
        cd:SetSwipeColor(0, 0, 0, o.swipeAlpha)
        pcall(button.SetDurationCooldown, button, cd)

        -- the texts ride above the swipe
        local top = CreateFrame("Frame", nil, button)
        top:SetAllPoints(button)
        top:SetFrameLevel((cd:GetFrameLevel() or 1) + 2)
        if o.countdown then
            local text = top:CreateFontString(nil, "OVERLAY")
            UI.FontFor("cooldownmanager", text, o.countdownSize, "OUTLINE")
            text:SetPoint("CENTER", button, "CENTER", 0, 0)
            text:SetTextColor(o.countdownColor.r, o.countdownColor.g, o.countdownColor.b)
            local f = ns.AuraDurationFormatter and ns.AuraDurationFormatter() or nil
            if not (f and pcall(button.SetDurationText, button, text, { textFormatter = f })) then
                pcall(button.SetDurationText, button, text, {})
            end
        end
        if o.count then
            local stacks = top:CreateFontString(nil, "OVERLAY")
            UI.FontFor("cooldownmanager", stacks, o.countSize, "OUTLINE")
            stacks:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 2, 2)
            stacks:SetTextColor(o.countColor.r, o.countColor.g, o.countColor.b)
            pcall(button.SetApplicationCount, button, stacks, {})
        end

        -- the border in the active colour: the phase reads at a glance
        local c = o.border
        if o.textOnly then
            -- numbers only: no ring, no edges
        elseif o.shapedBorder then
            local ring = top:CreateTexture(nil, "OVERLAY")
            ring:SetTexture(o.shapedBorder)
            ring:SetPoint("TOPLEFT", button, "TOPLEFT", -o.inset, o.inset)
            ring:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", o.inset, -o.inset)
            ring:SetVertexColor(c.r, c.g, c.b, c.a or 1)
        elseif o.borderSize > 0 then
            local edges = ns.MakeEdges(top, "OVERLAY")
            ns.LayoutEdges(edges, button, o.borderSize, c.r, c.g, c.b, c.a or 1, o.inset)
        end

        if o.glow then CM.Glow.Set({ button = button }, "main", o.glowType, o.glowColor, true) end

        pcall(button.SetMouseClickEnabled, button, false)
        pcall(button.SetMouseMotionEnabled, button, false)
    end
end

-- ---------------------------------------------------------------- life --

local build

local function release(icon)
    if icon.buffTimer then icon.buffTimer:Cancel(); icon.buffTimer = nil end
    local c = icon.buff
    if not c then return end
    pcall(c.SetUnit, c, "none")
    c:Hide()
    icon.buff, icon.buffKey = nil, nil
end

-- From CM.StyleFrame, after the icon's own look is set. entry nil = the icon
-- left the bar. `shape` is the bar's icon shape (CM.SHAPES).
function BuffPhase.Style(icon, bar, entry, size, shape)
    if not (entry and bar and entry.kind == "spell" and CM.Val(bar, entry, "activePhase")) then
        release(icon)
        return
    end
    local rid = CM.Resolve(entry)
    local set = idSet(entry, rid)
    local ac = entry.activeColor or { r = 0.2, g = 0.9, b = 0.4 }
    local o = {
        size = size,
        zoom = bar.iconZoom or 0,
        mask = shape and shape.mask or nil,
        shapedBorder = shape and shape.border or nil,
        swipe = CM.Val(bar, entry, "showSwipe") ~= false and not bar.textOnly,
        textOnly = bar.textOnly and true or false,
        swipeAlpha = CM.Val(bar, entry, "swipeAlpha") or 0.7,
        countdown = CM.Val(bar, entry, "showCountdown") ~= false and not entry.antiClip,
        countdownSize = bar.countdownSize or 12,
        countdownColor = bar.countdownColor or { r = 1, g = 1, b = 1 },
        count = CM.Val(bar, entry, "showCount") ~= false,
        countSize = bar.countSize or 11,
        countColor = bar.countColor or { r = 1, g = 1, b = 1 },
        border = { r = ac.r, g = ac.g, b = ac.b, a = (bar.borderColor and bar.borderColor.a) or 1 },
        borderSize = math.max(1, bar.borderSize or 1),
        inset = tonumber(bar.borderInset) or 0,
        glow = entry.activeGlow and true or false,
        glowType = CM.Val(bar, entry, "glowType") or "pixel",
        glowColor = ac,
    }
    local key = table.concat({ o.size, o.zoom, tostring(o.mask), tostring(o.shapedBorder),
        tostring(o.swipe), o.swipeAlpha, tostring(o.countdown), o.countdownSize,
        o.countdownColor.r, o.countdownColor.g, o.countdownColor.b, tostring(o.count), o.countSize,
        o.countColor.r, o.countColor.g, o.countColor.b, ac.r, ac.g, ac.b, o.borderSize, o.inset,
        tostring(o.glow), o.glowType, tostring(o.textOnly), setKey(set) }, ":")
    if icon.buffTimer then icon.buffTimer:Cancel(); icon.buffTimer = nil end
    if icon.buff and icon.buffKey == key then return end
    -- A container is a frame for good: dragging a slider would leave one per
    -- step. A change waits until the dragging stops.
    if icon.buff then
        icon.buffTimer = C_Timer.NewTimer(REBUILD_DELAY, function()
            icon.buffTimer = nil
            build(icon, o, set, key)
        end)
        return
    end
    build(icon, o, set, key)
end

build = function(icon, o, set, key)
    release(icon)
    local ok, c = pcall(CreateFrame, "AuraContainer", nil, icon.button, "CustomAuraContainerTemplate")
    if not ok or not c then return end
    c:SetAllPoints(icon.button)
    -- over the icon's own swipe and the dot time, under the corner texts
    c:SetFrameLevel((icon.cooldown:GetFrameLevel() or 1) + 3)
    pcall(c.EnableMouse, c, false)
    -- The group goes in BEFORE the unit: a group added after the first parse
    -- renders nothing (Auras/Bars.lua).
    local grouped = pcall(c.AddAuraGroup, c, "buff", FILTER, {
        maxFrameCount = 1,
        candidateFilters = { includeSpellIDs = set },
        initializeFrame = initializer(o),
        layout = { elementWidth = o.size, elementHeight = o.size, elementSpacing = 0, lineSpacing = 0 },
    })
    if not grouped then c:Hide(); return end
    if c.SetFlowLayoutAnchorPoint then pcall(c.SetFlowLayoutAnchorPoint, c, "TOPLEFT") end
    pcall(c.SetUnit, c, "player")
    icon.buff, icon.buffKey = c, key
end

function BuffPhase.Release(icon) release(icon) end
BuffPhase.SetKey = function(set) return setKey(set) end
