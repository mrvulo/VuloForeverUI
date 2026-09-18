-- VuloForeverUI / Modules / UnitFramesClassic
--
-- The Classic look as a RESKIN of Blizzard's PlayerFrame and TargetFrame:
-- the original UI-TargetingFrame art laid over the frame, Blizzard's own
-- portrait, bars, name and level moved to the Classic coordinates, the
-- retail chrome hidden. Blizzard's untainted code keeps driving every bar,
-- text, aura and the target cast bar -- in combat too. Nothing here reads a
-- unit value except UnitClassification("target") for the art file.
--
-- Rules this file lives by:
--   * widget calls and hooksecurefunc only -- no Lua field is ever written
--     into a Blizzard frame table; our regions sit in the weak side table
--     `own` below;
--   * textures we replace get Hide() AND SetAlpha(0): Blizzard's Show()
--     brings them back, the alpha keeps them invisible;
--   * frames on protected templates (…ContentMain, HealthBarsContainer, the
--     bars) are never hidden or reparented; their points and sizes change
--     out of combat only, everything positional waits for
--     PLAYER_REGEN_ENABLED when a hook fires mid-fight;
--   * every group of calls sits in a pcall so one refused call cannot abort
--     the rest, and a refusal is reported once per region per session.
--
-- Draw order, checked against Forever's Mainline/PlayerFrame.xml and
-- TargetFrame.xml: the root frame holds two full-size children at the same
-- level -- the Container (portrait on BACKGROUND, retail frame art, the
-- threat flash) and the Content frame whose ContentMain (bars, name, level)
-- and ContentContextual (auras, icons) sit one level higher. Our art is a
-- BORDER texture on the Container: above the portrait, below every bar,
-- text, aura and icon, and below the class icon the Extras layer puts on the
-- Container's OVERLAY. No frame level of any Blizzard frame is touched.
local _, ns = ...
ns.UF = ns.UF or {}
local UF = ns.UF

UF.Classic = {}
local Classic = UF.Classic

local ART = "Interface\\TargetingFrame\\UI-TargetingFrame"
local ART_BY_CLASS = {
    elite     = ART .. "-Elite",
    worldboss = ART .. "-Elite",
    rare      = ART .. "-Rare",
    rareelite = ART .. "-Rare-Elite",
}
local BAR   = "Interface\\TargetingFrame\\UI-StatusBar"
local WHITE = "Interface\\Buttons\\WHITE8X8"
local WRAP  = "CLAMPTOBLACKADDITIVE"

-- The art as Blizzard's Classic XML cut it: the player mirrored (left > right).
local PLAYER_ART = { coords = { 0.85546875, 0.1015625, 0.0625, 0.6640625 }, w = 193, h = 77, x = 0,    y = 0 }
local TARGET_ART = { coords = { 0.1015625, 1.0, 0.0078125, 0.78125 },      w = 230, h = 99, x = 18.5, y = -4 }

local active, mod = false, nil
local own = setmetatable({}, { __mode = "k" })   -- Blizzard frame -> { art, backdrop }
local pendingPlayer, pendingTarget = false, false
local reported = {}

------------------------------------------------------------------------------
-- Blizzard's frame tree, nil-safe. A key that is missing on some build must
-- never throw; the region is simply left alone.
------------------------------------------------------------------------------

local function playerParts()
    local pf = _G.PlayerFrame
    if not pf then return nil end
    local container  = pf.PlayerFrameContainer
    local content    = pf.PlayerFrameContent
    local main       = content and content.PlayerFrameContentMain
    local contextual = content and content.PlayerFrameContentContextual
    local hc         = main and main.HealthBarsContainer
    return {
        unit = "player", side = "LEFT", sign = 1, art = PLAYER_ART,
        frame = pf, container = container, main = main,
        portrait = container and container.PlayerPortrait,
        mask     = container and container.PlayerPortraitMask,
        healthContainer = hc,
        health   = hc and hc.HealthBar,
        mana     = main and main.ManaBarArea and main.ManaBarArea.ManaBar,
        name     = _G.PlayerName,
        level    = _G.PlayerLevelText,
        status   = main and main.StatusTexture,
        -- Keyed, not a list: a region missing on some build leaves a nil
        -- hole, and pairs walks past it where ipairs would stop.
        hide = {
            retailArt      = container and container.FrameTexture,
            altPowerArt    = container and container.AlternatePowerFrameTexture,
            vehicleArt     = container and container.VehicleFrameTexture,
            combatFlash    = container and container.FrameFlash,
            levelCircle    = main and main.LevelBackgroundCircle,
            portraitCorner = contextual and contextual.PlayerPortraitCornerIcon,
        },
    }
end

local function targetParts()
    local tf = _G.TargetFrame
    if not tf then return nil end
    local container = tf.TargetFrameContainer
    local content   = tf.TargetFrameContent
    local main      = content and content.TargetFrameContentMain
    local hc        = main and main.HealthBarsContainer
    return {
        unit = "target", side = "RIGHT", sign = -1, art = TARGET_ART,
        frame = tf, container = container, main = main,
        portrait = container and container.Portrait,
        mask     = container and container.PortraitMask,
        healthContainer = hc,
        health   = hc and hc.HealthBar,
        mana     = main and main.ManaBar,
        name     = main and main.Name,
        level    = main and main.LevelText,
        hide = {
            retailArt       = container and container.FrameTexture,
            bossArt         = container and container.BossPortraitFrameTexture,
            threatFlash     = container and container.Flash,
            levelCircle     = main and main.LevelBackgroundCircle,
            reputationColor = main and main.ReputationColor,
        },
    }
end

------------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------------

-- One pcall per region group: a refused call (a protected frame that turned
-- out to be locked after all) skips that group only, and is said once.
local function guard(key, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok and not reported[key] then
        reported[key] = true
        ns:Print("Classic reskin: %s could not be applied (%s)", key, tostring(err))
    end
    return ok
end

local function hideTexture(t)
    if not t then return end
    t:Hide()
    t:SetAlpha(0)
end

local function artFile(p)
    if p.unit == "player" then
        return (mod and mod.db and mod.db.playerElite) and ART_BY_CLASS.elite or ART
    end
    local c = UnitClassification("target")
    if ns.CanRead and not ns.CanRead(c) then c = nil end
    return (c and ART_BY_CLASS[c]) or ART
end

-- Our two regions per frame, created once on Blizzard's Container frame.
local function skinFor(p)
    local s = own[p.frame]
    if s then return s end
    local host = p.container or p.frame
    s = {
        art      = host:CreateTexture(nil, "BORDER"),
        backdrop = host:CreateTexture(nil, "BACKGROUND", nil, -8),
    }
    s.backdrop:SetColorTexture(0, 0, 0, 0.5)
    own[p.frame] = s
    return s
end

-- A plain UI-StatusBar is white; Blizzard's atlas bars carry their colour in
-- the art and get SetStatusBarColor(1, 1, 1). The power token Blizzard wrote
-- onto the bar in UnitFrameManaBar_UpdateType names the Classic colour.
local function tintMana(bar)
    local colors = _G.PowerBarColor
    if not colors then return end
    local info = colors[bar.powerToken] or colors[bar.powerType]
    if info and info.r then bar:SetStatusBarColor(info.r, info.g, info.b) end
end

local function setBarTexture(bar)
    bar:SetStatusBarTexture(BAR)
    local t = bar:GetStatusBarTexture()
    if t and t.SetTexCoord then t:SetTexCoord(0, 1, 0, 1) end
end

------------------------------------------------------------------------------
-- Paint: textures, alpha, colours. Nothing positional, so it may run in
-- combat -- a new target mid-fight gets its art and bar texture at once.
------------------------------------------------------------------------------

local function paint(p)
    local key = p.unit
    guard(key .. ".art", function()
        local s = skinFor(p)
        local c = p.art.coords
        s.art:SetTexture(artFile(p))
        s.art:SetTexCoord(c[1], c[2], c[3], c[4])
        s.art:Show()
        s.backdrop:Show()
    end)
    guard(key .. ".chrome", function()
        for _, t in pairs(p.hide) do hideTexture(t) end
        if p.status then
            p.status:SetTexture(nil)
            hideTexture(p.status)
        end
    end)
    guard(key .. ".mask", function()
        if p.mask then p.mask:SetTexture(WHITE, WRAP, WRAP) end
    end)
    guard(key .. ".bars", function()
        if p.health then setBarTexture(p.health) end
        if p.mana then
            setBarTexture(p.mana)
            tintMana(p.mana)
        end
    end)
    guard(key .. ".name", function()
        if p.name then p.name:SetJustifyH("CENTER") end
    end)
end

------------------------------------------------------------------------------
-- Layout: every SetPoint / SetSize / ClearAllPoints, out of combat only.
-- Anchors relative to the Blizzard root frame, as the Classic XML had them;
-- `sign` flips the x offsets for the target, `side` the anchor edge.
------------------------------------------------------------------------------

local function layout(p)
    local key, f, sign, side = p.unit, p.frame, p.sign, p.side
    local topSide, bottomSide = "TOP" .. side, "BOTTOM" .. side

    guard(key .. ".art", function()
        local s, a = skinFor(p), p.art
        s.art:ClearAllPoints()
        s.art:SetSize(a.w, a.h)
        s.art:SetPoint("CENTER", f, "CENTER", a.x, a.y)
        s.backdrop:ClearAllPoints()
        s.backdrop:SetSize(119, 41)
        s.backdrop:SetPoint(topSide, f, topSide, sign * 89.5, -26)
    end)
    guard(key .. ".portrait", function()
        if not p.portrait then return end
        p.portrait:ClearAllPoints()
        p.portrait:SetSize(64, 64)
        p.portrait:SetPoint(topSide, f, topSide, sign * 24, -16)
        if p.mask then
            -- Square, grown 4 px each side; the art's ring hides the corners.
            p.mask:ClearAllPoints()
            p.mask:SetPoint("TOPLEFT", p.portrait, "TOPLEFT", -4, 4)
            p.mask:SetPoint("BOTTOMRIGHT", p.portrait, "BOTTOMRIGHT", 4, -4)
        end
    end)
    guard(key .. ".health", function()
        local hc = p.healthContainer
        if not hc then return end
        hc:ClearAllPoints()
        hc:SetSize(119, 12)
        hc:SetPoint(topSide, f, topSide, sign * 90, -45)
        if p.health then
            -- Blizzard anchors the bar TOPLEFT only and sets its height by
            -- hand in the art switches; two anchors make it follow the
            -- container no matter what height is set on it afterwards.
            p.health:ClearAllPoints()
            p.health:SetPoint("TOPLEFT", hc, "TOPLEFT", 0, 0)
            p.health:SetPoint("BOTTOMRIGHT", hc, "BOTTOMRIGHT", 0, 0)
        end
    end)
    guard(key .. ".mana", function()
        if not p.mana then return end
        p.mana:ClearAllPoints()
        p.mana:SetSize(119, 12)
        p.mana:SetPoint(topSide, f, topSide, sign * 90, -56)
    end)
    guard(key .. ".name", function()
        if not p.name then return end
        p.name:ClearAllPoints()
        p.name:SetSize(100, 12)
        p.name:SetPoint("CENTER", f, "CENTER", sign * 34, 15)
    end)
    guard(key .. ".level", function()
        if not p.level then return end
        p.level:ClearAllPoints()
        p.level:SetPoint("CENTER", f, bottomSide, sign * 35.25, 30)
    end)
end

------------------------------------------------------------------------------
-- Relayout = paint now, layout now or after combat. One PLAYER_REGEN_ENABLED
-- waiter for both frames; the registry refuses a second registration of the
-- same handler, so a hook firing ten times in a fight arms it once.
------------------------------------------------------------------------------

local onRegen

local function relayoutPlayer()
    if not active then return end
    local p = playerParts()
    if not p then return end
    paint(p)
    if ns:InCombat() then
        pendingPlayer = true
        ns:RegisterEventOnce("PLAYER_REGEN_ENABLED", onRegen)
        return
    end
    layout(p)
end

local function relayoutTarget()
    if not active then return end
    local p = targetParts()
    if not p then return end
    paint(p)
    if ns:InCombat() then
        pendingTarget = true
        ns:RegisterEventOnce("PLAYER_REGEN_ENABLED", onRegen)
        return
    end
    layout(p)
end

onRegen = function()
    local doPlayer, doTarget = pendingPlayer, pendingTarget
    pendingPlayer, pendingTarget = false, false
    if not active then return end
    if doPlayer then relayoutPlayer() end
    if doTarget then relayoutTarget() end
end

------------------------------------------------------------------------------
-- Hooks: installed once, every body gated on `active`. All seven names were
-- checked in Forever's Blizzard_UnitFrame (Mainline/PlayerFrame.lua,
-- Mainline/UnitFrame.lua, Mainline/TargetFrame.lua).
------------------------------------------------------------------------------

local hooked = false

local function installHooks()
    if hooked then return end
    hooked = true

    -- Player art switches re-anchor the bars, the name and the status glow.
    for _, name in ipairs({
        "PlayerFrame_ToPlayerArt",
        "PlayerFrame_ToVehicleArt",
        "PlayerFrame_UpdateArt",
        "PlayerFrame_UpdatePlayerNameTextAnchor",
    }) do
        if type(_G[name]) == "function" then
            hooksecurefunc(name, relayoutPlayer)
        end
    end

    -- Power type changes put the retail atlas back on the mana bar.
    if type(_G.UnitFrameManaBar_UpdateType) == "function" then
        hooksecurefunc("UnitFrameManaBar_UpdateType", function(bar)
            if not active or not bar then return end
            local pp, tp = playerParts(), targetParts()
            if (pp and bar == pp.mana) or (tp and bar == tp.mana) then
                guard("manabar.type", function()
                    setBarTexture(bar)
                    tintMana(bar)
                end)
            end
        end)
    end

    -- Every target change runs CheckFaction, and CheckClassification resets
    -- the health container's anchor and the health bar's atlas.
    local tf = _G.TargetFrame
    if tf then
        for _, method in ipairs({ "CheckClassification", "CheckFaction" }) do
            if type(tf[method]) == "function" then
                hooksecurefunc(tf, method, relayoutTarget)
            end
        end
    end
end

------------------------------------------------------------------------------
-- Public
------------------------------------------------------------------------------

function Classic.Enable(m)
    mod, active = m, true
    installHooks()
    relayoutPlayer()
    relayoutTarget()
end

-- Hides our art only. Blizzard's regions stay where we put them and the
-- hooks stay installed (gated off); the module asks for a reload.
function Classic.Disable()
    active = false
    pendingPlayer, pendingTarget = false, false
    for _, s in pairs(own) do
        s.art:Hide()
        s.backdrop:Hide()
    end
end

function Classic.IsActive()
    return active
end
