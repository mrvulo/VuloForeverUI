## 0.28.0

**New**

- **Quality of Life** — loot roll list: a loot history for the session. The
  clock button in the header (or "Show loot history" in the options) folds
  out the last 15 rolls with your own choice and the winner with their roll.
  A winner that is only decided later is filled in when the game reports it.
- **Quality of Life** — flight map: hovering a destination shows the flight
  time under the price. Once you have flown a route all the way, it is the
  time you measured; before that, the time worked out from the flight paths,
  or an estimate marked with "~". Can be switched off under Quality of Life
  → General → Flight time.

**Changed**

- **Quality of Life** — gold check: the window now reads like a character
  sheet. Portrait, name in class colour, level, race, class and guild at the
  top; Overview, Players, History and Compare as tabs with the scan buttons
  on the same row; four big tiles for creatures killed, quests, deaths and
  most gold owned; sections with icons, professions as bars. For another
  character, your own numbers stand beside theirs.
- **Quality of Life** — loot roll list: finished rolls leave after the time
  set in the new "Show the result" slider (3 s by default, 0 = at once)
  instead of waiting for the winner.
- **Reminders** — clicking the food reminder eats what you picked, else the
  food that last made you Well Fed, else your role's food, else the best
  buff food your level allows. The Well Fed line in "Possible buffs" can be
  clicked the same way.
- **Cooldown Manager** — "Glow at full charges" now works in combat too.
  Proc glow is set on every redraw: spells added by ID glow like the
  others, a spell that already glows lights up right after adding it, and
  no glow stays behind on a moved icon.
- **Cooldown Manager** — new "Only while castable": a spell icon shows only
  while it is usable, off cooldown and affordable. The new right-click
  entries sit in the "Charges" and "Dim and hide" submenus.

**Fixed**

- **Reminders** — a potion that leaves a buff named like a food buff no
  longer counts as Well Fed, and a cancelled meal between fights no longer
  stops the food reminder from learning what you ate.
- **Cooldown Manager** — icons hidden by "Only while castable", dimming and
  the ready glow come back the moment a cooldown ends. "Hand every setting
  back to the bar" keeps the talent conditions.
- **Resource bars** — DoT bars: no bright line of the game world shows
  between the icon and the bar any more.
