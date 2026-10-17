-- VuloForeverUI / Modules / QoL / Fishing
--
-- One key for fishing, a step per press:
--
--   no pole in hand      -> equip the best pole from the bags
--   no lure on the pole  -> apply the best lure the fishing skill allows
--   otherwise            -> cast Fishing
--   bobber in the water  -> the same key reels in
--
-- Optionally a double right-click casts, and while the line is out the
-- client's own interact icon marks the bobber.
--
-- HOW, AND WHY THIS WAY
--
-- Equipping, using a lure on the main hand and casting are protected: they
-- need a hardware event on a secure button. So the key is a binding to a
-- SecureActionButton of ours ("CLICK VuloForeverUIFishButton:LeftButton",
-- declared in Bindings.xml, set by the player in the client's key bindings),
-- and its PreClick -- out of combat, where attributes may change -- points the
-- button at the next step before the secure click runs.
--
-- Reeling in is not an action a button can take. While the Fishing channel
-- runs, the same key is overridden to the client's own INTERACTTARGET, with
-- soft interact switched on for game objects so the bobber becomes that
-- target; when the channel ends the key is the button again. The CVars the
-- player had are put back once the fishing is over.
--
-- Double click: the second right mouse-down within the interval binds the
-- right button to a second button of ours for that one click; its mouse-up
-- is the click, and the override is cleared right after (see below).
local _, ns = ...
local L = ns.L

local QoL = ns.QoL
local Fish = QoL.RegisterPart("fishing", {})
QoL.Fishing = Fish

local BUTTON = "VuloForeverUIFishButton"
local MOUSE_BUTTON = "VuloForeverUIFishMouseButton"
local BINDING = "CLICK " .. BUTTON .. ":LeftButton"
local DOUBLE = 0.4                         -- seconds between the two right clicks
local POLE_CLASS, POLE_SUB = 2, 20         -- Enum.ItemClass.Weapon, Fishingpole
local FISHING_SPELL = 7620                 -- any rank: the name casts the best known

-- Lures by bonus, best first, with the fishing skill they need.
local LURES = {
    { id = 6533, skill = 100 },  -- Aquadynamic Fish Attractor (+100)
    { id = 7307, skill = 100 },  -- Flesh Eating Worm (+75)
    { id = 6532, skill = 100 },  -- Bright Baubles (+75)
    { id = 6811, skill = 50 },   -- Aquadynamic Fish Lens (+50)
    { id = 6530, skill = 50 },   -- Nightcrawlers (+50)
    { id = 6529, skill = 0 },    -- Shiny Bauble (+25)
}

-- What the bobber needs while the line is out. The player's own values are
-- kept in the saved settings (fishing.savedCVars), not in a local, so a
-- reload, a disconnect or a fight in the middle of fishing cannot leave them
-- changed: whatever is kept there goes back at the next chance out of combat.
-- SoftTargetInteract is a secure CVar -- never written in combat.
local CVARS = { SoftTargetInteract = "3", SoftTargetIconGameObject = "1", SoftTargetIconInteract = "1" }

local button, mouseButton, owner, registered
local reeling = false
local lastRight, lastNote = 0, 0
local mouseTimer

local function db() return QoL.db().fishing end

-- ------------------------------------------------------------ bags --

local function poleInHand()
    local id = GetInventoryItemID("player", INVSLOT_MAINHAND or 16)
    if not id then return false end
    local _, _, _, _, _, classID, subID = C_Item.GetItemInfoInstant(id)
    return classID == POLE_CLASS and subID == POLE_SUB
end

-- "bag slot" of the best pole (highest item level) or of a lure, for the
-- secure "item" attribute.
local function findPole()
    local best, bestLevel
    for _, bag in ipairs(ns.CarriedBags()) do
        for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
            local id = C_Container.GetContainerItemID(bag, slot)
            if id then
                local _, _, _, _, _, classID, subID = C_Item.GetItemInfoInstant(id)
                if classID == POLE_CLASS and subID == POLE_SUB then
                    local lvl = C_Item.GetDetailedItemLevelInfo(C_Container.GetContainerItemLink(bag, slot)) or 0
                    if not bestLevel or lvl > bestLevel then best, bestLevel = bag .. " " .. slot, lvl end
                end
            end
        end
    end
    return best
end

local function fishingSkill()
    local _, _, _, fishing = GetProfessions()
    if not fishing then return 0 end
    local _, _, rank = GetProfessionInfo(fishing)
    return ns.Num(rank, 0)
end

local function findLure()
    local skill = fishingSkill()
    for _, lure in ipairs(LURES) do
        if lure.skill <= skill and C_Item.GetItemCount(lure.id) > 0 then
            for _, bag in ipairs(ns.CarriedBags()) do
                for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
                    if C_Container.GetContainerItemID(bag, slot) == lure.id then return bag .. " " .. slot end
                end
            end
        end
    end
end

-- A temporary enchant on the main hand -- the lure. Same reading as the
-- reminders' weapon slots (Reminder/Core.lua, enchantLeft).
local function hasLure()
    local ok, list = pcall(C_Item.GetWeaponEnchantInfo, Enum.WeaponSlot.MainHand)
    if not ok or type(list) ~= "table" then return false end
    for _, e in pairs(list) do
        if ns.CanRead(e.hasEnchant) and e.hasEnchant
            and ns.CanRead(e.enchantType) and e.enchantType ~= Enum.ItemEnchantType.Permanent then
            return true
        end
    end
    return false
end

-- -------------------------------------------------------- the step --

-- PreClick: the next step into the secure attributes. Out of combat only;
-- in a fight the button keeps the step it had.
local function prepare(self)
    if InCombatLockdown() then return end
    self:SetAttribute("type", nil)
    self:SetAttribute("item", nil)
    self:SetAttribute("spell", nil)
    self:SetAttribute("target-slot", nil)
    -- switched off: the binding may still point here, the button does nothing
    if not registered then return end
    if not poleInHand() then
        local pole = findPole()
        if pole then
            self:SetAttribute("type", "item")
            self:SetAttribute("item", pole)
        elseif GetTime() - lastNote > 2 then
            -- PreClick runs on both edges of a press: one line, not two
            lastNote = GetTime()
            ns:Print(L["No fishing pole in your bags."])
        end
        return
    end
    if db().lure and not hasLure() then
        local lure = findLure()
        if lure then
            self:SetAttribute("type", "item")
            self:SetAttribute("item", lure)
            self:SetAttribute("target-slot", INVSLOT_MAINHAND or 16)
            return
        end
    end
    local name = C_Spell.GetSpellName(FISHING_SPELL)
    if name then
        self:SetAttribute("type", "spell")
        self:SetAttribute("spell", name)
    end
end

-- ---------------------------------------------------------- binding --

-- Every key the player bound to the button (the client allows two).
local function boundKeys()
    return { GetBindingKey(BINDING) }
end

local function restoreCVars()
    local keep = db().savedCVars
    if type(keep) ~= "table" or not next(keep) then return end
    if InCombatLockdown() then
        ns:RunOutOfCombatOnce("qol_fishing_cvars", restoreCVars)
        return
    end
    for k, v in pairs(keep) do C_CVar.SetCVar(k, v) end
    db().savedCVars = nil
end

local function setCVars()
    if InCombatLockdown() then return end
    local keep = db().savedCVars
    if type(keep) ~= "table" then keep = {}; db().savedCVars = keep end
    for k, v in pairs(CVARS) do
        if db().indicator or k == "SoftTargetInteract" then
            local cur = C_CVar.GetCVar(k)
            if cur ~= nil then
                if keep[k] == nil then keep[k] = cur end
                C_CVar.SetCVar(k, v)
            end
        end
    end
end

-- While the line is out every bound key interacts; otherwise they are the
-- button again (their binding points there, so nothing is overridden).
local function setReel(on)
    if InCombatLockdown() or not owner then return end
    ClearOverrideBindings(owner)
    reeling = on
    if on then
        for _, key in ipairs(boundKeys()) do
            SetOverrideBinding(owner, true, key, "INTERACTTARGET")
        end
    end
end

local function isFishing(spellID)
    return type(spellID) == "number" and ns.CanRead(spellID)
        and C_Spell.GetSpellName(spellID) == C_Spell.GetSpellName(FISHING_SPELL)
end

local function channelIsFishing()
    local _, _, _, _, _, _, _, spellID = UnitChannelInfo("player")
    return isFishing(spellID)
end

-- ---------------------------------------------------------- events --

local function onChannelStart(_, unit, _, spellID)
    if unit ~= "player" or not isFishing(spellID) then return end
    setCVars()
    setReel(true)
end

-- the CVars stay through the loot window; back a little later, unless the
-- next cast has begun by then
local function restoreSoon()
    C_Timer.After(3, function()
        if not reeling then restoreCVars() end
    end)
end

local function onChannelStop(_, unit)
    if unit ~= "player" then return end
    if reeling then setReel(false) end
    restoreSoon()
end

-- PLAYER_REGEN_DISABLED runs before the lockdown: every override goes now,
-- the reel one and a double-click one alike, or the right mouse button
-- would click the fishing button for the whole fight.
local function onCombatStart()
    if owner then ClearOverrideBindings(owner) end
    reeling = false
    restoreCVars()
end

-- A fight that ends while the line is still out: the key reels in again.
local function onCombatEnd()
    if registered and channelIsFishing() then
        setCVars()
        setReel(true)
    end
end

local EVENTS = {
    UNIT_SPELLCAST_CHANNEL_START = onChannelStart,
    UNIT_SPELLCAST_CHANNEL_STOP = onChannelStop,
    PLAYER_REGEN_DISABLED = onCombatStart,
    PLAYER_REGEN_ENABLED = onCombatEnd,
}

-- ------------------------------------------------------ double click --
--
-- The mouse path has its own secure button that acts on the mouse-UP
-- (useOnKeyDown false): the override is set on the second mouse-down, so
-- only the release reaches it, and the client's default of acting on the
-- down edge would let that release do nothing. A timer takes the override
-- off again if the release never turns into a click.

local function clearMouse()
    if mouseTimer then mouseTimer:Cancel(); mouseTimer = nil end
    if owner and not InCombatLockdown() and not reeling then ClearOverrideBindings(owner) end
end

local function onWorldMouseDown(_, mouse)
    if not (registered and db().doubleClick) or mouse ~= "RightButton" then return end
    if InCombatLockdown() or IsMounted() or not poleInHand() or reeling then return end
    local now = GetTime()
    if now - lastRight < DOUBLE then
        lastRight = 0
        SetOverrideBindingClick(owner, true, "BUTTON2", MOUSE_BUTTON)
        if mouseTimer then mouseTimer:Cancel() end
        mouseTimer = C_Timer.NewTimer(1, clearMouse)
    else
        lastRight = now
    end
end

-- ----------------------------------------------------------- build --

local function build()
    if button then return end
    button = CreateFrame("Button", BUTTON, UIParent, "SecureActionButtonTemplate")
    button:RegisterForClicks("AnyUp", "AnyDown")
    button:SetScript("PreClick", prepare)
    button:Hide()
    mouseButton = CreateFrame("Button", MOUSE_BUTTON, UIParent, "SecureActionButtonTemplate")
    mouseButton:RegisterForClicks("AnyUp")
    mouseButton:SetAttribute("useOnKeyDown", false)
    mouseButton:SetScript("PreClick", prepare)
    mouseButton:SetScript("PostClick", clearMouse)
    mouseButton:Hide()
    owner = CreateFrame("Frame")
    if WorldFrame and WorldFrame.HookScript then
        WorldFrame:HookScript("OnMouseDown", onWorldMouseDown)
    end
end

function Fish.Apply()
    local on = QoL.mod.active and db().enabled and true or false
    if on then
        if InCombatLockdown() then
            ns:RunOutOfCombatOnce("qol_fishing", Fish.Apply)
            return
        end
        build()
        -- left over from a reload or a fight mid-fishing
        if not channelIsFishing() then restoreCVars() end
    end
    if on == (registered or false) then return end
    registered = on
    for event, fn in pairs(EVENTS) do QoL.SyncEvent(on, event, fn) end
    if not on then Fish.Disable() end
end

function Fish.Disable()
    for event, fn in pairs(EVENTS) do ns:UnregisterEvent(event, fn) end
    registered = nil
    if owner then
        if InCombatLockdown() then
            ns:RunOutOfCombatOnce("qol_fishing_clear", function() ClearOverrideBindings(owner) end)
        else
            ClearOverrideBindings(owner)
        end
    end
    reeling = false
    restoreCVars()
end

-- The key's name in the client's key bindings, in the player's language.
ns.OnLocaleReady(function()
    _G.BINDING_HEADER_VULOFOREVERUI = "VuloForeverUI"
    -- the AddOns list shows no header, so the name carries the addon's
    _G["BINDING_NAME_" .. BINDING] = "VuloForeverUI: " .. L["Fishing"]
end)

function Fish.KeyText()
    local keys = boundKeys()
    if #keys == 0 then return nil end
    local out = {}
    for i, key in ipairs(keys) do out[i] = GetBindingText(key) end
    return table.concat(out, ", ")
end
