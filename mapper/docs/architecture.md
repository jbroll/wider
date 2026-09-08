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

`src/view.js`, `src/places.js` and `src/tweaks.js` take a `localStorage`-shaped
store as an argument instead of reading the global directly. That is what lets
them run under `node --test` without a browser. `src/store.js` wraps
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
button.

Startup no longer passes MapLibre a style URL. `main.jsx` fetches the style
JSON itself, runs it through `applyTweaks`, and constructs the map from the
resulting object, because MapLibre's `transformStyle` hook exists only on
`setStyle` and not on the map constructor. The fetch carries a 15 second
timeout, so a hung request reaches the failure message instead of leaving an
empty window. A failed startup fetch shows the style-load message directly; a
body MapLibre rejects still reaches `map.on('error')`, because the map is
constructed through the validating path.

`styles.jsx` holds the style as fetched, untransformed, so moving a stepper or
a color picker re-transforms that held object rather than refetching. Two
transforms compose over it, `applyColors` over `applyTweaks`, in both places a
style is applied: `main.jsx` at startup and `styles.jsx` on a switch or a
control move. Both return a new style for the same reason: the held object is
transformed repeatedly, and a mutating transform would compound scale on scale.
Each reads its own values at the moment it applies rather than when the click
happened, so a control moved during an in-flight switch is carried by that
switch when it lands.

The colors live in their own `mapper.colors` key rather than joining
`mapper.tweaks` because they fall back differently. A malformed field in
`mapper.tweaks` resets the whole document, which suits two coupled notches and
does not suit four independent colors; in `mapper.colors` a bad color falls
back on its own group. Separate keys also mean a malformed color cannot reset
the text size.

`colors.js` stays pure and store-argument-taking like the other four modules,
and never converts a color: it writes only the `#rgb` or `#rrggbb` the user
picked. Seeding an unset swatch from the current style does need a conversion,
because the styles write their colors as `#666`, `hsl(...)` and `rgba(...)`
while `<input type="color">` takes only `#rrggbb`. That code assigns the string
to a detached element's `style.color` and reads `getComputedStyle` back, which
the browser normalises to `rgb(r, g, b)`. It needs a DOM, so it lives in
`colors.jsx` and Playwright covers it rather than `node --test`.

The toast host is appended to `document.body`, not into `#map`, so it
survives `#map` being blanked by the style-load failure message. `#toast` is
always in the document and carries `hidden` when there is no message, so its
`aria-live` region exists before the text lands in it. A test asserting the
toast is absent wants `toBeHidden()`, not `toHaveCount(0)`.

## Why openfreemap

The styles come from `https://tiles.openfreemap.org/styles/`: vector tiles,
no API key, whole-planet coverage, and labels that stay upright under
rotation. Liberty is the default. OpenFreeMap's site also names a "3D"
style, but `/styles/3d` is a 404, so mapper offers the five that answer.
