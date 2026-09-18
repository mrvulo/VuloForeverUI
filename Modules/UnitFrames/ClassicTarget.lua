-- VuloForeverUI / Modules / UnitFrames / ClassicTarget
--
-- Target, focus and their target-of-target frames in the Classic style: a
-- port of the second reference's target skin. Numbers and region paths are
-- the reference's; see UnitFramesClassic.lua for the rules the port adds.
--
-- Region paths checked against Forever's Blizzard_UnitFrame:
--   Mainline/TargetFrame.xml  :58 TargetFrameContainer (:61 Portrait,
--     :78 FrameTexture, :85 Flash, :92 BossPortraitFrameTexture),
--     :102 ContentMain (:105 ReputationColor, :112 Name,
--     :118 LevelBackgroundCircle, :123 LevelText, :127 HealthBarsContainer
--     with :140 HealthBar and :172-:187 LeftText / RightText / DeadText /
--     UnconsciousText; :213 ManaBar), :257 ContentContextual
--     (:274 HighLevelTexture, :279 LeaderIcon, :284 GuideIcon,
--     :289 RaidTargetIcon, :295 BossIcon, :300 QuestIcon, :316 PetBattleIcon,
--     :338 Auras, :339 NumericalThreat), :404 TargetofTargetFrameTemplate
--     (:415 Portrait, :432 FrameTexture, :439 Name, :448 HealthBar,
--     :486 ManaBar, :515-:530 $parentDebuff1..4), :556 TargetFrame,
--     :579 FocusFrame
--   Mainline/TargetFrame.lua  :280 CheckLevel, :366 CheckBattlePet,
--     :380 CheckClassification, :527 AnchorAuraContainer, :724 totFrame
--   Mainline/UnitFrame.lua    :1005 UnitFrame_UpdateThreatIndicator
--
-- Two things Blizzard does on EVERY target change, in combat too, that the
-- reference answers with SetSize / SetPoint and we, under the combat gate,
-- cannot (Mainline/TargetFrame.lua:393-:426, both SetAtlas calls pass
-- UseAtlasSize):
--   * FrameTexture is resized to the retail atlas. Ours carries TWO anchors
--     (the reference's TOPLEFT 20,-4 plus the BOTTOMRIGHT that makes it
--     232 x 100), and two anchors outrank an explicit size -- the resize has
--     no effect, only the texture file is swapped back, which is paint.
--   * the threat Flash is resized the same way, and its Classic geometry
--     differs by classification, so one fixed anchor pair cannot hold it.
--     Blizzard's Flash goes to alpha 0 and three textures of ours (normal,
--     elite, minus), laid out once, show its state and colour instead.
local _, ns = ...
local UF = ns.UF
local Classic = UF.Classic

local BAR     = Classic.BAR
local ART     = "Interface\\TargetingFrame\\UI-TargetingFrame"
local FLASH   = "Interface\\TargetingFrame\\UI-TargetingFrame-Flash"
local ROLES   = "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES"
local ART_COORDS = { 0.09375, 1, 0, 0.78125 }

-- classification -> art file suffix, flash kind, whether the cast bar has to
-- clear an elite dragon (the reference's `haveElite`)
local CLASSIFICATION = {
    rareelite = { "-Rare-Elite", "elite",  true },
    worldboss = { "-Elite",      "elite",  true },
    elite     = { "-Elite",      "elite",  true },
    rare      = { "-Rare",       "normal", true },
    minus     = { "-Minus",      "minus",  false },
}
local NORMAL = { "", "normal", false }

local overlays = {}      -- Blizzard frame -> our overlay button
local flashOwner = setmetatable({}, { __mode = "k" })   -- Blizzard's Flash -> its frame

local function parts(frame)
    if not frame then return nil end
    local container = frame.TargetFrameContainer
    local content   = frame.TargetFrameContent
    local main      = content and content.TargetFrameContentMain
    local ctx       = content and content.TargetFrameContentContextual
    local hc        = main and main.HealthBarsContainer
    if not (container and main and ctx and hc and hc.HealthBar and main.ManaBar) then return nil end
    return {
        frame = frame, container = container, main = main, ctx = ctx,
        hc = hc, hb = hc.HealthBar, mb = main.ManaBar, art = container.FrameTexture,
    }
end

------------------------------------------------------------------------------
-- The threat flash, mirrored
------------------------------------------------------------------------------

local function syncFlash(frame)
    local s = Classic.State(frame)
    local fl, p = s.flash, parts(frame)
    if not fl or not p or not p.container.Flash then return end
    local blizzard = p.container.Flash
    local shown = Classic.IsActive() and blizzard:IsShown()
    local r, g, b = blizzard:GetVertexColor()
    for kind, tex in pairs(fl) do
        tex:SetVertexColor(r, g, b)
        tex:SetAlpha((shown and kind == s.flashKind) and 1 or 0)
    end
end

local function createFlash(frame)
    local s = Classic.State(frame)
    if s.flash then return end
    local function make(file, w, h, x, y, l, r, t, b)
        local tex = frame:CreateTexture(nil, "BACKGROUND")
        tex:SetTexture(file)
        tex:SetTexCoord(l, r, t, b)
        tex:SetSize(w, h)
        tex:SetPoint("TOPLEFT", x, y)
        tex:SetAlpha(0)
        return tex
    end
    s.flash = {
        normal = make(FLASH, 242, 93, -4, -4, 0, 0.9453125, 0, 0.181640625),
        elite  = make(FLASH, 242, 112, -2, 5, 0, 0.9453125, 0.181640625, 0.400390625),
        minus  = make("Interface\\TargetingFrame\\UI-TargetingFrame-Minus-Flash", 256, 128, -4, -4, 0, 1, 0, 1),
    }
    s.flashKind = "normal"
end

------------------------------------------------------------------------------
-- Classification (reference: its CheckClassification hook)
------------------------------------------------------------------------------

local function checkClassification(frame)
    local p, overlay = parts(frame), overlays[frame]
    if not p or not overlay then return end
    local s = Classic.State(frame)

    -- Compared, so it has to be readable; an unreadable one gets the plain art.
    local class = Classic.Readable(UnitClassification(frame.unit))
    local look = (class and CLASSIFICATION[class]) or NORMAL
    local minus = class == "minus"

    Classic.Guard("target.classification", function()
        p.art:SetTexture(ART .. look[1])
        p.art:SetTexCoord(ART_COORDS[1], ART_COORDS[2], ART_COORDS[3], ART_COORDS[4])
        p.main.ReputationColor:SetAlpha(minus and 0 or 1)
        overlay.ManaBar:SetAlpha(minus and 0 or 1)
        s.flashKind = look[2]
        s.haveElite = look[3] or nil
        syncFlash(frame)
    end)

    Classic.Layout("target.classification.layout." .. frame.unit, function()
        local hb, hc = p.hb, p.hc
        local y, textY = -1, 0
        if minus then
            overlay.Background:SetSize(119, 12)
            overlay.Background:SetPoint("BOTTOMLEFT", 7, 47)
            y, textY = -6, -6
        else
            overlay.Background:SetSize(119, 25)
            overlay.Background:SetPoint("BOTTOMLEFT", 7, 35)
        end
        hb.TextString:SetPoint("CENTER", hc, "CENTER", 0, textY)
        hc.LeftText:SetPoint("LEFT", hc, "LEFT", 5, y)
        hc.RightText:SetPoint("RIGHT", hc, "RIGHT", -7, y)
        hc.DeadText:SetPoint("CENTER", hc, "CENTER", 0, y)
        hc.UnconsciousText:SetPoint("CENTER", hc, "CENTER", 0, y)

        local mb = p.mb
        mb.TextString:SetPoint("CENTER", mb, "CENTER", -4, 3)
        mb.LeftText:SetPoint("LEFT", mb, "LEFT", 5, 3)
        mb.RightText:SetPoint("RIGHT", mb, "RIGHT", -15, 3)
    end)
end

------------------------------------------------------------------------------
-- The smaller hooks
------------------------------------------------------------------------------

local function checkLevel(frame)
    local p = parts(frame)
    if not p then return end
    local level, skull = p.main.LevelText, p.ctx.HighLevelTexture
    Classic.Guard("target.level", function()
        level:SetFontObject(GameNormalNumberFont)
        skull:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-Skull")
    end)
    Classic.Layout("target.level.layout." .. frame.unit, function()
        level:SetParent(p.ctx)
        level:ClearAllPoints()
        level:SetPoint("CENTER", 82, -21)
        skull:SetSize(16, 16)
        skull:ClearAllPoints()
        skull:SetPoint("CENTER", 81, -21)
    end)
end

local function checkBattlePet(frame)
    local p = parts(frame)
    if not p or not p.ctx.PetBattleIcon then return end
    Classic.Layout("target.battlepet.layout." .. frame.unit, function()
        p.ctx.PetBattleIcon:ClearAllPoints()
        p.ctx.PetBattleIcon:SetPoint("CENTER", p.art, "RIGHT", -44, 10)
    end)
end

-- The container is read from its parentKey (TargetFrame.lua:493 returns the
-- same field) rather than through Blizzard's method.
local function anchorAuras(frame)
    local p = parts(frame)
    local auras = p and p.ctx.Auras
    if not auras then return end
    Classic.Layout("target.auras.layout." .. frame.unit, function()
        auras:ClearAllPoints()
        auras:SetPoint("TOPLEFT", p.art, "BOTTOMLEFT", 5, 32)
    end)
end

------------------------------------------------------------------------------
-- Target of target
------------------------------------------------------------------------------

local function setupToT(frame)
    local tot = frame.totFrame
    if not tot then return end
    local s = Classic.State(tot)

    Classic.Guard("tot.paint", function()
        tot.FrameTexture:SetTexture("Interface\\TargetingFrame\\UI-TargetofTargetFrame")
        tot.FrameTexture:SetTexCoord(0.015625, 0.7265625, 0, 0.703125)
        tot.HealthBar:SetStatusBarTexture(BAR)
        tot.HealthBar:SetStatusBarColor(0, 1, 0)
        if not s.background then
            s.background = tot.HealthBar:CreateTexture(nil, "BACKGROUND")
            s.background:SetSize(46, 15)
            s.background:SetColorTexture(0, 0, 0, 0.5)
            s.background:SetPoint("BOTTOMLEFT", tot, "BOTTOMLEFT", 45, 20)
        end
    end)
    Classic.RegisterManaBar(tot.ManaBar)

    Classic.Layout("tot.layout." .. frame.unit, function()
        tot:SetFrameStrata("HIGH")
        if frame == _G.TargetFrame then
            tot:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", 12, 31)
        end

        tot.FrameTexture:SetSize(93, 45)
        tot.FrameTexture:ClearAllPoints()
        tot.FrameTexture:SetPoint("TOPLEFT", 0, 0)

        tot.Portrait:SetSize(35, 35)

        tot.Name:SetWidth(100)
        tot.Name:ClearAllPoints()
        tot.Name:SetPoint("BOTTOMLEFT", 42, 7)

        tot.HealthBar:SetSize(46, 7)
        tot.HealthBar:ClearAllPoints()
        tot.HealthBar:SetPoint("TOPRIGHT", -29, -15)
        tot.HealthBar:SetFrameLevel(1)

        for _, key in ipairs({ "DeadText", "UnconsciousText" }) do
            local fs = tot.HealthBar[key]
            if fs then
                fs:SetParent(tot)
                fs:ClearAllPoints()
                fs:SetPoint("LEFT", 48, 3)
            end
        end

        tot.ManaBar:SetSize(46, 7)
        tot.ManaBar:ClearAllPoints()
        tot.ManaBar:SetPoint("TOPRIGHT", -29, -23)
        tot.ManaBar:SetFrameLevel(1)

        -- the four debuffs, two by two at the frame's right edge
        local name = tot:GetName()
        local spots = { { -23, -8 }, { -10, -8 }, { -23, -21 }, { -10, -21 } }
        for i = 1, 4 do
            local debuff = name and _G[name .. "Debuff" .. i]
            if debuff then
                debuff:ClearAllPoints()
                debuff:SetPoint("TOPLEFT", tot, "TOPRIGHT", spots[i][1], spots[i][2])
            end
        end
    end)
end

------------------------------------------------------------------------------
-- Once per frame: what the reference's SkinFrame does while its file loads
------------------------------------------------------------------------------

local function setup(frame, unit)
    local p = parts(frame)
    if not p then return end

    local overlay = overlays[frame]
    if not overlay then
        overlay = Classic.NewOverlay(frame, unit,
            { "PLAYER_ENTERING_WORLD", unit == "focus" and "PLAYER_FOCUS_CHANGED" or "PLAYER_TARGET_CHANGED" },
            { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_DISPLAYPOWER", "UNIT_POWER_UPDATE", "UNIT_MAXPOWER" },
            { unit })
        overlay:SetPoint("TOPLEFT", 20, -4)
        overlay.Background:SetPoint("BOTTOMLEFT", 7, 35)
        overlay.Background:SetSize(119, 25)
        overlay.HealthBar:SetPoint("TOPRIGHT", -106, -41)
        overlay.ManaBar:SetPoint("TOPRIGHT", -106, -52)
        overlays[frame] = overlay
    end
    overlay:SetAlpha(1)

    local s = Classic.State(frame)
    if s.isSetUp then return end
    s.isSetUp = true

    local hb, hc, mb, ctx, main, container = p.hb, p.hc, p.mb, p.ctx, p.main, p.container

    Classic.Guard("target.setup.paint", function()
        hb:SetAlpha(0)
        mb:SetAlpha(0)
        main.LevelBackgroundCircle:SetAlpha(0)
        main.Name:SetJustifyH("CENTER")
        main.ReputationColor:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-LevelBackground")
        ctx.LeaderIcon:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon")
        ctx.GuideIcon:SetTexture(ROLES)
        ctx.GuideIcon:SetTexCoord(0, 0.296875, 0.015625, 0.3125)
        ctx.QuestIcon:SetTexture("Interface\\TargetingFrame\\PortraitQuestBadge")
        -- The reference hides these two on every CheckClassification; alpha 0
        -- survives Blizzard's Show() and needs no call in combat.
        ctx.BossIcon:SetAlpha(0)
        container.BossPortraitFrameTexture:SetAlpha(0)
        -- Blizzard's flash only lends its state from here on (see the header).
        container.Flash:SetAlpha(0)
        flashOwner[container.Flash] = frame
        createFlash(frame)
    end)

    Classic.Layout("target.setup.layout." .. unit, function()
        ctx:SetFrameStrata("MEDIUM")
        container:SetFrameStrata("MEDIUM")

        p.art:SetSize(232, 100)
        p.art:ClearAllPoints()
        p.art:SetPoint("TOPLEFT", 20, -4)
        p.art:SetPoint("BOTTOMRIGHT", container, "TOPLEFT", 252, -104)

        container.Portrait:SetSize(64, 64)
        container.Portrait:ClearAllPoints()
        container.Portrait:SetPoint("TOPRIGHT", -22, -16)

        ctx.NumericalThreat:SetParent(frame)
        ctx.NumericalThreat:ClearAllPoints()
        ctx.NumericalThreat:SetPoint("BOTTOM", frame, "TOP", -30, -26)

        ctx.RaidTargetIcon:ClearAllPoints()
        ctx.RaidTargetIcon:SetPoint("CENTER", container.Portrait, "TOP", 2, -2)

        main.Name:SetParent(ctx)
        main.Name:SetWidth(100)
        main.Name:ClearAllPoints()
        main.Name:SetPoint("TOPLEFT", 36, -30)

        hb.TextString:SetParent(container)
        hc.RightText:SetParent(container)
        hc.LeftText:SetParent(container)
        hc.DeadText:SetParent(container)
        hc.UnconsciousText:SetParent(container)
        mb.TextString:SetParent(container)
        mb.RightText:SetParent(container)
        mb.LeftText:SetParent(container)

        main.ReputationColor:SetSize(119, 19)
        main.ReputationColor:ClearAllPoints()
        main.ReputationColor:SetPoint("TOPRIGHT", -86, -26)

        ctx.LeaderIcon:SetSize(16, 16)
        ctx.LeaderIcon:ClearAllPoints()
        ctx.LeaderIcon:SetPoint("TOPRIGHT", -24, -14)

        ctx.GuideIcon:SetSize(19, 19)
        ctx.GuideIcon:ClearAllPoints()
        ctx.GuideIcon:SetPoint("TOPRIGHT", -20, -14)

        ctx.QuestIcon:SetSize(32, 32)
        ctx.QuestIcon:ClearAllPoints()
        ctx.QuestIcon:SetPoint("TOP", 32, -16)
    end)

    if frame == _G.TargetFrame and _G.ComboFrame then
        Classic.Layout("target.setup.combo", function()
            _G.ComboFrame:ClearAllPoints()
            _G.ComboFrame:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -24, -13)
        end)
    end

    setupToT(frame)
end

------------------------------------------------------------------------------
-- Part
------------------------------------------------------------------------------

local function frames()
    return { { _G.TargetFrame, "target" }, { _G.FocusFrame, "focus" } }
end

local function hookMethod(frame, method, fn)
    if type(frame[method]) ~= "function" then return end
    hooksecurefunc(frame, method, function(self)
        if not Classic.IsActive() or not overlays[self] then return end
        fn(self)
    end)
end

-- For the cast bar file: did the last classification put a dragon on `frame`?
function Classic.HaveElite(frame)
    return Classic.State(frame).haveElite and true or false
end

Classic.RegisterPart({
    name = "target",

    install = function()
        for _, entry in ipairs(frames()) do
            local frame = entry[1]
            if frame then
                hookMethod(frame, "CheckBattlePet", checkBattlePet)
                hookMethod(frame, "CheckClassification", checkClassification)
                hookMethod(frame, "CheckLevel", checkLevel)
                hookMethod(frame, "AnchorAuraContainer", anchorAuras)
            end
        end
        if type(_G.UnitFrame_UpdateThreatIndicator) == "function" then
            hooksecurefunc("UnitFrame_UpdateThreatIndicator", function(indicator)
                local frame = indicator and flashOwner[indicator]
                if not frame or not Classic.IsActive() then return end
                Classic.Guard("target.flash", syncFlash, frame)
            end)
        end
    end,

    -- The reference leans on Blizzard running the Check* methods after its
    -- hooks went in; we come later, so we run our half ourselves.
    enable = function()
        for _, entry in ipairs(frames()) do
            local frame, unit = entry[1], entry[2]
            if frame then
                setup(frame, unit)
                if overlays[frame] then
                    checkClassification(frame)
                    checkLevel(frame)
                    checkBattlePet(frame)
                    anchorAuras(frame)
                    Classic.Guard("target.feed", Classic.UpdateFrame, overlays[frame])
                end
            end
        end
    end,

    -- Alpha, not Hide(): the overlays are children of protected frames, and
    -- the module can be switched off in the middle of a fight.
    disable = function()
        for frame, overlay in pairs(overlays) do
            overlay:SetAlpha(0)
            Classic.Guard("target.flash", syncFlash, frame)
        end
    end,
})
