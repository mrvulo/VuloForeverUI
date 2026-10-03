-- VuloForeverUI / Modules / ActionBars / ClassicBarDress: the 1.x art on the bags, the key ring and the page arrows, and the backpack's free-slot count
local _, ns = ...
local AB = ns.AB
local Classic = AB.ClassicBar
local P = AB._classic

local KEYRING_W, ratio, unskipMicro = P.KEYRING_W, P.ratio, P.unskipMicro

-- ---------------------------------------------------------------- dress --
--
-- The bags keep the client's frames but wear the 1.x art. They are plain
-- buttons, not secure action buttons, so their textures are ours to set, and
-- the client's own texture pass puts its art back on restore.

-- The bags: the 1.x ring around a square icon. The client re-dresses a bag
-- button in its own UpdateTextures whenever that bag changes, so the dress is
-- hooked onto that call, once per button, and does nothing while the band is
-- off.
local BAG_RING = "Interface\\Buttons\\UI-Quickslot2"
local bagHooked = setmetatable({}, { __mode = "k" })

local function bagButtons()
    local out = {}
    for _, name in ipairs({ "MainMenuBarBackpackButton", "CharacterBag0Slot", "CharacterBag1Slot",
        "CharacterBag2Slot", "CharacterBag3Slot", "CharacterReagentBag0Slot", "KeyRingButton" }) do
        if _G[name] then out[#out + 1] = _G[name] end
    end
    return out
end

-- The key ring was never a bag slot in 1.x but a tall narrow post.
local KEYRING_ART = "Interface\\Buttons\\UI-Button-KeyRing"
local KEYRING_COORDS = { 0, 0.5625, 0, 0.609375 }
local KEYRING_H = 39

local function dressKeyRing(b)
    local fs = ratio(b)
    local function post(tex, file)
        if not tex then return end
        pcall(function()
            tex:SetTexture(file)
            tex:SetTexCoord(unpack(KEYRING_COORDS))
            tex:ClearAllPoints()
            tex:SetPoint("CENTER", b, "CENTER")
            tex:SetSize(KEYRING_W / fs, KEYRING_H / fs)
        end)
    end
    post(b:GetNormalTexture(), KEYRING_ART)
    post(b:GetPushedTexture(), KEYRING_ART .. "-Down")
    post(b:GetHighlightTexture(), KEYRING_ART .. "-Highlight")
    if b.icon then pcall(b.icon.SetAlpha, b.icon, 0) end
end

local function dressBag(b)
    if not P.applied then return end
    if b == _G.KeyRingButton then return dressKeyRing(b) end
    local w = b:GetWidth() or 45
    if w <= 0 then w = 45 end
    local ring = w * 64 / 37
    for _, tex in ipairs({ b:GetNormalTexture(), b:GetPushedTexture() }) do
        pcall(function()
            tex:SetTexture(BAG_RING)
            tex:SetTexCoord(0, 1, 0, 1)
            tex:ClearAllPoints()
            tex:SetPoint("CENTER", b, "CENTER", 0, -w / 37)
            tex:SetSize(ring, ring)
        end)
    end
    -- The rounded mask is what made the icon a porthole; 1.x bags are square.
    if b.icon and b.SquareMask then pcall(b.icon.RemoveMaskTexture, b.icon, b.SquareMask) end
end

-- The free bag slots on the backpack, in the 1.x place (bottom right). The
-- client writes the same number into the backpack's own Count, but on the
-- band that string ended up out of sight under the ring; a font string of
-- ours on a frame ABOVE the button is on top whatever the client's layers do.
-- The backpack is a plain button, so a child frame of ours on it is allowed.
-- Not tied to the band: the number is wanted on the client's own bag bar just
-- as much, so the action bar module switches it on whatever the bar style.
local freeHost, freeText, freeWanted
local freeEvents = CreateFrame("Frame")

local function paintFree()
    if not freeText then return end
    local on = freeWanted and AB.db().backpackFreeSlots ~= false
    freeHost:SetShown(on)
    local own = _G.MainMenuBarBackpackButton and _G.MainMenuBarBackpackButton.Count
    if own then pcall(own.SetAlpha, own, on and 0 or 1) end
    if not on then return end
    -- Re-asserted on every paint: the band's layout and the client's bag bar
    -- both re-level the button after we built the host, and a host left at its
    -- old level ends up under the ring with the number out of sight.
    local b = _G.MainMenuBarBackpackButton
    if b then
        freeHost:SetFrameStrata(b:GetFrameStrata())
        freeHost:SetFrameLevel(b:GetFrameLevel() + 5)
    end
    local free = C_Container.CalculateTotalNumberOfFreeBagSlots()
    freeText:SetText(type(free) == "number" and tostring(free) or "")
end

freeEvents:SetScript("OnEvent", paintFree)

local function dressFreeSlots(on)
    freeWanted = on
    local b = _G.MainMenuBarBackpackButton
    if not b then return end
    if on and not freeHost then
        freeHost = CreateFrame("Frame", nil, b)
        freeHost:SetAllPoints(b)
        freeHost:SetFrameLevel(b:GetFrameLevel() + 5)
        freeText = freeHost:CreateFontString(nil, "OVERLAY", "NumberFontNormal", 7)
        freeText:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -3, 3)
        freeText:SetJustifyH("RIGHT")
    end
    if on then
        freeEvents:RegisterEvent("BAG_UPDATE_DELAYED")
        freeEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
        if not freeHost.hooked then
            freeHost.hooked = true
            hooksecurefunc(b, "SetFrameLevel", paintFree)
            b:HookScript("OnShow", paintFree)
        end
    else
        freeEvents:UnregisterAllEvents()
    end
    paintFree()
end

-- For a look from the chat when the number does not show:
-- /run print(VuloForeverUI.AB.ClassicBar.FreeSlotsState())
-- Called by the module on every apply and on disable.
function Classic.FreeSlots(on)
    dressFreeSlots(on and AB.db().backpackFreeSlots ~= false)
end

function Classic.FreeSlotsState()
    local b = _G.MainMenuBarBackpackButton
    return "applied", P.applied, "setting", AB.db().backpackFreeSlots,
        "host", freeHost ~= nil, freeHost and freeHost:IsVisible(), freeHost and freeHost:GetFrameLevel(),
        "button", b and b:GetFrameLevel(), b and b:GetEffectiveScale(),
        "text", freeText and freeText:GetText(), freeText and freeText:IsVisible(),
        freeText and freeText:GetStringWidth(), freeText and freeText:GetAlpha()
end

local function dressBags(on)
    for _, b in ipairs(bagButtons()) do
        if on then
            if not bagHooked[b] and type(b.UpdateTextures) == "function" then
                bagHooked[b] = true
                hooksecurefunc(b, "UpdateTextures", dressBag)
            end
            dressBag(b)
            -- No drag off the band: a slot dragged by accident lifts the
            -- whole bag onto the cursor. Clicking still opens the bag and
            -- still drops a bag held on the cursor into the slot.
            pcall(b.RegisterForDrag, b)
        else
            pcall(b.RegisterForDrag, b, "LeftButton")
            if b.icon and b.SquareMask then pcall(b.icon.AddMaskTexture, b.icon, b.SquareMask) end
            if b.icon then pcall(b.icon.SetAlpha, b.icon, 1) end
            -- The client's pass adds a TOPLEFT point without clearing ours
            -- first; two points would override its size, so ours go.
            for _, tex in ipairs({ b:GetNormalTexture(), b:GetPushedTexture(), b:GetHighlightTexture() }) do
                if tex then pcall(tex.ClearAllPoints, tex) end
            end
            -- The client's own pass puts its art, size and anchor back.
            if type(b.UpdateTextures) == "function" then pcall(b.UpdateTextures, b) end
        end
    end
end

-- The page arrows: the 1.x sheets, 32 pixel squares with the arrow in the
-- middle. A client without them keeps its own atlases.
local ARROW_ART = {
    up   = { file = "Interface\\MainMenuBar\\UI-MainMenu-ScrollUpButton",
             atlas = "ui-hud-actionbar-pageuparrow" },
    down = { file = "Interface\\MainMenuBar\\UI-MainMenu-ScrollDownButton",
             atlas = "ui-hud-actionbar-pagedownarrow" },
}

local function dressArrow(button, arrow, on)
    if not button then return end
    local normal = button:GetNormalTexture()
    local classic = on and normal and normal:SetTexture(arrow.file .. "-Up") ~= false
    pcall(function()
        if classic then
            button:SetPushedTexture(arrow.file .. "-Down")
            button:SetDisabledTexture(arrow.file .. "-Disabled")
            button:SetHighlightTexture(arrow.file .. "-Highlight", "ADD")
        else
            button:SetNormalAtlas(arrow.atlas .. "-up")
            button:SetPushedAtlas(arrow.atlas .. "-down")
            button:SetDisabledAtlas(arrow.atlas .. "-disabled")
            button:SetHighlightAtlas(arrow.atlas .. "-mouseover")
        end
        if not on then
            button:SetSize(17, 14)
            button:SetHitRectInsets(0, 0, 0, 0)
        end
    end)
end

local function dress(on)
    local bar = _G.MainActionBar
    local pn = bar and bar.ActionBarPageNumber
    if pn then
        dressArrow(pn.UpButton, ARROW_ART.up, on)
        dressArrow(pn.DownButton, ARROW_ART.down, on)
    end
    dressBags(on)
    if not on then unskipMicro() end
end


-- What the band's other files take from here.
P.dress = dress
