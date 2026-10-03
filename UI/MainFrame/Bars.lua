-- VuloForeverUI / UI / MainFrame / Bars: the frame-time readout in the title bar and the bottom bar with its buttons.
local _, ns = ...
local L = ns.L
local UI = ns.UI
local MF = UI._MF
local BOTTOMBAR_H = MF.BOTTOMBAR_H

-- Part of UI:CreateMainFrame, called from it at the same point: the frame-time
-- readout beside the version and the OnShow/OnHide hooks that drive it. Returns
-- the readout; the crumb anchors to it.
function MF.BuildFrameTimeReadout(f, titleBar, version)
    local cpuText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    UI.Font(cpuText, 10)
    cpuText:SetPoint("LEFT", version, "RIGHT", 10, 0)
    cpuText:SetText("")

    -- The client carries its own always-on profiler (used by Blizzard's own addon
    -- list). It needs no CVar and no /reload, and it reports per-frame timings
    -- rather than a cumulative counter we have to difference ourselves. The old
    -- family stays as the fallback for clients without it -- there it still needs
    -- scriptProfile and a reload, which is what the option next to this says.
    local PROF = _G.C_AddOnProfiler
    local METRIC = _G.Enum and _G.Enum.AddOnProfilerMetric

    -- CPU still lives in globals on this client; the add-on list in C_AddOns
    local _UpdateCPU  = UpdateAddOnCPUUsage
    local _GetCPU     = GetAddOnCPUUsage
    local _GetNum     = C_AddOns.GetNumAddOns
    local _IsLoaded   = C_AddOns.IsAddOnLoaded

    local function getTotalAddonCPU()
        if not _GetCPU or not _GetNum then return 0 end
        local total = 0
        for i = 1, _GetNum() do
            if not _IsLoaded or _IsLoaded(i) then
                total = total + (_GetCPU(i) or 0)
            end
        end
        return total
    end

    local cpuTicker
    -- GetAddOnCPUUsage is cumulative ms since profiling started; we show the per-tick delta.
    local _lastTotal, _lastOwn, _lastTime = 0, 0, 0

    -- Blizzard's own share formula (Blizzard_AddOnList): NOT own/all-addons, but
    -- own divided by the frame time this addon is actually responsible for --
    -- otherwise the number grows as other addons get cheaper.
    local function sharePercent(metric)
        local app     = PROF.GetApplicationMetric(metric)
        local overall = PROF.GetOverallMetric(metric)
        local own     = PROF.GetAddOnMetric(ns.NAME, metric)
        local rel = app - overall + own
        if rel <= 0 then return 0, own end
        return own / rel * 100, own
    end

    local function updateCPUModern()
        local pct, own = sharePercent(METRIC.RecentAverageTime)
        local peak = PROF.GetAddOnMetric(ns.NAME, METRIC.PeakTime)
        cpuText:SetText(string.format(
            L["|cff888888%.2f ms/frame |cff666666(%.1f%% of ours, peak %.1f ms)|r|r"],
            own, pct, peak))
    end

    local function updateCPULegacy()
        local cv = (C_CVar and C_CVar.GetCVar and C_CVar.GetCVar("scriptProfile"))
                or (GetCVar and GetCVar("scriptProfile"))
        if cv ~= "1" then
            cpuText:SetText(L["|cff666666CPU: off|r"])
            return
        end
        if _UpdateCPU then _UpdateCPU() end

        local now   = GetTime() or 0
        local own   = (_GetCPU and _GetCPU("VuloForeverUI")) or 0
        local total = getTotalAddonCPU()

        if _lastTime == 0 then
            cpuText:SetText(L["|cff888888CPU: measuring...|r"])
            _lastTotal, _lastOwn, _lastTime = total, own, now
            return
        end

        local dt = now - _lastTime
        if dt < 0.1 then return end

        local totalRate = (total - _lastTotal) / dt
        local ownRate   = (own   - _lastOwn)   / dt

        cpuText:SetText(string.format(
            L["|cff888888CPU: %.2f ms/s |cff666666(VFUI: %.2f)|r|r"],
            totalRate, ownRate))

        _lastTotal, _lastOwn, _lastTime = total, own, now
    end

    -- IsEnabled matters, not just the presence of the functions: Blizzard gates
    -- its own performance UI on it, and with the profiler off every metric
    -- reads 0 -- the header would sit at "0.00 ms/frame" forever without ever
    -- erroring, so nothing would trip the fallback.
    local useModern = PROF and METRIC and PROF.GetAddOnMetric
        and PROF.GetApplicationMetric and PROF.GetOverallMetric
        and METRIC.RecentAverageTime ~= nil and METRIC.PeakTime ~= nil
        and (not PROF.IsEnabled or PROF.IsEnabled())
    local function updateCPU()
        if useModern then
            local ok = pcall(updateCPUModern)
            if ok then return end
            useModern = false   -- fall back for the rest of the session
        end
        updateCPULegacy()
    end

    f:HookScript("OnShow", function()
        UI:FitMainFrame()
        updateCPU()
        if not cpuTicker and C_Timer and C_Timer.NewTicker then
            cpuTicker = C_Timer.NewTicker(2, updateCPU)
        end
    end)
    f:HookScript("OnHide", function()
        if cpuTicker then cpuTicker:Cancel(); cpuTicker = nil end
        for _, fn in ipairs(UI._mainHideHooks) do fn() end
    end)
    return cpuText
end

-- Part of UI:CreateMainFrame, called from it at the same point: the bottom bar,
-- its buttons and the copy-link popup.
function MF.BuildBottomBar(f)
    local bottomBar = CreateFrame("Frame", nil, f)
    bottomBar:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",  0, 0)
    bottomBar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    bottomBar:SetHeight(BOTTOMBAR_H)
    local bbBG = UI.SetColorBG(bottomBar, ns.TC("barBottom"))
    do
        local top, bot = ns.COLORS.barTop, ns.COLORS.barBottom
        UI.SetGradient(bbBG, "VERTICAL",
            top.r, top.g, top.b, top.a or 1,
            bot.r, bot.g, bot.b, bot.a or 1)
    end

    local bottomSep = f:CreateTexture(nil, "ARTWORK")
    bottomSep:SetColorTexture(ns.COLORS.border.r, ns.COLORS.border.g, ns.COLORS.border.b, 1)
    bottomSep:SetPoint("BOTTOMLEFT",  bottomBar, "TOPLEFT",  0, 0)
    bottomSep:SetPoint("BOTTOMRIGHT", bottomBar, "TOPRIGHT", 0, 0)
    bottomSep:SetHeight(1)

    local resetBtn = UI:CreateButton(bottomBar, {
        label = L["Reset Module"], width = 130, height = 26,
        tooltip = L["Resets all settings of the current module to defaults."],
        onClick = function()
            if not UI.currentModule then return end
            local mod = ns.modules[UI.currentModule]
            if not mod then return end
            for k, v in pairs(mod.defaults or {}) do
                if type(v) == "table" then
                    mod.db[k] = ns:DeepCopy(v)
                else
                    mod.db[k] = v
                end
            end
            -- Keep the tab: rebuilding without it makes GetOptions(nil) return
            -- every section at once, so the page turned into one long list while
            -- the tab column still showed a single tab as selected.
            UI:BuildOptionsPage(UI.currentModule, UI.currentTab)
            UI:RefreshSidebarStates()
            ns:Print(L["Module '%s' reset."], L[mod.name])
        end,
    })
    resetBtn:SetPoint("LEFT", bottomBar, "LEFT", 10, 0)

    local reloadBtn = UI:CreateButton(bottomBar, {
        label = L["Reload UI"], width = 100, height = 26,
        tooltip = L["Reloads the WoW UI completely (/reload)."],
        onClick = function() ReloadUI() end,
    })
    reloadBtn:SetPoint("LEFT", resetBtn, "RIGHT", 6, 0)

    local doneBtn = UI:CreateButton(bottomBar, {
        label = L["Done"], width = 90, height = 26, primary = true,
        onClick = function() f:Hide() end,
    })
    doneBtn:SetPoint("RIGHT", bottomBar, "RIGHT", -10, 0)

    -- the client cannot open a browser, so links are shown pre-selected for Ctrl+C
    StaticPopupDialogs["VFUI_COPY_URL"] = StaticPopupDialogs["VFUI_COPY_URL"] or {
        text = L["Copy the link with Ctrl+C:"],
        button1 = CLOSE or "Close",
        hasEditBox = true,
        editBoxWidth = 260,
        OnShow = function(self)
            local eb = ns.PopupEditBox(self)
            if not eb then return end
            eb:SetText(self.data or "")
            eb:HighlightText()
            eb:SetFocus()
        end,
        EditBoxOnTextChanged = function(self, data)
            if self:GetText() ~= (data or "") then
                self:SetText(data or "")
                self:HighlightText()
            end
        end,
        EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
        EditBoxOnEnterPressed  = function(self) self:GetParent():Hide() end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }

    local function socialButton(iconFile, label, url, xOff)
        local b = CreateFrame("Button", nil, bottomBar)
        b:SetSize(20, 20)
        b:SetPoint("CENTER", bottomBar, "CENTER", xOff, 0)
        local t = b:CreateTexture(nil, "ARTWORK")
        t:SetAllPoints(b)
        t:SetTexture("Interface\\AddOns\\VuloForeverUI\\Media\\Icons\\ui\\" .. iconFile)
        t:SetVertexColor(ns.TC("textSoft", 0.9))
        b:SetScript("OnEnter", function(self)
            t:SetVertexColor(ns.TC("textHi"))
            UI:ShowTooltip(self, {
                anchor = "ANCHOR_TOP", title = label,
                lines  = { L["Click: copy link"] },
            })
        end)
        b:SetScript("OnLeave", function()
            t:SetVertexColor(ns.TC("textSoft", 0.9))
            UI:HideTooltip()
        end)
        b:SetScript("OnClick", function()
            StaticPopup_Show("VFUI_COPY_URL", nil, nil, url)
        end)
        return b
    end
    socialButton("TwitchV.tga",  "Twitch",  "https://www.twitch.tv/mrvulo", -14)
    socialButton("DiscordV.tga", "Discord", "https://discord.gg/mxhvFBSXSf",  14)
end
