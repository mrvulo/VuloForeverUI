## 0.25.1

**Changed**

- **Profiles** — a new look out of the box: nameplate colours and the cast
  target name under the cast bar, a "+ Combat" / "- Combat" alert, the
  priest's class display, time stamps in chat, and new places for bags,
  bank and the minimap buttons. Anything you set yourself stays as it is.
  The weapon enchant reminder for the main hand is now off by default.
- **Chat** — click a player name in one of the grey lines kept from the
  last session to whisper that player.

**Fixed**

- **Bags** — after a bank visit, buying a bank slot or using an item could
  be blocked as "forbidden" for the rest of the session.
- **Bags** — clicking a bank tab a second time changed the bags' default
  view, and the bank then only showed "Free" or one slot.
- **Bags** — renaming or removing the category that was the default view
  left the bags on a view that no longer existed.
- **Bags** — the bank view away from the bank kept the settings of the
  profile that was active when it was first built.
- **Bar Setups** — loading a setup cleared slots holding a mount, an
  equipment set or a pet, even on your own unchanged setup. Save older
  setups once more for this to take effect.
- **Resource bars** — the cast bar stopped early when a second spell key
  was pressed during a cast.
- **Chat** — after switching the module off and on again, no chat window
  scrolled with the mouse wheel until a reload.
- **Chat** — with the module off, "fade on mouse over" still faded the chat
  windows.
- **Quality of Life** — selling junk now checks at each step that the
  merchant is still open, so it can never use items after the window
  closed. Auto-open no longer puts containers into a trade, the auction
  house or the guild bank instead of opening them.
- **Quality of Life** — the gold check no longer throws an error with no
  income data, and its mail panel goes away at once when it is switched
  off.
- **Profiles** — switching profiles by key binding was undone by the reload
  it offers. Importing only part of a full profile string now gives the
  left-out modules the exporter's defaults.
- **Edit Mode** — "Discard" lost the gap of docked frames. "Reset" and
  "Discard" no longer stay open when a fight closes the mode.
- **Options** — a locked slider could still be changed with +/- or the
  number field, and locks now follow their switch at once. "Reset module"
  on a sub-module's tab reset the wrong module. The colour picker writes to
  the row that opened it.
- **Action bars** — the range tint came back after it was switched off.
- **Cooldown Manager** — proc glows also show for another rank of the same
  spell.
- **Damage meter** — searching in the options showed every meter window;
  switching the module off only turns the game's own meter back on if it
  was on before.
- **Auras** — a setting changed during a fight is applied after it.
- **Nameplates** — aura rows follow a unit that changes sides in a duel.
- **Minimap** — the difficulty short name no longer cuts Cyrillic names in
  the middle of a letter.
