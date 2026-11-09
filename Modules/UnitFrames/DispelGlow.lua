-- VuloForeverUI / Modules / UnitFrames / DispelGlow
--
-- On an enemy target, the buffs the player can take off glow in a row of
-- their own just above the target frame.
--
-- Why a row of our own and not a glow on Blizzard's buff icons: those icons
-- live in the client's secure aura container (TargetFrameAuraContainer.xml
-- sits in a forbidden object table) and whether a buff is dispellable is
-- secret in combat, so no addon may look at an icon and decide to light it.
-- What the client DOES let us do is hand it a filter string: an engine aura
-- container on "target" with HELPFUL|DISPELLABLE, which the client evaluates
-- in C, creates the buttons for and lays out. We only style the buttons, once,
-- in the initialiser (the same route as the nameplate auras).
--
-- Whether the player can dispel at all comes from the spellbook
-- (NP.AuraStyle.CanDispelMagic), never from an aura. Magic only: DISPELLABLE
-- alone means "anyone could", so the row also narrows to the dispel type the
-- offensive dispels of this client take off (Purge, Dispel Magic, Devour
-- Magic) -- the engine compares it in C.
local _, ns = ...
ns.UF = ns.UF or {}
local UF = ns.UF

local DG = {}
UF.DispelGlow = DG

local SIZE, GAP = 26, 3
local MAX = 8
local GLOW = "Interface\\Buttons\\UI-ActionButton-Border"

local holder, container
local refused        -- the client cannot build engine containers: stop asking
local mod
local unitSet        -- the token the container was last given

local function filter()
    local F = AuraUtil and AuraUtil.AuraFilters or {}
    local parts = { F.Helpful or "HELPFUL", F.Dispellable or "DISPELLABLE" }
    if AuraUtil and AuraUtil.CreateFilterString then
        return AuraUtil.CreateFilterString(unpack(parts))
    end
    return table.concat(parts, "|")
end

local function canDispel()
    local S = ns.NP and ns.NP.AuraStyle
    if not S then return false end
    S.RefreshDispel()
    return S.CanDispelMagic()
end

-- The engine hands each button over once, here; afterwards it is theirs.
local function initButton(button)
    button:SetSize(SIZE, SIZE)

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(button)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local cd = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    cd:SetAllPoints(button)
    cd:SetReverse(true)
    cd:SetHideCountdownNumbers(true)

    -- Above the cooldown, so the swipe does not dim the light.
    local top = CreateFrame("Frame", nil, button)
    top:SetAllPoints(button)
    top:SetFrameLevel(cd:GetFrameLevel() + 1)

    local edges = ns.MakeEdges(top, "OVERLAY")
    ns.LayoutEdgesAt(edges, button, 1, 0.45, 0.8, 1, 1, -1)

    -- The light: the classic action-button glow, additive, softly pulsing.
    local glow = top:CreateTexture(nil, "OVERLAY")
    glow:SetTexture(GLOW)
    glow:SetBlendMode("ADD")
    glow:SetVertexColor(0.45, 0.8, 1)
    glow:SetPoint("CENTER", button, "CENTER", 0, 0)
    glow:SetSize(SIZE * 1.9, SIZE * 1.9)
    local ag = glow:CreateAnimationGroup()
    ag:SetLooping("BOUNCE")
    local a = ag:CreateAnimation("Alpha")
    a:SetFromAlpha(1)
    a:SetToAlpha(0.35)
    a:SetDuration(0.7)
    a:SetSmoothing("IN_OUT")
    ag:Play()

    local stacks = top:CreateFontString(nil, "OVERLAY")
    stacks:SetFont(ns.ModuleFontPath and ns.ModuleFontPath("unitframes") or STANDARD_TEXT_FONT, 11, "OUTLINE")
    stacks:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 1, 1)

    pcall(button.SetIcon, button, icon)
    pcall(button.SetDurationCooldown, button, cd)
    pcall(button.SetApplicationCount, button, stacks, {})
    -- Tooltips on engine buttons are the client's (AuraButtonTooltip); a
    -- click would only swallow the one meant for the frame below.
    pcall(button.SetMouseClickEnabled, button, false)
end

local function build()
    if container or refused then return container end
    holder = CreateFrame("Frame", nil, UIParent)
    holder:SetSize(1, 1)
    local ok, c = pcall(CreateFrame, "AuraContainer", nil, holder, "CustomAuraContainerTemplate")
    if not (ok and c) then refused = true; return nil end
    -- Pinned once, before the group; the container sizes itself from there.
    c:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", 0, 0)
    local opts = {
        maxFrameCount   = MAX,
        candidateFilters = { includeDispelTypes = { Magic = true } },
        initializeFrame = initButton,
        layout = { elementWidth = SIZE, elementHeight = SIZE,
                   elementSpacing = GAP, lineSpacing = GAP },
    }
    if not pcall(c.AddAuraGroup, c, "main", filter(), opts) then refused = true; return nil end

    local dir = AnchorUtil and AnchorUtil.FlowDirection
    if c.SetFlowLayoutPadding then pcall(c.SetFlowLayoutPadding, c, 0, 0, 0, 0) end
    if dir and c.SetFlowLayoutGrowthDirection then
        pcall(c.SetFlowLayoutGrowthDirection, c, dir.Right, dir.Up)
    end
    if c.SetFlowLayoutAnchorPoint then pcall(c.SetFlowLayoutAnchorPoint, c, "BOTTOMLEFT") end
    if c.SetFlowLayoutMaximumLineSize then
        pcall(c.SetFlowLayoutMaximumLineSize, c, MAX * (SIZE + GAP))
    end
    container = c
    return c
end

-- The frame the player sees for the target: ours in the Modern style,
-- Blizzard's otherwise. Its left edge where the bars start.
local function anchorFrame()
    if mod.db.style == "modern" then
        local f = UF.Frames and UF.Frames.target
        if f then return f, 0, 4 end
    end
    if _G.TargetFrame then return _G.TargetFrame, 26, 2 end
    return nil
end

-- Our holder sits under UIParent, so it follows the target frame's scale by
-- hand: a frame of ours parented into Blizzard's secure frame would run its
-- hide scripts in Blizzard's path.
local function place()
    if not holder then return end
    local f, x, y = anchorFrame()
    holder:ClearAllPoints()
    if not f then holder:Hide(); return end
    local s = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
    holder:SetScale(s)
    holder:SetPoint("BOTTOMLEFT", f, "TOPLEFT", x, y)
    holder:Show()
end

local function wanted()
    return mod and mod.active and mod.db.dispelGlow ~= false and canDispel()
end

local function hostileTarget()
    if not UnitExists("target") then return false end
    local ok, v = pcall(UnitCanAttack, "player", "target")
    return ok and ns.CanRead(v) and v == true
end

local function setUnit(token)
    if not container then return end
    if unitSet ~= token then
        if pcall(container.SetUnit, container, token) then unitSet = token end
    elseif token ~= "none" then
        -- same token, new unit behind it: SetUnit would be a no-op
        pcall(container.UpdateAllAuras, container)
    end
end

function DG.Refresh()
    if not wanted() then
        setUnit("none")
        if holder then holder:Hide() end
        return
    end
    if not build() then return end
    place()
    setUnit(hostileTarget() and "target" or "none")
end

local hooked
function DG.Enable(m)
    mod = m
    if not hooked then
        hooked = true
        for _, ev in ipairs({ "PLAYER_TARGET_CHANGED", "SPELLS_CHANGED",
                              "PLAYER_ENTERING_WORLD", "UNIT_FACTION", "UNIT_FLAGS" }) do
            ns:RegisterEvent(ev, function(_, unit)
                -- faction and flags: a duel or PvP flag can turn the same
                -- target hostile without a target change
                if (ev == "UNIT_FACTION" or ev == "UNIT_FLAGS") and unit ~= "target" then return end
                if mod then DG.Refresh() end
            end)
        end
        -- Edit Mode may move or rescale the target frame; out of a fight
        -- the row follows on the next refresh.
        ns:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED", function()
            if mod then ns.NextFrame(DG.Refresh) end
        end)
    end
    DG.Refresh()
end
