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

local function shorten()
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
    ours = nil
    if _G.PaperDollFrame_UpdateStats and _G.CharacterFrame and _G.CharacterFrame:IsShown() then
        _G.PaperDollFrame_UpdateStats()
    end
end

local function toggle(name)
    if type(name) ~= "string" or name == "" then return end
    local folded = Skins.db().collapsed
    folded[name] = (not folded[name]) and true or nil
    refill()
end

-- ---------------------------------------------------------------- look --

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
        local ac = ns.COLORS.accent
        if title then title:SetTextColor(ac.r, ac.g, ac.b) end
        local w = title and title:GetStringWidth() or 60
        d.left:ClearAllPoints();  d.left:SetPoint("LEFT", frame, "LEFT", 10, 0)
        d.left:SetPoint("RIGHT", frame, "CENTER", -w / 2 - 6, 0)
        d.right:ClearAllPoints(); d.right:SetPoint("LEFT", frame, "CENTER", w / 2 + 6, 0)
        d.right:SetPoint("RIGHT", frame, "RIGHT", fold and -24 or -10, 0)
        d.left:SetVertexColor(ac.r, ac.g, ac.b, 0.6); d.right:SetVertexColor(ac.r, ac.g, ac.b, 0.6)
        d.left:Show(); d.right:Show()
    else
        d.left:Hide(); d.right:Hide()
        if title and d.titleColor then title:SetTextColor(unpack(d.titleColor)) end
    end
end

local function styleRow(frame)
    if not frame.Background then return end
    local a = (Skins.Modern() and Skins.db().character) and 0.35 or 1
    frame.Background:SetVertexColor(1, 1, 1, a)
end

local function styleAll()
    local sb = pane()
    if not (sb and sb.ScrollBox) then return end
    sb.ScrollBox:ForEachFrame(function(frame)
        if frame.Title then styleHeader(frame) elseif frame.Label then styleRow(frame) end
    end)
end

-- ---------------------------------------------------------------- wiring --

local hooked
function Stats.Enable()
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
    if Skins.mod.active then
        if folding() and next(Skins.db().collapsed) then shorten() end
        styleAll()
    else
        local sb = pane()
        if sb and sb.ScrollBox then
            sb.ScrollBox:ForEachFrame(function(frame)
                local d = deco[frame]
                if d then d.button:Hide() end
            end)
        end
    end
end
