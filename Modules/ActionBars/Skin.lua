-- VuloForeverUI / Modules / ActionBars / Skin
--
-- The three looks.
--
--   standard  the client's own art, untouched
--   classic   the 1.x buttons: the open socket behind, the bevelled ring over
--   modern    flat -- the art off, a thin border of ours around the icon
--
-- HOW THIS SURVIVES THE CLIENT REDRAWING ITS OWN BUTTONS
--
-- The client re-sets a button's textures whenever the action in it changes, a
-- page turns, or a form is taken. So nothing here is done once: the look is
-- re-applied from the module's own pass, which the events in Core drive. What
-- is NOT done is hooking the client's own art functions -- an action button is
-- a secure button, and a hook whose body writes to it is exactly the kind of
-- thing that taints the click that casts the spell.
--
-- Nothing here writes a FIELD on a button either. What we need to remember --
-- what the art looked like before we touched it -- lives in the side table.
local _, ns = ...
local AB = ns.AB

local Skin = {}
AB.Skin = Skin

-- The classic art. These are the client's own files, the same ones our Classic
-- cast bar skin already draws from, so nothing is bundled for them.
local CLASSIC = {
    normal    = "Interface\\Buttons\\UI-Quickslot2",
    socket    = "Interface\\Buttons\\UI-Quickslot",
    pushed    = "Interface\\Buttons\\UI-Quickslot-Depress",
    highlight = "Interface\\Buttons\\ButtonHilight-Square",
    checked   = "Interface\\Buttons\\CheckButtonHilight",
    flash     = "Interface\\Buttons\\UI-QuickslotRed",
    border    = "Interface\\Buttons\\UI-ActionButton-Border",
}
-- The 1.x art was drawn around a 36 pixel button.
local BASE = 36
local WHITE = "Interface\\Buttons\\WHITE8X8"

-- What a button looked like before we arrived, kept off the button. Dropped
-- again once a restore has put it back, so Standard costs nothing per event.
local original = setmetatable({}, { __mode = "k" })
-- Frames and textures of OURS on a button outlive any one look, so they live
-- apart from the snapshot: the Modern border and the Standard slot ground.
local edgesOf = setmetatable({}, { __mode = "k" })
local grounds = setmetatable({}, { __mode = "k" })

-- Every texture a look touches. Each one is photographed whole before the
-- first change -- art, layer, size, anchors, colour -- because a look that is
-- only half undone is what leaves Standard without its slot art.
local function texturesOf(button)
    return {
        slot      = button.SlotBackground,
        slotArt   = button.SlotArt,
        normal    = button.GetNormalTexture and button:GetNormalTexture(),
        pushed    = button.GetPushedTexture and button:GetPushedTexture(),
        highlight = button.GetHighlightTexture and button:GetHighlightTexture(),
        checked   = button.GetCheckedTexture and button:GetCheckedTexture(),
        flash     = button.Flash,
        border    = button.Border,
    }
end

local function snapshot(tex)
    local s = {
        atlas = tex.GetAtlas and tex:GetAtlas() or nil,
        file  = tex:GetTexture(),
        alpha = tex:GetAlpha(),
        blend = tex:GetBlendMode(),
        coords = { tex:GetTexCoord() },
        color  = { tex:GetVertexColor() },
        points = {},
    }
    s.layer, s.sublevel = tex:GetDrawLayer()
    s.w, s.h = tex:GetSize()
    for i = 1, tex:GetNumPoints() do
        s.points[i] = { tex:GetPoint(i) }
    end
    return s
end

local function putBack(tex, s)
    if s.atlas then
        tex:SetAtlas(s.atlas)
    else
        tex:SetTexture(s.file)
        tex:SetTexCoord(unpack(s.coords))
    end
    tex:SetAlpha(s.alpha)
    tex:SetBlendMode(s.blend)
    tex:SetVertexColor(unpack(s.color))
    tex:SetDrawLayer(s.layer, s.sublevel)
    tex:ClearAllPoints()
    for _, p in ipairs(s.points) do tex:SetPoint(unpack(p)) end
    tex:SetSize(s.w, s.h)
end

local function remember(button)
    local o = original[button]
    if o then return o end
    o = { tex = {} }
    for key, tex in pairs(texturesOf(button)) do
        if tex then o.tex[key] = snapshot(tex) end
    end
    original[button] = o
    return o
end

local function scaleOf(button)
    local w = button:GetWidth()
    if not w or w == 0 then w = 45 end
    return w / BASE, w
end

local function centered(tex, size)
    if not tex then return end
    tex:ClearAllPoints()
    tex:SetPoint("CENTER")
    tex:SetSize(size, size)
    tex:SetTexCoord(0, 1, 0, 1)
end

-- ---------------------------------------------------------------- looks --

-- Is there something in this slot? The action the button shows right now --
-- its paged one -- decides between the filled ring and the empty socket.
local function isFilled(button)
    local action = button.action
    if type(action) ~= "number" and button.GetAttribute then
        action = button:GetAttribute("action")
    end
    if type(action) ~= "number" then return true end
    return C_ActionBar.HasAction(action) and true or false
end

local function skinClassic(button, filled)
    local s, w = scaleOf(button)
    local o = remember(button)

    -- Coming from Modern: its border off, and the tints it put on the pushed
    -- and highlight textures taken back.
    if edgesOf[button] then ns.LayoutEdges(edgesOf[button], button, 0, 0, 0, 0, 0, 0) end
    for _, tex in ipairs({ button.GetPushedTexture and button:GetPushedTexture(),
        button.GetHighlightTexture and button:GetHighlightTexture(),
        button.GetCheckedTexture and button:GetCheckedTexture(), button.SlotBackground }) do
        if tex then tex:SetVertexColor(1, 1, 1, 1) end
    end

    -- The 1.x icon is square and fills the button. The client's rounded mask
    -- is what shrinks it into a porthole, so it comes off the icon (and goes
    -- back on in restore); the mask texture itself is left as the client made it.
    local icon = button.icon
    if icon and button.IconMask and not o.unmasked then
        icon:RemoveMaskTexture(button.IconMask)
        o.unmasked = true
    end
    -- And it spans the whole button. The main bar's icon is not laid over the
    -- full button -- the mask hid that -- so unmasked it sat short of the ring.
    if icon then
        if not o.iconPoints then
            o.iconPoints = {}
            for i = 1, icon:GetNumPoints() do o.iconPoints[i] = { icon:GetPoint(i) } end
            o.iconW, o.iconH = icon:GetSize()
        end
        icon:ClearAllPoints()
        icon:SetAllPoints(button)
    end
    -- The swipe covers the whole square icon, not the porthole it was cut for.
    local cd = button.cooldown
    if cd and not o.cdPoints then
        o.cdPoints = {}
        for i = 1, cd:GetNumPoints() do o.cdPoints[i] = { cd:GetPoint(i) } end
    end
    if cd then
        cd:ClearAllPoints()
        cd:SetAllPoints(button)
    end

    -- The square ring IS the slot: neither of the client's slot textures shows.
    if button.SlotArt then button.SlotArt:SetAlpha(0) end
    if button.SlotBackground then button.SlotBackground:SetAlpha(0) end

    -- The 1.x ring, drawn around the 36 pixel button it was made for: 66/36
    -- of the button, one step low. An empty slot wears the open socket.
    local normal = button.GetNormalTexture and button:GetNormalTexture()
    if normal then
        if filled == nil then filled = isFilled(button) end
        normal:SetTexture(filled and CLASSIC.normal or CLASSIC.socket)
        normal:SetTexCoord(0, 1, 0, 1)
        normal:ClearAllPoints()
        normal:SetPoint("CENTER", button, "CENTER", 0, -s)
        normal:SetSize(66 * s, 66 * s)
        normal:SetDrawLayer("OVERLAY")
        normal:SetAlpha(1)
    end

    local pushed = button.GetPushedTexture and button:GetPushedTexture()
    if pushed then
        pushed:SetTexture(CLASSIC.pushed)
        pushed:SetTexCoord(0, 1, 0, 1)
        pushed:ClearAllPoints()
        pushed:SetAllPoints(button)
        pushed:SetDrawLayer("OVERLAY", 7)
    end
    local highlight = button.GetHighlightTexture and button:GetHighlightTexture()
    if highlight then
        highlight:SetTexture(CLASSIC.highlight)
        highlight:SetTexCoord(0, 1, 0, 1)
        highlight:ClearAllPoints()
        highlight:SetAllPoints(button)
        highlight:SetBlendMode("ADD")
    end
    local checked = button.GetCheckedTexture and button:GetCheckedTexture()
    if checked then
        checked:SetTexture(CLASSIC.checked)
        checked:SetTexCoord(0, 1, 0, 1)
        checked:ClearAllPoints()
        checked:SetAllPoints(button)
        checked:SetBlendMode("ADD")
    end
    if button.Flash then
        button.Flash:SetTexture(CLASSIC.flash)
        centered(button.Flash, w)
    end
    if button.Border then
        button.Border:SetTexture(CLASSIC.border)
        button.Border:SetTexCoord(0, 1, 0, 1)
        button.Border:ClearAllPoints()
        button.Border:SetPoint("CENTER", button, "CENTER", 0, s)
        button.Border:SetSize(62 * s, 62 * s)
        button.Border:SetBlendMode("ADD")
    end
end

local function skinModern(button)
    local db = AB.db()
    local s, w = scaleOf(button)
    remember(button)

    if button.SlotArt then button.SlotArt:SetAlpha(0) end

    -- Flat: the socket becomes a plain dark square and the ring goes away, so
    -- the icon is the whole button.
    local socket = button.SlotBackground
    if socket then
        socket:SetTexture(WHITE)
        socket:SetTexCoord(0, 1, 0, 1)
        socket:ClearAllPoints()
        socket:SetAllPoints(button)
        socket:SetVertexColor(0.08, 0.08, 0.09, 1)
        socket:SetAlpha(1)
        socket:SetDrawLayer("BACKGROUND", -1)
        socket:Show()
    end

    local normal = button.GetNormalTexture and button:GetNormalTexture()
    if normal then normal:SetAlpha(0) end

    local pushed = button.GetPushedTexture and button:GetPushedTexture()
    if pushed then
        pushed:SetTexture(WHITE)
        centered(pushed, w)
        pushed:SetVertexColor(1, 1, 1, 0.2)
        pushed:SetDrawLayer("OVERLAY")
    end
    local highlight = button.GetHighlightTexture and button:GetHighlightTexture()
    if highlight then
        highlight:SetTexture(WHITE)
        centered(highlight, w)
        highlight:SetVertexColor(1, 1, 1, 0.15)
        highlight:SetBlendMode("ADD")
    end

    -- A one pixel border of ours, in the chosen colour. The four textures are
    -- created ON the button, which is allowed -- it is a FIELD on a secure
    -- button that taints its click, so the handle to them is kept in our own
    -- side table instead.
    edgesOf[button] = edgesOf[button] or ns.MakeEdges(button, "OVERLAY")
    local c = db.borderColor
    ns.LayoutEdges(edgesOf[button], button, 1, c.r, c.g, c.b, c.a or 1, 0)
end

local function restore(button)
    local o = original[button]
    if not o then return end

    for key, tex in pairs(texturesOf(button)) do
        local s = o.tex[key]
        if tex and s then putBack(tex, s) end
    end
    if edgesOf[button] then ns.LayoutEdges(edgesOf[button], button, 0, 0, 0, 0, 0, 0) end
    if o.unmasked and button.icon and button.IconMask then
        button.icon:AddMaskTexture(button.IconMask)
        o.unmasked = nil
    end
    if o.iconPoints and button.icon then
        local icon = button.icon
        icon:ClearAllPoints()
        for _, p in ipairs(o.iconPoints) do icon:SetPoint(unpack(p)) end
        if #o.iconPoints < 2 then icon:SetSize(o.iconW, o.iconH) end
    end
    local cd = button.cooldown
    if cd and o.cdPoints then
        cd:ClearAllPoints()
        for _, p in ipairs(o.cdPoints) do cd:SetPoint(unpack(p)) end
    end

    -- Which of the two slot textures shows is the client's call, per bar: with
    -- the bar art on it shows the slot and hides the plain background. Both
    -- looks force the background on, so the client is asked to decide again.
    if type(button.UpdateButtonArt) == "function" then
        button:UpdateButtonArt()
    end
    -- Put back: the next look photographs the client's art afresh.
    original[button] = nil

    -- The icon is deliberately left alone. Its colour and its desaturation
    -- belong to the CLIENT -- that is how an action you cannot afford, or one
    -- out of range, is drawn -- and resetting them here would paint over the
    -- client's own answer.
end

-- ---------------------------------------------------------------- ground --
--
-- The Standard slot ground, drawn by us. The client's own slot art does not
-- hold on this client: which of its two slot textures shows is re-decided per
-- bar on every redraw, and an empty slot ends up showing the bar's wood
-- through the ring. So Standard wears its own copy of the client's slot atlas,
-- on a frame one level under the button -- the icon still draws over it, and
-- nothing on the secure button itself is written.
local SLOT_ATLAS = "UI-HUD-ActionBar-IconFrame-Slot"

local function slotGround(button, show)
    if not show then
        if grounds[button] then grounds[button]:Hide() end
        return
    end
    if not grounds[button] then
        -- A child of a secure button is created out of combat only; the
        -- regen pass comes back for it.
        if InCombatLockdown() then return end
        local f = CreateFrame("Frame", nil, button)
        f:SetAllPoints(button)
        f:SetFrameLevel(math.max(0, button:GetFrameLevel() - 1))
        f:EnableMouse(false)
        local tex = f:CreateTexture(nil, "BACKGROUND", nil, -1)
        tex:SetAtlas(SLOT_ATLAS)
        tex:SetAllPoints(f)
        grounds[button] = f
    end
    grounds[button]:Show()
end

-- ---------------------------------------------------------------- pass --

function Skin.ApplyAll()
    local db = AB.db()
    local buttons = AB.Buttons(db.skinPetStance)

    -- The band comes first: it moves the buttons, and the look below dresses
    -- them where they end up.
    if db.skin and db.style == "classic" and db.classicBar then
        AB.ClassicBar.Apply()
    else
        AB.ClassicBar.Restore()
    end

    for _, button in ipairs(buttons) do
        if db.skin and db.style == "classic" then
            slotGround(button, false)
            skinClassic(button)
        elseif db.skin and db.style == "modern" then
            slotGround(button, false)
            skinModern(button)
        else
            restore(button)
            -- Only the main bar sits on the wood; the others float free and
            -- stay as the client draws them.
            slotGround(button, AB.IsMainBarButton(button))
        end
    end
end

-- One button in one look, for the settings page's preview: the same passes the
-- real bars go through, so the preview cannot drift from them. `filled` says
-- whether the slot holds something; the preview's buttons have no action.
function Skin.Dress(button, style, filled)
    if style == "classic" then
        skinClassic(button, filled)
    elseif style == "modern" then
        skinModern(button)
    else
        restore(button)
    end
end

function Skin.RestoreAll()
    AB.ClassicBar.Restore()
    for _, button in ipairs(AB.Buttons(true)) do
        restore(button)
        slotGround(button, false)
    end
end
