-- VuloForeverUI / Core / TaintTrace
--
-- Finds out WHO taints the client's party and raid frames. Reported
-- 2026-11-28: CompactUnitFrame_GetRangeAlpha read `outOfRange` (a secret
-- boolean) "while execution tainted by VuloForeverUI" on a plain UNIT_FLAGS
-- event, with the Edit Mode preview status still on the frame. Nothing of
-- ours touches those frames, so something of ours is READ on their way, or a
-- field of theirs was written while our execution was on the stack.
--
-- This only watches. After each client range update and centre-icon update it
-- asks whether the fields just written are still secure. The first time one
-- is not, it notes the call stack that led there and every tainted field on
-- the frame, its option table and the Edit Mode manager, once per session.
-- A file of ours in the stack is the caller; a stack of the client's own
-- files means the run read something of ours on its way, and the field list
-- names it. Read back through the return channel (`kind = "taint"`).
local _, ns = ...

local noted = {}

local function stack()
    local s = (type(debugstack) == "function" and debugstack(3, 12, 6)) or "?"
    return (s:gsub("Interface/AddOns/", ""):gsub("%s+", " ")):sub(1, 1400)
end

local function taintedFields(label, tbl, out)
    if type(tbl) ~= "table" then return end
    for key in pairs(tbl) do
        local secure, by = issecurevariable(tbl, key)
        if not secure and #out < 40 then
            out[#out + 1] = label .. "." .. tostring(key) .. "<" .. tostring(by) .. ">"
        end
    end
end

local function scan(frame)
    local out = {}
    taintedFields("frame", frame, out)
    taintedFields("frame.optionTable", frame and frame.optionTable, out)
    taintedFields("EditModeManagerFrame", _G.EditModeManagerFrame, out)
    for _, name in ipairs({ "CompactUnitFrame_UpdateInRange", "CompactUnitFrame_GetRangeAlpha",
        "CompactUnitFrame_UpdateCenterStatusIcon", "CompactUnitFrame_GetCenterStatusIconState",
        "EditModeManagerFrame", "DefaultCompactUnitFrameOptions", "CompactPartyFrame",
        "CompactRaidFrameContainer", "UnitPhaseReason", "UnitInOtherParty" }) do
        local secure, by = issecurevariable(name)
        if not secure then out[#out + 1] = "_G." .. name .. "<" .. tostring(by) .. ">" end
    end
    if #out == 0 then return "no tainted field on the frame, its options or the Edit Mode manager" end
    return table.concat(out, ", ")
end

local function check(frame, key, where)
    -- type() and not `== nil`: outOfRange is a secret boolean, and comparing
    -- one from our code throws.
    if noted[key] or type(frame) ~= "table" or type(frame[key]) == "nil" then return end
    local secure, by = issecurevariable(frame, key)
    if secure then return end
    noted[key] = true
    local name = (frame.GetName and frame:GetName()) or "?"
    ns.Diag.Note("taint", ("%s.%s written tainted by %s in %s: %s")
        :format(name, key, tostring(by), where, stack()))
    ns.Diag.Note("taint", "tainted around " .. name .. ": " .. scan(frame))
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    if type(issecurevariable) ~= "function" or type(hooksecurefunc) ~= "function" then return end
    if _G.CompactUnitFrame_UpdateInRange then
        hooksecurefunc("CompactUnitFrame_UpdateInRange", function(frame)
            check(frame, "outOfRange", "UpdateInRange")
        end)
    end
    if _G.CompactUnitFrame_UpdateCenterStatusIcon then
        hooksecurefunc("CompactUnitFrame_UpdateCenterStatusIcon", function(frame)
            check(frame, "editModeStatus", "UpdateCenterStatusIcon")
        end)
    end
end)
