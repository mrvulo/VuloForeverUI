-- VuloForeverUI / Core / Theme: the look of the settings window and every
-- window built from the same widgets (Edit Mode panel, dialogs, popups, color
-- picker). A theme is a palette written INTO ns.COLORS in place, so every
-- painter that reads ns.COLORS at paint time follows it without knowing themes
-- exist. Chosen under Global Settings -> Styles; a /reload applies it, because
-- textures already painted keep the color they were given.
local _, ns = ...

-- Every painter reads through here instead of writing numbers:
--   tex:SetColorTexture(ns.TC("control"))      -- the theme's own alpha
--   tex:SetColorTexture(ns.TC("textHi", 0.05)) -- a wash in the text color
function ns.TC(key, a)
    local c = ns.COLORS[key] or ns.COLORS.text
    return c.r, c.g, c.b, a or c.a or 1
end

local function rgb(r, g, b, a) return { r = r, g = g, b = b, a = a } end

-- Beyond the palette a theme may carry:
--   accent    "theme" = the Theme color setting, "class" = the player's class
--             color, a table = fixed
--   art       "classic" = UIPanelButton, UICheckButton and UISlider art;
--             "modern" = the same button with the minimal checkbox and slider
--             knob of Blizzard's own settings panel (UI/Widgets.lua)
--   window    { layout = NineSlice layout name, bgFile? } for the settings
--             window (UI.ApplyWindowArt)
--   listArt   the sidebar's selected and hover rows use the settings panel's
--             list atlases
--   edge      border width in pixels; titleFont the window title's font
-- All art named here is art Forever's own FrameXML loads (checked against the
-- 1.60.1 source and atlas list).
ns.THEMES = {
    vulo = {
        accent = "theme",
        bg = rgb(0.06, 0.06, 0.08, 0.96), bgLight = rgb(0.055, 0.055, 0.07, 0.96),
        bgContent = rgb(0.08, 0.08, 0.10, 0.96),
        border = rgb(0.25, 0.25, 0.30, 1), borderDark = rgb(0.02, 0.02, 0.03, 1),
        text = rgb(1, 1, 1), textHi = rgb(1, 1, 1), label = rgb(0.95, 0.95, 0.97),
        heading = rgb(0.92, 0.90, 0.96), textSoft = rgb(0.80, 0.80, 0.86),
        textDim = rgb(0.65, 0.65, 0.70), textMuted = rgb(0.50, 0.50, 0.56),
        sectionHdr = rgb(0.55, 0.50, 0.60), toggleOff = rgb(0.20, 0.20, 0.23, 1),
        input = rgb(0.04, 0.04, 0.055, 0.95), popup = rgb(0.06, 0.06, 0.08, 0.98),
        card = rgb(0.09, 0.09, 0.115, 0.95), chip = rgb(0.12, 0.12, 0.15, 0.95),
        control = rgb(0.13, 0.13, 0.16, 1), controlHover = rgb(0.19, 0.19, 0.23, 1),
        track = rgb(0.10, 0.10, 0.13, 1), thumb = rgb(0.97, 0.97, 1.0, 1),
        knobOff = rgb(0.72, 0.72, 0.78, 1), divider = rgb(0.32, 0.32, 0.38),
        barTop = rgb(0.085, 0.085, 0.11, 1), barBottom = rgb(0.045, 0.045, 0.06, 1),
        knob = rgb(1, 1, 1, 1), danger = rgb(0.92, 0.40, 0.40),
    },
    -- Blizzard's classic windows: metal frame over rock, red buttons, the old
    -- checkbox and slider knob.
    blizzard = {
        accent = rgb(1.0, 0.82, 0.0), edge = 2, titleFont = "Fonts\\FRIZQT__.TTF",
        art = "classic",
        window = { layout = "ButtonFrameTemplateNoPortrait", bgFile = "Interface\\FrameGeneral\\UI-Background-Rock" },
        bg = rgb(0.04, 0.04, 0.035, 0.97), bgLight = rgb(0.03, 0.03, 0.025, 0.55),
        bgContent = rgb(0.02, 0.02, 0.02, 0.40),
        border = rgb(0.48, 0.39, 0.21, 1), borderDark = rgb(0.48, 0.39, 0.21, 1),
        text = rgb(1, 1, 1), textHi = rgb(1, 1, 1), label = rgb(1, 1, 1),
        heading = rgb(1.0, 0.82, 0.0), textSoft = rgb(0.85, 0.82, 0.74),
        textDim = rgb(0.72, 0.68, 0.58), textMuted = rgb(0.50, 0.47, 0.40),
        sectionHdr = rgb(1.0, 0.82, 0.0), toggleOff = rgb(0.22, 0.19, 0.14, 1),
        input = rgb(0, 0, 0, 0.9), popup = rgb(0.07, 0.06, 0.05, 0.98),
        card = rgb(0.09, 0.08, 0.06, 0.95), chip = rgb(0.12, 0.10, 0.07, 0.95),
        control = rgb(0.42, 0.08, 0.04, 1), controlHover = rgb(0.56, 0.12, 0.06, 1),
        track = rgb(0.15, 0.13, 0.09, 1), thumb = rgb(0.90, 0.88, 0.80, 1),
        knobOff = rgb(0.60, 0.55, 0.45, 1), divider = rgb(0.48, 0.39, 0.21),
        barTop = rgb(0.13, 0.11, 0.08, 0.45), barBottom = rgb(0.07, 0.06, 0.045, 0.45),
        knob = rgb(1, 1, 1, 1), danger = rgb(1.0, 0.72, 0.60),
    },
    -- Blizzard's current settings panel: the same metal frame over a flat dark
    -- panel, minimal checkbox and slider, list-row art in the sidebar.
    retail = {
        accent = rgb(1.0, 0.82, 0.0), titleFont = "Fonts\\FRIZQT__.TTF",
        art = "modern", listArt = true,
        window = { layout = "ButtonFrameTemplateNoPortrait" },
        bg = rgb(0.05, 0.05, 0.06, 0.97), bgLight = rgb(0, 0, 0, 0.35),
        bgContent = rgb(0, 0, 0, 0.20),
        border = rgb(0.30, 0.30, 0.30, 1), borderDark = rgb(0.20, 0.20, 0.20, 1),
        text = rgb(1, 1, 1), textHi = rgb(1, 1, 1), label = rgb(1, 1, 1),
        heading = rgb(1.0, 0.82, 0.0), textSoft = rgb(0.85, 0.85, 0.85),
        textDim = rgb(0.65, 0.65, 0.65), textMuted = rgb(0.50, 0.50, 0.50),
        sectionHdr = rgb(1.0, 0.82, 0.0), toggleOff = rgb(0.18, 0.18, 0.18, 1),
        input = rgb(0, 0, 0, 0.6), popup = rgb(0.06, 0.06, 0.07, 0.98),
        card = rgb(0.10, 0.10, 0.11, 0.80), chip = rgb(0.12, 0.12, 0.13, 0.90),
        control = rgb(0.14, 0.14, 0.15, 1), controlHover = rgb(0.20, 0.20, 0.21, 1),
        track = rgb(0.12, 0.12, 0.12, 1), thumb = rgb(1, 1, 1, 1),
        knobOff = rgb(0.60, 0.60, 0.60, 1), divider = rgb(0.35, 0.35, 0.35),
        barTop = rgb(0.10, 0.10, 0.10, 0.5), barBottom = rgb(0.05, 0.05, 0.05, 0.5),
        knob = rgb(1, 1, 1, 1), danger = rgb(1.0, 0.45, 0.40),
    },
    flat = {
        accent = "class",
        bg = rgb(0.105, 0.105, 0.115, 0.97), bgLight = rgb(0.08, 0.08, 0.085, 0.97),
        bgContent = rgb(0.105, 0.105, 0.115, 0.97),
        border = rgb(0, 0, 0, 1), borderDark = rgb(0, 0, 0, 1),
        text = rgb(0.91, 0.91, 0.91), textHi = rgb(1, 1, 1), label = rgb(0.91, 0.91, 0.91),
        heading = rgb(0.95, 0.95, 0.95), textSoft = rgb(0.78, 0.78, 0.80),
        textDim = rgb(0.60, 0.60, 0.63), textMuted = rgb(0.42, 0.42, 0.45),
        sectionHdr = rgb(0.54, 0.54, 0.56), toggleOff = rgb(0.20, 0.20, 0.21, 1),
        input = rgb(0.07, 0.07, 0.075, 1), popup = rgb(0.09, 0.09, 0.095, 0.98),
        card = rgb(0.14, 0.14, 0.15, 0.95), chip = rgb(0.16, 0.16, 0.17, 0.95),
        control = rgb(0.165, 0.165, 0.175, 1), controlHover = rgb(0.22, 0.22, 0.23, 1),
        track = rgb(0.08, 0.08, 0.085, 1), thumb = rgb(0.95, 0.95, 0.95, 1),
        knobOff = rgb(0.60, 0.60, 0.62, 1), divider = rgb(0.25, 0.25, 0.27),
        barTop = rgb(0.08, 0.08, 0.085, 1), barBottom = rgb(0.08, 0.08, 0.085, 1),
        knob = rgb(1, 1, 1, 1), danger = rgb(0.92, 0.40, 0.40),
    },
    -- Crisp pixel look: neutral grays, black one-pixel lines, a cool blue for
    -- everything that is active.
    pixel = {
        accent = rgb(0.09, 0.52, 0.82),
        bg = rgb(0.06, 0.06, 0.06, 0.92), bgLight = rgb(0.10, 0.10, 0.10, 0.95),
        bgContent = rgb(0.06, 0.06, 0.06, 0.92),
        border = rgb(0, 0, 0, 1), borderDark = rgb(0, 0, 0, 1),
        text = rgb(1, 1, 1), textHi = rgb(1, 1, 1), label = rgb(0.93, 0.93, 0.93),
        heading = rgb(1, 1, 1), textSoft = rgb(0.80, 0.80, 0.80),
        textDim = rgb(0.60, 0.60, 0.60), textMuted = rgb(0.42, 0.42, 0.42),
        sectionHdr = rgb(0.09, 0.52, 0.82), toggleOff = rgb(0.15, 0.15, 0.15, 1),
        input = rgb(0.03, 0.03, 0.03, 1), popup = rgb(0.08, 0.08, 0.08, 0.97),
        card = rgb(0.10, 0.10, 0.10, 0.95), chip = rgb(0.12, 0.12, 0.12, 0.95),
        control = rgb(0.10, 0.10, 0.10, 1), controlHover = rgb(0.16, 0.16, 0.16, 1),
        track = rgb(0.04, 0.04, 0.04, 1), thumb = rgb(0.90, 0.90, 0.90, 1),
        knobOff = rgb(0.55, 0.55, 0.55, 1), divider = rgb(0.20, 0.20, 0.20),
        barTop = rgb(0.10, 0.10, 0.10, 1), barBottom = rgb(0.10, 0.10, 0.10, 1),
        knob = rgb(1, 1, 1, 1), danger = rgb(0.90, 0.30, 0.30),
    },
}
ns.THEME_ORDER = { "vulo", "blizzard", "retail", "flat", "pixel" }

-- The active theme table; painters that need more than a color (border width,
-- title font, art) read it here.
ns.theme = ns.THEMES.vulo

local function hex(c)
    return string.format("%02x%02x%02x", math.floor(c.r * 255 + 0.5),
        math.floor(c.g * 255 + 0.5), math.floor(c.b * 255 + 0.5))
end

-- Writes theme `key` into ns.COLORS in place. themeColor is the Theme color
-- setting, used only by a theme whose accent is "theme".
function ns:ApplyUIStyle(key, themeColor)
    local t = ns.THEMES[key] or ns.THEMES.vulo
    ns.theme = t
    for k, v in pairs(t) do
        if type(v) == "table" and k ~= "accent" and v.r then
            local own = ns.COLORS[k]
            if own then
                own.r, own.g, own.b, own.a = v.r, v.g, v.b, v.a
            else
                ns.COLORS[k] = { r = v.r, g = v.g, b = v.b, a = v.a }
            end
        end
    end

    local c = t.accent
    if c == "class" then
        local _, token = UnitClass("player")
        c = (ns.ClassColor and ns.ClassColor(token))
            or (_G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[token])
    elseif c == "theme" then
        c = themeColor
    end
    if not (type(c) == "table" and type(c.r) == "number") then
        c = { r = 0.608, g = 0.424, b = 1.000 }
    end
    local A, D = ns.COLORS.accent, ns.COLORS.accentDim
    A.r, A.g, A.b = c.r, c.g, c.b
    D.r, D.g, D.b = c.r * 0.5, c.g * 0.47, c.b * 0.5
    if ns.C then
        ns.C.accent = "|cff" .. hex(c)
        ns.PREFIX = ns.C.accent .. "VuloForeverUI|r"
    end
end
