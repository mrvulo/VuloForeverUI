-- VuloForeverUI / Modules / Reminder / Display
--
-- The icon row. Every icon is a SECURE button, because casting a buff or
-- running "/use" on a weapon is a protected action. Everything that touches
-- them -- attributes, points, Show/Hide -- runs out of combat only; Core.lua
-- makes sure of that, and the state driver hides the whole row in a fight.
--
-- Every action attribute carries the "*...1" form: the "1" so only a LEFT
-- click resolves one (the middle click is ours, PostClick below), the "*" so
-- a left click with Shift, Ctrl or Alt held still finds it.
local _, ns = ...
local L = ns.L
local R = ns.Reminder

local holder, mover
local buttons = {}
local MAX_SHOWN = 8

function R.IsBuilt() return holder ~= nil end

-- ---------------------------------------------------------------- look --
--
-- One frame for an icon, three looks (shared with the settings preview):
--   Standard         the game's action button ring (the 1.x art, 66/36 of
--                    the button, one step low)
--   Modern, rounded  the rounded square the bags use, its ring in the
--                    state's colour (red missing, gold running out)
--   Modern, square   a one-pixel edge in that colour
-- f carries .icon and .border (a BackdropTemplate frame over it).
local MASK = "Interface\\AddOns\\VuloForeverUI\\Media\\Masks\\csquare_mask.tga"
local RING = "Interface\\AddOns\\VuloForeverUI\\Media\\Masks\\csquare_ring.tga"
local STD_RING = "Interface\\Buttons\\UI-Quickslot2"
local MARGIN = 10 / 108
local looks = setmetatable({}, { __mode = "k" })

function R.StyleIcon(f, size, r, g, b)
    local d = looks[f]
    if not d then
        d = {}
        d.mask = f:CreateMaskTexture()
        d.mask:SetTexture(MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        d.ring = f.border:CreateTexture(nil, "OVERLAY", nil, 2)
        d.ring:SetTexture(RING)
        d.std = f.border:CreateTexture(nil, "OVERLAY", nil, 1)
        d.std:SetTexture(STD_RING)
        looks[f] = d
    end
    local db = R.mod.db
    local std = db.style == "standard"
    local round = not std and db.round ~= false
    local e = size * MARGIN
    for _, t in ipairs({ d.mask, d.ring }) do
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", f, "TOPLEFT", -e, e)
        t:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", e, -e)
    end
    if d.round ~= round then
        if round then f.icon:AddMaskTexture(d.mask) else f.icon:RemoveMaskTexture(d.mask) end
        d.round = round
    end
    -- the icon fills the frame in the rounded and Standard looks, keeps its
    -- crop in the square one
    if std then
        local s = size / 36
        d.std:ClearAllPoints()
        d.std:SetPoint("CENTER", f, "CENTER", 0, -s)
        d.std:SetSize(66 * s, 66 * s)
        d.std:Show()
        d.ring:Hide()
        f.border:SetBackdropBorderColor(0, 0, 0, 0)
    elseif round then
        d.std:Hide()
        d.ring:SetVertexColor(r, g, b, 1)
        d.ring:Show()
        f.border:SetBackdropBorderColor(0, 0, 0, 0)
    else
        d.std:Hide()
        d.ring:Hide()
        f.border:SetBackdropBorderColor(r, g, b, 1)
    end
end

local laidOut
function R.Layout()
    local db = R.mod.db
    local key = db.size .. ":" .. db.spacing
    if mover then mover.opts.db = db.pos end    -- a profile switch hands us a new table
    if laidOut == key then return end
    laidOut = key
    holder:SetSize(db.size * 4 + db.spacing * 3, db.size)
    if mover then
        mover.opts.width, mover.opts.height = holder:GetWidth(), db.size
        ns:RefreshMoverGeometry(mover)
    end
end

function R.Relayout() laidOut = nil end

local function showTooltip(b)
    local it = b.item
    if not it then return end
    GameTooltip:SetOwner(b, "ANCHOR_TOP")
    if it.spell or it.tip then
        GameTooltip:SetSpellByID(it.spell or it.tip)
    elseif it.itemID then
        GameTooltip:SetItemByID(it.itemID)
    else
        GameTooltip:SetText(it.title or "", 1, 1, 1)
    end
    GameTooltip:AddLine(it.line, 1, 0.82, 0)
    if it.hint then GameTooltip:AddLine(it.hint, 0.6, 1, 0.6) end
    GameTooltip:AddLine(L["Middle click: hide until the next loading screen"], 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

local function newButton(i)
    local b = CreateFrame("Button", "VuloForeverUIReminder" .. i, holder, "SecureActionButtonTemplate")
    b:RegisterForClicks("LeftButtonDown", "LeftButtonUp", "MiddleButtonUp")
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.border = CreateFrame("Frame", nil, b, "BackdropTemplate")
    b.border:SetPoint("TOPLEFT", -1, 1)
    b.border:SetPoint("BOTTOMRIGHT", 1, -1)
    b.border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    b.hl = b:CreateTexture(nil, "HIGHLIGHT")
    b.hl:SetAllPoints()
    b.hl:SetColorTexture(1, 1, 1, 0.15)
    b.label = b.border:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.label:SetPoint("TOP", b, "BOTTOM", 0, -3)
    b.label:SetWordWrap(false)

    -- a slow pulse, so the row reads as "do something"
    b.pulse = b.icon:CreateAnimationGroup()
    b.pulse:SetLooping("BOUNCE")
    local a = b.pulse:CreateAnimation("Alpha")
    a:SetFromAlpha(1)
    a:SetToAlpha(0.45)
    a:SetDuration(0.8)

    b:SetScript("OnEnter", showTooltip)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:HookScript("PostClick", function(self, button)
        if button == "MiddleButton" and self.item then
            R.dismissed[self.item.key] = true
            R.Queue()
        end
    end)
    buttons[i] = b
    return b
end

local function setAction(b, it)
    local spell = it.spell and R.SpellName(it.spell)
    if spell then
        b:SetAttribute("*type1", "spell")
        b:SetAttribute("*spell1", spell)
        b:SetAttribute("*unit1", "player")
        b:SetAttribute("*macrotext1", nil)
    elseif it.macro then
        b:SetAttribute("*type1", "macro")
        b:SetAttribute("*macrotext1", it.macro)
        b:SetAttribute("*spell1", nil)
        b:SetAttribute("*unit1", nil)
    else
        b:SetAttribute("*type1", nil)
        b:SetAttribute("*spell1", nil)
        b:SetAttribute("*unit1", nil)
        b:SetAttribute("*macrotext1", nil)
    end
end

function R.Show(items)
    local db = R.mod.db
    local size, gap = db.size, db.spacing
    local n = math.min(#items, MAX_SHOWN)
    local width = n * size + math.max(n - 1, 0) * gap
    for i = 1, math.max(n, #buttons) do
        local b = buttons[i]
        local it = items[i]
        if i <= n then
            b = b or newButton(i)
            b.item = it
            b:SetSize(size, size)
            b:ClearAllPoints()
            b:SetPoint("LEFT", holder, "CENTER", -width / 2 + (i - 1) * (size + gap), 0)
            b.icon:SetTexture(it.icon or 134400)
            if it.soon then
                R.StyleIcon(b, size, 1, 0.82, 0)
            else
                R.StyleIcon(b, size, 0.9, 0.2, 0.2)
            end
            b.label:SetWidth(size + gap)
            b.label:SetText(db.showLabels and it.short or "")
            setAction(b, it)
            b:Show()
            if not b.pulse:IsPlaying() then b.pulse:Play() end
        elseif b then
            b.item = nil
            setAction(b, {})
            b:Hide()
        end
    end
end

-- Out of combat only (Core.lua's afterCombat).
function R.Build()
    local mod = R.mod
    if not mod.active then return end
    if not holder then
        holder = CreateFrame("Frame", "VuloForeverUIReminderRow", UIParent)
        holder:SetFrameStrata("MEDIUM")
        R.Layout()
        mover = ns:CreateMover(holder, {
            key      = "reminders",
            label    = L["Reminders"],
            db       = mod.db.pos,
            width    = holder:GetWidth(),
            height   = mod.db.size,
            scalable = true,
        })
    end
    laidOut = nil
    R.Layout()
    ns:ApplyMover(mover)
    RegisterStateDriver(holder, "visibility", "[combat] hide; show")
    R.Queue()
end

function R.Teardown()
    if R.mod.active or not holder then return end
    UnregisterStateDriver(holder, "visibility")
    R.Show({})
    holder:Hide()
end
