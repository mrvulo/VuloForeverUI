-- VuloForeverUI / Modules / UnitFrames
--
-- Player and target frames in three styles. Standard keeps Blizzard's frames
-- and lays extras on them (UnitFramesExtras); Classic and Modern are our own
-- frames (UnitFramesEngine + UnitFramesSkins) and silence Blizzard's.
local _, ns = ...
local L = ns.L
local UF = ns.UF

local mod = ns:RegisterModule("unitframes", {
    name        = "Unit Frames",
    group       = "Unit Frames",
    description = "Player and target frames: Blizzard's own with extras, the Classic look, or a flat Modern look.",
    defaults = {
        enabled     = true,
        style       = "standard",
        classColor  = true,
        -- Both off by default on Blizzard's frames: the retail frame shows
        -- threat itself, and the class icon is a matter of taste.
        threat      = false,
        classIcon   = false,
        playerElite = true,
        classicClassColor = false,     -- Classic: Blizzard's green unless asked
        portrait    = true,
        player      = { x = -260, y = -180, scale = 1 },
        target      = { x =  260, y = -180, scale = 1 },
    },
})

local function needsReloadFrom(oldStyle)
    return oldStyle == "classic" or oldStyle == "modern"
end

-- Going back to Standard needs a reload: Blizzard's frames were silenced and
-- their events cannot be re-registered from here. Said before the switch,
-- not after it.
ns.OnLocaleReady(function()
StaticPopupDialogs["VFUI_UNITFRAMES_RELOAD"] = {
    text = L["Blizzard's frames come back after a reload. Reload the UI now?"],
    button1 = L["Reload now"],
    button2 = L["Later"],
    OnAccept = function() ReloadUI() end,
    timeout = 0, whileDead = 1, hideOnEscape = 1, preferredIndex = 3,
}
end)

local pendingApply = false

local function applyStyle(oldStyle)
    if ns:InCombat() then
        if not pendingApply then
            pendingApply = true
            ns:RegisterEventOnce("PLAYER_REGEN_ENABLED", function()
                pendingApply = false
                applyStyle(oldStyle)
            end)
        end
        return
    end
    local style = mod.db.style
    if style == "modern" then
        if UF.Extras  then UF.Extras.Disable() end
        if UF.Classic then UF.Classic.Disable() end
        UF.ActivateOwnFrames(mod)
    elseif style == "classic" then
        UF.DeactivateOwnFrames()
        if UF.Extras  then UF.Extras.Enable(mod) end
        if UF.Classic then UF.Classic.Enable(mod) end
    else
        UF.DeactivateOwnFrames()
        if UF.Classic then UF.Classic.Disable() end
        if UF.Extras  then UF.Extras.Enable(mod) end
    end
    if oldStyle and oldStyle ~= style and needsReloadFrom(oldStyle) then
        StaticPopup_Show("VFUI_UNITFRAMES_RELOAD")
    end
end

mod.ApplyStyle = applyStyle

function mod:OnEnable()
    -- PLAYER_ENTERING_WORLD: Blizzard's frames exist and have laid out by then,
    -- and it also covers a /reload.
    self:RegisterEvent("PLAYER_ENTERING_WORLD", function()
        applyStyle()
    end)
    if IsLoggedIn and IsLoggedIn() then applyStyle() end
end

function mod:OnDisable()
    local oldStyle = mod.db.style
    UF.DeactivateOwnFrames()
    if UF.Extras then UF.Extras.Disable() end
    if UF.Classic then UF.Classic.Disable() end
    if needsReloadFrom(oldStyle) then
        StaticPopup_Show("VFUI_UNITFRAMES_RELOAD")
    end
end

function mod:GetOptions()
    local items = {
        { type = "header", text = L["Style"] },
        { type = "dropdown", label = L["Frame style"], width = 240,
          values = {
              { value = "standard", text = L["Standard (Blizzard's frames plus extras)"] },
              { value = "classic",  text = L["Classic (original frame art)"] },
              { value = "modern",   text = L["Modern (flat house style)"] },
          },
          get = function() return mod.db.style end,
          set = function(_, v)
              if v == mod.db.style then return end
              local old = mod.db.style
              mod.db.style = v
              applyStyle(old)
              if ns.UI and ns.UI.BuildOptionsPage then ns.UI:BuildOptionsPage("unitframes") end
          end },
        { type = "desc", text = L["|cffaaaaaaClassic reskins Blizzard's frames; Modern is our own frame, moved with /vedit. Leaving Classic or Modern asks for a reload.|r"] },
        { type = "spacer", height = 8 },
    }

    if mod.db.style == "standard" then
        items[#items + 1] = { type = "header", text = L["Extras on Blizzard's frames"] }
        items[#items + 1] = { type = "toggle", label = L["Class color on the health bar"],
            get = function() return mod.db.classColor end,
            set = function(_, v) mod.db.classColor = v; applyStyle() end }
        items[#items + 1] = { type = "toggle", label = L["Threat display on the target frame"],
            get = function() return mod.db.threat end,
            set = function(_, v) mod.db.threat = v; applyStyle() end }
        items[#items + 1] = { type = "toggle", label = L["Class icon on the portrait"],
            get = function() return mod.db.classIcon end,
            set = function(_, v) mod.db.classIcon = v; applyStyle() end }
    elseif mod.db.style == "classic" then
        items[#items + 1] = { type = "header", text = L["Classic"] }
        items[#items + 1] = { type = "toggle", label = L["Elite dragon on the player frame"],
            get = function() return mod.db.playerElite end,
            set = function(_, v) mod.db.playerElite = v; applyStyle() end }
        items[#items + 1] = { type = "toggle", label = L["Class color on the health bar"],
            get = function() return mod.db.classicClassColor end,
            set = function(_, v) mod.db.classicClassColor = v; applyStyle() end }
        items[#items + 1] = { type = "desc", text = L["|cffaaaaaaClassic keeps Blizzard's frames underneath: target auras, the target cast bar and the pet frame stay, and Edit Mode moves them.|r"] }
    else
        items[#items + 1] = { type = "header", text = L["Modern"] }
        items[#items + 1] = { type = "toggle", label = L["Show portrait"],
            get = function() return mod.db.portrait end,
            set = function(_, v) mod.db.portrait = v; applyStyle() end }
    end

    if mod.db.style == "modern" then
        items[#items + 1] = { type = "spacer", height = 8 }
        items[#items + 1] = { type = "header", text = L["Size"] }
        for _, unit in ipairs({ "player", "target" }) do
            local key = unit
            items[#items + 1] = { type = "slider",
                label = unit == "player" and L["Player frame scale"] or L["Target frame scale"],
                min = 0.5, max = 2, step = 0.05,
                get = function() return mod.db[key].scale or 1 end,
                set = function(_, v)
                    mod.db[key].scale = v
                    local f = UF.Frames[key]
                    if f and f.mover then ns:MoverSetScale(f.mover, v) end
                end }
        end
        items[#items + 1] = { type = "button", label = L["Open Edit Mode"],
            onClick = function() ns:SetEditMode(true) end }
    end

    return items
end
