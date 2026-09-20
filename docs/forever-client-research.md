# WoW: Forever client research (2026-09-17)

Source: static analysis of the Forever UI source (Gethe/wow-ui-source, branch `forever`, 1.60.1.69893) compared with `live` (12.1.0.69814) and `classic_era` (1.15.9), plus public info. Items marked **confirmed** were checked in the beta client on 2026-09-18 (build 1.60.1.69913); everything else is still static analysis.

## Facts
- Beta: 2026-09-17 to 2026-10-21, level cap 30. Release: 2026-11-04.
- Local install: `C:\Program Files (x86)\World of Warcraft\_classic_beta_`, product `wow_classic_beta`, build 1.60.1.69893 (the doc's source snapshot); the client ran 1.60.1.69913 on 2026-09-18.
- TOC: `## Interface: 16001`. **Confirmed:** a plain `.toc` with this line loads; `GetBuildInfo()` reports `1.60.1`, build `69913`, interface `16001`.
- Internal game type is **camelot**, part of the **Mainline family**. In Blizzard TOCs, `[Family]` resolves to `Mainline/` and `[Game]` to `Camelot/`. Classic FrameXML and the classic deprecation shims do **not** load.
- **Secret values and addon restrictions are fully active**, the same as retail 12.x:
  - The combat log can't be read (`CombatLogGetCurrentEventInfo` is nil).
  - `SendAddonMessage` can't be used in chat lockdown.
  - `SetRaidTarget` is restricted.
  - `UnitHealth` always returns a secret.
  - Auras, cooldowns, threat and casts of other units are secret in combat.
- Forever only: `Cooldown:SetCooldown*` and `:Clear` are protected functions.

## UI (camelot)
- **Edit Mode** has the presets Modern, Classic and Gamepad. New systems: TotemActionBar, MainActionBarEndCap (gryphons), SwingTimer, DamageMeter, CooldownViewer, GroupFinder.
- **Retail frames:** `MainActionBar`, `PlayerFrame.PlayerFrameContent...`, `MicroMenuContainer`, `BagsBar`, `MinimapCluster`, `ObjectiveTrackerFrame`, `PlayerCastingBarFrame`, `BuffFrame`/`DebuffFrame`, `CompactRaidFrames`.
- **Camelot-specific frames:**
  - `CharacterFrame` with tabs PaperDoll, Reputation, Token, PVPRank, Skills and Statistics.
  - Classic bag art with a key ring.
  - Nameplate level frame, round minimap, day/night indicator (`DIEL_CYCLE_CHANGED`), `LegacyMicroButton`.
- **Talents** use `C_Traits` (`Enum.TraitConfigType.CamelotCombat`) in `PlayerSpellsFrame`. There is dual spec, and `GetTalentInfo` and `PlayerTalentFrame` don't exist.
- **Not loaded:** EncounterTimeline and EncounterWarnings (only the API exists), retail GroupFinder (replaced by `Blizzard_GroupFinder_VanillaStyle`), PVPUI, Housing, arena frames.
- **New systems:**
  - Legacy system with trait trees 1187/1188/1189 and currency 4225.
  - PvP ranks (faction 2800).
  - Hardcore.
  - Gamepad UI.
  - Skyborne race.
  - Only 9 classes.

## API
- **Missing globals, use the replacement:**

  | Missing | Use instead |
  |---|---|
  | `UnitAura`/`UnitBuff`/`UnitDebuff` | `C_UnitAuras` |
  | `GetSpellInfo` | `C_Spell` |
  | `GetItemInfo` and `GetItem*` | `C_Item` |
  | `GetContainerItemInfo` | `C_Container` |
  | `GetQuestLogTitle` | `C_QuestLog` |
  | `GetTrackingInfo` | `C_Minimap` |
  | `GetNumSkillLines` | `C_SkillInfo` |
  | `CastingInfo` | `UnitCastingInfo` |
  | `EasyMenu` | `MenuUtil` |
  | `InterfaceOptions_AddCategory` | Settings API |
  | `IsAddOnLoaded` | `C_AddOns` |

- **Forever only:** `C_SwingTimer` + `PLAYER_SWING`, `C_PetInfo.GetPetHappiness`/`GetPetLoyalty`, `C_SkillInfo`, `C_PaperDollInfo.AmmoNeeded`, `UnitDefenseSkill`, `C_GameRules.IsHardcoreActive`, `table.*`/`string.*`/`math.*` extensions.
- **Detection (confirmed):** `local toc = select(4, GetBuildInfo()); isForever = toc >= 16000 and toc < 20000 and C_SwingTimer ~= nil` evaluates to true in the client.
- **Confirmed:** `WOW_PROJECT_ID == 1` (`WOW_PROJECT_MAINLINE`) and `C_GameRules.GetActiveGameMode() == 1`. Neither distinguishes Forever from retail, which is why detection goes through the interface range plus the `C_SwingTimer` probe.

## Port assessment of VuloClassicUI 1.62.0
- On Forever, the current flavor detection would wrongly set `ns.isEra = true`.
- **Low risk, reusable:** Core (registry, DB/profiles, events, Mover, schedule, locale) and UI/* (options, widgets, own Edit Mode HUD), plus bags/BagSort, SlotPicker, Vulslot, PopupSkin, CastHistory, gold/auto-buy/mail/queue timer.
- **Medium:** UnlockMode (check LibEditModeOverride against camelot), Auras, Reminders, Trinkets, PowerBar, PlayerCastBar, SwingTimer (rebuild on `PLAYER_SWING`), ActionRing, GuildBank, Chat (secret guards), Trackbars, Loadouts.
- **High, rewrite against Mainline frames:** UnitFrames, CharacterPanel, FriendList, Bank (`C_Bank`), QuestTracker (ObjectiveTracker), ActionBars, CooldownManager, MinimapStyle, DarkSkin, Nameplates.
- **Blocked or drop:**
  - Meter: reskin `C_DamageMeter` instead.
  - Arena frames, ClassTrackers/Paladin twist, the scrolling combat text engine, cooldownpulse (combat log).
  - TalentView.
  - General: quest log and profession window as they are now.
  - Anniversary bug fixes, LazyVulo.
- Roughly: Low ≈ 23k lines, Medium ≈ 31k, High ≈ 22k, Blocked/drop ≈ 19k.
- **Recommendation:** clean rebuild that reuses Core and UI, not a fork.

## Public findings from other developers (collected 2026-09-19)

Sources: two public research repos measuring the same beta build
([forever-addon-kit](https://github.com/Thunderz96/forever-addon-kit),
[forever-addon-dev](https://github.com/imperial64/forever-addon-dev), `research/findings.md`),
the Warcraft Wiki pages [Secret Values](https://warcraft.wiki.gg/wiki/Secret_Values) and
[Patch 12.1.0/API changes](https://warcraft.wiki.gg/wiki/Patch_12.1.0/API_changes). The addon
developer Discord (WoWUIDev) is login-only and was not read. Labels: **ours** = matches our
own client data, **source** = checked in the `forever` UI source, **reported** = their
measurement, not yet repeated here.

### From the addon developer Discord (WoWUIDev, read 2026-09-19)
Channels `#forever`, `#forever-faq-temp` and the `bugs` forum (tags `forever-ptr` /
`forever-live`). This is where Blizzard's answers arrive first; re-read it after each build.
- **SavedVariables not loading: Blizzard is tracking it.** It is *unpredictable*, not
  constant -- some addons load in one session and not the next; a freshly created saved
  file tends to load for that one session. `## LoadSavedVariablesFirst: 1` does not help.
  Our dev seed already covers both outcomes (the client wins when it does load).
- **Secure snippets / `loadstring_untainted`: confirmed by Blizzard as unintentional**, being
  looked into. Do not design around it as permanent.
- **`UnitPower("player", Enum.PowerType.ComboPoints)` secret: fix pending for the next
  build** (word from Blizzard). Combo points are the only secondary class power Forever has
  (no holy power, soul shards, runes, essence). Primary power being secret is not
  mentioned in that answer -- re-run `/vfsecrets` on the next build.
- **No realms; names are "Main Secondary".** `UnitName("player")` returns the full unique
  name as ONE string, `UnitName("target")` returns TWO values (main, secondary), and
  `GetPlayerInfoByGUID` only the main name. Blizzard has not settled the final shape.
  The WTF folder spells it `Main-Secondary`. Anything keyed per character must not assume
  `Name-Realm`; the moderators suggest the *ruleset* as a realm substitute.
  `Modules/UnitFrames/Engine.lua` passes `UnitName(unit)` straight into `SetText`, so other
  units show the main name only -- fine for now, revisit when the API settles.
- **`UnitRace` (and similar) can freeze or crash the client**, even with no addons loaded.
  We do not call it; keep it that way until fixed.
- **The GCD spell is 29515 on Forever, not 61304**, and it is secret in combat (not on the
  never-secret list yet). Use the duration object or the non-secret `isOnGCD` field of the
  spell cooldown info.
- **TOC:** `_Mainline.toc` also loads on Forever. Recommended is one TOC with per-line
  conditions: `file.lua [AllowLoadGameType camelot][ExcludeLoadGameType standard, classic]`
  (Forever only, may change), `## AllowLoadGameType: standard` (retail only). Our single
  plain TOC is the recommended setup. This settles "To verify" item 2.
- `WOW_PROJECT_ID` equal to retail is reported as a bug there too -- it may change, another
  reason our detection does not use it.
- Talents: no `GetNumTalents`/`GetActiveTalentGroup`/`GetNumTalentTabs`; the trees reuse
  `C_Traits` TraitNodeGroups. The community is still working out the iteration pattern.
- A dependency on an addon that does not exist on Forever (e.g. Housing) makes an addon
  refuse to load **without any error**.

### Beta bugs (Blizzard's, not ours)
- **SavedVariables are written on logout and never read back.** Both repos proved it
  independently (pre-seeded file, global stays nil from main chunk to logout). **ours:**
  `global.freshLog` in our saved file holds only the newest login on 2026-09-19 although
  the 2026-09-18 file had one too -- nothing accumulated, so the file was never loaded. This
  is the "empty database at login" problem; the load probe in `Core/Init.lua` cannot find
  a cause on our side because there is none (probe removed 2026-09-19). Dev workaround
  (built and **confirmed in the client 2026-09-19**, account and character file restored;
  the watcher picked up the client's save and the next load used it):
  `node tools/sv-seed.js [--watch]` copies the saved files from WTF into
  `Dev/SavedSeed.lua`, which the TOC loads as addon code; `ns:InitDB` takes the seed only
  while `VuloForeverUIDB` arrives nil, and prints "dev seed: the client loaded the saved
  settings itself" at login once a beta build fixes the bug. Not shippable -- players
  have no external script -- so the committed file is an empty stub.
- **`loadstring_untainted` is missing**, so secure snippets cannot compile. **source:**
  `Blizzard_RestrictedAddOnEnvironment/RestrictedExecution.lua:22` captures the global,
  `:79` calls it. **reported:** every `WrapScript`, `_onstate-*`, `RunAttribute` and
  `initialConfigFunction` throws "attempt to call a nil value". We use none of these today
  (checked 2026-09-19); ActionBars and anything with state drivers will hit it. Guard with
  `if loadstring_untainted then`.
- **`C_CooldownViewer` categories are empty** for Forever specs (**reported**). A cooldown
  module has to read the spellbook, not the viewer data.
- **`C_AssistedCombat` is inert** (`IsAvailable()` false) (**reported**).

### Restrictions
- **`ReloadUI()` works from a button click (ours, confirmed 2026-09-19, build 69913):** no
  error, no blocked-action dialog. The public reports of it being "protected" describe
  calls made *without* user input (a timer or an event handler, for an unattended reload
  loop) -- that case is untested here and we have no such call: all 11 of ours
  (GlobalSettings, Profiles, Minimap menu, MainFrame, Setup, Init, UnitFrames popups) run
  from a click, a popup button or a slash command. Keep it that way; never call
  `ReloadUI()` from `C_Timer` or an event.
- **`UseAction` is forbidden in and out of combat**; `EditMacro` and
  `SetOverrideBindingClick` are blocked in combat only (**reported**).
  `SecureActionButton:SetAttribute` raised no error in combat, but "no error" is not
  "took effect" -- do not build on it untested.
- **`COMBAT_LOG_EVENT(_UNFILTERED)`: the subscription itself is refused**, always, and
  **`RegisterEvent` still returns normally** -- a `pcall` reports success while the client
  shows the blocked-action dialog. Never register it, not even behind a pcall.
- **Registering an event the client does not know throws and aborts the file**
  (**reported**). `ns:RegisterEvent` already wraps this in `pcall` (`Core/Events.lua:27`);
  raw `frame:RegisterEvent` calls in modules need the same.
- **After 100 Lua errors per session the client stops delivering errors to any handler.**
  An error flood hides the real error -- fix floods first, `/reload` to reset.
- **Gates in combat (reported, matches ours where we measured):** auras, cooldowns, action
  cooldowns, unit stats, threat values -> secret. `ShouldUnitSpellCastBeSecret()` stays
  **false** (cast bars of other units work), threat **state** stays readable, unit identity
  and max health stay readable. `UnitPower("player")` is secret always.
- `C_RestrictedActions.GetAddOnRestrictionState()` goes 0 -> 2 and
  `IsAddOnRestrictionActive()` false -> true on entering combat: one queryable global switch
  next to the per-category `C_Secrets` gates.
- `C_ChatInfo.AreOutgoingAddonChatMessagesRestricted()` is **true even out of combat** --
  no addon-message features (profile sharing over chat, version checks) for now.
- **Three refusal shapes:** a throw (auras), a secret that survives `tostring()` and
  detonates at the next index/compare (power, health), a plain nil (cast info, cooldown
  start). `tostring(secret)` is a secret string: test with `issecretvalue` before **and**
  after converting, and never let one reach SavedVariables -- it would break the flush.
- `UNIT_AURA`'s added/removed payload lists arrive as secret tables in combat.

### Tools the client gives us
- **Forced-restriction CVars for testing without a fight:** `addonCombatRestrictionsForced`
  **exists on 1.60.1 (ours, 2026-09-19):** `C_CVar.GetCVarInfo` returns value "0", default
  "0", and false for server-stored, locked-from-user, secure and read-only.
  `/vfsecrets force` toggles it; the report and the login line say when it is on, because
  the CVar outlives the session. **To verify:** that setting it to 1 really flips the
  `C_Secrets` gates and makes the aura API throw. The siblings
  `addonMapRestrictionsForced`, `addonPvPMatchRestrictionsForced` and
  `addonEncounterRestrictionsForced` (wiki) are unchecked.
- **More secret helpers than we use:** `issecrettable`, `canaccesstable`,
  `hasanysecretvalues`, `scrub`, `scrubsecretvalues`, `secretwrap`, `canaccesssecrets`,
  `dropsecretaccess`; on widgets `HasSecretAspect`, `HasSecretValues`, `HasAnySecretAspect`,
  `IsAnchoringSecret` (explains finding 10 below: anchoring secrecy is inherited from the
  frame a region is anchored to).
- **Allowed on secrets from tainted code:** storing, passing on, concatenation and
  `string.format`/`string.concat`/`string.join` (wiki, 12.x) -- the result is secret again.
  Forbidden: arithmetic, compare, boolean test, `#`, table key, indexing.
- **Sanctioned display paths:** `C_CurveUtil.CreateColorCurve()` for colour-by-percent
  (in use, `Modules/UnitFrames/Engine.lua`), `C_CurveUtil.CreateCurve()`,
  `C_DurationUtil.CreateDuration()` + `StatusBar:SetTimerDuration()` for timer bars,
  `C_Spell.GetSpellCooldownDuration(id)` / `C_UnitAuras.GetAuraDuration(unit, instanceID)`
  -> duration object -> `Cooldown:SetCooldownFromDurationObject()` (in use,
  `Core/Secret.lua`). Reported: a duration object must be set **before** combat for the
  widget to tick.
- **12.1 aura widgets:** `CreateFrame("AuraContainer")` with `AddAuraGroup`/`AddAuraSlot`/
  `AddItemEnchantment`; the container creates its `AuraButton`s itself and they carry
  forbidden aspects. On 12.1 this is the route to show auras in combat from addon code.
  **Ours, 2026-09-19:** `pcall(CreateFrame, "AuraContainer", nil, UIParent)` returns true
  and a frame on 1.60.1 -- the widget type exists. Not yet tried: adding a group and
  seeing buttons appear in combat.
  `SecureAuraHeaderTemplate` is removed. Also 12.1: `getglobal`/`setglobal` deprecated,
  `MouseIsOver` -> `InputUtil.IsMouseOver`, `UnitClass`/`UnitSex`/`UnitGroupRolesAssigned`
  secret when unit identity is secret.
- `C_Secrets.GetSpellAuraSecrecy(id)` returns `Enum.SecrecyLevel`
  (NeverSecret / AlwaysSecret / ContextuallySecret) -- whitelisted spells can be shown
  with full data even in combat.
- `C_EncodingUtil` (JSON, CBOR, base64, compress) exists -- a native alternative to
  LibDeflate for profile export strings.
- New swing API detail: `PLAYER_SWING(swingDuration, swingType)`,
  `PLAYER_SWING_RANGE_UPDATE(swingType, isInRange, checksRange)`, `Enum.PlayerSwingType`
  (MainHand 0, OffHand 1, Ranged 2), `C_SwingTimer.IsTargetWithinSwingRange(type)`.
- Costs (**reported**): `C_Map.GetPlayerMapPosition` allocates ~1.8 KB per call -- poll on
  an accumulator, never per frame. `OnUpdate` `elapsed` has 1 ms resolution; profile with
  `debugprofilestop`. `gxBrightness`/`gxContrast`/`gxGamma` do not exist; the CVars are
  `Brightness`, `Contrast`, `Gamma`. `maxFPS` keeps its value while `useMaxFPS` is 0.
- Version trap: retail-style checks `select(4, GetBuildInfo()) >= 100000` are false here.
  Ours uses the 16000-20000 range plus the `C_SwingTimer` probe, which is correct.

## Nameplates (measured in the client 2026-09-20, build 69913)

`/vfsecrets np` on a targeted mob, out of combat. What it settled:

- **`nameplate.namePlateUnitToken` does NOT exist.** The retail field name returns nil and
  `UnitIsUnit(nil, "target")` throws "bad argument #1". The base plate keeps its unit in
  **`.unitToken`**, read with **`:GetUnit()`** (`Blizzard_NamePlateBase.lua:29-38`). Any code
  that maps a base plate back to a unit must use the getter -- `ns.NP.UnitOf(nameplate)`
  does, and the module additionally keeps its own weak `nameplate -> plate` map.
- **`ShowClassColorInNameplate` does not exist** on this client. `nameplateShowClassColor`
  does, and that is the one that matters.
- **CVars confirmed present:** `nameplateMinScale`, `nameplateMaxScale`,
  `nameplateSelectedScale`, `nameplateMinAlpha`, `nameplateMaxAlpha`,
  `nameplateMaxAlphaDistance`, `nameplateMinAlphaDistance`, `nameplateOverlapH`,
  `nameplateOverlapV`, `nameplateOccludedAlphaMult`, `nameplateStackingTypes`,
  `nameplateShowAll`, `nameplateShowEnemies`, `nameplateShowEnemyPets`,
  `nameplateShowClassColor`, `nameplateMaxDistance`. So the scale/alpha/distance set the
  Settings panel does not register is real after all.
- **Readable for a nameplate unit, out of combat:** `UnitClassification`,
  `UnitEffectiveLevel`, `UnitReaction`, `UnitIsTapDenied`, `UnitAffectingCombat`, and the
  `GetStatusBarColor()` of Blizzard's hidden health bar -- which is the route to an enemy
  player's class colour, since `UnitClass` is identity-restricted.
- **`UnitGetTotalAbsorbs` is secret** even out of combat, like health.
- `UnitThreatSituation` and `GetRaidTargetIndex` returned **nil** with no threat
  relationship and no marker set -- nil, not secret, so `type(v) == "nil"` is the right
  test for both.
- **`UnitGroupRolesAssigned("player")` returns "NONE"** while solo. Whether it ever returns
  TANK on Forever is still open; the nameplate module has an "I am the tank" option for
  exactly that reason.

**Second run, IN COMBAT, same build.** The remaining questions, answered:

- **Text from a secret number works after all, through the widget and through
  `string.format`.** All three accepted a secret: `SetFormattedText("%d%%", secret)`,
  `string.format("%d", secret)` (its result is a secret string, which `SetText` takes) and
  `AbbreviateNumbers(secret)`. This does not contradict "text from a secret number: only
  natively" above -- that entry is about the *formatter objects*
  (`Curve:Evaluate`, `SecondsFormatter:Format`, `NumericFormatter:FormatNumber`), which
  stay `AllowedWhenUntainted`. Plain format strings are the open route, exactly as the
  12.x wiki says. **So health percent, health number and the cast timer need no fallback.**
- `CurveConstants`, `AbbreviateNumbers` and `GetCreatureDifficultyColor` all exist as
  globals -- the three the nameplate spec had listed as unlocated.
- **`C_NamePlate.SetNamePlateSize` and `C_NamePlateManager.SetNamePlateHitTestInsets` were
  accepted IN COMBAT** (156x17). Careful: the probe fed them the values they already had,
  so this proves the call is not blocked outright, not that a real change takes effect
  mid-fight. The module still defers both to out of combat.
- **In combat, on an open-world mob:** `UnitName`, `UnitClass`, `UnitClassification`,
  `UnitEffectiveLevel`, `UnitReaction`, `UnitIsTapDenied`, `UnitAffectingCombat` and
  `UnitThreatSituation` are all **readable**; `UnitGetTotalAbsorbs` is secret and
  `GetRaidTargetIndex` nil (none set). Identity is documented as restricted on
  "addon-restricted maps", so expect this to differ in instances and PvP -- the module
  guards every one of these reads anyway.
- **`UnitIsUnit(plate token, "target")` is readable**, and the plate token is `nameplate1`
  -- the `GetUnit()` route works.
- **The interrupt spell ids are right.** Every candidate resolved to its proper German
  name (Tritt, Schildhieb, Zuschlagen, Gegenzauber, Erdschock, Stille, Wilde Attacke,
  Zaubersperre), so Forever does not renumber these. The test character is a level 11
  warrior, and Shield Bash is learned at 12: "no interrupt known" was the correct answer,
  not a bug. Re-check the kick colour and the tick once a character has one.

**Still to measure:** `UnitCastingInfo` field by field and the duration object's getters,
both of which need a nameplate unit that is actually casting.

## To verify in the beta
1. ~~Values of `/dump WOW_PROJECT_ID`, `GetBuildInfo()`, `C_GameRules.GetActiveGameMode()`.~~ Done 2026-09-18, see Facts.
2. ~~Whether a plain `.toc` with `## Interface: 16001` loads~~ (it does), and whether a `_Mainline.toc` suffix is accepted.
3. Whether LibEditModeOverride works with camelot Edit Mode. Our own Edit Mode HUD (`/vedit`) opens without errors (2026-09-18); the library itself is loaded but no module calls it yet, so this stays open until one does.
4. Which power types stay readable (player mana, rage, energy). Partly answered: `UnitPower("player")` is **secret in combat** and `canaccessvalue` says no; `UnitPowerMax("player")` stays readable. Per-power-type differences not checked yet.
5. ~~`issecretvalue(UnitHealth("player"))` in and out of combat.~~ Both (2026-09-18): `UnitHealth`, `UnitHealthPercent` and `UnitPower` of the **player** are secret and not accessible **even out of combat**; `UnitHealthMax`/`UnitPowerMax` of the player and `UnitThreatSituation(player, target)` stay readable in combat. Spell cooldowns are readable out of combat and secret in combat.
6. **New, confirmed 2026-09-18:** `C_UnitAuras.GetAuraDataByIndex("player", 1, "HELPFUL")` in combat does not return a secret, it **throws**: `Auras cannot be accessed when secret while tainted by 'VuloForeverUI'`. Aura code must gate on `C_Secrets.ShouldAurasBeSecret()` (`ns.AurasRestricted()`) before calling; a display-only path is not enough. Cooldown and threat APIs do NOT throw: cooldowns come back secret, threat stays readable.
7. **Predicate namespace:** the system is documented as `SecretUtil` but the Lua table is **`C_Secrets`** (`SecretPredicateAPIDocumentation.lua`, `Namespace = "C_Secrets"`; Blizzard's aura container calls `C_Secrets.GetSpellAuraSecrecy`). `_G.SecretUtil` is nil. There is no `ShouldUnitHealthBeSecret` -- health is always secret -- only `ShouldUnitHealthMaxBeSecret`. Whether the predicates return true in combat is still to confirm with the fixed report.
8. **Classic unit-frame art is in the client (confirmed 2026-09-18):** `Interface\TargetingFrame\UI-TargetingFrame`, `-Elite` and `-Rare-Elite` all load (`Texture:SetTexture` returns true). Forever's own player/target frames are the Mainline retail ones (`UI-HUD-UnitFrame-Player-PortraitOn-*` atlases; `Camelot/PlayerFrame.lua` only moves the level circle and PvP icon), so a Classic-shaped frame has to be our own frame, but it can use the original textures.
9. **`UnregisterAllEvents()` is refused on secure-environment frames (confirmed 2026-09-18):** calling it from addon code on the target frame's aura container (`TargetFrame.xml:338`, loaded with `[LoadIntoEnvironment secure]`) throws `Function call not permitted due to forbidden aspect 'EventRegistrations'`. Wrap every event change on a Blizzard frame tree in `pcall`; hiding the parent is what actually silences such frames.
10. **Widget getters can return secrets (confirmed 2026-09-18):** `GetPoint()` on Blizzard's status-text font strings (anchored from the secure environment) returns secret strings/numbers to addon code — comparing them throws. Treat every getter on a Blizzard region (`GetPoint`, `GetSize`, `GetNumPoints`, `GetText`) as possibly secret: guard with `ns.CanRead` and fall back to re-applying the setter.
