-- VuloForeverUI / Modules / Bags / Sidebar
--
-- The column of buttons down the left edge of a window: one for everything,
-- one per bank tab, one per shelf the current draw produced. A click filters
-- the window to that one thing; a right-click on a BANK TAB opens the tab's
-- own settings -- its name and what the client deposits into it.
--
-- The tab settings are the client's, not ours. C_Bank.UpdateBankTabSettings
-- writes them to the server, so a tab renamed here is renamed in the client's
-- own bank frame and on the next character that opens it. Storing a name of
-- our own would have been half a feature: the deposit filter is server side
-- whatever we do, and two names for one tab is how a player loses track.
--
-- A client without purchased bank tabs answers with an empty list, and then
-- the bar is categories only. Nothing here assumes the tabbed bank exists.
local _, ns = ...
local L = ns.L
local Bags = ns.Bags

local Sidebar = {}
Bags.Sidebar = Sidebar

local BUTTON, GAP = 22, 4
-- The column: the window's own margin on the left, the buttons, then a gap,
-- a hairline, and the same gap again before the first slot.
local INSET, SPLIT = 10, 6
Sidebar.WIDTH = BUTTON + SPLIT * 2

-- One look for every button in the bar: a square item icon, cut the same
-- way, on the same dark ground inside the same thin edge. The fixed shelves
-- have an icon each; a shelf without one -- the player's own categories, a
-- set -- shows its first item, and an empty one the plain bag. The old mix of
-- round bag atlases, a glow and a plus sign is gone.
local Q = "Interface\\Icons\\"
local ICON = {
    all        = Q .. "INV_Misc_Bag_08",
    allbags    = Q .. "INV_Misc_Bag_10",
    perbag     = Q .. "INV_Misc_Bag_07",
    equipment  = Q .. "INV_Chest_Chain",
    consumable = Q .. "INV_Potion_51",
    tradegoods = Q .. "INV_Fabric_Linen_01",
    quest      = Q .. "INV_Misc_Note_01",
    reagent    = Q .. "INV_Misc_Dust_02",
    junk       = Q .. "INV_Misc_Bone_HumanSkull_01",
    misc       = Q .. "INV_Misc_Gear_01",
    free       = Q .. "INV_Box_01",
    pinned     = Q .. "INV_Misc_Book_09",
    recent     = Q .. "INV_Misc_Gift_01",
}
local FALLBACK = Q .. "INV_Misc_Bag_09"
local MISSING = 134400              -- the question mark, should a file be absent

local function iconFor(win, key)
    return ICON[key] or (win.shelfIcons and win.shelfIcons[key]) or FALLBACK
end

local function setIcon(tex, icon)
    if not tex:SetTexture(icon) then tex:SetTexture(MISSING) end
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
end

-- ---------------------------------------------------------------- deposit --

-- The deposit filter is a BITFIELD on the tab, and these are the bits the
-- client's own bank menu offers. The labels are the client's global strings:
-- the same words the player sees in the client's bag filter menu, in their
-- language, with nothing of ours to translate.
local FLAGS = {
    { flag = 0x2,  text = "BAG_FILTER_EQUIPMENT" },
    { flag = 0x4,  text = "BAG_FILTER_CONSUMABLES" },
    { flag = 0x8,  text = "BAG_FILTER_PROFESSION_GOODS" },
    { flag = 0x80, text = "BAG_FILTER_REAGENTS" },
    { flag = 0x20, text = "BAG_FILTER_QUEST_ITEMS" },
    { flag = 0x10, text = "BAG_FILTER_JUNK" },
}

local function bankType()
    return (Enum.BankType and Enum.BankType.Character) or 0
end

-- Every purchased tab of the character's bank, or nothing at all on a client
-- whose bank has no tabs. Called on every draw: the list changes when a tab is
-- bought, renamed or refiltered, and all three come with an event we redraw on.
function Sidebar.Tabs()
    local fetch = C_Bank and C_Bank.FetchPurchasedBankTabData
    if type(fetch) ~= "function" then return {} end
    local ok, list = pcall(fetch, bankType())
    if not (ok and type(list) == "table") then return {} end
    return list
end

-- The parameter is `mask`, not `bit`: naming it `bit` shadows the client's bit
-- library inside this function, and the next line needs it.
local function hasFlag(flags, mask)
    if type(flags) ~= "number" then return false end
    if type(bit) ~= "table" or type(bit.band) ~= "function" then
        -- No bit library: fall back to arithmetic on a plain settings number.
        return math.floor(flags / mask) % 2 == 1
    end
    return bit.band(flags, mask) ~= 0
end

local function writeTab(tab, name, flags)
    local update = C_Bank and C_Bank.UpdateBankTabSettings
    if type(update) ~= "function" then return end
    pcall(update, bankType(), tab.ID, name or tab.name or "",
        tab.icon and tostring(tab.icon) or "", flags or tab.depositFlags or 0)
    Bags.Refresh()
end

-- Renaming goes through the client's own popup shape, because that is the one
-- an addon may use to ask for a line of text without building a window.
local pendingTab

ns.OnLocaleReady(function()
    StaticPopupDialogs["VFUI_BANK_TAB_NAME"] = {
        text = L["Name for this bank tab:"],
        button1 = _G.SAVE or L["Save"], button2 = _G.CANCEL,
        hasEditBox = true, maxLetters = 32,
        OnShow = function(self)
            local box = ns.PopupEditBox(self)
            if box then
                box:SetText((pendingTab and pendingTab.name) or "")
                box:HighlightText()
                box:SetFocus()
            end
        end,
        OnAccept = function(self)
            local box = ns.PopupEditBox(self)
            if box and pendingTab then writeTab(pendingTab, box:GetText(), nil) end
        end,
        EditBoxOnEnterPressed = function(self)
            if pendingTab then writeTab(pendingTab, self:GetText(), nil) end
            self:GetParent():Hide()
        end,
        EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
end)

local function tabMenu(tab)
    local entries = {
        { text = tab.name or L["Bank"], title = true },
        { text = L["Rename"], func = function()
            pendingTab = tab
            StaticPopup_Show("VFUI_BANK_TAB_NAME")
        end },
        { separator = true },
        { text = L["Deposit filters"], title = true },
    }
    for _, spec in ipairs(FLAGS) do
        local label = _G[spec.text]
        entries[#entries + 1] = {
            text = (type(label) == "string" and label) or spec.text,
            keepOpen = true,
            checked = function()
                local list = Sidebar.Tabs()
                for _, t in ipairs(list) do
                    if t.ID == tab.ID then return hasFlag(t.depositFlags, spec.flag) end
                end
                return false
            end,
            func = function()
                local flags = tonumber(tab.depositFlags) or 0
                if hasFlag(flags, spec.flag) then
                    flags = flags - spec.flag
                else
                    flags = flags + spec.flag
                end
                tab.depositFlags = flags
                writeTab(tab, nil, flags)
            end,
        }
    end
    return entries
end

-- ---------------------------------------------------------------- bar --

local function button(win, index)
    win.sideButtons = win.sideButtons or {}
    local b = win.sideButtons[index]
    if b then return b end
    b = CreateFrame("Button", nil, win.frame)
    b:SetSize(BUTTON, BUTTON)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local ground = b:CreateTexture(nil, "BACKGROUND")
    ground:SetAllPoints(b)
    ground:SetColorTexture(0, 0, 0, 0.6)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
    b.icon:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
    b.edges = ns.MakeEdges(b, "OVERLAY")
    -- The chosen one is marked twice: its gold edge, and a short gold bar in
    -- the gap to its left -- readable at a glance down a long column.
    b.mark = b:CreateTexture(nil, "OVERLAY")
    b.mark:SetColorTexture(0.9, 0.75, 0.3, 1)
    b.mark:SetPoint("RIGHT", b, "LEFT", -2, 0)
    b.mark:SetSize(2, BUTTON - 6)
    b.mark:Hide()
    -- Calm at rest, colour on the way in: an unchosen icon is greyed down,
    -- and lights up in full while the mouse is on it.
    local function look(self, lit)
        self.icon:SetDesaturated(not lit)
        self.icon:SetAlpha(lit and 1 or 0.7)
    end
    b.look = look
    b:SetScript("OnEnter", function(self)
        look(self, true)
        ns.UI:ShowTooltip(self, self.vfTip)
    end)
    b:SetScript("OnLeave", function(self)
        look(self, self.vfActive)
        ns.UI:HideTooltip()
    end)
    b:SetScript("OnClick", function(self, mouse)
        if mouse == "RightButton" then
            if self.vfTab then ns:ShowPopupMenu(tabMenu(self.vfTab), "cursor", self) end
            return
        end
        win.view = self.vfView
        win.Refresh()
    end)
    win.sideButtons[index] = b
    return b
end

-- The fold arrow on top of the bar, always there: it IS the switch for the
-- bar (bagSidebar / bankSidebar, the same setting the options carry). Folded,
-- the bar is this arrow alone and the slots take the room back; the shelves
-- still stand as headings in the window, only their buttons go.
local ARROW = 16
local ARROW_LEFT  = "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up"
local ARROW_RIGHT = "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up"
Sidebar.COLLAPSED_WIDTH = ARROW + SPLIT * 2

local function settingKey(win)
    return win.key == "bank" and "bankSidebar" or "bagSidebar"
end

local function arrow(win)
    if win.sideArrow then return win.sideArrow end
    local a = CreateFrame("Button", nil, win.frame)
    a:SetSize(ARROW, ARROW)
    a.tex = a:CreateTexture(nil, "ARTWORK")
    a.tex:SetAllPoints(a)
    a:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    a:SetScript("OnClick", function()
        local db, k = Bags.db(), settingKey(win)
        db[k] = not db[k]
        win.Refresh()
    end)
    a:SetScript("OnEnter", function(self)
        ns.UI:ShowTooltip(self, Bags.db()[settingKey(win)] and L["Hide categories"] or L["Show categories"])
    end)
    a:SetScript("OnLeave", function() ns.UI:HideTooltip() end)
    win.sideArrow = a
    return a
end

-- One row of the bar. `keys` is what the draw actually produced, so a shelf
-- with nothing on it has no button -- the bar is a map of THIS bag, not of
-- every shelf that could exist.
function Sidebar.Layout(win, keys)
    local db = Bags.db()
    local on = db[settingKey(win)] and true or false

    -- level with the first row of slots, wherever the window's look puts it
    local top = -Bags.WindowFactory.ContentTop(db)
    local a = arrow(win)
    a.tex:SetTexture(on and ARROW_LEFT or ARROW_RIGHT)
    a:ClearAllPoints()
    a:SetPoint("TOPLEFT", win.frame, "TOPLEFT", on and (INSET + (BUTTON - ARROW) / 2) or INSET, top)
    a:Show()

    -- the hairline between the column and the slots, down to the margin
    if not win.sideLine then
        win.sideLine = win.frame:CreateTexture(nil, "ARTWORK")
        win.sideLine:SetColorTexture(1, 1, 1, 0.10)
    end
    local lineX = INSET + (on and BUTTON or ARROW) + SPLIT
    win.sideLine:ClearAllPoints()
    win.sideLine:SetPoint("TOPLEFT", win.frame, "TOPLEFT", lineX, top)
    win.sideLine:SetPoint("BOTTOMLEFT", win.frame, "BOTTOMLEFT", lineX, INSET)
    win.sideLine:SetWidth(1)
    win.sideLine:Show()

    if not on then
        for _, b in ipairs(win.sideButtons or {}) do b:Hide() end
        return Sidebar.COLLAPSED_WIDTH, math.abs(top) + ARROW + 4
    end

    local rows = { { view = "all", key = "all", label = L["All items"] } }
    -- The physical views, bags window only: the bank has its own tabs.
    if win.key == "bags" then
        rows[#rows + 1] = { view = "allbags", key = "allbags", label = L["All bags"] }
        rows[#rows + 1] = { view = "perbag", key = "perbag", label = L["Per bag"] }
    end

    if win.key == "bank" and not db.bankHideTabsInSidebar then
        for _, tab in ipairs(Sidebar.Tabs()) do
            rows[#rows + 1] = {
                view  = "bag:" .. tab.ID,
                key   = "tab",
                label = tab.name,
                icon  = tab.icon,
                tab   = tab,
            }
        end
    end

    for _, key in ipairs(keys) do
        if key ~= "all" then
            rows[#rows + 1] = { view = key, key = key, label = Bags.Categories.Label(key) }
        end
    end

    local y = top - ARROW - GAP
    for i, row in ipairs(rows) do
        local b = button(win, i)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", win.frame, "TOPLEFT", INSET, y)
        setIcon(b.icon, row.icon or iconFor(win, row.view))
        b.vfView = row.view
        b.vfTab  = row.tab
        b.vfTip  = row.tab
            and { title = row.label, lines = { L["Right-click for name and deposit filters."] } }
            or row.label
        local active = (win.view or "all") == row.view
        -- every button carries its edge: a dark hairline at rest, gold when
        -- chosen
        if active then
            ns.LayoutEdges(b.edges, b, 1, 0.9, 0.75, 0.3, 1, 0)
        else
            ns.LayoutEdges(b.edges, b, 1, 0.22, 0.22, 0.24, 1, 0)
        end
        b.vfActive = active
        b.mark:SetShown(active)
        b.look(b, active or b:IsMouseOver())
        b:Show()
        y = y - BUTTON - GAP
    end
    for i = #rows + 1, #(win.sideButtons or {}) do win.sideButtons[i]:Hide() end

    -- What the layout has to leave free on the left, and how far down the bar
    -- reaches: a bar longer than the slots decides the window's height.
    return Sidebar.WIDTH, math.abs(y) + 4
end
