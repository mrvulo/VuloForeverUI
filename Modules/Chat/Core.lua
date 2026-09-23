-- VuloForeverUI / Modules / Chat / Core
--
-- Our own chat display, drawn on top of the client's own chat windows.
--
-- THE SHAPE OF THIS MODULE, AND WHY IT IS THAT SHAPE
--
-- Blizzard's chat frames stay. They keep receiving every message, they keep
-- their hyperlink hit zones, they keep their dock and their tabs, and they keep
-- doing all of it in the client's own secure code. What we do is draw the lines
-- a second time, in our own font on our own panel, and make the client's copy
-- invisible -- so the text you see is ours and the click that opens an item
-- link is still theirs.
--
-- THE FOUR RULES EVERYTHING HERE OBEYS
--
-- Chat is the most taint-sensitive corner of the interface, because the secure
-- whisper path walks through the dock, the tabs and the message handler on
-- every line. Four rules, each of which is a bug somebody has already had:
--
--   1. NEVER write a field on a Blizzard chat frame. A field we set stays
--      tainted for the session, and the secure code that reads it later dies
--      on the secret values a whisper carries. Our per-frame state lives in
--      the side table below, keyed by the frame.
--   2. NEVER reparent a Blizzard chat widget, and never hook an FCF_ function.
--      Both taint the secure pass that touches them afterwards -- and for the
--      FCF_ ones it is the CALLER that is tainted, so deferring the body of
--      the hook does not help. Visuals are suppressed with alpha and mouse
--      state only, and window management is left entirely to the client.
--   3. NEVER compare a chat string before asking whether it is secret. In an
--      instance, in a raid and on every Battle.net whisper the text can arrive
--      secret, and on a secret even `text == ""` throws. A secret string is
--      passed on WHOLE -- no concatenation, no gsub, no measuring.
--   4. NEVER touch chat during the client's own execution. Everything runs
--      from our own deferred passes, so we are never half-way through a loop
--      of Blizzard's when we change something under it.
local _, ns = ...
local L = ns.L

local Chat = {}
ns.Chat = Chat

Chat.MAX_LINES = 128        -- what our own message frame keeps per window

local mod = ns:RegisterModule("chat", {
    name        = "Chat",
    group       = "General",
    description = "Draws the chat in the suite's own style, with its own tabs, its own side buttons and a scrollback that survives a reload.",
    defaults = {
        -- Off out of the box. This module draws over the client's chat
        -- windows, which is the last thing anyone wants to discover by
        -- surprise at a first login.
        enabled = false,

        -- The panel
        visibility   = "always",    -- always | mouseover | never
        lockChatSize = false,       -- the main window's resize grip
        bgColor      = { r = 0.03, g = 0.045, b = 0.05, a = 0.65 },
        bgTexture    = "",          -- empty: the flat fill, no shared-media bar
        borderSize   = 1,
        borderColor  = { r = 1, g = 1, b = 1, a = 0.18 },
        showBorder   = true,
        padding      = 6,

        -- The text
        fontSize     = 12,
        fontOutline  = "NONE",
        timestamps   = true,
        timestampFormat = "%H:%M",
        timestampColor  = { r = 0.5, g = 0.5, b = 0.55 },
        classColorNames = true,

        -- The tabs
        -- Only the two things that are ours to decide. The height, the spacing
        -- and the padding of a tab belong to the client's strip, which our
        -- ghosts sit exactly on top of -- setting them here would mean moving
        -- the client's tabs, and moving those is how the whisper path breaks.
        -- Everything below is drawn INSIDE the ghost's rectangle, which is the
        -- real tab's rectangle. That is the line: colour, font, padding and a
        -- border of our own are ours to set, because they change what is
        -- painted in that box. Height, spacing and alignment would change the
        -- box itself, and the box is the client's click target.
        tabFontSize  = 11,
        tabFont      = "",          -- empty: whatever the chat font is
        tabTextColor       = { r = 0.6, g = 0.6, b = 0.62 },
        tabTextColorActive = { r = 1, g = 1, b = 1 },
        -- Both transparent out of the box. These are new, and a new setting
        -- that paints something is a new setting that changes the look of a
        -- chat nobody asked to have changed.
        tabBgColor         = { r = 0.03, g = 0.045, b = 0.05, a = 0 },
        tabBgColorActive   = { r = 0.03, g = 0.045, b = 0.05, a = 0 },
        tabTexture         = "",
        tabPaddingX        = 0,

        activeUnderline = true,
        underlineSize   = 2,
        -- On, the underline follows the suite's accent colour and the custom
        -- one below is ignored. Off, the custom colour is used as it stands.
        underlineAccent = true,
        underlineColor  = { r = 0.05, g = 0.82, b = 0.61, a = 0.9 },

        -- On, the tab border copies the panel's border settings. Off, the
        -- three below apply.
        --
        -- Off by default, and the size at zero with it: syncing by default
        -- would put a border on every tab that never had one, because the
        -- panel's own border IS on by default. A new setting starts by
        -- changing nothing.
        tabBorderSync   = false,
        tabBorderSize   = 0,
        tabBorderColor       = { r = 1, g = 1, b = 1, a = 0.18 },
        -- Same alpha as the inactive one: the two share a single opacity
        -- slider, so starting them apart would make the first drag of it look
        -- like it changed something it did not.
        tabBorderColorActive = { r = 1, g = 1, b = 1, a = 0.18 },

        -- The side buttons
        --
        -- `sidebar` stays the on/off it always was and `sidebarVisibility`
        -- holds only the two visible modes. The options row presents them as
        -- one dropdown, which is what a reader wants -- but keeping the old
        -- key as the authority means a profile saved with the column switched
        -- off still comes back with it switched off, without a migration to
        -- get wrong.
        sidebar      = true,
        sidebarVisibility = "always",   -- always | mouseover
        sidebarRight = false,
        sidebarSpacing = 10,
        sidebarScale = 1,
        -- 0 means "as wide as the icons", which is what the column has always
        -- been. A real width centres the icons in it.
        sidebarWidth = 0,
        -- Hidden, because until now there was no background at all and a new
        -- setting starts by changing nothing.
        hideSidebarBg = true,
        sidebarSeparate = false,
        sidebarSeparateSpacing = 8,
        iconColor    = { r = 1, g = 1, b = 1 },
        iconUseAccent = false,
        -- The jump-to-newest button on the chat itself rather than in the
        -- column, where the client also keeps its own.
        scrollButtonOnChat = false,
        -- Drag the icons where you want them. Positions are offsets from the
        -- top of the column, per button key, so a button that is switched off
        -- and on again comes back where it was left.
        freeMoveIcons = false,
        iconPositions = {},
        showCopy     = true,
        showFriends  = true,
        showGuild    = false,
        showSettings = true,
        showScroll   = true,
        hideTooltipOnHover = false,

        -- The input line
        inputOnTop   = false,
        inputHeight  = 23,
        inputFontSize = 12,
        -- On, the input line wears the chat font. Off, the client's own stays.
        inputUseChatFont = true,

        -- Extras
        -- A sound on an incoming whisper. Playing one needs no look at the
        -- line, which is the whole point: the text may be secret, the fact
        -- that something arrived is not.
        whisperSound = "",

        -- Behaviour
        idleFade     = true,
        idleFadeDelay = 15,
        idleFadeStrength = 40,
        history      = true,
        historyLines = 100,
    },
})
Chat.mod = mod

function Chat.db() return mod.db end

-- ---------------------------------------------------------------- state --
--
-- Everything we know about one of Blizzard's chat frames. A weak table keyed
-- by the frame, because rule 1 says the frame itself is not ours to write on.
local data = setmetatable({}, { __mode = "k" })

function Chat.Data(cf)
    local d = data[cf]
    if not d then d = {}; data[cf] = d end
    return d
end

function Chat.Frames()
    local out = {}
    for i = 1, Constants.ChatFrameConstants.MaxChatWindows do
        local cf = _G["ChatFrame" .. i]
        if cf then out[#out + 1] = cf end
    end
    return out
end

-- Is this window one the player actually has open? A window Blizzard still
-- considers unopened must NOT be touched: its pop-out seeding walks its own
-- messages, and anything of ours in that loop makes the next read come back
-- secret and the comparison inside it throw, with the pop-out half done.
function Chat.IsOpen(cf)
    local index = cf and cf.GetID and cf:GetID()
    if type(index) ~= "number" then return false end
    if FCF_IsChatWindowIndexActive then
        local ok, active = pcall(FCF_IsChatWindowIndexActive, index)
        if ok then return active and true or false end
    end
    local _, _, _, _, _, _, shown = GetChatWindowInfo(index)
    return shown and true or false
end

-- ---------------------------------------------------------------- passes --
--
-- Rule 4 in one function. Work is queued by key and runs on the next frame,
-- coalesced, so a burst of events costs one pass and nothing of ours ever
-- runs inside a loop of Blizzard's.
local queued = {}

function Chat.Queue(key, fn)
    if queued[key] then return end
    queued[key] = true
    C_Timer.After(0, function()
        queued[key] = nil
        if not mod.active then return end
        local ok, err = pcall(fn)
        if not ok then ns:Debug("chat: pass %s failed (%s)", key, tostring(err)) end
    end)
end

-- The full pass: take in any window that has appeared, restyle the ones we
-- have, and put the tabs and the side buttons where they belong.
function Chat.Refresh()
    Chat.Queue("chat.full", function()
        Chat.Engine.IntegrateAll()
        Chat.Panel.ApplyAll()
        if Chat.Tabs then Chat.Tabs.Refresh() end
        if Chat.Sidebar then Chat.Sidebar.Refresh() end
        if Chat.History then Chat.History.Replay() end
        if Chat.Fade then Chat.Fade.Install() end
    end)
end

-- ---------------------------------------------------------------- lifecycle --

function mod:OnEnable()
    -- Deferred, never synchronous at login: anchoring anything into the chat
    -- frame's rect web while the dock is still resolving makes that pass run
    -- tainted, and the dock state it leaves behind poisons every whisper
    -- window opened later in the session.
    self:RegisterEvent("PLAYER_ENTERING_WORLD", function()
        C_Timer.After(1, function()
            if mod.active then Chat.Refresh() end
        end)
    end)

    self:RegisterEvent("UPDATE_CHAT_WINDOWS", function() Chat.Refresh() end)
    self:RegisterEvent("UPDATE_FLOATING_CHAT_WINDOWS", function() Chat.Refresh() end)
    self:RegisterEvent("UPDATE_CHAT_COLOR", function() Chat.Refresh() end)

    -- A sound on an incoming whisper. The handler never looks at the payload:
    -- in an instance and on every Battle.net whisper the text arrives secret,
    -- and "something arrived" is knowable without reading a word of it.
    local function whisper()
        if not mod.active then return end
        local name = Chat.db().whisperSound
        if not name or name == "" then return end
        local file = ns.MediaSound and ns.MediaSound(name)
        if file then PlaySoundFile(file, "Master") end
    end
    self:RegisterEvent("CHAT_MSG_WHISPER", whisper)
    self:RegisterEvent("CHAT_MSG_BN_WHISPER", whisper)

    -- The size lock touches a protected frame, so it is skipped in combat and
    -- caught up here. Only the lock: a full refresh on every regen would redo
    -- the whole panel pass for a setting nobody changed.
    self:RegisterEvent("PLAYER_REGEN_ENABLED", function()
        if mod.active then Chat.Panel.ApplyLock() end
    end)

    if not Chat.profileHooked then
        Chat.profileHooked = true
        hooksecurefunc(ns, "LoadProfile", function()
            if mod.active then Chat.Refresh() end
        end)
    end

    if IsLoggedIn() then C_Timer.After(1, function()
        if mod.active then Chat.Refresh() end
    end) end

    ns:RegisterSlash({ key = "CHAT", commands = { "/vfchat" },
        desc = "Open the chat settings.",
    })
end

ns.Slash.CHAT = function()
    local f = ns.UI:CreateMainFrame()
    f:Show()
    ns.UI:PopulateSidebar()
    ns.UI:ShowModulePage("chat")
end

-- Switching the module off gives the client's own chat back: the alpha we
-- took away is returned, and our own surfaces go away. What cannot be undone
-- is said out loud rather than pretended away -- hooks do not come off, so a
-- clean state is a reload.
function mod:OnDisable()
    Chat.Engine.Release()
    Chat.Panel.Release()
    if Chat.Tabs then Chat.Tabs.Release() end
    if Chat.Sidebar then Chat.Sidebar.Release() end
    if Chat.Fade then Chat.Fade.Release() end
    ns:Print(L["The chat is the client's again. A reload puts the last of it back."])
end
