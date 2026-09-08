# mapper style switching

mapper draws one hardcoded map style. This adds a control for choosing among
the five OpenFreeMap serves, remembered across launches.

## The styles

    liberty   https://tiles.openfreemap.org/styles/liberty
    bright    https://tiles.openfreemap.org/styles/bright
    positron  https://tiles.openfreemap.org/styles/positron
    dark      https://tiles.openfreemap.org/styles/dark
    fiord     https://tiles.openfreemap.org/styles/fiord

All five answer 200. OpenFreeMap's site also names a "3D" style, but
`/styles/3d` is a 404 and it is not included.

Liberty stays the default, so an existing install looks the same until the user
picks something else.

## The control

A MapLibre custom control at `top-right`, so it stacks below the existing
`NavigationControl` without being positioned by hand and inherits
`.maplibregl-ctrl-group` styling. Five buttons, one per style, labelled with the
style name. The current one is marked.

Preact renders the buttons into the element the control's `onAdd` returns.
MapLibre owns where the control sits; Preact owns what is inside it.

## Remembering the choice

The style id is stored in localStorage under `mapper.style`, its own key beside
`mapper.view` and `mapper.places`. On load the stored id is read and looked up;
an unknown, missing or malformed id falls back to Liberty. Validation lives in
`styles.js` as pure functions, tested without a browser, the same shape as
`view.js` and `places.js`.

## Switching

Clicking a style fetches its JSON first, then calls `map.setStyle(style)` with
the parsed object. Fetching before switching means a failed request never tears
down the running map: the current style stays on screen, a toast names the
failure, and neither the stored id nor the marked button moves, so the control
keeps showing the style that is actually displayed.

The toast is a short-lived line of text that disappears on its own. It is the
only new user-visible surface besides the control.

Startup keeps loading the style by URL through MapLibre, so a style that cannot
be fetched at launch still reaches the existing failure message. That path is
unchanged, and the error handler that distinguishes a style failure from a tile
error is untouched.

`setStyle` preserves the camera, and markers are DOM overlays rather than style
layers, so the view, the saved places and a half-typed pin all survive a switch.

## Files

    src/styles.js     the five styles, load/save/lookup (pure)
    src/styles.jsx    the control's buttons and the toast
    src/map.js        createMap takes a style URL instead of hardcoding one
    src/main.jsx      reads the saved style, adds the control
    src/style.css     rules for the button group and the toast
    test/styles.test.js
    test/map.spec.js  three added specs

## Tests

`styles.test.js` covers the pure module: the default when the key is missing,
an unknown id, a malformed value, a round trip, and that every listed id
resolves to a URL.

Playwright covers the browser behavior. The harness currently answers every
`tiles.openfreemap.org` path with one stub, so it gains a per-style stub that a
test can tell apart by background colour:

- clicking a style requests that style's URL and marks its button current
- a reload comes back on the chosen style
- the centre, zoom and a saved place survive a switch
- a style whose request fails leaves the previous style on screen and shows the
  toast

## Left out

A control for how much the map draws when zoomed out, and per-style memory of
such overrides. What a style shows at a given zoom is mostly its own
zoom-interpolated opacity and label collision, which a zoom-range override
cannot reach, and beneath that the tiles have hard floors: buildings only exist
from zoom 13, POIs from 11, road labels from 6. Choosing a style that draws more
is the lever that works, which is what this adds.

The vector source ends at zoom 14, so a close-up past that is magnified z14 data
rather than more detail. Nothing here changes that.

Both go in `docs/backlog.md`.
