-- VuloForeverUI / Modules / ActionBars / ClassicBarApply: laying and handing back the band, the watch that keeps it laid, and the report
local _, ns = ...
local AB = ns.AB
local Classic = AB.ClassicBar
local P = AB._classic

local ART_W, TEX, original, restoreFrame, ratio = P.ART_W, P.TEX, P.original, P.restoreFrame, P.ratio
local placed, build, paint, placeRow = P.placed, P.build, P.paint, P.placeRow
local laid, layoutButtons, layoutPageArrows, layoutBags = P.laid, P.layoutButtons, P.layoutPageArrows, P.layoutBags
local layoutMicro, XP_CONTAINERS, placeExperience, layoutExperience = P.layoutMicro, P.XP_CONTAINERS, P.placeExperience, P.layoutExperience
local restoreExperience, hookExperience, hookBags, hideModernArt = P.restoreExperience, P.hookExperience, P.hookBags, P.hideModernArt
local dress = P.dress

-- Forward: the watch is written after the layout it calls, and Apply installs
-- it before that.
local watch

-- ---------------------------------------------------------------- pass --

-- Is the client's own Edit Mode open? While it is, it owns these frames.
local function editModeOpen()
    local f = _G.EditModeManagerFrame
    return f and f.IsShown and f:IsShown() and true or false
end

-- The client's own edit mode: the band hands everything back while it is open
-- (it moves these same frames) and lays them again the moment it closes.
local editHooked = false

local function hookEditMode()
    if editHooked or not (EventRegistry and EventRegistry.RegisterCallback) then return end
    editHooked = true
    EventRegistry:RegisterCallback("EditMode.Enter", function()
        if P.applied then Classic.Restore() end
    end, "VuloForeverUI_ClassicBarEnter")
    EventRegistry:RegisterCallback("EditMode.Exit", function()
        if AB.mod.active then AB.Apply() end
    end, "VuloForeverUI_ClassicBarExit")
end

function Classic.Apply()
    hookEditMode()
    if InCombatLockdown() then return false end
    if editModeOpen() then
        Classic.Restore()
        return false
    end
    build()
    if not paint() then
        P.art:Hide()
        return false
    end

    -- Out of combat only (checked above): the client's secure buttons hang
    -- from the band, and its scale moves them.
    P.art:SetScale(P.bandScale())
    P.art:Show()
    if not P.art.watching then
        P.art.watching = true
        P.art:SetScript("OnUpdate", watch)
    end
    -- The band at its chosen place, or on the bottom edge's centre.
    placeRow(P.art, "band", "BOTTOM", UIParent, "BOTTOM", 0, 0)
    hideModernArt(true)
    layoutButtons()
    layoutPageArrows()
    layoutMicro(layoutBags())
    hookExperience()
    hookBags()
    placeExperience()
    layoutExperience()
    P.applied = true
    -- After the flag: the bag hook dresses only while the band is applied.
    dress(true)
    return true
end

-- A new UI scale or window size changes how much room the screen has, and
-- with it the cap on the band's size (bandScale): lay it out again.
local resized = CreateFrame("Frame")
resized:RegisterEvent("UI_SCALE_CHANGED")
resized:RegisterEvent("DISPLAY_SIZE_CHANGED")
resized:SetScript("OnEvent", function()
    if P.applied and AB.mod.active and not InCombatLockdown() then AB.Apply() end
end)

function Classic.Restore()
    if not P.applied then
        if P.art then P.art:Hide() end
        return
    end
    if InCombatLockdown() then return end
    P.applied = false

    if P.art then P.art:Hide() end
    hideModernArt(false)
    dress(false)
    restoreExperience()
    local pn = _G.MainActionBar and _G.MainActionBar.ActionBarPageNumber
    if pn and P.pageWasShown == false then pcall(pn.Hide, pn) end
    P.pageWasShown = nil
    for frame in pairs(original) do
        restoreFrame(frame)
    end
    -- Not asking the client to lay its bars out again: UpdateGridLayout only
    -- runs when its cached settings changed, which they did not, and when it
    -- does run it writes fields on a secure bar from our code. The snapshot
    -- above already put every container, bar and size back where it was.
end

-- ---------------------------------------------------------------- watch --
--
-- The client lays its own bar out again whenever almost anything happens --
-- a setting, a page, a form, Edit Mode closing -- and every one of those puts
-- the containers back where IT wants them. There is no single function to
-- hook for it, so the band simply checks, twice a second, that its row is
-- still its row, and lays it again when it is not.
local WATCH_EVERY = 0.5

function watch(self, elapsed)
    -- The experience bar every frame, and in a fight too: it is not protected,
    -- and a half second of the client's own bar is exactly the flicker seen.
    if P.applied then
        for _, name in ipairs(XP_CONTAINERS) do
            local c = _G[name]
            if c and c:IsShown() then
                -- Its place, its width, and the width of the bars inside: the
                -- client resets the last two on its own after a loading
                -- screen, with the anchor left where the band put it.
                local ok, _, rel = pcall(c.GetPoint, c, 1)
                local w = c:GetWidth() or 0
                local stale = (ok and rel ~= placed[c]) or math.abs(w * ratio(c) - (ART_W - 4)) > 1
                local bars = not stale and c.bars
                if type(bars) == "table" then
                    for _, child in pairs(bars) do
                        if child:IsShown() and (child:GetWidth() or 0) > w + 1 then stale = true break end
                    end
                end
                if stale then layoutExperience() break end
            end
        end
    end
    self.wait = (self.wait or 0) + elapsed
    if self.wait < WATCH_EVERY then return end
    self.wait = 0
    if not P.applied or InCombatLockdown() or not AB.mod.active then return end
    -- One comparison per bar is enough: if its first container is no longer
    -- sitting on our row, the client has been through here.
    local function moved(bar, rowIndex)
        local first = bar and bar:IsShown() and bar.actionButtons and bar.actionButtons[1]
        local container = first and first.container
        local row = P.art and P.art.rows and P.art.rows[rowIndex]
        if not (container and row) then return false end
        local ok, _, rel = pcall(container.GetPoint, container, 1)
        return ok and rel ~= row
    end
    local bar = _G.MainActionBar
    if not bar then return end
    local okBar, _, barRel = pcall(bar.GetPoint, bar, 1)
    local stale = moved(bar, 1) or (okBar and barRel ~= (P.art.rows and P.art.rows[1]))
    for laidBar, rowIndex in pairs(laid) do
        stale = stale or moved(laidBar, rowIndex)
    end
    if not stale then
        for frame in pairs(placed) do
            if frame:IsShown() then
                local ok, _, rel = pcall(frame.GetPoint, frame, 1)
                if ok and rel ~= placed[frame] then stale = true break end
            end
        end
    end
    if stale then Classic.Apply() end
end

function Classic.IsApplied() return P.applied end

-- ---------------------------------------------------------------- report --
--
-- What the client actually answers, printed on demand.
--
-- This exists because the alternative is guessing from screenshots. The three
-- things that decide whether the Classic bar can work at all -- does the old
-- art still ship, what scale is each piece wearing, and does the client re-lay
-- out its own bar after we have -- are all questions only the client can
-- answer, and none of them shows up in a picture.
function Classic.Report()
    local A, R = ns.C.accent, ns.C.r
    ns:Print(A .. "Classic bar" .. R)

    local probe = UIParent:CreateTexture()
    for key, path in pairs(TEX) do
        local ok = probe:SetTexture(path)
        ns:Print("  art %s: %s", key, (ok == false) and (ns.C.neg .. "missing" .. R) or "ok")
    end
    probe:SetTexture(nil)

    local function scaleOf(frame)
        if not frame then return "-" end
        return ("%.3f"):format(frame:GetEffectiveScale() or 0)
    end
    ns:Print("  scale  UIParent %s, MainActionBar %s, ActionButton1 %s, band %s",
        scaleOf(UIParent), scaleOf(_G.MainActionBar), scaleOf(_G.ActionButton1), scaleOf(P.art))

    local b = _G.ActionButton1
    if b then
        local w, h = b:GetWidth(), b:GetHeight()
        ns:Print("  ActionButton1 size %.1f x %.1f, points %d",
            w or 0, h or 0, b:GetNumPoints() or 0)
        local point, rel, relPoint, x, y = b:GetPoint(1)
        if ns.CanRead(point) then
            ns:Print("    1: %s of %s %s at %.1f, %.1f", tostring(point),
                (rel and rel.GetName and rel:GetName()) or "?", tostring(relPoint), x or 0, y or 0)
        end
    end
    local b2 = _G.ActionButton2
    if b and b2 then
        local x1, x2 = b:GetLeft(), b2:GetLeft()
        if x1 and x2 then ns:Print("  pitch on screen: %.1f", x2 - x1) end
    end

    -- The slot art of a filled and an empty button, and the bar's own art:
    -- which of them is on, at what alpha, wearing which atlas.
    local function texLine(label, tex)
        if not tex then ns:Print("    %s: none", label) return end
        local layer, sub = tex:GetDrawLayer()
        ns:Print("    %s: %s, alpha %.2f, %s %s, %s", label,
            tex:IsShown() and "shown" or (ns.C.neg .. "hidden" .. R), tex:GetAlpha() or 0,
            tostring(layer), tostring(sub),
            tostring(tex.GetAtlas and tex:GetAtlas() or tex:GetTexture()))
    end
    for _, name in ipairs({ "ActionButton1", "ActionButton4" }) do
        local btn = _G[name]
        if btn then
            ns:Print("  %s (bar art %s)", name,
                (btn.bar and btn.bar.hideBarArt) and "hidden" or "on")
            texLine("SlotArt", btn.SlotArt)
            texLine("SlotBackground", btn.SlotBackground)
            texLine("Normal", btn:GetNormalTexture())
        end
    end
    for _, name in ipairs({ "MainActionBar" }) do
        local frame = _G[name]
        if frame then
            ns:Print("  %s regions", name)
            for i, region in ipairs({ frame:GetRegions() }) do
                if region:GetObjectType() == "Texture" then texLine("#" .. i, region) end
            end
            for key, child in pairs(frame) do
                if type(key) == "string" and key:find("Art") and type(child) == "table"
                    and child.GetObjectType then
                    ns:Print("    child %s: %s, alpha %.2f", key,
                        child:IsShown() and "shown" or "hidden", child:GetAlpha() or 0)
                end
            end
        end
    end

    -- Which of the client's own layout calls exist. One of these putting the
    -- buttons back is the likeliest reason a row we placed does not stay
    -- placed, and the fix is a hook on whichever one is really there.
    local bar = _G.MainActionBar
    if bar then
        local found = {}
        for _, name in ipairs({ "UpdateGridLayout", "UpdateShownButtons", "Layout",
            "ApplySystemAnchor", "UpdateSystemSettingIconSize", "MarkDirty" }) do
            if type(bar[name]) == "function" then found[#found + 1] = name end
        end
        ns:Print("  MainActionBar methods: %s", (#found > 0) and table.concat(found, ", ") or "none of the usual")
    end
end
