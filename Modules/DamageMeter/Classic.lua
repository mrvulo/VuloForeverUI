-- VuloForeverUI / Modules / DamageMeter / Classic
--
-- The Classic look of the meter windows: the window Blizzard frames its own
-- panels in, the same one the settings window wears in its Blizzard theme.
--
--   window   the metal frame (NineSlice "ButtonFrameTemplateNoPortrait") over
--            the rock background, the rows on a dark wash inside it
--   header   the metal's own top band: the title sits in it in gold, the way
--            a Blizzard window carries its title
--   bars     the game's own bar fill over a quarter-black track (seeded once,
--            the settings stay yours afterwards)
--   buttons  1.x button art and spell icons, in colour, a step brighter on hover
--
-- Modern is everything the window did before; switching between the two is
-- live, nothing here needs a reload.
local _, ns = ...
local DM = ns.DM

local C = {
    LAYOUT = "ButtonFrameTemplateNoPortrait",
    ROCK   = "Interface\\FrameGeneral\\UI-Background-Rock",
    -- Laid on the window as it is, the left rim reads wider than the right
    -- (seen in game). The metal -- and the rock under it -- start this far
    -- IN on the left, so both rims match and nothing stands out on the left.
    INSET_L = 12,
    -- The metal's visible rim starts this far right of its own frame's edge;
    -- rock laid from the edge itself showed as a grey strip outside the rim.
    ROCK_L  = 16,
    BAND   = 22,       -- the metal's top band: the header lives in it
    -- The rows start this far inside the window, clear of the metal. The
    -- left one is the right one plus the rock's own inset on that side.
    PAD    = { l = 17, r = 5, t = 0, b = 5 },
    WASH   = 0.35,     -- black over the rock behind the rows, for the text
    TITLE  = { 1.0, 0.82, 0.0 },
    TITLE_X = 12,      -- the title's distance from the header's left end
    ART_LEVEL = 30,    -- the metal over the window's own layers ...
    HDR_LEVEL = 35,    -- ... and the header over the metal
    ICON_SCALE = 0.85, -- header art drawn this much smaller than the glyphs
    ICON_PAD   = 2,    -- with this gap between buttons
    IDLE = 0.85, HOVER = 1,
}
DM.CLASSIC = C

function DM.IsClassic()
    local d = DM.db()
    return d and d.style == "classic" or false
end

-- ---------------------------------------------------------------- box --

-- The frame of one window, kept off the frame.
local boxes = setmetatable({}, { __mode = "k" })

local function buildBox(frame)
    local box = {}
    local rock = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    -- Starts where the metal's rim starts, so none of it stands out on the left.
    rock:SetPoint("TOPLEFT", frame, "TOPLEFT", C.ROCK_L, 0)
    rock:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    rock:SetTexture(C.ROCK, "REPEAT", "REPEAT")
    rock:SetHorizTile(true)
    rock:SetVertTile(true)
    box.rock = rock

    local wash = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
    wash:SetPoint("TOPLEFT", frame, "TOPLEFT", C.PAD.l, -C.BAND)
    wash:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -C.PAD.r, C.PAD.b)
    box.wash = wash

    -- The metal takes no mouse, so everything under it still clicks.
    if NineSliceUtil and NineSliceUtil.ApplyLayoutByName then
        local art = CreateFrame("Frame", nil, frame)
        art:SetPoint("TOPLEFT", frame, "TOPLEFT", C.INSET_L, 0)
        art:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        art:EnableMouse(false)
        pcall(NineSliceUtil.ApplyLayoutByName, art, C.LAYOUT)
        box.art = art
    end
    return box
end

-- The whole Classic frame on a window, or gone. `a` is the window's opacity
-- setting, carried by the rock.
function DM.ClassicBox(frame, show, _, _, _, a)
    local box = boxes[frame]
    if not show then
        if box then
            box.rock:Hide()
            box.wash:Hide()
            if box.art then box.art:Hide() end
        end
        return
    end
    if not box then
        box = buildBox(frame)
        boxes[frame] = box
    end
    box.rock:SetVertexColor(1, 1, 1, a or 1)
    box.rock:Show()
    box.wash:SetColorTexture(0, 0, 0, C.WASH * (a or 1))
    box.wash:Show()
    if box.art then
        box.art:SetFrameLevel(frame:GetFrameLevel() + C.ART_LEVEL)
        box.art:Show()
    end
end

-- ---------------------------------------------------------------- art --

-- Header art per button key: 1.x sheets cropped to their visible art (the
-- lock and close sheets are 32x32 with the button at columns 6..24, rows
-- 7..24), spell icons for the meter types. `scale` insets the art inside its
-- button; a full-bleed icon otherwise reads larger than its neighbours.
local T = DM.T or {}
local ART = {
    settings = { file = "Interface\\Icons\\Trade_Engineering", crop = 0.08, scale = 0.9 },
    segment  = { file = "Interface\\QuestFrame\\UI-QuestLog-BookIcon", l = 0.015625, r = 0.96875, t = 0.03125, b = 0.96875 },
    reset    = { file = "Interface\\Buttons\\UI-RefreshButton", scale = 0.9 },
    open     = { file = "Interface\\Buttons\\UI-PlusButton-Up" },
    close    = { file = "Interface\\Buttons\\UI-Panel-MinimizeButton-Up", l = 0.1875, r = 0.78125, t = 0.21875, b = 0.78125 },
    types = {
        [T.DamageDone or -1]           = { file = "Interface\\Icons\\INV_Sword_04", crop = 0.08, scale = 0.85 },
        [T.HealingDone or -2]          = { file = "Interface\\Icons\\Spell_Holy_Heal", crop = 0.08, scale = 0.85 },
        [T.DamageTaken or -3]          = { file = "Interface\\Icons\\Ability_Warrior_ShieldWall", crop = 0.08, scale = 0.85 },
        [T.AvoidableDamageTaken or -4] = { file = "Interface\\Icons\\Spell_Fire_Fire", crop = 0.08, scale = 0.85 },
        [T.EnemyDamageTaken or -5]     = { file = "Interface\\Icons\\INV_Sword_27", crop = 0.08, scale = 0.85 },
        [T.Interrupts or -6]           = { file = "Interface\\Icons\\Ability_Kick", crop = 0.08, scale = 0.85 },
        [T.Dispels or -7]              = { file = "Interface\\Icons\\Spell_Holy_DispelMagic", crop = 0.08, scale = 0.85 },
        [T.Deaths or -8]               = { file = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01", crop = 0.08, scale = 0.85 },
    },
}

function DM.ClassicArt(key, dmType)
    if key == "mode" then return ART.types[dmType] or ART.types[T.DamageDone or -1] end
    return ART[key]
end

-- Paint an art entry on a button's icon, seated inside the button.
function DM.PaintClassicArt(tex, art, size)
    tex:SetDesaturated(false)
    tex:SetTexture(art.file)
    if art.crop then
        tex:SetTexCoord(art.crop, 1 - art.crop, art.crop, 1 - art.crop)
    else
        tex:SetTexCoord(art.l or 0, art.r or 1, art.t or 0, art.b or 1)
    end
    local s = size * (art.scale or 1)
    tex:ClearAllPoints()
    tex:SetPoint("CENTER", tex:GetParent(), "CENTER", 0, 0)
    tex:SetSize(s, s)
    tex:SetVertexColor(C.IDLE, C.IDLE, C.IDLE, 1)
end

-- ---------------------------------------------------------------- seed --

-- The first switch to Classic on a profile: a near-black window, the game's
-- own bar fill, and a quarter-black track behind every bar. Once per profile,
-- and only over values still at the Modern defaults: a colour or texture
-- somebody chose is theirs, and Classic becoming the default must not take
-- it. The controls stay the user's afterwards either way.
local function isColor(c, r, g, b)
    return type(c) == "table" and c.r == r and c.g == g and c.b == b
end

function DM.SeedClassic()
    local d = DM.db()
    if not d or d.classicSeeded then return end
    d.classicSeeded = true
    if isColor(d.bgColor, 0, 0, 0) then
        d.bgColor = { r = 16 / 255, g = 16 / 255, b = 16 / 255 }
    end
    if d.barTexture == nil or d.barTexture == "Atrocity" then d.barTexture = "Blizzard" end
    if (d.barBgAlpha or 0) == 0 and isColor(d.barBgColor, 0, 0, 0) and not d.barBgUseClassColor then
        d.barBgAlpha = 0.25
    end
end
