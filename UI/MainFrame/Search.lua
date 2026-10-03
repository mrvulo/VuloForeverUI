-- VuloForeverUI / UI / MainFrame / Search: the settings search -- index, result list, keys -- and its slash entry.
local _, ns = ...
local L = ns.L
local UI = ns.UI
local MF = UI._MF

-- Part of UI:CreateMainFrame, called from it at the same point: the result list
-- under the search box, the search over every module's options and the keys.
function MF.BuildSearchResults(f, searchBox, placeholder)
    local searchDD = CreateFrame("Frame", nil, f)
    searchDD:SetSize(440, 200)
    searchDD:SetPoint("TOPRIGHT", searchBox, "BOTTOMRIGHT", 0, -2)
    searchDD:SetFrameStrata("FULLSCREEN_DIALOG")
    searchDD:SetFrameLevel(300)
    searchDD:Hide()

    UI:CreateShadow(searchDD)
    local ddBg = searchDD:CreateTexture(nil, "BACKGROUND")
    ddBg:SetAllPoints(searchDD)
    ddBg:SetColorTexture(ns.TC("input"))
    local ddBorder = CreateFrame("Frame", nil, searchDD, BackdropTemplateMixin and "BackdropTemplate")
    ddBorder:SetAllPoints(searchDD)
    if ddBorder.SetBackdrop then
        ddBorder:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        ddBorder:SetBackdropBorderColor(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 1)
    end

    -- Every hit remembers where it sits -- tab, section, the gear rows above
    -- it -- so opening it can unfold and scroll to the row itself
    -- (UI:RevealRow), not merely to its page. Tooltips are indexed too: the
    -- word a player remembers is often in the explanation, not in the label.
    local SEP = "  \194\187  "
    local function searchOptions(query)
        query = query:lower()
        local results, seen = {}, {}
        for _, key in ipairs(ns.moduleOrder or {}) do
            if #results >= 20 then break end
            local m = ns.modules[key]
            -- page members are indexed once via their page, and a sub-module
            -- once via its container's tab -- indexing it under its own key as
            -- well listed every one of its rows twice
            if m and m.GetOptions and not m._pageMember and not m.parentTab then
                local tabIds, tabLabels = {}, {}
                local realTabs = m.tabs and #m.tabs > 1
                if m.tabs then
                    for _, t in ipairs(m.tabs) do
                        table.insert(tabIds, t.id); tabLabels[t.id] = t.label
                    end
                else
                    table.insert(tabIds, "default")
                end
                local modName = L[m.name]
                local container = m.parentTab and ns.modules[m.parentTab]
                if container then modName = L[container.name] .. SEP .. modName end
                for _, tid in ipairs(tabIds) do
                    local ok, items = ns.ModuleOptions(m, tid)
                    if ok and type(items) == "table" then
                        local tabName = realTabs and tabLabels[tid] and L[tabLabels[tid]] or nil
                        local function add(res)
                            -- The section is part of the identity: two rows
                            -- with the same label under different headings
                            -- are two hits, not one.
                            local id = key .. "/" .. tostring(tid) .. "/" .. tostring(res.section)
                                .. "/" .. tostring(res.subKey or res.label)
                            if seen[id] then return false end
                            seen[id] = true
                            local path = modName
                            if tabName then path = path .. SEP .. tabName end
                            if res.section and res.section ~= res.label then
                                path = path .. SEP .. tostring(res.section)
                            end
                            res.modKey, res.tabId, res.path = key, tid, path
                            table.insert(results, res)
                            return #results >= 20
                        end
                        local function matches(raw)
                            if not raw or raw == "" then return false end
                            -- match the translated label AND the English key, so
                            -- searching works in the user's language and in English
                            local shown = L[raw]
                            return shown:lower():find(query, 1, true)
                                or tostring(raw):lower():find(query, 1, true)
                        end
                        local function scan(list, sec, parents)
                            for _, item in ipairs(list) do
                                if type(item) == "table" then
                                    if item.type == "section" then
                                        local s = { title = item.title, key = item.key or item.title,
                                                    collapsible = item.collapsible, collapsed = item.collapsed }
                                        -- title: sections. Their headings were plain
                                        -- header rows once and searchable via text;
                                        -- becoming sections must not unlist them.
                                        if matches(item.title) then
                                            if add({ label = L[item.title], section = item.title, isPlace = true }) then return true end
                                        end
                                        if scan(item.items or {}, s, parents) then return true end
                                    else
                                        local raw = item.label or item.text
                                        local hit = matches(raw)
                                        if not hit and item.label and type(item.tooltip) == "string" then
                                            hit = item.tooltip:lower():find(query, 1, true)
                                        end
                                        if hit then
                                            local res = { label = raw, shown = L[raw],
                                                section = sec and sec.title,
                                                subKey = item.subKey,
                                                parents = (#parents > 0) and parents or nil }
                                            if sec and sec.collapsible then
                                                res.sectionKey, res.sectionClosed = sec.key, sec.collapsed
                                            end
                                            -- text and headings are places, not rows: they
                                            -- scroll to their heading rather than flash
                                            if not item.label then
                                                res.isPlace = true
                                                if item.type == "header" then res.section = raw end
                                            end
                                            if add(res) then return true end
                                        end
                                        if item.items then
                                            if scan(item.items, sec, parents) then return true end
                                        end
                                        -- and behind a gear: folded away is not gone,
                                        -- and a setting you cannot find is the one you
                                        -- search for
                                        if item.subOptions then
                                            local chain = {}
                                            for i, v in ipairs(parents) do chain[i] = v end
                                            chain[#chain + 1] = item.subKey or item.label
                                            if scan(item.subOptions, sec, chain) then return true end
                                        end
                                    end
                                end
                            end
                        end
                        if scan(items, nil, {}) then break end
                    end
                end
            end
        end
        return results
    end

    local resultRows = {}
    local shownResults = {}
    local selected = 1

    local function closeSearch()
        searchBox:ClearFocus()
        searchBox:SetText("")
        placeholder:Show()
        searchDD:Hide()
    end

    local function openResult(res)
        if not res then return end
        closeSearch()
        if not UI.RevealRow then
            if UI.ShowModulePage then UI:ShowModulePage(res.modKey) end
            return
        end
        UI:RevealRow({
            mod = res.modKey, tab = res.tabId,
            label = (not res.isPlace) and res.label or nil,
            subKey = res.subKey, parents = res.parents,
            sectionKey = res.sectionKey, sectionClosed = res.sectionClosed,
            section = res.section,
        })
    end

    local function paintSelection()
        for i, row in ipairs(resultRows) do
            if row:IsShown() then row.hover:SetShown(i == selected) end
        end
    end

    local function renderResults(results)
        for _, row in ipairs(resultRows) do row:Hide() end
        shownResults = results
        selected = 1
        if #results == 0 then searchDD:Hide(); return end
        local y = -4
        for i, res in ipairs(results) do
            local row = resultRows[i]
            if not row then
                row = CreateFrame("Button", nil, searchDD)
                row:SetHeight(20)
                row:SetPoint("LEFT", searchDD, "LEFT", 4, 0)
                row:SetPoint("RIGHT", searchDD, "RIGHT", -4, 0)
                row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                UI.Font(row.text, 11)
                row.text:SetPoint("LEFT", row, "LEFT", 6, 0)
                row.text:SetPoint("RIGHT", row, "RIGHT", -6, 0)
                row.text:SetJustifyH("LEFT")
                row.text:SetWordWrap(false)
                row.hover = row:CreateTexture(nil, "BACKGROUND")
                row.hover:SetAllPoints(row)
                row.hover:SetColorTexture(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 0.25)
                row.hover:Hide()
                -- the mouse and the arrow keys move the same selection
                row:SetScript("OnEnter", function(self) selected = self._index; paintSelection() end)
                row:SetScript("OnClick", function(self) openResult(shownResults[self._index]) end)
                resultRows[i] = row
            end
            row._index = i
            row:SetPoint("TOP", searchDD, "TOP", 0, y)
            -- the path in the muted tone, the hit itself bright: the eye goes
            -- to what it typed, the path says where that is
            row.text:SetText(string.format("|cff8a8a96%s|r%s%s",
                res.path or "", SEP, res.shown or res.label or ""))
            row:Show()
            y = y - 22
        end
        searchDD:SetHeight(math.min(440, 8 + #results * 22))
        searchDD:Show()
        paintSelection()
    end

    searchBox:HookScript("OnTextChanged", function(self)
        local q = self:GetText() or ""
        if q == "" then placeholder:Show() else placeholder:Hide() end
        if #q < 2 then searchDD:Hide(); return end
        renderResults(searchOptions(q))
    end)
    searchBox:SetScript("OnEscapePressed", function(self)
        self:SetText(""); self:ClearFocus(); searchDD:Hide(); placeholder:Show()
    end)
    -- Enter opens the selected hit; arrows move the selection. Typing a word
    -- and pressing Enter therefore lands on the first hit without the mouse.
    searchBox:SetScript("OnEnterPressed", function(self)
        if searchDD:IsShown() and shownResults[selected] then
            openResult(shownResults[selected])
        else
            self:ClearFocus()
        end
    end)
    local function onArrow(_, key)
        if not searchDD:IsShown() or #shownResults == 0 then return end
        if key == "DOWN" then
            selected = (selected % #shownResults) + 1
        elseif key == "UP" then
            selected = ((selected - 2) % #shownResults) + 1
        else
            return
        end
        paintSelection()
    end
    -- The edit box's own arrow handler where the client has it; the generic
    -- key handler otherwise -- SetScript with a name this client does not
    -- know would be an error at load, not a silent no-op.
    if searchBox:HasScript("OnArrowPressed") then
        searchBox:SetScript("OnArrowPressed", onArrow)
    else
        searchBox:SetScript("OnKeyDown", onArrow)
    end
end

-- Entry from outside the window: the slash command. File level, not inside
-- CreateMainFrame -- defined there it did not exist until the window had been
-- opened once, and "/vfui search x" on a fresh login did nothing. Setting the
-- text runs the search, so the list is open on arrival.
function UI:OpenSearch(text)
    local main = UI:CreateMainFrame()
    if not main:IsShown() then UI:ToggleMainFrame() end
    local box = main.searchBox
    if not box then return end
    box:SetText(text or "")
    box:SetFocus()
    if text and text ~= "" then box:SetCursorPosition(#text) end
end
