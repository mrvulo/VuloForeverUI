-- VuloForeverUI / Modules / DamageMeter / Classic
--
-- The Classic look of the meter windows: the stock meter's shape in 1.x art.
--
--   window   the tooltip background, tiled and tinted in the window colour,
--            inside the border the 1.x chat tabs wear (cut from ChatFrameTab)
--   header   a lighter band of the same tile, over a rim-grey hairline
--   bars     the game's own bar fill over a quarter-black track (seeded once,
--            the settings stay yours afterwards)
--   buttons  1.x button art and spell icons, in colour, a step brighter on hover
--
-- Modern is everything the window did before; switching between the two is
-- live, nothing here needs a reload.
local _, ns = ...
local DM = ns.DM

local C = {
    BG        = "Interface\\Tooltips\\UI-Tooltip-Background",
    EDGE      = "Interface\\ChatFrame\\ChatFrameTab",
    EDGE_SIZE = 5,     -- one edge piece: shadow (2), rim (1), bevel (2)
    BODY      = 3,     -- the tile starts this far inside the window (under the bevel)
    INSET     = 5,     -- header and rows start this far inside (past the bevel)
    HDR_SHADE = 1.6,   -- the header band's tint relative to the window's
    HDR_LIFT  = 0.05,  -- plus this, so a black window still shows a band
    LINE      = 0.41,  -- the chat tab rim's own grey, for the header hairline
    ICON_SCALE = 0.85, -- header art drawn this much smaller than the glyphs
    ICON_PAD   = 2,    -- with this gap between buttons
    IDLE = 0.85, HOVER = 1,
}
DM.CLASSIC = C

function DM.IsClassic()
    local d = DM.db()
    return d and d.style == "classic" or false
end

-- ---------------------------------------------------------------- tile --

-- A texture as the tiled tooltip background in a colour: the file is near
-- white, the vertex colour is the tone.
function DM.ClassicTint(tex, r, g, b, a)
    if not tex._vfClassicTiled then
        tex._vfClassicTiled = true
        tex:SetHorizTile(true)
        tex:SetVertTile(true)
        tex:SetTexture(C.BG, "REPEAT", "REPEAT")
    end
    tex:SetVertexColor(r or 0, g or 0, b or 0, a or 1)
end

-- The chat tab's border, measured on its 64x32 sheet: every piece is 5x5,
-- the top corners at columns 2..6 / 57..61, rows 9..13, the top edge from a
-- uniform stretch of the top rim, the sides from rows 20..23; the bottom
-- pieces are the top ones flipped. { point, left, right, top, bottom }.
local EDGE_UV = {
    { "TOPLEFT",     0.03125,  0.109375, 0.28125, 0.4375  },
    { "TOPRIGHT",    0.890625, 0.96875,  0.28125, 0.4375  },
    { "BOTTOMLEFT",  0.03125,  0.109375, 0.4375,  0.28125 },
    { "BOTTOMRIGHT", 0.890625, 0.96875,  0.4375,  0.28125 },
    { "TOP",         0.375,    0.5,      0.28125, 0.4375  },
    { "BOTTOM",      0.375,    0.5,      0.4375,  0.28125 },
    { "LEFT",        0.03125,  0.109375, 0.625,   0.75    },
    { "RIGHT",       0.890625, 0.96875,  0.625,   0.75    },
}

-- The box of one window, kept off the frame.
local boxes = setmetatable({}, { __mode = "k" })

local function buildBox(frame)
    local box = { parts = {} }
    local tile = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    tile:SetPoint("TOPLEFT", frame, "TOPLEFT", C.BODY, -C.BODY)
    tile:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -C.BODY, C.BODY)
    box.tile = tile

    local p = {}
    for i, spec in ipairs(EDGE_UV) do
        local t = frame:CreateTexture(nil, "BORDER")
        t:SetTexture(C.EDGE)
        t:SetTexCoord(spec[2], spec[3], spec[4], spec[5])
        if i <= 4 then t:SetSize(C.EDGE_SIZE, C.EDGE_SIZE) end
        p[spec[1]] = t
        box.parts[#box.parts + 1] = t
    end
    p.TOPLEFT:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    p.TOPRIGHT:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    p.BOTTOMLEFT:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    p.BOTTOMRIGHT:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    p.TOP:SetPoint("TOPLEFT", p.TOPLEFT, "TOPRIGHT", 0, 0)
    p.TOP:SetPoint("BOTTOMRIGHT", p.TOPRIGHT, "BOTTOMLEFT", 0, 0)
    p.BOTTOM:SetPoint("TOPLEFT", p.BOTTOMLEFT, "TOPRIGHT", 0, 0)
    p.BOTTOM:SetPoint("BOTTOMRIGHT", p.BOTTOMRIGHT, "BOTTOMLEFT", 0, 0)
    p.LEFT:SetPoint("TOPLEFT", p.TOPLEFT, "BOTTOMLEFT", 0, 0)
    p.LEFT:SetPoint("BOTTOMRIGHT", p.BOTTOMLEFT, "TOPRIGHT", 0, 0)
    p.RIGHT:SetPoint("TOPLEFT", p.TOPRIGHT, "BOTTOMLEFT", 0, 0)
    p.RIGHT:SetPoint("BOTTOMRIGHT", p.BOTTOMRIGHT, "TOPRIGHT", 0, 0)
    return box
end

-- The whole Classic box on a window, tinted in the window colour -- or gone.
function DM.ClassicBox(frame, show, r, g, b, a)
    local box = boxes[frame]
    if not show then
        if box then
            box.tile:Hide()
            for _, t in ipairs(box.parts) do t:Hide() end
        end
        return
    end
    if not box then
        box = buildBox(frame)
        boxes[frame] = box
    end
    DM.ClassicTint(box.tile, r, g, b, a)
    box.tile:Show()
    for _, t in ipairs(box.parts) do t:Show() end
end

-- The header band: the window's tile again, lighter.
function DM.ClassicHeaderTint(tex, winR, winG, winB, a)
    local k, lift = C.HDR_SHADE, C.HDR_LIFT
    DM.ClassicTint(tex,
        math.min(1, (winR or 0) * k + lift),
        math.min(1, (winG or 0) * k + lift),
        math.min(1, (winB or 0) * k + lift), a)
end

-- Back to a flat colour: the tile setup is undone so SetColorTexture draws.
function DM.ClassicUntint(tex)
    if tex._vfClassicTiled then
        tex._vfClassicTiled = nil
        tex:SetHorizTile(false)
        tex:SetVertTile(false)
        tex:SetVertexColor(1, 1, 1, 1)
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
