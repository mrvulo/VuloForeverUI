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
--
-- A counter the client does not report is shown as "--" and never counted as
-- zero. The request shares one comparison slot with the achievement window
-- and other addons: it waits for the server's spacing, gives up after 15 s,
-- and drops a scan whose slot someone else took (see THE COMPARISON SLOT).
local _, ns = ...
local L = ns.L

local QoL = ns.QoL
local TC = QoL.RegisterPart("tradecheck", {})
QoL.TradeCheck = TC

-- Statistic ids (Achievement table, statistics flag), stable across clients.
local STAT = {
    peak = 334, acquired = 328, looted = 333, quest = 326, vendor = 921, auction = 919,
    daily = 753, travel = 1146, barber = 1147, postage = 1148, respec = 1150,
    posted = 329, bought = 330, bestBid = 331, bestSale = 332,
    quests = 98, kills = 107, dungeons = 932, deaths = 60, flights = 349, honor = 588,
}
local MONEY = {
    peak = true, acquired = true, looted = true, quest = true, vendor = true, auction = true,
    daily = true, travel = true, barber = true, postage = true, respec = true, bestBid = true, bestSale = true,
}
local NUM_STATS = 0
for _ in pairs(STAT) do NUM_STATS = NUM_STATS + 1 end
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
local YOUNG_PEAK = 10 * 10000     -- under 10 gold ever owned: too little to judge
local YOUNG_LEVEL = 10
local BANK_AUCTIONS = 500         -- posted + bought: a trading character
-- The reply to a comparison request can take its time on a busy server, and
-- the server throttles requests that come quicker than every few seconds.
local TIMEOUT = 15
local SPACING = 5

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

-- A counter the client does not report stays nil -- missing is not zero,
-- and nothing below adds a missing counter in as 0.
local function readStats(p)
    local get = p.own and GetStatistic or GetComparisonStatistic
    local stats, n = {}, 0
    for key, id in pairs(STAT) do
        local ok, text = pcall(get, id)
        if ok then stats[key] = parse(readable(text), MONEY[key]) end
        if stats[key] then n = n + 1 end
    end
    p.readable = n
    local profs = {}
    for _, prof in ipairs(PROFESSIONS) do
        local ok, text = pcall(get, prof.id)
        local value = ok and parse(readable(text), false)
        if value and value > 0 then profs[#profs + 1] = { key = prof.key, value = value } end
    end
    local ok, done, month, day, year
    if p.own then
        local _, _, _, completed, m, d, y = GetAchievementInfo(LEVEL_10)
        ok, done, month, day, year = true, completed, m, d, y
    else
        ok, done, month, day, year = pcall(GetAchievementComparisonInfo, LEVEL_10)
    end
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

-- THE COMPARISON SLOT
--
-- The client has ONE comparison request at a time, shared by the
-- achievement window and every addon. Ours is marked while we hold it
-- (`owning`); our own calls run with `internal` set, so the hooks below can
-- tell another caller apart. Someone else setting or clearing it while we
-- wait means the reply that comes may be for someone else: the scan is
-- dropped and says so, and our next request waits a moment.
local owning, internal = false, false
local nextRequest, externalUntil = 0, 0

local function release()
    if not owning then return end
    owning = false
    -- leave the comparison to the achievement window if it is using it
    local cmp = _G.AchievementFrameComparison
    if cmp and cmp:IsShown() then return end
    internal = true
    pcall(ClearAchievementComparisonUnit)
    internal = false
end

local function finish(p, ok, reason)
    if pending ~= p then return end
    pending = nil
    p.done, p.failed, p.reason = true, not ok, reason
    if ok then
        readStats(p)
        save(p)
    end
    release()
    result = p
    refresh()
end

local hooked
local function hookSlot()
    if hooked then return end
    hooked = true
    local function displaced()
        if internal then return end
        owning = false
        externalUntil = GetTime() + SPACING
        if pending and not pending.queued then finish(pending, false, "displaced") end
    end
    hooksecurefunc("SetAchievementComparisonUnit", displaced)
    hooksecurefunc("ClearAchievementComparisonUnit", displaced)
end

-- Sends the request for a scan, now or -- while the server would throttle
-- it -- when the spacing has passed. Everything is checked again when it
-- goes out: a queued scan may wait seconds.
local function send(p)
    if pending ~= p then return end
    p.queued = nil
    if not (UnitExists(p.unit) and readable(UnitGUID(p.unit)) == p.guid) then return finish(p, false, "gone") end
    if InCombatLockdown() then return finish(p, false, "combat") end
    -- a trade partner ("npc") stands next to you; anyone else must be in reach
    if p.unit ~= "npc" and CanInspect and not CanInspect(p.unit, false) then return finish(p, false, "reach") end
    local ach = _G.AchievementFrame
    if ach and ach:IsShown() and ach.isComparison then return finish(p, false, "busy") end
    local wait = math.max(nextRequest, externalUntil) - GetTime()
    if wait > 0 then
        p.queued = true
        C_Timer.After(wait, function() send(p) end)
        refresh()
        return
    end
    hookSlot()
    nextRequest = GetTime() + SPACING
    internal = true
    local ok = pcall(SetAchievementComparisonUnit, p.unit)
    internal = false
    if not ok then return finish(p, false, "refused") end
    owning = true
    p.deadline = GetTime() + TIMEOUT
    C_Timer.After(TIMEOUT, function() finish(p, false, "timeout") end)
    refresh()
end

-- Starts reading `unit`'s statistics. Another player's answer arrives as an
-- event; your own are read at once.
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
        own = UnitIsUnit(unit, "player"),
    }
    if pending and pending ~= p then finish(pending, false, "replaced") end
    pending, result = p, p
    if p.own then
        finish(p, true)
        return true
    end
    send(p)
    return true
end

local function onReady(_, guid)
    local p = pending
    if not p or p.queued then return end
    guid = readable(guid)
    if p.guid and guid and guid ~= p.guid then return end
    finish(p, true)
end

-- --------------------------------------------------------------- verdict --

local function analyse(p, offer)
    local s = p.stats or {}
    local a = { offer = offer }
    -- the client's own total; the four sources only stand in for it when all
    -- four are known -- a missing one is not zero
    local acq = s.acquired
    if not acq and s.looted and s.quest and s.vendor and s.auction then
        acq = s.looted + s.quest + s.vendor + s.auction
    end
    a.peak, a.acq = s.peak, acq
    if s.travel or s.barber or s.postage or s.respec then
        a.spent = (s.travel or 0) + (s.barber or 0) + (s.postage or 0) + (s.respec or 0)
    end
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

    -- judged only on what was reported: a missing counter is not "no play"
    local level = p.level or 1
    local quests, kills = s.quests, s.kills
    a.gameplay = (quests ~= nil and quests >= math.max(5, level)) or (kills ~= nil and kills >= level * 40)

    -- WHAT THE NUMBERS CAN CARRY
    --
    -- Three cases where red or green would claim more than the counters show:
    --   young    a low character or a small peak: too little history to judge
    --   bank     many auctions and little questing or fighting: a bank or
    --            trading character, whose gold arrives by mail by design
    --   partial  an income source the client did not report: no total to
    --            compare, or a gap that may be overstated -- never red then
    local missing = {}
    if s.looted == nil then missing[#missing + 1] = L["Gold looted"] end
    if s.quest == nil then missing[#missing + 1] = L["Quest rewards"] end
    if s.vendor == nil then missing[#missing + 1] = L["Vendor sales"] end
    if s.auction == nil then missing[#missing + 1] = L["Auction earnings"] end
    a.missing = missing
    if s.posted or s.bought then a.auctions = (s.posted or 0) + (s.bought or 0) end
    if a.peak and (a.peak < YOUNG_PEAK or level < YOUNG_LEVEL) then
        a.state = "young"
    elseif (a.state == "warn" or a.state == "bad") and a.auctions and a.auctions >= BANK_AUCTIONS and not a.gameplay then
        a.state = "bank"
    elseif not a.state and a.peak and not acq then
        a.state = "partial"
    elseif a.state == "bad" and #missing > 0 then
        a.state = "warn"
    end

    local obs = {}
    if a.state == "good" then
        obs[#obs + 1] = { "good", L["Explained income. Recorded income covers %d%% of their peak."]:format(math.floor(a.share * 100 + 0.5)) }
    elseif a.state then
        obs[#obs + 1] = { a.state, L["%s of their peak gold has no recorded source -- it came by trade or mail."]:format(plainMoney(a.unexplained)) }
    end
    if #missing > 0 and a.peak then
        obs[#obs + 1] = { "none", L["Not reported: %s -- the gap may be overstated."]:format(table.concat(missing, ", ")) }
    end
    if p.stored then
        obs[#obs + 1] = { "none", L["From your scan on %s -- they are not in reach now."]:format(date("%d.%m.%Y", p.at)) }
    end
    if s.quests and s.kills then
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
    young = { 0.60, 0.60, 0.65 },
    partial = { 0.60, 0.60, 0.65 },
    bank = { 0.40, 0.65, 1.00 },
}

-- Why a scan came back empty, in words the player can act on. Spelled out
-- per reason so every text is a literal key.
local function failedText(reason)
    if reason == "combat" then return L["Not in combat -- scan again once the fight is over."] end
    if reason == "reach" then return L["Out of reach -- move closer and scan again."] end
    if reason == "busy" then return L["The achievement comparison is open -- close it and scan again."] end
    if reason == "displaced" then return L["Another window took over the comparison -- scan again."] end
    if reason == "timeout" then return L["No answer within 15 seconds -- move closer and scan again."] end
    if reason == "gone" then return L["They are no longer your target."] end
    return L["No statistics -- they are out of reach or the client refused."]
end

local function headline(a, p)
    if p.unknown then return L["Not in reach, and you have never scanned them. Target them when you meet them and use Scan your target."], nil end
    if p.queued then return L["Waiting a moment -- the server only answers every few seconds."], nil end
    if not p.done then return L["Reading their statistics..."], nil end
    if p.failed then return failedText(p.reason), nil end
    if a.state == "good" then
        return L["Gold matches recorded income"], L["Recorded income covers %d%% of their peak."]:format(math.floor(a.share * 100 + 0.5))
    elseif a.state == "warn" then
        return L["Part of their gold is unexplained"], L["Recorded income covers %d%% of their peak."]:format(math.floor(a.share * 100 + 0.5))
    elseif a.state == "bad" then
        return L["Most of their gold is unexplained"], L["Recorded income covers %d%% of their peak."]:format(math.floor(a.share * 100 + 0.5))
    elseif a.state == "young" then
        return L["Too little history to judge"], L["Level %s, at most %s ever owned."]:format(p.level or "?", plainMoney(a.peak))
    elseif a.state == "bank" then
        return L["Likely a bank or trading character"], L["%d auctions posted or bought, little questing or fighting. Gold by mail is normal here."]:format(a.auctions)
    elseif a.state == "partial" then
        return L["Partial data -- no verdict"], L["Not reported: %s"]:format(table.concat(a.missing, ", "))
    end
    return L["Not enough statistics to judge"], nil
end

-- One or two words for a list row.
local function shortVerdict(state)
    if state == "good" then return L["Explained"] end
    if state == "warn" then return L["Partly unexplained"] end
    if state == "bad" then return L["Mostly unexplained"] end
    if state == "young" then return L["Too little history"] end
    if state == "bank" then return L["Bank character"] end
    if state == "partial" then return L["Partial data"] end
    return "--"
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
-- A label on the left, its value on the right. The value keeps its full
-- width (a gold amount must stay readable); the label gets what is left
-- and ends in "..." rather than running under the value.
local function pairRow(parent, y, x, width)
    local l = text(parent, 11, ns.TC("textDim"))
    l:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    l:SetJustifyH("LEFT")
    l:SetWordWrap(false)
    local r = text(parent, 11)
    r:SetJustifyH("RIGHT")
    r:SetWordWrap(false)
    r:SetPoint("TOPRIGHT", parent, "TOPLEFT", x + width, y)
    return { l = l, r = r, width = width }
end

local function setPair(row, label, value)
    row.r:SetText(value or "")
    local vw = (value and value ~= "") and math.ceil(row.r:GetUnboundedStringWidth()) or 0
    row.l:SetWidth(math.max(20, row.width - vw - 8))
    row.l:SetText(label or "")
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

local W, H = 700, 560

local function column(parent, x, y, title, n)
    local c = {}
    c.title = text(parent, 12, ns.TC("heading"))
    c.title:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    c.title:SetText(title)
    c.rows = {}
    for i = 1, n do c.rows[i] = pairRow(parent, y - 18 - (i - 1) * 15, x, 212) end
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

    local colX = { 16, 16 + 226, 16 + 452 }
    f.cIncome  = column(f, colX[1], -200, L["Income sources"], 6)
    f.cSpend   = column(f, colX[2], -200, L["Spending"], 5)
    f.cAuction = column(f, colX[3], -200, L["Auction activity"], 4)
    f.cPlay    = column(f, colX[1], -320, L["Gameplay footprint"], 7)
    f.cProf    = column(f, colX[2], -320, L["Professions"], 7)
    f.cHist    = column(f, colX[3], -320, L["Your history with them"], 3)

    f.obsTitle = text(f, 12, ns.TC("heading"))
    f.obsTitle:SetPoint("TOPLEFT", 16, -452)
    f.obsTitle:SetText(L["Observations"])
    f.obs = {}
    for i = 1, 4 do
        local d = dot(f, 7)
        d:SetPoint("TOPLEFT", 18, -472 - (i - 1) * 15)
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
    f.self = ns.UI:CreateButton(f, { label = L["Check yourself"], width = 120, height = 22,
        onClick = function() TC.Scan("player") end })
    f.self:SetPoint("RIGHT", f.rescan, "LEFT", -8, 0)
    -- the two other views of the same window (built further down)
    if TC.BuildViews then TC.BuildViews(f) end

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
    -- nothing scanned yet: the start view instead of an empty frame
    if TC.RenderEmpty then TC.RenderEmpty(p == nil) end
    f.copy:SetShown(p ~= nil)
    if f.histBtn then f.histBtn:SetShown(p ~= nil) end
    if not p then
        f.name:SetText("")
        f.info:SetText("")
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
    local lines = L["%d scans saved"]:format(nScans) .. "\n" .. ago(p.at)
    -- how much of the record the client gave; a missing counter is not zero
    if p.done and not p.failed and p.readable then
        lines = lines .. "\n" .. L["%d / %d counters readable"]:format(p.readable, NUM_STATS)
    end
    f.snaps:SetText(lines)

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
        { L["Average earned per day"], money(s.daily) },
    })
    local pct = (a.spent and a.acq and a.acq > 0) and ("%d%%"):format(math.floor(a.spent / a.acq * 100 + 0.5)) or "--"
    fillColumn(f.cSpend, {
        { L["Travel"], money(s.travel) },
        { L["Postage"], money(s.postage) },
        { L["Barber shops"], money(s.barber) },
        { L["Talent respecs"], money(s.respec) },
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
        { L["Honorable kills"], count(s.honor) },
        { L["Level 10 reached"], p.level10 or "--" },
    })
    local profs = {}
    for i, prof in ipairs(p.professions or {}) do
        if i > 7 then break end
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

-- ---------------------------------------------------------------- views --
--
-- Two more views in the gold check window, each laid over its middle:
--   Players  every character you ever scanned, searchable and sortable;
--            a click opens their last scan
--   History  the saved scans of the character on show, with the rise of
--            their recorded income between two scans

local VIEW_TOP, VIEW_BOTTOM = 82, 46
local ROWS, ROW_H = 15, 22

local function nameOf(key)
    return (type(key) == "string" and key:match("^(.-)%-[^%-]*$")) or key
end

local listState = { query = "", sort = "seen", desc = true }

local function listRows()
    local out, total = {}, 0
    local q = listState.query:lower()
    for key, entry in pairs(store()) do
        local last = type(entry) == "table" and entry.last
        if type(last) == "table" and type(last.stats) == "table" then
            total = total + 1
            local name = nameOf(key)
            local hay = (key .. " " .. (last.guild or "") .. " " .. (last.className or "")):lower()
            if q == "" or hay:find(q, 1, true) then
                local p = kept(key, name)
                local a = analyse(p, nil)
                out[#out + 1] = { key = key, name = name, class = last.class, level = last.level,
                    peak = a.peak, state = a.state, seen = last.at or 0, sortName = name:lower() }
            end
        end
    end
    local key, desc = listState.sort, listState.desc
    local ORDER = { bad = 1, warn = 2, partial = 3, bank = 4, young = 5, good = 6 }
    table.sort(out, function(x, y)
        local a, b
        if key == "name" then a, b = x.sortName, y.sortName
        elseif key == "level" then a, b = x.level, y.level
        elseif key == "peak" then a, b = x.peak, y.peak
        elseif key == "verdict" then a, b = ORDER[x.state or ""] or 9, ORDER[y.state or ""] or 9
        else a, b = x.seen, y.seen end
        -- unknown values last, whichever way the column runs
        if a == nil and b ~= nil then return false end
        if b == nil and a ~= nil then return true end
        if a ~= b then if desc then return a > b else return a < b end end
        return x.sortName < y.sortName
    end)
    return out, total
end

function TC.BuildViews(f)
    local function overlay()
        local v = CreateFrame("Frame", nil, f)
        v:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -VIEW_TOP)
        v:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, VIEW_BOTTOM)
        v:SetFrameLevel(f:GetFrameLevel() + 20)
        v:EnableMouse(true)
        local bg = v:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(v)
        bg:SetColorTexture(ns.COLORS.bg.r, ns.COLORS.bg.g, ns.COLORS.bg.b, 1)
        v:Hide()
        return v
    end

    -- ---- players
    local list = overlay()
    f.listView = list
    list.search = ns.UI:CreateSearchBox(list, { width = 220, onText = function(self)
        listState.query = self:GetText() or ""
        list.offset = 0
        TC.RenderList()
    end })
    list.search:SetPoint("TOPLEFT", 15, -6)
    list.caption = text(list, 11, ns.TC("textDim"))
    list.caption:SetPoint("TOPRIGHT", -16, -8)
    local cols = {
        { "name", L["Character"], 15, 200, "LEFT" },
        { "level", L["Level"], 220, 50, "RIGHT" },
        { "peak", L["Peak gold"], 280, 140, "RIGHT" },
        { "verdict", L["Verdict"], 440, 140, "LEFT" },
        { "seen", L["Last scan"], 590, 90, "RIGHT" },
    }
    list.cols = cols
    for _, c in ipairs(cols) do
        local h = CreateFrame("Button", nil, list)
        h:SetPoint("TOPLEFT", list, "TOPLEFT", c[3], -32)
        h:SetSize(c[4], 16)
        h.fs = text(h, 11, ns.TC("heading"))
        h.fs:SetAllPoints(h); h.fs:SetJustifyH(c[5]); h.fs:SetText(c[2])
        h:SetScript("OnClick", function()
            if listState.sort == c[1] then listState.desc = not listState.desc
            else listState.sort, listState.desc = c[1], c[1] ~= "name" end
            TC.RenderList()
        end)
    end
    list.rows = {}
    for i = 1, ROWS do
        local r = CreateFrame("Button", nil, list)
        r:SetPoint("TOPLEFT", list, "TOPLEFT", 10, -52 - (i - 1) * ROW_H)
        r:SetPoint("RIGHT", list, "RIGHT", -10, 0)
        r:SetHeight(ROW_H)
        if i % 2 == 1 then
            local st = r:CreateTexture(nil, "BACKGROUND")
            st:SetAllPoints(r); st:SetColorTexture(1, 1, 1, 0.03)
        end
        local hl = r:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints(r); hl:SetColorTexture(1, 1, 1, 0.06)
        r.cells = {}
        for n, c in ipairs(cols) do
            local fs = text(r, 11)
            fs:SetPoint("LEFT", r, "LEFT", c[3] - 10 + (n == 4 and 14 or 0), 0)
            fs:SetWidth(c[4] - (n == 4 and 14 or 0)); fs:SetJustifyH(c[5]); fs:SetWordWrap(false)
            r.cells[c[1]] = fs
        end
        r.dot = dot(r, 8)
        r.dot:SetPoint("LEFT", r, "LEFT", cols[4][3] - 10, 0)
        r:SetScript("OnClick", function(self)
            if not self.key then return end
            local p = kept(self.key, nameOf(self.key))
            if p then list:Hide(); TC.ShowWindow(p) end
        end)
        list.rows[i] = r
    end
    list.empty = text(list, 12, ns.TC("textDim"))
    list.empty:SetPoint("CENTER")
    list.offset = 0
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, delta)
        list.offset = math.max(0, (list.offset or 0) - delta * 3)
        TC.RenderList()
    end)

    -- ---- history
    local hist = overlay()
    f.histView = hist
    hist.title = text(hist, 13, ns.TC("heading"))
    hist.title:SetPoint("TOPLEFT", 15, -8)
    local hcols = {
        { L["Scanned"], 15, 160, "LEFT" }, { L["Level"], 180, 50, "RIGHT" },
        { L["Peak gold"], 240, 140, "RIGHT" }, { L["Total gold acquired"], 390, 140, "RIGHT" },
        { L["Increase"], 540, 140, "RIGHT" },
    }
    for _, c in ipairs(hcols) do
        local fs = text(hist, 11, ns.TC("heading"))
        fs:SetPoint("TOPLEFT", hist, "TOPLEFT", c[2], -32)
        fs:SetWidth(c[3]); fs:SetJustifyH(c[4]); fs:SetText(c[1])
    end
    hist.rows = {}
    for i = 1, MAX_SCANS do
        local cells = {}
        for n, c in ipairs(hcols) do
            local fs = text(hist, 11)
            fs:SetPoint("TOPLEFT", hist, "TOPLEFT", c[2], -52 - (i - 1) * ROW_H)
            fs:SetWidth(c[3]); fs:SetJustifyH(c[4]); fs:SetWordWrap(false)
            cells[n] = fs
        end
        hist.rows[i] = cells
    end
    hist.note = text(hist, 10, ns.TC("textDim"))
    hist.note:SetPoint("BOTTOMLEFT", 15, 8)
    hist.note:SetText(L["The rise is shown only between two scans whose totals both are known and did not fall."])

    -- ---- start view: shown while nothing has been scanned this session
    local empty = CreateFrame("Frame", nil, f)
    f.emptyView = empty
    empty:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -30)
    empty:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, VIEW_BOTTOM)
    empty:SetFrameLevel(f:GetFrameLevel() + 15)
    empty:EnableMouse(true)
    local ebg = empty:CreateTexture(nil, "BACKGROUND")
    ebg:SetAllPoints(empty)
    ebg:SetColorTexture(ns.COLORS.bg.r, ns.COLORS.bg.g, ns.COLORS.bg.b, 1)
    empty:Hide()

    local coinIcon = empty:CreateTexture(nil, "ARTWORK")
    coinIcon:SetSize(44, 44)
    coinIcon:SetPoint("TOP", empty, "TOP", 0, -18)
    coinIcon:SetTexture("Interface\\Icons\\INV_Misc_Coin_02")
    coinIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local et = text(empty, 17)
    et:SetPoint("TOP", coinIcon, "BOTTOM", 0, -10)
    et:SetText(L["No player checked yet"])
    local es = text(empty, 12, ns.TC("textSoft"))
    es:SetPoint("TOP", et, "BOTTOM", 0, -6)
    es:SetWidth(W - 160); es:SetJustifyH("CENTER")
    es:SetText(L["The gold check sets the most gold a character ever owned against everything it earned itself."])

    -- the three ways to a check, numbered
    local steps = {
        L["Open a trade -- the check runs by itself beside the trade window."],
        L["Inspect a player and press Gold check under the inspect window."],
        L["Target a player in reach and press Scan your target below."],
    }
    local card = CreateFrame("Frame", nil, empty)
    card:SetPoint("TOP", es, "BOTTOM", 0, -16)
    card:SetSize(W - 120, #steps * 26 + 16)
    ns.UI:StyleBackdrop(card, { bg = ns.COLORS.card or ns.COLORS.bg, border = ns.COLORS.border })
    for i, line in ipairs(steps) do
        local badge = card:CreateTexture(nil, "ARTWORK")
        badge:SetSize(18, 18)
        badge:SetPoint("TOPLEFT", card, "TOPLEFT", 14, -10 - (i - 1) * 26)
        local ac = ns.COLORS.accent
        badge:SetColorTexture(ac.r, ac.g, ac.b, 0.85)
        local num = text(card, 11)
        num:SetPoint("CENTER", badge, "CENTER", 0, 0)
        num:SetText(tostring(i))
        local fs = text(card, 12)
        fs:SetPoint("LEFT", badge, "RIGHT", 10, 0)
        fs:SetWidth(W - 190); fs:SetJustifyH("LEFT")
        fs:SetText(line)
    end

    -- the last checked characters, one click away
    local recentTitle = text(empty, 12, ns.TC("heading"))
    recentTitle:SetPoint("TOPLEFT", card, "BOTTOMLEFT", 0, -18)
    recentTitle:SetText(L["Checked lately"])
    empty.recentTitle = recentTitle
    empty.recent = {}
    for i = 1, 5 do
        local r = CreateFrame("Button", nil, empty)
        r:SetPoint("TOPLEFT", recentTitle, "BOTTOMLEFT", 0, -6 - (i - 1) * 20)
        r:SetSize(W - 120, 20)
        local hl = r:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints(r); hl:SetColorTexture(1, 1, 1, 0.06)
        r.dot = dot(r, 8); r.dot:SetPoint("LEFT", r, "LEFT", 4, 0)
        r.name = text(r, 12); r.name:SetPoint("LEFT", r, "LEFT", 20, 0)
        r.name:SetWidth(220); r.name:SetJustifyH("LEFT"); r.name:SetWordWrap(false)
        r.verdict = text(r, 11, ns.TC("textSoft")); r.verdict:SetPoint("LEFT", r, "LEFT", 250, 0)
        r.when = text(r, 11, ns.TC("textDim")); r.when:SetPoint("RIGHT", r, "RIGHT", -4, 0)
        r:SetScript("OnClick", function(self)
            local pp = self.key and kept(self.key, nameOf(self.key))
            if pp then TC.ShowWindow(pp) end
        end)
        empty.recent[i] = r
    end
    empty.note = text(empty, 10, ns.TC("textDim"))
    empty.note:SetPoint("BOTTOM", empty, "BOTTOM", 0, 10)
    empty.note:SetWidth(W - 80); empty.note:SetJustifyH("CENTER")
    empty.note:SetText(L["A hint, not proof: a guild bank or a generous friend looks the same as bought gold."])

    -- ---- switches
    local function toggle(view, other)
        other:Hide()
        view:SetShown(not view:IsShown())
        if view:IsShown() then
            if view == list then TC.RenderList() else TC.RenderHistory() end
        end
    end
    f.listBtn = ns.UI:CreateButton(f, { label = L["Players"], width = 100, height = 22,
        onClick = function() toggle(list, hist) end })
    f.listBtn:SetPoint("BOTTOMLEFT", 16, 12)
    f.histBtn = ns.UI:CreateButton(f, { label = L["History"], width = 100, height = 22,
        onClick = function() toggle(hist, list) end })
    f.histBtn:SetPoint("LEFT", f.listBtn, "RIGHT", 8, 0)
end

function TC.RenderEmpty(on)
    local empty = window and window.emptyView
    if not empty then return end
    empty:SetShown(on)
    if not on then return end
    -- newest scans first, reusing the player list's own ordering
    local sort, desc, query = listState.sort, listState.desc, listState.query
    listState.sort, listState.desc, listState.query = "seen", true, ""
    local rows = listRows()
    listState.sort, listState.desc, listState.query = sort, desc, query
    empty.recentTitle:SetShown(#rows > 0)
    for i, r in ipairs(empty.recent) do
        local d = rows[i]
        r.key = d and d.key
        if d then
            local cc = d.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[d.class]
            r.name:SetText(d.name)
            if cc then r.name:SetTextColor(cc.r, cc.g, cc.b) else r.name:SetTextColor(1, 1, 1) end
            r.verdict:SetText(shortVerdict(d.state))
            setDot(r.dot, d.state or "none")
            r.when:SetText(d.seen > 0 and date("%d.%m.%y %H:%M", d.seen) or "")
            r:Show()
        else
            r:Hide()
        end
    end
end

function TC.RenderList()
    local list = window and window.listView
    if not (list and list:IsShown()) then return end
    local rows, total = listRows()
    local maxOff = math.max(0, #rows - ROWS)
    list.offset = math.min(list.offset or 0, maxOff)
    list.caption:SetText(L["%d of %d characters"]:format(#rows, total))
    for i, r in ipairs(list.rows) do
        local d = rows[list.offset + i]
        r.key = d and d.key
        if d then
            local cc = d.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[d.class]
            r.cells.name:SetText(d.name)
            if cc then r.cells.name:SetTextColor(cc.r, cc.g, cc.b) else r.cells.name:SetTextColor(1, 1, 1) end
            r.cells.level:SetText(d.level and tostring(d.level) or "--")
            r.cells.peak:SetText(money(d.peak))
            r.cells.verdict:SetText(shortVerdict(d.state))
            setDot(r.dot, d.state or "none")
            r.cells.seen:SetText(d.seen > 0 and date("%d.%m.%y", d.seen) or "--")
            r:Show()
        else
            r:Hide()
        end
    end
    list.empty:SetShown(#rows == 0)
    list.empty:SetText(total == 0 and L["No characters scanned yet."] or L["No character matches the search."])
end

function TC.RenderHistory()
    local hist = window and window.histView
    if not (hist and hist:IsShown()) then return end
    local p = result
    local entry = p and store()[p.key]
    local scans = entry and entry.scans or {}
    hist.title:SetText(p and L["History: %s"]:format(p.name or p.key) or L["No scan yet"])
    -- newest first
    for i, cells in ipairs(hist.rows) do
        local idx = #scans - i + 1
        local sc, prev = scans[idx], scans[idx - 1]
        if sc then
            cells[1]:SetText(date("%d.%m.%y %H:%M", sc.at or 0))
            cells[2]:SetText(sc.level and tostring(sc.level) or "--")
            cells[3]:SetText(money(sc.peak))
            cells[4]:SetText(money(sc.acquired))
            local rise = prev and prev.acquired and sc.acquired and sc.acquired >= prev.acquired
                and (sc.acquired - prev.acquired) or nil
            cells[5]:SetText(rise and ("+ " .. coinText(rise)) or "--")
            for _, c in ipairs(cells) do c:Show() end
        else
            for _, c in ipairs(cells) do c:Hide() end
        end
    end
end

function TC.ShowWindow(p)
    if p and p.stats then result = p end
    buildWindow()
    -- a character opened from the list goes back to the main view
    if window.listView then window.listView:Hide() end
    if window.histView and window.histView:IsShown() then TC.RenderHistory() end
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

-- ------------------------------------------------------------- inspect --
--
-- A "Gold check" button under the inspect window, and -- when switched on --
-- a scan each time the window opens, so a check does not need a trade.
local inspectButton

local function nextToInspect()
    buildWindow()
    local ins = _G.InspectFrame
    if ins and ins:IsShown() then
        window:ClearAllPoints()
        window:SetPoint("TOPLEFT", ins, "TOPRIGHT", 12, 0)
    end
end

local function checkInspected()
    local ins = _G.InspectFrame
    local unit = ins and ins.unit
    if not unit then return end
    nextToInspect()
    TC.Scan(unit)
    TC.ShowWindow()
end

local function hookInspect()
    local ins = _G.InspectFrame
    if inspectButton or not ins then return end
    -- a child of a panel the client manages: made out of combat only
    if InCombatLockdown() then return end
    inspectButton = ns.UI:CreateButton(ins, { label = L["Gold check"], width = 110, height = 22,
        onClick = checkInspected })
    inspectButton:SetPoint("TOPRIGHT", ins, "BOTTOMRIGHT", -18, 0)
    ins:HookScript("OnShow", function()
        inspectButton:SetShown(registered == true)
        if registered and db().inspectAuto then checkInspected() end
    end)
end

local function onAddonLoaded(_, name)
    if name == "Blizzard_InspectUI" then hookInspect() end
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
    ADDON_LOADED = onAddonLoaded,
    PLAYER_REGEN_ENABLED = function() if _G.InspectFrame then hookInspect() end end,
    UI_INFO_MESSAGE = onInfo,
    MAIL_SHOW = onMailShow,
}

function TC.Apply()
    local on = QoL.mod.active and (db().tradeCheck or db().mailCheck) and true or false
    if on == registered then return end
    registered = on
    for event, fn in pairs(EVENTS) do QoL.SyncEvent(on, event, fn) end
    if on and _G.InspectFrame then hookInspect() end
    if inspectButton then inspectButton:SetShown(on) end
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
    if inspectButton then inspectButton:Hide() end
end
