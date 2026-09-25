-- VuloForeverUI / Modules / Chat / Fade
--
-- The chat goes quiet when nothing happens, and comes back the moment it has
-- something to say or the mouse asks for it.
--
-- Driven by a TIMER, not by a per-frame handler: the interesting moment is
-- "nothing has happened for fifteen seconds", and that is one timer, where an
-- OnUpdate would be sixty wake-ups a second to ask the same question. The
-- short alpha slide is the only thing that runs per frame, and only while it
-- is sliding.
local _, ns = ...
local Chat = ns.Chat

local Fade = {}
Chat.Fade = Fade

local IN_TIME, OUT_TIME = 0.25, 1.0

local timer, driver
local current, target = 1, 1

-- Every surface of ours the fade applies to. The client's own frames are NOT
-- in here: their alpha is the suppression the engine set, and a fade that
-- wrote over it would bring the client's text back at half strength on top of
-- ours.
--
-- The tab strip and the button column are asked for BY NAME. Both are parented
-- to UIParent, not to the panel -- they have to sit beside and above it -- so
-- neither inherits the panel's alpha, and leaving them out meant the chat
-- faded while its own tabs and buttons stayed at full strength. Invisible at
-- "never", that left a row of labels and five icons floating over nothing.
-- Each surface comes with its own ceiling, which the fade multiplies into.
-- That is how the button column gets a "only while the mouse is near" of its
-- own without a second piece of code writing the same frame's alpha.
local function surfaces()
    local out = {}
    for _, cf in ipairs(Chat.Frames()) do
        local d = Chat.Data(cf)
        if Chat.Owned(cf) then
            if d.bg then out[#out + 1] = { f = d.bg, max = 1 } end
            if d.host then out[#out + 1] = { f = d.host, max = 1 } end
            -- The combat log's text is the client's own, drawn on the window
            -- itself, so the window is what fades. The client's own hover
            -- fades write its art and scroll bar, never the window's alpha.
            if d.native then out[#out + 1] = { f = cf, max = 1 } end
        end
    end
    local strip = Chat.Tabs and Chat.Tabs.Strip and Chat.Tabs.Strip()
    if strip then out[#out + 1] = { f = strip, max = 1 } end
    local quickHost = Chat.Tabs and Chat.Tabs.QuickHost and Chat.Tabs.QuickHost()
    if quickHost then out[#out + 1] = { f = quickHost, max = 1 } end
    local bar = Chat.Sidebar and Chat.Sidebar.Bar and Chat.Sidebar.Bar()
    if bar then
        out[#out + 1] = { f = bar, max = Chat.Sidebar.AlphaCeiling() }
    end
    return out
end

local function applyAlpha(alpha)
    for _, s in ipairs(surfaces()) do
        s.f:SetAlpha(math.min(alpha, s.max))
    end
end

local function ensureDriver()
    if driver then return driver end
    driver = CreateFrame("Frame")
    driver:Hide()
    driver:SetScript("OnUpdate", function(self, elapsed)
        local speed = (target > current) and (1 / IN_TIME) or (1 / OUT_TIME)
        local step = elapsed * speed
        if target > current then
            current = math.min(target, current + step)
        else
            current = math.max(target, current - step)
        end
        applyAlpha(current)
        if math.abs(current - target) < 0.01 then
            current = target
            applyAlpha(current)
            self:Hide()
        end
    end)
    return driver
end

local function slideTo(value)
    target = value
    ensureDriver():Show()
end

-- ---------------------------------------------------------------- state --

-- The ceiling the visibility setting puts on everything below it.
--
-- One authority, not two. "Never" and an un-hovered "mouseover" are simply a
-- ceiling of zero, so the idle fade underneath keeps working exactly as it did
-- and never has to know which mode it is in -- it just cannot slide ABOVE the
-- ceiling. Two systems both writing alpha is how a chat ends up visible in a
-- mode that says it should not be.
local function ceiling()
    local mode = Chat.db().visibility or "always"
    if mode == "never" then return 0 end
    if mode == "mouseover" then return Fade.mouseOver and 1 or 0 end
    return 1
end

local function fadedAlpha()
    local db = Chat.db()
    local strength = math.max(0, math.min(100, db.idleFadeStrength or 40))
    return math.min(ceiling(), 1 - strength / 100)
end

local function startIdle()
    if not (Chat.mod.active and Chat.db().idleFade) then return end
    if Fade.mouseOver then return end
    slideTo(fadedAlpha())
end

-- Something happened: a line arrived, the mouse came over, somebody typed.
function Fade.Poke()
    if not Chat.mod.active then return end
    local db = Chat.db()
    local top = ceiling()
    if top <= 0 then
        if timer then timer:Cancel(); timer = nil end
        slideTo(0)
        return
    end
    if not db.idleFade then
        slideTo(top)
        return
    end
    slideTo(top)
    if timer then timer:Cancel() end
    timer = C_Timer.NewTimer(db.idleFadeDelay or 15, startIdle)
end

function Fade.SetMouseOver(over)
    Fade.mouseOver = over and true or false
    if over then
        Fade.Poke()
        return
    end
    -- Leaving in mouseover mode hides it whether or not the idle fade is on:
    -- there the mouse IS the switch, and waiting for an idle timer that may be
    -- switched off would leave the chat up for good.
    if (Chat.db().visibility or "always") == "mouseover" then
        if timer then timer:Cancel(); timer = nil end
        slideTo(0)
        return
    end
    if Chat.db().idleFade then
        if timer then timer:Cancel() end
        timer = C_Timer.NewTimer(1, startIdle)
        return
    end
    -- Nothing above changed the target, but a surface ceiling may have: the
    -- button column's "only while the mouse is near" is one. slideTo to the
    -- target we already have runs the driver for one pass, which re-applies
    -- every ceiling. Without it, leaving the chat with the idle fade switched
    -- off left the column standing.
    slideTo(target)
end

-- The mouse watch. The chat frame itself answers the mouse for its links, so
-- the hover is asked of it rather than of a box of ours over it.
-- Per FRAME, not once for the module: a window opened later would otherwise
-- fade with the rest and never come back under the mouse, because it never got
-- the hover hooks. And the poke at the end runs on EVERY pass, which is what
-- makes switching the fade off in the settings take effect at once instead of
-- at the next incoming line.
function Fade.Install()
    for _, cf in ipairs(Chat.Frames()) do
        local d = Chat.Data(cf)
        if Chat.Owned(cf) and not d.fadeHooked then
            d.fadeHooked = true
            pcall(cf.HookScript, cf, "OnEnter", function() Fade.SetMouseOver(true) end)
            pcall(cf.HookScript, cf, "OnLeave", function() Fade.SetMouseOver(false) end)
        end
    end
    Fade.Poke()
end

function Fade.Release()
    Fade.mouseOver = false
    if timer then timer:Cancel(); timer = nil end
    if driver then driver:Hide() end
    current, target = 1, 1
    applyAlpha(1)
end
