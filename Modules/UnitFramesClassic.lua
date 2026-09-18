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
local NAMEBG = "Interface\\TargetingFrame\\UI-TargetingFrame-LevelBackground"
local WHITE = "Interface\\Buttons\\WHITE8X8"
-- Classic's combat swords (right half) and resting "zzz" (left half).
local STATE_ICON = "Interface\\CharacterFrame\\UI-StateIcon"
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
        unit = "player", side = "LEFT", sign = 1, art = PLAYER_ART, backdropH = 41,
        frame = pf, container = container, main = main,
        portrait = container and container.PlayerPortrait,
        mask     = container and container.PlayerPortraitMask,
        healthContainer = hc,
        health   = hc and hc.HealthBar,
        mana     = main and main.ManaBarArea and main.ManaBarArea.ManaBar,
        name     = _G.PlayerName,
        level    = _G.PlayerLevelText,
        status   = main and main.StatusTexture,
        healthMask = hc and hc.HealthBarMask,
        levelCircle = main and main.LevelBackgroundCircle,
        nameColor = { 1, 0.82, 0 },
        -- Blizzard's status text strings (TextStatusBar): the health pair
        -- sits on the container, the mana pair on the bar itself.
        healthLeft  = hc and hc.LeftText,
        healthRight = hc and hc.RightText,
        manaLeft    = main and main.ManaBarArea and main.ManaBarArea.ManaBar and main.ManaBarArea.ManaBar.LeftText,
        manaRight   = main and main.ManaBarArea and main.ManaBarArea.ManaBar and main.ManaBarArea.ManaBar.RightText,
        attackIcon  = contextual and contextual.AttackIcon,
        restLoop    = contextual and contextual.PlayerRestLoop,
        -- Retail's red "just lost" trail and the temp-max-health bar draw
        -- their own atlases over the bar; alpha only, they are frames. The
        -- rest flipbook goes the same way; our "zzz" follows its shown state.
        fade = {
            animatedLoss = hc and hc.PlayerFrameHealthBarAnimatedLoss,
            tempMaxLoss  = hc and hc.PlayerFrameTempMaxHealthLoss,
            restLoop     = contextual and contextual.PlayerRestLoop,
        },
        -- Keyed, not a list: a region missing on some build leaves a nil
        -- hole, and pairs walks past it where ipairs would stop.
        hide = {
            retailArt      = container and container.FrameTexture,
            altPowerArt    = container and container.AlternatePowerFrameTexture,
            vehicleArt     = container and container.VehicleFrameTexture,
            combatFlash    = container and container.FrameFlash,
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
        -- dx: the whole Classic layout sits 18 px further left than the art
        -- would put it, so it stays inside Edit Mode's selection box (inset
        -- 20 px from the frame edge); a drag on the ring found nothing
        -- (2026-09-18).
        unit = "target", side = "RIGHT", sign = -1, art = TARGET_ART, dx = -18, backdropH = 25,
        frame = tf, container = container, main = main,
        portrait = container and container.Portrait,
        mask     = container and container.PortraitMask,
        healthContainer = hc,
        health   = hc and hc.HealthBar,
        mana     = main and main.ManaBar,
        name     = main and main.Name,
        level    = main and main.LevelText,
        healthMask = hc and hc.HealthBarMask,
        levelCircle = main and main.LevelBackgroundCircle,
        nameColor = { 1, 1, 1 },
        healthLeft  = hc and hc.LeftText,
        healthRight = hc and hc.RightText,
        manaLeft    = main and main.ManaBar and main.ManaBar.LeftText,
        manaRight   = main and main.ManaBar and main.ManaBar.RightText,
        -- Blizzard's reaction-tinted strip becomes the Classic name box:
        -- CheckFaction keeps colouring it, we give it the Classic art and,
        -- for a player target, the class colour on top.
        nameBox  = main and main.ReputationColor,
        fade = { tempMaxLoss = hc and hc.TempMaxHealthLoss },
        hide = {
            retailArt   = container and container.FrameTexture,
            bossArt     = container and container.BossPortraitFrameTexture,
            threatFlash = container and container.Flash,
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
    if p.unit == "player" then
        -- Classic's "zzz" at the ring's foot; shown exactly when Blizzard
        -- shows its rest flipbook (which we fade), so no state is read.
        s.rest = host:CreateTexture(nil, "OVERLAY")
        s.rest:SetTexture(STATE_ICON)
        s.rest:SetTexCoord(0, 0.5, 0, 0.421875)
        s.rest:Hide()
    end
    own[p.frame] = s
    return s
end

local function syncRest(p)
    local s = own[p.frame]
    if s and s.rest and p.restLoop then s.rest:SetShown(p.restLoop:IsShown()) end
end

-- Blizzard's status text strings, once: our face at 10 px, outlined.
local fonted = setmetatable({}, { __mode = "k" })
local function fontText(fs, justify)
    if not fs or fonted[fs] then return end
    fonted[fs] = true
    ns.UI.Font(fs, 10, "OUTLINE")
    fs:SetJustifyH(justify)
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

-- Retail clips each fill with a rounded MaskTexture cut for the retail bar
-- (attached in OnLoadBase). Detach it from the fill and turn it into a
-- plain white square, so nothing of the Classic bar is clipped.
local function unmaskTexture(bar, mask)
    if not mask then return end
    local t = bar and bar.GetStatusBarTexture and bar:GetStatusBarTexture()
    if t and t.RemoveMaskTexture then pcall(t.RemoveMaskTexture, t, mask) end
    mask:SetTexture(WHITE, WRAP, WRAP)
    mask:Show()
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
        for _, fr in pairs(p.fade or {}) do fr:SetAlpha(0) end
        if p.status then
            p.status:SetTexture(nil)
            hideTexture(p.status)
        end
        if p.attackIcon then
            -- Blizzard keeps showing/hiding it; only the picture changes.
            p.attackIcon:SetTexture(STATE_ICON)
            p.attackIcon:SetTexCoord(0.5, 1, 0, 0.484375)
        end
        syncRest(p)
    end)
    guard(key .. ".level", function()
        -- Blizzard's round badge stays and moves to the ring's corner
        -- (Camelot anchors the level text to it at load; we anchor both).
        if p.levelCircle then
            p.levelCircle:SetAlpha(1)
            p.levelCircle:Show()
        end
    end)
    guard(key .. ".text", function()
        fontText(p.healthLeft, "LEFT")
        fontText(p.healthRight, "RIGHT")
        fontText(p.manaLeft, "LEFT")
        fontText(p.manaRight, "RIGHT")
    end)
    guard(key .. ".mask", function()
        if p.mask then p.mask:SetTexture(WHITE, WRAP, WRAP) end
        if p.health then unmaskTexture(p.health, p.healthMask) end
        if p.mana then unmaskTexture(p.mana, p.mana.ManaBarMask) end
    end)
    guard(key .. ".bars", function()
        if p.health then
            setBarTexture(p.health)
            -- Both health bars carry lockColor (TargetFrameStatusBarMixin:OnLoad,
            -- the player bar's XML OnLoad), so Blizzard never tints them and a
            -- plain UI-StatusBar would stay tan. Classic green first; the Extras
            -- layer puts a class colour on top only if its Classic toggle says so.
            p.health:SetStatusBarColor(0, 1, 0)
            if UF.Extras and UF.Extras.Recolor then UF.Extras.Recolor(p.health, p.unit) end
        end
        if p.mana then
            setBarTexture(p.mana)
            tintMana(p.mana)
        end
    end)
    guard(key .. ".name", function()
        if p.name then
            p.name:SetJustifyH("CENTER")
            local c = p.nameColor
            if c then p.name:SetTextColor(c[1], c[2], c[3]) end
        end
        if p.nameBox then
            p.nameBox:SetTexture(NAMEBG)
            p.nameBox:SetTexCoord(0, 1, 0, 1)
            p.nameBox:SetAlpha(1)
            p.nameBox:Show()
            -- After CheckFaction's reaction tint: a player target gets its
            -- class colour instead (the unit question lives in Extras).
            if UF.Extras and UF.Extras.ClassTint then
                local r, g, b = UF.Extras.ClassTint(p.unit)
                if r then p.nameBox:SetVertexColor(r, g, b) end
            end
        end
    end)
end

------------------------------------------------------------------------------
-- Layout: every SetPoint / SetSize / ClearAllPoints, out of combat only.
-- Anchors relative to the Blizzard root frame, as the Classic XML had them;
-- `sign` flips the x offsets for the target, `side` the anchor edge.
--
-- Idempotent on purpose: the hooks fire on every target change (and Edit
-- Mode's enter targets the player, which runs both of them), so a region
-- that already sits where we want it is left alone -- no ClearAllPoints /
-- SetPoint churn on a protected frame for nothing. Only what Blizzard
-- actually moved back gets re-anchored.
------------------------------------------------------------------------------

-- GetPoint on a region Blizzard anchored from its secure environment (the
-- status text strings) answers with SECRET values on this client (seen
-- 2026-09-18: "attempt to compare local 'cp' (a secret string value)").
-- An anchor we cannot read counts as "different", so the region is simply
-- re-anchored -- a widget call, which is allowed.
local function samePoint(region, i, point, rel, relPoint, x, y)
    local cp, cr, crp, cx, cy = region:GetPoint(i)
    if not (ns.CanRead(cp) and ns.CanRead(crp) and ns.CanRead(cx) and ns.CanRead(cy)) then
        return false
    end
    return cp == point and cr == rel and crp == relPoint
        and math.abs((cx or 0) - x) < 0.01 and math.abs((cy or 0) - y) < 0.01
end

-- One or two anchors plus an optional size; touches the region only when
-- something differs from the wanted state.
local function place(region, w, h, p1, r1, rp1, x1, y1, p2, r2, rp2, x2, y2)
    local want = p2 and 2 or 1
    local n = region:GetNumPoints()
    local same = ns.CanRead(n) and n == want
        and samePoint(region, 1, p1, r1, rp1, x1, y1)
        and (not p2 or samePoint(region, 2, p2, r2, rp2, x2, y2))
    if not same then
        region:ClearAllPoints()
        region:SetPoint(p1, r1, rp1, x1, y1)
        if p2 then region:SetPoint(p2, r2, rp2, x2, y2) end
    end
    if w then
        local cw, ch = region:GetSize()
        if not (ns.CanRead(cw) and ns.CanRead(ch))
            or math.abs((cw or 0) - w) > 0.01 or math.abs((ch or 0) - h) > 0.01 then
            region:SetSize(w, h)
        end
    end
end

-- `barsOnly`: what Blizzard's CheckClassification puts back on every target
-- change (health container anchor and size). Portrait, mask, name and level
-- are placed once at Enable and after the player art switches.
local function layout(p, barsOnly)
    local key, f, sign, side = p.unit, p.frame, p.sign, p.side
    local dx = p.dx or 0
    local topSide, bottomSide = "TOP" .. side, "BOTTOM" .. side

    guard(key .. ".art", function()
        local s, a = skinFor(p), p.art
        place(s.art, a.w, a.h, "CENTER", f, "CENTER", a.x + dx, a.y)
        place(s.backdrop, 119, p.backdropH or 41, topSide, f, topSide, sign * 89.5 + dx, -26)
    end)
    guard(key .. ".health", function()
        local hc = p.healthContainer
        if not hc then return end
        place(hc, 119, 12, topSide, f, topSide, sign * 90 + dx, -45)
        if p.health then
            -- Single anchor plus an explicit size, as Blizzard has it; the
            -- player art switches set the height by hand and the hook on
            -- them puts 12 back.
            place(p.health, 119, 12, "TOPLEFT", hc, "TOPLEFT", 0, 0)
            if p.healthLeft  then place(p.healthLeft,  nil, nil, "LEFT",  p.health, "LEFT",  4, 0) end
            if p.healthRight then place(p.healthRight, nil, nil, "RIGHT", p.health, "RIGHT", -4, 0) end
            if p.healthMask then
                place(p.healthMask, nil, nil,
                    "TOPLEFT", p.health, "TOPLEFT", -4, 4,
                    "BOTTOMRIGHT", p.health, "BOTTOMRIGHT", 4, -4)
            end
        end
    end)
    guard(key .. ".mana", function()
        if not p.mana then return end
        place(p.mana, 119, 12, topSide, f, topSide, sign * 90 + dx, -56)
        if p.manaLeft  then place(p.manaLeft,  nil, nil, "LEFT",  p.mana, "LEFT",  4, 0) end
        if p.manaRight then place(p.manaRight, nil, nil, "RIGHT", p.mana, "RIGHT", -4, 0) end
        if p.mana.ManaBarMask then
            place(p.mana.ManaBarMask, nil, nil,
                "TOPLEFT", p.mana, "TOPLEFT", -4, 4,
                "BOTTOMRIGHT", p.mana, "BOTTOMRIGHT", 4, -4)
        end
    end)
    if barsOnly then return end

    guard(key .. ".portrait", function()
        if not p.portrait then return end
        place(p.portrait, 64, 64, topSide, f, topSide, sign * 24 + dx, -16)
        if p.mask then
            -- Square, grown 4 px each side; the art's ring hides the corners.
            place(p.mask, nil, nil,
                "TOPLEFT", p.portrait, "TOPLEFT", -4, 4,
                "BOTTOMRIGHT", p.portrait, "BOTTOMRIGHT", 4, -4)
        end
    end)
    guard(key .. ".name", function()
        if p.name then
            place(p.name, 100, 12, "CENTER", f, "CENTER", sign * 34 + dx, 15)
        end
        if p.nameBox then
            place(p.nameBox, 119, 19, topSide, f, topSide, sign * 90 + dx, -26)
        end
    end)
    guard(key .. ".level", function()
        if p.levelCircle then
            place(p.levelCircle, nil, nil, "CENTER", f, bottomSide, sign * 35.25 + dx, 30)
        end
        if p.level then
            place(p.level, nil, nil, "CENTER", f, bottomSide, sign * 35.25 + dx, 30)
        end
    end)
    guard(key .. ".status", function()
        -- Combat swords and "zzz" at the ring's foot, as Classic drew them.
        if p.attackIcon then
            place(p.attackIcon, 32, 32, "TOPLEFT", f, "TOPLEFT", 20.5, -52)
        end
        local s = own[f]
        if s and s.rest then
            place(s.rest, 31, 33, "TOPLEFT", f, "TOPLEFT", 19.5, -52)
        end
    end)
end

------------------------------------------------------------------------------
-- Relayout = paint now, layout now or after combat. One PLAYER_REGEN_ENABLED
-- waiter for both frames; the registry refuses a second registration of the
-- same handler, so a hook firing ten times in a fight arms it once. A
-- deferred layout is always the full one -- idempotent, so it costs nothing
-- extra.
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

-- `scope`: nil = paint and full layout; "paint" = textures only (CheckFaction
-- changes colours, never positions); "bars" = paint plus the bar layout
-- CheckClassification undoes.
local function relayoutTarget(scope)
    if not active then return end
    local p = targetParts()
    if not p then return end
    paint(p)
    if scope == "paint" then return end
    if ns:InCombat() then
        pendingTarget = true
        ns:RegisterEventOnce("PLAYER_REGEN_ENABLED", onRegen)
        return
    end
    layout(p, scope == "bars")
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

    -- Resting / combat: Blizzard toggles its flipbook here; ours follows.
    if type(_G.PlayerFrame_UpdateStatus) == "function" then
        hooksecurefunc("PlayerFrame_UpdateStatus", function()
            if not active then return end
            local p = playerParts()
            if p then guard("player.rest", syncRest, p) end
        end)
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

    -- Every target change runs both: CheckClassification puts the retail
    -- atlas and anchor back on the health container (bars layout again),
    -- CheckFaction only recolours the portrait and the name strip (textures
    -- only, nothing to re-anchor).
    local tf = _G.TargetFrame
    if tf then
        if type(tf.CheckClassification) == "function" then
            hooksecurefunc(tf, "CheckClassification", function() relayoutTarget("bars") end)
        end
        if type(tf.CheckFaction) == "function" then
            hooksecurefunc(tf, "CheckFaction", function() relayoutTarget("paint") end)
        end
    end
end

------------------------------------------------------------------------------
-- Public
------------------------------------------------------------------------------

-- Blizzard's own status text, always on, percent + value: the two CVars
-- TextStatusBar.lua reads (`statusText` via the bar's `cvar`, and
-- `statusTextDisplay`). Display mode first, so the CVAR_UPDATE for the
-- second one repaints every bar with it. Never restored: it is the user's
-- setting from here on, changeable in Blizzard's options.
local function applyStatusTextCVars()
    if not (mod and mod.db and mod.db.classicStatusText) then return end
    if ns:InCombat() then return end
    guard("statustext.cvars", function()
        SetCVar("statusTextDisplay", "BOTH")
        SetCVar("statusText", "1")
    end)
end

function Classic.Enable(m)
    mod, active = m, true
    installHooks()
    applyStatusTextCVars()
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
        if s.rest then s.rest:Hide() end
    end
end

function Classic.IsActive()
    return active
end
