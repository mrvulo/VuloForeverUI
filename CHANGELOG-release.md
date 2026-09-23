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
