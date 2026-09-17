-- Factory collapsing a sidebar group into one tabbed entry. A container file MUST be listed in the .toc AFTER every module in its group, so the ns.moduleOrder scan sees them all.
local _, ns = ...
local L = ns.L

-- opts.group        where the container's own ROW appears in the sidebar
-- opts.memberGroup  which modules it swallows as tabs (defaults to opts.group)
-- opts.memberGroups a LIST of groups instead, for a container that collects
--                   several categories into one row (the "General" collection)
--
-- group/memberGroup were one field while there was one container per sidebar
-- group. Four containers under a single header need them apart: the row lives
-- under "Tools" while each one collects a different category.
function ns:MakeGroupContainer(opts)
    local memberOf = {}
    if opts.memberGroups then
        for _, g in ipairs(opts.memberGroups) do memberOf[g] = true end
    else
        memberOf[opts.memberGroup or opts.group] = true
    end

    local mod = ns:RegisterModule(opts.key, {
        name         = opts.name,
        group        = opts.group,
        sidebarOrder = opts.sidebarOrder,
        description  = "",   -- per-tab description is shown instead
        defaults     = { enabled = true },
    })

    mod.tabs    = {}
    mod.subKeys = {}
    local exclude = opts.exclude or {}
    local function addTab(key, sub)
        mod.tabs[#mod.tabs + 1]       = { id = key, label = sub.name }
        mod.subKeys[#mod.subKeys + 1] = key
        sub.parentTab = opts.key
    end

    if opts.firstKey then
        local f = ns.modules[opts.firstKey]
        if f and memberOf[f.group] then addTab(opts.firstKey, f) end
    end
    for _, key in ipairs(ns.moduleOrder) do
        local sub = ns.modules[key]
        if sub and memberOf[sub.group]
           and key ~= opts.key and key ~= opts.firstKey and not exclude[key] then
            addTab(key, sub)
        end
    end

    -- A tab is not always a module of its own: some front several real ones and
    -- carry their own toggleGet/toggleSet, which is the only pair that reaches
    -- the members. Cascading through the plain enable flag flipped a shell with
    -- no lifecycle while everything behind it kept running.
    local function subEnabled(key)
        local sub = ns.modules[key]
        if sub and sub.toggleGet then return sub.toggleGet() and true or false end
        return ns:IsModuleEnabled(key) and true or false
    end

    local function setSubEnabled(key, v)
        local sub = ns.modules[key]
        if sub and sub.toggleSet then sub.toggleSet(v, true) else ns:ToggleModule(key, v, true) end
    end

    function mod.toggleGet()
        for _, key in ipairs(mod.subKeys) do
            if subEnabled(key) then return true end
        end
        return false
    end

    -- Switching OFF remembers each sub-module's state so switching back ON restores it.
    function mod.toggleSet(v)
        -- per-character saved-state memory (enable is a per-char preference)
        local store
        if VuloForeverUICharDB then
            VuloForeverUICharDB.containerSaved = VuloForeverUICharDB.containerSaved or {}
            store = VuloForeverUICharDB.containerSaved
        end
        if v then
            local saved = store and store[opts.key]
            for _, key in ipairs(mod.subKeys) do
                local want = (saved == nil) and true or (saved[key] and true or false)
                setSubEnabled(key, want)
            end
            if store then store[opts.key] = nil end
            ns:Print(L["%s: modules restored."], L[opts.name])
        else
            local saved = {}
            for _, key in ipairs(mod.subKeys) do
                saved[key] = subEnabled(key)
                setSubEnabled(key, false)
            end
            if store then store[opts.key] = saved end
            ns:Print(L["%s: all modules off. /reload recommended."], L[opts.name])
        end
        if ns.UI then
            if ns.UI.RefreshSidebarStates then ns.UI:RefreshSidebarStates() end
            if ns.UI.currentModule == opts.key and ns.UI.currentTab then
                ns.UI:BuildOptionsPage(opts.key, ns.UI.currentTab)
            end
        end
    end

    function mod:GetOptions(tabId)
        local sub = tabId and ns.modules[tabId]
        if not sub then
            return { { type = "desc", text = L["|cffaaaaaaPick a tab above.|r"] } }
        end

        local items = {}

        items[#items + 1] = {
            type = "toggle", label = L["Module enabled"],
            -- A tab can front several real modules instead of being one itself.
            -- Those carry their own toggleGet/toggleSet, and that pair is the
            -- only thing that reaches the members. Going through ToggleModule
            -- alone flipped a pseudo-module with no lifecycle of its own: the
            -- switch read off, survived reloads, and every member kept running.
            -- The sidebar and the dashboard already prefer these.
            get = sub.toggleGet or function() return ns:IsModuleEnabled(tabId) end,
            set = function(_, v)
                if sub.toggleSet then sub.toggleSet(v) else ns:ToggleModule(tabId, v) end
                if ns.UI then
                    if ns.UI.RefreshSidebarStates then ns.UI:RefreshSidebarStates() end
                    ns.UI:BuildOptionsPage(opts.key, tabId)
                end
            end,
        }
        items[#items + 1] = { type = "spacer", height = 8 }

        if sub.description and sub.description ~= "" then
            items[#items + 1] = { type = "desc", text = L[sub.description] }
            items[#items + 1] = { type = "spacer", height = 6 }
        end

        -- a broken sub-module GetOptions must not take down the whole page
        if sub.GetOptions then
            local ok, subItems = pcall(function() return sub:GetOptions() end)
            if ok and type(subItems) == "table" then
                for _, it in ipairs(subItems) do items[#items + 1] = it end
            else
                items[#items + 1] = { type = "desc", text = L["|cffff5555This tab failed to load.|r"] }
            end
        end
        return items
    end

    return mod
end
