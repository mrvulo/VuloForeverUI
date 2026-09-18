# Unit Frames — design (2026-09-18)

Player and target frames for VuloForeverUI in three styles. Approved in
conversation on 2026-09-18; this is the written record the implementation
plan is built from.

## Scope

- Units: **player** and **target**. Nothing else in the first version.
- Styles: **Standard**, **Classic**, **Modern** — one setting, one choice.
- No auras on our own frames in the first version. Blizzard's buff frame at
  the top right stays. Reason: aura APIs throw for tainted code in combat
  (confirmed 2026-09-18), so a target debuff row would work out of combat and
  vanish in a fight. A half feature is worse than none.

## Client facts the design rests on

All confirmed in the beta client on 2026-09-18 (`docs/forever-client-research.md`):

- `UnitHealth`, `UnitHealthPercent`, `UnitPower` are secret **always**, the
  player's own included, out of combat too. `UnitHealthMax`, `UnitPowerMax`
  and `UnitThreatSituation(player, target)` stay readable in combat.
- `C_UnitAuras.*` throws in combat rather than returning a secret.
- The secrecy predicates live on `C_Secrets`; they answer true in combat.
- Forever's own PlayerFrame/TargetFrame are the Mainline retail frames
  (`UI-HUD-UnitFrame-*` atlases). The Classic frame art
  (`Interface\TargetingFrame\UI-TargetingFrame`, `-Elite`, `-Rare-Elite`)
  is present in the client and loads.

## 1. Module and options

- Module key `unitframes`, group "Unit Frames", per-profile db.
- `style = "standard" | "classic" | "modern"` — the one setting that decides
  everything.
- Extras (Standard style only; built into Classic and Modern): `classColor`,
  `threat`, `classIcon`. Each a toggle, default on.
- Classic only: `playerElite` — the dragon border on the player frame,
  default on (what the previous product showed).
- Modern only: `portrait` toggle, default on.
- Position and scale of our own frames go through the mover system, so they
  are editable in `/vedit` and saved per profile like every other mover.
- Style change **to** Classic or Modern applies live, out of combat. Change
  **back to Standard** asks for `/reload` through the framework's reload
  popup: Blizzard's frames were silenced (events unregistered) and cannot be
  revived cleanly. In combat the change is stored and applied at
  `PLAYER_REGEN_ENABLED`.

## 2. Engine — one for both own skins

File: `Modules/UnitFramesEngine.lua`. Owns nothing visual beyond the bars
and font strings it creates; the skins only tell it where things go.

### Frames

- One `Button` per unit, `SecureUnitButtonTemplate`, named
  `VuloForeverUI_PlayerFrame` / `VuloForeverUI_TargetFrame`.
- `unit` attribute set once at creation (out of combat, at enable);
  `RegisterUnitWatch` owns show/hide; `*type1 = target`,
  `*type2 = togglemenu`, `RegisterForClicks("AnyUp")`.
- Children per frame: health bar, power bar, name, level, health text,
  power text, portrait, threat text + glow, class icon, classification
  border (Classic) — created once, shown or hidden by the skin.

### Events

`RegisterUnitEvent` wherever the event has a unit argument, so the client
filters delivery. Player frame registers for `player` and `vehicle`.

| Channel | Events |
|---|---|
| health | `UNIT_HEALTH`, `UNIT_MAXHEALTH` |
| power | `UNIT_POWER_UPDATE`, `UNIT_MAXPOWER`, `UNIT_DISPLAYPOWER` |
| identity | `UNIT_NAME_UPDATE`, `UNIT_LEVEL`, `UNIT_FACTION`, `UNIT_CLASSIFICATION_CHANGED`, `UNIT_PORTRAIT_UPDATE` |
| threat | `UNIT_THREAT_SITUATION_UPDATE`, `UNIT_THREAT_LIST_UPDATE` |
| all | `PLAYER_TARGET_CHANGED` (target frame), `PLAYER_ENTERING_WORLD` |

Each channel is one painter function `paint<Channel>(frame, unit)`. A full
repaint runs every channel.

### Painters — the secret rules, applied

- **Health bar:** `ns:SetHealthFill(bar, unit)` — the bar is scaled 0..100
  and fed `UnitHealthPercent`; the secret goes straight into `SetValue`.
- **Power bar:** `ns:SetPowerFill(bar, unit)` — raw `UnitPowerMax` and
  `UnitPower` into `SetMinMaxValues`/`SetValue`.
- **Health text:** `fs:SetFormattedText("%s", AbbreviateNumbers(UnitHealth(unit)))`
  for the value; `fs:SetFormattedText("%d%%", UnitHealthPercent(unit, true, CurveConstants.ScaleTo100))`
  for the percent. Both arguments are secret and travel untouched. Dead,
  ghost and offline are decided on `UnitIsDeadOrGhost` / `UnitIsConnected`,
  which are readable.
- **Power text:** same shape with `UnitPower`.
- **Bar colour:** class colour when `select(2, UnitClass(unit))` is readable
  (`ns.CanRead`); otherwise the health gradient: a `C_CurveUtil` colour
  curve (green → yellow → red) handed to `UnitHealthPercent(unit, true, curve)`,
  whose returned colour goes into `SetStatusBarColor` uninspected. Power
  colour from `PowerBarColor[UnitPowerType(unit)]`; the power type is checked
  with `ns.CanRead` and falls back to the mana colour.
- **Name / level:** `SetText(UnitName(unit))` directly (name may be secret;
  `SetText` accepts it). Level: `UnitLevel` through `ns.Num(level, nil)`;
  unreadable → keep the last text. `-1` → "??". Level colour via
  `GetCreatureDifficultyColor` only when the level is readable.
- **Portrait:** `SetPortraitTexture(tex, unit)` (Classic and Modern with
  portrait on).
- **Threat:** `UnitThreatSituation("player", "target")` for the target
  frame, `UnitThreatSituation("player")` for the player frame — readable.
  Status → colour and text via the readable integer; glow shown at status
  ≥ 2. Threat percent via `UnitDetailedThreatSituation` only where
  `ns.CanRead` says yes; otherwise the text shows the status word alone.
- **Classification:** `UnitClassification(unit)` through `ns.CanRead`;
  unreadable → keep the last border.
- **Class icon:** class token through `ns.CanRead`; unreadable → hide.

Rule of thumb enforced in review: no `if` on a value that came out of
`UnitHealth`, `UnitPower`, `UnitHealthPercent` or an aura/cooldown API.

### Silencing Blizzard's frames (Classic and Modern only)

The recipe of the Modern reference, which runs on this client family:

1. `frame:UnregisterAllEvents()`, `frame:Hide()`, `frame:SetParent(hiddenParent)`
   where `hiddenParent` is a hidden frame created once.
2. `hooksecurefunc(frame, "SetParent", …)` re-applies the hidden parent on
   the next frame if Edit Mode or anything else reparents it back.
3. Also unregister the children that self-update: health bar, mana bar,
   cast bar, alternate power bar, aura frame, pet frame, ToT frame.
4. In combat: the frame is put on a list and handled at
   `PLAYER_REGEN_ENABLED`.

Applies to `PlayerFrame` and `TargetFrame`. `PetFrame` and `FocusFrame` are
left alone — they are not ours yet.

## 3. Skins — two layout tables

File: `Modules/UnitFramesSkins.lua`. A skin is a table the engine reads:
size, anchors of every child, textures, fonts, which children exist. No
logic beyond `apply(frame, skin)`.

### Classic

- Player: 232×100 body, portrait 64×64 on the left, health and power bars
  to the right, name above the health bar, level in the circle at the
  portrait corner — the original layout of Blizzard's Classic PlayerFrame.
- Target: mirrored (portrait right).
- Frame texture: `Interface\TargetingFrame\UI-TargetingFrame`; target
  swaps to `-Elite`, `-Rare`, `-Rare-Elite` by classification; player wears
  `-Elite` when `playerElite` is on.
- Bar textures: Blizzard's `UI-StatusBar`. Fonts: `GameFontNormalSmall`
  (name), `GameFontNormalSmall` (level), `TextStatusBarText` (values).
- Health text and percent shown on the bar, always (the previous product's
  "real health" replaced by the secret-safe path).

### Modern

- Player and target: 220×46 flat panel, `ns.UI:StyleBackdrop` ground,
  `ns.UI:CreateShadow`, one-pixel accent line at the top.
- Health bar 220×28 (class coloured), power bar 220×12 underneath, both
  with the profile's LibSharedMedia texture (`ns.Media`).
- Name left inside the health bar, level right of the name in a small
  font, health percent right-aligned inside the health bar, power value
  right-aligned inside the power bar. Font: `ns.UI.Font`.
- Portrait: 46×46 square left of the panel when `portrait` is on, dark
  ground, one-pixel border in the accent colour.
- Threat: name colour turns to the threat colour; glow is the shadow tinted.
- Classification: "Elite" / "Rare" as a small tag after the level.

## 4. Extras — Standard style

File: `Modules/UnitFramesExtras.lua`. Cosmetic hooks on Blizzard's
PlayerFrame and TargetFrame; never touches their secure state; nothing here
is protected.

- **Class colour:** `hooksecurefunc("UnitFrameHealthBar_Update", …)` and
  `…HealthBar_OnValueChanged` → `bar:SetStatusBarColor(class colour)` when
  the class token is readable; otherwise leave Blizzard's colour.
  Anchored to the health bar of `PlayerFrame.PlayerFrameContent…` and
  `TargetFrame.TargetFrameContent…` — parent keys taken from Forever's
  `Mainline/PlayerFrame.xml` and `TargetFrame.xml` at implementation time,
  not remembered.
- **Threat:** own font string and glow texture on the target frame, driven
  by `UNIT_THREAT_SITUATION_UPDATE` and `PLAYER_TARGET_CHANGED`, same
  painter as the engine's (shared function).
- **Class icon:** own texture over the portrait corner, `CLASS_ICON_TCOORDS`,
  hidden when the class token is unreadable.
- Dropped from the previous product because Retail already does it: the
  rare/elite border (the retail frame shows it), permanent health text
  (Blizzard's "Status Text: Always" setting).

## 5. Combat, errors, testing

- Everything painted onto our own frames is insecure and legal in combat.
  Gated on "out of combat": frame creation, `SetAttribute`, silencing
  Blizzard's frames, style switch. Each gated action has a pending flag
  resolved at `PLAYER_REGEN_ENABLED`.
- Every decision on a unit value has a "cannot read" branch: keep the last
  state, or a neutral fallback. No arithmetic, comparison, concatenation or
  table-keying on anything from the secret list.
- Painters run inside the framework's event dispatch, which `pcall`s
  non-hot handlers; hot handlers (`UNIT_HEALTH`, `UNIT_POWER_UPDATE`) must
  not throw — the review checks them line by line.
- Tests: `cd tools && node check.js` green; `/vfsecrets` in combat as the
  reference for what is readable; adversarial review of the four files
  against the Modern reference and Forever's `Blizzard_UnitFrame` source;
  then the in-game pass: both skins, out of and in combat, target swap
  mid-fight, `/vedit` move and reload, style switch each way.

## Files

```
Modules/UnitFrames.lua          module, options, style switch, reload popup
Modules/UnitFramesEngine.lua    frames, events, painters, Blizzard silencing
Modules/UnitFramesSkins.lua     the two layout tables + apply()
Modules/UnitFramesExtras.lua    Standard-style hooks
```

All four in `VuloForeverUI.toc` after `Modules\Minimap.lua`, in this order.

## Out of scope (later versions)

Target-of-target, focus, pet, party; auras on own frames; cast bars on own
frames (Blizzard's player cast bar stays as it is; the target cast bar is a
child of TargetFrame and disappears with it in Classic/Modern — accepted for
the first version, to be replaced by an own target cast bar later).
