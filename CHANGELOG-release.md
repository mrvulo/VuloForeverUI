## 0.13.0

**New**

- **Reminders** — a "Show possible buffs" button opens a list of every buff
  you could have right now: your own class buffs, buffs other classes give,
  world buffs from level 55, and the best flask, elixir, food, scroll,
  potion, poison, sharpening stone, weightstone or oil for your role and
  level. Each line shows whether it is on you and for how long, and whether
  the item is in your bags. Pick your role at the top of the window.
- **Bags** — items that start a quest carry the game's yellow "!" until you
  take the quest.
- **Cooldown Manager** — queued next-swing abilities (Heroic Strike, Cleave,
  Maul, Raptor Strike) light up like their action bar button.
- **Resource Bars** — XP per hour and time to level follow your pace over
  the last 15 minutes instead of the whole session.
- **Nameplates** — "All of your own debuffs" (on by default) shows every
  debuff you or your pet cast, also the many classic damage-over-time spells
  the game does not mark for nameplates.

**Changed**

- **Bags** — the category bar folds in and out with its arrow, has uniform
  square icons (a new category shows its first item), and nothing in the
  window touches the frame or the slots any more.
- **Bags** — profession and reagent bags tint their slots in both styles; a
  leather reagent bag is leatherworking brown. "Rounded slots" now works in
  the Standard style too, and the bank view away from the bank uses the
  Standard look as well.
- **Bags** — the window is prepared in the background after a loading
  screen, so the first open of a session no longer stutters, and the bags
  make far less garbage memory.
- **Chat** — "Copy chat" shows the text like the chat itself, every alphabet
  at once, and Ctrl+C copies everything; "Select text" lets you pick a part.
- **Locales** — module, group and tab names are translated in every language.

**Fixed**

- **Bags** — the tooltip no longer blinks off while you hover an item.
- **Bags** — the stuck "You received a reagent bag" tip box is hidden.
- **Bags** — the reagent bag counts as its own number next to the free slots
  again.
- **Bags** — opening and closing the bags no longer leads to blocked-action
  errors at the bank or after Edit Mode.
