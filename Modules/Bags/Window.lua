-- VuloForeverUI / Modules / Bags / Window
--
-- The window itself, and the layout that fills it: a header with the money,
-- the free slots and the tool row, a search box, and below that one section
-- per category.
--
-- One factory builds both windows. The bags and the bank differ in exactly two
-- things -- which containers they show and what they are called -- so they are
-- two calls to the same function rather than two files that drift apart.
local _, ns = ...
local L = ns.L
local Bags = ns.Bags

local Window = {}
Bags.WindowFactory = Window

local PAD, HEADER_H = 10, 28
local TOOL = 18          -- edge length of a tool button

-- ---------------------------------------------------------------- chrome --

-- One tool button: an icon, a tooltip, and a click. They live in a row under
-- the title and each one is shown only while its setting is on, so a player
-- who wants none of them gets a header with nothing in it.
local function toolButton(f, atlas, tooltip, onClick)
    local b = CreateFrame("Button", nil, f)
    b:SetSize(TOOL, TOOL)
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(b)
    icon:SetAtlas(atlas)
    b.icon = icon
    b.edges = ns.MakeEdges(b, "OVERLAY")
    b:SetScript("OnEnter", function(self)
        ns.UI:ShowTooltip(self, self.vfTip)
    end)
    b:SetScript("OnLeave", function() ns.UI:HideTooltip() end)
    b:SetScript("OnClick", onClick)
    b.vfTip = tooltip
    return b
end

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

    -- The money line answers for itself. It is a frame over the text rather
    -- than a button in the row: the number IS the thing being asked about.
    local moneyHit = CreateFrame("Frame", nil, f)
    moneyHit:SetAllPoints(info)
    moneyHit:EnableMouse(true)
    moneyHit:SetScript("OnEnter", function(self)
        if not Bags.db().goldTracking then return end
        ns.UI:ShowTooltip(self, { title = L["Gold"], accent = true, lines = Bags.Gold.Lines() })
    end)
    moneyHit:SetScript("OnLeave", function() ns.UI:HideTooltip() end)
    f.moneyHit = moneyHit

    -- The house close button rather than a font string with a multiplication
    -- sign in it: that glyph only exists if the chosen font happens to carry
    -- it, and this is the shape every other window here already uses.
    f.close = ns.UI:CreateCloseX(f, function() win.Close() end)

    -- Escape closes it, like every window the client owns.
    if type(_G.UISpecialFrames) == "table" then
        local name = f:GetName()
        if name then table.insert(_G.UISpecialFrames, name) end
    end

    -- The tool row. Sorting is the client's own call; the other two switch a
    -- MODE on, because a click on a slot belongs to the client (Slots.lua).
    f.sort = toolButton(f, "bags-button-autosort-up", L["Sort"], function()
        local fn = (win.key == "bank") and C_Container.SortBankBags or C_Container.SortBags
        if type(fn) == "function" then pcall(fn) end
    end)
    f.pin = toolButton(f, "PetJournal-FavoritesIcon", L["Pin items"], function()
        Bags.Slots.SetMode("pin")
    end)
    f.split = toolButton(f, "bags-greenarrow", L["Split a stack"], function()
        Bags.Slots.SetMode("split")
    end)

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
    --
    -- Shift is the default, and deliberately so: the body of this window is
    -- mostly item slots, and a bag that walks off across the screen because
    -- somebody missed a slot by two pixels is a bag nobody trusts.
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self)
        if not (Bags.db().moveWithoutShift or IsShiftKeyDown()) then return end
        self:StartMoving()
    end)
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

-- Several stacks of the same item shown as one.
--
-- The stack that is DRAWN is a real stack in a real slot: the click on it
-- still belongs to that one stack, and the number under the icon is the total
-- the player owns. That is the honest version of this feature -- merging
-- cannot move items, and a slot that pretended to hold eighty flasks while
-- clicking it picked up twenty would be worse than no merging at all.
local function merge(items)
    local out, byID = {}, {}
    for _, entry in ipairs(items) do
        local id = entry.info and entry.info.itemID
        local first = id and byID[id]
        if first then
            first.merged = (first.merged or first.info.stackCount or 1)
                + (tonumber(entry.info.stackCount) or 1)
        else
            out[#out + 1] = entry
            if id then byID[id] = entry end
        end
    end
    return out
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

-- How wide the window should be when it is left to decide for itself: as near
-- to a square as a whole number of columns gets, within the range the slider
-- offers, so a bag that fills up grows sideways instead of down the screen.
local function autoColumns(count)
    local cols = math.ceil(math.sqrt(math.max(count, 1) * 1.6))
    return math.max(6, math.min(20, cols))
end

-- The money, the free slots and whichever currencies the player asked for.
local function headerText(win, bagIDs, db)
    local parts = {}
    if db.showFreeSlots then
        local free, total = Bags.CountSlots(bagIDs)
        parts[#parts + 1] = ("%d/%d"):format(free, total)
    end

    local list = db.currencies
    if type(list) == "table" and C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
        for id in pairs(list) do
            local ok, cur = pcall(C_CurrencyInfo.GetCurrencyInfo, tonumber(id))
            if ok and type(cur) == "table" and cur.quantity then
                local icon = cur.iconFileID and ("|T" .. cur.iconFileID .. ":12|t") or ""
                parts[#parts + 1] = icon .. tostring(cur.quantity)
            end
        end
    end

    if db.showMoney and win.key == "bags" then
        parts[#parts + 1] = Bags.Gold.Text(GetMoney())
    end
    return table.concat(parts, "   ")
end

function Window.Layout(win)
    local db = Bags.db()
    local f = win.frame
    if not f then return end

    local rules = Bags.Categories.Rules(win.key)
    local grouped = Bags.Categories.Grouped(rules)
    local bagIDs = win.bags()
    local items, empty = collect(bagIDs)
    if db.mergeDuplicates then items = merge(items) end

    -- The view. A bank tab view ("bag:6") is a filter on the CONTAINER and is
    -- applied before the shelves are built, because it is a different question
    -- from which shelf something belongs on.
    local view = win.view or "all"
    local onlyBag = tostring(view):match("^bag:(%-?%d+)$")
    if onlyBag then
        onlyBag = tonumber(onlyBag)
        local kept, keptEmpty = {}, {}
        for _, entry in ipairs(items) do
            if entry.bag == onlyBag then kept[#kept + 1] = entry end
        end
        for _, entry in ipairs(empty) do
            if entry.bag == onlyBag then keptEmpty[#keptEmpty + 1] = entry end
        end
        items, empty = kept, keptEmpty
    end

    -- Sort into shelves. Without grouping everything lands on one.
    local buckets, order = {}, {}
    local keys = {}
    for _, entry in ipairs(items) do
        local key = Bags.Categories.For(entry, rules) or "misc"
        if not buckets[key] then buckets[key] = {}; keys[#keys + 1] = key end
        table.insert(buckets[key], entry)
    end
    -- A shelf that is empty but switched on is drawn as a heading with
    -- nothing under it, which is what someone wants who is used to finding
    -- a category in the same place every time.
    if grouped and rules.categories and db.hideEmptyCategories == false then
        for _, key in ipairs(Bags.Categories.ORDER) do
            if not buckets[key] and Bags.Categories.Enabled(key) then
                buckets[key] = {}
                keys[#keys + 1] = key
            end
        end
    end
    order = Bags.Categories.Sort(keys)
    win.shelves = order

    if view ~= "all" and not onlyBag then
        local only = {}
        for _, key in ipairs(order) do if key == view then only[#only + 1] = key end end
        order = only
    end

    -- The free slots. They are what a player drops things into, so they stay
    -- whatever the view is -- except on a grouped window that asked for them
    -- to go, which is what "hide empty slots when grouped" means.
    if #empty > 0 and not (grouped and rules.hideEmpty) then
        buckets.free = empty
        order[#order + 1] = "free"
    end

    -- The side bar is laid out from the shelves this draw produced, BEFORE the
    -- slots: it decides how much room the left edge has to give up, and a
    -- window whose bar is longer than its slots takes its height from the bar.
    local barW, barH = Bags.Sidebar.Layout(win, win.shelves or {})
    local left    = PAD + (barW or 0)
    local size    = db.slotSize or 37
    local gap     = db.spacing or 4
    local columns = db.autoSize and autoColumns(#items + #empty) or math.max(1, db.columns or 12)
    local width   = columns * size + (columns - 1) * gap + PAD * 2 + (barW or 0)

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
        ns.UI.FontFor("bags", head, db.categoryTitleSize or 11, nil)
        head:SetTextColor(0.65, 0.65, 0.7)
        head:ClearAllPoints()
        head:SetPoint("TOPLEFT", f, "TOPLEFT", left, -y)
        if key == "free" then
            head:SetFormattedText("%s (%d)", L["Free"], #list)
        elseif key == "all" then
            head:SetText("")
        else
            head:SetFormattedText("%s (%d)", Bags.Categories.Label(key), #list)
        end
        head:Show()
        y = y + ((key == "all") and 0 or ((db.categoryTitleSize or 11) + 7))

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
                left + column * (size + gap), -y)
            slot.mergedCount = entry.merged
            Bags.Slots.Paint(slot, entry.bag, entry.slot, entry.info)
            Bags.Slots.ApplyMode(slot, entry.bag, entry.slot, entry.info)
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

    f:SetSize(width, math.max(y + PAD, (barH or 0) + PAD))
    f:SetScale(db.scale or 1)
    f.bg:SetColorTexture(db.bgColor.r, db.bgColor.g, db.bgColor.b, db.bgColor.a or 0.92)
    ns.LayoutEdges(f.edges, f, db.borderSize or 1,
        db.borderColor.r, db.borderColor.g, db.borderColor.b, db.borderColor.a or 0.12, 0)

    ns.UI.FontFor("bags", f.title, 13, nil)
    f.title:SetText(Bags.Title(win.key))
    ns.UI.FontFor("bags", f.info, 11, nil)
    ns.UI.FontFor("bags", f.search, 11, nil)
    f.search:SetShown(db.search ~= false)

    f.info:SetText(headerText(win, bagIDs, db))
    f.moneyHit:SetShown(db.goldTracking and db.showMoney and win.key == "bags")

    Window.LayoutTools(win)

    if missing and not win.warned and not db.hideBagWarnings then
        win.warned = true
        if refused then
            ns:Print(L["The client refused to create more item buttons; the window shows what it has."])
        else
            ns:Print(L["Some slots are waiting for the fight to end: an item button made in combat cannot be used."])
        end
    end
end

-- The tool row: whichever tools are switched on, laid out left to right under
-- the title, with the active mode lit.
function Window.LayoutTools(win)
    local db = Bags.db()
    local f = win.frame
    local mode = Bags.Slots.Mode()
    local x = PAD
    for _, spec in ipairs({
        { button = f.sort,  on = db.showSortButton },
        { button = f.pin,   on = db.showPinned,    mode = "pin" },
        { button = f.split, on = db.stackSplitter, mode = "split" },
    }) do
        local b = spec.button
        if spec.on then
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", f, "TOPLEFT", x, -PAD - 15)
            local lit = spec.mode and mode == spec.mode
            ns.LayoutEdges(b.edges, b, lit and 1 or 0, 0.9, 0.75, 0.3, 1, 1)
            b.icon:SetAlpha(lit and 1 or 0.7)
            b:Show()
            x = x + TOOL + 4
        else
            b:Hide()
            -- a switched-off tool cannot leave its overlay on every slot:
            -- the button that would end the mode is the one just hidden
            if spec.mode and mode == spec.mode then
                ns.NextFrame(function()
                    if Bags.Slots.Mode() == spec.mode then Bags.Slots.SetMode(spec.mode) end
                end)
            end
        end
    end
    -- The title moves out of the tool row's way rather than sitting on top of
    -- it: the row is under the title, and with three tools on it the title
    -- would otherwise overlap the first one on a narrow window.
    f.title:ClearAllPoints()
    f.title:SetPoint("TOPLEFT", f, "TOPLEFT", (x > PAD) and x or PAD, -PAD)
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
        -- The view a window opens with is the one the settings name, and that
        -- setting is the BAGS'. The bank opens on everything: "default bag
        -- type" is about the bag somebody works out of, and a bank that opened
        -- filtered to one shelf would hide the rest of a player's belongings
        -- behind a setting made for something else.
        win.view = (win.key == "bags") and (Bags.db().defaultView or "all") or "all"
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
