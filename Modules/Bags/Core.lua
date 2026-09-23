-- VuloForeverUI / Modules / Bags / Core
--
-- One window for all the bags, one for the bank, both sorted into categories.
--
-- THE TWO RULES A BAG ADDON LIVES OR DIES BY
--
-- An item slot is a SECURE button: clicking it uses, equips or moves an item,
-- and the client only allows that from a button it considers untainted. Two
-- things make a button tainted, and both are silent until the moment somebody
-- clicks in a dungeon:
--
--   1. A secure item button created IN COMBAT is tainted for good. Using the
--      item then fails with a blocked action rather than an error. So slots
--      are only ever created out of combat, the pool is grown ahead of time,
--      and a window that needs more slots than it has while a fight is on
--      simply shows what it has until the fight ends.
--   2. A custom field written on such a button taints the secure chain that
--      reads it. Everything we remember about a slot lives in the pool's own
--      wrapper table, never on the button itself.
--
-- Nothing else about bags is restricted on this client: item data is not
-- secret, so this module reads counts, qualities and item levels freely.
local _, ns = ...
local L = ns.L

local Bags = {}
ns.Bags = Bags

Bags.SLOT_SIZE = 37

local mod = ns:RegisterModule("bags", {
    name        = "Bags",
    group       = "General",
    description = "One window for every bag, sorted into categories, with a search box -- and the same for the bank.",
    defaults = {
        enabled  = false,
        replaceBlizzard = true,

        columns  = 12,
        slotSize = 37,
        spacing  = 4,
        scale    = 1,

        bgColor     = { r = 0.05, g = 0.05, b = 0.06, a = 0.92 },
        borderColor = { r = 1, g = 1, b = 1, a = 0.12 },
        borderSize  = 1,

        categories   = true,
        hideEmptyCategories = true,
        search       = true,
        showMoney    = true,
        showFreeSlots = true,

        qualityBorder = true,
        showCount     = true,
        countSize     = 11,
        showItemLevel = true,
        itemLevelSize = 11,
        itemLevelColor = { r = 0.95, g = 0.85, b = 0.4 },
        dimJunk       = true,

        -- display
        iconZoom          = 0,
        autoSize          = false,
        mergeDuplicates   = false,
        categoryTitleSize = 11,
        defaultView       = "all",
        -- An empty list means every category: a player who has never opened
        -- the list has not switched anything off.
        enabledCategories = {},
        currencies        = {},

        -- gear
        splitEquipmentSets = false,
        groupArmoryBySlot  = false,
        groupByExpansion   = false,
        showSetNames   = false,
        setNameSize    = 10,
        setNameLetters = 3,
        setNameColor   = { r = 0.6, g = 0.8, b = 1 },
        showBindTags   = false,
        bindTagSize    = 10,
        bindTagColor   = { r = 0.4, g = 1, b = 0.4 },
        warboundColor  = { r = 1, g = 0.7, b = 0.3 },

        -- extras
        showSortButton = true,
        showPinned     = true,
        showRecent     = true,
        recentColor    = { r = 0.3, g = 0.8, b = 1 },
        pinnedTips     = true,
        goldTracking   = true,
        moveWithoutShift = false,
        stackSplitter  = false,
        hideBagWarnings = false,
        pinned         = {},

        -- the bank, which groups and filters on its own switches
        bank = true,
        bankGroupByCategory = true,
        bankGroupByExpansion = false,
        bankSidebar = false,
        bankHideTabsInSidebar = false,
        bankHideEmptyWhenGrouped = false,
        bagSidebar = false,
    },
})
Bags.mod = mod

function Bags.db() return mod.db end

-- Rule 2 in practice: a slot's own state lives in the wrapper table the slot
-- pool hands out (Slots.lua), never on the button. There is no side table here
-- because nothing needs one -- an apparatus nobody calls is worse than none.

-- ---------------------------------------------------------------- bags --

-- The bags a player carries. Asked of the client rather than assumed: this
-- build may or may not have a reagent bag, and a bag id that does not exist
-- answers with no slots, which is the same as not being there.
function Bags.CarriedBags()
    local out = {}
    local idx = Enum.BagIndex
    local ids = { (idx and idx.Backpack) or 0 }
    for i = 1, (NUM_BAG_SLOTS or 4) do ids[#ids + 1] = i end
    if idx and idx.ReagentBag then ids[#ids + 1] = idx.ReagentBag end

    for _, id in ipairs(ids) do
        local slots = C_Container.GetContainerNumSlots(id)
        if type(slots) == "number" and slots > 0 then out[#out + 1] = id end
    end
    return out
end

-- The bank's containers. This is the one place where the two client families
-- differ: the newer bank is a set of numbered TABS, the older one a container
-- plus bought bags. Both are probed, neither is assumed.
function Bags.BankBags()
    local out = {}
    local idx = Enum.BagIndex

    if idx then
        -- nine tabs on 1.60.1, not six
        local tabs = Constants and Constants.InventoryConstants
            and Constants.InventoryConstants.NumCharacterBankSlots or 9
        for i = 1, tabs do
            local id = idx["CharacterBankTab_" .. i]
            if id then out[#out + 1] = id end
        end
    end
    if #out == 0 then
        local bank = (idx and idx.Bank) or _G.BANK_CONTAINER or -1
        out[#out + 1] = bank
        for i = 1, (NUM_BANKBAGSLOTS or 7) do
            local id = idx and idx["BankBag_" .. i]
            if not id then id = (NUM_BAG_SLOTS or 4) + i end
            out[#out + 1] = id
        end
    end

    local usable = {}
    for _, id in ipairs(out) do
        local slots = C_Container.GetContainerNumSlots(id)
        if type(slots) == "number" and slots > 0 then usable[#usable + 1] = id end
    end
    return usable
end

-- How many slots are free across a set of bags, and how many there are.
function Bags.CountSlots(bagIDs)
    local free, total = 0, 0
    for _, id in ipairs(bagIDs) do
        local slots = C_Container.GetContainerNumSlots(id) or 0
        total = total + slots
        local f = C_Container.GetContainerNumFreeSlots(id)
        free = free + (tonumber(f) or 0)
    end
    return free, total
end

-- ---------------------------------------------------------------- refresh --

local pending

function Bags.Refresh()
    if pending then return end
    pending = true
    ns.NextFrame(function()
        pending = false
        if not mod.active then return end
        if Bags.Window then Bags.Window.Refresh() end
        if Bags.Bank then Bags.Bank.Refresh() end
    end)
end

local repainting

function Bags.Repaint()
    if repainting then return end
    repainting = true
    ns.NextFrame(function()
        repainting = false
        if not mod.active then return end
        if Bags.Window then Bags.Window.Repaint() end
        if Bags.Bank then Bags.Bank.Repaint() end
    end)
end

-- ---------------------------------------------------------------- lifecycle --

function mod:OnEnable()
    -- What changed the SHAPE of the bags gets a full layout.
    self:RegisterEvent("BAG_UPDATE_DELAYED", function()
        -- The snapshot first: "what is new" is the difference between this
        -- pass and the last one, so it has to be taken before the draw that
        -- wants to mark it.
        Bags.Marks.Scan()
        Bags.Refresh()
    end)
    self:RegisterEvent("PLAYERBANKSLOTS_CHANGED", function() Bags.Refresh() end)
    -- A tab bought, renamed or refiltered: the sidebar draws its name and its
    -- icon from the client, so it has to be asked again.
    self:RegisterEvent("BANK_TAB_SETTINGS_UPDATED", function() Bags.Refresh() end)
    self:RegisterEvent("BANK_TABS_CHANGED", function() Bags.Refresh() end)
    self:RegisterEvent("PLAYER_MONEY", function()
        Bags.Gold.Record()
        Bags.Refresh()
    end)
    -- An item the client had not loaded yet answered with nothing, so its tags
    -- were left undecided rather than decided wrongly. This is the answer.
    self:RegisterEvent("GET_ITEM_INFO_RECEIVED", function(_, itemID)
        Bags.Items.Forget(itemID)
        Bags.Repaint()
    end)
    -- What only changed an ITEM gets a repaint. These two fire constantly --
    -- every cooldown that starts, twice for every item picked up.
    self:RegisterEvent("ITEM_LOCK_CHANGED", function() Bags.Repaint() end)
    self:RegisterEvent("BAG_UPDATE_COOLDOWN", function() Bags.Repaint() end)

    self:RegisterEvent("BANKFRAME_OPENED", function()
        if Bags.db().bank and Bags.Bank then Bags.Bank.Open() end
    end)
    self:RegisterEvent("BANKFRAME_CLOSED", function()
        if Bags.Bank then Bags.Bank.Close() end
    end)

    -- The pool is grown while it is safe to grow it. A fight that starts with
    -- a full bag would otherwise be a fight where the newest slots can never
    -- be created, and rule 1 says a slot made in combat is worse than none.
    self:RegisterEvent("PLAYER_REGEN_ENABLED", function()
        Bags.Slots.Warm()
        -- The retry the combat path promises: hiding the client's bags is
        -- refused while a fight is on and says nothing about it, so a window
        -- opened mid-fight sits on top of theirs until here.
        if Bags.db().replaceBlizzard and Bags.Window.IsShown() then Bags.HideBlizzard() end
        Bags.Refresh()
    end)
    self:RegisterEvent("PLAYER_ENTERING_WORLD", function()
        Bags.Slots.Warm()
        Bags.HookBlizzard()
        if Bags.Bank then Bags.Bank.Hook() end
    end)

    if IsLoggedIn() then
        Bags.Slots.Warm()
        Bags.HookBlizzard()
        if Bags.Bank then Bags.Bank.Hook() end
    end
    Bags.Marks.Scan()
    Bags.Gold.Record()

    ns:RegisterSlash({ key = "BAGS", commands = { "/vfbags" },
        desc = "Open the bag window.",
    })
end

ns.Slash.BAGS = function()
    if Bags.Window then Bags.Window.Toggle() end
end

function mod:OnDisable()
    if Bags.Window then Bags.Window.Close() end
    if Bags.Bank then Bags.Bank.Close() end
    -- What we took from the client is given back -- the bank frame above all,
    -- which we only ever dimmed and parked.
    if Bags.Bank then Bags.Bank.RestoreBlizzard() end
end

-- ---------------------------------------------------------------- takeover --

-- Taking the place of the client's own bags.
--
-- Hooks only. Replacing ToggleAllBags and friends outright would mean writing
-- a global, which this codebase does not do -- and a hook is enough: the
-- client opens its window, we hide it and show ours in its place.
-- The flag is set at the END, and only if a hook really went on. Set at the
-- top, a single early call -- before the client had built these frames -- used
-- to mark the whole takeover as done and leave the session with no takeover at
-- all, silently.
function Bags.HookBlizzard()
    if Bags.hooked then return end

    -- THE TOGGLE IS OURS, and it has to be.
    --
    -- The client's own toggle decides from whether ITS windows are shown --
    -- and we hide those behind its back, so it takes the "open" branch every
    -- single time. Hooked naively, the bag key opened our window and could
    -- never close it again. So the key press is read as "toggle", and what is
    -- toggled is our window.
    --
    -- The second guard is the double call: the client's Toggle calls its own
    -- Open, so one key press arrives here twice. Two full layouts of every
    -- slot per press is not what a key press should cost.
    local lastToggle = 0
    local function takeOver()
        if not (mod.active and Bags.db().replaceBlizzard) then return end
        local now = GetTime()
        if now - lastToggle < 0.05 then return end
        lastToggle = now
        if Bags.Window.IsShown() then
            Bags.Window.Close()
        else
            Bags.HideBlizzard()
            Bags.Window.Open()
        end
    end

    local installed = 0
    for _, name in ipairs({ "ToggleAllBags", "ToggleBackpack" }) do
        if type(_G[name]) == "function" then
            hooksecurefunc(name, takeOver)
            installed = installed + 1
        end
    end
    -- The plain Open functions are not a toggle and must not be read as one:
    -- a loot window or a vendor asks for the bags to be OPEN.
    for _, name in ipairs({ "OpenAllBags", "OpenBackpack" }) do
        if type(_G[name]) == "function" then
            hooksecurefunc(name, function()
                if not (mod.active and Bags.db().replaceBlizzard) then return end
                Bags.HideBlizzard()
                Bags.Window.Open()
            end)
            installed = installed + 1
        end
    end
    for _, name in ipairs({ "CloseAllBags", "CloseBackpack" }) do
        if type(_G[name]) == "function" then
            hooksecurefunc(name, function()
                if mod.active and Bags.db().replaceBlizzard then Bags.Window.Close() end
            end)
            installed = installed + 1
        end
    end

    -- A container frame that shows itself anyway -- a bag opened from the
    -- keyring, a loot window pushing one open -- is closed again on the next
    -- frame rather than inside the client's own show pass.
    for i = 1, (NUM_CONTAINER_FRAMES or 13) do
        local frame = _G["ContainerFrame" .. i]
        if frame then
            frame:HookScript("OnShow", function(self)
                if not (mod.active and Bags.db().replaceBlizzard) then return end
                ns.NextFrame(function() pcall(self.Hide, self) end)
            end)
            installed = installed + 1
        end
    end

    Bags.hooked = installed > 0
end

function Bags.HideBlizzard()
    -- In combat a protected frame refuses to be hidden and says nothing about
    -- it, so the attempt is wrapped and simply left for the next try.
    for i = 1, (NUM_CONTAINER_FRAMES or 13) do
        local frame = _G["ContainerFrame" .. i]
        if frame then pcall(frame.Hide, frame) end
    end
    if _G.ContainerFrameCombinedBags then
        pcall(_G.ContainerFrameCombinedBags.Hide, _G.ContainerFrameCombinedBags)
    end
end

-- The label of a category or a window, built lazily: a locale key read while
-- the file loads is read in whatever language the client started in.
function Bags.Title(which)
    local titles = {
        bags = L["Bags"],
        bank = L["Bank"],
    }
    return titles[which] or which
end
