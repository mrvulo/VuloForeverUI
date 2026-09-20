-- VuloForeverUI / Modules / Bags / Window
--
-- The window itself, and the layout that fills it: a header with the money and
-- the free slots, a search box, and below that one section per category.
--
-- One factory builds both windows. The bags and the bank differ in exactly two
-- things -- which containers they show and what they are called -- so they are
-- two calls to the same function rather than two files that drift apart.
local _, ns = ...
local L = ns.L
local Bags = ns.Bags

local Window = {}
Bags.WindowFactory = Window

local PAD, HEADER_H, SECTION_H = 10, 28, 18

-- ---------------------------------------------------------------- chrome --

local function build(win)
    local f = CreateFrame("Frame", "VuloForeverUIBags" .. win.key, UIParent)
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:Hide()
    win.frame = f

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(f)
    bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    f.bg = bg
    f.edges = ns.MakeEdges(f, "BORDER")

    local title = f:CreateFontString(nil, "OVERLAY")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -PAD)
    f.title = title

    local info = f:CreateFontString(nil, "OVERLAY")
    info:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD - 24, -PAD)
    info:SetJustifyH("RIGHT")
    f.info = info

    -- The house close button rather than a font string with a multiplication
    -- sign in it: that glyph only exists if the chosen font happens to carry
    -- it, and this is the shape every other window here already uses.
    f.close = ns.UI:CreateCloseX(f, function() win.Close() end)

    -- Escape closes it, like every window the client owns.
    if type(_G.UISpecialFrames) == "table" then
        local name = f:GetName()
        if name then table.insert(_G.UISpecialFrames, name) end
    end

    local search = CreateFrame("EditBox", nil, f)
    search:SetAutoFocus(false)
    search:SetHeight(18)
    search:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -PAD - HEADER_H + 4)
    search:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, -PAD - HEADER_H + 4)
    local sbg = search:CreateTexture(nil, "BACKGROUND")
    sbg:SetAllPoints(search)
    sbg:SetColorTexture(0, 0, 0, 0.4)
    search:SetTextInsets(6, 6, 0, 0)
    search:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
    search:SetScript("OnTextChanged", function(self)
        win.filter = self:GetText()
        win.Refresh()
    end)
    f.search = search

    -- Dragged by its own body, and the place it lands is remembered. Nothing
    -- secure is involved: this is our frame from edge to edge.
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, dx, dy = self:GetPoint()
        local store = Bags.db()[win.key .. "Pos"] or {}
        store.point, store.relPoint, store.x, store.y = point, relPoint, dx, dy
        Bags.db()[win.key .. "Pos"] = store
    end)

    win.sections = {}
    return f
end

local function placeWindow(win)
    local store = Bags.db()[win.key .. "Pos"]
    win.frame:ClearAllPoints()
    if store and store.point then
        win.frame:SetPoint(store.point, UIParent, store.relPoint or store.point, store.x or 0, store.y or 0)
    elseif win.key == "bank" then
        win.frame:SetPoint("CENTER", UIParent, "CENTER", -260, 0)
    else
        win.frame:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -40, 120)
    end
end

-- A section heading, pooled per window.
local function section(win, index)
    local s = win.sections[index]
    if s then return s end
    s = win.frame:CreateFontString(nil, "OVERLAY")
    win.sections[index] = s
    return s
end

-- ---------------------------------------------------------------- content --

-- Everything in these bags, as plain entries. Empty slots are kept: a bag
-- window that hides its free space is a window nobody can drop anything into.
local function collect(bagIDs)
    local items, empty = {}, {}
    for _, bag in ipairs(bagIDs) do
        local slots = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, slots do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            local entry = { bag = bag, slot = slot, info = info }
            if info then items[#items + 1] = entry else empty[#empty + 1] = entry end
        end
    end
    return items, empty
end

-- Does this entry survive the search box? The item's name is the only thing
-- asked about, and only when there is something to ask.
local function matches(entry, filter)
    if not filter or filter == "" then return true end
    local link = entry.info and entry.info.hyperlink
    if type(link) ~= "string" then return false end
    local name = C_Item.GetItemNameByID and C_Item.GetItemNameByID(link)
    if type(name) ~= "string" then name = link end
    return name:lower():find(filter:lower(), 1, true) ~= nil
end

function Window.Layout(win)
    local db = Bags.db()
    local f = win.frame
    if not f then return end

    local bagIDs = win.bags()
    local items, empty = collect(bagIDs)

    -- Sort into shelves. Without categories everything lands on one.
    local buckets, order = {}, {}
    if db.categories then
        for _, entry in ipairs(items) do
            local key = Bags.Categories.For(entry.info) or "misc"
            buckets[key] = buckets[key] or {}
            table.insert(buckets[key], entry)
        end
        for _, key in ipairs(Bags.Categories.ORDER) do
            local list = buckets[key]
            -- An empty shelf is normally left out. Kept, it is a heading with
            -- nothing under it -- which is what someone wants who is used to
            -- finding a category in the same place every time.
            if (list and #list > 0) or db.hideEmptyCategories == false then
                buckets[key] = list or {}
                order[#order + 1] = key
            end
        end
    else
        buckets.all = items
        order[1] = "all"
    end
    if #empty > 0 then
        buckets.free = empty
        order[#order + 1] = "free"
    end

    local size    = db.slotSize or 37
    local gap     = db.spacing or 4
    local columns = math.max(1, db.columns or 12)
    local width   = columns * size + (columns - 1) * gap + PAD * 2

    Bags.Slots.Begin(win.key)
    win.placed = win.placed or {}
    wipe(win.placed)
    local y = PAD + HEADER_H + (db.search and 22 or 0)
    local sectionIndex = 0
    local missing, refused = false, false

    for _, key in ipairs(order) do
        local list = buckets[key]
        sectionIndex = sectionIndex + 1
        local head = section(win, sectionIndex)
        ns.UI.FontFor("bags", head, 11, nil)
        head:SetTextColor(0.65, 0.65, 0.7)
        head:ClearAllPoints()
        head:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -y)
        if key == "free" then
            head:SetFormattedText("%s (%d)", L["Free"], #list)
        elseif key == "all" then
            head:SetText("")
        else
            head:SetText(Bags.Categories.Label(key))
        end
        head:Show()
        y = y + ((key == "all") and 0 or SECTION_H)

        local column = 0
        for _, entry in ipairs(list) do
            local slot, why = Bags.Slots.Next(win.key)
            if not slot then
                if why == "refused" then refused = true end
                -- The pool is empty and a fight is on, so no more secure
                -- buttons may be made. What is drawn stays drawn; the rest
                -- appears when the fight is over.
                missing = true
                break
            end
            slot.frame:SetParent(f)
            slot.frame:ClearAllPoints()
            slot.frame:SetPoint("TOPLEFT", f, "TOPLEFT",
                PAD + column * (size + gap), -y)
            Bags.Slots.Paint(slot, entry.bag, entry.slot, entry.info)
            Bags.Slots.SetFiltered(slot, not matches(entry, win.filter))
            win.placed[#win.placed + 1] = { slot = slot, bag = entry.bag, slotID = entry.slot }

            column = column + 1
            if column >= columns then
                column = 0
                y = y + size + gap
            end
        end
        if column > 0 then y = y + size + gap end
        y = y + 4
        if missing then break end
    end

    for i = sectionIndex + 1, #win.sections do win.sections[i]:Hide() end
    Bags.Slots.HideRest(win.key)

    f:SetSize(width, y + PAD)
    f:SetScale(db.scale or 1)
    f.bg:SetColorTexture(db.bgColor.r, db.bgColor.g, db.bgColor.b, db.bgColor.a or 0.92)
    ns.LayoutEdges(f.edges, f, db.borderSize or 1,
        db.borderColor.r, db.borderColor.g, db.borderColor.b, db.borderColor.a or 0.12, 0)

    ns.UI.FontFor("bags", f.title, 13, nil)
    f.title:SetText(Bags.Title(win.key))
    ns.UI.FontFor("bags", f.info, 11, nil)
    ns.UI.FontFor("bags", f.search, 11, nil)
    f.search:SetShown(db.search ~= false)

    local free, total = Bags.CountSlots(bagIDs)
    local parts = {}
    if db.showFreeSlots then parts[#parts + 1] = ("%d/%d"):format(free, total) end
    if db.showMoney and win.key == "bags" and GetMoneyString then
        local ok, money = pcall(GetMoneyString, GetMoney(), true)
        if ok and type(money) == "string" then parts[#parts + 1] = money end
    end
    f.info:SetText(table.concat(parts, "   "))

    if missing and not win.warned then
        win.warned = true
        if refused then
            ns:Print(L["The client refused to create more item buttons; the window shows what it has."])
        else
            ns:Print(L["Some slots are waiting for the fight to end: an item button made in combat cannot be used."])
        end
    end
end

-- The cheap pass: the same slots, in the same places, painted again. This is
-- what an item CHANGING gets -- a cooldown starting, something picked up --
-- because a full layout per potion in a raid rebuilds a hundred and fifty
-- buttons to redraw one swirl.
function Window.Repaint(win)
    if not (win.frame and win.frame:IsShown() and win.placed) then return end
    for _, placed in ipairs(win.placed) do
        local info = C_Container.GetContainerItemInfo(placed.bag, placed.slotID)
        Bags.Slots.Paint(placed.slot, placed.bag, placed.slotID, info)
    end
end

-- ---------------------------------------------------------------- factory --

function Window.New(key, bagsFn)
    local win = { key = key, bags = bagsFn }

    function win.Open()
        if not win.frame then build(win) end
        placeWindow(win)
        Window.Layout(win)
        win.frame:Show()
    end

    function win.Close()
        if not win.frame then return end
        win.frame:Hide()
        -- The search goes with the window: coming back to bags still filtered
        -- by something typed ten minutes ago reads as a broken bag.
        win.filter = nil
        if win.frame.search then win.frame.search:SetText("") end
    end

    function win.Toggle()
        if win.frame and win.frame:IsShown() then win.Close() else win.Open() end
    end

    function win.Refresh()
        if win.frame and win.frame:IsShown() then Window.Layout(win) end
    end

    function win.Repaint()
        Window.Repaint(win)
    end

    function win.IsShown()
        return win.frame and win.frame:IsShown()
    end

    return win
end

Bags.Window = Window.New("bags", function() return Bags.CarriedBags() end)
