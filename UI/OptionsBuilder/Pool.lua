-- VuloForeverUI / UI / OptionsBuilder / Pool: widget pools, the widget factory, the layout constants and the card panel.
-- Together the OptionsBuilder files build a module page from mod:GetOptions(tabId).
-- Item spec:
--   { type = "header",    text }
--   { type = "desc",      text, width? }
--   { type = "checkbox" / "toggle", label, tooltip, get, set, width? }
--   { type = "slider",    label, tooltip, min, max, step, get, set }
--   { type = "dropdown",  label, tooltip, values, get, set, width?, reorder? }
--       values entries take optional per-row fields:
--         separator = true            a greyed caption, not selectable
--         action = true, onClick      an "add a new one" row at the bottom
--         draggable = true            may be dragged; needs config.reorder(from, to)
--         buttons = { { icon | glyph, tooltip, onClick(value, opt) }, ... }
--   { type = "editbox",   label, tooltip, get, set, numeric, width? }
--   { type = "button",    label, tooltip, onClick, width?, primary? }
--   { type = "spacer",    height? }
--   { type = "group",     layout = "row" | "columns", items, columns?, gap? }
--   { type = "custom",    build = function(parent) -> frame end, height?, width? }
local _, ns = ...
ns.UI = ns.UI or {}
local UI = ns.UI
local L = ns.L

-- State and helpers shared between the OptionsBuilder files. Values that are
-- reassigned after load (rowPopup, flashFrame, createWidget) are only ever
-- read through this table, never through a local copy.
UI._OB = UI._OB or {}
local OB = UI._OB

local CONTENT_PADDING = 14

-- Shared dropdown value lists for the visibility pair several modules offer.
-- Built per call, never at file load: the saved language override is only
-- readable once SavedVariables are in.
function ns.VisibilityValues()
    return {
        { value = "always",    text = L["Always shown"] },
        { value = "mouseover", text = L["Mouseover"] },
        { value = "combat",    text = L["In combat"] },
        { value = "noncombat", text = L["Out of combat"] },
    }
end

-- Anchor points as words. They were built as { value = "CENTER", text = "CENTER" }
-- -- the raw frame token shown to the reader, in every language. The VALUE stays
-- the token because the client needs it; only the text is translated.
function ns.AnchorPointValues()
    return {
        { value = "CENTER",      text = L["Centre"] },
        { value = "TOP",         text = L["Top"] },
        { value = "BOTTOM",      text = L["Bottom"] },
        { value = "LEFT",        text = L["Left"] },
        { value = "RIGHT",       text = L["Right"] },
        { value = "TOPLEFT",     text = L["Top left"] },
        { value = "TOPRIGHT",    text = L["Top right"] },
        { value = "BOTTOMLEFT",  text = L["Bottom left"] },
        { value = "BOTTOMRIGHT", text = L["Bottom right"] },
    }
end

-- Frames are never garbage-collected: widgets are pooled by type and reconfigured via _vcSetup.
-- Declared up here for UI.ResetWidgetPools; each is built further down.
-- rowPopup and flashFrame live on OB (OB.rowPopup, OB.flashFrame): Popup.lua
-- and Reveal.lua build them, and the reset below drops them again.
local navChips = {}

local poolHost = CreateFrame("Frame")
poolHost:Hide()
local pools = {}

-- Pooled widgets carry the colors of the style they were built in; a style
-- switch without /reload (UI:RebuildMainFrame) starts every pool empty.
function UI.ResetWidgetPools()
    pools = {}
    if OB.rowPopup then OB.rowPopup:Hide() end
    OB.rowPopup = nil
    if OB.flashFrame then OB.flashFrame:Hide() end
    OB.flashFrame = nil
    wipe(navChips)
end

local function acquire(vctype, parent)
    local p = pools[vctype]
    local w = p and table.remove(p)
    if w then
        w:SetParent(parent)
        w:Show()
    end
    return w
end

local function release(w)
    local t = w._vcType
    if not t or not w._vcSetup then return false end
    w:Hide()
    w:ClearAllPoints()
    w:SetParent(poolHost)
    pools[t] = pools[t] or {}
    table.insert(pools[t], w)
    return true
end

local function clearChildren(parent)
    local kids = { parent:GetChildren() }
    for _, k in ipairs(kids) do
        -- A sub-column container holds pooled widgets of its OWN; they must go
        -- back to their pools first, or the container would carry them into the
        -- pool and show them again on whatever page acquires it next.
        if k._vcType == "subcol" then clearChildren(k) end
        if not release(k) then
            if k == UI._dashContainer then
                k:Hide()
            else
                k:Hide()
                k:SetParent(nil)
                k:ClearAllPoints()
            end
        end
    end
    local regions = { parent:GetRegions() }
    for _, r in ipairs(regions) do
        if r.SetText then r:SetText("") end
        r:Hide()
        r:ClearAllPoints()
    end
end
UI.ClearOptionsChildren = clearChildren

local function obtain(vctype, parent, item, factory)
    local w = acquire(vctype, parent)
    if w then
        w:_vcSetup(item)
        return w
    end
    return factory()
end

local function createWidget(parent, item)
    local t = item.type
    if t == "header" then
        local w = obtain("header", parent, item, function()
            return UI:CreateHeader(parent, item.text or "")
        end)
        return w, 26, 480
    elseif t == "desc" then
        local w = obtain("desc", parent, item, function()
            return UI:CreateDescription(parent, item.text or "")
        end)
        w:SetDescWidth(item.width or 480)
        return w, math.max(20, w:GetDescHeight() + 4), item.width or 480
    elseif t == "checkbox" or t == "toggle" then
        -- The eye variant is built differently at construction and cannot be
        -- reconfigured into a switch or back, so the two need separate pools.
        -- Sharing one made an ordinary on/off row come back as an eye glyph
        -- after visiting a page that used the eye style.
        local w = obtain(item.style == "eye" and "toggle_eye" or "toggle", parent, item, function()
            return UI:CreateToggle(parent, item)
        end)
        return w, 26, w:GetWidth() or 260
    elseif t == "slider" then
        local w = obtain("slider", parent, item, function()
            return UI:CreateSlider(parent, item)
        end)
        -- Ask the row, like every other type here does. The flat 280 was right
        -- while a slider WAS its track; since it became a one-line row the label
        -- column and the value block are part of its width too.
        return w, 24, w:GetWidth() or 280
    elseif t == "dropdown" then
        local w = obtain("dropdown", parent, item, function()
            return UI:CreateDropdown(parent, item)
        end)
        return w, item.label and 30 or 28, item.width or 200
    elseif t == "segmented" then
        local w = obtain("segmented", parent, item, function()
            return UI:CreateSegmented(parent, item)
        end)
        return w, 26, item.width or 260
    elseif t == "editbox" then
        local w = obtain("editbox", parent, item, function()
            return UI:CreateEditBox(parent, item)
        end)
        return w, 28, w:GetWidth() or 160
    elseif t == "color" then
        local w = obtain("color", parent, item, function()
            return UI:CreateColorSwatch(parent, item)
        end)
        return w, 26, w:GetWidth() or 200
    elseif t == "button" then
        local w = obtain("button", parent, item, function()
            return UI:CreateButton(parent, item)
        end)
        return w, 30, (w:GetWidth() or item.width or 120)
    elseif t == "iconbutton" then
        local w = obtain("iconbutton", parent, item, function()
            return UI:CreateIconButton(parent, item)
        end)
        return w, 28, item.width or 28
    elseif t == "custom" then
        -- build(parent) must return a module-owned, memoised frame: it survives clearChildren.
        local w = item.build and item.build(parent)
        if not w then return nil, 0, 0 end
        -- memoised against the window it was first built in; after a style
        -- switch (UI:RebuildMainFrame) that window is gone, so bring it over
        if w:GetParent() ~= parent then w:SetParent(parent) end
        return w, item.height or (w:GetHeight() or 100), item.width or 480
    end
    return nil, 0, 0
end

local function estimateHeight(item)
    local t = item.type
    if t == "checkbox" or t == "toggle" then return 26
    elseif t == "button" or t == "iconbutton" then return 30
    elseif t == "header" then return 26
    elseif t == "desc"   then return 22
    elseif t == "slider" then return 24
    elseif t == "dropdown" then return item.label and 30 or 28
    elseif t == "segmented" then return 26
    elseif t == "editbox" then return 28
    elseif t == "color" then return 26
    elseif t == "custom" then return item.height or 100
    end
    return 26
end

-- Consecutive compact controls auto-arrange into a two-column grid; everything
-- else is full width. The slider joined them once it became a one-line row:
-- while its label sat above the track it needed its own taller shape, and that
-- was the reason a page had three different row heights in it.
local COMPACT = { toggle = true, checkbox = true, dropdown = true, editbox = true, color = true, slider = true, segmented = true }
local COL_GAP  = 14
local ROW_H    = 38
local CARD_GAP = 8
local CARD_H   = ROW_H - CARD_GAP
local CARD_VPAD = 11

local function makePanel(parent)
    local p = acquire("panel", parent)
    if p then return p end
    p = CreateFrame("Frame", nil, parent)
    p._vcType  = "panel"
    p._vcSetup = function() end
    p.bg = p:CreateTexture(nil, "BACKGROUND")
    p.bg:SetAllPoints(p)
    -- LIGHTER than the page behind it (bgContent is 0.08). It used to be 0.075,
    -- i.e. a hair DARKER than the page, so a card was nothing but its outline
    -- and the eye had to trace borders to see where one setting ended. Raising
    -- the fill lets the card read as an object and lets the border step back.
    p.bg:SetColorTexture(ns.TC("card"))
    for _, s in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local t = p:CreateTexture(nil, "BORDER")
        t:SetColorTexture(ns.TC("border"))
        if s == "TOP" or s == "BOTTOM" then
            t:SetPoint(s .. "LEFT"); t:SetPoint(s .. "RIGHT"); t:SetHeight(1)
        else
            t:SetPoint("TOP" .. s); t:SetPoint("BOTTOM" .. s); t:SetWidth(1)
        end
    end
    return p
end

-- for the OptionsBuilder files loaded after this one
OB.CONTENT_PADDING = CONTENT_PADDING
OB.navChips = navChips
OB.poolHost = poolHost
OB.acquire = acquire
OB.clearChildren = clearChildren
OB.createWidget = createWidget
OB.estimateHeight = estimateHeight
OB.COMPACT = COMPACT
OB.COL_GAP = COL_GAP
OB.ROW_H = ROW_H
OB.CARD_GAP = CARD_GAP
OB.CARD_H = CARD_H
OB.CARD_VPAD = CARD_VPAD
OB.makePanel = makePanel
