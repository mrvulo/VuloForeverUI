-- VuloForeverUI / Modules / QoL / NodeSparkle
--
-- The herb or ore vein in front of you sparkles: a soft glow, motes rising
-- through it and small stars flashing up, in a colour of your choice.
--
-- HOW, AND WHY ONLY ONE
--
-- No API puts an effect on a world object or tells where nodes are. Soft
-- interact (set up by Professions.lua) picks ONE object near you as the unit
-- "softinteract"; with SoftTargetNameplateInteract on, the client gives that
-- object a nameplate, and the sparkle is drawn on it. So it is always the
-- nearest usable object in front of you, never every node on the screen.
--
-- What the object is comes from the cursor the client would show over it:
-- the herb cursor or the pickaxe. Only those, and only for a profession the
-- character has, open the object nameplate; a mailbox, a chest or an NPC
-- leaves it closed, so nothing else gets a plate it did not have.
--
-- The nameplate CVars are kept and given back by Professions.lua with the rest
-- of its values. With a controller connected the client runs its own interact
-- target, and CVar writes from us made its gamepad bar run as addon code
-- (SetPreferredGamepadInteractTarget blocked) -- so the sparkle stays off then.
local _, ns = ...

local QoL = ns.QoL
local Prof = QoL.Professions

local Sparkle = {}
Prof.Sparkle = Sparkle

local SOFT = "softinteract"
local TEX = "Interface\\AddOns\\VuloForeverUI\\Media\\textures\\"
local SIZE, OFFSET_Y = 110, -40
local STARS, MOTES = 6, 3
local sin, pi, random, sqrt, cos = math.sin, math.pi, math.random, math.sqrt, math.cos

Sparkle.DEFAULT_COLOR = { r = 1, g = 0.76, b = 0.26 }

local function db() return QoL.db().professions end
local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a = pcall(fn, ...)
    if ok then return a end
end

local function padConnected()
    if C_CVar.GetCVar("GamePadEnable") ~= "1" then return false end
    local ids = C_GamePad and call(C_GamePad.GetAllDeviceIDs)
    return type(ids) == "table" and #ids > 0
end

-- Read by Professions.lua when it builds its CVar list.
function Sparkle.Wanted()
    local d = db()
    return QoL.mod.active and d.gatherIcon and d.sparkle and not padConnected() and true or false
end

-- ------------------------------------------------------------ what is it --

local probe, cursorKinds
local function kindOf()
    local obj = call(UnitIsGameObject, SOFT)
    if not ns.CanRead(obj) or obj ~= true then return nil end
    if not probe then
        probe = UIParent:CreateTexture(nil, "BACKGROUND")
        probe:Hide()
        cursorKinds = {}
        for file, kind in pairs({ GatherHerbs = "herb", Mine = "ore" }) do
            for _, pre in ipairs({ "", "Unable" }) do
                local id = call(GetFileIDFromPath, "Interface\\Cursor\\" .. pre .. file)
                if id then cursorKinds[id] = kind end
            end
        end
    end
    if not pcall(SetUnitCursorTexture, probe, SOFT, nil, true) then return nil end
    local tex = probe:GetTexture()
    if not ns.CanRead(tex) then return nil end
    if type(tex) == "number" then return cursorKinds[tex] end
    if type(tex) == "string" then
        local name = tex:lower()
        if name:find("gatherherbs", 1, true) then return "herb" end
        if name:find("mine", 1, true) then return "ore" end
    end
end

local function trained(kind)
    if kind == "herb" then return Prof.KnowsHerbalism() end
    if kind == "ore" then return Prof.KnowsMining() end
    return false
end

-- ------------------------------------------------------------- the plate --

-- nil = not known, set it on the next decision
local gate
local function setGate(open)
    if open == gate or InCombatLockdown() then return end
    gate = open
    local v = open and "1" or "0"
    if C_CVar.GetCVar("SoftTargetNameplateInteract") ~= v then
        C_CVar.SetCVar("SoftTargetNameplateInteract", v)
    end
end

-- ------------------------------------------------------------ the sparkle --

local glow
local release

local function tint(t, r, g, b, a)
    t:SetVertexColor(r, g, b, a <= 0 and 0 or (a >= 1 and 1 or a))
end

local function animate(self, elapsed)
    -- the plate went without a removal event reaching us
    if not (glow.anchor and glow.anchor:IsVisible()) then release(); return end
    if elapsed > 0.1 then elapsed = 0.1 end
    glow.appear = math.min(1, glow.appear + elapsed / 0.45)
    glow.clock = glow.clock + elapsed
    local t = glow.clock
    local a = 1 - (1 - glow.appear) ^ 3
    local breath = 0.5 + 0.5 * sin(t * 2.5)
    local c = glow.color
    local r, g, b = c.r or 1, c.g or 1, c.b or 1

    local h = SIZE * (1.25 + 0.1 * breath)
    glow.halo:SetSize(h, h)
    tint(glow.halo, r, g, b, a * 0.45 * (0.85 + 0.15 * breath))

    -- motes rising slowly through the light, a little paler than the glow
    local lr, lg, lb = r + (1 - r) * 0.55, g + (1 - g) * 0.55, b + (1 - b) * 0.55
    for i, m in ipairs(glow.motes) do
        local climb = (t * 0.14 + i / MOTES) % 1
        m:SetPoint("CENTER", self, "CENTER",
            (i - 2) * SIZE * 0.22 + sin(t * 0.9 + i * 2.3) * SIZE * 0.05,
            (climb - 0.45) * SIZE * 0.7)
        local ms = SIZE * 0.06
        m:SetSize(ms, ms)
        tint(m, lr, lg, lb, a * sin(pi * climb) * 0.7)
    end

    -- stars flash up somewhere in the disc, fade, and come back elsewhere
    for _, s in ipairs(glow.stars) do
        s.age = s.age + elapsed
        if s.age >= s.life then
            local angle, reach = random() * 2 * pi, sqrt(random())
            s.x, s.y = cos(angle) * reach * SIZE * 0.38, sin(angle) * reach * SIZE * 0.38
            s.life, s.scale, s.age = 0.7 + 0.9 * random(), 0.55 + 0.75 * random(), -0.5 * random()
            s.tex:SetPoint("CENTER", self, "CENTER", s.x, s.y)
        end
        if s.age < 0 then
            tint(s.tex, 1, 1, 1, 0)
        else
            local p = sin(pi * (s.age / s.life))
            local size = SIZE * 0.26 * s.scale * (0.6 + 0.4 * p)
            s.tex:SetSize(size, size)
            s.tex:SetRotation(t * 0.6)
            tint(s.tex, lr, lg, lb, a * p)
        end
    end
end

local function build()
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(SIZE, SIZE)
    f:Hide()
    if f.SetIgnoreParentAlpha then f:SetIgnoreParentAlpha(true) end
    local function layer(file, drawLayer)
        local t = f:CreateTexture(nil, drawLayer)
        t:SetTexture(TEX .. file)
        t:SetBlendMode("ADD")
        t:SetPoint("CENTER")
        t:SetVertexColor(1, 1, 1, 0)
        return t
    end
    glow = { frame = f, halo = layer("soft-glow", "BACKGROUND"), motes = {}, stars = {},
        appear = 0, clock = 0, color = Sparkle.DEFAULT_COLOR }
    for i = 1, MOTES do glow.motes[i] = layer("round-fill", "ARTWORK") end
    for i = 1, STARS do
        glow.stars[i] = { tex = layer("sparkle-star", "OVERLAY"), age = 0, life = 0, scale = 1 }
    end
    f:SetScript("OnUpdate", animate)
end

release = function()
    if not glow or not glow.anchor then return end
    local f = glow.frame
    f:Hide()
    f:ClearAllPoints()
    f:SetParent(UIParent)
    glow.anchor = nil
end

local function attach(plate)
    if not glow then build() end
    glow.color = db().sparkleColor or Sparkle.DEFAULT_COLOR
    if glow.anchor == plate then return end
    local f = glow.frame
    f:SetParent(plate)
    f:ClearAllPoints()
    f:SetPoint("CENTER", plate, "CENTER", 0, OFFSET_Y)
    -- a getter on a Blizzard frame may come back secret
    f:SetFrameLevel(math.max(ns.Num(plate:GetFrameLevel(), 1) - 1, 0))
    glow.anchor, glow.appear, glow.clock = plate, 0, random() * 10
    for _, s in ipairs(glow.stars) do s.age, s.life = 0, 0 end
    f:Show()
end

-- --------------------------------------------------------------- deciding --

local on = false

local function evaluate()
    if not on then release(); return end
    local kind = kindOf()
    if not (kind and trained(kind)) then
        setGate(false)
        release()
        return
    end
    setGate(true)
    -- nil until the client has made the plate; NAME_PLATE_UNIT_ADDED follows
    local plate = C_NamePlate and call(C_NamePlate.GetNamePlateForUnit, SOFT)
    if plate then attach(plate) else release() end
end

local function onRemoved(_, unit)
    if not (glow and glow.anchor) then return end
    local plate = C_NamePlate and call(C_NamePlate.GetNamePlateForUnit, unit)
    if plate == glow.anchor then release() end
end

local function onWorld()
    -- the client sets some soft-interact values back after a loading screen
    C_Timer.After(3, function()
        if on and not InCombatLockdown() then
            gate = nil
            Prof.Refresh()
        end
    end)
end

local function onCombatEnd() evaluate() end

local EVENTS = {
    PLAYER_SOFT_INTERACT_CHANGED = evaluate,
    NAME_PLATE_UNIT_ADDED        = evaluate,
    NAME_PLATE_UNIT_REMOVED      = onRemoved,
    PLAYER_ENTERING_WORLD        = onWorld,
    PLAYER_REGEN_ENABLED         = onCombatEnd,
}

-- From Professions.lua after its CVars are set; off = the module is going.
function Sparkle.Apply(off)
    local want = not off and Sparkle.Wanted() and Prof.KnowsGathering()
    if want ~= on then
        on = want
        for event, handler in pairs(EVENTS) do QoL.SyncEvent(on, event, handler) end
    end
    -- Professions.lua has just written the plate switch back to closed
    gate = nil
    evaluate()
end
