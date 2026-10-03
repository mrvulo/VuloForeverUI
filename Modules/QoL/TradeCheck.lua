-- VuloForeverUI / Modules / QoL / TradeCheck
--
-- A look at where a trade partner's gold came from, beside the trade window.
--
-- WHERE THE NUMBERS COME FROM
--
-- The character statistics of the achievement window. The client lets any
-- player compare them with another one in reach (SetAchievementComparisonUnit,
-- then INSPECT_ACHIEVEMENT_READY, then GetComparisonStatistic), the same way
-- the achievement window's compare view does. Among them: the most gold the
-- character ever owned, and every source of income the client keeps a total
-- for -- looted, quest rewards, vendor sales, auctions.
--
-- WHAT IT CONCLUDES
--
-- Gold that was never looted, earned from a quest, sold to a vendor or made
-- on the auction house came from another player: by trade or by mail. If the
-- most gold a character ever owned is far above everything it ever earned
-- itself, the rest was handed over. That is a hint, not proof -- a guild bank
-- or a generous friend look the same.
--
-- Every scan is kept account-wide (ns.db.global.qolTradeScans), together with
-- how often you traded with that character, so a second meeting has history.
local _, ns = ...
local L = ns.L

local QoL = ns.QoL
local TC = QoL.RegisterPart("tradecheck", {})
QoL.TradeCheck = TC

-- Statistic ids (Achievement table, statistics flag), stable across clients.
local STAT = {
    peak = 334, acquired = 328, looted = 333, quest = 326, vendor = 921, auction = 919,
    travel = 1146, barber = 1147, postage = 1148,
    posted = 329, bought = 330, bestBid = 331, bestSale = 332,
    quests = 98, kills = 107, dungeons = 932, deaths = 60, flights = 349,
}
local MONEY = {
    peak = true, acquired = true, looted = true, quest = true, vendor = true, auction = true,
    travel = true, barber = true, postage = true, bestBid = true, bestSale = true,
}
local PROFESSIONS = {
    { id = 1527, key = "Alchemy" },     { id = 1532, key = "Blacksmithing" },
    { id = 1535, key = "Enchanting" },  { id = 1544, key = "Engineering" },
    { id = 1538, key = "Herbalism" },   { id = 1536, key = "Leatherworking" },
    { id = 1537, key = "Mining" },      { id = 1541, key = "Skinning" },
    { id = 1542, key = "Tailoring" },   { id = 281,  key = "First Aid" },
    { id = 1524, key = "Cooking" },     { id = 1519, key = "Fishing" },
}
local LEVEL_10 = 6          -- the "Level 10" achievement: roughly the character's age
local MAX_SCANS = 10
local TIMEOUT = 5

local registered, pending, tradeKey, result
local panel, window

local function db() return QoL.db().gold end

local readable = ns.Readable

local function store()
    local g = ns.db and ns.db.global
    if not g then return {} end
    if type(g.qolTradeScans) ~= "table" then g.qolTradeScans = {} end
    return g.qolTradeScans
end

-- ---------------------------------------------------------------- money --

local function coinText(amount)
    amount = math.floor(amount or 0)
    local fn = C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString
    if fn then
        local ok, text = pcall(fn, amount)
        if ok and type(text) == "string" then return text end
    end
    return ("%dg %ds %dc"):format(amount / 10000, (amount / 100) % 100, amount % 100)
end

local function plainMoney(amount)
    amount = math.floor(amount or 0)
    return ("%dg %ds %dc"):format(amount / 10000, (amount / 100) % 100, amount % 100)
end

local function digits(s)
    return tonumber((s:gsub("[^%d]", "")))
end

local function coin(s, word)
    local n = s:match("([%d%.,]+)%s*|T[^|]-" .. word) or s:match("([%d%.,]+)%s*|A:[^|]-" .. word)
    return n and digits(n) or 0
end

-- A statistic comes back as display text: "--" for none, a number with the
-- client's separators, or for money the coin icons after each figure.
local function parse(text, isMoney)
    if type(text) ~= "string" or not text:find("%d") then return nil end
    if isMoney and (text:find("|T") or text:find("|A:")) then
        return coin(text, "[Gg]old") * 10000 + coin(text, "[Ss]ilver") * 100 + coin(text, "[Cc]opper")
    end
    return digits(text)
end

-- ----------------------------------------------------------------- scan --

local function unitName(unit)
    local name, realm = UnitName(unit)
    name, realm = readable(name), readable(realm)
    if type(name) ~= "string" then return nil end
    if type(realm) ~= "string" or realm == "" then
        realm = GetRealmName()
    end
    return name, name .. "-" .. (realm or "?")
end

local function readStats(p)
    local stats = {}
    for key, id in pairs(STAT) do
        local ok, text = pcall(GetComparisonStatistic, id)
        if ok then stats[key] = parse(readable(text), MONEY[key]) end
    end
    local profs = {}
    for _, prof in ipairs(PROFESSIONS) do
        local ok, text = pcall(GetComparisonStatistic, prof.id)
        local value = ok and parse(readable(text), false)
        if value and value > 0 then profs[#profs + 1] = { key = prof.key, value = value } end
    end
    local ok, done, month, day, year = pcall(GetAchievementComparisonInfo, LEVEL_10)
    if ok and readable(done) == true and readable(day) and readable(month) and readable(year) then
        p.level10 = ("%02d.%02d.%02d"):format(day, month, year % 100)
    end
    p.stats, p.professions = stats, profs
end

local function save(p)
    local t = store()
    local entry = t[p.key]
    if type(entry) ~= "table" then
        entry = { first = time(), trades = 0, scans = {} }
        t[p.key] = entry
    end
    -- the whole latest scan, for a mail from them while they are far away
    entry.last = { at = p.at, level = p.level, class = p.class, className = p.className,
        guild = p.guild, level10 = p.level10, stats = p.stats, professions = p.professions }
    local snap = { at = p.at, level = p.level, peak = p.stats.peak, acquired = p.stats.acquired }
    local last = entry.scans[#entry.scans]
    -- one snapshot an hour is history enough; a second trade a minute later
    -- replaces the first rather than filling the list
    if last and p.at - (last.at or 0) < 3600 then
        entry.scans[#entry.scans] = snap
    else
        entry.scans[#entry.scans + 1] = snap
        while #entry.scans > MAX_SCANS do table.remove(entry.scans, 1) end
    end
end

local refresh

local function finish(p, ok)
    if pending ~= p then return end
    pending = nil
    p.done, p.failed = true, not ok
    if ok then
        readStats(p)
        save(p)
    end
    -- leave the comparison to the achievement window if it is using it
    local cmp = _G.AchievementFrameComparison
    if not (cmp and cmp:IsShown()) then pcall(ClearAchievementComparisonUnit) end
    result = p
    refresh()
end

-- Starts reading `unit`'s statistics. The answer arrives as an event.
function TC.Scan(unit)
    if not (UnitExists(unit) and UnitIsPlayer(unit)) then return false end
    local name, key = unitName(unit)
    if not name then return false end
    local _, class = UnitClass(unit)
    local className = UnitClass(unit)
    local p = {
        unit = unit, name = name, key = key, at = time(),
        guid = readable(UnitGUID(unit)),
        level = readable(UnitLevel(unit)),
        class = readable(class), className = readable(className),
        guild = readable(GetGuildInfo(unit)),
    }
    pending, result = p, p
    pcall(ClearAchievementComparisonUnit)
    if not pcall(SetAchievementComparisonUnit, unit) then
        -- refused: the panel says so rather than vanishing
        finish(p, false)
        return true
    end
    C_Timer.After(TIMEOUT, function() finish(p, false) end)
    refresh()
    return true
end

local function onReady(_, guid)
    local p = pending
    if not p then return end
    guid = readable(guid)
    if p.guid and guid and guid ~= p.guid then return end
    finish(p, true)
end

-- --------------------------------------------------------------- verdict --

local function analyse(p, offer)
    local s = p.stats or {}
    local a = { offer = offer }
    local acq = s.acquired
    if not acq and (s.looted or s.quest or s.vendor or s.auction) then
        acq = (s.looted or 0) + (s.quest or 0) + (s.vendor or 0) + (s.auction or 0)
    end
    a.peak, a.acq = s.peak, acq
    a.spent = (s.travel or 0) + (s.barber or 0) + (s.postage or 0)
    if a.peak and acq then
        a.explained = math.min(a.peak, acq)
        a.unexplained = math.max(0, a.peak - acq)
        a.share = (a.peak > 0) and (a.explained / a.peak) or 1
        if a.unexplained <= math.max(a.peak * 0.05, 10000) then
            a.state = "good"
        elseif a.share >= 0.5 then
            a.state = "warn"
        else
            a.state = "bad"
        end
    end
    if offer and acq and acq > 0 then a.ratio = offer / acq end

    local level = p.level or 1
    local quests, kills = s.quests or 0, s.kills or 0
    a.gameplay = (quests >= math.max(5, level)) or (kills >= level * 40)

    local obs = {}
    if a.state == "good" then
        obs[#obs + 1] = { "good", L["Explained income. Recorded income covers %d%% of their peak."]:format(math.floor(a.share * 100 + 0.5)) }
    elseif a.state then
        obs[#obs + 1] = { a.state, L["%s of their peak gold has no recorded source -- it came by trade or mail."]:format(plainMoney(a.unexplained)) }
    end
    if p.stored then
        obs[#obs + 1] = { "none", L["From your scan on %s -- they are not in reach now."]:format(date("%d.%m.%Y", p.at)) }
    end
    if s.quests or s.kills then
        obs[#obs + 1] = { a.gameplay and "good" or "bad",
            (a.gameplay and L["Real gameplay present. %d quests and %d kills at level %d."]
                or L["Little gameplay: %d quests and %d kills at level %d."]):format(quests, kills, level) }
    end
    if a.ratio and a.ratio > 1 then
        obs[#obs + 1] = { "bad", L["The offer is more than everything they ever earned themselves."] }
    end
    local entry = store()[p.key]
    if entry and (entry.trades or 0) > 0 then
        obs[#obs + 1] = { "good", L["%d earlier trades with you"]:format(entry.trades) }
    end
    if entry and entry.scans and #entry.scans > 1 then
        local prev = entry.scans[#entry.scans - 1]
        if prev.peak and a.peak and a.peak > prev.peak then
            obs[#obs + 1] = { "warn", L["Peak gold rose by %s since your scan on %s."]:format(plainMoney(a.peak - prev.peak), date("%d.%m.", prev.at)) }
        end
    end
    a.obs = obs
    return a
end

local STATE_COLOR = {
    good = { 0.35, 0.85, 0.40 },
    warn = { 1.00, 0.75, 0.20 },
    bad  = { 0.95, 0.35, 0.30 },
    none = { 0.60, 0.60, 0.65 },
}

local function headline(a, p)
    if p.unknown then return L["Not in reach, and you have never scanned them. Target them when you meet them and use Scan your target."], nil end
    if not p.done then return L["Reading their statistics..."], nil end
    if p.failed then return L["No statistics -- they are out of reach or the client refused."], nil end
    if a.state == "good" then
        return L["Gold matches recorded income"], L["Recorded income covers %d%% of their peak."]:format(math.floor(a.share * 100 + 0.5))
    elseif a.state == "warn" then
        return L["Part of their gold is unexplained"], L["Recorded income covers %d%% of their peak."]:format(math.floor(a.share * 100 + 0.5))
    elseif a.state == "bad" then
        return L["Most of their gold is unexplained"], L["Recorded income covers %d%% of their peak."]:format(math.floor(a.share * 100 + 0.5))
    end
    return L["Not enough statistics to judge"], nil
end

local function offerNow()
    local m = GetTargetTradeMoney and readable(GetTargetTradeMoney())
    return type(m) == "number" and m or 0
end

local function itemsNow()
    local n = 0
    for i = 1, 6 do
        local name = GetTradeTargetItemInfo and readable(GetTradeTargetItemInfo(i))
        if name then n = n + 1 end
    end
    return n
end

-- ------------------------------------------------------------- widgets --

local function text(parent, size, r, g, b)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    ns.UI.Font(fs, size)
    fs:SetJustifyH("LEFT")
    fs:SetTextColor(r or 1, g or 1, b or 1)
    return fs
end

local function dot(parent, size)
    local t = parent:CreateTexture(nil, "OVERLAY")
    t:SetSize(size, size)
    t:SetTexture("Interface\\Buttons\\WHITE8x8")
    return t
end

local function setDot(t, state)
    local c = STATE_COLOR[state] or STATE_COLOR.none
    t:SetVertexColor(c[1], c[2], c[3], 1)
end

local function box(parent)
    local f = CreateFrame("Frame", nil, parent)
    ns.UI:StyleBackdrop(f, { bg = ns.COLORS.card })
    return f
end

-- A two-column row inside a box: label grey left, value right.
local function pairRow(parent, y, x, width)
    local l = text(parent, 11, ns.TC("textDim"))
    l:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    local r = text(parent, 11)
    r:SetJustifyH("RIGHT")
    r:SetPoint("TOPRIGHT", parent, "TOPLEFT", x + width, y)
    return { l = l, r = r }
end

local function setPair(row, label, value)
    row.l:SetText(label or "")
    row.r:SetText(value or "")
end

-- -------------------------------------------------------------- panel --

-- One panel per window it sits beside: the trade window and the open mail.
local function makePanel(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(250, 220)
    f:SetPoint("TOPLEFT", parent, "TOPRIGHT", 4, 0)
    ns.UI:StyleBackdrop(f)

    f.dot = dot(f, 9)
    f.dot:SetPoint("TOPLEFT", 12, -14)
    f.title = text(f, 14, ns.TC("heading"))
    f.title:SetPoint("LEFT", f.dot, "RIGHT", 7, 0)
    f.title:SetText(L["Gold check"])

    f.sub = text(f, 11, ns.TC("textSoft"))
    f.sub:SetPoint("TOPLEFT", 12, -32)
    f.sub:SetWidth(226)
    f.sub:SetWordWrap(true)

    f.box = box(f)
    f.box:SetPoint("TOPLEFT", 10, -60)
    f.box:SetSize(230, 70)
    f.rows = {}
    for i = 1, 4 do f.rows[i] = pairRow(f.box, -6 - (i - 1) * 15, 8, 214) end
    f.msg = text(f.box, 11, ns.TC("textSoft"))
    f.msg:SetPoint("TOPLEFT", 8, -6)
    f.msg:SetWidth(214)
    f.msg:SetWordWrap(true)

    f.obs = {}
    for i = 1, 4 do
        local d = dot(f, 6)
        d:SetPoint("TOPLEFT", 14, -142 - (i - 1) * 15)
        local fs = text(f, 11, ns.TC("textSoft"))
        fs:SetPoint("LEFT", d, "RIGHT", 6, 0)
        fs:SetWidth(214)
        fs:SetWordWrap(false)
        f.obs[i] = { d = d, fs = fs }
    end

    f.full = ns.UI:CreateButton(f, { label = L["View full scan"], width = 120, height = 22,
        onClick = function() TC.ShowWindow(f.shown) end })
    f.full:SetPoint("BOTTOMRIGHT", -10, 10)
    return f
end

local function buildPanel()
    if not panel and TradeFrame then panel = makePanel(TradeFrame) end
    return panel
end

local function fillObs(list, obs)
    for i, row in ipairs(list) do
        local o = obs and obs[i]
        if o then
            setDot(row.d, o[1]); row.d:Show()
            row.fs:SetText(o[2]); row.fs:Show()
        else
            row.d:Hide(); row.fs:Hide()
        end
    end
end

-- `p` is a scan (live or kept), `amount` what they hand over, `line` the
-- sentence under the title.
local function fillPanel(f, p, amount, line)
    f.shown = p
    local a = analyse(p, amount)
    setDot(f.dot, p.done and a.state or "none")
    f.sub:SetText(line)
    f.full:SetShown(p.stats ~= nil)
    if not p.done or p.failed or not a.state then
        f.msg:SetText((headline(a, p)))
        f.msg:Show()
        for i = 1, 4 do setPair(f.rows[i], "", "") end
        fillObs(f.obs, p.stats and a.obs or nil)
        return
    end
    f.msg:Hide()
    setPair(f.rows[1], L["Peak gold"], a.peak and coinText(a.peak) or "--")
    setPair(f.rows[2], L["Explained by recorded income"], a.explained and coinText(a.explained) or "--")
    setPair(f.rows[3], L["Unexplained"], a.unexplained and coinText(a.unexplained) or "--")
    setPair(f.rows[4], L["This offer vs recorded income"], a.ratio and ("%.1fx"):format(a.ratio) or "--")
    fillObs(f.obs, a.obs)
end

local function updatePanel()
    if not (panel and panel:IsShown() and result) then return end
    local p = result
    local offer = offerNow()
    local items = itemsNow()
    local line
    if items > 0 then
        line = L["%s offers %s and %d items."]:format(p.name, coinText(offer), items)
    else
        line = L["%s offers %s."]:format(p.name, coinText(offer))
    end
    fillPanel(panel, p, offer, line)
end

-- ------------------------------------------------------------- window --

local W, H = 640, 500

local function column(parent, x, y, title, n)
    local c = {}
    c.title = text(parent, 12, ns.TC("heading"))
    c.title:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    c.title:SetText(title)
    c.rows = {}
    for i = 1, n do c.rows[i] = pairRow(parent, y - 18 - (i - 1) * 15, x, 190) end
    return c
end

local function fillColumn(c, data)
    for i, row in ipairs(c.rows) do
        local d = data[i]
        setPair(row, d and d[1], d and d[2])
    end
end

local function buildWindow()
    if window then return window end
    local f = CreateFrame("Frame", "VuloForeverUITradeCheck", UIParent)
    f:SetSize(W, H)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    ns.UI:StyleBackdrop(f)
    tinsert(UISpecialFrames, "VuloForeverUITradeCheck")
    ns.UI:CreateCloseX(f, function() f:Hide() end)

    f.head = text(f, 12, ns.TC("textDim"))
    f.head:SetPoint("TOPLEFT", 16, -12)
    f.head:SetText(L["Gold check"])

    f.name = text(f, 20)
    f.name:SetPoint("TOPLEFT", 16, -36)
    f.info = text(f, 12, ns.TC("textSoft"))
    f.info:SetPoint("TOPLEFT", 16, -60)
    f.snaps = text(f, 11, ns.TC("textDim"))
    f.snaps:SetJustifyH("RIGHT")
    f.snaps:SetPoint("TOPRIGHT", -36, -40)

    f.banner = box(f)
    f.banner:SetPoint("TOPLEFT", 16, -82)
    f.banner:SetSize(W - 32, 46)
    f.bdot = dot(f.banner, 12)
    f.bdot:SetPoint("LEFT", 12, 0)
    f.bline = text(f.banner, 15)
    f.bline:SetPoint("TOPLEFT", 32, -8)
    f.bsub = text(f.banner, 11, ns.TC("textSoft"))
    f.bsub:SetPoint("TOPLEFT", 32, -27)

    f.peakLabel = text(f, 12, ns.TC("textSoft"))
    f.peakLabel:SetPoint("TOPLEFT", 16, -140)
    f.peakLabel:SetText(L["Most gold ever owned"])
    f.peakValue = text(f, 12)
    f.peakValue:SetJustifyH("RIGHT")
    f.peakValue:SetPoint("TOPRIGHT", -16, -140)
    f.bar = CreateFrame("Frame", nil, f)
    f.bar:SetPoint("TOPLEFT", 16, -158)
    f.bar:SetSize(W - 32, 10)
    f.barBg = f.bar:CreateTexture(nil, "BACKGROUND")
    f.barBg:SetAllPoints()
    f.barBg:SetColorTexture(0.12, 0.12, 0.15, 1)
    f.barGood = f.bar:CreateTexture(nil, "ARTWORK")
    f.barGood:SetPoint("TOPLEFT"); f.barGood:SetPoint("BOTTOMLEFT")
    f.barGood:SetColorTexture(0.35, 0.75, 0.40, 1)
    f.barBad = f.bar:CreateTexture(nil, "ARTWORK")
    f.barBad:SetPoint("TOPLEFT", f.barGood, "TOPRIGHT"); f.barBad:SetPoint("BOTTOMLEFT", f.barGood, "BOTTOMRIGHT")
    f.barBad:SetColorTexture(0.85, 0.35, 0.30, 1)
    f.legend = text(f, 11, ns.TC("textDim"))
    f.legend:SetPoint("TOPLEFT", 16, -174)

    local colX = { 16, 16 + 206, 16 + 412 }
    f.cIncome  = column(f, colX[1], -200, L["Income sources"], 5)
    f.cSpend   = column(f, colX[2], -200, L["Spending"], 4)
    f.cAuction = column(f, colX[3], -200, L["Auction activity"], 4)
    f.cPlay    = column(f, colX[1], -300, L["Gameplay footprint"], 6)
    f.cProf    = column(f, colX[2], -300, L["Professions"], 6)
    f.cHist    = column(f, colX[3], -300, L["Your history with them"], 3)

    f.obsTitle = text(f, 12, ns.TC("heading"))
    f.obsTitle:SetPoint("TOPLEFT", 16, -408)
    f.obsTitle:SetText(L["Observations"])
    f.obs = {}
    for i = 1, 4 do
        local d = dot(f, 7)
        d:SetPoint("TOPLEFT", 18, -428 - (i - 1) * 15)
        local fs = text(f, 11, ns.TC("textSoft"))
        fs:SetPoint("LEFT", d, "RIGHT", 7, 0)
        fs:SetWidth(W - 60)
        fs:SetWordWrap(false)
        f.obs[i] = { d = d, fs = fs }
    end

    f.copy = ns.UI:CreateButton(f, { label = L["Copy report"], width = 110, height = 22,
        onClick = function() TC.CopyReport() end })
    f.copy:SetPoint("BOTTOMRIGHT", -16, 12)
    f.rescan = ns.UI:CreateButton(f, { label = L["Scan your target"], width = 130, height = 22,
        onClick = function() TC.Scan("target") end })
    f.rescan:SetPoint("RIGHT", f.copy, "LEFT", -8, 0)

    f:Hide()
    window = f
    return f
end

local function ago(at)
    local mins = math.floor((time() - (at or time())) / 60)
    if mins < 60 then return L["%d min old"]:format(mins) end
    return L["%d h old"]:format(math.floor(mins / 60))
end

-- Spelled out so every name is a literal key the locale check can see.
local function profName(key)
    local names = {
        Alchemy = L["Alchemy"], Blacksmithing = L["Blacksmithing"], Enchanting = L["Enchanting"],
        Engineering = L["Engineering"], Herbalism = L["Herbalism"], Leatherworking = L["Leatherworking"],
        Mining = L["Mining"], Skinning = L["Skinning"], Tailoring = L["Tailoring"],
        ["First Aid"] = L["First Aid"], Cooking = L["Cooking"], Fishing = L["Fishing"],
    }
    return names[key] or key
end

local function money(v) return v and coinText(v) or "--" end
local function count(v) return v and tostring(v) or "--" end

local function updateWindow()
    local f = window
    if not (f and f:IsShown()) then return end
    local p = result
    if not p then
        f.name:SetText(L["No scan yet"])
        f.info:SetText(L["Open a trade, or target a player and press Scan your target."])
        return
    end
    local tradeOpen = TradeFrame and TradeFrame:IsShown()
    local a = analyse(p, tradeOpen and offerNow() or nil)
    local s = p.stats or {}

    local cc = p.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[p.class]
    f.name:SetText(p.name)
    if cc then f.name:SetTextColor(cc.r, cc.g, cc.b) else f.name:SetTextColor(1, 1, 1) end
    f.info:SetText(L["Level %s %s - %s"]:format(p.level or "?", p.className or "",
        p.guild and ("<" .. p.guild .. ">") or L["No guild"]))
    local entry = store()[p.key]
    local nScans = entry and entry.scans and #entry.scans or 0
    f.snaps:SetText(L["%d scans saved"]:format(nScans) .. "\n" .. ago(p.at))

    local line, sub = headline(a, p)
    setDot(f.bdot, p.done and a.state or "none")
    f.bline:SetText(line)
    f.bsub:SetText(sub or "")

    f.peakValue:SetText(money(a.peak))
    local width = W - 32
    if a.peak and a.peak > 0 then
        local good = math.max(1, width * (a.explained / a.peak))
        f.barGood:SetWidth(good)
        f.barBad:SetWidth(math.max(1, width - good))
        f.barBad:SetShown(a.unexplained > 0)
        f.barGood:Show()
    else
        f.barGood:Hide(); f.barBad:Hide()
    end
    f.legend:SetText(("|cff59bf66%s|r: %s     |cffd9594d%s|r: %s"):format(
        L["Explained by recorded income"], money(a.explained), L["Unexplained"], money(a.unexplained)))

    fillColumn(f.cIncome, {
        { L["Gold looted"], money(s.looted) },
        { L["Quest rewards"], money(s.quest) },
        { L["Vendor sales"], money(s.vendor) },
        { L["Auction earnings"], money(s.auction) },
        { L["Total gold acquired"], money(a.acq) },
    })
    local pct = (a.acq and a.acq > 0) and ("%d%%"):format(math.floor(a.spent / a.acq * 100 + 0.5)) or "--"
    fillColumn(f.cSpend, {
        { L["Travel"], money(s.travel) },
        { L["Postage"], money(s.postage) },
        { L["Barber shops"], money(s.barber) },
        { L["Spent vs acquired"], pct },
    })
    fillColumn(f.cAuction, {
        { L["Auctions posted"], count(s.posted) },
        { L["Auction purchases"], count(s.bought) },
        { L["Largest sale"], money(s.bestSale) },
        { L["Largest bid"], money(s.bestBid) },
    })
    fillColumn(f.cPlay, {
        { L["Quests completed"], count(s.quests) },
        { L["Creatures killed"], count(s.kills) },
        { L["Dungeons entered"], count(s.dungeons) },
        { L["Deaths"], count(s.deaths) },
        { L["Flight paths taken"], count(s.flights) },
        { L["Level 10 reached"], p.level10 or "--" },
    })
    local profs = {}
    for i, prof in ipairs(p.professions or {}) do
        if i > 6 then break end
        profs[i] = { profName(prof.key), tostring(prof.value) }
    end
    if #profs == 0 then profs[1] = { L["None recorded"], "" } end
    fillColumn(f.cProf, profs)
    fillColumn(f.cHist, {
        { L["Trades with you"], tostring(entry and entry.trades or 0) },
        { L["Scans saved"], tostring(nScans) },
        { L["First scanned"], entry and date("%d.%m.%Y", entry.first) or "--" },
    })
    fillObs(f.obs, p.done and not p.failed and a.obs or nil)
end

-- ---------------------------------------------------------------- mail --
--
-- A mail carries a sender's name, never a unit, and the statistics only come
-- through a unit in reach. So for a mail with gold the panel shows, in this
-- order: a live scan when the sender is your target, focus, mouseover or in
-- your group; else the last scan you kept of them; else that there is none.

local mailPanel, mailHooked, mailOpen
local marks = {}

local function senderKey(sender)
    if type(sender) ~= "string" or sender == "" then return nil end
    if sender:find("-", 1, true) then return sender end
    return sender .. "-" .. (GetRealmName() or "?")
end

local function isTrue(v) return ns.CanRead(v) and v == true end

local function unitFor(key)
    local function match(unit)
        if not (UnitExists(unit) and UnitIsPlayer(unit)) then return false end
        local _, k = unitName(unit)
        return k == key
    end
    for _, u in ipairs({ "target", "focus", "mouseover" }) do
        if match(u) then return u end
    end
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            if match("raid" .. i) then return "raid" .. i end
        end
    else
        for i = 1, 4 do
            if match("party" .. i) then return "party" .. i end
        end
    end
    return nil
end

local function kept(key, name)
    local entry = store()[key]
    local last = entry and entry.last
    if type(last) ~= "table" or type(last.stats) ~= "table" then return nil end
    local p = {}
    for k, v in pairs(last) do p[k] = v end
    p.name, p.key, p.done, p.stored = name, key, true, true
    return p
end

-- What a mail from `key` should show right now.
local function mailView(key, name)
    local r = result
    if r and r.key == key and not r.stored and (not r.done or not r.failed) then return r end
    return kept(key, name) or { name = name, key = key, done = true, unknown = true }
end

-- The gold mail at inbox index `i`, or nil: from a player, not a GM, money on it.
local function goldMail(i)
    local _, _, sender, _, money, _, _, _, _, _, _, canReply, isGM = GetInboxHeaderInfo(i)
    sender, money = readable(sender), readable(money)
    if type(sender) ~= "string" or type(money) ~= "number" then return nil end
    if not isTrue(canReply) or isTrue(isGM) then return nil end
    return sender, money
end

local function updateMail()
    local index = InboxFrame and InboxFrame.openMailID
    local on = registered and db().mailCheck and OpenMailFrame and OpenMailFrame:IsShown()
    local sender, money
    if on and index and index > 0 then sender, money = goldMail(index) end
    -- taking the money zeroes it on the mail; the panel keeps the amount
    if sender and mailOpen and mailOpen.index == index and mailOpen.sender == sender then
        money = math.max(money or 0, mailOpen.money)
    end
    if not (sender and money and money > 0) then
        mailOpen = nil
        if mailPanel then mailPanel:Hide() end
        return
    end
    local key = senderKey(sender)
    local fresh = not (mailOpen and mailOpen.key == key)
    mailOpen = { index = index, sender = sender, key = key, money = money }
    if fresh then
        local unit = unitFor(key)
        if unit and not (result and result.key == key and not result.stored and not result.failed) then
            TC.Scan(unit)
        end
    end
    mailPanel = mailPanel or makePanel(OpenMailFrame)
    mailPanel:Show()
    fillPanel(mailPanel, mailView(key, sender), money, L["%s sent you %s."]:format(sender, coinText(money)))
end

local function stateOf(key)
    local p = kept(key, key)
    if not p then return nil end
    return analyse(p, nil).state or "none"
end

-- A mark on every gold mail in the inbox: the colour of your last scan of the
-- sender, or an orange ? when you have none.
local function markInbox()
    if not (InboxFrame and InboxFrame:IsShown()) then return end
    local on = registered and db().mailCheck
    local base = ((InboxFrame.pageNum or 1) - 1) * INBOXITEMS_TO_DISPLAY
    for i = 1, INBOXITEMS_TO_DISPLAY do
        local button = _G["MailItem" .. i .. "Button"]
        if button then
            local m = marks[i]
            if not m then
                m = {}
                m.q = button:CreateFontString(nil, "OVERLAY")
                ns.UI.Font(m.q, 14, "OUTLINE")
                m.q:SetPoint("TOPRIGHT", button, "TOPRIGHT", 2, 2)
                m.q:SetText("?")
                m.q:SetTextColor(1, 0.55, 0.1)
                m.d = dot(button, 8)
                m.d:SetPoint("TOPRIGHT", button, "TOPRIGHT", 0, 0)
                marks[i] = m
            end
            local sender, money
            if on and button:IsShown() then sender, money = goldMail(base + i) end
            local state = sender and money > 0 and stateOf(senderKey(sender))
            m.q:SetShown(sender ~= nil and money > 0 and not state)
            m.d:SetShown(state and true or false)
            if state then setDot(m.d, state) end
        end
    end
end

local function mailTooltip(item)
    if not (registered and db().mailCheck and item and item.index) then return end
    local sender, money = goldMail(item.index)
    if not (sender and money > 0) then return end
    local key = senderKey(sender)
    local p = kept(key, sender)
    GameTooltip:AddLine(" ")
    if p then
        local a = analyse(p, money)
        local line = headline(a, p)
        local c = STATE_COLOR[a.state or "none"]
        GameTooltip:AddLine(L["Gold check"] .. ": " .. line, c[1], c[2], c[3], true)
        GameTooltip:AddLine(L["From your scan on %s."]:format(date("%d.%m.%Y", p.at)), 0.6, 0.6, 0.65)
    else
        GameTooltip:AddLine(L["Gold check"] .. ": " .. L["never scanned"], 1, 0.55, 0.1)
    end
    GameTooltip:Show()
end

local function hookMail()
    if mailHooked or not (InboxFrame and OpenMailFrame) then return end
    mailHooked = true
    hooksecurefunc(InboxFrame, "Update", markInbox)
    hooksecurefunc(OpenMailFrame, "Update", updateMail)
    OpenMailFrame:HookScript("OnHide", function()
        mailOpen = nil
        if mailPanel then mailPanel:Hide() end
    end)
    if type(InboxFrameItem_OnEnter) == "function" then
        hooksecurefunc("InboxFrameItem_OnEnter", mailTooltip)
    end
end

local function onMailShow()
    if not db().mailCheck then return end
    hookMail()
end

refresh = function()
    updatePanel()
    if mailPanel and mailPanel:IsShown() then updateMail() end
    updateWindow()
end

function TC.ShowWindow(p)
    if p and p.stats then result = p end
    buildWindow()
    window:Show()
    window:Raise()
    updateWindow()
end

function TC.CopyReport()
    local p = result
    if not (p and p.done and p.stats) then return end
    local a = analyse(p, nil)
    local s = p.stats
    local out = {
        ("%s, %s %s %s"):format(p.key, L["Level"], p.level or "?", p.className or ""),
        (headline(a, p)),
        ("%s: %s"):format(L["Most gold ever owned"], a.peak and plainMoney(a.peak) or "--"),
        ("%s: %s"):format(L["Total gold acquired"], a.acq and plainMoney(a.acq) or "--"),
        ("%s: %s"):format(L["Unexplained"], a.unexplained and plainMoney(a.unexplained) or "--"),
        ("%s: %s / %s: %s"):format(L["Quests completed"], count(s.quests), L["Creatures killed"], count(s.kills)),
    }
    for _, o in ipairs(a.obs) do out[#out + 1] = "- " .. o[2] end
    ns.UI:ShowCopyDialog(L["Copy report"], table.concat(out, "\n"))
end

-- -------------------------------------------------------------- events --

local function onTradeShow()
    if not db().tradeCheck then return end
    local _, key = unitName("npc")
    tradeKey = key
    if buildPanel() then panel:Show() end
    if not TC.Scan("npc") and panel then panel:Hide() end
end

local function onTradeClosed()
    if panel then panel:Hide() end
end

local function onTradeChanged()
    updatePanel()
end

local function onInfo(_, _, msg)
    if not (tradeKey and readable(msg) and msg == ERR_TRADE_COMPLETE) then return end
    local entry = store()[tradeKey]
    if entry then entry.trades = (entry.trades or 0) + 1 end
    tradeKey = nil
end

local EVENTS = {
    TRADE_SHOW = onTradeShow,
    TRADE_CLOSED = onTradeClosed,
    TRADE_MONEY_CHANGED = onTradeChanged,
    TRADE_TARGET_ITEM_CHANGED = onTradeChanged,
    INSPECT_ACHIEVEMENT_READY = onReady,
    UI_INFO_MESSAGE = onInfo,
    MAIL_SHOW = onMailShow,
}

function TC.Apply()
    local on = QoL.mod.active and (db().tradeCheck or db().mailCheck) and true or false
    if on == registered then return end
    registered = on
    for event, fn in pairs(EVENTS) do QoL.SyncEvent(on, event, fn) end
    if not on and panel then panel:Hide() end
    if mailPanel and not (on and db().mailCheck) then mailPanel:Hide() end
end

function TC.Disable()
    if registered then
        for event, fn in pairs(EVENTS) do ns:UnregisterEvent(event, fn) end
    end
    registered = nil
    if panel then panel:Hide() end
    if mailPanel then mailPanel:Hide() end
end
