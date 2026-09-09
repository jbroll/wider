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
pure      view.js  styles.js  tweaks.js  colors.js  places.js  route.js
browser   main.jsx  map.js  store.js  places.jsx  styles.jsx
          tweaks.jsx  colors.jsx  route.jsx
page      index.html  style.css
```

## Build

```bash
npm run build
```

Writes `dist/index.html`.

## Test

```bash
node --test test/*.test.js   # unit tests: build, serve, view, styles, tweaks, colors, places, route
npx playwright test          # browser specs: test/map.spec.js, test/route.spec.js
node --run test              # both, in that order
```

Playwright specs run headless Chromium with `--use-gl=swiftshader`
(already set in `playwright.config.js`), since headless Chromium has no
GPU and MapLibre needs a WebGL context.

A new spec file is not picked up automatically: add it to `testMatch` in
`playwright.config.js` or it never runs.

`test/harness.js` builds the page and serves it for the specs. Its
`startDomHarness` serves `test/dom-harness.jsx`, a bundle of `colors.jsx`
alone, so `toHex` can be called directly on colors no loaded style can carry.
