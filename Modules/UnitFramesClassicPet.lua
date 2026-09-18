-- VuloForeverUI / Modules / UnitFramesClassicPet
--
-- The pet frame in the Classic style: a port of the second reference's pet
-- skin. It is all one-time work -- PetFrameMixin:Update
-- (Mainline/PetFrame.lua:73) never touches the geometry again, and the mana
-- bar's fill, which Blizzard does put back on every power-type update, is
-- answered by the shared UnitFrameManaBar_UpdateType hook.
--
-- Every region here is a named global of Forever's Mainline/PetFrame.xml:
--   :11 PetFrame, :24 PetPortrait, :41 PetFrameTexture, :48 PetFrameFlash,
--   :53 PetAttackModeTexture, :66 PetHitIndicator, :73 PetName,
--   :84 PetFrameHealthBar (:97 PetFrameOverAbsorbGlow, :101/:106/:111 its
--   three texts, :119 PetFrameHealthBarMask), :133 PetFrameManaBar
--   (:140/:145/:150 its three texts, :158 PetFrameManaBarMask)
local _, ns = ...
local UF = ns.UF
local Classic = UF.Classic

local BAR = Classic.BAR
local isSetUp = false

local function setup()
    local pet = _G.PetFrame
    if not pet or isSetUp then return end
    isSetUp = true
    local G = _G

    Classic.Guard("pet.paint", function()
        G.PetFrameTexture:SetTexture("Interface\\TargetingFrame\\UI-SmallTargetingFrame")
        G.PetFrameFlash:SetTexture("Interface\\TargetingFrame\\UI-PartyFrame-Flash")
        G.PetFrameFlash:SetTexCoord(0, 1, 1, 0)
        G.PetFrameFlash:SetDrawLayer("BACKGROUND")
        G.PetFrameHealthBar:SetStatusBarTexture(BAR)
        G.PetFrameHealthBar:SetStatusBarColor(0, 1, 0)
        G.PetFrameOverAbsorbGlow:SetDrawLayer("ARTWORK", 7)
        G.PetAttackModeTexture:SetTexture("Interface\\TargetingFrame\\UI-Player-AttackStatus")
        G.PetAttackModeTexture:SetTexCoord(0.703125, 1, 0, 1)
    end)
    Classic.RegisterManaBar(G.PetFrameManaBar)

    Classic.Layout("pet.layout", function()
        pet:SetSize(128, 53)

        G.PetPortrait:ClearAllPoints()
        G.PetPortrait:SetPoint("TOPLEFT", 7, -6)

        G.PetName:SetWidth(0)
        G.PetName:ClearAllPoints()
        G.PetName:SetPoint("BOTTOMLEFT", 53, 33)

        G.PetFrameTexture:SetSize(128, 64)
        G.PetFrameTexture:ClearAllPoints()
        G.PetFrameTexture:SetPoint("TOPLEFT", 0, -2)

        G.PetFrameFlash:SetSize(128, 64)
        G.PetFrameFlash:SetPoint("TOPLEFT", -4, 11)

        G.PetFrameHealthBar:SetSize(69, 8)
        G.PetFrameHealthBar:ClearAllPoints()
        G.PetFrameHealthBar:SetPoint("TOPLEFT", 47, -22)
        G.PetFrameHealthBar:SetFrameLevel(1)
        if G.PetFrameHealthBarMask then G.PetFrameHealthBarMask:Hide() end

        G.PetFrameManaBar:SetSize(69, 8)
        G.PetFrameManaBar:ClearAllPoints()
        G.PetFrameManaBar:SetPoint("TOPLEFT", 47, -29)
        G.PetFrameManaBar:SetFrameLevel(1)
        if G.PetFrameManaBarMask then G.PetFrameManaBarMask:Hide() end

        -- The bars sit below the art now; their texts move onto the frame.
        local texts = {
            { "PetFrameHealthBarText",      "CENTER", 81,  -26 },
            { "PetFrameHealthBarTextLeft",  "LEFT",   47,  -26 },
            { "PetFrameHealthBarTextRight", "RIGHT",  114, -26 },
            { "PetFrameManaBarText",        "CENTER", 82,  -36 },
            { "PetFrameManaBarTextLeft",    "LEFT",   46,  -36 },
            { "PetFrameManaBarTextRight",   "RIGHT",  113, -36 },
        }
        for _, t in ipairs(texts) do
            local fs = G[t[1]]
            if fs then
                fs:SetParent(pet)
                fs:ClearAllPoints()
                fs:SetPoint(t[2], pet, "TOPLEFT", t[3], t[4])
            end
        end

        G.PetFrameOverAbsorbGlow:SetParent(pet)

        G.PetAttackModeTexture:SetSize(76, 64)
        G.PetAttackModeTexture:ClearAllPoints()
        G.PetAttackModeTexture:SetPoint("TOPLEFT", 6, -9)

        G.PetHitIndicator:ClearAllPoints()
        G.PetHitIndicator:SetPoint("CENTER", pet, "TOPLEFT", 28, -27)
    end)
end

Classic.RegisterPart({
    name = "pet",
    enable = setup,
})
