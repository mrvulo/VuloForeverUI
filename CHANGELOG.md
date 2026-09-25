# Changelog

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
