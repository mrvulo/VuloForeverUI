-- VuloForeverUI / Modules / Bags / Special
--
-- Profession bags as blocks of their own in the bag window.
--
-- A bag that takes only one kind of thing -- the reagent bag in its own slot,
-- an herb, enchanting or mining bag, a quiver, a soul bag -- is not part of
-- the room a player plans with. Mixed into the shelves its contents hide
-- among everything else, and its free slots look like room for a sword.
-- Here each such bag leaves the shelves and the "all bags" block and stands
-- underneath as a block of its own: its slots in bag order, full and free
-- side by side, under the bag's name. One button in the tool row folds all
-- of them away; a search unfolds them for as long as it lasts, so a hit can
-- never sit in a block nobody sees.
--
-- Colours and frames are the window's own: the slots keep the family tint
-- and the quality ring they have everywhere else (Slots.lua).
--
-- The "per bag" view already shows every bag as its own block, and a bank
-- tab view is one container by definition: neither is touched.
local _, ns = ...

local Bags = ns.Bags
local Special = {}
Bags.Special = Special

-- The reagent bag's slot always, any other bag by the family it reports --
-- the test the header's second free-slot number uses (Bags.CountSlots).
local function isSpecial(bag)
    if type(bag) ~= "number" or bag <= 0 then return false end
    if Enum.BagIndex and bag == Enum.BagIndex.ReagentBag then return true end
    local _, family = C_Container.GetContainerNumFreeSlots(bag)
    if type(family) == "number" and family > 0 then return true end
    -- A bag the slots tint as a profession bag (the family of the bag item
    -- itself, where the container reports none) is one here too.
    return Bags.Slots.FamilyColor(bag) ~= nil
end

function Special.Enabled()
    local db = Bags.db()
    return db ~= nil and db.specialSection ~= false
end

function Special.IsOpen()
    return Bags.db().specialOpen ~= false
end

-- The special bags of this window, in bag order. Only the bags have them.
local function list(win)
    if not (win and win.key == "bags" and Special.Enabled()) then return nil end
    local out
    for _, bag in ipairs(win.bags()) do
        if isSpecial(bag) then
            out = out or {}
            out[#out + 1] = bag
        end
    end
    return out
end

function Special.Has(win)
    return list(win) ~= nil
end

-- Does this view pull the special bags out at all?
function Special.Applies(win, view)
    if view == "perbag" or tostring(view):match("^bag:") then return false end
    return Special.Has(win)
end

-- The face of the tool button: the first special bag's own icon.
function Special.Icon(win)
    local bags = list(win)
    if not bags then return nil end
    local ok, inv = pcall(C_Container.ContainerIDToInventoryID, bags[1])
    if not ok or type(inv) ~= "number" then return nil end
    return GetInventoryItemTexture("player", inv)
end

-- Takes the special bags' slots out of the two lists the window collected.
-- Returns what is left of them and the blocks, one per special bag:
-- { key = "special:<bag>", bag = <id>, list = <entries in slot order> }.
function Special.Split(win, items, empty)
    local bags = list(win)
    if not bags then return items, empty, nil end
    local blocks, byBag = {}, {}
    for _, bag in ipairs(bags) do
        local block = { key = "special:" .. bag, bag = bag, list = {} }
        blocks[#blocks + 1] = block
        byBag[bag] = block.list
    end
    local function sift(source)
        local kept = {}
        for _, entry in ipairs(source) do
            local into = byBag[entry.bag]
            if into then into[#into + 1] = entry else kept[#kept + 1] = entry end
        end
        return kept
    end
    items, empty = sift(items), sift(empty)
    for _, block in ipairs(blocks) do
        table.sort(block.list, function(a, b) return a.slot < b.slot end)
    end
    return items, empty, blocks
end

-- The button in the tool row.
function Special.Toggle()
    local db = Bags.db()
    db.specialOpen = not Special.IsOpen()
    Bags.Refresh()
end
