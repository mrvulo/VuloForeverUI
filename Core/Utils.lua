-- General helpers used by multiple modules.
local _, ns = ...

-- The format string is almost always a translated L[...]. A translation that
-- drops or reorders a %s would otherwise throw INSIDE the function the addon
-- uses to report errors -- including the event dispatcher's own reporter.
-- Falling back to the unformatted text keeps the message readable and visible.
local function safeFormat(msg, ...)
    if select("#", ...) == 0 then return msg end
    local ok, out = pcall(string.format, msg, ...)
    return ok and out or (tostring(msg) .. " |cffff5555[format?]|r")
end

function ns:Print(msg, ...)
    DEFAULT_CHAT_FRAME:AddMessage(ns.PREFIX .. ": " .. tostring(safeFormat(msg, ...)))
end

function ns:Debug(msg, ...)
    if not (ns.db and ns.db.global) or not ns.db.global.debug then return end
    DEFAULT_CHAT_FRAME:AddMessage("|cff888888[VFUI debug]|r " .. tostring(safeFormat(msg, ...)))
end

function ns:InCombat()
    return InCombatLockdown and InCombatLockdown()
end

-- "Do this once the current frame has finished." Thirteen byte-identical copies
-- of the same guarded call, because C_Timer is missing on the oldest clients we
-- still load on -- there the work simply happens inline, which is what those
-- copies did too.
function ns.NextFrame(fn)
    if C_Timer and C_Timer.After then C_Timer.After(0, fn) else fn() end
end

-- Newer clients expose a StaticPopup's box as .EditBox, older ones as .editBox,
-- and the oldest only under the global <popupName>EditBox. Thirteen copies of
-- this line had drifted apart: nine of them concatenated self:GetName() with no
-- guard, which errors outright on a nameless popup.
function ns.PopupEditBox(popup)
    if not popup then return nil end
    return popup.EditBox or popup.editBox
        or (popup.GetName and _G[(popup:GetName() or "") .. "EditBox"])
end

-- 1 physical pixel == (768 / physicalScreenHeight) coord units at scale 1.0, divided by the frame's effective scale.
function ns:Pixel(frame, n)
    local _, physH = GetPhysicalScreenSize()
    if not physH or physH <= 0 then physH = 1080 end
    -- The scale of a frame inside a restricted tree (a nameplate) can come back
    -- secret; ns.Num is defined later in the load order but only called here.
    local es = frame and frame.GetEffectiveScale and frame:GetEffectiveScale()
    es = ns.Num and ns.Num(es, nil) or (type(es) == "number" and es) or 1
    if es <= 0 then es = 1 end
    return (n or 1) * (768 / physH) / es
end

function ns:PixelSnap(value, frame)
    local px = ns:Pixel(frame, 1)
    if px <= 0 then return value end
    return math.floor(value / px + 0.5) * px
end

-- Duration text on an engine-made aura button: the client formats the time
-- itself, we only say in which words. Seconds up to a minute, then "5m", "2h",
-- "3d" -- Blizzard's own one-letter shape, which is what fits under an icon.
-- Shared, because every aura display in the suite wants the same wording.
local durationFormatter

function ns.AuraDurationFormatter()
    if durationFormatter ~= nil then return durationFormatter or nil end
    durationFormatter = false
    local util = C_StringUtil
    if not (util and util.CreateNumericRuleFormatter) then return nil end
    local ok, f = pcall(util.CreateNumericRuleFormatter)
    if not ok or not f then return nil end
    local Up = Enum.NumericRuleFormatRounding and Enum.NumericRuleFormatRounding.Up
    -- rounding sits on the COMPONENT: on the breakpoint it would only round
    -- `step`, which is not set, and 91 s would read "2m".
    local okSet = pcall(f.SetBreakpoints, f, {
        { threshold = 0,     format = "%d" },
        { threshold = 60,    format = "%dm", components = { { div = 60, rounding = Up } } },
        { threshold = 3600,  format = "%dh", components = { { div = 3600, rounding = Up } } },
        { threshold = 86400, format = "%dd", components = { { div = 86400, rounding = Up } } },
    })
    if not okSet then return nil end
    durationFormatter = f
    return f
end

-- Four one-pixel edge textures, not a filled quad: outlines an icon or bar
-- without washing it out. Shared by nameplates, the power bar and the arena
-- aura ring, which each hand-rolled the same four textures before.
function ns.MakeEdges(parent, layer)
    local e = {}
    for _, side in ipairs({ "top", "bot", "lft", "rgt" }) do
        local t = parent:CreateTexture(nil, layer or "OVERLAY")
        t:SetColorTexture(0, 0, 0, 1)
        e[side] = t
    end
    return e
end

-- Border of n physical pixels around anchor, offset pad outward; n <= 0 hides it.
function ns.LayoutEdges(edges, anchor, n, r, g, b, a, pad)
    if not edges then return end
    if n <= 0 then for _, t in pairs(edges) do t:Hide() end; return end
    local th  = ns:Pixel(anchor, n)
    local off = ns:Pixel(anchor, pad or 0)
    local top, bot, lft, rgt = edges.top, edges.bot, edges.lft, edges.rgt
    for _, t in pairs(edges) do t:SetColorTexture(r, g, b, a or 1); t:Show() end
    top:ClearAllPoints(); top:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", -th - off, off); top:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", th + off, off); top:SetHeight(th)
    bot:ClearAllPoints(); bot:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", -th - off, -off); bot:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", th + off, -off); bot:SetHeight(th)
    lft:ClearAllPoints(); lft:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -off, off); lft:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMLEFT", -off, -off); lft:SetWidth(th)
    rgt:ClearAllPoints(); rgt:SetPoint("TOPLEFT", anchor, "TOPRIGHT", off, off); rgt:SetPoint("BOTTOMLEFT", anchor, "BOTTOMRIGHT", off, -off); rgt:SetWidth(th)
end

-- Snap a CENTER offset so the frame's leading EDGE lands on the physical pixel
-- grid. Going through the edge rather than the centre keeps odd-width frames on
-- their half pixel automatically — snapping the centre itself rounds that .5
-- away and the frame creeps a pixel on every save/reload cycle.
function ns:PixelSnapCenter(value, dim, frame)
    local px = ns:Pixel(frame, 1)
    if px <= 0 then return value end
    local half = (dim or 0) / 2
    return math.floor((value - half) / px + 0.5) * px + half
end

-- Blizzard reads UIPanelWindows from inside its own secure panel code, so
-- replacing an entry from Lua taints that whole system. The visible symptom is
-- not being able to open the character sheet or the spellbook while in combat.
-- SetUIPanelAttribute is the sanctioned route and keeps the taint off the
-- shared table. Returns false when the client has no such API, in which case
-- the caller must leave the panel alone rather than fall back to the raw write.
function ns:SetPanelLayout(frame, attrs)
    if not (frame and type(attrs) == "table") then return false end
    if type(_G.SetUIPanelAttribute) ~= "function" then return false end
    for k, v in pairs(attrs) do
        pcall(_G.SetUIPanelAttribute, frame, k, v)
    end
    return true
end

-- Class icons come out of Blizzard's character-creation atlas, so there is no
-- art to ship and no client restart to wait for. The coordinates are cut for
-- exactly that texture; any other class-icon sheet uses a different grid.
local CLASS_ICON_TEXTURE = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes"
local CLASS_ICON_FALLBACK = {
    WARRIOR     = { 0,    0.25, 0,    0.25 },
    MAGE        = { 0.25, 0.49, 0,    0.25 },
    ROGUE       = { 0.49, 0.73, 0,    0.25 },
    DRUID       = { 0.73, 0.97, 0,    0.25 },
    HUNTER      = { 0,    0.25, 0.25, 0.5  },
    SHAMAN      = { 0.25, 0.49, 0.25, 0.5  },
    PRIEST      = { 0.49, 0.73, 0.25, 0.5  },
    WARLOCK     = { 0.73, 0.97, 0.25, 0.5  },
    PALADIN     = { 0,    0.25, 0.5,  0.75 },
    DEATHKNIGHT = { 0.25, 0.49, 0.5,  0.75 },
}

-- Returns texture, {left, right, top, bottom} — or nil for an unknown class.
function ns:GetClassIcon(classToken)
    if not classToken then return nil end
    local token = classToken:upper()
    local coords = (_G.CLASS_ICON_TCOORDS and _G.CLASS_ICON_TCOORDS[token])
        or CLASS_ICON_FALLBACK[token]
    if not coords then return nil end
    return CLASS_ICON_TEXTURE, coords
end

-- Our own class sheets under Media/ClassSheets. A DIFFERENT grid from Blizzard's
-- atlas above: 8x8 cells, so the coordinates are not interchangeable.
-- These sheets ship with the addon and carry their licence next to them:
-- two are game-icons.net glyphs under CC BY 3.0, one is the author's own work.
-- Nothing here needs a licence we do not have, which is the whole point --
-- art that did was kept out of the repo entirely rather than gitignored, so
-- there is no longer a folder anyone could accidentally reference.
ns.CLASS_SHEET_PATH   = "Interface\\AddOns\\VuloForeverUI\\Media\\ClassSheets\\"
ns.CLASS_SHEET_COORDS = {
    WARRIOR     = { 0,     0.125, 0,     0.125 },
    MAGE        = { 0.125, 0.25,  0,     0.125 },
    ROGUE       = { 0.25,  0.375, 0,     0.125 },
    DRUID       = { 0.375, 0.5,   0,     0.125 },
    EVOKER      = { 0.5,   0.625, 0,     0.125 },
    HUNTER      = { 0,     0.125, 0.125, 0.25  },
    SHAMAN      = { 0.125, 0.25,  0.125, 0.25  },
    PRIEST      = { 0.25,  0.375, 0.125, 0.25  },
    WARLOCK     = { 0.375, 0.5,   0.125, 0.25  },
    PALADIN     = { 0,     0.125, 0.25,  0.375 },
    DEATHKNIGHT = { 0.125, 0.25,  0.25,  0.375 },
    MONK        = { 0.25,  0.375, 0.25,  0.375 },
    DEMONHUNTER = { 0.375, 0.5,   0.25,  0.375 },
}

-- The nicer class art used by the friends list. Falls back to Blizzard's atlas
-- when the sheet is not on disk, so a stripped install still shows an icon
-- rather than a blank square.
function ns:GetVuloClassIcon(classToken, sheet)
    if not classToken then return ns:GetClassIcon(classToken) end
    local token  = classToken:upper()
    local coords = ns.CLASS_SHEET_COORDS[token]
    if not coords then return ns:GetClassIcon(classToken) end

    local path = ns.CLASS_SHEET_PATH .. (sheet or "vuloepic") .. ".tga"
    if _G.GetFileIDFromPath and not _G.GetFileIDFromPath(path) then
        return ns:GetClassIcon(classToken)
    end
    return path, coords
end

function ns:DeepCopy(t)
    if type(t) ~= "table" then return t end
    local copy = {}
    for k, v in pairs(t) do
        copy[k] = ns:DeepCopy(v)
    end
    return copy
end

function ns:ApplyDefaults(target, defaults)
    if type(target) ~= "table" then target = {} end
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            -- never clobber a saved scalar with a fresh table (drops the user's value)
            if target[k] == nil or type(target[k]) == "table" then
                target[k] = ns:ApplyDefaults(target[k], v)
            end
        elseif target[k] == nil then
            target[k] = v
        end
    end
    return target
end

function ns:SafeGetFontString(bar, suffix)
    if not bar or not bar.GetName then return nil end
    local n = bar:GetName()
    if not n or n == "" then return nil end
    return _G[n .. suffix]
end

function ns:ApplyFontSize(fs, size)
    if not fs or not fs.GetFont or not fs.SetFont then return end
    local font, cur, flags = fs:GetFont()
    -- Skip when the size already matches: this sits behind a hook that fires
    -- on every health/power text tick, and SetFont is not a cheap setter --
    -- it re-lays-out the string. Epsilon, not equality: GetFont answers with
    -- values like 9.999999 for a size that was set as 10.
    if font and not (cur and cur > size - 0.05 and cur < size + 0.05) then
        fs:SetFont(font, size, flags)
    end
end

function ns:SetBarTextFontSize(bar, size)
    if not bar then return end
    local center = bar.TextString or ns:SafeGetFontString(bar, "Text")
    local left   = bar.LeftText   or ns:SafeGetFontString(bar, "TextLeft")
    local right  = bar.RightText  or ns:SafeGetFontString(bar, "TextRight")
    ns:ApplyFontSize(center, size)
    ns:ApplyFontSize(left, size)
    ns:ApplyFontSize(right, size)
end
