-- VuloForeverUI / Modules / Classes / Core
--
-- One page per class, each a tab of its own. A class file registers itself
-- with CL.Register(token, def) and runs only on a character of that class;
-- every tab is shown on every character, so a class can be set up from any
-- of them.
--
--   def = {
--       tab     = "priest",        tab id, also the key of its settings
--       label   = "Priest",        tab label (an English locale key)
--       Enable  = function() end,  the character is of this class, module on
--       Disable = function() end,
--       Apply   = function() end,  a setting changed
--       Options = function(rows) return { ... } end,
--   }
--
--   Core.lua    module, tabs, the switch between classes
--   Priest.lua  shield arc and Inner Fire arc
local _, ns = ...
local L = ns.L

local CL = { classes = {}, byTab = {} }
ns.Classes = CL

local mod = ns:RegisterModule("classes", {
    name        = "Classes",
    group       = "Unit Frames",
    description = "Displays for one class each: what the client shows nowhere else, drawn where you look in a fight.",
    defaults = {
        enabled = true,
        priest = {
            shield         = true,    -- the arc right of the character
            shieldNumber   = true,
            shieldTime     = true,
            lowWarn        = true,    -- lowest quarter turns red while the shield is in it
            flashHit       = true,    -- white flash when a hit is swallowed
            shieldColor    = { r = 0.95, g = 0.89, b = 0.56 },
            warnColor      = { r = 1.00, g = 0.30, b = 0.10 },
            innerFire      = true,    -- the arc left of the character
            innerFireFlash = true,
            innerFireColor = { r = 1.00, g = 0.45, b = 0.00 },
            segments       = 20,
            distance       = 100,     -- from the middle to each arc
            height         = 270,
            curve          = 15,      -- degrees of circle each arc spans
            segSize        = 40,
            numberSize     = 20,
            alpha          = 1,
            pos            = { x = 0, y = 30 },
        },
    },
})
CL.mod = mod
mod.tabs = {}
mod.tabsAlways = true     -- one class so far; the tab says which

local function playerClass()
    local _, token = UnitClass("player")
    return token
end

-- The tab order is the order the class files load in.
function CL.Register(token, def)
    CL.classes[token] = def
    CL.byTab[def.tab] = def
    mod.tabs[#mod.tabs + 1] = { id = def.tab, label = def.label }
end

local function current()
    return CL.classes[playerClass() or ""]
end

function CL.db(tab)
    return mod.db and mod.db[tab]
end

function mod:OnEnable()
    local def = current()
    if def and def.Enable then def.Enable() end
end

function mod:OnDisable()
    local def = current()
    if def and def.Disable then def.Disable() end
end

local function apply()
    local def = current()
    if mod.active and def and def.Apply then def.Apply() end
end
CL.Apply = apply

function mod:GetOptions(tabId)
    local def = CL.byTab[tabId] or CL.byTab[mod.tabs[1] and mod.tabs[1].id]
    if not def then return {} end
    local rows = ns.OptionRows(function() return CL.db(def.tab) end, apply)
    local items = {}
    if current() ~= def then
        items[1] = { type = "desc", text = L["|cffaaaaaaThese settings take effect on a character of this class.|r"] }
    end
    for _, row in ipairs(def.Options(rows)) do items[#items + 1] = row end
    return items
end
