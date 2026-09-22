-- Minimap button: left click opens the UI, right click the module dropdown, Shift+drag moves it.
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("minimap", {
    name        = "Minimap Button",
    group       = "Core",
    description = "Shows a button on the minimap to quickly open VuloForeverUI. Shift+drag moves the button.",
    defaults = {
        angle  = 215,       -- degrees on the minimap (0 = right, 90 = top, 180 = left, 270 = bottom)
        -- radius: distance from the minimap center; unset = sit on the rim (see edgeRadius)
        hide   = false,     -- hide completely
    },
})

local button

local function createButton()
    if button then return button end

    -- Sizes are the Mainline set of the common minimap-button recipe (this is
    -- a Mainline client): 31 button, 50 ring, 24 ground, 18 icon, all centred.
    -- The Classic set (53 ring, offsets from TOPLEFT) sits visibly off-centre
    -- here, which is what the button looked like before.
    button = CreateFrame("Button", "VuloForeverUIMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFixedFrameStrata(true)
    button:SetFrameLevel(8)
    button:SetFixedFrameLevel(true)
    button:RegisterForClicks("AnyUp")
    button:RegisterForDrag("LeftButton")
    button:SetMovable(true)
    button:EnableMouse(true)

    button.bg = button:CreateTexture(nil, "BACKGROUND")
    button.bg:SetSize(24, 24)
    button.bg:SetPoint("CENTER", 0, 0)
    button.bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")

    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetSize(18, 18)
    button.icon:SetPoint("CENTER", 0, 0)

    -- We ship vui4.tga locally (VuloForeverUI/Media/Icons/ui/vui4.tga).
    -- If someone has VuloMedia installed instead, that works too.
    local iconPath
    if C_AddOns.IsAddOnLoaded("VuloMedia") then
        iconPath = "Interface\\AddOns\\VuloMedia\\Icons\\vui4"
    else
        iconPath = "Interface\\AddOns\\VuloForeverUI\\Media\\Icons\\ui\\vui4"
    end
    button.icon:SetTexture(iconPath)

    -- Press feedback: the icon rests 5% inset and fills out while the mouse
    -- is down, so a click is visible without a second texture.
    local function setPressed(pressed)
        local d = pressed and 0 or 0.05
        button.icon:SetTexCoord(d, 1 - d, d, 1 - d)
    end
    setPressed(false)
    button:SetScript("OnMouseDown", function() setPressed(true) end)
    button:SetScript("OnMouseUp",   function() setPressed(false) end)

    button.border = button:CreateTexture(nil, "OVERLAY")
    button.border:SetSize(50, 50)
    button.border:SetPoint("TOPLEFT", 0, 0)
    button.border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    button:SetScript("OnClick", function(_, mouseBtn)
        if mouseBtn == "LeftButton" then
            if ns.UI and ns.UI.ToggleMainFrame then
                ns.UI:ToggleMainFrame()
            else
                ns:Print(L["UI is not loaded yet."])
            end
        elseif mouseBtn == "RightButton" then
            mod:ShowDropdown()
        end
    end)

    button:SetScript("OnDragStart", function(self)
        if IsShiftKeyDown() then
            self.isMoving = true
            self:SetScript("OnUpdate", mod.OnUpdatePosition)
        end
    end)
    button:SetScript("OnDragStop", function(self)
        self.isMoving = false
        self:SetScript("OnUpdate", nil)
    end)

    ns.UI:AttachTooltip(button, {
        anchor = "ANCHOR_LEFT",
        title  = (ns.C and ns.C.accent or "|cff9b6cff") .. "VuloForeverUI|r",
        lines  = {
            { L["|cffffffffLeft click:|r Open options"],           1, 1, 1 },
            { L["|cffffffffRight click:|r Quick module selection"], 1, 1, 1 },
            { L["|cffffffffShift+drag:|r Move button"],            1, 1, 1 },
        },
    })

    return button
end

-- The rim follows the minimap's actual size, so the button stays on the edge
-- whatever size the client or another setting gives the minimap. 5 px past
-- the half width puts the ring half over the map edge, level with the other
-- buttons that share this recipe.
local RIM_OVERHANG = 5

local function edgeRadius(extent)
    return math.floor((extent or 140) / 2 + RIM_OVERHANG + 0.5)
end

-- GetMinimapShape is the convention minimap addons use to announce a square or
-- corner-cut map. Per quadrant (1 = top-right, going counter-clockwise):
-- true = round there (follow the circle), false = square there (push out to
-- the corner, clamped to the box).
local minimapShapes = {
    ["ROUND"]                 = { true,  true,  true,  true  },
    ["SQUARE"]                = { false, false, false, false },
    ["CORNER-TOPLEFT"]        = { false, false, false, true  },
    ["CORNER-TOPRIGHT"]       = { false, false, true,  false },
    ["CORNER-BOTTOMLEFT"]     = { false, true,  false, false },
    ["CORNER-BOTTOMRIGHT"]    = { true,  false, false, false },
    ["SIDE-LEFT"]             = { false, true,  false, true  },
    ["SIDE-RIGHT"]            = { true,  false, true,  false },
    ["SIDE-TOP"]              = { false, false, true,  true  },
    ["SIDE-BOTTOM"]           = { true,  true,  false, false },
    ["TRICORNER-TOPLEFT"]     = { false, true,  true,  true  },
    ["TRICORNER-TOPRIGHT"]    = { true,  false, true,  true  },
    ["TRICORNER-BOTTOMLEFT"]  = { true,  true,  false, true  },
    ["TRICORNER-BOTTOMRIGHT"] = { true,  true,  true,  false },
}

local function updatePosition()
    if not button then return end
    local angle = math.rad(mod.db.angle or 215)
    local x, y, q = math.cos(angle), math.sin(angle), 1
    if x < 0 then q = q + 1 end
    if y > 0 then q = q + 2 end
    local shape = (_G.GetMinimapShape and _G.GetMinimapShape()) or "ROUND"
    local quads = minimapShapes[shape] or minimapShapes.ROUND
    local w = mod.db.radius or edgeRadius(Minimap:GetWidth())
    local h = mod.db.radius or edgeRadius(Minimap:GetHeight())
    if quads[q] then
        x, y = x * w, y * h
    else
        local diagW = math.sqrt(2 * w ^ 2) - 10
        local diagH = math.sqrt(2 * h ^ 2) - 10
        x = math.max(-w, math.min(x * diagW, w))
        y = math.max(-h, math.min(y * diagH, h))
    end
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

mod.UpdatePosition = updatePosition

function mod.OnUpdatePosition()
    if not button or not button.isMoving then return end
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    cx, cy = cx / scale, cy / scale
    local dx, dy = cx - mx, cy - my
    -- Angle in degrees (0 = right, mathematical)
    local angle = math.deg(math.atan2(dy, dx))
    mod.db.angle = angle
    updatePosition()
end

local function applyVisibility()
    if not button then return end
    if mod.db.hide then button:Hide() else button:Show() end
end

mod.ApplyVisibility = applyVisibility

-- Uses the ns:ShowPopupMenu helper (EasyMenu is unreliable in Anniversary)
function mod:ShowDropdown(anchor)
    local entries = {
        { title = true, text = (ns.C and ns.C.accent or "|cff9b6cff") .. "VuloForeverUI|r" },
        { text = L["Open Options"],
          func = function() if ns.UI then ns.UI:ToggleMainFrame() end end },
        { separator = true },
    }

    for _, key in ipairs(ns.moduleOrder) do
        local m = ns.modules[key]
        if m and m.db then
            local capturedKey, capturedMod = key, m
            table.insert(entries, {
                text     = L[capturedMod.name],  -- raw key → translate live
                checked  = function() return ns:IsModuleEnabled(capturedKey) end,
                func     = function() ns:ToggleModule(capturedKey, not ns:IsModuleEnabled(capturedKey)) end,
                keepOpen = true,
            })
        end
    end

    table.insert(entries, { separator = true })
    table.insert(entries, { text = L["Reload UI"], func = function() ReloadUI() end })

    -- the button as owner: a cursor anchor cannot be mouse-over-tested, and
    -- without it the opening click could never toggle the menu closed again
    ns:ShowPopupMenu(entries, anchor or "cursor", anchor or button)
end

function mod:OnEnable()
    createButton()
    updatePosition()
    applyVisibility()
end

function mod:GetOptions()
    return {
        { type = "header", text = L["Minimap"] },
        {
            type = "toggle", label = L["Show button on minimap"],
            tooltip = L["If off, the button is completely hidden."],
            get = function() return not mod.db.hide end,
            set = function(_, v) mod.db.hide = not v; applyVisibility() end,
        },
        {
            type = "slider", label = L["Distance from center"],
            min = 50, max = 160, step = 1,
            get = function() return mod.db.radius or edgeRadius(Minimap:GetWidth()) end,
            set = function(_, v) mod.db.radius = v; updatePosition() end,
        },
        {
            type = "slider", label = L["Angle (degrees)"],
            min = 0, max = 360, step = 1,
            get = function() return mod.db.angle end,
            set = function(_, v) mod.db.angle = v; updatePosition() end,
        },
        { type = "spacer", height = 6 },
        { type = "desc", text = L["Tip: You can also move the button directly on the minimap — hold Shift and drag it to the desired position."] },
    }
end
