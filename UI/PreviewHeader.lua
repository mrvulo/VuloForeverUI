-- VuloForeverUI / UI / PreviewHeader
--
-- The live preview every settings page with one wears, pinned above the page
-- so it stays in view while the settings under it scroll. One look for all
-- of them: a faint ground with a hairline under it, an optional picker on
-- top (which unit, which bar), the preview itself at the size it has on
-- screen, and under it a note and a one-time hint.
--
-- What the preview SHOWS is the module's business; this file only gives it a
-- stage to draw on and the tools every preview needs:
--   * H:RealScale()   the scale that makes one pixel here one pixel on screen
--   * H:Fit(w, h, s)  that scale, shrunk only where the drawing would not fit
--   * H:Spot(...)     a click target over a part of the drawing that scrolls
--                     the page to the setting owning it and flashes the row
--
-- A module mounts it from mod.BuildPageHeader(host, tabId), which the options
-- builder calls on every page build, and returns what Mount returns: the
-- header's height. Later changes of height (a taller frame, the hint going)
-- are written straight to the host, and the scroll area, which hangs off the
-- host's bottom edge, follows without a rebuild.
local _, ns = ...
local L  = ns.L
local UI = ns.UI

local PAD        = 12
local CONTROL_H  = 26
local CONTROL_W  = 350
local GAP        = 14
local NOTE_H     = 18
local HINT_H     = 20
local HOVER_EDGE = 2
local MAX_STAGE  = 220        -- a taller drawing is shrunk, not the page buried

local Header = {}
Header.__index = Header

local function accent()
    local c = ns.COLORS and ns.COLORS.accent
    return (c and c.r) or 0.61, (c and c.g) or 0.42, (c and c.b) or 1
end

local function hintSeen(key)
    local g = ns.db and ns.db.global
    return g and type(g.previewHintSeen) == "table" and g.previewHintSeen[key] == true
end

local function markHintSeen(key)
    local g = ns.db and ns.db.global
    if not g then return end
    if type(g.previewHintSeen) ~= "table" then g.previewHintSeen = {} end
    g.previewHintSeen[key] = true
end

-- opts.key: whose preview this is (the hint is dismissed per key).
-- opts.hint: whether the preview has click targets worth a hint.
function UI:CreatePreviewHeader(opts)
    local H = setmetatable({ key = opts.key, wantHint = opts.hint and true or false,
                             spots = {} }, Header)

    local panel = CreateFrame("Frame")
    panel:Hide()
    H.panel = panel

    local bg = panel:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(panel)
    bg:SetColorTexture(0, 0, 0, 0.1)
    local divider = panel:CreateTexture(nil, "BORDER")
    divider:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 0, 0)
    divider:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)
    divider:SetHeight(1)
    divider:SetColorTexture(1, 1, 1, 0.06)

    H.stage = CreateFrame("Frame", nil, panel)
    H.stage:SetHeight(40)

    H.note = panel:CreateFontString(nil, "OVERLAY")
    UI.Font(H.note, 11)
    H.note:SetTextColor(0.6, 0.6, 0.6)
    H.note:SetWordWrap(false)
    H.note:Hide()           -- a font string starts shown; only SetNote shows it

    local hint = CreateFrame("Frame", nil, panel)
    hint:SetHeight(HINT_H)
    local text = hint:CreateFontString(nil, "OVERLAY")
    UI.Font(text, 11)
    text:SetPoint("CENTER", hint, "CENTER", 0, 0)
    text:SetTextColor(1, 1, 1, 0.45)
    hint.text = text
    hint.fade = hint:CreateAnimationGroup()
    local a = hint.fade:CreateAnimation("Alpha")
    a:SetFromAlpha(1)
    a:SetToAlpha(0)
    a:SetDuration(0.3)
    hint.fade:SetScript("OnFinished", function()
        hint:Hide()
        H:Layout()                  -- the header gives the line back
    end)
    H.hint = hint
    return H
end

-- ------------------------------------------------------------------ mount --

-- spec.control: a dropdown config ({ values, get, set, width? }) for the picker
-- on top, or nil for none. Returns the header's height for the builder.
function Header:Mount(host, spec)
    spec = spec or {}
    local panel = self.panel
    panel:SetParent(host)
    panel:ClearAllPoints()
    panel:SetAllPoints(host)
    panel:Show()

    if spec.control then
        local cfg = spec.control
        cfg.width = cfg.width or math.min(CONTROL_W, math.max(160, (host:GetWidth() or 500) - 40))
        cfg.noDefaultMark = true
        if not self.control then
            self.control = UI:CreateDropdown(panel, cfg)
        else
            self.control:_vcSetup(cfg)
        end
        self.control:ClearAllPoints()
        self.control:SetPoint("TOP", panel, "TOP", 0, -PAD)
        self.control:Show()
    elseif self.control then
        self.control:Hide()
    end

    self.hint.text:SetText(L["Click an element to open its settings"])
    self.hint:SetAlpha(1)
    self.hint:SetShown(self.wantHint and not hintSeen(self.key))
    self.mounted = true
    return self:Layout()
end

function Header:IsLive()
    return self.mounted and self.panel:IsVisible()
end

-- A small grey line under the drawing: what it shows, or at what scale.
function Header:SetNote(text)
    self.note:SetText(text or "")
    self.note:SetShown(text ~= nil and text ~= "")
end

-- --------------------------------------------------------------- geometry --

-- The width the drawing may take.
function Header:Room()
    return math.max(100, (self.panel:GetWidth() or 500) - 40)
end

-- One pixel on the stage = one pixel on screen, times `scale` (the drawn
-- thing's own scale on screen, 1 when it has none).
function Header:RealScale(scale)
    local here = self.stage:GetEffectiveScale()
    if not here or here <= 0 then here = 1 end
    return UIParent:GetEffectiveScale() / here * (scale or 1)
end

-- The real scale, shrunk only as far as a drawing of w x h needs to fit the
-- page. Returns the scale and whether it is the real one.
function Header:Fit(w, h, scale)
    local s = self:RealScale(scale)
    local fit = math.min(s, self:Room() / math.max(w, 1), MAX_STAGE / math.max(h, 1))
    return fit, fit >= s - 0.001
end

-- The stage is as tall as the drawing; the header follows.
function Header:SetStageHeight(h)
    self.stage:SetHeight(math.max(1, h))
    return self:Layout()
end

-- Stacks control, stage, note and hint, and writes the height to the host.
-- Always measured, visible or not: during a page build the host is still
-- hidden, and the height returned then is the one the builder lays out with.
function Header:Layout()
    if not self.mounted then return 0 end
    local panel = self.panel
    local y = PAD
    if self.control and self.control:IsShown() then y = y + CONTROL_H + GAP end
    self.stage:ClearAllPoints()
    self.stage:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -y)
    self.stage:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, -y)
    y = y + self.stage:GetHeight() + GAP
    if self.note:IsShown() then
        self.note:ClearAllPoints()
        self.note:SetPoint("TOP", panel, "TOP", 0, -y + 4)
        y = y + NOTE_H
    end
    if self.hint:IsShown() then
        self.hint:ClearAllPoints()
        self.hint:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -y + 4)
        self.hint:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, -y + 4)
        y = y + HINT_H
    end
    y = math.floor(y + PAD / 2 + 0.5)
    local host = panel:GetParent()
    if host then host:SetHeight(y) end
    return y
end

-- ----------------------------------------------------------- click spots --

function Header:DismissHint()
    if not self.hint:IsShown() then return end
    markHintSeen(self.key)
    self.hint.fade:Play()
end

local function spotEnter(self)
    local r, g, b = accent()
    ns.LayoutEdges(self.edges, self, HOVER_EDGE, r, g, b, 1)
    UI:ShowTooltip(self, { title = self.vfTitle, accent = true,
        lines = { L["Click to open the setting"] } })
end

local function spotLeave(self)
    ns.LayoutEdges(self.edges, self, 0, 1, 1, 1, 1)
    UI:HideTooltip()
end

local function spotClick(self)
    local H, t = self.vfHeader, self.vfTarget
    H:DismissHint()
    UI:RevealRow({ mod = t.mod, tab = t.tab, label = t.label, subKey = t.subKey,
        section = t.section, sectionKey = t.sectionKey })
end

-- A click target over `region`. target = { mod, tab?, label, subKey?, section? }:
-- the row it opens, by its TRANSLATED label (or the gear key the row
-- carries), and the section to fall back on. `level` lifts it over the spots
-- it overlaps: texts over the bar they sit on. A hidden region hides its spot.
function Header:Spot(key, region, target, level, pad)
    local b = self.spots[key]
    if not b then
        b = CreateFrame("Button", nil, self.stage)
        b.edges = ns.MakeEdges(b, "OVERLAY")
        b.vfHeader = self
        b:SetScript("OnEnter", spotEnter)
        b:SetScript("OnLeave", spotLeave)
        b:SetScript("OnClick", spotClick)
        self.spots[key] = b
    end
    if not (region and region:IsShown() and target) then
        b:Hide()
        return nil
    end
    b.vfTarget, b.vfTitle = target, target.title or target.label
    -- A text or a texture has no level of its own: the frame it is drawn on
    -- decides what the spot has to clear.
    local owner = region.GetFrameLevel and region or region:GetParent() or self.stage
    b:SetFrameStrata(owner:GetFrameStrata())
    b:SetFrameLevel(owner:GetFrameLevel() + 20 + (level or 0))
    ns.LayoutEdges(b.edges, b, 0, 1, 1, 1, 1)
    pad = pad or 1
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", region, "TOPLEFT", -pad, pad)
    b:SetPoint("BOTTOMRIGHT", region, "BOTTOMRIGHT", pad, -pad)
    b:Show()
    return b
end

function Header:HideSpot(key)
    local b = self.spots[key]
    if b then b:Hide() end
end
