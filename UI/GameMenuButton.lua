-- VuloForeverUI / UI / GameMenuButton
--
-- A button for our settings window on the game menu (Escape), in the menu's
-- own red button style, in the list under "Macros".
--
-- It is NOT added through the menu's own AddButton. The list is rebuilt by
-- the menu's code on every open, from a button pool and counters on the
-- frame; AddButton from addon code writes into that pool and those counters,
-- the menu's layout reads them back while it is being shown, and from there
-- the whole show -- the UI panel manager included -- runs tainted.
--
-- So the button is ours, parented to the menu so it shows and hides with it,
-- and it carries no layoutIndex: the menu's layout never sees it. After each
-- layout pass (hooksecurefunc, which hands the caller back its own security)
-- it is set under Macros, and the buttons below are moved down one row and
-- the frame made one row taller. Only positions and sizes are written -- widget
-- calls, not fields in the menu's tables -- and the next layout pass starts
-- from its own numbers again.
local _, ns = ...

local button

-- The buttons the layout placed, in its order.
local function laidOut(menu)
    local out = {}
    for _, child in ipairs({ menu:GetChildren() }) do
        if child ~= button and child:IsShown() and type(child.layoutIndex) == "number" then
            out[#out + 1] = child
        end
    end
    table.sort(out, function(a, b) return a.layoutIndex < b.layoutIndex end)
    return out
end

local function place(menu)
    if not button then return end
    local list = laidOut(menu)
    local after
    for i, child in ipairs(list) do
        if child.GetText and child:GetText() == _G.MACROS then after = i end
    end
    -- No Macros button on this menu (a kiosk build, a trial): under the last
    -- button instead of the list is better than no button at all.
    if not after then
        button:ClearAllPoints()
        button:SetPoint("TOP", menu, "BOTTOM", 0, -10)
        return
    end

    local anchor = list[after]
    local spacing = type(menu.spacing) == "number" and menu.spacing or 0
    local step = button:GetHeight() + spacing
    button:ClearAllPoints()
    button:SetPoint("TOP", anchor, "BOTTOM", 0, -spacing)

    for i = after + 1, #list do
        local child = list[i]
        local point, rel, relPoint, x, y = child:GetPoint(1)
        if point and type(y) == "number" then
            child:ClearAllPoints()
            child:SetPoint(point, rel, relPoint, x, y - step)
        end
    end
    menu:SetHeight(menu:GetHeight() + step)
end

local function build()
    local menu = _G.GameMenuFrame
    if not menu or button then return end

    button = CreateFrame("Button", nil, menu, "MainMenuFrameButtonTemplate")
    button:SetText("VuloForeverUI")
    button:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION)
        HideUIPanel(menu)
        local main = ns.UI:CreateMainFrame()
        if not main:IsShown() then ns.UI:ToggleMainFrame() end
    end)
    ns.gameMenuButton = button

    hooksecurefunc(menu, "Layout", place)
    if menu:IsShown() then place(menu) end
end

if _G.GameMenuFrame then
    build()
else
    EventUtil.ContinueOnAddOnLoaded("Blizzard_GameMenu", build)
end
