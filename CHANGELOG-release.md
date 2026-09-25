## 0.3.0

**New**

- **Trinkets** — a new tab under Quality of Life: two trinket slots on screen
  with their cooldowns. Left click uses the trinket, right click picks another
  from your bags, alt-click switches the slot's auto-queue, which puts the next
  ready trinket of your list on once the one in the slot is spent (out of
  combat). The order and the stop marker are set per slot, and the window can be
  unlocked and moved without Edit Mode.
- **Threat meter** — a new tab in the damage meter: the threat on your target
  for everyone in the group, one bar each, with an optional pull-aggro bar and a
  warning sound. A healer sees the threat on the mob the tank is fighting.
- **Damage meter** — a Classic window style in the original art, now the
  default for new profiles. Every meter window, the combat timer and the cast
  history have their own box in Edit Mode.
- **Bags** — a bag bar: a tool button shows your bags in a row. Hover lights up
  a bag's slots, a click shows that bag alone, and bags can be dragged in and
  out. Two new views: all bags as one block, and one block per bag.
- **Bags** — your own sort: stacks are merged first, then items go by category
  and quality, and vendor junk moves to the end. Grey items a vendor pays for
  are marked with an orange C.
- **Bags** — see your bank from anywhere: a window shows the bank as it was on
  your last visit, per character, grouped by tab.
- **Profile import** — nameplate and damage meter settings can be imported from
  another UI suite's profile string. Every setting that exists here is taken
  over; window places and sizes stay yours.
- **Game menu** — a VuloForeverUI button under Macros opens the settings.
- **Nameplates** — each aura group (buffs, debuffs, crowd control) can grow up,
  down, left or right, and has its own border size and colour.
- **Action bars** — the whole classic bar places every bar, and every bar and
  group on the band (micro menu, bags, experience bar, page arrows) can be moved
  on its own in Edit Mode. The settings page shows a live preview of your
  buttons in the chosen look.
- **Minimap** — the minimap and each of its text readouts have their own box in
  Edit Mode.
- **Resource bars** — a Text layer option draws a bar's text over or under the
  fill; the cast bar icon and time can be moved on their own in Edit Mode.
- **Chat** — the whole chat can be moved in Edit Mode. The Friends icon shows
  how many friends are online.
- **Flight time** — a route you fly for the first time gets an estimate from
  its length and your learned flight speed. The bar's font, size, text
  positions and border can be set.

**Changed**

- **Bags** — the client's bag windows no longer flash open for a moment. The
  tool buttons wear the game's own icon frames, and the settings button closes
  the settings again on a second click. Item slots have a flat look with a thin
  border in the item's quality colour.
- **Chat** — tab names sit centred in their tab (left is an option), switching
  tabs follows at once, and the combat log's filter row wears the tab style.
  The input line is part of the chat panel. The copy window lets you select
  just the part you want and shows Chinese, Korean and Russian text.
- **Unit frames** — the class icon on the Classic target portrait is on by
  default and sits centred in its ring.
- **Auras** — icons run to the left by default.
- **Action bars** — the Classic button look uses the full-size original frame
  with square icons.

**Fixed**

- **Bags** — a second click on the bag button no longer opens the client's
  bags, and after a login everything is no longer marked as just picked up.
- **Flight time** — the bar now appears when the flight starts, and its text
  is no longer drawn under the fill.
- **Trinkets** — clicking a slot no longer throws an error.
- **Nameplates** — "keep the bar's own colour" on the target texture no longer
  draws the texture white, and the client's own target highlight can no longer
  show through.
- **Chat** — new chat windows no longer keep the old input box, docked windows
  no longer draw their text over each other, and the chat can no longer come up
  empty.
- **Import boxes** — pasting a long string works, including when the paste
  does not arrive character by character.
- **Resource bars** — bar text is no longer drawn under the fill.
- **Action bars** — the experience bar no longer snaps back to the game's width,
  and switching back to Standard restores every button's slot art.
