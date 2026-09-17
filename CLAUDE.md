# VuloForeverUI

UI suite for **World of Warcraft: Forever**, client 1.60.1, `## Interface: 16001`.
Successor to VuloClassicUI (Era / Anniversary / Wrath) — a separate product, not a port.

## The client, in one paragraph

Forever is **not** a Classic client. Its internal game type `camelot` belongs to Blizzard's
**Mainline family**, so it loads retail FrameXML, retail Edit Mode, `C_Traits` talents and
the full retail 12.x in-combat addon restrictions, with Classic-style art and a handful of
`Camelot/` overrides on top. Details, with evidence:
[docs/forever-client-research.md](docs/forever-client-research.md).

## Rules for writing code here

1. **Retail API only.** `C_Item`, `C_Spell`, `C_Container`, `C_UnitAuras`, `C_AddOns`,
   `C_QuestLog`, `C_Minimap`, `C_Traits`, `MenuUtil`, the Settings API. The Classic globals
   (`GetItemInfo`, `UnitAura`, `GetSpellInfo`, `EasyMenu`, `InterfaceOptions_AddCategory`,
   `IsAddOnLoaded`, …) do not exist. Do not add a compat shim to bring them back — this
   addon ships for one client.
2. **Display a secret, never decide on one.** Combat data arrives as secret values: no
   arithmetic, comparison, concatenation, or use as a table key. Pass them into widget
   setters. Use `Core/Secret.lua` (`ns.IsSecret`, `ns.CanRead`, `ns.Num`,
   `ns:SetHealthFill`, `ns:SetPowerFill`, `ns:SetSpellCooldown`, `ns.AurasRestricted`, …).
3. **There is no combat log.** `CombatLogGetCurrentEventInfo` is nil and
   `COMBAT_LOG_EVENT_UNFILTERED` is restricted. Anything that needs it needs a different
   design: `PLAYER_SWING` + `C_SwingTimer` for swings, `C_DamageMeter` for damage.
4. **Everything lives on `ns`.** No bare globals except the one addon table in
   `Core/Namespace.lua`. The checker enforces this.
5. **Never name another addon** in code, comments, strings or commit messages.
6. **Locale keys are English text.** Never evaluate `L[...]` at file scope — the saved
   language override only exists from `ADDON_LOADED`. Use `ns.OnLocaleReady(fn)` for
   file-scope-style blocks.
7. **Before assuming an API exists, check the client source**, not memory. Mirrors used
   for the research are Gethe/wow-ui-source branches `forever` (1.60.1) and `live` (12.1).

## Layout

```
Core/      framework: namespace, db/profiles, module + slash registry, events,
           scheduler, mover, media, secret-value layer
UI/        settings window, widgets, options builder, own Edit Mode HUD
Modules/   feature modules (GlobalSettings, Profiles, Minimap so far)
Media/     fonts, textures, icons
Libs/      LibStub, CallbackHandler, LibSharedMedia, LibDataBroker, LibDeflate,
           LibEditModeOverride
tools/     node check.js — syntax, locals cap, locale coverage, house rules, TOC
docs/      client research
```

## Adding a module

```lua
local _, ns = ...
local L = ns.L

local M = ns:RegisterModule("mymodule", {
    name = "My Module",
    group = "HUD",                       -- sidebar group
    desc = "One line, English, shown in the options.",
    defaults = { enabled = true, scale = 1 },
})

function M:OnEnable()  self:RegisterEvent("PLAYER_ENTERING_WORLD", function() end) end
function M:OnDisable() end
function M:GetOptions() return { { type = "slider", key = "scale", label = L["Scale"], min = 0.5, max = 2 } } end
```

Then add the file to `VuloForeverUI.toc` (the checker verifies the list matches disk) and
run `cd tools && node check.js`.

## Before shipping anything

`cd tools && node check.js` must print `RESULT: OK`. In the client, `/vfsecrets` tells you
what is actually readable — the API docs cannot, and a module built on a value that turns
secret in combat fails only in combat.
