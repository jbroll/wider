# Backlog

- Offline tiles and tile caching.
- Geocoding search.
- Reading the wider slot configuration.
- A control for how much the map draws when zoomed out, and per-style memory
  of such overrides. What a style shows at a given zoom is mostly its own
  zoom-interpolated opacity and label collision, which a zoom-range override
  cannot reach, and beneath that the tiles have hard floors: buildings only
  exist from zoom 13, POIs from 11, road labels from 6. Choosing a style that
  draws more is the lever that works.
- The vector source ends at zoom 14, so a close-up past that is magnified z14
  data rather than more detail.
- Report a source's TileJSON failure. A source that cannot fetch its TileJSON
  fires its error with a `sourceId`, so `main.jsx` treats it as a tile error and
  ignores it, leaving a blank map and a message only in the console. The Liberty
  style loads its vector source by TileJSON `url`, so this is the likeliest way
  to get a blank map with no explanation.
