-- VuloForeverUI / Modules / Skins / Friends
--
-- The OLDER friends window. Forever normally opens the newer social window
-- instead (Social.lua); this one is what the client shows when that system
-- is switched off (ToggleFriendsFrame: SocialUIControl.IsEnabled()).
--
-- The client's friends window (Blizzard_FriendsFrame, Camelot build) in the
-- flat dark look: our ground under the window, the status dropdown, the
-- BattleTag bar and the contacts menu button flat, a copy button beside the
-- BattleTag, flat list rows (game, class or Battle.net icon on the left, the
-- character and level in class colour, the status dot behind the name, a
-- small flat invite button), flat dividers, scroll bar, buttons and tabs.
--
-- The rows are the client's: FriendsFrame_UpdateFriendButton fills one, our
-- post-hook dresses it. Dividers have no fill function; the list's own
-- "frame initialized" callback catches them. Everything works in a fight:
-- none of these frames is protected.
--
-- TAINT: art is faded (Skins.Fade, given back by Skins.RestoreAll), never
-- hidden; nothing is reparented and no field is written on a client frame.
-- Only client texts and textures are re-anchored -- never a client frame, so
-- no button under the mouse gets OnLeave/OnEnter from us. The client's
-- friend list is never rebuilt by us: a data provider set from our code
-- would fill every row (and its HelpTip) in our taint. That is also why
-- there are no friend groups, search or filter: the client has none, and
-- building them would mean exactly that.
--
-- Secret values: the friend data is read only where ns.CanRead says so;
-- anything unreadable leaves the client's own text in place.
local _, ns = ...
local L = ns.L
local Skins = ns.Skins

local Friends = {}
Skins.Friends = Friends
table.insert(Skins.parts, Friends)

local ICON = 26                      -- the left icon of a row
local GOLD = { 1, 0.82, 0, 1 }

local ready, ground, copyBtn
local ours = setmetatable({}, { __mode = "k" })     -- our own regions: never faded
local flat = setmetatable({}, { __mode = "k" })     -- client button -> { panel, hover }
local rows = setmetatable({}, { __mode = "k" })     -- client row -> our decoration
local lines = setmetatable({}, { __mode = "k" })    -- divider / invite header -> our texture
local tabs = {}                                     -- { tab, top } in paint order

local function on()
    local db = Skins.db()
    return Skins.mod.active and db.friends and db.friendsStyle == "modern" or false
end

local function mine(t) ours[t] = true; return t end

-- Every texture of a client frame faded, except ours and `keep`.
local function fadeTextures(frame, keep)
    for _, r in ipairs({ frame:GetRegions() }) do
        if r:GetObjectType() == "Texture" and not ours[r] and not (keep and keep[r]) then
            Skins.Fade(r)
        end
    end
end

-- A client button made flat: its art faded, a strip panel of ours one level
-- below it (so its text and our marks stay on top), a light wash on hover.
local function flatButton(b, show, keep)
    if not b then return end
    local f = flat[b]
    if show then
        fadeTextures(b, keep)
        if not f then
            f = { panel = Skins.Panel(b, Skins.STRIP, 0) }
            f.panel:SetFrameLevel(math.max(0, b:GetFrameLevel() - 1))
            f.hover = mine(b:CreateTexture(nil, "HIGHLIGHT"))
            f.hover:SetAllPoints(b)
            f.hover:SetColorTexture(1, 1, 1, 0.07)
            flat[b] = f
        end
        f.panel:Show()
        f.hover:Show()
    elseif f then
        f.panel:Hide()
        f.hover:Hide()
    end
    return f
end

-- shared with Social.lua (the newer friends window)
Skins.Mine, Skins.FadeTextures, Skins.FlatButton = mine, fadeTextures, flatButton

-- ---------------------------------------------------------------- names --

local classByName
local function classToken(name)
    if type(name) ~= "string" or not ns.CanRead(name) then return nil end
    if not classByName then
        classByName = {}
        for _, list in ipairs({ _G.LOCALIZED_CLASS_NAMES_MALE, _G.LOCALIZED_CLASS_NAMES_FEMALE }) do
            for token, n in pairs(list or {}) do classByName[n] = token end
        end
    end
    return classByName[name]
end

local function classHex(token)
    local c = token and ns.ClassColor(token)
    if not (c and c.r) then return "ffd0d0d0" end
    return ("ff%02x%02x%02x"):format(c.r * 255, c.g * 255, c.b * 255)
end

local function readable(v) return v ~= nil and ns.CanRead(v) end

local function levelText(level)
    if type(level) == "number" and ns.CanRead(level) and level > 0 then
        return L["Lvl %d"]:format(level)
    end
end

-- The row's name as the reference look has it, or nil to keep the client's:
--   character friend  "Name Lvl 25", the name in class colour
--   Battle.net friend "Account (Character Lvl 25)", the bracket in class colour
local function nameFor(button)
    local id = button.id
    if type(id) ~= "number" then return nil end
    if button.buttonType == _G.FRIENDS_BUTTON_TYPE_WOW then
        local info = C_FriendList.GetFriendInfoByIndex(id)
        if not (info and readable(info.connected) and info.connected) then return nil end
        if not (readable(info.name) and type(info.name) == "string") then return nil end
        local lvl = levelText(info.level)
        local s = "|c" .. classHex(classToken(info.className)) .. info.name .. "|r"
        if lvl then s = s .. " |cff9d9d9d" .. lvl .. "|r" end
        return s, classToken(info.className)
    elseif button.buttonType == _G.FRIENDS_BUTTON_TYPE_BNET then
        local acc = C_BattleNet.GetFriendAccountInfo(id)
        local game = acc and acc.gameAccountInfo
        if not (game and readable(game.isOnline) and game.isOnline) then return nil end
        if not readable(game.clientProgram) or game.clientProgram ~= _G.BNET_CLIENT_WOW then return nil end
        local char = game.characterName
        if not (type(char) == "string" and ns.CanRead(char) and char ~= "") then return nil end
        local account = _G.BNet_GetBNetAccountName and _G.BNet_GetBNetAccountName(acc)
        if not (type(account) == "string" and ns.CanRead(account)) then return nil end
        local token = classToken(game.className)
        local coop = _G.CanCooperateWithGameAccount and _G.CanCooperateWithGameAccount(acc)
        local hex = coop and classHex(token) or "ff9d9d9d"
        local lvl = levelText(game.characterLevel)
        return account .. " |c" .. hex .. "(" .. char .. (lvl and (" " .. lvl) or "") .. ")|r", token
    end
end

-- ---------------------------------------------------------------- rows --

local function deco(button)
    local d = rows[button]
    if d then return d end
    d = {}
    d.icon = mine(button:CreateTexture(nil, "ARTWORK"))
    d.icon:SetSize(ICON, ICON)
    d.icon:SetPoint("LEFT", button, "LEFT", 6, 0)
    d.line = mine(button:CreateTexture(nil, "BACKGROUND", nil, 1))
    d.line:SetColorTexture(1, 1, 1, 0.05)
    d.line:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 4, 0)
    d.line:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -4, 0)
    d.hover = mine(button:CreateTexture(nil, "HIGHLIGHT"))
    d.hover:SetAllPoints(button)
    d.hover:SetColorTexture(1, 1, 1, 0.07)
    -- the selected friend (the client's own highlight is faded): a gold bar
    -- on the left and a faint gold wash
    d.sel = mine(button:CreateTexture(nil, "BACKGROUND", nil, 2))
    d.sel:SetAllPoints(button)
    d.sel:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.08)
    d.bar = mine(button:CreateTexture(nil, "BACKGROUND", nil, 3))
    d.bar:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
    d.bar:SetPoint("TOPLEFT", button, "TOPLEFT", 0, -2)
    d.bar:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, 2)
    d.bar:SetWidth(2)
    -- the invite button: a small flat square with a plus, on the client's button
    local tp = button.travelPassButton
    if tp then
        d.inv = CreateFrame("Frame", nil, tp, "BackdropTemplate")
        d.inv:SetSize(20, 20)
        d.inv:SetPoint("CENTER", tp, "CENTER", -1, 0)
        d.inv:SetFrameLevel(math.max(0, tp:GetFrameLevel() - 1))
        d.inv:EnableMouse(false)
        ns.PixelBackdrop(d.inv, { fill = true })
        d.inv:SetBackdropColor(Skins.STRIP[1], Skins.STRIP[2], Skins.STRIP[3], 1)
        d.inv:SetBackdropBorderColor(Skins.EDGE[1], Skins.EDGE[2], Skins.EDGE[3], 1)
        d.plus = mine(tp:CreateTexture(nil, "OVERLAY"))
        d.plus:SetAtlas("uitools-icon-plus")
        d.plus:SetSize(10, 10)
        d.plus:SetPoint("CENTER", d.inv, "CENTER", 0, 0)
        d.invHover = mine(tp:CreateTexture(nil, "HIGHLIGHT"))
        d.invHover:SetAllPoints(d.inv)
        d.invHover:SetColorTexture(1, 1, 1, 0.12)
    end
    rows[button] = d
    return d
end

local function art(button)
    local tp = button.travelPassButton
    return button.background, button.highlight,
        tp and tp.NormalTexture, tp and tp.PushedTexture,
        tp and tp.DisabledTexture, tp and tp.HighlightTexture
end

-- The client's own layout of a row (FriendsListButtonTemplate). fresh: the
-- client has just filled the row, so its name text is already its own.
local function restoreRow(button, d, fresh)
    local name, status, icon = button.name, button.status, button.gameIcon
    name:ClearAllPoints(); name:SetPoint("TOPLEFT", button, "TOPLEFT", 20, -4); name:SetWidth(226)
    button.info:SetWidth(260)
    status:ClearAllPoints(); status:SetPoint("TOPLEFT", button, "TOPLEFT", 4, -3); status:SetSize(16, 16)
    icon:ClearAllPoints(); icon:SetPoint("TOPRIGHT", button, "TOPRIGHT", -23, -5); icon:SetSize(24, 24)
    if d.rewritten and d.orig and not fresh then name:SetText(d.orig) end
    d.rewritten = false
    local fav = button.Favorite
    if fav and fav:IsShown() then
        fav:ClearAllPoints()
        fav:SetPoint("TOPLEFT", name, "TOPLEFT", name:GetStringWidth(), 0)
    end
    d.icon:Hide(); d.line:Hide(); d.hover:Hide(); d.sel:Hide(); d.bar:Hide()
    if d.inv then d.inv:Hide(); d.plus:Hide(); d.invHover:Hide() end
end

-- fresh: called right after the client filled the row (its text is its own);
-- otherwise a repaint of a row that may carry our text already.
local function paintRow(button, fresh)
    if not (button and button.name and button.status and button.gameIcon) then return end
    local d = deco(button)
    if fresh then d.rewritten = false end
    if not on() then
        if d.line:IsShown() then restoreRow(button, d, fresh) end
        return
    end
    for _, t in ipairs({ art(button) }) do Skins.Fade(t) end
    d.line:Show(); d.hover:Show()
    local ff = _G.FriendsFrame
    local picked = ff.selectedFriendType == button.buttonType and ff.selectedFriend == button.id
    d.sel:SetShown(picked); d.bar:SetShown(picked)

    -- the name first: the status dot and the star go behind its end
    local name = button.name
    local text, token = nameFor(button)
    if text and d.rewritten then
        name:SetText(text)
    elseif text then
        local cur = name:GetText()
        if type(cur) == "string" and ns.CanRead(cur) then
            d.orig = cur
            name:SetText(text)
            d.rewritten = true
        end
    end
    name:ClearAllPoints()
    name:SetPoint("TOPLEFT", button, "TOPLEFT", ICON + 14, -5)
    -- a favourite's star needs room behind the dot, before the invite button
    local fav = button.Favorite
    local starred = fav and fav:IsShown()
    local room = starred and 172 or 206
    name:SetWidth(room)
    button.info:SetWidth(214)
    local w = math.min(name:GetStringWidth() or 0, room)
    local status = button.status
    status:ClearAllPoints()
    status:SetSize(13, 13)
    status:SetPoint("LEFT", name, "LEFT", w + 3, 0)
    if starred then
        fav:ClearAllPoints()
        fav:SetPoint("LEFT", name, "LEFT", w + 17, 0)
    end

    -- the icon on the left: the client's game icon, else ours
    local gi = button.gameIcon
    gi:ClearAllPoints()
    gi:SetPoint("LEFT", button, "LEFT", 6, 0)
    gi:SetSize(ICON, ICON)
    local summon = button.summonButton
    local icon = d.icon
    -- the summon button sits on the game icon only for Battle.net friends;
    -- a character friend's sits on the right
    local summonLeft = summon and summon:IsShown() and button.buttonType == _G.FRIENDS_BUTTON_TYPE_BNET
    if gi:IsShown() or summonLeft then
        icon:Hide()
    else
        local online = text ~= nil
        if button.buttonType == _G.FRIENDS_BUTTON_TYPE_WOW then
            if not token then
                local info = C_FriendList.GetFriendInfoByIndex(button.id)
                token = info and classToken(info.className)
            end
            local tex, c = ns:GetClassIcon(token)
            if tex then
                icon:SetTexture(tex)
                icon:SetTexCoord(c[1], c[2], c[3], c[4])
            else
                online = nil                -- no class known: no icon
            end
        else
            icon:SetTexCoord(0, 1, 0, 1)
            local ok = pcall(C_Texture.SetTitleIconTexture, icon, _G.BNET_CLIENT_APP or "App",
                Enum.TitleIconVersion.Medium)
            if not ok then icon:SetTexture("Interface\\FriendsFrame\\Battlenet-Portrait") end
        end
        if online == nil then
            icon:Hide()
        else
            icon:SetDesaturated(not online)
            icon:SetAlpha(online and 1 or 0.45)
            icon:Show()
        end
    end

    if d.inv then
        d.inv:Show(); d.plus:Show(); d.invHover:Show()
        local enabled = button.travelPassButton:IsEnabled()
        d.plus:SetDesaturated(not enabled)
        d.plus:SetAlpha(enabled and 0.9 or 0.3)
    end
end

-- A divider between online and offline friends: its gold line faded, a
-- thin line of ours. A pending-invite header: its rock and button art
-- faded (the arrows and the flash stay), a strip of ours under it.
local function paintOther(frame)
    local get = frame.GetElementData
    local data = get and get(frame)
    local divider = type(data) == "table" and data.buttonType == _G.FRIENDS_BUTTON_TYPE_DIVIDER
    local header = frame.BG and frame.RightArrow and frame.DownArrow
    if not (divider or header) then return end
    local t = lines[frame]
    if not on() then
        if t then t:Hide() end
        return
    end
    if not t then
        t = mine(frame:CreateTexture(nil, "BACKGROUND", nil, -1))
        if divider then
            t:SetColorTexture(Skins.EDGE[1], Skins.EDGE[2], Skins.EDGE[3], 1)
            t:SetPoint("LEFT", frame, "LEFT", 8, 0)
            t:SetPoint("RIGHT", frame, "RIGHT", -8, 0)
            t:SetHeight(ns:Pixel(frame, 1))
        else
            t:SetColorTexture(Skins.STRIP[1], Skins.STRIP[2], Skins.STRIP[3], 1)
            t:SetAllPoints(frame)
        end
        lines[frame] = t
    end
    if divider then
        fadeTextures(frame)
    else
        fadeTextures(frame, { [frame.RightArrow] = true, [frame.DownArrow] = true, [frame.Flash] = true })
    end
    t:Show()
end

local function paintFrame(frame)
    if frame.travelPassButton then paintRow(frame, false) else paintOther(frame) end
end

local function paintList()
    local box = _G.FriendsListFrame and _G.FriendsListFrame.ScrollBox
    if box and type(box.ForEachFrame) == "function" then box:ForEachFrame(paintFrame) end
end

-- ---------------------------------------------------------------- tabs --

local function paintTabs(show)
    local sel = _G.PanelTemplates_GetSelectedTab and _G.PanelTemplates_GetSelectedTab(_G.FriendsFrame)
    for _, e in ipairs(tabs) do
        local tab = e.tab
        if show then
            fadeTextures(tab)
            if not e.panel then
                e.panel = Skins.Panel(tab, Skins.STRIP, e.top and -1 or -4)
                e.panel:SetFrameLevel(math.max(0, tab:GetFrameLevel() - 1))
            end
            local picked
            if e.top then picked = tab.IsSelected and tab:IsSelected()
            else picked = sel ~= nil and sel == tab:GetID() end
            local c = picked and GOLD or Skins.EDGE
            e.panel:SetBackdropBorderColor(c[1], c[2], c[3], c[4])
            e.panel:Show()
        elseif e.panel then
            e.panel:Hide()
        end
    end
end

local function collectTabs()
    local ff = _G.FriendsFrame
    for _, tab in ipairs(ff.Tabs or {}) do tabs[#tabs + 1] = { tab = tab } end
    local sys = ff.FriendsTabHeader and ff.FriendsTabHeader.TabSystem
    if sys then
        for _, tab in ipairs({ sys:GetChildren() }) do
            if type(tab.GetTabID) == "function" then
                tabs[#tabs + 1] = { tab = tab, top = true }
                if type(tab.SetTabSelected) == "function" then
                    hooksecurefunc(tab, "SetTabSelected", function() paintTabs(on()) end)
                end
            end
        end
    end
end

-- ---------------------------------------------------------------- header --

local function battleTag()
    local _, tag = BNGetInfo()
    if type(tag) == "string" and ns.CanRead(tag) and tag ~= "" then return tag end
end

local function paintCopy()
    if not copyBtn then return end
    local bn = _G.FriendsFrame.FriendsTabHeader.BattlenetFrame
    copyBtn:SetShown(on() and bn.Tag:IsShown() and battleTag() ~= nil)
end

local function buildHeader()
    local bn = _G.FriendsFrame.FriendsTabHeader.BattlenetFrame
    copyBtn = CreateFrame("Button", nil, bn)
    copyBtn:SetSize(14, 14)
    copyBtn:SetPoint("LEFT", bn.Tag, "RIGHT", 5, 0)
    local t = copyBtn:CreateTexture(nil, "ARTWORK")
    t:SetAtlas("friends-icon-battlenet-copy")
    t:SetAllPoints(copyBtn)
    t:SetVertexColor(0.8, 0.8, 0.85)
    copyBtn:SetScript("OnEnter", function(self)
        t:SetVertexColor(1, 1, 1)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["Copy BattleTag"])
        GameTooltip:Show()
    end)
    copyBtn:SetScript("OnLeave", function()
        t:SetVertexColor(0.8, 0.8, 0.85)
        GameTooltip:Hide()
    end)
    copyBtn:SetScript("OnClick", function()
        local tag = battleTag()
        if tag then ns.UI:ShowCopyDialog(L["Copy BattleTag"], tag) end
    end)
    copyBtn:Hide()

    -- the contacts menu: three bars instead of the arrow
    local menu = bn.ContactsMenuButton
    if menu then
        local bars = {}
        for i = 1, 3 do
            local b = mine(menu:CreateTexture(nil, "OVERLAY"))
            b:SetColorTexture(0.85, 0.85, 0.88, 1)
            b:SetSize(12, 2)
            b:SetPoint("CENTER", menu, "CENTER", 0, (2 - i) * 4)
            b:Hide()
            bars[i] = b
        end
        Friends.menuBars = bars
    end
    -- the status dropdown: a thin chevron instead of the gold arrow
    local dd = _G.FriendsFrame.FriendsTabHeader.StatusDropdown
    if dd then
        local c = mine(dd:CreateTexture(nil, "OVERLAY"))
        c:SetAtlas("uitools-icon-chevron-down")
        c:SetSize(10, 10)
        c:SetPoint("RIGHT", dd, "RIGHT", -6, 0)
        c:Hide()
        Friends.chevron = c
    end
end

-- ---------------------------------------------------------------- window --

local function windowArt()
    local ff = _G.FriendsFrame
    local list = {}
    local function add(t) if t then list[#list + 1] = t end end
    add(ff.NineSlice); add(ff.Bg or _G.FriendsFrameBg); add(ff.TopTileStreaks)
    add(ff.PortraitContainer); add(_G.FriendsFrameIcon)
    add(_G.FriendsFrameButtonBottomBorder)
    local inset = ff.Inset or _G.FriendsFrameInset
    if inset then add(inset.NineSlice); add(inset.Bg) end
    local bn = ff.FriendsTabHeader and ff.FriendsTabHeader.BattlenetFrame
    if bn then
        for _, r in ipairs({ bn:GetRegions() }) do
            if r:GetObjectType() == "Texture" then add(r) end
        end
    end
    return list
end

function Friends.Apply()
    local ff = _G.FriendsFrame
    if not (ready and ff) then return end
    local show = on()
    if show then
        ground = ground or Skins.Ground(ff, Skins.BG)
        for _, r in ipairs(windowArt()) do Skins.Fade(r) end
    end
    if ground then ground:SetShown(show) end
    Skins.FlatClose(ff.CloseButton or _G.FriendsFrameCloseButton, show)
    Skins.FlatScrollBar(_G.FriendsListFrame and _G.FriendsListFrame.ScrollBar, show)

    local head = ff.FriendsTabHeader
    flatButton(head.StatusDropdown, show)
    flatButton(head.BattlenetFrame.ContactsMenuButton, show)
    for _, b in ipairs(Friends.menuBars or {}) do b:SetShown(show) end
    if Friends.chevron then Friends.chevron:SetShown(show) end
    flatButton(_G.FriendsFrameAddFriendButton, show)
    flatButton(_G.FriendsFrameSendMessageButton, show)
    paintTabs(show)
    paintCopy()
    paintList()
end

local function setup()
    local ff = _G.FriendsFrame
    if ready or not (ff and ff.FriendsTabHeader and _G.FriendsListFrame
        and _G.FriendsFrame_UpdateFriendButton) then return end
    ready = true
    buildHeader()
    collectTabs()
    hooksecurefunc("FriendsFrame_UpdateFriendButton", function(button) paintRow(button, true) end)
    -- a click selects without refilling the rows
    if _G.FriendsFrame_FriendButtonSetSelection then
        hooksecurefunc("FriendsFrame_FriendButtonSetSelection", function(button, selected)
            local d = rows[button]
            if d and on() then d.sel:SetShown(selected and true or false); d.bar:SetShown(selected and true or false) end
        end)
    end
    if _G.FriendsFrame_CheckBattlenetStatus then
        hooksecurefunc("FriendsFrame_CheckBattlenetStatus", paintCopy)
    end
    if _G.PanelTemplates_SetTab then
        hooksecurefunc("PanelTemplates_SetTab", function(frame)
            if frame == ff then paintTabs(on()) end
        end)
    end
    -- dividers and invite headers have no fill function of their own
    local box = _G.FriendsListFrame.ScrollBox
    local ev = _G.ScrollBoxListMixin and _G.ScrollBoxListMixin.Event
    if ev and ev.OnInitializedFrame and box.RegisterCallback then
        box:RegisterCallback(ev.OnInitializedFrame, function(_, frame)
            if not frame.travelPassButton then paintOther(frame) end
        end, Friends)
    end
    ff:HookScript("OnShow", function() paintTabs(on()); paintCopy() end)
    Friends.Apply()
end

function Friends.Enable(mod)
    if C_AddOns.IsAddOnLoaded("Blizzard_FriendsFrame") then setup() end
    mod:RegisterEvent("ADDON_LOADED", function(_, name)
        if name == "Blizzard_FriendsFrame" then setup() end
    end)
end
