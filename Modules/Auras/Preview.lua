-- VuloForeverUI / Modules / Auras / Preview
--
-- The live preview pinned above the aura page: a row of buffs over a row of
-- debuffs, at the size, spacing, direction, crop, border and text the real
-- rows use. A click on a row opens that row's settings, a click on a time or
-- a stack count opens the text settings.
--
-- The real rows are the client's aura widget, which fills itself from the
-- player and cannot be handed made-up auras. So these icons are DRAWN: plain
-- frames laid out by the same numbers Style.Initializer and the row layout
-- read, with sample art, times and counts. Nothing here touches an aura.
local _, ns = ...
local L = ns.L
local A = ns.Auras
local UI = ns.UI

local ROW_GAP = 12              -- between the buff block and the debuff block
local MOST    = 16              -- icons drawn per block at the most

local BUFF_ART = {
    "Interface\\Icons\\Spell_Holy_WordFortitude",
    "Interface\\Icons\\Spell_Nature_Regeneration",
    "Interface\\Icons\\Spell_Holy_MagicalSentry",
    "Interface\\Icons\\Spell_Nature_Thorns",
    "Interface\\Icons\\Spell_Holy_GreaterBlessingofKings",
    "Interface\\Icons\\Spell_Nature_LightningShield",
}
local DEBUFF_ART = {
    "Interface\\Icons\\Spell_Shadow_ShadowWordPain",
    "Interface\\Icons\\Spell_Shadow_CurseOfTounges",
    "Interface\\Icons\\Ability_Creature_Disease_02",
    "Interface\\Icons\\Spell_Nature_CorrosiveBreath",
    "Interface\\Icons\\Ability_Gouge",
}
-- The dispel type each sample debuff stands for, in DEBUFF_ART's order.
local DEBUFF_TYPE = { "dispelMagic", "dispelCurse", "dispelDisease", "dispelPoison", "dispelBleed" }
local TIMES  = { "58m", "12s", "2h", "4s", "27m", "9s" }
local STACKS = { "", "3", "", "", "5", "" }

local header, mod
local blocks = {}

local function newIcon(parent)
    local f = CreateFrame("Frame", nil, parent)
    f.tex = f:CreateTexture(nil, "ARTWORK")
    f.tex:SetAllPoints(f)
    f.edges = ns.MakeEdges(f, "OVERLAY")
    f.dispel = ns.MakeEdges(f, "OVERLAY")
    f.duration = f:CreateFontString(nil, "OVERLAY")
    f.stacks = f:CreateFontString(nil, "OVERLAY")
    return f
end

local function placeText(fs, point, x, y, button)
    local a = A.Style.ANCHORS[point] or A.Style.ANCHORS.CENTER
    fs:ClearAllPoints()
    fs:SetPoint(a[1], button, a[1], a[2] + x, a[3] + y)
end

-- One block, laid out from the top corner its growth starts in. Returns the
-- block's width and height.
local function layoutBlock(kind, db)
    local buffs = kind == "buffs"
    local block = blocks[kind]
    local size = db.iconSize
    local perRow = buffs and db.perRowBuffs or db.perRowDebuffs
    local rows = buffs and db.rowsBuffs or db.rowsDebuffs
    local most = buffs and db.maxBuffs or db.maxDebuffs
    local pad = buffs and db.paddingBuffs or db.paddingDebuffs
    local count = math.min(most, perRow * rows, MOST)
    local across = math.min(count, perRow)
    local down = math.ceil(count / math.max(1, perRow))
    local w = across * size + math.max(0, across - 1) * pad
    local h = down * size + math.max(0, down - 1) * pad
    block:SetSize(math.max(w, 1), math.max(h, 1))

    local zoom = (buffs and db.buffZoom or db.debuffZoom) / 100
    local bSize = buffs and db.buffBorderSize or db.debuffBorderSize
    local bColor = buffs and db.buffBorderColor or db.debuffBorderColor
    local font = ns.ModuleFontPath("auras")
    local fromRight = db.growthX == "left"
    local upward = db.growthY == "up"

    block.icons = block.icons or {}
    for i = 1, count do
        local f = block.icons[i] or newIcon(block)
        block.icons[i] = f
        f:SetSize(size, size)
        local col = (i - 1) % perRow
        local row = math.floor((i - 1) / perRow)
        local x = col * (size + pad)
        local y = row * (size + pad)
        f:ClearAllPoints()
        if fromRight and upward then
            f:SetPoint("BOTTOMRIGHT", block, "BOTTOMRIGHT", -x, y)
        elseif fromRight then
            f:SetPoint("TOPRIGHT", block, "TOPRIGHT", -x, -y)
        elseif upward then
            f:SetPoint("BOTTOMLEFT", block, "BOTTOMLEFT", x, y)
        else
            f:SetPoint("TOPLEFT", block, "TOPLEFT", x, -y)
        end

        local art = buffs and BUFF_ART or DEBUFF_ART
        local n = (i - 1) % #art + 1
        f.tex:SetTexture(art[n])
        f.tex:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)
        ns.LayoutEdges(f.edges, f, bSize, bColor.r, bColor.g, bColor.b, 1)
        -- The client paints a debuff's border in its dispel type; here each
        -- sample debuff stands for one type.
        local dc = (not buffs) and db.dispelColors and db[DEBUFF_TYPE[n]]
        if dc then
            ns.LayoutEdges(f.dispel, f, db.dispelBorderSize, dc.r, dc.g, dc.b, 1)
        else
            ns.LayoutEdges(f.dispel, f, 0, 0, 0, 0, 0)
        end

        local t = (i - 1) % #TIMES + 1
        f.duration:SetFont(font, db.durationSize, "OUTLINE")
        placeText(f.duration, db.durationPosition, db.durationX, db.durationY, f)
        f.duration:SetText(db.showDuration and TIMES[t] or "")
        f.stacks:SetFont(font, db.stackSize, "OUTLINE")
        placeText(f.stacks, db.stackPosition, db.stackX, db.stackY, f)
        f.stacks:SetText(db.showStacks and STACKS[t] or "")
        f:Show()
    end
    for i = count + 1, #block.icons do block.icons[i]:Hide() end
    return w, h
end

-- `force`: the page build, before the header is on screen.
function A.RefreshPreview(force)
    if not (header and mod) then return end
    if not force and not header:IsLive() then return end
    local db = mod.db
    local bw, bh = layoutBlock("buffs", db)
    local dw, dh = layoutBlock("debuffs", db)
    local wide = math.max(bw, dw)
    local high = bh + ROW_GAP + dh

    -- Both blocks hang from the side their icons start on, as on screen.
    local holder = blocks.holder
    holder:SetSize(wide, high)
    local point = db.growthX == "left" and "TOPRIGHT" or "TOPLEFT"
    blocks.buffs:ClearAllPoints()
    blocks.buffs:SetPoint(point, holder, point, 0, 0)
    blocks.debuffs:ClearAllPoints()
    blocks.debuffs:SetPoint(point, holder, point, 0, -(bh + ROW_GAP))

    local scale = header:Fit(wide, high, db.buffs and db.buffs.scale or 1)
    holder:SetScale(scale)
    holder:ClearAllPoints()
    holder:SetPoint("CENTER", header.stage, "CENTER", 0, 0)

    local B, D, T = L["Buffs"], L["Debuffs"], L["Text"]
    header:Spot("buffs", blocks.buffs,
        { mod = "auras", subKey = "perRowBuffs", label = L["Icons per row"], section = B }, 0)
    header:Spot("debuffs", blocks.debuffs,
        { mod = "auras", subKey = "perRowDebuffs", label = L["Icons per row"], section = D }, 0)
    local first = blocks.buffs.icons and blocks.buffs.icons[1]
    header:Spot("duration", db.showDuration and first and first.duration or nil,
        { mod = "auras", label = L["Show the time left"], section = T }, 2)
    local stacked = blocks.buffs.icons and blocks.buffs.icons[2]
    header:Spot("stacks", db.showStacks and stacked and stacked:IsShown() and stacked.stacks or nil,
        { mod = "auras", label = L["Show the stack count"], section = T }, 2)
    return header:SetStageHeight(high * scale)
end

-- Pinned above the page while our own rows are on (Auras.lua).
function A.BuildPreviewHeader(host, owner)
    mod = owner
    if not header then
        header = UI:CreatePreviewHeader({ key = "auras", hint = true })
        blocks.holder = CreateFrame("Frame", nil, header.stage)
        blocks.buffs = CreateFrame("Frame", nil, blocks.holder)
        blocks.debuffs = CreateFrame("Frame", nil, blocks.holder)
    end
    header:Mount(host)
    return A.RefreshPreview(true) or 0
end
