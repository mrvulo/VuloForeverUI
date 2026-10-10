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
local TOOL = 20          -- edge length of a tool button

-- THE TWO LOOKS
--
-- Modern is the flat window this file always drew. Standard is the client's
-- own bag look: the frame Forever's bags are made of (PortraitFrameFlatTemplate
-- -- border, title bar, bag portrait, close button) under the same content.
-- That frame is a child of the window drawn one level BELOW it, so the
-- window's own texts and slots stay on top of its ground; only the header
-- moves, down out of the title bar and right of the portrait.
local function isStandard()
    return Bags.db().style == "standard"
end
Window.IsStandard = isStandard

-- Where the header rows start, and how far in from the left they begin.
local function headTop() return isStandard() and 30 or PAD end
local function headLeft() return isStandard() and 62 or PAD end
-- How much further down everything below the header starts than in Modern
-- (the side bar reads this too).
function Window.TopExtra() return headTop() - PAD end
Window.PAD = PAD

-- Where the first row of slots starts, below the header and the tool row.
function Window.ContentTop(db)
    return headTop() + HEADER_H + (Window.HasToolRow(db) and 22 or 0)
end

-- ---------------------------------------------------------------- chrome --

-- One tool button: an icon, a tooltip, and a click. They live in a row under
-- the title and each one is shown only while its setting is on, so a player
-- who wants none of them gets a header with nothing in it.
--
-- Dressed the way the client dresses its own icons, so the row reads as part
-- of the game rather than of us: the art on a dark ground, the action bar's
-- icon frame over it, and that frame's own hover and pressed states. The art
-- is an atlas name, or an Interface\Icons path; `style`:
--   "icon"   -- a full square icon, masked to the frame's shape
--   "glyph"  -- a symbol with a transparent edge, drawn over the dark ground
local function toolButton(f, art, style, tooltip, onClick)
    local b = CreateFrame("Button", nil, f)
    b:SetSize(TOOL, TOOL)

    local ground = b:CreateTexture(nil, "BACKGROUND")
    ground:SetAllPoints(b)
    ground:SetColorTexture(0, 0, 0, 0.75)

    local icon = b:CreateTexture(nil, "ARTWORK")
    if art:find("\\", 1, true) then
        icon:SetTexture(art)
        -- the icon files carry a baked-in border of their own
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    else
        icon:SetAtlas(art)
    end
    icon:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
    b.icon = icon
    if style == "icon" then
        local mask = b:CreateMaskTexture()
        mask:SetAtlas("UI-HUD-ActionBar-IconFrame-Mask")
        mask:SetAllPoints(icon)
        icon:AddMaskTexture(mask)
    end

    -- The frame sits a little outside the button, as it does on the action
    -- bar, so the icon inside keeps its full size.
    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetAtlas("UI-HUD-ActionBar-IconFrame")
    border:SetPoint("TOPLEFT", b, "TOPLEFT", -2, 2)
    border:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 2, -2)
    b.border = border
    b:SetHighlightAtlas("UI-HUD-ActionBar-IconFrame-Mouseover", "ADD")
    b:SetPushedAtlas("UI-HUD-ActionBar-IconFrame-Down")
    for _, t in ipairs({ b:GetHighlightTexture(), b:GetPushedTexture() }) do
        t:ClearAllPoints()
        t:SetAllPoints(border)
    end
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
    -- Room underneath, and room above: the Standard frame's ground is a child
    -- at level 0 and has to stay below the window's own texts, while the
    -- client's item buttons sit at level 10 (their template says so). A window
    -- at 10 itself drew its ground over the icons as a grey veil.
    f:SetFrameLevel(3)
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
    f.close = ns.UI:CreateCloseX(f, function() win.Close() end, "box")

    -- The Standard look's frame (see THE TWO LOOKS). Its close button is the
    -- client's; its click is ours, set on this instance of the template.
    local ok, chrome = pcall(CreateFrame, "Frame", nil, f, "PortraitFrameFlatTemplate")
    if ok and chrome then
        chrome:SetAllPoints(f)
        chrome:EnableMouse(false)
        if chrome.CloseButton then
            chrome.CloseButton:SetScript("OnClick", function() win.Close() end)
        end
        chrome:Hide()
        f.chrome = chrome
    end

    -- Escape closes it, like every window the client owns.
    if type(_G.UISpecialFrames) == "table" then
        local name = f:GetName()
        if name then table.insert(_G.UISpecialFrames, name) end
    end

    -- The tool row. Sorting is ours, for the bags and the bank alike
    -- (Sort.lua); the other two switch a MODE on, because a click on a slot
    -- belongs to the client (Slots.lua).
    f.sort = toolButton(f, "bags-button-autosort-up", "icon", L["Sort"], function()
        Bags.Sort.Run(win.key == "bank" and "bank" or "bags")
    end)
    f.pin = toolButton(f, "PetJournal-FavoritesIcon", "glyph", L["Pin items"], function()
        Bags.Slots.SetMode("pin")
    end)
    f.split = toolButton(f, "bags-greenarrow", "glyph", L["Split a stack"], function()
        Bags.Slots.SetMode("split")
    end)
    -- The bags themselves, one button each, in a row of their own (BagBar.lua).
    -- The bank gets the same row, one button per bank tab.
    f.bagBar = toolButton(f, "bag-main", "icon",
        win.key == "bank" and L["Show the bank tabs"] or L["Show the bags"], function()
        win.showBagBar = not win.showBagBar
        if win.key == "bank" then
            Bags.db().bankShowBagBar = win.showBagBar
        else
            Bags.db().showBagBar = win.showBagBar
        end
        win.Refresh()
    end)
    -- The bank as it was at the last visit, from anywhere (BankView.lua).
    f.bankView = toolButton(f, "Interface\\Icons\\INV_Misc_Coin_02", "icon", L["Show the bank"], function() Bags.BankView.Toggle() end)
    -- The bag settings, one click away from the bags themselves. Always shown:
    -- it is the way back to every switch that hides the other tools. A second
    -- click closes them again -- but only when it is the bags' page that is
    -- up; the settings open on anything else are switched over instead.
    f.options = toolButton(f, "Interface\\Icons\\Trade_Engineering", "icon",
        L["Bag settings"], function()
            local open = ns.UI.mainFrame
            if open and open:IsShown() and ns.UI.currentModule == "bags" then
                open:Hide()
                return
            end
            local main = ns.UI:CreateMainFrame()
            main:Show()
            ns.UI:PopulateSidebar()
            ns.UI:ShowModulePage("bags")
        end)

    -- Made to be FOUND: a magnifier, a grey "Search" while it is empty, a
    -- visible edge that turns gold while you type, and a ground a step
    -- lighter than the window. The same in both looks.
    local search = CreateFrame("EditBox", nil, f)
    search:SetAutoFocus(false)
    search:SetHeight(20)
    search:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -PAD - HEADER_H + 4)
    search:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, -PAD - HEADER_H + 4)
    local sbg = search:CreateTexture(nil, "BACKGROUND")
    sbg:SetAllPoints(search)
    sbg:SetColorTexture(1, 1, 1, 0.08)
    local edges = ns.MakeEdges(search, "BORDER")
    local function edge(focused)
        if focused then
            ns.LayoutEdges(edges, search, 1, 1, 0.82, 0.3, 0.9, 0)
        else
            ns.LayoutEdges(edges, search, 1, 0.6, 0.6, 0.65, 0.55, 0)
        end
    end
    edge(false)

    local glass = search:CreateTexture(nil, "ARTWORK")
    glass:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
    glass:SetSize(14, 14)
    glass:SetPoint("LEFT", search, "LEFT", 5, -1)
    glass:SetVertexColor(0.75, 0.75, 0.8)
    search:SetTextInsets(22, 6, 0, 0)

    local hint = search:CreateFontString(nil, "ARTWORK")
    hint:SetPoint("LEFT", search, "LEFT", 22, 0)
    hint:SetTextColor(0.55, 0.55, 0.6)
    search.hint = hint
    local function showHint(self)
        hint:SetShown(not self:HasFocus() and (self:GetText() or "") == "")
    end

    search:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
    search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    search:SetScript("OnEditFocusGained", function(self)
        edge(true); glass:SetVertexColor(1, 0.82, 0.3); showHint(self)
    end)
    search:SetScript("OnEditFocusLost", function(self)
        edge(false); glass:SetVertexColor(0.75, 0.75, 0.8); showHint(self)
    end)
    search:SetScript("OnTextChanged", function(self)
        showHint(self)
        win.filter = self:GetText()
        win.Refresh()
    end)
    search:SetScript("OnEnter", function(self) Bags.Search.ShowHelp(self) end)
    search:SetScript("OnLeave", function() GameTooltip:Hide() end)
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
        -- the edit-mode box reads the same place (Window.AttachMover)
        if win.moverEntry then win.moverEntry.sync() end
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
    if win.moverEntry then win.moverEntry.sync() end
end

-- ------------------------------------------------------------------ mover --
--
-- A box in our own edit mode for each of the windows. The saved place stays
-- what it always was -- a point of the window pinned to the same point of
-- UIParent ({ point, relPoint, x, y }) -- so a position saved by a shift-drag
-- before this existed is read unchanged and nothing jumps. The mover's own
-- table (x/y as a CENTRE offset, which is what the edit mode works in) is only
-- a view of that place, kept in step every time the window is placed.
--
-- A drop keeps the point the window already had: a bag window pinned by its
-- bottom-right corner goes on growing up and to the left from wherever it was
-- put, and does not start growing from its middle.

-- Offsets that pin `f` by `point` to the same point of UIParent, without
-- moving it. In f's own units, the units SetPoint takes.
function Window.AnchorOffsets(f, point)
    local l, b, w, h = f:GetLeft(), f:GetBottom(), f:GetWidth(), f:GetHeight()
    local ul, ub, uw, uh = UIParent:GetLeft(), UIParent:GetBottom(), UIParent:GetWidth(), UIParent:GetHeight()
    if not (l and b and w and h and ul and ub and uw and uh) then return nil end
    local r = ns:GetScaleRatio(f)
    ul, ub, uw, uh = ul / r, ub / r, uw / r, uh / r
    local function at(pl, pb, pw, ph)
        local x = point:find("LEFT", 1, true) and pl or (point:find("RIGHT", 1, true) and pl + pw) or (pl + pw / 2)
        local y = point:find("BOTTOM", 1, true) and pb or (point:find("TOP", 1, true) and pb + ph) or (pb + ph / 2)
        return x, y
    end
    local fx, fy = at(l, b, w, h)
    local ux, uy = at(ul, ub, uw, uh)
    return fx - ux, fy - uy
end

-- A window holding item buttons may count as protected; its anchors are then
-- not ours to write while a fight is on.
local function locked(f)
    if not InCombatLockdown() then return false end
    local ok, prot = pcall(f.IsProtected, f)
    return (not ok) or (prot and true or false)
end
Window.Locked = locked

local afterCombat
function Window.AfterCombat(fn)
    if not afterCombat then
        afterCombat = CreateFrame("Frame")
        afterCombat.queue = {}
        afterCombat:SetScript("OnEvent", function(self)
            self:UnregisterEvent("PLAYER_REGEN_ENABLED")
            local q = self.queue
            self.queue = {}
            for _, f in ipairs(q) do pcall(f) end
        end)
    end
    afterCombat.queue[#afterCombat.queue + 1] = fn
    afterCombat:RegisterEvent("PLAYER_REGEN_ENABLED")
end

local attached = {}

-- spec: key, label, storeKey, defaultPoint, place() (from the store, or the
-- default), preview(on).
function Window.AttachMover(f, spec)
    local mdb = {}
    local entry = { spec = spec, frame = f, mdb = mdb }

    function entry.sync()
        local x, y = ns:GetCenterOffsets(f)
        if x then mdb.x, mdb.y = x, y end
    end

    -- The window sits where it should: write that place in the saved model.
    local function commit()
        local all = Bags.db()
        local store = all[spec.storeKey]
        local point = (type(store) == "table" and type(store.point) == "string" and store.point)
            or spec.defaultPoint
        local x, y = Window.AnchorOffsets(f, point)
        if not x then return end
        all[spec.storeKey] = { point = point, relPoint = point, x = x, y = y }
        f:ClearAllPoints()
        f:SetPoint(point, UIParent, point, x, y)
        entry.sync()
    end

    f.mover = ns:CreateMover(f, {
        key    = spec.key,
        label  = spec.label,
        db     = mdb,
        module = "bags",
        width  = 240,
        height = 120,
        -- Nudge, reset, re-apply. A reset hands the window its default place
        -- back; anything else re-places from the store and only commits when
        -- the box was really moved, so a re-apply never rewrites the save.
        applyPos = function()
            if locked(f) then return end
            if ns._inMoverReset then
                Bags.db()[spec.storeKey] = nil
                spec.place()
                entry.sync()
                return
            end
            local wx, wy = mdb.x, mdb.y
            spec.place()
            local x, y = ns:GetCenterOffsets(f)
            if wx and wy and x and (math.abs(x - wx) > 0.5 or math.abs(y - wy) > 0.5) then
                f:ClearAllPoints()
                f:SetPoint("CENTER", UIParent, "CENTER", wx, wy)
                commit()
            else
                entry.sync()
            end
        end,
        -- A drop, a discard, a link: the core has put the window's centre
        -- there already.
        onMove = function() commit() end,
        editPreview = spec.preview,
    })
    -- CreateMover unclamps its target; these windows have always been clamped.
    f:SetClampedToScreen(true)
    entry.sync()
    attached[#attached + 1] = entry
    return entry
end

-- Discard. The core restores every box by its CENTRE, which is only right if
-- the window still has the size it had when the edit mode opened -- and a bag
-- window that was closed then and is open now does not. So the saved places
-- themselves are copied at the snapshot and put back after the core's restore.
local editSaved

hooksecurefunc(ns, "SnapshotEditState", function()
    local all = Bags.db and Bags.db()
    if type(all) ~= "table" then return end
    editSaved = {}
    for _, e in ipairs(attached) do
        local s = all[e.spec.storeKey]
        editSaved[e.spec.storeKey] = type(s) == "table" and CopyTable(s) or false
    end
end)

hooksecurefunc(ns, "RestoreEditState", function()
    local all = Bags.db and Bags.db()
    if not (editSaved and type(all) == "table") then return end
    for _, e in ipairs(attached) do
        local s = editSaved[e.spec.storeKey]
        if s ~= nil then
            all[e.spec.storeKey] = s and CopyTable(s) or nil
            if locked(e.frame) then
                Window.AfterCombat(e.spec.place)
            else
                e.spec.place()
            end
        end
    end
end)

hooksecurefunc(ns, "ClearEditSnapshot", function() editSaved = nil end)

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

-- Does this entry survive the search box? Search.lua decides.
local function matches(entry, filter)
    return Bags.Search.Matches(entry, filter)
end

-- How wide the window should be when it is left to decide for itself: as near
-- to a square as a whole number of columns gets, within the range the slider
-- offers, so a bag that fills up grows sideways instead of down the screen.
local function autoColumns(count)
    local cols = math.ceil(math.sqrt(math.max(count, 1) * 1.6))
    return math.max(6, math.min(20, cols))
end

-- The money, the free slots and whichever currencies the player asked for.
-- The free slots are the ones anything fits into; room in profession bags is
-- told apart, in their colour, because it is no room for loot.
local function headerText(win, bagIDs, db)
    local parts = {}
    if db.showFreeSlots then
        local free, total, specialFree, specialTotal = Bags.CountSlots(bagIDs)
        local text = ("%d/%d"):format(free, total)
        if specialTotal > 0 then
            -- in the colour the special bag's slots carry, so the two match
            local hex = "66cccc"
            for _, id in ipairs(bagIDs) do
                local c = Bags.Slots.FamilyColor(id)
                if c then
                    hex = ("%02x%02x%02x"):format(math.floor(c[1] * 255 + 0.5),
                        math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
                    break
                end
            end
            text = text .. "  |cff" .. hex .. ("%d/%d"):format(specialFree, specialTotal) .. "|r"
        end
        parts[#parts + 1] = text
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

-- The heading of a physical block: the whole bag set, or one bag by the name
-- of the bag that is equipped there.
function Window.BagLabel(key)
    if key == "allbags" then return L["Bags"] end
    local bag = tonumber(key:match("^bagsec:(%-?%d+)$"))
    if bag == 0 then return L["Backpack"] end
    local name = bag and C_Container.GetBagName and C_Container.GetBagName(bag)
    if type(name) == "string" and name ~= "" then return name end
    return (L["Bag %d"]):format(bag or 0)
end

function Window.Layout(win)
    local db = Bags.db()
    local f = win.frame
    if not f then return end

    local rules = Bags.Categories.Rules(win.key)
    local grouped = Bags.Categories.Grouped(rules)
    local bagIDs = win.bags()
    local items, empty = collect(bagIDs)
    -- The physical views need every stack in its own slot, so they take the
    -- list before any merging.
    local rawItems = items
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
    -- The first item of each shelf, as the face of a shelf that has no fixed
    -- icon of its own (the player's own categories, sets) in the side bar.
    win.shelfIcons = win.shelfIcons or {}
    wipe(win.shelfIcons)
    for key, list in pairs(buckets) do
        local info = list[1] and list[1].info
        local icon = info and (info.iconFileID or info.icon or info.texture)
        if icon then win.shelfIcons[key] = icon end
    end

    if view ~= "all" and not onlyBag then
        local only = {}
        for _, key in ipairs(order) do if key == view then only[#only + 1] = key end end
        order = only
    end

    -- All bags and per bag: the bags as they physically are, item and empty
    -- slot side by side in bag and slot order, no shelves -- one block for all
    -- bags, or one block per bag. The categories above are still worked out,
    -- because the side bar lists them for switching back.
    local physical = (view == "allbags" or view == "perbag") and win.key == "bags"
    if physical then
        local all = {}
        for _, e in ipairs(rawItems) do all[#all + 1] = e end
        for _, e in ipairs(empty) do all[#all + 1] = e end
        table.sort(all, function(a, b)
            if a.bag ~= b.bag then return a.bag < b.bag end
            return a.slot < b.slot
        end)
        buckets, order = {}, {}
        if view == "allbags" then
            buckets.allbags = all
            order[1] = "allbags"
        else
            for _, e in ipairs(all) do
                local key = "bagsec:" .. e.bag
                if not buckets[key] then buckets[key] = {}; order[#order + 1] = key end
                table.insert(buckets[key], e)
            end
        end
    end

    -- The free slots. They are what a player drops things into, so they stay
    -- whatever the view is -- except on a grouped window that asked for them
    -- to go, which is what "hide empty slots when grouped" means.
    if not physical and #empty > 0 and not (grouped and rules.hideEmpty) then
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
    -- [bag][slot] -> its placed entry, for repainting one slot
    win.placedAt = win.placedAt or {}
    for _, t in pairs(win.placedAt) do wipe(t) end
    -- The second header row carries the search field and the tool buttons, so
    -- it is reserved while either is on. Asked the same way the field itself
    -- is shown (search ~= false): a nil setting meant a field on screen with no
    -- room made for it, drawn over the tools and eating their clicks.
    local y = headTop() + HEADER_H + (Window.HasToolRow(db) and 22 or 0)
    y = y + Bags.BagBar.Layout(win, left, y)
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
        elseif key == "allbags" then
            -- The free slots are in the header already; one block of all bags
            -- would only say the same thing again, the other way round.
            head:SetText(Window.BagLabel(key))
        elseif key:match("^bagsec:") then
            -- Per bag the same count as the header -- free of total -- so the
            -- two never read as different numbers for the same thing.
            local free = 0
            for _, e in ipairs(list) do if not e.info then free = free + 1 end end
            head:SetFormattedText("%s (%d/%d)", Window.BagLabel(key), free, #list)
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
            -- Moved only when its place really changes. Re-anchoring the slot
            -- under the mouse, even onto the very same spot, made the client
            -- see the mouse leave and enter again: the tooltip blinked out and
            -- back on every layout pass.
            local px, py = left + column * (size + gap), -y
            if slot.placedIn ~= f or slot.px ~= px or slot.py ~= py then
                if slot.frame:GetParent() ~= f then slot.frame:SetParent(f) end
                slot.frame:ClearAllPoints()
                slot.frame:SetPoint("TOPLEFT", f, "TOPLEFT", px, py)
                slot.placedIn, slot.px, slot.py = f, px, py
            end
            slot.mergedCount = entry.merged
            Bags.Slots.Paint(slot, entry.bag, entry.slot, entry.info)
            Bags.Slots.ApplyMode(slot, entry.bag, entry.slot, entry.info)
            local filtered = not matches(entry, win.filter) or Bags.Context.Fades(entry.info)
            Bags.Slots.SetFiltered(slot, filtered)
            local rec = { slot = slot, bag = entry.bag, slotID = entry.slot, filtered = filtered }
            win.placed[#win.placed + 1] = rec
            local at = win.placedAt[entry.bag]
            if not at then at = {}; win.placedAt[entry.bag] = at end
            at[entry.slot] = rec

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

    -- The texts of the header first: the window is never narrower than they
    -- are, so the header cannot run into itself with few columns.
    ns.UI.FontFor("bags", f.info, 11, nil)
    f.info:SetText(headerText(win, bagIDs, db))
    ns.UI.FontFor("bags", f.title, 13, nil)
    f.title:SetText(Bags.Title(win.key))
    width = math.max(width, Window.MinWidth(win, db))

    f:SetSize(width, math.max(y + PAD, (barH or 0) + PAD))
    f:SetScale(db.scale or 1)
    Window.PaintFrame(win)
    ns.UI.FontFor("bags", f.search, 12, nil)
    ns.UI.FontFor("bags", f.search.hint, 12, nil)
    f.search.hint:SetText(L["Search"])
    f.search.hint:SetShown(not f.search:HasFocus() and (f.search:GetText() or "") == "")
    f.search:SetShown(db.search ~= false)

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

-- The window's own ground and border, or the client's frame in their place.
function Window.PaintFrame(win)
    local db, f = Bags.db(), win.frame
    local standard = isStandard() and f.chrome ~= nil
    if f.chrome then
        f.chrome:SetShown(standard)
        if standard then
            local level = f:GetFrameLevel()
            f.chrome:SetFrameLevel(math.max(0, level - 1))
            -- Measured with the frame stack: the template puts its ground at
            -- level 10000 and its border at 498, over the item buttons (10+),
            -- a translucent grey veil over the whole window. Ground to the
            -- bottom, border just over our own ground and under the buttons.
            if f.chrome.Bg then f.chrome.Bg:SetFrameLevel(0) end
            if f.chrome.NineSlice then f.chrome.NineSlice:SetFrameLevel(level + 1) end
            if f.chrome.SetTitle then f.chrome:SetTitle(Bags.Title(win.key)) end
            if f.chrome.SetPortraitToAsset then
                f.chrome:SetPortraitToAsset(win.key == "bank" and 133784 or 133633)
            end
        end
    end
    f.close:SetShown(not standard)
    f.title:SetShown(not standard)
    f.bg:ClearAllPoints()
    if standard then
        -- The template's own ground is translucent (it sits at the bottom,
        -- see above); ours is the dark of the client's flat panels, inside
        -- its border.
        f.bg:SetPoint("TOPLEFT", f, "TOPLEFT", 3, -3)
        f.bg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -3, 3)
        f.bg:SetColorTexture(0.06, 0.06, 0.07, 0.97)
        ns.LayoutEdges(f.edges, f, 0, 0, 0, 0, 0, 0)
    else
        f.bg:SetAllPoints(f)
        f.bg:SetColorTexture(db.bgColor.r, db.bgColor.g, db.bgColor.b, db.bgColor.a or 0.92)
        ns.LayoutEdges(f.edges, f, db.borderSize or 1,
            db.borderColor.r, db.borderColor.g, db.borderColor.b, db.borderColor.a or 0.12, 0)
    end
    ns.UI.FontFor("bags", f.title, 13, nil)
    f.title:SetText(Bags.Title(win.key))
end

-- The tool row: whichever tools are switched on, laid out left to right under
-- the title, with the active mode lit.
function Window.HasToolRow(db)
    -- The settings button is always there, so the row always is.
    return true
end

-- The tool buttons sit at the right end of the search row, and the search
-- field stops short of the first of them. They used to share the field's
-- height at the left, underneath it -- the field was made after them and lay
-- on top, so it took every click meant for a tool: a mode switched on could
-- not be switched off again.
local function toolSpecs(win, db)
    local f = win.frame
    return {
        { button = f.sort,  on = db.showSortButton },
        { button = f.pin,   on = db.showPinned,    mode = "pin" },
        { button = f.split, on = db.stackSplitter, mode = "split" },
        { button = f.bagBar, on = win.key == "bags" or win.key == "bank", lit = win.showBagBar },
        { button = f.bankView, on = win.key == "bags" },
        { button = f.options, on = true },
    }
end

-- The narrowest the window may be: the top row (title, money line) and the
-- second row (search field at a usable width, every tool button) side by
-- side with their gaps, plus the margins.
local SEARCH_MIN = 140
function Window.MinWidth(win, db)
    local f = win.frame
    local tools = 0
    for _, spec in ipairs(toolSpecs(win, db)) do
        if spec.on then tools = tools + 1 end
    end
    local info = f.info:GetStringWidth() or 0
    local top
    if isStandard() then
        top = headLeft() + info + PAD
    else
        top = PAD + (f.title:GetStringWidth() or 0) + 16 + info + 24 + PAD
    end
    local second = headLeft() + SEARCH_MIN + tools * (TOOL + 8) + PAD
    return math.ceil(math.max(top, second))
end

function Window.LayoutTools(win)
    local db = Bags.db()
    local f = win.frame
    local mode = Bags.Slots.Mode()
    local rowY = -headTop() - HEADER_H + 4
    local right = -PAD
    local specs = toolSpecs(win, db)
    for i = #specs, 1, -1 do
        local spec = specs[i]
        local b = spec.button
        if spec.on then
            b:ClearAllPoints()
            b:SetPoint("TOPRIGHT", f, "TOPRIGHT", right, rowY)
            b:SetFrameLevel(f.search:GetFrameLevel() + 2)
            local lit = spec.lit or (spec.mode and mode == spec.mode)
            -- On: the client's frame turns gold.
            if lit then b.border:SetVertexColor(1, 0.82, 0.3) else b.border:SetVertexColor(1, 1, 1) end
            b.icon:SetAlpha(lit and 1 or 0.85)
            b:Show()
            right = right - TOOL - 8
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
    f.search:ClearAllPoints()
    f.search:SetPoint("TOPLEFT", f, "TOPLEFT", headLeft(), rowY)
    f.search:SetPoint("TOPRIGHT", f, "TOPRIGHT", right - 2, rowY)
    f.title:ClearAllPoints()
    f.title:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -PAD)
    -- The money line: next to our close box in Modern, at the right edge
    -- under the client's title bar in Standard.
    f.info:ClearAllPoints()
    if isStandard() then
        f.info:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, -headTop())
    else
        f.info:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD - 24, -PAD)
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

-- One slot only: an item locked or unlocked (picked up, dropped, traded).
-- False when the slot is not drawn on its own (a merged stack, another
-- view) -- the caller then repaints the window.
function Window.RepaintSlot(win, bag, slotID)
    if not (win.frame and win.frame:IsShown() and win.placedAt) then return true end
    local at = win.placedAt[bag]
    if not at then return true end          -- a bag this window does not show
    local rec = at[slotID]
    if not rec then return false end
    Bags.Slots.Paint(rec.slot, bag, slotID, C_Container.GetContainerItemInfo(bag, slotID))
    return true
end

-- Only the swirls: what a cooldown starting changes.
function Window.RepaintCooldowns(win)
    if not (win.frame and win.frame:IsShown() and win.placed) then return end
    for _, placed in ipairs(win.placed) do
        Bags.Slots.PaintCooldown(placed.slot, placed.bag, placed.slotID)
    end
end

-- ---------------------------------------------------------------- factory --

function Window.New(key, bagsFn)
    local win = { key = key, bags = bagsFn }

    local Prof = ns.Prof
    local function setup()
        local t0 = Prof.Begin()
        if not win.frame then build(win) end
        Prof.End("bags open: build", t0)
        -- The view a window opens with is the one the settings name, and that
        -- setting is the BAGS'. The bank opens on everything: "default bag
        -- type" is about the bag somebody works out of, and a bank that opened
        -- filtered to one shelf would hide the rest of a player's belongings
        -- behind a setting made for something else.
        win.view = (win.key == "bags") and (Bags.db().defaultView or "all") or "all"
        if win.key == "bank" then
            win.showBagBar = Bags.db().bankShowBagBar == true
        else
            win.showBagBar = win.key == "bags" and Bags.db().showBagBar == true
        end
        placeWindow(win)
        t0 = Prof.Begin()
        Window.Layout(win)
        Prof.End("bags open: layout", t0)
    end

    function win.Open()
        setup()
        local t0 = Prof.Begin()
        win.frame:Show()
        Prof.End("bags open: show", t0)
        -- a real open: the edit mode's preview no longer owns this window
        win.previewing, win.previewClose = nil, nil
    end

    -- The first open of a session built the window and loaded a hundred icons
    -- in one frame: a hitch of a quarter second (/vfuiprof, 2026-10-10). Done
    -- once, hidden, a few seconds after the loading screen, it costs nothing
    -- the player sees.
    -- The frame itself exists from the start (EnsureMover); what matters is
    -- that it was never laid out.
    function win.Prepare()
        if win.placed or InCombatLockdown() then return end
        setup()
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

    function win.RepaintSlot(bag, slotID)
        return Window.RepaintSlot(win, bag, slotID)
    end

    function win.RepaintCooldowns()
        Window.RepaintCooldowns(win)
    end

    function win.IsShown()
        return win.frame and win.frame:IsShown()
    end

    -- While our edit mode is open the window has to be on screen, or its box
    -- (a child of it) is not. The bags open for real; the bank away from a
    -- banker has nothing to show, so it stands in at the size it last had.
    local function preview(on)
        local f = win.frame
        if not f then return end
        if on then
            win.previewClose = nil
            if f:IsShown() or not (Bags.mod and Bags.mod.active) then return end
            if locked(f) then return end
            if win.key == "bags" then
                win.Open()
            else
                local db = Bags.db()
                -- scale first: the saved offsets are in the window's own units
                f:SetScale(db.scale or 1)
                if (f:GetWidth() or 0) < 50 or (f:GetHeight() or 0) < 50 then
                    local cols = math.max(1, db.columns or 12)
                    local size, gap = db.slotSize or 37, db.spacing or 4
                    f:SetSize(cols * (size + gap) - gap + PAD * 2, 320)
                    Window.PaintFrame(win)
                end
                placeWindow(win)
                f:Show()
            end
            win.previewing = true
        elseif win.previewing then
            win.previewing = nil
            if not f:IsShown() then return end
            -- A fight that ended the edit mode: the window goes after it,
            -- unless it has been opened for real in the meantime.
            if locked(f) then
                win.previewClose = true
                Window.AfterCombat(function()
                    if win.previewClose then
                        win.previewClose = nil
                        win.Close()
                    end
                end)
            else
                win.Close()
            end
        end
    end

    -- Built up front (hidden) so the box exists before the edit mode's
    -- snapshot is taken; called from the module's OnEnable.
    function win.EnsureMover()
        if win.moverEntry then return end
        if not win.frame then build(win) end
        win.frame:SetScale(Bags.db().scale or 1)
        placeWindow(win)
        win.moverEntry = Window.AttachMover(win.frame, {
            key          = "bags_" .. win.key,
            label        = (win.key == "bank") and L["Bank"] or L["Bags"],
            storeKey     = win.key .. "Pos",
            defaultPoint = (win.key == "bank") and "CENTER" or "BOTTOMRIGHT",
            place        = function() placeWindow(win) end,
            preview      = preview,
        })
    end

    return win
end

Bags.Window = Window.New("bags", ns.CarriedBags)
