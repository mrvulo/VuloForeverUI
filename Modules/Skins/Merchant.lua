-- VuloForeverUI / Modules / Skins / Merchant
--
-- The merchant window: what you already have -- a recipe you know, a mount,
-- pet or toy you own -- is drawn red, the way the client draws what you
-- cannot use.
--
-- "Already have" is the client's own answer, not a lookup by item type: the
-- item's merchant tooltip carries the line ITEM_SPELL_KNOWN ("Already
-- known"), or the pet line ITEM_PET_KNOWN with a count above zero.
--
-- TAINT (docs/concepts.md, engine rules): the cells are the client's. Only
-- vertex colours are set on them, after the client's own update (a
-- post-hook). No field is written, no cell is hidden or moved, and the
-- client's update is never called from here: it writes price and link on
-- the buttons, and a purchase reads them.
local _, ns = ...

local Skins = ns.Skins
local Merchant = {}
Skins.Merchant = Merchant
table.insert(Skins.parts, Merchant)

local CELLS = 10            -- MERCHANT_ITEMS_PER_PAGE
local tinted = {}           -- cell number -> true while its red is ours

local function wanted()
    return Skins.mod.active and Skins.db().merchantOwned == true
end

-- "Collected (%d/%d)" as a pattern that captures the first number.
local petPattern
local function petCount(text)
    if petPattern == nil then
        local fmt = _G.ITEM_PET_KNOWN
        petPattern = type(fmt) == "string"
            and ("^" .. fmt:gsub("([%%%(%)%.%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%%%d", "(%%d+)")) or false
    end
    return petPattern and tonumber((text:match(petPattern))) or 0
end

local function owned(index)
    local data = C_TooltipInfo.GetMerchantItem(index)
    if type(data) ~= "table" or not ns.CanRead(data) or type(data.lines) ~= "table" then return false end
    local known = _G.ITEM_SPELL_KNOWN
    for _, line in ipairs(data.lines) do
        local text = line.leftText
        if type(text) == "string" and ns.CanRead(text) then
            if text == known or petCount(text) > 0 then return true end
        end
    end
    return false
end

local function colour(i, nr, ng, nb, sr, sg, sb, ir, ig, ib)
    local cell, button = _G["MerchantItem" .. i], _G["MerchantItem" .. i .. "ItemButton"]
    if not (cell and button) then return end
    SetItemButtonNameFrameVertexColor(cell, nr, ng, nb)
    SetItemButtonSlotVertexColor(cell, sr, sg, sb)
    SetItemButtonTextureVertexColor(button, ir, ig, ib)
    SetItemButtonNormalTextureVertexColor(button, ir, ig, ib)
end

-- The item a cell shows, or nil for an empty one.
local function indexOf(i)
    local button = _G["MerchantItem" .. i .. "ItemButton"]
    if not (button and button:IsShown()) then return nil end
    local index = button:GetID()
    if type(index) == "number" and index >= 1 and index <= GetMerchantNumItems() then return index end
end

-- After the client has drawn the page: red over what you already have.
local function paint()
    if not wanted() then return end
    wipe(tinted)
    if MerchantFrame.selectedTab ~= 1 then return end      -- buyback draws its own
    for i = 1, CELLS do
        local index = indexOf(i)
        if index and owned(index) then
            colour(i, 1, 0, 0, 1, 0, 0, 0.9, 0, 0)
            tinted[i] = true
        end
    end
end

-- Switched off while the window is open: every cell of ours gets the colour
-- the client gives it (MerchantFrame_UpdateMerchantInfo, the four cases).
local function restore()
    if MerchantFrame.selectedTab == 1 then
        for i in pairs(tinted) do
            local index = indexOf(i)
            local info = index and C_MerchantFrame.GetItemInfo(index)
            if type(info) == "table" then
                local red = not info.isPurchasable or not info.isUsable
                if info.numAvailable == 0 then
                    local c = red and 0 or 0.5
                    colour(i, 0.5, c, c, 0.5, c, c, 0.5, c, c)
                elseif red then
                    colour(i, 1, 0, 0, 1, 0, 0, 0.9, 0, 0)
                else
                    colour(i, 0.5, 0.5, 0.5, 1, 1, 1, 1, 1, 1)
                end
            end
        end
    end
    wipe(tinted)
end

local hooked
function Merchant.Apply()
    local frame = _G.MerchantFrame
    if not frame then return end
    if wanted() and not hooked and type(_G.MerchantFrame_UpdateMerchantInfo) == "function" then
        hooked = true
        hooksecurefunc("MerchantFrame_UpdateMerchantInfo", paint)
    end
    if not frame:IsShown() then wipe(tinted); return end
    if wanted() then paint() else restore() end
end

function Merchant.Enable(mod)
    -- A tooltip the client had not loaded yet says nothing about "known";
    -- when the item arrives the page is looked at again, once per frame.
    local queued
    mod:RegisterEvent("GET_ITEM_INFO_RECEIVED", function()
        if queued or not hooked or not wanted() then return end
        local frame = _G.MerchantFrame
        if not (frame and frame:IsShown()) then return end
        queued = true
        ns.NextFrame(function()
            queued = false
            if frame:IsShown() then paint() end
        end)
    end)
end
