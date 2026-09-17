-- Minimap button: left click opens the UI, right click the module dropdown, Shift+drag moves it.
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("minimap", {
    name        = "Minimap Button",
    group       = "Core",
    description = "Shows a button on the minimap to quickly open VuloForeverUI. Shift+drag moves the button.",
    defaults = {
        angle  = 215,       -- degrees on the minimap (0 = top, 90 = right, 180 = bottom, 270 = left)
        radius = 80,        -- distance from the minimap center
        hide   = false,     -- hide completely
    },
})

local button

local function createButton()
    if button then return button end

    button = CreateFrame("Button", "VuloForeverUIMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("AnyUp")
    button:RegisterForDrag("LeftButton")
    button:SetMovable(true)
    button:EnableMouse(true)

    button.bg = button:CreateTexture(nil, "BACKGROUND")
    button.bg:SetSize(20, 20)
    button.bg:SetPoint("CENTER", 0, 1)
    button.bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")

    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetSize(20, 20)
    button.icon:SetPoint("CENTER", 0, 1)

    -- We ship vui4.tga locally (VuloForeverUI/Media/Icons/vui4.tga).
    -- If someone has VuloMedia installed instead, that works too.
    local iconPath
    if C_AddOns.IsAddOnLoaded("VuloMedia") then
        iconPath = "Interface\\AddOns\\VuloMedia\\Icons\\vui4"
    else
        iconPath = "Interface\\AddOns\\VuloForeverUI\\Media\\Icons\\vui4"
    end
    button.icon:SetTexture(iconPath)
    button.icon:SetTexCoord(0, 1, 0, 1)

    button.border = button:CreateTexture(nil, "OVERLAY")
    button.border:SetSize(54, 54)
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

local function updatePosition()
    if not button then return end
    local angle  = math.rad(mod.db.angle or 215)
    local radius = mod.db.radius or 80
    local x = radius * math.cos(angle)
    local y = radius * math.sin(angle)
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
            min = 50, max = 120, step = 1,
            get = function() return mod.db.radius end,
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
