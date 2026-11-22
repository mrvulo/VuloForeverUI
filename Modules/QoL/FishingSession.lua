-- VuloForeverUI / Modules / QoL / FishingSession
--
-- What a fishing trip adds up to, and two nudges while it lasts:
--
--   session   casts, catches, catch rate, catches per hour, time spent fishing
--   recap     the catch for a few seconds above the middle of the screen
--   escaped   a sound when the fish got away or the click came too late
--   recast    one sound when the line has been in for a while and nothing
--             was cast again, while the player stands still with the pole
--
-- Fishing.lua forwards the events (channel start/stop, loot, the client's
-- error/info line) to the Fish.On* functions here, so all of it runs only
-- while the fishing part is on.
--
-- The session belongs to the character and survives a reload. Thirty
-- minutes without a cast start a new one; time only counts the gaps under
-- two minutes, so a break does not dilute the catches per hour. A catch is
-- the first fishing loot after a cast -- auto loot opens the loot too, just
-- without the window.
local _, ns = ...
local L = ns.L

local QoL = ns.QoL
local Fish = QoL.Fishing

local NEW_SESSION = 30 * 60
local ACTIVE_GAP = 120
local RECAP_TIME = 4
local RECAP_FADE = 1
local RECAP_ROWS = 4
local ICON = 26

-- Two of the client's own sounds, and shared media after them.
local KITS = { readycheck = 8960, raidwarning = 8959 }

local awaitingLoot = false
local reminder
local recap

-- --------------------------------------------------------- session --

local function session(startNew)
    local c = Fish.CharDB()
    local s = c.session
    local now = time()
    if type(s) ~= "table" or (startNew and now - (s.last or 0) > NEW_SESSION) then
        s = { casts = 0, catches = 0, escaped = 0, seconds = 0, last = now }
        c.session = s
    end
    return s
end

-- time spent fishing: only the short gaps count
local function tick(s)
    local now = time()
    local gap = now - (s.last or now)
    if gap > 0 and gap < ACTIVE_GAP then s.seconds = (s.seconds or 0) + gap end
    s.last = now
end

local function perHour(s)
    if (s.seconds or 0) < 60 then return nil end
    return math.floor(s.catches * 3600 / s.seconds + 0.5)
end

local function clock(sec)
    sec = math.floor(sec or 0)
    local h, m, x = math.floor(sec / 3600), math.floor(sec % 3600 / 60), sec % 60
    if h > 0 then return ("%d:%02d:%02d"):format(h, m, x) end
    return ("%d:%02d"):format(m, x)
end

function Fish.SessionText()
    local s = Fish.CharDB().session
    if type(s) ~= "table" or (s.casts or 0) == 0 then return nil end
    local rate = math.floor(s.catches * 100 / s.casts + 0.5)
    local hour = perHour(s)
    return L["%d casts, %d catches (%d%%), %s per hour, %s fishing"]:format(
        s.casts, s.catches, rate, hour and tostring(hour) or "–", clock(s.seconds))
end

function Fish.ResetSession()
    Fish.CharDB().session = nil
    -- a line out right now belongs to the old session
    awaitingLoot = false
    if ns.UI.RebuildCurrentPage then ns.UI:RebuildCurrentPage() end
end

-- ----------------------------------------------------------- sound --

function Fish.PlayAlert()
    local key = Fish.db().alertSound
    if KITS[key] then
        PlaySound(KITS[key], "Master")
        return
    end
    local path = ns.MediaSoundPath(key)
    if path then PlaySoundFile(path, "Master") end
end

function Fish.AlertValues()
    local v = ns.MediaSoundValues(L["None"])
    table.insert(v, 2, { value = "readycheck", text = L["Ready check"] })
    table.insert(v, 3, { value = "raidwarning", text = L["Raid warning"] })
    return v
end

-- ----------------------------------------------------------- recap --

local function buildRecap()
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(260, 20)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 170)
    f:SetFrameStrata("MEDIUM")
    f:EnableMouse(false)
    f.rows = {}
    for i = 1, RECAP_ROWS do
        local row = CreateFrame("Frame", nil, f)
        row:SetSize(260, ICON)
        row:SetPoint("TOP", f, "TOP", 0, -(i - 1) * (ICON + 4))
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(ICON, ICON)
        row.icon:SetPoint("LEFT")
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.text = row:CreateFontString(nil, "OVERLAY")
        row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
        f.rows[i] = row
    end
    f.footer = f:CreateFontString(nil, "OVERLAY")
    f.anim = f:CreateAnimationGroup()
    local fade = f.anim:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0)
    fade:SetStartDelay(RECAP_TIME)
    fade:SetDuration(RECAP_FADE)
    f.anim:SetScript("OnFinished", function() f:Hide() end)
    f:Hide()
    return f
end

local function showRecap(items, s)
    recap = recap or buildRecap()
    local font, outline = QoL.Font(), QoL.Outline()
    local shown = 0
    for i, row in ipairs(recap.rows) do
        local it = items[i]
        if it then
            shown = i
            row.text:SetFont(font, 13, outline)
            row.icon:SetTexture(it.icon)
            local r, g, b = 1, 1, 1
            local color = it.quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[it.quality]
            if color then r, g, b = color.r, color.g, color.b end
            row.text:SetTextColor(r, g, b)
            row.text:SetText(it.count > 1 and ("%d× %s"):format(it.count, it.name) or it.name)
            row:Show()
        else
            row:Hide()
        end
    end
    if shown == 0 then return end
    recap.footer:SetFont(font, 11, outline)
    recap.footer:SetTextColor(0.7, 0.7, 0.7)
    recap.footer:ClearAllPoints()
    recap.footer:SetPoint("TOP", recap, "TOP", 0, -shown * (ICON + 4) - 2)
    local hour = perHour(s)
    recap.footer:SetText(hour and L["%d catches this session, %d per hour"]:format(s.catches, hour)
        or L["%d catches this session"]:format(s.catches))
    recap.anim:Stop()
    recap:SetAlpha(1)
    recap:Show()
    recap.anim:Play()
end

-- ---------------------------------------------------------- events --

local function stopReminder()
    if reminder then reminder:Cancel(); reminder = nil end
end
Fish.StopReminder = stopReminder

function Fish.OnCast()
    stopReminder()
    local s = session(true)
    tick(s)
    s.casts = s.casts + 1
    awaitingLoot = true
end

-- One sound, only if the player is still standing there with the pole and
-- has not cast again: walking off, mounting or a fight is a choice, not a
-- forgotten cast.
local function remind()
    reminder = nil
    if not Fish.db().recastReminder then return end
    if InCombatLockdown() or IsMounted() or UnitIsDeadOrGhost("player") then return end
    if Fish.ChannelIsFishing() or UnitCastingInfo("player") or not Fish.PoleInHand() then return end
    local speed = GetUnitSpeed("player")
    if ns.CanRead(speed) and type(speed) == "number" and speed > 0 then return end
    Fish.PlayAlert()
end

function Fish.OnLineIn()
    stopReminder()
    if not Fish.db().recastReminder then return end
    local delay = tonumber(Fish.db().recastDelay) or 10
    reminder = C_Timer.NewTimer(delay, remind)
end

function Fish.OnLoot()
    if not awaitingLoot or not IsFishingLoot() then return end
    awaitingLoot = false
    local s = session(false)
    tick(s)
    s.catches = s.catches + 1
    if not Fish.db().recap then return end
    local items = {}
    for slot = 1, GetNumLootItems() do
        if LootSlotHasItem(slot) then
            local icon, name, count, _, quality = GetLootSlotInfo(slot)
            if ns.CanRead(name) and type(name) == "string" and icon then
                count = (ns.CanRead(count) and type(count) == "number") and count or 1
                quality = (ns.CanRead(quality) and type(quality) == "number") and quality or nil
                items[#items + 1] = { icon = icon, name = name, count = count, quality = quality }
            end
        end
    end
    showRecap(items, s)
end

function Fish.OnMessage(msg)
    if not ns.CanRead(msg) or type(msg) ~= "string" then return end
    if msg ~= _G.ERR_FISH_ESCAPED and msg ~= _G.ERR_FISH_NOT_HOOKED then return end
    awaitingLoot = false
    local s = session(false)
    s.escaped = (s.escaped or 0) + 1
    if Fish.db().escapeAlert then Fish.PlayAlert() end
end
