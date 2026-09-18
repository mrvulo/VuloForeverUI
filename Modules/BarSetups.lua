-- Bar Setups: named snapshots of action bars, macros and keybindings. Spells
-- match by ID with name fallback, macros by name, so snapshots survive relogs
-- and macro reshuffles.
--
-- The share string is the same format VuloClassicUI writes ("!VBAR1"/"!VBAR2",
-- identical Encode/DecodeShareString), so a setup exported on that client
-- reads in here. What does NOT carry over is decided per entry at restore
-- time: a spell the character does not know, an item it does not own, a
-- binding command this client has no such action for -- each is skipped and
-- counted, never allowed to stop the run.
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("vulslot", {
    name        = "Bar Setups",
    -- "Account" is a sidebar-hidden group: this page is reached through the
    -- Bar Setups tab of Global Settings, the same way the profile manager is
    -- reached through the Profile tab.
    group       = "Account",
    noToggle    = true,   -- nothing to switch off: OnEnable/OnDisable are empty
    description = "Saves named snapshots of your action bars, macros and keybindings, and restores them with one click.",
    defaults    = {
        enabled         = true,
        restoreMacros   = true,
        restoreBindings = true,
        -- The snapshots themselves are NOT here -- see library() below.
    },
})

-- Appear as a TAB of Global Settings instead of a sidebar row. The framework
-- reads this field in four places: the sidebar skips the row, the dashboard
-- skips the toggle, clicking through to this module opens the container and
-- selects the tab, and BuildOptionsPage redirects "vulslot" to
-- ("globalsettings", "vulslot"). The tab id in GlobalSettings must therefore
-- stay equal to this module's key.
mod.parentTab = "globalsettings"

-- name -> snapshot, account-wide. A snapshot records the class it was taken on
-- and loadProfile only warns when it does not match -- shared data, so it lives
-- in db.global rather than once per profile.
local function library()
    local g = ns.db and ns.db.global
    if not g then return {} end          -- before InitDB: no store, no crash
    g.vulslotProfiles = g.vulslotProfiles or {}
    return g.vulslotProfiles
end

local MAX_SLOTS = 120

local function accountMacroCap()
    return _G.MAX_ACCOUNT_MACROS or 120
end
local function characterMacroCap()
    return _G.MAX_CHARACTER_MACROS or 30
end

-- Blizzard's own macro UI never asks for an index by name, and the client does
-- not document such a call, so the lookup is done here: cheap, and one less
-- global to be wrong about.
local function macroIndexByName(name)
    if not name then return 0 end
    -- Both blocks are walked in full: the account block has holes at its end,
    -- and the character block starts after them.
    for i = 1, accountMacroCap() + characterMacroCap() do
        if GetMacroInfo(i) == name then return i end
    end
    return 0
end

local function spellName(id)
    local info = id and C_Spell.GetSpellInfo(id)
    return info and info.name or nil
end

local function snapshotActions()
    local out = {}
    for slot = 1, MAX_SLOTS do
        local t, id = GetActionInfo(slot)
        if t == "spell" and id then
            out[slot] = { type = "spell", id = id, name = spellName(id) }
        elseif t == "macro" and id then
            local name = GetMacroInfo(id)
            if name then out[slot] = { type = "macro", name = name } end
        elseif t == "item" and id then
            out[slot] = { type = "item", id = id, name = C_Item.GetItemInfo(id) }
        end
    end
    return out
end

local function snapshotMacros()
    local out = {}
    local cap = accountMacroCap() + characterMacroCap()
    for i = 1, cap do
        local name, icon, body = GetMacroInfo(i)
        if name then
            out[#out + 1] = {
                name    = name,
                icon    = icon,
                body    = body,
                perchar = i > accountMacroCap(),
            }
        end
    end
    return out
end

local function snapshotBindings()
    local out = {}
    for i = 1, (GetNumBindings and GetNumBindings() or 0) do
        local command = GetBinding(i)
        if command and type(command) == "string" then
            local k1, k2 = GetBindingKey(command)
            if k1 or k2 then
                out[#out + 1] = { command = command, k1 = k1, k2 = k2 }
            end
        end
    end
    return out
end

-- The counterpart to the three snapshots above, for data that did NOT come from
-- this client. An imported setup was written by a stranger, and every step of
-- the restore INDEXES its entries -- saved.type, m.name, b.command. A number
-- where a table belongs throws in the middle of the run, with part of the bars
-- already changed and no way back.
--
-- Bad entries are DROPPED, not the whole setup: one broken row is no reason to
-- refuse the other hundred, and the load report shows the gap as skipped slots.
local VALID_ACTION = { spell = true, item = true, macro = true }

local function sanitizeSetup(d)
    if type(d) ~= "table" then return nil end
    local out = { actions = {}, macros = {}, bindings = {} }

    if type(d.class) == "string" then out.class = d.class end

    if type(d.actions) == "table" then
        for slot, e in pairs(d.actions) do
            if type(slot) == "number" and slot == math.floor(slot)
                and slot >= 1 and slot <= MAX_SLOTS
                and type(e) == "table" and VALID_ACTION[e.type] then
                out.actions[slot] = {
                    type = e.type,
                    id   = type(e.id) == "number" and e.id or nil,
                    name = type(e.name) == "string" and e.name or nil,
                }
            end
        end
    end

    if type(d.macros) == "table" then
        for _, m in ipairs(d.macros) do
            if type(m) == "table" and type(m.name) == "string" and m.name ~= "" then
                -- The icon is a file id on some clients and a path on others,
                -- so both shapes are legal here; anything else is dropped and
                -- restoreMacros falls back to its question mark.
                local icon = (type(m.icon) == "string" or type(m.icon) == "number") and m.icon or nil
                out.macros[#out.macros + 1] = {
                    name    = m.name,
                    icon    = icon,
                    body    = type(m.body) == "string" and m.body or "",
                    perchar = m.perchar and true or false,
                }
            end
        end
    end

    if type(d.bindings) == "table" then
        for _, b in ipairs(d.bindings) do
            if type(b) == "table" and type(b.command) == "string" and b.command ~= "" then
                local k1 = type(b.k1) == "string" and b.k1 or nil
                local k2 = type(b.k2) == "string" and b.k2 or nil
                -- A command whose keys did not survive the check is DROPPED, not
                -- kept keyless. restoreBindings frees every listed command's
                -- CURRENT keys in its first pass and binds back only what the
                -- entry carries -- so a keyless entry out of a hand-made or
                -- damaged string would strip the player's own key for that
                -- command and then save it that way, permanently.
                if k1 or k2 then
                    out.bindings[#out.bindings + 1] = {
                        command = b.command,
                        k1 = k1,
                        k2 = k2,
                    }
                end
            end
        end
    end

    return out
end

local function saveProfile(name)
    local _, class = UnitClass("player")
    local actions  = snapshotActions()
    local macros   = snapshotMacros()
    local bindings = snapshotBindings()
    library()[name] = {
        class    = class,
        actions  = actions,
        macros   = macros,
        bindings = bindings,
    }

    -- Say what went IN, not just that something did. Counting the slots rather
    -- than trusting a length: actions is keyed by slot number and full of
    -- holes, so # would answer nonsense.
    local slots = 0
    for _ in pairs(actions) do slots = slots + 1 end
    ns:Print(L["Bar setup '%s' saved: %d slots, %d macros, %d key bindings."],
        name, slots, #macros, #bindings)
    if #bindings == 0 then
        ns:Print(L["|cffff8800No key bindings were captured.|r This client may not report them."])
    end
end

local function restoreMacros(list, keepExisting)
    local edited, created, failed, kept = 0, 0, 0, 0
    ClearCursor()
    for _, m in ipairs(list or {}) do
        local idx = macroIndexByName(m.name)
        if idx > 0 then
            -- An IMPORTED setup never rewrites a macro that is already there.
            -- Macros are matched by NAME, and names like Pull or Burst belong to
            -- everyone -- a stranger's setup would otherwise replace the BODY of
            -- yours. Your own setups keep overwriting: there the match is
            -- exactly the point.
            if keepExisting then
                kept = kept + 1
            else
                local ok = pcall(EditMacro, idx, m.name, m.icon, m.body)
                if ok then edited = edited + 1 else failed = failed + 1 end
            end
        else
            local ok, newId = pcall(CreateMacro, m.name,
                m.icon or "INV_MISC_QUESTIONMARK", m.body, m.perchar)
            if ok and newId then created = created + 1 else failed = failed + 1 end
        end
    end
    return edited + created, failed, kept
end

local function restoreSlot(slot, saved, counts)
    local curType, curId = GetActionInfo(slot)

    if not saved then
        if curType then
            PickupAction(slot)
            ClearCursor()
            counts.cleared = counts.cleared + 1
        end
        return
    end

    -- Skip when the slot already matches (no flicker, no churn)
    if saved.type == "spell" and curType == "spell" and curId == saved.id then return end
    if saved.type == "item"  and curType == "item"  and curId == saved.id then return end
    if saved.type == "macro" and curType == "macro" and curId then
        local curName = GetMacroInfo(curId)
        if curName == saved.name then return end
    end

    ClearCursor()
    if saved.type == "spell" then
        -- By ID first, by name second: a setup from another client carries
        -- that client's spell IDs, and the name is what both have in common.
        if saved.id then pcall(C_Spell.PickupSpell, saved.id) end
        if not GetCursorInfo() and saved.name then
            pcall(C_Spell.PickupSpell, saved.name)
        end
    elseif saved.type == "macro" then
        local idx = macroIndexByName(saved.name)
        if idx > 0 then PickupMacro(idx) end
    elseif saved.type == "item" then
        if saved.id then pcall(C_Item.PickupItem, saved.id) end
    end

    if GetCursorInfo() then
        PlaceAction(slot)   -- previous content lands on the cursor
        ClearCursor()
        counts.placed = counts.placed + 1
    else
        -- spell unknown / item not owned / macro missing: keep what's there
        counts.skipped = counts.skipped + 1
    end
end

-- Returns applied, unknown: SetBinding answers false for a command this client
-- has no action of that name for, which is what a setup from another client
-- brings along. Those are counted and named, not silently lost.
local function restoreBindings(list)
    list = list or {}
    -- Pass 1 (free): clear each managed command's CURRENT keys *and* every key
    -- the snapshot wants -- whoever currently holds it. This makes the restore
    -- exact and order-independent: nothing foreign keeps a snapshot key, and
    -- no managed command keeps a stale extra key. Keys outside the snapshot
    -- are left alone.
    for _, b in ipairs(list) do
        local c1, c2 = GetBindingKey(b.command)
        if c1 then SetBinding(c1) end
        if c2 then SetBinding(c2) end
        if b.k1 then SetBinding(b.k1) end
        if b.k2 then SetBinding(b.k2) end
    end
    -- Pass 2 (bind): apply the snapshot's key -> command map onto the now-free keys
    local applied, unknown = 0, {}
    for _, b in ipairs(list) do
        local ok1 = b.k1 and SetBinding(b.k1, b.command)
        local ok2 = b.k2 and SetBinding(b.k2, b.command)
        if ok1 or ok2 then
            applied = applied + 1
        else
            unknown[#unknown + 1] = b.command
        end
    end
    if SaveBindings then
        SaveBindings((GetCurrentBindingSet and GetCurrentBindingSet()) or 2)
    end
    return applied, unknown
end

local function doLoadProfile(name)
    local p = library()[name]
    if not p then return end
    if ns:InCombat() then
        ns:Print(L["Not in combat — bars can't be changed while fighting."])
        return
    end

    local _, class = UnitClass("player")
    if p.class and p.class ~= class then
        ns:Print(L["Note: profile '%s' was saved on another class (%s)."], name, p.class)
    end

    -- Order matters: macros first so slots can resolve them by name. Every
    -- step reports its counts, and a switch that is off is said out loud:
    -- "nothing happened" is not an answer anyone can act on.
    if p.macros and #p.macros > 0 then
        if not mod.db.restoreMacros then
            ns:Print(L["Macros left alone: the switch above is off."])
        else
            local done, failed, kept = restoreMacros(p.macros, p.imported)
            if (failed or 0) > 0 then
                ns:Print(L["Macros: %d restored, |cffff8800%d failed|r -- the macro list may be full."],
                    done or 0, failed)
            elseif (kept or 0) > 0 then
                ns:Print(L["Macros: %d restored, %d of your own kept (an import does not rewrite them)."],
                    done or 0, kept)
            else
                ns:Print(L["Macros: %d restored."], done or 0)
            end
        end
    end

    local counts = { placed = 0, cleared = 0, skipped = 0 }
    for slot = 1, MAX_SLOTS do
        restoreSlot(slot, p.actions and p.actions[slot], counts)
    end

    if p.bindings and #p.bindings > 0 then
        if not mod.db.restoreBindings then
            ns:Print(L["Key bindings left alone: the switch above is off."])
        else
            local applied, unknown = restoreBindings(p.bindings)
            if #unknown > 0 then
                ns:Print(L["Key bindings: %d applied, |cffff8800%d skipped|r -- this client has no such action: %s"],
                    applied, #unknown, table.concat(unknown, ", "))
            else
                ns:Print(L["Key bindings: %d applied."], applied)
            end
        end
    end

    if counts.skipped > 0 then
        ns:Print(L["Bar setup '%s' loaded: %d slots set, %d cleared, |cffff8800%d skipped|r (unknown spell / missing item or macro)."],
            name, counts.placed, counts.cleared, counts.skipped)
    else
        ns:Print(L["Bar setup '%s' loaded: %d slots set, %d cleared."],
            name, counts.placed, counts.cleared)
    end
end

-- Loading is a write with no way back: 120 slots are set, and every slot the
-- setup does not carry is CLEARED. So it is asked first.
--
-- The NAME is remembered, not the table: the list can be imported into or
-- deleted from while the dialog stands, and a name that is gone by then simply
-- does nothing. Armed only once the dialog IS up -- a second question reuses
-- the same dialog, and the reuse wipes a record armed before the call.
local pendingLoad

ns.OnLocaleReady(function()
    StaticPopupDialogs["VFUI_VULSLOT_LOAD"] = {
        text           = L["Load '%s'? Every button on your bars is overwritten or cleared."],
        button1        = YES or "Yes",
        button2        = NO or "No",
        timeout        = 0,
        whileDead      = true,
        hideOnEscape   = true,
        preferredIndex = 3,
        OnAccept = function()
            local n = pendingLoad
            pendingLoad = nil
            if n then doLoadProfile(n) end
        end,
        OnCancel = function() pendingLoad = nil end,
        OnHide   = function() pendingLoad = nil end,
    }
end)

local function loadProfile(name)
    if not library()[name] then return end
    -- Refused before the question, not after it: a fight is no state to ask in.
    if ns:InCombat() then
        ns:Print(L["Not in combat — bars can't be changed while fighting."])
        return
    end
    if not (StaticPopupDialogs and StaticPopupDialogs["VFUI_VULSLOT_LOAD"]
        and StaticPopup_Show) then
        doLoadProfile(name)
        return
    end
    local dialog = StaticPopup_Show("VFUI_VULSLOT_LOAD", name)
    if not dialog then return end
    pendingLoad = name
end

-- Pure on-demand module: nothing to wire up in lifecycle
function mod:OnEnable() end
function mod:OnDisable() end

local newName  = ""
local selected = nil

local function sortedProfileNames()
    local names = {}
    for n in pairs(library()) do names[#names + 1] = n end
    table.sort(names)
    return names
end

local function rebuildPage()
    if ns.UI and ns.UI.BuildOptionsPage then
        ns.UI:BuildOptionsPage("vulslot")
    end
end

function mod:GetOptions()
    local names = sortedProfileNames()
    if selected and not library()[selected] then selected = nil end
    if not selected and names[1] then selected = names[1] end

    local values = {}
    for _, n in ipairs(names) do
        local p = library()[n]
        local suffix = (p and p.class) and (" |cff888888(" .. p.class .. ")|r") or ""
        values[#values + 1] = { value = n, text = n .. suffix }
    end

    local function doSave()
        local n = newName:gsub("^%s+", ""):gsub("%s+$", "")
        if n == "" then
            ns:Print(L["Please enter a profile name first."])
            return
        end
        saveProfile(n)
        newName  = ""
        selected = n
        rebuildPage()
    end

    local items = {
        { type = "header", text = L["Bar Setups"] },
        { type = "desc",
          text = L["|cffaaaaaaSaves your complete bar setup (all action slots, macros, keybindings) as a named profile and restores it with one click — e.g. PvP and Raid layouts, or to copy a setup to a twink (account-wide storage).|r"] },
        { type = "spacer", height = 6 },

        { type = "header", text = L["Save"] },
        { type = "group", layout = "row", gap = 8, items = {
            { type = "editbox", label = L["Name"], width = 260, editWidth = 180,
              commitOnFocusLost = true,
              get = function() return newName end,
              set = function(_, v) newName = tostring(v or "") end,
              onEnter = function() doSave() end },
            { type = "button", label = L["Save current setup"], width = 180, primary = true,
              onClick = function() doSave() end },
        } },
        { type = "spacer", height = 8 },

        { type = "header", text = L["Load"] },
    }

    if #values == 0 then
        items[#items + 1] = { type = "desc",
            text = L["|cff888888No profiles saved yet.|r"] }
    else
        items[#items + 1] = { type = "dropdown", label = L["Profile"], width = 260,
            values = values,
            get = function() return selected end,
            set = function(_, v) selected = v end }
        items[#items + 1] = { type = "toggle", label = L["Also restore macros"],
            tooltip = L["Rewrites saved macros by name (existing ones are updated, missing ones created)."],
            get = function() return mod.db.restoreMacros end,
            set = function(_, v) mod.db.restoreMacros = v end }
        items[#items + 1] = { type = "toggle", label = L["Also restore keybindings"],
            get = function() return mod.db.restoreBindings end,
            set = function(_, v) mod.db.restoreBindings = v end }
        items[#items + 1] = { type = "spacer", height = 4 }
        items[#items + 1] = { type = "group", layout = "row", gap = 8, items = {
            { type = "button", label = L["Load profile"], width = 150, primary = true,
              onClick = function()
                  if selected then loadProfile(selected) end
              end },
            { type = "button", label = L["Overwrite with current setup"], width = 220,
              tooltip = L["Replaces the selected profile with your current bars/macros/bindings."],
              onClick = function()
                  if selected then saveProfile(selected) end
              end },
            { type = "button", label = L["Delete"], width = 110,
              onClick = function()
                  if selected then
                      library()[selected] = nil
                      ns:Print(L["Bar setup '%s' deleted."], selected)
                      selected = nil
                      rebuildPage()
                  end
              end },
        } }
        items[#items + 1] = { type = "spacer", height = 4 }
        items[#items + 1] = {
            type = "button", label = L["Export as string"], width = 180,
            tooltip = L["Packs the selected bar setup into a string you can pass on. Slots, macros and key bindings travel with it."],
            onClick = function()
                if not selected then return end
                local setup = library()[selected]
                if not setup then return end
                -- Its own prefix pair, not the profile's: the two strings must
                -- never be mistakable for one another.
                local str = ns:EncodeShareString("!VBAR1", "!VBAR2",
                    { v = 1, n = selected, d = setup })
                if str and ns.UI and ns.UI.ShowProfileExportDialog then
                    ns.UI:ShowProfileExportDialog(str)
                end
            end }
    end

    -- Import stands OUTSIDE the "is there anything saved" branch: an empty
    -- library is exactly when someone wants to read a setup in.
    items[#items + 1] = {
        type = "button", label = L["Import from string"], width = 180,
        tooltip = L["Reads a bar setup string into your library. Putting it onto your bars stays a separate step."],
        onClick = function()
            if not (ns.UI and ns.UI.ShowStringImportDialog) then return end
            ns.UI:ShowStringImportDialog(L["Import from string"], function(text)
                local payload, why = ns:DecodeShareString("!VBAR1", "!VBAR2", text)
                if not payload then
                    return (why == "damaged") and L["The bar setup string is damaged."]
                        or L["This is not a bar setup string."]
                end
                -- Nothing from the string is stored as it arrived: sanitizeSetup
                -- rebuilds it entry by entry, so the restore can only ever walk
                -- shapes it knows.
                local d = sanitizeSetup(payload.d)
                if not d or (not next(d.actions)
                    and #d.macros == 0 and #d.bindings == 0) then
                    return L["The bar setup string is damaged."]
                end
                -- Marked as foreign, and it stays marked: restoreMacros reads
                -- this to leave macros of your own alone. Saving over the setup
                -- later builds a fresh table without the flag, which is right --
                -- from then on it is yours.
                d.imported = true
                local name = (type(payload.n) == "string" and payload.n ~= "")
                    and payload.n or L["Imported"]
                -- Never overwrite silently. Someone else's setup arriving under
                -- a name you already use must not eat yours.
                local base, n = name, 2
                while library()[name] do
                    name = base .. " " .. n
                    n = n + 1
                end
                library()[name] = d
                selected = name
                ns:Print(L["Bar setup '%s' imported."], name)
                rebuildPage()
            end)
        end }

    return items
end
