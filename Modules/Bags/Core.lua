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

        bgColor     = { r = 0.05, g = 0.05, b = 0.06, a = 0.97 },
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
        markJunk      = true,

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
        sortMethod     = "type",    -- type | quality | name | itemlevel (Sort.lua)
        sortFromBottom = false,
        showPinned     = true,
        showRecent     = true,
        showBagBar     = false,
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

-- The bank's containers: numbered character TABS, nine on 1.60.1.
function Bags.BankBags()
    local out = {}
    local idx = Enum.BagIndex
    for i = 1, Constants.InventoryConstants.NumCharacterBankSlots do
        local id = idx["CharacterBankTab_" .. i]
        if id then out[#out + 1] = id end
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
    -- A saved view that no longer exists (a renamed view, a category that was
    -- dropped) would open the window on an empty filter; it goes back to all.
    local db = Bags.db()
    local known = false
    for _, v in ipairs(Bags.Categories.ViewValues()) do
        if v.value == db.defaultView then known = true; break end
    end
    if not known then db.defaultView = "all" end

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
    if Bags.BankView then Bags.BankView.Release() end
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
        Bags.ParkBlizzard()
        Bags.Refresh()
    end)
    self:RegisterEvent("PLAYER_ENTERING_WORLD", function()
        Bags.Marks.Quiet(5)
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

    -- The windows' boxes in our edit mode. Built now, hidden, so they exist
    -- before the edit mode takes its snapshot (Window.AttachMover).
    if Bags.Window then Bags.Window.EnsureMover() end
    if Bags.Bank then Bags.Bank.EnsureMover() end
    if Bags.BankView then Bags.BankView.EnsureMover() end

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
    Bags.UnparkBlizzard()
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
-- Every bag frame the client owns: one per container, and the combined
-- backpack that is the one a player actually sees.
local function blizzardFrames()
    local out = {}
    for i = 1, (NUM_CONTAINER_FRAMES or 13) do
        local frame = _G["ContainerFrame" .. i]
        if frame then out[#out + 1] = frame end
    end
    if _G.ContainerFrameCombinedBags then out[#out + 1] = _G.ContainerFrameCombinedBags end
    return out
end

function Bags.HookBlizzard()
    if Bags.hooked then Bags.ParkBlizzard(); return end

    -- THE TOGGLE IS OURS, and it has to be.
    --
    -- The client's own toggles decide from whether ITS windows are shown --
    -- and we hide those behind its back, so they take the "open" branch every
    -- time. Worse, one click is several calls: a bag button calls ToggleBag,
    -- which calls ToggleBackpack_Combined, which calls OpenBackpack. Answered
    -- call by call, the Open inside the toggle reopened what the toggle meant
    -- to close, and a bag button could open the bags but never close them.
    --
    -- So every call in one frame is only NOTED, together with whether our
    -- window was up when the first one arrived, and the next frame decides
    -- once: any toggle flips that remembered state; otherwise a close wins
    -- over nothing, and an open over a close (a vendor opening the bags).
    local wasShown, wantToggle, wantOpen, wantClose, queued
    local function resolve()
        queued = false
        local toggle, open, close = wantToggle, wantOpen, wantClose
        wantToggle, wantOpen, wantClose = nil, nil, nil
        if not (mod.active and Bags.db().replaceBlizzard) then return end
        -- Re-asserted on every toggle: the client can hand its frames back to
        -- UIParent (its full-screen frame handling), and then they flash again.
        Bags.ParkBlizzard()
        -- The client's frames go in every branch, the closing one included:
        -- its own toggle saw its frames hidden and OPENED them, so the second
        -- click on a bag button left its combined backpack standing where
        -- ours had just closed.
        Bags.HideBlizzard()
        if toggle then
            if wasShown then Bags.Window.Close() else Bags.Window.Open() end
        elseif open then
            Bags.Window.Open()
        elseif close then
            Bags.Window.Close()
        end
    end
    local function request(kind)
        if not (mod.active and Bags.db().replaceBlizzard) then return end
        if not queued then
            queued = true
            wasShown = Bags.Window.IsShown()
            ns.NextFrame(resolve)
        end
        if kind == "toggle" then wantToggle = true
        elseif kind == "open" then wantOpen = true
        else wantClose = true end
    end

    local installed = 0
    local function hookAll(names, kind)
        for _, name in ipairs(names) do
            if type(_G[name]) == "function" then
                hooksecurefunc(name, function() request(kind) end)
                installed = installed + 1
            end
        end
    end
    hookAll({ "ToggleAllBags", "ToggleBackpack" }, "toggle")
    -- ToggleBag is what the bag buttons on the action bar call. The keyring
    -- goes through it as well and is not one of our bags.
    if type(_G.ToggleBag) == "function" then
        hooksecurefunc("ToggleBag", function(id)
            if id ~= nil and id == _G.KEYRING_CONTAINER then return end
            request("toggle")
        end)
        installed = installed + 1
    end
    -- The plain Open functions are not a toggle and must not be read as one:
    -- a loot window or a vendor asks for the bags to be OPEN.
    hookAll({ "OpenAllBags", "OpenBackpack" }, "open")
    hookAll({ "CloseAllBags", "CloseBackpack" }, "close")

    -- A container frame that shows itself anyway -- a bag opened from the
    -- keyring, a loot window pushing one open -- is closed again on the next
    -- frame rather than inside the client's own show pass. Parked (below), a
    -- frame never becomes visible and this never fires; it is the fallback
    -- for the moment before the park, a login in the middle of a fight.
    for _, frame in ipairs(blizzardFrames()) do
        frame:HookScript("OnShow", function(self)
            if not (mod.active and Bags.db().replaceBlizzard) then return end
            ns.NextFrame(function() pcall(self.Hide, self) end)
        end)
        installed = installed + 1
    end

    Bags.hooked = installed > 0
    Bags.ParkBlizzard()
end

function Bags.HideBlizzard()
    -- In combat a protected frame refuses to be hidden and says nothing about
    -- it, so the attempt is wrapped and simply left for the next try.
    for _, frame in ipairs(blizzardFrames()) do pcall(frame.Hide, frame) end
end

-- The client's bag frames, PARKED under a frame of ours that is never shown.
--
-- Hiding them after they open was always a frame late: the client drew its
-- combined backpack once, and then it went -- a flash on every open. Under a
-- hidden parent the client may open them as often as it likes and none of it
-- reaches the screen. SetParent is a method call, it writes no field on the
-- frame, and it is refused in a fight, so a park asked for then waits for
-- PLAYER_REGEN_ENABLED.
local park = CreateFrame("Frame")
park:Hide()
local parkedFrom = {}   -- frame -> the parent it had before

-- An unpark asked for in a fight (the takeover switched off, the module
-- disabled) waits for the fight to end on a frame of its own: the module's
-- event registry is already gone when the module is being switched off, and a
-- lost unpark left the client's bags invisible until a reload.
local unparkRetry = CreateFrame("Frame")
unparkRetry:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    Bags.UnparkBlizzard()
end)

function Bags.ParkBlizzard()
    if not (mod.active and Bags.db().replaceBlizzard) then return end
    if InCombatLockdown() then return end
    unparkRetry:UnregisterEvent("PLAYER_REGEN_ENABLED")   -- a pending unpark is void
    for _, frame in ipairs(blizzardFrames()) do
        local parent = frame:GetParent()
        if parent ~= park then
            parkedFrom[frame] = parent or UIParent
            frame:SetParent(park)
        end
    end
end

function Bags.UnparkBlizzard()
    if InCombatLockdown() then
        unparkRetry:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    unparkRetry:UnregisterEvent("PLAYER_REGEN_ENABLED")
    for frame, parent in pairs(parkedFrom) do
        if frame:GetParent() == park then
            -- Shown under the park means "open" to the client, and would
            -- turn up the moment it is back: it comes back closed.
            pcall(frame.Hide, frame)
            frame:SetParent(parent)
        end
    end
    wipe(parkedFrom)
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
