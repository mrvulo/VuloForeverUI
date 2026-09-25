-- VuloForeverUI / Modules / Nameplates / AuraStyle
--
-- How one engine-made aura button looks, and the one question about auras we
-- are allowed to ask: can the player dispel at all.
--
-- The engine creates its own buttons and hands each one to us ONCE, in the
-- initialiser below. That callback is the only moment a button may be touched:
-- afterwards it belongs to the engine, and while auras are secret our writes
-- to it are refused. So everything -- regions, fonts, the formatter, mouse
-- behaviour -- happens here, and anything we need later is cached now.
--
-- Not one aura is read. The duration text is produced by a FORMATTER the client
-- runs against a time we never see.
local _, ns = ...
local NP = ns.NP

local Style = {}
NP.AuraStyle = Style

-- ---------------------------------------------------------------------------
-- Duration text. The client formats the remaining time itself; we only say in
-- which words. Seconds up to a minute, then "5m", then "2h", then "3d" --
-- Blizzard's own one-letter shape, which is what fits under a 24 px icon.
-- ---------------------------------------------------------------------------
-- Built once for the whole suite (ns.AuraDurationFormatter, Core/Utils): the
-- player's aura bars want the same wording under their icons.
function Style.Formatter()
    return ns.AuraDurationFormatter()
end

-- ---------------------------------------------------------------------------
-- Can the player take a buff off an enemy?
--
-- From the SPELLBOOK, which is plain data about us -- never from the aura,
-- whose dispel type we may not look at. The answer is a property of the player,
-- so it decides whether the dispel GROUP exists at all; the engine then matches
-- the auras to it in C.
-- ---------------------------------------------------------------------------
local MAGIC_SPELLS = {
    370, 8012,                          -- Purge
    527, 988,                           -- Dispel Magic
}
local MAGIC_PET_SPELLS = { 19505, 19731, 19734, 19736 }   -- Devour Magic
local ENRAGE_SPELLS = {
    19801,                              -- Tranquilizing Shot
    2908, 8955, 9901,                   -- Soothe Animal
}

local function knows(ids, bank)
    for _, id in ipairs(ids) do
        local ok, res
        if bank then ok, res = pcall(C_SpellBook.IsSpellKnownOrInSpellBook, id, bank)
        else ok, res = pcall(C_SpellBook.IsSpellKnownOrInSpellBook, id) end
        if ok and res == true then return true end
    end
    return false
end

local canMagic, canEnrage = false, false

function Style.RefreshDispel()
    local pet = Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Pet
    canMagic = knows(MAGIC_SPELLS) or (pet and knows(MAGIC_PET_SPELLS, pet)) or false
    canEnrage = knows(ENRAGE_SPELLS)
end

function Style.CanDispelMagic() return canMagic end
function Style.CanDispelEnrage() return canEnrage end

-- ---------------------------------------------------------------------------
-- The initialiser
--
-- One per kind, built once and handed to AddAuraGroup. The engine calls it with
-- a freshly created button; by then the style must already be decided, so the
-- current settings are captured when the container is built and a style change
-- rebuilds the containers rather than reaching into live buttons.
-- ---------------------------------------------------------------------------
local function styleOf(kind)
    local db = NP.db()
    local a = db.auras[kind]
    local t = db.auraText
    return a, t.duration, t.stacks, db
end

local ANCHORS = {
    topleft     = { "TOPLEFT",     1,  -1 },
    topright    = { "TOPRIGHT",   -1,  -1 },
    bottomleft  = { "BOTTOMLEFT",  1,   1 },
    bottomright = { "BOTTOMRIGHT", -1,  1 },
    centre      = { "CENTER",      0,   0 },
}

local function placeText(fs, cfg, button)
    local a = ANCHORS[cfg.position] or ANCHORS.topleft
    fs:ClearAllPoints()
    fs:SetPoint(a[1], button, a[1], a[2] + cfg.x, a[3] + cfg.y)
end

-- One kind's border: its size (0 when switched off) and colour. The preview
-- asks the same function, so it draws what the plates will.
function Style.Border(a)
    if a.hideBorder then return 0, nil end
    local size = tonumber(a.borderSize) or 1
    local c = a.borderColor
    if type(c) ~= "table" then c = { r = 0, g = 0, b = 0 } end
    return math.max(0, size), c
end

-- Every engine call is wrapped: a refusal must cost us that one feature, not
-- the whole batch of buttons the engine is building.
local function register(button, method, ...)
    local f = button[method]
    if not f then return false end
    return (pcall(f, button, ...))
end

function Style.Initializer(kind, size)
    return function(button)
        local a, durCfg, stackCfg = styleOf(kind)
        local font = ns.ModuleFontPath("nameplates")

        -- The AuraButton intrinsic carries no size of its own, and the flow
        -- layout only ANCHORS its elements -- layout.elementWidth is used for
        -- the spacing arithmetic and never reaches the frame. Without this the
        -- button stays 0x0 and nothing is ever visible, while every call
        -- involved reports success.
        button:SetSize(size, size)

        local icon = button:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints(button)
        local crop = a.crop and (a.cropPct / 100) or 0
        icon:SetTexCoord(crop, 1 - crop, crop, 1 - crop)

        local cd = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
        cd:SetAllPoints(button)
        cd:SetReverse(true)
        cd:SetHideCountdownNumbers(true)

        local bSize, bc = Style.Border(a)
        if bSize > 0 and bc then
            local edges = ns.MakeEdges(button, "OVERLAY")
            ns.LayoutEdges(edges, button, bSize, bc.r, bc.g, bc.b, bc.a or 1)
        end

        -- Fonts BEFORE the engine is told about the strings: an unstyled
        -- FontString has no font assigned and the engine errors on it.
        local stacks = button:CreateFontString(nil, "OVERLAY")
        stacks:SetFont(font, stackCfg.size, "OUTLINE")
        stacks:SetTextColor(stackCfg.color.r, stackCfg.color.g, stackCfg.color.b)
        placeText(stacks, stackCfg, button)

        local duration = button:CreateFontString(nil, "OVERLAY")
        duration:SetFont(font, durCfg.size, "OUTLINE")
        duration:SetTextColor(durCfg.color.r, durCfg.color.g, durCfg.color.b)
        placeText(duration, durCfg, button)

        register(button, "SetIcon", icon)
        register(button, "SetDurationCooldown", cd)
        if stackCfg.position ~= "none" then
            register(button, "SetApplicationCount", stacks, {})
        end

        if durCfg.position ~= "none" then
            local f = Style.Formatter()
            if not (f and register(button, "SetDurationText", duration, { textFormatter = f })) then
                -- no formatter on this client: better no text than a wrong one
                register(button, "SetDurationText", duration, {})
            end
        end

        -- Engine buttons take mouse clicks and swallow the one meant for the
        -- plate behind them. Both calls are refused on a restricted button, and
        -- this callback is the one moment when it is not restricted yet.
        pcall(button.SetMouseClickEnabled, button, false)
        pcall(button.EnableMouse, button, false)
    end
end
