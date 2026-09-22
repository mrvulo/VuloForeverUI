Icons live in Icons\, sorted by what they are for:

  Icons\ui\        the suite's own interface glyphs -- arrows, gear, lock,
                   eye, pin, reset, the Discord and Twitch marks, and vui4.tga,
                   which is both the minimap button and the addon-list icon
  Icons\modules\   one glyph per module, named after the module key; the
                   sidebar builds its paths from that name (UI\Sidebar.lua)

A texture is addressed by its full path, e.g.
Interface\AddOns\VuloForeverUI\Media\Icons\ui\vui4

A new or renamed texture file needs a FULL CLIENT RESTART: the client builds
its file index at startup, and /reload does not rebuild it.
