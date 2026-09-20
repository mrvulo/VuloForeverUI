-- VuloForeverUI / Modules / Chat / Sidebar
--
-- The little column of buttons beside the chat: copy, friends, guild, the
-- settings, and jump to the newest line.
--
-- All of it is ours -- our frame, our buttons, anchored to our own panel --
-- so nothing here is near the taint rules the rest of the module lives under.
-- The one place it does touch the client is the copy window, and that reads
-- OUR lines rather than the client's, because ours are the ones the player
-- can see.
local _, ns = ...
local L = ns.L
local Chat = ns.Chat

local Sidebar = {}
Chat.Sidebar = Sidebar

local ICON = "Interface\\AddOns\\VuloForeverUI\\Media\\Icons\\"

local bar

-- ---------------------------------------------------------------- copy --

-- Everything visible in the active window, as text someone can select.
--
-- Escapes are turned into something readable: a hyperlink becomes its label,
-- textures and unresolved tokens go away, and the colour codes STAY, because
-- the point of copying a conversation is to still see who said what.
local function stripEscapes(line)
    if type(line) ~= "string" then return nil end
    line = line:gsub("|H.-|h(.-)|h", "%1")
    line = line:gsub("|T.-|t", "")
    line = line:gsub("|A.-|a", "")
    line = line:gsub("|K.-|k", "")
    return line
end

local function activeFrame()
    if FCFDock_GetSelectedWindow then
        local ok, cf = pcall(FCFDock_GetSelectedWindow, _G.GENERAL_CHAT_DOCK)
        if ok and cf then return cf end
    end
    return _G.ChatFrame1
end

function Sidebar.CopyText()
    local cf = activeFrame()
    local d = cf and Chat.Data(cf)
    local smf = d and d.smf
    -- A temporary window -- a whisper tab, a pet battle log -- is never one of
    -- ours, so there is nothing of it to copy. The main window is what the
    -- button then offers, rather than an empty box.
    if not smf then
        local main = _G.ChatFrame1
        smf = main and Chat.Data(main).smf
    end
    if not smf then return "" end

    local out = {}
    local ok, count = pcall(smf.GetNumMessages, smf)
    if not (ok and type(count) == "number") then return "" end
    for i = 1, count do
        local okLine, text = pcall(smf.GetMessageInfo, smf, i)
        -- A secret line is skipped rather than copied: it may not be measured,
        -- joined or put in a table with anything, and a copy is all three.
        if okLine and type(text) == "string" and not ns.IsSecret(text) then
            out[#out + 1] = stripEscapes(text)
        end
    end
    return table.concat(out, "\n")
end

-- ---------------------------------------------------------------- buttons --

local BUTTONS = {
    { key = "showCopy",     icon = "copy.tga",     action = function()
        -- An empty result is said out loud. It happens for a real reason --
        -- a whisper tab is not one of our windows and has no lines of ours --
        -- and an export box with nothing in it looks like a broken button.
        local text = Sidebar.CopyText()
        if text == "" then
            ns:Print(ns.L["There is nothing in this window to copy."])
        else
            ns.UI:ShowProfileExportDialog(text)
        end
    end },
    { key = "showFriends",  icon = "friends.tga",  action = function()
        if _G.ToggleFriendsFrame then pcall(_G.ToggleFriendsFrame) end
    end },
    { key = "showGuild",    icon = "landmark.tga",    action = function()
        if _G.ToggleGuildFrame then pcall(_G.ToggleGuildFrame) end
    end },
    { key = "showSettings", icon = "gear.tga", action = function()
        ns.Slash.CHAT()
    end },
    { key = "showScroll",   icon = "arrow_down.tga",    action = function()
        local cf = activeFrame()
        if cf then pcall(cf.ScrollToBottom, cf) end
    end },
}

-- The tooltips, built when the bar is, never at file scope: a locale key read
-- while the file loads is read in the wrong language.
local function tooltipFor(key)
    local t = {
        showCopy     = L["Copy the chat"],
        showFriends  = L["Friends"],
        showGuild    = L["Guild"],
        showSettings = L["Chat settings"],
        showScroll   = L["Jump to the newest line"],
    }
    return t[key]
end

local function makeButton(parent, def)
    local b = CreateFrame("Button", nil, parent)
    b.def = def
    b:SetSize(16, 16)
    local tex = b:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints(b)
    tex:SetTexture(ICON .. def.icon)
    tex:SetDesaturated(true)
    b.tex = tex
    -- The tooltip is read from the button's CURRENT job, not from the one it
    -- had when it was made: these are pooled, and a slot changes hands the
    -- moment a button above it is switched off.
    b:SetScript("OnEnter", function(self)
        tex:SetDesaturated(false)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText((self.def and tooltipFor(self.def.key)) or "", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function()
        tex:SetDesaturated(true)
        GameTooltip:Hide()
    end)
    b:SetScript("OnClick", function() def.action() end)
    return b
end

function Sidebar.Refresh()
    local db = Chat.db()
    local cf = _G.ChatFrame1
    local d = cf and Chat.Data(cf)
    if not (d and d.bg) then return end

    if not db.sidebar then
        if bar then bar:Hide() end
        return
    end

    if not bar then
        bar = CreateFrame("Frame", nil, UIParent)
        bar:SetFrameStrata("MEDIUM")
        bar.buttons = {}
    end
    bar:SetFrameLevel((d.bg:GetFrameLevel() or 2) + 2)

    local scale = db.sidebarScale or 1
    local spacing = db.sidebarSpacing or 10
    local size = 16 * scale

    bar:ClearAllPoints()
    if db.sidebarRight then
        bar:SetPoint("TOPLEFT", d.bg, "TOPRIGHT", 6, 0)
    else
        bar:SetPoint("TOPRIGHT", d.bg, "TOPLEFT", -6, 0)
    end

    local shown, last = 0, nil
    for _, def in ipairs(BUTTONS) do
        if db[def.key] then
            shown = shown + 1
            local b = bar.buttons[shown]
            if not b then
                b = makeButton(bar, def)
                bar.buttons[shown] = b
            end
            b.def = def
            b:SetScript("OnClick", function() def.action() end)
            b.tex:SetTexture(ICON .. def.icon)
            b:SetSize(size, size)
            b:ClearAllPoints()
            if last then
                b:SetPoint("TOP", last, "BOTTOM", 0, -spacing)
            else
                b:SetPoint("TOP", bar, "TOP", 0, 0)
            end
            b:Show()
            last = b
        end
    end
    for i = shown + 1, #bar.buttons do bar.buttons[i]:Hide() end

    bar:SetSize(size, math.max(size, shown * size + math.max(0, shown - 1) * spacing))
    bar:SetShown(shown > 0)
end

function Sidebar.Release()
    if bar then bar:Hide() end
end
