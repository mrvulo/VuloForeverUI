-- VuloForeverUI / Modules / Skins / Social
--
-- The social window Forever opens with O (Blizzard_SocialUI: SocialUIFrame,
-- the Friends tab is FriendsListSocialViewTemplate from Blizzard_FriendsFrame)
-- in the flat dark look of the "Friends list" card. The window brings its own
-- search field, filter, groups, BattleTag copy button and menu button; we
-- only change how they look:
--
--   window     our ground, portrait/frame/fade art faded, a flat close X
--   header     status dropdown, menu button, search field, filter: flat
--   list       every friend card a flat dark row with a thin line, a hover
--              wash and a gold bar while selected; the invite and summon
--              buttons flat squares; group headers flat strips
--   bottom     "Add Friend" flat, the scroll bar thin
--
-- Cards and headers come from the list's ScrollBox; its "frame initialized"
-- callback dresses each one after the client filled it. A card's selection
-- changes without a refill, so its SetSelected is post-hooked.
--
-- TAINT: as in Friends.lua -- art only faded, our textures and frames on
-- top, nothing hidden, reparented or moved, no data provider of ours. The
-- older window (Friends.lua) stays skinned for when the client uses it.
local _, ns = ...
local Skins = ns.Skins

local Social = {}
Skins.Social = Social
table.insert(Skins.parts, Social)

local GOLD = { 1, 0.82, 0 }
local CARD = { 0.085, 0.085, 0.10, 1 }

local ready, ground
local registered = setmetatable({}, { __mode = "k" })   -- list content frame -> true
local cards = setmetatable({}, { __mode = "k" })        -- card / header -> our textures
local chevrons = setmetatable({}, { __mode = "k" })     -- dropdown -> our arrow

local function on()
    local db = Skins.db()
    return Skins.mod.active and db.friends and db.friendsStyle == "modern" or false
end

-- a flat row ground of ours on a client button: fill, bottom line, hover wash
local function rowGround(frame, color)
    local mine = Skins.Mine
    local d = {}
    d.bg = mine(frame:CreateTexture(nil, "BACKGROUND", nil, -1))
    d.bg:SetAllPoints(frame)
    d.bg:SetColorTexture(color[1], color[2], color[3], color[4])
    d.line = mine(frame:CreateTexture(nil, "BACKGROUND", nil, 1))
    d.line:SetColorTexture(Skins.EDGE[1], Skins.EDGE[2], Skins.EDGE[3], 0.6)
    d.line:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    d.line:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    d.line:SetHeight(ns:Pixel(frame, 1))
    d.hover = mine(frame:CreateTexture(nil, "HIGHLIGHT"))
    d.hover:SetAllPoints(frame)
    d.hover:SetColorTexture(1, 1, 1, 0.06)
    return d
end

local function showGround(d, show)
    d.bg:SetShown(show); d.line:SetShown(show); d.hover:SetShown(show)
end

local function actionButton(b, show)
    if not b then return end
    Skins.FlatButton(b, show, b.ActionIcon and { [b.ActionIcon] = true } or nil)
end

local function locked(card)
    return type(card.IsHighlightLocked) == "function" and card:IsHighlightLocked() or false
end

local function paintCard(card)
    local d = cards[card]
    local show = on()
    if not d then
        if not show then return end
        d = rowGround(card, CARD)
        d.bar = Skins.Mine(card:CreateTexture(nil, "BACKGROUND", nil, 2))
        d.bar:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
        d.bar:SetPoint("TOPLEFT", card, "TOPLEFT", 0, 0)
        d.bar:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 0, 0)
        d.bar:SetWidth(2)
        cards[card] = d
        if type(card.SetSelected) == "function" then
            hooksecurefunc(card, "SetSelected", function(_, selected)
                d.bar:SetShown(on() and selected and true or false)
            end)
        end
    end
    if show then
        Skins.Fade(card.Background)
        Skins.Fade(card:GetHighlightTexture())
    end
    showGround(d, show)
    d.bar:SetShown(show and locked(card))
    actionButton(card.PartyButton, show)
    actionButton(card.RAFSummonButton, show)
end

local function paintHeader(h)
    local d = cards[h]
    local show = on()
    if not d then
        if not show then return end
        d = rowGround(h, Skins.STRIP)
        cards[h] = d
    end
    if show then Skins.FadeTextures(h) end
    showGround(d, show)
end

local function paintFrame(frame)
    if frame.PartyButton and frame.PresenceHolder then
        paintCard(frame)
    elseif frame.CollapseButton and frame.ButtonText then
        paintHeader(frame)
    end
end

-- a thin chevron of ours on a flat dropdown (its own arrow is faded)
local function chevron(dd, show)
    if not dd then return end
    local c = chevrons[dd]
    if not c then
        if not show then return end
        c = Skins.Mine(dd:CreateTexture(nil, "OVERLAY"))
        c:SetAtlas("uitools-icon-chevron-down")
        c:SetSize(10, 10)
        c:SetPoint("RIGHT", dd, "RIGHT", -6, 0)
        chevrons[dd] = c
    end
    c:SetShown(show)
end

local function windowArt(f)
    local list = {}
    local function add(t) if t then list[#list + 1] = t end end
    add(f.NineSlice); add(f.Bg); add(f.TopTileStreaks); add(f.PortraitContainer)
    add(f.TopFade); add(f.BottomFade)
    local bar = f.BattleNetBar
    if bar then
        add(bar.Background)
        if bar.ControlsContainer then add(bar.ControlsContainer.BattleNetBackground) end
    end
    local fl = f.FriendsList
    if fl then add(fl.TopDivider); add(fl.BottomDivider) end
    return list
end

-- The Friends tab's content: its ScrollBox calls us for every frame it fills.
local function register(fl)
    if registered[fl] or not (fl and fl.ScrollBox) then return end
    local ev = _G.ScrollBoxListMixin and _G.ScrollBoxListMixin.Event
    if not (ev and ev.OnInitializedFrame and fl.ScrollBox.RegisterCallback) then return end
    registered[fl] = true
    fl.ScrollBox:RegisterCallback(ev.OnInitializedFrame, function(_, frame) paintFrame(frame) end, Social)
end

function Social.Apply()
    local f = _G.SocialUIFrame
    if not (ready and f) then return end
    local show = on()
    if show then
        ground = ground or Skins.Ground(f, Skins.BG)
        for _, r in ipairs(windowArt(f)) do Skins.Fade(r) end
    end
    if ground then ground:SetShown(show) end
    Skins.FlatClose(f.CloseButton, show)

    local cc = f.BattleNetBar and f.BattleNetBar.ControlsContainer
    if cc then
        Skins.FlatButton(cc.OnlineStatusDropdown, show)
        chevron(cc.OnlineStatusDropdown, show)
        local menu = cc.BattleNetMenuButton
        if menu then Skins.FlatButton(menu, show, menu.Icon and { [menu.Icon] = true } or nil) end
    end

    local fl = f.FriendsList
    if fl then
        register(fl)
        local bar = fl.FilterBar
        if bar then
            local sb = bar.SearchBar
            if sb then
                Skins.FlatButton(sb, show, sb.searchIcon and { [sb.searchIcon] = true } or nil)
                if show and sb.NineSlice then Skins.Fade(sb.NineSlice) end
            end
            Skins.FlatButton(bar.SearchFilterDropdown, show)
            chevron(bar.SearchFilterDropdown, show)
        end
        Skins.FlatButton(fl.ActionButton, show)
        Skins.FlatScrollBar(fl.ScrollBar, show)
        if fl.ScrollBox and type(fl.ScrollBox.ForEachFrame) == "function" then
            fl.ScrollBox:ForEachFrame(paintFrame)
        end
    end
end

local function setup()
    local f = _G.SocialUIFrame
    if ready or not f then return end
    ready = true
    -- the Friends tab's content is built with the window's tabs; look again
    -- on every open in case it came later
    f:HookScript("OnShow", function() Social.Apply() end)
    Social.Apply()
end

function Social.Enable(mod)
    if _G.SocialUIFrame then setup() end
    mod:RegisterEvent("ADDON_LOADED", function(_, name)
        if name == "Blizzard_SocialUI" or name == "Blizzard_FriendsFrame" then setup() end
    end)
end
