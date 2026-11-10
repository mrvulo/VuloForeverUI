-- VuloForeverUI / Modules / UnitFrames / DispelGlow
--
-- On an enemy target the buff row stays what it is -- every buff, where the
-- client draws them, under the debuffs -- and the buffs THIS character can
-- take off glow. Friendly targets and everything else are left alone.
--
-- Blizzard's buff icons cannot be lit from here: they live in the client's
-- locked aura container, and whether a buff is dispellable is secret in
-- combat. So on an enemy target the buff ROW is replaced, in place:
--   * Blizzard's container keeps its debuffs; its buff group is capped at
--     0 (SetMaxBuffs, the container's public setter). Its filter string is no
--     help: the target container's ShouldIncludeAuraInGroup ignores the
--     filter match and takes every helpful aura (TargetFrameAuraContainer.lua
--     :257 / :358). TargetFrame:ConfigureAuraContainer puts the cap back on
--     every target, faction and target-of-target change (TargetFrame.lua
--     :511), so a post-hook lowers it again. On a friendly target the cap is
--     handed back and Blizzard draws its own row.
--   * Our engine container, pinned under Blizzard's (where the client puts an
--     enemy's buffs: after the debuffs), shows the same buffs in two groups
--     that flow as one row: HELPFUL|RAID_PLAYER_DISPELLABLE with a glow --
--     the engine itself answers "can THIS player take it off" -- and
--     HELPFUL|!RAID_PLAYER_DISPELLABLE without. We never look at an aura.
--
-- Only for a character whose spellbook knows a spell that takes a buff off an
-- enemy, magic or enrage (NP.AuraStyle.CanDispel); everyone else keeps
-- Blizzard's row untouched.
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
local MAX_GLOW = 16
local MAX_REST = 32
-- The light is the client's own "this spell just lit up" art from the action
-- bar: a warm white frame with a golden halo that runs around the icon. The
-- numbers are the client's (ActionButtonSpellAlerts.xml / .lua): thirty
-- frames in six rows of five, one second a lap, 1.4 times the button.
local GLOW_ATLAS = "UI-HUD-ActionBar-Proc-Loop-Flipbook"
local GLOW_SCALE = 1.4
-- Should a build not carry the atlas: the older ring of the same art.
local GLOW_FILE  = "Interface\\SpellActivationOverlay\\IconAlert"

local holder
local glowC               -- our engine container
local refused              -- the client refused our container
local blizzOff             -- Blizzard's buff group is capped at 0
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

local function blizzContainer()
    local tf = _G.TargetFrame
    local c = tf and tf.TargetFrameContent and tf.TargetFrameContent.TargetFrameContentContextual
    return c and c.Auras
end

local function canDispel()
    local S = ns.NP and ns.NP.AuraStyle
    if not S then return false end
    S.RefreshDispel()
    return S.CanDispel()
end

-- The engine hands each button over once, here; afterwards it is theirs.
-- `lit`: the button belongs to the group of buffs the player can take off.
local function initButton(button, lit)
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

    -- Mouse motion stays for the client's own aura tooltip; a click would
    -- only swallow the one meant for the frame.
    pcall(button.SetMouseClickEnabled, button, false)
    if not lit then return end

    -- The light. Every aura in the lit group is one to purge, so it is a
    -- plain texture of ours, animated on a frame of ours; nothing is asked.
    local layer = CreateFrame("Frame", nil, button)
    layer:SetAllPoints(button)
    layer:SetFrameLevel(top:GetFrameLevel() + 1)
    local glow = layer:CreateTexture(nil, "OVERLAY")
    glow:SetPoint("CENTER", button, "CENTER", 0, 0)
    glow:SetSize(SIZE * GLOW_SCALE, SIZE * GLOW_SCALE)
    local ag = glow:CreateAnimationGroup()
    if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(GLOW_ATLAS) then
        glow:SetAtlas(GLOW_ATLAS)
        ag:SetLooping("REPEAT")
        local flip = ag:CreateAnimation("FlipBook")
        flip:SetFlipBookRows(6)
        flip:SetFlipBookColumns(5)
        flip:SetFlipBookFrames(30)
        flip:SetFlipBookFrameWidth(0)
        flip:SetFlipBookFrameHeight(0)
        flip:SetDuration(1)
    else
        glow:SetTexture(GLOW_FILE)
        glow:SetTexCoord(0.00781250, 0.50781250, 0.27734375, 0.52734375)
        glow:SetBlendMode("ADD")
        ag:SetLooping("BOUNCE")
        local a = ag:CreateAnimation("Alpha")
        a:SetFromAlpha(1)
        a:SetToAlpha(0.45)
        a:SetDuration(0.6)
        a:SetSmoothing("IN_OUT")
    end
    ag:Play()
end

local function newContainer()
    local ok, c = pcall(CreateFrame, "AuraContainer", nil, holder, "CustomAuraContainerTemplate")
    if not (ok and c) then return nil end
    -- Two groups, one row: the buffs to purge first, lit, then the rest.
    local function group(key, index, max, lit, ...)
        return pcall(c.AddAuraGroup, c, key, filter(F("Helpful", "HELPFUL"), ...), {
            maxFrameCount   = max,
            initializeFrame = function(button) initButton(button, lit) end,
            layout = { layoutIndex = index, elementWidth = SIZE, elementHeight = SIZE,
                       elementSpacing = GAP, lineSpacing = GAP,
                       groupSpacing = GAP, groupLineSpacing = GAP },
        })
    end
    local mine = F("RaidPlayerDispellable", "RAID_PLAYER_DISPELLABLE")
    local neg = (AuraUtil and AuraUtil.AuraFilterNegationPrefix) or "!"
    if not group("purge", 1, MAX_GLOW, true, mine) then return nil end
    if not group("rest", 2, MAX_REST, false, neg .. mine) then return nil end
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

-- Blizzard's buff group off (cap 0) or back to what the frame asks for.
local function blizzCap()
    local tf = _G.TargetFrame
    local n = tf and tf.maxBuffs or D.MaxBuffs
    return type(n) == "number" and n or 32
end

local function setBlizzard(off)
    local bc = blizzContainer()
    if not (bc and bc.SetMaxBuffs) then return false end
    if pcall(bc.SetMaxBuffs, bc, off and 0 or blizzCap()) then
        blizzOff = off
        return true
    end
    return false
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
    -- Ours only on an enemy, and only once Blizzard's buffs are gone there:
    -- never two rows. Everything else is Blizzard's row, untouched.
    if not (hostileTarget() and setBlizzard(true)) then
        setUnit(glowC, "none")
        holder:Hide()
        if blizzOff then setBlizzard(false) end
        return
    end
    place()
    setUnit(glowC, "target")
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
        -- Blizzard puts its buff cap back on every reconfigure.
        local tf = _G.TargetFrame
        if tf and tf.ConfigureAuraContainer then
            hooksecurefunc(tf, "ConfigureAuraContainer", function()
                if blizzOff and mod then setBlizzard(true) end
            end)
        end
        -- Edit Mode may move or rescale the target frame.
        ns:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED", function()
            if mod then ns.NextFrame(DG.Refresh) end
        end)
    end
    DG.Refresh()
end
