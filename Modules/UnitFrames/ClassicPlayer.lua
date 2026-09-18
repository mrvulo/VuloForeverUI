-- VuloForeverUI / Modules / UnitFrames / ClassicPlayer
--
-- The player frame of the Classic style, vehicle art included: a port of the
-- second reference's player skin. Numbers and region paths are the
-- reference's; see UnitFramesClassic.lua for the rules the port adds (active
-- gate, side table instead of fields, paint / layout split, secret guards).
--
-- Region paths checked against Forever's Blizzard_UnitFrame:
--   Mainline/PlayerFrame.xml  :23 PlayerFrameContainer (:26 PlayerPortrait,
--     :32 PlayerPortraitMask, :43 VehicleFrameTexture, :48 FrameTexture,
--     :53 AlternatePowerFrameTexture, :60 FrameFlash), :70 ContentMain
--     (:83 StatusTexture, :102 LevelBackgroundCircle, :111 HitIndicator,
--     :122 HealthBarsContainer with :165 AnimatedLoss, :171 HealthBar,
--     :219/:224 LeftText/RightText, :231 HealthBarMask; :251 ManaBarArea,
--     :253 ManaBar, :264 FeedbackFrame, :265 FullPowerFrame, :294 ManaBarMask),
--     :322 ContentContextual (:326 LeaderIcon, :331 GuideIcon, :336 RoleIcon,
--     :343 AttackIcon, :348 PlayerPortraitCornerIcon, :377 PvpTimerText,
--     :394 PlayerRestLoop, :435 GroupIndicator)
--   Mainline/BuilderSpenderFrame.xml  :6 BarTexture, :9 LossGlowTexture,
--     :12 GainGlowTexture (the mana bar's FeedbackFrame)
--   `TextString` is the field TextStatusBar keeps for the main text
--     (Mainline/TargetFrame.lua:410 and :1172 use it the same way).
--   Hooked globals, Mainline/PlayerFrame.lua: :275 UpdatePlayerNameTextAnchor,
--     :301 UpdateLevel, :314 UpdatePartyLeader, :415 UpdateRolesAssigned,
--     :474 UpdateStatus, :508 UpdatePlayerRestLoop, :566 ToVehicleArt,
--     :654 ToPlayerArt; Camelot/PlayerFrame.lua:70 UpdatePvPStatus.
local _, ns = ...
local UF = ns.UF
local Classic = UF.Classic

local BAR       = Classic.BAR
local ART       = "Interface\\TargetingFrame\\UI-TargetingFrame"
local STATE     = "Interface\\CharacterFrame\\UI-StateIcon"
local GROUP_ART = "Interface\\CharacterFrame\\UI-CharacterFrame-GroupIndicator"
local ROLES     = "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES"
local VEHICLE_FLASH = "Interface\\Vehicles\\UI-Vehicle-Frame-Flash"

local overlay                     -- our button on PlayerFrame
local icons                       -- our rest / attack textures
local glowOn = { attack = false, rest = false }
local pulse                       -- our OnUpdate frame for the glow pulse
local isSetUp = false

-- Blizzard's tree, nil-safe down to the branches; a missing leaf is caught by
-- the pcall around the block that wants it.
local function parts()
    local pf = _G.PlayerFrame
    if not pf then return nil end
    local container = pf.PlayerFrameContainer
    local content   = pf.PlayerFrameContent
    local main      = content and content.PlayerFrameContentMain
    local ctx       = content and content.PlayerFrameContentContextual
    local hc        = main and main.HealthBarsContainer
    local mba       = main and main.ManaBarArea
    if not (container and main and ctx and hc and mba and hc.HealthBar and mba.ManaBar) then
        return nil
    end
    return {
        frame = pf, container = container, main = main, ctx = ctx,
        hc = hc, hb = hc.HealthBar, mba = mba, mb = mba.ManaBar,
        status = main.StatusTexture, flash = container.FrameFlash,
    }
end

local function inVehicle()
    return Classic.Readable(UnitHasVehiclePlayerFrameUI("player")) and true or false
end

-- Our one addition to the reference: the option that gives the player the
-- elite dragon. Same cut, same mirror, other file.
local function artFile()
    local m = Classic.Mod()
    return (m and m.db and m.db.playerElite) and (ART .. "-Elite") or ART
end

------------------------------------------------------------------------------
-- Player art (reference: its PlayerFrame_ToPlayerArt hook)
------------------------------------------------------------------------------

local function playerArt()
    local p = parts()
    if not p or not overlay then return end

    Classic.Guard("player.art", function()
        local art = artFile()
        local ft = p.container.FrameTexture
        ft:SetTexture(art)
        ft:SetTexCoord(1, 0.09375, 0, 0.78125)
        ft:SetDrawLayer("BORDER")
        local apt = p.container.AlternatePowerFrameTexture
        apt:SetTexture(art)
        apt:SetTexCoord(1, 0.09375, 0, 0.78125)

        p.flash:SetTexture(ART .. "-Flash")
        p.flash:SetTexCoord(0.9453125, 0, 0, 0.181640625)
        p.flash:SetDrawLayer("BACKGROUND")

        p.status:SetTexture("Interface\\CharacterFrame\\UI-Player-Status")
        p.status:SetTexCoord(0, 0.74609375, 0, 0.53125)
        p.status:SetBlendMode("ADD")
    end)

    overlay.unit = "player"
    Classic.Guard("player.feed", Classic.UpdateFrame, overlay)

    Classic.Layout("player.art.layout", function()
        -- The second anchor pins 232 x 100 whatever anyone does to the size.
        -- Nothing in Forever resizes these two today -- unlike the target's,
        -- PlayerFrame_ToPlayerArt sets the atlas WITHOUT UseAtlasSize
        -- (Mainline/PlayerFrame.lua:673) -- so this is insurance: the art can
        -- never drift off the overlay, which has the same TOPLEFT.
        local ft = p.container.FrameTexture
        ft:SetSize(232, 100)
        ft:ClearAllPoints()
        ft:SetPoint("TOPLEFT", -19, -4)
        ft:SetPoint("BOTTOMRIGHT", p.container, "TOPLEFT", 213, -104)
        local apt = p.container.AlternatePowerFrameTexture
        apt:SetSize(232, 100)
        apt:ClearAllPoints()
        apt:SetPoint("TOPLEFT", -19, -4)
        apt:SetPoint("BOTTOMRIGHT", p.container, "TOPLEFT", 213, -104)

        p.flash:SetParent(p.frame)
        p.flash:SetSize(242, 93)
        p.flash:ClearAllPoints()
        p.flash:SetPoint("TOPLEFT", -6, -4)

        p.status:SetParent(p.ctx)
        p.status:SetSize(190, 66)
        p.status:ClearAllPoints()
        p.status:SetPoint("TOPLEFT", 16, -12)

        overlay.HealthBar:SetWidth(119)
        overlay.HealthBar:SetPoint("TOPLEFT", 106, -41)
        overlay.ManaBar:SetWidth(119)
        overlay.ManaBar:SetPoint("TOPLEFT", 106, -52)
        overlay.Background:SetSize(119, 41)

        local hb, hc, mb = p.hb, p.hc, p.mb
        hb.TextString:SetPoint("CENTER", hc, "CENTER")
        hb.LeftText:SetPoint("LEFT", hc, "LEFT", 6, 0)
        hb.RightText:SetPoint("RIGHT", hc, "RIGHT", -4, 0)

        for _, key in ipairs({ "MyHealPredictionBar", "OtherHealPredictionBar", "HealAbsorbBar", "TotalAbsorbBar" }) do
            local seg = hb[key]
            if seg then
                seg:SetParent(overlay.HealthBar)
                seg:ClearAllPoints()
                seg:SetAllPoints(overlay.HealthBar)
            end
        end

        hb.OverAbsorbGlow:ClearAllPoints()
        hb.OverAbsorbGlow:SetPoint("TOPLEFT", overlay.HealthBar, "TOPRIGHT", -7, 0)
        hb.OverAbsorbGlow:SetPoint("BOTTOMLEFT", overlay.HealthBar, "BOTTOMRIGHT", -7, 0)
        hb.OverHealAbsorbGlow:ClearAllPoints()
        hb.OverHealAbsorbGlow:SetPoint("BOTTOMRIGHT", overlay.HealthBar, "BOTTOMLEFT", 7, 0)
        hb.OverHealAbsorbGlow:SetPoint("TOPRIGHT", overlay.HealthBar, "TOPLEFT", 7, 0)

        local loss = hc.PlayerFrameHealthBarAnimatedLoss
        if loss then
            loss:SetParent(overlay.HealthBar)
            loss:ClearAllPoints()
            loss:SetAllPoints(overlay.HealthBar)
        end

        mb.TextString:SetPoint("CENTER", mb, "CENTER", 0, 3)
        mb.LeftText:SetPoint("LEFT", mb, "LEFT", 6, 3)
        mb.RightText:SetPoint("RIGHT", mb, "RIGHT", -4, 3)

        if mb.FeedbackFrame then
            mb.FeedbackFrame:SetParent(overlay.ManaBar)
            mb.FeedbackFrame:ClearAllPoints()
            mb.FeedbackFrame:SetAllPoints(overlay.ManaBar)
        end
        if mb.FullPowerFrame then
            mb.FullPowerFrame:SetParent(overlay.ManaBar)
            mb.FullPowerFrame:SetSize(119, 12)
            mb.FullPowerFrame:ClearAllPoints()
            mb.FullPowerFrame:SetPoint("TOPRIGHT", overlay.ManaBar, "TOPRIGHT")
        end

        p.ctx.GroupIndicator:ClearAllPoints()
        p.ctx.GroupIndicator:SetPoint("BOTTOMLEFT", overlay, "TOPLEFT", 97, -20)
        p.ctx.RoleIcon:SetPoint("TOPLEFT", 76, -19)

        if _G.PlayerLevelText then _G.PlayerLevelText:Show() end
    end)
end

------------------------------------------------------------------------------
-- Vehicle art (reference: its PlayerFrame_ToVehicleArt hook)
------------------------------------------------------------------------------

local function vehicleArt()
    local p = parts()
    if not p or not overlay then return end

    Classic.Guard("player.vehicle", function()
        local vt = p.container.VehicleFrameTexture
        vt:SetTexture("Interface\\Vehicles\\UI-Vehicle-Frame")
        vt:SetDrawLayer("BORDER")

        p.flash:SetTexture(VEHICLE_FLASH)
        p.flash:SetTexCoord(-0.02, 1, 0.07, 0.86)
        p.flash:SetDrawLayer("BACKGROUND")

        p.status:SetTexture(VEHICLE_FLASH)
        p.status:SetTexCoord(-0.02, 1, 0.07, 0.86)
        p.status:SetDrawLayer("BACKGROUND")
    end)

    overlay.unit = "vehicle"
    Classic.Guard("player.feed", Classic.UpdateFrame, overlay)

    Classic.Layout("player.art.layout", function()
        local vt = p.container.VehicleFrameTexture
        vt:SetSize(240, 120)
        vt:ClearAllPoints()
        vt:SetPoint("TOPLEFT", -3, 6)

        p.flash:SetParent(p.frame)
        p.flash:SetSize(242, 93)
        p.flash:ClearAllPoints()
        p.flash:SetPoint("TOPLEFT", -6, -4)

        p.status:SetParent(p.frame)
        p.status:SetSize(242, 93)
        p.status:ClearAllPoints()
        p.status:SetPoint("TOPLEFT", -6, -4)

        overlay.HealthBar:SetWidth(100)
        overlay.HealthBar:SetPoint("TOPLEFT", 119, -41)
        overlay.ManaBar:SetWidth(100)
        overlay.ManaBar:SetPoint("TOPLEFT", 119, -52)
        overlay.Background:SetSize(114, 41)

        local hb, hc, mb = p.hb, p.hc, p.mb
        hb.TextString:SetPoint("CENTER", hc, "CENTER", -2, -1)
        hb.LeftText:SetPoint("LEFT", hc, "LEFT", 0, -2)
        hb.RightText:SetPoint("RIGHT", hc, "RIGHT", -9, -2)

        mb.TextString:SetPoint("CENTER", mb, "CENTER", -2, 3)
        mb.LeftText:SetPoint("LEFT", mb, "LEFT", 0, 3)
        mb.RightText:SetPoint("RIGHT", mb, "RIGHT", -4, 3)

        p.ctx.GroupIndicator:ClearAllPoints()
        p.ctx.GroupIndicator:SetPoint("BOTTOMLEFT", overlay, "TOPLEFT", 97, -13)
        p.ctx.RoleIcon:SetPoint("TOPLEFT", 76, -19)

        local name = _G.PlayerName
        if name then
            name:SetParent(p.container)
            name:ClearAllPoints()
            name:SetPoint("TOPLEFT", p.container, "TOPLEFT", 97, -26)
        end

        if _G.PlayerLevelText then _G.PlayerLevelText:Hide() end
    end)
end

-- Both arts share one layout key: whichever ran last is the one to replay.
local function applyArt()
    if inVehicle() then vehicleArt() else playerArt() end
end

------------------------------------------------------------------------------
-- The smaller hooks
------------------------------------------------------------------------------

local function updateLevel()
    local p, level = parts(), _G.PlayerLevelText
    if not p or not level then return end
    Classic.Guard("player.level", function()
        level:SetDrawLayer("ARTWORK")
        level:SetFontObject(GameNormalNumberFont)
        level:SetVertexColor(1.0, 0.82, 0.0, 1.0)
    end)
    Classic.Layout("player.level.layout", function()
        level:SetParent(p.ctx)
        level:ClearAllPoints()
        level:SetPoint("CENTER", -80, -21)
    end)
end

local function updatePartyLeader()
    local p = parts()
    if not p then return end
    local leader, guide = p.ctx.LeaderIcon, p.ctx.GuideIcon
    Classic.Guard("player.leader", function()
        leader:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon")
        guide:SetTexture(ROLES)
        guide:SetTexCoord(0, 0.296875, 0.015625, 0.3125)
    end)
    Classic.Layout("player.leader.layout", function()
        leader:SetSize(16, 16)
        leader:ClearAllPoints()
        leader:SetPoint("TOPLEFT", 21, -16)
        guide:SetSize(19, 19)
        guide:ClearAllPoints()
        guide:SetPoint("TOPLEFT", 21, -16)
    end)
end

local function updateNameAnchor()
    local name = _G.PlayerName
    if not name then return end
    Classic.Guard("player.name", function() name:SetJustifyH("CENTER") end)
    Classic.Layout("player.name.layout", function()
        name:SetWidth(100)
        name:ClearAllPoints()
        name:SetPoint("TOPLEFT", 97, -30)
    end)
end

-- Blizzard's rest flipbook: the frame sits at alpha 0 from setup on (its
-- Show() cannot bring it back), the animation is stopped as the reference
-- does. No Hide() on the protected child is needed for that.
local function updateRestLoop()
    local p = parts()
    local loop = p and p.ctx.PlayerRestLoop
    if not loop then return end
    Classic.Guard("player.restloop", function()
        loop:SetAlpha(0)
        if loop.PlayerRestLoopAnim then loop.PlayerRestLoopAnim:Stop() end
    end)
end

-- The reference also moves PVPIcon and PrestigePortrait here. On this client
-- those two are never shown: Camelot/PlayerFrame.lua:32 draws the PvP badge
-- with PvpBackgroundCircle / PvpBackgroundIcon on ContentMain instead, at the
-- portrait's lower left -- where Classic had it. Only the timer text is left
-- to place.
local function updatePvP()
    local p = parts()
    local timer = p and p.ctx.PvpTimerText
    if not timer then return end
    Classic.Layout("player.pvp.layout", function()
        timer:ClearAllPoints()
        timer:SetPoint("TOPLEFT", 9, -7)
    end)
end

local ROLE_COORDS   -- role enum -> tex coords, built on first use
local function updateRoles()
    local p = parts()
    if not p then return end
    local icon = p.ctx.RoleIcon
    if not ROLE_COORDS then
        ROLE_COORDS = {}
        local r = Enum and Enum.LFGRole
        if r then
            if r.Tank   ~= nil then ROLE_COORDS[r.Tank]   = { 0, 19 / 64, 22 / 64, 41 / 64 } end
            if r.Healer ~= nil then ROLE_COORDS[r.Healer] = { 20 / 64, 39 / 64, 1 / 64, 20 / 64 } end
            if r.Damage ~= nil then ROLE_COORDS[r.Damage] = { 20 / 64, 39 / 64, 22 / 64, 41 / 64 } end
        end
    end
    -- The enum is compared (it keys a table), so it has to be readable.
    local role = type(UnitGroupRolesAssignedEnum) == "function"
        and Classic.Readable(UnitGroupRolesAssignedEnum("player")) or nil
    local c = role and ROLE_COORDS[role]

    Classic.Guard("player.role", function()
        icon:SetTexture(ROLES)
        if c then icon:SetTexCoord(c[1], c[2], c[3], c[4]) end
    end)
    local vehicle = inVehicle()
    Classic.Layout("player.role.layout", function()
        icon:SetSize(19, 19)
        icon:SetShown(c ~= nil)
        if _G.PlayerLevelText then _G.PlayerLevelText:SetShown(not vehicle) end
    end)
end

------------------------------------------------------------------------------
-- Rest and combat icons with the classic pulse. The five textures are ours
-- (created on Blizzard's contextual frame so they draw above the art); their
-- anchors are set once, their visibility is alpha -- a hook that fires in
-- combat then never has to Show or Hide anything.
--
-- The pulse: Blizzard's PlayerFrame_OnUpdate (Mainline/PlayerFrame.lua:203)
-- already runs the 0.5 s saw-tooth on StatusTexture. The reference repeats
-- that arithmetic in an OnUpdate hook and writes statusCounter / statusSign
-- back into PlayerFrame; here the glows simply take StatusTexture's alpha.
------------------------------------------------------------------------------

local function setIcons(attackIcon, attackGlow, restIcon, restGlow, attackBackground)
    if not icons then return end
    icons.attackIcon:SetAlpha(attackIcon and 1 or 0)
    icons.restIcon:SetAlpha(restIcon and 1 or 0)
    icons.attackBackground:SetAlpha(attackBackground and 0.4 or 0)
    glowOn.attack, glowOn.rest = attackGlow, restGlow
    if not attackGlow then icons.attackGlow:SetAlpha(0) end
    if not restGlow then icons.restGlow:SetAlpha(0) end
end

local function updateStatus()
    local pf = _G.PlayerFrame
    if not pf or not icons then return end
    Classic.Guard("player.status", function()
        if inVehicle() then
            setIcons(false, false, false, false, false)
        elseif Classic.Readable(IsResting()) then
            setIcons(false, false, true, true, false)
        elseif pf.inCombat then
            setIcons(true, true, false, false, true)
        elseif pf.onHateList then
            setIcons(true, false, false, false, false)
        else
            setIcons(false, false, false, false, false)
        end
    end)
end

local function onPulse()
    if not Classic.IsActive() or not icons then return end
    if not (glowOn.attack or glowOn.rest) then return end
    local p = parts()
    local st = p and p.status
    if not st or not st:IsShown() then return end
    local alpha = st:GetAlpha()
    if glowOn.attack then icons.attackGlow:SetAlpha(alpha) end
    if glowOn.rest then icons.restGlow:SetAlpha(alpha) end
end

local function createIcons(ctx)
    if icons then return end
    icons = {}
    local rest = ctx:CreateTexture(nil, "OVERLAY")
    rest:SetSize(31, 31)
    rest:SetTexture(STATE)
    rest:SetTexCoord(0, 0.5, 0, 0.421875)
    rest:SetPoint("TOPLEFT", 20, -54)
    icons.restIcon = rest

    local restGlow = ctx:CreateTexture(nil, "OVERLAY")
    restGlow:SetSize(32, 32)
    restGlow:SetTexture(STATE)
    restGlow:SetTexCoord(0, 0.5, 0.5, 1)
    restGlow:SetBlendMode("ADD")
    restGlow:SetPoint("TOPLEFT", rest, "TOPLEFT")
    icons.restGlow = restGlow

    local attack = ctx:CreateTexture(nil, "OVERLAY")
    attack:SetSize(32, 31)
    attack:SetTexture(STATE)
    attack:SetTexCoord(0.5, 1.0, 0, 0.484375)
    attack:SetPoint("TOPLEFT", rest, "TOPLEFT", 1, 1)
    icons.attackIcon = attack

    local attackGlow = ctx:CreateTexture(nil, "OVERLAY")
    attackGlow:SetSize(32, 32)
    attackGlow:SetTexture(STATE)
    attackGlow:SetTexCoord(0.5, 1, 0.5, 1)
    attackGlow:SetVertexColor(1, 0, 0)
    attackGlow:SetBlendMode("ADD")
    attackGlow:SetPoint("TOPLEFT", attack, "TOPLEFT")
    icons.attackGlow = attackGlow

    local bg = ctx:CreateTexture(nil, "ARTWORK")
    bg:SetSize(32, 32)
    bg:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-AttackBackground")
    bg:SetVertexColor(0.8, 0.1, 0.1)
    bg:SetPoint("TOPLEFT", attack, "TOPLEFT", -3, -1)
    icons.attackBackground = bg

    for _, t in pairs(icons) do t:SetAlpha(0) end
end

------------------------------------------------------------------------------
-- Once: what the reference does while its file loads
------------------------------------------------------------------------------

local function setupGroupIndicator(gi)
    if not gi then return end
    local s = Classic.State(gi)
    for _, key in ipairs({ "GroupIndicatorLeft", "GroupIndicatorRight" }) do
        gi[key]:SetSize(24, 16)
        gi[key]:SetTexture(GROUP_ART)
        gi[key]:SetAlpha(0.3)
    end
    gi.GroupIndicatorLeft:SetTexCoord(0, 0.1875, 0, 1)
    gi.GroupIndicatorRight:SetTexCoord(0.53125, 0.71875, 0, 1)
    -- Blizzard's unnamed middle piece is the third region (PlayerFrame.xml:452);
    -- ours is created after it, so the order holds.
    local blizzardMiddle = select(3, gi:GetRegions())
    if blizzardMiddle then blizzardMiddle:SetAlpha(0) end
    if not s.middle then
        local mid = gi:CreateTexture(nil, "BACKGROUND")
        mid:SetSize(0, 16)
        mid:SetTexture(GROUP_ART)
        mid:SetTexCoord(0.1875, 0.53125, 0, 1)
        mid:SetPoint("LEFT", gi.GroupIndicatorLeft, "RIGHT")
        mid:SetPoint("RIGHT", gi.GroupIndicatorRight, "LEFT")
        mid:SetAlpha(0.3)
        s.middle = mid
    end
    if _G.PlayerFrameGroupIndicatorText then
        _G.PlayerFrameGroupIndicatorText:SetPoint("LEFT", 20, -2)
    end
end

-- Mainline/AlternatePowerBar.xml:7 -- the druid / priest / shaman mana bar
-- under the main bars. The Classic group-indicator art makes its border.
local function paintAlternatePowerBar(bar)
    bar:SetStatusBarTexture(BAR)
    bar:SetStatusBarColor(0, 0, 1)
end

local function setupAlternatePowerBar()
    local bar = _G.AlternatePowerBar
    if not bar then return end
    local s = Classic.State(bar)
    bar:SetSize(104, 12)
    bar:ClearAllPoints()
    bar:SetPoint("BOTTOMLEFT", 95, 19)
    if _G.AlternatePowerBarText then _G.AlternatePowerBarText:SetPoint("CENTER", 0, -1) end
    if bar.LeftText then bar.LeftText:SetPoint("LEFT", 0, -1) end
    if bar.RightText then bar.RightText:SetPoint("RIGHT", 0, -1) end
    if bar.PowerBarMask then bar.PowerBarMask:Hide() end

    if not s.background then
        s.background = bar:CreateTexture(nil, "BACKGROUND")
        s.background:SetAllPoints()
        s.background:SetColorTexture(0, 0, 0, 0.5)

        s.border = bar:CreateTexture(nil, "OVERLAY")
        s.border:SetSize(0, 16)
        s.border:SetTexture(GROUP_ART)
        s.border:SetTexCoord(0.125, 0.250, 1, 0)
        s.border:SetPoint("TOPLEFT", 4, 0)
        s.border:SetPoint("TOPRIGHT", -4, 0)

        s.leftBorder = bar:CreateTexture(nil, "OVERLAY")
        s.leftBorder:SetSize(16, 16)
        s.leftBorder:SetTexture(GROUP_ART)
        s.leftBorder:SetTexCoord(0, 0.125, 1, 0)
        s.leftBorder:SetPoint("RIGHT", s.border, "LEFT")

        s.rightBorder = bar:CreateTexture(nil, "OVERLAY")
        s.rightBorder:SetSize(16, 16)
        s.rightBorder:SetTexture(GROUP_ART)
        s.rightBorder:SetTexCoord(0.125, 0, 1, 0)
        s.rightBorder:SetPoint("LEFT", s.border, "RIGHT")
    end
    paintAlternatePowerBar(bar)
end

local function setup()
    local p = parts()
    if not p then return end

    if not overlay then
        overlay = Classic.NewOverlay(p.frame, "player",
            { "PLAYER_ENTERING_WORLD", "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST" },
            { "UNIT_ENTERED_VEHICLE", "UNIT_EXITED_VEHICLE", "UNIT_HEALTH", "UNIT_MAXHEALTH",
              "UNIT_DISPLAYPOWER", "UNIT_POWER_UPDATE", "UNIT_MAXPOWER" },
            { "player", "vehicle" })
        overlay:SetPoint("TOPLEFT", -19, -4)
        overlay.Background:SetPoint("TOPLEFT", 106, -22)
        overlay.HealthBar:SetPoint("TOPLEFT", 106, -41)
        overlay.ManaBar:SetPoint("TOPLEFT", 106, -52)
    end
    overlay:SetAlpha(1)
    if isSetUp then return end
    isSetUp = true

    local hb, hc, mb = p.hb, p.hc, p.mb
    local mask = hc.HealthBarMask

    Classic.Guard("player.setup.bars", function()
        hc:SetAlpha(0)
        p.mba:SetAlpha(0)
        if mask then
            for _, path in ipairs({
                { "MyHealPredictionBar", "Fill" }, { "OtherHealPredictionBar", "Fill" },
                { "HealAbsorbBar", "Fill" }, { "HealAbsorbBar", "LeftShadow" },
                { "HealAbsorbBar", "RightShadow" }, { "TotalAbsorbBar", "Fill" },
                { "TotalAbsorbBar", "TiledFillOverlay" },
            }) do
                local t = hb[path[1]] and hb[path[1]][path[2]]
                if t then t:RemoveMaskTexture(mask) end
            end
            hb.OverAbsorbGlow:RemoveMaskTexture(mask)
            hb.OverHealAbsorbGlow:RemoveMaskTexture(mask)
        end
        hb.MyHealPredictionBar.Fill:SetTexture(BAR)
        hb.OtherHealPredictionBar.Fill:SetTexture(BAR)
        hb.HealAbsorbBar.Fill:SetTexture("Interface\\RaidFrame\\Absorb-Fill", true, true)
        hb.TotalAbsorbBar.Fill:SetTexture("Interface\\RaidFrame\\Shield-Fill")
    end)
    Classic.Guard("player.setup.loss", function()
        local loss = hc.PlayerFrameHealthBarAnimatedLoss
        if mask then loss:GetStatusBarTexture():RemoveMaskTexture(mask) end
        loss:SetStatusBarTexture(BAR)
    end)
    Classic.Guard("player.setup.feedback", function()
        local fb = mb.FeedbackFrame
        for _, key in ipairs({ "BarTexture", "LossGlowTexture", "GainGlowTexture" }) do
            if fb[key] then fb[key]:RemoveMaskTexture(mb.ManaBarMask) end
        end
    end)
    Classic.Guard("player.setup.chrome", function()
        p.main.LevelBackgroundCircle:SetAlpha(0)
        -- The reference hides these two on every PlayerFrame_UpdateStatus;
        -- alpha 0 survives Blizzard's Show() and needs no call in combat.
        p.ctx.AttackIcon:SetAlpha(0)
        p.ctx.PlayerPortraitCornerIcon:SetAlpha(0)
        p.ctx.PlayerRestLoop:SetAlpha(0)
        p.container.PlayerPortraitMask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
        createIcons(p.ctx)
    end)

    Classic.Layout("player.setup.layout", function()
        local container = p.container
        hb.TextString:SetParent(container)
        hb.LeftText:SetParent(container)
        hb.RightText:SetParent(container)
        hb.OverAbsorbGlow:SetParent(container)
        hb.OverHealAbsorbGlow:SetParent(container)
        mb.TextString:SetParent(container)
        mb.LeftText:SetParent(container)
        mb.RightText:SetParent(container)

        -- Art and portrait above our bars, icons above the art; the overlay
        -- one below the art whatever level PlayerFrame itself sits on.
        container:SetFrameLevel(4)
        p.ctx:SetFrameLevel(5)
        overlay:SetFrameLevel(3)

        container.PlayerPortrait:SetSize(64, 64)
        container.PlayerPortrait:SetPoint("TOPLEFT", 23, -16)
        container.PlayerPortraitMask:SetSize(64, 64)
        container.PlayerPortraitMask:SetPoint("TOPLEFT", 23, -16)

        local hit = p.main.HitIndicator
        hit:SetParent(p.ctx)
        hit.HitText:ClearAllPoints()
        hit.HitText:SetPoint("CENTER", hit, "TOPLEFT", 54, -46)
    end)
    Classic.Layout("player.setup.group", function() setupGroupIndicator(p.ctx.GroupIndicator) end)
    Classic.Layout("player.setup.altpower", setupAlternatePowerBar)
end

------------------------------------------------------------------------------
-- Part
------------------------------------------------------------------------------

local function hook(name, fn)
    if type(_G[name]) ~= "function" then return end
    hooksecurefunc(name, function()
        if not Classic.IsActive() or not overlay then return end
        fn()
    end)
end

Classic.RegisterPart({
    name = "player",

    install = function()
        hook("PlayerFrame_ToPlayerArt", playerArt)
        hook("PlayerFrame_ToVehicleArt", vehicleArt)
        hook("PlayerFrame_UpdateLevel", updateLevel)
        hook("PlayerFrame_UpdatePartyLeader", updatePartyLeader)
        hook("PlayerFrame_UpdatePlayerNameTextAnchor", updateNameAnchor)
        hook("PlayerFrame_UpdatePlayerRestLoop", updateRestLoop)
        hook("PlayerFrame_UpdatePvPStatus", updatePvP)
        hook("PlayerFrame_UpdateRolesAssigned", updateRoles)
        hook("PlayerFrame_UpdateStatus", updateStatus)

        local alt = _G.AlternatePowerBar
        if alt and type(alt.EvaluateUnit) == "function" then
            hooksecurefunc(alt, "EvaluateUnit", function(bar)
                if not Classic.IsActive() then return end
                Classic.Guard("player.altpower", paintAlternatePowerBar, bar)
                Classic.Layout("player.altpower.mask", function()
                    if bar.PowerBarMask then bar.PowerBarMask:Hide() end
                end)
            end)
        end

        pulse = CreateFrame("Frame")
        pulse:SetScript("OnUpdate", onPulse)
    end,

    -- The reference leans on Blizzard running every one of these once while
    -- the UI loads; we come later, so we run them ourselves.
    enable = function()
        setup()
        if not overlay then return end
        applyArt()
        updateLevel()
        updatePartyLeader()
        updateNameAnchor()
        updateRestLoop()
        updatePvP()
        updateRoles()
        updateStatus()
        if pulse then pulse:Show() end
    end,

    -- Alpha, not Hide(): the overlay is a child of a protected frame, and
    -- the module can be switched off in the middle of a fight.
    disable = function()
        if overlay then overlay:SetAlpha(0) end
        if icons then setIcons(false, false, false, false, false) end
        if pulse then pulse:Hide() end
    end,
})
