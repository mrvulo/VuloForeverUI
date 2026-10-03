-- VuloForeverUI / Core / Mover / Fade: transparency by situation (combat, out of combat, mouseover).
local _, ns = ...
local MV = ns._MV
local moverShouldEdit = MV.moverShouldEdit

-- ---------------------------------------------------------------------------
-- Transparency by situation: db.fade = { combat = 0..1, ooc = 0..1,
-- mouseover = bool }. Absent, or both at 1 = the frame is left alone; this
-- code only ever writes alpha to a frame someone faded.
--
-- SetAlpha is not a protected call, so this also runs in a fight, on secure
-- frames too. The frame that fades is opts.fadeTarget (the real Blizzard
-- frame behind a proxy box) or the target. opts.noFade = the module fades
-- that frame itself (chat, cooldown bars), and two writers would fight.
--
-- In edit mode every frame is at full strength: the boxes are children of
-- their targets and would fade with them.
local fadeInCombat = false
local fadeHover = {}
local fadeDriver, fadePolling

local function fadeTarget(m) return m.opts.fadeTarget or m.target end

function ns:MoverCanFade(m)
    return m ~= nil and m.opts ~= nil and m.opts.db ~= nil and not m.opts.noFade
end

function ns:GetMoverFade(m, state)
    local f = m and m.opts and m.opts.db and m.opts.db.fade
    if state == "mouseover" then return not f or f.mouseover ~= false end
    return (f and f[state]) or 1
end

local function isFaded(m)
    local f = m.opts.db and m.opts.db.fade
    return type(f) == "table" and ((f.combat or 1) < 1 or (f.ooc or 1) < 1)
end

local function wantAlpha(m)
    if moverShouldEdit(m) then return 1 end
    local f = m.opts.db.fade
    if f.mouseover ~= false and fadeHover[m] then return 1 end
    if fadeInCombat then return f.combat or 1 end
    return f.ooc or 1
end

local function setAlpha(t, a)
    local cur = t:GetAlpha()
    if not (ns.CanRead(cur) and math.abs(cur - a) < 0.01) then t:SetAlpha(a) end
end

-- The poll runs only while some frame is faded: mouseover has no event, and
-- a module that rebuilds its frame puts the alpha back to 1 on its own.
local function fadePass()
    local any = false
    for _, m in ipairs(ns._movers) do
        if ns:MoverCanFade(m) then
            local t = fadeTarget(m)
            if isFaded(m) then
                any = true
                local over = t:IsVisible() and t:IsMouseOver()
                fadeHover[m] = ns.CanRead(over) and over == true or nil
                setAlpha(t, wantAlpha(m))
                m._faded = true
            elseif m._faded then
                -- switched back to full strength: hand the alpha back once
                m._faded, fadeHover[m] = nil, nil
                t:SetAlpha(1)
            end
        end
    end
    return any
end

function ns:ApplyMoverFades()
    if not fadeDriver then
        fadeDriver = CreateFrame("Frame")
        fadeDriver:RegisterEvent("PLAYER_REGEN_DISABLED")
        fadeDriver:RegisterEvent("PLAYER_REGEN_ENABLED")
        fadeDriver:RegisterEvent("PLAYER_ENTERING_WORLD")
        fadeDriver:SetScript("OnEvent", function(_, event)
            if event == "PLAYER_ENTERING_WORLD" then
                -- the modules build their frames around this event; a moment
                -- later every mover exists and gets its saved fade
                fadeInCombat = InCombatLockdown()
                C_Timer.After(1, function() ns:ApplyMoverFades() end)
                return
            end
            fadeInCombat = event == "PLAYER_REGEN_DISABLED"
            ns:ApplyMoverFades()
        end)
        fadeInCombat = InCombatLockdown()
    end
    local any = fadePass()
    if any and not fadePolling then
        fadePolling = true
        local acc = 0
        fadeDriver:SetScript("OnUpdate", function(self, elapsed)
            acc = acc + elapsed
            if acc < 0.1 then return end
            acc = 0
            if not fadePass() then
                self:SetScript("OnUpdate", nil)
                fadePolling = false
            end
        end)
    end
end

-- Built at load, so the login event reaches it.
ns:ApplyMoverFades()

function ns:SetMoverFade(m, state, value)
    if not ns:MoverCanFade(m) then return end
    local db = m.opts.db
    if type(db.fade) ~= "table" then db.fade = {} end
    db.fade[state] = value
    ns:ApplyMoverFades()
end
