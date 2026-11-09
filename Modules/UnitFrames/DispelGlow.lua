-- VuloForeverUI / Modules / UnitFrames / DispelGlow
--
-- Under the target frame only the buffs the player can take off, glowing.
-- Every other buff is gone from there, on friend and foe alike: the player
-- asked for a target frame that shows what is worth a purge and nothing else.
--
-- Blizzard's buff icons cannot be lit from here: they live in the client's
-- locked aura container (TargetFrameAuraContainer.xml sits in a forbidden
-- object table), and whether a buff is dispellable is secret in combat. So
-- the buff ROW is replaced, in place:
--   * Blizzard's container keeps its debuffs; its buff group is handed a
--     filter that matches nothing (SetBuffFilterString is the container's
--     public setter, called out of combat only, and it persists).
--   * Our engine container, pinned under Blizzard's, shows HELPFUL|DISPELLABLE
--     narrowed to Magic (candidate filter includeDispelTypes), which is what
--     Purge, Dispel Magic and Devour Magic take off. The client filters in C;
--     we never look. Each button carries a glow texture.
--   * Only on an enemy target: no friendly buff is ours to purge.
--
-- Only for a character whose spellbook knows a magic dispel
-- (NP.AuraStyle.CanDispelMagic); everyone else keeps Blizzard's row untouched.
-- Not in the Modern style: its own target frame shows no auras at all.
local _, ns = ...
ns.UF = ns.UF or {}
local UF = ns.UF

local DG = {}
UF.DispelGlow = DG

local D = _G.TargetFrameAuraContainerDefaults or {}
local SIZE    = D.SmallAuraSize or 17
local GAP     = D.FlowLayoutElementSpacing or 3
local LINE    = D.FlowLayoutLineSize or 122
local MAX     = 16
local GLOW    = "Interface\\Buttons\\UI-ActionButton-Border"

local holder
local glowC               -- our engine container
local refused              -- the client refused a container or Blizzard's filter
local blizzOff             -- Blizzard's buff group is emptied
local mod
local unitOf = {}          -- container -> token it was last given

local function F(key, fallback)
    local t = AuraUtil and AuraUtil.AuraFilters
    return t and t[key] or fallback
end

local function filter(...)
    if AuraUtil and AuraUtil.CreateFilterString then return AuraUtil.CreateFilterString(...) end
    return table.concat({ ... }, "|")
end

-- Matches nothing on this client: MAW returns Torghast auras only.
local function emptyFilter() return filter(F("Helpful", "HELPFUL"), F("Maw", "MAW")) end
local function blizzFilter()
    return D.BuffFilterString or F("Helpful", "HELPFUL")
end

local function blizzContainer()
    local tf = _G.TargetFrame
    local c = tf and tf.TargetFrameContent and tf.TargetFrameContent.TargetFrameContentContextual
    return c and c.Auras
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

    local cd = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    cd:SetAllPoints(button)
    cd:SetReverse(true)
    cd:SetHideCountdownNumbers(true)

    local top = CreateFrame("Frame", nil, button)
    top:SetAllPoints(button)
    top:SetFrameLevel(cd:GetFrameLevel() + 1)

    local stacks = top:CreateFontString(nil, "OVERLAY")
    stacks:SetFont(ns.ModuleFontPath and ns.ModuleFontPath("unitframes") or STANDARD_TEXT_FONT, 10, "OUTLINE")
    stacks:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 2, -1)

    pcall(button.SetIcon, button, icon)
    pcall(button.SetDurationCooldown, button, cd)
    pcall(button.SetApplicationCount, button, stacks, {})

    -- The light. Every aura in this container is one to purge, so it is
    -- a plain texture of ours, pulsing on a frame of ours.
    local layer = CreateFrame("Frame", nil, button)
    layer:SetAllPoints(button)
    layer:SetFrameLevel(top:GetFrameLevel() + 1)
    local glow = layer:CreateTexture(nil, "OVERLAY")
    glow:SetTexture(GLOW)
    glow:SetBlendMode("ADD")
    glow:SetVertexColor(0.45, 0.8, 1)
    glow:SetPoint("CENTER", button, "CENTER", 0, 0)
    glow:SetSize(SIZE * 1.9, SIZE * 1.9)
    local ag = layer:CreateAnimationGroup()
    ag:SetLooping("BOUNCE")
    local a = ag:CreateAnimation("Alpha")
    a:SetFromAlpha(1)
    a:SetToAlpha(0.35)
    a:SetDuration(0.7)
    a:SetSmoothing("IN_OUT")
    ag:Play()
    -- Mouse motion stays for the client's own aura tooltip; a click would
    -- only swallow the one meant for the frame.
    pcall(button.SetMouseClickEnabled, button, false)
end

local function newContainer()
    local ok, c = pcall(CreateFrame, "AuraContainer", nil, holder, "CustomAuraContainerTemplate")
    if not (ok and c) then return nil end
    local opts = {
        maxFrameCount    = MAX,
        candidateFilters = { includeDispelTypes = { Magic = true } },
        initializeFrame  = initButton,
        layout = { elementWidth = SIZE, elementHeight = SIZE,
                   elementSpacing = GAP, lineSpacing = GAP },
    }
    local want = filter(F("Helpful", "HELPFUL"), F("Dispellable", "DISPELLABLE"))
    if not pcall(c.AddAuraGroup, c, "main", want, opts) then return nil end
    local dir = AnchorUtil and AnchorUtil.FlowDirection
    if c.SetFlowLayoutPadding then pcall(c.SetFlowLayoutPadding, c, 0, 0, 0, 0) end
    if dir and c.SetFlowLayoutGrowthDirection then
        pcall(c.SetFlowLayoutGrowthDirection, c, dir.Right, dir.Down)
    end
    if c.SetFlowLayoutAnchorPoint then pcall(c.SetFlowLayoutAnchorPoint, c, "TOPLEFT") end
    if c.SetFlowLayoutMaximumLineSize then pcall(c.SetFlowLayoutMaximumLineSize, c, LINE) end
    c:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
    unitOf[c] = "none"
    return c
end

local function build()
    if glowC or refused then return glowC end
    holder = CreateFrame("Frame", nil, UIParent)
    holder:SetSize(1, 1)
    glowC = newContainer()
    if not glowC then refused = true end
    return glowC
end

-- Under Blizzard's container: it holds the debuffs and grows down from the
-- frame, so our row follows it as Blizzard's own buff row did. Our holder
-- sits under UIParent and copies the frame's scale by hand.
local function place()
    local bc, tf = blizzContainer(), _G.TargetFrame
    if not (holder and bc and tf) then return end
    holder:SetScale(tf:GetEffectiveScale() / UIParent:GetEffectiveScale())
    holder:ClearAllPoints()
    if not pcall(holder.SetPoint, holder, "TOPLEFT", bc, "BOTTOMLEFT", 0, -GAP) then
        holder:SetPoint("TOPLEFT", tf, "BOTTOMLEFT", 25, 0)
    end
    holder:Show()
end

local function setUnit(c, token)
    if not c then return end
    if unitOf[c] ~= token then
        if pcall(c.SetUnit, c, token) then unitOf[c] = token end
    elseif token ~= "none" then
        -- same token, new unit behind it: SetUnit would be a no-op
        pcall(c.UpdateAllAuras, c)
    end
end

local function hostileTarget()
    if not UnitExists("target") then return false end
    local ok, v = pcall(UnitCanAttack, "player", "target")
    return ok and ns.CanRead(v) and v == true
end

-- Blizzard's buff group off or back on. Its filter persists, so this runs
-- out of combat only, and our row waits for it.
local function setBlizzard(off)
    local bc = blizzContainer()
    if not (bc and bc.SetBuffFilterString) then refused = true; return end
    ns:RunOutOfCombatOnce("vfui_dispelglow_blizz", function()
        if pcall(bc.SetBuffFilterString, bc, off and emptyFilter() or blizzFilter()) then
            blizzOff = off
        else
            -- refused either way: never ours on top of Blizzard's, and no
            -- second try that would only be refused again
            refused = true
            if not off then blizzOff = false end
        end
        DG.Refresh()
    end)
end

local function wanted()
    return mod and mod.active and mod.db.dispelGlow ~= false
        and mod.db.style ~= "modern" and canDispel()
end

function DG.Refresh()
    if refused or not wanted() then
        setUnit(glowC, "none")
        if holder then holder:Hide() end
        if blizzOff then setBlizzard(false) end
        return
    end
    if not build() then return end
    if not blizzOff then
        -- ours only once Blizzard's buffs are gone: never two rows
        setBlizzard(true)
        return
    end
    place()
    setUnit(glowC, hostileTarget() and "target" or "none")
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
        -- Edit Mode may move or rescale the target frame.
        ns:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED", function()
            if mod then ns.NextFrame(DG.Refresh) end
        end)
    end
    DG.Refresh()
end
