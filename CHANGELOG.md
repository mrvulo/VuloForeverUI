# Changelog

## 0.12.0

**New**

- **Locales** — the suite now speaks French, Spanish (Spain and Latin
  America), Russian and Brazilian Portuguese besides English and German. Auto
  follows your game client; the language page lets you pick one.
- **Bags** — a Style choice: Modern is the flat window as before; Standard
  dresses the same window in the game's own bag look, with its frame, title
  bar, bag portrait, close button, slot art and quality rings. Search,
  categories, marks and the bank work the same in both.
- **Action Bars** — newly learned spell ranks take the place of your previous
  highest rank on the action bars. Lower ranks you placed on purpose stay.
- **Global Settings** — a font for the damage numbers the game floats over
  your target (damage, heals, misses), e.g. Expressway. Applies after you log
  out and back in.
- **Resource Bars** — the three texts of the XP bar can each be shifted left
  or right.

**Changed**

- **Bags** — the search box is easier to find: a magnifier, a grey "Search"
  placeholder, a visible edge that turns gold while you type.
- **Action Bars** — on the classic bar, the bars above the band sit a little
  higher so the experience bar's texts stay readable; a slider sets how far.

**Fixed**

- **Action Bars** — the free bag slot count on the backpack no longer counts
  quivers, ammo pouches or profession bags, so full bags read 0.
- **Quality of Life** — one-click looting no longer flashes the loot window.

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

## 0.10.0

**New**

- **Bags** — the search box understands more than names: #keywords in
  English or German for quality (#blue, #epic), binding (#boe, #soulbound,
  #warbound), item type (#weapon, #armor, #consumable, #recipe, #quest) and
  marks (#new, #pinned, #set, #junk, #upgrade, #cooldown). Any other #word
  matches the game's own type, subtype and slot names in your language
  (#potion, #cloth, #head). Numbers filter gear by item level (>30, <=50,
  20-40). Words next to each other must all fit, | means either, ! means
  not. Hover the search box for the list.
- **Bags** — your own categories: a new Categories tab where each category is
  a name and a search, e.g. "Upgrades" for #upgrade. They come first in the bag
  window, in your order, and show in the side bar and as a bag view.
- **Bags** — items you cannot use where you stand are faded: at a merchant
  what it pays nothing for, at the mailbox, a trade or the auction house
  everything soulbound. Can be switched off.
- **Bags** — upgrade arrows: a green arrow on gear with a higher item level
  than what you wear in that slot, if this character can wear it now.
- **Bags** — icon corners: item level, pin, upgrade arrow, BoE / warbound,
  set name and the junk C each get a corner of your choice; marks in the same
  corner sit side by side.

**Changed**

- **Bags** — the "new item" border goes away as soon as the mouse has been
  over the item, and otherwise after a time you set (5 minutes by default,
  was half an hour).
- **Bags** — the free slots read "17/52" for your normal bags, with the
  profession bags apart in their own colour ("5/12"). The count no longer
  appears twice in the "all bags" view, and per bag it counts free of total
  as well.

**Fixed**

- **Bags** — using an item from a stack, splitting, merging or sorting no
  longer marks the stack as new.

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

## 0.8.0

**New**

- **Quality of Life** — a Gold tab. Track the gold of the day: earned, spent,
  what is left and the balance under the money line of the bags, kept through
  a reload and a relog. Check a trade partner's gold: beside the trade window,
  the most gold they ever owned against everything they ever earned
  themselves; the same check beside a mail with gold.
- **Quality of Life** — a Quest tab. On the minimap a yellow ! for the quests
  the game offers in this zone and a yellow ? where a finished quest is handed
  in; quest progress on the tooltip of items a quest asks for; quest levels in
  the tracker and at quest givers, an elite quest with a +.
- **Quality of Life** — quest sounds for objective progress, a finished
  objective and a quest ready to hand in, each with its own choice; Tell the
  party sends quest progress to party chat (off by default).
- **Bags** — the bank gets its own row of bank tabs: the icon of the bag in
  each tab, its tooltip, bags dragged in, out or swapped, empty bought slots,
  and the slots still for sale with their price; a click buys the next one
  through the game's own purchase dialog.
- **Bags** — Mark profession bag slots: slots in a herb, enchanting, mining or
  other profession bag are tinted in that bag's colour. On by default.
- **Bags** — Rounded slots: icons, borders and empty slots get rounded
  corners. On by default.
- **Auras** — No dispel type: debuffs without a dispel type get their own
  border colour, red by default.

**Changed**

- **Bags** — the close button of the bags and the bank is a dark box with a
  red cross.
- **Action bars** — Free bag slots on the backpack now also shows with the
  game's own bag bar, not only with the Classic band.
- **Nameplates** — the cast bar sits 4 pixels lower by default.

**Fixed**

- **Auras** — borders and dispel strips are pixel exact, all four sides the
  same width, also after moving or scaling.
- **Action bars** — the free bag slot number could end up hidden under the
  ring of the backpack button.

This version brings new files: restart the game once, a /reload is not enough.

## 0.7.0

**New**

- **Quality of Life** — the flight bar shows the route below it, every stop
  with the time until it, and moves on as a stop goes by. A button next to it
  lands at the next stop; it fades on the last leg. A /reload in mid-flight
  keeps destination, time and stops. Flight bar, route and button are on by
  default.
- **Action bars** — Shamans can show the game's totem bar in the Classic stone
  band, in the small row behind the stance and pet bars, and move it in our
  Edit Mode (off by default).
- **Minimap** — a size slider for the queue eye, and the eye can be moved in
  our Edit Mode.
- **Chat** — Glow on tabs with unread messages: a tab you are not on glows
  softly while the game would make it flash (a whisper, or a channel the
  window alerts for). On by default.
- **Nameplates** — Quest progress instead of the marker (3/8, 40%) under
  General, Extras; Enemy types in instances only, so outside dungeons grey
  means one thing: tagged by someone else; Border in the bar's color.

**Changed**

- **Nameplates** — a new default look: a wider and taller bar with the name on
  the left and health as value and percent on the right, a black border, a
  white border on your target instead of a glow, other plates at 70 percent,
  new colours, cast bar and icon places.
- **Nameplates** — with Show All Debuffs off, only your own debuffs (and your
  pet's) are shown. Side aura rows grow away from the bar instead of upwards.
  Aura icons are zoomed in a little and carry a sharp border inside the icon.
- **Nameplates** — the execute glow is always red, without a colour setting.
- **Nameplates** — the profile import now also takes text places, icon places,
  aura groups and aura texts, the low health glow and the quest progress.
- **Nameplates** — the spell target in the settings preview can be clicked.

**Fixed**

- **Nameplates** — the quest marker disappears once nothing is left to do for
  that mob, and shows up sooner when the game fills in a mob's details.
- **Nameplates** — the execute glow did not show.
- **Nameplates** — Spell Target: first name only works in combat too; there
  the first name of the caster's own target is shown.
- **Nameplates** — the target's and the hover border no longer run around the
  cast bar.
- **Damage meter** — the window sits above the quest tracker instead of below
  it.
- **Resource bars** — spell icon and cast time on the cast bar disappear
  together with the game's bar; a failed second spell or a settings change no
  longer freezes the time mid-cast.

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

## 0.5.0

**New**

- **Tooltip IDs** — a new module under General: spell, item, NPC, quest,
  currency, mount, pet, macro, icon, talent, map point and appearance IDs in
  tooltips. All 23 ID types can be switched one by one, with All on, All off
  and Defaults. On request the IDs only show while Shift, Ctrl or Alt is held,
  and pressing the key over an open tooltip adds them at once. IDs the game
  keeps hidden in combat are left out. Buff tooltips on the aura bars cannot
  carry IDs on this client: the game does not let addons write into them.

**Changed**

- **Action bars** — the Modern style is rebuilt: square icons across the whole
  button with a trimmed rim, a dark ground behind them, a thin border inside
  the button, a soft pale gold glow along the inner edge on press and hover, a
  white glow on the spell being cast and a gold edge on the cooldown sweep.
  Keybind, charges, macro name and countdown use Expressway with an outline,
  and keybinds are shortened (SHIFT-BUTTON4 reads SM4).
- **Action bars** — new settings while Modern is picked: border size, colour
  and class colour, icon zoom, icon background with opacity and colour,
  cooldown numbers, interaction colour and class colour, press and hover look
  in five steps, highlight on spell cast, size and position of every text, and
  keybind and macro name can be hidden.
- **Action bars** — the style menu now simply reads Standard, Classic and
  Modern.
- **Global Settings** — the Show IDs in Tooltips switch under Developer is
  gone. It never worked; Tooltip IDs is now switched from its sidebar row like
  every module.

This version brings new texture files: restart the game once, a /reload is
not enough.

## 0.4.0

**New**

- **Unit frames** — the Modern style can now show focus, target of target,
  focus target, pet and up to five boss frames in a column. Each unit is
  switched on by itself (all off by default), and every frame can be grabbed in
  Edit Mode even when its unit is not there.
- **Live previews** — the unit frame, nameplate, action bar, cooldown bar,
  reminder, aura and resource bar settings show a live preview pinned above the
  page, at the size it has on screen. A click on a part of it jumps to the
  setting that owns it. The unit frame page picks its unit and the cooldown
  bar page its bar right above the preview.
- **Reminders** — a new module under General: missing buffs of your own and
  weapon enchants as clickable icons. It remembers the last poison or oil used
  on each weapon, watches the campfire buff and spell IDs you add, hides in
  combat, and a middle click hides an icon until the next loading screen.
- **Window styles** — five looks for the settings window on the Styles tab of
  Global Settings: Vulo, Blizzard classic, Blizzard modern, Flat with class
  colour and Pixel. The style changes at once, without a reload. Blizzard classic is the
  new default.
- **Edit Mode** — every window has its own opacity in and out of combat, at
  full strength under the mouse. Layouts also save chat, minimap, action bars
  and the damage meter, and the player, target, focus, target of target and
  quest tracker frames can be moved.
- **Mail** — an arrow next to the recipient box lists your characters, the
  characters you know and your last recipients. It shows every character of
  the account on this realm, including ones you have not logged in since
  installing.
- **Nameplates** — an option to show only the first name of a cast's target.
  The icon size of each aura group is set right in its gear.
- **Auras** — a tooltip when hovering your own buff and debuff rows, and a
  choice of cooldown swipe: reversed, normal or off.
- **Action bars** — the classic band writes the number of free bag slots on
  the backpack button.
- **Cooldown manager** — a left click on an icon in the preview opens that
  spell's settings as a menu under the icon.
- **Resource bars** — the frame of the client's own cast bar can be hidden in
  the Standard and Classic styles.
- **Info bars** — VuloForeverUI as an entry: left click opens the settings,
  right click the module list.

**Changed**

- **Damage meter** — the Classic style wears Blizzard's metal window frame over
  the rock background, with the title in gold.
- **Nameplates** — friendly player plates are off by default; the plain name
  over friendly players stays where the game puts it. Enemies tagged by another
  player turn grey at once, from their first hit, and aura borders stay sharp
  at a small interface scale.
- **Bags** — your own sort has a choice of order and can sort from the bottom.
  Special bags come first and only get what they take, a bag the server
  refuses an item for is remembered, and the window redraws once at the end
  instead of at every move.
- **Class colours** — your own class colours now reach the unit frames, the
  damage meter and the cooldown bars too.

**Fixed**

- **Nameplates** — the quest mark no longer disappears in combat once a kill
  counts for the quest, and it goes away as soon as the quest is complete.
- **Action bars** — the bag buttons and the key ring stay in place while items
  are picked up, put down or sorted. The Standard style no longer draws a slot
  of its own under bar 1, and the preview no longer fills the error log with
  warnings about a missing frame.
- **Bags** — a saved view that no longer exists opens the window on All.
- **Mail** — the Unknown entry under My characters is gone.

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

## 0.2.1

**Changed**

- **Minimap** — the minimap button's menu no longer offers to switch off the
  minimap module itself, which left the button stranded until a reload.

**Fixed**

- **Damage meter** — clicking a row during a fight no longer throws an error
  on every update, and neither does opening the death breakdown of someone
  killed by melee or a fall. Windows shown in combat only now hide once the
  group is out of the fight.
- **Minimap** — going back to the Standard look, or switching the module off,
  now puts every piece back: zoom buttons, tracking, clock, calendar, the queue
  eye and the Edit Mode size. The map no longer jumps back to its old spot after
  a zone change when it was moved in Edit Mode. Mouse-wheel zoom comes back when
  the module is off, hidden zoom buttons stay hidden on hover, the minimap
  button sits on the ring of the Classic look, and the zone colour by PvP
  status works.
- **Action bars** — the Classic bar now finds the client's main bar, so the page
  arrows, hiding the stock art and switching back work. Keep page can be
  switched off again, logging in during a fight no longer turns it off for
  good, and switching the module off during a fight now takes effect afterwards.
- **Cooldown manager** — bars no longer appear while the module is off, a proc
  glow no longer stays on an icon that now shows another spell, and bars set up
  per specialisation now actually follow the specialisation.
- **Unit frames** — the target frame no longer shows aggro on an enemy that has
  not touched you, and switching the module off during a fight finishes once the
  fight ends.
- **Resource bars** — with the module off, the player has a cast bar again, and
  the settings page no longer brings back bars of a switched-off module. The
  power threshold colour no longer risks an error in combat.
- **Nameplates** — "Interrupted" no longer sticks on a cast bar, and changes to
  the aura count and filters reach every plate.
- **Bags** — from the second bank visit on, an invisible bank window no longer
  sits on the left taking clicks. Bank tabs seven to nine show up, turning off
  the bank takeover gives the client's bank back, and the split mode no longer
  blocks every slot when its tool is switched off.
- **Quality of Life** — combat messages stop when the module is off, the repair
  line works without the durability warning, and the stack split window is left
  alone when the module is off.
- **Chat** — the mouse wheel and the scroll bar move the chat you see.

## 0.2.0

**New**

- **Locales** — a page of its own for the language the suite speaks: the game
  client's own, English or German. Only the languages that actually ship are
  offered.
- **Quality of Life / General** — the answers you would otherwise click: accept
  and hand in quests, take a resurrection or a summon (never mid-fight), release
  in battlegrounds and arenas, pick a single NPC dialogue option, and block
  group invites or trades from anyone who is not a friend, a guild member or one
  of your Battle.net friends.
- **Flight time** — a bar that measures a route the first time you fly it and
  counts the next one down. The times are remembered account-wide.
- **Mail** — the last twelve people you sent mail to, one click away from the
  name field.
- **Splitting a stack** — a button that takes the whole stack, and the suite's
  look on the client's own split window.
- **Combat line** — it now also says when a cast is interrupted, when something
  is reflected, when a hit is dodged, parried or missed, when someone in your
  group dies, and an early word when your gear is wearing out.
- **Chat** — the sidebar, the tabs and the input line can be set up.
- **Live previews** you can touch for nameplates, bags, the bank and the
  cooldown bars.

**Changed**

- German is complete. Every label, message and tooltip in the suite now has a
  German entry, and the interface terms follow the game's own wording.
- The cooldown preview draws its icons smaller and puts the plus button in the
  row, right next to the last icon.
- Quality of Life is sorted differently: General comes first, the durability
  warning moved to Display, and the Stats tab is gone.
- The General group sits above HUD in the sidebar.

**Fixed**

- A settings row that ended up alone in its group was drawn across the whole
  page instead of keeping its column.
