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
-- For skilling: the key can be set from the options page (a small window
-- that takes the next key press), auto loot and a louder bobber while the
-- line is out, the weapons the key took off come back on mounting, and one
-- chat line when the skill sits at the top of its rank.
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
local LOOT_CVARS = { autoLootDefault = "1" }
-- The splash is a positional sound effect some 15-20 yards away. Effects
-- cannot go past full, so the rest goes quiet instead: music, ambience,
-- voices, pets, emotes, armour rustle and error speech off; and the
-- distance low-pass and reverb that muffle a sound that far away are off too.
local SOUND_CVARS = {
    Sound_EnableAllSound = "1", Sound_MasterVolume = "1",
    Sound_EnableSFX = "1", Sound_SFXVolume = "1",
    Sound_EnableGameplaySFX = "1", Sound_GameplaySFX = "1",
    Sound_EnableSoundWhenGameIsInBG = "1",
    Sound_MusicVolume = "0", Sound_AmbienceVolume = "0", Sound_DialogVolume = "0",
    Sound_EnablePetSounds = "0", Sound_EnableEmoteSounds = "0", Sound_EnableErrorSpeech = "0",
    Sound_EnableArmorFoleySoundForSelf = "0", Sound_EnableArmorFoleySoundForOthers = "0",
    Sound_EnablePositionalLowPassFilter = "0", Sound_EnableReverb = "0",
}
local TOP_RANK = 300                       -- below this a full rank means "see the trainer"
local MODIFIER = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true,
                   LALT = true, RALT = true, LMETA = true, RMETA = true }
local MOUSE_KEYS = { MiddleButton = true, Button4 = true, Button5 = true }

local button, mouseButton, owner, registered
local reeling = false
local lastRight, lastNote = 0, 0
local mouseTimer
local capture

-- The mouse wheel as the key: one turn is a burst of notches, each one a
-- press. Two guards keep a burst to one action -- presses of the same edge
-- within WHEEL_SETTLE do nothing, and the wheel reels in only WHEEL_REEL
-- after the cast, when no fish can have bitten yet anyway.
local WHEEL_SETTLE = 0.6
local WHEEL_REEL = 1
local lastActed = { [true] = 0, [false] = 0 }   -- per edge: down, up

local function isWheel(key)
    return type(key) == "string" and key:find("MOUSEWHEEL", 1, true) ~= nil
end

local function wheelBound()
    for _, key in ipairs({ GetBindingKey(BINDING) }) do
        if isWheel(key) then return true end
    end
    return false
end

local function db() return QoL.db().fishing end
Fish.db = db

-- What belongs to this character, not to the (often shared) profile: the
-- weapons the key took off and the skill rank already announced.
local function charDB()
    local c = VuloForeverUICharDB
    if type(c) ~= "table" then return {} end
    if type(c.fishing) ~= "table" then c.fishing = {} end
    return c.fishing
end
Fish.CharDB = charDB

-- ------------------------------------------------------------ bags --

local function poleInHand()
    local id = GetInventoryItemID("player", INVSLOT_MAINHAND or 16)
    if not id then return false end
    local _, _, _, _, _, classID, subID = C_Item.GetItemInfoInstant(id)
    return classID == POLE_CLASS and subID == POLE_SUB
end
Fish.PoleInHand = poleInHand

-- "bag slot" of the best pole (most fishing bonus, then highest item level)
-- or of a lure, for the secure "item" attribute.
local function findPole()
    local best, bestBonus, bestLevel
    for _, bag in ipairs(ns.CarriedBags()) do
        for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
            local id = C_Container.GetContainerItemID(bag, slot)
            if id then
                local _, _, _, _, _, classID, subID = C_Item.GetItemInfoInstant(id)
                if classID == POLE_CLASS and subID == POLE_SUB then
                    local lvl = C_Item.GetDetailedItemLevelInfo(C_Container.GetContainerItemLink(bag, slot)) or 0
                    local bonus = Fish.BagBonus and Fish.BagBonus(bag, slot) or 0
                    if not bestLevel or bonus > bestBonus or (bonus == bestBonus and lvl > bestLevel) then
                        best, bestBonus, bestLevel = bag .. " " .. slot, bonus, lvl
                    end
                end
            end
        end
    end
    return best
end

-- rank, max; nil when the character never learned Fishing
local function fishingSkill()
    local _, _, _, fishing = GetProfessions()
    if not fishing then return nil end
    local _, _, rank, max = GetProfessionInfo(fishing)
    return ns.Num(rank, 0), ns.Num(max, 0)
end
Fish.Skill = fishingSkill

local function findLure()
    local skill = fishingSkill() or 0
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

-- The weapons the key is about to take off, kept per character so a reload
-- between fishing and mounting does not lose them. Only reached with no pole
-- in hand, so whatever is held is the player's current weapon: it always
-- replaces an older note (weapons changed by hand since the last pole).
local function rememberWeapons()
    if not db().swapBack then return end
    local main = GetInventoryItemID("player", INVSLOT_MAINHAND or 16)
    if not main then return end
    charDB().weaponsBack = { main = main, off = GetInventoryItemID("player", INVSLOT_OFFHAND or 17) }
end

-- -------------------------------------------------------- the step --

-- PreClick: the next step into the secure attributes. Out of combat only;
-- in a fight the button keeps the step it had.
local function castFishing(self)
    local name = C_Spell.GetSpellName(FISHING_SPELL)
    if name then
        self:SetAttribute("type", "spell")
        self:SetAttribute("spell", name)
    end
end

local function prepare(self, mouse, down)
    if InCombatLockdown() then return end
    self:SetAttribute("type", nil)
    self:SetAttribute("item", nil)
    self:SetAttribute("spell", nil)
    self:SetAttribute("target-slot", nil)
    -- switched off: the binding may still point here, the button does nothing
    if not registered then return end
    -- the line is out: only Ctrl + key casts again. The keyboard is the
    -- reel key by now; this catches a late wheel notch before the wheel is.
    if reeling and mouse ~= "Recast" then return end
    -- the rest of a wheel turn: nothing
    local edge = down and true or false
    if wheelBound() then
        local now = GetTime()
        if now - lastActed[edge] < WHEEL_SETTLE then return end
        lastActed[edge] = now
    end
    -- Ctrl + key while the line is out: straight back to casting, no gear,
    -- no lure -- for landing the bobber in a school of fish.
    if mouse == "Recast" then
        castFishing(self)
        return
    end
    if db().gear and Fish.WearGear then Fish.WearGear() end
    if not poleInHand() then
        local pole = findPole()
        if pole then
            rememberWeapons()
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
    castFishing(self)
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

local function setGroup(keep, list, only)
    for k, v in pairs(list) do
        if not only or k == only then
            local cur = C_CVar.GetCVar(k)
            if cur ~= nil then
                if keep[k] == nil then keep[k] = cur end
                C_CVar.SetCVar(k, v)
            end
        end
    end
end

local function setCVars()
    if InCombatLockdown() then return end
    local keep = db().savedCVars
    if type(keep) ~= "table" then keep = {}; db().savedCVars = keep end
    setGroup(keep, CVARS, not db().indicator and "SoftTargetInteract" or nil)
    if db().autoLoot then setGroup(keep, LOOT_CVARS) end
    if db().sound then setGroup(keep, SOUND_CVARS) end
end

-- The same chord with Ctrl added, modifiers in the client's own order; nil
-- when the key already carries Ctrl.
local CHORD_ORDER = { "ALT", "CTRL", "SHIFT", "META" }
local function withCtrl(key)
    local mods, base = {}, key
    while true do
        local m, rest = base:match("^(%u+)%-(.+)$")
        if not (m and MODIFIER["L" .. m]) then break end
        mods[m] = true
        base = rest
    end
    if mods.CTRL then return nil end
    mods.CTRL = true
    local out = ""
    for _, m in ipairs(CHORD_ORDER) do
        if mods[m] then out = out .. m .. "-" end
    end
    return out .. base
end

-- While the line is out every bound key interacts and, with quick recast,
-- Ctrl + key clicks the button as "Recast"; otherwise the keys are the
-- button again (their binding points there, so nothing is overridden).
local function reelKey(key)
    SetOverrideBinding(owner, true, key, "INTERACTTARGET")
    local recast = db().quickRecast and withCtrl(key)
    if recast then SetOverrideBindingClick(owner, true, recast, BUTTON, "Recast") end
end

local reelSerial = 0
local function setReel(on)
    if InCombatLockdown() or not owner then return end
    ClearOverrideBindings(owner)
    reeling = on
    reelSerial = reelSerial + 1
    if not on then return end
    local wheels = {}
    for _, key in ipairs(boundKeys()) do
        if isWheel(key) then wheels[#wheels + 1] = key else reelKey(key) end
    end
    if #wheels == 0 then return end
    -- the wheel turn that cast must not reel straight back in
    local serial = reelSerial
    C_Timer.After(WHEEL_REEL, function()
        if serial ~= reelSerial or not reeling or InCombatLockdown() then return end
        for _, key in ipairs(wheels) do reelKey(key) end
    end)
end

local function isFishing(spellID)
    return type(spellID) == "number" and ns.CanRead(spellID)
        and C_Spell.GetSpellName(spellID) == C_Spell.GetSpellName(FISHING_SPELL)
end

local function channelIsFishing()
    local _, _, _, _, _, _, _, spellID = UnitChannelInfo("player")
    return isFishing(spellID)
end
Fish.ChannelIsFishing = channelIsFishing

-- ------------------------------------------------- weapons, skill --

-- Back to the weapons the key took off. Only while the pole is still what
-- the key put there: anything the player equipped since is their choice.
-- The off hand waits until the main hand is in place and unlocked (the pole
-- out of both hands); a slow server gets a few more tries.
local function offHandBack(main, off, tries)
    if InCombatLockdown() or GetInventoryItemID("player", INVSLOT_OFFHAND or 17) == off then return end
    local mainSlot = INVSLOT_MAINHAND or 16
    if GetInventoryItemID("player", mainSlot) ~= main or IsInventoryItemLocked(mainSlot) then
        if tries > 0 then C_Timer.After(0.5, function() offHandBack(main, off, tries - 1) end) end
        return
    end
    if C_Item.GetItemCount(off) > 0 then C_Item.EquipItemByName(off, INVSLOT_OFFHAND or 17) end
end

local function weaponsBack()
    local c = charDB()
    local w = c.weaponsBack
    if type(w) ~= "table" then return end
    if InCombatLockdown() or UnitIsDeadOrGhost("player") or channelIsFishing() then return end
    if not db().swapBack or not poleInHand() or C_Item.GetItemCount(w.main) == 0 then
        c.weaponsBack = nil
        return
    end
    c.weaponsBack = nil
    C_Item.EquipItemByName(w.main, INVSLOT_MAINHAND or 16)
    if w.off then
        C_Timer.After(0.5, function() offHandBack(w.main, w.off, 6) end)
    end
end

local function onMount()
    if not IsMounted() then return end
    weaponsBack()
    if Fish.GearBack then Fish.GearBack() end
end

-- One line when the skill sits at the top of a rank below the last; the max
-- it was said for is kept, so neither a reload nor the next skill event
-- repeats it.
local function checkRank()
    if not db().capNotice then return end
    local rank, max = fishingSkill()
    if not rank or max <= 0 or max >= TOP_RANK or rank < max then return end
    local c = charDB()
    if c.capNoticed == max then return end
    c.capNoticed = max
    ns:Print(L["Fishing is at %d / %d: the next rank waits at the fishing trainer."]:format(rank, max))
end

-- ---------------------------------------------------------- events --

local function onChannelStart(_, unit, _, spellID)
    if unit ~= "player" or not isFishing(spellID) then return end
    setCVars()
    setReel(true)
    if Fish.OnCast then Fish.OnCast() end
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
    local wasFishing = reeling
    if reeling then setReel(false) end
    restoreSoon()
    if wasFishing and Fish.OnLineIn then Fish.OnLineIn() end
end

-- PLAYER_REGEN_DISABLED runs before the lockdown: every override goes now,
-- the reel one and a double-click one alike, or the right mouse button
-- would click the fishing button for the whole fight.
local function onCombatStart()
    if capture then capture:Hide() end
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
    PLAYER_MOUNT_DISPLAY_CHANGED = onMount,
    SKILL_LINES_CHANGED = checkRank,
    -- the catch and the fish that got away (FishingSession.lua)
    LOOT_OPENED = function() if Fish.OnLoot then Fish.OnLoot() end end,
    UI_ERROR_MESSAGE = function(_, _, msg) if Fish.OnMessage then Fish.OnMessage(msg) end end,
    UI_INFO_MESSAGE = function(_, _, msg) if Fish.OnMessage then Fish.OnMessage(msg) end end,
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
        checkRank()
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
    if Fish.StopReminder then Fish.StopReminder() end
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

function Fish.SkillText()
    local rank, max = fishingSkill()
    if not rank then return nil end
    return L["Fishing skill: %d / %d"]:format(rank, max)
end

-- ------------------------------------------------------ key capture --
--
-- The options page sets the key itself: a small window takes the next key
-- press through an edit box nobody sees (no protected keyboard propagation),
-- and the key replaces whatever was bound to the fishing button before.
-- Binding is refused in a fight, and a fight closes the window.

local function bindTo(chord)
    if capture then capture:Hide() end
    if InCombatLockdown() then
        ns:Print(L["Key bindings cannot be changed during a fight."])
        return
    end
    local old = GetBindingAction(chord)
    if old == BINDING then old = nil end
    -- the new key replaces the old ones; they come back if it cannot be bound
    local before = boundKeys()
    for _, key in ipairs(before) do SetBinding(key) end
    if not SetBinding(chord, BINDING) then
        for _, key in ipairs(before) do SetBinding(key, BINDING) end
        ns:Print(L["That key cannot be bound."])
        return
    end
    SaveBindings(GetCurrentBindingSet())
    local text = GetBindingText(chord)
    if type(old) == "string" and old ~= "" then
        ns:Print(L["Fishing key: %s (was: %s)"]:format(text, _G["BINDING_NAME_" .. old] or old))
    else
        ns:Print(L["Fishing key: %s"]:format(text))
    end
    if ns.UI.RebuildCurrentPage then ns.UI:RebuildCurrentPage() end
end

local function buildCapture()
    local f = CreateFrame("Frame", "VuloForeverUIFishKeyCapture", UIParent)
    f:SetSize(380, 110)
    f:SetPoint("CENTER", 0, 140)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetToplevel(true)
    f:EnableMouse(true)
    ns.UI:StyleBackdrop(f)
    ns.UI:CreateCloseX(f, function() f:Hide() end)

    f.title = f:CreateFontString(nil, "OVERLAY")
    ns.UI.Font(f.title, 14, "")
    f.title:SetPoint("TOP", 0, -14)
    f.text = f:CreateFontString(nil, "OVERLAY")
    ns.UI.Font(f.text, 11, "")
    f.text:SetPoint("TOPLEFT", 18, -42)
    f.text:SetPoint("TOPRIGHT", -18, -42)
    f.text:SetJustifyH("CENTER")

    local input = CreateFrame("EditBox", nil, f)
    input:SetSize(1, 1)
    input:SetPoint("TOPLEFT")
    input:SetAutoFocus(false)
    input:SetFontObject(ChatFontNormal)
    input:SetAlpha(0)
    input:SetScript("OnChar", function(self) self:SetText("") end)
    input:SetScript("OnEscapePressed", function() f:Hide() end)
    input:SetScript("OnKeyDown", function(_, key)
        if key == "ESCAPE" then f:Hide(); return end
        -- what the client's own key bindings skip: modifiers alone, unknown
        -- keys, the screenshot key
        if MODIFIER[key] or key == "PRINTSCREEN"
            or (IsKeyPressIgnoredForBinding and IsKeyPressIgnoredForBinding(key)) then return end
        bindTo(CreateKeyChordStringUsingMetaKeyState(key))
    end)
    f:SetScript("OnMouseDown", function(_, mouse)
        if MOUSE_KEYS[mouse] then
            bindTo(CreateKeyChordStringUsingMetaKeyState(GetConvertedKeyOrButton(mouse)))
        end
    end)
    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(_, delta)
        bindTo(CreateKeyChordStringUsingMetaKeyState(delta > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN"))
    end)
    f:SetScript("OnShow", function()
        f.title:SetText(L["Set the fishing key"])
        f.text:SetText(L["Press the key now, with Shift, Ctrl or Alt if you like, or mouse button 3, 4 or 5 or the mouse wheel over this window. Escape cancels."])
        input:SetFocus()
    end)
    -- parented to the options window: closing it ends the capture too, so a
    -- key pressed afterwards (say W) can never become the fishing key
    f:SetScript("OnHide", function(self)
        input:ClearFocus()
        if self:IsShown() then self:Hide() end
    end)
    f:Hide()
    return f
end

function Fish.CaptureKey()
    if InCombatLockdown() then
        ns:Print(L["Key bindings cannot be changed during a fight."])
        return
    end
    capture = capture or buildCapture()
    capture:SetParent(ns.UI.mainFrame or UIParent)
    capture:SetFrameStrata("FULLSCREEN_DIALOG")
    capture:Show()
end

function Fish.ClearKey()
    if InCombatLockdown() then
        ns:Print(L["Key bindings cannot be changed during a fight."])
        return
    end
    for _, key in ipairs(boundKeys()) do SetBinding(key) end
    SaveBindings(GetCurrentBindingSet())
    if ns.UI.RebuildCurrentPage then ns.UI:RebuildCurrentPage() end
end
