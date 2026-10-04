-- VuloForeverUI / Modules / ResourceBars / Preview
--
-- The live preview pinned above each tab: the bars of that tab, one under the
-- other, at the size they have on screen. A click on a bar, its texts or the
-- cast icon opens that bar's section and flashes the row.
--
-- They are the same bars. Each preview bar is built by RB.BuildRegions and
-- dressed by RB.PaintLook and RB.ApplyTicksTo, the passes the real bars go
-- through; only the fill and the texts are invented, so nothing here reads a
-- value the client could hand out as a secret. It works with the module off,
-- which is the point: the module ships off.
local _, ns = ...
local L  = ns.L
local RB = ns.RB
local UI = ns.UI

local GAP = 8

-- Which bars stand on which tab, and how full each one is drawn.
local TAB_BARS = {
    resources = { "power", "mana" },
    cast      = { "cast" },
    swing     = { "swingMain", "swingOff", "swingRanged" },
    xp        = { "xp" },
}
local FILL = { power = 0.72, mana = 0.45, cast = 0.6, swingMain = 0.35, swingOff = 0.6, swingRanged = 0.85 }
local MAX  = { power = 4800, mana = 3200 }
-- The experience bar's invented numbers: under half full, a stretch of rest
-- and two quests ready to hand in, so every overlay is on show.
local XP_SAMPLE = { cur = 4520, max = 10000, rested = 3000, questComplete = 900,
                    questIncomplete = 700, perHour = 15400, toLevel = 1430,
                    levelTime = 4380, totalTime = 412000, sessionTime = 2700 }
local CAST_SPELL = 116             -- a spell every client knows, for its name and icon

local header, holder
local frames = {}
local currentTab = "resources"

local function playerPower()
    local _, token = UnitPowerType("player")
    if ns.CanRead(token) and type(token) == "string" then return token end
    return "MANA"
end

local function castSample()
    local name, icon
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, CAST_SPELL)
        if ok and type(info) == "table" then name, icon = info.name, info.iconID end
    end
    return name or L["Cast bar"], icon or 135846
end

local function leftText(key, bar)
    local mode = bar.leftText or "none"
    if mode == "label" then return RB.Label(key) end
    if mode == "name" then
        if key == "cast" then return (castSample()) end
        if key == "power" then return _G[playerPower()] or RB.Label(key) end
        return RB.Label(key)
    end
    return ""
end

local function rightText(key, bar)
    local mode = bar.rightText or "none"
    local frac = FILL[key] or 0.5
    local max = MAX[key] or 100
    if mode == "value" then return tostring(math.floor(max * frac)) end
    if mode == "valuemax" then return math.floor(max * frac) .. " / " .. max end
    if mode == "percent" then return math.floor(frac * 100 + 0.5) .. "%" end
    if mode == "time" then return string.format("%.1f", (1 - frac) * 2.5) end
    return ""
end

local function frameFor(i)
    local f = frames[i]
    if not f then
        f = CreateFrame("Frame", nil, holder)
        RB.BuildRegions(f)
        frames[i] = f
    end
    return f
end

-- ---------------------------------------------------------------- draw --

local function xpSample(bar)
    local d = {}
    for k, v in pairs(XP_SAMPLE) do d[k] = v end
    d.rawCur, d.rawMax = d.cur, d.max
    d.level = ns.Num(UnitLevel("player"), 1)
    -- The real rest state where it can be read, so the colour shown here is
    -- the one the bar has right now; rested otherwise.
    local state = ns.Num(GetRestState())
    d.isRested = state == nil or state == 1
    return d
end

-- A pooled frame that showed the experience bar keeps its extra regions; any
-- other bar drawn on it must not inherit them.
local function clearXP(f)
    if not f.xpQuest then return end
    f.xpQuest:Hide(); f.xpIncomplete:Hide(); f.xpRested:Hide()
    f.center:Hide(); f.xpInfo:Hide()
end

local function paint(f, key, bar)
    RB.PaintLook(f, bar)
    if key == "xp" then
        RB.ApplyTicksTo(f, bar, XP_SAMPLE.max)
        RB.XP.Paint(f, bar, xpSample(bar))
        f.icon:Hide()
        f.shield:SetAlpha(0)
        f:SetAlpha(bar.enabled and (bar.opacity or 1) or 0.3)
        return 0, false
    end
    clearXP(f)
    f.fill:SetMinMaxValues(0, 1)
    f.fill:SetValue(FILL[key] or 0.5)
    if (key == "power" or key == "mana") and bar.useTypeColor then
        local c = PowerBarColor and PowerBarColor[key == "power" and playerPower() or "MANA"]
        if c then f.fill:SetStatusBarColor(c.r, c.g, c.b) end
    end
    RB.ApplyTicksTo(f, bar, MAX[key])
    f.left:SetText(leftText(key, bar))
    f.right:SetText(rightText(key, bar))
    local withIcon = key == "cast" and bar.showIcon
    if withIcon then
        local _, icon = castSample()
        f.icon:SetTexture(icon)
    end
    f.icon:SetShown(withIcon and true or false)
    f.shield:SetAlpha(0)
    -- A bar that is switched off still shows, faintly, so its settings are
    -- not edited blind.
    f:SetAlpha(bar.enabled and (bar.opacity or 1) or 0.3)
    return withIcon and (bar.height + 2) or 0, bar.iconSide == "RIGHT"
end

local function spots(i, f, key, tab)
    local base = { mod = "resourcebars", tab = tab, section = RB.Label(key), sectionKey = key }
    local function target(field, label)
        return { mod = base.mod, tab = tab, section = base.section, sectionKey = key,
                 subKey = key .. field, label = label }
    end
    header:Spot("bar" .. i, f, target("width", L["Width"]), 0)
    header:Spot("left" .. i, (f.left:GetText() or "") ~= "" and f.left or nil, target("leftText", L["Left text"]), 2)
    header:Spot("right" .. i, (f.right:GetText() or "") ~= "" and f.right or nil, target("rightText", L["Right text"]), 2)
    header:Spot("icon" .. i, f.icon:IsShown() and f.icon or nil, target("showIcon", L["Show the spell icon"]), 2)
    local center = key == "xp" and f.center and (f.center:GetText() or "") ~= "" and f.center or nil
    header:Spot("center" .. i, center, target("centerText", L["Middle text"]), 2)
    local info = key == "xp" and f.xpInfo and (f.xpInfo:GetText() or "") ~= "" and f.xpInfo or nil
    header:Spot("info" .. i, info, target("showRate", L["Info line under the bar"]), 2)
end

-- Room the experience bar's info line takes under the bar itself.
function RB.PreviewBelow(f, bar)
    if not (f.xpInfo and f.xpInfo:IsShown() and (f.xpInfo:GetText() or "") ~= "") then return 0 end
    return (bar.infoSize or 11) + 5
end

-- `force`: the page build, before the header is on screen.
function RB.RefreshPreview(force)
    if not header then return end
    if not force and not header:IsLive() then return end
    local keys = TAB_BARS[currentTab] or TAB_BARS.resources
    if currentTab == "cast" and (RB.Bar("cast").castStyle or "standard") ~= "modern" then
        keys = {}
    end

    -- Measure first, in bar units: the widest bar with its icon, all heights
    -- and the gaps between them.
    local wide, high, left, right = 0, 0, 0, 0
    local list = {}
    for i, key in ipairs(keys) do
        local bar = RB.Bar(key)
        local f = frameFor(i)
        local iconW, iconRight = paint(f, key, bar)
        if iconRight then right = math.max(right, iconW) else left = math.max(left, iconW) end
        wide = math.max(wide, bar.width)
        high = high + bar.height + (i > 1 and GAP or 0) + RB.PreviewBelow(f, bar)
        list[i] = { f = f, key = key, bar = bar }
    end
    for i = #keys + 1, #frames do
        frames[i]:Hide()
        for _, s in ipairs({ "bar", "left", "right", "icon", "center", "info" }) do header:HideSpot(s .. i) end
    end
    -- Nothing of ours on this tab (the cast bar under a style that keeps the
    -- client's): no header at all, rather than an empty strip with a hint.
    if #list == 0 then
        holder:Hide()
        return 0
    end

    local total = left + wide + right
    holder:SetSize(total, high)
    local scale = header:Fit(total, high, list[1].bar.scale or 1)
    holder:SetScale(scale)
    holder:ClearAllPoints()
    holder:SetPoint("CENTER", header.stage, "CENTER", 0, 0)
    holder:Show()

    local y = 0
    for i, e in ipairs(list) do
        e.f:ClearAllPoints()
        e.f:SetPoint("TOP", holder, "TOP", (left - right) / 2, -y)
        e.f:Show()
        y = y + e.bar.height + GAP + RB.PreviewBelow(e.f, e.bar)
        spots(i, e.f, e.key, currentTab)
    end
    return header:SetStageHeight(high * scale)
end

-- Pinned above every tab (Options.lua hands the builder this).
function RB.BuildPreviewHeader(host, tabId)
    if not header then
        header = UI:CreatePreviewHeader({ key = "resourcebars", hint = true })
        holder = CreateFrame("Frame", nil, header.stage)
    end
    currentTab = tabId or "resources"
    header:Mount(host)
    return RB.RefreshPreview(true) or 0
end
