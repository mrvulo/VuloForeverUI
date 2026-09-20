-- VuloForeverUI / Modules / CooldownManager / Bindings
--
-- Which key casts the spell on an icon, and how that key is written on it.
--
-- The answer comes from the ACTION BARS, not from the icon: a cooldown icon is
-- not a button anyone presses, so the key it shows is the key of the action
-- slot that holds the same spell. That is plain data about our own interface,
-- never about a fight -- but GetActionInfo is still read only out of combat,
-- because an action slot is one of the things this client may close off, and a
-- stale map costs nothing while a throw costs the whole paint pass.
local _, ns = ...
local CM = ns.CM

local B = {}
CM.Bindings = B

-- Action slot ranges and the binding command each one answers to. The main
-- bar is the only one with a plain name; every other bar is a MULTIACTIONBAR
-- with its own numbering, and slots that belong to no bar (the paged copies
-- of the main bar) are simply absent here -- they have no binding at all.
local RANGES = {
    { first = 1,   last = 12,  command = "ACTIONBUTTON%d" },
    { first = 61,  last = 72,  command = "MULTIACTIONBAR1BUTTON%d" },
    { first = 49,  last = 60,  command = "MULTIACTIONBAR2BUTTON%d" },
    { first = 25,  last = 36,  command = "MULTIACTIONBAR3BUTTON%d" },
    { first = 37,  last = 48,  command = "MULTIACTIONBAR4BUTTON%d" },
    { first = 145, last = 156, command = "MULTIACTIONBAR5BUTTON%d" },
    { first = 157, last = 168, command = "MULTIACTIONBAR6BUTTON%d" },
    { first = 169, last = 180, command = "MULTIACTIONBAR7BUTTON%d" },
}

-- "SHIFT-BUTTON4" is longer than the icon it would sit on. The short forms
-- below are the ones people read at a glance; anything unknown keeps its own
-- text and is cut to four characters.
local SHORT = {
    ["SHIFT%-"] = "s", ["CTRL%-"] = "c", ["ALT%-"] = "a",
    ["BUTTON"] = "m", ["MOUSEWHEELUP"] = "mu", ["MOUSEWHEELDOWN"] = "md",
    ["NUMPAD"] = "n", ["PAGEUP"] = "pu", ["PAGEDOWN"] = "pd",
    ["SPACE"] = "sp", ["INSERT"] = "ins", ["HOME"] = "hm", ["DELETE"] = "del",
    ["BACKSPACE"] = "bs", ["CAPSLOCK"] = "cl",
}

function B.Abbreviate(key)
    if type(key) ~= "string" or key == "" then return "" end
    local out = key
    for pattern, short in pairs(SHORT) do
        out = out:gsub(pattern, short)
    end
    if #out > 5 then out = out:sub(1, 5) end
    return out
end

-- spellID -> key text, itemID -> key text. Rebuilt, never patched: a single
-- pass over 180 slots is cheaper than working out which slot a change touched.
local spells, items = {}, {}

function B.Rebuild()
    if ns:InCombat() then return end
    wipe(spells)
    wipe(items)
    if not (GetActionInfo and GetBindingKey) then return end
    for _, range in ipairs(RANGES) do
        for slot = range.first, range.last do
            local ok, kind, id = pcall(GetActionInfo, slot)
            if ok and type(id) == "number" then
                -- A macro is a slot like any other; what matters is the spell
                -- it currently casts, which is what the icon shows as well.
                if kind == "macro" and GetMacroSpell then
                    local okm, sid = pcall(GetMacroSpell, id)
                    kind, id = "spell", (okm and sid) or nil
                end
                if type(id) == "number" then
                    local command = range.command:format(slot - range.first + 1)
                    local okb, binding = pcall(GetBindingKey, command)
                    if okb and type(binding) == "string" and binding ~= "" then
                        local text = B.Abbreviate(binding)
                        if kind == "spell" and spells[id] == nil then
                            spells[id] = text
                        elseif kind == "item" and items[id] == nil then
                            items[id] = text
                        end
                    end
                end
            end
        end
    end
end

function B.For(entry)
    if type(entry) ~= "table" or type(entry.id) ~= "number" then return nil end
    if entry.kind == "item" then return items[entry.id] end
    return spells[entry.id]
end
