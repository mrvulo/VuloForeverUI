-- VuloForeverUI / Modules / ResourceBars / Cast
--
-- Our own cast bar for the player.
--
-- Measured on this client (see docs/forever-client-research.md): every field
-- UnitCastingInfo returns is SECRET -- name, texture, the interrupt flag, the
-- spell id -- while UnitCastingDuration returns a duration OBJECT that is
-- readable, and the object is the whole bar: StatusBar:SetTimerDuration runs
-- the fill in C, frame by frame, without us touching a clock.
--
-- So the three secret fields each go where a secret is allowed:
--   name       SetText, untouched
--   texture    SetTexture, untouched
--   notInterruptible  a colour fold and an alpha fold, evaluated by the engine
--
-- Blizzard's own player cast bar is hidden rather than reparented: it lives in
-- the secure environment, where UnitRegisterAllEvents is refused to us, and
-- hiding is the one thing that always works.
local _, ns = ...
local RB = ns.RB

local Cast = {}
RB.Cast = Cast

local ELAPSED   = Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.ElapsedTime or 0
local REMAINING = Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.RemainingTime or 1
local IMMEDIATE = Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate or 0

local KEY = "cast"

-- Forward declaration: Cast.Apply switches the style off and has to clear a
-- running cast, and it is written above the clearing code.
local stop

-- ---------------------------------------------------------------- blizzard --

-- Two different things, and mixing them into one flag installed a second hook
-- every time the player switched back to our own bar:
--   hookInstalled  the OnShow hook is laid, and a hook is never taken off
--   hiddenBlizzard we are hiding the client's bar RIGHT NOW
local hookInstalled = false
local hiddenBlizzard = false

local function blizzardBar()
    return _G.PlayerCastingBarFrame or _G.CastingBarFrame
end

-- Which of the three the player chose. Everything below branches on this one
-- string, and on nothing else.
local function styleOf()
    local bar = RB.Bar(KEY)
    return (bar and bar.castStyle) or "standard"
end
Cast.Style = styleOf

function Cast.Apply()
    local bar = RB.Bar(KEY)
    local blizz = blizzardBar()
    if not bar then return end

    local mode = styleOf()
    local frame = RB.frames[KEY]

    -- Our own frame exists for one style only. Under the other two it is not
    -- hidden but switched off, so Edit Mode does not offer it either.
    if frame then
        frame.disabledByStyle = (mode ~= "modern")
        if frame.disabledByStyle then
            stop()
        end
        RB.UpdateVisibility(KEY)
    end

    if mode ~= "modern" then
        -- The client's bar stays, and gets whatever the style asks of it.
        -- Showing it again is all we may do: asking it to work out whether it
        -- SHOULD be shown means calling its own update from our context, and
        -- that is the call that makes the client read protected cast values as
        -- us. So after a switch away from our own bar an idle client bar can
        -- sit there once, until its own next cast puts it right.
        if blizz and hiddenBlizzard then
            hiddenBlizzard = false
            pcall(blizz.Show, blizz)
        end
        if mode ~= "classic" then RB.CastSkin.Restore() end
        RB.CastSkin.Apply()
        return
    end

    if not blizz then return end
    if bar.enabled and bar.hideBlizzard then
        hiddenBlizzard = true
        if not hookInstalled then
            hookInstalled = true
            -- HookScript, never SetScript, and never UnregisterAllEvents: the
            -- frame belongs to the secure environment and both of those are
            -- refused there. A hook that hides on every show is the version
            -- that cannot be refused.
            -- THE STYLE IS PART OF THE QUESTION, and leaving it out cost the
            -- Classic style its cast bar: a hook cannot be taken off again, so
            -- one visit to the Modern style used to hide the client's bar for
            -- the rest of the session -- including under the two styles whose
            -- whole job is to show it.
            pcall(blizz.HookScript, blizz, "OnShow", function(self)
                if not hiddenBlizzard or not RB.mod.active then return end
                if styleOf() ~= "modern" then return end
                local b = RB.Bar(KEY)
                if b and b.enabled and b.hideBlizzard then pcall(self.Hide, self) end
            end)
        end
        pcall(blizz.Hide, blizz)
    elseif hiddenBlizzard then
        -- The hook stays, but it asks the style and the setting every time, so
        -- clearing the flag is enough to let the frame live again.
        hiddenBlizzard = false
        pcall(blizz.Show, blizz)
    end
end

function Cast.Release()
    local blizz = blizzardBar()
    if blizz and hiddenBlizzard then
        hiddenBlizzard = false
        pcall(blizz.Show, blizz)
    end
end

-- ---------------------------------------------------------------- paint --

function stop()
    RB.CastSkin.OnCastStop()
    local frame = RB.frames[KEY]
    if not frame then return end
    ns:DurationText(frame, frame.right, nil)
    frame.icon:Hide()
    frame.shield:SetAlpha(0)
    -- The name goes too: Edit Mode and the settings page force this bar back
    -- on screen, and it would carry the last spell it cast into both.
    frame.left:SetText("")
    frame.right:SetText("")
    RB.SetActive(KEY, false)
end

local function start()
    local frame, bar = RB.frames[KEY], RB.Bar(KEY)
    if not bar then return end
    if not frame and styleOf() == "modern" then return end

    local name, texture, notInt, isChannel, duration
    name, _, texture, _, _, _, _, notInt = UnitCastingInfo("player")
    if ns.Exists(name) then
        isChannel = false
        duration = UnitCastingDuration and UnitCastingDuration("player")
    else
        -- A channel returns one field FEWER before the interrupt flag, so it
        -- sits at 7 rather than at 8 (checked against Nameplates/CastBar).
        name, _, texture, _, _, _, notInt = UnitChannelInfo("player")
        if ns.Exists(name) then
            isChannel = true
            duration = UnitChannelDuration and UnitChannelDuration("player")
        end
    end
    if not ns.Exists(name) then stop(); return end

    -- Under the two styles that keep the client's bar, the client draws the
    -- cast and all we add is the icon and the time beside it.
    if styleOf() ~= "modern" then
        RB.CastSkin.OnCastStart(texture, duration)
        return
    end

    if ns.Exists(duration) and frame.fill.SetTimerDuration then
        frame.fill:SetTimerDuration(duration, IMMEDIATE, isChannel and REMAINING or ELAPSED)
        if bar.rightText == "time" then
            ns:DurationText(frame, frame.right, duration)
        end
    else
        frame.fill:SetMinMaxValues(0, 1)
        frame.fill:SetValue(1)
    end

    -- The colour. A channel has its own; an uninterruptible cast has its own;
    -- and "uninterruptible" is a secret boolean, so the engine picks between
    -- the two colours and we never learn which way it went.
    local r, g, b = bar.fillColor.r, bar.fillColor.g, bar.fillColor.b
    if isChannel then
        local c = bar.channelColor
        r, g, b = c.r, c.g, c.b
    end
    if ns.Exists(notInt) then
        local u = bar.uninterruptibleColor
        frame.fill:SetStatusBarColor(ns.FoldColor(notInt, u.r, u.g, u.b, r, g, b))
    else
        frame.fill:SetStatusBarColor(r, g, b)
    end

    if bar.showShield and ns.Exists(notInt) then
        ns.AlphaFromBool(frame.shield, notInt, 1, 0)
    else
        frame.shield:SetAlpha(0)
    end

    RB.SetLeftText(KEY, name, nil)
    if bar.showIcon and ns.Exists(texture) then
        frame.icon:SetTexture(texture)
        frame.icon:Show()
    else
        frame.icon:Hide()
    end

    RB.SetActive(KEY, true)
end

-- Asked by a settings change or a profile switch: re-apply the LOOK, and only
-- while a cast is actually running. It deliberately does not ask the client
-- whether one is -- see Modules/Nameplates/CastBar, which found that under
-- restriction a cast that has just ended still answers with a non-nil secret
-- tuple, and a bar started from that never goes away again.
function Cast.Refresh()
    local frame = RB.frames[KEY]
    if not (frame and frame.active) then return end
    start()
end

-- The full ask. Only a cast event and the login pass may use it.
function Cast.Update()
    local frame = RB.frames[KEY]
    if not frame then return end
    start()
end

function Cast.RegisterEvents(mod)
    local function onStart(_, unit)
        if unit and unit ~= "player" then return end
        start()
    end
    local function onStop(_, unit)
        if unit and unit ~= "player" then return end
        stop()
    end

    mod:RegisterEvent("UNIT_SPELLCAST_START", onStart)
    mod:RegisterEvent("UNIT_SPELLCAST_DELAYED", onStart)
    mod:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START", onStart)
    mod:RegisterEvent("UNIT_SPELLCAST_CHANNEL_UPDATE", onStart)
    mod:RegisterEvent("UNIT_SPELLCAST_EMPOWER_START", onStart)
    mod:RegisterEvent("UNIT_SPELLCAST_EMPOWER_UPDATE", onStart)

    mod:RegisterEvent("UNIT_SPELLCAST_STOP", onStop)
    mod:RegisterEvent("UNIT_SPELLCAST_FAILED", onStop)
    mod:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED", onStop)
    mod:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP", onStop)
    mod:RegisterEvent("UNIT_SPELLCAST_EMPOWER_STOP", onStop)

    mod:RegisterEvent("PLAYER_ENTERING_WORLD", function()
        Cast.Apply()
        start()
    end)
end
