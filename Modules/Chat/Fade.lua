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
local function surfaces()
    local out = {}
    for _, cf in ipairs(Chat.Frames()) do
        local d = Chat.Data(cf)
        if d.bridged then
            if d.bg then out[#out + 1] = d.bg end
            if d.host then out[#out + 1] = d.host end
        end
    end
    return out
end

local function applyAlpha(alpha)
    for _, frame in ipairs(surfaces()) do
        frame:SetAlpha(alpha)
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

local function fadedAlpha()
    local db = Chat.db()
    local strength = math.max(0, math.min(100, db.idleFadeStrength or 40))
    return 1 - strength / 100
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
    if not db.idleFade then
        slideTo(1)
        return
    end
    slideTo(1)
    if timer then timer:Cancel() end
    timer = C_Timer.NewTimer(db.idleFadeDelay or 15, startIdle)
end

function Fade.SetMouseOver(over)
    Fade.mouseOver = over and true or false
    if over then
        Fade.Poke()
    elseif Chat.db().idleFade then
        if timer then timer:Cancel() end
        timer = C_Timer.NewTimer(1, startIdle)
    end
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
        if d.bridged and not d.fadeHooked then
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
