-- VuloForeverUI / Modules / ResourceBars / CastSkin
--
-- The two cast bar styles that keep the CLIENT's own bar and work on it:
--
--   standard  the bar the client ships, untouched, plus our icon and our
--             cast time next to it, both freely placed
--   classic   the same, and the bar itself dressed back to the 1.x shape:
--             195 x 13, the old border sheet, the plain status bar fill in
--             the four old colours, a static spark, and none of the modern
--             flakes, wisps and glow lines
--
-- THE ONE RULE THIS FILE IS BUILT AROUND
--
-- Nothing here ever WRITES A FIELD on a cast bar. A field written from addon
-- code taints every later read of it, and the bar's own update loop then trips
-- over the secret cast values it carries. So Blizzard's bar keeps running its
-- own code untouched, our state lives in a table keyed by the frame, and the
-- old art is put back by secure hooks after each of Blizzard's own changes.
--
-- The fill colour is the second place where care is needed: the cast TYPE is a
-- secret, so it is never read. What is read is the ATLAS NAME Blizzard just
-- chose for the fill -- a plain string that says the same thing.
local _, ns = ...
local RB = ns.RB

local Skin = {}
RB.CastSkin = Skin

local KEY = "cast"

-- Blizzard's modern decoration. All of it goes away in the classic style; the
-- names are the frame's own parentKeys, so they have to be spelled out.
local FX = {
    "Flakes01", "Flakes02", "Flakes03", "BaseGlow", "WispGlow",
    "Sparkles01", "Sparkles02", "Shine", "EnergyGlow", "InterruptGlow",
    "ChargeGlow", "ChargeFlash", "StandardGlow", "CraftGlow",
    "ChannelShadow", "DropShadow", "TextBorder",
}
local FINISH_ANIMS = { "StandardFinish", "ChannelFinish", "CraftingFinish" }

local FILL = "Interface\\TargetingFrame\\UI-StatusBar"
local BORDER = "Interface\\CastingBar\\UI-CastingBar-Border"
local SPARK  = "Interface\\CastingBar\\UI-CastingBar-Spark"
local FLASH  = "Interface\\CastingBar\\UI-CastingBar-Flash"

-- The four colours 1.x used. Chosen from the atlas name, never from the type.
local YELLOW = { 1, 0.7, 0 }
local GREEN  = { 0, 1, 0 }
local GRAY   = { 0.5, 0.5, 0.5 }
local RED    = { 1, 0, 0 }

-- Our state about a foreign frame, kept OUT of that frame.
local state = setmetatable({}, { __mode = "k" })

local function stateOf(frame)
    local s = state[frame]
    if not s then s = {}; state[frame] = s end
    return s
end

local function guard(key, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok and not Skin.reported then
        Skin.reported = true
        ns:Debug("cast skin: %s could not be applied (%s)", key, tostring(err))
    end
    return ok
end

function Skin.Frame()
    return _G.PlayerCastingBarFrame or _G.CastingBarFrame
end

local function style()
    local bar = RB.Bar(KEY)
    return (bar and bar.castStyle) or "standard"
end

-- ---------------------------------------------------------------- classic --

local function hideFx(bar)
    for _, key in ipairs(FX) do
        local region = bar[key]
        if region then
            if region.SetAtlas then pcall(region.SetAtlas, region, nil) end
            region:SetAlpha(0)
            region:Hide()
        end
    end
end

-- The fill colour for the atlas Blizzard just picked. The atlas name carries
-- the cast type, and a name is a plain string -- which is the whole point:
-- the type itself is secret and may not be compared with anything.
local function fillColor(atlas)
    if not (type(atlas) == "string" and ns.CanRead(atlas)) then return YELLOW end
    local name = atlas:lower()
    if name:find("interrupted", 1, true) then return RED end
    if name:find("uninterrupt", 1, true) then return GRAY end
    if name:find("channel", 1, true) then return GREEN end
    if name:find("full", 1, true) then return GREEN end
    return YELLOW
end

local function dressFill(bar)
    if style() ~= "classic" then return end
    local tex = bar:GetStatusBarTexture()
    local atlas = tex and tex.GetAtlas and tex:GetAtlas()
    local c = fillColor(atlas)
    bar:SetStatusBarTexture(FILL)
    bar:SetStatusBarColor(c[1], c[2], c[3])
end

local function dressSpark(bar)
    if not bar.Spark then return end
    bar.Spark:SetTexture(SPARK)
    bar.Spark:SetTexCoord(0, 1, 0, 1)
    bar.Spark:SetSize(32, 32)
    bar.Spark:SetBlendMode("ADD")
end

local function dressFlash(bar)
    if not bar.Flash then return end
    bar.Flash:SetTexture(FLASH)
    bar.Flash:SetTexCoord(0, 1, 0, 1)
    bar.Flash:SetBlendMode("ADD")
    bar.Flash:ClearAllPoints()
    bar.Flash:SetSize(256, 64)
    bar.Flash:SetPoint("TOP", bar, "TOP", 0, 28)
end

-- The 1.x shape. Done here rather than by calling the client's own SetLook:
-- that call would make Blizzard read protected cast values inside our context.
-- Set the first time we actually dress the bar, and never cleared while the
-- session lasts unless we put it back. Restore below hangs off it.
local dressed = false

local function dress(bar)
    if style() ~= "classic" then return end
    dressed = true

    bar:SetSize(195, 13)
    if bar.Border then
        bar.Border:SetTexture(BORDER)
        bar.Border:SetTexCoord(0, 1, 0, 1)
        bar.Border:ClearAllPoints()
        bar.Border:SetSize(256, 64)
        bar.Border:SetPoint("TOP", bar, "TOP", 0, 28)
    end
    if bar.BorderShield then
        bar.BorderShield:ClearAllPoints()
        bar.BorderShield:SetSize(256, 64)
        bar.BorderShield:SetPoint("TOP", bar, "TOP", 0, 28)
    end
    if bar.Text then
        bar.Text:ClearAllPoints()
        bar.Text:SetSize(185, 16)
        bar.Text:SetPoint("TOP", bar, "TOP", 0, 5)
        bar.Text:SetFontObject("GameFontHighlight")
    end
    if bar.Background then
        if bar.Background.SetAtlas then pcall(bar.Background.SetAtlas, bar.Background, nil) end
        bar.Background:SetColorTexture(0, 0, 0, 0.5)
        bar.Background:ClearAllPoints()
        bar.Background:SetAllPoints(bar)
    end
    dressSpark(bar)
    dressFlash(bar)
    hideFx(bar)
    dressFill(bar)
end

local function stopFinish(bar)
    for _, key in ipairs(FINISH_ANIMS) do
        local anim = bar[key]
        if anim and anim.Stop then anim:Stop() end
    end
    hideFx(bar)
end

-- ---------------------------------------------------------------- ours --

-- Our icon and our cast time. They live on a frame of OURS, parented to the
-- client's bar so they come and go with it, and placed by two offsets each so
-- they can be put wherever the chosen style leaves room.
local function holder(bar)
    local s = stateOf(bar)
    if s.holder then return s.holder end

    local f = CreateFrame("Frame", nil, bar)
    f:SetAllPoints(bar)
    f:SetFrameLevel((bar:GetFrameLevel() or 1) + 3)

    s.icon = f:CreateTexture(nil, "OVERLAY")
    s.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    s.icon:Hide()

    s.time = f:CreateFontString(nil, "OVERLAY")
    s.time:Hide()

    s.holder = f
    return f
end

function Skin.LayoutExtras()
    local bar = Skin.Frame()
    local cfg = RB.Bar(KEY)
    if not (bar and cfg) then return end
    local mode = style()
    if mode == "modern" then
        local s = state[bar]
        if s and s.holder then s.holder:Hide() end
        return
    end

    holder(bar)
    local s = stateOf(bar)
    s.holder:Show()

    local size = cfg.attachIconSize or 20
    s.icon:ClearAllPoints()
    s.icon:SetSize(size, size)
    s.icon:SetPoint("RIGHT", bar, "LEFT", (cfg.attachIconX or -6), (cfg.attachIconY or 0))
    s.icon:SetShown(cfg.attachIcon == true)

    ns.UI.FontFor("resourcebars", s.time, cfg.attachTimeSize or 12, "OUTLINE")
    s.time:ClearAllPoints()
    s.time:SetPoint("LEFT", bar, "RIGHT", (cfg.attachTimeX or 6), (cfg.attachTimeY or 0))
    s.time:SetShown(cfg.attachTime == true)
end

-- Fed from the cast events: the icon texture and the duration object may both
-- be secret, and both go straight into a setter.
function Skin.OnCastStart(texture, duration)
    local bar = Skin.Frame()
    local cfg = RB.Bar(KEY)
    if not (bar and cfg) or style() == "modern" then return end
    local s = stateOf(bar)
    if not s.holder then return end

    if cfg.attachIcon and ns.Exists(texture) then
        s.icon:SetTexture(texture)
        s.icon:Show()
    else
        s.icon:Hide()
    end

    if cfg.attachTime and ns.Exists(duration) then
        -- The holder owns the ticking, so the time stops by itself the moment
        -- the client's bar goes away and takes its children with it.
        ns:DurationText(s.holder, s.time, duration)
        s.time:Show()
    else
        ns:DurationText(s.holder, s.time, nil)
        s.time:Hide()
    end
end

function Skin.OnCastStop()
    local bar = Skin.Frame()
    if not bar then return end
    local s = state[bar]
    if not s then return end
    if s.holder and s.time then ns:DurationText(s.holder, s.time, nil) end
    if s.icon then s.icon:Hide() end
end

-- ---------------------------------------------------------------- install --

local function hookMethod(bar, method, key, fn)
    if type(bar[method]) ~= "function" then return end
    hooksecurefunc(bar, method, function(self, ...)
        if style() ~= "classic" or not RB.mod.active then return end
        guard(key, fn, self)
    end)
end

local installed = false

function Skin.Apply()
    local bar = Skin.Frame()
    if not bar then return end

    if not installed then
        installed = true
        -- Blizzard re-sets each of these on its own schedule -- the look on a
        -- style change, the fill atlas on every start, stop and finish, the
        -- spark and the glow on every cast. Each hook simply puts the old art
        -- back afterwards, and asks the setting first, so switching the style
        -- back needs no unhooking (a hook cannot be taken off anyway).
        hookMethod(bar, "SetLook", "cast.look", dress)
        hookMethod(bar, "UpdateShownState", "cast.shown", dress)
        hookMethod(bar, "UpdateBarFillTexture", "cast.fill", dressFill)
        hookMethod(bar, "ShowSpark", "cast.spark", function(b) dressSpark(b); hideFx(b) end)
        hookMethod(bar, "PlayFadeAnim", "cast.fade", dressFlash)
        hookMethod(bar, "PlayFinishAnim", "cast.finish", stopFinish)
        hookMethod(bar, "PlayInterruptAnims", "cast.interrupt", hideFx)
    end

    if style() == "classic" then guard("cast.dress", dress, bar) end
    Skin.LayoutExtras()
end

-- Switching away from classic.
--
-- THIS ONLY EVER RUNS IF WE DRESSED THE BAR FIRST. It used to run on every
-- settings change in the standard style as well, and since it force-feeds the
-- atlases it thinks the bar should have, it was REPAINTING a bar nobody had
-- touched: switching the icon or the cast time on was enough to leave the
-- client's own cast bar with the wrong fill, the wrong border and every
-- decoration forced back to full alpha. A style that promises to change
-- nothing about the bar must touch nothing about the bar.
--
-- Even for a bar we did dress, the atlases go back but Blizzard's own layout
-- numbers are not ours to restore -- so this says so instead of pretending.
function Skin.Restore()
    if not dressed then return end
    local bar = Skin.Frame()
    if not bar then return end
    dressed = false
    if not Skin.reloadHinted then
        Skin.reloadHinted = true
        ns:Print(ns.L["The cast bar keeps a little of the old style until you reload the interface."])
    end
    guard("cast.restore", function()
        if bar.Border and bar.Border.SetAtlas then bar.Border:SetAtlas("ui-castingbar-frame") end
        if bar.Spark and bar.Spark.SetAtlas then bar.Spark:SetAtlas("ui-castingbar-pip") end
        if bar.Flash and bar.Flash.SetAtlas then bar.Flash:SetAtlas("ui-castingbar-full-glow-standard") end
        if bar.Background and bar.Background.SetAtlas then bar.Background:SetAtlas("ui-castingbar-background") end
        for _, key in ipairs(FX) do
            if bar[key] then bar[key]:SetAlpha(1) end
        end
    end)
end
