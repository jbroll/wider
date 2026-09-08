# Development

## Layout

```
mapper/
  mapper            launcher script
  serve.js          serves dist/index.html on a loopback port
  build.js          bundles src/ into dist/index.html
  src/               source: map.js, view.js, places.js, places.jsx, main.jsx, style.css, index.html
  test/              node --test unit tests and Playwright specs
  playwright.config.js
  mapper.desktop
```

## Build

```bash
npm run build
```

Writes `dist/index.html`.

## Test

```bash
node --test test/*.test.js   # unit tests: build, serve, view, places
npx playwright test          # browser specs: test/map.spec.js
node --run test               # both, in that order
```

Playwright specs run headless Chromium with `--use-gl=swiftshader`
(already set in `playwright.config.js`), since headless Chromium has no
GPU and MapLibre needs a WebGL context.

A new spec file is not picked up automatically: add it to `testMatch` in
`playwright.config.js` or it never runs.
