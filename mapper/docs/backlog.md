# Backlog

- Offline tiles and tile caching.
- Geocoding search.
- Style switching.
- Reading the wider slot configuration.
- Report a source's TileJSON failure. A source that cannot fetch its TileJSON
  fires its error with a `sourceId`, so `main.jsx` treats it as a tile error and
  ignores it, leaving a blank map and a message only in the console. The Liberty
  style loads its vector source by TileJSON `url`, so this is the likeliest way
  to get a blank map with no explanation.
