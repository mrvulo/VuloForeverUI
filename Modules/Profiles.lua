-- Profiles: profile manager module — switch, create, copy, delete, rename profiles, assign per class.
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("profiles", {
    name        = "Profiles",
    group       = "Account",
    description = "Manage profiles with different settings. A default profile can be assigned per class and is loaded automatically on login.",
    noToggle    = true,  -- no power button in the sidebar
    -- The nine class rows are the reason: without a shared grid the ninth sits
    -- alone on full width and each dropdown box starts a few pixels off the one
    -- above it. See UI._grid in UI/OptionsBuilder.
    optionsGrid = true,
    defaults    = {
        enabled = true,
    },
})

-- This "module" has no lifecycle logic of its own
function mod:OnEnable() end

local CLASS_LIST = {
    "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST",
    "SHAMAN", "MAGE", "WARLOCK", "DRUID",
}

local CLASS_LABELS
ns.OnLocaleReady(function()
CLASS_LABELS = {
    WARRIOR = L["Warrior"], PALADIN = L["Paladin"], HUNTER = L["Hunter"], ROGUE = L["Rogue"],
    PRIEST = L["Priest"], SHAMAN = L["Shaman"], MAGE = L["Mage"], WARLOCK = L["Warlock"],
    DRUID = L["Druid"],
}
end)

-- Buffers for UI input (not saved in the DB)
local newProfileNameBuffer = ""
local copyFromBuffer       = nil
local renameNewBuffer      = ""
local manageBuffer         = nil   -- profile selected in the manage section

-- This page is reachable two ways: directly via /vfui profiles, and - the only
-- way anyone actually finds it - as the "Profile" tab of Global Settings, where
-- currentModule is "globalsettings". Checking for "profiles" alone meant every
-- refresh here did nothing on the path people use, leaving all dropdowns stale.
-- Selection for the partial export; file-local so it survives the page
-- rebuild every checkbox click triggers. false = deselected, absent =
-- selected. Look data (account-wide fonts and colors) starts DESELECTED:
-- recoloring someone's whole account on import is opt-in, not a side effect.
local exportSel = { __look = false }
local function selGet(k) return exportSel[k] ~= false end
local function selSet(k, v)
    if v then exportSel[k] = nil else exportSel[k] = false end
end

-- Modules worth an export row: they own settings beyond the enabled flag.
-- Containers and collection pages carry none, and the profile page cannot
-- export itself. Sorted by the translated name -- the list is for scanning.
local function exportableModules()
    local list = {}
    for _, key in ipairs(ns.moduleOrder or {}) do
        local m = ns.modules[key]
        if m and key ~= "profiles" then
            for dk in pairs(m.defaults or {}) do
                if dk ~= "enabled" then list[#list + 1] = key; break end
            end
        end
    end
    table.sort(list, function(a, b)
        return tostring(L[ns.modules[a].name]) < tostring(L[ns.modules[b].name])
    end)
    return list
end

local function refreshUI()
    local UI = ns.UI
    if not (UI and UI.BuildOptionsPage and UI._currentBuildKey) then return end
    if UI._currentBuildKey == "profiles" or UI._currentBuildKey == "globalsettings" then
        UI:BuildOptionsPage(UI._currentBuildKey, UI.currentTab)
    end
end

ns.OnLocaleReady(function()
StaticPopupDialogs["VFUI_PROFILE_RELOAD"] = {
    text = L["Profile changed. Reload the UI now so every module picks it up?"],
    button1 = L["Reload now"],
    button2 = L["Later"],
    OnAccept = function() ReloadUI() end,
    timeout = 0, whileDead = 1, hideOnEscape = 1, preferredIndex = 3,
}
end)
local function askReload()
    StaticPopup_Show("VFUI_PROFILE_RELOAD")
end

ns.OnLocaleReady(function()
StaticPopupDialogs["VFUI_PROFILE_DELETE"] = {
    text = L["Delete profile '%s'? This cannot be undone."],
    button1 = L["Delete"],
    button2 = CANCEL,
    OnAccept = function(self, data)
        local wasActive = ns:GetActiveProfileName() == data
        local ok, err = ns:DeleteProfile(data)
        if not ok then ns:Print("|cffff5555%s|r", err or L["Error."]) end
        if manageBuffer == data then manageBuffer = nil end
        refreshUI()
        if ok and wasActive then askReload() end
    end,
    timeout = 0, whileDead = 1, hideOnEscape = 1, preferredIndex = 3,
    showAlert = 1,
}

StaticPopupDialogs["VFUI_PROFILE_RESET"] = {
    text = L["Reset profile '%s' to the default settings? This cannot be undone."],
    button1 = L["Reset"],
    button2 = CANCEL,
    OnAccept = function(self, data)
        local ok, err = ns:ResetProfile(data)
        if not ok then ns:Print("|cffff5555%s|r", err or L["Error."]) end
        refreshUI()
        if ok and ns:GetActiveProfileName() == data then askReload() end
    end,
    timeout = 0, whileDead = 1, hideOnEscape = 1, preferredIndex = 3,
    showAlert = 1,
}
end)

-- After an import the one question that matters: use it now? Switching
-- persists at the same scope the Switch dropdown uses, so it survives relog.
ns.OnLocaleReady(function()
StaticPopupDialogs["VFUI_PROFILE_IMPORT_SWITCH"] = {
    text = L["Profile '%s' imported. Switch to it now and reload the UI?"],
    button1 = L["Switch and reload"],
    button2 = L["Later"],
    OnAccept = function(self, data)
        ns:SwitchProfile(data)
        if ns:GetCharAssignment() then
            ns:AssignCharToProfile(data)
        else
            ns:AssignClassToProfile(ns:GetMyClassKey(), data)
        end
        ReloadUI()
    end,
    timeout = 0, whileDead = 1, hideOnEscape = 1, preferredIndex = 3,
}
end)

local function getProfileValues()
    local values = {}
    for _, name in ipairs(ns:GetProfileNames()) do
        table.insert(values, { value = name, text = name })
    end
    return values
end

local function getProfileValuesWithNone()
    local values = { { value = "", text = L["- none -"] } }
    for _, name in ipairs(ns:GetProfileNames()) do
        table.insert(values, { value = name, text = name })
    end
    return values
end

function mod:GetOptions()
    local items = {}
    local activeName = ns:GetActiveProfileName()
    local myClass    = ns:GetMyClassKey()

    table.insert(items, { type = "header", text = L["Active Profile"] })

    table.insert(items, {
        type = "desc",
        text = string.format(L["You are currently using: |cff9b6cff%s|r  (Class: %s)"],
            activeName, CLASS_LABELS[myClass] or myClass)
    })

    table.insert(items, {
        type = "dropdown", label = L["Switch Profile"],
        width = 220,
        values = getProfileValues(),
        get = function() return ns:GetActiveProfileName() end,
        set = function(_, v)
            local prev = ns:GetActiveProfileName()
            ns:SwitchProfile(v)
            -- Persist the switch so it survives relog. A pinned character keeps
            -- its pin in step; otherwise the choice sticks at CLASS scope (the
            -- default scope) — without this the class assignment written on
            -- first login would silently revert the switch at the next login.
            if ns:GetCharAssignment() then
                ns:AssignCharToProfile(v)
            else
                ns:AssignClassToProfile(ns:GetMyClassKey(), v)
            end
            refreshUI()
            if v ~= prev then askReload() end
        end,
    })

    -- The one-click backup: a dated copy of the active profile, no dialog, no
    -- typing. Sub-minute duplicates collide on purpose -- the second click
    -- gets the honest "already exists" instead of a second identical copy.
    table.insert(items, {
        type = "button", label = L["Save a backup copy"], width = 220,
        tooltip = L["Creates a dated copy of the active profile as a restore point. Nothing switches - the copy just sits in the profile list."],
        onClick = function()
            local active = ns:GetActiveProfileName()
            local name = string.format("%s %s", active, date("%d.%m. %H:%M"))
            local ok, err = ns:CreateProfile(name, active)
            if not ok then
                ns:Print("|cffff5555%s|r", err or L["Error."])
            else
                ns:Print(L["Backup '%s' created."], name)
                refreshUI()
            end
        end,
    })

    -- Directly under the active profile, not four sections down. Export and
    -- import act on THIS profile, so they belong beside the line that names it
    -- -- and a backup you have to scroll for is a backup nobody takes.
    table.insert(items, { type = "spacer", height = 12 })

    table.insert(items, { type = "header", text = L["Share Profile"] })
    table.insert(items, {
        type = "desc",
        text = L["|cffaaaaaaExport the current profile as a text string - as a backup or to share it. Importing always creates a NEW profile and never overwrites anything.|r"],
    })
    table.insert(items, {
        type = "desc",
        text = L["|cffaaaaaaUntick modules to share only a part - a partial string merges onto the importer's active profile.|r"],
    })

    table.insert(items, {
        type = "group", layout = "row", gap = 6, noCard = true,
        items = {
            { type = "button", label = L["Select all"], width = 130,
              onClick = function()
                  wipe(exportSel)
                  refreshUI()
              end },
            { type = "button", label = L["Deselect all"], width = 130,
              onClick = function()
                  for _, k in ipairs(exportableModules()) do exportSel[k] = false end
                  exportSel.__layout, exportSel.__look = false, false
                  -- Only where its checkbox exists: latching it false on a
                  -- client without dual talents would silently turn every
                  -- later full export into a partial one.
                  if ns.HasTalentGroups and ns:HasTalentGroups() then
                      exportSel.__overrides = false
                  end
                  refreshUI()
              end },
        },
    })

    -- One checkbox per module, its stored on/off state in the exported
    -- profile as a dimmed suffix -- the grid pairs the rows two-up.
    local expKeys  = exportableModules()
    local expProf  = VuloForeverUIDB.profiles and VuloForeverUIDB.profiles[activeName]
    local expMods  = expProf and expProf.modules or {}
    local selCount = 0
    for _, key in ipairs(expKeys) do
        local k = key
        local m = ns.modules[k]
        if selGet(k) then selCount = selCount + 1 end
        local stored = expMods[k] and expMods[k].enabled
        if stored == nil then stored = m.defaults and m.defaults.enabled end
        local status = (stored ~= false)
            and ("|cff44ff44" .. L["On"] .. "|r")
            or  ("|cff888888" .. L["Off"] .. "|r")
        table.insert(items, { type = "checkbox",
            label = tostring(L[m.name]) .. "  |cff666677-|r " .. status,
            get = function() return selGet(k) end,
            set = function(_, v) selSet(k, v); refreshUI() end })
    end

    -- The label's parenthetical is stripped for display (StripParens); the
    -- tooltip carries the full sentence, which is that helper's contract.
    table.insert(items, { type = "checkbox",
        label = L["Interface layout (window positions and links)"],
        tooltip = L["Interface layout (window positions and links)"],
        get = function() return selGet("__layout") end,
        set = function(_, v) selSet("__layout", v); refreshUI() end })
    if ns.HasTalentGroups and ns:HasTalentGroups() then
        table.insert(items, { type = "checkbox",
            label = L["Talent Overrides"],
            get = function() return selGet("__overrides") end,
            set = function(_, v) selSet("__overrides", v); refreshUI() end })
    end
    table.insert(items, { type = "checkbox",
        label = L["Fonts & colors (account-wide)"],
        tooltip = L["Also carries your account-wide font and color settings; they apply immediately when the string is imported."],
        get = function() return selGet("__look") end,
        set = function(_, v) selSet("__look", v); refreshUI() end })

    table.insert(items, { type = "desc",
        text = string.format(L["|cffaaaaaaThe export will include %d of %d modules.|r"], selCount, #expKeys) })

    table.insert(items, {
        type = "group", layout = "row", gap = 6,
        items = {
            { type = "button", label = L["Export as string"], width = 180, primary = true,
              onClick = function()
                  local keys = exportableModules()
                  local selected, n, all = {}, 0, true
                  for _, k in ipairs(keys) do
                      if selGet(k) then selected[k] = true; n = n + 1 else all = false end
                  end
                  -- Where the overrides checkbox does not exist, its value
                  -- must count as "not subset", or the export turns partial.
                  local hasOv = ns.HasTalentGroups and ns:HasTalentGroups() and true or false
                  local ovSel = hasOv and selGet("__overrides")
                  local opts = {
                      modules   = (not all) and selected or nil,
                      layout    = selGet("__layout"),
                      overrides = (not hasOv) and true or ovSel,
                      look      = selGet("__look"),
                  }
                  if n == 0 and not (opts.layout or ovSel or opts.look) then
                      ns:Print(L["Nothing selected to export."])
                      return
                  end
                  local s = ns:ExportProfileString(nil, opts)
                  if s then
                      ns.UI:ShowProfileExportDialog(s)
                  end
              end },
            { type = "button", label = L["Import from string"], width = 180,
              onClick = function()
                  ns.UI:ShowProfileImportDialog(function(name)
                      ns:Print(L["Profile '%s' imported. Activate it via 'Switch Profile'."], name)
                      refreshUI()
                      StaticPopup_Show("VFUI_PROFILE_IMPORT_SWITCH", name, nil, name)
                  end)
              end },
        },
    })

    table.insert(items, { type = "spacer", height = 12 })

    table.insert(items, { type = "header", text = L["Profile for this character"] })
    table.insert(items, {
        type = "desc",
        text = L["|cffaaaaaaPins a profile to THIS character only. At login it beats the class assignment and the account-wide selection - so every character can keep its own minimap, bars and window settings.|r"],
    })
    table.insert(items, {
        type = "dropdown", label = UnitName and UnitName("player") or L["This character"],
        width = 220,
        values = getProfileValuesWithNone(),
        get = function() return ns:GetCharAssignment() or "" end,
        set = function(_, v)
            ns:AssignCharToProfile(v)
            if v ~= "" and v ~= ns:GetActiveProfileName() then
                ns:SwitchProfile(v)
                refreshUI()
                askReload()
            else
                refreshUI()
            end
        end,
    })

    table.insert(items, { type = "spacer", height = 12 })

    table.insert(items, { type = "header", text = L["Per-class profile (quick setup)"] })
    table.insert(items, {
        type = "desc",
        text = L["|cffaaaaaaOne click: makes a profile named after your class (copied from the current one) and loads it for this class automatically. Run it once on each character — every class then keeps its own cooldown bars, frames and settings.|r"],
    })
    table.insert(items, {
        type = "button", primary = true, width = 320,
        label = string.format(L["Set up a %s profile"], CLASS_LABELS[myClass] or myClass),
        onClick = function()
            local pname = CLASS_LABELS[myClass] or myClass
            if not ns:ProfileExists(pname) then
                ns:CreateProfile(pname, ns:GetActiveProfileName())
            end
            ns:SwitchProfile(pname)
            ns:AssignClassToProfile(myClass, pname)
            -- a character pin would override the class profile at login —
            -- the explicit class setup wins, so drop the pin
            ns:AssignCharToProfile(nil)
            ns:Print(L["'%s' is now the %s profile. |cffffff00/reload|r to apply."],
                pname, CLASS_LABELS[myClass] or myClass)
            refreshUI()
            askReload()
        end,
    })

    table.insert(items, { type = "spacer", height = 12 })

    table.insert(items, { type = "header", text = L["Create New Profile"] })

    table.insert(items, {
        type = "editbox", label = L["Name"],
        width = 220,
        get = function() return newProfileNameBuffer end,
        set = function(_, v) newProfileNameBuffer = v end,
    })

    table.insert(items, {
        type = "dropdown", label = L["Copy Settings From"],
        width = 220,
        values = (function()
            local v = { { value = "", text = L["- empty profile (defaults) -"] } }
            for _, name in ipairs(ns:GetProfileNames()) do
                table.insert(v, { value = name, text = name })
            end
            return v
        end)(),
        get = function() return copyFromBuffer or "" end,
        set = function(_, v) copyFromBuffer = (v ~= "" and v) or nil end,
    })

    table.insert(items, {
        type = "button", label = L["Create Profile"], width = 160,
        onClick = function()
            local name = (newProfileNameBuffer or ""):match("^%s*(.-)%s*$")
            if not name or name == "" then
                ns:Print(L["|cffff5555Please enter a name.|r"])
                return
            end
            local ok, err = ns:CreateProfile(name, copyFromBuffer)
            if not ok then
                ns:Print("|cffff5555%s|r", err or L["Error."])
            else
                newProfileNameBuffer = ""
                copyFromBuffer = nil
                refreshUI()
            end
        end,
    })

    table.insert(items, { type = "spacer", height = 12 })

    table.insert(items, { type = "header", text = L["Manage Profiles"] })

    -- Read at the moment a button is pressed, never captured. Rename, Delete and
    -- Reset all act on this name, so a copy taken while the page was built would
    -- point at whatever was selected back then - and rename does its work without
    -- a confirmation dialog, so the wrong profile would be renamed unnoticed.
    local function managedName()
        local n = manageBuffer
        if not n or not ns:ProfileExists(n) then return ns:GetActiveProfileName() end
        return n
    end

    table.insert(items, {
        type = "dropdown", label = L["Profile"], width = 220,
        values = getProfileValues(),
        get = function() return managedName() end,
        set = function(_, v) manageBuffer = v; refreshUI() end,
    })

    table.insert(items, {
        type = "dropdown", label = L["Profile keybind"], width = 220,
        tooltip = L["Switches to this profile outside combat and then asks to reload the UI. Override bindings are restored at login."],
        values = ns:GetProfileKeybindValues(),
        get = function() return ns:GetProfileKeybind(managedName()) or "" end,
        set = function(_, v)
            local ok, err = ns:SetProfileKeybind(managedName(), v)
            if not ok then ns:Print("|cffff5555%s|r", err or L["Error."]) end
            refreshUI()
        end,
    })

    table.insert(items, {
        type = "group", layout = "row", gap = 6,
        items = {
            {
                type = "editbox", label = L["Rename to"],
                width = 180,
                get = function() return renameNewBuffer end,
                set = function(_, v) renameNewBuffer = v end,
            },
            {
                type = "button", label = L["Rename"], width = 110,
                onClick = function()
                    local newName = (renameNewBuffer or ""):match("^%s*(.-)%s*$")
                    if not newName or newName == "" then
                        ns:Print(L["|cffff5555Please enter a new name.|r"])
                        return
                    end
                    local oldName = managedName()
                    local ok, err = ns:RenameProfile(oldName, newName)
                    if not ok then
                        ns:Print("|cffff5555%s|r", err or L["Error."])
                    else
                        renameNewBuffer = ""
                        if manageBuffer == oldName then manageBuffer = newName end
                        refreshUI()
                    end
                end,
            },
        },
    })

    table.insert(items, {
        type = "group", layout = "row", gap = 6,
        items = {
            { type = "button", label = L["Delete..."], width = 130,
              onClick = function()
                  local name = managedName()
                  if name == "Default" then
                      ns:Print(L["|cffff5555Default profile cannot be deleted.|r"])
                      return
                  end
                  StaticPopup_Show("VFUI_PROFILE_DELETE", name, nil, name)
              end },
            { type = "button", label = L["Reset to defaults..."], width = 200,
              onClick = function()
                  local name = managedName()
                  StaticPopup_Show("VFUI_PROFILE_RESET", name, nil, name)
              end },
        },
    })

    table.insert(items, {
        type = "button", label = L["Apply to Active Class"], width = 220,
        tooltip = string.format(L["Sets the current profile as the default for %s."],
            CLASS_LABELS[myClass] or myClass),
        onClick = function()
            ns:AssignClassToProfile(myClass, ns:GetActiveProfileName())
            ns:Print(L["'%s' is now the default profile for %s."],
                ns:GetActiveProfileName(), CLASS_LABELS[myClass] or myClass)
            refreshUI()
        end,
    })

    table.insert(items, { type = "spacer", height = 14 })

    table.insert(items, { type = "header", text = L["Profile Assignment per Class"] })

    table.insert(items, {
        type = "desc",
        text = L["Choose a default profile for each class. When logging in with a character of that class, the profile will be loaded automatically."],
    })

    local values = getProfileValuesWithNone()

    for _, classKey in ipairs(CLASS_LIST) do
        table.insert(items, {
            type = "dropdown", label = CLASS_LABELS[classKey] or classKey,
            width = 200,
            values = values,
            get = function() return ns:GetClassAssignment(classKey) or "" end,
            set = function(_, v) ns:AssignClassToProfile(classKey, v) end,
        })
    end

    -- Per-talent-group values for individual settings, so a second build does
    -- not need a duplicate profile. Engine in Core/TalentOverrides.lua.
    -- Gated on the API existing, NOT on a group count: the client offers no way
    -- to ask how many talent groups a character has.
    if ns.HasTalentGroups and ns:HasTalentGroups() then
        local active = ns:ActiveTalentGroup()

        table.insert(items, { type = "spacer", height = 10 })
        table.insert(items, { type = "header", text = L["Talent Overrides"] })
        table.insert(items, { type = "desc", text = L["Overrides apply on their own when you switch talent groups. This client has no specialisations, so the dual talent system is the axis."] })
        table.insert(items, { type = "desc", text = "|cff888888" .. ns:TalentGroupText(active) .. "|r" })

        local groups = ns:OverrideGroups()
        local any = false
        for id, g in pairs(groups) do
            any = true
            table.insert(items, { type = "spacer", height = 6 })
            table.insert(items, {
                type  = "desc",
                text  = "|cffffffff" .. g.name .. "|r  |cff666666"
                        .. string.format(L["%d settings overridden"], ns:CountOverrides(id)) .. "|r",
            })
            table.insert(items, {
                type    = "checkbox",
                label   = L["Owns the current talent group"],
                -- noOverride: the override machinery must never record its own
                -- controls, or turning one on would store it as a value.
                noOverride = true,
                get = function() return (g.members and g.members[active]) and true or false end,
                set = function(_, v)
                    ns:AssignTalentGroup(active, v and id or nil)
                    if ns.UI and ns.UI.RebuildCurrentPage then ns.UI:RebuildCurrentPage() end
                end,
            })

            -- Second axis. A group may name a build, a situation, or both; both
            -- means it only applies when both are true, and then it wins over a
            -- group that names just one. See ns:MatchingOverrideGroups.
            local sitValues = { { value = "", text = L["Everywhere"] } }
            for _, k in ipairs(ns.OVERRIDE_SITUATIONS or {}) do
                sitValues[#sitValues + 1] = { value = k, text = ns:SituationLabel(k) }
            end
            table.insert(items, {
                type    = "dropdown",
                label   = L["Situation"],
                width   = 240,
                tooltip = L["Applies only in this situation. Combined with a talent group, both have to be true - and that group then overrides one that names only the talent group."],
                noOverride = true,
                values  = sitValues,
                get = function() return ns:OverrideGroupSituation(id) or "" end,
                set = function(_, v)
                    ns:SetOverrideGroupSituation(id, v)
                    ns:ApplyOverrides()
                    if ns.UI and ns.UI.RebuildCurrentPage then ns.UI:RebuildCurrentPage() end
                end,
            })

            local iconValues = { { value = 0, text = L["No icon"] } }
            for n = 1, 8 do
                iconValues[n + 1] = {
                    value = n,
                    text  = ns:OverrideIconMarkup(n) .. ns:OverrideIconLabel(n),
                }
            end
            table.insert(items, {
                type    = "dropdown",
                label   = L["Icon"],
                width   = 240,
                tooltip = L["Shown in front of the group name in the menu and on the header button."],
                noOverride = true,
                values  = iconValues,
                get = function() return ns:OverrideGroupIcon(id) or 0 end,
                set = function(_, v)
                    ns:SetOverrideGroupIcon(id, v)
                    if ns.UI and ns.UI.RefreshOverrideButton then ns.UI:RefreshOverrideButton() end
                    if ns.UI and ns.UI.RebuildCurrentPage then ns.UI:RebuildCurrentPage() end
                end,
            })
            -- The overrides themselves, one row each, inside a section so a
            -- group with forty of them does not bury the rest of the page.
            -- Sections start closed, so this costs one line until you open it.
            local list = ns:OverrideList(id)
            if #list > 0 then
                local rows = {}
                for _, e in ipairs(list) do
                    local oid = e.id
                    rows[#rows + 1] = {
                        type  = "checkbox",
                        -- One per row: the label is a path, not a setting name,
                        -- and this page runs the two-column grid.
                        fullWidth = true,
                        label = e.text .. "  |cff888888" .. ns:OverrideValueText(e.value) .. "|r",
                        tooltip = L["Switch off to drop this one override. The setting then follows the profile again."],
                        -- Without this the machinery would record its own rows
                        -- as overrides the moment you touched one.
                        noOverride = true,
                        get = function() return true end,
                        set = function(_, v)
                            if v then return end   -- only unticking means anything
                            ns:RemoveOverride(id, oid)
                            if ns.UI and ns.UI.RebuildCurrentPage then ns.UI:RebuildCurrentPage() end
                        end,
                    }
                end
                table.insert(items, {
                    type  = "section",
                    -- Group name in the title, so two groups get two collapse
                    -- states instead of sharing one.
                    title = string.format(L["Overridden settings: %s"], g.name),
                    items = rows,
                })
            end

            table.insert(items, { type = "group", layout = "row", noCard = true, items = {
                { type = "button", label = L["Forget all overrides for this talent group"],
                  onClick = function()
                      ns:ClearOverrides(id)
                      if ns.UI and ns.UI.RebuildCurrentPage then ns.UI:RebuildCurrentPage() end
                  end },
                { type = "button", label = L["Delete this group"],
                  onClick = function()
                      ns:DeleteOverrideGroup(id)
                      if ns.UI and ns.UI.RebuildCurrentPage then ns.UI:RebuildCurrentPage() end
                  end },
            } })
        end

        if not any then
            table.insert(items, { type = "desc", text = "|cff888888" .. L["No groups yet."] .. "|r" })
        end

        table.insert(items, {
            type  = "button",
            label = L["New group..."],
            onClick = function() StaticPopup_Show("VFUI_OVERRIDE_GROUP_NEW") end,
        })
    end

    return items
end
