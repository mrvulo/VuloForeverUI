-- VuloForeverUI / Modules / Skins / Stats
--
-- The stat pane of the character window: a ScrollBox list the client fills
-- from PAPERDOLL_STATCATEGORIES in CharacterStatsPaneScrollBox:UpdateStats().
-- Headers and rows are pooled frames handed out by the list.
--
-- LOOK (Modern): a header loses its gold plate and becomes a title in the
-- accent colour between two hairlines; the row stripes go quieter.
--
-- FOLDING ("Stat sections"): a click on a header folds its section. The
-- list is the client's, so folding means handing the list a shorter data
-- provider made from the client's own entries -- and ONLY then: with nothing
-- folded the client's provider is never touched, so no taint can come from
-- here. The client sets its own provider again on every update and whenever
-- it drops a hidden stat (HideElements); both are hooked, and a provider that
-- is not ours is shortened again. Ours does not trigger another round: after
-- it, HideElements finds nothing to drop and leaves the provider alone.
local _, ns = ...
local L = ns.L
local Skins = ns.Skins

local Stats = {}
Skins.Stats = Stats
table.insert(Skins.parts, Stats)

local deco = setmetatable({}, { __mode = "k" })    -- header frame -> ours
local ours                                         -- the provider we set

local function pane() return _G.CharacterStatsPaneScrollBox end

local function folding()
    local db = Skins.db()
    return Skins.mod.active and db.character and db.statSections
end

-- ---------------------------------------------------------------- fold --

-- Never in a fight: a new provider runs every row's update in OUR taint,
-- and a stat that is secret in combat would throw there. The fold waits for
-- the fight to end (PLAYER_REGEN_ENABLED, Stats.Enable).
local function shorten()
    if InCombatLockdown() then return end
    local sb = pane()
    if not (sb and sb.ScrollBox and type(sb.elementData) == "table") then return end
    local folded = Skins.db().collapsed
    if not (folding() and next(folded)) then return end
    local list, skip = {}, false
    for _, e in ipairs(sb.elementData) do
        if e.isHeader then
            skip = folded[e.name] == true
            list[#list + 1] = e
        elseif not skip and not e.shouldRemove then
            list[#list + 1] = e
        end
    end
    if #list == #sb.elementData then ours = nil; return end
    ours = CreateDataProvider(list)
    sb.ScrollBox:SetDataProvider(ours, ScrollBoxConstants.RetainScrollPosition)
end

-- The client's own full list again: it rebuilds from scratch.
local function refill()
    if InCombatLockdown() then return end
    ours = nil
    if _G.PaperDollFrame_UpdateStats and _G.CharacterFrame and _G.CharacterFrame:IsShown() then
        _G.PaperDollFrame_UpdateStats()
    end
end

local function toggle(name)
    if type(name) ~= "string" or name == "" or InCombatLockdown() then return end
    local folded = Skins.db().collapsed
    folded[name] = (not folded[name]) and true or nil
    refill()
end

-- ---------------------------------------------------------------- look --

-- Each section its own colour in Modern; the rows below take it for their
-- values. Keyed by the client's own section names.
local SECTION_COLOR = {
    STAT_CATEGORY_GENERAL            = { 0.30, 0.80, 0.95 },
    STAT_CATEGORY_PRIMARY_ATTRIBUTES = { 0.05, 0.82, 0.62 },
    STAT_CATEGORY_WEAPONS            = { 1.00, 0.35, 0.12 },
    STAT_CATEGORY_MODIFIERS          = { 0.47, 0.26, 0.78 },
    STAT_CATEGORY_DEFENSE            = { 0.25, 0.66, 1.00 },
}
local function sectionColor(name)
    for key, c in pairs(SECTION_COLOR) do
        if _G[key] == name then return c end
    end
    local ac = ns.COLORS.accent
    return { ac.r, ac.g, ac.b }
end

local rowDeco = setmetatable({}, { __mode = "k" })    -- row frame -> ours

local function headerDeco(frame)
    local d = deco[frame]
    if d then return d end
    d = {}
    d.button = CreateFrame("Button", nil, frame)
    d.button:SetAllPoints(frame)
    d.button:SetFrameLevel(frame:GetFrameLevel() + 2)
    d.button:SetScript("OnClick", function()
        local t = frame.Title and frame.Title:GetText()
        if ns.CanRead(t) then toggle(t) end
    end)
    d.button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["Click: fold or unfold this section"], 1, 1, 1)
        GameTooltip:Show()
    end)
    d.button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    d.arrow = d.button:CreateTexture(nil, "OVERLAY")
    d.arrow:SetSize(12, 12)
    d.arrow:SetPoint("RIGHT", frame, "RIGHT", -8, 0)
    d.arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
    d.left = d.button:CreateTexture(nil, "ARTWORK")
    d.right = d.button:CreateTexture(nil, "ARTWORK")
    for _, t in ipairs({ d.left, d.right }) do t:SetHeight(1); t:SetColorTexture(1, 1, 1, 1) end
    deco[frame] = d
    return d
end

local function styleHeader(frame)
    local d = headerDeco(frame)
    local modern = Skins.Modern() and Skins.db().character
    local fold = folding()
    d.button:SetShown(fold or modern)
    d.button:EnableMouse(fold and true or false)
    d.arrow:SetShown(fold)
    local title = frame.Title
    local name = title and title:GetText()
    if fold then
        local closed = ns.CanRead(name) and Skins.db().collapsed[name]
        d.arrow:SetRotation(closed and 0 or -math.pi / 2)
    end
    if title and not d.titleColor then d.titleColor = { title:GetTextColor() } end
    if modern then
        Skins.Fade(frame.Background)
        local c = sectionColor(name)
        if title then title:SetTextColor(c[1], c[2], c[3]) end
        -- the hairlines hang on the title itself, so they follow its width
        d.left:ClearAllPoints();  d.left:SetPoint("LEFT", frame, "LEFT", 8, 0)
        d.left:SetPoint("RIGHT", title or frame, "LEFT", -6, 0)
        d.right:ClearAllPoints(); d.right:SetPoint("LEFT", title or frame, "RIGHT", 6, 0)
        d.right:SetPoint("RIGHT", frame, "RIGHT", fold and -24 or -8, 0)
        d.left:SetVertexColor(c[1], c[2], c[3], 0.8); d.right:SetVertexColor(c[1], c[2], c[3], 0.8)
        d.left:Show(); d.right:Show()
        return c
    else
        d.left:Hide(); d.right:Hide()
        if title and d.titleColor then title:SetTextColor(unpack(d.titleColor)) end
    end
end

-- Modern rows: no stripes, a faint hairline under each, the label grey and
-- the value in its section's colour. Standard gets the client's colours back.
local function styleRow(frame, color)
    local d = rowDeco[frame]
    if not d then
        d = { label = { frame.Label:GetTextColor() }, value = frame.Value and { frame.Value:GetTextColor() } }
        d.line = frame:CreateTexture(nil, "ARTWORK")
        d.line:SetHeight(1)
        d.line:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 8, 0)
        d.line:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 0)
        d.line:SetColorTexture(1, 1, 1, 0.06)
        rowDeco[frame] = d
    end
    if Skins.Modern() and Skins.db().character then
        if frame.Background then Skins.Fade(frame.Background) end
        d.line:Show()
        frame.Label:SetTextColor(0.7, 0.7, 0.7, 0.8)
        if frame.Value and color then frame.Value:SetTextColor(color[1], color[2], color[3]) end
    else
        d.line:Hide()
        frame.Label:SetTextColor(unpack(d.label))
        if frame.Value and d.value then frame.Value:SetTextColor(unpack(d.value)) end
    end
end

-- Each entry of the client's list -> its section's colour. The visible
-- frames are only a window on the list: the first rows on screen may sit
-- under a header that has scrolled away, so the section is looked up, not
-- carried along.
local sectionOf = setmetatable({}, { __mode = "k" })
local function mapSections(sb)
    wipe(sectionOf)
    local c
    for _, e in ipairs(sb.elementData or {}) do
        if e.isHeader then c = sectionColor(e.name) else sectionOf[e] = c end
    end
end

local function styleAll()
    local sb = pane()
    if not (sb and sb.ScrollBox) then return end
    mapSections(sb)
    sb.ScrollBox:ForEachFrame(function(frame)
        if frame.Title then
            styleHeader(frame)
        elseif frame.Label then
            local e = frame.GetElementData and frame:GetElementData()
            styleRow(frame, e and sectionOf[e])
        end
    end)
end

-- ---------------------------------------------------------------- wiring --

local hooked
function Stats.Enable(mod)
    if mod then
        mod:RegisterEvent("PLAYER_REGEN_ENABLED", function()
            if folding() and next(Skins.db().collapsed) then shorten() end
        end)
    end
    local sb = pane()
    if hooked or not (sb and sb.UpdateStats and sb.HideElements) then return end
    hooked = true
    hooksecurefunc(sb, "UpdateStats", function()
        if not Skins.mod.active then return end
        shorten()
        styleAll()
    end)
    -- runs on every layout of the list (scrolling too): restyle, and shorten
    -- again when the client has put its own full provider back
    hooksecurefunc(sb, "HideElements", function()
        if not Skins.mod.active then return end
        if ours and sb.ScrollBox:GetDataProvider() ~= ours then shorten() end
        styleAll()
    end)
end

function Stats.Apply()
    -- a fold switched off or the module off: the client's list back as it was
    if ours and not (folding() and next(Skins.db().collapsed)) then refill() end
    if Skins.mod.active and folding() and next(Skins.db().collapsed) then shorten() end
    -- off or Standard: the same pass puts the client's colours back and
    -- hides our hairlines and fold buttons
    styleAll()
end
