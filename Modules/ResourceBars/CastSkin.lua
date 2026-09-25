-- VuloForeverUI / Modules / ResourceBars / CastSkin
--
-- The two cast bar styles that keep the CLIENT's own bar and work on it:
--
--   standard  the bar the client ships, untouched, plus our icon and our
--             cast time next to it, both freely placed
--   classic   the same, and the bar itself dressed back to the 1.x shape:
--             195 x 13, the old border sheet, the plain status bar fill in
--             the four old colours, a static spark, and none of the modern
--             flakes, wisps and glow lines
--
-- THE ONE RULE THIS FILE IS BUILT AROUND
--
-- Nothing here ever WRITES A FIELD on a cast bar. A field written from addon
-- code taints every later read of it, and the bar's own update loop then trips
-- over the secret cast values it carries. So Blizzard's bar keeps running its
-- own code untouched, our state lives in a table keyed by the frame, and the
-- old art is put back by secure hooks after each of Blizzard's own changes.
--
-- The fill colour is the second place where care is needed: the cast TYPE is a
-- secret, so it is never read. What is read is the ATLAS NAME Blizzard just
-- chose for the fill -- a plain string that says the same thing.
local _, ns = ...
local RB = ns.RB

local Skin = {}
RB.CastSkin = Skin

local KEY = "cast"

-- Blizzard's modern decoration. All of it goes away in the classic style; the
-- names are the frame's own parentKeys, so they have to be spelled out.
local FX = {
    "Flakes01", "Flakes02", "Flakes03", "BaseGlow", "WispGlow",
    "Sparkles01", "Sparkles02", "Shine", "EnergyGlow", "InterruptGlow",
    "ChargeGlow", "ChargeFlash", "StandardGlow", "CraftGlow",
    "ChannelShadow", "DropShadow", "TextBorder",
}
local FINISH_ANIMS = { "StandardFinish", "ChannelFinish", "CraftingFinish" }

local FILL = "Interface\\TargetingFrame\\UI-StatusBar"
local BORDER = "Interface\\CastingBar\\UI-CastingBar-Border"
local SPARK  = "Interface\\CastingBar\\UI-CastingBar-Spark"
local FLASH  = "Interface\\CastingBar\\UI-CastingBar-Flash"

-- The four colours 1.x used. Chosen from the atlas name, never from the type.
local YELLOW = { 1, 0.7, 0 }
local GREEN  = { 0, 1, 0 }
local GRAY   = { 0.5, 0.5, 0.5 }
local RED    = { 1, 0, 0 }

-- Our state about a foreign frame, kept OUT of that frame.
local state = setmetatable({}, { __mode = "k" })

local function stateOf(frame)
    local s = state[frame]
    if not s then s = {}; state[frame] = s end
    return s
end

local function guard(key, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok and not Skin.reported then
        Skin.reported = true
        ns:Debug("cast skin: %s could not be applied (%s)", key, tostring(err))
    end
    return ok
end

function Skin.Frame()
    return _G.PlayerCastingBarFrame
end

local function style()
    local bar = RB.Bar(KEY)
    return (bar and bar.castStyle) or "standard"
end

-- ---------------------------------------------------------------- classic --

local function hideFx(bar)
    for _, key in ipairs(FX) do
        local region = bar[key]
        if region then
            if region.SetAtlas then pcall(region.SetAtlas, region, nil) end
            region:SetAlpha(0)
            region:Hide()
        end
    end
end

-- The fill colour for the atlas Blizzard just picked. The atlas name carries
-- the cast type, and a name is a plain string -- which is the whole point:
-- the type itself is secret and may not be compared with anything.
local function fillColor(atlas)
    if not (type(atlas) == "string" and ns.CanRead(atlas)) then return YELLOW end
    local name = atlas:lower()
    if name:find("interrupted", 1, true) then return RED end
    if name:find("uninterrupt", 1, true) then return GRAY end
    if name:find("channel", 1, true) then return GREEN end
    if name:find("full", 1, true) then return GREEN end
    return YELLOW
end

local function dressFill(bar)
    if style() ~= "classic" then return end
    local tex = bar:GetStatusBarTexture()
    local atlas = tex and tex.GetAtlas and tex:GetAtlas()
    local c = fillColor(atlas)
    bar:SetStatusBarTexture(FILL)
    bar:SetStatusBarColor(c[1], c[2], c[3])
end

local function dressSpark(bar)
    if not bar.Spark then return end
    bar.Spark:SetTexture(SPARK)
    bar.Spark:SetTexCoord(0, 1, 0, 1)
    bar.Spark:SetSize(32, 32)
    bar.Spark:SetBlendMode("ADD")
end

local function dressFlash(bar)
    if not bar.Flash then return end
    bar.Flash:SetTexture(FLASH)
    bar.Flash:SetTexCoord(0, 1, 0, 1)
    bar.Flash:SetBlendMode("ADD")
    bar.Flash:ClearAllPoints()
    bar.Flash:SetSize(256, 64)
    bar.Flash:SetPoint("TOP", bar, "TOP", 0, 28)
end

-- The 1.x shape. Done here rather than by calling the client's own SetLook:
-- that call would make Blizzard read protected cast values inside our context.
-- Set the first time we actually dress the bar, and never cleared while the
-- session lasts unless we put it back. Restore below hangs off it.
local dressed = false

local function dress(bar)
    if style() ~= "classic" then return end
    dressed = true

    bar:SetSize(195, 13)
    if bar.Border then
        bar.Border:SetTexture(BORDER)
        bar.Border:SetTexCoord(0, 1, 0, 1)
        bar.Border:ClearAllPoints()
        bar.Border:SetSize(256, 64)
        bar.Border:SetPoint("TOP", bar, "TOP", 0, 28)
    end
    if bar.BorderShield then
        bar.BorderShield:ClearAllPoints()
        bar.BorderShield:SetSize(256, 64)
        bar.BorderShield:SetPoint("TOP", bar, "TOP", 0, 28)
    end
    if bar.Text then
        bar.Text:ClearAllPoints()
        bar.Text:SetSize(185, 16)
        bar.Text:SetPoint("TOP", bar, "TOP", 0, 5)
        bar.Text:SetFontObject("GameFontHighlight")
    end
    if bar.Background then
        if bar.Background.SetAtlas then pcall(bar.Background.SetAtlas, bar.Background, nil) end
        bar.Background:SetColorTexture(0, 0, 0, 0.5)
        bar.Background:ClearAllPoints()
        bar.Background:SetAllPoints(bar)
    end
    dressSpark(bar)
    dressFlash(bar)
    hideFx(bar)
    dressFill(bar)
end

local function stopFinish(bar)
    for _, key in ipairs(FINISH_ANIMS) do
        local anim = bar[key]
        if anim and anim.Stop then anim:Stop() end
    end
    hideFx(bar)
end

-- ---------------------------------------------------------------- ours --

-- Our icon and our cast time. They live on a frame of OURS, parented to the
-- client's bar so they come and go with it, and placed by two offsets each so
-- they can be put wherever the chosen style leaves room.
--
-- Each of the two sits on a small frame of its own (s.iconBox, s.timeBox), and
-- that frame is what our edit mode drags.
--
-- THE POSITION MODEL. The saved truth stays what the sliders write: the icon's
-- RIGHT edge relative to the bar's LEFT edge (attachIconX/Y), the time's LEFT
-- edge relative to the bar's RIGHT edge (attachTimeX/Y), in the bar's own
-- units. So both keep following the client's bar wherever the client's own
-- Edit Mode puts it, and at whatever scale.
--
-- The mover wants a centre offset from the middle of the screen instead. It
-- gets a table of its own that is never saved (PLACES[..].pos) and holds the
-- absolute centre the relative offsets work out to. A drop, a nudge, the edit
-- panel's X/Y or a discard write that table; onMove / applyPos turn it back
-- into the relative offsets and anchor the box to the bar again. A reset puts
-- the defaults back (-6 / +6 beside the bar), not the middle of the screen.
local DEFAULT = { icon = { -6, 0 }, time = { 6, 0 } }

local PLACES = {
    icon = { key = "resourcebar_casticon", box = "iconBox", ox = "attachIconX", oy = "attachIconY",
             point = "RIGHT", rel = "LEFT", pos = {} },
    time = { key = "resourcebar_casttime", box = "timeBox", ox = "attachTimeX", oy = "attachTimeY",
             point = "LEFT", rel = "RIGHT", pos = {} },
}

-- A plain number we may do arithmetic on, or nil.
local function num(v)
    if type(v) ~= "number" or not ns.CanRead(v) then return nil end
    return v
end

-- Where the bar's anchor edge is, in the bar's own units: x of the named side
-- and the vertical centre. nil while the bar has no rect yet.
local function barEdge(bar, side)
    local x = num(side == "LEFT" and bar:GetLeft() or bar:GetRight())
    local _, cy = bar:GetCenter()
    cy = num(cy)
    if not (x and cy) then return nil end
    return x, cy
end

-- Box and bar always share one effective scale -- the box is a grandchild of
-- the bar, or while editing a UIParent child scaled to match -- so the box's
-- local units ARE the bar's units, and the maths below needs no conversion
-- between the two. Only UIParent's centre has to be carried over.
local function uiCentre(box)
    local ux, uy = UIParent:GetCenter()
    local r = (UIParent:GetEffectiveScale() or 1) / ((box:GetEffectiveScale() or 1))
    if not (ux and uy) or r == 0 then return nil end
    return ux * r, uy * r
end

-- relative offsets -> the centre offset the mover stores
local function toAbsolute(bar, box, p, cfg)
    local ex, ey = barEdge(bar, p.rel)
    local ux, uy = uiCentre(box)
    if not (ex and ux) then return nil end
    local half = (box:GetWidth() or 0) / 2
    local cx = ex + (cfg[p.ox] or 0) + ((p.point == "RIGHT") and -half or half)
    return cx - ux, ey + (cfg[p.oy] or 0) - uy
end

-- the centre offset -> relative offsets
local function toRelative(bar, box, p, cfg, x, y)
    local ex, ey = barEdge(bar, p.rel)
    local ux, uy = uiCentre(box)
    if not (ex and ux) then return end
    local half = (box:GetWidth() or 0) / 2
    local edge = ux + x + ((p.point == "RIGHT") and half or -half)
    cfg[p.ox], cfg[p.oy] = edge - ex, (uy + y) - ey
end

local function anchorBox(bar, which)
    local s, cfg, p = stateOf(bar), RB.Bar(KEY), PLACES[which]
    local box = s[p.box]
    if not (box and cfg) then return end
    box:ClearAllPoints()
    box:SetPoint(p.point, bar, p.rel, cfg[p.ox] or 0, cfg[p.oy] or 0)
    -- the mover's copy of where that is
    local x, y = toAbsolute(bar, box, p, cfg)
    if x then p.pos.x, p.pos.y = x, y end
    p.synced = x and { x, y } or nil
end

-- What a discard has to hand back, taken when our edit mode opens. The
-- snapshot the editor keeps was read before that moment, from p.pos -- which
-- can be stale if the client's own Edit Mode moved the bar since. So when a
-- discard brings back exactly that stale pair, the offsets from the same
-- moment are restored instead of converting it against a bar that moved.
local function captureOpen(which)
    local cfg, p = RB.Bar(KEY), PLACES[which]
    if not cfg then return end
    p.open = { x = p.pos.x, y = p.pos.y, ox = cfg[p.ox], oy = cfg[p.oy] }
end

local function fromMover(which, x, y)
    local bar = Skin.Frame()
    local cfg, p = RB.Bar(KEY), PLACES[which]
    if not (bar and cfg) then return end
    local s = stateOf(bar)
    local box = s[p.box]
    if not box then return end
    local o = p.open
    if ns._inMoverReset then
        cfg[p.ox], cfg[p.oy] = DEFAULT[which][1], DEFAULT[which][2]
    elseif o and o.ox and p.pos.x == o.x and p.pos.y == o.y then
        -- also covers a pair that was never measured (nil): the discard then
        -- writes nil back, and the mover hands us 0, 0 for it
        cfg[p.ox], cfg[p.oy] = o.ox, o.oy
    else
        toRelative(bar, box, p, cfg, x, y)
    end
    anchorBox(bar, which)
end

-- applyPos: ApplyMover, a nudge, a reset. When the stored centre is still the
-- one the offsets produced, nothing moved it and the offsets are placed as they
-- are; when it differs, a nudge or a reset changed it and it is read back.
local function placeFromMover(which)
    local bar = Skin.Frame()
    local p = PLACES[which]
    if not bar then return end
    local sy = p.synced
    if ns._inMoverReset then
        fromMover(which, 0, 0)
    elseif sy and p.pos.x and p.pos.y and (sy[1] ~= p.pos.x or sy[2] ~= p.pos.y) then
        fromMover(which, p.pos.x, p.pos.y)
    else
        -- nothing moved it, or it was never measured (no rect yet): the
        -- offsets are the truth and are placed as they are
        anchorBox(bar, which)
    end
end

local editPreview   -- below; the movers need it

local function holder(bar)
    local s = stateOf(bar)
    if s.holder then return s.holder end

    local f = CreateFrame("Frame", nil, bar)
    f:SetAllPoints(bar)
    f:SetFrameLevel((bar:GetFrameLevel() or 1) + 3)
    s.holder = f

    s.iconBox = CreateFrame("Frame", nil, f)
    s.icon = s.iconBox:CreateTexture(nil, "OVERLAY")
    s.icon:SetAllPoints(s.iconBox)
    s.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    s.icon:Hide()

    s.timeBox = CreateFrame("Frame", nil, f)
    s.timeBox:SetSize(48, 16)
    s.time = s.timeBox:CreateFontString(nil, "OVERLAY")
    s.time:SetPoint("LEFT", s.timeBox, "LEFT", 0, 0)
    s.time:SetJustifyH("LEFT")

    for which, p in pairs(PLACES) do
        s[p.box].mover = ns:CreateMover(s[p.box], {
            key      = p.key,
            label    = (which == "icon") and ns.L["Cast bar icon"] or ns.L["Cast bar time"],
            db       = p.pos,
            module   = "resourcebars",
            width    = 40,
            height   = 20,
            applyPos = function() placeFromMover(which) end,
            onMove   = function(x, y) fromMover(which, x, y) end,
            -- Both only show while a cast runs, and the client's bar they hang
            -- on is hidden in between: while our edit mode is open they are
            -- lifted out onto the screen with an example in them.
            editPreview = function(on) editPreview(on) end,
        })
    end
    if ns:IsMoverEditMode() then editPreview(true) end
    return f
end

-- While our edit mode is open the two boxes are lifted off the client's bar
-- onto UIParent -- the bar is hidden between casts and would take them along --
-- at the bar's own effective scale, so the offsets keep meaning the same thing.
-- They stay anchored to the bar all along. Closing puts them back.
local PREVIEW_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

function editPreview(on)
    local bar = Skin.Frame()
    local s = bar and state[bar]
    if not (s and s.holder) then return end
    local want = on and RB.mod.active and style() ~= "modern"

    if want and not s.previewing then
        for which in pairs(PLACES) do captureOpen(which) end
        s.previewing = true
        local r = (bar:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
        for _, p in pairs(PLACES) do
            local box = s[p.box]
            box:SetParent(UIParent)
            box:SetScale(r > 0 and r or 1)
            box:SetFrameStrata(bar:GetFrameStrata() or "MEDIUM")
            box:SetFrameLevel((bar:GetFrameLevel() or 1) + 3)
        end
        ns:DurationText(s.holder, s.time, nil)
        s.icon:SetTexture(PREVIEW_ICON)
        s.icon:Show()
        s.time:SetText("1.5")
        s.time:Show()
    elseif not want and s.previewing then
        s.previewing = nil
        for _, p in pairs(PLACES) do
            local box = s[p.box]
            box:SetParent(s.holder)
            box:SetScale(1)
            box:SetFrameStrata(s.holder:GetFrameStrata())
            box:SetFrameLevel((s.holder:GetFrameLevel() or 1) + 1)
        end
        s.icon:Hide()
        s.time:SetText("")
    end
    if not on then
        for _, p in pairs(PLACES) do p.open = nil end
    end
    ns:ApplyMover(s.iconBox.mover)
    ns:ApplyMover(s.timeBox.mover)
end

function Skin.LayoutExtras()
    local bar = Skin.Frame()
    local cfg = RB.Bar(KEY)
    if not (bar and cfg) then return end
    local mode = style()
    if mode == "modern" then
        local s = state[bar]
        if s and s.holder then
            if s.previewing then editPreview(false) end
            s.holder:Hide()
        end
        return
    end

    holder(bar)
    local s = stateOf(bar)
    s.holder:Show()

    local size = cfg.attachIconSize or 20
    s.iconBox:SetSize(size, size)
    s.iconBox:SetShown(cfg.attachIcon == true)

    local tsize = cfg.attachTimeSize or 12
    ns.UI.FontFor("resourcebars", s.time, tsize, "OUTLINE")
    -- Wide enough for "10.0" at the chosen size; the text is left-aligned in it,
    -- so the width only decides how big the edit box is.
    s.timeBox:SetSize(tsize * 3, tsize + 4)
    s.timeBox:SetShown(cfg.attachTime == true)

    ns:ApplyMover(s.iconBox.mover)
    ns:ApplyMover(s.timeBox.mover)
end

-- Fed from the cast events: the icon texture and the duration object may both
-- be secret, and both go straight into a setter.
function Skin.OnCastStart(texture, duration)
    local bar = Skin.Frame()
    local cfg = RB.Bar(KEY)
    if not (bar and cfg) or style() == "modern" then return end
    local s = stateOf(bar)
    -- the edit mode example stays until the editor closes
    if not s.holder or s.previewing then return end

    if cfg.attachIcon and ns.Exists(texture) then
        s.icon:SetTexture(texture)
        s.icon:Show()
    else
        s.icon:Hide()
    end

    if cfg.attachTime and ns.Exists(duration) then
        -- The holder owns the ticking, so the time stops by itself the moment
        -- the client's bar goes away and takes its children with it.
        ns:DurationText(s.holder, s.time, duration)
        s.time:Show()
    else
        ns:DurationText(s.holder, s.time, nil)
        s.time:Hide()
    end
end

function Skin.OnCastStop()
    local bar = Skin.Frame()
    if not bar then return end
    local s = state[bar]
    if not s or s.previewing then return end
    if s.holder and s.time then ns:DurationText(s.holder, s.time, nil) end
    if s.icon then s.icon:Hide() end
end

-- ---------------------------------------------------------------- install --

local function hookMethod(bar, method, key, fn)
    if type(bar[method]) ~= "function" then return end
    hooksecurefunc(bar, method, function(self, ...)
        if style() ~= "classic" or not RB.mod.active then return end
        guard(key, fn, self)
    end)
end

-- The frame around the client's bar (its Border region), switched off on
-- request, in the standard and the classic style alike. Alpha on a texture,
-- which a fight does not refuse. Touched only when asked, or to give back what
-- we took: a style that promises to change nothing about the bar must not
-- write its border on every settings change.
local borderHidden = false

function Skin.ApplyBorder()
    local bar = Skin.Frame()
    if not (bar and bar.Border) then return end
    local cfg = RB.Bar(KEY)
    local want = (RB.mod.active and style() ~= "modern" and cfg and cfg.hideBorder) and true or false
    if want == borderHidden then return end
    borderHidden = want
    bar.Border:SetAlpha(want and 0 or 1)
end

local installed = false

function Skin.Apply()
    local bar = Skin.Frame()
    if not bar then return end

    if not installed then
        installed = true
        -- Blizzard re-sets each of these on its own schedule -- the look on a
        -- style change, the fill atlas on every start, stop and finish, the
        -- spark and the glow on every cast. Each hook simply puts the old art
        -- back afterwards, and asks the setting first, so switching the style
        -- back needs no unhooking (a hook cannot be taken off anyway).
        hookMethod(bar, "SetLook", "cast.look", dress)
        hookMethod(bar, "UpdateShownState", "cast.shown", dress)
        hookMethod(bar, "UpdateBarFillTexture", "cast.fill", dressFill)
        hookMethod(bar, "ShowSpark", "cast.spark", function(b) dressSpark(b); hideFx(b) end)
        hookMethod(bar, "PlayFadeAnim", "cast.fade", dressFlash)
        hookMethod(bar, "PlayFinishAnim", "cast.finish", stopFinish)
        hookMethod(bar, "PlayInterruptAnims", "cast.interrupt", hideFx)
    end

    if style() == "classic" then guard("cast.dress", dress, bar) end
    Skin.LayoutExtras()
    guard("cast.border", Skin.ApplyBorder)
end

-- Switching away from classic.
--
-- THIS ONLY EVER RUNS IF WE DRESSED THE BAR FIRST. It used to run on every
-- settings change in the standard style as well, and since it force-feeds the
-- atlases it thinks the bar should have, it was REPAINTING a bar nobody had
-- touched: switching the icon or the cast time on was enough to leave the
-- client's own cast bar with the wrong fill, the wrong border and every
-- decoration forced back to full alpha. A style that promises to change
-- nothing about the bar must touch nothing about the bar.
--
-- Even for a bar we did dress, the atlases go back but Blizzard's own layout
-- numbers are not ours to restore -- so this says so instead of pretending.
function Skin.Restore()
    if not dressed then return end
    local bar = Skin.Frame()
    if not bar then return end
    dressed = false
    if not Skin.reloadHinted then
        Skin.reloadHinted = true
        ns:Print(ns.L["The cast bar keeps a little of the old style until you reload the interface."])
    end
    guard("cast.restore", function()
        if bar.Border and bar.Border.SetAtlas then bar.Border:SetAtlas("ui-castingbar-frame") end
        if bar.Spark and bar.Spark.SetAtlas then bar.Spark:SetAtlas("ui-castingbar-pip") end
        if bar.Flash and bar.Flash.SetAtlas then bar.Flash:SetAtlas("ui-castingbar-full-glow-standard") end
        if bar.Background and bar.Background.SetAtlas then bar.Background:SetAtlas("ui-castingbar-background") end
        for _, key in ipairs(FX) do
            if bar[key] then bar[key]:SetAlpha(1) end
        end
    end)
end
