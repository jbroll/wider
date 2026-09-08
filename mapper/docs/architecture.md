# Architecture

## Launch

`mapper` (a shell script) builds `dist/index.html` if missing, starts
`serve.js` on port 0, reads the chosen port from its stdout through a
fifo, then launches Chromium with `--app`, `--class=Mapper`, and a
private `--user-data-dir`. Its exit trap kills the server. `--class=Mapper`
is the `WM_CLASS` wider matches a slot against.

`serve.js` also watches its own parent pid and exits if it changes, so a
launcher that is killed outright (bypassing the trap) does not leave the
server running forever.

## Build

`build.js` bundles `src/style.css` and `src/main.jsx` with esbuild and
inlines both into `src/index.html`, replacing the `/*CSS*/` and `/*JS*/`
placeholders. The result, `dist/index.html`, is a single file with no
external script or stylesheet references, so `serve.js` needs no static
directory, just that one file.

## UI

MapLibre owns the map canvas directly (`src/map.js`). Preact renders only
the places panel (`src/places.jsx`), which is why `map.js` is a plain
function rather than a component.

`src/view.js` and `src/places.js` take a `localStorage`-shaped store as an
argument instead of reading the global directly. That is what lets them
run under `node --test` without a browser.

`window.mapper.map` exposes the MapLibre map instance for the Playwright
specs and for poking at from a browser console.

## Why openfreemap Liberty

The map style is `https://tiles.openfreemap.org/styles/liberty`: vector
tiles, no API key, whole-planet coverage, and labels that stay upright
under rotation.
