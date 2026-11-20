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
-- ONE LOG PER CHAT WINDOW
--
-- Each window (tab) keeps its own lines and gets exactly those back. The
-- first version kept one list for all windows and replayed it into the first
-- one: whispers from a tab of their own came back in "General" -- or not at
-- all, because a hundred lines of trade chat had pushed them out of the
-- shared list (the player's report, 2026-11-20). A log remembers the name of
-- its window; a window that carries another name by now is another window,
-- and the old lines are not put into it.
--
-- Replayed lines land in OUR surface only. The client's invisible copy is
-- where hyperlink clicks come from, and we cannot put a line into it without
-- calling into its secure side -- so a link in a replayed line is text, not a
-- link. That is the honest trade for having the text at all.
--
-- A PLAYER'S NAME is the one exception, and it is ours, not the client's
-- (F-70, "names" below): a left click on the name in a replayed line opens a
-- whisper to that player. The click is read off our own surface -- which line
-- and which character lie under the mouse -- and nothing is written into the
-- client's chat frame.
local _, ns = ...
local L = ns.L
local Chat = ns.Chat

local History = {}
Chat.History = History

local MAX_TEXT = 4096

-- Rides along with every replayed line as its extra data (the message frame
-- keeps whatever follows the colour), so a line on screen can be told from
-- the session's own, whose links are the client's business.
local OLD = "vfui-old"

-- Per character, not per profile: the conversation belongs to the character
-- who had it. Saved as { v = 2, windows = { [id] = { name, lines } } }.
--
-- `previous` is what the store held when this session first looked at it:
-- the only lines that are ever replayed. Lines captured in this session go
-- into the store, never into `previous`, so a second pass over a window can
-- not hand the running session back as "the previous one".
local previous

local function store()
    if not VuloForeverUICharDB then return nil end
    local s = VuloForeverUICharDB.chatHistory
    if type(s) ~= "table" then s = {}; VuloForeverUICharDB.chatHistory = s end
    if s.v ~= 2 then
        -- The first version: one flat list, replayed into the first window.
        local old = {}
        for i, entry in ipairs(s) do old[i] = entry; s[i] = nil end
        s.v, s.windows = 2, {}
        if #old > 0 then s.windows[1] = { lines = old } end
    end
    if type(s.windows) ~= "table" then s.windows = {} end
    if not previous then
        previous = {}
        for id, w in pairs(s.windows) do
            if type(w) == "table" and type(w.lines) == "table" then
                local copy = {}
                for i, entry in ipairs(w.lines) do copy[i] = entry end
                previous[id] = { name = w.name, lines = copy }
            end
        end
    end
    return s.windows
end

local function windowID(cf)
    local id = cf and cf.GetID and cf:GetID()
    return type(id) == "number" and id or nil
end

local function windowName(id)
    local ok, name = pcall(GetChatWindowInfo, id)
    if ok and type(name) == "string" and name ~= "" then return name end
    return nil
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

-- Called from the tail of a window's own AddMessage (Engine.lua), so a line
-- shown in two windows is kept by both: each gets back what it showed.
function History.Capture(cf, text)
    if not captureAllowed() then return end
    -- Secret first, before any comparison: on a secret string even a test
    -- against the empty string throws.
    if ns.IsSecret(text) or type(text) ~= "string" then return end
    if text == "" or #text > MAX_TEXT then return end
    if text:find("|K", 1, true) then return end     -- see the header

    local id = windowID(cf)
    local windows = id and store()
    if not windows then return end
    local w = windows[id]
    if type(w) ~= "table" or type(w.lines) ~= "table" then
        w = { lines = {} }
        windows[id] = w
    end
    local name = windowName(id)
    if w.name and name and w.name ~= name then w.lines = {} end
    w.name = name or w.name
    local log = w.lines
    log[#log + 1] = { text = text, at = time() }

    local limit = math.max(10, math.min(500, Chat.db().historyLines or 100))
    while #log > limit do table.remove(log, 1) end
end

-- ---------------------------------------------------------------- replay --

-- Puts a window's lines of the previous session onto its surface. Called by
-- the engine right after it has emptied that surface and before it refills
-- it from the client's buffer (Engine.Rebuild), so the old lines always
-- stand above the new ones -- on the first pass after login and on every
-- later one, which used to wipe them for the rest of the session.
function History.Write(cf)
    if not Chat.db().history then return end
    local id = windowID(cf)
    if not (id and store()) then return end
    local old = previous[id]
    if not (old and #old.lines > 0) then return end
    if old.name and old.name ~= windowName(id) then return end
    local d = Chat.Data(cf)
    if not d.smf then return end

    local count = 0
    d.smf:AddMessage(("|cff777777%s|r"):format(L["--- previous session ---"]), 0.5, 0.5, 0.5)
    for _, entry in ipairs(old.lines) do
        if type(entry) == "table" and type(entry.text) == "string" then
            -- As it was captured: a line the client stamped carries that
            -- stamp in its text, with the time it was said.
            d.smf:AddMessage(entry.text, 0.75, 0.75, 0.75, OLD)
            count = count + 1
        end
    end
    d.smf:AddMessage(("|cff777777%s|r"):format(L["--- this session ---"]), 0.5, 0.5, 0.5)

    -- The client knows nothing about these lines, so its own line count is
    -- lower than ours by exactly this many, and the bridge has to be told or
    -- it reads the difference as "the client cleared its window".
    d.extraLines = count + 2
end

-- ---------------------------------------------------------------- names --

-- The player link that character `index` of a line's raw text falls into.
local function playerAt(text, index)
    local init = 1
    while true do
        local s, e, name = text:find("|Hplayer:([^:|]+)[^|]*|h.-|h", init)
        if not s then return nil end
        if index >= s and index <= e then return name end
        init = e + 1
    end
end

-- Is the click meant for the chat? Not when another window lies over it:
-- then that window has the mouse, not the chat frame and not the world.
-- Second value: what had the mouse, for the measurement note.
local function chatHasMouse(cf, host)
    if type(GetMouseFoci) ~= "function" then return true, "?" end
    local top = GetMouseFoci()[1]
    if not top then return true, "none" end
    if top == WorldFrame then return true, "world" end
    if top.IsForbidden and top:IsForbidden() then return false, "forbidden" end
    local label = (top.GetName and top:GetName()) or "unnamed"
    -- a frame that only watches the mouse move takes no click
    if top.IsMouseClickEnabled and not top:IsMouseClickEnabled() then return true, label end
    for _ = 1, 6 do
        if top == cf or top == host then return true, label end
        top = top.GetParent and top:GetParent()
        if not top or (top.IsForbidden and top:IsForbidden()) then break end
    end
    return false, label
end

-- The replayed line under the mouse and the character in it, read off our
-- own surface. Only lines that carry the OLD mark are asked anything: their
-- text is the string we stored ourselves and never a secret.
local function oldLineAt(smf)
    if type(smf.visibleLines) ~= "table" then return nil end
    local scale = ns.Num(smf:GetEffectiveScale(), 0)
    if scale <= 0 then return nil end
    local cx, cy = GetCursorPosition()
    local x, y = cx / scale, cy / scale
    for _, line in ipairs(smf.visibleLines) do
        local info = line.messageInfo
        local extra = type(info) == "table" and info.extraData
        if type(extra) == "table" and ns.CanRead(extra[1]) and extra[1] == OLD and line:IsShown()
            and type(info.message) == "string" and line.FindCharacterIndexAtCoordinate then
            local index, inside = line:FindCharacterIndexAtCoordinate(x, y)
            if ns.CanRead(index) and type(index) == "number" and ns.CanRead(inside) and inside then
                return info.message, index
            end
        end
    end
    return nil
end

local downX, downY
local measured = false

function History.MouseDown(_, button)
    if button ~= "LeftButton" then downX = nil; return end
    downX, downY = GetCursorPosition()
end

-- Any release of the left button, wherever it lands: our surface takes no
-- mouse (the click belongs to the client's text underneath), so this is
-- where a click on it can be seen at all.
function History.MouseUp(_, button)
    if button ~= "LeftButton" or not downX then return end
    local cx, cy = GetCursorPosition()
    local moved = math.abs(cx - downX) > 4 or math.abs(cy - downY) > 4
    downX = nil
    if moved or not (Chat.mod.active and Chat.db().history) then return end
    if IsModifierKeyDown() or IsMouselooking() then return end

    for _, cf in ipairs(Chat.Frames()) do
        local d = Chat.Owned(cf) and Chat.Data(cf)
        local smf = d and d.extraLines and d.smf
        if smf and smf:IsVisible() and smf:IsMouseOver() then
            local ok, text, index = pcall(oldLineAt, smf)
            if not (ok and text) then return end
            local name = playerAt(text, index)
            local free, under = chatHasMouse(cf, d.host)
            -- Once per session, for the return channel: what the client's
            -- "character under the mouse" counts in, and which frame has the
            -- mouse over the chat text, were never measured.
            if not measured and ns.Diag then
                measured = true
                ns.Diag.Note("chat", ("old line click: character %d of %d, name %s, mouse on %s (%s)")
                    :format(index, #text, tostring(name), tostring(under), free and "ours" or "blocked"))
            end
            if name and free and ChatFrameUtil and ChatFrameUtil.SendTell then
                ChatFrameUtil.SendTell(name, cf)
            end
            return
        end
    end
end

-- The client emptied this window (the player cleared the chat): the old
-- lines go with it and are not written back for the rest of the session.
function History.Forget(cf)
    local id = windowID(cf)
    if id and previous then previous[id] = nil end
end

function History.Clear()
    if VuloForeverUICharDB then VuloForeverUICharDB.chatHistory = nil end
    previous = {}
end
