-- VuloForeverUI / UI / Setup: the first-time setup, three steps in a modal.
--
-- A new account sees it once, a second after the first login: pick a
-- starting template, set font and scale, reload. Nothing here switches a
-- module live -- the template is written into the profile and the reload at
-- the end applies it, which is the one path every module survives.
-- Reachable again through /vfui setup and a button under Global Settings.
local _, ns = ...
local L = ns.L
ns.UI = ns.UI or {}
local UI = ns.UI

local CreateFrame = CreateFrame
local ipairs, pairs = ipairs, pairs

local DIALOG_W, DIALOG_H = 560, 510
local PAD  = 18
local FOOT = 50

local host, dlg
local w = {}           -- widgets by name
local step = 1
local chosen = "standard"

-- ---------------------------------------------------------------------------
-- Templates. on/off name modules relative to their registered default; every
-- key any template names is written on every run, so choosing Standard after
-- Minimal really restores the shipped state.
-- ---------------------------------------------------------------------------
local TEMPLATES = {
    { key = "standard",
      name = "Standard",
      desc = "Every module as the addon ships it: the dark look, the HUD, bags, nameplates, the combat meter and the class tools.",
      on = {}, off = {} },
    { key = "minimal",
      name = "Minimal",
      desc = "Only the look: the dark skin for the game's windows, chat, bags, unit frames and the character panel. No HUD modules, no nameplates, no meter. Switch on later what you miss.",
      on = {},
      off = { "meter", "cooldownmanager", "actionring", "combattext", "reminders", "trackbars",
              "powerbar", "actionbars", "nameplates", "playercastbar", "cooldownpulse", "fontbars",
              "swingtimer", "vtmanadisplay", "arenaframes", "lazyvulo", "vulfishing",
              "disenchantqueue", "goldtracker", "trinkets", "vullfg", "queuetimer",
              "autoitembuy", "loadouts" } },
    { key = "healer",
      name = "Healer",
      desc = "The standard set plus what a healer watches: the meter opens on healing, the power bar and the buff reminders are on, and the combat text shows your heals.",
      on = { "powerbar", "reminders", "combattext" }, off = {},
      meter = "heal" },
    { key = "pvp",
      name = "PvP",
      desc = "The standard set plus the arena frames, the trinket tracker, the power bar and the reminders; the meter opens on damage.",
      on = { "arenaframes", "trinkets", "powerbar", "reminders", "combattext" }, off = {},
      meter = "damage" },
}

local function templateByKey(key)
    for _, t in ipairs(TEMPLATES) do
        if t.key == key then return t end
    end
    return TEMPLATES[1]
end

-- Module on/off lives per character with the profile default behind it. The
-- template writes the default in the active profile AND in "Default" (the
-- seed every new class profile is copied from) and drops the character's own
-- override, so the choice holds for this class and for classes rolled later.
-- The seed holds only what differs from the defaults (the logout strip
-- empties it), so the entry is created here rather than looked for.
local function setModuleDefault(key, state)
    local mod = ns.modules[key]
    if not mod then return end
    if mod.db then mod.db.enabled = state end
    local profiles = VuloForeverUIDB and VuloForeverUIDB.profiles
    local seed = profiles and profiles.Default
    if seed and seed ~= ns.db.profile then
        seed.modules = seed.modules or {}
        local entry = seed.modules[key]
        if not entry then
            entry = {}
            seed.modules[key] = entry
        end
        entry.enabled = state
    end
    local ov = VuloForeverUICharDB and VuloForeverUICharDB.modEnabled
    if ov then ov[key] = nil end
end

-- Runs once, at the end (Reload now / Later): a template chosen and then
-- backed out of must leave nothing behind. Every key any template names is
-- written, so Standard after Minimal is the shipped state again. The meter
-- keeps its window list and positions; only the first window's mode follows
-- the template (damage is what ships).
local function applyTemplate(t)
    local state = {}
    for _, tt in ipairs(TEMPLATES) do
        for _, key in ipairs(tt.on)  do state[key] = state[key] or "default" end
        for _, key in ipairs(tt.off) do state[key] = state[key] or "default" end
    end
    for _, key in ipairs(t.on)  do state[key] = true  end
    for _, key in ipairs(t.off) do state[key] = false end
    for key, s in pairs(state) do
        if s == "default" then
            local mod = ns.modules[key]
            s = mod and mod.defaults and mod.defaults.enabled and true or false
        end
        setModuleDefault(key, s)
    end
    local meter = ns.modules.meter
    if meter and meter.db then
        local list = meter.db.windows
        if type(list) ~= "table" then
            list = {}
            meter.db.windows = list
        end
        if not list[1] then list[1] = { segment = "current" } end
        list[1].mode = t.meter or "damage"
    end
    if ns.db and ns.db.global then ns.db.global.setupTemplate = t.key end
end

local function markDone()
    if ns.db and ns.db.global then ns.db.global.setupDone = true end
end

local function finish()
    applyTemplate(templateByKey(chosen))
    markDone()
end

-- ---------------------------------------------------------------------------
-- Shell
-- ---------------------------------------------------------------------------
local showStep

local function close()
    markDone()
    if host then host:Hide() end
end

local function card(parent, t)
    local c = CreateFrame("Button", nil, parent)
    c:SetHeight(74)
    UI:StyleBackdrop(c, { bg = ns.COLORS.bgContent, border = ns.COLORS.border })
    c.name = c:CreateFontString(nil, "OVERLAY")
    UI.Font(c.name, 13)
    c.name:SetPoint("TOPLEFT", c, "TOPLEFT", 12, -9)
    c.name:SetText(L[t.name])
    c.desc = c:CreateFontString(nil, "OVERLAY")
    UI.Font(c.desc, 11)
    c.desc:SetPoint("TOPLEFT", c.name, "BOTTOMLEFT", 0, -4)
    c.desc:SetPoint("RIGHT", c, "RIGHT", -12, 0)
    c.desc:SetJustifyH("LEFT")
    c.desc:SetJustifyV("TOP")
    c.desc:SetWordWrap(true)
    c.desc:SetText(L[t.desc])
    local d = ns.COLORS.textDim
    c.desc:SetTextColor(d.r, d.g, d.b)
    c.key = t.key
    c:SetScript("OnClick", function(self)
        chosen = self.key
        showStep(1)
    end)
    c:SetScript("OnEnter", function(self)
        if chosen ~= self.key then
            local a = ns.COLORS.accent
            for _, b in ipairs(self._vcBorders) do b:SetColorTexture(a.r, a.g, a.b, 0.5) end
        end
    end)
    c:SetScript("OnLeave", function(self)
        if chosen ~= self.key then
            local b0 = ns.COLORS.border
            for _, b in ipairs(self._vcBorders) do b:SetColorTexture(b0.r, b0.g, b0.b, 1) end
        end
    end)
    return c
end

local function paintCards()
    local a, b0, bg, bgSel = ns.COLORS.accent, ns.COLORS.border, ns.COLORS.bgContent, ns.COLORS.bg
    for _, c in ipairs(w.cards) do
        local sel = c.key == chosen
        for _, b in ipairs(c._vcBorders) do
            if sel then b:SetColorTexture(a.r, a.g, a.b, 1) else b:SetColorTexture(b0.r, b0.g, b0.b, 1) end
        end
        local col = sel and bgSel or bg
        c._vcBG:SetColorTexture(col.r, col.g, col.b, col.a or 1)
        if sel then c.name:SetTextColor(a.r, a.g, a.b) else c.name:SetTextColor(0.95, 0.95, 0.97) end
    end
end

local function buildStep1(page)
    local intro = page:CreateFontString(nil, "OVERLAY")
    UI.Font(intro, 12)
    intro:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
    intro:SetPoint("RIGHT", page, "RIGHT", 0, 0)
    intro:SetJustifyH("LEFT")
    intro:SetWordWrap(true)
    intro:SetText(L["Choose a starting point. The template switches modules on or off for this character's profile; every setting stays editable afterwards."])
    local d = ns.COLORS.textDim
    intro:SetTextColor(d.r, d.g, d.b)

    w.cards = {}
    local prev
    for i, t in ipairs(TEMPLATES) do
        local c = card(page, t)
        if prev then
            c:SetPoint("TOPLEFT",  prev, "BOTTOMLEFT",  0, -6)
            c:SetPoint("TOPRIGHT", prev, "BOTTOMRIGHT", 0, -6)
        else
            c:SetPoint("TOPLEFT",  intro, "BOTTOMLEFT",  0, -12)
            c:SetPoint("TOPRIGHT", intro, "BOTTOMRIGHT", 0, -12)
        end
        w.cards[i] = c
        prev = c
    end
end

local OUTLINE_VALUES

local function buildStep2(page)
    OUTLINE_VALUES = OUTLINE_VALUES or {
        { value = "NONE",         text = L["None"] },
        { value = "OUTLINE",      text = L["Outline"] },
        { value = "THICKOUTLINE", text = L["Thick Outline"] },
    }
    local function fonts() return (ns.db and ns.db.global and ns.db.global.fonts) or {} end
    local function getScale()
        local v = (C_CVar and C_CVar.GetCVar and C_CVar.GetCVar("uiScale")) or (GetCVar and GetCVar("uiScale"))
        return tonumber(v) or 1
    end

    local intro = page:CreateFontString(nil, "OVERLAY")
    UI.Font(intro, 12)
    intro:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
    intro:SetPoint("RIGHT", page, "RIGHT", 0, 0)
    intro:SetJustifyH("LEFT")
    intro:SetWordWrap(true)
    intro:SetText(L["The font reaches everything after the reload at the end; the scale changes while you drag."])
    local d = ns.COLORS.textDim
    intro:SetTextColor(d.r, d.g, d.b)

    w.font = UI:CreateDropdown(page, {
        label = L["Global Font"], width = 300,
        values = ns.MediaFontValues and ns.MediaFontValues() or {},
        get = function() return fonts().font end,
        set = function(_, v)
            fonts().font = v
            if ns.ApplyGlobalFont then ns.ApplyGlobalFont() end
        end,
    })
    w.font:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", 0, -16)

    w.outline = UI:CreateDropdown(page, {
        label = L["Outline Mode"], width = 300,
        values = OUTLINE_VALUES,
        get = function() return fonts().outline or "NONE" end,
        set = function(_, v)
            fonts().outline = v
            if ns.ApplyGlobalFont then ns.ApplyGlobalFont() end
        end,
    })
    w.outline:SetPoint("TOPLEFT", w.font, "BOTTOMLEFT", 0, -10)

    w.scale = UI:CreateSlider(page, {
        label = L["UI Scale"], min = 0.40, max = 1.15, step = 0.01, width = 260,
        get = function() return getScale() end,
        set = function(_, v) if ns.ApplyUIScale then ns.ApplyUIScale(v) end end,
    })
    w.scale:SetPoint("TOPLEFT", w.outline, "BOTTOMLEFT", 0, -28)

    local function preset(label, fn, anchor, first)
        local b = UI:CreateButton(page, { label = label, width = 120, onClick = function()
            local s = fn()
            if s and ns.ApplyUIScale then ns.ApplyUIScale(s) end
            if w.scale and w.scale._vcSetup then w.scale:_vcSetup(w.scale._vcConfig) end
        end })
        if first then
            b:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -14)
        else
            b:SetPoint("LEFT", anchor, "RIGHT", 8, 0)
        end
        return b
    end
    local b1 = preset(L["Pixel Perfect"], function() return ns.PixelPerfectScale and ns.PixelPerfectScale() end, w.scale, true)
    local b2 = preset(L["1080p Scale"], function() return 768 / 1080 end, b1)
    preset(L["1440p Scale"], function() return 768 / 1440 end, b2)
end

local function buildStep3(page)
    w.summary = page:CreateFontString(nil, "OVERLAY")
    UI.Font(w.summary, 12)
    w.summary:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
    w.summary:SetPoint("RIGHT", page, "RIGHT", 0, 0)
    w.summary:SetJustifyH("LEFT")
    w.summary:SetWordWrap(true)
    w.summary:SetSpacing(4)

    local hint = page:CreateFontString(nil, "OVERLAY")
    UI.Font(hint, 11)
    hint:SetPoint("TOPLEFT", w.summary, "BOTTOMLEFT", 0, -18)
    hint:SetPoint("RIGHT", page, "RIGHT", 0, 0)
    hint:SetJustifyH("LEFT")
    hint:SetWordWrap(true)
    hint:SetText(L["You can run this again any time with /vfui setup or from Global Settings."])
    local d = ns.COLORS.textDim
    hint:SetTextColor(d.r, d.g, d.b)
end

local function fillSummary()
    local t = templateByKey(chosen)
    local f = (ns.db and ns.db.global and ns.db.global.fonts) or {}
    local scale = (C_CVar and C_CVar.GetCVar and C_CVar.GetCVar("uiScale")) or (GetCVar and GetCVar("uiScale"))
    local a = ns.COLORS.accent
    local col = string.format("|cff%02x%02x%02x",
        math.floor(a.r * 255 + 0.5), math.floor(a.g * 255 + 0.5), math.floor(a.b * 255 + 0.5))
    w.summary:SetText(
        L["Everything is written. A reload applies the template, the font and the scale."] .. "\n\n"
        .. L["Template"] .. ": " .. col .. L[t.name] .. "|r\n"
        .. L["Global Font"] .. ": " .. col .. tostring(f.font or "") .. "|r\n"
        .. L["UI Scale"] .. ": " .. col .. string.format("%.2f", tonumber(scale) or 1) .. "|r")
end

local function applyAccent()
    local ac = ns.COLORS.accent
    UI.SetGradient(w.strip, "HORIZONTAL", ac.r, ac.g, ac.b, 0.1, ac.r, ac.g, ac.b, 0.9)
    w.title:SetTextColor(ac.r, ac.g, ac.b)
end

local function ensureShell()
    if host then return end
    host = CreateFrame("Frame", "VFUI_SetupHost", UIParent)
    host:SetFrameStrata("FULLSCREEN_DIALOG")
    host:SetAllPoints(UIParent)
    host:EnableMouse(true)
    host:Hide()
    local dim = host:CreateTexture(nil, "BACKGROUND")
    dim:SetAllPoints(host)
    dim:SetColorTexture(0, 0, 0, 0.45)
    -- ESC closes like "Later": the marker is set, the dialog does not return.
    _G.UISpecialFrames = _G.UISpecialFrames or {}
    table.insert(_G.UISpecialFrames, "VFUI_SetupHost")
    host:SetScript("OnHide", markDone)

    dlg = CreateFrame("Frame", nil, host)
    dlg:SetSize(DIALOG_W, DIALOG_H)
    dlg:SetPoint("CENTER", host, "CENTER", 0, 30)
    dlg:EnableMouse(true)
    UI:StyleBackdrop(dlg, { bg = ns.COLORS.bg, border = ns.COLORS.accentDim })
    if UI.CreateShadow then UI:CreateShadow(dlg) end

    w.strip = dlg:CreateTexture(nil, "ARTWORK")
    w.strip:SetPoint("TOPLEFT", dlg, "TOPLEFT", 0, 0)
    w.strip:SetPoint("TOPRIGHT", dlg, "TOPRIGHT", 0, 0)
    w.strip:SetHeight(2)

    w.title = dlg:CreateFontString(nil, "OVERLAY")
    UI.Font(w.title, 14)
    w.title:SetPoint("TOPLEFT", dlg, "TOPLEFT", PAD, -14)
    w.title:SetText(L["Set up VuloForeverUI"])

    w.stepText = dlg:CreateFontString(nil, "OVERLAY")
    UI.Font(w.stepText, 11)
    w.stepText:SetPoint("TOPRIGHT", dlg, "TOPRIGHT", -PAD - 24, -16)
    local d = ns.COLORS.textDim
    w.stepText:SetTextColor(d.r, d.g, d.b)

    UI:CreateCloseX(dlg, close)

    w.pages = {}
    for i = 1, 3 do
        local p = CreateFrame("Frame", nil, dlg)
        p:SetPoint("TOPLEFT",     dlg, "TOPLEFT",     PAD, -48)
        p:SetPoint("BOTTOMRIGHT", dlg, "BOTTOMRIGHT", -PAD, FOOT)
        p:Hide()
        w.pages[i] = p
    end
    buildStep1(w.pages[1])
    buildStep2(w.pages[2])
    buildStep3(w.pages[3])

    -- Footer: skip / back on the left, next or finish on the right.
    w.skip = UI:CreateButton(dlg, { label = L["Skip"], width = 110, onClick = close })
    w.skip:SetPoint("BOTTOMLEFT", dlg, "BOTTOMLEFT", PAD, 14)
    w.back = UI:CreateButton(dlg, { label = L["Go back"], width = 110, onClick = function() showStep(step - 1) end })
    w.back:SetPoint("BOTTOMLEFT", dlg, "BOTTOMLEFT", PAD, 14)
    w.next = UI:CreateButton(dlg, { label = L["Next"], width = 130, primary = true, onClick = function()
        showStep(step + 1)
    end })
    w.next:SetPoint("BOTTOMRIGHT", dlg, "BOTTOMRIGHT", -PAD, 14)
    -- Later writes the template too; the next reload applies it, nothing
    -- switches live either way.
    w.later = UI:CreateButton(dlg, { label = L["Later"], width = 110, onClick = function()
        finish()
        host:Hide()
    end })
    w.later:SetPoint("BOTTOMRIGHT", dlg, "BOTTOMRIGHT", -PAD, 14)
    w.reload = UI:CreateButton(dlg, { label = L["Reload now"], width = 140, primary = true, onClick = function()
        if InCombatLockdown() then
            ns:Print(L["Not possible in combat."])
            return
        end
        finish()
        ReloadUI()
    end })
    w.reload:SetPoint("RIGHT", w.later, "LEFT", -8, 0)
end

showStep = function(n)
    if n < 1 then n = 1 elseif n > 3 then n = 3 end
    step = n
    for i = 1, 3 do w.pages[i]:SetShown(i == n) end
    w.stepText:SetFormattedText(L["Step %d of %d"], n, 3)
    w.skip:SetShown(n == 1)
    w.back:SetShown(n > 1)
    w.next:SetShown(n < 3)
    w.later:SetShown(n == 3)
    w.reload:SetShown(n == 3)
    if n == 1 then paintCards() end
    if n == 2 then
        -- re-read the saved values every time the page comes up
        for _, k in ipairs({ "font", "outline", "scale" }) do
            local wd = w[k]
            if wd and wd._vcSetup then wd:_vcSetup(wd._vcConfig) end
        end
    end
    if n == 3 then fillSummary() end
end

function ns:ShowSetup()
    ensureShell()
    applyAccent()
    -- A re-run starts from the template chosen last time; a fresh account
    -- from Standard.
    local g = ns.db and ns.db.global
    chosen = (g and g.setupTemplate) or "standard"
    if not templateByKey(chosen) or templateByKey(chosen).key ~= chosen then chosen = "standard" end
    host:Show()
    showStep(1)
end
