-- VuloForeverUI / UI / Widgets / Base: font, gradient and hover-tooltip helpers shared by every widget file.
local _, ns = ...
ns.UI = ns.UI or {}
local UI = ns.UI

-- Private to the UI/Widgets files: the helpers more than one of them needs.
-- Filled at the end of this file; the later widget files read it at load.
UI._W = UI._W or {}
local W = UI._W

local FONT_PATH = "Interface\\AddOns\\VuloForeverUI\\Media\\Fonts\\Expressway.TTF"
UI.FONT_PATH  = FONT_PATH
-- Default outline flags for text that names none. The global-font settings
-- overwrite BOTH fields early at ADDON_LOADED; UI.Font must therefore read the
-- exported fields, not the local above -- the local exists only as the shipped
-- default and for code that wants Expressway regardless of the setting.
UI.FONT_FLAGS = ""

-- Strips "(...)" hints from labels and dropdown values; the full text stays in the tooltip.
function UI.StripParens(s)
    if type(s) ~= "string" then return s end
    return (s:gsub("%s*%b()", ""):gsub("%s+$", ""))
end
local clean = UI.StripParens

function UI.Font(fs, size, flags)
    fs:SetFont(UI.FONT_PATH, size or 12, flags or UI.FONT_FLAGS)
    return fs
end

-- Like UI.Font, but a module's own font override (Global Settings -> Fonts)
-- wins over the global face. Explicit flags stay explicit -- text that chose
-- its outline keeps it; only unflagged text follows the module outline.
function UI.FontFor(modKey, fs, size, flags)
    local path = ns.ModuleFontPath and ns.ModuleFontPath(modKey) or UI.FONT_PATH
    local fl = flags
    if fl == nil then
        fl = ns.ModuleFontFlags and ns.ModuleFontFlags(modKey) or UI.FONT_FLAGS
    end
    fs:SetFont(path, size or 12, fl)
    return fs
end

-- ------------------------------------------------------- text edge --
--
-- Two things about text edges on this client that are not what the API
-- suggests:
--
--   * FontString:SetShadowOffset at runtime draws no drop shadow. A shadow
--     shows only when it comes with a FONT OBJECT. So a string is first given
--     one of two font objects of ours (shadow / none) and THEN its face and
--     size with SetFont; the shadow survives the SetFont, the text colour too.
--   * The engine can draw an outline through its vector renderer ("SLUG" in
--     the flags): smooth, even edges instead of the stepped bitmap outline.
--     Whether this client knows the token is asked once, at the first use: a
--     probe string is given it and keeps it only when it is understood.
local shadowObj, plainObj
local function edgeObjects()
    if shadowObj then return end
    shadowObj = CreateFont("VuloForeverUIShadowFont")
    shadowObj:SetFont(FONT_PATH, 12, "")
    shadowObj:SetShadowColor(0, 0, 0, 1)
    shadowObj:SetShadowOffset(1, -1)
    plainObj = CreateFont("VuloForeverUIPlainFont")
    plainObj:SetFont(FONT_PATH, 12, "")
    plainObj:SetShadowColor(0, 0, 0, 0)
    plainObj:SetShadowOffset(0, 0)
end

-- Call BEFORE SetFont / UI.FontFor: the font object would replace the face.
function UI.TextShadow(fs, on)
    if not (fs and fs.SetFontObject) then return end
    edgeObjects()
    fs:SetFontObject(on and shadowObj or plainObj)
end

local slugKnown
local function slugSupported()
    if slugKnown == nil then
        slugKnown = false
        local probe = UIParent:CreateFontString(nil, "OVERLAY")
        local ok, set = pcall(probe.SetFont, probe, FONT_PATH, 12, "OUTLINE, SLUG")
        if ok and set ~= false then
            local _, _, flags = probe:GetFont()
            slugKnown = type(flags) == "string" and flags:find("SLUG", 1, true) ~= nil
        end
        probe:Hide()
    end
    return slugKnown
end

-- The flags with the smooth renderer added, for an outline on a client that
-- has it. Text without an outline stays as it is.
function UI.SmoothFlags(flags)
    if type(flags) ~= "string" or not flags:find("OUTLINE", 1, true) or flags:find("SLUG", 1, true) then
        return flags
    end
    if not slugSupported() then return flags end
    return flags .. ", SLUG"
end

function UI.SmoothSupported() return slugSupported() end

-- SetGradient(tex, orient, ...): first color is bottom/left, second is top/right.
function UI.SetGradient(tex, orient, r1, g1, b1, a1, r2, g2, b2, a2)
    tex:SetTexture("Interface\\Buttons\\WHITE8X8")
    if tex.SetGradient and CreateColor then
        tex:SetGradient(orient, CreateColor(r1, g1, b1, a1), CreateColor(r2, g2, b2, a2))
    elseif tex.SetGradientAlpha then
        tex:SetGradientAlpha(orient, r1, g1, b1, a1, r2, g2, b2, a2)
    else
        tex:SetColorTexture((r1 + r2) / 2, (g1 + g2) / 2, (b1 + b2) / 2, ((a1 or 1) + (a2 or 1)) / 2)
    end
end

-- Pooled widgets are reused with a new _vcConfig, so the tooltip text has to be
-- read at hover time. Every widget below builds its spec through this.
-- A row label lives in a measured column and is cut when the translation runs
-- long -- German option names do that regularly. When it has been cut, the full
-- name leads the tooltip and the explanation follows it; a row whose label
-- fits is left exactly as it was.
--
-- GetStringWidth reports what the text NEEDS, GetWidth what the column gave it,
-- so the comparison is the truncation test without having to reproduce the
-- client's ellipsis logic. One pixel of slack, because the two disagree by
-- about that much on a string that only just fits.
local function labelClipped(fs)
    if not fs or not fs:IsShown() then return nil end
    local text = fs:GetText()
    if not text or text == "" then return nil end
    local room = fs:GetWidth() or 0
    if room <= 0 then return nil end
    if (fs:GetStringWidth() or 0) <= room + 1 then return nil end
    return text
end

local function configTip(self)
    local cfg = self._vcConfig
    local text = cfg and cfg.tooltip
    local full = labelClipped(self._label or self._labelFS)
    if not text then
        return full and { title = full, wrap = true } or nil
    end
    if not full then return { title = text, wrap = true } end
    return { title = full, wrap = true, lines = { { text, nil, nil, nil, true } } }
end

local function tooltipShow(self) UI:ShowTooltip(self, configTip(self)) end
local function tooltipHide() UI:HideTooltip() end

-- Installed once and reading the live _vcConfig: pooled widgets would otherwise stack hooks.
local function attachTooltip(frame)
    frame:SetScript("OnEnter", tooltipShow)
    frame:SetScript("OnLeave", tooltipHide)
end

W.FONT_PATH     = FONT_PATH
W.clean         = clean
W.labelClipped  = labelClipped
W.configTip     = configTip
W.attachTooltip = attachTooltip
