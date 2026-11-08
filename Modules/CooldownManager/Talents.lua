-- VuloForeverUI / Modules / CooldownManager / Talents
--
-- Talent conditions on a row: show an icon only WITH a chosen talent, or only
-- WITHOUT it. A spell that a talent replaces, or one that is only worth a
-- slot in one build, keeps its place on the bar and simply steps aside while
-- the build does not fit it.
--
-- Stored on the row as `talents = { [nodeID] = true | false }`: true = only
-- with this talent, false = only without it. Node ids belong to the class
-- tree, so a row keeps its conditions across reloads and respecs.
--
-- Where the talents come from: Forever has no GetTalentInfo. Its three trees
-- are one C_Traits tree (config type CamelotCombat) whose nodes sit in three
-- node GROUPS, one per tree -- the client's own talent frame names its tree
-- headers from GetGroupDisplayInfoByTreeID the same way.
--
-- Talents cannot change in combat, so everything here is read out of combat,
-- cached, and dropped when the client says the build changed.
local _, ns = ...
local L  = ns.L
local CM = ns.CM

local T = {}
CM.Talents = T

local cache       -- { trees = { {name, icon, items = { {node, name, icon} } } } }
local known       -- [nodeID] = true | false; nil while the client did not answer
local stale       -- the build changed in combat; reread once it ends
local pendingRestyle

local function num(v)
    return type(v) == "number" and ns.CanRead(v) and v or nil
end

-- The config the character plays with right now: the combat config of the
-- active spec group, the way the client's talent frame finds it.
local function configID()
    local S = C_SpecializationInfo
    if S and S.GetActiveSpecGroup and S.GetCombatConfigIDForSpecGroup then
        local ok, group = pcall(S.GetActiveSpecGroup)
        if ok and num(group) then
            local ok2, id = pcall(S.GetCombatConfigIDForSpecGroup, group)
            if ok2 and num(id) then return id end
        end
    end
    if C_ClassTalents and C_ClassTalents.GetActiveConfigID then
        local ok, id = pcall(C_ClassTalents.GetActiveConfigID)
        if ok and num(id) then return id end
    end
    return nil
end

local function nodeSpell(cfg, info)
    local entryID = info.activeEntry and info.activeEntry.entryID
        or (type(info.entryIDs) == "table" and info.entryIDs[1])
    if not num(entryID) then return nil end
    local okE, entry = pcall(C_Traits.GetEntryInfo, cfg, entryID)
    if not (okE and type(entry) == "table" and num(entry.definitionID)) then return nil end
    local okD, def = pcall(C_Traits.GetDefinitionInfo, entry.definitionID)
    if not (okD and type(def) == "table") then return nil end
    -- spellID is the talent itself; overriddenSpellID is the spell it
    -- REPLACES (the client's "Replaces X" line), not a name for it.
    local spellID = num(def.spellID)
    local name = def.overrideName
    if type(name) ~= "string" or name == "" then
        name = spellID and C_Spell.GetSpellName(spellID)
    end
    if type(name) ~= "string" or name == "" then return nil end
    local icon = def.overrideIcon
    if not num(icon) and spellID then icon = C_Spell.GetSpellTexture(spellID) end
    return name, icon
end

local function build()
    local cfg = configID()
    if not (cfg and C_Traits and C_Traits.GetConfigInfo) then return nil end
    local okC, config = pcall(C_Traits.GetConfigInfo, cfg)
    local treeID = okC and type(config) == "table" and type(config.treeIDs) == "table"
        and num(config.treeIDs[1])
    if not treeID then return nil end

    -- The three trees, in the client's order.
    local trees, byGroup = {}, {}
    local okG, groups = pcall(C_Traits.GetGroupDisplayInfoByTreeID, treeID)
    if okG and type(groups) == "table" then
        table.sort(groups, function(a, b) return (a.orderIndex or 0) < (b.orderIndex or 0) end)
        for _, g in ipairs(groups) do
            local tree = { name = g.displayName, icon = g.icon, items = {} }
            trees[#trees + 1] = tree
            byGroup[g.groupID] = tree
        end
    end
    local loose  -- nodes in no named tree; a fallback that should stay empty

    local okN, nodes = pcall(C_Traits.GetTreeNodes, treeID)
    if not (okN and type(nodes) == "table") then return nil end
    known = {}
    for _, nodeID in ipairs(nodes) do
        local okI, info = pcall(C_Traits.GetNodeInfo, cfg, nodeID)
        if okI and type(info) == "table" and info.isVisible ~= false then
            local name, icon = nodeSpell(cfg, info)
            if name then
                local tree
                for _, gid in ipairs(info.groupIDs or {}) do
                    tree = tree or byGroup[gid]
                end
                if not tree then
                    if not loose then
                        loose = { name = L["Talents"], items = {} }
                        trees[#trees + 1] = loose
                    end
                    tree = loose
                end
                tree.items[#tree.items + 1] = { node = nodeID, name = name, icon = icon,
                    x = num(info.posX) or 0, y = num(info.posY) or 0 }
                -- activeRank, the client's own "talent is on" test: it counts
                -- granted ranks and leaves out picks that are only staged.
                local ranks = num(info.activeRank)
                if ranks then known[nodeID] = ranks > 0 end
            end
        end
    end
    -- Top to bottom, left to right: the order the tree is read in.
    for _, tree in ipairs(trees) do
        table.sort(tree.items, function(a, b)
            if a.y ~= b.y then return a.y < b.y end
            return a.x < b.x
        end)
    end
    return { trees = trees }
end

-- Rebuilt on demand, never in combat. In a fight the last answer stands,
-- which is right: nothing can change it there.
--
-- A build that succeeds where there was none (login before the client had a
-- config, a change read late) can shorten a bar, and a shorter list painted
-- onto the old layout is drawn wrong: so the bars are laid out again, once,
-- on the next frame.
local function ensure()
    if cache then return cache end
    if ns:InCombat() then return nil end
    cache = build()
    if cache and not pendingRestyle then
        pendingRestyle = true
        ns.NextFrame(function()
            pendingRestyle = false
            if CM.db() then CM.RestyleAll() end
            if CM.RefreshPreview then CM.RefreshPreview() end
        end)
    end
    return cache
end

-- In combat the last answer is kept: a cleared one would let every row pass
-- for the rest of the fight, "without" rows included. It is reread when the
-- fight ends.
function T.Invalidate()
    if ns:InCombat() then stale = true; return end
    stale = nil
    cache, known = nil, nil
end

-- The trees with their talents, for the menu. nil when the client has none.
function T.Trees()
    local c = ensure()
    return c and c.trees or nil
end

-- Does this row's build fit? A row without conditions always does, and a
-- talent the client could not answer about never hides anything.
function T.Pass(entry)
    local want = type(entry) == "table" and entry.talents
    if type(want) ~= "table" or next(want) == nil then return true end
    ensure()
    if not known then return true end
    for nodeID, need in pairs(want) do
        local has = known[nodeID]
        if has ~= nil and has ~= need then return false end
    end
    return true
end

function T.Count(entry)
    local n = 0
    if type(entry) == "table" and type(entry.talents) == "table" then
        for _ in pairs(entry.talents) do n = n + 1 end
    end
    return n
end

-- ---------------------------------------------------------------- menu --

local function stateText(item, state)
    if state == true then
        return item.name .. "  |cff40d060(" .. L["with"] .. ")|r"
    elseif state == false then
        return item.name .. "  |cffe05050(" .. L["without"] .. ")|r"
    end
    return item.name
end

-- Root: one flyout per tree. A click on a talent walks it through
-- "does not matter" -> "only with" -> "only without".
function T.Menu(entry, onChange)
    local menu = { { text = L["Talent conditions"], title = true } }
    local trees = T.Trees()
    if not trees and ns:InCombat() then
        menu[#menu + 1] = { text = L["Talents can only be read out of combat"], disabled = true }
        return menu
    end
    if not trees or #trees == 0 then
        menu[#menu + 1] = { text = L["The client has no talents to offer yet"], disabled = true }
        return menu
    end
    for _, tree in ipairs(trees) do
        local sub = {}
        local set = 0
        for _, item in ipairs(tree.items) do
            local it = item
            local state = entry.talents and entry.talents[it.node]
            if state ~= nil then set = set + 1 end
            local row = { icon = it.icon, keepOpen = true, radio = true }
            row.text = stateText(it, state)
            row.checked = function() return entry.talents and entry.talents[it.node] ~= nil end
            row.func = function()
                local cur = entry.talents and entry.talents[it.node]
                local nxt
                if cur == nil then nxt = true elseif cur == true then nxt = false end
                if nxt ~= nil then
                    entry.talents = entry.talents or {}
                    entry.talents[it.node] = nxt
                elseif entry.talents then
                    entry.talents[it.node] = nil
                    if next(entry.talents) == nil then entry.talents = nil end
                end
                row.text = stateText(it, nxt)
                onChange()
            end
            sub[#sub + 1] = row
        end
        if #sub == 0 then sub[1] = { text = L["Nothing to add"], disabled = true } end
        local label = tree.name or L["Talents"]
        if set > 0 then label = ("%s  |cff777777(%d)|r"):format(label, set) end
        menu[#menu + 1] = { text = label, icon = tree.icon, submenu = sub }
    end
    menu[#menu + 1] = { separator = true }
    menu[#menu + 1] = { text = L["Click a talent: only with it, only without it, does not matter."],
        disabled = true }
    if T.Count(entry) > 0 then
        menu[#menu + 1] = { text = L["Clear talent conditions"], func = function()
            entry.talents = nil
            onChange()
        end }
    end
    return menu
end

-- The build changed: forget what we read. The bars that are up redraw from
-- Core's own handler; this one runs even while the module is off, so the
-- preview on the settings page never shows yesterday's build.
for _, event in ipairs({ "TRAIT_CONFIG_UPDATED", "TRAIT_CONFIG_LIST_UPDATED",
                         "PLAYER_TALENT_UPDATE", "ACTIVE_COMBAT_CONFIG_CHANGED",
                         "PLAYER_SPECIALIZATION_CHANGED" }) do
    ns:RegisterEvent(event, T.Invalidate)
end
ns:RegisterEvent("PLAYER_REGEN_ENABLED", function()
    if stale then
        T.Invalidate()
        if CM.db() then CM.RestyleAll() end
    end
end)
