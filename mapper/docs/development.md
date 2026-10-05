# Development

## Layout

```
mapper/
  mapper            launcher script
  serve.js          serves dist/index.html on a loopback port
  build.js          bundles src/ into dist/index.html
  src/              source, below
  test/             node --test unit tests and Playwright specs
  playwright.config.js
  mapper.desktop
```

`src/` splits into pure modules that take a `localStorage`-shaped store as an
argument and run under `node --test`, and browser modules that do not:

```
pure      view.js  styles.js  tweaks.js  colors.js  pins.js  places.js  route.js
browser   main.jsx  map.js  store.js  places.jsx  styles.jsx
          tweaks.jsx  colors.jsx  pins.jsx  route.jsx
page      index.html  style.css
```

## Build

```bash
npm run build
```

Writes `dist/index.html`. `build.js` bundles `src/style.css` (`.svg` and `.png`
inlined as data URLs) and `src/main.jsx` with esbuild (`iife`, `es2022`,
minified, `legalComments: 'none'`, automatic JSX with `jsxImportSource:
'preact'`) and substitutes the results into the `/*CSS*/` and `/*JS*/`
placeholders in `src/index.html`. `buildHtml()` is exported so tests can build
without writing to disk.

`dist/`, `node_modules/` and `test-results/` are ignored by git.

## Test

```bash
node --test test/*.test.js   # unit tests: build, serve, view, styles, tweaks, colors, pins, places, route
npx playwright test          # browser specs: test/map.spec.js, test/route.spec.js
npm test                     # both, in that order
```

Playwright runs headless Chromium with `--use-gl=swiftshader
--enable-unsafe-swiftshader`, since headless Chromium has no GPU and MapLibre
needs a WebGL context. It runs one worker, not in parallel, with a 30 second
test timeout and a 10 second `expect` timeout, all set in
`playwright.config.js`.

A new spec file is not picked up automatically: add it to `testMatch` in
`playwright.config.js` or it never runs.

`test/pw.js` wraps Playwright's `test` so every request to a host other than
`127.0.0.1` or `localhost` is aborted. `test/harness.js` builds the page once
per run and serves it, and its `routeStyle` answers OpenFreeMap style requests
with small stub styles, one per style id. Its `startDomHarness` serves
`test/dom-harness.jsx`, a bundle of `colors.jsx` alone, so `toHex` can be
called directly on colors no loaded style can carry.

The routing specs in `test/route.spec.js` answer requests to the
OpenRouteService address with `page.route` stubs, so they run off the local
network too.

No linter is configured.

## Release

None. The package is private (`"private": true`, version `0.1.0`) and runs
from the checkout.
