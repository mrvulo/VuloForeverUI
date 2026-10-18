-- VuloForeverUI / Modules / ResourceBars / Dots
--
-- Your damage-over-time spells on the target as bars: one row per dot you
-- know, grey while it is not on the target, filled with its remaining time
-- while it is -- and beside it how much stronger or weaker a recast would be
-- right now than the one that is ticking.
--
-- HOW, WITH AURAS CLOSED IN COMBAT
--
-- Target auras are secret in combat and C_UnitAuras throws at addon code, so
-- nothing here reads one. Every row carries its own client aura container
-- with one group: filter HARMFUL|PLAYER on "target", candidate filter
-- includeSpellIDs = every id of that spell (DotData.lua). The client finds the
-- aura, creates the button, and drives what we registered on it: the duration
-- BAR (SetDurationBar), the time text, the coloured icon. Under it sits our
-- own grey row -- the empty state, seen whenever the client shows nothing.
-- Exact spell ids are allowed as a filter on a hostile unit
-- (AuraContainerUtil.CanApplyIdentityCandidateFilters).
--
-- THE PERCENT
--
-- At your own cast of a dot (UNIT_SPELLCAST_SUCCEEDED, player, not secret)
-- the numbers of its tooltip text are kept -- the client writes them with your
-- current spell power and talents in. Later, the same text is read again: the
-- number that changed, as a ratio, is what a recast would gain or lose. Only
-- shown for the target the dot was cast on, for as long as the dot can last.
-- Where the client makes the text secret, nothing is shown.
local _, ns = ...
local L = ns.L
local RB = ns.RB

local Dots = {}
RB.Dots = Dots

local frame, rows, events
local snaps = {}              -- [dot key] = { guid, id, numbers, until }
local applyTimer
local list = {}               -- the dots this character knows: { ids, set, icon, known }

local function db() return RB.db().dots end

local F = AuraUtil and AuraUtil.AuraFilters or {}
local FILTER = table.concat({ F.Harmful or "HARMFUL", F.Player or "PLAYER" }, "|")

-- ------------------------------------------------------------- the dots --

local function knownId(entry)
    -- the highest rank the player has; any rank will do for name and icon
    for i = #entry.ids, 1, -1 do
        if C_SpellBook.IsSpellKnown(entry.ids[i]) then return entry.ids[i] end
    end
end

local function collect()
    wipe(list)
    local _, class = UnitClass("player")
    for _, entry in ipairs((RB.DOTS or {})[class] or {}) do
        local id = knownId(entry)
        if id and not (db().hidden and db().hidden[entry.name]) then
            local set = {}
            for _, x in ipairs(entry.ids) do set[x] = true end
            list[#list + 1] = { key = entry.name, ids = entry.ids, set = set, known = id }
        end
    end
end

-- ------------------------------------------------------------ percent --

local function numbers(id)
    local ok, text = pcall(C_Spell.GetSpellDescription, id)
    if not ok or type(text) ~= "string" or not ns.CanRead(text) then return nil end
    -- Thousands separators differ by language ("1,020", "1.020", "1 020"):
    -- a separator followed by exactly three digits joins the groups. A decimal
    -- ("1,5 Sek.") stays two numbers, the same on both sides of a comparison.
    text = text:gsub("\194\160", " "):gsub("\226\128\175", " ")   -- no-break spaces
    for _ = 1, 2 do
        text = text:gsub("(%d)[,%. ](%d%d%d)%f[%D]", "%1%2")
    end
    local out = {}
    for n in text:gmatch("%d+") do out[#out + 1] = tonumber(n) end
    return #out > 0 and out or nil
end

-- The number that moved the most between then and now, as a ratio.
local function change(old, new)
    if not (old and new) or #old ~= #new then return nil end
    local best
    for i = 1, #old do
        if old[i] > 0 and old[i] ~= new[i] then
            local r = new[i] / old[i] - 1
            if not best or math.abs(r) > math.abs(best) then best = r end
        end
    end
    return best or 0
end

local function targetGUID()
    local g = UnitGUID("target")
    return ns.CanRead(g) and g or nil
end

-- ---------------------------------------------------------------- rows --

local function filterIds(entry) return { includeSpellIDs = entry.set } end

-- What the client registers on each button it creates: an icon over ours,
-- the duration bar, the time. Read at the moment of the call, like the aura
-- module does (Auras/Style.lua): a later settings change rebuilds.
local function initializer(width, height)
    return function(button)
        local d = db()
        button:SetSize(width, height)
        local icon = button:CreateTexture(nil, "ARTWORK")
        icon:SetSize(height, height)
        icon:SetPoint("LEFT")
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        local bar = CreateFrame("StatusBar", nil, button)
        bar:SetPoint("TOPLEFT", height + 1, 0)
        bar:SetPoint("BOTTOMRIGHT")
        bar:SetStatusBarTexture(ns.MediaStatusbar(d.texture, "Interface\\Buttons\\WHITE8X8"))
        local c = d.fillColor
        bar:SetStatusBarColor(c.r, c.g, c.b, 1)
        local time = bar:CreateFontString(nil, "OVERLAY")
        ns.UI.FontFor("resourcebars", time, d.textSize, "OUTLINE")
        time:SetPoint("RIGHT", -3, 0)
        pcall(button.SetIcon, button, icon)
        local opts = Enum.StatusBarTimerDirection and { direction = Enum.StatusBarTimerDirection.RemainingTime } or {}
        if not pcall(button.SetDurationBar, button, bar, opts) then pcall(button.SetDurationBar, button, bar) end
        if d.showTime then
            local f = ns.AuraDurationFormatter and ns.AuraDurationFormatter()
            if not (f and pcall(button.SetDurationText, button, time, { textFormatter = f })) then
                pcall(button.SetDurationText, button, time, {})
            end
        end
        pcall(button.SetMouseClickEnabled, button, false)
        pcall(button.SetMouseMotionEnabled, button, false)
    end
end

local function newRow(i)
    local d = db()
    local r = CreateFrame("Frame", nil, frame)
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.icon = r:CreateTexture(nil, "BORDER")
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.icon:SetDesaturated(true)
    r.icon:SetAlpha(0.6)
    r.edges = ns.MakeEdges(r, "OVERLAY")
    -- text on a frame above the client's button, so the bar does not cover it
    r.top = CreateFrame("Frame", nil, r)
    r.top:SetAllPoints(r)
    r.pct = r.top:CreateFontString(nil, "OVERLAY")
    local ok, c = pcall(CreateFrame, "AuraContainer", nil, r, "CustomAuraContainerTemplate")
    if ok and c then
        c:SetAllPoints(r)
        r.container = c
    end
    rows[i] = r
    return r
end

-- What the client's buttons were made with. Their look is fixed when the
-- client creates them, so a change of any of it means a fresh container.
local function styleKey(width, height)
    local d, c = db(), db().fillColor
    return table.concat({ width, height, d.texture or "", c.r, c.g, c.b, d.textSize,
        tostring(d.showTime) }, ":")
end

-- (Re)builds the group of a row for its dot and the current size. A group is
-- never removed; a container whose buttons carry an old look is let go (unit
-- "none", hidden) and replaced, and a row with nothing to show is parked.
local function setupRow(r, entry, width, height)
    local key = styleKey(width, height)
    if r.container and r.grouped and r.style ~= key then
        pcall(r.container.SetUnit, r.container, "none")
        r.container:Hide()
        local ok, c = pcall(CreateFrame, "AuraContainer", nil, r, "CustomAuraContainerTemplate")
        r.container = ok and c or nil
        if r.container then r.container:SetAllPoints(r) end
        r.grouped = false
    end
    r.style = key
    local c = r.container
    if not c then return end
    if not r.grouped then
        r.grouped = pcall(c.AddAuraGroup, c, "dot", FILTER, {
            maxFrameCount = 1,
            candidateFilters = filterIds(entry),
            initializeFrame = initializer(width, height),
            layout = { elementWidth = width, elementHeight = height, elementSpacing = 0, lineSpacing = 0 },
        })
        if c.SetFlowLayoutAnchorPoint then pcall(c.SetFlowLayoutAnchorPoint, c, "TOPLEFT") end
    else
        pcall(c.SetAuraGroupCandidateFilters, c, "dot", filterIds(entry))
        pcall(c.SetAuraGroupLayout, c, "dot", { elementWidth = width, elementHeight = height,
            elementSpacing = 0, lineSpacing = 0 })
    end
    pcall(c.SetUnit, c, "target")
end

local function paintPercent(i)
    local r, entry = rows[i], list[i]
    if not (r and entry) then return end
    local s = snaps[entry.key]
    local guid = targetGUID()
    if not (db().showPercent and s and guid and s.guid == guid and GetTime() < s["until"]) then
        r.pct:SetText("")
        return
    end
    -- the rank that was cast, not the highest known: a downranked cast
    -- compared with the top rank would show a gain that is not there
    local ch = change(s.numbers, numbers(s.id))
    if not ch then r.pct:SetText(""); return end
    local pct = math.floor(ch * 100 + (ch >= 0 and 0.5 or -0.5))
    if pct == 0 then r.pct:SetText(""); return end
    local c = pct >= 0 and db().betterColor or db().worseColor
    r.pct:SetTextColor(c.r, c.g, c.b)
    r.pct:SetText(("%+d%%"):format(pct))
end

local function paintAllPercent()
    for i = 1, #list do paintPercent(i) end
end

-- ------------------------------------------------------------- layout --

function Dots.Layout()
    if not frame then return end
    local d = db()
    local h, w, gap = d.height, d.width, d.spacing
    local n = #list
    frame:SetSize(w, math.max(h, n * h + math.max(0, n - 1) * gap))
    for i = 1, math.max(n, #rows) do
        local r = rows[i]
        local entry = list[i]
        if entry then
            r = r or newRow(i)
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", 0, -(i - 1) * (h + gap))
            r:SetSize(w, h)
            r.icon:SetTexture(C_Spell.GetSpellTexture(entry.known))
            r.icon:SetSize(h, h)
            r.icon:ClearAllPoints()
            r.icon:SetPoint("LEFT")
            r.bg:ClearAllPoints()
            r.bg:SetPoint("TOPLEFT", h + 1, 0)
            r.bg:SetPoint("BOTTOMRIGHT")
            local e = d.emptyColor
            r.bg:SetColorTexture(e.r, e.g, e.b, e.a or 0.85)
            ns.LayoutEdges(r.edges, r, 1, 0, 0, 0, 1)
            ns.UI.FontFor("resourcebars", r.pct, d.textSize, "OUTLINE")
            r.pct:ClearAllPoints()
            r.pct:SetPoint("LEFT", r.icon, "RIGHT", 4, 0)
            setupRow(r, entry, w, h)
            r.top:SetFrameLevel((r.container and r.container:GetFrameLevel() or r:GetFrameLevel()) + 10)
            r:Show()
        elseif r then
            if r.container then pcall(r.container.SetUnit, r.container, "none") end
            r:Hide()
        end
    end
    paintAllPercent()
end

-- Shown with a hostile target (or always, if the player wants), never empty.
function Dots.UpdateVisibility()
    if not frame then return end
    local d = db()
    local on = RB.mod.active and d.enabled and #list > 0
    if on and d.hideWithoutTarget then
        local can = UnitExists("target") and UnitCanAttack("player", "target")
        on = ns.CanRead(can) and can and true or false
    end
    if ns.IsEditModeActive and ns:IsEditModeActive() then on = RB.mod.active and d.enabled end
    frame:SetShown(on and true or false)
end

-- ------------------------------------------------------------- events --

local function onCast(_, unit, _, spellID)
    if unit ~= "player" or type(spellID) ~= "number" or not ns.CanRead(spellID) then return end
    for i, entry in ipairs(list) do
        if entry.set[spellID] then
            local nums = numbers(spellID)
            local guid = targetGUID()
            if nums and guid then
                -- kept for as long as any dot lasts in this game (60 s covers
                -- them all); a repaint at the end takes the text away
                snaps[entry.key] = { guid = guid, id = spellID, numbers = nums, ["until"] = GetTime() + 60 }
                C_Timer.After(60.1, function() paintPercent(i) end)
            end
            paintPercent(i)
            return
        end
    end
end

local function onSpells()
    collect()
    Dots.Layout()
    Dots.UpdateVisibility()
end

local EVENTS = {
    UNIT_SPELLCAST_SUCCEEDED = onCast,
    PLAYER_TARGET_CHANGED = function()
        -- SetUnit("target") again is a no-op for the same token; the client's
        -- own target frame asks its container to look again (UpdateAllAuras)
        for _, r in ipairs(rows or {}) do
            if r.container and r:IsShown() then pcall(r.container.UpdateAllAuras, r.container) end
        end
        paintAllPercent()
        Dots.UpdateVisibility()
    end,
    UNIT_FACTION = function(_, unit) if unit == "target" then Dots.UpdateVisibility() end end,
    SPELLS_CHANGED = onSpells,
    PLAYER_LEVEL_UP = onSpells,
    -- a buff gained or lost changes what a recast would do
    UNIT_AURA = function(_, unit) if unit == "player" then paintAllPercent() end end,
    PLAYER_REGEN_ENABLED = paintAllPercent,
}

-- ------------------------------------------------------------- public --

local function build()
    if frame then return end
    rows = {}
    frame = CreateFrame("Frame", "VuloForeverUIDotBars", UIParent)
    frame:SetFrameStrata("MEDIUM")
    local d = db()
    frame:SetSize(d.width, d.height)
    frame.mover = ns:CreateMover(frame, {
        key = "resourcebar_dots", label = L["DoT bars"], db = d, module = "resourcebars",
        width = d.width, height = d.height * 3, scalable = true, fill = true,
    })
    ns:ApplyMover(frame.mover)
    events = CreateFrame("Frame")
    events:SetScript("OnEvent", function(_, event, ...)
        local fn = EVENTS[event]
        if fn then fn(event, ...) end
    end)
end

-- Settings arrive once per slider step; a container restyle builds ten
-- buttons per row, so the work waits until the value has settled.
function Dots.Apply()
    if applyTimer then applyTimer:Cancel() end
    applyTimer = C_Timer.NewTimer(0.3, function() applyTimer = nil; Dots.ApplyNow() end)
end

function Dots.ApplyNow()
    local on = RB.mod.active and db().enabled
    if not on then
        if events then events:UnregisterAllEvents() end
        if frame then frame:Hide() end
        return
    end
    if InCombatLockdown() then
        ns:RunOutOfCombatOnce("rb_dots", Dots.ApplyNow)
        return
    end
    build()
    for e in pairs(EVENTS) do
        if e == "UNIT_SPELLCAST_SUCCEEDED" or e == "UNIT_AURA" then
            events:RegisterUnitEvent(e, "player")
        elseif e == "UNIT_FACTION" then
            events:RegisterUnitEvent(e, "target")
        else
            events:RegisterEvent(e)
        end
    end
    collect()
    -- the mover follows the profile and the size
    local d = db()
    frame.mover.opts.db = d
    frame.mover.opts.width, frame.mover.opts.height = d.width, math.max(d.height, #list * (d.height + d.spacing))
    if ns.RefreshMoverGeometry then ns:RefreshMoverGeometry(frame.mover) end
    ns:ApplyMover(frame.mover)
    Dots.Layout()
    Dots.UpdateVisibility()
end

-- The dots this class has, for the options (name + icon of the known rank).
function Dots.Catalog()
    local out = {}
    local _, class = UnitClass("player")
    for _, entry in ipairs((RB.DOTS or {})[class] or {}) do
        local id = knownId(entry)
        if id then out[#out + 1] = { key = entry.name, name = C_Spell.GetSpellName(id) or entry.name } end
    end
    return out
end
