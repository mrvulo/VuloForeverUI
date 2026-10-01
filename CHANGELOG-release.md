## 0.6.0

**New**

- **Quality of Life** — a Train all button next to Train at every trainer: it
  learns everything you can afford, one after the other. Learning a new
  profession stays your decision, and the pet trainer is left out.
- **Quality of Life** — zone levels on the world map: the level range of the
  zone in the top left corner, coloured like a quest of that level; on a
  continent, the zone under the cursor. The game gives no ranges on this
  client, so they come from a table of the original zones plus Riverglades and
  Mount Hyjal.
- **Quality of Life** — group invite on a whispered keyword (inv by default),
  Battle.net whispers included, optionally only for friends, guild and
  Battle.net friends.
- **Quality of Life** — decline duels, decline Battle.net friend requests, and
  block quests shared by strangers before the automatic accept can take them.
- **Auras** — right-clicking one of your own buffs removes it, as on the game's
  own buff row.
- **Resource bars** — spell cost: while a spell with a cast time is being cast,
  the power bar and the extra mana bar shade the part it will use, with its own
  switch, colour and opacity per bar.
- **Action bars** — Modern settings per bar, with a bar picker (action bars 1
  to 8, pet, stance), Apply to all bars and Reset this bar; the preview shows
  the icons and keybinds of the picked bar.
- **Action bars** — icons turn red when out of range, per bar, with a colour of
  your own, without covering the game's own tint for unusable and out of mana.

**Changed**

- **Unit frames** — on a new profile the Modern frames start where the game's
  frames stand instead of at fixed places. Existing profiles keep their layout
  exactly as it is.
- **Action bars** — Show bar background and Show end caps: the frame and
  dividers of action bar 1 and the figures at its ends can be hidden on their
  own. Not offered with the whole Classic bar.
- **Sidebar** — Quality of Life and Resource bars show their own icon.
- **Tooltip IDs** — ExpansionID is gone: on this client every item shows the
  same expansion.

**Fixed**

- **Damage meter** — in the Classic style the bars start clear of the frame, so
  the class icon and the first bar are no longer cut off.
- **Action bars** — the gold edge on the cooldown circle was never visible; pet
  and stance buttons stayed styled after their option was switched off; macro
  names lost their shadow on a style change; stance buttons showed keybinds;
  keybind texts when switching to a gamepad.
- **Tooltip IDs** — no longer shows a tooltip itself in the middle of the
  game's own tooltip setup.

This version brings new files: restart the game once, a /reload is not enough.
