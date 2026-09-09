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

Each saved place gets a MapLibre `Marker` DOM overlay, not a style layer, so
it survives a style switch without being re-added. Its element is one
zero-size container with two absolutely-positioned children, a pin and a
label, rather than two `Marker`s per place - a single container keeps one
drag target and one object to reconcile. The container has no size of its
own, so MapLibre's `translate(-50%,-50%)` centering places the container's
own origin, not some visible box, at the coordinate; the pin is centered on
that origin so its exact center marks the point, and the label sits offset
beside it with `pointer-events: none` so it never steals the drag or the
click. `places.jsx` reconciles the marker set against the `places` signal
inside an `effect`, keyed by place id so an unrelated signal update touches
no marker; because `savePlaces` rebuilds every place object on each commit,
the effect diffs by the place's lat/lon/name values rather than by object
identity; an unchanged entry gets neither a `setLngLat` nor a label update.

A marker is draggable; dropping it calls the pure `movePlace` (`places.js`)
and commits the result, the same path a panel edit uses. MapLibre suppresses
the marker's own click while a drag is in progress (it sets the element's
`pointer-events` to `none` for the duration), which is what keeps a drag from
also flying the map to the place - verified in `test/map.spec.js` rather than
assumed.

Rows in the places list reorder by native HTML5 drag-and-drop (`draggable`,
`dragstart`/`dragover`/`drop` on the `<li>`) rather than a pointer-tracking
library, because Playwright's `locator.dragTo()` drives that API directly.
The drop handler calls the pure `reorderPlace` (`places.js`) and commits the
result, the same `commit` every other places edit uses.

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
to a throwaway element's `style.color` and reads `getComputedStyle` back, which
the browser normalises to `rgb(r, g, b)`. It needs a DOM, so it lives in
`colors.jsx` and Playwright covers it rather than `node --test`. `seedColors`
runs on the fetched style before `map.setStyle` ever sees it, so a color the
browser can't reduce to `rgb()` - `lab()`, `oklch()` - does reach `toHex`'s
null-returning paths in production; that style then fails MapLibre's own
validation and never loads, so no test can observe those paths through a
loaded map. `test/dom-harness.jsx` bundles `colors.jsx` alone and
`test/harness.js`'s `startDomHarness` serves it so those paths can be called
directly.

`<input type="color">` fires `input` continuously while its dialog is open, at
pointer rate, unlike the steppers' discrete clicks. `styles.jsx` splits the
picker's two callbacks accordingly: `onPreview` runs on every `input`, sets the
signal eagerly so the swatch stays responsive, and coalesces the map update to
one `requestAnimationFrame` per drag; `onCommit` runs once, on `change` or on
the clear click, and is the only path that writes `mapper.colors`. A commit
cancels any pending preview frame so a stale one cannot re-apply after the
commit's own `setStyle`.

The toast host is appended to `document.body`, not into `#map`, so it
survives `#map` being blanked by the style-load failure message. `#toast` is
always in the document and carries `hidden` when there is no message, so its
`aria-live` region exists before the text lands in it. A test asserting the
toast is absent wants `toBeHidden()`, not `toHaveCount(0)`.

## Routing

`route.js` is pure, like `colors.js`: it holds the ORS base URL and profile,
builds the request body, parses the response, and `applyRoute` appends a
GeoJSON source and a `line` layer for the route - the third transform in the
chain, `applyRoute(applyColors(applyTweaks(style, tweaks), colors), route)`,
composed identically at both places a style is applied (`main.jsx` at
startup, and `styles.jsx`'s `transform` closure). It must be a transform
rather than an added `map.addSource`/`map.addLayer` pair for the same reason
`applyTweaks` and `applyColors` are: `map.setStyle` runs on every switch,
stepper move and color commit, and that call destroys anything added outside
the style body it is given. The layer draws as round blue dots rather than a
solid stroke: `line-cap: 'round'` with a `line-dasharray` of `[0, 2]` turns
each zero-length dash into a dot the width of the line, spaced by the second
element in line-width units. A `circle` layer on the route geometry was
rejected - circles land on the LineString's vertices, which ORS spaces by
road geometry rather than evenly, so the dots would cluster at corners and
thin out along straights.

`route.jsx` holds the selection (`selected`, membership only - which places
are in the route) and the fetched `route` signal, and drives both from one
place: `attachRoute(map)` sets up two `effect`s. One prunes `selected` of an
id whose place got deleted, reusing the identity-preserving idiom
`places.jsx` already uses for its marker set - a no-op write when nothing
changed - so pruning cannot loop against the second effect. The second
filters `places.value` down to the selected ids, in list order, and debounces
the fetch 300ms after the last change, the same constant and shape as
`main.jsx`'s `moveend` save, so ticking several checkboxes - or dragging a
row - in a row sends one request. Waypoint order is list order, not tick
order, so dragging a row in the panel reorders the route; the same filter
also drives the order badge in `places.jsx`. Reading `places.value` in this
effect means any place edit re-triggers it, including one that leaves the
selected set's coordinates unchanged; that is what makes a marker drag
re-route through the new position without a separate wiring path, at the
cost of an occasional redundant fetch the debounce absorbs anyway. Fewer than
two selected places (after pruning) clears the route rather than fetching;
deleting a checked place is just the prune effect shrinking `selected`, so it
re-routes through what remains instead of clearing outright, unless that
drops it below two.

A request in flight is tracked with a token, the same pattern `switchStyle`
uses, so a selection change that lands while an earlier fetch is still out
does not let the stale response overwrite it.

Setting or clearing the route calls `reapplyStyle`, exported from
`styles.jsx`: `map.setStyle(transform(fetched))` using the same private
`fetched` and `transform` that a stepper move or color commit already use.
That is what makes a route drawn now survive a later switch, stepper move or
color commit - it is re-derived from the held style on every one of those,
not drawn once and left for the next `setStyle` to erase.

`places.jsx` renders the checkbox and order badge per row, reading `selected`
and calling `toggleSelected` from `route.jsx`; `route.jsx` reads the `places`
signal `places.jsx` exports and calls `toast`/`reapplyStyle` from
`styles.jsx`, and `styles.jsx` reads the `route` signal from `route.jsx` for
`transform`. That makes `route.jsx` the hub of two import cycles
(`places.jsx` <-> `route.jsx`, `styles.jsx` <-> `route.jsx`). Nothing at
module top level uses another module's export - every use is inside a
function, render, or effect callback, run only after the whole graph has
loaded - so the cycles resolve under normal ES module live-binding semantics
and esbuild's bundling of them.

The route is transient by design: `route.js` and `route.jsx` never touch
`localStorage`, so a reload always starts with nothing selected and no route
drawn.

## Why openfreemap

The styles come from `https://tiles.openfreemap.org/styles/`: vector tiles,
no API key, whole-planet coverage, and labels that stay upright under
rotation. Liberty is the default. OpenFreeMap's site also names a "3D"
style, but `/styles/3d` is a 404, so mapper offers the five that answer.
