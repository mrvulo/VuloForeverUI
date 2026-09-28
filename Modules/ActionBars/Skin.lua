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
-- Modern's own icon ground, and which look a button last wore: a change of
-- look goes through a full restore first, so nothing of the old one lingers.
local groundsModern = setmetatable({}, { __mode = "k" })
local lookOf = setmetatable({}, { __mode = "k" })

-- Modern's press, hover and cast art: a soft white glow along the inner edge,
-- in three strengths, tinted at runtime.
local PRESS_DIR = "Interface\\AddOns\\VuloForeverUI\\Media\\textures\\"
local PRESS_FILES = {
    PRESS_DIR .. "ab-press-light",
    PRESS_DIR .. "ab-press-medium",
    PRESS_DIR .. "ab-press-strong",
}
local PRESS_SOLID, PRESS_NONE = 4, 6

-- Border steps, in physical pixels.
local BORDER_PX = { none = 0, thin = 1, normal = 2, heavy = 3, strong = 4 }
AB.BORDER_STEPS = { "none", "thin", "normal", "heavy", "strong" }

-- The text regions a look restyles. The cooldown's countdown is the first
-- font string inside the cooldown frame; it only exists once the client made it.
local function cooldownText(button)
    local cd = button.cooldown
    if not cd then return nil end
    if cd.GetCountdownFontString then
        local fs = cd:GetCountdownFontString()
        if fs then return fs end
    end
    if not cd.GetRegions then return nil end
    for _, r in ipairs({ cd:GetRegions() }) do
        if r.GetObjectType and r:GetObjectType() == "FontString" then return r end
    end
end

local function textsOf(button)
    return { hotkey = button.HotKey, count = button.Count, name = button.Name,
        cooldown = cooldownText(button) }
end

local function snapFont(fs)
    local s = { font = { fs:GetFont() }, justify = fs:GetJustifyH(), alpha = fs:GetAlpha(), points = {} }
    for i = 1, fs:GetNumPoints() do s.points[i] = { fs:GetPoint(i) } end
    return s
end

local function putFont(fs, s)
    if s.font[1] then fs:SetFont(s.font[1], s.font[2], s.font[3] or "") end
    fs:SetJustifyH(s.justify)
    fs:SetAlpha(s.alpha)
    fs:ClearAllPoints()
    for _, p in ipairs(s.points) do fs:SetPoint(unpack(p)) end
end

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
        newAction = button.NewActionTexture,
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
    o.fonts = {}
    for key, fs in pairs(textsOf(button)) do o.fonts[key] = snapFont(fs) end
    if button.icon then o.iconCoords = { button.icon:GetTexCoord() } end
    local cd = button.cooldown
    if cd and cd.GetEdgeScale then o.edgeScale = cd:GetEdgeScale() end
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

-- ---------------------------------------------------------------- modern --
--
-- Flat and square: the client's frame art off, the icon filling the button
-- with its edges trimmed, a dark ground behind it, a thin border inside the
-- button, and the press, hover and cast states as a soft tinted glow along
-- the inner edge. Keybind, charges, macro name and countdown in the suite
-- font, the keybind shortened (SHIFT-BUTTON4 reads SM4).

-- Pet, stance and possess buttons are smaller; their texts step down.
local function isSmall(button)
    local name = button:GetName() or ""
    return name:find("^PetActionButton") or name:find("^StanceButton") or name:find("^PossessButton")
end

local function classColor()
    local _, class = UnitClass("player")
    local c = class and C_ClassColor.GetClassColor(class)
    if c then return { r = c.r, g = c.g, b = c.b, a = 1 } end
    return { r = 1, g = 1, b = 1, a = 1 }
end

-- The binding a button fires. The client stores it on the button; the pet
-- and stance buttons and our preview buttons are worked out from the name.
local function bindingKey(button)
    local action = button.bindingAction
    local name = button:GetName() or ""
    if type(action) ~= "string" then
        local n = name:match("^PetActionButton(%d+)$")
        if n then action = "BONUSACTIONBUTTON" .. n end
        n = name:match("^StanceButton(%d+)$")
        if n then action = "SHAPESHIFTBUTTON" .. n end
        n = name:match("PreviewActionButton(%d+)$")
        if n then action = "ACTIONBUTTON" .. n end
    end
    local key = action and GetBindingKey(action)
    if not key and name ~= "" then key = GetBindingKey("CLICK " .. name .. ":LeftButton") end
    return key
end

local HOTKEY_SHORT = {
    { "CTRL%-", "C" }, { "ALT%-", "A" }, { "SHIFT%-", "S" }, { "META%-", "M" },
    { "MOUSEWHEELUP", "MwU" }, { "MOUSEWHEELDOWN", "MwD" }, { "CAPSLOCK", "Caps" },
    { "NUMPADDECIMAL", "N." }, { "NUMPADPLUS", "N+" }, { "NUMPADMINUS", "N-" },
    { "NUMPADMULTIPLY", "N*" }, { "NUMPADDIVIDE", "N/" }, { "NUMPAD", "N" },
    { "BUTTON", "M" },
}

function AB.ShortKey(key)
    if type(key) ~= "string" or key == "" then return nil end
    if IsBindingForGamePad and IsBindingForGamePad(key) then return GetBindingText(key, 1) end
    for _, rule in ipairs(HOTKEY_SHORT) do key = key:gsub(rule[1], rule[2]) end
    return key
end

-- Where a text sits. "default" is the look's own spot; the six others are
-- the button's corners and edge middles, two pixels in.
local function placeText(fs, button, pos, default)
    fs:ClearAllPoints()
    if pos == "default" or not pos then
        default(fs)
        return
    end
    local dx = pos:find("LEFT") and 2 or (pos:find("RIGHT") and -2 or 0)
    local dy = pos:find("TOP") and -3 or 3
    fs:SetPoint(pos, button, pos, dx, dy)
    fs:SetJustifyH(pos:find("LEFT") and "LEFT" or (pos:find("RIGHT") and "RIGHT" or "CENTER"))
end

-- One of the press-type textures (pushed, highlight): a glow file, a flat
-- colour, or nothing.
local function pressTexture(tex, button, kind, c, blend)
    if not tex then return end
    tex:ClearAllPoints()
    tex:SetAllPoints(button)
    if kind == PRESS_NONE then tex:SetAlpha(0); return end
    tex:SetAlpha(1)
    if kind == PRESS_SOLID then
        tex:SetColorTexture(c.r, c.g, c.b, 0.35)
        tex:SetVertexColor(1, 1, 1, 1)
    else
        tex:SetTexture(PRESS_FILES[kind] or PRESS_FILES[2])
        tex:SetTexCoord(0, 1, 0, 1)
        tex:SetVertexColor(c.r, c.g, c.b, 1)
    end
    tex:SetBlendMode(blend)
end

local function skinModern(button)
    local db = AB.db()
    local o = remember(button)
    local small = isSmall(button)
    local press = db.pressClassColor and classColor() or db.pressColor

    -- The client's frame art, off. Alpha rather than Hide: the client shows
    -- these again on its own redraws and would undo a Hide.
    if button.SlotArt then button.SlotArt:SetAlpha(0) end
    if button.SlotBackground then button.SlotBackground:SetAlpha(0) end
    local normal = button.GetNormalTexture and button:GetNormalTexture()
    if normal then normal:SetAlpha(0) end
    if button.Border then button.Border:SetAlpha(0) end

    -- Our own ground, under everything. A texture on the button is allowed;
    -- the handle to it lives in the side table, never as a field.
    local ground = groundsModern[button]
    if not ground then
        ground = button:CreateTexture(nil, "BACKGROUND", nil, -8)
        groundsModern[button] = ground
    end
    local gc = db.iconBgColor
    ground:ClearAllPoints()
    ground:SetAllPoints(button)
    ground:SetColorTexture(gc.r, gc.g, gc.b, (db.iconBgOpacity or 50) / 100)
    ground:Show()

    -- The icon: square, the whole button, its rim trimmed by the zoom.
    local icon = button.icon
    if icon then
        if button.IconMask and not o.unmasked then
            icon:RemoveMaskTexture(button.IconMask)
            o.unmasked = true
        end
        if not o.iconPoints then
            o.iconPoints = {}
            for i = 1, icon:GetNumPoints() do o.iconPoints[i] = { icon:GetPoint(i) } end
            o.iconW, o.iconH = icon:GetSize()
        end
        icon:ClearAllPoints()
        icon:SetAllPoints(button)
        local z = (db.iconZoom or 5.5) / 100
        icon:SetTexCoord(z, 1 - z, z, 1 - z)
    end

    -- The swipe over the whole square, its moving edge in the interaction colour.
    local cd = button.cooldown
    if cd then
        if not o.cdPoints then
            o.cdPoints = {}
            for i = 1, cd:GetNumPoints() do o.cdPoints[i] = { cd:GetPoint(i) } end
        end
        cd:ClearAllPoints()
        cd:SetAllPoints(button)
        if cd.SetEdgeColor then cd:SetEdgeColor(press.r, press.g, press.b, 1) end
        if cd.SetEdgeScale then cd:SetEdgeScale(2.1) end
    end

    pressTexture(button.GetPushedTexture and button:GetPushedTexture(), button, db.pushedType, press, "BLEND")
    pressTexture(button.GetHighlightTexture and button:GetHighlightTexture(), button, db.highlightType, press, "ADD")

    -- The cast and auto-attack states stay white, as the light glow; the
    -- new-action mark and the attack flash take the interaction colour.
    local checked = button.GetCheckedTexture and button:GetCheckedTexture()
    if checked then
        checked:SetTexture(PRESS_FILES[1])
        checked:SetTexCoord(0, 1, 0, 1)
        checked:ClearAllPoints()
        checked:SetAllPoints(button)
        checked:SetVertexColor(1, 1, 1, 1)
        checked:SetBlendMode("ADD")
        checked:SetAlpha(db.castHighlight and 1 or 0)
    end
    for _, key in ipairs({ "Flash", "NewActionTexture" }) do
        local tex = button[key]
        if tex then
            tex:SetTexture(PRESS_FILES[1])
            tex:SetTexCoord(0, 1, 0, 1)
            tex:ClearAllPoints()
            tex:SetAllPoints(button)
            tex:SetDesaturated(true)
            tex:SetVertexColor(press.r, press.g, press.b, 1)
        end
    end

    -- The border, inside the button edge.
    edgesOf[button] = edgesOf[button] or ns.MakeEdges(button, "OVERLAY")
    local n = BORDER_PX[db.borderSize] or 1
    local bc = db.borderClassColor and classColor() or db.borderColor
    ns.LayoutEdges(edgesOf[button], button, n, bc.r, bc.g, bc.b, bc.a or 1, -n)

    -- Texts.
    local font = ns.MediaFont("Expressway")
    local step = small and 2 or 0

    local hk = button.HotKey
    if hk then
        hk:SetFont(font, math.max(6, db.keybindSize - step), "OUTLINE")
        hk:SetShadowOffset(0, 0)
        hk:SetHeight(0)
        placeText(hk, button, db.keybindPos, function(fs)
            fs:SetPoint("TOPRIGHT", button, "TOPRIGHT", -1, -3)
            fs:SetPoint("TOPLEFT", button, "TOPLEFT", 4, -3)
            fs:SetJustifyH("RIGHT")
        end)
        hk:SetAlpha(db.keybindHide and 0 or 1)
        local text = AB.ShortKey(bindingKey(button))
        if text then hk:SetText(text); hk:Show() end
    end

    local count = button.Count
    if count then
        count:SetFont(font, db.countSize, "OUTLINE")
        count:SetShadowOffset(0, 0)
        count:ClearAllPoints()
        count:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 4)
        count:SetJustifyH("RIGHT")
    end

    local name = button.Name
    if name then
        name:SetFont(font, math.max(6, db.macroSize - step), "OUTLINE")
        name:SetShadowOffset(0, 0)
        name:ClearAllPoints()
        name:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 1, 4)
        name:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 4)
        name:SetJustifyH("CENTER")
        name:SetAlpha(db.macroHide and 0 or 1)
    end

    local cdText = cooldownText(button)
    if cdText then
        -- made by the client after the first snapshot: photograph it now
        if not o.fonts.cooldown then o.fonts.cooldown = snapFont(cdText) end
        cdText:SetFont(font, db.cooldownSize, "OUTLINE")
        cdText:ClearAllPoints()
        cdText:SetPoint("CENTER", button, "CENTER", 0, 0)
    end
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

    -- What only Modern changes: the trim, the edge, the ground, the texts.
    if o.iconCoords and button.icon then button.icon:SetTexCoord(unpack(o.iconCoords)) end
    if cd and cd.SetEdgeColor then cd:SetEdgeColor(1, 1, 1, 1) end
    if cd and o.edgeScale and cd.SetEdgeScale then cd:SetEdgeScale(o.edgeScale) end
    if button.NewActionTexture then button.NewActionTexture:SetDesaturated(false) end
    if button.Flash then button.Flash:SetDesaturated(false) end
    if groundsModern[button] then groundsModern[button]:Hide() end
    for key, fs in pairs(textsOf(button)) do
        local f = o.fonts and o.fonts[key]
        if f then putFont(fs, f) end
    end
    -- The keybind as the client writes it, in the box the client gives it.
    local hk = button.HotKey
    if hk and o.fonts and o.fonts.hotkey then
        hk:SetSize(math.max(1, (button:GetWidth() or 45) - 8), 10)
        local key = bindingKey(button)
        local text = key and GetBindingText(key, 1)
        if text and text ~= "" then hk:SetText(text) end
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
        local look = db.skin and db.style or "standard"
        if lookOf[button] and lookOf[button] ~= look then restore(button) end
        lookOf[button] = look
        if db.skin and db.style == "classic" then
            slotGround(button, false)
            skinClassic(button)
        elseif db.skin and db.style == "modern" then
            slotGround(button, false)
            skinModern(button)
        else
            -- Standard is the client's art, untouched -- action bar 1 included.
            -- A slot of ours under the main bar's empty buttons drew the retail
            -- square where this client draws its own winged slot emblem; the
            -- client decides that art itself (restore asks it to, above).
            restore(button)
            slotGround(button, false)
        end
    end
end

-- One button in one look, for the settings page's preview: the same passes the
-- real bars go through, so the preview cannot drift from them. `filled` says
-- whether the slot holds something; the preview's buttons have no action.
function Skin.Dress(button, style, filled)
    if lookOf[button] and lookOf[button] ~= style then restore(button) end
    lookOf[button] = style
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
        lookOf[button] = nil
        slotGround(button, false)
    end
end
