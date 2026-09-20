-- VuloForeverUI / Modules / Chat / Panel
--
-- The panel a window is drawn on: the background, the border, and where our
-- message surface sits over the client's.
--
-- HOW THE PANEL IS PLACED, AND WHY NOT THE OBVIOUS WAY
--
-- The obvious way is to anchor our panel to the chat frame and be done. That
-- is exactly what must not happen: it puts an addon frame into the client's
-- own anchor web, and the secure pass that resolves the dock then resolves
-- through us. So the panel is placed NUMERICALLY -- the chat frame's rectangle
-- is read, converted into screen coordinates, and our frames are pinned to
-- UIParent at those numbers. Nothing of ours ever appears in a Blizzard rect
-- chain, and the two still sit on top of each other to the pixel.
--
-- The rectangle itself may come back secret on this client, which is why every
-- read is gated: an unreadable rect means the panel keeps the place it had,
-- rather than jumping to a guess.
local _, ns = ...
local L = ns.L
local Chat = ns.Chat

local Panel = {}
Chat.Panel = Panel

-- The chat frame's rectangle, in UIParent's coordinates, or nothing.
local function readable(v)
    return ns.CanRead(v) and type(v) == "number"
end

local function rectOf(cf)
    local ok, left, bottom, width, height = pcall(cf.GetRect, cf)
    if not ok then return nil end
    -- Each value on its own, never a table walk: GetRect answers with plain
    -- NILS for a frame whose rectangle is not resolved yet -- which is exactly
    -- the state a chat window is in for the first moments after login -- and
    -- ipairs over a table with a nil in it stops at the hole and checks
    -- nothing at all. That is how a missing rect became "arithmetic on a nil".
    if not (readable(left) and readable(bottom) and readable(width) and readable(height)) then
        return nil
    end
    local s = (cf:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
    return left * s, bottom * s, width * s, height * s
end

-- ---------------------------------------------------------------- build --

local function ensure(cf)
    local d = Chat.Data(cf)
    if d.bg then return d.bg end

    local bg = CreateFrame("Frame", nil, UIParent)
    bg:SetFrameStrata(cf:GetFrameStrata())
    bg:SetFrameLevel(math.max(1, (cf:GetFrameLevel() or 2) - 1))

    local tex = bg:CreateTexture(nil, "BACKGROUND")
    tex:SetAllPoints(bg)
    tex:SetTexture("Interface\\Buttons\\WHITE8X8")
    bg.tex = tex
    bg.edges = ns.MakeEdges(bg, "BORDER")

    d.bg = bg
    return bg
end

-- ---------------------------------------------------------------- input --

-- The edit box over the window instead of under it.
--
-- Only the numbered windows are touched. A temporary window's edit box is off
-- limits: hooking or re-scripting one taints its execution and the whisper
-- history that runs through it afterwards.
local function placeEditBox(cf, db)
    local eb = cf.editBox or _G[cf:GetName() .. "EditBox"]
    if not eb then return end
    local index = cf.GetID and cf:GetID()
    if type(index) ~= "number" or index > (NUM_CHAT_WINDOWS or 10) then return end

    local d = Chat.Data(cf)
    local want = db.inputOnTop and "TOP" or "BOTTOM"
    -- The client's own placement is left ALONE until the setting actually asks
    -- for the other one. Re-anchoring it "back to the bottom" on the first
    -- pass threw away anchors that were never ours, for a setting nobody had
    -- changed.
    if not db.inputOnTop and not d.editMoved then return end
    if d.editSide == want then return end
    d.editSide = want
    d.editMoved = true

    local drop = 5
    pcall(function()
        eb:ClearAllPoints()
        if db.inputOnTop then
            eb:SetPoint("BOTTOMLEFT", cf, "TOPLEFT", 0, drop)
            eb:SetPoint("BOTTOMRIGHT", cf, "TOPRIGHT", 0, drop)
        else
            eb:SetPoint("TOPLEFT", cf, "BOTTOMLEFT", 0, -drop)
            eb:SetPoint("TOPRIGHT", cf, "BOTTOMRIGHT", 0, -drop)
        end
    end)
end

-- ---------------------------------------------------------------- apply --

function Panel.Apply(cf)
    local db = Chat.db()
    local d = Chat.Data(cf)
    if not d.bridged then return end

    local left, bottom, width, height = rectOf(cf)
    local bg = ensure(cf)
    local host = d.host

    -- Suppression follows the panel, not the bridge: the client's copy is only
    -- made invisible once ours is actually somewhere. Otherwise an unreadable
    -- rectangle means both are invisible and the chat is simply blank.
    if left then
        Chat.Engine.Suppress(cf)
    else
        Chat.Engine.Unsuppress(cf)
    end

    if left then
        local pad = db.padding or 6
        bg:ClearAllPoints()
        bg:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left - pad, bottom - pad)
        bg:SetSize(width + pad * 2, height + pad * 2)

        if host then
            host:ClearAllPoints()
            host:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, bottom)
            host:SetSize(width, height)
        end
    end

    bg.tex:SetColorTexture(db.bgColor.r, db.bgColor.g, db.bgColor.b, db.bgColor.a or 0.65)
    ns.LayoutEdges(bg.edges, bg, db.showBorder and (db.borderSize or 1) or 0,
        db.borderColor.r, db.borderColor.g, db.borderColor.b, db.borderColor.a or 0.18, 0)
    bg:Show()
    if host then host:Show() end

    Chat.Engine.ApplyFont(cf)
    placeEditBox(cf, db)

    -- The panel has to follow the window when it is dragged or resized. A
    -- script hook is safe where a field write is not, and the work itself is
    -- deferred so it never runs inside the client's own layout pass.
    if not d.sizeHooked then
        d.sizeHooked = true
        local function follow()
            if not Chat.mod.active then return end
            Chat.Queue("chat.place." .. tostring(cf:GetID()), function() Panel.Apply(cf) end)
        end
        pcall(cf.HookScript, cf, "OnSizeChanged", follow)
        pcall(cf.HookScript, cf, "OnShow", follow)
    end
end

function Panel.ApplyAll()
    for _, cf in ipairs(Chat.Frames()) do
        if Chat.Data(cf).bridged then Panel.Apply(cf) end
    end
end

function Panel.Release()
    for _, cf in ipairs(Chat.Frames()) do
        local d = Chat.Data(cf)
        if d.bg then d.bg:Hide() end
        -- An input line we moved goes back under the window, which is where
        -- the client had it.
        if d.editMoved and d.editSide == "TOP" then
            local eb = cf.editBox or _G[cf:GetName() .. "EditBox"]
            if eb then
                pcall(function()
                    eb:ClearAllPoints()
                    eb:SetPoint("TOPLEFT", cf, "BOTTOMLEFT", 0, -5)
                    eb:SetPoint("TOPRIGHT", cf, "BOTTOMRIGHT", 0, -5)
                end)
                d.editSide = "BOTTOM"
            end
        end
    end
end

-- What the options say about a panel that cannot be placed, so the answer is
-- in one place rather than guessed at three call sites.
function Panel.StatusText()
    for _, cf in ipairs(Chat.Frames()) do
        if Chat.Data(cf).bridged and not rectOf(cf) then
            return L["The client is not letting the addon read where the chat window is right now."]
        end
    end
    return nil
end
