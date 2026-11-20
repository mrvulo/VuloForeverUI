-- VuloForeverUI / Modules / QoL / Windows
--
-- The game's own windows, movable: grab one by its title bar, put it where
-- you want it, and it opens there from then on.
--
-- HOW THE CLIENT PLACES A WINDOW
--
-- Its panel manager gives every window a slot (left, centre, right) and
-- writes the place with ClearAllPoints + SetPoint each time a window opens or
-- closes (UpdateUIPanelPositions). A window that was only dragged would jump
-- back the moment its neighbour closes. So the place is remembered, and a
-- hook behind the window's SetPoint puts it back whenever the client has
-- just written its own.
--
-- WHAT IS TOUCHED, AND WHAT IS NOT
--
--   * The grip is a frame of OURS over the title bar. No script of the
--     window is replaced or hooked, nothing is written into its table.
--   * Only the window's place changes -- never its parent, its visibility or
--     its slot in the panel manager, and no function of the client's is
--     called to "refresh" anything.
--   * A protected window cannot be placed during a fight. It is neither
--     dragged nor put back then; it shows where the client put it until the
--     fight ends, and a drag still running when a fight starts is ended.
--   * A window the client shows maximized (the world map) is left alone
--     while it is.
--
-- The place is saved as the window's top left corner measured from the bottom
-- left of the screen, in the window's own units, per profile.
local _, ns = ...
local L = ns.L

local QoL = ns.QoL
local Windows = QoL.RegisterPart("windows", {})
QoL.Windows = Windows

-- Every window that gets a grip, by its global name. A name this client does
-- not have, or whose addon has not loaded yet, is simply skipped until it
-- exists. Not in the list on purpose: the loot window (Edit Mode places it),
-- the game menu and the settings window (the client moves those itself),
-- full-screen scenes, and mail's reading pane (it hangs on the mail window).
local NAMES = {
    "CharacterFrame", "PlayerSpellsFrame", "ProfessionsBookFrame", "ProfessionsFrame",
    "WorldMapFrame", "QuestFrame", "QuestLogPopupDetailFrame", "GossipFrame", "ItemTextFrame",
    "MerchantFrame", "MailFrame", "TradeFrame", "AuctionHouseFrame", "TaxiFrame",
    "ClassTrainerFrame", "TabardFrame", "GuildRegistrarFrame", "PetitionFrame", "PetStableFrame",
    "FriendsFrame", "CommunitiesFrame", "GuildControlUI", "GuildBankFrame", "ChannelFrame",
    "RaidParentFrame", "LFGParentFrame", "PVEFrame", "EncounterJournal",
    "CollectionsJournal", "AchievementFrame", "CalendarFrame", "TimeManagerFrame",
    "InspectFrame", "DressUpFrame", "ItemSocketingFrame", "ItemUpgradeFrame", "WeeklyRewardsFrame",
    "GenericTraitFrame", "DeathRecapFrame", "MacroFrame", "AddonList", "HelpFrame",
}

-- The grip covers the title bar between the portrait on the left and the
-- buttons on the right (close, and on some windows minimize/maximize).
local GRIP_LEFT, GRIP_RIGHT, GRIP_HEIGHT = 56, 56, 20

-- A window whose top strip is in use gets its grip somewhere else: `over`
-- names a child of the window the grip lies on instead.
local SPECIAL = {
    -- filter and search field sit in the top strip; the plate with the
    -- points above the window is free
    AchievementFrame = { over = "Header" },
    -- help button on the left, minimize/maximize beside the close button
    WorldMapFrame = { left = 70, right = 90 },
}

local adopted = {}      -- [name] = { frame, grip, moving }
local applying          -- our own SetPoint is running
local registered

local function db() return QoL.db().windows end

local function active()
    return QoL.mod.active and db().move and true or false
end

local function places()
    local d = db()
    if type(d.pos) ~= "table" then d.pos = {} end
    return d.pos
end

-- A protected window may not be placed or dragged from addon code in a fight.
local function locked(frame)
    return InCombatLockdown() and frame:IsProtected()
end

local function maximized(frame)
    local fn = frame.IsMaximized
    if type(fn) ~= "function" then return false end
    local ok, yes = pcall(fn, frame)
    return ok and yes and true or false
end

local placeAll

-- Put a window back where the player left it.
local function place(name)
    local entry = adopted[name]
    if not (entry and active()) or entry.moving then return end
    local pos = places()[name]
    if type(pos) ~= "table" or type(pos.x) ~= "number" or type(pos.y) ~= "number" then return end
    local frame = entry.frame
    if maximized(frame) then return end
    if locked(frame) then
        ns:RunOutOfCombatOnce("qol_windows_place", placeAll)
        return
    end
    applying = true
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos.x, pos.y)
    applying = false
end

function placeAll()
    for name, entry in pairs(adopted) do
        if entry.frame:IsShown() then place(name) end
    end
end

local function remember(name, frame)
    local x, y = frame:GetLeft(), frame:GetTop()
    if type(x) ~= "number" or type(y) ~= "number" then return end
    places()[name] = { x = x, y = y }
end

local function dragStart(name)
    local entry = adopted[name]
    local frame = entry.frame
    if not active() or entry.moving or locked(frame) or maximized(frame) then return end
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:StartMoving()
    entry.moving = true
end

local function dragStop(name)
    local entry = adopted[name]
    if not entry.moving then return end
    entry.moving = nil
    local frame = entry.frame
    frame:StopMovingOrSizing()
    -- Not the client's own layout cache: the place is ours to keep, and a
    -- "user placed" window is one the panel manager stops looking after.
    pcall(frame.SetUserPlaced, frame, false)
    remember(name, frame)
    place(name)
end

-- A fight is about to lock the protected windows: whatever is still being
-- dragged is set down now, while that is still allowed.
local function stopAll()
    for name, entry in pairs(adopted) do
        if entry.moving then dragStop(name) end
    end
end

local function adopt(name)
    if adopted[name] then return end
    local frame = _G[name]
    if type(frame) ~= "table" or type(frame.GetObjectType) ~= "function" then return end
    if frame.IsForbidden and frame:IsForbidden() then return end
    if type(frame.SetPoint) ~= "function" or type(frame.StartMoving) ~= "function" then return end

    local spec = SPECIAL[name]
    local host = spec and spec.over and frame[spec.over]
    if spec and spec.over and (type(host) ~= "table" or type(host.GetObjectType) ~= "function") then
        return      -- the part the grip would lie on is not there: no grip
    end
    local grip = CreateFrame("Frame", nil, frame)
    if host then
        grip:SetAllPoints(host)
    else
        grip:SetPoint("TOPLEFT", frame, "TOPLEFT", spec and spec.left or GRIP_LEFT, -1)
        grip:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -(spec and spec.right or GRIP_RIGHT), -1)
        grip:SetHeight(GRIP_HEIGHT)
    end
    -- Above the window's own pages: several of them cover the whole window,
    -- title bar included, and would take the click.
    grip:SetFrameLevel(math.min(9990, frame:GetFrameLevel() + 500))
    grip:EnableMouse(true)
    grip:RegisterForDrag("LeftButton")
    grip:SetScript("OnDragStart", function() dragStart(name) end)
    grip:SetScript("OnDragStop", function() dragStop(name) end)
    grip:SetScript("OnHide", function() dragStop(name) end)
    grip:SetShown(active())

    adopted[name] = { frame = frame, grip = grip }
    hooksecurefunc(frame, "SetPoint", function()
        if applying then return end
        place(name)
    end)
    if frame:IsShown() then place(name) end
end

-- Grips are made out of combat only: a child may not be hung onto a
-- protected window during a fight.
local function adoptAll()
    for _, name in ipairs(NAMES) do adopt(name) end
end

local function scan()
    if not active() then return end
    ns:RunOutOfCombatOnce("qol_windows_scan", adoptAll)
end

-- The options button. A window that is open stays where it is until the
-- client next places it -- nothing of the client's is called to hurry that.
function Windows.Reset()
    db().pos = {}
    ns:Print(L["Window positions reset. Each window is back in its own place the next time it opens."])
end

function Windows.Apply()
    local on = active()
    for _, entry in pairs(adopted) do entry.grip:SetShown(on) end
    if on ~= registered then
        registered = on
        QoL.SyncEvent(on, "ADDON_LOADED", scan)
        QoL.SyncEvent(on, "PLAYER_ENTERING_WORLD", scan)
        QoL.SyncEvent(on, "PLAYER_REGEN_DISABLED", stopAll)
    end
    if on then
        scan()
        placeAll()
    end
end

function Windows.Disable()
    stopAll()
    for _, entry in pairs(adopted) do entry.grip:Hide() end
    if not registered then return end
    registered = nil
    ns:UnregisterEvent("ADDON_LOADED", scan)
    ns:UnregisterEvent("PLAYER_ENTERING_WORLD", scan)
    ns:UnregisterEvent("PLAYER_REGEN_DISABLED", stopAll)
end
