-- VuloForeverUI / UI / OptionsBuilder / Card: one thing to switch and style,
-- as a card -- icon, title, a line of description, its style dropdown on the
-- right, and an arrow that folds its own settings out underneath.
--
--   { type = "card", key, title, desc, icon, values, get, set, items }
--
-- For a page that lists many things of one kind (the window skins): every
-- thing is one line at rest, and only the one being worked on shows its
-- settings. Open state is per session, keyed like the row gears; the items
-- stay in the spec either way, so the settings search and the change filter
-- still see every row of a closed card.
local _, ns = ...
local UI = ns.UI
local OB = UI._OB
local CONTENT_PADDING = OB.CONTENT_PADDING
local CARD_GAP = OB.CARD_GAP

local HEAD_H = 52
local ARROW = "Interface\\ChatFrame\\ChatFrameExpandArrow"

UI.cardOpen = UI.cardOpen or {}

local function setup(card, spec, open)
    card.title:SetText(spec.title or "")
    card.desc:SetText(spec.desc or "")
    if spec.icon then
        if type(spec.icon) == "string" and not spec.icon:find("[\\/]") then
            card.icon:SetAtlas(spec.icon)
        else
            card.icon:SetTexture(spec.icon)
        end
        card.icon:Show()
    else
        card.icon:Hide()
    end
    -- the arrow points down while closed, up while open; no settings, no arrow
    card.arrow:SetRotation(open and (math.pi / 2) or (-math.pi / 2))
    card.arrow:SetShown(spec.items ~= nil and #spec.items > 0)
    local ac = ns.COLORS.accent
    card.strip:SetColorTexture(ac.r, ac.g, ac.b, 1)
    card.strip:SetShown(open)
end

local function create(parent)
    local c = CreateFrame("Button", nil, parent)
    c._vcType = "card"
    c._vcSetup = setup
    c.bg = c:CreateTexture(nil, "BACKGROUND")
    c.bg:SetAllPoints(c)
    c.bg:SetColorTexture(ns.TC("card"))
    for _, s in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local t = c:CreateTexture(nil, "BORDER")
        t:SetColorTexture(ns.TC("border"))
        if s == "TOP" or s == "BOTTOM" then
            t:SetPoint(s .. "LEFT"); t:SetPoint(s .. "RIGHT"); t:SetHeight(1)
        else
            t:SetPoint("TOP" .. s); t:SetPoint("BOTTOM" .. s); t:SetWidth(1)
        end
    end
    c.strip = c:CreateTexture(nil, "ARTWORK")
    c.strip:SetPoint("TOPLEFT"); c.strip:SetPoint("BOTTOMLEFT"); c.strip:SetWidth(3)
    c.icon = c:CreateTexture(nil, "ARTWORK")
    c.icon:SetSize(22, 22)
    c.icon:SetPoint("LEFT", c, "LEFT", 14, 0)
    c.title = c:CreateFontString(nil, "OVERLAY")
    UI.Font(c.title, 13)
    c.title:SetTextColor(ns.TC("textHi"))
    c.title:SetPoint("TOPLEFT", c, "TOPLEFT", 48, -10)
    c.title:SetJustifyH("LEFT")
    c.desc = c:CreateFontString(nil, "OVERLAY")
    UI.Font(c.desc, 10)
    c.desc:SetTextColor(ns.TC("textMuted"))
    c.desc:SetPoint("TOPLEFT", c.title, "BOTTOMLEFT", 0, -4)
    c.desc:SetJustifyH("LEFT")
    c.desc:SetWordWrap(false)
    c.arrow = c:CreateTexture(nil, "ARTWORK")
    c.arrow:SetSize(14, 14)
    c.arrow:SetPoint("RIGHT", c, "RIGHT", -14, 0)
    c.arrow:SetTexture(ARROW)
    c.hl = c:CreateTexture(nil, "HIGHLIGHT")
    c.hl:SetAllPoints(c)
    c.hl:SetColorTexture(1, 1, 1, 0.03)
    c:SetScript("OnClick", function(self) if self._onClick then self._onClick() end end)
    return c
end

function OB.placeCard(parent, spec, y)
    local availW = (parent:GetWidth() or 540) - 2 * CONTENT_PADDING
    local base = parent:GetFrameLevel()
    local key = (UI._currentBuildKey or "?") .. "/" .. (UI.currentTab or "") .. "/c/" .. tostring(spec.key or spec.title)
    local open = UI.cardOpen[key] == true
        or (UI.onlyChanged and UI._building and spec._vcChangedInside)

    local card = OB.acquire("card", parent) or create(parent)
    card:_vcSetup(spec, open)
    card:ClearAllPoints()
    card:SetPoint("TOPLEFT", parent, "TOPLEFT", CONTENT_PADDING, y)
    card:SetSize(availW, HEAD_H)
    card:SetFrameLevel(base + 1)
    local hasItems = spec.items ~= nil and #spec.items > 0
    card._onClick = hasItems and function()
        UI.cardOpen[key] = not open
        UI:BuildOptionsPage(UI._currentBuildKey, UI.currentTab)
    end or nil

    -- the style box: a pooled dropdown of the page, laid on the card's right
    local right = 40
    if spec.values then
        local dd = OB.createWidget(parent, { type = "dropdown", values = spec.values,
            get = spec.get, set = spec.set, width = 150, tooltip = spec.tooltip })
        if dd then
            dd:ClearAllPoints()
            dd:SetPoint("RIGHT", card, "RIGHT", -right, 0)
            dd:SetFrameLevel(base + 4)
            right = right + 160
        end
    end
    card.desc:SetWidth(math.max(60, availW - 48 - right - 12))
    card.title:SetWidth(math.max(60, availW - 48 - right - 12))

    y = y - HEAD_H
    if open and hasItems then
        y = y - 6
        UI._sectionDepth = (UI._sectionDepth or 0) + 1
        y = OB.placeItemList(parent, spec.items, y)
        UI._sectionDepth = UI._sectionDepth - 1
        y = y - 6
    end
    return y - CARD_GAP
end
