-- VuloForeverUI / Modules / Chat / Tabs
--
-- Our own tab strip -- and it is a strip of GHOSTS.
--
-- THE ONE IDEA IN THIS FILE
--
-- This module never selects, closes, creates, renames or reorders a chat
-- window. Not once. Every one of those goes through an FCF_ function, and
-- hooking or calling one from addon code taints the CALLER: the measured chain
-- is a hooked FCF_ call leaving `isLocked` tainted forever, after which the
-- tab's own context menu dies iterating its private message list and the
-- resize code dies on the secret name in a whisper tab. Deferring the hook
-- body does not help, because it is the wrapper that taints.
--
-- So the client's tabs stay exactly where they are and keep every click. Ours
-- are drawn beside them, with the mouse switched off, and the client's strip
-- is taken to alpha zero -- alpha does not disable a mouse, so the invisible
-- real tab under our drawing is what the player actually clicks. We draw; the
-- client decides.
local _, ns = ...
local Chat = ns.Chat

local Tabs = {}
Chat.Tabs = Tabs

local strip

-- ---------------------------------------------------------------- strip --

local function ensureStrip()
    if strip then return strip end
    strip = CreateFrame("Frame", nil, UIParent)
    strip:SetFrameStrata("MEDIUM")
    -- Motion without clicks, and both propagated: a motion-enabled overlay
    -- that does not propagate swallows the click meant for the real tab under
    -- it, and kills the client's own tab tooltip with it.
    pcall(strip.SetMouseClickEnabled, strip, false)
    pcall(strip.SetMouseMotionEnabled, strip, true)
    if strip.SetPropagateMouseClicks then pcall(strip.SetPropagateMouseClicks, strip, true) end
    if strip.SetPropagateMouseMotion then pcall(strip.SetPropagateMouseMotion, strip, true) end
    strip.ghosts = {}
    return strip
end

-- The client's strip, made invisible without being disabled. Its per-tab
-- alphas are rewritten by the client on every dock pass and multiply into
-- this one, so the dock's own alpha is the place to write.
local function suppressDock()
    local dock = _G.GeneralDockManager
    if not dock or Tabs.dockHidden then return end
    Tabs.dockHidden = true
    pcall(dock.SetAlpha, dock, 0)
    -- The overflow button is a click target that would vanish with the parent
    -- alpha; it keeps its own.
    local overflow = dock.overflowButton
    if overflow and overflow.SetIgnoreParentAlpha then
        pcall(overflow.SetIgnoreParentAlpha, overflow, true)
    end
end

local function restoreDock()
    local dock = _G.GeneralDockManager
    if not (dock and Tabs.dockHidden) then return end
    Tabs.dockHidden = false
    pcall(dock.SetAlpha, dock, 1)
end

-- ---------------------------------------------------------------- ghosts --

local function ghost(index)
    local s = ensureStrip()
    local g = s.ghosts[index]
    if g then return g end

    g = CreateFrame("Frame", nil, s)
    g:EnableMouse(false)
    g.text = g:CreateFontString(nil, "OVERLAY")
    -- Anchored by its left edge and never measured: a whisper tab's label can
    -- be secret, and measuring a secret string is as forbidden as comparing
    -- one.
    g.text:SetPoint("LEFT", g, "LEFT", 0, 0)

    g.underline = g:CreateTexture(nil, "ARTWORK")
    g.underline:SetTexture("Interface\\Buttons\\WHITE8X8")
    g.underline:SetPoint("BOTTOMLEFT", g, "BOTTOMLEFT", 0, 0)
    g.underline:SetPoint("BOTTOMRIGHT", g, "BOTTOMRIGHT", 0, 0)
    g.underline:SetHeight(2)
    g.underline:Hide()

    s.ghosts[index] = g
    return g
end

-- The label of a real tab. It may be secret, so it is asked about first and
-- then goes straight into SetText -- the one sink a secret string is allowed
-- to reach.
local function tabLabel(tab)
    local fs = tab and (tab.Text or (tab.GetName and _G[tab:GetName() .. "Text"]))
    if not fs then return nil end
    local ok, text = pcall(fs.GetText, fs)
    if not ok then return nil end
    return text
end

local function isSelected(cf)
    if not FCFDock_GetSelectedWindow then return false end
    local ok, selected = pcall(FCFDock_GetSelectedWindow, _G.GENERAL_CHAT_DOCK)
    return ok and selected == cf
end

function Tabs.Refresh()
    if not Chat.mod.active then return end
    local db = Chat.db()
    suppressDock()
    local s = ensureStrip()

    local shown = 0
    for _, cf in ipairs(Chat.Frames()) do
        local d = Chat.Data(cf)
        local tab = cf.GetName and _G[cf:GetName() .. "Tab"]
        if d.bridged and tab and Chat.IsOpen(cf) then
            shown = shown + 1
            local g = ghost(shown)

            -- Anchored TO the real tab, never parented to it: a parent of ours
            -- in the client's frame tree is exactly what taints the next dock
            -- pass. An anchor is only geometry.
            g:ClearAllPoints()
            g:SetPoint("TOPLEFT", tab, "TOPLEFT", 0, 0)
            g:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", 0, 0)

            ns.UI.FontFor("chat", g.text, db.tabFontSize or 11, "NONE")
            local label = tabLabel(tab)
            if type(label) ~= "nil" then g.text:SetText(label) end

            local active = isSelected(cf)
            if active then
                g.text:SetTextColor(1, 1, 1)
                g.underline:SetShown(db.activeUnderline ~= false)
                g.underline:SetColorTexture(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 0.9)
            else
                g.text:SetTextColor(0.6, 0.6, 0.62)
                g.underline:Hide()
            end
            g:Show()
        end
    end
    for i = shown + 1, #s.ghosts do s.ghosts[i]:Hide() end
    s:Show()
end

-- A line arrived in a window. The client owns the flashing of its own tab; all
-- we do is re-read which tab is selected, on the next frame.
function Tabs.OnMessage()
    Chat.Queue("chat.tabs", function() Tabs.Refresh() end)
end

function Tabs.Release()
    restoreDock()
    if strip then strip:Hide() end
end
