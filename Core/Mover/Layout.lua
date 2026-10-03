-- VuloForeverUI / Core / Mover / Layout: layout capture/apply and the export string format.
local _, ns = ...
local MV = ns._MV
local applyPos  = MV.applyPos
local commitPos = MV.commitPos

-- Layout snapshot: key -> {x,y,scale,anchor}.
--
-- Movers with their own opts.applyPos (chat, minimap parts, the classic bar
-- rows, the meter windows, frames moved through a proxy) are in it too, with
-- their POSITION only: each of them treats db.x/db.y as the centre it is told
-- to go to and re-derives its own anchor model from there -- the same contract
-- "Reset" relies on when it writes 0,0 and calls applyPos. Scale and anchor
-- stay theirs; a flat snapshot cannot say what those mean for them.
function ns:CaptureLayout()
    local snap = {}
    for _, mover in ipairs(ns._movers) do
        local k  = mover.key
        local o  = mover.opts
        local db = o and o.db
        if k and db then
            local e = { x = db.x or 0, y = db.y or 0 }
            if not o.applyPos then
                if o.scalable  and db.scale  then e.scale  = db.scale  end
                if o.anchorable and db.anchor then e.anchor = db.anchor end
            end
            snap[k] = e
        end
    end
    return snap
end

-- Returns how many movers were moved; movers absent from the snapshot are untouched.
function ns:ApplyLayout(snap)
    if type(snap) ~= "table" then return 0 end
    local n = 0
    for _, mover in ipairs(ns._movers) do
        local o  = mover.opts
        local k  = mover.key
        local e  = k and snap[k]
        local db = o and o.db
        if e and db then
            db.x, db.y = tonumber(e.x) or 0, tonumber(e.y) or 0
            if not o.applyPos then
                if o.scalable   then db.scale  = tonumber(e.scale) or db.scale end
                if o.anchorable then db.anchor = e.anchor or db.anchor end
            end
            -- through the combat queue: a protected target cannot be placed mid-fight
            if o.applyPos then pcall(applyPos, mover) else pcall(commitPos, mover) end
            n = n + 1
        end
    end
    ns:ApplyAllMoverLinks()
    return n
end

-- Export format: VFUI1!<name>!key=x,y[,s<scale>][,a<anchor>];...!<checksum>
local function esc(s)
    return (tostring(s):gsub("[%%;=,!\n\r]", function(c)
        return string.format("%%%02X", string.byte(c))
    end))
end
local function unesc(s)
    return (tostring(s):gsub("%%(%x%x)", function(h)
        return string.char(tonumber(h, 16))
    end))
end
local function checksum(s)
    local sum = 0
    for i = 1, #s do sum = (sum * 31 + string.byte(s, i)) % 1000000007 end
    return string.format("%X", sum)
end

function ns:SerializeLayout(name, snap)
    local parts = {}
    for k, e in pairs(snap or {}) do
        -- Two decimals, not whole units: positions are pixel-snapped now and
        -- rounding to integers here would undo that on every export/import.
        local s = esc(k) .. "=" .. string.format("%.2f", tonumber(e.x) or 0)
                          .. "," .. string.format("%.2f", tonumber(e.y) or 0)
        if e.scale  then s = s .. ",s" .. string.format("%.4g", e.scale) end
        if e.anchor then s = s .. ",a" .. esc(e.anchor) end
        parts[#parts + 1] = s
    end
    table.sort(parts)
    local payload = esc(name or "") .. "!" .. table.concat(parts, ";")
    return "VFUI1!" .. payload .. "!" .. checksum(payload)
end

-- Returns name, snap on success; nil, errorKey on failure.
function ns:DeserializeLayout(str)
    if type(str) ~= "string" then return nil, "empty" end
    str = str:gsub("^%s+", ""):gsub("%s+$", "")
    if str == "" then return nil, "empty" end
    local payload, sum = str:match("^VFUI1!(.*)!(%x+)$")
    if not payload then return nil, "format" end
    if checksum(payload) ~= sum then return nil, "checksum" end
    local namePart, body = payload:match("^(.-)!(.*)$")
    if not namePart then return nil, "format" end
    local snap = {}
    if body ~= "" then
        for entry in body:gmatch("[^;]+") do
            local k, vals = entry:match("^(.-)=(.+)$")
            if k then
                local e = {}
                for tok in vals:gmatch("[^,]+") do
                    local p = tok:sub(1, 1)
                    if     p == "s" then e.scale  = tonumber(tok:sub(2))
                    elseif p == "a" then e.anchor = unesc(tok:sub(2))
                    elseif not e.x  then e.x = tonumber(tok)
                    elseif not e.y  then e.y = tonumber(tok) end
                end
                if e.x and e.y then snap[unesc(k)] = e end
            end
        end
    end
    return unesc(namePart), snap
end
