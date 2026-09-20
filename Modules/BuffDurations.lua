-- Short buff durations: "58m" / "2h" under Blizzard's buff and debuff icons instead of the client's localized "58 min" / "2 Std.".
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("buffdurations", {
    name        = "Short Buff Durations",
    group       = "HUD",
    description = "Shortens the time under your buffs and debuffs to one letter: 58m, 2h, 4s.",
    defaults = {
        enabled = true,
    },
})

-- The client's own rule, kept as it is so only the spelling changes
-- (Blizzard_SharedXML/TimeUtil.lua:463 SecondsToTimeAbbrev, threshold 1.5):
-- a unit takes over once the time reaches one and a half of it, rounded up.
local MIN, HOUR, DAY = 60, 3600, 86400
local THRESHOLD = 1.5

local function short(seconds)
    if seconds >= DAY * THRESHOLD then return "%dd", math.ceil(seconds / DAY) end
    if seconds >= HOUR * THRESHOLD then return "%dh", math.ceil(seconds / HOUR) end
    if seconds >= MIN * THRESHOLD then return "%dm", math.ceil(seconds / MIN) end
    return "%ds", seconds
end

-- Runs after Blizzard_BuffFrame/BuffFrame.lua:1355 AuraButtonMixin:UpdateDuration,
-- which has just written its own text. In combat the time left is a secret
-- value: no comparison and no arithmetic, so Blizzard's text stays as it is
-- there. (A curve cannot help either -- Curve:Evaluate takes secrets only from
-- untainted code.)
local function afterUpdateDuration(self, timeLeft)
    if not mod.active or self.isExample then return end
    -- Secret check first: even "== nil" is a comparison, and that throws.
    if not ns.CanRead(timeLeft) or type(timeLeft) ~= "number" then return end
    local duration = self.Duration
    if not duration then return end
    duration:SetFormattedText(short(timeLeft))
end

-- The buttons are created once, in AuraFrame_OnLoad (BuffFrame.lua:191), and
-- carry their own copy of the mixin method, so each one is hooked by itself.
-- A secure hook cannot be taken back; mod.active is what switches it off, and
-- Blizzard rewrites the text on the very next frame.
local hooked = setmetatable({}, { __mode = "k" })

local function hookFrame(auraFrame)
    if not (auraFrame and auraFrame.auraFrames) then return end
    for _, button in ipairs(auraFrame.auraFrames) do
        -- private aura anchors sit in the same list and have no duration text
        if not hooked[button] and type(button.UpdateDuration) == "function" then
            hooked[button] = true
            hooksecurefunc(button, "UpdateDuration", afterUpdateDuration)
        end
    end
end

function mod:OnEnable()
    hookFrame(_G.BuffFrame)
    hookFrame(_G.DebuffFrame)
end

function mod:OnDisable() end

function mod:GetOptions()
    return {
        { type = "header", text = L["Short Buff Durations"] },
        { type = "desc", text = L["|cffaaaaaaWrites the time under your buffs and debuffs with one letter: 58m, 2h, 4s. In combat the game hides these times from addons, so its own wording is shown there.|r"] },
    }
end
