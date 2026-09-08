# Backlog

- Offline tiles and tile caching.
- Geocoding search.
- Reading the wider slot configuration.
- Per-style memory of the Text and Buildings settings. One setting shared by
  all five styles is a statement about the screen, not about Liberty. What a
  style shows at a given zoom is mostly its own zoom-interpolated opacity and
  label collision, which the Buildings floor cannot reach, and beneath that the
  tiles have hard floors: buildings only exist from zoom 13, POIs from 11, road
  labels from 6.
- The vector source ends at zoom 14, so a close-up past that is magnified z14
  data rather than more detail.
- Report a source's TileJSON failure. A source that cannot fetch its TileJSON
  fires its error with a `sourceId`, so `main.jsx` treats it as a tile error and
  ignores it, leaving a blank map and a message only in the console. The Liberty
  style loads its vector source by TileJSON `url`, so this is the likeliest way
  to get a blank map with no explanation.
- Route a switch-time style-load failure to the toast instead of the blank-map
  message. A style that fetches successfully but fails to apply - an invalid
  body, or a failed sprite fetch - emits a bare error with no `tile` and no
  `sourceId`, so `main.jsx` classifies it as a style-load failure and blanks
  `#map`, taking the style control down with it. Fixing that means teaching
  the error handler which failures belong to a switch. A failed sprite fetch
  is worse than a blank map with no explanation: MapLibre fires styledata for
  it anyway (from the same chain's `.finally`), so `switchStyle` persists the
  id and moves the marked button a tick after the error handler has already
  blanked `#map` - `styledata` is not the event that would prevent that, since
  it fires whether or not the sprite fetch succeeded.
- A switch whose `setStyle` produces no styledata - an invalid style, or a
  diff that yields no operations - leaves `switchStyle`'s wait pending and
  its `map.once('styledata')` listener registered forever. The button and the
  stored id are silently left on whatever style was current before the click.
- Close the frame between `setStyle` and the styledata that moves the marked
  button. A click on the current style landing in that window takes
  `switchStyle`'s early return, does no `setStyle` of its own, and cancels the
  pending persist, leaving the new style drawn with the old button marked and
  the old id stored. It is about one frame wide and it is the one case where
  the control does not show the style that is actually displayed.
