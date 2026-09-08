# mapper — a desktop OpenStreetMap window

A sub-project of wider at `wider/mapper/`. A full-window vector map you run as
`./mapper`, pan and zoom with the mouse, rotate, and click a compass to return
to north. It remembers where you left it and keeps a list of saved places.

## Why not a browser tab

openstreetmap.org in a tab carries a header, a search box and a sidebar, forgets
the view between sessions, and cannot be placed in a wider slot by class. mapper
is a chromeless window with a stable WM_CLASS, a persisted view, and a pin list.

## Running it

`mapper` is an `sh` script beside the sources, the same shape as `shooter`:

    #!/bin/sh
    # pick a free port, start serve.js on 127.0.0.1, wait for it, then
    exec chromium --app=http://127.0.0.1:$PORT \
                  --class=Mapper \
                  --user-data-dir="$HOME/.config/mapper/chrome"

`--app` removes all browser chrome. `--class=Mapper` gives wider a stable
WM_CLASS to match a slot against; wider sets WM_WINDOW_ROLE itself via xprop for
apps that cannot set their own. The private `--user-data-dir` keeps the window
out of the normal Chromium session, so it opens as its own window and its
localStorage belongs to the app alone.

The script traps exit and kills the server when the window closes.
`mapper.desktop` mirrors `shooter.desktop` so the app appears in the menu and
can be launched from autostart.

`serve.js` is a Node static server that serves the single built
`dist/index.html` on 127.0.0.1 and exits when its parent goes away. It binds
port 0 and prints the chosen port on stdout for the launcher to read.

## The map

MapLibre GL JS fills the viewport, styled from OpenFreeMap's Liberty style at
`https://tiles.openfreemap.org/styles/liberty`. No API key, no account, whole
planet. Vector tiles keep labels upright under rotation and give 3D buildings
under tilt.

Interactions are MapLibre's defaults: left-drag pans, wheel zooms, right-drag
and ctrl-drag rotate and tilt. A `NavigationControl` sits top-right with
`showCompass: true`; clicking the compass animates bearing and pitch back to
north-up and flat. That is the return-to-north button, and it is a MapLibre
built-in rather than something we draw.

If the map fails to construct — no WebGL in the window — the page shows a single
line of text saying so instead of an empty black canvas.

## Remembering the view

On `moveend`, debounced, `{center, zoom, bearing, pitch}` is written to
localStorage under one key. On load the stored value is read, validated, and
applied; anything missing, malformed, or out of range falls back to a wide
default view. Validation lives in `view.js` as pure functions so it is tested
without a browser.

## Saved places

Right-clicking the map drops a marker and opens an inline name field in a
collapsible panel in the top-left corner. Enter saves, Escape discards the pin.
An entry records name, lat, lon, zoom and bearing. Clicking an entry flies the
map back to that exact view. An × on the entry deletes it. The list persists in
localStorage under its own key.

MapLibre uses right-drag for rotation, so the pin handler must not fire at the
end of a rotate gesture. This is a behavior to verify with a test, not assume: a
Playwright spec performs a right-drag and asserts no pin appeared. If MapLibre
does fire `contextmenu` after a rotate, the pin gesture moves to shift+right-click
and the docs say so.

## Files

    mapper/
      mapper              launcher (sh, executable)
      mapper.desktop
      serve.js
      build.js            esbuild, inlines everything into dist/index.html
      package.json
      src/
        index.html        template with /*CSS*/ and /*JS*/ slots
        style.css
        main.jsx          mounts the panel, constructs the map
        map.js            style URL, map construction, controls
        view.js           view load/save/validate (pure)
        places.js         places store: add, remove, list (pure)
        places.jsx        the corner panel
      test/
        view.test.js
        places.test.js
        build.test.js
        map.spec.js
      dist/index.html     built, not checked in
      README.md
      docs/
        quickstart.md install.md user-manual.md architecture.md
        development.md backlog.md

`build.js` follows `rtl433-web-receiver/dashboard/build.js`: esbuild bundles
`main.jsx` and `style.css` in memory and substitutes them into the HTML
template, producing one self-contained file. Preact with `@preact/signals`
supplies the panel; MapLibre owns the canvas and is not wrapped in a component.

The root `README.md` gains a line for mapper beside wider, shooter and tkx.

## Tests

`node --test test/*.test.js` covers the pure modules:

- `view.test.js` — round-trip, missing key, malformed JSON, out-of-range
  coordinates and zoom, all falling back to the default.
- `places.test.js` — add, remove, rename, persistence, stable ids across
  reloads.
- `build.test.js` — the built HTML references no external script or stylesheet,
  so the file is self-contained apart from tile requests.

Playwright covers the browser behavior: the map loads and the canvas appears;
the compass button returns bearing to 0; a right-click adds a pin and a
right-drag does not; clicking a saved entry moves the map to its stored view; a
reload restores the last view. Headless Chromium needs software WebGL for
MapLibre, so `playwright.config.js` launches with `--use-gl=swiftshader` and
`--enable-unsafe-swiftshader`.

## Left out

Offline tiles, tile caching, geocoding search, style switching, and any read of
the wider slot configuration. Each goes in `docs/backlog.md`.
