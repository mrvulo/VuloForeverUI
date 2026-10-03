-- VuloForeverUI / UI / OptionsBuilder / Reveal: finding a row again: active module, expand, scroll to section, reveal and flash a row, recently changed.
local _, ns = ...
local UI = ns.UI
local OB = UI._OB
local COMPACT = OB.COMPACT

-- True if the module's options are on screen, directly or as its container's active tab.
function UI:IsModuleActive(key)
    if UI.currentModule == key then return true end
    local m = ns.modules[key]
    if not m then return false end
    if m.parentTab and UI.currentModule == m.parentTab and UI.currentTab == key then
        return true
    end
    -- A page member has no page of its own: it is rendered as a section of its
    -- page, which is itself a tab of a container. Without this the answer was
    -- always no, so those modules never redrew their own options and lists that
    -- an Add or Remove button had just changed stayed stale.
    if m._pageKey and (UI.currentTab == m._pageKey or UI.currentModule == m._pageKey) then
        return true
    end
    return false
end

-- Scrolls the open page so the named section's heading sits at the top edge.
-- Open a gear row from OUTSIDE the page (a preview's click-to-navigate). The
-- suffix is the row's subKey (or its label, for rows without one) -- the same
-- tail rowKey builds, so a module needs no knowledge of the full recipe.
-- Only opens; a second click on a preview icon should not close settings the
-- user is looking at.
function UI:ExpandRow(subKey)
    UI.rowExpanded[(UI._currentBuildKey or "?") .. "/" .. (UI.currentTab or "")
        .. "/r/" .. tostring(subKey)] = true
end

-- Consumer: the action-bar preview's click-to-navigate; the title must be the
-- TRANSLATED section title, exactly as the page declared it.
function UI:ScrollToSection(title)
    local f = UI.mainFrame
    local off = f and UI._sectionY and UI._sectionY[title]
    if not off then return end
    local maxOff = math.max(0,
        (f.scrollChild:GetHeight() or 0) - (f.scroll:GetHeight() or 0))
    f.scroll:SetVerticalScroll(math.min(off, maxOff))
end

-- ---------------------------------------------------------------------------
-- Reveal a row: open its page, unfold what hides it, scroll to it, light it up.
-- Used by the settings search and by the "recently changed" list. The target
-- carries what those two know: { mod, tab, label | subKey, parents = { gear
-- row labels above it }, sectionKey (collapsible section holding it),
-- sectionClosed, section (title, the fallback when the row is not found) }.
-- ---------------------------------------------------------------------------
local function flashRow(p)
    local fl = OB.flashFrame
    if not fl then
        fl = CreateFrame("Frame", nil, UIParent)
        fl:EnableMouse(false)
        local fill = fl:CreateTexture(nil, "ARTWORK")
        fill:SetAllPoints(fl)
        fl._fill = fill
        fl._edges = {}
        for i, s in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
            local t = fl:CreateTexture(nil, "OVERLAY")
            if s == "TOP" or s == "BOTTOM" then
                t:SetPoint(s .. "LEFT"); t:SetPoint(s .. "RIGHT"); t:SetHeight(2)
            else
                t:SetPoint("TOP" .. s); t:SetPoint("BOTTOM" .. s); t:SetWidth(2)
            end
            fl._edges[i] = t
        end
        -- Two pulses and a long fade: enough to draw the eye to where the
        -- page stopped, gone before it becomes decoration.
        local ag = fl:CreateAnimationGroup()
        local function step(order, from, to, dur)
            local a = ag:CreateAnimation("Alpha")
            a:SetFromAlpha(from); a:SetToAlpha(to); a:SetDuration(dur); a:SetOrder(order)
        end
        step(1, 0, 1, 0.12); step(2, 1, 0.25, 0.30); step(3, 0.25, 1, 0.12); step(4, 1, 0, 1.2)
        ag:SetScript("OnFinished", function() fl:Hide() end)
        fl._anim = ag
        OB.flashFrame = fl
    end
    if fl._anim:IsPlaying() then fl._anim:Stop() end
    local a = ns.COLORS.accent
    fl._fill:SetColorTexture(a.r, a.g, a.b, 0.14)
    for _, t in ipairs(fl._edges) do t:SetColorTexture(a.r, a.g, a.b, 0.9) end
    -- Inside the scroll child, so the scroll frame clips it like the row.
    fl:SetParent(p:GetParent())
    fl:SetFrameLevel((p:GetFrameLevel() or 1) + 8)
    fl:ClearAllPoints()
    fl:SetPoint("TOPLEFT",     p, "TOPLEFT",     -3,  3)
    fl:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT",  3, -3)
    fl:SetAlpha(0)
    fl:Show()
    fl._anim:Play()
end

function UI:RevealRow(t)
    if type(t) ~= "table" or not t.mod or not ns.modules[t.mod] then return end
    local f = UI:CreateMainFrame()
    if not f:IsShown() then UI:ToggleMainFrame() end
    UI:ShowModulePage(t.mod)
    if t.tab and t.tab ~= "default" and UI.currentTab ~= t.tab then
        -- Only a tab the page really has: a stale record would otherwise
        -- build an empty page under a tab that no longer exists.
        local m = ns.modules[UI.currentModule]
        if m and m.tabs then
            for _, tb in ipairs(m.tabs) do
                if tb.id == t.tab then UI:ShowTab(t.tab); break end
            end
        end
    end
    local prefix = (UI._currentBuildKey or "?") .. "/" .. (UI.currentTab or "")
    local rk = prefix .. "/r/" .. tostring(t.subKey or t.label)
    local rebuild = false
    if t.parents then
        for _, pl in ipairs(t.parents) do
            local k = prefix .. "/r/" .. tostring(pl)
            if not UI.rowExpanded[k] then UI.rowExpanded[k] = true; rebuild = true end
        end
    end
    if t.sectionKey then
        local k = prefix .. "/s/" .. tostring(t.sectionKey)
        if UI.sectionOpen[k] == false or (UI.sectionOpen[k] == nil and t.sectionClosed) then
            UI.sectionOpen[k] = true; rebuild = true
        end
    end
    -- The changed-only filter must not hide the very row that was asked for.
    if UI.onlyChanged and not UI._rowFrames[rk] then
        UI.onlyChanged = false; rebuild = true
    end
    if rebuild then UI:BuildOptionsPage(UI._currentBuildKey, UI.currentTab) end
    local buildKey, buildTab = UI._currentBuildKey, UI.currentTab
    -- Next frame: the rows were anchored this frame and measure against a
    -- scroll child whose height was set a moment ago.
    ns.NextFrame(function()
        if not (f:IsShown() and UI._currentBuildKey == buildKey and UI.currentTab == buildTab) then return end
        local p = UI._rowFrames[rk]
        local top, ctop = p and p:GetTop(), f.scrollChild:GetTop()
        if p and p:IsShown() and top and ctop then
            local maxOff = math.max(0, (f.scrollChild:GetHeight() or 0) - (f.scroll:GetHeight() or 0))
            f.scroll:SetVerticalScroll(math.max(0, math.min(ctop - top - 40, maxOff)))
            flashRow(p)
        elseif t.section then
            UI:ScrollToSection(t.section)
        end
        if UI.UpdateNavActive then UI:UpdateNavActive() end
    end)
end

-- ---------------------------------------------------------------------------
-- Recently changed: every setter on the page reports into an account-wide
-- ring, newest first, so the overview can list what was touched last and jump
-- back to it. Sliders report on every drag step; the ring dedupes by row, so
-- one row is one entry however long the drag was.
-- ---------------------------------------------------------------------------
local RECENT_CHANGES_MAX = 12
local function noteChange(rec)
    local g = ns.db and ns.db.global
    if not g then return end
    local list = g.recentChanges
    if type(list) ~= "table" then list = {}; g.recentChanges = list end
    for i = #list, 1, -1 do
        local e = list[i]
        if type(e) == "table" and e.mod == rec.mod and e.tab == rec.tab
           and e.label == rec.label and e.subKey == rec.subKey then
            table.remove(list, i)
        end
    end
    table.insert(list, 1, rec)
    for i = #list, RECENT_CHANGES_MAX + 1, -1 do table.remove(list, i) end
end

local function wrapRecent(items, modKey, tabId, skip)
    if skip then return end
    local function wrap(list, section, parents)
        for _, it in ipairs(list) do
            if type(it) == "table" then
                if it.type == "section" then
                    wrap(it.items or {}, it.title, parents)
                else
                    if it.items then wrap(it.items, section, parents) end
                    if it.subOptions then
                        local chain = {}
                        for i, v in ipairs(parents) do chain[i] = v end
                        chain[#chain + 1] = it.subKey or it.label
                        wrap(it.subOptions, section, chain)
                    end
                    if COMPACT[it.type] and type(it.set) == "function" and it.label
                       and not it._vcRecentWrapped then
                        it._vcRecentWrapped = true
                        local setter = it.set
                        -- Stored by ENGLISH key, never by the translated text
                        -- (the house rule in Core/Locale.lua): the overview
                        -- translates on display, and a language switch keeps
                        -- every entry readable and reachable.
                        local ek = ns.EnglishKey and function(s) return ns:EnglishKey(s) end
                            or function(s) return s end
                        local label, subKey = ek(it.label), it.subKey
                        local chain
                        if #parents > 0 then
                            chain = {}
                            for i, v in ipairs(parents) do chain[i] = ek(v) end
                        end
                        local sectionKey = section and ek(section) or nil
                        it.set = function(...)
                            setter(...)
                            noteChange({ mod = modKey, tab = tabId, label = label, subKey = subKey,
                                section = sectionKey, parents = chain, t = time() })
                        end
                    end
                end
            end
        end
    end
    wrap(items, nil, {})
end

-- for the OptionsBuilder files loaded after this one
OB.wrapRecent = wrapRecent
