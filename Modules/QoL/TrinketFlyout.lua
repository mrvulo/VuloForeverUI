-- VuloForeverUI / Modules / QoL / TrinketFlyout
--
-- The pick grid: hovering a trinket slot opens a grid of every trinket in
-- the bags, each with its own cooldown. Left click puts it into the upper
-- slot, right click into the lower one; alt-click hides it from the grid
-- (with Alt held the hidden ones show grey and come back the same way).
--
-- A plain frame, never secure: equipping is refused in a fight anyway, so a
-- click there only notes the pick (Trinkets.Pick) and it goes on when the
-- fight ends. Showing and hiding a plain frame is free in combat too.
--
-- It opens away from the screen's middle (down from a window in the top
-- half, up from one in the bottom half) and closes once the mouse has left
-- both the slots and the grid.
local _, ns = ...
local L = ns.L

local QoL = ns.QoL
local Trinkets = QoL.Trinkets

local CELL, GAP, PAD = 32, 3, 4

local grid, cells = nil, {}

local function hiddenSet()
    local c = _G.VuloForeverUICharDB
    if type(c) ~= "table" then return {} end
    if type(c.trinketHidden) ~= "table" then c.trinketHidden = {} end
    return c.trinketHidden
end

local function showTip(cell)
    local id = cell.id
    if not id then return end
    GameTooltip:SetOwner(cell, "ANCHOR_RIGHT")
    GameTooltip:SetItemByID(id)
    GameTooltip:AddLine(L["Left click: upper slot. Right click: lower slot. Alt-click: hide from this grid."], 0.6, 0.6, 0.65, true)
    if InCombatLockdown() then
        GameTooltip:AddLine(L["In combat: the pick goes on after the fight."], 1, 0.82, 0, true)
    end
    GameTooltip:Show()
end

local render

local function makeCell(i)
    local c = CreateFrame("Button", nil, grid)
    c:SetSize(CELL, CELL)
    c:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local bg = c:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(c)
    bg:SetColorTexture(0, 0, 0, 0.6)
    c.icon = c:CreateTexture(nil, "ARTWORK")
    c.icon:SetPoint("TOPLEFT", 1, -1)
    c.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    c.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    c.cd = CreateFrame("Cooldown", nil, c, "CooldownFrameTemplate")
    c.cd:SetAllPoints(c.icon)
    c.edges = ns.MakeEdges(c, "OVERLAY")
    local hl = c:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(c.icon)
    hl:SetColorTexture(1, 1, 1, 0.15)
    c:SetScript("OnClick", function(self, button)
        local id = self.id
        if not id then return end
        if IsAltKeyDown() then
            local h = hiddenSet()
            h[id] = (not h[id]) and true or nil
            render()
            return
        end
        Trinkets.Pick(id, button == "RightButton" and 14 or 13)
        GameTooltip:Hide()
        if not InCombatLockdown() then Trinkets.HideGrid() else render() end
    end)
    c:SetScript("OnEnter", showTip)
    c:SetScript("OnLeave", function() GameTooltip:Hide() end)
    cells[i] = c
    return c
end

-- The trinkets to offer: in the bags, not worn, not hidden (Alt shows the
-- hidden ones, grey, so they can be brought back).
local function offer()
    local out, hidden, alt = {}, hiddenSet(), IsAltKeyDown()
    for _, id in ipairs(Trinkets.Owned()) do
        if Trinkets.InBags(id) and (alt or not hidden[id]) then out[#out + 1] = id end
    end
    return out
end

function render()
    if not (grid and grid:IsShown()) then return end
    local list = offer()
    if #list == 0 then grid:Hide(); return end
    local cols = math.max(1, math.min(#list, Trinkets.Db().gridColumns or 4))
    local rows = math.ceil(#list / cols)
    grid:SetSize(PAD * 2 + cols * CELL + (cols - 1) * GAP, PAD * 2 + rows * CELL + (rows - 1) * GAP)
    local hidden = hiddenSet()
    local picked = {}
    for _, pid in pairs(Trinkets.pendingPick) do picked[pid] = true end
    for i, id in ipairs(list) do
        local c = cells[i] or makeCell(i)
        local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
        c:ClearAllPoints()
        c:SetPoint("TOPLEFT", grid, "TOPLEFT", PAD + col * (CELL + GAP), -PAD - row * (CELL + GAP))
        c.id = id
        c.icon:SetTexture(Trinkets.ItemIcon(id))
        c.icon:SetDesaturated(hidden[id] == true)
        c.icon:SetAlpha(hidden[id] and 0.5 or 1)
        -- a pick waiting for the fight to end is framed in gold
        if picked[id] then
            ns.LayoutEdges(c.edges, c, 1, 1, 0.82, 0, 1)
        else
            ns.LayoutEdges(c.edges, c, 1, 0, 0, 0, 1)
        end
        -- handed on as they come: secret in a fight, so nil is tested by TYPE
        local start, dur = C_Container.GetItemCooldown(id)
        if type(start) == "nil" then start = 0 end
        if type(dur) == "nil" then dur = 0 end
        pcall(c.cd.SetCooldown, c.cd, start, dur)
        c:Show()
    end
    for i = #list + 1, #cells do cells[i]:Hide(); cells[i].id = nil end
end

local elapsed = 0
local function watch(self, dt)
    elapsed = elapsed + dt
    if elapsed < 0.2 then return end
    elapsed = 0
    local holder = Trinkets.Holder()
    if not (self:IsMouseOver() or (holder and holder:IsMouseOver())) then self:Hide() end
end

local function build()
    if grid then return end
    grid = CreateFrame("Frame", "VuloForeverUITrinketGrid", UIParent)
    grid:SetFrameStrata("DIALOG")
    grid:SetClampedToScreen(true)
    grid:EnableMouse(true)
    grid:Hide()
    ns.UI:StyleBackdrop(grid, { bg = ns.COLORS.bg, border = ns.COLORS.border })
    grid:SetScript("OnUpdate", watch)
    grid:SetScript("OnEvent", function() render() end)
    grid:SetScript("OnShow", function(self)
        self:RegisterEvent("MODIFIER_STATE_CHANGED")
        self:RegisterEvent("BAG_UPDATE_DELAYED")
        self:RegisterEvent("BAG_UPDATE_COOLDOWN")
        self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    end)
    grid:SetScript("OnHide", function(self) self:UnregisterAllEvents() end)
end

function Trinkets.ShowGrid(slotButton)
    local d = Trinkets.Db()
    if not d.grid then return end
    local holder = Trinkets.Holder()
    if not holder then return end
    build()
    -- away from the middle of the screen, lined up with the slots
    grid:ClearAllPoints()
    local _, cy = holder:GetCenter()
    local up = cy and cy < (UIParent:GetHeight() / 2)
    if up then
        grid:SetPoint("BOTTOMLEFT", holder, "TOPLEFT", 0, 4)
    else
        grid:SetPoint("TOPLEFT", holder, "BOTTOMLEFT", 0, -4)
    end
    grid:SetScale(holder:GetEffectiveScale() / UIParent:GetEffectiveScale())
    elapsed = 0
    grid:Show()
    render()
end

function Trinkets.HideGrid()
    if grid then grid:Hide() end
end
