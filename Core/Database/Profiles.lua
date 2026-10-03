-- VuloForeverUI / Core / Database / Profiles: profile list, create/delete/rename/switch, assignments and profile keybinds
local _, ns = ...
local L = ns.L
local P = ns._DB
local DEFAULT_PROFILE = P.DEFAULT_PROFILE
local getClassKey = P.getClassKey

function ns:GetActiveProfileName()
    return VuloForeverUIDB and VuloForeverUIDB.activeProfile or DEFAULT_PROFILE
end

function ns:GetProfileNames()
    local list = {}
    if not VuloForeverUIDB or not VuloForeverUIDB.profiles then return list end
    for name in pairs(VuloForeverUIDB.profiles) do table.insert(list, name) end
    table.sort(list)
    return list
end

function ns:ProfileExists(name)
    return VuloForeverUIDB and VuloForeverUIDB.profiles and VuloForeverUIDB.profiles[name] ~= nil
end

function ns:CreateProfile(name, copyFrom)
    if not name or name == "" then return false, L["Name cannot be empty."] end
    if ns:ProfileExists(name) then return false, L["Profile already exists."] end

    local newProfile
    if copyFrom and ns:ProfileExists(copyFrom) then
        newProfile = ns:DeepCopy(VuloForeverUIDB.profiles[copyFrom])
    else
        newProfile = ns:DeepCopy(ns.defaults.profile)
    end

    VuloForeverUIDB.profiles[name] = newProfile
    ns:Print(L["Profile '%s' created%s."], name, copyFrom and string.format(L[" (copy of '%s')"], copyFrom) or "")
    return true
end

function ns:DeleteProfile(name)
    if name == DEFAULT_PROFILE then return false, L["Default profile cannot be deleted."] end
    if not ns:ProfileExists(name) then return false, L["Profile does not exist."] end
    if ns.GetProfileKeybind and ns:GetProfileKeybind(name)
       and InCombatLockdown and InCombatLockdown() then
        return false, L["Not possible in combat."]
    end

    VuloForeverUIDB.profiles[name] = nil
    if ns.RemoveProfileKeybind then ns:RemoveProfileKeybind(name) end

    for classKey, assigned in pairs(VuloForeverUIDB.classAssignments) do
        if assigned == name then
            VuloForeverUIDB.classAssignments[classKey] = nil
        end
    end
    if VuloForeverUICharDB and VuloForeverUICharDB.profileOverride == name then
        VuloForeverUICharDB.profileOverride = nil
    end

    if ns:GetActiveProfileName() == name then
        ns:LoadProfile(DEFAULT_PROFILE)
        ns:Print(L["Active profile deleted. Default loaded. /reload recommended."])
    end

    ns:Print(L["Profile '%s' deleted."], name)
    return true
end

function ns:RenameProfile(oldName, newName)
    if oldName == DEFAULT_PROFILE then return false, L["Default profile cannot be renamed."] end
    if not ns:ProfileExists(oldName) then return false, L["Profile does not exist."] end
    if ns.GetProfileKeybind and ns:GetProfileKeybind(oldName)
       and InCombatLockdown and InCombatLockdown() then
        return false, L["Not possible in combat."]
    end
    if not newName or newName == "" then return false, L["Name cannot be empty."] end
    if ns:ProfileExists(newName) then return false, L["New name already exists."] end

    VuloForeverUIDB.profiles[newName] = VuloForeverUIDB.profiles[oldName]
    VuloForeverUIDB.profiles[oldName] = nil
    if ns.RenameProfileKeybind then ns:RenameProfileKeybind(oldName, newName) end

    for classKey, assigned in pairs(VuloForeverUIDB.classAssignments) do
        if assigned == oldName then
            VuloForeverUIDB.classAssignments[classKey] = newName
        end
    end
    if VuloForeverUICharDB and VuloForeverUICharDB.profileOverride == oldName then
        VuloForeverUICharDB.profileOverride = newName
    end

    if ns:GetActiveProfileName() == oldName then
        VuloForeverUIDB.activeProfile = newName
    end

    ns:Print(L["Profile '%s' renamed to '%s'."], oldName, newName)
    return true
end

function ns:SwitchProfile(name)
    if not ns:ProfileExists(name) then
        ns:Print(L["|cffff5555Profile '%s' does not exist.|r"], name)
        return false
    end
    local prev = ns:GetActiveProfileName()
    if prev == name then return true end

    -- an imported profile can hold junk that makes LoadProfile throw halfway
    -- (activeProfile already flipped, mod.db not repointed) — roll back
    local ok, err = pcall(ns.LoadProfile, ns, name)
    if not ok then
        pcall(ns.LoadProfile, ns, prev)
        ns:Print(L["|cffff5555Profile '%s' could not be loaded:|r %s"], name, tostring(err))
        return false
    end
    -- The new profile carries its own talent overrides; the ones from the old
    -- profile are still sitting in the live settings until these run.
    if ns.ApplyOverrides and ns.ActiveTalentGroup then
        pcall(ns.ApplyOverrides, ns, ns:ActiveTalentGroup())
    end
    ns:Print(L["Profile '%s' loaded. |cffffff00/reload|r recommended so all modules use the new settings."], name)
    return true
end

-- Lives in the char SavedVariables and beats the class assignment at login.
function ns:AssignCharToProfile(profileName)
    if profileName and profileName ~= "" and not ns:ProfileExists(profileName) then
        return false
    end
    VuloForeverUICharDB.profileOverride = (profileName ~= "" and profileName) or nil
    return true
end

function ns:GetCharAssignment()
    return VuloForeverUICharDB and VuloForeverUICharDB.profileOverride
end

function ns:AssignClassToProfile(classKey, profileName)
    if profileName and profileName ~= "" and not ns:ProfileExists(profileName) then
        return false
    end
    if profileName == "" or profileName == nil then
        VuloForeverUIDB.classAssignments[classKey] = nil
    else
        VuloForeverUIDB.classAssignments[classKey] = profileName
    end
    return true
end

function ns:GetClassAssignment(classKey)
    return VuloForeverUIDB and VuloForeverUIDB.classAssignments
        and VuloForeverUIDB.classAssignments[classKey]
end

function ns:GetMyClassKey() return getClassKey() end

-- ---------------------------------------------------------------------------
-- Profile keybinds
--
-- Bindings are intentionally account-wide. A binding activates a named profile,
-- then offers the normal reload prompt; no protected actionbar or frame work is
-- attempted while in combat. Frame names use stable short ids so old, long or
-- non-ASCII profile names cannot create invalid or colliding global frame names.
local PROFILE_BIND_PREFIX = "VFUIProfileBind_"
local profileBindButtons = {}

function ns:GetProfileKeybindValues()
    local values = { { value = "", text = L["- none -"] } }
    for i = 1, 12 do
        values[#values + 1] = { value = "F" .. i, text = "F" .. i }
    end
    for _, mod in ipairs({ "SHIFT", "CTRL", "ALT" }) do
        for i = 1, 12 do
            local key = mod .. "-F" .. i
            values[#values + 1] = { value = key, text = key }
        end
    end
    return values
end

local function profileBindButtonName(profileName)
    local g = VuloForeverUIDB.global
    g.profileKeybindButtonIds = g.profileKeybindButtonIds or {}
    local id = g.profileKeybindButtonIds[profileName]
    if not id then
        g.nextProfileKeybindButtonId = (tonumber(g.nextProfileKeybindButtonId) or 0) + 1
        id = g.nextProfileKeybindButtonId
        g.profileKeybindButtonIds[profileName] = id
    end
    return PROFILE_BIND_PREFIX .. tostring(id)
end

local function canChangeProfileBinding()
    return not (InCombatLockdown and InCombatLockdown())
end

local function showProfileReloadPrompt()
    if StaticPopupDialogs and StaticPopupDialogs["VFUI_PROFILE_RELOAD"] then
        StaticPopup_Show("VFUI_PROFILE_RELOAD")
    else
        ns:Print(L["Profile changed. Use /reload when you are out of combat."])
    end
end

local function ensureProfileBindButton(profileName)
    local btn = profileBindButtons[profileName]
    if btn then return btn end

    btn = CreateFrame("Button", profileBindButtonName(profileName), UIParent)
    btn:RegisterForClicks("AnyUp")
    btn:Hide()
    btn._profileName = profileName
    btn:SetScript("OnClick", function(self)
        local name = self._profileName
        if not canChangeProfileBinding() then
            ns:Print(L["Not possible in combat."])
            return
        end
        if ns:GetActiveProfileName() == name then return end
        if ns:SwitchProfile(name) then showProfileReloadPrompt() end
    end)
    profileBindButtons[profileName] = btn
    return btn
end

function ns:GetProfileKeybind(profileName)
    local g = VuloForeverUIDB and VuloForeverUIDB.global
    local bindings = g and g.profileKeybinds
    return bindings and bindings[profileName] or nil
end

function ns:SetProfileKeybind(profileName, key)
    if not ns:ProfileExists(profileName) then return false, L["Profile does not exist."] end
    if not canChangeProfileBinding() then return false, L["Not possible in combat."] end

    local g = VuloForeverUIDB.global
    g.profileKeybinds = g.profileKeybinds or {}

    -- One physical key must have one owner. Leaving the old owner in the table
    -- would make the winner depend on pairs() order after the next login.
    if key and key ~= "" then
        for otherName, otherKey in pairs(g.profileKeybinds) do
            if otherName ~= profileName and otherKey == key then
                local otherBtn = ensureProfileBindButton(otherName)
                ClearOverrideBindings(otherBtn)
                g.profileKeybinds[otherName] = nil
            end
        end
    end

    local btn = ensureProfileBindButton(profileName)
    ClearOverrideBindings(btn)

    if key and key ~= "" then
        SetOverrideBindingClick(btn, true, key, btn:GetName())
        g.profileKeybinds[profileName] = key
    else
        g.profileKeybinds[profileName] = nil
    end
    return true
end

function ns:RestoreProfileKeybinds()
    if not canChangeProfileBinding() then return end
    local g = VuloForeverUIDB and VuloForeverUIDB.global
    local bindings = g and g.profileKeybinds
    if type(bindings) ~= "table" then return end
    local names, claimed = {}, {}
    for profileName in pairs(bindings) do names[#names + 1] = profileName end
    table.sort(names)
    for _, profileName in ipairs(names) do
        local key = bindings[profileName]
        if ns:ProfileExists(profileName) and type(key) == "string" and key ~= "" and not claimed[key] then
            local btn = ensureProfileBindButton(profileName)
            ClearOverrideBindings(btn)
            SetOverrideBindingClick(btn, true, key, btn:GetName())
            claimed[key] = true
        else
            bindings[profileName] = nil
        end
    end
end

function ns:RemoveProfileKeybind(profileName)
    local g = VuloForeverUIDB and VuloForeverUIDB.global
    if g and g.profileKeybinds then g.profileKeybinds[profileName] = nil end
    if g and g.profileKeybindButtonIds then g.profileKeybindButtonIds[profileName] = nil end
    local btn = profileBindButtons[profileName]
    if btn and canChangeProfileBinding() then ClearOverrideBindings(btn) end
    profileBindButtons[profileName] = nil
end

function ns:RenameProfileKeybind(oldName, newName)
    local g = VuloForeverUIDB and VuloForeverUIDB.global
    local bindings = g and g.profileKeybinds
    if not bindings then return end
    local key = bindings[oldName]
    if not key then return end

    local bindId = g.profileKeybindButtonIds and g.profileKeybindButtonIds[oldName]
    local btn = profileBindButtons[oldName]
    if btn and canChangeProfileBinding() then ClearOverrideBindings(btn) end
    profileBindButtons[oldName] = nil
    bindings[oldName] = nil
    if g.profileKeybindButtonIds then g.profileKeybindButtonIds[oldName] = nil end

    bindings[newName] = key
    if bindId then g.profileKeybindButtonIds[newName] = bindId end
    if btn then
        btn._profileName = newName
        profileBindButtons[newName] = btn
        if canChangeProfileBinding() then
            SetOverrideBindingClick(btn, true, key, btn:GetName())
        end
    else
        self:SetProfileKeybind(newName, key)
    end
end
