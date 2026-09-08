# Architecture

## Launch

`mapper` (a shell script) builds `dist/index.html` if missing, starts
`serve.js` on its fixed port (8737 by default, or `MAPPER_PORT` when set),
reads the port back from its stdout through a fifo, then launches Chromium
with `--app`, `--class=Mapper`, and a private `--user-data-dir`. Its exit
trap kills the server. `--class=Mapper` is the `WM_CLASS` wider matches a
slot against.

A fixed port keeps `localStorage` on one origin across launches, which is
what lets the saved view and places persist. If the port is already taken,
by another mapper instance or something else, `serve.js` exits without
printing a port and the launcher stops with an error instead of opening a
window onto a dead server.

`serve.js` also watches its own parent pid and exits if it changes, so a
launcher that is killed outright (bypassing the trap) does not leave the
server running forever.

## Build

`build.js` bundles `src/style.css` and `src/main.jsx` with esbuild and
substitutes both into the `src/index.html` template, replacing the
`/*CSS*/` and `/*JS*/` placeholders, then writes the result to
`dist/index.html`. That file is a single document with no external script
or stylesheet references, so `serve.js` needs no static directory, just
that one file.

## UI

MapLibre owns the map canvas directly (`src/map.js`), which is why `map.js`
is a plain function rather than a component. Preact renders the places
panel (`src/places.jsx`) and the style control and toast (`src/styles.jsx`).

`src/view.js` and `src/places.js` take a `localStorage`-shaped store as an
argument instead of reading the global directly. That is what lets them
run under `node --test` without a browser. `src/store.js` wraps
`window.localStorage` so a thrown access (a browser policy blocking site
data, or a quota error) yields a no-op store instead of crashing the page;
`main.jsx` and `places.jsx` pass that wrapper where a store is needed.

`window.mapper.map` exposes the MapLibre map instance for the Playwright
specs and for poking at from a browser console.

`src/styles.js` holds the style table and the stored-id validation, pure
and store-argument-taking like `view.js` and `places.js`. `src/styles.jsx`
is a MapLibre custom control: MapLibre decides where it sits in the
`top-right` stack and gives it `.maplibregl-ctrl-group`, and Preact renders
the buttons into the element `onAdd` returns.

A switch fetches the style JSON and only then calls `map.setStyle` with the
parsed object. A failed fetch never reaches `setStyle`, so the running map
stays up and the stored id and the marked button stay on the style that is
actually drawn. The switch does not count as done at `setStyle` either: it
waits for MapLibre's `styledata` event. That event is not a load
confirmation - it is the "style changed" tick MapLibre fires once
`Style.setState` accepts the body, on the next render frame. What the wait
actually buys is narrower: a style body MapLibre rejects as invalid never
fires styledata, so it never gets persisted and never moves the marked
button. Startup still passes
MapLibre a style URL, which keeps a launch-time failure on the existing
`map.on('error')` path.

The toast host is appended to `document.body`, not into `#map`, so it
survives `#map` being blanked by the style-load failure message.

## Why openfreemap

The styles come from `https://tiles.openfreemap.org/styles/`: vector tiles,
no API key, whole-planet coverage, and labels that stay upright under
rotation. Liberty is the default. OpenFreeMap's site also names a "3D"
style, but `/styles/3d` is a 404, so mapper offers the five that answer.
