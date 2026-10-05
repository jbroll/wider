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

The pure modules (`view.js`, `styles.js`, `tweaks.js`, `colors.js`,
`pins.js`, `places.js`, `route.js`, `backup.js`) take a `localStorage`-shaped store as an argument
instead of reading the global directly. That is what lets them run under
`node --test` without a browser. `src/store.js` wraps `window.localStorage` so
a thrown access (a browser policy blocking site data, or a quota error) yields
a no-op store instead of crashing the page; `main.jsx`, `places.jsx`,
`route.jsx` and `styles.jsx` pass that wrapper where a store is needed.

## Persistence

| Key | Module | Shape | Fallback on missing or invalid |
|---|---|---|---|
| `mapper.view` | `view.js` | `{center:[lon,lat], zoom, bearing, pitch}` | zoom 3.5 at `[-98.5795, 39.8283]`, bearing 0, pitch 0 |
| `mapper.style` | `styles.js` | one of the five style ids | `liberty` |
| `mapper.tweaks` | `tweaks.js` | `{textScale, buildingMinZoom}` | `{1, 13}`, whole document on any bad field |
| `mapper.colors` | `colors.js` | `{places, streets, pois, water}` | per group; a bad color resets only its own group |
| `mapper.pins` | `pins.js` | `{scale, iconScale, text, background}`; `scale` is the label's; `background` may be `transparent` | per field: scales 1, colors null |
| `mapper.places` | `places.js` | array of `{id, name, lat, lon, zoom, bearing, icon, hidden}` | `[]`; invalid entries dropped individually; a missing or unknown `icon` is `pin`; `hidden` is false unless exactly `true` |
| `mapper.routePref` | `route.js` | ORS `preference`: `shortest` or `recommended` | `shortest` |
| `mapper.routeSelected` | `route.js` | array of checked place ids, in check order | `[]`; entries that are not a non-empty string dropped individually; ids with no place dropped at startup |

Validation bounds: longitude ±180, latitude ±90, zoom 0–24, pitch 0–85.
A text or pin scale is a whole number of tenths with no upper bound and a
floor of 1, except the pin icon scale, whose floor is 0.5; `validateScale` snaps floating-point drift back onto the tenth, and
`stepScale` counts in integer tenths so stepping never produces it.
Bearing is normalised into 0–360; a view's stored bearing must first lie
within ±360. A place needs a non-empty string `id` and a string `name`. Place
ids are `'p'` + base-36 time + up to 6 random base-36 characters.

Every key in the table is also in `KEYS` in `src/backup.js`, which drives
[export and import](#export-and-import). `test/backup.test.js` fails if the two
differ in keys or order, or if a module exports a `*_KEY` constant naming a
`mapper.` key that `KEYS` lacks, so a new persisted key needs a table row and
a `KEYS` entry.

`window.mapper.map` exposes the MapLibre map instance for the Playwright
specs and for poking at from a browser console.

Each saved place gets a MapLibre `Marker` DOM overlay, not a style layer, so
it survives a style switch without being re-added. It's a plain
`new maplibregl.Marker({ draggable: true })` with no custom `element`, the
same icon MapLibre draws for the pending right-click pin, so both read as
the same mark and MapLibre's own anchor math (not ours) puts the pin's tip
on the coordinate. The name label is appended to the marker's own element
(`marker.getElement()`), absolutely positioned so it carries no layout
weight and can't shift where MapLibre anchors the pin, with
`pointer-events: none` so it never steals the drag or the click - one
element keeps one drag target and one object to reconcile, rather than two
`Marker`s per place. `places.jsx` reconciles the marker set against the `places` signal
inside an `effect`, keyed by place id so an unrelated signal update touches
no marker; because `savePlaces` rebuilds every place object on each commit,
the effect diffs by the place's lat/lon/name values rather than by object
identity; an unchanged entry gets neither a `setLngLat` nor a label update.
A hidden place is filtered out before reconciling, so hiding removes its
marker exactly as deleting the place would, and showing it builds a new one.
Hiding touches only the markers: the panel and the route read the full list.

A place's `icon` picks its marker from the `ICONS` table in `places.js`. `pin`
keeps MapLibre's default marker. Every other entry is an emoji in a custom
`element`, placed by the table's MapLibre `anchor` so the glyph's point of
contact lands on the coordinate: the star's center, the flag's pole foot.
Noto Color Emoji, the emoji font Chromium uses here, draws the pole a quarter
em in from the glyph's left edge, so the table's `shift` of `-0.25` em becomes
a negative left margin on the glyph and pulls the pole onto the element's
bottom-left corner. Another emoji font would draw the pole elsewhere. A
Marker's element is fixed at construction, so the reconciling effect replaces
the marker outright when a place's icon changes instead of updating it.
Adding an icon is one table entry, plus a `.place-label` `top` rule in
`style.css` if the label should not sit a third of the way down the glyph.

Markers scale by Text times the pin Icon stepper, independently of the label's
Text times Label. `style.css` sizes the emoji's font and the default pin's SVG
from `--text-scale` and `--icon-scale`.
MapLibre anchors by percentage translates, so an emoji stays on its point at
any size, and the flag's `shift` is in em so it scales too. The default pin is
the exception: MapLibre centres it and lifts it a fixed 14px so the tip, not
the centre, is on the point. A second effect in `places.jsx` watches the two
scale signals and calls `setOffset` with the lift times the scale on every pin
marker; new pin markers are built with the current lift.

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

`styles.jsx` holds the style as fetched, untransformed, in a module-private
`fetched`, so moving a stepper or a color picker re-transforms that held object
rather than refetching. Three transforms compose over it,
`applyRoute(applyColors(applyTweaks(style, tweaks), colors), route)`, in both
places a style is applied: `main.jsx` at startup and `styles.jsx`'s `transform`
closure on a switch or a control move. Each returns a new style because the
held object is transformed repeatedly, and a mutating transform would compound
scale on scale.
Each reads its own values at the moment it applies rather than when the click
happened, so a control moved during an in-flight switch is carried by that
switch when it lands.

The colors live in their own `mapper.colors` key rather than joining
`mapper.tweaks` because they fall back differently. A malformed field in
`mapper.tweaks` resets the whole document, which suits its two settings and
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

The pin label controls never touch the style. The labels belong to the marker
DOM overlay, so `pins.jsx` writes `pinCss` (`pins.js`, pure) to five custom
properties on the root element, `--pin-scale`, `--icon-scale`, `--pin-text`,
`--pin-background` and `--pin-halo`. The `.place-label` rule reads all but
`--icon-scale`, which sizes the marker icons. The label's font size is
`13px * --text-scale * --pin-scale`, so Text still scales pin labels and Label
multiplies on top. A preview is therefore cheap, and the pin pickers set the
properties on every `input` with no frame coalescing; only `change`, a click
on `×` or **No background**, and an Icon or Label step write `mapper.pins`. With a
transparent background the label sits directly on the map, so `--pin-halo`
becomes a one-pixel `text-shadow` outline in `haloFor`'s black or white,
matching the halos the label color pickers give map labels. `mapper.pins` is
its own key with per-field fallback for the same reason `mapper.colors` is.

The toast host is appended to `document.body`, not into `#map`, so it
survives `#map` being blanked by the style-load failure message. `#toast` is
always in the document and carries `hidden` when there is no message, so its
`aria-live` region exists before the text lands in it. A test asserting the
toast is absent wants `toBeHidden()`, not `toHaveCount(0)`.

## Export and import

`localStorage` is keyed by origin, so mapper served from a website and the
desktop launcher on `127.0.0.1:8737` start with separate data. Export and
import move it between them as a file.

The format:

```
{ "app": "mapper", "version": 1, "exported": "<ISO 8601 time>",
  "data": { "<key>": <value>, ... } }
```

`data` holds each key from the Persistence table that is set, as its parsed
value: an object or array for the JSON keys, the bare string for
`mapper.style` and `mapper.routePref`, which are stored unquoted. A reader
rejects any other `app` or `version`. A change to the shape of `data` or of a
stored value that an older mapper would misread needs a new version number.

`src/backup.js` is pure and store-argument-taking like the other modules.
Each `KEYS` entry pairs a key with a `json` flag and a `validate` function
built from the owning module's own validator (`validateView`,
`validatePlaces`, and so on), so import accepts exactly what load accepts.
`validateColors` and `validatePins` never fail, they fall back per field, so
their entries add a check that the value is an object at all; a non-object
would otherwise import as all defaults. Validation returns the cleaned value,
which is what gets written, so an imported place with no `icon` is stored with
`icon: "pin"` exactly as a load would read it. `buildExport` runs stored
values through the same functions, which keeps a value that would load as its
fallback out of the file.

`parseImport` returns either `{ error }`, rejecting the file, or `{ writes,
skipped }`; `applyImport(store, writes)` does the writing. Splitting them lets
`backup.jsx` show the confirmation between the two. `backup.jsx` holds the
DOM side: the Blob download, the hidden `<input type="file">`, `confirm`, and
the reload. It renders as the last section of the style control, beside the
other settings, and gets `toast` as a prop from `styles.jsx` rather than
importing it, which would add a third import cycle.

Import reloads the page instead of updating signals, because each module
reads its key once at startup (`places.jsx` and `route.jsx` at module load,
`route.jsx` again in `attachRoute`, `main.jsx` and `styles.jsx` in `start` and
`addStyleControl`) and re-seeding all of them would
mean a reset path per module. The result message has to outlive the reload,
so `backup.jsx` leaves it in `sessionStorage` under `mapper.importNotice` and
`addStyleControl` shows it as a toast on the next start, then removes it.
`sessionStorage` is per tab, so the message never reaches another window.

## Routing

`route.js` is pure, like `colors.js`: it holds the ORS path and profile,
builds the request URL and body, parses the response, and `applyRoute` appends a
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

The page never names the ORS host, because the deployed page is HTTPS and off
the home network, where a fetch to `http://192.168.1.169` is both blocked as
mixed content and unreachable. `ORS_BASE_URL` is the relative path `ors`, so a
request resolves under whatever path served the page, and that server proxies
it:

| Served from | Request goes to | Proxied to |
|---|---|---|
| `serve.js`, `http://127.0.0.1:8737/` | `/ors/v2/...` | `http://192.168.1.169:8082/ors/v2/...` |
| Apache, `https://apps.rkroll.com/mapper/` | `/mapper/ors/v2/...` | `https://symon.rkroll.com:8443/routing/ors/v2/...` |

The request is same-origin, so ORS needs no CORS headers. `serve.js` passes any method
under `/ors/` through with the body streamed and the status and headers sent
back, and answers 502 when ORS cannot be reached. `MAPPER_ORS_URL` overrides
its target, which is how `test/serve.test.js` points it at a fake.

The Apache mount checks a `token` query parameter on every request, including
the proxied ones, and sets no cookie. `directionsUrl` therefore takes the
page's query string (`route.jsx` passes `window.location.search`, keeping
`route.js` pure) and appends `?token=` when the page was opened with one. No
other page parameter is forwarded. ORS ignores the extra parameter.

Every request sends an explicit ORS `preference`, defaulting to `shortest`.
ORS's own default, `recommended`, weights `foot-walking` away from tertiary and
busier roads, so a walk along a main street such as Albany Street in
Schenectady comes back as a detour through side streets 60% longer. Quiet in
the route row keeps that weighting available.

`places.jsx` holds the selection (`selected`, membership only - which places
are in the route) and `route.jsx` holds the fetched `route` signal and drives
both from one place: `attachRoute(map)` seeds `selected` from
`mapper.routeSelected` and sets up three `effect`s. The seed runs through
`pruneSelected`, which drops ids with no place; `places` is already loaded at
module load, so a stale id, such as one from an import whose selection and
places disagree, is gone before anything renders.
That is why an import writes `mapper.routeSelected` without checking it
against the imported places. The first effect prunes `selected` the same way
when a place is deleted, writing only when something changed, so pruning
cannot loop against the others. The second writes `selected` to
`mapper.routeSelected` on every change, the prune included, but skips its
first run so a startup with nothing to change leaves the store untouched. The
third filters `places.value` down to the selected ids, in list order, reads
`routePref` so a Direct/Quiet click also refetches, and debounces
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
and calling its own `toggleSelected`; `route.jsx` reads the `places` and
`selected` signals `places.jsx` exports and calls `toast`/`reapplyStyle` from
`styles.jsx`, and `styles.jsx` reads the `route` signal from `route.jsx` for
`transform`. That makes an import cycle, `styles.jsx` <-> `route.jsx`. Nothing
at module top level uses another module's export - every use is inside a
function, render, or effect callback, run only after the whole graph has
loaded - so the cycle resolves under normal ES module live-binding semantics
and esbuild's bundling of it.

The selection is saved; the route geometry is not, and is recomputed from the
saved selection on load: the third effect's first run fetches it when two or
more places remain after the prune.

## Limits

- Routing is walking only: `PROFILE` in `src/route.js` is fixed at
  `foot-walking`. The ORS server behind the proxy covers the Schenectady area
  only.
- From the desktop launcher, routing works only on the network that reaches
  `192.168.1.169`, unless `MAPPER_ORS_URL` points `serve.js` elsewhere. The
  copy at `apps.rkroll.com` routes from anywhere.
- Only one instance runs at a time: the fixed port and Chromium's profile
  singleton both assume it (see `install.md`).
- Text, Buildings and the four label colors are one setting shared by all
  five styles.
- The vector source ends at zoom 14, so anything closer is magnified z14 data.
  The tiles carry buildings from z13, POIs from z11, and road labels from z6.

## Why openfreemap

The styles come from `https://tiles.openfreemap.org/styles/`: vector tiles,
no API key, whole-planet coverage, and labels that stay upright under
rotation. Liberty is the default. OpenFreeMap's site also names a "3D"
style, but `/styles/3d` is a 404, so mapper offers the five that answer.
