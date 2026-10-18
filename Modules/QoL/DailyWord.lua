-- VuloForeverUI / Modules / QoL / DailyWord
--
-- A word game for the time on a flight: guess the five-letter word of the day
-- in six tries. Green is the right letter in the right place, yellow a letter
-- the word has elsewhere, grey one it does not have.
--
--   * one word a day (the player's own calendar day), the same for everyone
--     with the same language -- German for a German addon, English otherwise
--   * a button beside the flight-time bar opens it while flying; landing
--     closes the window, /vfword opens it any time to play on
--   * the day's guesses and the statistics are account-wide
--     (global.qolDailyWord), so a game started on one character finishes on
--     another
--
-- Typing goes into an invisible edit box that holds the keyboard focus while
-- the window is open: no protected key propagation, and Escape closes.
local _, ns = ...
local L = ns.L

local QoL = ns.QoL
local Word = QoL.RegisterPart("dailyword", {})
QoL.DailyWord = Word

local LEN, TRIES = 5, 6
local TILE, GAP = 40, 5
local KEY_W, KEY_H, KEY_GAP = 24, 30, 3
local W = 300
local GREEN  = { 0.42, 0.67, 0.39 }
local YELLOW = { 0.79, 0.69, 0.30 }
local GREY   = { 0.22, 0.22, 0.25 }

local ROWS = {
    de = { "qwertzuiop", "asdfghjkl", "yxcvbnm" },
    en = { "qwertyuiop", "asdfghjkl", "zxcvbnm" },
}

local window, input, buttonOnBar
local current = ""          -- the guess being typed
local message               -- text under the grid until the next key
local guessSet = {}         -- [lang] = { word = true }

local function db() return QoL.db().dailyWord end

-- ------------------------------------------------------------- the day --

local function lang()
    local over = _G.VuloForeverUIDB and _G.VuloForeverUIDB.localeOverride
    local loc = (type(over) == "string" and over ~= "" and over ~= "auto") and over or GetLocale()
    return (loc or ""):sub(1, 2) == "de" and "de" or "en"
end

-- Day 1 is 18 October 2026; noon keeps a clock change from moving the day.
local function dayIndex()
    local t = date("*t")
    local today = math.floor(time({ year = t.year, month = t.month, day = t.day, hour = 12 }) / 86400)
    local first = math.floor(time({ year = 2026, month = 10, day = 18, hour = 12 }) / 86400)
    return today - first + 1
end

local function secondsToMidnight()
    local t = date("*t")
    return time({ year = t.year, month = t.month, day = t.day + 1, hour = 0 }) - time()
end

local function data() return ns.DailyWordData[lang()] end

local function answerOf(day)
    local a = data().answers
    local n = #a / LEN
    local i = ((day - 1) % n) * LEN
    return a:sub(i + 1, i + LEN)
end

local function known(word)
    local l = lang()
    local set = guessSet[l]
    if not set then
        set = {}
        local g = data().guesses
        for i = 1, #g, LEN do set[g:sub(i, i + LEN - 1)] = true end
        local a = data().answers
        for i = 1, #a, LEN do set[a:sub(i, i + LEN - 1)] = true end
        guessSet[l] = set
    end
    return set[word] == true
end

-- -------------------------------------------------------------- state --

local function store()
    local g = ns.db and ns.db.global
    if not g then return {} end
    if type(g.qolDailyWord) ~= "table" then g.qolDailyWord = {} end
    return g.qolDailyWord
end

local function game()
    local s, l, day = store(), lang(), dayIndex()
    local cur = s[l]
    if type(cur) ~= "table" or cur.day ~= day then
        cur = { day = day, guesses = {} }
        s[l] = cur
    end
    return cur
end

local function stats()
    local s, l = store(), lang()
    s.stats = s.stats or {}
    s.stats[l] = s.stats[l] or { played = 0, wins = 0, streak = 0, best = 0 }
    return s.stats[l]
end

-- Two passes, as the game has it: greens first, so a letter the word holds
-- once is not shown yellow a second time.
local function score(guess, answer)
    local out, left = {}, {}
    for i = 1, LEN do
        local a = answer:sub(i, i)
        if guess:sub(i, i) == a then out[i] = 3 else left[a] = (left[a] or 0) + 1 end
    end
    for i = 1, LEN do
        if not out[i] then
            local c = guess:sub(i, i)
            if (left[c] or 0) > 0 then out[i] = 2; left[c] = left[c] - 1 else out[i] = 1 end
        end
    end
    return out
end

local function finish(g, won)
    g.done, g.won = true, won
    local st = stats()
    st.played = st.played + 1
    if won then
        st.wins = st.wins + 1
        st.streak = (st.lastWin == g.day - 1) and st.streak + 1 or 1
        st.best = math.max(st.best, st.streak)
        st.lastWin = g.day
    else
        st.streak = 0
    end
end

-- ------------------------------------------------------------- window --

local function colour(tex, c) tex:SetColorTexture(c[1], c[2], c[3], 1) end

local function makeTile(parent, size)
    local t = CreateFrame("Frame", nil, parent)
    t:SetSize(size, size)
    t.bg = t:CreateTexture(nil, "BACKGROUND")
    t.bg:SetAllPoints(t)
    t.edges = ns.MakeEdges(t, "BORDER")
    ns.LayoutEdges(t.edges, t, 1, 0.32, 0.32, 0.36, 1)
    t.text = t:CreateFontString(nil, "OVERLAY")
    ns.UI.Font(t.text, math.floor(size * 0.5), "")
    t.text:SetPoint("CENTER")
    return t
end

local function paint()
    if not (window and window:IsShown()) then return end
    local g, answer = game(), answerOf(dayIndex())
    window.title:SetText(L["Daily Word #%d"]:format(g.day))
    local keys = {}
    for r = 1, TRIES do
        local guess = g.guesses[r]
        local typing = not guess and not g.done and r == #g.guesses + 1
        local marks = guess and score(guess, answer)
        for c = 1, LEN do
            local t = window.tiles[r][c]
            local ch = guess and guess:sub(c, c) or (typing and current:sub(c, c)) or ""
            t.text:SetText(ch:upper())
            if marks then
                colour(t.bg, marks[c] == 3 and GREEN or marks[c] == 2 and YELLOW or GREY)
                local k = keys[ch]
                if not k or marks[c] > k then keys[ch] = marks[c] end
            else
                t.bg:SetColorTexture(0.05, 0.05, 0.06, 0.9)
            end
        end
    end
    for ch, key in pairs(window.keys) do
        local k = keys[ch]
        if k then colour(key.bg, k == 3 and GREEN or k == 2 and YELLOW or { 0.12, 0.12, 0.13 })
        else key.bg:SetColorTexture(0.30, 0.30, 0.34, 1) end
    end
    if message then
        window.note:SetText(message)
    elseif g.done then
        window.note:SetText(g.won and L["Solved in %d."]:format(#g.guesses)
            or L["The word was %s."]:format(answer:upper()))
    else
        window.note:SetText("")
    end
    local st = stats()
    window.stats:SetText(L["Played %d  ·  Won %d%%  ·  Streak %d  ·  Best %d"]:format(
        st.played, st.played > 0 and math.floor(st.wins / st.played * 100 + 0.5) or 0, st.streak, st.best))
end

local function press(key)
    local g = game()
    message = nil
    if g.done then paint(); return end
    if key == "ENTER" then
        if #current < LEN then
            message = L["Not enough letters."]
        elseif not known(current) then
            message = L["Not in the word list."]
        else
            g.guesses[#g.guesses + 1] = current
            local won = current == answerOf(g.day)
            current = ""
            if won or #g.guesses >= TRIES then finish(g, won) end
        end
    elseif key == "BACK" then
        current = current:sub(1, -2)
    elseif #current < LEN and key:match("^%l$") then
        current = current .. key
    end
    paint()
end

local function keyRow(f, letters, y, extra)
    local wide = KEY_W * 1.6
    local width = #letters * (KEY_W + KEY_GAP) - KEY_GAP + (extra and 2 * (wide + KEY_GAP) or 0)
    local x = (W - width) / 2
    local function key(label, value, w)
        local b = CreateFrame("Button", nil, f)
        b:SetSize(w, KEY_H)
        b:SetPoint("TOPLEFT", x, y)
        x = x + w + KEY_GAP
        b.bg = b:CreateTexture(nil, "BACKGROUND")
        b.bg:SetAllPoints(b)
        b.bg:SetColorTexture(0.30, 0.30, 0.34, 1)
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints(b)
        hl:SetColorTexture(1, 1, 1, 0.12)
        local fs = b:CreateFontString(nil, "OVERLAY")
        ns.UI.Font(fs, 11, "")
        fs:SetPoint("CENTER")
        fs:SetText(label)
        b:SetScript("OnClick", function() press(value) end)
        return b
    end
    if extra then key(L["Enter"], "ENTER", wide) end
    for i = 1, #letters do
        local ch = letters:sub(i, i)
        f.keys[ch] = key(ch:upper(), ch, KEY_W)
    end
    if extra then key("<", "BACK", wide) end
end

local function build()
    if window then return window end
    local f = CreateFrame("Frame", "VuloForeverUIDailyWord", UIParent)
    f:SetSize(W, 470)
    f:SetPoint("CENTER", 0, 60)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    ns.UI:StyleBackdrop(f)
    ns.UI:CreateCloseX(f, function() f:Hide() end)
    tinsert(UISpecialFrames, "VuloForeverUIDailyWord")

    f.title = f:CreateFontString(nil, "OVERLAY")
    ns.UI.Font(f.title, 14, "")
    f.title:SetPoint("TOPLEFT", 14, -12)
    f.title:SetTextColor(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b)
    f.next = f:CreateFontString(nil, "OVERLAY")
    ns.UI.Font(f.next, 11, "")
    f.next:SetPoint("TOP", 0, -36)
    f.next:SetTextColor(0.65, 0.65, 0.70)

    f.tiles = {}
    local gridW = LEN * TILE + (LEN - 1) * GAP
    for r = 1, TRIES do
        f.tiles[r] = {}
        for c = 1, LEN do
            local t = makeTile(f, TILE)
            t:SetPoint("TOPLEFT", (W - gridW) / 2 + (c - 1) * (TILE + GAP), -56 - (r - 1) * (TILE + GAP))
            f.tiles[r][c] = t
        end
    end
    local gridBottom = -56 - TRIES * (TILE + GAP)

    f.note = f:CreateFontString(nil, "OVERLAY")
    ns.UI.Font(f.note, 11, "")
    f.note:SetPoint("TOP", 0, gridBottom - 2)
    f.note:SetWidth(W - 24)

    f.keys = {}
    local rows = ROWS[lang()]
    local y = gridBottom - 20
    for i, letters in ipairs(rows) do
        keyRow(f, letters, y, i == #rows)
        y = y - KEY_H - KEY_GAP
    end

    f.stats = f:CreateFontString(nil, "OVERLAY")
    ns.UI.Font(f.stats, 10, "")
    f.stats:SetPoint("BOTTOM", 0, 10)
    f.stats:SetTextColor(0.65, 0.65, 0.70)

    -- the keyboard: an edit box nobody sees, focused while the window is open
    input = CreateFrame("EditBox", nil, f)
    input:SetSize(1, 1)
    input:SetPoint("TOPLEFT")
    input:SetAutoFocus(false)
    input:SetFontObject(ChatFontNormal)
    input:SetAlpha(0)
    input:SetScript("OnChar", function(self, ch)
        self:SetText("")
        ch = ch and ch:lower()
        if ch and ch:match("^%l$") then press(ch) end
    end)
    input:SetScript("OnEnterPressed", function() press("ENTER") end)
    input:SetScript("OnEscapePressed", function() f:Hide() end)
    input:SetScript("OnKeyDown", function(_, key)
        if key == "BACKSPACE" then press("BACK") end
    end)

    local since = 0
    f:SetScript("OnUpdate", function(_, elapsed)
        since = since + elapsed
        if since < 0.5 then return end
        since = 0
        local s = secondsToMidnight()
        f.next:SetText(L["Next word in %s"]:format(("%d:%02d:%02d"):format(
            math.floor(s / 3600), math.floor(s % 3600 / 60), math.floor(s % 60))))
        -- a new day while it is open
        if game().day ~= dayIndex() then current = ""; paint() end
    end)
    f:SetScript("OnShow", function() input:SetFocus(); paint() end)
    f:SetScript("OnHide", function() input:ClearFocus() end)
    f:Hide()
    window = f
    return f
end

-- ------------------------------------------------------------- public --

function Word.Toggle()
    build()
    if window:IsShown() then window:Hide() else window:Show() end
end

function Word.Open()
    build()
    window:Show()
end

-- Landing closes the game; the state stays, /vfword plays on.
function Word.OnLanded()
    if window and window:IsShown() then window:Hide() end
end

-- The button beside the flight-time bar (Flight.lua calls this once).
function Word.AttachButton(bar)
    if buttonOnBar or not bar then return end
    local b = ns.UI:CreateButton(bar, { label = L["Word"], width = 54, height = math.max(16, bar:GetHeight()),
        onClick = function() Word.Toggle() end })
    b:SetPoint("LEFT", bar, "RIGHT", 4, 0)
    b.bar = bar
    b:SetScript("OnEnter", function(self)
        ns.UI:ShowTooltip(self, { title = L["Daily Word"], accent = true,
            lines = { L["Guess the word of the day while you fly. /vfword opens it any time."] } })
    end)
    b:SetScript("OnLeave", function() ns.UI:HideTooltip() end)
    buttonOnBar = b
    Word.Apply()
end

-- Beside the bar, behind the land-early button when that one is shown: both
-- sit right of the bar, and on the same spot the word button covered it.
function Word.Place()
    local b = buttonOnBar
    if not b then return end
    local bar, land = b.bar, b.bar.land
    b:ClearAllPoints()
    if land and land:IsShown() then
        b:SetPoint("LEFT", land, "RIGHT", 3, 0)
        b:SetHeight(land:GetHeight())
    else
        b:SetPoint("LEFT", bar, "RIGHT", 4, 0)
        b:SetHeight(math.max(16, bar:GetHeight()))
    end
end

function Word.Apply()
    local on = QoL.mod.active and db().enabled and true or false
    if buttonOnBar then buttonOnBar:SetShown(on) end
    if on then
        ns:RegisterSlash({ key = "DAILYWORD", commands = { "/vfword" },
            desc = "Open the daily word game." })
    end
end

function Word.Disable()
    if buttonOnBar then buttonOnBar:Hide() end
    if window then window:Hide() end
end

ns.Slash = ns.Slash or {}
ns.Slash.DAILYWORD = function()
    if QoL.mod.active and db().enabled then Word.Toggle() end
end
