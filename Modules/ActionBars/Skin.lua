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
-- The 1.x art was drawn around a 36 pixel button, and the ring is cropped to
-- the part of the sheet that carries it.
local BASE = 36
local CROP = { 0.1875, 0.796875, 0.1875, 0.796875 }
local WHITE = "Interface\\Buttons\\WHITE8X8"

-- What a button looked like before we arrived, kept off the button.
local original = setmetatable({}, { __mode = "k" })

local function remember(button)
    local o = original[button]
    if o then return o end
    o = {}
    local slot = button.SlotBackground
    if slot then
        o.slotAtlas = slot.GetAtlas and slot:GetAtlas() or nil
        o.slotAlpha = slot:GetAlpha()
    end
    o.artAlpha = button.SlotArt and button.SlotArt:GetAlpha() or nil
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

local function skinClassic(button)
    local s, w = scaleOf(button)
    remember(button)

    if button.SlotArt then button.SlotArt:SetAlpha(0) end

    -- The ring, over everything, at half strength: it is a bevel, not a frame.
    local normal = button.GetNormalTexture and button:GetNormalTexture()
    if normal then
        normal:SetTexture(CLASSIC.normal)
        normal:ClearAllPoints()
        normal:SetPoint("CENTER")
        normal:SetTexCoord(CROP[1], CROP[2], CROP[3], CROP[4])
        normal:SetSize(40 * s, 40 * s)
        normal:SetDrawLayer("OVERLAY")
        normal:SetAlpha(0.5)
    end

    -- The open socket behind the icon. It is put on its own sublevel and said
    -- so: the client keeps the socket and the icon on the same layer, where
    -- the order two textures draw in is not promised -- and the old socket art
    -- coming out on top of a spell is what reads as a dimmed icon.
    local socket = button.SlotBackground
    if socket then
        socket:SetTexture(CLASSIC.socket)
        socket:SetTexCoord(0, 1, 0, 1)
        socket:ClearAllPoints()
        socket:SetPoint("CENTER")
        socket:SetSize(66 * s, 66 * s)
        socket:SetAlpha(0.4)
        socket:SetDrawLayer("BACKGROUND", -1)
        socket:Show()
    end

    local pushed = button.GetPushedTexture and button:GetPushedTexture()
    if pushed then
        pushed:SetTexture(CLASSIC.pushed)
        centered(pushed, w)
        pushed:SetDrawLayer("OVERLAY")
    end
    local highlight = button.GetHighlightTexture and button:GetHighlightTexture()
    if highlight then
        highlight:SetTexture(CLASSIC.highlight)
        centered(highlight, w)
        highlight:SetBlendMode("ADD")
    end
    local checked = button.GetCheckedTexture and button:GetCheckedTexture()
    if checked then
        checked:SetTexture(CLASSIC.checked)
        centered(checked, w)
        checked:SetBlendMode("ADD")
    end
    if button.Flash then
        button.Flash:SetTexture(CLASSIC.flash)
        centered(button.Flash, w)
    end
    if button.Border then
        button.Border:SetTexture(CLASSIC.border)
        centered(button.Border, 62 * s)
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
    local o = remember(button)
    o.edges = o.edges or ns.MakeEdges(button, "OVERLAY")
    local c = db.borderColor
    ns.LayoutEdges(o.edges, button, 1, c.r, c.g, c.b, c.a or 1, 0)
end

local function restore(button)
    local o = original[button]
    if not o then return end

    if button.SlotArt and o.artAlpha then button.SlotArt:SetAlpha(o.artAlpha) end
    local socket = button.SlotBackground
    if socket then
        socket:SetVertexColor(1, 1, 1, 1)
        socket:SetAlpha(o.slotAlpha or 1)
        socket:SetDrawLayer("BACKGROUND", 0)
        socket:SetTexCoord(0, 1, 0, 1)
        socket:ClearAllPoints()
        socket:SetAllPoints(button)
        if o.slotAtlas and socket.SetAtlas then pcall(socket.SetAtlas, socket, o.slotAtlas) end
    end
    local normal = button.GetNormalTexture and button:GetNormalTexture()
    if normal then
        normal:SetAlpha(1)
        normal:SetTexCoord(0, 1, 0, 1)
        normal:ClearAllPoints()
        normal:SetAllPoints(button)
        normal:SetDrawLayer("BORDER")
    end
    if o.edges then ns.LayoutEdges(o.edges, button, 0, 0, 0, 0, 0, 0) end

    -- The icon is deliberately left alone. Its colour and its desaturation
    -- belong to the CLIENT -- that is how an action you cannot afford, or one
    -- out of range, is drawn -- and resetting them here would paint over the
    -- client's own answer.
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
            skinClassic(button)
        elseif db.skin and db.style == "modern" then
            skinModern(button)
        else
            restore(button)
        end
    end
end

function Skin.RestoreAll()
    AB.ClassicBar.Restore()
    for _, button in ipairs(AB.Buttons(true)) do
        restore(button)
    end
end
