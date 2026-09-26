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
                b.border:SetBackdropBorderColor(1, 0.82, 0, 1)
            else
                b.border:SetBackdropBorderColor(0.9, 0.2, 0.2, 1)
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
