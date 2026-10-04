## 0.11.0

**New**

- **Resource Bars** — a new XP bar tab. By default it lays itself over the
  game's own experience bar, which keeps its place, look and colours (blue
  while rested, purple otherwise). On top of it: the experience of quests
  ready to hand in and your rested stretch after the fill, your level on the
  left, the values in the middle, and the percent on the right with the
  finished quests counted in. Next to them, if you like: time to level and
  experience per hour, quest and rested share, time played on this level and
  this session. Texts that do not fit are cut short instead of overlapping.
  Can also be a free-standing bar of its own, placed with /vedit.
- **Auras** — temporary weapon enchants (weapon imbues, poisons, stones) show
  at the front of the buff row, as in the game's own row. Can be switched
  off.

**Changed**

- **Auras** — buffs and debuffs start next to the minimap, debuffs below the
  buffs. Left unmoved they follow the minimap; once dragged they stay, and
  Reset sends them back.
- **Bags** — the upgrade arrow looks at armour, stats and weapon damage first
  and only falls back to the item level when those disagree or are missing:
  a grey item with a higher item level no longer gets the arrow over better
  gear.

**Fixed**

- **Bags** — opening the bank no longer fails to claim the free first bank
  tab with an "AddOn tried to call a protected function" error.
- **Bags** — closing the game's Edit Mode no longer throws an error in the
  party frames after the bags or the bank had been used.
- **Chat** — no more blocked-action error when the chat tabs are built for
  the first time during a fight.
