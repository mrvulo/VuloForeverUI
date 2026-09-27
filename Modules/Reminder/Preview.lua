-- VuloForeverUI / Modules / Reminder / Preview
--
-- The live preview at the top of the settings page: every reminder that is
-- switched on for this character, in the size, spacing and labels the row
-- uses, redrawn on every change. Full colour = due right now, faded = on but
-- not due (the buff is up, the weapon is enchanted).
--
-- Plain frames, not the secure buttons: no clicks, nothing to taint, and it
-- works while the module is off or a fight is on.
local _, ns = ...
local L = ns.L
local R = ns.Reminder

local row, empty
local icons = {}

local function showTooltip(f)
    local it = f.item
    if not it then return end
    GameTooltip:SetOwner(f, "ANCHOR_TOP")
    if it.spell or it.tip then
        GameTooltip:SetSpellByID(it.spell or it.tip)
    elseif it.itemID then
        GameTooltip:SetItemByID(it.itemID)
    else
        GameTooltip:SetText(it.title or "", 1, 1, 1)
    end
    if it.due then
        GameTooltip:AddLine(it.line, 1, 0.82, 0)
    else
        GameTooltip:AddLine(L["Not due right now"], 0.6, 0.6, 0.6)
    end
    GameTooltip:Show()
end

local function makeIcon(i)
    local f = CreateFrame("Frame", nil, row)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetAllPoints()
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.border = CreateFrame("Frame", nil, f, "BackdropTemplate")
    f.border:SetPoint("TOPLEFT", -1, 1)
    f.border:SetPoint("BOTTOMRIGHT", 1, -1)
    f.border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    f.label = f.border:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.label:SetPoint("TOP", f, "BOTTOM", 0, -3)
    f.label:SetWordWrap(false)
    f:EnableMouse(true)
    f:SetScript("OnEnter", showTooltip)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)
    icons[i] = f
    return f
end

local header

-- `force`: the page build, before the header is on screen.
function R.RefreshPreview(force)
    if not header then return end
    if not force and not header:IsLive() then return end
    local db = R.mod.db
    local items = R.Collect(true)
    local size, gap = db.size, db.spacing
    local n = #items
    local width = n * size + math.max(n - 1, 0) * gap

    for i = 1, math.max(n, #icons) do
        local f = icons[i]
        local it = items[i]
        if it then
            f = f or makeIcon(i)
            f.item = it
            f:SetSize(size, size)
            f:ClearAllPoints()
            f:SetPoint("LEFT", row, "LEFT", (i - 1) * (size + gap), 0)
            f.icon:SetTexture(it.icon or 134400)
            f.icon:SetDesaturated(not it.due)
            f:SetAlpha(it.due and 1 or 0.45)
            if not it.due then
                f.border:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
            elseif it.soon then
                f.border:SetBackdropBorderColor(1, 0.82, 0, 1)
            else
                f.border:SetBackdropBorderColor(0.9, 0.2, 0.2, 1)
            end
            f.label:SetWidth(size + gap)
            f.label:SetText(db.showLabels and it.short or "")
            f:Show()
        elseif f then
            f.item = nil
            f:Hide()
        end
    end

    -- Real size, at the row's own scale on screen; a long row shrinks to fit.
    -- The names hang under the icons, so the stage makes room for them.
    local labels = (db.showLabels and n > 0) and 16 or 0
    row:SetSize(math.max(width, 1), size)
    local scale = header:Fit(math.max(width, 1), size + labels, db.pos and db.pos.scale or 1)
    row:SetScale(scale)
    row:ClearAllPoints()
    row:SetPoint("CENTER", header.stage, "CENTER", 0, labels / 2)
    empty:SetShown(n == 0)
    local h = (n == 0) and 30 or (size + labels) * scale
    return header:SetStageHeight(h)
end

-- Pinned above the page. The icons keep their spell tooltips, so there are no
-- click targets here and no hint about them.
function R.BuildPreviewHeader(host)
    if not header then
        header = ns.UI:CreatePreviewHeader({ key = "reminders", hint = false })
        row = CreateFrame("Frame", nil, header.stage)
        empty = header.stage:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        empty:SetPoint("CENTER", header.stage, "CENTER", 0, 0)
    end
    empty:SetText(L["No reminder is switched on for this character."])
    header:Mount(host)
    header:SetNote(L["Preview -- faded icons are switched on but not due right now"])
    return R.RefreshPreview(true) or 0
end
