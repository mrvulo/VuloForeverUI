-- VuloForeverUI / Modules / Chat / History
--
-- The last lines of the previous session, put back after a reload, so a
-- /reload no longer costs the conversation you were having.
--
-- WHAT IS STORED, AND WHY THAT AND NOT THE OTHER THING
--
-- The FORMATTED line is stored -- the text as it appeared on screen -- not the
-- event and its arguments. Two reasons: a replayed line then looks exactly
-- like the ones around it, and the alternative would mean re-running the
-- client's own formatting from addon code on data that no longer exists.
--
-- WHAT IS NOT STORED
--
--   * anything secret. In instances, in raids and on Battle.net whispers a
--     line can arrive as a secret string, and a secret may not be measured,
--     compared or written into a saved variable. Those lines are skipped, and
--     capture stops altogether where the client is holding chat back.
--   * Battle.net tokens. A stored |K token resolves against the NEXT session's
--     table, where the same number is somebody else -- a whole conversation
--     replayed under the wrong friend. Any line still carrying one is dropped.
--
-- Replayed lines land in OUR surface only. The client's invisible copy is
-- where hyperlink clicks come from, and we cannot put a line into it without
-- calling into its secure side -- so a link in a replayed line is text, not a
-- link. That is the honest trade for having the text at all.
local _, ns = ...
local L = ns.L
local Chat = ns.Chat

local History = {}
Chat.History = History

local MAX_TEXT = 4096

-- Per character, not per profile: the conversation belongs to the character
-- who had it.
local function store()
    if not VuloForeverUICharDB then return nil end
    VuloForeverUICharDB.chatHistory = VuloForeverUICharDB.chatHistory or {}
    return VuloForeverUICharDB.chatHistory
end

-- Is the client holding chat back right now? Then nothing is captured: what
-- would arrive is secret, and a session log full of skipped lines is worse
-- than no session log.
local function captureAllowed()
    if not Chat.db().history then return false end
    local inInstance, kind = IsInInstance()
    if inInstance and (kind == "party" or kind == "raid" or kind == "pvp" or kind == "arena") then
        return false
    end
    return true
end

-- ---------------------------------------------------------------- capture --

-- The same line reaches us once per window that shows it, and a player with
-- guild in two windows would have stored every guild line twice. The last few
-- lines are remembered and a repeat within a second is dropped. The key is a
-- plain string, which it is allowed to be: the secret test above has already
-- happened by the time anything lands here.
local recent, recentAt = {}, {}

local function isRepeat(text)
    local now = GetTime()
    local seen = recentAt[text]
    if seen and (now - seen) < 1 then return true end
    recentAt[text] = now
    recent[#recent + 1] = text
    if #recent > 40 then
        local gone = table.remove(recent, 1)
        if recentAt[gone] and recentAt[gone] ~= now then recentAt[gone] = nil end
    end
    return false
end

function History.Capture(text)
    if not captureAllowed() then return end
    -- Secret first, before any comparison: on a secret string even a test
    -- against the empty string throws.
    if ns.IsSecret(text) or type(text) ~= "string" then return end
    if text == "" or #text > MAX_TEXT then return end
    if text:find("|K", 1, true) then return end     -- see the header
    if isRepeat(text) then return end

    local log = store()
    if not log then return end
    log[#log + 1] = { text = text, at = time() }

    local limit = math.max(10, math.min(500, Chat.db().historyLines or 100))
    while #log > limit do table.remove(log, 1) end
end

-- ---------------------------------------------------------------- replay --

function History.Replay()
    if not Chat.db().history then return end
    local log = store()
    if not (log and #log > 0) then return end
    if History.replayed then return end

    local cf = _G.ChatFrame1
    local d = cf and Chat.Data(cf)
    -- The flag is set only once there IS somewhere to replay into. Set before
    -- the check, a single early pass -- the module switched on from the
    -- settings window, before the window was taken in -- used to swallow the
    -- whole scrollback for the rest of the session.
    if not (d and d.smf) then return end
    History.replayed = true

    d.smf:AddMessage(("|cff777777%s|r"):format(L["--- previous session ---"]), 0.5, 0.5, 0.5)
    local db = Chat.db()
    for _, entry in ipairs(log) do
        if type(entry) == "table" and type(entry.text) == "string" then
            -- The stamp is the time the line was SAID, taken from the entry --
            -- re-stamping it with the time of the reload would date the whole
            -- conversation to one minute.
            local line = entry.text
            if db.timestamps and type(entry.at) == "number" then
                local c = db.timestampColor
                line = ("|cff%02x%02x%02x%s|r %s"):format(
                    (c.r or 1) * 255, (c.g or 1) * 255, (c.b or 1) * 255,
                    date(db.timestampFormat or "%H:%M", entry.at), line)
            end
            d.smf:AddMessage(line, 0.75, 0.75, 0.75)
        end
    end
    d.smf:AddMessage(("|cff777777%s|r"):format(L["--- this session ---"]), 0.5, 0.5, 0.5)

    -- Two things the restored lines owe the rest of the module:
    --   the client knows nothing about them, so its own line count is lower
    --   than ours by exactly this many, and the bridge has to be told or it
    --   reads the difference as "the client cleared its window"
    --   and the view has to be put back where the client's is, or the two
    --   surfaces show different lines at the same offset
    d.extraLines = (d.extraLines or 0) + #log + 2
    Chat.Engine.MirrorScroll(cf)
end

function History.Clear()
    if VuloForeverUICharDB then VuloForeverUICharDB.chatHistory = nil end
end

function History.Count()
    local log = store()
    return log and #log or 0
end
