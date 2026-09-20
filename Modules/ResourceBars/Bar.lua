-- VuloForeverUI / Modules / ResourceBars / Bar
--
-- The one bar every display in this module is made of: a status bar with a
-- background, a border, a spark, two texts, a pool of tick marks and a mover.
--
-- Power bars are always there; cast and swing bars are TRANSIENT -- they exist
-- only while something is running. That difference lives here, in one flag, so
-- the three displays above do not each invent their own way of hiding.
local _, ns = ...
local RB = ns.RB
local UI = ns.UI

RB.frames = RB.frames or {}

local WHITE = RB.WHITE

-- A bar that is only there while something runs. Power is not; everything else
-- is, and in Edit Mode all of them are, or there would be nothing to drag.
local function isTransient(key)
    return key ~= "power" and key ~= "mana"
end
RB.IsTransient = isTransient

-- ---------------------------------------------------------------- build --

function RB.BuildBar(key)
    if RB.frames[key] then return RB.frames[key] end
    local bar = RB.Bar(key)
    if not bar then return nil end

    local frame = CreateFrame("Frame", "VuloForeverUIResourceBar" .. key, UIParent)
    frame:SetSize(bar.width, bar.height)
    frame:SetFrameStrata("MEDIUM")
    frame.barKey = key
    RB.frames[key] = frame

    local fill = CreateFrame("StatusBar", nil, frame)
    fill:SetAllPoints(frame)
    fill:SetMinMaxValues(0, 1)
    fill:SetValue(0)
    frame.fill = fill

    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(frame)
    bg:SetTexture(WHITE)
    frame.bg = bg

    frame.edges = ns.MakeEdges(frame, "OVERLAY")

    -- The spark rides the end of the fill. It is anchored to the fill TEXTURE,
    -- not to a value: the texture is where the engine actually drew, which is
    -- the only place that stays right while a secret value moves it.
    local spark = fill:CreateTexture(nil, "OVERLAY")
    spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
    spark:SetBlendMode("ADD")
    spark:SetWidth(16)
    frame.spark = spark

    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:Hide()
    frame.icon = icon

    -- The shield for a cast nobody can interrupt. A texture, never a decision:
    -- whether it shows is an alpha folded from a secret boolean.
    local shield = frame:CreateTexture(nil, "OVERLAY")
    shield:SetTexture("Interface\\CastingBar\\UI-CastingBar-Small-Shield")
    shield:SetAlpha(0)
    frame.shield = shield

    local left = frame:CreateFontString(nil, "OVERLAY")
    left:SetPoint("LEFT", frame, "LEFT", 4, 0)
    left:SetJustifyH("LEFT")
    frame.left = left

    local right = frame:CreateFontString(nil, "OVERLAY")
    right:SetPoint("RIGHT", frame, "RIGHT", -4, 0)
    right:SetJustifyH("RIGHT")
    frame.right = right

    frame.ticks = {}

    frame.mover = ns:CreateMover(frame, {
        key      = "resourcebar_" .. key,
        label    = RB.Label(key),
        db       = bar,
        module   = "resourcebars",
        width    = bar.width,
        height   = bar.height,
        scalable = true,
        -- A transient bar is invisible most of the time; the mover box has to
        -- stand in for it, or there is nothing to grab in Edit Mode.
        fill     = isTransient(key),
    })
    ns:ApplyMover(frame.mover)

    return frame
end

-- ---------------------------------------------------------------- ticks --

-- "20,40,60" -> three marks. Percent or absolute, both plain numbers typed by
-- the player: nothing here touches a value the client owns.
local function parseTicks(str)
    local out = {}
    if type(str) ~= "string" then return out end
    for piece in str:gmatch("[^,%s]+") do
        local n = tonumber(piece)
        if n and n > 0 then out[#out + 1] = n end
    end
    return out
end
RB.ParseTicks = parseTicks

-- maxVal is needed only for absolute ticks, and it is the MAX, which stays
-- readable on this client. An unreadable one simply draws no absolute marks.
function RB.ApplyTicks(key, maxVal)
    local frame = RB.frames[key]
    local bar = RB.Bar(key)
    if not (frame and bar) then return end

    local values = parseTicks(bar.ticks)
    local width  = frame:GetWidth() or bar.width
    local shown  = 0

    for _, value in ipairs(values) do
        local frac
        if bar.tickPercent then
            frac = value / 100
        elseif type(maxVal) == "number" and maxVal > 0 and ns.CanRead(maxVal) then
            frac = value / maxVal
        end
        if frac and frac > 0 and frac < 1 then
            shown = shown + 1
            local tick = frame.ticks[shown]
            if not tick then
                tick = frame:CreateTexture(nil, "OVERLAY", nil, 2)
                tick:SetTexture(WHITE)
                frame.ticks[shown] = tick
            end
            tick:ClearAllPoints()
            tick:SetPoint("TOP", frame, "TOPLEFT", width * frac, 0)
            tick:SetPoint("BOTTOM", frame, "BOTTOMLEFT", width * frac, 0)
            tick:SetWidth(ns:Pixel(frame, bar.tickWidth or 1))
            tick:SetColorTexture(bar.tickColor.r, bar.tickColor.g, bar.tickColor.b, bar.tickColor.a or 0.6)
            tick:Show()
        end
    end
    for i = shown + 1, #frame.ticks do frame.ticks[i]:Hide() end
end

-- ---------------------------------------------------------------- style --

function RB.StyleBar(key)
    local frame = RB.frames[key] or RB.BuildBar(key)
    local bar = RB.Bar(key)
    if not (frame and bar) then return end

    frame:SetSize(bar.width, bar.height)
    frame.fill:SetStatusBarTexture(ns.MediaStatusbar(bar.texture, WHITE))
    frame.fill:SetStatusBarColor(bar.fillColor.r, bar.fillColor.g, bar.fillColor.b)
    frame.bg:SetColorTexture(bar.bgColor.r, bar.bgColor.g, bar.bgColor.b, bar.bgColor.a or 0.85)
    ns.LayoutEdges(frame.edges, frame, bar.borderSize or 0,
        bar.borderColor.r, bar.borderColor.g, bar.borderColor.b, bar.borderColor.a or 1, 0)

    frame.spark:SetHeight(bar.height * 2)
    frame.spark:ClearAllPoints()
    frame.spark:SetPoint("CENTER", frame.fill:GetStatusBarTexture(), "RIGHT", 0, 0)
    frame.spark:SetShown(bar.showSpark ~= false)

    UI.FontFor("resourcebars", frame.left, bar.fontSize or 11, "OUTLINE")
    UI.FontFor("resourcebars", frame.right, bar.fontSize or 11, "OUTLINE")
    frame.left:SetTextColor(bar.textColor.r, bar.textColor.g, bar.textColor.b)
    frame.right:SetTextColor(bar.textColor.r, bar.textColor.g, bar.textColor.b)

    -- The icon eats into the bar on the side it sits, so the text never lands
    -- underneath it.
    local size = bar.height
    frame.icon:ClearAllPoints()
    if bar.iconSide == "RIGHT" then
        frame.icon:SetPoint("LEFT", frame, "RIGHT", 2, 0)
    else
        frame.icon:SetPoint("RIGHT", frame, "LEFT", -2, 0)
    end
    frame.icon:SetSize(size, size)
    frame.shield:ClearAllPoints()
    frame.shield:SetPoint("CENTER", frame, "LEFT", 0, 0)
    frame.shield:SetSize(size * 1.6, size * 1.6)

    RB.ApplyTicks(key, frame.maxValue)

    if frame.mover then
        frame.mover.opts.db = bar
        frame.mover.opts.label = RB.Label(key)
        frame.mover.opts.width, frame.mover.opts.height = bar.width, bar.height
        ns:RefreshMoverGeometry(frame.mover)
        ns:ApplyMover(frame.mover)
    end
    RB.UpdateVisibility(key)
end

-- ---------------------------------------------------------------- state --

-- Transient bars say "something is running now" through this, and nothing
-- else. Whether that ends up on screen is still UpdateVisibility's word.
function RB.SetActive(key, active)
    local frame = RB.frames[key]
    if not frame then return end
    frame.active = active and true or false
    RB.UpdateVisibility(key)
end

function RB.UpdateVisibility(key)
    local frame = RB.frames[key]
    local bar = RB.Bar(key)
    if not (frame and bar) then return end

    -- A bar the chosen style does not use at all is not a hidden bar, it is a
    -- bar that does not exist: our own cast bar under the two styles that keep
    -- the client's. Edit Mode must not offer it either, or it would be placing
    -- something nothing will ever show.
    if frame.disabledByStyle then frame:Hide(); return end

    -- Edit Mode and the settings page show everything else, transient or not:
    -- a bar that only appears mid-swing cannot be placed while it is invisible.
    if ns:IsEditModeActive() or RB.optionsOpen then
        frame:Show()
        frame:SetAlpha(bar.opacity or 1)
        return
    end
    if not bar.enabled then frame:Hide(); return end

    local vis = bar.visibility or "always"
    local shown = true
    if vis == "hidden" then shown = false
    elseif vis == "combat" then shown = ns:InCombat()
    elseif vis == "noncombat" then shown = not ns:InCombat() end

    if shown and isTransient(key) then shown = frame.active == true end
    -- A display may say it has nothing to show at all -- the additional power
    -- bar outside a form, for instance. That is about which powers exist,
    -- which is readable, never about how full one is, which is not.
    if shown and frame.suppressed then shown = false end
    frame:SetShown(shown)

    if shown then
        local alpha = bar.opacity or 1
        if bar.oocFade and not ns:InCombat() then alpha = bar.oocAlpha or 0.45 end
        frame:SetAlpha(alpha)
    end
end

-- ---------------------------------------------------------------- text --

-- The left corner: a name, a fixed label, or nothing. `name` may be a secret
-- string (a cast's name is one in combat) and goes into SetText untouched.
function RB.SetLeftText(key, name, label)
    local frame, bar = RB.frames[key], RB.Bar(key)
    if not (frame and bar) then return end
    local mode = bar.leftText or "none"
    if mode == "name" and type(name) ~= "nil" then
        frame.left:SetText(name)
    elseif mode == "label" and label then
        frame.left:SetText(label)
    else
        frame.left:SetText("")
    end
end
