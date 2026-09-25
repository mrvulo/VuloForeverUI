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
-- The pieces of the client's scroll bar. Their OWN alpha is ours to write:
-- the client's hover fade animates the bar itself (FCF_FadeInScrollbar), never
-- its children, so alpha 0 on the arrows and the track holds where alpha 0 on
-- the bar is undone by the first mouse-over.
local function barParts(sb)
    return sb.Back, sb.Forward, sb.Track
end

local function setMouse(f, on)
    if not f then return end
    if f.SetMouseClickEnabled then pcall(f.SetMouseClickEnabled, f, on) end
    if f.SetMouseMotionEnabled then pcall(f.SetMouseMotionEnabled, f, on) end
end

-- The client's window art: background, border and the button frame's border,
-- by the names the client itself keeps in CHAT_FRAME_TEXTURES. Its hover fade
-- rewrites the ALPHA of every one of these on each mouse-over, so an alpha of
-- ours cannot hold -- the file is taken away instead, which nothing of the
-- client's ever puts back, and the fade then animates an empty texture. What
-- was there is remembered so switching the module off gives it back.
local function stripArt(cf, d)
    local name = cf:GetName()
    local list = _G.CHAT_FRAME_TEXTURES
    if not name or type(list) ~= "table" then return end
    d.art = d.art or {}
    for _, key in ipairs(list) do
        local t = _G[name .. key]
        if t and t.GetObjectType and t:GetObjectType() == "Texture" then
            if d.art[t] == nil then
                local okA, atlas = pcall(t.GetAtlas, t)
                local okF, file = pcall(t.GetTexture, t)
                d.art[t] = {
                    atlas = okA and ns.CanRead(atlas) and type(atlas) == "string" and atlas ~= "" and atlas or nil,
                    file  = okF and ns.CanRead(file) and file or nil,
                }
            end
            pcall(t.SetTexture, t, "")
        end
    end
end

local function restoreArt(d)
    if not d.art then return end
    for t, was in pairs(d.art) do
        if was.atlas then
            pcall(t.SetAtlas, t, was.atlas)
        elseif was.file then
            pcall(t.SetTexture, t, was.file)
        end
    end
    d.art = nil
end

function Engine.Suppress(cf)
    local d = Chat.Data(cf)
    if d.suppressed then return end
    d.suppressed = true

    -- A native window (the combat log) keeps the client's text: that text is
    -- the only copy there is.
    if cf.FontStringContainer and not d.native then
        d.hadContainerAlpha = true
        cf.FontStringContainer:SetAlpha(0)
    end
    stripArt(cf, d)
    -- The scrollbar: ours is drawn on the panel, so the client's goes quiet.
    -- GetAlpha on these widgets can answer with a secret while chat is
    -- restricted, so it is never read back -- only written.
    local sb = cf.ScrollBar
    if sb then
        for _, part in ipairs({ barParts(sb) }) do
            pcall(part.SetAlpha, part, 0)
            setMouse(part, false)
        end
        if sb.Track and sb.Track.Thumb then setMouse(sb.Track.Thumb, false) end
        setMouse(sb, false)
    end
    local stb = cf.ScrollToBottomButton
    if stb then
        -- Its alpha is animated by the client, so no alpha of ours can win an
        -- argument with it. Hidden holds: hidden now, and hidden again in the
        -- same execution whenever the client shows it. Hooked once -- a hook
        -- cannot come off, so re-enabling the module must not stack another.
        if not d.stbHooked then
            d.stbHooked = true
            pcall(stb.HookScript, stb, "OnShow", function(self)
                if Chat.mod.active then pcall(self.Hide, self) end
            end)
        end
        pcall(stb.Hide, stb)
    end
    if cf.buttonFrame then pcall(cf.buttonFrame.SetAlpha, cf.buttonFrame, 0) end
end

function Engine.Unsuppress(cf)
    local d = Chat.Data(cf)
    if not d.suppressed then return end
    d.suppressed = false
    if cf.FontStringContainer then cf.FontStringContainer:SetAlpha(1) end
    restoreArt(d)
    local sb = cf.ScrollBar
    if sb then
        for _, part in ipairs({ barParts(sb) }) do
            pcall(part.SetAlpha, part, 1)
            setMouse(part, true)
        end
        if sb.Track and sb.Track.Thumb then setMouse(sb.Track.Thumb, true) end
        setMouse(sb, true)
    end
    if cf.buttonFrame then pcall(cf.buttonFrame.SetAlpha, cf.buttonFrame, 1) end
    if cf.ScrollToBottomButton then
        pcall(cf.ScrollToBottomButton.SetAlpha, cf.ScrollToBottomButton, 1)
        pcall(cf.ScrollToBottomButton.Show, cf.ScrollToBottomButton)
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

-- The outline setting as SetFont wants it: "" for none, never nil.
function Engine.FontFlags(db)
    local o = db.fontOutline
    if type(o) ~= "string" or o == "NONE" then return "" end
    return o
end

-- One font family per window. A plain SetFont binds ONE file, and a Latin
-- face has no CJK glyphs; the client's own chat font is a family per
-- alphabet, and CreateFontFamily lets us build the same thing. Created once
-- per window and re-driven in place on every font change. nil when the API
-- is missing or refused -- the caller then falls back to a plain SetFont.
local CJK_FILES = {
    korean             = "Fonts\\2002.ttf",
    simplifiedchinese  = "Fonts\\ARKai_T.ttf",
    traditionalchinese = "Fonts\\blei00d.TTF",
}
-- On a CJK client every line is that alphabet, so it takes the size as set;
-- CJK dropped into a Western chat reads small at Latin sizes and gets +2.
local CLIENT_CJK = ({ koKR = "korean", zhCN = "simplifiedchinese", zhTW = "traditionalchinese" })[GetLocale()]
local families = {}

function Engine.FontFamily(id, path, size, flags)
    if type(id) ~= "number" then return nil end
    local fam = families[id]
    if fam == false then return nil end
    local function members()
        local list = {
            { alphabet = "roman",   file = path, height = size, flags = flags },
            { alphabet = "russian", file = path, height = size, flags = flags },
        }
        for alphabet, file in pairs(CJK_FILES) do
            local own = alphabet == CLIENT_CJK
            list[#list + 1] = { alphabet = alphabet, file = own and path or file,
                height = own and size or size + 2, flags = flags }
        end
        return list
    end
    if not fam then
        if type(_G.CreateFontFamily) ~= "function" then families[id] = false; return nil end
        local ok, made = pcall(_G.CreateFontFamily, "VuloForeverUIChatFont" .. id, members())
        if not (ok and made) then families[id] = false; return nil end
        families[id] = made
        fam = made
    end
    local ok = pcall(function()
        for _, m in ipairs(members()) do
            local fo = fam:GetFontObjectForAlphabet(m.alphabet)
            fo:SetFont(m.file, m.height, m.flags)
            fo:SetJustifyH("LEFT")
        end
    end)
    return ok and fam or nil
end

-- The font, set on BOTH surfaces from one place. A different font on the two
-- is the bug where a link clicks several characters away from where it looks.
function Engine.ApplyFont(cf)
    local db = Chat.db()
    local d = Chat.Data(cf)
    if not (d.smf or d.native) then return end

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
    -- A string, never nil: on this client the flags argument of SetFont is
    -- mandatory, and a nil there raised inside the pcall below -- our message
    -- frame was left with no font at all, and a message frame without a font
    -- drops every line it is handed. That was the whole "empty chat".
    local flags = Engine.FontFlags(db)

    -- A font family first, so Chinese, Korean and Taiwanese lines render
    -- instead of turning into boxes: our face carries the Latin and Cyrillic
    -- alphabets, the client's own CJK files the rest. The same object goes
    -- on both surfaces, which keeps the hit zones under our letters.
    local fam = Engine.FontFamily(cf:GetID(), path, size, flags)
    -- Native: the client draws the text, so the client's frame is the only
    -- surface to dress. No alignment to keep -- there is no second copy.
    -- A font object carries its own alignment and a frame takes it over with
    -- the object; the family's default is CENTER, which centred every combat
    -- log line. Put back to LEFT on every surface after the object lands --
    -- on the bridged windows too, where the client's invisible copy has to
    -- sit exactly where ours does or its link zones slide sideways.
    if d.native then
        if fam then
            pcall(cf.SetFontObject, cf, fam)
        else
            pcall(cf.SetFont, cf, path, size, flags)
        end
        pcall(cf.SetJustifyH, cf, "LEFT")
        return
    end
    if fam then
        pcall(d.smf.SetFontObject, d.smf, fam)
        pcall(cf.SetFontObject, cf, fam)
        pcall(d.smf.SetJustifyH, d.smf, "LEFT")
        pcall(cf.SetJustifyH, cf, "LEFT")
        pcall(d.smf.SetShadowOffset, d.smf, 1, -1)
        pcall(d.smf.SetShadowColor, d.smf, 0, 0, 0, 0.8)
        pcall(cf.SetIndentedWordWrap, cf, true)
        return
    end

    -- SetFont answers false for a file that does not resolve (a shared-media
    -- font whose addon is gone) and leaves the widget fontless, so the shipped
    -- font is the fallback and the client's chat font object the last resort.
    local ok, set = pcall(d.smf.SetFont, d.smf, path, size, flags)
    if not (ok and set) then
        path = ns.UI.FONT_PATH
        ok, set = pcall(d.smf.SetFont, d.smf, path, size, flags)
        if not (ok and set) and _G.ChatFontNormal then
            path = nil
            d.smf:SetFontObject(_G.ChatFontNormal)
        end
    end
    -- The client's copy has to match glyph for glyph, or its hit zones no
    -- longer sit under our letters.
    if path then
        pcall(cf.SetFont, cf, path, size, flags)
    elseif _G.ChatFontNormal then
        pcall(cf.SetFontObject, cf, _G.ChatFontNormal)
    end
    pcall(d.smf.SetShadowOffset, d.smf, 1, -1)
    pcall(d.smf.SetShadowColor, d.smf, 0, 0, 0, 0.8)
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

-- ---------------------------------------------------------------- stamps --

-- The client stamps player chat itself when its own timestamp option is on,
-- and ours stamps every line -- together that was two times on one line. While
-- ours is on, the client's goes off; what the player had is kept in the
-- profile (the CVar survives a reload, so memory alone would forget it) and
-- given back the moment ours is switched off or the module is.
function Engine.ApplyClientStamps()
    if not (C_CVar and C_CVar.GetCVar) then return end
    local db = Chat.db()
    local cur = C_CVar.GetCVar("showTimestamps")
    if type(cur) ~= "string" then return end
    if Chat.mod.active and db.timestamps then
        if cur ~= "none" then
            db.clientStamps = cur
            C_CVar.SetCVar("showTimestamps", "none")
        end
    elseif db.clientStamps then
        if cur == "none" then C_CVar.SetCVar("showTimestamps", db.clientStamps) end
        db.clientStamps = nil
    end
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
    -- the client's wheel handler and the scroll bar go through these two
    "ScrollByAmount", "SetScrollOffset",
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
-- The combat log is left to the client whole: its quick buttons, filters and
-- refill machinery are its own, and a second copy of it drawn by us only ever
-- lay on top of whatever window was really selected.
local function isCombatLog(cf)
    if type(_G.IsCombatLog) ~= "function" then return false end
    local ok, yes = pcall(_G.IsCombatLog, cf)
    return ok and ns.CanRead(yes) and yes and true or false
end
Engine.IsCombatLog = isCombatLog

-- The combat log on our panel, with the client still drawing its text: its
-- art and scroll bar go, our background goes behind it, the font becomes ours
-- and the wheel scrolls it. No hook on its AddMessage and no copy of its
-- lines, so there is nothing of ours in its filter and refill machinery.
function Engine.Adopt(cf)
    if not Chat.IsOpen(cf) then return false end
    local d = Chat.Data(cf)
    d.native = true
    installScroll(cf)
    Engine.ApplyFont(cf)
    return true
end

function Engine.Integrate(cf)
    if not Chat.IsOpen(cf) then return false end
    if isCombatLog(cf) then return Engine.Adopt(cf) end
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
    Engine.ApplyClientStamps()
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
    -- mod.active is already false here, so this hands the client its own
    -- timestamps back.
    Engine.ApplyClientStamps()
end
