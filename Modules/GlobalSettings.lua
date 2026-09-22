-- GlobalSettings: sidebar entry with two tabs — General (UI scale, camera, minimap button) and Profile (delegates to the Profiles module).
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("globalsettings", {
    name        = "Global Settings",
    group       = "Global",
    description = "Global UI settings + profile management.",
    -- Per TAB, because this module owns the profile tab and only delegates its
    -- options -- there is no "profile" module to carry the flag.
    optionsGrid = { profile = true, general = true, fonts = true, colors = true, styles = true },
    defaults    = {
        enabled    = true,
        themeColor = { r = 0.608, g = 0.424, b = 1.000 },   -- house purple
    },
})

mod.tabs = {
    { id = "general",  label = "General" },
    { id = "fonts",    label = "Fonts" },
    { id = "colors",   label = "Colors" },
    -- Styles sits next to Fonts and Colors because it answers the same kind of
    -- question -- what the suite LOOKS like, across every module -- rather than
    -- what one module does.
    { id = "styles",   label = "Styles" },
    { id = "profile",  label = "Profile" },
    -- Bar setups get their own tab rather than a ninth section on the profile
    -- page. Two reasons: on that page it would need scrolling to reach, which
    -- is the problem it was moved out of the sidebar to solve; and "profile"
    -- would then mean two different things -- a settings profile and a saved
    -- bar layout -- one above the other.
    --
    -- The id is the MODULE KEY on purpose. Modules/Vulslot.lua sets
    -- parentTab = "globalsettings", and the framework's rule for that pair is
    -- tabId == module key: it is what makes BuildOptionsPage("vulslot") from
    -- inside the module land on this tab instead of nowhere.
    { id = "vulslot", label = "Bar Setups" },
}

local function setCVar(cvar, val)
    pcall(SetCVar, cvar, tostring(val))
end

local function getCVarNum(cvar)
    local v = (C_CVar and C_CVar.GetCVar and C_CVar.GetCVar(cvar))
           or (GetCVar and GetCVar(cvar))
    return tonumber(v) or 0
end

-- The client clamps the uiScale CVar at 0.64, so a smaller scale survives only
-- as long as nobody reloads: the CVar comes back as 0.64 and UIParent with it.
-- The chosen value is therefore remembered account-wide and put back onto
-- UIParent at login and whenever the client rescales the UI.
local function storedUIScale()
    local g = ns.db and ns.db.global
    return g and tonumber(g.uiScale) or nil
end

local function reapplyUIScale()
    local scale = storedUIScale()
    if not scale or not (UIParent and UIParent.SetScale) then return end
    if math.abs(UIParent:GetScale() - scale) < 0.0005 then return end
    if ns:InCombat() then
        ns:RegisterEventOnce("PLAYER_REGEN_ENABLED", reapplyUIScale)
        return
    end
    pcall(UIParent.SetScale, UIParent, scale)
end

local function applyUIScale(scale)
    if not scale or scale <= 0 then return end
    if ns.db and ns.db.global then ns.db.global.uiScale = scale end
    -- useUiScale must be "1" for uiScale to take effect
    setCVar("useUiScale", "1")
    setCVar("uiScale", scale)
    reapplyUIScale()
end

ns:RegisterEvent("PLAYER_ENTERING_WORLD", reapplyUIScale)
ns:RegisterEvent("UI_SCALE_CHANGED", reapplyUIScale)
ns:RegisterEvent("DISPLAY_SIZE_CHANGED", reapplyUIScale)

local function pixelPerfectScale()
    -- 768 / vertical physical resolution
    if GetPhysicalScreenSize then
        local _, h = GetPhysicalScreenSize()
        if h and h > 0 then return 768 / h end
    end
    return 0.65
end

-- StaticPopup for profiling toggle (requires /reload for the CVar to take effect)
local THEME_PRESETS
ns.OnLocaleReady(function()
StaticPopupDialogs["VFUI_RELOAD_PROFILING"] = {
    text = L["Script profiling changed. /reload required for the CPU display to update."],
    button1 = L["Reload now"],
    button2 = L["Later"],
    OnAccept = function() ReloadUI() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- StaticPopup for theme color (already-painted textures keep the old color
-- until the UI reloads)
StaticPopupDialogs["VFUI_RELOAD_THEME"] = {
    text = L["Theme color changed. /reload applies it to everything (elements already drawn keep the old color until then)."],
    button1 = L["Reload now"],
    button2 = L["Later"],
    OnAccept = function() ReloadUI() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- StaticPopup for the global font (existing text keeps its font until reload)
StaticPopupDialogs["VFUI_RELOAD_FONT"] = {
    text = L["Font changed. /reload required to apply it everywhere."],
    button1 = L["Reload now"],
    button2 = L["Later"],
    OnAccept = function() ReloadUI() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

THEME_PRESETS = {
    { value = "9b6cff", text = L["Purple (default)"] },
    { value = "4f9bff", text = L["Blue"] },
    { value = "37d67a", text = L["Green"] },
    { value = "ff5c5c", text = L["Red"] },
    { value = "ffd100", text = L["Gold"] },
    { value = "2dd4cf", text = L["Turquoise"] },
    { value = "ff6ec7", text = L["Pink"] },
    { value = "ff8c1a", text = L["Orange"] },
}
end)

local function themeHex()
    local c = mod.db and mod.db.themeColor or {}
    return string.format("%02x%02x%02x",
        math.floor((c.r or 0.608) * 255 + 0.5),
        math.floor((c.g or 0.424) * 255 + 0.5),
        math.floor((c.b or 1.000) * 255 + 0.5))
end

local function setTheme(r, g, b)
    mod.db.themeColor = { r = r, g = g, b = b }
    if ns.ApplyThemeColor then ns:ApplyThemeColor() end
    StaticPopup_Show("VFUI_RELOAD_THEME")
end

-- ===== Fonts & Colors tab =================================================

-- Shipped resource colors, snapshotted at file load BEFORE anything mutates
-- ns.POWER_COLORS in place.
local POWER_DEFAULTS = {}
for tok, c in pairs(ns.POWER_COLORS) do
    POWER_DEFAULTS[tok] = { r = c.r, g = c.g, b = c.b }
end

-- Client defaults, captured on first apply BEFORE any override is laid over
-- them, so clearing an override restores the exact client color.
local defaultClassColors = {}

-- The addon's OWN class color book. Deliberately not Blizzard's table:
-- writing RAID_CLASS_COLORS marks every entry as ours, and Blizzard's compact
-- party/raid frames read that table while they build their members -- the
-- read marks the whole execution and the next protected call in combat is
-- refused with this addon named. Measured 11.08.2026 (flowsort probe): the
-- clean edit-mode login apply turned ours exactly at the class color read
-- inside CompactUnitFrame_UpdateAll, and the session ended in a blocked
-- CompactPartyFramePet4:Hide(). So overrides live here, our own painters read
-- this book, and Blizzard-owned displays keep stock colors on purpose.
ns.CLASS_COLORS = {}

-- Single lookup for every painter: the book first (defaults + overrides),
-- the stock table as read-only guard for lookups before the first apply.
function ns.ClassColor(token)
    if not token then return nil end
    local c = ns.CLASS_COLORS[token]
    if c then return c end
    local rcc = _G.RAID_CLASS_COLORS
    return rcc and rcc[token] or nil
end

local function applyGlobalFont()
    local db = ns.db and ns.db.global and ns.db.global.fonts
    if not db then return end
    ns.UI.FONT_PATH  = (ns.MediaFont and ns.MediaFont(db.font)) or ns.UI.FONT_PATH
    ns.UI.FONT_FLAGS = (db.outline and db.outline ~= "NONE") and db.outline or ""
end
-- The first-time setup (UI/Setup.lua) offers the same font and scale rows;
-- it goes through these so the two pages cannot drift apart.
ns.ApplyGlobalFont   = applyGlobalFont
ns.ApplyUIScale      = applyUIScale
ns.PixelPerfectScale = pixelPerfectScale

-- Per-module font overrides: g.fonts.modules[key] = { font = <media name>,
-- outline = <mode> }, either field absent = follow the global font. Resolved at
-- text-creation time through UI.FontFor; like the global font, a change takes
-- a /reload to reach text that is already on screen (the reference resolves
-- the same way and reloads too -- no live reapply loop to maintain).
function ns.ModuleFontPath(key)
    local db = ns.db and ns.db.global and ns.db.global.fonts
    local o = db and db.modules and db.modules[key]
    local name = o and o.font
    return (name and ns.MediaFont and ns.MediaFont(name)) or ns.UI.FONT_PATH
end

function ns.ModuleFontFlags(key)
    local db = ns.db and ns.db.global and ns.db.global.fonts
    local o = db and db.modules and db.modules[key]
    local m = o and o.outline
    if not m then return ns.UI.FONT_FLAGS end
    return m ~= "NONE" and m or ""
end

-- The client keeps a registry of every named font object; replacing the face
-- there reaches chat, tooltips, quest text and the rest without a hook. Size
-- and flags stay native. Pull-style consumers pick the path up on their own.
local function applyGameTextFont()
    local db = ns.db and ns.db.global and ns.db.global.fonts
    if not db or not db.gameText then return end
    -- No combat guard on purpose: SetFont on font objects is not protected,
    -- and a guard here turned a reload issued during combat into a whole
    -- session without the font (PLAYER_LOGIN fires while still in lockdown).
    local path = ns.UI.FONT_PATH
    _G.STANDARD_TEXT_FONT = path
    if type(GetFonts) == "function" then
        for _, name in ipairs(GetFonts() or {}) do
            local obj = type(name) == "string" and _G[name] or name
            if type(obj) == "table" and obj.GetFont and obj.SetFont then
                local _, size, flags = obj:GetFont()
                if size then pcall(obj.SetFont, obj, path, size, flags) end
            end
        end
    end
    -- The sweep just rewrote the combat-number font objects CombatText owns;
    -- its appliers take them back and no-op when their switches are off.
    local ct = ns.modules and ns.modules.combattext
    if ct and ct._enabled then
        if ct.ReapplySharpFonts     then ct.ReapplySharpFonts()     end
        if ct.ReapplyDamageTextFont then ct.ReapplyDamageTextFont() end
    end
end

-- In-place field mutation, never table replacement: every consumer in this
-- addon reads ns.CLASS_COLORS / ns.POWER_COLORS at paint time and may cache a
-- reference, so rewriting the fields recolors everything on its next repaint.
-- An absent override restores the captured client default. Blizzard's
-- RAID_CLASS_COLORS is read once for the defaults and never written;
-- PowerBarColor is not touched at all -- see the book comment above.
local function applyCustomColors()
    local g = ns.db and ns.db.global
    if not g then return end

    local rcc = _G.RAID_CLASS_COLORS
    if rcc then
        for tok, c in pairs(rcc) do
            if not defaultClassColors[tok] then
                defaultClassColors[tok] = { r = c.r, g = c.g, b = c.b }
            end
            local own = ns.CLASS_COLORS[tok]
            if not own then own = {}; ns.CLASS_COLORS[tok] = own end
            local src = g.classColors[tok] or defaultClassColors[tok]
            own.r, own.g, own.b = src.r, src.g, src.b
            -- colorStr is what our chat and name coloring read; it must follow.
            own.colorStr = string.format("ff%02x%02x%02x",
                math.floor(own.r * 255 + 0.5),
                math.floor(own.g * 255 + 0.5),
                math.floor(own.b * 255 + 0.5))
        end
    end

    for tok, own in pairs(ns.POWER_COLORS) do
        local src = g.powerColors[tok] or POWER_DEFAULTS[tok]
        if src then own.r, own.g, own.b = src.r, src.g, src.b end
    end
end

-- Applied at ADDON_LOADED (before any module builds a frame) and again on
-- every setter. PLAYER_LOGIN re-runs the game-text pass each session because
-- font objects reset with the client.
ns.OnLocaleReady(function()
    applyGlobalFont()
    applyCustomColors()
end)
-- One hook for the profile import: a string carrying look data applies it
-- through this instead of waiting for the next login.
ns.ApplyLookSettings = function()
    applyGlobalFont()
    applyCustomColors()
    applyGameTextFont()
end
ns:RegisterEvent("PLAYER_LOGIN", applyGameTextFont)

local CLASS_ORDER = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST",
                      "SHAMAN", "MAGE", "WARLOCK", "DRUID", "DEATHKNIGHT" }

local OUTLINE_VALUES  -- built lazily: labels are locale lookups

-- The module-fonts list, modeled on the reference layout the user pointed at
-- (23.08.2026): one row per module, a dropdown whose first entry follows the
-- global font. ALL rows store in g.fonts.modules[key].font -- account-wide
-- like the global font, so no class or profile carries a different reach than
-- its neighbours (review find: the nameplates row briefly wrote the module
-- db and would have read empty on every other class). Read through
-- ns.ModuleFontPath at text-creation time. Uniform apply semantics: /reload,
-- like the global font itself -- no live reapply loop to maintain.
local MODULE_FONT_DEFS  -- built lazily: labels are locale lookups

local function moduleFontValues()
    local v = { { value = "", text = L["Global Font"] } }
    for _, e in ipairs(ns.MediaFontValues and ns.MediaFontValues() or {}) do
        v[#v + 1] = e
    end
    return v
end

local function moduleFontsSection()
    local g = ns.db.global

    MODULE_FONT_DEFS = MODULE_FONT_DEFS or {
        { key = "actionbars", name = L["Action Bars"],
          desc = L["Button texts (keybind, macro name, count) and the XP bar text."] },
        { key = "nameplates", name = L["Nameplates"],
          desc = L["Name, level, health, cast and aura text on nameplates."] },
        { key = "cooldownmanager", name = L["Cooldown Manager"],
          desc = L["Duration, stacks and keybind text on the icons, the strip and the resource bar."] },
        { key = "chat", name = L["Chat"],
          desc = L["Chat messages, the input box and the tab labels, while the chat module uses the addon font."] },
        { key = "characterpanel", name = L["Character Panel"],
          desc = L["The stats sheet of the modern character panel."] },
        { key = "auras", name = L["Auras"],
          desc = L["Time left and stack count on your own buff and debuff icons."] },
    }

    local rows = {
        { type = "desc",
          text = L["|cffaaaaaaGive single modules their own font; everything else follows the global font. Changes need a /reload.|r"] },
    }
    for _, def in ipairs(MODULE_FONT_DEFS) do
        local d = def
        rows[#rows + 1] = {
            type = "dropdown", label = d.name, width = 220, noOverride = true,
            values = moduleFontValues(),
            tooltip = d.desc .. "\n\n|cffaaaaaa" .. L["Requires /reload."] .. "|r",
            get = function()
                local m = g.fonts.modules
                local o = m and m[d.key]
                return (o and o.font) or ""
            end,
            set = function(_, v)
                if v == "" then v = nil end
                local m = g.fonts.modules
                if v then
                    -- created on first real override, not on opening the tab
                    if not m then m = {}; g.fonts.modules = m end
                    m[d.key] = m[d.key] or {}
                    m[d.key].font = v
                elseif m and m[d.key] then
                    m[d.key].font = nil
                    if next(m[d.key]) == nil then m[d.key] = nil end
                    if next(m) == nil then g.fonts.modules = nil end
                end
                StaticPopup_Show("VFUI_RELOAD_FONT")
            end,
        }
    end
    return { type = "section", title = L["Module Fonts"], items = rows }
end

local function fontsOptions()
    local g = ns.db.global
    local fdb = g.fonts

    OUTLINE_VALUES = OUTLINE_VALUES or {
        { value = "NONE",         text = L["None"] },
        { value = "OUTLINE",      text = L["Outline"] },
        { value = "THICKOUTLINE", text = L["Thick Outline"] },
    }

    local fontRows = {
        { type = "dropdown", label = L["Global Font"], noOverride = true,
          tooltip = L["The font for the whole VuloForeverUI interface. Fonts shared by other addons appear here too.\n\n|cffaaaaaaRequires /reload to apply everywhere.|r"],
          values = ns.MediaFontValues and ns.MediaFontValues() or {},
          get = function() return fdb.font end,
          set = function(_, v)
              fdb.font = v
              applyGlobalFont()
              StaticPopup_Show("VFUI_RELOAD_FONT")
          end },

        { type = "dropdown", label = L["Outline Mode"], noOverride = true,
          tooltip = L["Default outline for VuloForeverUI text. Elements with their own outline setting keep it.\n\n|cffaaaaaaRequires /reload to apply everywhere.|r"],
          values = OUTLINE_VALUES,
          get = function() return fdb.outline or "NONE" end,
          set = function(_, v)
              fdb.outline = v
              applyGlobalFont()
              StaticPopup_Show("VFUI_RELOAD_FONT")
          end },

        { type = "toggle", label = L["Apply to All Game Texts"], noOverride = true,
          tooltip = L["Replaces the font of the game's own texts (chat, tooltips, quest log and more) with the global font.\n\n|cffaaaaaaTurning it off requires /reload to restore the original fonts.|r"],
          get = function() return fdb.gameText end,
          set = function(_, v)
              fdb.gameText = v and true or false
              if v then
                  applyGameTextFont()
              else
                  StaticPopup_Show("VFUI_RELOAD_FONT")
              end
          end },
    }

    return {
        { type = "section", title = L["Global Font"], items = fontRows },
        moduleFontsSection(),
    }
end

-- The Styles tab. Empty on purpose for now: a page of settings that nothing
-- reads yet would be a page of switches that do nothing, and the checker says
-- so out loud (module defaults nothing reads).
local function stylesOptions()
    return {
        { type = "desc", text = L["|cffaaaaaaNothing here yet. This tab is where the look shared by every module will live -- bar textures, borders and backdrops, the way Fonts and Colors already work.|r"] },
    }
end

local function colorsOptions()
    local g = ns.db.global

    -- Only classes this era can PLAY (the fixed order above) and this client
    -- can NAME. The client's color table is retail-complete and also carries
    -- classes that do not exist here -- iterating it raised DEMONHUNTER and
    -- MONK rows with raw token labels on a client that has neither. The name
    -- check alone is not enough either: the death knight is namable on 2.5.x
    -- but playable only on the Wrath-based client (Titan Reforged 3.80.x), so
    -- he carries an explicit era gate.
    local classRows = {}
    do
        local rcc   = _G.RAID_CLASS_COLORS or {}
        local names = _G.LOCALIZED_CLASS_NAMES_MALE or {}
        local tokens = {}
        for _, tok in ipairs(CLASS_ORDER) do
            if rcc[tok] and names[tok]
               and tok ~= "DEATHKNIGHT" then
                tokens[#tokens + 1] = tok
            end
        end

        for _, tok in ipairs(tokens) do
            local token = tok
            classRows[#classRows + 1] = {
                type = "color", label = names[token],
                labelTint = true, noOverride = true,
                get = function() return ns.CLASS_COLORS[token] or _G.RAID_CLASS_COLORS[token] end,
                set = function(r, gg, b)
                    g.classColors[token] = { r = r, g = gg, b = b }
                    applyCustomColors()
                end,
                onReset = function()
                    g.classColors[token] = nil
                    applyCustomColors()
                end,
            }
        end
    end

    -- Resource rows only for powers this client can name; the label is the
    -- client's own localized string. Runic power rides the same era gate as
    -- the death knight -- its string exists on 2.5.x, the resource does not.
    local powerRows = {}
    for _, tok in ipairs({ "MANA", "RAGE", "ENERGY", "FOCUS" }) do
        local token = tok
        local name = _G[token]
        if type(name) == "string" and name ~= ""
        then
            powerRows[#powerRows + 1] = {
                type = "color", label = name,
                labelTint = true, noOverride = true,
                get = function() return ns.POWER_COLORS[token] end,
                set = function(r, gg, b)
                    g.powerColors[token] = { r = r, g = gg, b = b }
                    applyCustomColors()
                end,
                onReset = function()
                    g.powerColors[token] = nil
                    applyCustomColors()
                end,
            }
        end
    end

    return {
        { type = "section", title = L["Class Colors"],    items = classRows },
        { type = "section", title = L["Resource Colors"], items = powerRows },
    }
end

-- ===== Optimized graphics =================================================

-- The reference's optimized-graphics preset, values ported 1:1. Neither client
-- family could be proven offline -- the extracted source tree carries no
-- graphics settings definitions at all -- so every CVar is runtime-guarded
-- instead: GetCVar answering nil (or throwing, which legacy GetCVar does on an
-- unknown name) means this client does not know the setting, and it is skipped
-- in both directions, apply and backup. The button reports what it touched.
local OPTIMIZED_CVARS = {
    { "graphicsShadowQuality",     "1" },
    { "graphicsLiquidDetail",      "0" },
    { "graphicsParticleDensity",   "5" },
    { "graphicsSSAO",              "0" },
    { "graphicsDepthEffects",      "0" },
    { "graphicsComputeEffects",    "0" },
    { "graphicsOutlineMode",       "0" },
    { "graphicsTextureResolution", "2" },
    { "graphicsSpellDensity",      "1" },
    { "graphicsProjectedTextures", "1" },
    { "graphicsViewDistance",      "1" },
    { "graphicsEnvironmentDetail", "1" },
    { "graphicsGroundClutter",     "1" },
    { "RAIDsettingsEnabled",       "0" },
    { "ResampleAlwaysSharpen",     "1" },
}

local function getCVarRaw(cvar)
    local ok, v = pcall(function()
        if C_CVar and C_CVar.GetCVar then return C_CVar.GetCVar(cvar) end
        if GetCVar then return GetCVar(cvar) end
    end)
    if ok then return v end
end

local function applyOptimizedGfx()
    if ns:InCombat() then ns:Print(L["Not possible in combat."]); return end
    local g = ns.db and ns.db.global
    if not g then return end
    -- One-time snapshot: a second click re-applies but must not overwrite the
    -- backup with already-optimized values, or restore would restore those.
    local fresh  = not g.gfxBackup
    local backup = g.gfxBackup or {}
    local applied = 0
    for _, entry in ipairs(OPTIMIZED_CVARS) do
        local cvar, value = entry[1], entry[2]
        local cur = getCVarRaw(cvar)
        if cur ~= nil then
            if fresh then backup[cvar] = tostring(cur) end
            setCVar(cvar, value)
            applied = applied + 1
        end
    end
    -- Contrast rides along like in the reference: +10 while at/below 55, so
    -- the lowered settings do not read as washed out. Backed up on FIRST
    -- TOUCH, not on the first click: a first click at 60 skips it, and when a
    -- later click finds it lowered and boosts it, that boost must be in the
    -- backup too or restore breaks its promise for this one setting.
    local contrast = tonumber(getCVarRaw("Contrast"))
    if contrast and contrast <= 55 then
        if backup.Contrast == nil then backup.Contrast = tostring(contrast) end
        setCVar("Contrast", contrast + 10)
        applied = applied + 1
    end
    if fresh and applied > 0 then g.gfxBackup = backup end
    ns:Print(L["Graphics optimized: %d settings applied."], applied)
    ns.UI:BuildOptionsPage("globalsettings", "general")
end

local function restoreGfxSettings()
    if ns:InCombat() then ns:Print(L["Not possible in combat."]); return end
    local g = ns.db and ns.db.global
    local backup = g and g.gfxBackup
    if not backup then return end
    -- Walked over the BACKUP, not the preset table: only what was actually
    -- touched on this client goes back, including Contrast when it rode along.
    for cvar, saved in pairs(backup) do
        setCVar(cvar, saved)
    end
    g.gfxBackup = nil
    ns:Print(L["Graphics settings restored."])
    ns.UI:BuildOptionsPage("globalsettings", "general")
end

-- Three sections in a two-column grid, modeled on the reference layout the
-- user pointed at (31.07.2026): the optimize button centred above everything,
-- a dense Display block, camera on its own, and a Developer block at the
-- bottom. The old page was six one-row headers in a single column; the headers
-- Language/Theme color/Minimap/Performance Display folded into rows or
-- tooltips of the Display section.
local function generalOptions()
    local display = {
        { type = "dropdown", label = L["Theme color"],
          tooltip = L["|cffaaaaaaColors everything that is purple today in the color of your choice - sidebar, borders, highlights, bars. A /reload applies it everywhere.|r"],
          values = THEME_PRESETS,
          get = function() return themeHex() end,
          set = function(_, v)
              local r = tonumber(v:sub(1, 2), 16) / 255
              local g = tonumber(v:sub(3, 4), 16) / 255
              local b = tonumber(v:sub(5, 6), 16) / 255
              setTheme(r, g, b)
          end },
        { type = "color", label = L["Custom color"],
          get = function() return mod.db.themeColor end,
          set = function(r, g, b) setTheme(r, g, b) end },

        { type = "slider", label = L["UI Scale"],
          min = 0.40, max = 1.15, step = 0.01,
          tooltip = L["Manual UI scaling. 0.65 is smaller, 1.0 is default."],
          get = function() return storedUIScale() or getCVarNum("uiScale") end,
          set = function(_, v) applyUIScale(v) end },

        -- Directly under the client's own scale, because the two get confused
        -- otherwise: that one moves the whole game, this one moves this window
        -- and nothing else. It takes effect while you drag it -- the window you
        -- are dragging it in IS the preview.
        { type = "slider", label = L["Settings Window Scale"],
          min = 0.70, max = 1.30, step = 0.05,
          tooltip = L["Scales this settings window on its own. The game's interface keeps the size it has."],
          get = function() return ns.UI:MainFrameScale() end,
          set = function(_, v) ns.UI:SetMainFrameScale(v) end },

        { type = "toggle", label = L["Show Minimap Button"],
          tooltip = L["Toggle the VuloForeverUI button on the minimap."],
          get = function()
              return ns:IsModuleEnabled("minimap")
          end,
          set = function(_, v)
              if ns.ToggleModule then ns:ToggleModule("minimap", v) end
          end },
    }

    -- The client's own always-on profiler needs neither the CVar nor a reload,
    -- so on those clients there is nothing left to switch and the readout is
    -- simply always there. The old switch only appears where it still does work.
    local prof = _G.C_AddOnProfiler
    local alwaysOnProfiler =
        prof and prof.GetAddOnMetric and (not prof.IsEnabled or prof.IsEnabled())
    if not alwaysOnProfiler then
        display[#display + 1] = { type = "toggle", label = L["Show CPU Usage in Header"],
            tooltip = L["Shows total CPU usage of all active addons (plus VuloForeverUI's own share) at the top of the config header.\n\n|cffaaaaaaRequires /reload after toggling.\n\nNote: Enables WoW's scriptProfile CVar, which costs ~3-5% performance — that's the price for WoW collecting this data at all.|r"],
            get = function() return getCVarNum("scriptProfile") == 1 end,
            set = function(_, v)
                setCVar("scriptProfile", v and "1" or "0")
                StaticPopup_Show("VFUI_RELOAD_PROFILING")
            end }
    end

    display[#display + 1] = { type = "group", layout = "row", gap = 8,
        items = {
            { type = "button", label = L["Pixel Perfect"], width = 130,
              onClick = function()
                  local s = pixelPerfectScale()
                  applyUIScale(s)
                  ns:Print(L["UI Scale = %.4f (pixel perfect)"], s)
              end },
            { type = "button", label = L["1080p Scale"], width = 130,
              onClick = function() applyUIScale(768/1080); ns:Print(L["UI Scale = 0.7111 (1080p)"]) end },
            { type = "button", label = L["1440p Scale"], width = 130,
              onClick = function() applyUIScale(768/1440); ns:Print(L["UI Scale = 0.5333 (1440p)"]) end },
        },
    }

    display[#display + 1] = { type = "button", label = L["Open setup again"], width = 200,
        tooltip = L["Show the first-time setup again: template, font and scale."],
        onClick = function() if ns.ShowSetup then ns:ShowSetup() end end }

    if alwaysOnProfiler then
        display[#display + 1] = { type = "desc",
            text = L["|cffaaaaaaThe header shows how much frame time VuloForeverUI costs. Your client measures this on its own, all the time — no setting and no reload needed.|r"] }
    end

    -- Centred pair above all sections, like the reference places it. The
    -- restore button exists only while a backup does; both click handlers
    -- rebuild the page, which is what makes it appear and disappear.
    local gfxRow = {
        type = "group", layout = "row", gap = 10, align = "center",
        items = {
            { type = "button", label = L["Optimize My FPS and Graphics"],
              width = 240, primary = true,
              tooltip = L["Applies a proven set of graphics settings that noticeably raises FPS while keeping the game looking good - shadows, liquids, ambient occlusion and view distance go down, textures and spell effects stay sharp. Your current values are saved first and the restore button brings them back. Only settings this client knows are touched."],
              onClick = applyOptimizedGfx },
        },
    }
    if ns.db and ns.db.global and ns.db.global.gfxBackup then
        gfxRow.items[#gfxRow.items + 1] = {
            type = "button", label = L["Restore My Graphics Settings"],
            tooltip = L["Returns every graphics setting the optimize button changed to its previous value and removes the backup."],
            onClick = restoreGfxSettings }
    end

    return {
        gfxRow,

        { type = "section", title = L["Display"], items = display },

        { type = "section", title = L["Camera"], items = {
            { type = "slider", label = L["Max Camera Distance"],
              min = 1.0, max = 3.4, step = 0.1,
              tooltip = L["Maximum camera distance (CVar cameraDistanceMaxZoomFactor)."],
              get = function() return getCVarNum("cameraDistanceMaxZoomFactor") end,
              set = function(_, v) setCVar("cameraDistanceMaxZoomFactor", v) end },
        } },

        { type = "section", title = L["Developer"], items = {
            -- The CVar is the state: the client saves it account-wide on its
            -- own, so there is nothing to store or to re-apply at login.
            -- noOverride on both toggles: account-level switches make no sense
            -- replayed per talent group, and the replay would even print the
            -- module-disabled line on every switch.
            { type = "toggle", label = L["Suppress Lua Errors"], noOverride = true,
              tooltip = L["Hides the game's own Lua error popup (CVar scriptErrors). Errors still happen and error-collecting addons still see them - they just stop interrupting you."],
              get = function() return getCVarNum("scriptErrors") == 0 end,
              set = function(_, v) setCVar("scriptErrors", v and "0" or "1") end },

            -- Drives the existing Tooltip IDs module instead of duplicating its
            -- hooks; per-ID fine-tuning stays on that module's own page.
            { type = "toggle", label = L["Show IDs in Tooltips"], noOverride = true,
              tooltip = L["Shows spell, item, NPC and other IDs in tooltips. Which ID types appear can be fine-tuned on the Tooltip IDs page in the Extras group."],
              get = function() return ns:IsModuleEnabled("tooltipids") end,
              set = function(_, v)
                  if ns.ToggleModule then ns:ToggleModule("tooltipids", v) end
              end },

            -- Shows the popup /vfui reset shows (alert, reload, own combat
            -- re-check in OnAccept) instead of wiping anything on its own —
            -- and refuses in combat the same way the slash path does.
            { type = "button", label = L["Reset All Settings"], width = 300,
              primary = true, danger = true,
              onClick = function()
                  if ns:InCombat() then ns:Print(L["Not possible in combat."]); return end
                  StaticPopup_Show("VFUI_DB_RESET")
              end },
        } },
    }
end

-- Both delegating tabs hand the page to the module that owns it, so the options
-- live next to the code they drive instead of being copied here.
local function delegate(key, missingText)
    local m = ns.modules and ns.modules[key]
    if m and m.GetOptions then
        local ok, items = pcall(m.GetOptions, m)
        if ok and items then return items end
    end
    return { { type = "desc", text = missingText } }
end

function mod:GetOptions(tabId)
    if tabId == "fonts" then
        return fontsOptions()
    end
    if tabId == "colors" then
        return colorsOptions()
    end
    if tabId == "styles" then
        return stylesOptions()
    end
    if tabId == "profile" then
        return delegate("profiles", L["|cffff5555Profile module not loaded.|r"])
    end
    if tabId == "vulslot" then
        return delegate("vulslot", L["|cffff5555Bar setups module not loaded.|r"])
    end
    return generalOptions()
end
