## 0.9.0

**New**

- **Quality of Life** — quest markers on the minimap: every quest you have
  not finished gets a marker where the game points for its objectives. Hover
  it for the open objectives and the distance; click it and the game's own
  waypoint leads you there, click again to stop.
- **Quality of Life** — the ! of an available quest takes the colour of the
  quest's level, like in the quest log; daily and repeatable quests show a
  blue ! (can be switched off), a repeatable hand-in a blue ?. Every quest
  marker names the quest line and the step, e.g. "Step 3 of 7".
- **Quality of Life** — a quest journal per character: every quest accepted,
  handed in and abandoned and every level gained, with date, level, zone and
  experience. Open it with /vfjournal or from the Quest tab.
- **Quality of Life** — mark junk yourself: Alt + right click (or Ctrl, your
  choice) on an item in your bags marks every item of that kind as junk, or
  unmarks it. Marked items are sold at the merchant together with the greys
  and carry the junk C in the bags, ours and the game's. A button clears the
  list.
- **Quality of Life** — Destroy junk when the bags are full (off by default):
  when the game says your bags are full, the cheapest grey or marked stack is
  destroyed to make room. Never in combat; the chat says what went.
- **Diagnostics** — /vfdiag keeps a log for bug reports: errors, blocked
  actions and the output of the addon's commands, saved at /reload and
  logout. '/vfdiag note <text>' adds a note of your own.

**Changed**

- **Nameplates** — the execute glow is a soft red glow around the health bar
  with a red wash over it, pulsing faster; dead targets no longer glow. The
  threshold is set in percent.
- **Minimap** — the Classic style shows the map as large as the Standard
  style and grows with the UI scale and the size slider. The tracking button
  and the button of the minimap button collection have the size of the
  standard map, the zone name sits centred in the header, and the zoom
  buttons are shown by default.
- **Action bars** — the Classic style is as large as the standard bar and
  follows the UI scale; on narrow screens it shrinks so the band and the
  gryphons stay fully visible.
- **Options** — every opacity is a slider in percent; sliders show their unit,
  and typed values with % or a decimal comma are understood. The colour
  picker has an opacity slider wherever the setting keeps one.
- **Options** — every border has the same set of settings in the same order:
  show, texture, thickness, offset, colour with opacity, class colour. Font
  outlines offer the same three choices everywhere.
- **Nameplates** — the cast bar uses the game's own spark.
- **Chat, Cooldown Manager** — the whisper sound and the ready sound offer the
  sounds other addons share instead of two bundled ones.

**Fixed**

- **Options** — resetting a colour also restores its opacity; the opacity can
  be set while class colour is on.

This version brings new files: restart the game once, a /reload is not enough.
