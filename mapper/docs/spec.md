# Specification

What mapper does, in one document: the whole feature set with its exact values,
bounds, and failure behavior. It describes what is built, not what is intended,
so anything listed here is implemented and anything absent is not. The user
manual covers the same features for someone using them; `architecture.md`
covers why they are built the way they are.

## 1. Product

A chromeless desktop OpenStreetMap window for X11 Linux. It runs as a Chromium
`--app` window with `WM_CLASS` `Mapper`, so wider can place it in a slot like
any other application. The whole UI is one page: a MapLibre GL map, a places
panel at the top left, a style control in MapLibre's top-right control stack,
and a toast at the bottom.

Version `0.1.0`, private (unpublished) npm package.

## 2. Runtime and dependencies

| Requirement | Value |
|---|---|
| Node | 22 or newer |
| Browser | `chromium` on `PATH` |
| Display | X11 |
| Map renderer | maplibre-gl ^5.0.0 |
| UI | preact ^10.29.8, @preact/signals ^1.3.4 |
| Bundler | esbuild ^0.24.0 |
| Test | @playwright/test ^1.49.0, `node --test` |

Network services, both external to the project:

- Map styles and vector tiles: `https://tiles.openfreemap.org/styles/<id>`.
  No API key.
- Walking routes: a self-hosted OpenRouteService at
  `http://192.168.1.169:8082/ors`, hardcoded in `src/route.js`.

## 3. Process model

`mapper` (POSIX shell) does the following, in order:

1. Resolves node: `PATH` first, then the newest `node` under `$NVM_DIR`,
   `~/.nvm`, or `~/.config/nvm`. A desktop or autostart launch has no login
   shell, so `PATH` alone is not enough. Exits with an error if none is found.
2. Builds `dist/index.html` by running `build.js` if the file is missing.
3. Starts `serve.js` with its stdout on a fifo and reads the port back from it.
   No port on the fifo is a fatal error with a diagnostic naming the likely
   causes.
4. Launches `chromium --app=http://127.0.0.1:<port> --class=Mapper
   --user-data-dir=$HOME/.config/mapper/chrome`.
5. On `EXIT`, `INT`, or `TERM`, kills the server and removes the fifo.

`serve.js` binds `127.0.0.1` on port `8737`, or `$MAPPER_PORT` when set. It
serves the single in-memory `dist/index.html` at `/` with
`Cache-Control: no-store` and returns 404 for every other path. On `EADDRINUSE`
it prints a message and exits 1. It polls its own `ppid` every second and exits
if the parent changes, so a launcher killed outright does not orphan it.

The port is fixed rather than ephemeral because `localStorage` is keyed by
origin, and all persistence depends on the origin being stable across launches.

Only one instance is supported. A second launch on a different `MAPPER_PORT`
starts its own server, but Chromium's profile singleton hands the URL to the
running Chromium instead of opening a new process; the second launcher then
exits and its trap kills the server backing the tab that was just opened.

## 4. Build

`build.js` bundles `src/style.css` and `src/main.jsx` with esbuild
(`iife`, `es2022`, minified, `legalComments: 'none'`, automatic JSX with
`jsxImportSource: 'preact'`, `.svg`/`.png` as data URLs) and substitutes the
two results into the `/*CSS*/` and `/*JS*/` placeholders in `src/index.html`.
Output is `dist/index.html`: one document with no external script or stylesheet
references.

`buildHtml()` is exported so tests can build without writing to disk.

## 5. Persistence

Four `localStorage` keys, each with its own pure module that takes a
store-shaped object as an argument rather than reading the global. `src/store.js`
wraps `window.localStorage` in try/catch so a blocked or full store degrades to
a no-op instead of crashing the page.

| Key | Module | Shape | Fallback on missing or invalid |
|---|---|---|---|
| `mapper.view` | `view.js` | `{center:[lon,lat], zoom, bearing, pitch}` | zoom 3.5 at `[-98.5795, 39.8283]`, bearing 0, pitch 0 |
| `mapper.style` | `styles.js` | one of the five style ids | `liberty` |
| `mapper.tweaks` | `tweaks.js` | `{textScale, buildingMinZoom}` | `{1, 13}`, whole document on any bad field |
| `mapper.colors` | `colors.js` | `{places, streets, pois, water}` | per group; a bad color resets only its own group |
| `mapper.places` | `places.js` | array of place objects | `[]`; invalid entries dropped individually |

Validation bounds: longitude ±180, latitude ±90, zoom 0–24, pitch 0–85,
bearing normalised into 0–360. A place needs a non-empty string `id`, a string
`name`, and valid `lat`, `lon`, `zoom`, `bearing`.

The current route is deliberately not persisted. `route.js` and `route.jsx`
never touch `localStorage`, so a reload starts with nothing selected.

## 6. Map and navigation

- Pan: left-drag. Zoom: wheel. Rotate and tilt: right-drag or ctrl-drag.
- MapLibre `NavigationControl` in `top-right` with compass and pitch
  visualisation. The compass button resets bearing and pitch to 0.
- Compact attribution control.
- The view is written to `mapper.view` on `moveend`, debounced 300 ms.
- `window.mapper.map` exposes the MapLibre instance for the Playwright specs
  and for console use.

## 7. Map styles

Five styles from OpenFreeMap, rendered as a button group at the top of the
style control: Liberty, Bright, Positron, Dark, Fiord. The current one carries
`.current` and `aria-pressed="true"`. OpenFreeMap also names a "3D" style, but
`/styles/3d` returns 404, so it is not offered.

Switching fetches the style JSON first and only then calls `map.setStyle` with
the parsed object, so a failed fetch leaves the running map untouched and shows
a toast instead. The switch is not considered done at `setStyle` either: it
waits for MapLibre's `styledata` before persisting the id and moving the marked
button. An in-flight switch is tracked by a token, so a later click wins.

Startup does not hand MapLibre a style URL. `main.jsx` fetches the JSON itself
with a 15 second timeout, transforms it, and constructs the map from the
resulting object, because MapLibre's `transformStyle` hook exists only on
`setStyle`.

### 7.1 Style transform chain

Three pure transforms compose over the style as fetched, in this order, at both
places a style is applied (`main.jsx` at startup and `styles.jsx`'s `transform`
closure):

```
applyRoute(applyColors(applyTweaks(style, tweaks), colors), route)
```

Each returns a new style rather than mutating. `styles.jsx` holds the untransformed
fetched style in a module-private `fetched`, so moving a control re-transforms
that held object instead of refetching, and each transform reads its values at
apply time rather than at click time. Every one of these transforms must be part
of the style body: `map.setStyle` destroys anything added outside it.

### 7.2 Text and Buildings steppers

Two steppers below the style buttons, each a `−`/value/`+` row with the end
button disabled at the end of its range.

- **Text**: eleven notches, 100% to 200% in ten-point steps. Multiplies
  `text-size` on every symbol layer. A numeric size is scaled directly; a flat
  `["interpolate", ["linear"], ["zoom"], …]` has its outputs (even indexes from
  4 up) scaled; anything else is left alone. The scale is also written to the
  `--text-scale` CSS custom property so the saved-place markers grow with the
  labels, since they are DOM overlays the style transform cannot reach.
- **Buildings**: notches 13, 14, 15, 16, Off. Sets the minimum zoom on every
  layer with `source-layer: building`. Off drops those layers entirely. 13 is
  the default because the tiles carry no building data below it.

Both write `mapper.tweaks` and apply to whichever style is showing.

### 7.3 Label color pickers

Four `<input type="color">` rows, each with a `×` clear button that is disabled
while the group is unset.

| Group | Source layers |
|---|---|
| Places | `place` |
| Streets | `transportation_name` |
| POIs | `poi`, `aerodrome_label` |
| Water | `water_name`, `waterway` |

Setting a color rewrites `text-color` on every symbol layer in that group that
already declares a `text-color`, and sets `text-halo-color` to white or black
by WCAG relative luminance (threshold 0.5). A layer with no `text-halo-width`
gets 1, since MapLibre's default halo width is 0. Symbol layers without a
`text-color` draw no text of their own and are skipped, which is what excludes
the route shields.

An unset swatch is seeded from what the current style paints that group.
Because styles write colors as `#666`, `hsl(...)` and `rgba(...)` while the
input takes only `#rrggbb`, `toHex` assigns the string to a throwaway element
and reads `getComputedStyle` back. Seeding runs on the fetched style before
`setStyle`, and only `#rgb`/`#rrggbb` is ever written to the store.

The picker fires `input` continuously while its dialog is open. `onPreview`
runs on every `input`, sets the signal eagerly, and coalesces the map update to
one `requestAnimationFrame`; `onCommit` runs once on `change` or on the clear
click and is the only path that writes `mapper.colors`. A commit cancels any
pending preview frame.

Coverage differs by style: Dark and Fiord carry no POIs, and only Liberty,
Bright and Positron name airports. A picker for a group the current style does
not draw still works and is still remembered.

Colors live in their own key rather than joining `mapper.tweaks` because they
fall back per group where the tweaks fall back as a document.

## 8. Saved places

Right-click the map to drop a pin and open a name field. Enter saves, Escape
discards. An empty name saves as `Unnamed`. A place records `id`, `name`,
`lat`, `lon`, and the `zoom` and `bearing` at the moment the pin was dropped.
Ids are `'p' + base36 time + 6 random base36 chars`.

The panel at the top left has a header button `▾ Places (N)` that collapses and
expands the list. Each row carries, left to right: a `⠿` drag handle, a route
checkbox, an order badge, the name as a button, and a `×` delete button.

- Clicking the name flies the map to the saved center, zoom, and bearing.
- `×` deletes the place and removes its marker.
- Rows reorder by native HTML5 drag-and-drop. A drop on a row inserts before
  it; a drop anywhere else in the list, including the trailing `.place-dropzone`
  element, appends. The new order is saved immediately.

Every place also gets a map marker: a plain `maplibregl.Marker({ draggable: true })`
with no custom element, so it is the same pin as the pending right-click pin and
MapLibre's own anchor math puts the tip on the coordinate. The name label is
appended to the marker's element, absolutely positioned and `pointer-events: none`,
so it adds no layout weight and never steals the drag or the click. Clicking a
pin flies to the place; dragging one moves it, taking the same `movePlace` and
`commit` path a panel edit takes. MapLibre suppresses the marker's click during
a drag, so a drag does not also fly the map.

Markers are DOM overlays rather than style layers, so they survive a style
switch without being re-added. `places.jsx` reconciles the marker set in an
effect keyed by place id, diffing by `lat`/`lon`/`name` because `savePlaces`
rebuilds every object on commit.

## 9. Walking routes

Checking two or more places draws a walking route through them in **list
order**, not tick order, and each checked row shows its 1-based position.
Dragging a row reorders the route with the list.

- Profile `foot-walking`, `POST` to `<base>/v2/directions/foot-walking/geojson`
  with `{coordinates: [[lon, lat], …]}`.
- The route redraws automatically on any selection or list change, debounced
  300 ms, so a run of clicks or a drag sends one request. A token guards
  against a stale response overwriting a newer selection.
- Drawn as a `line` layer, `#4285f4`, width 7, opacity 0.95, with
  `line-cap: round` and `line-dasharray: [0, 2]`, which renders as evenly
  spaced round dots. A `circle` layer was rejected because circles land on the
  LineString's vertices, which ORS spaces by road geometry.
- Distance and duration show below the panel, with a Clear button. Distance is
  metres under 1 km and one decimal of km above; duration is whole minutes,
  minimum 1.
- Dropping below two checked places clears the route. Deleting a checked place
  prunes the selection and re-routes through what remains, clearing only if
  fewer than two are left.
- Setting or clearing a route calls `reapplyStyle`, so the route is re-derived
  from the held style on every later switch, stepper move, or color commit.

Coverage is limited to what the self-hosted ORS instance carries: walking only,
Schenectady, New York area only, and only from the local network.

## 10. Errors surfaced to the user

| Condition | Behavior |
|---|---|
| No WebGL context | `#map` replaced with "This window cannot draw the map: WebGL is unavailable." |
| Startup style fetch fails or times out (15 s) | `#map` replaced with "This window cannot draw the map: the map style failed to load." |
| MapLibre error with no `tile` and no `sourceId` | Same style-load message |
| MapLibre error carrying `tile` or `sourceId` | Logged to console; map keeps working |
| Style switch fetch fails | Toast "Could not load the `<Name>` style."; map unchanged |
| Routing service unreachable, or non-404 error | Toast "Could not reach the routing service. Is mapper on the local network?" |
| Routing returns 404 | Toast "No walking route there; routing only covers the Schenectady area." |

Toasts last 4000 ms. The toast host is appended to `document.body` rather than
into `#map`, so it survives `#map` being blanked, and `#toast` is always in the
document carrying `hidden` when empty, so its `aria-live` region exists before
text lands in it.

## 11. Module structure

Pure, store-argument-taking, testable under `node --test`:
`view.js`, `styles.js`, `tweaks.js`, `colors.js`, `places.js`, `route.js`.

Browser-side: `map.js` (a plain function, since MapLibre owns the canvas),
`store.js`, `main.jsx` (startup and wiring), `places.jsx` (places signal, panel,
markers), `styles.jsx` (style control, transform chain, toast),
`tweaks.jsx` (steppers), `colors.jsx` (pickers and `toHex`),
`route.jsx` (selection, fetch, status).

`route.jsx` sits at the hub of two import cycles, with `places.jsx` and with
`styles.jsx`. Nothing at module top level uses another module's export, so the
cycles resolve under ES module live bindings and esbuild's bundling.

## 12. Tests

- `node --test test/*.test.js`: `build`, `serve`, `view`, `places`, `styles`,
  `tweaks`, `colors`, `route`.
- `npx playwright test`: `test/map.spec.js` and `test/route.spec.js`, headless
  Chromium with `--use-gl=swiftshader --enable-unsafe-swiftshader`, single
  worker, not parallel, 30 s timeout and 10 s expect timeout.
- `test/dom-harness.jsx` bundles `colors.jsx` alone so `toHex`'s null-returning
  paths can be exercised directly; they are unreachable through a loaded map,
  because a style whose colors the browser cannot reduce to `rgb()` fails
  MapLibre's own validation.
- A new spec file must be added to `testMatch` in `playwright.config.js` or it
  never runs.

## 13. Known limits

Properties of the built system, as opposed to defects. The open defects and the
roadmap are in `docs/backlog.md`.

- The ORS base URL and profile are hardcoded in `src/route.js`. Routing works
  only on one local network and only for walking.
- Only one instance runs at a time (section 3).
- Text, Buildings and the four label colors are one setting shared by all five
  styles, not remembered per style.
- The vector source ends at zoom 14, so anything closer is magnified z14 data.
  Tile floors below that: buildings from z13, POIs from z11, road labels from z6.
- No offline tiles or tile caching, no geocoding search, and no reading of the
  wider slot configuration.
