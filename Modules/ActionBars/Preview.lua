-- VuloForeverUI / Modules / ActionBars / Preview
--
-- The live preview at the top of the settings page: twelve buttons in the
-- look the bars are set to, redrawn on every change.
--
-- The buttons are the client's own button template, not a drawing of one, and
-- they are dressed by Skin.Dress -- the very passes the real bars go through.
-- So Standard shows the client's art, Classic the 1.x ring and Modern our flat
-- border, exactly as the bars will wear them. With the whole old bar switched
-- on, the stone band is drawn behind them too.
--
-- None of it is secure: the template the real bars use adds the secure half on
-- top of this one, and the preview takes only the plain half. Its buttons have
-- no action, no clicks and no mouse, so they cannot cast, drag or taint.
--
-- It works while the module is off, which is the point: the module ships off.
local _, ns = ...
local L  = ns.L
local AB = ns.AB

local COUNT = 12
-- The first two slices of the 1.x band, drawn behind the buttons when the
-- whole old bar is on. The icons are the player's own slots 1 to 12; an empty
-- slot stays empty, so a Classic socket shows as a socket.
local BAND_FILE = "Interface\\MainMenuBar\\UI-MainMenuBar-Dwarf"
local BAND_SLICES = { { 0.83203125, 1.0 }, { 0.58203125, 0.75 } }

local row, band
local buttons = {}

local function style()
    local db = AB.db()
    if not (db and db.skin) then return "standard", false end
    return db.style or "standard", db.style == "classic" and db.classicBar
end

-- The icon of the player's own slot i, and whether there is one. The texture
-- is only handed to SetTexture, never tested for truth: type() is the one
-- question a secret value answers without an error.
local function iconOf(i)
    -- The bar picked on the settings page: whatever its live button i shows.
    -- Pet and stance bars have ten buttons, so the last two stay empty.
    local bar = AB.selectedBar or "bar1"
    local real = AB.ButtonOf(bar, i)
    if real and real.icon then
        local tex = real.icon:GetTexture()
        if type(tex) ~= "nil" and real.icon:IsShown() then return tex, true end
        return nil, false
    end
    if bar ~= "bar1" then return nil, false end
    local get = C_ActionBar and C_ActionBar.GetActionTexture
    local ok, tex = pcall(get, i)
    if ok and type(tex) ~= "nil" then return tex, true end
    return nil, false
end

local function makeButton(i)
    -- Named: the template's cooldown flash anchors to "$parent", which the
    -- client resolves by NAME, and a nameless button logs a warning per anchor.
    local ok, b = pcall(CreateFrame, "CheckButton", "VuloForeverUIPreviewActionButton" .. i, row, "ActionButtonTemplate")
    if not (ok and b) then return nil end
    -- Ours, so a field is ours to set: the client's art pass reads it to pick
    -- the with-bar-art look the main bar wears.
    b.bar = { hideBarArt = false }
    b:EnableMouse(false)
    for _, script in ipairs({ "OnEnter", "OnLeave", "OnDragStart", "OnAttributeChanged" }) do
        pcall(b.SetScript, b, script, nil)
    end
    -- The client's own art pass, once, so Standard starts from what it draws.
    if type(b.UpdateButtonArt) == "function" then pcall(b.UpdateButtonArt, b) end
    buttons[i] = b
    return b
end

local header

local function build()
    header = ns.UI:CreatePreviewHeader({ key = "actionbars", hint = true })
    row = CreateFrame("Frame", nil, header.stage)

    band = {}
    for i, v in ipairs(BAND_SLICES) do
        local t = row:CreateTexture(nil, "BACKGROUND", nil, -8)
        t:SetTexture(BAND_FILE)
        t:SetTexCoord(0, 1, v[1], v[2])
        t:SetSize(256, 43)
        t:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", (i - 1) * 256, 0)
        band[i] = t
    end

    for i = 1, COUNT do makeButton(i) end
end

-- The scale the client's own bar stands at on screen, relative to the rest of
-- the interface: Edit Mode sizes the bar, and the preview draws it that size.
local function barScale()
    local b = _G.ActionButton1
    local ok, s = pcall(function() return b:GetEffectiveScale() / UIParent:GetEffectiveScale() end)
    if ok and type(s) == "number" and s > 0 then return s end
    return 1
end

-- Pinned above the page (Options.lua hands the builder this).
function AB.BuildPreviewHeader(host)
    if not header then build() end
    header:Mount(host)
    return AB.RefreshPreview(true) or 0
end

function AB.RefreshPreview(force)
    if not header then return end
    if not force and not header:IsLive() then return end
    local look, withBand = style()

    -- 1.x spacing for Classic -- 36 pixel buttons 42 apart on the band --
    -- and the client's own 45 with a 4 pixel gap for the other two.
    local size, pitch, left, bottom = 45, 49, 0, 0
    if look == "classic" then size, pitch, left, bottom = 36, 42, 8, 4 end
    local width = left + (COUNT - 1) * pitch + size + left
    local height = withBand and 43 or size
    row:SetSize(width, height)
    local scale = header:Fit(width, height, barScale())
    row:SetScale(scale)
    row:ClearAllPoints()
    row:SetPoint("CENTER", header.stage, "CENTER", 0, 0)

    for _, t in ipairs(band) do t:SetShown(withBand and true or false) end

    for i = 1, COUNT do
        local b = buttons[i]
        if b then
            b:SetScale(size / 45)
            b:ClearAllPoints()
            b:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT",
                (left + (i - 1) * pitch) * 45 / size, bottom * 45 / size)
            local tex, filled = iconOf(i)
            if b.icon then
                if filled then b.icon:SetTexture(tex); b.icon:Show() else b.icon:Hide() end
            end
            pcall(AB.Skin.Dress, b, look, filled)
        end
    end

    header:SetNote(AB.StyleLabel(look))
    -- The row stands for the look it is dressed in. The band gets no spot of
    -- its own: it lies under the first six buttons and would take their clicks.
    header:Spot("buttons", row, { mod = "actionbars", label = L["Style"] })
    return header:SetStageHeight(height * scale)
end
