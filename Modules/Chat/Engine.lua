-- VuloForeverUI / Modules / Chat / Engine
--
-- The bridge: every line the client writes into a chat frame is written a
-- second time into a message frame of ours, and the client's copy is made
-- invisible. Two surfaces, one scroll offset, one set of hyperlink hit zones.
--
-- WHY TWO SURFACES AND NOT ONE
--
-- The client's frame has to stay alive and has to keep its text: its font
-- strings carry the hyperlink hit zones, and those zones are what turns a
-- click on an item link into Blizzard's own secure SetItemRef. So the client's
-- text stays exactly where it is, at alpha zero, and ours is drawn over it in
-- the same font, wrapped the same way, scrolled to the same line. Click lands
-- on theirs, reading happens on ours.
--
-- That alignment is the whole difficulty of this file:
--   * the same font on both surfaces, or the zones drift sideways
--   * the same indented word wrap, or every wrapped line's link is off
--   * the same scroll offset after every single add, because a message frame
--     pins a scrolled view by itself and the two would drift a line apart
--
-- WHAT MAY NOT BE DONE HERE
--
--   * the hook is hooksecurefunc, never a replacement of cf.AddMessage: a
--     replaced method taints the secure message handler, whose whisper tail
--     then dies on the secret name of the sender
--   * nothing is reparented -- suppression is alpha and mouse state only
--   * no field is written on a chat frame; state lives in Chat.Data(cf)
--   * a secret line is asked about with type()/IsSecret BEFORE anything else
--     touches it, and then passed on whole
local _, ns = ...
local Chat = ns.Chat

local Engine = {}
Chat.Engine = Engine

-- ---------------------------------------------------------------- suppress --

-- The client's visuals, taken down to nothing. Alpha only, and once per frame:
-- nothing in Blizzard's own code writes these alphas back, while reparenting
-- any of it would taint the next secure pass that touches the frame.
function Engine.Suppress(cf)
    local d = Chat.Data(cf)
    if d.suppressed then return end
    d.suppressed = true

    if cf.FontStringContainer then
        d.hadContainerAlpha = true
        cf.FontStringContainer:SetAlpha(0)
    end
    -- The scrollbar: ours is drawn on the panel, so the client's goes quiet.
    -- GetAlpha on these widgets can answer with a secret while chat is
    -- restricted, so it is never read back -- only written.
    local sb = cf.ScrollBar
    if sb then
        if sb.Track then sb.Track:SetAlpha(0) end
        pcall(sb.SetAlpha, sb, 0)
        pcall(sb.EnableMouse, sb, false)
    end
    if cf.ScrollToBottomButton then
        -- Its alpha is animated by the client, so no alpha of ours can win an
        -- argument with it; hiding it on every show is the version that holds.
        pcall(cf.ScrollToBottomButton.SetAlpha, cf.ScrollToBottomButton, 0)
        pcall(cf.ScrollToBottomButton.HookScript, cf.ScrollToBottomButton, "OnShow", function(self)
            if Chat.mod.active then pcall(self.Hide, self) end
        end)
    end
    if cf.buttonFrame then pcall(cf.buttonFrame.SetAlpha, cf.buttonFrame, 0) end
end

function Engine.Unsuppress(cf)
    local d = Chat.Data(cf)
    if not d.suppressed then return end
    d.suppressed = false
    if cf.FontStringContainer then cf.FontStringContainer:SetAlpha(1) end
    local sb = cf.ScrollBar
    if sb then
        if sb.Track then sb.Track:SetAlpha(1) end
        pcall(sb.SetAlpha, sb, 1)
        pcall(sb.EnableMouse, sb, true)
    end
    if cf.buttonFrame then pcall(cf.buttonFrame.SetAlpha, cf.buttonFrame, 1) end
    if cf.ScrollToBottomButton then
        pcall(cf.ScrollToBottomButton.SetAlpha, cf.ScrollToBottomButton, 1)
    end
    -- The font we wrote is given back too, or the client's chat keeps our
    -- typeface and our size after the module is switched off.
    if d.oldFont then
        pcall(cf.SetFont, cf, d.oldFont[1], d.oldFont[2], d.oldFont[3])
    elseif _G.ChatFontNormal then
        pcall(cf.SetFont, cf, _G.ChatFontNormal:GetFont())
    end
    if d.oldWrap ~= nil then pcall(cf.SetIndentedWordWrap, cf, d.oldWrap) end
    if d.wheelSet then
        d.wheelSet = nil
        pcall(cf.SetScript, cf, "OnMouseWheel", nil)
    end
end

-- ---------------------------------------------------------------- surface --

-- Our own message frame for one window. A real ScrollingMessageFrame, not a
-- pool of font strings: it wraps text exactly as the client's does, which is
-- the requirement the hyperlink zones impose, and it handles a secret string
-- the same way the client's does.
function Engine.Surface(cf)
    local d = Chat.Data(cf)
    if d.smf then return d.smf end

    local host = CreateFrame("Frame", nil, UIParent)
    host:SetFrameStrata(cf:GetFrameStrata())
    host:SetFrameLevel((cf:GetFrameLevel() or 1) + 2)
    d.host = host

    local smf = CreateFrame("ScrollingMessageFrame", nil, host)
    smf:SetAllPoints(host)
    smf:SetMaxLines(Chat.MAX_LINES)
    smf:SetFading(false)
    smf:SetJustifyH("LEFT")
    smf:SetIndentedWordWrap(true)
    -- A message frame made from Lua starts with scrolling switched OFF, and
    -- then ScrollUp and ScrollDown are silently no-ops.
    if smf.SetScrollAllowed then smf:SetScrollAllowed(true) end
    -- It answers no mouse at all: the click belongs to the client's invisible
    -- text underneath, which is where the hyperlink zones live.
    smf:EnableMouse(false)
    smf:EnableMouseWheel(false)
    d.smf = smf

    return smf
end

-- The font, set on BOTH surfaces from one place. A different font on the two
-- is the bug where a link clicks several characters away from where it looks.
function Engine.ApplyFont(cf)
    local db = Chat.db()
    local d = Chat.Data(cf)
    if not d.smf then return end

    -- Once, before our first write: what the client had. Read through CanRead,
    -- because a font query can answer with a secret while chat is restricted,
    -- and an unreadable answer simply means we restore from the client's own
    -- chat font object instead.
    if d.oldFont == nil then
        d.oldFont = false
        local ok, f, sz, fl = pcall(cf.GetFont, cf)
        if ok and ns.CanRead(f) and type(f) == "string" then d.oldFont = { f, sz, fl } end
        local okw, wrap = pcall(cf.GetIndentedWordWrap, cf)
        if okw and ns.CanRead(wrap) then d.oldWrap = wrap end
    end

    local path = ns.ModuleFontPath and ns.ModuleFontPath("chat") or ns.UI.FONT_PATH
    local size = db.fontSize or 12
    local flags = (db.fontOutline ~= "NONE") and db.fontOutline or nil

    if path then
        pcall(d.smf.SetFont, d.smf, path, size, flags)
        -- The client's copy has to match glyph for glyph, or its hit zones no
        -- longer sit under our letters.
        pcall(cf.SetFont, cf, path, size, flags)
    end
    -- Re-asserted here rather than once at setup: the client resets it on its
    -- own font and dock passes.
    pcall(cf.SetIndentedWordWrap, cf, true)
end

-- ---------------------------------------------------------------- names --

-- Player names in their class colour.
--
-- Not done by us, and it cannot be: colouring a name means finding it in the
-- line and wrapping it, which is a search and a join on a string that may be
-- secret. What the CLIENT offers instead is a per-channel switch for exactly
-- this, so the colouring happens inside its own formatter where the text is
-- still plain. We only turn the switch.
local NAME_GROUPS = {
    "SAY", "EMOTE", "YELL", "GUILD", "OFFICER", "PARTY", "PARTY_LEADER",
    "RAID", "RAID_LEADER", "RAID_WARNING", "INSTANCE_CHAT", "INSTANCE_CHAT_LEADER",
    "WHISPER", "CHANNEL",
}

function Engine.ApplyNameColors()
    local want = Chat.db().classColorNames and true or false
    local toggle = _G.ToggleChatColorNamesByClassGroup
    if type(toggle) ~= "function" then return false end
    for _, group in ipairs(NAME_GROUPS) do
        pcall(toggle, want, group)
    end
    return true
end

-- ---------------------------------------------------------------- scroll --

-- One scroll authority: the client's frame. Ours only ever copies from it.
local function mirrorScroll(cf)
    local d = Chat.Data(cf)
    if not d.smf then return end
    local ok, offset = pcall(cf.GetScrollOffset, cf)
    if ok and ns.CanRead(offset) and type(offset) == "number" then
        pcall(d.smf.SetScrollOffset, d.smf, offset)
    end
end
Engine.MirrorScroll = mirrorScroll

local SCROLL_METHODS = {
    "ScrollUp", "ScrollDown", "PageUp", "PageDown", "ScrollToTop", "ScrollToBottom",
}

local function installScroll(cf)
    local d = Chat.Data(cf)
    if d.scrollHooked then return end
    d.scrollHooked = true

    for _, method in ipairs(SCROLL_METHODS) do
        if type(cf[method]) == "function" then
            hooksecurefunc(cf, method, function(self) mirrorScroll(self) end)
        end
    end

    -- The wheel. On this client the chat frame's own wheel script is empty, so
    -- the scroll has to be driven from here -- into the CLIENT's frame, which
    -- then tells ours through the hooks above.
    -- Only when the client has nothing there. Replacing a script on a frame
    -- that is not ours takes something away that we cannot give back, and if
    -- the client does have a handler it already scrolls -- our mirror hooks
    -- above pick that up either way.
    if cf:GetScript("OnMouseWheel") then return end
    d.wheelSet = true
    cf:SetScript("OnMouseWheel", function(self, delta)
        if not Chat.mod.active then return end
        if delta > 0 then
            if IsShiftKeyDown() then self:ScrollToTop() else self:ScrollUp() end
        else
            if IsShiftKeyDown() then self:ScrollToBottom() else self:ScrollDown() end
        end
    end)
    cf:EnableMouseWheel(true)
end

-- ---------------------------------------------------------------- lines --

-- What we put on screen for one message. The timestamp is ours and is put in
-- front of the text -- but ONLY when the text is plain: a secret string may
-- not be concatenated with anything, so a secret line is shown exactly as it
-- came and simply carries no timestamp.
local function displayText(msg)
    local db = Chat.db()
    if ns.IsSecret(msg) or type(msg) ~= "string" then return msg end
    if not db.timestamps then return msg end

    local stamp = date(db.timestampFormat or "%H:%M")
    local c = db.timestampColor
    return ("|cff%02x%02x%02x%s|r %s"):format(
        (c.r or 1) * 255, (c.g or 1) * 255, (c.b or 1) * 255, stamp, msg)
end
Engine.DisplayText = displayText

-- The tail of the client's own AddMessage. Everything it receives may be
-- secret and none of it is inspected beyond "is this secret at all".
local function tail(cf, msg, r, g, b, ...)
    if not Chat.mod.active then return end
    local d = Chat.Data(cf)
    local smf = d.smf
    if not smf then return end

    -- pcall around the add itself: the colours arrive from the client and may
    -- be secret like the text, and one refused line must not take down the
    -- tail that the client is still inside of.
    local okText, text = pcall(displayText, msg)
    pcall(smf.AddMessage, smf, okText and text or msg, r, g, b)

    -- A message frame pins a scrolled view by itself when a line arrives, so
    -- after every single add the offset is taken from the client's frame
    -- again. Without this the two surfaces drift a line apart and every link
    -- is a line off from where it looks.
    mirrorScroll(cf)

    -- The client cleared or reused its window under us. Its buffer is the
    -- truth, so ours is thrown away and refilled on the next pass.
    local okA, mine = pcall(smf.GetNumMessages, smf)
    local okB, theirs = pcall(cf.GetNumMessages, cf)
    -- The restored scrollback sits ON TOP of our buffer and the client knows
    -- nothing about it, so its lines are taken off our count before the two
    -- are compared. Without that the first line after a reload looks like
    -- "the client cleared its window" and threw the whole restore away.
    mine = (type(mine) == "number") and (mine - (d.extraLines or 0)) or mine
    if okA and okB and ns.CanRead(mine) and ns.CanRead(theirs)
        and type(mine) == "number" and type(theirs) == "number" and theirs < mine then
        Chat.Queue("chat.rebuild", function() Engine.RebuildAll() end)
    end

    -- Everything below runs INSIDE the client's own AddMessage, so each piece
    -- is wrapped: an error of ours here would abort the client's handling of
    -- that line, which is how one bad profile value turns into no chat at all.
    if Chat.History then pcall(Chat.History.Capture, msg) end
    if Chat.Fade then pcall(Chat.Fade.Poke) end
    if Chat.Tabs then Chat.Tabs.OnMessage(cf) end
end

-- Fill our surface from the client's stored buffer. Used when a window is
-- taken in and after the client has cleared one under us.
function Engine.Rebuild(cf)
    local d = Chat.Data(cf)
    if not d.smf then return end
    d.smf:Clear()

    local ok, count = pcall(cf.GetNumMessages, cf)
    if not (ok and ns.CanRead(count) and type(count) == "number") then return end
    for i = 1, count do
        local okLine, text, cr, cg, cb = pcall(cf.GetMessageInfo, cf, i)
        if okLine and type(text) ~= "nil" then
            d.smf:AddMessage(displayText(text), cr, cg, cb)
        end
    end
    mirrorScroll(cf)
end

function Engine.RebuildAll()
    for _, cf in ipairs(Chat.Frames()) do
        if Chat.Data(cf).bridged then Engine.Rebuild(cf) end
    end
end

-- ---------------------------------------------------------------- bridge --

-- Take one window in. Once per frame per session: a hook cannot be removed,
-- so the guard is what keeps a second pass from doubling every line.
function Engine.Integrate(cf)
    if not Chat.IsOpen(cf) then return false end
    local d = Chat.Data(cf)

    Engine.Surface(cf)
    installScroll(cf)

    -- The HOOK is the only part that may happen once -- a hook cannot be taken
    -- off. Everything else has to run again on every integrate pass, because
    -- switching the module off and on again undoes all of it, and an early
    -- return here used to leave the client's text visible UNDER ours with our
    -- buffer missing every line that arrived while we were off.
    if not d.bridged then
        d.bridged = true
        hooksecurefunc(cf, "AddMessage", tail)
    end

    Engine.ApplyFont(cf)
    Engine.ApplyNameColors()
    Engine.Rebuild(cf)      -- everything said while we were not looking
    return true
end

function Engine.IntegrateAll()
    for _, cf in ipairs(Chat.Frames()) do
        Engine.Integrate(cf)
    end
end

-- Give the client its own chat back. The hooks stay -- they cannot be taken
-- off -- but they all ask whether the module is active before they do
-- anything, so this is enough to make them inert.
function Engine.Release()
    for _, cf in ipairs(Chat.Frames()) do
        local d = Chat.Data(cf)
        Engine.Unsuppress(cf)
        if d.host then d.host:Hide() end
        d.extraLines = nil
    end
end
