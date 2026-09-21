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

-- The colour an icon wears at rest. Accent mode reads the theme colour at
-- paint time rather than copying it, because the theme colour is live-mutated
-- and a copy would freeze whatever it was when it was saved.
local function iconColor(db)
    if db.iconUseAccent then return ns.COLORS.accent end
    return db.iconColor
end

-- Where a freely-placed button sits, as an offset from the top of the column.
-- Stored per button KEY, not per slot: slots change hands whenever a button
-- above is switched off, and a position that followed the slot would jump.
local function savedPos(db, key)
    local p = db.iconPositions and db.iconPositions[key]
    if type(p) ~= "table" then return nil end
    if type(p.x) ~= "number" or type(p.y) ~= "number" then return nil end
    return p.x, p.y
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

    -- Dragging is armed per refresh; the scripts are set once here so the
    -- pooled button does not collect a new closure on every pass.
    b:RegisterForDrag("LeftButton")
    -- Asked of the BUTTON, not only of the setting: the copy parked on the
    -- chat panel is never movable, and StartMoving on a frame that is not
    -- raises a Lua error rather than doing nothing.
    b:SetScript("OnDragStart", function(self)
        if not (Chat.db().freeMoveIcons and self:IsMovable()) then return end
        self:StartMoving()
    end)
    b:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if not (Chat.db().freeMoveIcons and self:IsMovable()) then return end
        local db = Chat.db()
        local owner = self:GetParent()
        -- Read as numbers and only then stored: GetLeft can answer nil for a
        -- frame whose rectangle is not resolved, and a nil here would be
        -- arithmetic on nil at the next layout pass.
        local bx, by = owner:GetLeft(), owner:GetTop()
        local sx, sy = self:GetLeft(), self:GetTop()
        if not (type(bx) == "number" and type(by) == "number"
            and type(sx) == "number" and type(sy) == "number") then
            Sidebar.Refresh()
            return
        end
        db.iconPositions = db.iconPositions or {}
        db.iconPositions[self.def.key] = { x = sx - bx, y = sy - by }
        Sidebar.Refresh()
    end)
    -- The tooltip is read from the button's CURRENT job, not from the one it
    -- had when it was made: these are pooled, and a slot changes hands the
    -- moment a button above it is switched off.
    b:SetScript("OnEnter", function(self)
        tex:SetDesaturated(false)
        -- The column fades with the chat, so hovering it has to bring it back
        -- the same way hovering the chat does -- otherwise the buttons are
        -- there to be clicked but never become visible enough to aim at.
        if Chat.Fade then Chat.Fade.SetMouseOver(true) end
        -- Asked at hover time, not when the button was made: these are pooled
        -- and outlive any number of settings changes.
        if Chat.db().hideTooltipOnHover then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText((self.def and tooltipFor(self.def.key)) or "", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function()
        tex:SetDesaturated(true)
        GameTooltip:Hide()
        if Chat.Fade then Chat.Fade.SetMouseOver(false) end
    end)
    b:SetScript("OnClick", function() def.action() end)
    return b
end

function Sidebar.Refresh()
    local db = Chat.db()
    local cf = _G.ChatFrame1
    local d = cf and Chat.Data(cf)
    if not (d and d.bg) then return end

    -- Before the column's own on/off: the button parked on the chat panel is
    -- not part of the column and must not disappear with it.
    Sidebar.PlaceScrollButton(d)

    if not db.sidebar then
        if bar then bar:Hide() end
        return
    end

    if not bar then
        bar = CreateFrame("Frame", nil, UIParent)
        bar:SetFrameStrata("MEDIUM")
        bar.buttons = {}
        bar.bg = bar:CreateTexture(nil, "BACKGROUND")
        bar.bg:SetAllPoints(bar)
        bar.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
        -- Motion without clicks, so the whole column is a hover target in
        -- "only while the mouse is near" mode instead of just its icons --
        -- a column given a real width would otherwise be mostly dead space
        -- you cannot hover back into view. Clicks stay with whatever is
        -- underneath, because the column sits over the world.
        pcall(bar.SetMouseClickEnabled, bar, false)
        pcall(bar.SetMouseMotionEnabled, bar, true)
        if bar.SetPropagateMouseClicks then pcall(bar.SetPropagateMouseClicks, bar, true) end
        bar:SetScript("OnEnter", function()
            if Chat.Fade then Chat.Fade.SetMouseOver(true) end
        end)
        bar:SetScript("OnLeave", function()
            if Chat.Fade then Chat.Fade.SetMouseOver(false) end
        end)
    end
    bar:SetFrameLevel((d.bg:GetFrameLevel() or 2) + 2)

    local scale = db.sidebarScale or 1
    local spacing = db.sidebarSpacing or 10
    local size = 16 * scale
    -- Zero means "as wide as the icons", which is the column as it has always
    -- been. Anything else is a real width the icons are centred in.
    local width = math.max(size, db.sidebarWidth or 0)

    -- Separate mode pushes the column away from the panel by the configured
    -- gap; otherwise it keeps the six pixels it has always had.
    local gap = db.sidebarSeparate and (db.sidebarSeparateSpacing or 8) or 6
    bar:ClearAllPoints()
    if db.sidebarRight then
        bar:SetPoint("TOPLEFT", d.bg, "TOPRIGHT", gap, 0)
    else
        bar:SetPoint("TOPRIGHT", d.bg, "TOPLEFT", -gap, 0)
    end

    -- The column's own ground, in the panel's colour so the two read as one
    -- surface. Hidden by default, which is what it looked like before there
    -- was one to hide.
    if db.hideSidebarBg then
        bar.bg:Hide()
    else
        local c = db.bgColor
        bar.bg:SetColorTexture(c.r, c.g, c.b, c.a or 0.65)
        bar.bg:Show()
    end

    local col = iconColor(db)
    local free = db.freeMoveIcons and true or false

    local shown, last = 0, nil
    for _, def in ipairs(BUTTONS) do
        -- The scroll button can be sent to the chat panel instead, where it
        -- sits in the corner the client keeps its own in. It then leaves the
        -- column entirely rather than appearing twice.
        local onChat = def.key == "showScroll" and db.scrollButtonOnChat
        if db[def.key] and not onChat then
            shown = shown + 1
            local b = bar.buttons[shown]
            if not b then
                b = makeButton(bar, def)
                bar.buttons[shown] = b
            end
            b.def = def
            b:SetScript("OnClick", function() def.action() end)
            b.tex:SetTexture(ICON .. def.icon)
            b.tex:SetVertexColor(col.r, col.g, col.b)
            b:SetSize(size, size)
            b:SetMovable(free)
            b:SetClampedToScreen(free)
            b:ClearAllPoints()

            local px, py = savedPos(db, def.key)
            if free and px then
                b:SetPoint("TOPLEFT", bar, "TOPLEFT", px, py)
                -- Deliberately NOT the new `last`: a button that was dragged
                -- out of the column must not become the anchor the rest of the
                -- column hangs from, or moving one icon drags the stack below
                -- it along.
            elseif last then
                b:SetPoint("TOP", last, "BOTTOM", 0, -spacing)
                last = b
            else
                b:SetPoint("TOP", bar, "TOP", 0, 0)
                last = b
            end
            b:Show()
        end
    end
    for i = shown + 1, #bar.buttons do bar.buttons[i]:Hide() end

    bar:SetSize(width, math.max(size, shown * size + math.max(0, shown - 1) * spacing))
    bar:SetShown(shown > 0)
    if Chat.Fade then Chat.Fade.Poke() end
end

-- The jump-to-newest button, parked on the chat panel.
--
-- Parented to the PANEL, not to the column. It looks like a detail and is not:
-- a child of the column would go with the column, so switching every column
-- icon off -- or setting the column to "never" -- would take away a button
-- that is supposed to live on the chat and have nothing to do with the column
-- at all. It fades with the chat, which is where it sits.
local chatScroll

function Sidebar.PlaceScrollButton(d)
    local db = Chat.db()
    if not (db.showScroll and db.scrollButtonOnChat and d and d.bg) then
        if chatScroll then chatScroll:Hide() end
        return
    end
    local b = chatScroll
    if not b then
        local def
        for _, e in ipairs(BUTTONS) do
            if e.key == "showScroll" then def = e end
        end
        if not def then return end
        b = makeButton(d.bg, def)
        chatScroll = b
    end
    local size = 16 * (db.sidebarScale or 1)
    local col = iconColor(db)
    b.tex:SetVertexColor(col.r, col.g, col.b)
    b:SetSize(size, size)
    b:SetMovable(false)
    b:ClearAllPoints()
    b:SetPoint("BOTTOMRIGHT", d.bg, "BOTTOMRIGHT", -(db.padding or 6), (db.padding or 6))
    b:Show()
end

-- How bright the column is allowed to be, for the fade to multiply into.
--
-- Given to the fade rather than written here, so there is exactly ONE thing
-- writing this frame's alpha. The column is never HIDDEN for "mouseover"
-- either: a hidden frame takes no mouse, so it could never be hovered back
-- into view -- the same reason the chat itself goes to alpha zero instead of
-- hiding.
function Sidebar.AlphaCeiling()
    local db = Chat.db()
    if (db.sidebarVisibility or "always") ~= "mouseover" then return 1 end
    return (Chat.Fade and Chat.Fade.mouseOver) and 1 or 0
end

-- The button column, for the fade. Same reason as the tab strip: it is
-- parented to UIParent so it can sit beside the panel rather than inside it,
-- which puts it out of the fade's reach unless it is handed over.
function Sidebar.Bar()
    return bar
end

function Sidebar.Release()
    if bar then bar:Hide() end
    if chatScroll then chatScroll:Hide() end
end
