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

local BUTTON, GAP = 26, 3
Sidebar.WIDTH = BUTTON + 8

-- The client's own bag icons, so a shelf is recognisable before its name is
-- read. A shelf with no icon of its own gets the generic one rather than an
-- empty square.
local ICON = {
    all         = "bags-icon-multiple",
    equipment   = "bags-icon-equipment",
    consumable  = "bags-icon-consumables",
    tradegoods  = "bags-icon-tradegoods",
    quest       = "bags-icon-questitem",
    reagent     = "bags-icon-reagents",
    junk        = "bags-icon-junk",
    misc        = "bags-icon-addslots",
    free        = "bags-icon-addslots",
    pinned      = "PetJournal-FavoritesIcon",
    recent      = "bags-glow-green",
}

local function iconFor(key)
    local fixed = ICON[key]
    if fixed then return fixed end
    local kind = tostring(key):match("^(%a+):")
    if kind == "set" or kind == "slot" then return "bags-icon-equipment" end
    return "bags-icon-multiple"
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
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", b, "TOPLEFT", 2, -2)
    b.icon:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 2)
    b.edges = ns.MakeEdges(b, "OVERLAY")
    b:SetScript("OnEnter", function(self)
        ns.UI:ShowTooltip(self, self.vfTip)
    end)
    b:SetScript("OnLeave", function() ns.UI:HideTooltip() end)
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

-- One row of the bar. `keys` is what the draw actually produced, so a shelf
-- with nothing on it has no button -- the bar is a map of THIS bag, not of
-- every shelf that could exist.
function Sidebar.Layout(win, keys)
    local db = Bags.db()
    local on = (win.key == "bank") and db.bankSidebar or db.bagSidebar
    if not on then
        for _, b in ipairs(win.sideButtons or {}) do b:Hide() end
        return 0
    end

    local rows = { { view = "all", key = "all", label = L["All items"] } }

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

    local y = -34
    for i, row in ipairs(rows) do
        local b = button(win, i)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", win.frame, "TOPLEFT", 4, y)
        if row.icon then
            b.icon:SetTexture(row.icon)
        else
            b.icon:SetAtlas(iconFor(row.key))
        end
        b.vfView = row.view
        b.vfTab  = row.tab
        b.vfTip  = row.tab
            and { title = row.label, lines = { L["Right-click for name and deposit filters."] } }
            or row.label
        local active = (win.view or "all") == row.view
        ns.LayoutEdges(b.edges, b, active and 1 or 0, 0.9, 0.75, 0.3, 1, 1)
        b.icon:SetAlpha(active and 1 or 0.65)
        b:Show()
        y = y - BUTTON - GAP
    end
    for i = #rows + 1, #(win.sideButtons or {}) do win.sideButtons[i]:Hide() end

    -- What the layout has to leave free on the left, and how far down the bar
    -- reaches: a bar longer than the slots decides the window's height.
    return Sidebar.WIDTH, math.abs(y) + 4
end
