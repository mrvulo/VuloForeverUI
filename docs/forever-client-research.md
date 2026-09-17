# WoW: Forever client research (2026-09-17)

Source: static analysis of the Forever UI source (Gethe/wow-ui-source, branch `forever`, 1.60.1.69893) compared with `live` (12.1.0.69814) and `classic_era` (1.15.9), plus public info. Nothing here has been tested in the client yet.

## Facts
- Beta: 2026-09-17 to 2026-10-21, level cap 30. Release: 2026-11-04.
- Local install: `C:\Program Files (x86)\World of Warcraft\_classic_beta_`, product `wow_classic_beta`, build 1.60.1.69893.
- TOC: `## Interface: 16001`.
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
- **Detection (unverified):** `local toc = select(4, GetBuildInfo()); isForever = toc >= 16000 and toc < 20000 and C_SwingTimer ~= nil`. Check `/dump WOW_PROJECT_ID` in game.

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

## To verify in the beta
1. Values of `/dump WOW_PROJECT_ID`, `GetBuildInfo()`, `C_GameRules.GetActiveGameMode()`.
2. Whether a plain `.toc` with `## Interface: 16001` loads, and whether a `_Mainline.toc` suffix is accepted.
3. Whether LibEditModeOverride works with camelot Edit Mode.
4. Which power types stay readable (player mana, rage, energy).
5. `issecretvalue(UnitHealth("player"))` in and out of combat.
